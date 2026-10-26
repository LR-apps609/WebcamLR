package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Codec
import it.lrapps.webcamlr.protocollo.FormatoVideo
import it.lrapps.webcamlr.protocollo.Temperatura

/** Un formato video in orizzontale (come i formati della fotocamera): il verso lo decide come è tenuto il telefono. */
data class FormatoScelto(val larghezza: Int, val altezza: Int, val fps: Int, val codec: Codec)

/**
 * Il formato chiesto dal computer con `formato` (per esempio i 60 fps per un'app che usa la webcam a 60), adattato a
 * ciò che l'obiettivo attuale sa fare. Vale per la sessione: cambiando le Impostazioni sul telefono decade.
 * Come FormatoRichiesto.swift.
 */
object FormatoRichiesto {
    val RISOLUZIONI = listOf(3840 to 2160, 1920 to 1080, 1280 to 720)

    /**
     * Come vuole il protocollo: se l'obiettivo non ce la fa scendono prima gli fps, poi la risoluzione. La risoluzione
     * si riconosce dal lato lungo (il computer può chiedere anche in verticale). `fpsMassimo(l, a)` = 0 se l'obiettivo
     * non ha quella risoluzione. `null` se la richiesta non ha senso o nessuna risoluzione va bene.
     */
    fun da(richiesta: FormatoVideo, fpsMassimo: (Int, Int) -> Int): FormatoScelto? {
        val lato = maxOf(richiesta.larghezza, richiesta.altezza)
        if (lato <= 0 || richiesta.fps <= 0) return null
        val voluti = richiesta.fps.coerceIn(15, 60)
        val inizio = RISOLUZIONI.indexOfFirst { it.first <= lato }.let { if (it < 0) RISOLUZIONI.lastIndex else it }
        for ((larghezza, altezza) in RISOLUZIONI.drop(inizio)) {
            val massimo = fpsMassimo(larghezza, altezza)
            if (massimo <= 0) continue
            val fps = minOf(voluti, massimo)
            // Sotto i 24 fps (o sotto quelli chiesti, se meno) conviene scendere di risoluzione.
            if (fps >= minOf(voluti, 24)) return FormatoScelto(larghezza, altezza, fps, richiesta.codec)
        }
        return null
    }
}

/**
 * 1.14: quanto si è scesi per il calore, dal più leggero al più forte (come `RiduzioneCalore` di SessioneTelefono.swift).
 */
enum class RiduzioneCalore {
    NESSUNA,
    /** Al massimo 30 fps, la risoluzione resta. */
    A30FPS,
    /** Al massimo 1080p a 30 fps. */
    A1080P30,
    /** Al massimo 720p a 24 fps. */
    A720P24,
}

/**
 * I gradini del calore con isteresi. Si scende subito: «calda» per più di un minuto → 30 fps; «molto calda» →
 * 1080p a 30 fps; «critica» → 720p a 24 fps. Si risale di un gradino alla volta, dopo due minuti di fila più freschi
 * del gradino attuale: niente salti avanti e indietro. Il tempo arriva da fuori (millisecondi), così si prova.
 */
class RegolatoreCalore(
    private val millisecondiPrimaDiScendere: Long = 60_000,
    private val millisecondiPrimaDiRisalire: Long = 120_000,
) {
    var attuale = RiduzioneCalore.NESSUNA
        private set
    private var caldaDa: Long? = null
    private var piuFrescaDa: Long? = null

    /** Il gradino giusto adesso; `attivo` falso («Riduci la qualità se si scalda» spento) = sempre nessuna riduzione. */
    fun valuta(temperatura: Temperatura, attivo: Boolean, adesso: Long): RiduzioneCalore {
        attuale = calcola(temperatura, attivo, adesso)
        return attuale
    }

    private fun calcola(temperatura: Temperatura, attivo: Boolean, adesso: Long): RiduzioneCalore {
        if (!attivo) {
            caldaDa = null
            piuFrescaDa = null
            return RiduzioneCalore.NESSUNA
        }
        if (temperatura == Temperatura.NORMALE) caldaDa = null else if (caldaDa == null) caldaDa = adesso
        val bersaglio = when (temperatura) {
            Temperatura.NORMALE -> RiduzioneCalore.NESSUNA
            Temperatura.CALDA -> {
                val daUnMinuto = adesso - (caldaDa ?: adesso) >= millisecondiPrimaDiScendere
                if (daUnMinuto || attuale >= RiduzioneCalore.A30FPS) RiduzioneCalore.A30FPS else RiduzioneCalore.NESSUNA
            }
            Temperatura.MOLTO_CALDA -> RiduzioneCalore.A1080P30
            Temperatura.CRITICA -> RiduzioneCalore.A720P24
        }
        if (bersaglio >= attuale) {
            piuFrescaDa = null
            return bersaglio
        }
        val da = piuFrescaDa ?: run {
            piuFrescaDa = adesso
            return attuale
        }
        if (adesso - da < millisecondiPrimaDiRisalire) return attuale
        // Il gradino dopo, se serve, fra altri due minuti.
        piuFrescaDa = adesso
        return RiduzioneCalore.entries[attuale.ordinal - 1]
    }
}

/** Il formato con cui partire: Impostazioni o richiesta del computer, poi i limiti di calore, batteria, Pro e 4K. */
object SceltaFormato {
    /** 1.14: il 4K al massimo a 30 fps. */
    const val FPS_MASSIMI_4K = 30

    fun effettivo(
        impostazioni: FormatoScelto,
        richiesto: FormatoScelto?,
        calore: RiduzioneCalore,
        risparmioBatteria: Boolean,
        pro: Boolean,
    ): FormatoScelto {
        var (larghezza, altezza, fps, codec) = richiesto ?: impostazioni
        when (calore) {
            RiduzioneCalore.NESSUNA -> Unit
            RiduzioneCalore.A30FPS -> fps = minOf(fps, 30)
            RiduzioneCalore.A1080P30 -> {
                larghezza = minOf(larghezza, 1920)
                altezza = minOf(altezza, 1080)
                fps = minOf(fps, 30)
            }
            RiduzioneCalore.A720P24 -> {
                larghezza = minOf(larghezza, 1280)
                altezza = minOf(altezza, 720)
                fps = minOf(fps, 24)
            }
        }
        if (risparmioBatteria) fps = minOf(fps, 24)
        if (!pro) {
            larghezza = minOf(larghezza, LimitiGratis.LARGHEZZA)
            altezza = minOf(altezza, LimitiGratis.ALTEZZA)
            fps = minOf(fps, LimitiGratis.FPS)
        }
        if (larghezza >= 3840) {
            // Il 4K al massimo a 30 fps e, scelto sul telefono, in HEVC; il codec chiesto dal computer si rispetta.
            fps = minOf(fps, FPS_MASSIMI_4K)
            if (richiesto == null) codec = Codec.HEVC
        }
        return FormatoScelto(larghezza, altezza, fps.coerceIn(1, 60), codec)
    }
}
