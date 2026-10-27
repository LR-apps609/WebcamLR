package it.lrapps.webcamlr.android.effetti

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.util.Log
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.video.Sovrapposizione
import it.lrapps.webcamlr.protocollo.PacchettoImmagine
import it.lrapps.webcamlr.protocollo.SfondiPronti
import it.lrapps.webcamlr.protocollo.UsoImmagine
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Le immagini degli effetti disegnate con il Canvas di Android: sottopancia e logo (P17, come EffettoScritta.swift),
 * gli sfondi pronti (P14, in `assets/sfondi`) e le immagini caricate dal computer (logo e immagine personale, nel
 * contenitore dell'app: restano dopo il riavvio).
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

    /** Gli sfondi pronti che l'app ha davvero (`assets/sfondi/<id>.jpg`), nell'ordine del protocollo. */
    val sfondiPronti: List<String> by lazy {
        val presenti = try {
            app.assets.list("sfondi")?.toSet() ?: emptySet()
        } catch (e: Exception) {
            emptySet()
        }
        SfondiPronti.TUTTI.filter { "$it.jpg" in presenti }
    }

    /**
     * L'immagine per lo sfondo sostituito: uno degli sfondi pronti (1920×1080) o l'immagine personale; `null` se non
     * c'è (chi chiama ripiega sul primo sfondo pronto).
     */
    fun sfondo(scelto: String): Bitmap? =
        if (scelto == SfondiPronti.PERSONALE) caricaFotoSfondo() else if (scelto in sfondiPronti) leggiSfondoPronto(scelto) else null

    private fun leggiSfondoPronto(id: String): Bitmap? = try {
        app.assets.open("sfondi/$id.jpg").use { BitmapFactory.decodeStream(it) }?.let { ridotta(it, 1920) }
    } catch (e: Exception) {
        Log.w("WebcamLR", "Sfondo pronto non letto", e)
        null
    }

    // Immagini caricate dal computer (pacchetto immagine): si salvano i byte come sono arrivati, così l'impronta del
    // file è quella che calcola il computer (`stato.immaginePersonale`, `stato.logo`).

    private val fileLogo: File get() = File(app.filesDir, "LogoWebcamLR.png")
    private val fileFoto: File get() = File(app.filesDir, "SfondoWebcamLR.jpg")

    val haLogo: Boolean get() = fileLogo.exists()
    val haFotoSfondo: Boolean get() = fileFoto.exists()

    /** Le impronte dei file salvati, lette da [calcolaImpronte] e aggiornate da [salvaImmagine] e [togliLogo]. */
    @Volatile var improntaFoto: String? = null
        private set
    @Volatile var improntaLogo: String? = null
        private set

    /** Le impronte dei file già salvati (all'avvio della sessione), fuori dal thread principale. */
    fun calcolaImpronte() {
        improntaFoto = impronta(fileFoto)
        improntaLogo = impronta(fileLogo)
    }

    private fun impronta(file: File): String? = try {
        if (file.exists()) PacchettoImmagine.improntaDi(file.readBytes()) else null
    } catch (e: Exception) {
        null
    }

    /** Il logo salvato, ridotto (lato lungo 512 px), con la trasparenza. */
    fun caricaLogo(): Bitmap? = leggi(fileLogo, 512)

    fun caricaFotoSfondo(): Bitmap? = leggi(fileFoto, 1920)

    /**
     * Salva un'immagine dal computer al posto della precedente (fuori dal thread principale). Falso se i byte non
     * sono un'immagine che Android sa leggere o se non si è potuta scrivere: il file di prima resta.
     */
    fun salvaImmagine(immagine: PacchettoImmagine): Boolean {
        val misure = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(immagine.dati, 0, immagine.dati.size, misure)
        if (misure.outWidth <= 0 || misure.outHeight <= 0) return false
        val logo = immagine.uso == UsoImmagine.LOGO
        val file = if (logo) fileLogo else fileFoto
        val temporaneo = File(app.filesDir, file.name + ".nuovo")
        return try {
            temporaneo.writeBytes(immagine.dati)
            if (!temporaneo.renameTo(file)) {
                temporaneo.delete()
                return false
            }
            if (logo) improntaLogo = immagine.impronta else improntaFoto = immagine.impronta
            true
        } catch (e: Exception) {
            Log.w("WebcamLR", "Immagine non salvata", e)
            temporaneo.delete()
            false
        }
    }

    /** Cancella il logo (`comando.togliLogo`). */
    fun togliLogo() {
        fileLogo.delete()
        improntaLogo = null
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
