package it.lrapps.webcamlr.android.logica

import kotlin.math.abs
import kotlin.math.hypot

/** Un rettangolo normalizzato (0–1, origine in alto a sinistra). */
data class Rettangolo(val sinistra: Float, val alto: Float, val destra: Float, val basso: Float) {
    val larghezza: Float get() = destra - sinistra
    val altezza: Float get() = basso - alto
    val centroX: Float get() = (sinistra + destra) / 2
    val centroY: Float get() = (alto + basso) / 2
    val area: Float get() = larghezza * altezza

    fun unione(altro: Rettangolo) = Rettangolo(
        minOf(sinistra, altro.sinistra), minOf(alto, altro.alto), maxOf(destra, altro.destra), maxOf(basso, altro.basso),
    )

    /** Lo stesso rettangolo nel video specchiato da sinistra a destra. */
    fun specchiato() = Rettangolo(1f - destra, alto, 1f - sinistra, basso)
}

/**
 * I volti trovati in un fotogramma del video (prima dell'inquadratura automatica), con quando sono stati trovati
 * (millisecondi, orologio monotono) e con quale specchio: se lo specchio cambia nel frattempo si girano.
 */
data class VoltiTrovati(val rettangoli: List<Rettangolo>, val quando: Long, val specchiati: Boolean) {
    fun per(specchia: Boolean): List<Rettangolo> = if (specchia == specchiati) rettangoli else rettangoli.map { it.specchiato() }

    /** Il volto principale: il più grande (il più vicino). */
    fun principale(specchia: Boolean): Rettangolo? = per(specchia).maxByOrNull { it.area }
}

/**
 * P04 Inquadratura automatica (come InquadraturaAutomatica.swift): uno zoom digitale che tiene i volti al centro del
 * video, con movimenti morbidi.
 *
 * - Bersaglio: l'unione dei volti con aria attorno (il volto alto circa un terzo del riquadro) e un po' sopra il
 *   centro; zoom da 1× a 1,6×.
 * - Zona morta: il bersaglio cambia solo se si sposta di più del 6% o lo zoom di più dell'8%.
 * - Molla smorzata in modo critico su centro e zoom; nessun volto per 2 secondi: si torna piano all'inquadratura intera.
 * - Spenta mentre è zoomata: torna morbida all'inquadratura intera, poi si spegne del tutto.
 *
 * [passo] gira sul thread che disegna, una volta per fotogramma; [acceso] si cambia da qualsiasi thread.
 */
class Inquadratura {
    /** Centro del riquadro (normalizzato, origine in alto) e zoom. */
    data class Riquadro(val x: Float = 0.5f, val y: Float = 0.5f, val zoom: Float = 1f) {
        val intero: Boolean get() = zoom < 1.002f

        /** Da un punto del video ritagliato al punto del video intero. */
        fun primaDelloZoom(px: Float, py: Float): Pair<Float, Float> =
            (x + (px - 0.5f) / zoom).coerceIn(0f, 1f) to (y + (py - 0.5f) / zoom).coerceIn(0f, 1f)
    }

    @Volatile var acceso = false
        set(valore) {
            if (field && !valore) inRitorno = true
            if (valore) inRitorno = false
            field = valore
        }
    @Volatile private var inRitorno = false

    /** L'ultimo riquadro uscito (per il tocco del fuoco), da qualsiasi thread. */
    @Volatile var uscito = Riquadro()
        private set

    val attivo: Boolean get() = acceso || inRitorno

    private var attuale = Riquadro()
    private var vx = 0f
    private var vy = 0f
    private var vz = 0f
    private var bersaglio = Riquadro()
    private var ultimoVolto = Long.MIN_VALUE
    private var ultimaAnalisi = Long.MIN_VALUE

