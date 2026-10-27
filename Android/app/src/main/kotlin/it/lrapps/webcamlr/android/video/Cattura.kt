package it.lrapps.webcamlr.android.video

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.MeteringRectangle
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.logica.FormatoRichiesto
import it.lrapps.webcamlr.android.logica.SceltaFormato
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.protocollo.FormatoSupportato
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
    /** P08 luce sul volto: la regione dell'esposizione sul volto (coordinate delle regioni), `null` = automatica. */
    private var regioneVolto: Rect? = null
    /** Ogni apertura ha il suo numero: gli avvisi di una fotocamera già chiusa si ignorano. */
    private var generazione = 0

    // Riduzione del rumore e nitidezza «alta qualità» finché regge i fotogrammi (vedi [contaFotogrammi]).
    private var altaQualita = true
    private var secondiLenti = 0
    private var fotogrammiContati = 0
    private var inizioConteggio = 0L
    private var durataSensore = 0L
    private var fpsPossibili = 30

    /** I fotogrammi al secondo che la fotocamera consegna davvero (misurati ogni secondo; 0 = non ancora). */
    @Volatile var fpsFotocamera = 0.0
        private set

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

    /**
     * I fotogrammi al secondo massimi di un obiettivo a una risoluzione 16:9 (in orizzontale), 0 se non c'è: il
     * minimo tra la durata minima dei fotogrammi della fotocamera (per la SurfaceTexture), gli intervalli dell'esposizione
     * automatica e il codificatore hardware (`fpsCodificatore`). Al massimo 60.
     */
    fun fpsMassimo(obiettivo: ObiettivoAndroid, larghezza: Int, altezza: Int, fpsCodificatore: (Int, Int) -> Int): Int = try {
        val dati = gestoreFotocamere.getCameraCharacteristics(obiettivo.idFotocamera)
        val mappa = dati.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val dimensione = mappa?.getOutputSizes(SurfaceTexture::class.java)?.filter {
            abs(it.width * 9 - it.height * 16) <= it.width / 20 && it.width >= larghezza && it.height >= altezza
        }?.minByOrNull { it.width * it.height }
        if (mappa == null || dimensione == null) {
            0
        } else {
            val durata = mappa.getOutputMinFrameDuration(SurfaceTexture::class.java, dimensione)
            val daSensore = if (durata > 0) (1_000_000_000L / durata).toInt() else 30
            val daEsposizione = dati.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)?.maxOfOrNull { it.upper } ?: 30
            minOf(daSensore, daEsposizione, fpsCodificatore(larghezza, altezza), 60)
        }
    } catch (e: Exception) {
        0
    }

    /** `capacita.formati` per l'obiettivo: 4K, 1080p e 720p con i fotogrammi massimi (il 4K al massimo a 30). */
    fun formatiSupportati(obiettivo: ObiettivoAndroid, fpsCodificatore: (Int, Int) -> Int): List<FormatoSupportato> =
        FormatoRichiesto.RISOLUZIONI.mapNotNull { (l, a) ->
            val fps = fpsMassimo(obiettivo, l, a, fpsCodificatore).let { if (l >= 3840) minOf(it, SceltaFormato.FPS_MASSIMI_4K) else it }
            if (fps >= 15) FormatoSupportato(l, a, fps) else null
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
            regioneVolto = null
            altaQualita = fotogrammiAlSecondo <= 30
            secondiLenti = 0
            inizioConteggio = 0L
            durataSensore = 0L
            fpsFotocamera = 0.0
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
                        pronta(Testi.testo(R.string.fotocamera_altra_app))
                    }

                    override fun onError(camera: CameraDevice, errore: Int) {
                        camera.close()
                        if (questa != generazione) return
                        if (dispositivo === camera) dispositivo = null
                        pronta(
                            when (errore) {
                                ERROR_CAMERA_IN_USE, ERROR_MAX_CAMERAS_IN_USE -> Testi.testo(R.string.fotocamera_altra_app)
                                ERROR_CAMERA_DISABLED -> Testi.testo(R.string.fotocamera_criterio)
                                else -> Testi.testo(R.string.fotocamera_non_risponde)
                            },
                        )
                    }
                }, gestore)
            } catch (e: CameraAccessException) {
                pronta(Testi.testo(R.string.fotocamera_occupata))
            } catch (e: SecurityException) {
                pronta(Testi.testo(R.string.fotocamera_senza_permesso))
            } catch (e: Exception) {
                Log.w(TAG, "Fotocamera non aperta", e)
                pronta(Testi.testo(R.string.fotocamera_non_disponibile))
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
                    pronta(Testi.testo(R.string.fotocamera_formato))
                }
            }, gestore)
        } catch (e: Exception) {
            Log.w(TAG, "Sessione della fotocamera non creata", e)
            pronta(Testi.testo(R.string.fotocamera_non_disponibile))
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

    /**
     * P08 luce sul volto: l'esposizione automatica misura sul volto. `volto` nel fotogramma della fotocamera
     * (normalizzato, orientamento del sensore: sinistra, alto, destra, basso, vedi [Geometria.videoAllaFotocamera]);
     * `null` = di nuovo tutta la scena. Con l'esposizione manuale o AE/AF bloccati non cambia nulla; senza regioni AE
     * sul telefono non fa nulla.
     */
    fun esponiSulVolto(volto: FloatArray?) = gestore.post {
        val dati = caratteristiche ?: return@post
        if ((dati.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE) ?: 0) <= 0) return@post
        regioneVolto = volto?.let { regioneDa(it[0], it[1], it[2], it[3], dati, margine = 0.15f) }
        if (!bloccati) applica()
    }

    /** La dimensione del flusso della fotocamera verso il renderizzatore (per le proporzioni delle regioni). */
    @Volatile var larghezzaFlusso = 1920
    @Volatile var altezzaFlusso = 1080

    /**
     * Tocco sull'anteprima già portato nel fotogramma della fotocamera (normalizzato, orientamento del sensore).
     * `blocca`: AE/AF bloccati.
     */
    fun metteAFuocoNelFotogramma(x: Float, y: Float, blocca: Boolean) = gestore.post {
        val dati = caratteristiche ?: return@post
        val lato = 0.08f
        val regione = regioneDa(x - lato, y - lato, x + lato, y + lato, dati, margine = 0f) ?: return@post
        mettiAFuoco(regione, blocca)
    }

    /**
     * Dal fotogramma della fotocamera (normalizzato) alle coordinate delle regioni AE/AF: con CONTROL_ZOOM_RATIO tutta
     * l'area attiva (da 0) corrisponde al campo inquadrato; prima di Android 11 il ritaglio dello zoom.
     */
    private fun regioneDa(x1: Float, y1: Float, x2: Float, y2: Float, dati: CameraCharacteristics, margine: Float): Rect? {
        val area = dati.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return null
        if (!x1.isFinite() || !y1.isFinite() || !x2.isFinite() || !y2.isFinite()) return null
        val conRapporto = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && dati.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE) != null
        val campo = if (conRapporto) RectF(0f, 0f, area.width().toFloat(), area.height().toFloat()) else ritaglioAttuale(dati, area)
        val (sx, sy) = Geometria.versoRegioni(
            minOf(x1, x2), minOf(y1, y2), campo.left, campo.top, campo.width(), campo.height(), larghezzaFlusso, altezzaFlusso,
        )
        val (ex, ey) = Geometria.versoRegioni(
            maxOf(x1, x2), maxOf(y1, y2), campo.left, campo.top, campo.width(), campo.height(), larghezzaFlusso, altezzaFlusso,
        )
        val mx = (ex - sx) * margine
        val my = (ey - sy) * margine
        val r = Rect(
            (sx - mx).roundToInt().coerceIn(0, area.width() - 1), (sy - my).roundToInt().coerceIn(0, area.height() - 1),
            (ex + mx).roundToInt().coerceIn(1, area.width()), (ey + my).roundToInt().coerceIn(1, area.height()),
        )
        return if (r.width() >= 8 && r.height() >= 8) r else null
    }

    private fun ritaglioAttuale(dati: CameraCharacteristics, area: Rect): RectF {
        val massimo = dati.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM) ?: 1f
        val fattore = ((obiettivo?.zoomBase ?: 1f) * zoom).coerceIn(1f, massimo)
        val l = area.width() / fattore
        val a = area.height() / fattore
        return RectF((area.width() - l) / 2, (area.height() - a) / 2, (area.width() + l) / 2, (area.height() + a) / 2)
    }

    /** Tocco sull'anteprima: punto normalizzato (0–1) nelle coordinate del sensore. `blocca`: AE/AF bloccati. */
    fun metteAFuoco(xSensore: Float, ySensore: Float, blocca: Boolean) = gestore.post {
        val area = caratteristiche?.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE) ?: return@post
        val lato = (minOf(area.width(), area.height()) * 0.12f).roundToInt()
        val cx = (xSensore.coerceIn(0f, 1f) * area.width()).roundToInt()
        val cy = (ySensore.coerceIn(0f, 1f) * area.height()).roundToInt()
        val rettangolo = Rect(
            (cx - lato).coerceAtLeast(0), (cy - lato).coerceAtLeast(0),
            (cx + lato).coerceAtMost(area.width()), (cy + lato).coerceAtMost(area.height()),
        )
        mettiAFuoco(rettangolo, blocca)
    }

    /** Sul thread della fotocamera: fuoco ed esposizione sulla regione, poi di nuovo automatici (salvo `blocca`). */
    private fun mettiAFuoco(rettangolo: Rect, blocca: Boolean) {
        val costruttore = richiesta ?: return
        val attuale = sessione ?: return
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
                attuale.setRepeatingRequest(costruttore.build(), contaFotogrammi, gestore)
            } else {
                // Dopo qualche secondo si torna alla messa a fuoco automatica che segue la scena.
                attuale.setRepeatingRequest(costruttore.build(), contaFotogrammi, gestore)
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
        fpsPossibili = minOf(fps, scelto?.upper ?: fps)
        // La stabilizzazione elettronica aggiunge ritardo e taglia i bordi: spenta (il telefono sta fermo). Quella
        // ottica non ritarda nulla: accesa se c'è, toglie il tremolio dei tocchi e del tavolo.
        costruttore.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF)
        val ottica = dati.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION)
        if (ottica?.contains(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_ON) == true) {
            costruttore.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE, CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_ON)
        }
        // Niente HDR: su Camera2 il video HDR è a 10 bit (cambia i colori e il codificatore) o è la scena «HDR», che
        // toglie esposizione e bianco manuali e spesso abbassa i fotogrammi.
        impostaElaborazione(costruttore, dati)
    }

    /**
     * Riduzione del rumore e nitidezza: «alta qualità» finché la fotocamera regge i fotogrammi scelti, altrimenti
     * «veloce» (che per definizione non li abbassa). A 60 fps si parte da «veloce». Vedi [controllaFotogrammi].
     */
    private fun impostaElaborazione(costruttore: CaptureRequest.Builder, dati: CameraCharacteristics) {
        val rumore = dati.get(CameraCharacteristics.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES)?.toList().orEmpty()
        val bordi = dati.get(CameraCharacteristics.EDGE_AVAILABLE_EDGE_MODES)?.toList().orEmpty()
        val modoRumore = when {
            altaQualita && CaptureRequest.NOISE_REDUCTION_MODE_HIGH_QUALITY in rumore -> CaptureRequest.NOISE_REDUCTION_MODE_HIGH_QUALITY
            CaptureRequest.NOISE_REDUCTION_MODE_FAST in rumore -> CaptureRequest.NOISE_REDUCTION_MODE_FAST
            else -> null
        }
        val modoBordi = when {
            altaQualita && CaptureRequest.EDGE_MODE_HIGH_QUALITY in bordi -> CaptureRequest.EDGE_MODE_HIGH_QUALITY
            CaptureRequest.EDGE_MODE_FAST in bordi -> CaptureRequest.EDGE_MODE_FAST
            else -> null
        }
        modoRumore?.let { costruttore.set(CaptureRequest.NOISE_REDUCTION_MODE, it) }
        modoBordi?.let { costruttore.set(CaptureRequest.EDGE_MODE, it) }
    }

    /**
     * Ogni secondo, dai risultati della fotocamera: i fotogrammi arrivati. Se con «alta qualità» restano sotto il 90%
     * di quelli possibili per 3 secondi di fila si passa a «veloce», fino alla prossima apertura. «Possibili»: i
     * fotogrammi scelti, o meno se il sensore stesso rallenta (poca luce, la durata del fotogramma si allunga).
     */
    private val contaFotogrammi = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureCompleted(session: CameraCaptureSession, request: CaptureRequest, result: TotalCaptureResult) {
            result.get(CaptureResult.SENSOR_FRAME_DURATION)?.let { if (it > 0) durataSensore = it }
            val adesso = SystemClock.elapsedRealtime()
            if (inizioConteggio == 0L) {
                inizioConteggio = adesso
                fotogrammiContati = 0
                return
            }
            fotogrammiContati++
            val trascorso = adesso - inizioConteggio
            if (trascorso < 1_000) return
            val alSecondo = fotogrammiContati * 1000.0 / trascorso
            inizioConteggio = adesso
            fotogrammiContati = 0
            fpsFotocamera = alSecondo
            controllaFotogrammi(alSecondo)
        }
    }

    private fun controllaFotogrammi(alSecondo: Double) {
        if (!altaQualita) return
        val dalSensore = if (durataSensore > 0) 1e9 / durataSensore else fps.toDouble()
        val possibili = minOf(fpsPossibili.toDouble(), dalSensore)
        secondiLenti = if (alSecondo < possibili * 0.9) secondiLenti + 1 else 0
        if (secondiLenti < 3) return
        altaQualita = false
        secondiLenti = 0
        Log.i(TAG, "Riduzione del rumore «alta qualità» troppo lenta (${"%.1f".format(alSecondo)} fps): passo a «veloce»")
        val costruttore = richiesta ?: return
        val dati = caratteristiche ?: return
        impostaElaborazione(costruttore, dati)
        applica()
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
                // P08: con la luce sul volto l'esposizione misura il volto (con l'esposizione manuale non serve).
                val volto = regioneVolto
                costruttore.set(
                    CaptureRequest.CONTROL_AE_REGIONS,
                    if (volto != null && iso <= 0 && tempo <= 0) arrayOf(MeteringRectangle(volto, MeteringRectangle.METERING_WEIGHT_MAX - 1)) else null,
                )
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
            attuale.setRepeatingRequest(costruttore.build(), contaFotogrammi, gestore)
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
