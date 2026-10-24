package it.lrapps.webcamlr.android.dati

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.lrapps.webcamlr.protocollo.Codec

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
        risoluzione = preferenze.getString("risoluzione", "1080p") ?: "1080p"
        fps = preferenze.getInt("fps", 30)
        codec = preferenze.getString("codec", "h264") ?: "h264"
        specchia = preferenze.getBoolean("specchia", false)
        riduciSeCaldo = preferenze.getBoolean("riduciSeCaldo", true)
        oscuraDaSolo = preferenze.getBoolean("oscuraDaSolo", true)
        risparmioBatteria = preferenze.getBoolean("risparmioBatteria", true)
        griglia = preferenze.getBoolean("griglia", false)
    }

    var benvenutoVisto by mutableStateOf(false)
        private set
    var modalitaAvanzata by mutableStateOf(false)
        private set
    /** "720p", "1080p" o "4K". */
    var risoluzione by mutableStateOf("1080p")
        private set
    var fps by mutableStateOf(30)
        private set
    /** "h264" o "hevc". */
    var codec by mutableStateOf("h264")
        private set
    var specchia by mutableStateOf(false)
        private set
    var riduciSeCaldo by mutableStateOf(true)
        private set
    var oscuraDaSolo by mutableStateOf(true)
        private set
    var risparmioBatteria by mutableStateOf(true)
        private set
    var griglia by mutableStateOf(false)
        private set

    fun impostaBenvenutoVisto(valore: Boolean) { benvenutoVisto = valore; salva("benvenutoVisto", valore) }
    fun impostaModalitaAvanzata(valore: Boolean) { modalitaAvanzata = valore; salva("modalitaAvanzata", valore) }
    fun impostaRisoluzione(valore: String) { risoluzione = valore; preferenze.edit().putString("risoluzione", valore).apply() }
    fun impostaFps(valore: Int) { fps = valore; preferenze.edit().putInt("fps", valore).apply() }
    fun impostaCodec(valore: String) { codec = valore; preferenze.edit().putString("codec", valore).apply() }
    fun impostaSpecchia(valore: Boolean) { specchia = valore; salva("specchia", valore) }
    fun impostaRiduciSeCaldo(valore: Boolean) { riduciSeCaldo = valore; salva("riduciSeCaldo", valore) }
    fun impostaOscuraDaSolo(valore: Boolean) { oscuraDaSolo = valore; salva("oscuraDaSolo", valore) }
    fun impostaRisparmioBatteria(valore: Boolean) { risparmioBatteria = valore; salva("risparmioBatteria", valore) }
    fun impostaGriglia(valore: Boolean) { griglia = valore; salva("griglia", valore) }

    val codecScelto: Codec get() = if (codec == "hevc") Codec.HEVC else Codec.H264

    /** Larghezza e altezza della risoluzione scelta, in orizzontale. */
    val dimensioni: Pair<Int, Int>
        get() = when (risoluzione) {
            "720p" -> 1280 to 720
            "4K" -> 3840 to 2160
            else -> 1920 to 1080
        }

    /** L'ultimo obiettivo usato ("principale", "frontale"…). */
    var obiettivo: String
        get() = preferenze.getString("obiettivo", "principale") ?: "principale"
        set(valore) = preferenze.edit().putString("obiettivo", valore).apply()

    /** Il nome dell'ultimo computer collegato: al prossimo avvio ci si ricollega da soli se compare (novità 2). */
    var ultimoComputer: String?
        get() = preferenze.getString("ultimoComputer", null)
        set(valore) = preferenze.edit().putString("ultimoComputer", valore).apply()

    private fun salva(chiave: String, valore: Boolean) = preferenze.edit().putBoolean(chiave, valore).apply()
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
