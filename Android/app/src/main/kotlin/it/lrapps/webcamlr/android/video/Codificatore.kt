package it.lrapps.webcamlr.android.video

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import it.lrapps.webcamlr.android.logica.BitrateVideo
import it.lrapps.webcamlr.android.sistema.Orologio
import it.lrapps.webcamlr.protocollo.AnnexB
import it.lrapps.webcamlr.protocollo.Codec
import it.lrapps.webcamlr.protocollo.FormatoVideo
import it.lrapps.webcamlr.protocollo.FotogrammaVideo
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

/**
 * Comprime il video con il codificatore hardware del telefono (MediaCodec), H.264 di serie e HEVC a scelta,
 * con le impostazioni per la latenza bassa: priorità tempo reale, latenza di un fotogramma (Android 11+), nessun
 * fotogramma B, un fotogramma chiave ogni 2 secondi (e su richiesta) con SPS/PPS davanti, bitrate costante (CBR,
 * altrimenti VBR) che si cambia al volo quando la rete rallenta. Profilo High per H.264 (Main per HEVC) se il
 * codificatore lo dichiara: a pari bitrate più qualità, e senza fotogrammi B nessun ritardo in più. Il bitrate
 * della qualità scelta viene da [BitrateVideo].
 * L'ingresso è una Surface (disegnata dal [Renderizzatore]): nessuna copia dei fotogrammi.
 */
