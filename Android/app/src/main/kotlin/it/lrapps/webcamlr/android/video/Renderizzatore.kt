package it.lrapps.webcamlr.android.video

import android.graphics.Bitmap
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import it.lrapps.webcamlr.android.logica.Inquadratura
import it.lrapps.webcamlr.android.logica.RicettaFiltro
import it.lrapps.webcamlr.android.logica.RicetteFiltri
import it.lrapps.webcamlr.android.logica.VoltiTrovati
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Gli effetti da disegnare, come li vuole la GPU: un'istantanea immutabile che la sessione sostituisce. */
data class ParametriEffetti(
    /** `null` = filtro `naturale`. */
    val ricetta: RicettaFiltro? = null,
    val luminosita: Float = 0f,
    val contrasto: Float = 0f,
    val saturazione: Float = 0f,
    val nitidezza: Float = 0f,
    val sfondo: Sfondo = Sfondo.NESSUNO,
    val intensitaSfondo: Float = 0.5f,
    val pelle: Float = 0f,
    /** P08 «Luce sul volto»: schiarimento morbido della zona del volto (gratis), oltre all'esposizione sul volto. */
    val luceVolto: Boolean = false,
    /** «Calore» (gratis), da 0 a 1: la matrice di colore verso il caldo su tutta l'immagine (vedi [guadagniCalore]). */
    val calore: Float = 0f,
) {
    enum class Sfondo { NESSUNO, SFOCATO, SOSTITUITO }

    /** Qualcosa da fare oltre a ruotare e specchiare. */
    val attivi: Boolean
        get() = ricetta != null || luminosita != 0f || contrasto != 0f || saturazione != 0f || nitidezza != 0f ||
            sfondo != Sfondo.NESSUNO || pelle > 0f || calore > 0f
}

/** Un'immagine da appoggiare sul video (sottopancia, logo), già con la trasparenza; `rettangolo` normalizzato, origine in alto. */
class Sovrapposizione(val immagine: Bitmap, val rettangolo: RectF)

/**
 * Dalla fotocamera al codificatore e all'anteprima, con OpenGL ES 2 su un thread suo (nessuna copia dei fotogrammi
 * nella memoria del processore).
 *
 * A ogni fotogramma:
 * 1. la fotocamera (SurfaceTexture) si disegna nel **video di base**, grande come il video inviato: ruotata di come è
 *    tenuto il telefono, ingrandita fino a riempire, specchiata se serve (1.14: specchio dal vivo);
 * 2. ogni tanto un'immagine piccola del video di base va all'analisi (maschera della persona, volti);
 * 3. se ci sono effetti: inquadratura automatica (ritaglio), calore, sfondo sfocato o sostituito con la maschera, ritocco
 *    della pelle, nitidezza, filtro e regolazioni, poi sottopancia e logo (dopo lo specchio: si leggono dritti);
 * 4. il risultato va al codificatore e all'anteprima. Con [anteprimaDelVideo] l'anteprima è **il video inviato**,
 *    girato per lo schermo e ingrandito fino a riempirlo (come la Fotocamera: senza bande, i bordi in più si tagliano
 *    solo sullo schermo; il codificatore riceve sempre il video intero); senza (lettore del QR code) è la fotocamera
 *    dritta rispetto allo schermo che riempie la vista.
 *
 * Convenzioni: la matrice della SurfaceTexture porta l'immagine dritta nell'orientamento naturale del telefono
 * (in verticale, già specchiata per la fotocamera frontale, come la mostra Android); le rotazioni sono in gradi in senso
 * orario; i punti normalizzati hanno l'origine in alto a sinistra (vedi [Geometria]).
 */
class Renderizzatore(private val anteprimaDelVideo: Boolean = false) {
    private val thread = HandlerThread("webcamlr-gl").apply { start() }
    private val gestore = Handler(thread.looper)

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var contesto: EGLContext = EGL14.EGL_NO_CONTEXT
    private var configurazione: EGLConfig? = null
    private var superficieVuota: EGLSurface = EGL14.EGL_NO_SURFACE

    private var programmaFotocamera: Programma? = null
    private var programmaCopia: Programma? = null
    private var programmaSfocatura: Programma? = null
    private var programmaRiduzione: Programma? = null
    private var programmaComposizione: Programma? = null

    private var texture = 0
    private var superficieTexture: SurfaceTexture? = null
    private var superficieCamera: Surface? = null

    private var codifica: EGLSurface = EGL14.EGL_NO_SURFACE
    private var larghezzaCodifica = 0
    private var altezzaCodifica = 0
    private var anteprima: EGLSurface = EGL14.EGL_NO_SURFACE
    @Volatile private var larghezzaAnteprima = 0
    @Volatile private var altezzaAnteprima = 0

    // I passaggi intermedi (sul thread GL).
    private val base = Bersaglio()
    private val finale = Bersaglio()
    private val ridotto = Bersaglio()
    private val ridottoB = Bersaglio()
    private val analisi = Bersaglio()
    private var textureMaschera = 0
    private var textureSfondo = 0
    private var textureCurva = 0
    private var ricettaCaricata: RicettaFiltro? = null
    private var sovrapposteCaricate: List<Pair<Int, RectF>> = emptyList()

    /** Dimensioni dell'immagine nell'orientamento naturale del telefono (in verticale sui telefoni). */
    private var larghezzaNaturale = 1080
    private var altezzaNaturale = 1920

    /** Il fotogramma della fotocamera come lo dà Camera2 (per [Geometria]). */
    @Volatile var larghezzaFotocamera = 1920
        private set
    @Volatile var altezzaFotocamera = 1080
        private set

    /** Come è girato il telefono (0, 90, 180, 270 in senso orario): decide il verso del video inviato. */
    @Volatile var rotazioneTelefono = 90

    /** Di quanto è girato lo schermo rispetto all'orientamento naturale: decide il verso dell'anteprima. */
    @Volatile var rotazioneSchermo = 0

    /** Lo specchio finale del video (per la frontale si toglie quello di Android, salvo «Specchia»). Dal vivo. */
    @Volatile var specchiaCodifica = false

    /**
     * Effetti sul computer: l'anteprima del telefono specchiata come uno specchio (solo sullo schermo, il video inviato
     * resta com'è). Il tocco per il fuoco ne tiene conto.
     */
    @Volatile var specchiaAnteprima = false

    /** Falso a schermo oscurato: niente disegno dell'anteprima, meno consumo. */
    @Volatile var anteprimaAttiva = true

    /** P07/P10: in pausa nessun fotogramma va al codificatore (né all'analisi). */
    @Volatile var codificaInPausa = false

    /** 1.14: finché il verso del telefono non è noto non si codifica nulla (nessun fotogramma girato male). */
    @Volatile var rotazioneNota = true

    /** Il timestamp (ns, orologio della fotocamera) dell'ultimo fotogramma disegnato sul codificatore. */
    @Volatile var suFotogramma: ((Long) -> Unit)? = null

    /** Gli effetti da disegnare; la sessione sostituisce l'istantanea. */
    @Volatile var effetti = ParametriEffetti()

    /** P04: lo zoom che segue i volti, calcolato qui a ogni fotogramma (la sessione lo accende e spegne). */
    val inquadratura = Inquadratura()

    /** Gli ultimi volti trovati dall'analisi, per l'inquadratura. */
    @Volatile var volti: VoltiTrovati? = null

    /**
     * L'analisi vuole immagini (maschera, volti): almeno ogni [intervalloAnalisiMs] il video di base, piccolo, va a
     * [suAnalisi] (sul thread GL; chi riceve copia o lavora e poi chiama [analisiFinita]).
     */
    @Volatile var analisiRichiesta = false
    @Volatile var intervalloAnalisiMs = 80L
    @Volatile var suAnalisi: ((immagine: Bitmap, specchiata: Boolean, rotazione: Int) -> Unit)? = null
    private val analisiOccupata = AtomicBoolean(false)
    private var ultimaAnalisi = 0L
    private var bitmapAnalisi: Bitmap? = null
    private var bufferAnalisi: ByteBuffer? = null

    // La maschera della persona più recente (sul thread GL).
    private var mascheraSpecchiata = false
    private var larghezzaMaschera = 1
    private var altezzaMaschera = 1
    private var mascheraRotazione = -1
    private var mascheraValida = false

