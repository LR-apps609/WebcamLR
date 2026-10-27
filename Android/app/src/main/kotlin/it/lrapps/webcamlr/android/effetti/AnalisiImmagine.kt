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
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import it.lrapps.webcamlr.android.logica.Rettangolo
import it.lrapps.webcamlr.android.logica.VoltiTrovati
import java.nio.ByteOrder
import kotlin.math.abs

/**
 * L'analisi delle immagini per gli effetti, sul telefono e senza rete, con MediaPipe Tasks (Apache 2.0) e i modelli
 * in `assets/modelli` (Apache 2.0):
 *
 * - **maschera della persona** per lo sfondo sfocato o sostituito e per limitare il ritocco alla persona. Prima scelta
 *   il modello a più classi (sfondo, capelli, pelle, volto, vestiti, accessori: bordo dei capelli molto migliore) sulla
 *   GPU; se il telefono non lo regge (in media più di [MS_MASSIMI_MULTICLASSE] ms per maschera, cioè meno di circa
 *   22 maschere al secondo) o la GPU non si apre, il Selfie Segmenter leggero sul processore (il modello «landscape»
 *   per il video orizzontale). Una maschera lenta resta indietro rispetto al video e lascia scie: meglio un bordo
 *   un po' meno fine ma a ogni fotogramma. Confronto dei modelli in `Documenti/Modelli ritaglio.md`;
 * - **volti** (BlazeFace a corto raggio) per inquadratura automatica, luce sul volto e postura.
 *
 * Perché MediaPipe e non ML Kit: è open source con licenza Apache 2.0 (codice e modelli), funziona senza servizi Google
 * (anche sui Huawei, come il resto dell'app) e senza scaricare nulla dopo l'installazione. Gira sul processore
 * (delegato CPU, il più prevedibile su tutti i telefoni; GPU solo per il modello a più classi) su immagini piccole
 * (384×216) al massimo una alla volta.
 * Con lo sfondo acceso la maschera si calcola a ogni fotogramma (appena finita la precedente); i volti bastano circa
 * 12 volte al secondo.
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
    /** Il modello a più classi sulla GPU è ancora in prova (o scelto); `false` per sempre dopo il primo ripiego. */
    private var multiclassePossibile = true
    private var segmentatoreMulticlasse = false
    private var mediaMsMulticlasse = 0f
    private var maschereMulticlasse = 0
    private var rilevatore: FaceDetector? = null
    private var mascheraPrecedente: FloatArray? = null
    private var mascheraUscita = ByteArray(0)
    private var ultimiVolti = 0L

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
                val inizio = SystemClock.elapsedRealtime()
                val multiclasse = segmentatoreMulticlasse
                val risultato = try {
                    segmentatore.segment(mp)
                } catch (e: Throwable) {
                    if (!multiclasse) throw e
                    ripiegaSulLeggero("errore della GPU", e) // testo tecnico
                    return@let
                }
                val durata = SystemClock.elapsedRealtime() - inizio
                val maschere = risultato.confidenceMasks().orElse(null)
                // Con più classi (softmax, la somma fa 1) la prima è lo sfondo: persona = 1 − sfondo, così capelli,
                // pelle, volto, vestiti e accessori contano tutti. Il Selfie Segmenter ha un solo canale: la persona.
                val complemento = (maschere?.size ?: 0) > 1
                val maschera = if (complemento) maschere?.firstOrNull() else maschere?.lastOrNull()
                // Di solito grande come l'immagine; se no va bene lo stesso (sulla GPU le coordinate sono normalizzate).
                val lm = maschera?.getWidth() ?: 0
                val am = maschera?.getHeight() ?: 0
                if (maschera != null && lm > 0 && am > 0) {
                    val valori = ByteBufferExtractor.extract(maschera).order(ByteOrder.nativeOrder()).asFloatBuffer()
                    val n = lm * am
                    if (valori.remaining() >= n) {
                        val attuale = FloatArray(n).also { valori.get(it) }
                        if (complemento) for (i in 0 until n) attuale[i] = 1f - attuale[i]
                        // Filtro adattivo, senza ritardo: dove la maschera cambia poco (tremolio del bordo) un filo di
                        // quella di prima, dove cambia (la persona si muove) subito la nuova. Niente scie.
                        val precedente = mascheraPrecedente?.takeIf { it.size == n }
                        if (mascheraUscita.size != n) mascheraUscita = ByteArray(n)
                        for (i in 0 until n) {
                            val v = if (precedente != null) {
                                val nuova = attuale[i]
                                val peso = (PESO_MASCHERA_NUOVA + 3f * abs(nuova - precedente[i])).coerceAtMost(1f)
                                nuova * peso + precedente[i] * (1f - peso)
                            } else {
                                attuale[i]
                            }
                            attuale[i] = v
                            mascheraUscita[i] = (v.coerceIn(0f, 1f) * 255f + 0.5f).toInt().toByte()
                        }
                        mascheraPrecedente = attuale
                        suMaschera?.invoke(mascheraUscita.copyOf(), lm, am, specchiata, rotazione)
                    }
                }
                if (multiclasse) misuraMulticlasse(durata)
            }
        }
        val adesso = SystemClock.elapsedRealtime()
        if (vuoleVolti && adesso - ultimiVolti >= INTERVALLO_VOLTI_MS) {
            ultimiVolti = adesso
            rilevatorePronto()?.let { rilevatore ->
                val trovati = rilevatore.detect(mp).detections().map { volto ->
                    val r = volto.boundingBox()
                    Rettangolo(
                        (r.left / l).coerceIn(0f, 1f), (r.top / a).coerceIn(0f, 1f),
                        (r.right / l).coerceIn(0f, 1f), (r.bottom / a).coerceIn(0f, 1f),
                    )
                }.filter { it.larghezza > 0.01f && it.altezza > 0.01f }
                suVolti?.invoke(VoltiTrovati(trovati, adesso, specchiata))
            }
        }
    }

    private fun segmentatorePer(orizzontale: Boolean): ImageSegmenter? {
        // Il modello a più classi accetta qualunque proporzione: uno solo per verticale e orizzontale.
        if (segmentatore != null && segmentatoreMulticlasse) return segmentatore
        if (segmentatore != null && segmentatoreOrizzontale == orizzontale) return segmentatore
        runCatching { segmentatore?.close() }
        segmentatore = null
        mascheraPrecedente = null
        if (multiclassePossibile) {
            segmentatore = creaSegmentatore(MODELLO_MULTICLASSE, Delegate.GPU)
            if (segmentatore != null) {
                segmentatoreMulticlasse = true
                mediaMsMulticlasse = 0f
                maschereMulticlasse = 0
                Log.i(TAG, "Maschera della persona: modello a più classi sulla GPU")
                return segmentatore
            }
            multiclassePossibile = false
            Log.i(TAG, "Modello a più classi non disponibile: uso il Selfie Segmenter")
        }
        segmentatoreMulticlasse = false
        val modello = if (orizzontale) "modelli/selfie_segmenter_landscape.tflite" else "modelli/selfie_segmenter.tflite"
        segmentatore = creaSegmentatore(modello, Delegate.CPU)
        segmentatoreOrizzontale = orizzontale
        return segmentatore
    }

    private fun creaSegmentatore(modello: String, delegato: Delegate): ImageSegmenter? = try {
        ImageSegmenter.createFromOptions(
            app,
            ImageSegmenter.ImageSegmenterOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath(modello).setDelegate(delegato).build())
                .setRunningMode(RunningMode.IMAGE)
                .setOutputCategoryMask(false)
                .setOutputConfidenceMasks(true)
                .build(),
        )
    } catch (e: Throwable) {
        Log.w(TAG, "Maschera della persona non disponibile ($modello)", e)
        null
    }

    /** Media dei tempi del modello a più classi: se è troppo lento per questo telefono si passa al leggero. */
    private fun misuraMulticlasse(ms: Long) {
        maschereMulticlasse++
        // Le prime maschere sulla GPU sono lente (compilazione degli shader): non contano.
        if (maschereMulticlasse <= MASCHERE_DI_RISCALDAMENTO) return
        mediaMsMulticlasse = if (maschereMulticlasse == MASCHERE_DI_RISCALDAMENTO + 1) {
            ms.toFloat()
        } else {
            mediaMsMulticlasse * 0.9f + ms * 0.1f
        }
        if (maschereMulticlasse >= MASCHERE_DI_RISCALDAMENTO + MASCHERE_DI_PROVA && mediaMsMulticlasse > MS_MASSIMI_MULTICLASSE) {
            ripiegaSulLeggero("troppo lento: %.0f ms per maschera".format(mediaMsMulticlasse), null) // testo tecnico
        }
    }

    /** Dal modello a più classi al Selfie Segmenter, per il resto della sessione. */
    private fun ripiegaSulLeggero(motivo: String, errore: Throwable?) {
        Log.i(TAG, "Modello a più classi lasciato ($motivo): uso il Selfie Segmenter", errore)
        multiclassePossibile = false
        segmentatoreMulticlasse = false
        runCatching { segmentatore?.close() }
        segmentatore = null
        segmentatoreOrizzontale = null
        mascheraPrecedente = null
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
        /** Quanto conta la maschera nuova dove quasi non cambia (dove cambia di 0,1 o più conta tutta). */
        private const val PESO_MASCHERA_NUOVA = 0.7f
        private const val INTERVALLO_VOLTI_MS = 80L
        /** Selfie Multiclass 256×256 di MediaPipe (float32, ~16 MB): sfondo, capelli, pelle, volto, vestiti, accessori. */
        private const val MODELLO_MULTICLASSE = "modelli/selfie_multiclass_256x256.tflite"
        private const val MASCHERE_DI_RISCALDAMENTO = 5
        private const val MASCHERE_DI_PROVA = 20
        /** Oltre questa media (circa 22 maschere al secondo) la maschera resta indietro rispetto al video a 30 fps. */
        private const val MS_MASSIMI_MULTICLASSE = 45f
    }
}