    /** Un fotogramma: `dt` in secondi dal precedente; `volti` l'ultimo risultato dell'analisi (anche vecchio). */
    fun passo(volti: VoltiTrovati?, specchia: Boolean, adesso: Long, dt: Float): Riquadro {
        val passoTempo = if (dt.isFinite() && dt > 0f) minOf(dt, 0.1f) else 1f / 30
        val accesoOra = acceso
        if (accesoOra && volti != null && adesso - volti.quando < 1_000 && volti.quando != ultimaAnalisi) {
            ultimaAnalisi = volti.quando
            val rettangoli = volti.per(specchia)
            if (rettangoli.isNotEmpty()) {
                ultimoVolto = adesso
                val nuovo = riquadroPer(rettangoli)
                val soglia = 0.06f / bersaglio.zoom
                if (abs(nuovo.x - bersaglio.x) > soglia || abs(nuovo.y - bersaglio.y) > soglia ||
                    abs(nuovo.zoom - bersaglio.zoom) / bersaglio.zoom > 0.08f
                ) {
                    bersaglio = nuovo
                }
            }
        }
        val senzaVolti = !accesoOra || ultimoVolto == Long.MIN_VALUE || adesso - ultimoVolto > 2_000
        if (senzaVolti) bersaglio = Riquadro()

        val omega = if (senzaVolti) 1.3f else 2.8f
        var x = attuale.x
        var y = attuale.y
        var zoom = attuale.zoom
        molla(x, vx, bersaglio.x, omega, passoTempo).let { (v, vel) -> x = v; vx = vel }
        molla(y, vy, bersaglio.y, omega, passoTempo).let { (v, vel) -> y = v; vy = vel }
        molla(zoom, vz, bersaglio.zoom, omega, passoTempo).let { (v, vel) -> zoom = v; vz = vel }
        zoom = zoom.coerceIn(1f, ZOOM_MASSIMO)
        val meta = 0.5f / zoom
        x = x.coerceIn(meta, 1f - meta)
        y = y.coerceIn(meta, 1f - meta)
        attuale = Riquadro(x, y, zoom)

        val ferma = abs(vx) < 0.0005f && abs(vy) < 0.0005f && abs(vz) < 0.0005f
        if (attuale.intero) {
            if (!accesoOra && ferma) {
                inRitorno = false
                attuale = Riquadro()
                vx = 0f; vy = 0f; vz = 0f
            }
            uscito = Riquadro()
            return uscito
        }
        uscito = attuale
        return attuale
    }

    /** Specchio cambiato dal vivo: lo stato si specchia, così la molla non attraversa tutto il fotogramma. */
    fun specchioCambiato() {
        attuale = attuale.copy(x = 1f - attuale.x)
        bersaglio = bersaglio.copy(x = 1f - bersaglio.x)
        vx = -vx
        uscito = if (uscito.intero) uscito else uscito.copy(x = 1f - uscito.x)
    }

    /** Altro obiettivo o telefono girato: si riparte dall'inquadratura intera. */
    fun azzera() {
        attuale = Riquadro()
        bersaglio = Riquadro()
        vx = 0f; vy = 0f; vz = 0f
        ultimoVolto = Long.MIN_VALUE
        uscito = Riquadro()
    }

    companion object {
        const val ZOOM_MASSIMO = 1.6f

        /** Il riquadro che contiene tutti i volti con aria attorno. */
        fun riquadroPer(volti: List<Rettangolo>): Riquadro {
            val unione = volti.reduce { a, b -> a.unione(b) }
            val necessario = maxOf(unione.altezza * 3.2f, unione.larghezza * 2.2f, 1f / ZOOM_MASSIMO)
            val zoom = (1f / necessario).coerceIn(1f, ZOOM_MASSIMO)
            // Il volto un po' sopra il centro: il centro del riquadro scende (origine in alto).
            return Riquadro(unione.centroX, unione.centroY + 0.12f / zoom, zoom)
        }

        private fun molla(valore: Float, velocita: Float, verso: Float, omega: Float, dt: Float): Pair<Float, Float> {
            val accelerazione = omega * omega * (verso - valore) - 2 * omega * velocita
            val nuovaVelocita = velocita + accelerazione * dt
            return (valore + nuovaVelocita * dt) to nuovaVelocita
        }
    }
}

