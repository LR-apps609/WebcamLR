package it.lrapps.webcamlr.android.sistema

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import it.lrapps.webcamlr.protocollo.Temperatura
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.text.DateFormat
import java.util.Date
import java.util.Locale

/** Batteria, carica e temperatura del telefono, per il messaggio `stato` e gli avvisi in «In onda». */
object StatoDispositivo {

    data class Misura(val batteria: Int, val inCarica: Boolean, val temperatura: Temperatura)

    fun misura(context: Context): Misura {
        val intento: Intent? = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val livello = intento?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scala = intento?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteria = if (livello >= 0 && scala > 0) (livello * 100 + scala / 2) / scala else -1
        val stato = intento?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val inCarica = stato == BatteryManager.BATTERY_STATUS_CHARGING || stato == BatteryManager.BATTERY_STATUS_FULL
        // Decimi di grado: serve solo dove manca lo stato termico di sistema (prima di Android 10).
        val decimiDiGrado = intento?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        return Misura(batteria, inCarica, temperatura(context, decimiDiGrado))
    }

    /** Gli stessi livelli di iOS: da Android 10 lo stato termico di sistema, prima la temperatura della batteria. */
    private fun temperatura(context: Context, decimiDiGrado: Int): Temperatura {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val energia = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            return when (energia.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_NONE, PowerManager.THERMAL_STATUS_LIGHT -> Temperatura.NORMALE
                PowerManager.THERMAL_STATUS_MODERATE -> Temperatura.CALDA
                PowerManager.THERMAL_STATUS_SEVERE -> Temperatura.MOLTO_CALDA
                else -> Temperatura.CRITICA
            }
        }
        if (decimiDiGrado == Int.MIN_VALUE) return Temperatura.NORMALE
        return when {
            decimiDiGrado >= 500 -> Temperatura.CRITICA
            decimiDiGrado >= 450 -> Temperatura.MOLTO_CALDA
            decimiDiGrado >= 400 -> Temperatura.CALDA
            else -> Temperatura.NORMALE
        }
    }

    /** Il nome del telefono per il computer: quello scelto nelle impostazioni, altrimenti marca e modello. */
    fun nomeTelefono(context: Context): String {
        val scelto = try {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        } catch (e: Exception) {
            null
        }
        if (!scelto.isNullOrBlank()) return scelto
        val marca = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        return if (Build.MODEL.startsWith(marca, ignoreCase = true)) Build.MODEL else "$marca ${Build.MODEL}"
    }
}

/**
 * Il registro del collegamento (1.5): le ultime righe, in memoria. La pagina del registro le osserva ([righe]) e si
 * aggiorna mentre è aperta (passo 9); «Segnala un bug» allega le ultime 50 ([testo]).
 */
object RegistroCollegamento {
    private const val MASSIMO = 200
    /** Quante righe allega «Segnala un bug», come su iPhone, Mac e Windows. */
    const val PER_SEGNALAZIONE = 50

    private val stato = MutableStateFlow<List<String>>(emptyList())
    /** Le righe, la più vecchia per prima. */
    val righe: StateFlow<List<String>> = stato.asStateFlow()

    @Synchronized
    fun aggiungi(testo: String) {
        // L'ora nella lingua dell'app (passo 9): «14:02:31» in italiano, «2:02:31 PM» in inglese.
        val lingua = try { Testi.locale } catch (e: IllegalStateException) { Locale.getDefault() }
        val ora = DateFormat.getTimeInstance(DateFormat.MEDIUM, lingua).format(Date())
        stato.value = (stato.value + "$ora  $testo").takeLast(MASSIMO)
    }

    fun tutte(): List<String> = stato.value

    /** Le ultime [quante] righe in ordine di tempo, una per riga: per «Copia», «Condividi» e «Segnala un bug». */
    fun testo(quante: Int = MASSIMO): String = stato.value.takeLast(quante).joinToString("\n")
}
