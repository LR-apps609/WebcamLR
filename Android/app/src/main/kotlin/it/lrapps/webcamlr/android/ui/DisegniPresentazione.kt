package it.lrapps.webcamlr.android.ui

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// I disegni della presentazione, fatti solo di forme nei colori di Tema (come DisegniPresentazione.swift
// dell'iPhone): niente foto, niente video, niente loghi di altri. Ogni disegno prende una larghezza in pixel
// e ricava il resto in proporzione.

/** Le proporzioni dei disegni (altezza diviso larghezza), per impaginare le scene. */
object Proporzioni {
    /** Portatile: schermo più base. */
    const val PORTATILE = 0.655f
    /** Telefono in verticale. */
    const val TELEFONO = 2.05f
    /** Il supporto sotto il telefono. */
    const val SUPPORTO = 0.65f
    /** Monitor da scrivania: schermo, collo e piede. */
    const val MONITOR = 0.78f
}

private fun DrawScope.rettangoloArrotondato(colore: Color, rett: Rect, raggio: Float) =
    drawRoundRect(colore, topLeft = rett.topLeft, size = rett.size, cornerRadius = CornerRadius(raggio))

private fun DrawScope.bordoArrotondato(colore: Color, rett: Rect, raggio: Float, spessore: Float = 1.5f) =
    drawRoundRect(colore, topLeft = rett.topLeft, size = rett.size, cornerRadius = CornerRadius(raggio), style = Stroke(spessore))

/** Disegna `contenuto` ritagliato in un rettangolo arrotondato. */
fun DrawScope.ritagliato(rett: Rect, raggio: Float, contenuto: DrawScope.() -> Unit) {
    val percorso = Path().apply { addRoundRect(RoundRect(rett, CornerRadius(raggio))) }
    clipPath(percorso) { contenuto() }
}

private fun coperchioPortatile(origine: Offset, larghezza: Float) =
    Rect(origine.x + larghezza * 0.07f, origine.y, origine.x + larghezza * 0.93f, origine.y + larghezza * 0.62f)

/** Il vetro dello schermo del portatile: per mettere sopra un comando o una scritta nello stesso punto. */
fun vetroPortatile(origine: Offset, larghezza: Float): Rect = coperchioPortatile(origine, larghezza).deflate(larghezza * 0.028f)

/** Il vetro dello schermo del monitor. */
fun vetroMonitor(origine: Offset, larghezza: Float): Rect = Rect(origine, Size(larghezza, larghezza * 0.6f)).deflate(larghezza * 0.03f)

/**
 * Un portatile generico (nessun marchio) con l'angolo in alto a sinistra in `origine`.
 * `schermo` disegna nel rettangolo dello schermo, già ritagliato.
 */
fun DrawScope.disegnaPortatile(origine: Offset, larghezza: Float, schermo: DrawScope.(Rect) -> Unit) {
    val coperchio = coperchioPortatile(origine, larghezza)
    rettangoloArrotondato(Colori.pannelloChiaro, coperchio, larghezza * 0.035f)
    bordoArrotondato(Colori.bordo, coperchio, larghezza * 0.035f)
    val vetro = coperchio.deflate(larghezza * 0.028f)
    ritagliato(vetro, larghezza * 0.015f) {
        drawRect(Colori.sfumaturaScura, vetro.topLeft, vetro.size)
        schermo(vetro)
    }
    val base = Rect(origine.x, coperchio.bottom, origine.x + larghezza, coperchio.bottom + larghezza * 0.035f)
    val percorso = Path().apply {
        addRoundRect(
            RoundRect(
                base, topLeft = CornerRadius.Zero, topRight = CornerRadius.Zero,
                bottomRight = CornerRadius(larghezza * 0.03f), bottomLeft = CornerRadius(larghezza * 0.03f),
            ),
        )
    }
    drawPath(percorso, Colori.salviaScura)
    drawRoundRect(
        Colori.pannelloScuro,
        topLeft = Offset(base.center.x - larghezza * 0.07f, base.top),
        size = Size(larghezza * 0.14f, larghezza * 0.012f),
        cornerRadius = CornerRadius(larghezza * 0.006f),
    )
}