    // Il video inviato: dimensioni del video di base (anche prima che ci sia il codificatore, per l'anteprima).
    @Volatile private var larghezzaVideo = 1920
    @Volatile private var altezzaVideo = 1080

    private var ultimoIstante = 0L

    // «Luce sul volto» (sul thread GL): la zona schiarita segue il volto, levigata, e si accende e spegne piano.
    private var luceX = 0.5f
    private var luceY = 0.5f
    private var luceL = 0f
    private var luceA = 0f
    private var luceForza = 0f

    private val trasformazione = FloatArray(16)
    private val identita = FloatArray(16).also { android.opengl.Matrix.setIdentityM(it, 0) }
    /** t → 1 − t, per le texture caricate da una bitmap (prima riga in alto). */
    private val capovoltaY = FloatArray(16).also {
        android.opengl.Matrix.setIdentityM(it, 0)
        it[5] = -1f
        it[13] = 1f
    }
    private val mvp = FloatArray(16)
    private val vertici: FloatBuffer = buffer(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val coordinate: FloatBuffer = buffer(floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f))

    private val tempoDisegno = java.util.concurrent.atomic.AtomicLong()

    /** I fotogrammi della fotocamera scartati perché ne era già arrivato uno più recente (per il registro). */
    private val fotogrammiSaltati = AtomicInteger()

    /** I fotogrammi saltati dall'ultima chiamata (poi si riparte da zero). */
    fun leggiFotogrammiSaltati(): Int = fotogrammiSaltati.getAndSet(0)
    private val fotogrammiDisegnati = java.util.concurrent.atomic.AtomicInteger()

    /**
     * Il misuratore: i millisecondi medi sul thread GL per ogni fotogramma mandato al codificatore dall'ultima
     * chiamata (poi si riparte da zero); `null` se non ne è passato nessuno. I comandi alla GPU sono asincroni: è il
     * tempo del thread, non quello della GPU, ma cresce con gli effetti e con la copia per l'analisi.
     */
    fun leggiMsPerFotogramma(): Double? {
        val n = fotogrammiDisegnati.getAndSet(0)
        val ns = tempoDisegno.getAndSet(0)
        return if (n > 0) ns / 1e6 / n else null
    }

    /** Le dimensioni della vista dell'anteprima (per il tocco del fuoco). */
    val dimensioniAnteprima: Pair<Int, Int> get() = larghezzaAnteprima to altezzaAnteprima

    /** Le dimensioni del video inviato (come le avrà il codificatore). */
    val dimensioniVideo: Pair<Int, Int> get() = larghezzaVideo to altezzaVideo

