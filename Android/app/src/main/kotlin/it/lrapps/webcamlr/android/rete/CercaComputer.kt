package it.lrapps.webcamlr.android.rete

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.lrapps.webcamlr.protocollo.Associazione
import it.lrapps.webcamlr.protocollo.Piattaforma
import it.lrapps.webcamlr.protocollo.Servizio
import java.net.Inet4Address

/** Un computer da collegare: trovato in rete, letto dal QR code o scritto a mano. */
data class ComputerTrovato(
    val nome: String,
    val indirizzi: List<String>,
    val porta: Int,
    val piattaforma: Piattaforma? = null,
    /** Dal QR code: l'impronta del computer, da verificare nella stretta di mano. */
    val impronta: String? = null,
    /** Dal QR code: il gettone di abbinamento. */
    val gettone: String? = null,
    /** Vero se trovato con la ricerca automatica (mDNS), falso dal QR code o dall'indirizzo scritto. */
    val annunciato: Boolean = true,
) {
    companion object {
        fun da(associazione: Associazione) = ComputerTrovato(
            nome = associazione.nome,
            indirizzi = associazione.indirizzi,
            porta = associazione.porta,
            impronta = associazione.impronta,
            gettone = associazione.gettone,
            annunciato = false,
        )
    }
}

/**
 * Ricerca dei computer in rete con NsdManager (mDNS, `_webcamlr._tcp`), senza servizi Google.
 * I risultati si risolvono uno alla volta: su molti telefoni NsdManager non ne regge due insieme.
 * Gli aggiornamenti arrivano sul thread principale, pronti per Compose.
 */
class CercaComputer(context: Context) {
    enum class Stato { FERMA, CERCA, ERRORE }

    private val applicazione = context.applicationContext
    private val nsd = applicazione.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val principale = Handler(Looper.getMainLooper())
    private var bloccoMulticast: WifiManager.MulticastLock? = null

    val computer = mutableStateListOf<ComputerTrovato>()
    var stato by mutableStateOf(Stato.FERMA)
        private set

    private var ascoltatore: NsdManager.DiscoveryListener? = null
    private val daRisolvere = ArrayDeque<NsdServiceInfo>()
    private var risolvendo = false

    fun avvia() {
        if (ascoltatore != null) return
        // Alcuni telefoni (Xiaomi, Huawei) scartano il multicast con lo schermo acceso e il Wi-Fi in risparmio.
        bloccoMulticast = (applicazione.getSystemService(Context.WIFI_SERVICE) as? WifiManager)
            ?.createMulticastLock("webcamlr-ricerca")?.apply {
                setReferenceCounted(false)
                try { acquire() } catch (e: Exception) { Log.w(TAG, "Multicast non disponibile", e) }
            }
        val nuovo = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(tipo: String) {
                principale.post { stato = Stato.CERCA }
            }
            override fun onDiscoveryStopped(tipo: String) = Unit

            override fun onStartDiscoveryFailed(tipo: String, errore: Int) {
                Log.w(TAG, "Ricerca non partita: $errore")
                principale.post {
                    stato = Stato.ERRORE
                    ascoltatore = null
                    // Riprovo da solo: spesso è il Wi-Fi che si sta accendendo.
                    principale.postDelayed({ if (stato == Stato.ERRORE) avvia() }, 3_000)
                }
            }

            override fun onStopDiscoveryFailed(tipo: String, errore: Int) = Unit

            override fun onServiceFound(info: NsdServiceInfo) {
                principale.post {
                    daRisolvere.addLast(info)
                    risolviProssimo()
                }
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                val nome = nomeLeggibile(info.serviceName)
                principale.post { computer.removeAll { it.nome == nome } }
            }
        }
        ascoltatore = nuovo
        try {
            nsd.discoverServices(Servizio.TIPO_BONJOUR, NsdManager.PROTOCOL_DNS_SD, nuovo)
        } catch (e: Exception) {
            Log.w(TAG, "Ricerca non partita", e)
            ascoltatore = null
            stato = Stato.ERRORE
        }
    }

    fun ferma() {
        ascoltatore?.let { try { nsd.stopServiceDiscovery(it) } catch (e: Exception) { /* già ferma */ } }
        ascoltatore = null
        daRisolvere.clear()
        stato = Stato.FERMA
        try { bloccoMulticast?.release() } catch (e: Exception) { /* già rilasciato */ }
        bloccoMulticast = null
    }

    /** Sul thread principale. */
    @Suppress("DEPRECATION") // resolveService: deprecato da Android 14 ma presente ovunque, e va bene per noi.
    private fun risolviProssimo() {
        if (risolvendo || ascoltatore == null) return
        val info = daRisolvere.removeFirstOrNull() ?: return
        risolvendo = true
        try {
            nsd.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(info: NsdServiceInfo, errore: Int) {
                    principale.post {
                        risolvendo = false
                        // Già in corso: si riprova tra poco.
                        if (errore == NsdManager.FAILURE_ALREADY_ACTIVE) {
                            daRisolvere.addLast(info)
                            principale.postDelayed({ risolviProssimo() }, 300)
                        } else {
                            risolviProssimo()
                        }
                    }
                }

                override fun onServiceResolved(info: NsdServiceInfo) {
                    val trovato = daRisolto(info)
                    principale.post {
                        risolvendo = false
                        if (trovato != null && ascoltatore != null) {
                            val indice = computer.indexOfFirst { it.nome == trovato.nome }
                            if (indice >= 0) computer[indice] = trovato else computer.add(trovato)
                        }
                        risolviProssimo()
                    }
                }
            })
        } catch (e: Exception) {
            risolvendo = false
            Log.w(TAG, "Risoluzione non riuscita", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun daRisolto(info: NsdServiceInfo): ComputerTrovato? {
        val indirizzo = info.host ?: return null
        // Solo IPv4, come nel QR code: gli indirizzi IPv6 di collegamento locale danno problemi su molti router.
        if (indirizzo !is Inet4Address) return null
        val attributi = try { info.attributes } catch (e: Exception) { emptyMap<String, ByteArray>() }
        val piattaforma = when (attributi["p"]?.toString(Charsets.UTF_8)) {
            "mac" -> Piattaforma.MAC
            "windows" -> Piattaforma.WINDOWS
            else -> null
        }
        return ComputerTrovato(
            nome = nomeLeggibile(info.serviceName),
            indirizzi = listOf(indirizzo.hostAddress ?: return null),
            porta = if (info.port > 0) info.port else Servizio.PORTA_PREDEFINITA,
            piattaforma = piattaforma,
        )
    }

    companion object {
        private const val TAG = "WebcamLR"

        /** Alcune versioni di Android lasciano i caratteri protetti di DNS-SD: «MacBook\032Pro» → «MacBook Pro». */
        fun nomeLeggibile(nome: String): String {
            if ('\\' !in nome) return nome
            val byte = java.io.ByteArrayOutputStream()
            var i = 0
            while (i < nome.length) {
                val c = nome[i]
                if (c == '\\' && i + 3 < nome.length && nome.substring(i + 1, i + 4).all { it.isDigit() }) {
                    byte.write(nome.substring(i + 1, i + 4).toInt())
                    i += 4
                } else if (c == '\\' && i + 1 < nome.length) {
                    byte.write(nome[i + 1].toString().toByteArray(Charsets.UTF_8))
                    i += 2
                } else {
                    byte.write(c.toString().toByteArray(Charsets.UTF_8))
                    i++
                }
            }
            return byte.toString(Charsets.UTF_8.name())
        }
    }
}
