package it.lrapps.webcamlr.android.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.media.audiofx.NoiseSuppressor
import android.os.Process
import android.util.Log
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.sistema.Orologio
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.protocollo.FormatoAudio
import it.lrapps.webcamlr.protocollo.PacchettoAudio
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs

/**
 * P20: il microfono del telefono al computer (protocollo, «Audio»; come CodificatoreAudio.swift). AudioRecord a
 * 48 kHz mono → codificatore AAC-LC di sistema (MediaCodec), 96 kbit/s (voce piena, senza artefatti sulle sibilanti)
 * → un pacchetto per frame AAC di 1024 campioni, grezzo (senza ADTS). Il timestamp è quello del primo campione, sullo
 * stesso orologio dei fotogrammi ([Orologio]): AudioRecord.getTimestamp con la base del tempo giusta, su una linea del
 * tempo regolare (passi esatti di 1024 campioni) che segue il microfono piano: il ritardo resta stabile.
 *
 * Tutto su un thread suo, con priorità audio. Ogni avvio è un «flusso» nuovo: il collegamento rimanda `formato-audio`.
 * Sorgente CAMCORDER: il microfono pensato per i video, senza la cancellazione dell'eco delle chiamate (l'eco la toglie
 * l'app di videochiamata sul computer, che sa cosa esce dalle casse: il telefono non suona la chiamata, quindi una
 * sua cancellazione dell'eco non avrebbe nulla da togliere e rovinerebbe solo la voce).
 * Riduzione del rumore del sistema (NoiseSuppressor) se il telefono ce l'ha: usa più microfoni e toglie ventole e
 * rumore di fondo meglio di quanto possa fare dopo l'app sul computer. Il controllo automatico del volume (AGC) no:
 * l'app di chiamata ha già il suo, e due in fila fanno «pompare» il volume.
 */
