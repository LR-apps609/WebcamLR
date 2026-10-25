package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Capacita
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.Filtri
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.Regolazioni
import it.lrapps.webcamlr.protocollo.Scritta
import it.lrapps.webcamlr.protocollo.StatoTelefono

/**
 * Gli effetti scelti sul telefono o dal computer (come EffettiVisivi e FunzioniVolto dell'iPhone), restano salvati sul
 * telefono. Valori sempre già nei limiti: chi li costruisce passa da [ModelloEffetti].
 */
data class StatoEffetti(
    /** Uno dei `Filtri`; `naturale` = nessun filtro. */
    val filtro: String = Filtri.NATURALE,
    /** Da -1 a 1, 0 = neutro. */
    val luminosita: Double = 0.0,
    val contrasto: Double = 0.0,
    val saturazione: Double = 0.0,
    val nitidezza: Double = 0.0,
    /** Uno dei `ModiSfondo`. */
    val sfondo: String = ModiSfondo.NESSUNO,
    /** Da 0 a 1: quanto sfocare, o quanto è netto il bordo dello sfondo sostituito. */
    val intensitaSfondo: Double = 0.5,
    /** Quale immagine con «sostituito»: uno di [SfondiPronti]. */
    val sfondoScelto: String = SfondiPronti.STUDIO,
    /** Ritocco della pelle, da 0 (spento) a 1. */
    val pelle: Double = 0.0,
    /** L'ultima intensità usata, per riaccendere il ritocco come l'utente l'aveva lasciato. */
    val ultimaPelle: Double = PELLE_DI_SERIE,
    /** Sottopancia: nome vuoto = nessuna scritta. */
    val nomeScritta: String = "",
    val ruoloScritta: String = "",
    val mostraLogo: Boolean = true,
    val inquadratura: Boolean = false,
    val luceVolto: Boolean = false,
    val postura: Boolean = false,
) {
    val regolazioniNeutre: Boolean get() = luminosita == 0.0 && contrasto == 0.0 && saturazione == 0.0 && nitidezza == 0.0

    /** C'è un sottopancia da disegnare (il logo lo sa chi ha l'immagine). */
    val scrittaVisibile: Boolean get() = nomeScritta.isNotBlank()

    companion object {
        const val PELLE_DI_SERIE = 0.3
        const val LUNGHEZZA_NOME = 40
        const val LUNGHEZZA_RUOLO = 50
    }
}

/** Le immagini pronte per lo sfondo sostituito (la foto la sceglie l'utente). */
object SfondiPronti {
    const val STUDIO = "studio"
    const val SALVIA = "salvia"
    const val FOTO = "foto"
    val TUTTI = listOf(STUDIO, SALVIA, FOTO)
}

/** Cosa sa fare davvero questo telefono, per `capacita` (si dichiara solo ciò che funziona). */
data class FunzioniDisponibili(
    val filtri: Boolean = true,
    /** Maschera della persona pronta (MediaPipe): sfondo sfocato e sostituito. */
    val sfondo: Boolean = false,
    val pelle: Boolean = true,
    val scritta: Boolean = true,
    /** Rilevamento dei volti pronto: inquadratura, luce sul volto, postura. */
    val volti: Boolean = false,
    /** Il microfono si può usare (permesso concesso o ancora da chiedere). */
    val audio: Boolean = false,
)

object ModelloEffetti {
    /** I campi degli effetti di un `comando` (solo quelli presenti), nei limiti. Valori sconosciuti come dice il protocollo. */
    fun applica(stato: StatoEffetti, comando: Comando): StatoEffetti {
        var nuovo = stato
        comando.filtro?.let { nuovo = nuovo.copy(filtro = filtro(it)) }
        comando.regolazioni?.let { r ->
            nuovo = nuovo.copy(
                luminosita = r.luminosita?.let { limita(it, -1.0, 1.0, 0.0) } ?: nuovo.luminosita,
                contrasto = r.contrasto?.let { limita(it, -1.0, 1.0, 0.0) } ?: nuovo.contrasto,
                saturazione = r.saturazione?.let { limita(it, -1.0, 1.0, 0.0) } ?: nuovo.saturazione,
                nitidezza = r.nitidezza?.let { limita(it, -1.0, 1.0, 0.0) } ?: nuovo.nitidezza,
            )
        }
        comando.sfondo?.let { nuovo = nuovo.copy(sfondo = sfondo(it)) }
        comando.intensitaSfondo?.let { nuovo = nuovo.copy(intensitaSfondo = limita(it, 0.0, 1.0, 0.5)) }
        comando.pelle?.let { nuovo = conPelle(nuovo, it) }
        comando.scritta?.let { nuovo = conScritta(nuovo, it.nome, it.ruolo ?: "") }
        comando.inquadratura?.let { nuovo = nuovo.copy(inquadratura = it) }
        comando.luceVolto?.let { nuovo = nuovo.copy(luceVolto = it) }
        comando.postura?.let { nuovo = nuovo.copy(postura = it) }
        return nuovo
    }

