package it.lrapps.webcamlr.android.effetti

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import it.lrapps.webcamlr.android.logica.Rettangolo
import it.lrapps.webcamlr.android.logica.VoltiTrovati
import java.nio.ByteOrder

/**
 * L'analisi delle immagini per gli effetti, sul telefono e senza rete, con MediaPipe Tasks (Apache 2.0) e i modelli
 * in `assets/modelli` (Apache 2.0):
 *
 * - **maschera della persona** (Selfie Segmenter; il modello «landscape» per il video orizzontale) per lo sfondo
 *   sfocato o sostituito e per limitare il ritocco alla persona;
 * - **volti** (BlazeFace a corto raggio) per inquadratura automatica, luce sul volto e postura.
 *
 * Perché MediaPipe e non ML Kit: è open source con licenza Apache 2.0 (codice e modelli), funziona senza servizi Google
 * (anche sui Huawei, come il resto dell'app) e senza scaricare nulla dopo l'installazione. Gira sul processore
 * (delegato CPU, il più prevedibile su tutti i telefoni) su immagini piccole (384×216) al massimo una alla volta.
 *
 * Le immagini arrivano dal [it.lrapps.webcamlr.android.video.Renderizzatore] (video di base, già girato e specchiato
 * come quello inviato); i risultati sono nelle coordinate del video, prima dell'inquadratura automatica.
 */
class AnalisiImmagine(context: Context) {
    private val app = context.applicationContext
    private val thread = HandlerThread("webcamlr-analisi").apply { start() }
    private val gestore = Handler(thread.looper)

    // Solo sul thread dell'analisi.
    private var segmentatore: ImageSegmenter? = null
    private var segmentatoreOrizzontale: Boolean? = null
    private var rilevatore: FaceDetector? = null
    private var mascheraPrecedente: FloatArray? = null
    private var mascheraUscita = ByteArray(0)

    /** Cosa serve adesso (dalla sessione). */
    @Volatile var vuoleMaschera = false
    @Volatile var vuoleVolti = false

    /** La maschera (byte per punto, righe dall'alto) con lo specchio e la rotazione dell'immagine analizzata. */
    @Volatile var suMaschera: ((dati: ByteArray, larghezza: Int, altezza: Int, specchiata: Boolean, rotazione: Int) -> Unit)? = null
    @Volatile var suVolti: ((VoltiTrovati) -> Unit)? = null

    /** I modelli ci sono e MediaPipe si carica: lo si sa dopo [prepara]. */
    @Volatile var mascheraDisponibile = false
        private set
    @Volatile var voltiDisponibili = false
        private set

    /** Prova a caricare i modelli (in sottofondo); `pronta` arriva sul thread dell'analisi. */
    fun prepara(pronta: () -> Unit) = gestore.post {
        mascheraDisponibile = runCatching { segmentatorePer(orizzontale = true) != null }.getOrDefault(false)
        voltiDisponibili = runCatching { rilevatorePronto() != null }.getOrDefault(false)
        pronta()
    }

    /**
     * Un'immagine del video da analizzare (sul thread GL): si lavora sul thread dell'analisi e alla fine si chiama
     * `finito` (l'immagine si può riusare da lì).
     */
    fun analizza(immagine: Bitmap, specchiata: Boolean, rotazione: Int, finito: () -> Unit) {
        val inviato = gestore.post {
            try {
                elabora(immagine, specchiata, rotazione)
            } catch (e: Throwable) {
                Log.w(TAG, "Analisi non riuscita", e)
            } finally {
                finito()
            }
        }
        if (!inviato) finito()
    }

    /** La maschera vecchia non serve più (altro obiettivo, rotazione): niente fusione con la prossima. */
    fun dimentica() = gestore.post { mascheraPrecedente = null }

    fun termina() {
        gestore.post {
            runCatching { segmentatore?.close() }
            runCatching { rilevatore?.close() }
            segmentatore = null
            rilevatore = null
            thread.quitSafely()
        }
    }