class CodificatoreAudio(
    /** Ogni pacchetto, dal thread dell'audio, con il numero del flusso. */
    private val suPacchetto: (PacchettoAudio, Int) -> Unit,
    /** Il microfono non si è aperto o si è fermato da solo (permesso tolto, un'altra app): dal thread dell'audio. */
    private val suErrore: (String) -> Unit,
) {
    private val attivo = AtomicBoolean(false)
    private val flussi = AtomicInteger(0)
    @Volatile private var thread: Thread? = null

    val inFunzione: Boolean get() = attivo.get()

    /** Accende il microfono (serve il permesso RECORD_AUDIO, chiesto prima dall'interfaccia). */
    fun avvia() {
        if (!attivo.compareAndSet(false, true)) return
        val flusso = flussi.incrementAndGet()
        thread = Thread({ registra(flusso) }, "webcamlr-audio").apply { isDaemon = true; start() }
    }

    /** Spegne il microfono e aspetta (al massimo mezzo secondo) che il thread finisca. */
    fun ferma() {
        if (!attivo.compareAndSet(true, false)) return
        val vecchio = thread
        thread = null
        try {
            vecchio?.join(500)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    @SuppressLint("MissingPermission") // il permesso lo controlla la sessione prima di avviare
    private fun registra(flusso: Int) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val minimo = AudioRecord.getMinBufferSize(FREQUENZA, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minimo <= 0) {
            fallisci(Testi.testo(R.string.microfono_motivo_48khz))
            return
        }
        val registratore = try {
            AudioRecord(MediaRecorder.AudioSource.CAMCORDER, FREQUENZA, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minimo, BYTE_PER_FRAME * 8))
        } catch (e: Exception) {
            fallisci(Testi.testo(R.string.microfono_motivo_non_acceso))
            return
        }
        if (registratore.state != AudioRecord.STATE_INITIALIZED) {
            registratore.release()
            fallisci(Testi.testo(R.string.microfono_motivo_non_acceso))
            return
        }
        val riduzioneRumore = attivaRiduzioneRumore(registratore.audioSessionId)
        val codec = try {
            creaCodec()
        } catch (e: Exception) {
            Log.e(TAG, "Codificatore AAC non disponibile", e)
            riduzioneRumore?.release()
            registratore.release()
            fallisci(Testi.testo(R.string.microfono_motivo_codifica))
            return
        }
        try {
            registratore.startRecording()
            if (registratore.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                fallisci(Testi.testo(R.string.microfono_motivo_altra_app))
                return
            }
            ciclo(registratore, codec, flusso)
        } catch (e: Exception) {
            Log.w(TAG, "Audio interrotto", e)
            if (attivo.get()) fallisci(Testi.testo(R.string.microfono_motivo_interrotto))
        } finally {
            runCatching { registratore.stop() }
            riduzioneRumore?.let { runCatching { it.release() } }
            registratore.release()
            runCatching { codec.stop() }
            codec.release()
        }
    }

    /** La riduzione del rumore del sistema sul microfono, se c'è e si accende; `null` altrimenti (si va senza). */
    private fun attivaRiduzioneRumore(sessione: Int): NoiseSuppressor? {
        if (!RIDUZIONE_RUMORE || !NoiseSuppressor.isAvailable()) return null
        return try {
            NoiseSuppressor.create(sessione)?.also { effetto ->
                if (effetto.setEnabled(true) != android.media.audiofx.AudioEffect.SUCCESS) Log.i(TAG, "Riduzione del rumore non accesa")
            }
        } catch (e: Exception) {
            Log.i(TAG, "Riduzione del rumore non disponibile", e)
            null
        }
    }

    private fun creaCodec(): MediaCodec {
        val formato = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, FREQUENZA, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, BYTE_PER_FRAME * 2)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(formato, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        return codec
    }

    /** Legge 1024 campioni alla volta, li dà al codificatore con il loro istante, e manda quello che esce. */
    private fun ciclo(registratore: AudioRecord, codec: MediaCodec, flusso: Int) {
        val pcm = ByteArray(BYTE_PER_FRAME)
        val info = MediaCodec.BufferInfo()
        val istante = AudioTimestamp()
        val base = if (Orologio.tempoReale) AudioTimestamp.TIMEBASE_BOOTTIME else AudioTimestamp.TIMEBASE_MONOTONIC
        var campioniLetti = 0L
        // L'istante (µs) del campione 0 del flusso: la linea del tempo regolare da cui escono tutti i timestamp.
        var ancora = Long.MIN_VALUE
        while (attivo.get()) {
            var letti = 0
            while (letti < pcm.size && attivo.get()) {
                val n = registratore.read(pcm, letti, pcm.size - letti)
                if (n < 0) throw IllegalStateException("AudioRecord.read: $n")
                letti += n
            }
            if (!attivo.get()) break
            // L'istante del campione 0 secondo l'ultimo timestamp del microfono, se c'è. La linea del tempo lo segue
            // piano (1/32 dello scarto a blocco, circa 0,7 s): niente oscillazioni tra un pacchetto e l'altro, ma
            // nemmeno deriva tra l'orologio dell'audio e quello del telefono. Uno scarto grande (inizio, blocchi
            // persi dal sistema) si corregge subito. Senza timestamp: adesso meno i campioni letti, solo per partire.
            val misurato = if (registratore.getTimestamp(istante, base) == AudioRecord.SUCCESS && istante.nanoTime > 0) {
                istante.nanoTime / 1000 - istante.framePosition * 1_000_000L / FREQUENZA
            } else {
                null
            }
            if (misurato != null) {
                val scarto = if (ancora == Long.MIN_VALUE) Long.MAX_VALUE else misurato - ancora
                ancora = if (abs(scarto) > SCARTO_MASSIMO_US) misurato else ancora + scarto / 32
            } else if (ancora == Long.MIN_VALUE) {
                ancora = Orologio.adesso().toLong() - (campioniLetti + CAMPIONI_PER_FRAME) * 1_000_000L / FREQUENZA
            }
            val tempo = ancora + campioniLetti * 1_000_000L / FREQUENZA
            campioniLetti += CAMPIONI_PER_FRAME
            val indice = codec.dequeueInputBuffer(10_000)
            if (indice >= 0) {
                val ingresso = codec.getInputBuffer(indice)
                if (ingresso != null) {
                    ingresso.clear()
                    ingresso.put(pcm, 0, minOf(pcm.size, ingresso.remaining()))
                    codec.queueInputBuffer(indice, 0, minOf(pcm.size, ingresso.capacity()), maxOf(tempo, 0L), 0)
                } else {
                    codec.queueInputBuffer(indice, 0, 0, maxOf(tempo, 0L), 0)
                }
            }
            svuota(codec, info, flusso)
        }
    }

    private fun svuota(codec: MediaCodec, info: MediaCodec.BufferInfo, flusso: Int) {
        while (true) {
            val indice = codec.dequeueOutputBuffer(info, 0)
            if (indice < 0) return
            try {
                // La configurazione (AudioSpecificConfig) è sempre la stessa per 48 kHz mono: viaggia in `formato-audio`.
                val configurazione = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                if (!configurazione && info.size > 0) {
                    val uscita = codec.getOutputBuffer(indice)
                    if (uscita != null) {
                        uscita.position(info.offset)
                        uscita.limit(info.offset + info.size)
                        val dati = ByteArray(info.size).also { uscita.get(it) }
                        suPacchetto(PacchettoAudio(maxOf(info.presentationTimeUs, 0L).toULong(), dati), flusso)
                    }
                }
            } finally {
                codec.releaseOutputBuffer(indice, false)
            }
        }
    }

    private fun fallisci(motivo: String) {
        attivo.set(false)
        Log.w(TAG, motivo)
        suErrore(motivo)
    }

    companion object {
        private const val TAG = "WebcamLR"
        const val FREQUENZA = 48_000
        const val CAMPIONI_PER_FRAME = FormatoAudio.CAMPIONI_PER_PACCHETTO
        private const val BYTE_PER_FRAME = CAMPIONI_PER_FRAME * 2

        /** AAC-LC mono a 48 kHz: 96 kbit/s, la voce piena (64 bastavano appena). */
        const val BITRATE = 96_000

        /** Oltre questo scarto (µs) la linea del tempo dell'audio si riallinea di colpo invece di seguire piano. */
        private const val SCARTO_MASSIMO_US = 20_000L

        /** La riduzione del rumore del sistema, se il telefono ce l'ha (per ora sempre: nel protocollo non c'è un comando). */
        private const val RIDUZIONE_RUMORE = true
    }
}
