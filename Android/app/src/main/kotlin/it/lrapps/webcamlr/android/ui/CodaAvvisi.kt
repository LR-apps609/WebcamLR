package it.lrapps.webcamlr.android.ui

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * Gli avvisi sopra il video, uno alla volta (come CodaAvvisi dell'iPhone, 1.14). Ogni avviso ha un argomento (`id`):
 * mai due sulla stessa cosa. Si chiude da solo dopo 6 secondi o con un tocco; un avviso fisso resta finché dura la sua
 * condizione (o fino a un tocco), a turno con gli altri avvisi se ce ne sono. Un suggerimento si vede una volta per sessione; un avviso torna solo se la sua
 * condizione è finita e poi ricomincia, e non prima di due minuti (un avviso fisso subito).
 */
class CodaAvvisi(private val ambito: CoroutineScope) {
    data class Avviso(
        /** L'argomento: «rete», «caldo», «batteria»… */
        val id: String,
        val testo: String,
        val icona: ImageVector,
        /** Un consiglio (gira in orizzontale), nell'accento; altrimenti qualcosa che non va, in ambra. */
        val suggerimento: Boolean,
        /** Più alto, prima. */
        val priorita: Int,
        /** Resta finché la condizione dura (chiamata in corso, servizio rifiutato), non 6 secondi. */
        val fisso: Boolean = false,
    )

    var attuale by mutableStateOf<Avviso?>(null)
        private set

    private val inAttesa = mutableListOf<Avviso>()
    private val mostrati = mutableMapOf<String, Long>()
    /** Argomenti già mostrati la cui condizione poi è finita: possono tornare. */
    private val finiti = mutableSetOf<String>()
    private var attivi = emptySet<String>()
    private var compito: Job? = null

    /** Le condizioni vere adesso. */
    fun aggiorna(nuovi: List<Avviso>) {
        val adesso = nuovi.map { it.id }.toSet()
        for (id in attivi - adesso) if (mostrati.containsKey(id)) finiti.add(id)
        attivi = adesso
        // Condizioni finite: non si dicono più, e quella a schermo si chiude.
        inAttesa.removeAll { it.id !in adesso }
        val mostrato = attuale
        if (mostrato != null && mostrato.id !in adesso) chiudi()
        val ora = SystemClock.elapsedRealtime()
        for (avviso in nuovi) {
            if (attuale?.id == avviso.id || inAttesa.any { it.id == avviso.id }) continue
            val quando = mostrati[avviso.id]
            if (quando != null && (avviso.suggerimento || avviso.id !in finiti || (!avviso.fisso && ora - quando < PAUSA_PRIMA_DI_RIPETERE_MS))) continue
            inAttesa.add(avviso)
        }
        inAttesa.sortByDescending { it.priorita }
        val aSchermo = attuale
        if (aSchermo == null) {
            avanza()
        } else if (aSchermo.fisso && compito == null) {
            // Un avviso fisso e un altro che arriva: dopo 6 secondi gli lascia il posto.
            programma(aSchermo)
        }
    }

    /** Chiude l'avviso a schermo e passa al prossimo, se c'è. */
    fun chiudi() {
        compito?.cancel()
        compito = null
        attuale = null
        avanza()
    }

    /** Alla fine della sessione. */
    fun ferma() {
        compito?.cancel()
        compito = null
        inAttesa.clear()
        attuale = null
    }

    private fun avanza() {
        if (attuale != null || inAttesa.isEmpty()) return
        mostra(inAttesa.removeAt(0))
    }

    private fun mostra(avviso: Avviso) {
        mostrati[avviso.id] = SystemClock.elapsedRealtime()
        finiti.remove(avviso.id)
        attuale = avviso
        programma(avviso)
    }

    /**
     * Dopo 6 secondi l'avviso si chiude. Uno fisso resta finché dura la sua condizione, ma non ferma la coda: se altri
     * avvisi (non suggerimenti) aspettano, dopo 6 secondi lascia il posto al primo e torna subito dopo di lui.
     */
    private fun programma(avviso: Avviso) {
        compito?.cancel()
        compito = null
        if (avviso.fisso && inAttesa.none { !it.suggerimento }) return
        compito = ambito.launch {
            delay(DURATA_MS)
            compito = null
            scaduto()
        }
    }

    private fun scaduto() {
        val mostrato = attuale ?: return
        if (!mostrato.fisso) {
            chiudi()
            return
        }
        // Gli altri nel frattempo sono finiti: resta a schermo.
        val indice = inAttesa.indexOfFirst { !it.suggerimento }
        if (indice < 0) return
        val altro = inAttesa.removeAt(indice)
        inAttesa.add(0, mostrato)
        mostra(altro)
    }

    private companion object {
        const val DURATA_MS = 6_000L
        const val PAUSA_PRIMA_DI_RIPETERE_MS = 120_000L
    }
}

/**
 * La livella (solo sul telefono): di quanti gradi l'orizzonte è inclinato rispetto allo schermo, dal sensore di
 * gravità. Null se è spenta, se il telefono è quasi in piano o se il sensore non c'è.
 * Positivo = da disegnare ruotato in senso orario (come `rotate` di Compose).
 */
@Composable
fun ricordaLivella(accesa: Boolean): State<Float?> {
    val context = LocalContext.current
    val scostamento = remember { mutableStateOf<Float?>(null) }
    DisposableEffect(accesa) {
        val sensori = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensore = sensori?.getDefaultSensor(Sensor.TYPE_GRAVITY) ?: sensori?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (!accesa || sensori == null || sensore == null) {
            scostamento.value = null
            return@DisposableEffect onDispose { }
        }
        var filtroX = 0f
        var filtroY = 0f
        var primo = true
        val ascolto = object : SensorEventListener {
            override fun onSensorChanged(evento: SensorEvent) {
                // Un po' di filtro: la linea non trema.
                val x = evento.values[0]
                val y = evento.values[1]
                if (primo) {
                    filtroX = x; filtroY = y; primo = false
                } else {
                    filtroX += (x - filtroX) * 0.15f
                    filtroY += (y - filtroY) * 0.15f
                }
                // Dal telefono allo schermo: la componente verso destra e quella verso l'alto dello schermo.
                // `rotazioneSchermo` 270 = Surface.ROTATION_90 (alto del telefono a sinistra), 90 = ROTATION_270.
                val (destra, alto) = when (rotazioneSchermo(context)) {
                    270 -> -filtroY to filtroX
                    180 -> -filtroX to -filtroY
                    90 -> filtroY to -filtroX
                    else -> filtroX to filtroY
                }
                scostamento.value = calcola(destra, alto)
            }

            override fun onAccuracyChanged(sensore: Sensor?, precisione: Int) = Unit
        }
        sensori.registerListener(ascolto, sensore, SensorManager.SENSOR_DELAY_UI)
        onDispose { sensori.unregisterListener(ascolto) }
    }
    return scostamento
}

private fun calcola(destra: Float, alto: Float): Float? {
    if (sqrt(destra * destra + alto * alto) < 3f) return null
    return Math.toDegrees(atan2(destra.toDouble(), alto.toDouble())).toFloat()
}
