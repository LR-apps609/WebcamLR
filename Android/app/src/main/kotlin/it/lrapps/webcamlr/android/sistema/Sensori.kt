package it.lrapps.webcamlr.android.sistema

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import java.util.concurrent.Executor

/**
 * P07 faccia in giù: la gravità, cinque letture al secondo, sul thread principale. `giu` va da −1 (schermo verso
 * l'alto) a +1 (schermo verso il basso): su Android z è positivo con lo schermo in su, quindi giu = −z/g.
 */
class SensoreGravita(context: Context, private val suLettura: (giu: Double, adesso: Long) -> Unit) {
    private val sensori = context.applicationContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private val principale = Handler(Looper.getMainLooper())
    private var acceso = false

    private val ascolto = object : SensorEventListener {
        override fun onSensorChanged(evento: SensorEvent) {
            val z = evento.values.getOrNull(2) ?: return
            suLettura(-z / SensorManager.GRAVITY_EARTH.toDouble(), SystemClock.elapsedRealtime())
        }

        override fun onAccuracyChanged(sensore: Sensor?, precisione: Int) = Unit
    }

    fun avvia() {
        if (acceso || sensori == null) return
        val sensore = sensori.getDefaultSensor(Sensor.TYPE_GRAVITY) ?: sensori.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        acceso = sensori.registerListener(ascolto, sensore, 200_000, principale)
    }

    fun ferma() {
        if (!acceso) return
        sensori?.unregisterListener(ascolto)
        acceso = false
    }
}

/**
 * 1.14: lo stato termico di sistema cambiato (Android 10+), subito: non si aspettano i 5 secondi dello `stato`.
 * `suCambio` arriva sul thread principale.
 */
class AscoltoCalore(context: Context, private val suCambio: () -> Unit) {
    private val energia = context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val principale = Handler(Looper.getMainLooper())
    private var ascolto: Any? = null

    fun avvia() {
        if (ascolto != null || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val esecutore = Executor { principale.post(it) }
        val nuovo = PowerManager.OnThermalStatusChangedListener { suCambio() }
        try {
            energia.addThermalStatusListener(esecutore, nuovo)
            ascolto = nuovo
        } catch (e: Exception) {
            ascolto = null
        }
    }

    fun ferma() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        (ascolto as? PowerManager.OnThermalStatusChangedListener)?.let { runCatching { energia.removeThermalStatusListener(it) } }
        ascolto = null
    }
}
