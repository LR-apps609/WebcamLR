package it.lrapps.webcamlr.android.video

import kotlin.math.max

/**
 * Come un punto della fotocamera finisce nel video inviato, e ritorno (P24). Serve a portare i volti trovati da
 * Camera2 (coordinate del sensore) nel video, dove li usano inquadratura, ritocco e postura, e a riportare un volto
 * del video sul sensore per la luce sul volto.
 *
 * Convenzioni (le stesse del [Renderizzatore] e di `SessioneTelefono.puntoSulSensore`): punti normalizzati 0–1 con
 * l'origine in alto a sinistra; ruotare l'immagine di 90° in senso orario porta (x, y) in (1 − y, x); la matrice della
 * SurfaceTexture porta il fotogramma dritto nell'orientamento naturale del telefono, già specchiato per la frontale;
 * il video inviato è quello naturale ruotato di `rotazioneTelefono` in senso orario, ingrandito fino a riempire il
 * formato del video (quello che esce si taglia) e specchiato se `specchia`.
 */
data class ParametriGeometria(
    /** Il fotogramma della fotocamera (SurfaceTexture), come lo dà Camera2, nell'orientamento del sensore. */
    val larghezzaFotocamera: Int,
    val altezzaFotocamera: Int,
    val orientamentoSensore: Int,
    val frontale: Boolean,
    val rotazioneTelefono: Int,
    val specchia: Boolean,
    val larghezzaVideo: Int,
    val altezzaVideo: Int,
)

object Geometria {
    /** Ruota un punto dell'immagine di `gradi` (multipli di 90) in senso orario. */
    fun orario(x: Float, y: Float, gradi: Int): Pair<Float, Float> {
        var px = x
        var py = y
        repeat(Math.floorMod(gradi, 360) / 90) {
            val nx = 1f - py
            val ny = px
            px = nx
            py = ny
        }
        return px to py
    }

    fun antiorario(x: Float, y: Float, gradi: Int): Pair<Float, Float> = orario(x, y, 360 - Math.floorMod(gradi, 360))

    /** Di quanto il fotogramma ruotato va ingrandito in x e in y (≥ 1) per riempire il video. */
    private fun ingrandimento(p: ParametriGeometria): Pair<Float, Float> {
        val giratoSensore = Math.floorMod(p.orientamentoSensore, 180) == 90
        val larghezzaNaturale = if (giratoSensore) p.altezzaFotocamera else p.larghezzaFotocamera
        val altezzaNaturale = if (giratoSensore) p.larghezzaFotocamera else p.altezzaFotocamera
        val giratoVideo = Math.floorMod(p.rotazioneTelefono, 180) == 90
        val larghezzaRuotata = (if (giratoVideo) altezzaNaturale else larghezzaNaturale).toFloat().coerceAtLeast(1f)
        val altezzaRuotata = (if (giratoVideo) larghezzaNaturale else altezzaNaturale).toFloat().coerceAtLeast(1f)
        val video = p.larghezzaVideo.toFloat().coerceAtLeast(1f) to p.altezzaVideo.toFloat().coerceAtLeast(1f)
        val scala = max(video.first / larghezzaRuotata, video.second / altezzaRuotata)
        return (larghezzaRuotata * scala / video.first) to (altezzaRuotata * scala / video.second)
    }

    /** Dal fotogramma della fotocamera (normalizzato, orientamento del sensore) al video inviato. */
    fun fotocameraAlVideo(x: Float, y: Float, p: ParametriGeometria): Pair<Float, Float> {
        var (px, py) = orario(x, y, p.orientamentoSensore)
        if (p.frontale) px = 1f - px
        val (rx, ry) = orario(px, py, p.rotazioneTelefono)
        val (kx, ky) = ingrandimento(p)
        var vx = (rx - 0.5f) * kx + 0.5f
        val vy = (ry - 0.5f) * ky + 0.5f
        if (p.specchia) vx = 1f - vx
        return vx to vy
    }

    /** Dal video inviato al fotogramma della fotocamera: il contrario di [fotocameraAlVideo]. */
    fun videoAllaFotocamera(x: Float, y: Float, p: ParametriGeometria): Pair<Float, Float> {
        var vx = x
        if (p.specchia) vx = 1f - vx
        val (kx, ky) = ingrandimento(p)
        val rx = (vx - 0.5f) / kx + 0.5f
        val ry = (y - 0.5f) / ky + 0.5f
        var (px, py) = antiorario(rx, ry, p.rotazioneTelefono)
        if (p.frontale) px = 1f - px
        return antiorario(px, py, p.orientamentoSensore)
    }

    /**
     * Dove sta il video dentro la vista dell'anteprima (in pixel della vista: sinistra, alto, destra, basso), girato di
     * `rotazione` gradi in senso orario (quella del Renderizzatore: schermo − telefono). `riempi` falso: intero, con le
     * bande; vero: ingrandito fino a coprire la vista (come l'anteprima di «In onda»), quindi può uscire dalla vista.
     */
    fun rettangoloVideoNellaVista(
        larghezzaVista: Float, altezzaVista: Float, larghezzaVideo: Int, altezzaVideo: Int, rotazione: Int, riempi: Boolean = false,
    ): FloatArray {
        if (larghezzaVista <= 0f || altezzaVista <= 0f || larghezzaVideo <= 0 || altezzaVideo <= 0) {
            return floatArrayOf(0f, 0f, larghezzaVista.coerceAtLeast(0f), altezzaVista.coerceAtLeast(0f))
        }
        val girato = Math.floorMod(rotazione, 180) == 90
        val l = (if (girato) altezzaVideo else larghezzaVideo).toFloat()
        val a = (if (girato) larghezzaVideo else altezzaVideo).toFloat()
        val scala = if (riempi) maxOf(larghezzaVista / l, altezzaVista / a) else minOf(larghezzaVista / l, altezzaVista / a)
        val lv = l * scala
        val av = a * scala
        val x = (larghezzaVista - lv) / 2
        val y = (altezzaVista - av) / 2
        return floatArrayOf(x, y, x + lv, y + av)
    }

