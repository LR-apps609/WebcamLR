package it.lrapps.webcamlr.android.dati

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.lrapps.webcamlr.android.logica.ModelloEffetti
import it.lrapps.webcamlr.android.logica.PreferenzeCollegamento
import it.lrapps.webcamlr.android.logica.StatoEffetti
import it.lrapps.webcamlr.android.logica.limita
import it.lrapps.webcamlr.protocollo.Filtri
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.SfondiPronti

/**
 * Le impostazioni dell'app (come le chiavi `@AppStorage` dell'iPhone), salvate in SharedPreferences e osservabili
 * da Compose. Valgono dal prossimo collegamento.
 */
object Impostazioni {
    private lateinit var preferenze: SharedPreferences

    fun prepara(context: Context) {
        preferenze = context.getSharedPreferences("impostazioni", Context.MODE_PRIVATE)
        benvenutoVisto = preferenze.getBoolean("benvenutoVisto", false)
        modalitaAvanzata = preferenze.getBoolean("modalitaAvanzata", false)
        // Dal 27 ottobre la qualità si sceglie solo sul computer: le scelte salvate di prima non valgono più.
        preferenze.edit().remove("risoluzione").remove("fps").remove("codec").apply()
        riduciSeCaldo = preferenze.getBoolean("riduciSeCaldo", true)
        oscuraDaSolo = preferenze.getBoolean("oscuraDaSolo", true)
        risparmioBatteria = preferenze.getBoolean("risparmioBatteria", true)
        griglia = preferenze.getBoolean("griglia", false)
        collegamento = PreferenzeCollegamento.valida(preferenze.getString(CHIAVE_COLLEGAMENTO, null)) ?: PreferenzeCollegamento.AUTOMATICO
    }

    var benvenutoVisto by mutableStateOf(false)
        private set
    var modalitaAvanzata by mutableStateOf(false)
        private set
    var riduciSeCaldo by mutableStateOf(true)
        private set
    var oscuraDaSolo by mutableStateOf(true)
        private set
    var risparmioBatteria by mutableStateOf(true)
        private set
    var griglia by mutableStateOf(false)
        private set
    /** La strada verso il computer: "automatico", "wifi" o "cavo" (anche dal computer, `comando.collegamento`). */
    var collegamento by mutableStateOf(PreferenzeCollegamento.AUTOMATICO)
        private set

    fun impostaBenvenutoVisto(valore: Boolean) { benvenutoVisto = valore; salva("benvenutoVisto", valore) }
    fun impostaModalitaAvanzata(valore: Boolean) { modalitaAvanzata = valore; salva("modalitaAvanzata", valore) }
    fun impostaRiduciSeCaldo(valore: Boolean) { riduciSeCaldo = valore; salva("riduciSeCaldo", valore) }
    fun impostaOscuraDaSolo(valore: Boolean) { oscuraDaSolo = valore; salva("oscuraDaSolo", valore) }
    fun impostaRisparmioBatteria(valore: Boolean) { risparmioBatteria = valore; salva("risparmioBatteria", valore) }
    fun impostaGriglia(valore: Boolean) { griglia = valore; salva("griglia", valore) }
    fun impostaCollegamento(valore: String) {
        val valido = PreferenzeCollegamento.valida(valore) ?: return
        if (valido == collegamento) return
        collegamento = valido
        preferenze.edit().putString(CHIAVE_COLLEGAMENTO, valido).apply()
    }

    /** L'ultimo obiettivo usato ("principale", "frontale"…). */
    var obiettivo: String
        get() = preferenze.getString("obiettivo", "principale") ?: "principale"
        set(valore) = preferenze.edit().putString("obiettivo", valore).apply()

    /** Il nome dell'ultimo computer collegato: al prossimo avvio ci si ricollega da soli se compare (novità 2). */
    var ultimoComputer: String?
        get() = preferenze.getString("ultimoComputer", null)
        set(valore) = preferenze.edit().putString("ultimoComputer", valore).apply()

    /** P6: l'ultimo indirizzo valido scritto a mano, riproposto in «Collega a mano». */
    var ultimoIndirizzo: String
        get() = preferenze.getString("ultimoIndirizzo", null) ?: ""
        set(valore) = preferenze.edit().putString("ultimoIndirizzo", valore).apply()