    private fun elabora(immagine: Bitmap, specchiata: Boolean, rotazione: Int) {
        if (!vuoleMaschera && !vuoleVolti) return
        val mp = BitmapImageBuilder(immagine).build()
        val l = immagine.width
        val a = immagine.height
        if (vuoleMaschera) {
            segmentatorePer(l >= a)?.let { segmentatore ->
                val risultato = segmentatore.segment(mp)
                val maschere = risultato.confidenceMasks().orElse(null)
                // Selfie Segmenter: un canale, la probabilità che il punto sia la persona (l'ultimo, se fossero due).
                val maschera = maschere?.lastOrNull()
                // Di solito grande come l'immagine; se no va bene lo stesso (sulla GPU le coordinate sono normalizzate).
                val lm = maschera?.getWidth() ?: 0
                val am = maschera?.getHeight() ?: 0
                if (maschera != null && lm > 0 && am > 0) {
                    val valori = ByteBufferExtractor.extract(maschera).order(ByteOrder.nativeOrder()).asFloatBuffer()
                    val n = lm * am
                    if (valori.remaining() >= n) {
                        val attuale = FloatArray(n).also { valori.get(it) }
                        // Un po' della maschera di prima: meno tremolio sui bordi, senza scie (si fonde solo a parità).
                        val precedente = mascheraPrecedente?.takeIf { it.size == n }
                        if (mascheraUscita.size != n) mascheraUscita = ByteArray(n)
                        for (i in 0 until n) {
                            val v = if (precedente != null) attuale[i] * 0.7f + precedente[i] * 0.3f else attuale[i]
                            attuale[i] = v
                            mascheraUscita[i] = (v.coerceIn(0f, 1f) * 255f + 0.5f).toInt().toByte()
                        }
                        mascheraPrecedente = attuale
                        suMaschera?.invoke(mascheraUscita.copyOf(), lm, am, specchiata, rotazione)
                    }
                }
            }
        }
        if (vuoleVolti) {
            rilevatorePronto()?.let { rilevatore ->
                val trovati = rilevatore.detect(mp).detections().map { volto ->
                    val r = volto.boundingBox()
                    Rettangolo(
                        (r.left / l).coerceIn(0f, 1f), (r.top / a).coerceIn(0f, 1f),
                        (r.right / l).coerceIn(0f, 1f), (r.bottom / a).coerceIn(0f, 1f),
                    )
                }.filter { it.larghezza > 0.01f && it.altezza > 0.01f }
                suVolti?.invoke(VoltiTrovati(trovati, SystemClock.elapsedRealtime(), specchiata))
            }
        }
    }

    private fun segmentatorePer(orizzontale: Boolean): ImageSegmenter? {
        if (segmentatore != null && segmentatoreOrizzontale == orizzontale) return segmentatore
        runCatching { segmentatore?.close() }
        segmentatore = null
        mascheraPrecedente = null
        val modello = if (orizzontale) "modelli/selfie_segmenter_landscape.tflite" else "modelli/selfie_segmenter.tflite"
        segmentatore = try {
            ImageSegmenter.createFromOptions(
                app,
                ImageSegmenter.ImageSegmenterOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath(modello).build())
                    .setRunningMode(RunningMode.IMAGE)
                    .setOutputCategoryMask(false)
                    .setOutputConfidenceMasks(true)
                    .build(),
            )
        } catch (e: Throwable) {
            Log.w(TAG, "Maschera della persona non disponibile", e)
            null
        }
        segmentatoreOrizzontale = orizzontale
        return segmentatore
    }

    private fun rilevatorePronto(): FaceDetector? {
        rilevatore?.let { return it }
        rilevatore = try {
            FaceDetector.createFromOptions(
                app,
                FaceDetector.FaceDetectorOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath("modelli/blaze_face_short_range.tflite").build())
                    .setRunningMode(RunningMode.IMAGE)
                    .setMinDetectionConfidence(0.5f)
                    .build(),
            )
        } catch (e: Throwable) {
            Log.w(TAG, "Rilevamento dei volti non disponibile", e)
            null
        }
        return rilevatore
    }

    companion object {
        private const val TAG = "WebcamLR"
    }
}
