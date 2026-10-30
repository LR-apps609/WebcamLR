package it.lrapps.webcamlr.android.sistema

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat

/**
 * P3 e P4: permessi e risparmio energetico senza vicoli ciechi. Lo stato si rilegge a ogni ritorno nell'app
 * (MainActivity.onStart, [aggiorna]): dopo «Apri Impostazioni» schede e righe cambiano da sole.
 *
 * Batteria: niente REQUEST_IGNORE_BATTERY_OPTIMIZATIONS. Google Play lo permette solo alle app la cui funzione
 * principale non può funzionare altrimenti (sveglie, dispositivi medici…), e chiede di dichiararlo; la via sicura è
 * aprire la pagina dell'app nelle impostazioni di Android, dove c'è «Batteria» (o «Utilizzo batteria app») con
 * «Senza restrizioni». Se manca, la lista «Ottimizzazione batteria» di Android, che non chiede permessi.
 */
object Permessi {
    /** P3: Android ha rifiutato la fotocamera. La schermata dei computer lo dice con «Apri Impostazioni». */
    var fotocameraNegata by mutableStateOf(false)
        private set

    /** P4: WebcamLR è fuori dall'ottimizzazione della batteria («Senza restrizioni»). */
    var senzaLimitiBatteria by mutableStateOf(true)
        private set

    /** La risposta alla domanda della fotocamera. */
    fun fotocameraRisposta(concessa: Boolean) {
        fotocameraNegata = !concessa
    }

    /** Di nuovo nell'app (per esempio da Impostazioni): si rileggono permesso della fotocamera e batteria. */
    fun aggiorna(context: Context) {
        if (fotocameraNegata && ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            fotocameraNegata = false
        }
        senzaLimitiBatteria = leggiSenzaLimiti(context)
    }

    private fun leggiSenzaLimiti(context: Context): Boolean {
        val energia = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return try {
            energia.isIgnoringBatteryOptimizations(context.packageName)
        } catch (e: Exception) {
            true
        }
    }

    /** La pagina di WebcamLR nelle impostazioni di Android (Autorizzazioni, Batteria). */
    fun apriPaginaApp(context: Context) {
        val pagina = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        apriLaPrima(context, pagina, Intent(Settings.ACTION_SETTINGS))
    }

    /** P4: dove togliere le restrizioni della batteria: la pagina dell'app, poi la lista dell'ottimizzazione. */
    fun apriBatteria(context: Context) {
        val pagina = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        apriLaPrima(context, pagina, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), Intent(Settings.ACTION_SETTINGS))
    }

    private fun apriLaPrima(context: Context, vararg intenti: Intent) {
        for (intento in intenti) {
            // Da un contesto che non è un'attività (il servizio) serve un compito nuovo.
            if (context !is Activity) intento.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intento)
                return
            } catch (e: ActivityNotFoundException) {
                // si prova il successivo
            } catch (e: SecurityException) {
                // si prova il successivo
            }
        }
    }
}
