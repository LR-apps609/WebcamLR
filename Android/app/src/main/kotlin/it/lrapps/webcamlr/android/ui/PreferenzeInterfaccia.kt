package it.lrapps.webcamlr.android.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Le scelte nuove dell'interfaccia (round A1), nello stesso file di [it.lrapps.webcamlr.android.dati.Impostazioni]
 * («impostazioni») e con le stesse chiavi dell'iPhone (`@AppStorage`): la sessione può leggerle da lì senza
 * dipendere da questo file. Livella e presentazione riguardano solo il telefono; inquadratura, luce sul volto e
 * postura si mandano anche alla sessione con un [it.lrapps.webcamlr.protocollo.Comando].
 */
object PreferenzeInterfaccia {
    private var preferenze: SharedPreferences? = null

    fun prepara(context: Context) {
        if (preferenze != null) return
        val lette = context.applicationContext.getSharedPreferences("impostazioni", Context.MODE_PRIVATE)
        preferenze = lette
        livella = lette.getBoolean(LIVELLA, false)
        inquadratura = lette.getBoolean(INQUADRATURA, false)
        luceVolto = lette.getBoolean(LUCE_VOLTO, false)
        postura = lette.getBoolean(POSTURA, false)
        facciaInGiu = lette.getBoolean(FACCIA_IN_GIU, true)
    }

    var livella by mutableStateOf(false)
        private set
    var inquadratura by mutableStateOf(false)
        private set
    var luceVolto by mutableStateOf(false)
        private set
    var postura by mutableStateOf(false)
        private set
    var facciaInGiu by mutableStateOf(true)
        private set

    fun impostaLivella(valore: Boolean) { livella = valore; salva(LIVELLA, valore) }
    fun impostaInquadratura(valore: Boolean) { inquadratura = valore; salva(INQUADRATURA, valore) }
    fun impostaLuceVolto(valore: Boolean) { luceVolto = valore; salva(LUCE_VOLTO, valore) }
    fun impostaPostura(valore: Boolean) { postura = valore; salva(POSTURA, valore) }
    fun impostaFacciaInGiu(valore: Boolean) { facciaInGiu = valore; salva(FACCIA_IN_GIU, valore) }

    private fun salva(chiave: String, valore: Boolean) {
        preferenze?.edit()?.putBoolean(chiave, valore)?.apply()
    }

    const val LIVELLA = "livella"
    const val INQUADRATURA = "inquadraturaAutomatica"
    const val LUCE_VOLTO = "luceVolto"
    const val POSTURA = "postura"
    const val FACCIA_IN_GIU = "pausaFacciaInGiu"
}