/** Un monitor da scrivania generico, per il PC (nessun marchio). */
fun DrawScope.disegnaMonitor(origine: Offset, larghezza: Float, schermo: DrawScope.(Rect) -> Unit) {
    val cornice = Rect(origine, Size(larghezza, larghezza * 0.6f))
    rettangoloArrotondato(Colori.pannelloChiaro, cornice, larghezza * 0.03f)
    bordoArrotondato(Colori.bordo, cornice, larghezza * 0.03f)
    val vetro = cornice.deflate(larghezza * 0.03f)
    ritagliato(vetro, larghezza * 0.012f) {
        drawRect(Colori.sfumaturaScura, vetro.topLeft, vetro.size)
        schermo(vetro)
    }
    drawRect(Colori.salviaScura, Offset(cornice.center.x - larghezza * 0.05f, cornice.bottom), Size(larghezza * 0.1f, larghezza * 0.14f))
    drawRoundRect(
        Colori.salviaScura,
        topLeft = Offset(cornice.center.x - larghezza * 0.21f, cornice.bottom + larghezza * 0.14f),
        size = Size(larghezza * 0.42f, larghezza * 0.04f),
        cornerRadius = CornerRadius(larghezza * 0.02f),
    )
}

/** Il retro del telefono con il modulo delle fotocamere: è lui che riprende. */
fun DrawScope.disegnaTelefonoRetro(origine: Offset, larghezza: Float) {
    val corpo = Rect(origine, Size(larghezza, larghezza * Proporzioni.TELEFONO))
    drawRoundRect(
        Brush.linearGradient(listOf(Colori.pannelloChiaro, Colori.pannello), start = corpo.topLeft, end = corpo.bottomRight),
        topLeft = corpo.topLeft, size = corpo.size, cornerRadius = CornerRadius(larghezza * 0.2f),
    )
    bordoArrotondato(Colori.bordo, corpo, larghezza * 0.2f)
    val modulo = Rect(origine + Offset(larghezza * 0.1f, larghezza * 0.1f), Size(larghezza * 0.46f, larghezza * 0.46f))
    rettangoloArrotondato(Colori.pannelloScuro, modulo, larghezza * 0.12f)
    bordoArrotondato(Colori.linea, modulo, larghezza * 0.12f, 1f)
    val raggio = larghezza * 0.085f
    val centri = listOf(
        Offset(modulo.left + modulo.width * 0.3f, modulo.top + modulo.height * 0.3f),
        Offset(modulo.left + modulo.width * 0.7f, modulo.top + modulo.height * 0.3f),
        Offset(modulo.left + modulo.width * 0.3f, modulo.top + modulo.height * 0.7f),
    )
    for (centro in centri) {
        drawCircle(Colori.sfumaturaScura, raggio, centro)
        drawCircle(Colori.salviaScura, raggio, centro, style = Stroke(1.5f))
        drawCircle(Colori.accento.copy(alpha = 0.45f), raggio * 0.32f, centro - Offset(raggio * 0.24f, raggio * 0.24f))
    }
    drawCircle(Colori.salviaTenue.copy(alpha = 0.7f), raggio * 0.45f, Offset(modulo.left + modulo.width * 0.7f, modulo.top + modulo.height * 0.7f))
}

/** Il piccolo supporto da scrivania sotto il telefono: morsetto, asta e piede. */
fun DrawScope.disegnaSupporto(centroAlto: Offset, larghezza: Float) {
    drawRoundRect(
        Colori.salviaScura, topLeft = Offset(centroAlto.x - larghezza * 0.25f, centroAlto.y),
        size = Size(larghezza * 0.5f, larghezza * 0.1f), cornerRadius = CornerRadius(larghezza * 0.04f),
    )
    drawRect(Colori.salviaScura, Offset(centroAlto.x - larghezza * 0.05f, centroAlto.y + larghezza * 0.1f), Size(larghezza * 0.1f, larghezza * 0.45f))
    drawRoundRect(
        Colori.salviaScura, topLeft = Offset(centroAlto.x - larghezza * 0.475f, centroAlto.y + larghezza * 0.55f),
        size = Size(larghezza * 0.95f, larghezza * 0.1f), cornerRadius = CornerRadius(larghezza * 0.05f),
    )
}

/** Il telefono sul supporto, alto `larghezza × (TELEFONO + SUPPORTO)`. */
fun DrawScope.disegnaTelefonoSuSupporto(origine: Offset, larghezza: Float) {
    disegnaTelefonoRetro(origine, larghezza)
    disegnaSupporto(Offset(origine.x + larghezza / 2, origine.y + larghezza * Proporzioni.TELEFONO), larghezza)
}

