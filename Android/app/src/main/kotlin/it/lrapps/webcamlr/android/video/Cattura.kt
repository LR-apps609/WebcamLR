package it.lrapps.webcamlr.android.video

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.MeteringRectangle
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Un obiettivo che si può scegliere: su molti telefoni grandangolo e tele non sono fotocamere a parte ma la stessa
 * fotocamera «logica» con uno zoom diverso (sotto 1× passa da sola al grandangolo, sopra 2–3× al tele).
 */
data class ObiettivoAndroid(
    /** Lo stesso nome del protocollo: `grandangolo`, `principale`, `tele`, `frontale`. */
    val nome: String,
    val idFotocamera: String,
    /** Lo zoom di partenza della fotocamera per questo obiettivo (0,5 per il grandangolo logico). */
    val zoomBase: Float,
    val frontale: Boolean,
) {
    /** Come sull'iPhone: «0,5×», «1×», «Tele», «Frontale». */
    val etichetta: String
        get() = when (nome) {
            "grandangolo" -> "0,5×"
            "principale" -> "1×"
            "tele" -> "Tele"
            else -> "Frontale"
        }
}

/** Fotocamera non disponibile: il messaggio dice cosa fare. */
class ErroreCattura(messaggio: String) : Exception(messaggio)

/**
 * La fotocamera con Camera2 (funziona su tutti i telefoni da Android 5, senza librerie): apre l'obiettivo scelto e
 * manda i fotogrammi alla Surface del [Renderizzatore] (e, per il QR code, a una seconda Surface). Comandi:
 * zoom, torcia, esposizione, bilanciamento del bianco, ISO e tempo manuali, messa a fuoco con il tocco.
 * Tutto sul thread della fotocamera.
 */
class Cattura(context: Context) {
    private val gestoreFotocamere = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val thread = HandlerThread("webcamlr-fotocamera").apply { start() }
    private val gestore = Handler(thread.looper)

    private var dispositivo: CameraDevice? = null
    private var sessione: CameraCaptureSession? = null
    private var richiesta: CaptureRequest.Builder? = null
    private var caratteristiche: CameraCharacteristics? = null
    private var obiettivo: ObiettivoAndroid? = null
    private var fps = 30

    // Lo stato dei comandi, riapplicato a ogni nuova richiesta.
    private var zoom = 1f
    private var torciaAccesa = false
    private var esposizione = 0.0
    private var bianco = 0
    private var iso = 0.0
    private var tempo = 0
    private var bloccati = false
    /** Ogni apertura ha il suo numero: gli avvisi di una fotocamera già chiusa si ignorano. */
    private var generazione = 0

    /** Gli obiettivi di questo telefono, calcolati una volta. */
    val obiettivi: List<ObiettivoAndroid> by lazy { cercaObiettivi() }

    /** Fino a quanto si può ingrandire dentro l'obiettivo scelto. */
    @Volatile var zoomMassimo = 1.0
        private set

    @Volatile var haTorcia = false
        private set

    /** Limiti della sensibilità manuale, se la fotocamera la permette. */
    @Volatile var limitiIso: Pair<Double, Double>? = null
        private set

    /** L'orientamento del sensore, per il [Renderizzatore]. */
    @Volatile var orientamentoSensore = 90
        private set