    /** Passo 9: la descrizione di «Segnala un bug» non ancora inviata (Indietro non la perde). */
    var bozzaSegnalazione: String
        get() = preferenze.getString("bozzaSegnalazione", null) ?: ""
        set(valore) = preferenze.edit().putString("bozzaSegnalazione", valore).apply()

    /** Vero dopo «Invia la segnalazione»: alla prossima apertura la bozza riparte vuota. */
    var bozzaSegnalazioneInviata: Boolean
        get() = preferenze.getBoolean("bozzaSegnalazioneInviata", false)
        set(valore) = salva("bozzaSegnalazioneInviata", valore)

    /** Passo 9: «Includi il registro del collegamento» in «Segnala un bug», acceso di serie. */
    var segnalazioneConRegistro: Boolean
        get() = preferenze.getBoolean("segnalazioneConRegistro", true)
        set(valore) = salva("segnalazioneConRegistro", valore)

    /** La bozza da mostrare aprendo «Segnala un bug»: vuota se l'ultima è già stata inviata. */
    fun bozzaDaRiprendere(): String {
        if (bozzaSegnalazioneInviata) {
            bozzaSegnalazione = ""
            bozzaSegnalazioneInviata = false
        }
        return bozzaSegnalazione
    }

    private fun salva(chiave: String, valore: Boolean) = preferenze.edit().putBoolean(chiave, valore).apply()

    /** Il file delle impostazioni, per chi le osserva (la sessione segue le scelte fatte dall'interfaccia). */
    val file: SharedPreferences get() = preferenze

    // 1.14: lo specchio del video inviato, uno solo, di proprietà della sessione (SessioneTelefono.impostaSpecchio).
    internal var specchioSalvato: Boolean
        get() = preferenze.getBoolean(CHIAVE_SPECCHIO, false)
        set(valore) = preferenze.edit().putBoolean(CHIAVE_SPECCHIO, valore).apply()

    /** P07 «Faccia in giù = pausa», di serie acceso (chiave dell'iPhone). */
    val pausaFacciaInGiu: Boolean get() = preferenze.getBoolean(CHIAVE_FACCIA_IN_GIU, true)

    /** Gli effetti salvati sul telefono (al ricollegamento il computer li legge dal primo `stato`). */
    fun effetti(): StatoEffetti {
        val p = preferenze
        fun d(chiave: String, ripiego: Double) = p.getFloat(chiave, ripiego.toFloat()).toDouble()
        val grezzo = StatoEffetti(
            filtro = ModelloEffetti.filtro(p.getString("effetti.filtro", Filtri.NATURALE) ?: Filtri.NATURALE),
            luminosita = limita(d("effetti.luminosita", 0.0), -1.0, 1.0, 0.0),
            contrasto = limita(d("effetti.contrasto", 0.0), -1.0, 1.0, 0.0),
            saturazione = limita(d("effetti.saturazione", 0.0), -1.0, 1.0, 0.0),
            nitidezza = limita(d("effetti.nitidezza", 0.0), -1.0, 1.0, 0.0),
            sfondo = ModelloEffetti.sfondo(p.getString("effetti.sfondo", ModiSfondo.NESSUNO) ?: ModiSfondo.NESSUNO),
            intensitaSfondo = limita(d("effetti.intensitaSfondo", 0.5), 0.0, 1.0, 0.5),
            sfondoScelto = sfondoSalvato(p.getString("effetti.sfondoScelto", null)),
            pelle = limita(d("effetti.pelle", 0.0), 0.0, 1.0, 0.0),
            ultimaPelle = limita(d("effetti.ultimaPelle", StatoEffetti.PELLE_DI_SERIE), 0.01, 1.0, StatoEffetti.PELLE_DI_SERIE),
            mostraLogo = p.getBoolean("effetti.mostraLogo", true),
            inquadratura = p.getBoolean(CHIAVE_INQUADRATURA, false),
            luceVolto = p.getBoolean(CHIAVE_LUCE_VOLTO, false),
            postura = p.getBoolean(CHIAVE_POSTURA, false),
            // Chi aveva già l'app non ha la chiave: parte anche lui dal calore di serie.
            calore = limita(d("effetti.calore", StatoEffetti.CALORE_DI_SERIE), 0.0, 1.0, StatoEffetti.CALORE_DI_SERIE),
        )
        return ModelloEffetti.conScritta(grezzo, p.getString("effetti.nomeScritta", "") ?: "", p.getString("effetti.ruoloScritta", "") ?: "")
    }

