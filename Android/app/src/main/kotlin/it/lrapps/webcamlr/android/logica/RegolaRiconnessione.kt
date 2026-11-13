package it.lrapps.webcamlr.android.logica

/**
 * Collaudo 20 (t08 B1–B3, t13 B5–B6): quando riprovare e come leggere una chiusura arrivata prima del `benvenuto`.
 *
 * Un computer che sparisce mentre il telefono era collegato non fa arrendere il telefono: dopo i primi tentativi fitti
 * (gli stessi 8,5 secondi di prima) si continua con un'attesa che cresce fino a [ATTESA_MASSIMA_MS], finché l'utente
 * non tocca «Scollega» o «Riprova ora». Il foglio d'errore resta per i rifiuti veri.
 */
object RegolaRiconnessione {
    /** I tentativi fitti dell'inizio: dopo questi, al primo collegamento, ci si ferma e si dice cosa fare. */
    const val TENTATIVI_FITTI = 5

    /** L'attesa più lunga tra due tentativi quando il computer non torna. */
    const val ATTESA_MASSIMA_MS = 15_000L

    /** L'attesa prima del tentativo numero [tentativo] (da 1): 0,5 · 1 · 2 · 2 · 3 s, poi 5 · 10 · 15 · 15… */
    fun attesaMs(tentativo: Int): Long = when {
        tentativo <= 1 -> 500L
        tentativo == 2 -> 1_000L
        tentativo < TENTATIVI_FITTI -> 2_000L
        tentativo == TENTATIVI_FITTI -> 3_000L
        tentativo == TENTATIVI_FITTI + 1 -> 5_000L
        tentativo == TENTATIVI_FITTI + 2 -> 10_000L
        else -> ATTESA_MASSIMA_MS
    }

    /** Vero se, dopo i tentativi fitti, si continua a riprovare da soli: solo se il telefono era già stato collegato. */
    fun continua(tentativiFatti: Int, giaCollegato: Boolean): Boolean = tentativiFatti < TENTATIVI_FITTI || giaCollegato

    /**
     * Il computer chiude ogni domanda «Consentire…?» dopo 60 secondi (Windows e Mac), con lo stesso `arrivederci` del
     * «Non consentire». Un `arrivederci` arrivato così tardi è un tempo scaduto, non un no. Margine largo: sul telefono
     * l'`approvazione` può essere letta qualche secondo dopo il suo arrivo (thread principale occupato).
     */
    const val SOGLIA_SENZA_RISPOSTA_MS = 45_000L

    /** Come leggere la chiusura di un collegamento. */
    enum class Lettura {
        /** Sul computer qualcuno ha risposto «Non consentire». */
        RIFIUTATO_IN_CONFERMA,

        /** Nessuno ha risposto alla domanda sul computer entro il suo tempo. */
        CONFERMA_SENZA_RISPOSTA,

        /** Il computer ha detto `arrivederci` prima del `benvenuto`, senza chiedere il codice: non accetta il telefono. */
        NON_ACCETTATO,

        /** Il resto: rete persa, presa morta, computer che chiude dopo il benvenuto… si decide come sempre. */
        ALTRO,
    }

    /**
     * @param dalComputer il computer ha chiuso di proposito (`arrivederci`)
     * @param tempoScaduto il telefono non ha avuto il `benvenuto` in tempo (anche dopo la richiesta del codice)
     * @param accolto il `benvenuto` di questo collegamento era già arrivato
     * @param msDallaRichiestaDelCodice da quanto il computer aveva chiesto il codice; `null` se non l'aveva chiesto
     */
    fun leggi(dalComputer: Boolean, tempoScaduto: Boolean, accolto: Boolean, msDallaRichiestaDelCodice: Long?): Lettura = when {
        accolto -> Lettura.ALTRO
        msDallaRichiestaDelCodice != null && dalComputer ->
            if (msDallaRichiestaDelCodice >= SOGLIA_SENZA_RISPOSTA_MS) Lettura.CONFERMA_SENZA_RISPOSTA else Lettura.RIFIUTATO_IN_CONFERMA
        msDallaRichiestaDelCodice != null && tempoScaduto -> Lettura.CONFERMA_SENZA_RISPOSTA
        // In attesa del codice ma per la rete (o una presa morta): non è un no, si riprova (t08 B2 e B3).
        msDallaRichiestaDelCodice != null -> Lettura.ALTRO
        dalComputer -> Lettura.NON_ACCETTATO
        else -> Lettura.ALTRO
    }
}
