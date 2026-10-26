package it.lrapps.webcamlr.android.logica

/** Le due strade verso il computer: la rete (Wi-Fi, hotspot, Wi-Fi diretto) e il cavo (Tethering USB). */
enum class Strada(val valore: String) {
    WIFI("wifi"),
    CAVO("cavo");

    val altra: Strada get() = if (this == WIFI) CAVO else WIFI
}

/** I valori di `comando.collegamento` e di `stato.collegamento.preferenza` (Protocollo.md). */
object PreferenzeCollegamento {
    const val AUTOMATICO = "automatico"
    const val WIFI = "wifi"
    const val CAVO = "cavo"
    val TUTTE = listOf(AUTOMATICO, WIFI, CAVO)

    /** Un valore sconosciuto non cambia nulla (regola «Valori sconosciuti»). */
    fun valida(valore: String?): String? = valore?.takeIf { it in TUTTE }

    fun strada(preferenza: String): Strada? = when (preferenza) {
        WIFI -> Strada.WIFI
        CAVO -> Strada.CAVO
        else -> null
    }
}

/**
 * La regola del collegamento (Documenti/Interfaccia finale.md, «Automatico», decisa da Ledion: niente sbalzi).
 *
 * - La strada si sceglie all'inizio (la più veloce: vince il primo indirizzo che risponde) e poi resta quella.
 * - In automatico si cambia solo se la strada in uso si stacca, o se si attacca il cavo durante il Wi-Fi (un passaggio).
 * - Mai per la latenza misurata.
 * - Dopo un cambio, niente cambi per [pausaMs] (anche se il cavo va e viene); la strada persa fa eccezione, se no il
 *   video si fermerebbe.
 * - Preferenza manuale: resta quella; se si stacca si usa l'altra solo per non perdere il video e si torna alla
 *   scelta appena è di nuovo disponibile (passata la pausa).
 *
 * Logica pura, senza Android: i tempi arrivano da fuori (millisecondi di un orologio che non torna indietro).
 */
class RegolaCollegamento(private val pausaMs: Long = PAUSA_MS) {
    var preferenza: String = PreferenzeCollegamento.AUTOMATICO
        private set

    /** La strada del collegamento in uso (o dell'ultimo, durante una riconnessione); null prima del primo. */
    var attiva: Strada? = null
        private set

    private var ultimoCambio: Long? = null
    private var disponibili: Set<Strada>? = null
    /** Il cavo è comparso durante il Wi-Fi: il gesto dell'utente che in automatico vale un passaggio. */
    private var cavoAttaccato = false
    private val nonPrimaDi = HashMap<Strada, Long>()
    private val fallimenti = HashMap<Strada, Int>()

    /** Vero se la preferenza è cambiata. Un valore sconosciuto non cambia nulla. */
    fun impostaPreferenza(nuova: String): Boolean {
        val valida = PreferenzeCollegamento.valida(nuova) ?: return false
        if (valida == preferenza) return false
        preferenza = valida
        // Una scelta dell'utente: la strada scelta si può riprovare subito.
        PreferenzeCollegamento.strada(valida)?.let { sblocca(it) }
        return true
    }

    /** Il collegamento è accettato (il primo, una riconnessione o un passaggio) su questa strada. */
    fun collegato(strada: Strada, adesso: Long) {
        if (attiva != null && attiva != strada) ultimoCambio = adesso
        if (strada == Strada.CAVO) cavoAttaccato = false
        sblocca(strada)
        attiva = strada
    }

    /** Le strade che raggiungono il computer adesso. La prima volta fa solo da riferimento: il cavo c'era già. */
    fun disponibilita(nuove: Set<Strada>) {
        val prima = disponibili
        if (prima != null) {
            if (Strada.CAVO in nuove && Strada.CAVO !in prima && attiva == Strada.WIFI) cavoAttaccato = true
            // Una strada che ritorna si può riprovare, anche dopo tre tentativi non riusciti.
            for (strada in nuove) if (strada !in prima) sblocca(strada)
        }
        if (Strada.CAVO !in nuove) cavoAttaccato = false
        disponibili = nuove.toSet()
    }

