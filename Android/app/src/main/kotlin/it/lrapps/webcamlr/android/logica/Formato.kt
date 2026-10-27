package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Codec
import it.lrapps.webcamlr.protocollo.FormatoVideo
import it.lrapps.webcamlr.protocollo.Temperatura

/** Un formato video in orizzontale (come i formati della fotocamera): il verso lo decide come è tenuto il telefono. */
data class FormatoScelto(val larghezza: Int, val altezza: Int, val fps: Int, val codec: Codec)

/**
 * Il formato chiesto dal computer con `formato` (per esempio i 60 fps per un'app che usa la webcam a 60), adattato a
 * ciò che l'obiettivo attuale sa fare. Vale per la sessione: la qualità si sceglie solo sul computer (prima della
 * richiesta vale [SceltaFormato.diSerie]). Come FormatoRichiesto.swift.
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

/**
 * Perché il video inviato è più basso del formato chiesto (dal computer o, prima, quello di serie): per la riga
 * «Qualità» delle Impostazioni e «Formato» dei Dettagli, così i numeri tornano. Come `MotivoRiduzioneFormato` dell'iPhone.
 */
enum class MotivoRiduzione { CALORE, BATTERIA, GRATIS, OBIETTIVO }

/** Il formato con cui partire e, se è più basso di quello chiesto, perché. */
data class FormatoConMotivi(val formato: FormatoScelto, val motivi: List<MotivoRiduzione>)

/**
 * Il formato con cui partire: quello di serie o la richiesta del computer, poi i limiti di calore, batteria, Pro e 4K.
 * Dal 27 ottobre (decisione di Ledion) la qualità si sceglie solo sul computer: sul telefono non c'è più una scelta.
 */
object SceltaFormato {
    /** 1.14: il 4K al massimo a 30 fps. */
    const val FPS_MASSIMI_4K = 30

    /** Prima del `formato` del computer: 1080p a 30 fps con WebcamLR Pro, 720p a 30 senza, in H.264. */
    fun diSerie(pro: Boolean): FormatoScelto =
        if (pro) FormatoScelto(1920, 1080, 30, Codec.H264)
        else FormatoScelto(LimitiGratis.LARGHEZZA, LimitiGratis.ALTEZZA, LimitiGratis.FPS, Codec.H264)

    fun effettivo(
        diSerie: FormatoScelto,
        richiesto: FormatoScelto?,
        calore: RiduzioneCalore,
        risparmioBatteria: Boolean,
        pro: Boolean,
    ): FormatoScelto = conMotivi(diSerie, richiesto, null, calore, risparmioBatteria, pro).formato

    /**
     * Come [effettivo], con i motivi per cui si manda meno di quanto chiesto. `chiesto` è la richiesta del computer così
     * come è arrivata (per capire se l'obiettivo, adattando con [FormatoRichiesto.da], è sceso).
     */
    fun conMotivi(
        diSerie: FormatoScelto,
        richiesto: FormatoScelto?,
        chiesto: FormatoVideo?,
        calore: RiduzioneCalore,
        risparmioBatteria: Boolean,
        pro: Boolean,
    ): FormatoConMotivi {
        var (larghezza, altezza, fps, codec) = richiesto ?: diSerie
        val motivi = mutableListOf<MotivoRiduzione>()
        if (richiesto != null && chiesto != null &&
            (altezza < minOf(chiesto.larghezza, chiesto.altezza) || fps < chiesto.fps)
        ) {
            motivi += MotivoRiduzione.OBIETTIVO
        }
        val primaDelCalore = Triple(larghezza, altezza, fps)
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
        if (Triple(larghezza, altezza, fps) != primaDelCalore) motivi += MotivoRiduzione.CALORE
        if (risparmioBatteria && fps > 24) {
            fps = 24
            motivi += MotivoRiduzione.BATTERIA
        }
        if (!pro) {
            val primaDelLimite = Triple(larghezza, altezza, fps)
            larghezza = minOf(larghezza, LimitiGratis.LARGHEZZA)
            altezza = minOf(altezza, LimitiGratis.ALTEZZA)
            fps = minOf(fps, LimitiGratis.FPS)
            if (Triple(larghezza, altezza, fps) != primaDelLimite) motivi += MotivoRiduzione.GRATIS
        }
        if (larghezza >= 3840 && fps > FPS_MASSIMI_4K) {
            // Il 4K al massimo a 30 fps; il codec chiesto dal computer si rispetta (sa cosa decodifica).
            fps = FPS_MASSIMI_4K
            if (MotivoRiduzione.OBIETTIVO !in motivi) motivi += MotivoRiduzione.OBIETTIVO
        }
        return FormatoConMotivi(FormatoScelto(larghezza, altezza, fps.coerceIn(1, 60), codec), motivi)
    }

    /**
     * I motivi da mostrare se il video inviato è più basso di quello chiesto dal computer (o di quello di serie, prima
     * che lo chieda); `null` se si manda proprio quello. Più basso senza un motivo noto: l'obiettivo non ci arriva.
     */
    fun motiviMostrati(inviato: FormatoVideo, chiesto: FormatoVideo?, pro: Boolean, motivi: List<MotivoRiduzione>): List<MotivoRiduzione>? {
        val serie = diSerie(pro)
        val latoChiesto = chiesto?.let { minOf(it.larghezza, it.altezza) } ?: serie.altezza
        val fpsChiesti = chiesto?.fps ?: serie.fps
        if (minOf(inviato.larghezza, inviato.altezza) >= latoChiesto && inviato.fps >= fpsChiesti) return null
        return motivi.ifEmpty { listOf(MotivoRiduzione.OBIETTIVO) }
    }
}
