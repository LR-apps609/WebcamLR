package it.lrapps.webcamlr.android.video

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.max

/**
 * Dalla fotocamera al codificatore e all'anteprima, con OpenGL ES 2 su un thread suo.
 *
 * La fotocamera scrive in una SurfaceTexture; a ogni fotogramma lo si disegna sulla superficie del codificatore
 * (sempre in orizzontale, dritto rispetto a come è tenuto il telefono, specchiato se serve) e sull'anteprima
 * dello schermo (dritta rispetto allo schermo). Così rotazione e specchio non costano nulla al processore
 * e il fotogramma va al codificatore hardware senza copie.
 *
 * Convenzioni: la matrice della SurfaceTexture porta l'immagine dritta nell'orientamento naturale del telefono
 * (in verticale, già specchiata per la fotocamera frontale, come la mostra Android); le rotazioni sono in gradi
 * in senso orario.
 */
class Renderizzatore {
    private val thread = HandlerThread("webcamlr-gl").apply { start() }
    private val gestore = Handler(thread.looper)

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var contesto: EGLContext = EGL14.EGL_NO_CONTEXT
    private var configurazione: EGLConfig? = null
    private var superficieVuota: EGLSurface = EGL14.EGL_NO_SURFACE

    private var programma = 0
    private var posizioneMvp = 0
    private var posizioneTex = 0
    private var posizioneVertici = 0
    private var posizioneCoordinate = 0
    private var texture = 0
    private var superficieTexture: SurfaceTexture? = null
    private var superficieCamera: Surface? = null

    private var codifica: EGLSurface = EGL14.EGL_NO_SURFACE
    private var larghezzaCodifica = 0
    private var altezzaCodifica = 0
    private var anteprima: EGLSurface = EGL14.EGL_NO_SURFACE
    private var larghezzaAnteprima = 0
    private var altezzaAnteprima = 0

    /** Dimensioni dell'immagine nell'orientamento naturale del telefono (in verticale sui telefoni). */
    private var larghezzaNaturale = 1080
    private var altezzaNaturale = 1920

    /** Come è girato il telefono (0, 90, 180, 270 in senso orario): decide il verso del video inviato. */
    @Volatile var rotazioneTelefono = 90

    /** Di quanto è girato lo schermo rispetto all'orientamento naturale: decide il verso dell'anteprima. */
    @Volatile var rotazioneSchermo = 0

    /** Specchia il video inviato (per la frontale si toglie lo specchio di Android, salvo «Specchia»). */
    @Volatile var specchiaCodifica = false

    /** Falso a schermo oscurato: niente disegno dell'anteprima, meno consumo. */
    @Volatile var anteprimaAttiva = true

    /** Il timestamp (ns, orologio della fotocamera) dell'ultimo fotogramma disegnato sul codificatore. */
    @Volatile var suFotogramma: ((Long) -> Unit)? = null

