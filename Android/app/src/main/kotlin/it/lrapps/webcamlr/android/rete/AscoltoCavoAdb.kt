package it.lrapps.webcamlr.android.rete

import android.os.Handler
import android.os.Looper
import android.util.Log
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger

/**
 * Il cavo USB con il debug USB (Qualità 17), lato telefono: come l'iPhone (iPhone/Sorgenti/AscoltoCavo.swift), mentre
 * l'app è in primo piano resta in ascolto su **127.0.0.1:52741**, solo sull'indirizzo locale. Dalla rete non si
 * raggiunge: ci arriva solo il computer, attraverso il cavo e adb («host:transport» e «tcp:52741», vedi
 * Documenti/Protocollo.md, «Cavo USB con Android: adb»). Il computer riprova ogni secondo finché qualcuno ascolta.
 *
 * Ogni connessione che arriva va a `suConnessione` sul thread principale: chi la riceve la usa per una sessione
 * (stessa stretta di mano e stessa fiducia del Wi-Fi) oppure la chiude. Se la porta è occupata si riprova ogni 2 secondi.
 * Non serve nessun permesso in più: è un ascolto TCP su loopback (permesso INTERNET, già usato per il Wi-Fi).
 */
class AscoltoCavoAdb(private val suConnessione: (Socket) -> Unit) {
    private val principale = Handler(Looper.getMainLooper())
    /** Cresce a ogni avvia() e ferma(): un filo di un ascolto precedente, ancora sveglio, vede che non è più il suo turno. */
    private val turno = AtomicInteger(0)
    @Volatile private var acceso = false
    @Volatile private var presa: ServerSocket? = null
    @Volatile private var filo: Thread? = null

    /** Vero mentre l'ascolto è davvero aperto sulla porta. */
    val inAscolto: Boolean get() = presa?.isBound == true && presa?.isClosed == false

    /** Dal thread principale. */
    fun avvia() {
        if (acceso) return
        acceso = true
        val mio = turno.incrementAndGet()
        filo = Thread({ ciclo(mio) }, "webcamlr-ascolto-cavo").apply { isDaemon = true; start() }
    }

    /** Dal thread principale. */
    fun ferma() {
        if (!acceso) return
        acceso = false
        turno.incrementAndGet()
        runCatching { presa?.close() }
        presa = null
        filo?.interrupt()
        filo = null
    }

    private fun ciclo(mio: Int) {
        fun attivo() = turno.get() == mio
        while (attivo()) {
            val nuova = try {
                ServerSocket().apply {
                    reuseAddress = true
                    bind(InetSocketAddress(InetAddress.getLoopbackAddress(), PORTA), 2)
                }
            } catch (e: Exception) {
                // Porta occupata (un'altra copia dell'app, o il sistema non l'ha ancora liberata): si riprova.
                Log.w(TAG, "Ascolto sul cavo USB non riuscito: riprovo", e)
                if (!dormi(2_000) || !attivo()) return
                continue
            }
            presa = nuova
            // ferma() chiamato mentre si apriva: si chiude subito.
            if (!attivo()) {
                runCatching { nuova.close() }
                return
            }
            Log.i(TAG, "In ascolto sul cavo USB (porta $PORTA)")
            try {
                while (attivo()) {
                    val arrivata = nuova.accept()
                    // Per sicurezza, oltre all'indirizzo d'ascolto: solo connessioni da questo stesso telefono (adbd).
                    if (!arrivata.inetAddress.isLoopbackAddress) {
                        runCatching { arrivata.close() }
                        continue
                    }
                    runCatching { arrivata.tcpNoDelay = true }
                    Log.i(TAG, "Collegamento in arrivo dal cavo USB")
                    principale.post {
                        if (attivo()) suConnessione(arrivata) else runCatching { arrivata.close() }
                    }
                }
            } catch (e: Exception) {
                if (attivo()) Log.w(TAG, "Ascolto sul cavo USB interrotto: riprovo", e)
            } finally {
                runCatching { nuova.close() }
                if (presa === nuova) presa = null
            }
            if (!dormi(2_000) || !attivo()) return
        }
    }

    private fun dormi(millisecondi: Long): Boolean = try {
        Thread.sleep(millisecondi)
        true
    } catch (e: InterruptedException) {
        false
    }

    companion object {
        private const val TAG = "WebcamLR"

        /** La stessa porta dell'iPhone (Documenti/Protocollo.md, «Collegamento via cavo USB»). */
        const val PORTA = 52741
    }
}
