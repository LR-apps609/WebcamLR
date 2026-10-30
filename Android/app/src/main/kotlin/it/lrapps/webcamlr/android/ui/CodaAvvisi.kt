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
 * G2.2: un avviso su una condizione in corso (`persiste`: caldo, batteria, rete, microfono) chiuso dopo i 6 secondi o
 * con un tocco diventa un'icona ambra nella riga di stato ([ridotti]) finché la condizione dura; un tocco la riapre.
 * Ogni avviso nuovo passa da [registra] (il registro del collegamento). Con TalkBack ([conLettore]) un avviso non si
 * chiude da solo finché non c'è altro da dire; se altri aspettano lascia il posto dopo [DURATA_CON_LETTORE_MS], così
 * la coda non si blocca.
 */
class CodaAvvisi(
    private val ambito: CoroutineScope,
    private val conLettore: () -> Boolean = { false },
    private val registra: (Avviso) -> Unit = {},
) {
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
        /** La risposta a un gesto (doppio tocco in onda): prende subito il posto di quello a schermo, che torna dopo. */
        val subito: Boolean = false,
        /** G2.2: descrive una condizione ancora in corso: chiuso, resta come icona nella riga di stato. */
        val persiste: Boolean = false,
        /** P3 e P4: un pulsante sotto il testo («Apri Impostazioni»), per i permessi e la batteria. */
        val azione: Azione? = null,
    )

    /** Dove porta il pulsante dell'avviso. */
    enum class Azione {
        /** La pagina di WebcamLR nelle impostazioni di Android (Autorizzazioni). */
        IMPOSTAZIONI_APP,
        /** Dove togliere le restrizioni della batteria. */
        BATTERIA,
    }

    var attuale by mutableStateOf<Avviso?>(null)
        private set

    /** G2.2: gli avvisi chiusi la cui condizione dura ancora, come icone nella riga di stato. */
    var ridotti by mutableStateOf<List<Avviso>>(emptyList())
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
        // Condizioni finite: non si dicono più, l'icona sparisce e quella a schermo si chiude.
        inAttesa.removeAll { it.id !in adesso }
        if (ridotti.any { it.id !in adesso }) ridotti = ridotti.filter { it.id in adesso }
        val mostrato = attuale
        if (mostrato != null && mostrato.id !in adesso) togli(riduci = false)
        val ora = SystemClock.elapsedRealtime()
        for (avviso in nuovi) {
            if (attuale?.id == avviso.id || inAttesa.any { it.id == avviso.id } || ridotti.any { it.id == avviso.id }) continue
            val quando = mostrati[avviso.id]
            if (quando != null && (avviso.suggerimento || avviso.id !in finiti || (!avviso.fisso && ora - quando < PAUSA_PRIMA_DI_RIPETERE_MS))) continue
            inAttesa.add(avviso)
        }
        inAttesa.sortByDescending { it.priorita }
        val aSchermo = attuale
        val primo = inAttesa.firstOrNull()
        if (primo != null && primo.subito && aSchermo != null && !aSchermo.subito) {
            // Quello a schermo torna subito dopo, se la sua condizione dura ancora.
            inAttesa.removeAt(0)
            inAttesa.add(0, aSchermo)
            mostra(primo)
        } else if (aSchermo == null) {
            avanza()
        } else if (compito == null) {
            // Un avviso fisso (o uno con TalkBack) e un altro che arriva: dopo un po' gli lascia il posto.
            programma(aSchermo)
        }
    }

    /**
     * G2.2: lo stesso argomento con un testo nuovo («Batteria al 18%» → «al 15%»): a schermo, in coda e nelle icone si
     * aggiorna senza ricominciare i 6 secondi.
     */
    fun aggiornaTesti(nuovi: List<Avviso>) {
        val testi = nuovi.associate { it.id to it.testo }
        val mostrato = attuale
        val testoNuovo = mostrato?.let { testi[it.id] }
        if (mostrato != null && testoNuovo != null && testoNuovo != mostrato.testo) attuale = mostrato.copy(testo = testoNuovo)
        for (indice in inAttesa.indices) {
            val t = testi[inAttesa[indice].id] ?: continue
            inAttesa[indice] = inAttesa[indice].copy(testo = t)
        }
        if (ridotti.any { r -> testi[r.id]?.let { it != r.testo } == true }) {
            ridotti = ridotti.map { r -> testi[r.id]?.let { r.copy(testo = it) } ?: r }
        }
    }

    /** Chiude l'avviso a schermo (un tocco) e passa al prossimo, se c'è. Su una condizione in corso resta l'icona. */
    fun chiudi() = togli(riduci = true)

    /** G2.2: un tocco sull'icona riapre l'avviso; quello a schermo torna in coda per primo. */
    fun riapri(id: String) {
        val avviso = ridotti.firstOrNull { it.id == id } ?: return
        ridotti = ridotti.filter { it.id != id }
        attuale?.let { mostrato ->
            compito?.cancel()
            compito = null
            inAttesa.add(0, mostrato)
        }
        mostra(avviso, riaperto = true)
    }

    /** TalkBack acceso o spento: il tempo dell'avviso a schermo riparte con la regola nuova ([programma]). */
    fun lettoreCambiato() {
        val mostrato = attuale ?: return
        programma(mostrato)
    }

    /** Alla fine della sessione. */
    fun ferma() {
        compito?.cancel()
        compito = null
        inAttesa.clear()
        ridotti = emptyList()
        attuale = null
    }

    private fun togli(riduci: Boolean) {
        compito?.cancel()
        compito = null
        val mostrato = attuale
        if (riduci && mostrato != null && mostrato.persiste && mostrato.id in attivi && ridotti.none { it.id == mostrato.id }) {
            ridotti = ridotti + mostrato
        }
        attuale = null
        avanza()
    }

    private fun avanza() {
        if (attuale != null || inAttesa.isEmpty()) return
        mostra(inAttesa.removeAt(0))
    }

    private fun mostra(avviso: Avviso, riaperto: Boolean = false) {
        // G2.2: ogni avviso nel registro, la prima volta che compare (non quando si riapre dall'icona).
        if (!avviso.suggerimento && !riaperto && (!mostrati.containsKey(avviso.id) || avviso.id in finiti)) registra(avviso)
        mostrati[avviso.id] = SystemClock.elapsedRealtime()
        finiti.remove(avviso.id)
        if (ridotti.any { it.id == avviso.id }) ridotti = ridotti.filter { it.id != avviso.id }
        attuale = avviso
        programma(avviso)
    }

    /**
     * Dopo 6 secondi l'avviso si chiude. Uno fisso resta finché dura la sua condizione, ma non ferma la coda: se altri
     * avvisi (non suggerimenti) aspettano, dopo 6 secondi lascia il posto al primo e torna subito dopo di lui. Con
     * TalkBack non si chiude da solo se non aspetta nessuno; se altri aspettano, lascia il posto dopo 20 secondi (la coda
     * non si blocca su un avviso che nessuno tocca).
     */
    private fun programma(avviso: Avviso) {
        compito?.cancel()
        compito = null
        val lettore = conLettore()
        if (lettore && inAttesa.isEmpty()) return
        if (avviso.fisso && inAttesa.none { !it.suggerimento }) return
        compito = ambito.launch {
            delay(if (lettore) DURATA_CON_LETTORE_MS else DURATA_MS)
            compito = null
            scaduto()
        }
    }

    private fun scaduto() {
        val mostrato = attuale ?: return
        if (!mostrato.fisso) {
            togli(riduci = true)
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
        /** Con TalkBack: il tempo di sentire l'avviso prima di passare al prossimo in coda. */
        const val DURATA_CON_LETTORE_MS = 20_000L
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