    /**
     * Da un punto della vista dell'anteprima (normalizzato sulla vista) al punto del video inviato; `null` se cade
     * sulle bande. Il contrario di come il Renderizzatore disegna l'anteprima. Con `riempi` (anteprima ritagliata) il
     * punto toccato è sempre nel video: si tiene conto della parte tagliata fuori dallo schermo.
     */
    fun anteprimaAlVideo(
        x: Float, y: Float, larghezzaVista: Float, altezzaVista: Float, larghezzaVideo: Int, altezzaVideo: Int, rotazione: Int,
        riempi: Boolean = false,
    ): Pair<Float, Float>? {
        val r = rettangoloVideoNellaVista(larghezzaVista, altezzaVista, larghezzaVideo, altezzaVideo, rotazione, riempi)
        val px = x * larghezzaVista
        val py = y * altezzaVista
        if (r[2] <= r[0] || r[3] <= r[1] || px < r[0] || px > r[2] || py < r[1] || py > r[3]) return null
        val qx = (px - r[0]) / (r[2] - r[0])
        val qy = (py - r[1]) / (r[3] - r[1])
        return antiorario(qx, qy, rotazione)
    }

    /** Un rettangolo (sinistra, alto, destra, basso, normalizzati) dal video alla fotocamera. */
    fun rettangoloAllaFotocamera(sinistra: Float, alto: Float, destra: Float, basso: Float, p: ParametriGeometria): FloatArray {
        val (x1, y1) = videoAllaFotocamera(sinistra, alto, p)
        val (x2, y2) = videoAllaFotocamera(destra, basso, p)
        return floatArrayOf(minOf(x1, x2), minOf(y1, y2), maxOf(x1, x2), maxOf(y1, y2))
    }

    /** Un rettangolo (sinistra, alto, destra, basso, normalizzati) dalla fotocamera al video. */
    fun rettangoloAlVideo(sinistra: Float, alto: Float, destra: Float, basso: Float, p: ParametriGeometria): FloatArray {
        val (x1, y1) = fotocameraAlVideo(sinistra, alto, p)
        val (x2, y2) = fotocameraAlVideo(destra, basso, p)
        return floatArrayOf(minOf(x1, x2), minOf(y1, y2), maxOf(x1, x2), maxOf(y1, y2))
    }

    /**
     * Da un rettangolo delle regioni di Camera2 (volti, AE) al fotogramma della fotocamera, normalizzato.
     * `campo` è il campo visivo nelle stesse coordinate (con CONTROL_ZOOM_RATIO tutta l'area attiva, altrimenti il
     * ritaglio SCALER_CROP_REGION); il fotogramma ne mostra una parte centrata con le proporzioni del flusso.
     */
    fun daRegioni(
        sinistra: Float, alto: Float, destra: Float, basso: Float,
        campoSinistra: Float, campoAlto: Float, campoLarghezza: Float, campoAltezza: Float,
        larghezzaFotocamera: Int, altezzaFotocamera: Int,
    ): FloatArray {
        val proporzioneCampo = campoLarghezza / campoAltezza.coerceAtLeast(1f)
        val proporzioneFlusso = larghezzaFotocamera.toFloat() / altezzaFotocamera.coerceAtLeast(1)
        fun x(valore: Float): Float {
            val u = (valore - campoSinistra) / campoLarghezza.coerceAtLeast(1f)
            return if (proporzioneFlusso < proporzioneCampo) (u - 0.5f) * (proporzioneCampo / proporzioneFlusso) + 0.5f else u
        }
        fun y(valore: Float): Float {
            val v = (valore - campoAlto) / campoAltezza.coerceAtLeast(1f)
            return if (proporzioneFlusso > proporzioneCampo) (v - 0.5f) * (proporzioneFlusso / proporzioneCampo) + 0.5f else v
        }
        return floatArrayOf(x(sinistra), y(alto), x(destra), y(basso))
    }

    /** Il contrario di [daRegioni] per un punto: dal fotogramma alle coordinate delle regioni. */
    fun versoRegioni(
        x: Float, y: Float,
        campoSinistra: Float, campoAlto: Float, campoLarghezza: Float, campoAltezza: Float,
        larghezzaFotocamera: Int, altezzaFotocamera: Int,
    ): Pair<Float, Float> {
        val proporzioneCampo = campoLarghezza / campoAltezza.coerceAtLeast(1f)
        val proporzioneFlusso = larghezzaFotocamera.toFloat() / altezzaFotocamera.coerceAtLeast(1)
        val u = if (proporzioneFlusso < proporzioneCampo) (x - 0.5f) / (proporzioneCampo / proporzioneFlusso) + 0.5f else x
        val v = if (proporzioneFlusso > proporzioneCampo) (y - 0.5f) / (proporzioneFlusso / proporzioneCampo) + 0.5f else y
        return (campoSinistra + u * campoLarghezza) to (campoAlto + v * campoAltezza)
    }
}
