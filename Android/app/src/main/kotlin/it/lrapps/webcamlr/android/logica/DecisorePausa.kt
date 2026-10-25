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
 * - `nessuna-app`: `in-onda` falso e `anteprima` falsa da più di 10 secondi; mai se in questo collegamento non è
 *   arrivata nessuna `anteprima` (computer vecchio). Qui la fotocamera si spegne del tutto.
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

    /** Il motivo per `stato.pausa`, `null` se il video va. Prima i gesti scelti dall'utente. */
    val motivo: String?
        get() = when {
            facciaInGiu -> MotiviPausa.FACCIA_IN_GIU
            utente -> MotiviPausa.UTENTE
            nessunaApp -> MotiviPausa.NESSUNA_APP
            else -> null
        }

    /** `nessuna-app`: la fotocamera va spenta, non solo il video fermato. */
    val fotocameraSpenta: Boolean get() = nessunaApp

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
        giuDa = null
        nuovoCollegamento()
    }

    fun impostaPausaUtente(attiva: Boolean) {
        if (!inFunzione || attiva == utente) return
        utente = attiva
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