    /**
     * Prepara OpenGL e la superficie per la fotocamera. `larghezza`×`altezza` è la dimensione scelta tra quelle
     * della fotocamera (in orizzontale, come le dà Camera2); `orientamentoSensore` da CameraCharacteristics.
     */
    fun avvia(larghezza: Int, altezza: Int, orientamentoSensore: Int): Surface {
        var risultato: Surface? = null
        var errore: Throwable? = null
        eseguiEAspetta {
            try {
                if (display == EGL14.EGL_NO_DISPLAY) preparaEgl()
                rilasciaTexture()
                val verticale = orientamentoSensore % 180 == 90
                larghezzaNaturale = if (verticale) altezza else larghezza
                altezzaNaturale = if (verticale) larghezza else altezza
                larghezzaFotocamera = larghezza
                altezzaFotocamera = altezza
                val nuovaTexture = IntArray(1).also { GLES20.glGenTextures(1, it, 0) }[0]
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, nuovaTexture)
                parametriTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES)
                texture = nuovaTexture
                val st = SurfaceTexture(nuovaTexture)
                st.setDefaultBufferSize(larghezza, altezza)
                // Al massimo un fotogramma in coda: se il thread GL resta indietro (effetti, codificatore pieno) gli
                // avvisi si accumulano e [disegna] salta al più recente invece di smaltirli uno per uno.
                val inAttesa = AtomicInteger()
                st.setOnFrameAvailableListener({ if (inAttesa.getAndIncrement() == 0) gestore.post { disegna(st, inAttesa) } }, gestore)
                superficieTexture = st
                mascheraValida = false
                risultato = Surface(st).also { superficieCamera = it }
            } catch (e: Throwable) {
                errore = e
            }
        }
        errore?.let { throw IllegalStateException("OpenGL non disponibile", it) }
        return risultato ?: throw IllegalStateException("OpenGL non disponibile")
    }

    /** Le dimensioni del video inviato (già girate: 1080×1920 con il telefono in verticale). Valgono dal prossimo fotogramma. */
    fun impostaVideo(larghezza: Int, altezza: Int) {
        if (larghezza <= 0 || altezza <= 0) return
        larghezzaVideo = larghezza
        altezzaVideo = altezza
    }

    /** La superficie d'ingresso del codificatore, oppure `null` per smettere di codificare. */
    fun impostaCodifica(superficie: Surface?, larghezza: Int, altezza: Int) = eseguiEAspetta {
        if (codifica != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
            EGL14.eglDestroySurface(display, codifica)
            codifica = EGL14.EGL_NO_SURFACE
        }
        if (superficie != null && display != EGL14.EGL_NO_DISPLAY) {
            codifica = creaSuperficie(superficie)
            larghezzaCodifica = larghezza
            altezzaCodifica = altezza
            larghezzaVideo = larghezza
            altezzaVideo = altezza
        }
    }

    /** La superficie dell'anteprima sullo schermo (SurfaceView), oppure `null` quando sparisce. */
    fun impostaAnteprima(superficie: Surface?, larghezza: Int, altezza: Int) = eseguiEAspetta {
        if (anteprima != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
            EGL14.eglDestroySurface(display, anteprima)
            anteprima = EGL14.EGL_NO_SURFACE
        }
        if (superficie != null && superficie.isValid && display != EGL14.EGL_NO_DISPLAY) {
            anteprima = creaSuperficie(superficie)
            // L'anteprima non aspetta il ritmo dello schermo: eglSwapBuffers non blocca il thread GL, così il
            // fotogramma successivo per il codificatore non resta in coda dietro all'anteprima.
            EGL14.eglMakeCurrent(display, anteprima, anteprima, contesto)
            EGL14.eglSwapInterval(display, 0)
            EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
            larghezzaAnteprima = larghezza
            altezzaAnteprima = altezza
        }
    }

    /** L'analisi ha finito con l'immagine passata a [suAnalisi]: se ne può preparare un'altra. */
    fun analisiFinita() {
        analisiOccupata.set(false)
    }

    /**
     * La maschera della persona (un byte per punto, 255 = persona, righe dall'alto), calcolata su un'immagine del video
     * con questo specchio e questa rotazione. Da qualsiasi thread: si carica sulla GPU al prossimo fotogramma.
     */
    fun impostaMaschera(dati: ByteArray, larghezza: Int, altezza: Int, specchiata: Boolean, rotazione: Int) {
        if (dati.size < larghezza * altezza || larghezza <= 0 || altezza <= 0) return
        gestore.post {
            if (display == EGL14.EGL_NO_DISPLAY) return@post
            try {
                EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
                if (textureMaschera == 0) textureMaschera = nuovaTexture2D()
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureMaschera)
                GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 1)
                GLES20.glTexImage2D(
                    GLES20.GL_TEXTURE_2D, 0, GLES20.GL_LUMINANCE, larghezza, altezza, 0,
                    GLES20.GL_LUMINANCE, GLES20.GL_UNSIGNED_BYTE, ByteBuffer.wrap(dati, 0, larghezza * altezza),
                )
                mascheraSpecchiata = specchiata
                larghezzaMaschera = larghezza
                altezzaMaschera = altezza
                mascheraRotazione = rotazione
                mascheraValida = true
            } catch (e: RuntimeException) {
                Log.w(TAG, "Maschera non caricata", e)
            }
        }
    }

    /** La maschera non vale più (sfondo spento, altro obiettivo). */
    fun dimenticaMaschera() = gestore.post { mascheraValida = false }

    /** L'immagine dello sfondo sostituito (`null` per toglierla). La bitmap si può riciclare dopo il ritorno. */
    fun impostaSfondo(immagine: Bitmap?) = eseguiEAspetta {
        if (display == EGL14.EGL_NO_DISPLAY) return@eseguiEAspetta
        EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
        if (immagine == null) {
            if (textureSfondo != 0) GLES20.glDeleteTextures(1, intArrayOf(textureSfondo), 0)
            textureSfondo = 0
            larghezzaSfondo = 0
            altezzaSfondo = 0
            return@eseguiEAspetta
        }
        if (textureSfondo == 0) textureSfondo = nuovaTexture2D()
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureSfondo)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, immagine, 0)
        larghezzaSfondo = immagine.width
        altezzaSfondo = immagine.height
    }
    private var larghezzaSfondo = 0
    private var altezzaSfondo = 0

    /** Sottopancia e logo: le immagini si caricano sulla GPU subito; le bitmap si possono riciclare dopo il ritorno. */
    fun impostaSovrapposizioni(elenco: List<Sovrapposizione>) = eseguiEAspetta {
        if (display == EGL14.EGL_NO_DISPLAY) return@eseguiEAspetta
        EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
        sovrapposteCaricate.forEach { GLES20.glDeleteTextures(1, intArrayOf(it.first), 0) }
        sovrapposteCaricate = elenco.map { voce ->
            val id = nuovaTexture2D()
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, voce.immagine, 0)
            id to RectF(voce.rettangolo)
        }
    }

    fun ferma() {
        eseguiEAspetta {
            rilasciaTexture()
            if (display != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
                listOf(base, finale, ridotto, ridottoB, analisi).forEach { it.rilascia() }
                val texture = intArrayOf(textureMaschera, textureSfondo, textureCurva) + sovrapposteCaricate.map { it.first }
                texture.filter { it != 0 }.forEach { GLES20.glDeleteTextures(1, intArrayOf(it), 0) }
                EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                if (codifica != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, codifica)
                if (anteprima != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, anteprima)
                if (superficieVuota != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, superficieVuota)
                EGL14.eglDestroyContext(display, contesto)
                EGL14.eglReleaseThread()
                EGL14.eglTerminate(display)
            }
            textureMaschera = 0
            textureSfondo = 0
            textureCurva = 0
            sovrapposteCaricate = emptyList()
            codifica = EGL14.EGL_NO_SURFACE
            anteprima = EGL14.EGL_NO_SURFACE
            superficieVuota = EGL14.EGL_NO_SURFACE
            contesto = EGL14.EGL_NO_CONTEXT
            display = EGL14.EGL_NO_DISPLAY
        }
        thread.quitSafely()
    }

    // Sul thread GL

    private fun preparaEgl() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val versione = IntArray(2)
        check(EGL14.eglInitialize(display, versione, 0, versione, 1)) { "eglInitialize" }
        // EGL_RECORDABLE_ANDROID: la superficie del codificatore lo richiede su molti telefoni.
        val attributi = intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE,
        )
        val configurazioni = arrayOfNulls<EGLConfig>(1)
        val quante = IntArray(1)
        check(EGL14.eglChooseConfig(display, attributi, 0, configurazioni, 0, 1, quante, 0) && quante[0] > 0) { "eglChooseConfig" }
        configurazione = configurazioni[0]
        contesto = EGL14.eglCreateContext(
            display, configurazione, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
        )
        check(contesto != EGL14.EGL_NO_CONTEXT) { "eglCreateContext" }
        superficieVuota = EGL14.eglCreatePbufferSurface(
            display, configurazione, intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0,
        )
        EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
        programmaFotocamera = Programma(OMBREGGIATORE_VERTICI, FRAMMENTI_FOTOCAMERA)
        programmaCopia = Programma(OMBREGGIATORE_VERTICI, FRAMMENTI_COPIA)
        programmaSfocatura = Programma(OMBREGGIATORE_VERTICI, FRAMMENTI_SFOCATURA)
        programmaRiduzione = try {
            Programma(OMBREGGIATORE_VERTICI, FRAMMENTI_RIDUZIONE)
        } catch (e: RuntimeException) {
            Log.e(TAG, "Sfocatura senza alone non disponibile su questa GPU", e)
            null
        }
        // Se lo shader degli effetti non si compila su questo telefono, il video va lo stesso, senza effetti.
        programmaComposizione = try {
            Programma(OMBREGGIATORE_VERTICI, FRAMMENTI_COMPOSIZIONE)
        } catch (e: RuntimeException) {
            Log.e(TAG, "Effetti non disponibili su questa GPU", e)
            null
        }
    }

    /** Lo shader degli effetti si è compilato: si possono dichiarare al computer. */
    val effettiDisponibili: Boolean
        get() {
            var esito = false
            eseguiEAspetta {
                if (display == EGL14.EGL_NO_DISPLAY) preparaEgl()
                esito = programmaComposizione != null
            }
            return esito
        }

    private fun creaSuperficie(superficie: Surface): EGLSurface {
        val nuova = EGL14.eglCreateWindowSurface(display, configurazione, superficie, intArrayOf(EGL14.EGL_NONE), 0)
        check(nuova != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface" }
        return nuova
    }

    private fun rilasciaTexture() {
        superficieCamera?.release()
        superficieCamera = null
        superficieTexture?.setOnFrameAvailableListener(null)
        superficieTexture?.release()
        superficieTexture = null
        if (texture != 0) {
            GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
            texture = 0
        }
    }

    private fun disegna(st: SurfaceTexture, inAttesa: AtomicInteger) {
        val arrivati = inAttesa.getAndSet(0)
        if (st !== superficieTexture) return
        if (display == EGL14.EGL_NO_DISPLAY) return
        try {
            EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
            // Ogni updateTexImage prende il fotogramma successivo della coda: con più fotogrammi arrivati si scartano i
            // vecchi e si disegna solo l'ultimo (meno ritardo, nessun accumulo).
            repeat(arrivati.coerceAtLeast(1)) { st.updateTexImage() }
            if (arrivati > 1) fotogrammiSaltati.addAndGet(arrivati - 1)
            st.getTransformMatrix(trasformazione)
            val istante = st.timestamp
            val conCodifica = codifica != EGL14.EGL_NO_SURFACE && !codificaInPausa && rotazioneNota
            val conAnteprima = anteprima != EGL14.EGL_NO_SURFACE && anteprimaAttiva
            if (!anteprimaDelVideo) {
                // Lettore del QR code: la fotocamera dritta sullo schermo, nient'altro.
                if (conAnteprima) {
                    EGL14.eglMakeCurrent(display, anteprima, anteprima, contesto)
                    disegnaFotocamera(larghezzaAnteprima, altezzaAnteprima, rotazioneSchermo, false, capovolgi = false)
                    presenta(anteprima)
                }
                return
            }
            if (!conCodifica && !conAnteprima) return
            val inizio = System.nanoTime()
            val sorgente = preparaVideo(istante)
            if (conCodifica) {
                EGL14.eglMakeCurrent(display, codifica, codifica, contesto)
                copia(sorgente, larghezzaCodifica, altezzaCodifica, 0, riempi = true)
                EGLExt.eglPresentationTimeANDROID(display, codifica, istante)
                EGL14.eglSwapBuffers(display, codifica)
                suFotogramma?.invoke(istante)
                // Il misuratore: il tempo del fotogramma inviato sul thread GL (effetti, copia per l'analisi, consegna).
                tempoDisegno.addAndGet(System.nanoTime() - inizio)
                fotogrammiDisegnati.incrementAndGet()
            }
            if (conAnteprima) {
                EGL14.eglMakeCurrent(display, anteprima, anteprima, contesto)
                val relativa = Math.floorMod(rotazioneSchermo - rotazioneTelefono, 360)
                // Riempie lo schermo come la Fotocamera (si taglia solo a video): al computer va sempre il video intero.
                copia(sorgente, larghezzaAnteprima, altezzaAnteprima, relativa, riempi = true, specchia = specchiaAnteprima)
                presenta(anteprima)
            }
        } catch (e: RuntimeException) {
            Log.w(TAG, "Fotogramma non disegnato", e)
        }
    }

    private fun presenta(superficie: EGLSurface) {
        if (!EGL14.eglSwapBuffers(display, superficie) && superficie == anteprima) {
            // La SurfaceView è sparita prima di avvisare: si smette di disegnarci.
            EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
            EGL14.eglDestroySurface(display, anteprima)
            anteprima = EGL14.EGL_NO_SURFACE
        }
    }

    /** I passaggi 1–3: la texture con il video pronto da inviare. */
    private fun preparaVideo(istante: Long): Int {
        val l = larghezzaVideo
        val a = altezzaVideo
        base.prepara(l, a)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, base.framebuffer)
        disegnaFotocamera(l, a, rotazioneTelefono, specchiaCodifica, capovolgi = false)

        if (analisiRichiesta && !codificaInPausa) mandaAllAnalisi()

        // Inquadratura automatica: la molla va avanti a ogni fotogramma, alla stessa velocità a 24, 30 e 60 fps.
        val dt = if (ultimoIstante != 0L && istante > ultimoIstante) (istante - ultimoIstante) / 1e9f else 1f / 30
        ultimoIstante = istante
        val riquadro = if (inquadratura.attivo) {
            inquadratura.passo(volti, specchiaCodifica, SystemClock.elapsedRealtime(), dt)
        } else {
            Inquadratura.Riquadro()
        }
        val parametri = effetti
        aggiornaLuce(parametri.luceVolto, dt)
        val composizione = programmaComposizione
        val serveComposizione = composizione != null &&
            (parametri.attivi || luceForza > 0.001f || !riquadro.intero || sovrapposteCaricate.isNotEmpty())
        if (!serveComposizione) {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            return base.texture
        }
        finale.prepara(l, a)
        val maschera = mascheraValida && mascheraRotazione == rotazioneTelefono && textureMaschera != 0
        val sfocato = if (parametri.sfondo == ParametriEffetti.Sfondo.SFOCATO && maschera) sfoca(parametri.intensitaSfondo) else 0
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, finale.framebuffer)
        componi(composizione!!, parametri, riquadro, maschera, sfocato, l, a)
        disegnaSovrapposizioni(l, a)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        return finale.texture
    }

    /**
     * Il video di base, piccolo e con le righe dall'alto, all'analisi; al massimo una alla volta. Con lo sfondo acceso
     * a ogni fotogramma (appena l'analisi di prima ha finito): il bordo della persona non resta indietro.
     */
    private fun mandaAllAnalisi() {
        val adesso = SystemClock.elapsedRealtime()
        val intervallo = if (effetti.sfondo != ParametriEffetti.Sfondo.NESSUNO) 0L else intervalloAnalisiMs
        if (adesso - ultimaAnalisi < intervallo) return
        val ricevitore = suAnalisi ?: return
        if (!analisiOccupata.compareAndSet(false, true)) return
        ultimaAnalisi = adesso
        val orizzontale = larghezzaVideo >= altezzaVideo
        val l = if (orizzontale) LATO_ANALISI_LUNGO else LATO_ANALISI_CORTO
        val a = if (orizzontale) LATO_ANALISI_CORTO else LATO_ANALISI_LUNGO
        analisi.prepara(l, a)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, analisi.framebuffer)
        GLES20.glViewport(0, 0, l, a)
        // Capovolta: glReadPixels legge dal basso, così la prima riga letta è quella in alto.
        disegnaTexture(base.texture, identita, mvpCopia(l, a, l, a, 0, capovolgi = true, riempi = true))
        val buffer = bufferAnalisi?.takeIf { it.capacity() == l * a * 4 }
            ?: ByteBuffer.allocateDirect(l * a * 4).order(ByteOrder.nativeOrder()).also { bufferAnalisi = it }
        buffer.rewind()
        GLES20.glReadPixels(0, 0, l, a, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
        val immagine = bitmapAnalisi?.takeIf { it.width == l && it.height == a && !it.isRecycled }
            ?: Bitmap.createBitmap(l, a, Bitmap.Config.ARGB_8888).also { bitmapAnalisi = it }
        buffer.rewind()
        immagine.copyPixelsFromBuffer(buffer)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, base.framebuffer)
        try {
            ricevitore(immagine, specchiaCodifica, rotazioneTelefono)
        } catch (e: RuntimeException) {
            analisiOccupata.set(false)
            Log.w(TAG, "Analisi non partita", e)
        }
    }

    /**
     * «Luce sul volto»: il volto principale degli ultimi volti trovati (stesse coordinate del video di base), levigato;
     * senza volto per più di un secondo (o con la luce spenta) la forza torna piano a zero.
     */
    private fun aggiornaLuce(accesa: Boolean, dt: Float) {
        val trovati = volti
        val volto = if (accesa && trovati != null && SystemClock.elapsedRealtime() - trovati.quando < 1_000) {
            trovati.principale(specchiaCodifica)
        } else {
            null
        }
        val passo = (dt * 6f).coerceIn(0f, 1f)
        if (volto != null && volto.larghezza > 0.02f && volto.altezza > 0.02f) {
            if (luceForza < 0.001f) {
                luceX = volto.centroX
                luceY = volto.centroY
                luceL = volto.larghezza
                luceA = volto.altezza
            } else {
                luceX += (volto.centroX - luceX) * passo
                luceY += (volto.centroY - luceY) * passo
                luceL += (volto.larghezza - luceL) * passo
                luceA += (volto.altezza - luceA) * passo
            }
            luceForza += (1f - luceForza) * (dt * 3f).coerceIn(0f, 1f)
        } else {
            luceForza -= luceForza * (dt * 3f).coerceIn(0f, 1f)
            if (luceForza < 0.001f) luceForza = 0f
        }
    }

    /**
     * Lo sfondo sfocato «senza alone», a risoluzione ridotta: nella riduzione la persona (dalla maschera, un po'
     * allargata) si toglie e la trasparenza dice quanto sfondo c'è; i giri di sfocatura separabile (orizzontale e
     * verticale, passo piccolo: niente immagini doppie) sfocano colore e trasparenza insieme, e la composizione divide
     * l'uno per l'altra. Così attorno alla persona non colano i suoi colori. Raggio dall'intensità con
     * [sigmaSfocatura]; la riduzione (½, ¼, ⅛) secondo il raggio, così anche «Poco» resta fine. Restituisce la texture.
     */
    private fun sfoca(intensita: Float): Int {
        val programma = programmaSfocatura ?: return 0
        val sigma = sigmaSfocatura(intensita, min(larghezzaVideo, altezzaVideo))
        val fattore = riduzioneSfocatura(sigma)
        val l = max(16, larghezzaVideo / fattore)
        val a = max(16, altezzaVideo / fattore)
        ridotto.prepara(l, a)
        ridottoB.prepara(l, a)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, ridotto.framebuffer)
        GLES20.glViewport(0, 0, l, a)
        val riduzione = programmaRiduzione
        if (riduzione != null) {
            riduzione.usa()
            // Quattro letture a un quarto di punto ridotto dal centro: ognuna media 2×2 punti del video (meno sfarfallio).
            GLES20.glUniform2f(riduzione.uniforme("uMezzoPasso"), 0.25f / l, 0.25f / a)
            GLES20.glUniform1f(riduzione.uniforme("uMascheraSpecchiata"), if (mascheraSpecchiata != specchiaCodifica) 1f else 0f)
            legaTexture(riduzione, "sMaschera", 2, textureMaschera)
            disegnaCon(riduzione, GLES20.GL_TEXTURE_2D, base.texture, identita, mvpCopia(l, a, l, a, 0, capovolgi = false, riempi = true))
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        } else {
            disegnaTexture(base.texture, identita, mvpCopia(l, a, l, a, 0, capovolgi = false, riempi = true))
        }
        // Un giro (orizzontale + verticale) sfoca di 1,414 × passo; con n giri √n volte tanto.
        val sigmaRidotto = sigma / fattore
        val giri = ceil((sigmaRidotto / (1.414f * 1.5f)).let { it * it }).toInt().coerceIn(1, 10)
        val passo = (sigmaRidotto / (1.414f * sqrt(giri.toFloat()))).coerceIn(0.35f, 2.5f)
        repeat(giri) {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, ridottoB.framebuffer)
            sfocaPassaggio(programma, ridotto.texture, passo / l, 0f, l, a)
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, ridotto.framebuffer)
            sfocaPassaggio(programma, ridottoB.texture, 0f, passo / a, l, a)
        }
        return ridotto.texture
    }

    private fun sfocaPassaggio(programma: Programma, sorgente: Int, dx: Float, dy: Float, l: Int, a: Int) {
        GLES20.glViewport(0, 0, l, a)
        programma.usa()
        GLES20.glUniform2f(programma.uniforme("uDirezione"), dx, dy)
        disegnaCon(programma, GLES20.GL_TEXTURE_2D, sorgente, identita, mvpCopia(l, a, l, a, 0, capovolgi = false, riempi = true))
    }

    private fun componi(
        programma: Programma, p: ParametriEffetti, riquadro: Inquadratura.Riquadro, maschera: Boolean, sfocato: Int, l: Int, a: Int,
    ) {
        GLES20.glViewport(0, 0, l, a)
        programma.usa()
        // Il ritaglio dell'inquadratura: coordinata del video intero = origine + coordinata d'uscita × scala.
        // In GL l'origine delle texture è in basso: la y del riquadro (origine in alto) si gira.
        val scala = 1f / riquadro.zoom
        val origineX = riquadro.x - scala / 2
        val origineY = (1f - riquadro.y) - scala / 2
        GLES20.glUniform4f(programma.uniforme("uRitaglio"), scala, scala, origineX, origineY)
        // Passo del ritocco e della nitidezza: in proporzione al lato corto (stesso aspetto a 720p e in 4K).
        val proporzione = min(l, a) / 1080f
        GLES20.glUniform2f(programma.uniforme("uPasso"), 1f / l, 1f / a)
        GLES20.glUniform1f(programma.uniforme("uScalaPelle"), 3f * proporzione)
        val modo = when {
            !maschera -> 0f
            p.sfondo == ParametriEffetti.Sfondo.SFOCATO && sfocato != 0 -> 1f
            p.sfondo == ParametriEffetti.Sfondo.SOSTITUITO && textureSfondo != 0 -> 2f
            else -> 0f
        }
        GLES20.glUniform1f(programma.uniforme("uModoSfondo"), modo)
        // Bordo: più netto con l'intensità alta (sostituito), mai a scalini; per lo sfocato un bordo medio. La maschera
        // si legge con la stessa geometria a ogni risoluzione: la sfumatura in pixel cresce con il video.
        val bordo = if (modo == 2f) 0.24f - 0.14f * p.intensitaSfondo.coerceIn(0f, 1f) else 0.2f
        GLES20.glUniform1f(programma.uniforme("uBordo"), bordo)
        GLES20.glUniform2f(programma.uniforme("uTexelMaschera"), 1f / larghezzaMaschera, 1f / altezzaMaschera)
        GLES20.glUniform1f(programma.uniforme("uSfocaturaNormalizzata"), if (programmaRiduzione != null) 1f else 0f)
        GLES20.glUniform1f(programma.uniforme("uMascheraSpecchiata"), if (mascheraSpecchiata != specchiaCodifica) 1f else 0f)
        GLES20.glUniform1f(programma.uniforme("uMascheraValida"), if (maschera) 1f else 0f)
        // Lo sfondo sostituito copre il video senza deformarsi.
        GLES20.glUniform4fv(programma.uniforme("uSfondoRitaglio"), 1, ritaglioCopertura(larghezzaSfondo, altezzaSfondo, l, a), 0)
        GLES20.glUniform1f(programma.uniforme("uPelle"), p.pelle.coerceIn(0f, 1f))
        GLES20.glUniform1f(programma.uniforme("uNitidezza"), p.nitidezza.coerceIn(-1f, 1f))
        GLES20.glUniform3fv(programma.uniforme("uCalore"), 1, guadagniCalore(p.calore), 0)
        val ricetta = p.ricetta
        GLES20.glUniform1f(programma.uniforme("uFiltroAttivo"), if (ricetta != null) 1f else 0f)
        if (ricetta != null) {
            caricaCurva(ricetta)
            GLES20.glUniformMatrix3fv(programma.uniforme("uOmbre"), 1, false, ricetta.ombre, 0)
            GLES20.glUniform3fv(programma.uniforme("uBiasOmbre"), 1, ricetta.biasOmbre, 0)
            GLES20.glUniformMatrix3fv(programma.uniforme("uLuci"), 1, false, ricetta.luci, 0)
            GLES20.glUniform3fv(programma.uniforme("uBiasLuci"), 1, ricetta.biasLuci, 0)
            GLES20.glUniform1f(programma.uniforme("uSaturazioneFiltro"), ricetta.saturazione)
            GLES20.glUniform1f(programma.uniforme("uContrastoFiltro"), ricetta.contrasto)
            GLES20.glUniform1f(programma.uniforme("uVignetta"), ricetta.vignetta)
        }
        GLES20.glUniform1f(programma.uniforme("uLuminosita"), p.luminosita.coerceIn(-1f, 1f))
        GLES20.glUniform1f(programma.uniforme("uContrasto"), p.contrasto.coerceIn(-1f, 1f))
        GLES20.glUniform1f(programma.uniforme("uSaturazione"), p.saturazione.coerceIn(-1f, 1f))
        // Luce sul volto: centro e semiassi dell'ellisse nelle coordinate della texture (y dal basso), un po' più
        // larga del riquadro del volto perché il bordo sfumi fuori dal viso.
        GLES20.glUniform1f(programma.uniforme("uLuce"), LUCE_MASSIMA * luceForza)
        GLES20.glUniform4f(
            programma.uniforme("uVolto"),
            luceX, 1f - luceY, max(0.02f, luceL * 0.75f), max(0.02f, luceA * 0.85f),
        )

        legaTexture(programma, "sSfocato", 1, if (sfocato != 0) sfocato else base.texture)
        legaTexture(programma, "sMaschera", 2, if (textureMaschera != 0) textureMaschera else base.texture)
        legaTexture(programma, "sSfondo", 3, if (textureSfondo != 0) textureSfondo else base.texture)
        legaTexture(programma, "sCurva", 4, if (textureCurva != 0) textureCurva else base.texture)
        disegnaCon(programma, GLES20.GL_TEXTURE_2D, base.texture, identita, mvpCopia(l, a, l, a, 0, capovolgi = false, riempi = true))
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
    }

    private fun legaTexture(programma: Programma, nome: String, unita: Int, id: Int) {
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0 + unita)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
        GLES20.glUniform1i(programma.uniforme(nome), unita)
    }

    private fun caricaCurva(ricetta: RicettaFiltro) {
        if (ricetta === ricettaCaricata && textureCurva != 0) return
        if (textureCurva == 0) textureCurva = nuovaTexture2D()
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureCurva)
        GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 1)
        val tabella = RicetteFiltri.tabella(ricetta.curva)
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_LUMINANCE, 256, 1, 0, GLES20.GL_LUMINANCE, GLES20.GL_UNSIGNED_BYTE, ByteBuffer.wrap(tabella),
        )
        ricettaCaricata = ricetta
    }

    private fun disegnaSovrapposizioni(l: Int, a: Int) {
        val elenco = sovrapposteCaricate
        val programma = programmaCopia ?: return
        if (elenco.isEmpty()) return
        GLES20.glViewport(0, 0, l, a)
        GLES20.glEnable(GLES20.GL_BLEND)
        // Le bitmap di Android sono già moltiplicate per la trasparenza.
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        for ((id, rettangolo) in elenco) {
            // Le bitmap hanno la prima riga in alto (t = 0): le coordinate si capovolgono.
            disegnaCon(programma, GLES20.GL_TEXTURE_2D, id, capovoltaY, mvpRettangolo(rettangolo))
        }
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    /** La fotocamera (texture esterna) ruotata, specchiata e ingrandita fino a riempire `larghezza`×`altezza`. */
    private fun disegnaFotocamera(larghezza: Int, altezza: Int, rotazione: Int, specchia: Boolean, capovolgi: Boolean) {
        val programma = programmaFotocamera ?: return
        if (larghezza <= 0 || altezza <= 0) return
        GLES20.glViewport(0, 0, larghezza, altezza)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        calcolaMvp(mvp, larghezza, altezza, larghezzaNaturale, altezzaNaturale, rotazione, specchia, capovolgi, riempi = true)
        disegnaCon(programma, GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture, trasformazione, mvp)
    }

    /** Una texture del video (2D) su tutta la destinazione, girata di `rotazione`; `riempi` falso = intera con le bande. */
    private fun copia(sorgente: Int, larghezza: Int, altezza: Int, rotazione: Int, riempi: Boolean, specchia: Boolean = false) {
        if (larghezza <= 0 || altezza <= 0) return
        GLES20.glViewport(0, 0, larghezza, altezza)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        disegnaTexture(sorgente, identita, mvpCopia(larghezza, altezza, larghezzaVideo, altezzaVideo, rotazione, capovolgi = false, riempi = riempi, specchia = specchia))
    }

    private fun disegnaTexture(id: Int, matriceTexture: FloatArray, matrice: FloatArray) {
        val programma = programmaCopia ?: return
        disegnaCon(programma, GLES20.GL_TEXTURE_2D, id, matriceTexture, matrice)
    }

    private fun disegnaCon(programma: Programma, bersaglio: Int, id: Int, matriceTexture: FloatArray, matrice: FloatArray) {
        programma.usa()
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(bersaglio, id)
        GLES20.glUniform1i(programma.uniforme("sTexture"), 0)
        GLES20.glUniformMatrix4fv(programma.uniforme("uMvp"), 1, false, matrice, 0)
        GLES20.glUniformMatrix4fv(programma.uniforme("uTex"), 1, false, matriceTexture, 0)
        val posizione = programma.attributo("aPosizione")
        val coordinata = programma.attributo("aCoordinata")
        GLES20.glEnableVertexAttribArray(posizione)
        GLES20.glVertexAttribPointer(posizione, 2, GLES20.GL_FLOAT, false, 8, vertici)
        GLES20.glEnableVertexAttribArray(coordinata)
        GLES20.glVertexAttribPointer(coordinata, 2, GLES20.GL_FLOAT, false, 8, coordinate)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(posizione)
        GLES20.glDisableVertexAttribArray(coordinata)
    }

    private val matriceCopia = FloatArray(16)

    private fun mvpCopia(
        larghezza: Int, altezza: Int, larghezzaSorgente: Int, altezzaSorgente: Int, rotazione: Int, capovolgi: Boolean, riempi: Boolean,
        specchia: Boolean = false,
    ): FloatArray {
        calcolaMvp(matriceCopia, larghezza, altezza, larghezzaSorgente, altezzaSorgente, rotazione, specchia, capovolgi, riempi)
        return matriceCopia
    }

    private val matriceRettangolo = FloatArray(16)

    /** Il quadrato unitario portato su un rettangolo normalizzato (origine in alto) della destinazione. */
    private fun mvpRettangolo(r: RectF): FloatArray {
        matriceRettangolo.fill(0f)
        // x: −1..1 → sinistra..destra in NDC; y: −1..1 → basso..alto (in NDC l'alto è +1, nel rettangolo è 0).
        matriceRettangolo[0] = r.right - r.left
        matriceRettangolo[5] = r.bottom - r.top
        matriceRettangolo[10] = 1f
        matriceRettangolo[12] = r.left + r.right - 1f
        matriceRettangolo[13] = 1f - (r.top + r.bottom)
        matriceRettangolo[15] = 1f
        return matriceRettangolo
    }

    /**
     * MVP = scala in NDC · specchio · rotazione · dimensione della sorgente in pixel (vedi LEGGIMI, «Rotazione»).
     * `riempi`: la sorgente copre tutta la destinazione (quello che esce si taglia, come una webcam); falso = entra
     * intera con le bande. `capovolgi`: sottosopra (per leggere i pixel con le righe dall'alto).
     */
    private fun calcolaMvp(
        destinazione: FloatArray, larghezza: Int, altezza: Int, larghezzaSorgente: Int, altezzaSorgente: Int,
        rotazione: Int, specchia: Boolean, capovolgi: Boolean, riempi: Boolean,
    ) {
        val gradi = Math.floorMod(rotazione, 360)
        val girata = gradi % 180 == 90
        val larghezzaGirata = (if (girata) altezzaSorgente else larghezzaSorgente).coerceAtLeast(1)
        val altezzaGirata = (if (girata) larghezzaSorgente else altezzaSorgente).coerceAtLeast(1)
        val sx0 = larghezza.toFloat() / larghezzaGirata
        val sy0 = altezza.toFloat() / altezzaGirata
        val scala = if (riempi) max(sx0, sy0) else min(sx0, sy0)
        val mezzaLarghezza = larghezzaSorgente * scala / 2f
        val mezzaAltezza = altezzaSorgente * scala / 2f
        val (coseno, seno) = when (gradi) {
            90 -> 0f to 1f
            180 -> -1f to 0f
            270 -> 0f to -1f
            else -> 1f to 0f
        }
        // Rotazione oraria con l'asse y verso l'alto: x' = x·cos + y·sin, y' = −x·sin + y·cos.
        val a00 = coseno * mezzaLarghezza
        val a01 = seno * mezzaAltezza
        val a10 = -seno * mezzaLarghezza
        val a11 = coseno * mezzaAltezza
        val sx = 2f / larghezza * (if (specchia) -1f else 1f)
        val sy = 2f / altezza * (if (capovolgi) -1f else 1f)
        destinazione.fill(0f)
        // Colonne (OpenGL): m[0], m[1] prima colonna; m[4], m[5] seconda.
        destinazione[0] = sx * a00
        destinazione[1] = sy * a10
        destinazione[4] = sx * a01
        destinazione[5] = sy * a11
        destinazione[10] = 1f
        destinazione[15] = 1f
    }

    private fun parametriTexture(bersaglio: Int) {
        GLES20.glTexParameteri(bersaglio, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(bersaglio, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(bersaglio, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(bersaglio, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    }

    private fun nuovaTexture2D(): Int {
        val id = IntArray(1).also { GLES20.glGenTextures(1, it, 0) }[0]
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
        parametriTexture(GLES20.GL_TEXTURE_2D)
        return id
    }

    /** Una texture con il suo framebuffer, ricreata quando cambia la misura. */
    private inner class Bersaglio {
        var texture = 0
            private set
        var framebuffer = 0
            private set
        private var larghezza = 0
        private var altezza = 0

        fun prepara(l: Int, a: Int) {
            if (texture != 0 && l == larghezza && a == altezza) return
            rilascia()
            texture = nuovaTexture2D()
            GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, l, a, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null)
            framebuffer = IntArray(1).also { GLES20.glGenFramebuffers(1, it, 0) }[0]
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebuffer)
            GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0, GLES20.GL_TEXTURE_2D, texture, 0)
            val stato = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            check(stato == GLES20.GL_FRAMEBUFFER_COMPLETE) { "Framebuffer incompleto ($stato) a ${l}×$a" }
            larghezza = l
            altezza = a
        }

        fun rilascia() {
            if (framebuffer != 0) GLES20.glDeleteFramebuffers(1, intArrayOf(framebuffer), 0)
            if (texture != 0) GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
            framebuffer = 0
            texture = 0
            larghezza = 0
            altezza = 0
        }
    }

    /** Un programma OpenGL con le posizioni di uniformi e attributi già cercate. */
    private class Programma(vertici: String, frammenti: String) {
        val id: Int
        private val posizioni = HashMap<String, Int>()

        init {
            val v = compila(GLES20.GL_VERTEX_SHADER, vertici)
            val f = compila(GLES20.GL_FRAGMENT_SHADER, frammenti)
            id = GLES20.glCreateProgram()
            GLES20.glAttachShader(id, v)
            GLES20.glAttachShader(id, f)
            GLES20.glLinkProgram(id)
            val esito = IntArray(1)
            GLES20.glGetProgramiv(id, GLES20.GL_LINK_STATUS, esito, 0)
            check(esito[0] == GLES20.GL_TRUE) { "Programma OpenGL: ${GLES20.glGetProgramInfoLog(id)}" }
        }

        fun usa() = GLES20.glUseProgram(id)
        fun uniforme(nome: String): Int = posizioni.getOrPut("u:$nome") { GLES20.glGetUniformLocation(id, nome) }
        fun attributo(nome: String): Int = posizioni.getOrPut("a:$nome") { GLES20.glGetAttribLocation(id, nome) }

        private fun compila(tipo: Int, sorgente: String): Int {
            val ombreggiatore = GLES20.glCreateShader(tipo)
            GLES20.glShaderSource(ombreggiatore, sorgente)
            GLES20.glCompileShader(ombreggiatore)
            val esito = IntArray(1)
            GLES20.glGetShaderiv(ombreggiatore, GLES20.GL_COMPILE_STATUS, esito, 0)
            check(esito[0] == GLES20.GL_TRUE) { "Shader OpenGL: ${GLES20.glGetShaderInfoLog(ombreggiatore)}" }
            return ombreggiatore
        }
    }

    private fun eseguiEAspetta(azione: () -> Unit) {
        if (Thread.currentThread() == thread) {
            azione()
            return
        }
        val fatto = CountDownLatch(1)
        val inviato = gestore.post {
            try { azione() } catch (e: RuntimeException) { Log.w(TAG, "Operazione OpenGL non riuscita", e) } finally { fatto.countDown() }
        }
        if (inviato) fatto.await(3, TimeUnit.SECONDS)
    }

    companion object {
        private const val TAG = "WebcamLR"
        private const val EGL_RECORDABLE_ANDROID = 0x3142

        /** L'immagine per l'analisi: 384×216 (o 216×384 in verticale), abbastanza per volti e maschera. */
        const val LATO_ANALISI_LUNGO = 384
        const val LATO_ANALISI_CORTO = 216

        /** Quanto schiarisce la luce sul volto al centro del viso: esponente 1 − 0,35 (0,5 → 0,64, ben visibile). */
        private const val LUCE_MASSIMA = 0.35f

        /**
         * C: la sfocatura dello sfondo (deviazione standard in pixel del video) dall'intensità del `comando`. A 1080p:
         * 0,25 «Poco» → 3,5 (si riconosce ancora lo sfondo), 0,55 «Medio» → 12, 1 «Tanto» → 30; in mezzo lineare a
         * tratti, in proporzione al lato corto per le altre risoluzioni.
         */
        fun sigmaSfocatura(intensita: Float, latoCorto: Int): Float {
            val i = if (intensita.isNaN()) 0.5f else intensita.coerceIn(0f, 1f)
            val a1080 = when {
                i <= 0.25f -> 2f + 1.5f * (i / 0.25f)
                i <= 0.55f -> 3.5f + 8.5f * ((i - 0.25f) / 0.3f)
                else -> 12f + 18f * ((i - 0.55f) / 0.45f)
            }
            return a1080 * max(latoCorto, 1) / 1080f
        }

        /** Di quanto ridurre il video prima di sfocarlo: abbastanza per pochi giri, non tanto da perdere i dettagli fini. */
        fun riduzioneSfocatura(sigma: Float): Int = when {
            sigma <= 8f -> 2
            sigma <= 32f -> 4
            else -> 8
        }

        /**
         * Come coprire una destinazione `l`×`a` con un'immagine `li`×`ai` senza deformarla: scala e origine delle
         * coordinate dell'immagine (uv = origine + uv destinazione × scala), centrate.
         */
        /**
         * La matrice del calore (diagonale, sui valori del video): a 1 porta il bianco del video da 6500 K a circa 6050 K
         * lungo la curva della luce del giorno (+450 K di correzione, tinta neutra: il verde quasi non si muove),
         * con la stessa luminanza; nessuna saturazione in più. Da 0 a 1 si va in proporzione; 0 = identità.
         */
        fun guadagniCalore(calore: Float): FloatArray {
            val k = if (calore.isFinite()) calore.coerceIn(0f, 1f) else 0f
            return floatArrayOf(1f + (CALORE_ROSSO - 1f) * k, 1f + (CALORE_VERDE - 1f) * k, 1f + (CALORE_BLU - 1f) * k)
        }

        // Rapporto tra i bianchi a 6050 K e a 6500 K (luce del giorno CIE, sRGB lineare, luminanza uguale), elevato a 1/2,2
        // perché il video è già con la gamma.
        private const val CALORE_ROSSO = 1.0187f
        private const val CALORE_VERDE = 0.9978f
        private const val CALORE_BLU = 0.9651f

        fun ritaglioCopertura(li: Int, ai: Int, l: Int, a: Int): FloatArray {
            if (li <= 0 || ai <= 0 || l <= 0 || a <= 0) return floatArrayOf(1f, 1f, 0f, 0f)
            val proporzioneImmagine = li.toFloat() / ai
            val proporzione = l.toFloat() / a
            return if (proporzioneImmagine > proporzione) {
                val sx = proporzione / proporzioneImmagine
                floatArrayOf(sx, 1f, (1f - sx) / 2, 0f)
            } else {
                val sy = proporzioneImmagine / proporzione
                floatArrayOf(1f, sy, 0f, (1f - sy) / 2)
            }
        }

        private const val OMBREGGIATORE_VERTICI = """
            uniform mat4 uMvp;
            uniform mat4 uTex;
            attribute vec4 aPosizione;
            attribute vec4 aCoordinata;
            varying vec2 vCoordinata;
            void main() {
                gl_Position = uMvp * aPosizione;
                vCoordinata = (uTex * aCoordinata).xy;
            }
        """

        private const val FRAMMENTI_FOTOCAMERA = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vCoordinata;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vCoordinata);
            }
        """

        private const val FRAMMENTI_COPIA = """
            precision mediump float;
            varying vec2 vCoordinata;
            uniform sampler2D sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vCoordinata);
            }
        """

        /**
         * Sfocatura gaussiana a 9 punti in 5 letture (interpolazione lineare tra coppie di punti), anche della
         * trasparenza: lì c'è quanto sfondo c'era (vedi [FRAMMENTI_RIDUZIONE]).
         */
        private const val FRAMMENTI_SFOCATURA = """
            precision mediump float;
            varying vec2 vCoordinata;
            uniform sampler2D sTexture;
            uniform vec2 uDirezione;
            void main() {
                vec4 s = texture2D(sTexture, vCoordinata) * 0.2270270270;
                vec2 d1 = uDirezione * 1.3846153846;
                vec2 d2 = uDirezione * 3.2307692308;
                s += (texture2D(sTexture, vCoordinata + d1) + texture2D(sTexture, vCoordinata - d1)) * 0.3162162162;
                s += (texture2D(sTexture, vCoordinata + d2) + texture2D(sTexture, vCoordinata - d2)) * 0.0702702703;
                gl_FragColor = s;
            }
        """

        /**
         * La riduzione per lo sfondo sfocato senza alone: il video (4 letture) moltiplicato per «quanto è sfondo»
         * (1 − persona, con la persona un po' allargata così i suoi bordi non entrano), e quel valore nella trasparenza.
         */
        private const val FRAMMENTI_RIDUZIONE = """
            #ifdef GL_FRAGMENT_PRECISION_HIGH
            precision highp float;
            #else
            precision mediump float;
            #endif
            varying vec2 vCoordinata;
            uniform sampler2D sTexture;
            uniform sampler2D sMaschera;
            uniform vec2 uMezzoPasso;
            uniform float uMascheraSpecchiata;
            void main() {
                vec2 d = uMezzoPasso;
                vec3 c = (texture2D(sTexture, vCoordinata + vec2(-d.x, -d.y)).rgb + texture2D(sTexture, vCoordinata + vec2(d.x, -d.y)).rgb
                    + texture2D(sTexture, vCoordinata + vec2(-d.x, d.y)).rgb + texture2D(sTexture, vCoordinata + vec2(d.x, d.y)).rgb) * 0.25;
                vec2 m = vec2(mix(vCoordinata.x, 1.0 - vCoordinata.x, uMascheraSpecchiata), 1.0 - vCoordinata.y);
                float fondo = 1.0 - smoothstep(0.2, 0.45, texture2D(sMaschera, m).r);
                gl_FragColor = vec4(c * fondo, fondo);
            }
        """

        /**
         * Tutti gli effetti in un passaggio: ritaglio dell'inquadratura, nitidezza, ritocco della pelle (media pesata
         * dei vicini simili, solo sui toni della pelle e sulla persona), sfondo (sfocato o immagine) con la maschera,
         * filtro (due matrici mescolate con la luminanza, saturazione, contrasto, curva, vignettatura) e regolazioni.
         * Luce sul volto (`uLuce`, `uVolto`): mezzitoni e ombre del viso si alzano con una curva di potenza (i bianchi
         * restano bianchi, i neri neri) in un'ellisse dal bordo molto morbido; prima dello sfondo, così con la
         * sfocatura la parte dell'ellisse che cade sullo sfondo torna sfocata e non illuminata.
         * Calore (`uCalore`): una matrice diagonale sul colore, per tutta l'immagine (anche lo sfondo sfocato, che viene
         * dalla fotocamera; non l'immagine dello sfondo sostituito). Sta dopo nitidezza e ritocco perché è lineare e loro
         * sono medie e differenze di vicini: il risultato è lo stesso che applicarla per prima, senza correggere ogni
         * vicino, e il riconoscimento dei toni della pelle resta sui colori della fotocamera. Con 0 è l'identità.
         * Coordinate in alta precisione dove c'è: in 4K la media precisione sposterebbe i punti di qualche pixel.
         *
         * La maschera (`personaMorbida`) si ingrandisce in modo morbido: quattro letture bilineari a 3/4 di punto dal
         * centro (un filtro a tenda), così il contorno non va a scalini anche se la maschera è molto più piccola del
         * video; poi una soglia morbida (smoothstep) un po' sotto la metà, così capelli e bordi incerti restano della
         * persona. Sfondo sfocato senza alone: il colore sfocato diviso per quanto sfondo c'era (la trasparenza di
         * [FRAMMENTI_RIDUZIONE]); dove non ce n'era (dentro la persona, dove comunque non si vede) resta il video.
         */
        private const val FRAMMENTI_COMPOSIZIONE = """
            #ifdef GL_FRAGMENT_PRECISION_HIGH
            precision highp float;
            #else
            precision mediump float;
            #endif
            varying vec2 vCoordinata;
            uniform sampler2D sTexture;
            uniform sampler2D sSfocato;
            uniform sampler2D sMaschera;
            uniform sampler2D sSfondo;
            uniform sampler2D sCurva;
            uniform vec4 uRitaglio;
            uniform vec2 uPasso;
            uniform float uScalaPelle;
            uniform float uModoSfondo;
            uniform float uBordo;
            uniform vec2 uTexelMaschera;
            uniform float uSfocaturaNormalizzata;
            uniform float uMascheraSpecchiata;
            uniform float uMascheraValida;
            uniform vec4 uSfondoRitaglio;
            uniform float uPelle;
            uniform float uNitidezza;
            uniform vec3 uCalore;
            uniform float uFiltroAttivo;
            uniform mat3 uOmbre;
            uniform vec3 uBiasOmbre;
            uniform mat3 uLuci;
            uniform vec3 uBiasLuci;
            uniform float uSaturazioneFiltro;
            uniform float uContrastoFiltro;
            uniform float uVignetta;
            uniform float uLuminosita;
            uniform float uContrasto;
            uniform float uSaturazione;
            uniform float uLuce;
            uniform vec4 uVolto;

            float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

            float persona(vec2 uv) {
                vec2 m = vec2(mix(uv.x, 1.0 - uv.x, uMascheraSpecchiata), 1.0 - uv.y);
                return texture2D(sMaschera, m).r;
            }

            float personaMorbida(vec2 uv) {
                vec2 m = vec2(mix(uv.x, 1.0 - uv.x, uMascheraSpecchiata), 1.0 - uv.y);
                vec2 d = uTexelMaschera * 0.75;
                return (texture2D(sMaschera, m + vec2(-d.x, -d.y)).r + texture2D(sMaschera, m + vec2(d.x, -d.y)).r
                    + texture2D(sMaschera, m + vec2(-d.x, d.y)).r + texture2D(sMaschera, m + vec2(d.x, d.y)).r) * 0.25;
            }

            void main() {
                vec2 uv = uRitaglio.zw + vCoordinata * uRitaglio.xy;
                vec3 c = texture2D(sTexture, uv).rgb;

                if (uNitidezza != 0.0) {
                    vec3 vicini = texture2D(sTexture, uv + vec2(uPasso.x, 0.0)).rgb + texture2D(sTexture, uv - vec2(uPasso.x, 0.0)).rgb
                        + texture2D(sTexture, uv + vec2(0.0, uPasso.y)).rgb + texture2D(sTexture, uv - vec2(0.0, uPasso.y)).rgb;
                    vicini *= 0.25;
                    float forza = uNitidezza > 0.0 ? uNitidezza * 1.5 : uNitidezza * 0.9;
                    c = clamp(c + (c - vicini) * forza, 0.0, 1.0);
                }

                if (uPelle > 0.0) {
                    float y = luma(c);
                    float cb = (c.b - y) * 0.564 + 0.5;
                    float cr = (c.r - y) * 0.713 + 0.5;
                    float tono = smoothstep(0.26, 0.31, cb) * (1.0 - smoothstep(0.49, 0.53, cb))
                        * smoothstep(0.51, 0.55, cr) * (1.0 - smoothstep(0.67, 0.71, cr));
                    if (uMascheraValida > 0.5) tono *= smoothstep(0.3, 0.6, persona(uv));
                    if (tono > 0.01) {
                        vec3 somma = c;
                        float pesi = 1.0;
                        for (int i = 0; i < 8; i++) {
                            float angolo = float(i) * 0.7853982;
                            vec2 spostamento = vec2(cos(angolo), sin(angolo)) * uPasso * uScalaPelle;
                            vec3 v1 = texture2D(sTexture, uv + spostamento).rgb;
                            vec3 v2 = texture2D(sTexture, uv + spostamento * 2.0).rgb;
                            float p1 = 1.0 - smoothstep(0.0, 0.10, distance(v1, c));
                            float p2 = 1.0 - smoothstep(0.0, 0.10, distance(v2, c));
                            somma += v1 * p1 + v2 * p2;
                            pesi += p1 + p2;
                        }
                        c = mix(c, somma / pesi, uPelle * tono * 0.85);
                    }
                }

                c *= uCalore;

                if (uLuce > 0.0) {
                    float d = length((uv - uVolto.xy) / uVolto.zw);
                    float k = uLuce * (1.0 - smoothstep(0.55, 1.3, d));
                    if (k > 0.001) c = pow(max(c, vec3(0.0)), vec3(1.0 - k));
                }

                if (uModoSfondo > 0.5 && uMascheraValida > 0.5) {
                    float p = smoothstep(0.44 - uBordo, 0.44 + uBordo, personaMorbida(uv));
                    vec3 dietro;
                    if (uModoSfondo < 1.5) {
                        vec4 s = texture2D(sSfocato, uv);
                        vec3 normalizzato = s.rgb / max(s.a, 0.004);
                        dietro = uSfocaturaNormalizzata > 0.5 ? mix(c, normalizzato * uCalore, smoothstep(0.004, 0.03, s.a)) : s.rgb * uCalore;
                    } else {
                        dietro = texture2D(sSfondo, vec2(uSfondoRitaglio.z + vCoordinata.x * uSfondoRitaglio.x,
                                                         uSfondoRitaglio.w + (1.0 - vCoordinata.y) * uSfondoRitaglio.y)).rgb;
                    }
                    c = mix(dietro, c, p);
                }

                if (uFiltroAttivo > 0.5) {
                    float l = luma(c);
                    c = mix(uOmbre * c + uBiasOmbre, uLuci * c + uBiasLuci, l);
                    float l2 = luma(c);
                    c = mix(vec3(l2), c, uSaturazioneFiltro);
                    c = clamp((c - 0.5) * uContrastoFiltro + 0.5, 0.0, 1.0);
                    c = vec3(texture2D(sCurva, vec2(c.r * 0.99609375 + 0.001953125, 0.5)).r,
                             texture2D(sCurva, vec2(c.g * 0.99609375 + 0.001953125, 0.5)).r,
                             texture2D(sCurva, vec2(c.b * 0.99609375 + 0.001953125, 0.5)).r);
                    if (uVignetta > 0.0) {
                        float d = length(vCoordinata - 0.5) * 1.414;
                        c *= 1.0 - uVignetta * smoothstep(0.45, 1.0, d);
                    }
                }

                c += uLuminosita * 0.15;
                c = (c - 0.5) * (1.0 + uContrasto * 0.5) + 0.5;
                c = mix(vec3(luma(c)), c, 1.0 + uSaturazione);
                gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
            }
        """

        private fun buffer(valori: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(valori.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
                put(valori)
                position(0)
            }
    }
}