/** Il fronte del telefono, con un contenuto sullo schermo e il foro della fotocamera in alto. */
fun DrawScope.disegnaTelefonoFronte(origine: Offset, larghezza: Float, schermo: DrawScope.(Rect) -> Unit) {
    val corpo = Rect(origine, Size(larghezza, larghezza * Proporzioni.TELEFONO))
    rettangoloArrotondato(Colori.pannelloScuro, corpo, larghezza * 0.18f)
    bordoArrotondato(Colori.bordo, corpo, larghezza * 0.18f)
    val vetro = corpo.deflate(larghezza * 0.05f)
    ritagliato(vetro, larghezza * 0.14f) {
        drawRect(Colori.fondo, vetro.topLeft, vetro.size)
        schermo(vetro)
    }
    drawCircle(Colori.sfumaturaScura, larghezza * 0.045f, Offset(corpo.center.x, corpo.top + larghezza * 0.13f))
}

/** Una persona stilizzata (testa, capelli, spalle) con i piedi del busto in `centroBasso`, alta `altezza`. */
fun DrawScope.disegnaPersona(
    centroBasso: Offset,
    altezza: Float,
    pelle: Color = Colori.salviaChiara,
    maglia: Color = Colori.salviaScura,
    capelli: Color = Colori.sfumaturaScura,
) {
    val busto = Rect(centroBasso.x - altezza * 0.45f, centroBasso.y - altezza * 0.52f, centroBasso.x + altezza * 0.45f, centroBasso.y)
    drawPath(
        Path().apply {
            addRoundRect(
                RoundRect(
                    busto, topLeft = CornerRadius(altezza * 0.24f), topRight = CornerRadius(altezza * 0.24f),
                    bottomRight = CornerRadius.Zero, bottomLeft = CornerRadius.Zero,
                ),
            )
        },
        maglia,
    )
    val testa = altezza * 0.42f
    val altoTesta = busto.top - testa + altezza * 0.05f
    drawOval(pelle, Offset(centroBasso.x - testa * 0.41f, altoTesta), Size(testa * 0.82f, testa))
    drawPath(
        Path().apply {
            addRoundRect(
                RoundRect(
                    Rect(centroBasso.x - testa * 0.44f, altoTesta - testa * 0.05f, centroBasso.x + testa * 0.44f, altoTesta + testa * 0.31f),
                    topLeft = CornerRadius(testa * 0.45f), topRight = CornerRadius(testa * 0.45f),
                    bottomRight = CornerRadius(testa * 0.1f), bottomLeft = CornerRadius(testa * 0.1f),
                ),
            )
        },
        capelli,
    )
}

/**
 * L'inquadratura di una persona nella sua stanza (parete, finestra, mensola, pianta), con le regolazioni che i profili
 * cambiano: luce sul volto (0–1), sfondo sfocato (0–1: la stanza si sbiadisce, come una sfocatura), persona più
 * piccola e scrivania davanti (0–1).
 */
