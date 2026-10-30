package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.MotiviPausa
import it.lrapps.webcamlr.protocollo.Servizio

/** Un'attesa pianificata che si può annullare. */
fun interface Annullabile {
    fun annulla()
}

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
 * - `nessuna-app`: DISATTIVATA (decisione del 27 ottobre, dopo la prima prova vera). Il telefono non va più in pausa
 *   da solo perché nessuna app usa la webcam o perché la finestra del computer è ridotta o coperta: il video continua
 *   finché l'app del computer è aperta e si ferma solo quando si chiude (il collegamento cade). Con l'Apple ID gratuito
 *   sul Mac nessuna app usa mai la webcam virtuale, e spegnere e riaccendere la fotocamera lasciava la sessione
 *   incastrata. `anteprima` e `in-onda` si ricevono ancora (servono altrove); qui non decidono più nulla.
 *
 * Tutto sullo stesso thread (quello principale nell'app). `pianifica(ms, azione)` esegue l'azione più tardi sullo
 * stesso thread; nei test è finta.
 */
class DecisorePausa(
    private val pianifica: (Long, () -> Unit) -> Annullabile,
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
    private var anteprimaRicevuta = false
    private var anteprimaVisibile = false
    private var appInOnda = false
    private var trattenuta = false
    private var attesaNessunaApp: Annullabile? = null

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

    fun anteprima(visibile: Boolean) {
        anteprimaRicevuta = true
        anteprimaVisibile = visibile
        valutaNessunaApp()
    }

    fun inOnda(attivo: Boolean) {
        appInOnda = attivo
        valutaNessunaApp()
    }

    /** Nuovo `benvenuto`: si riparte come se il computer non avesse detto nulla (manderà la sua `anteprima`). */
    fun nuovoCollegamento() {
        attesaNessunaApp?.annulla()
        attesaNessunaApp = null
        anteprimaRicevuta = false
        anteprimaVisibile = false
        appInOnda = false
        nessunaApp = false
    }

    /** Mentre qualcuno guarda il video sul telefono (per esempio «Prova la webcam») niente pausa per «nessuna app». */
    fun trattieni(attiva: Boolean) {
        trattenuta = attiva
        valutaNessunaApp()
    }

    private fun valutaNessunaApp() {
        // Decisione del 27 ottobre: niente più pausa «nessuna app» (vedi sopra). Se una pausa del genere fosse
        // rimasta da prima, la si toglie.
        if (!PAUSA_NESSUNA_APP_ATTIVA) {
            attesaNessunaApp?.annulla()
            attesaNessunaApp = null
            if (nessunaApp) {
                nessunaApp = false
                suCambio()
            }
            return
        }
        val nessunoGuarda = inFunzione && anteprimaRicevuta && !anteprimaVisibile && !appInOnda && !trattenuta
        if (!nessunoGuarda) {
            attesaNessunaApp?.annulla()
            attesaNessunaApp = null
            if (nessunaApp) {
                nessunaApp = false
                suCambio()
            }
            return
        }
        if (nessunaApp || attesaNessunaApp != null) return
        attesaNessunaApp = pianifica(Servizio.SECONDI_PRIMA_DELLA_PAUSA * 1000L) {
            attesaNessunaApp = null
            if (inFunzione && !nessunaApp) {
                nessunaApp = true
                suCambio()
            }
        }
    }

    private companion object {
        /** Decisione del 27 ottobre: spenta. Il codice resta per poterla riaccendere se un giorno servirà. */
        const val PAUSA_NESSUNA_APP_ATTIVA = false
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
