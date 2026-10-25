package it.lrapps.webcamlr.android.rete

import android.util.Log
import it.lrapps.webcamlr.android.logica.DnsMulticast
import it.lrapps.webcamlr.protocollo.Piattaforma
import it.lrapps.webcamlr.protocollo.Servizio
import java.net.DatagramPacket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.MulticastSocket
import java.net.NetworkInterface
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * La ricerca del computer sulla rete del **Tethering USB** (il cavo di Android, `rndis`/`ncm`/`usb`), fatta da noi con
 * il DNS multicast: NsdManager cerca sempre sulle reti del telefono (Wi-Fi), ma la rete del cavo è una rete che il
 * telefono *offre* al computer, e solo alcune versioni di Android (14 e successive) ci cercano da sole.
 *
 * Ogni 3 secondi, finché è accesa: per ogni interfaccia del cavo attiva con un indirizzo IPv4 manda la domanda PTR di
 * `_webcamlr._tcp.local` e legge le risposte per un secondo e mezzo. I computer trovati arrivano a `suTrovato` (dal
 * thread della ricerca). Senza cavo non manda nulla.
 */
class RicercaCavo(private val suTrovato: (ComputerTrovato) -> Unit) {
    private val attiva = AtomicBoolean(false)
    @Volatile private var thread: Thread? = null

    fun avvia() {
        if (!attiva.compareAndSet(false, true)) return
        thread = Thread({ ciclo() }, "webcamlr-ricerca-cavo").apply { isDaemon = true; start() }
    }

    fun ferma() {
        attiva.set(false)
        thread?.interrupt()
        thread = null
    }

    private fun ciclo() {
        while (attiva.get()) {
            try {
                interfacceDelCavo().forEach { cerca(it) }
                Thread.sleep(3_000)
            } catch (e: InterruptedException) {
                return
            } catch (e: Exception) {
                Log.w(TAG, "Ricerca sul cavo non riuscita", e)
                try { Thread.sleep(3_000) } catch (i: InterruptedException) { return }
            }
        }
    }

    private fun cerca(interfaccia: NetworkInterface) {
        val gruppo = InetAddress.getByName(DnsMulticast.INDIRIZZO)
        val socket = apri() ?: return
        try {
            socket.networkInterface = interfaccia
            socket.timeToLive = 255
            runCatching { socket.joinGroup(InetSocketAddress(gruppo, DnsMulticast.PORTA), interfaccia) }
            val domanda = DnsMulticast.domanda(Servizio.TIPO_BONJOUR + ".local")
            socket.send(DatagramPacket(domanda, domanda.size, gruppo, DnsMulticast.PORTA))
            socket.soTimeout = 300
            val buffer = ByteArray(9_000)
            val fine = System.currentTimeMillis() + 1_500
            while (attiva.get() && System.currentTimeMillis() < fine) {
                val pacchetto = DatagramPacket(buffer, buffer.size)
                try {
                    socket.receive(pacchetto)
                } catch (e: SocketTimeoutException) {
                    continue
                }
                val messaggio = buffer.copyOf(pacchetto.length)
                for (servizio in DnsMulticast.leggi(messaggio, Servizio.TIPO_BONJOUR + ".local")) {
                    // Il protocollo 2: chi annuncia un'altra versione non si mostra.
                    if (servizio.testo["v"]?.let { it != Servizio.VERSIONE_PROTOCOLLO.toString() } == true) continue
                    suTrovato(
                        ComputerTrovato(
                            nome = CercaComputer.nomeLeggibile(servizio.nome),
                            indirizzi = servizio.indirizzi,
                            porta = servizio.porta,
                            piattaforma = when (servizio.testo["p"]) {
                                "mac" -> Piattaforma.MAC
                                "windows" -> Piattaforma.WINDOWS
                                else -> null
                            },
                            viaCavo = true,
                        ),
                    )
                }
            }
        } finally {
            runCatching { socket.leaveGroup(InetSocketAddress(gruppo, DnsMulticast.PORTA), interfaccia) }
            socket.close()
        }
    }

    /**
     * Sulla porta 5353 (con il riuso dell'indirizzo, come il servizio mDNS di sistema) le risposte multicast arrivano
     * anche a noi; se non si può, una porta qualsiasi: i computer rispondono direttamente (risposta «unicast»).
     */
    private fun apri(): MulticastSocket? = try {
        MulticastSocket(null).apply {
            reuseAddress = true
            bind(InetSocketAddress(DnsMulticast.PORTA))
        }
    } catch (e: Exception) {
        try {
            MulticastSocket(0)
        } catch (e2: Exception) {
            null
        }
    }

    companion object {
        private const val TAG = "WebcamLR"

        /** Le interfacce del Tethering USB attive, con un indirizzo IPv4 (il telefono fa da router: 192.168.x.129). */
        fun interfacceDelCavo(): List<NetworkInterface> = try {
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().filter { interfaccia ->
                val nome = interfaccia.name.lowercase()
                (nome.startsWith("rndis") || nome.startsWith("ncm") || nome.startsWith("usb")) &&
                    interfaccia.isUp && interfaccia.inetAddresses.toList().any { it is Inet4Address }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