fun DrawScope.disegnaStanza(
    rett: Rect,
    luceVolto: Float = 0f,
    sfocaSfondo: Float = 0f,
    scalaPersona: Float = 1f,
    scrivania: Float = 0f,
) {
    val w = rett.width
    val h = rett.height
    clipRect(rett.left, rett.top, rett.right, rett.bottom) {
        drawRect(Brush.verticalGradient(listOf(Colori.pannelloChiaro, Colori.pannello), startY = rett.top, endY = rett.bottom), rett.topLeft, rett.size)
        val dettagli = 1f - 0.75f * sfocaSfondo
        // La finestra
        rettangoloArrotondato(
            Colori.salviaTenue.copy(alpha = 0.3f * dettagli + 0.08f * sfocaSfondo),
            Rect(Offset(rett.left + w * 0.7f, rett.top + h * 0.1f), Size(w * 0.24f, h * 0.34f)), w * 0.02f,
        )
        drawRect(Colori.pannelloChiaro.copy(alpha = dettagli), Offset(rett.left + w * 0.814f, rett.top + h * 0.1f), Size(max(1f, w * 0.012f), h * 0.34f))
        // La mensola con i libri
        drawRect(Colori.salviaScura.copy(alpha = dettagli), Offset(rett.left + w * 0.05f, rett.top + h * 0.3f), Size(w * 0.26f, max(1.5f, h * 0.015f)))
        val coloriLibri = listOf(Colori.salvia, Colori.salviaTenue, Colori.salviaScura, Colori.testoSecondario)
        val altezzeLibri = listOf(0.1f, 0.13f, 0.09f, 0.12f)
        for (indice in 0 until 4) {
            val altezza = h * altezzeLibri[indice]
            drawRoundRect(
                coloriLibri[indice].copy(alpha = dettagli),
                topLeft = Offset(rett.left + w * (0.07f + indice * 0.038f), rett.top + h * 0.3f - altezza),
                size = Size(w * 0.03f, altezza), cornerRadius = CornerRadius(1f),
            )
        }
        // La pianta
        val basePianta = Offset(rett.left + w * 0.12f, rett.top + h * 0.94f)
        for (indice in 0 until 5) {
            rotate((indice - 2) * 22f, pivot = Offset(basePianta.x, basePianta.y - h * 0.08f)) {
                drawRoundRect(
                    (if (indice % 2 == 0) Colori.salvia else Colori.salviaScura).copy(alpha = dettagli),
                    topLeft = Offset(basePianta.x - w * 0.02f, basePianta.y - h * 0.28f), size = Size(w * 0.04f, h * 0.2f),
                    cornerRadius = CornerRadius(w * 0.02f),
                )
            }
        }
        rettangoloArrotondato(Colori.bordo.copy(alpha = dettagli), Rect(Offset(basePianta.x - w * 0.045f, basePianta.y - h * 0.08f), Size(w * 0.09f, h * 0.08f)), 2f)
        // La persona, con la luce sul volto
        val altezzaPersona = h * 0.8f * scalaPersona
        val base = rett.bottom - scrivania * h * 0.2f
        val pelle = lerp(Colori.salviaChiara, Colori.testo, 0.35f * luceVolto)
        disegnaPersona(Offset(rett.left + w / 2, base), altezzaPersona, pelle = pelle)
        if (luceVolto > 0f) {
            val centroVolto = Offset(rett.left + w / 2, base - altezzaPersona * 0.62f)
            drawCircle(
                Brush.radialGradient(listOf(Colori.testo.copy(alpha = 0.4f * luceVolto), Color.Transparent), center = centroVolto, radius = altezzaPersona * 0.34f),
                radius = altezzaPersona * 0.34f, center = centroVolto,
            )
        }
        // La scrivania in primo piano
        if (scrivania > 0f) {
            val alto = rett.top + h * 0.76f
            drawRect(
                Brush.verticalGradient(listOf(Colori.salviaScura, Colori.pannelloScuro), startY = alto, endY = rett.bottom),
                Offset(rett.left, alto), Size(w, h * 0.24f), alpha = scrivania,
            )
            rotate(-6f, pivot = Offset(rett.left + w * 0.5f, alto + h * 0.1f)) {
                drawRoundRect(Colori.testoChiaro, Offset(rett.left + w * 0.35f, alto + h * 0.05f), Size(w * 0.3f, h * 0.11f), CornerRadius(2f), alpha = scrivania)
            }
            rotate(20f, pivot = Offset(rett.left + w * 0.8f, alto + h * 0.1f)) {
                drawRoundRect(Colori.salviaChiara, Offset(rett.left + w * 0.72f, alto + h * 0.09f), Size(w * 0.16f, max(1.5f, h * 0.015f)), CornerRadius(2f), alpha = scrivania)
            }
        }
    }
}

private fun lerp(a: Color, b: Color, t: Float) = Color(
    red = a.red + (b.red - a.red) * t,
    green = a.green + (b.green - a.green) * t,
    blue = a.blue + (b.blue - a.blue) * t,
    alpha = 1f,
)

/** La webcam scadente del computer sopra la stanza: più scura, slavata, con la grana. */
fun DrawScope.disegnaWebcamScadente(rett: Rect, seme: Long) {
    drawRect(Colori.sfumaturaScura.copy(alpha = 0.42f), rett.topLeft, rett.size)
    drawRect(Colori.salviaScura.copy(alpha = 0.18f), rett.topLeft, rett.size)
    disegnaGrana(rett, seme, 0.35f)
}

