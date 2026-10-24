package it.lrapps.webcamlr.android.sistema

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import it.lrapps.webcamlr.protocollo.Temperatura

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

/** Il registro del collegamento per la modalità avanzata (1.5): le ultime righe, in memoria. */
object RegistroCollegamento {
    private val righe = ArrayDeque<String>()
    private val formato = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ITALY)

    @Synchronized
    fun aggiungi(testo: String) {
        righe.addLast("${formato.format(java.util.Date())}  $testo")
        while (righe.size > 200) righe.removeFirst()
    }

    @Synchronized
    fun tutte(): List<String> = righe.toList()
}
