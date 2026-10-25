package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Filtri
import kotlin.math.roundToInt

/**
 * Un filtro (P13) come numeri per lo shader del [it.lrapps.webcamlr.android.video.Renderizzatore], ricavato dalle
 * ricette Core Image dell'iPhone (EffettoFiltro.swift). Si lavora sui valori della fotocamera (già percettivi):
 *
 * colore = mescola(ombre·c + biasOmbre, luci·c + biasLuci, luminanza(c)) → saturazione e contrasto → curva (tabella
 * di 256 valori) → vignettatura. Le matrici sono 3×3 per colonne (come le vuole OpenGL).
 */
class RicettaFiltro(
    val ombre: FloatArray = IDENTITA,
    val biasOmbre: FloatArray = ZERO,
    val luci: FloatArray = IDENTITA,
    val biasLuci: FloatArray = ZERO,
    val saturazione: Float = 1f,
    val contrasto: Float = 1f,
    /** I valori della curva a 0; 0,25; 0,5; 0,75; 1. */
    val curva: FloatArray = floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1f),
    val vignetta: Float = 0f,
) {
    val neutra: Boolean
        get() = ombre.contentEquals(IDENTITA) && luci.contentEquals(IDENTITA) && biasOmbre.contentEquals(ZERO) &&
            biasLuci.contentEquals(ZERO) && saturazione == 1f && contrasto == 1f && vignetta == 0f &&
            curva.contentEquals(floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1f))

    companion object {
        val IDENTITA = floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f)
        val ZERO = floatArrayOf(0f, 0f, 0f)

        fun diagonale(r: Float, g: Float, b: Float) = floatArrayOf(r, 0f, 0f, 0f, g, 0f, 0f, 0f, b)
    }
}

object RicetteFiltri {
    /** Pesi Rec. 709 della luminanza. */
    private val MONO = floatArrayOf(0.2126f, 0.2126f, 0.2126f, 0.7152f, 0.7152f, 0.7152f, 0.0722f, 0.0722f, 0.0722f)

    /** Seppia classica (per colonne), mescolata al 75% con l'originale. */
    private val SEPPIA: FloatArray = run {
        val seppia = floatArrayOf(0.393f, 0.349f, 0.272f, 0.769f, 0.686f, 0.534f, 0.189f, 0.168f, 0.131f)
        FloatArray(9) { i -> RicettaFiltro.IDENTITA[i] * 0.25f + seppia[i] * 0.75f }
    }

    fun ricetta(filtro: String): RicettaFiltro = when (filtro) {
        Filtri.CALDO -> RicettaFiltro(
            ombre = RicettaFiltro.diagonale(1.07f, 1f, 0.88f), luci = RicettaFiltro.diagonale(1.07f, 1f, 0.88f), saturazione = 1.05f,
        )
        Filtri.FREDDO -> RicettaFiltro(
            ombre = RicettaFiltro.diagonale(0.92f, 0.98f, 1.08f), luci = RicettaFiltro.diagonale(0.92f, 0.98f, 1.08f),
            saturazione = 0.97f, curva = floatArrayOf(0f, 0.25f, 0.51f, 0.77f, 1f),
        )
        Filtri.LUMINOSO -> RicettaFiltro(curva = floatArrayOf(0.04f, 0.33f, 0.59f, 0.81f, 1f))
        Filtri.CINEMA -> RicettaFiltro(
            ombre = RicettaFiltro.diagonale(0.90f, 1f, 1.06f), biasOmbre = floatArrayOf(0f, 0.004f, 0.012f),
            luci = RicettaFiltro.diagonale(1.07f, 1f, 0.90f),
            saturazione = 0.92f, curva = floatArrayOf(0.02f, 0.20f, 0.5f, 0.80f, 0.98f), vignetta = 0.35f,
        )
        Filtri.VIVIDO -> RicettaFiltro(saturazione = 1.3f, contrasto = 1.04f)
        Filtri.TENUE -> RicettaFiltro(saturazione = 0.72f, curva = floatArrayOf(0.06f, 0.29f, 0.52f, 0.75f, 0.96f))
        Filtri.BIANCO_NERO -> RicettaFiltro(ombre = MONO, luci = MONO, curva = floatArrayOf(0f, 0.23f, 0.5f, 0.78f, 1f))
        Filtri.SEPPIA -> RicettaFiltro(ombre = SEPPIA, luci = SEPPIA, curva = floatArrayOf(0.04f, 0.27f, 0.51f, 0.75f, 0.97f))
        // Mezzo stop in più (circa ×1,17 sui valori percettivi), ombre aperte, un po' meno colore.
        Filtri.NOTTE -> RicettaFiltro(
            ombre = RicettaFiltro.diagonale(1.17f, 1.17f, 1.17f), luci = RicettaFiltro.diagonale(1.17f, 1.17f, 1.17f),
            saturazione = 0.95f, curva = floatArrayOf(0.03f, 0.34f, 0.60f, 0.82f, 1f),
        )
        else -> RicettaFiltro()
    }

    /**
     * La curva come tabella di 256 byte (uno per livello d'ingresso): interpolazione monotona (Fritsch–Carlson) tra i
     * cinque punti, così ombre e luci non fanno gradini e non si invertono.
     */
    fun tabella(curva: FloatArray): ByteArray {
        require(curva.size == 5)
        val x = floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1f)
        val h = 0.25f
        val pendenze = FloatArray(4) { (curva[it + 1] - curva[it]) / h }
        val tangenti = FloatArray(5)
        tangenti[0] = pendenze[0]
        tangenti[4] = pendenze[3]
        for (i in 1..3) {
            tangenti[i] = if (pendenze[i - 1] * pendenze[i] <= 0f) 0f else (pendenze[i - 1] + pendenze[i]) / 2
        }
        for (i in 0..3) {
            if (pendenze[i] == 0f) {
                tangenti[i] = 0f
                tangenti[i + 1] = 0f
                continue
            }
            val a = tangenti[i] / pendenze[i]
            val b = tangenti[i + 1] / pendenze[i]
            val somma = a * a + b * b
            if (somma > 9f) {
                val t = 3f / kotlin.math.sqrt(somma)
                tangenti[i] = t * a * pendenze[i]
                tangenti[i + 1] = t * b * pendenze[i]
            }
        }
        return ByteArray(256) { livello ->
            val v = livello / 255f
            val i = minOf((v / h).toInt(), 3)
            val t = (v - x[i]) / h
            val t2 = t * t
            val t3 = t2 * t
            val y = (2 * t3 - 3 * t2 + 1) * curva[i] + (t3 - 2 * t2 + t) * h * tangenti[i] +
                (-2 * t3 + 3 * t2) * curva[i + 1] + (t3 - t2) * h * tangenti[i + 1]
            (y.coerceIn(0f, 1f) * 255f).roundToInt().toByte()
        }
    }
}