class Codificatore(
    /** Ogni fotogramma compresso (Annex B, con SPS/PPS davanti ai fotogrammi chiave), dal thread del codificatore. */
    private val suFotogramma: (FotogrammaVideo) -> Unit,
    private val suErrore: (String) -> Unit,
) {
    private var codec: MediaCodec? = null
    private var thread: HandlerThread? = null
    @Volatile private var parametri: ByteArray? = null
    @Volatile private var primoFotogramma = true

    /** Il formato effettivo, da mandare al computer con il messaggio `formato`. */
    @Volatile var formato: FormatoVideo? = null
        private set

    /** Il bitrate della qualità scelta, prima dell'adattamento alla rete. */
    @Volatile var bitrateBase = 0
        private set

    /** Il bitrate più alto che il codificatore accetta (0 = non si sa). */
    @Volatile private var bitrateMassimo = 0

    // Il misuratore (Dettagli e registro): fotogrammi e byte usciti dal codificatore dall'ultima lettura.
    private val fotogrammiUsciti = AtomicInteger()
    private val byteUsciti = AtomicLong()

    /** Fotogrammi e byte compressi dall'ultima chiamata (poi si riparte da zero). */
    fun leggiUscita(): Pair<Int, Long> = fotogrammiUsciti.getAndSet(0) to byteUsciti.getAndSet(0)

    /** Il codificatore hardware per quel formato, se il telefono ce l'ha. */
    private fun cercaHardware(tipo: String): MediaCodecInfo? =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.firstOrNull { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(tipo, ignoreCase = true) } && eHardware(info)
        }

    private fun eHardware(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return info.isHardwareAccelerated && !info.isSoftwareOnly
        val nome = info.name.lowercase()
        return !nome.startsWith("omx.google.") && !nome.startsWith("c2.android.") && !nome.contains(".sw.")
    }

    /**
     * I fotogrammi al secondo massimi del codificatore hardware a questa risoluzione (in orizzontale o in verticale:
     * vale il peggiore dei due), per `capacita.formati`; 0 se non la sa fare.
     */
    fun fpsMassimo(larghezza: Int, altezza: Int, codec: Codec): Int {
        val tipo = if (codec == Codec.HEVC) MediaFormat.MIMETYPE_VIDEO_HEVC else MediaFormat.MIMETYPE_VIDEO_AVC
        val video = (cercaHardware(tipo) ?: cercaHardware(MediaFormat.MIMETYPE_VIDEO_AVC))
            ?.let { runCatching { it.getCapabilitiesForType(tipo).videoCapabilities }.getOrNull() ?: runCatching { it.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities }.getOrNull() }
            ?: return 30
        return listOf(60, 30, 24).firstOrNull { fps ->
            runCatching { video.areSizeAndRateSupported(larghezza, altezza, fps.toDouble()) && video.areSizeAndRateSupported(altezza, larghezza, fps.toDouble()) }
                .getOrDefault(false)
        } ?: 0
    }

    /**
     * Crea il codificatore e restituisce la sua Surface d'ingresso. Se HEVC non c'è si usa H.264; se la dimensione
     * non è supportata si scende (4K → 1080p → 720p). `verticale`: il telefono è tenuto in verticale e il video esce
     * girato (1080×1920), come sull'iPhone. `cavo`: collegati con il cavo, bitrate più alto. Il formato effettivo è
     * in [formato].
     */
    fun avvia(
        larghezzaVoluta: Int,
        altezzaVoluta: Int,
        fps: Int,
        codecVoluto: Codec,
        verticale: Boolean = false,
        cavo: Boolean = false,
        bitrateIniziale: (Int) -> Int,
    ): Surface {
        ferma()
        var scelto = codecVoluto
        var tipo = if (scelto == Codec.HEVC) MediaFormat.MIMETYPE_VIDEO_HEVC else MediaFormat.MIMETYPE_VIDEO_AVC
        var info = cercaHardware(tipo)
        if (info == null && scelto == Codec.HEVC) {
            scelto = Codec.H264
            tipo = MediaFormat.MIMETYPE_VIDEO_AVC
            info = cercaHardware(tipo)
        }
        val capacita = info?.getCapabilitiesForType(tipo)
        val lungo = maxOf(larghezzaVoluta, altezzaVoluta)
        val corto = minOf(larghezzaVoluta, altezzaVoluta)
        val (lato1, lato2) = listOf(lungo to corto, 1920 to 1080, 1280 to 720)
            .filter { it.first <= lungo }
            .firstOrNull { (l, a) ->
                capacita?.videoCapabilities?.let { v -> if (verticale) v.isSizeSupported(a, l) else v.isSizeSupported(l, a) } ?: true
            }
            ?: (1280 to 720)
        val larghezza = if (verticale) lato2 else lato1
        val altezza = if (verticale) lato1 else lato2

        bitrateMassimo = capacita?.videoCapabilities?.bitrateRange?.upper ?: 0
        val base = limitaBitrate(BitrateVideo.base(larghezza, altezza, fps, scelto, cavo))
        bitrateBase = base
        val profilo = profiloMigliore(capacita, scelto)
        val cbr = capacita?.encoderCapabilities?.isBitrateModeSupported(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR) == true

        /** Il formato per MediaCodec; `minimo`: senza le chiavi facoltative (per i codificatori che le rifiutano). */
        fun formatoCodec(minimo: Boolean) = MediaFormat.createVideoFormat(tipo, larghezza, altezza).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrateIniziale(base))
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
                setInteger(MediaFormat.KEY_PREPEND_HEADER_TO_SYNC_FRAMES, 1)
            }
            if (minimo) return@apply
            // Tempo reale: il codificatore non deve mai restare indietro.
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            // Un fotogramma esce appena è pronto, senza aspettarne altri (la chiave esiste da Android 11).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) setInteger(MediaFormat.KEY_LATENCY, 1)
            // Bitrate costante: nessun picco che la rete deve assorbire; senza CBR il VBR resta sotto KEY_BIT_RATE in media.
            setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                if (cbr) MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR else MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR,
            )
            if (profilo != null) {
                setInteger(MediaFormat.KEY_PROFILE, profilo.profile)
                setInteger(MediaFormat.KEY_LEVEL, profilo.level)
            }
        }

        val nuovoThread = HandlerThread("webcamlr-codifica").apply { start() }
        val nuovo = if (info != null) MediaCodec.createByCodecName(info.name) else MediaCodec.createEncoderByType(tipo)
        nuovo.setCallback(Richiamo(nuovo), Handler(nuovoThread.looper))
        try {
            nuovo.configure(formatoCodec(minimo = false), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        } catch (e: Exception) {
            // Qualche codificatore rifiuta le chiavi facoltative: si riprova con il minimo indispensabile.
            Log.w(TAG, "Formato rifiutato, riprovo senza latenza, priorità, modo del bitrate e profilo", e)
            nuovo.reset()
            nuovo.setCallback(Richiamo(nuovo), Handler(nuovoThread.looper))
            nuovo.configure(formatoCodec(minimo = true), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
        val superficie = nuovo.createInputSurface()
        nuovo.start()
        codec = nuovo
        thread = nuovoThread
        parametri = null
        primoFotogramma = true
        fotogrammiUsciti.set(0)
        byteUsciti.set(0)
        formato = FormatoVideo(scelto, larghezza, altezza, fps)
        Log.i(TAG, "Codificatore ${nuovo.name}: ${larghezza}×$altezza, $fps fps, ${base / 1000} kbit/s, profilo ${profilo?.profile}")
        return superficie
    }

    /**
     * Il collegamento è passato al cavo o al Wi-Fi senza fermare il codificatore: il bitrate della qualità scelta
     * cambia. Quello effettivo lo rimette chi chiama, con l'adattamento alla rete ([impostaBitrate]).
     */
    fun impostaCavo(cavo: Boolean) {
        val attuale = formato ?: return
        bitrateBase = limitaBitrate(BitrateVideo.base(attuale.larghezza, attuale.altezza, attuale.fps, attuale.codec, cavo))
    }

    private fun limitaBitrate(bitrate: Int): Int = if (bitrateMassimo > 0) minOf(bitrate, bitrateMassimo) else bitrate

    /** High per H.264, Main per HEVC, con il livello più alto che il codificatore dichiara; `null` se non lo dichiara. */
    private fun profiloMigliore(capacita: MediaCodecInfo.CodecCapabilities?, codec: Codec): MediaCodecInfo.CodecProfileLevel? {
        val voluto = if (codec == Codec.HEVC) {
            MediaCodecInfo.CodecProfileLevel.HEVCProfileMain
        } else {
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh
        }
        return capacita?.profileLevels?.filter { it.profile == voluto }?.maxByOrNull { it.level }
    }

    fun ferma() {
        val vecchio = codec ?: return
        codec = null
        try {
            vecchio.stop()
        } catch (e: Exception) {
            // già fermo o in errore
        }
        vecchio.release()
        thread?.quitSafely()
        thread = null
    }

    @Volatile private var ultimaRichiestaChiave = 0L

    /**
     * Il prossimo fotogramma sarà un fotogramma chiave (dopo una perdita o un nuovo collegamento). Con la rete satura
     * ogni scarto ne chiederebbe uno: al massimo uno ogni 500 ms, salvo `subito` (ripresa, collegamento nuovo).
     */
    fun richiediFotogrammaChiave(subito: Boolean = false) {
        val attuale = codec ?: return
        val adesso = android.os.SystemClock.elapsedRealtime()
        if (!subito && adesso - ultimaRichiestaChiave < 500) return
        ultimaRichiestaChiave = adesso
        try {
            attuale.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
        } catch (e: Exception) {
            Log.w(TAG, "Fotogramma chiave non richiesto", e)
        }
    }

    /** Cambia il bitrate senza fermare il codificatore (qualità che segue la rete). */
    fun impostaBitrate(bitrate: Int) {
        val attuale = codec ?: return
        try {
            attuale.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrate) })
        } catch (e: Exception) {
            Log.w(TAG, "Bitrate non cambiato", e)
        }
    }

    private inner class Richiamo(private val proprio: MediaCodec) : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, indice: Int) = Unit // ingresso da Surface

        override fun onOutputBufferAvailable(codec: MediaCodec, indice: Int, info: MediaCodec.BufferInfo) {
            if (proprio !== this@Codificatore.codec) return
            try {
                val buffer = codec.getOutputBuffer(indice)
                if (buffer != null && info.size > 0) {
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val dati = ByteArray(info.size).also { buffer.get(it) }
                    consegna(dati, info)
                }
                codec.releaseOutputBuffer(indice, false)
            } catch (e: IllegalStateException) {
                // il codificatore si sta fermando
            }
        }

        override fun onOutputFormatChanged(codec: MediaCodec, formato: MediaFormat) {
            // SPS e PPS (e VPS per HEVC) arrivano anche qui, in csd-0 e csd-1, già con i codici di inizio.
            val unione = java.io.ByteArrayOutputStream()
            for (chiave in listOf("csd-0", "csd-1", "csd-2")) {
                if (!formato.containsKey(chiave)) continue
                val buffer = formato.getByteBuffer(chiave) ?: continue
                val copia = ByteArray(buffer.remaining()).also { buffer.duplicate().get(it) }
                unione.write(copia)
            }
            if (unione.size() > 0) parametri = unione.toByteArray()
        }

        override fun onError(codec: MediaCodec, errore: MediaCodec.CodecException) {
            if (proprio !== this@Codificatore.codec) return
            Log.e(TAG, "Codificatore in errore", errore)
            suErrore(if (errore.isTransient) "transitorio" else "fermo")
        }
    }

    private fun consegna(dati: ByteArray, info: MediaCodec.BufferInfo) {
        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
            parametri = dati
            return
        }
        val chiave = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
        var uscita = dati
        var conParametri = false
        if (chiave) {
            val hevc = formato?.codec == Codec.HEVC
            val haParametri = AnnexB.unita(dati).any { nal ->
                if (hevc) AnnexB.tipoHEVC(nal) in 32..34 else AnnexB.tipoH264(nal) == 7
            }
            val salvati = parametri
            when {
                haParametri -> conParametri = true
                salvati != null -> {
                    // Ogni fotogramma chiave porta con sé i parametri: il computer può partire da lì.
                    uscita = salvati + dati
                    conParametri = true
                }
            }
        }
        fotogrammiUsciti.incrementAndGet()
        byteUsciti.addAndGet(uscita.size.toLong())
        if (primoFotogramma) {
            primoFotogramma = false
            Orologio.calibra(info.presentationTimeUs)
        }
        val timestamp = if (info.presentationTimeUs > 0) info.presentationTimeUs.toULong() else Orologio.adesso()
        suFotogramma(FotogrammaVideo(timestamp, chiave, conParametri, uscita))
    }

    companion object {
        private const val TAG = "WebcamLR"
    }
}
