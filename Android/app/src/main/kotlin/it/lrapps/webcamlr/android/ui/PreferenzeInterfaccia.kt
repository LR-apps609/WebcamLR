package it.lrapps.webcamlr.android.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.lrapps.webcamlr.android.dati.Impostazioni

/**
 * Le scelte dell'interfaccia che non hanno un posto in [Impostazioni], nello stesso file («impostazioni») e con le
 * chiavi dell'iPhone: la sessione le segue da lì (faccia in giù, postura). Livella: solo sul telefono.
 * Inquadratura e luce sul volto durante la sessione si leggono da [it.lrapps.webcamlr.android.sessione.SessioneTelefono.effetti].
 * Se la sessione riscrive una chiave (per esempio la postura cambiata dal computer) qui il valore si aggiorna.
 */
object PreferenzeInterfaccia {
    private var preferenze: SharedPreferences? = null

    /** Tenuto qui: SharedPreferences ricorda gli ascoltatori solo con un riferimento debole. */
    private val ascolto = SharedPreferences.OnSharedPreferenceChangeListener { _, chiave -> rileggi(chiave) }

    fun prepara(context: Context) {
        if (preferenze != null) return
        val lette = context.applicationContext.getSharedPreferences("impostazioni", Context.MODE_PRIVATE)
        preferenze = lette
        rileggi(null)
        lette.registerOnSharedPreferenceChangeListener(ascolto)
    }

    var livella by mutableStateOf(false)
        private set
    var postura by mutableStateOf(false)
        private set
    var facciaInGiu by mutableStateOf(true)
        private set

    fun impostaLivella(valore: Boolean) { livella = valore; salva(LIVELLA, valore) }
    fun impostaPostura(valore: Boolean) { postura = valore; salva(Impostazioni.CHIAVE_POSTURA, valore) }
    fun impostaFacciaInGiu(valore: Boolean) { facciaInGiu = valore; salva(Impostazioni.CHIAVE_FACCIA_IN_GIU, valore) }

    private fun rileggi(chiave: String?) {
        val p = preferenze ?: return
        if (chiave == null || chiave == LIVELLA) livella = p.getBoolean(LIVELLA, false)
        if (chiave == null || chiave == Impostazioni.CHIAVE_POSTURA) postura = p.getBoolean(Impostazioni.CHIAVE_POSTURA, false)
        if (chiave == null || chiave == Impostazioni.CHIAVE_FACCIA_IN_GIU) facciaInGiu = p.getBoolean(Impostazioni.CHIAVE_FACCIA_IN_GIU, true)
    }

    private fun salva(chiave: String, valore: Boolean) {
        preferenze?.edit()?.putBoolean(chiave, valore)?.apply()
    }

    const val LIVELLA = "livella"
}
