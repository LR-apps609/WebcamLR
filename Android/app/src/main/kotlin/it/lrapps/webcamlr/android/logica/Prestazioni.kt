package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Temperatura

/**
 * Il misuratore (riga «Prestazioni» dei Dettagli e registro del collegamento ogni 10 secondi con gli effetti accesi),
 * come sull'iPhone. Una misura per secondo.
 */
data class Prestazioni(
    /** I fotogrammi al secondo usciti davvero dal codificatore. */
    val fps: Double,
    /** Millisecondi medi per fotogramma sul thread GL (effetti, copia per l'analisi, consegna); `null` senza effetti. */
    val msEffetti: Double?,
    /** Maschere della persona al secondo; `null` se lo sfondo è spento. */
    val maschereAlSecondo: Double?,
    /** Il bitrate reale in uscita dal codificatore, in bit al secondo. */
    val bitrate: Long,
    val temperatura: Temperatura,
)

/**
 * Le misure di ogni secondo, mediate su [SECONDI_REGISTRO] secondi per il registro (un solo secondo è troppo
 * ballerino: il bitrate CBR oscilla con i fotogrammi chiave).
 */
class MediaPrestazioni {
    private val elenco = ArrayDeque<Prestazioni>()

    fun aggiungi(misura: Prestazioni) {
        elenco.addLast(misura)
        if (elenco.size > SECONDI_REGISTRO) elenco.removeFirst()
    }

    fun azzera() = elenco.clear()

    /** Vero ogni [SECONDI_REGISTRO] misure: il momento di scrivere nel registro. */
    val piena: Boolean get() = elenco.size >= SECONDI_REGISTRO

    /** La media delle misure raccolte (la temperatura è l'ultima), poi si riparte da capo; `null` se non ce ne sono. */
    fun prendi(): Prestazioni? {
        if (elenco.isEmpty()) return null
        val ultima = elenco.last()
        fun media(valori: List<Double>): Double? = if (valori.isEmpty()) null else valori.average()
        val risultato = Prestazioni(
            fps = elenco.map { it.fps }.average(),
            msEffetti = media(elenco.mapNotNull { it.msEffetti }),
            maschereAlSecondo = media(elenco.mapNotNull { it.maschereAlSecondo }),
            bitrate = elenco.map { it.bitrate }.average().toLong(),
            temperatura = ultima.temperatura,
        )
        elenco.clear()
        return risultato
    }

    companion object {
        const val SECONDI_REGISTRO = 10
    }
}