    private val trasformazione = FloatArray(16)
    private val mvp = FloatArray(16)
    private val vertici: FloatBuffer = buffer(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val coordinate: FloatBuffer = buffer(floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f))

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
                val nuovaTexture = IntArray(1).also { GLES20.glGenTextures(1, it, 0) }[0]
                GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, nuovaTexture)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
                texture = nuovaTexture
                val st = SurfaceTexture(nuovaTexture)
                st.setDefaultBufferSize(larghezza, altezza)
                st.setOnFrameAvailableListener({ disegna() }, gestore)
                superficieTexture = st
                risultato = Surface(st).also { superficieCamera = it }
            } catch (e: Throwable) {
                errore = e
            }
        }
        errore?.let { throw IllegalStateException("OpenGL non disponibile", it) }
        return risultato ?: throw IllegalStateException("OpenGL non disponibile")
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
            larghezzaAnteprima = larghezza
            altezzaAnteprima = altezza
        }
    }

    fun ferma() {
        eseguiEAspetta {
            rilasciaTexture()
            if (display != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                if (codifica != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, codifica)
                if (anteprima != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, anteprima)
                if (superficieVuota != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, superficieVuota)
                EGL14.eglDestroyContext(display, contesto)
                EGL14.eglReleaseThread()
                EGL14.eglTerminate(display)
            }
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
        programma = creaProgramma()
        posizioneMvp = GLES20.glGetUniformLocation(programma, "uMvp")
        posizioneTex = GLES20.glGetUniformLocation(programma, "uTex")
        posizioneVertici = GLES20.glGetAttribLocation(programma, "aPosizione")
        posizioneCoordinate = GLES20.glGetAttribLocation(programma, "aCoordinata")
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

    private fun disegna() {
        val st = superficieTexture ?: return
        if (display == EGL14.EGL_NO_DISPLAY) return
        try {
            EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
            st.updateTexImage()
            st.getTransformMatrix(trasformazione)
            val istante = st.timestamp

            if (codifica != EGL14.EGL_NO_SURFACE) {
                EGL14.eglMakeCurrent(display, codifica, codifica, contesto)
                disegnaSu(larghezzaCodifica, altezzaCodifica, rotazioneTelefono, specchiaCodifica)
                EGLExt.eglPresentationTimeANDROID(display, codifica, istante)
                EGL14.eglSwapBuffers(display, codifica)
                suFotogramma?.invoke(istante)
            }
            if (anteprima != EGL14.EGL_NO_SURFACE && anteprimaAttiva) {
                EGL14.eglMakeCurrent(display, anteprima, anteprima, contesto)
                disegnaSu(larghezzaAnteprima, altezzaAnteprima, rotazioneSchermo, false)
                if (!EGL14.eglSwapBuffers(display, anteprima)) {
                    // La SurfaceView è sparita prima di avvisare: si smette di disegnarci.
                    EGL14.eglMakeCurrent(display, superficieVuota, superficieVuota, contesto)
                    EGL14.eglDestroySurface(display, anteprima)
                    anteprima = EGL14.EGL_NO_SURFACE
                }
            }
        } catch (e: RuntimeException) {
            Log.w("WebcamLR", "Fotogramma non disegnato", e)
        }
    }

    /**
     * L'immagine ruotata di `rotazione` gradi in senso orario e ingrandita fino a riempire `larghezza`×`altezza`
     * (quello che esce si taglia, come una webcam), specchiata in orizzontale se richiesto.
     */
    private fun disegnaSu(larghezza: Int, altezza: Int, rotazione: Int, specchia: Boolean) {
        if (larghezza <= 0 || altezza <= 0) return
        GLES20.glViewport(0, 0, larghezza, altezza)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        calcolaMvp(larghezza, altezza, rotazione, specchia)
        GLES20.glUseProgram(programma)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glUniformMatrix4fv(posizioneMvp, 1, false, mvp, 0)
        GLES20.glUniformMatrix4fv(posizioneTex, 1, false, trasformazione, 0)
        GLES20.glEnableVertexAttribArray(posizioneVertici)
        GLES20.glVertexAttribPointer(posizioneVertici, 2, GLES20.GL_FLOAT, false, 8, vertici)
        GLES20.glEnableVertexAttribArray(posizioneCoordinate)
        GLES20.glVertexAttribPointer(posizioneCoordinate, 2, GLES20.GL_FLOAT, false, 8, coordinate)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(posizioneVertici)
        GLES20.glDisableVertexAttribArray(posizioneCoordinate)
    }

    /** MVP = scala in NDC · specchio · rotazione · dimensione dell'immagine in pixel (vedi LEGGIMI, «Rotazione»). */
    private fun calcolaMvp(larghezza: Int, altezza: Int, rotazione: Int, specchia: Boolean) {
        val gradi = ((rotazione % 360) + 360) % 360
        val girata = gradi % 180 == 90
        val larghezzaGirata = if (girata) altezzaNaturale else larghezzaNaturale
        val altezzaGirata = if (girata) larghezzaNaturale else altezzaNaturale
        val scala = max(larghezza.toFloat() / larghezzaGirata, altezza.toFloat() / altezzaGirata)
        val mezzaLarghezza = larghezzaNaturale * scala / 2f
        val mezzaAltezza = altezzaNaturale * scala / 2f
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
        val specchio = if (specchia) -1f else 1f
        val sx = 2f / larghezza * specchio
        val sy = 2f / altezza
        mvp.fill(0f)
        // Colonne (OpenGL): m[0], m[1] prima colonna; m[4], m[5] seconda.
        mvp[0] = sx * a00
        mvp[1] = sy * a10
        mvp[4] = sx * a01
        mvp[5] = sy * a11
        mvp[10] = 1f
        mvp[15] = 1f
    }

    private fun creaProgramma(): Int {
        val vertice = compila(GLES20.GL_VERTEX_SHADER, OMBREGGIATORE_VERTICI)
        val frammento = compila(GLES20.GL_FRAGMENT_SHADER, OMBREGGIATORE_FRAMMENTI)
        val programma = GLES20.glCreateProgram()
        GLES20.glAttachShader(programma, vertice)
        GLES20.glAttachShader(programma, frammento)
        GLES20.glLinkProgram(programma)
        val esito = IntArray(1)
        GLES20.glGetProgramiv(programma, GLES20.GL_LINK_STATUS, esito, 0)
        check(esito[0] == GLES20.GL_TRUE) { "Programma OpenGL: ${GLES20.glGetProgramInfoLog(programma)}" }
        return programma
    }

    private fun compila(tipo: Int, sorgente: String): Int {
        val ombreggiatore = GLES20.glCreateShader(tipo)
        GLES20.glShaderSource(ombreggiatore, sorgente)
        GLES20.glCompileShader(ombreggiatore)
        val esito = IntArray(1)
        GLES20.glGetShaderiv(ombreggiatore, GLES20.GL_COMPILE_STATUS, esito, 0)
        check(esito[0] == GLES20.GL_TRUE) { "Shader OpenGL: ${GLES20.glGetShaderInfoLog(ombreggiatore)}" }
        return ombreggiatore
    }

    private fun eseguiEAspetta(azione: () -> Unit) {
        if (Thread.currentThread() == thread) {
            azione()
            return
        }
        val fatto = CountDownLatch(1)
        val inviato = gestore.post {
            try { azione() } finally { fatto.countDown() }
        }
        if (inviato) fatto.await(3, TimeUnit.SECONDS)
    }

    companion object {
        private const val EGL_RECORDABLE_ANDROID = 0x3142

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

        private const val OMBREGGIATORE_FRAMMENTI = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vCoordinata;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vCoordinata);
            }
        """

        private fun buffer(valori: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(valori.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
                put(valori)
                position(0)
            }
    }
}
