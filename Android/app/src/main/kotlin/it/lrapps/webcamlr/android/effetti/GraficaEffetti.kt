package it.lrapps.webcamlr.android.effetti

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.util.Log
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.logica.SfondiPronti
import it.lrapps.webcamlr.android.video.Sovrapposizione
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Le immagini degli effetti disegnate con il Canvas di Android: sottopancia e logo (P17, come EffettoScritta.swift),
 * gli sfondi pronti (P14) e i file scelti dall'utente (logo e foto, nel contenitore dell'app).
 *
 * Colori e caratteri della famiglia LR Apps (gli stessi valori di `Stile`): barra verde scuro un po' trasparente,
 * filo dell'accento salvia, nome in Barlow Condensed Bold e ruolo in maiuscolo.
 */
class GraficaEffetti(context: Context) {
    private val app = context.applicationContext

    private val carattereNome: Typeface = carattere(R.font.barlow_condensed_bold, Typeface.DEFAULT_BOLD)
    private val carattereRuolo: Typeface = carattere(R.font.barlow_condensed_semibold, Typeface.DEFAULT)

    private fun carattere(id: Int, ripiego: Typeface): Typeface = try {
        app.resources.getFont(id)
    } catch (e: Exception) {
        ripiego
    }

    /**
     * Sottopancia in basso a sinistra e logo in alto a destra per un video `larghezza`×`altezza`. Misure in proporzione
     * al lato corto: a 720p, 1080p e 4K occupano la stessa parte dell'immagine. Vuoto se non c'è nulla da mostrare.
     */
    fun sovrapposizioni(nome: String, ruolo: String, logo: Bitmap?, larghezza: Int, altezza: Int): List<Sovrapposizione> {
        if (larghezza <= 0 || altezza <= 0) return emptyList()
        val elenco = mutableListOf<Sovrapposizione>()
        val corto = min(larghezza, altezza).toFloat()
        val margine = corto * 0.05f
        val nomePulito = nome.trim()
        if (nomePulito.isNotEmpty()) {
            val ruoloPulito = ruolo.trim().uppercase()
            val pennelloNome = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = carattereNome
                textSize = corto * 0.058f
                color = TESTO
            }
            val pennelloRuolo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = carattereRuolo
                textSize = corto * 0.030f
                letterSpacing = 0.08f
                color = TESTO_SECONDARIO
            }
            val spazio = corto * 0.022f
            val filo = corto * 0.008f
            val larghezzaMassima = larghezza * 0.72f
            val testoNome = taglia(nomePulito, pennelloNome, larghezzaMassima - spazio * 3 - filo)
            val testoRuolo = if (ruoloPulito.isEmpty()) "" else taglia(ruoloPulito, pennelloRuolo, larghezzaMassima - spazio * 3 - filo)
            val metricheNome = pennelloNome.fontMetrics
            val metricheRuolo = pennelloRuolo.fontMetrics
            val altezzaNome = metricheNome.descent - metricheNome.ascent
            val altezzaRuolo = if (testoRuolo.isEmpty()) 0f else metricheRuolo.descent - metricheRuolo.ascent
            val larghezzaTesto = max(pennelloNome.measureText(testoNome), if (testoRuolo.isEmpty()) 0f else pennelloRuolo.measureText(testoRuolo))
            val l = (filo + spazio * 2.2f + larghezzaTesto).roundToInt().coerceAtLeast(1)
            val a = (spazio * 1.6f + altezzaNome + altezzaRuolo).roundToInt().coerceAtLeast(1)
            val immagine = Bitmap.createBitmap(l, a, Bitmap.Config.ARGB_8888)
            val tela = Canvas(immagine)
            val raggio = corto * 0.012f
            tela.drawRoundRect(RectF(0f, 0f, l.toFloat(), a.toFloat()), raggio, raggio, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = BARRA })
            tela.drawRect(0f, 0f, filo, a.toFloat(), Paint().apply { color = ACCENTO })
            val x = filo + spazio * 1.1f
            var y = spazio * 0.8f - metricheNome.ascent
            tela.drawText(testoNome, x, y, pennelloNome)
            if (testoRuolo.isNotEmpty()) {
                y += metricheNome.descent - metricheRuolo.ascent
                tela.drawText(testoRuolo, x, y, pennelloRuolo)
            }
            val sinistra = margine / larghezza
            val basso = 1f - margine * 1.2f / altezza
            elenco += Sovrapposizione(immagine, RectF(sinistra, basso - a.toFloat() / altezza, sinistra + l.toFloat() / larghezza, basso))
        }
        if (logo != null && !logo.isRecycled && logo.width > 0 && logo.height > 0) {
            // Al massimo il 9% dell'altezza (e il 20% della larghezza), con la trasparenza del file.
            val scala = min(altezza * 0.09f / logo.height, larghezza * 0.20f / logo.width)
            val l = logo.width * scala / larghezza
            val a = logo.height * scala / altezza
            val destra = 1f - margine / larghezza
            val alto = margine / altezza
            elenco += Sovrapposizione(logo, RectF(destra - l, alto, destra, alto + a))
        }
        return elenco
    }

    private fun taglia(testo: String, pennello: Paint, massimo: Float): String {
        if (pennello.measureText(testo) <= massimo) return testo
        var fine = testo.length
        while (fine > 1 && pennello.measureText(testo.substring(0, fine) + "…") > massimo) fine--
        return testo.substring(0, fine) + "…"
    }

    /** Uno sfondo pronto (`studio`, `salvia`) a 1280×720, oppure la foto dell'utente; `null` se la foto non c'è. */
    fun sfondo(scelto: String): Bitmap? = when (scelto) {
        SfondiPronti.FOTO -> caricaFotoSfondo()
        SfondiPronti.SALVIA -> sfumatura(0xFF8FA199.toInt(), 0xFF3E5149.toInt())
        else -> sfumatura(0xFF30453E.toInt(), 0xFF0D1B18.toInt())
    }

    /** Una sfumatura radiale come lo sfondo del logo LR Apps, con una luce morbida in alto. */
    private fun sfumatura(centro: Int, bordo: Int): Bitmap {
        val l = 1280
        val a = 720
        val immagine = Bitmap.createBitmap(l, a, Bitmap.Config.ARGB_8888)
        val tela = Canvas(immagine)
        val pennello = Paint(Paint.ANTI_ALIAS_FLAG or Paint.DITHER_FLAG)
        pennello.shader = RadialGradient(l * 0.5f, a * 0.35f, l * 0.75f, centro, bordo, Shader.TileMode.CLAMP)
        tela.drawRect(0f, 0f, l.toFloat(), a.toFloat(), pennello)
        pennello.shader = LinearGradient(0f, 0f, 0f, a.toFloat(), Color.argb(28, 255, 255, 255), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        tela.drawRect(0f, 0f, l.toFloat(), a * 0.5f, pennello)
        return immagine
    }

    // File scelti dall'utente

    private val fileLogo: File get() = File(app.filesDir, "LogoWebcamLR.png")
    private val fileFoto: File get() = File(app.filesDir, "SfondoWebcamLR.jpg")

    val haLogo: Boolean get() = fileLogo.exists()
    val haFotoSfondo: Boolean get() = fileFoto.exists()

    /** Il logo salvato, ridotto (lato lungo 512 px), con la trasparenza. */
    fun caricaLogo(): Bitmap? = leggi(fileLogo, 512)

    fun caricaFotoSfondo(): Bitmap? = leggi(fileFoto, 1920)

    /** Salva il logo scelto (PNG, lato lungo al massimo 512 px). Falso se non si è potuto salvare. */
    fun salvaLogo(immagine: Bitmap?): Boolean = salva(immagine, fileLogo, 512, Bitmap.CompressFormat.PNG)

    /** Salva la foto per lo sfondo sostituito (JPEG, lato lungo al massimo 1920 px). */
    fun salvaFotoSfondo(immagine: Bitmap?): Boolean = salva(immagine, fileFoto, 1920, Bitmap.CompressFormat.JPEG)

    private fun salva(immagine: Bitmap?, file: File, latoMassimo: Int, formato: Bitmap.CompressFormat): Boolean {
        if (immagine == null) return file.delete() || !file.exists()
        return try {
            val ridotta = ridotta(immagine, latoMassimo)
            file.outputStream().use { ridotta.compress(formato, 90, it) }
            if (ridotta !== immagine) ridotta.recycle()
            true
        } catch (e: Exception) {
            Log.w("WebcamLR", "Immagine non salvata", e)
            false
        }
    }

    private fun leggi(file: File, latoMassimo: Int): Bitmap? {
        if (!file.exists()) return null
        return try {
            val misure = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, misure)
            var campione = 1
            while (max(misure.outWidth, misure.outHeight) / (campione * 2) >= latoMassimo) campione *= 2
            val letta = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = campione }) ?: return null
            ridotta(letta, latoMassimo)
        } catch (e: Exception) {
            null
        }
    }

    private fun ridotta(immagine: Bitmap, latoMassimo: Int): Bitmap {
        val lato = max(immagine.width, immagine.height)
        if (lato <= latoMassimo) return immagine
        val scala = latoMassimo.toFloat() / lato
        return Bitmap.createScaledBitmap(immagine, (immagine.width * scala).roundToInt().coerceAtLeast(1), (immagine.height * scala).roundToInt().coerceAtLeast(1), true)
    }

    companion object {
        private val BARRA = Color.argb(209, 0x13, 0x21, 0x1D)
        private val ACCENTO = 0xFF9FD0B6.toInt()
        private val TESTO = 0xFFE6EEEA.toInt()
        private val TESTO_SECONDARIO = 0xFFB4C2BB.toInt()
    }
}