    /**
     * Lo sfondo scelto salvato. Prima degli sfondi dal computer c'erano «salvia» (ora il verde WebcamLR) e «foto»
     * (la foto scelta sul telefono, che resta come immagine personale). Se l'immagine non c'è più vale il primo.
     */
    private fun sfondoSalvato(valore: String?): String = when (valore) {
        "salvia" -> SfondiPronti.LRAPPS
        "foto" -> SfondiPronti.PERSONALE
        null -> SfondiPronti.TUTTI.first()
        else -> if (valore == SfondiPronti.PERSONALE || valore in SfondiPronti.TUTTI) valore else SfondiPronti.TUTTI.first()
    }

    fun salvaEffetti(e: StatoEffetti) {
        preferenze.edit()
            .putString("effetti.filtro", e.filtro)
            .putFloat("effetti.luminosita", e.luminosita.toFloat())
            .putFloat("effetti.contrasto", e.contrasto.toFloat())
            .putFloat("effetti.saturazione", e.saturazione.toFloat())
            .putFloat("effetti.nitidezza", e.nitidezza.toFloat())
            .putString("effetti.sfondo", e.sfondo)
            .putFloat("effetti.intensitaSfondo", e.intensitaSfondo.toFloat())
            .putString("effetti.sfondoScelto", e.sfondoScelto)
            .putFloat("effetti.pelle", e.pelle.toFloat())
            .putFloat("effetti.ultimaPelle", e.ultimaPelle.toFloat())
            .putString("effetti.nomeScritta", e.nomeScritta)
            .putString("effetti.ruoloScritta", e.ruoloScritta)
            .putBoolean("effetti.mostraLogo", e.mostraLogo)
            .putBoolean(CHIAVE_INQUADRATURA, e.inquadratura)
            .putBoolean(CHIAVE_LUCE_VOLTO, e.luceVolto)
            .putBoolean(CHIAVE_POSTURA, e.postura)
            .putFloat("effetti.calore", e.calore.toFloat())
            .apply()
    }

    // Le stesse chiavi dell'iPhone (UserDefaults): le scrive anche l'interfaccia.
    const val CHIAVE_SPECCHIO = "specchia"
    const val CHIAVE_INQUADRATURA = "inquadraturaAutomatica"
    const val CHIAVE_LUCE_VOLTO = "luceVolto"
    const val CHIAVE_POSTURA = "postura"
    const val CHIAVE_FACCIA_IN_GIU = "pausaFacciaInGiu"
    const val CHIAVE_COLLEGAMENTO = "preferenzaCollegamento"
}

/**
 * «Computer conosciuti» (protocollo 2, «Fiducia del telefono verso il computer»): nome del computer → impronta della
 * sua chiave, salvata dopo il primo `benvenuto`. Se un computer con lo stesso nome si presenta con un'altra impronta,
 * il telefono si ferma: va riabbinato con il QR code.
 */
object ComputerConosciuti {
    private lateinit var preferenze: SharedPreferences

    fun prepara(context: Context) {
        preferenze = context.getSharedPreferences("computer_conosciuti", Context.MODE_PRIVATE)
    }

    data class Voce(val nome: String, val impronta: String)

    val tutti: List<Voce>
        get() = preferenze.all.mapNotNull { (nome, valore) -> (valore as? String)?.let { Voce(nome, it) } }
            .sortedBy { it.nome.lowercase() }

    fun impronta(nome: String): String? = preferenze.getString(nome, null)

    fun salva(impronta: String, nome: String) {
        if (impronta(nome) != impronta) preferenze.edit().putString(nome, impronta).apply()
    }

    fun dimentica(nome: String) = preferenze.edit().remove(nome).apply()
}
