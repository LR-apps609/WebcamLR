package it.lrapps.webcamlr.android.sistema

import android.os.SystemClock
import kotlin.math.abs

/**
 * L'orologio del protocollo sul telefono, in microsecondi (Documenti/Protocollo.md, «Latenza»): deve essere lo stesso
 * dei timestamp dei fotogrammi, perché il computer confronta i `pong` con i fotogrammi.
 *
 * Camera2 dà i timestamp con l'orologio `elapsedRealtimeNanos` (SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME) oppure con
 * quello monotono (`System.nanoTime`, sorgente «UNKNOWN» su molti telefoni): al primo fotogramma si sceglie quello
 * più vicino al timestamp ricevuto, così va bene in tutti e due i casi.
 */
object Orologio {
    @Volatile
    private var tempoReale = true

    fun adesso(): ULong = microsecondiDi(if (tempoReale) SystemClock.elapsedRealtimeNanos() else System.nanoTime())

    private fun microsecondiDi(nanosecondi: Long): ULong = if (nanosecondi > 0) (nanosecondi / 1000).toULong() else 0uL

    /**
     * All'apertura della fotocamera, prima dei `pong`: SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME vuol dire
     * `elapsedRealtimeNanos`; «UNKNOWN» in pratica è l'orologio monotono. Il primo fotogramma conferma ([calibra]).
     */
    fun impostaSorgente(tempoReale: Boolean) {
        this.tempoReale = tempoReale
    }

    /** Con il timestamp (µs) di un fotogramma appena uscito dalla fotocamera. */
    fun calibra(timestampMicrosecondi: Long) {
        val reale = SystemClock.elapsedRealtimeNanos() / 1000
        val monotono = System.nanoTime() / 1000
        tempoReale = abs(timestampMicrosecondi - reale) <= abs(timestampMicrosecondi - monotono)
    }
}