/** La grana: puntini chiari e scuri ripetibili (SplitMix64), stesso seme stessi puntini. */
fun DrawScope.disegnaGrana(rett: Rect, seme: Long, intensita: Float) {
    var stato = seme
    fun frazione(): Float {
        stato += -0x61c8864680b583ebL
        var z = stato
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        z = z xor (z ushr 31)
        return ((z ushr 11).toDouble() / (1L shl 53).toDouble()).toFloat()
    }
    val quanti = min(1800, (rett.width * rett.height / 40f).toInt())
    val lato = max(1.3f, density * 0.9f)
    for (indice in 0 until quanti) {
        val punto = Offset(rett.left + frazione() * rett.width, rett.top + frazione() * rett.height)
        val colore = if (indice % 2 == 0) Colori.testo.copy(alpha = intensita) else Colori.sfumaturaScura.copy(alpha = min(1f, intensita * 1.4f))
        drawRect(colore, punto, Size(lato, lato))
    }
}

/**
 * Onde di segnale che partono da `origine` (in basso a sinistra) verso `direzioneGradi` (−50 = in alto a destra).
 * `fase` da 0 a 1 le fa allargare; con le animazioni ridotte restano ferme.
 */
fun DrawScope.disegnaOnde(origine: Offset, lato: Float, fase: Float, ferme: Boolean, direzioneGradi: Float = -50f) {
    val direzione = Math.toRadians(direzioneGradi.toDouble())
    for (indice in 0 until 3) {
        val f = if (ferme) (indice + 1f) / 3.5f else ((fase + indice / 3f) % 1f)
        val raggio = lato * 1.15f * (0.2f + 0.8f * f)
        val arco = Path()
        for (passo in 0..12) {
            val angolo = direzione + (passo / 12.0 - 0.5)
            val punto = Offset(origine.x + raggio * cos(angolo).toFloat(), origine.y + raggio * sin(angolo).toFloat())
            if (passo == 0) arco.moveTo(punto.x, punto.y) else arco.lineTo(punto.x, punto.y)
        }
        drawPath(arco, Colori.accento.copy(alpha = if (ferme) 0.8f else 1f - f), style = Stroke(width = 3f * density / 1.5f, cap = StrokeCap.Round))
    }
}

/** Tra telefono e computer: i fotogrammi che passano (fotocamera). */
fun DrawScope.disegnaFotogrammi(rett: Rect, tempo: Float) {
    for (indice in 0 until 3) {
        val fase = (tempo * 0.5f + indice / 3f) % 1f
        val x = rett.left + fase * rett.width
        val lato = 9f * density / 1.5f
        drawRoundRect(
            Colori.accento.copy(alpha = sin(fase * Math.PI).toFloat().coerceIn(0f, 1f)),
            topLeft = Offset(x - lato * 1.5f, rett.center.y - lato), size = Size(lato * 3f, lato * 2f), cornerRadius = CornerRadius(lato * 0.5f),
        )
    }
}

/** Le barre dell'audio (microfono). */
fun DrawScope.disegnaAudio(rett: Rect, tempo: Float) {
    val quante = 7
    val passo = rett.width / quante
    for (indice in 0 until quante) {
        val ampiezza = 0.25f + 0.75f * abs(sin(tempo * 4f + indice * 0.9f))
        val altezza = rett.height * 0.8f * ampiezza
        drawRoundRect(
            Colori.accento,
            topLeft = Offset(rett.left + indice * passo + passo * 0.3f, rett.center.y - altezza / 2),
            size = Size(passo * 0.4f, altezza), cornerRadius = CornerRadius(passo * 0.2f),
        )
    }
}

/** I puntini dell'avviso (notifiche): uno alla volta si accende, come un battito. */
fun DrawScope.disegnaBattito(rett: Rect, tempo: Float, ferme: Boolean) {
    val quanti = 5
    val passo = rett.width / quanti
    val acceso = (tempo * 3f).toInt() % quanti
    for (indice in 0 until quanti) {
        val vicino = ferme || indice == acceso
        drawCircle(
            Colori.accento.copy(alpha = if (vicino) 1f else 0.3f),
            radius = min(passo * 0.22f, rett.height * 0.2f),
            center = Offset(rett.left + passo * (indice + 0.5f), rett.center.y),
        )
    }
}
