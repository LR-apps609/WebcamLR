package it.lrapps.webcamlr.android.ui

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.os.SystemClock
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Collaudo 20 (t11 B8): l'attività che non è un tocco sullo schermo. In onda «Oscura lo schermo dopo 30 secondi senza
 * tocchi» contava solo i tocchi: con una tastiera (o un comando a tasti) lo schermo si oscurava mentre Marta lo usava
 * e il fuoco andava perso. MainActivity registra ogni tasto qui; «In onda» lo conta come un tocco.
 */
object AttivitaUtente {
    /** L'ultimo tasto premuto ([SystemClock.elapsedRealtime]); 0 se nessuno. */
    var ultimoTasto by mutableLongStateOf(0L)
        private set

    /** Lo schermo oscurato è stato riacceso con un tasto: il fuoco della tastiera va ridato ai comandi. */
    var fuocoDaRidare by mutableStateOf(false)

    fun tasto() {
        val ora = SystemClock.elapsedRealtime()
        // Come per i tocchi: al massimo una scrittura ogni 250 ms (un tasto tenuto premuto si ripete).
        if (ora - ultimoTasto >= 250) ultimoTasto = ora
    }
}

/**
 * C'è un lettore di schermo o un display braille: TalkBack con l'esplorazione al tocco, o un servizio di accessibilità
 * che parla o scrive in braille (anche comandato da tastiera, senza esplorazione al tocco).
 */
fun lettoreDiSchermoAttivo(context: Context): Boolean {
    val accessibilita = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager ?: return false
    if (!accessibilita.isEnabled) return false
    if (accessibilita.isTouchExplorationEnabled) return true
    val tipi = AccessibilityServiceInfo.FEEDBACK_SPOKEN or AccessibilityServiceInfo.FEEDBACK_BRAILLE
    return try {
        accessibilita.getEnabledAccessibilityServiceList(tipi).isNotEmpty()
    } catch (e: Exception) {
        false
    }
}
