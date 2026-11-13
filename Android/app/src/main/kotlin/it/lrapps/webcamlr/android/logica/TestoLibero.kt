package it.lrapps.webcamlr.android.logica

/**
 * Collaudo 20 (t13 B1): i campi liberi hanno un tetto. Un testo enorme (un registro incollato, una bozza di 300 000
 * caratteri) mandava in crash «Segnala un bug»: il campo cresceva oltre l'altezza che Compose sa rappresentare, e
 * l'intento per l'app di posta rischiava di superare il limite di Android per i dati tra app.
 */
object TestoLibero {
    /** «Segnala un bug»: circa dieci pagine, più che abbastanza per una descrizione e un pezzo di registro. */
    const val MASSIMO_SEGNALAZIONE = 20_000

    /** I primi [massimo] caratteri, senza spezzare una coppia di surrogati (emoji). Il testo corto resta com'è. */
    fun taglia(testo: String, massimo: Int): String {
        if (testo.length <= massimo) return testo
        val fine = if (massimo > 0 && Character.isHighSurrogate(testo[massimo - 1])) massimo - 1 else massimo
        return testo.substring(0, fine.coerceAtLeast(0))
    }
}
