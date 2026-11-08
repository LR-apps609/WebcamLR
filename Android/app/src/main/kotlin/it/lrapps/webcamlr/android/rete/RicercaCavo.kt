package it.lrapps.webcamlr.android.rete

import android.util.Log
import it.lrapps.webcamlr.android.logica.DnsMulticast
import it.lrapps.webcamlr.android.logica.Sottoreti
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
 * thread della ricerca), solo con gli indirizzi nella sottorete del cavo. Un computer che non risponde più da
 * [SCADENZA_MS], o tutti quando le interfacce del cavo spariscono, arrivano a `suPerso` (come onServiceLost di
 * NsdManager). Senza cavo non manda nulla.
 */
class RicercaCavo(
    private val suTrovato: (ComputerTrovato) -> Unit,
    private val suPerso: (String) -> Unit = {},
) {
    private val attiva = AtomicBoolean(false)
    @Volatile private var thread: Thread? = null
    /** Nome del computer → ultima risposta sul cavo (millisecondi). Solo dal thread della ricerca. */
    private val ultimaRisposta = HashMap<String, Long>()

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
        ultimaRisposta.clear()
        while (attiva.get()) {
            try {
                interfacceDelCavo().forEach { cerca(it) }
                scadenze()
                Thread.sleep(3_000)
            } catch (e: InterruptedException) {
                return
            } catch (e: Exception) {
                Log.w(TAG, "Ricerca sul cavo non riuscita", e)
                try { Thread.sleep(3_000) } catch (i: InterruptedException) { return }
            }
        }
    }

    /** Collaudo 24: i computer che non rispondono più sul cavo (o il cavo staccato) si dicono persi. */
    private fun scadenze() {
        val adesso = System.currentTimeMillis()
        val senzaCavo = interfacceDelCavo().isEmpty()
        val persi = ultimaRisposta.filter { (_, ora) -> senzaCavo || adesso - ora > SCADENZA_MS }.keys.toList()
        for (nome in persi) {
            ultimaRisposta.remove(nome)
            Log.i(TAG, "Cavo: $nome non risponde più" + if (senzaCavo) " (cavo staccato)" else "")
            suPerso(nome)
        }
    }

    /** Le sottoreti IPv4 dell'interfaccia del cavo: (indirizzo, prefisso). */
    private fun sottoreti(interfaccia: NetworkInterface): List<Pair<Int, Int>> =
        interfaccia.interfaceAddresses.orEmpty().mapNotNull { voce ->
            val indirizzo = voce?.address as? Inet4Address ?: return@mapNotNull null
            val numero = indirizzo.hostAddress?.let { Sottoreti.numero(it) } ?: return@mapNotNull null
            numero to voce.networkPrefixLength.toInt()
        }

    private fun nelCavo(indirizzo: String, reti: List<Pair<Int, Int>>): Boolean {
        val numero = Sottoreti.numero(indirizzo) ?: return false
        return reti.any { (rete, prefisso) -> Sottoreti.stessa(numero, rete, prefisso) }
    }

    private fun cerca(interfaccia: NetworkInterface) {
        val gruppo = InetAddress.getByName(DnsMulticast.INDIRIZZO)
        val reti = sottoreti(interfaccia)
        if (reti.isEmpty()) return
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
                // Collaudo 25: la presa su 0.0.0.0:5353 riceve anche il mDNS del Wi-Fi (IP_MULTICAST_ALL): vale solo
                // ciò che arriva dalla sottorete del cavo, e solo con gli indirizzi del cavo.
                val sorgente = (pacchetto.address as? Inet4Address)?.hostAddress
                if (sorgente != null && !nelCavo(sorgente, reti)) continue
                val messaggio = buffer.copyOf(pacchetto.length)
                for (servizio in DnsMulticast.leggi(messaggio, Servizio.TIPO_BONJOUR + ".local")) {
                    // Il protocollo 2: chi annuncia un'altra versione non si mostra.
                    if (servizio.testo["v"]?.let { it != Servizio.VERSIONE_PROTOCOLLO.toString() } == true) continue
                    val indirizzi = servizio.indirizzi.filter { nelCavo(it, reti) }
                    if (indirizzi.isEmpty()) {
                        Log.d(TAG, "Cavo: ${servizio.nome} senza indirizzi nella sottorete del cavo, ignorato")
                        continue
                    }
                    val nome = CercaComputer.nomeLeggibile(servizio.nome)
                    ultimaRisposta[nome] = System.currentTimeMillis()
                    suTrovato(
                        ComputerTrovato(
                            nome = nome,
                            indirizzi = indirizzi,
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

        /** Senza risposta sul cavo per più di così (circa due giri di ricerca), il computer si dice perso. */
        const val SCADENZA_MS = 10_000L

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