/**
 * P08 Luce sul volto (come `seguiLuce` di FunzioniVolto.swift): il punto dell'esposizione segue il volto, levigato,
 * al massimo due volte al secondo e solo se il volto si è spostato abbastanza (o ogni 3 secondi). Senza volto per
 * 2 secondi si torna all'esposizione di sistema. Restituisce il rettangolo da dare alla fotocamera (nel video), oppure
 * [Lascia] per tornare all'automatico, oppure `null` per non cambiare nulla.
 */
class SeguiLuce {
    sealed interface Azione
    data class Esponi(val volto: Rettangolo) : Azione
    data object Lascia : Azione

    private var centro: Pair<Float, Float>? = null
    private var applicato: Pair<Float, Float>? = null
    private var ultimaLuce = Long.MIN_VALUE
    private var ultimoVolto = Long.MIN_VALUE

    fun considera(volto: Rettangolo?, adesso: Long): Azione? {
        if (volto == null) {
            if (applicato != null && (ultimoVolto == Long.MIN_VALUE || adesso - ultimoVolto > 2_000)) {
                azzera()
                return Lascia
            }
            return null
        }
        ultimoVolto = adesso
        val nuovo = volto.centroX to volto.centroY
        val levigato = centro?.let { (x, y) -> (x + (nuovo.first - x) * 0.35f) to (y + (nuovo.second - y) * 0.35f) } ?: nuovo
        centro = levigato
        if (ultimaLuce != Long.MIN_VALUE && adesso - ultimaLuce < 500) return null
        val spostato = applicato?.let { (x, y) -> hypot(x - levigato.first, y - levigato.second) > 0.06f } ?: true
        if (!spostato && adesso - ultimaLuce < 3_000) return null
        applicato = levigato
        ultimaLuce = adesso
        val mezzaL = volto.larghezza / 2
        val mezzaA = volto.altezza / 2
        return Esponi(Rettangolo(levigato.first - mezzaL, levigato.second - mezzaA, levigato.first + mezzaL, levigato.second + mezzaA))
    }

    /** Specchio, obiettivo o rotazione cambiati: si riparte dal primo volto nuovo. */
    fun azzera() {
        centro = null
        applicato = null
        ultimaLuce = Long.MIN_VALUE
    }
}

/**
 * P11 Postura (come FunzioniVolto.swift): «molto vicino» con il volto più alto del 45% del fotogramma per più di
 * 10 secondi; «uscito dall'inquadratura» senza volto per più di 5 secondi mentre si è in onda. Un promemoria ogni
 * 3 minuti al massimo. I promemoria restano sul telefono: non viaggiano.
 */
class ControlloPostura {
    enum class Avviso { VICINO, FUORI }

    private var vicinoDa: Long? = null
    private var fuoriDa: Long? = null
    private var ultimoAvviso: Long? = null

    /** Il promemoria da mostrare ora, o `null`. */
    fun considera(volto: Rettangolo?, inOnda: Boolean, adesso: Long): Avviso? {
        if (volto != null) {
            fuoriDa = null
            if (volto.altezza > SOGLIA_VICINO) {
                if (vicinoDa == null) vicinoDa = adesso
            } else if (volto.altezza < SOGLIA_VICINO - 0.05f) {
                vicinoDa = null
            }
        } else {
            vicinoDa = null
            fuoriDa = if (inOnda) fuoriDa ?: adesso else null
        }
        val tipo = when {
            vicinoDa != null && adesso - vicinoDa!! > 10_000 -> Avviso.VICINO
            fuoriDa != null && adesso - fuoriDa!! > 5_000 -> Avviso.FUORI
            else -> return null
        }
        vicinoDa = null
        fuoriDa = null
        val ultimo = ultimoAvviso
        if (ultimo != null && adesso - ultimo < 180_000) return null
        ultimoAvviso = adesso
        return tipo
    }

    /** Il tempo senza video (pausa, fotocamera ferma) non conta. */
    fun azzera() {
        vicinoDa = null
        fuoriDa = null
    }

    companion object {
        const val SOGLIA_VICINO = 0.45f
    }
}