    private fun cercaObiettivi(): List<ObiettivoAndroid> {
        val elenco = mutableListOf<ObiettivoAndroid>()
        val id = try { gestoreFotocamere.cameraIdList.toList() } catch (e: Exception) { emptyList() }
        fun direzione(id: String) = try {
            gestoreFotocamere.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
        } catch (e: Exception) {
            null
        }
        fun focale(id: String) = try {
            gestoreFotocamere.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.minOrNull()
        } catch (e: Exception) {
            null
        }
        val posteriori = id.filter { direzione(it) == CameraMetadata.LENS_FACING_BACK }
        val principale = posteriori.firstOrNull()
        if (principale != null) {
            val focalePrincipale = focale(principale) ?: 0f
            val intervallo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                gestoreFotocamere.getCameraCharacteristics(principale).get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
            } else {
                null
            }
            // Grandangolo: lo zoom sotto 1× della fotocamera logica, altrimenti una fotocamera a parte con focale più corta.
            val minimo = intervallo?.lower ?: 1f
            if (minimo <= 0.7f) {
                elenco += ObiettivoAndroid("grandangolo", principale, minimo, false)
            } else {
                posteriori.drop(1).firstOrNull { altro -> (focale(altro) ?: 0f).let { it > 0 && it < focalePrincipale * 0.75f } }
                    ?.let { elenco += ObiettivoAndroid("grandangolo", it, 1f, false) }
            }
            elenco += ObiettivoAndroid("principale", principale, 1f, false)
            // Tele: una fotocamera a parte con focale almeno doppia, oppure lo zoom 3× di una logica con tre obiettivi.
            val teleAParte = posteriori.drop(1).firstOrNull { altro -> (focale(altro) ?: 0f) >= focalePrincipale * 1.8f && focalePrincipale > 0 }
            if (teleAParte != null) {
                elenco += ObiettivoAndroid("tele", teleAParte, 1f, false)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && (intervallo?.upper ?: 1f) >= 3f) {
                val fisiche = gestoreFotocamere.getCameraCharacteristics(principale).physicalCameraIds.size
                if (fisiche >= 3) elenco += ObiettivoAndroid("tele", principale, 3f, false)
            }
        }
        id.firstOrNull { direzione(it) == CameraMetadata.LENS_FACING_FRONT }?.let {
            elenco += ObiettivoAndroid("frontale", it, 1f, true)
        }
        return elenco
    }

    /** La dimensione della fotocamera più adatta (16:9, almeno quella del video) per la SurfaceTexture. */
    fun dimensionePer(obiettivo: ObiettivoAndroid, larghezza: Int, altezza: Int): Size {
        val mappa = gestoreFotocamere.getCameraCharacteristics(obiettivo.idFotocamera)
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val disponibili = mappa?.getOutputSizes(SurfaceTexture::class.java)?.toList().orEmpty()
        if (disponibili.isEmpty()) return Size(larghezza, altezza)
        val sediciNoni = disponibili.filter { abs(it.width * 9 - it.height * 16) <= it.width / 20 }
        val candidati = sediciNoni.ifEmpty { disponibili }
        return candidati.filter { it.width >= larghezza && it.height >= altezza }.minByOrNull { it.width * it.height }
            ?: candidati.maxBy { it.width * it.height }
    }

    /** Dimensione per i fotogrammi YUV del lettore QR, vicina a 1280×720. */
    fun dimensioneYuv(obiettivo: ObiettivoAndroid): Size {
        val mappa = gestoreFotocamere.getCameraCharacteristics(obiettivo.idFotocamera)
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val disponibili = mappa?.getOutputSizes(android.graphics.ImageFormat.YUV_420_888)?.toList().orEmpty()
        return disponibili.minByOrNull { abs(it.width * it.height - 1280 * 720) } ?: Size(1280, 720)
    }

    fun orientamentoDi(obiettivo: ObiettivoAndroid): Int =
        gestoreFotocamere.getCameraCharacteristics(obiettivo.idFotocamera).get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90

    /**
     * Apre l'obiettivo e manda i fotogrammi alle superfici. `pronta` arriva sul thread della fotocamera,
     * con `null` se è andata bene o con il messaggio d'errore.
     */
    @SuppressLint("MissingPermission") // il permesso si chiede prima di arrivare qui
    fun apri(nuovo: ObiettivoAndroid, fotogrammiAlSecondo: Int, superfici: List<Surface>, pronta: (String?) -> Unit) {
        gestore.post {
            chiudiSulThread()
            val questa = ++generazione
            obiettivo = nuovo
            fps = fotogrammiAlSecondo
            zoom = 1f
            torciaAccesa = false
            bloccati = false
            try {
                val dati = gestoreFotocamere.getCameraCharacteristics(nuovo.idFotocamera)
                caratteristiche = dati
                orientamentoSensore = dati.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
                it.lrapps.webcamlr.android.sistema.Orologio.impostaSorgente(
                    dati.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE) == CameraMetadata.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME,
                )
                haTorcia = dati.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
                zoomMassimo = calcolaZoomMassimo(dati, nuovo)
                val manuale = dati.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                    ?.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR) == true
                limitiIso = if (manuale) dati.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
                    ?.let { it.lower.toDouble() to it.upper.toDouble() } else null
                gestoreFotocamere.openCamera(nuovo.idFotocamera, object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        if (questa != generazione) {
                            camera.close()
                            return
                        }
                        dispositivo = camera
                        creaSessione(camera, superfici, pronta)
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        camera.close()
                        if (questa != generazione) return
                        if (dispositivo === camera) dispositivo = null
                        pronta("Un'altra app sta usando la fotocamera: chiudila e tocca «Riprova».")
                    }

                    override fun onError(camera: CameraDevice, errore: Int) {
                        camera.close()
                        if (questa != generazione) return
                        if (dispositivo === camera) dispositivo = null
                        pronta(
                            when (errore) {
                                ERROR_CAMERA_IN_USE, ERROR_MAX_CAMERAS_IN_USE -> "Un'altra app sta usando la fotocamera: chiudila e tocca «Riprova»."
                                ERROR_CAMERA_DISABLED -> "La fotocamera è disattivata da un criterio del telefono: controlla le impostazioni di sicurezza."
                                else -> "La fotocamera non risponde: tocca «Riprova», e se succede ancora riavvia il telefono."
                            },
                        )
                    }
                }, gestore)
            } catch (e: CameraAccessException) {
                pronta("La fotocamera non è disponibile: chiudi le altre app che la usano e tocca «Riprova».")
            } catch (e: SecurityException) {
                pronta("Manca il permesso della fotocamera: consentilo nelle impostazioni del telefono, sezione App › WebcamLR.")
            } catch (e: Exception) {
                Log.w(TAG, "Fotocamera non aperta", e)
                pronta("La fotocamera non è disponibile: tocca «Riprova».")
            }
        }
    }

    @Suppress("DEPRECATION") // createCaptureSession(List): l'unica disponibile prima di Android 9
    private fun creaSessione(camera: CameraDevice, superfici: List<Surface>, pronta: (String?) -> Unit) {
        try {
            camera.createCaptureSession(superfici, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(nuova: CameraCaptureSession) {
                    if (dispositivo !== camera) {
                        nuova.close()
                        return
                    }
                    sessione = nuova
                    val costruttore = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                    superfici.forEach { costruttore.addTarget(it) }
                    richiesta = costruttore
                    impostaBase(costruttore)
                    applica()
                    pronta(null)
                }

                override fun onConfigureFailed(nuova: CameraCaptureSession) {
                    pronta("La fotocamera non accetta questo formato: scegli un'altra risoluzione in Impostazioni.")
                }
            }, gestore)
        } catch (e: Exception) {
            Log.w(TAG, "Sessione della fotocamera non creata", e)
            pronta("La fotocamera non è disponibile: tocca «Riprova».")
        }
    }

    fun chiudi() {
        gestore.post { chiudiSulThread() }
    }

    /** Chiude e aspetta (al massimo 2 secondi): prima di buttare la superficie su cui la fotocamera scrive. */
    fun chiudiEAspetta() {
        val fatto = java.util.concurrent.CountDownLatch(1)
        if (gestore.post { generazione++; chiudiSulThread(); fatto.countDown() }) {
            fatto.await(2, java.util.concurrent.TimeUnit.SECONDS)
        }
    }

    fun termina() {
        gestore.post {
            chiudiSulThread()
            thread.quitSafely()
        }
    }

    private fun chiudiSulThread() {
        try { sessione?.close() } catch (e: Exception) { /* già chiusa */ }
        sessione = null
        try { dispositivo?.close() } catch (e: Exception) { /* già chiusa */ }
        dispositivo = null
        richiesta = null
    }

    // Comandi (da qualsiasi thread)

    fun impostaZoom(fattore: Double) = gestore.post { zoom = fattore.toFloat().coerceIn(1f, zoomMassimo.toFloat()); applica() }
    fun impostaTorcia(accesa: Boolean) = gestore.post { torciaAccesa = accesa && haTorcia; applica() }
    fun impostaEsposizione(stop: Double) = gestore.post { esposizione = stop.coerceIn(-2.0, 2.0); applica() }
    fun impostaBianco(kelvin: Int) = gestore.post { bianco = kelvin; applica() }
    fun impostaManuale(nuovoIso: Double, nuovoTempo: Int) = gestore.post { iso = nuovoIso; tempo = nuovoTempo; applica() }
    fun fuocoContinuo() = gestore.post { bloccati = false; applica() }

    /** Tocco sull'anteprima: punto normalizzato (0–1) nelle coordinate del sensore. `blocca`: AE/AF bloccati. */
    fun metteAFuoco(xSensore: Float, ySensore: Float, blocca: Boolean) = gestore.post {
        val costruttore = richiesta ?: return@post
        val attuale = sessione ?: return@post
        val area = caratteristiche?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return@post
        val lato = (minOf(area.width(), area.height()) * 0.12f).roundToInt()
        val cx = (area.left + xSensore.coerceIn(0f, 1f) * area.width()).roundToInt()
        val cy = (area.top + ySensore.coerceIn(0f, 1f) * area.height()).roundToInt()
        val rettangolo = Rect(
            (cx - lato).coerceAtLeast(area.left), (cy - lato).coerceAtLeast(area.top),
            (cx + lato).coerceAtMost(area.right), (cy + lato).coerceAtMost(area.bottom),
        )
        val regione = arrayOf(MeteringRectangle(rettangolo, MeteringRectangle.METERING_WEIGHT_MAX - 1))
        try {
            bloccati = blocca
            costruttore.set(CaptureRequest.CONTROL_AF_REGIONS, regione)
            costruttore.set(CaptureRequest.CONTROL_AE_REGIONS, regione)
            costruttore.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO)
            costruttore.set(CaptureRequest.CONTROL_AE_LOCK, false)
            costruttore.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START)
            attuale.capture(costruttore.build(), null, gestore)
            costruttore.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE)
            if (blocca) {
                costruttore.set(CaptureRequest.CONTROL_AE_LOCK, true)
                attuale.setRepeatingRequest(costruttore.build(), null, gestore)
            } else {
                // Dopo qualche secondo si torna alla messa a fuoco automatica che segue la scena.
                attuale.setRepeatingRequest(costruttore.build(), null, gestore)
                gestore.postDelayed({ if (!bloccati) applica() }, 4_000)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Messa a fuoco non riuscita", e)
        }
    }

    private fun impostaBase(costruttore: CaptureRequest.Builder) {
        val dati = caratteristiche ?: return
        val intervalli = dati.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES).orEmpty()
        // Fotogrammi fissi se si può (video regolare), altrimenti il massimo sotto quelli scelti.
        val scelto = intervalli.filter { it.upper == fps }.maxByOrNull { it.lower }
            ?: intervalli.filter { it.upper <= fps }.maxByOrNull { it.upper * 100 + it.lower }
        if (scelto != null) costruttore.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, scelto)
        // La stabilizzazione elettronica aggiunge ritardo: spenta.
        costruttore.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF)
    }

    /** Riapplica tutti i comandi e rinnova la richiesta ripetuta. Sul thread della fotocamera. */
    private fun applica() {
        val costruttore = richiesta ?: return
        val attuale = sessione ?: return
        val dati = caratteristiche ?: return
        val obiettivoAttuale = obiettivo ?: return
        try {
            costruttore.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
            if (!bloccati) {
                val modiFuoco = dati.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.toList().orEmpty()
                if (CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO in modiFuoco) {
                    costruttore.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                }
                costruttore.set(CaptureRequest.CONTROL_AF_REGIONS, null)
                costruttore.set(CaptureRequest.CONTROL_AE_REGIONS, null)
                costruttore.set(CaptureRequest.CONTROL_AE_LOCK, false)
            }

            // Zoom: da Android 11 il rapporto (anche sotto 1× per il grandangolo), prima il ritaglio del sensore.
            val rapporto = obiettivoAttuale.zoomBase * zoom
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && dati.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE) != null) {
                val intervallo: Range<Float> = dati.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)!!
                costruttore.set(CaptureRequest.CONTROL_ZOOM_RATIO, rapporto.coerceIn(intervallo.lower, intervallo.upper))
            } else {
                val area = dati.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
                if (area != null) {
                    val massimo = dati.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
                    val fattore = rapporto.coerceIn(1f, massimo)
                    val larghezza = (area.width() / fattore).roundToInt()
                    val altezza = (area.height() / fattore).roundToInt()
                    val x = (area.width() - larghezza) / 2
                    val y = (area.height() - altezza) / 2
                    costruttore.set(CaptureRequest.SCALER_CROP_REGION, Rect(x, y, x + larghezza, y + altezza))
                }
            }

            // Esposizione: manuale (ISO e tempo dal computer) oppure automatica con la compensazione.
            val manuale = (iso > 0 || tempo > 0) && limitiIso != null
            if (manuale) {
                val (minimo, massimo) = limitiIso!!
                costruttore.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_OFF)
                val sensibilita = (if (iso > 0) iso else 400.0).coerceIn(minimo, massimo).roundToInt()
                costruttore.set(CaptureRequest.SENSOR_SENSITIVITY, sensibilita)
                // Mai più lungo di un fotogramma: i fotogrammi al secondo non cambiano.
                val denominatore = maxOf(if (tempo > 0) tempo else 100, fps)
                costruttore.set(CaptureRequest.SENSOR_EXPOSURE_TIME, 1_000_000_000L / denominatore)
                costruttore.set(CaptureRequest.SENSOR_FRAME_DURATION, 1_000_000_000L / fps)
            } else {
                costruttore.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                val passo = dati.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)
                val limiti = dati.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
                if (passo != null && limiti != null && passo.toDouble() > 0) {
                    val indice = (esposizione / passo.toDouble()).roundToInt().coerceIn(limiti.lower, limiti.upper)
                    costruttore.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, indice)
                }
            }
            // La torcia funziona solo con l'esposizione automatica «ON» (non con il flash automatico).
            costruttore.set(
                CaptureRequest.FLASH_MODE,
                if (torciaAccesa && haTorcia) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF,
            )
            costruttore.set(CaptureRequest.CONTROL_AWB_MODE, modoBianco(bianco))
            attuale.setRepeatingRequest(costruttore.build(), null, gestore)
        } catch (e: Exception) {
            Log.w(TAG, "Comando della fotocamera non applicato", e)
        }
    }

    private fun calcolaZoomMassimo(dati: CameraCharacteristics, obiettivo: ObiettivoAndroid): Double {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            dati.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)?.let { return maxOf(1.0, it.upper.toDouble() / obiettivo.zoomBase) }
        }
        return (dati.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f).toDouble()
    }

    companion object {
        private const val TAG = "WebcamLR"

        /**
         * Camera2 non accetta i kelvin: si sceglie il bilanciamento predefinito più vicino.
         * 0 = automatico, come nel protocollo.
         */
        fun modoBianco(kelvin: Int): Int = when {
            kelvin <= 0 -> CaptureRequest.CONTROL_AWB_MODE_AUTO
            kelvin < 3300 -> CaptureRequest.CONTROL_AWB_MODE_INCANDESCENT
            kelvin < 4200 -> CaptureRequest.CONTROL_AWB_MODE_WARM_FLUORESCENT
            kelvin < 5000 -> CaptureRequest.CONTROL_AWB_MODE_FLUORESCENT
            kelvin < 6000 -> CaptureRequest.CONTROL_AWB_MODE_DAYLIGHT
            kelvin < 7000 -> CaptureRequest.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT
            else -> CaptureRequest.CONTROL_AWB_MODE_SHADE
        }
    }
}
