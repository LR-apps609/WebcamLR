package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.MotiviPausa

/**
 * Le pause del video senza chiudere la sessione (protocollo, *Pausa intelligente*; come GestorePausa di
 * iPhone/Sorgenti/PausaTelefono.swift). Decide solo il motivo: cosa fermare lo fa la sessione (`suCambio`).
 *
 * - `faccia-in-giu`: telefono appoggiato con lo schermo in giù (gravità oltre 0,9 verso il basso per più di un
 *   secondo); girato di nuovo (sotto 0,7) riprende. La fotocamera resta accesa: la ripresa è immediata.
 * - `utente`: il pulsante «Pausa» di «In onda».
 * - `sottofondo`: l'app non è più in primo piano e il servizio in primo piano non c'è (Android l'ha rifiutato): senza
 *   servizio Android toglie la fotocamera alle app in sottofondo. Con il servizio attivo il video continua e questo
 *   motivo non si usa (protocollo, *Pausa intelligente*). La fotocamera si spegne; al ritorno si riaccende.
 * - `fotocamera-interrotta`: il sistema ha tolto la fotocamera (un'altra app, un criterio del telefono). Finisce
 *   quando la fotocamera torna disponibile.
 * - `nessuna-app` (Qualità 18, pausa automatica): **decide il computer** con il messaggio `pausa-automatica`, perché
 *   solo lui sa se un'app usa la webcam virtuale e se qualcuno guarda la sua finestra (Protocollo.md, «Pausa
 *   automatica»). Vero: fotocamera e codifica ferme, collegamento vivo. Falso, o `in-onda` vero: si riprende subito,
 *   da un fotogramma chiave. Il telefono non decide più da solo con `anteprima` e `in-onda` (la vecchia regola, spenta
 *   il 27 ottobre: con l'Apple ID gratuito sul Mac nessuna app risultava mai in uso). Un computer vecchio non manda
 *   `pausa-automatica`: il telefono non va mai in pausa per questo motivo.
 *
 * Tutto sullo stesso thread (quello principale nell'app). Nessun tempo qui: quello della pausa automatica lo conta il
 * computer.
 */
class DecisorePausa(
    private val suCambio: () -> Unit,
) {
    var facciaInGiu = false
        private set
    var nessunaApp = false
        private set
    var utente = false
        private set
    var sottofondo = false
        private set
    var fotocameraInterrotta = false
        private set

    /** «Faccia in giù = pausa» nelle Impostazioni (di serie acceso). */
    var facciaInGiuAbilitata = true
        set(valore) {
            field = valore
            if (!valore) {
                giuDa = null
                if (facciaInGiu) {
                    facciaInGiu = false
                    suCambio()
                }
            }
        }

    /**
     * Il motivo per `stato.pausa`, `null` se il video va. Prima quello che toglie la fotocamera (il computer deve
     * sapere perché riprendere non dipende dal telefono in mano), poi i gesti scelti dall'utente.
     */
    val motivo: String?
        get() = when {
            sottofondo -> MotiviPausa.SOTTOFONDO
            fotocameraInterrotta -> MotiviPausa.FOTOCAMERA_INTERROTTA
            facciaInGiu -> MotiviPausa.FACCIA_IN_GIU
            utente -> MotiviPausa.UTENTE
            nessunaApp -> MotiviPausa.NESSUNA_APP
            else -> null
        }

    /**
     * `nessuna-app`, `sottofondo`, `fotocamera-interrotta`: la fotocamera va spenta (o è già stata tolta), non solo il
     * video fermato. Finché vale, la sessione non prova a riaccenderla.
     */
    val fotocameraSpenta: Boolean get() = nessunaApp || sottofondo || fotocameraInterrotta

    private var inFunzione = false
    private var giuDa: Long? = null
    /** Un'app usa la webcam con questo telefono (`in-onda` dal computer, in questo collegamento). */
    private var appInOnda = false

    fun avvia() {
        inFunzione = true
    }

    /** Fine della sessione: in silenzio, non c'è nulla da riprendere. */
    fun ferma() {
        inFunzione = false
        facciaInGiu = false
        utente = false
        sottofondo = false
        fotocameraInterrotta = false
        giuDa = null
        nuovoCollegamento()
    }

    fun impostaPausaUtente(attiva: Boolean) {
        if (!inFunzione || attiva == utente) return
        utente = attiva
        suCambio()
    }

    /** L'app è andata in sottofondo senza servizio in primo piano (vero) o è tornata in primo piano (falso). */
    fun impostaSottofondo(attivo: Boolean) {
        if (!inFunzione || attivo == sottofondo) return
        sottofondo = attivo
        suCambio()
    }

    /** Il sistema ha tolto la fotocamera (vero) o la fotocamera è tornata (falso). */
    fun impostaFotocameraInterrotta(attiva: Boolean) {
        if (!inFunzione || attiva == fotocameraInterrotta) return
        fotocameraInterrotta = attiva
        suCambio()
    }

    /**
     * Messaggio `pausa-automatica` dal computer. Vero: nessuna app usa la webcam e nessuno guarda il video da un po', la
     * fotocamera si spegne. Falso: il video serve di nuovo, si riprende subito.
     */
    fun pausaAutomatica(attiva: Boolean) {
        // Un'app che usa la webcam vince sempre: in onda non si va in pausa, anche se i messaggi si incrociano.
        val nuova = attiva && inFunzione && !appInOnda
        if (nuova == nessunaApp) return
        nessunaApp = nuova
        suCambio()
    }

    /** Messaggio `in-onda`: un'app che apre la webcam toglie subito la pausa automatica. */
    fun inOnda(attivo: Boolean) {
        appInOnda = attivo
        if (!attivo || !nessunaApp) return
        nessunaApp = false
        suCambio()
    }

    /**
     * Nuovo `benvenuto`: si riparte come se il computer non avesse detto nulla (dopo il `benvenuto` manda subito il suo
     * `pausa-automatica`). In silenzio: la sessione riaccende da sé la fotocamera.
     */
    fun nuovoCollegamento() {
        appInOnda = false
        nessunaApp = false
    }

    /**
     * Una lettura della gravità: `giu` da -1 (schermo verso l'alto) a +1 (schermo verso il basso), già divisa per g.
     * (Su Android il sensore dà z positivo con lo schermo in su: chi chiama passa −z/g.)
     */
    fun gravita(giu: Double, adesso: Long) {
        if (!inFunzione || !facciaInGiuAbilitata || !giu.isFinite()) return
        if (giu > 0.9) {
            val inizio = giuDa ?: adesso.also { giuDa = it }
            if (!facciaInGiu && adesso - inizio >= 1_000) {
                facciaInGiu = true
                suCambio()
            }
        } else {
            giuDa = null
            if (facciaInGiu && giu < 0.7) {
                facciaInGiu = false
                suCambio()
            }
        }
    }
}