    /** Il passaggio a questa strada non è riuscito: si riprova dopo la pausa; dopo tre volte solo se la strada torna. */
    fun tentativoFallito(strada: Strada, adesso: Long) {
        val volte = (fallimenti[strada] ?: 0) + 1
        fallimenti[strada] = volte
        nonPrimaDi[strada] = if (volte >= TENTATIVI_MASSIMI) Long.MAX_VALUE else adesso + pausaMs
    }

    /**
     * Dove passare adesso, oppure null per restare. `sceltaUtente`: subito dopo una preferenza scelta dall'utente
     * (dal telefono o dal computer), che non aspetta la pausa.
     */
    fun decidi(adesso: Long, sceltaUtente: Boolean = false): Strada? {
        val inUso = attiva ?: return null
        val strade = disponibili ?: return null
        val altra = inUso.altra
        if (altra !in strade) return null
        // La strada in uso si è staccata: l'altra subito, per non perdere il video.
        if (inUso !in strade) return altra.takeIf { (nonPrimaDi[it] ?: Long.MIN_VALUE) != Long.MAX_VALUE }
        if ((nonPrimaDi[altra] ?: Long.MIN_VALUE) > adesso) return null
        val inPausa = ultimoCambio?.let { adesso - it < pausaMs } ?: false
        if (inPausa && !sceltaUtente) return null
        return when (preferenza) {
            PreferenzeCollegamento.WIFI -> Strada.WIFI.takeIf { inUso == Strada.CAVO }
            PreferenzeCollegamento.CAVO -> Strada.CAVO.takeIf { inUso == Strada.WIFI }
            else -> Strada.CAVO.takeIf { inUso == Strada.WIFI && cavoAttaccato && !sceltaUtente }
        }
    }

    /**
     * Per un collegamento nuovo: la strada scelta dall'utente, se raggiunge il computer; null = tutte insieme, vince
     * la più veloce.
     */
    fun stradaIniziale(strade: Set<Strada>): Strada? = PreferenzeCollegamento.strada(preferenza)?.takeIf { it in strade }

    private fun sblocca(strada: Strada) {
        nonPrimaDi.remove(strada)
        fallimenti.remove(strada)
    }

    companion object {
        /** Dopo un cambio, niente cambi automatici per 30 secondi. */
        const val PAUSA_MS = 30_000L
        const val TENTATIVI_MASSIMI = 3

        /** «più veloce ora»: la strada con la latenza più bassa tra quelle misurate (solo un'informazione). */
        fun piuVeloce(misure: Map<Strada, Int>): Strada? = misure.minByOrNull { it.value }?.key
    }
}

/** Indirizzi IPv4 e sottoreti, per sapere da quale interfaccia del telefono si raggiunge un indirizzo del computer. */
object Sottoreti {
    /** L'indirizzo IPv4 in un intero (192.168.1.20 → 0xC0A80114); null se non è un IPv4 scritto con i punti. */
    fun numero(indirizzo: String): Int? {
        val parti = indirizzo.trim().split('.')
        if (parti.size != 4) return null
        var risultato = 0
        for (parte in parti) {
            val valore = parte.toIntOrNull() ?: return null
            if (valore !in 0..255) return null
            risultato = (risultato shl 8) or valore
        }
        return risultato
    }

    /** Vero se `a` e `b` stanno nella stessa sottorete di `prefisso` bit. */
    fun stessa(a: Int, b: Int, prefisso: Int): Boolean {
        if (prefisso <= 0) return true
        if (prefisso >= 32) return a == b
        val maschera = -1 shl (32 - prefisso)
        return (a and maschera) == (b and maschera)
    }
}