    fun filtro(valore: String): String = if (valore in Filtri.TUTTI) valore else Filtri.NATURALE

    fun sfondo(valore: String): String =
        if (valore == ModiSfondo.SFOCATO || valore == ModiSfondo.SOSTITUITO) valore else ModiSfondo.NESSUNO

    fun conPelle(stato: StatoEffetti, valore: Double): StatoEffetti {
        val limitato = limita(valore, 0.0, 1.0, 0.0)
        return stato.copy(pelle = limitato, ultimaPelle = if (limitato > 0.01) limitato else stato.ultimaPelle)
    }

    /** Nome e ruolo tagliati alle lunghezze massime; i caratteri di controllo (a capo compresi) diventano spazi. */
    fun conScritta(stato: StatoEffetti, nome: String, ruolo: String): StatoEffetti =
        stato.copy(
            nomeScritta = pulito(nome).take(StatoEffetti.LUNGHEZZA_NOME),
            ruoloScritta = pulito(ruolo).take(StatoEffetti.LUNGHEZZA_RUOLO),
        )

    private fun pulito(testo: String): String = testo.map { if (it.isISOControl()) ' ' else it }.joinToString("")

    /** Senza Pro restano sfondo sfocato, luce sul volto e postura; il resto si spegne. */
    fun spegniPro(stato: StatoEffetti): StatoEffetti = stato.copy(
        filtro = Filtri.NATURALE,
        luminosita = 0.0, contrasto = 0.0, saturazione = 0.0, nitidezza = 0.0,
        sfondo = if (stato.sfondo == ModiSfondo.SOSTITUITO) ModiSfondo.NESSUNO else stato.sfondo,
        pelle = 0.0,
        nomeScritta = "", ruoloScritta = "",
        mostraLogo = false,
        inquadratura = false,
    )

    /**
     * Un telefono che sa fare gli effetti manda sempre in `stato` tutti quelli che dichiara in `capacita`: qui solo
     * quelli disponibili, con gli stessi criteri di [completa] per `capacita`.
     */
    fun completa(stato: StatoTelefono, effetti: StatoEffetti, funzioni: FunzioniDisponibili): StatoTelefono {
        var risultato = stato
        if (funzioni.filtri) {
            risultato = risultato.copy(
                filtro = effetti.filtro,
                regolazioni = Regolazioni(effetti.luminosita, effetti.contrasto, effetti.saturazione, effetti.nitidezza),
            )
        }
        if (funzioni.sfondo) risultato = risultato.copy(sfondo = effetti.sfondo, intensitaSfondo = effetti.intensitaSfondo)
        if (funzioni.pelle) risultato = risultato.copy(pelle = effetti.pelle)
        if (funzioni.scritta) {
            val nome = effetti.nomeScritta.trim()
            val ruolo = effetti.ruoloScritta.trim()
            risultato = risultato.copy(scritta = Scritta(nome, if (nome.isEmpty() || ruolo.isEmpty()) null else ruolo))
        }
        if (funzioni.volti) {
            risultato = risultato.copy(inquadratura = effetti.inquadratura, luceVolto = effetti.luceVolto, postura = effetti.postura)
        }
        return risultato
    }

    fun completa(capacita: Capacita, funzioni: FunzioniDisponibili): Capacita = capacita.copy(
        filtri = if (funzioni.filtri) Filtri.TUTTI else null,
        sfondo = if (funzioni.sfondo) true else null,
        pelle = if (funzioni.pelle) true else null,
        scritta = if (funzioni.scritta) true else null,
        inquadratura = if (funzioni.volti) true else null,
        luceVolto = if (funzioni.volti) true else null,
        postura = if (funzioni.volti) true else null,
        audio = funzioni.audio,
    )
}
