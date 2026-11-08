package it.lrapps.webcamlr.android.rete

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
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
    /** Trovato sulla rete del Tethering USB (il cavo): gli indirizzi del cavo sono i primi da provare. */
    val viaCavo: Boolean = false,
) {
    /** Lo stesso computer visto anche da un'altra ricerca: indirizzi uniti, quelli del cavo per primi. */
    fun unitoA(altro: ComputerTrovato): ComputerTrovato {
        val primi = if (altro.viaCavo && !viaCavo) altro.indirizzi + indirizzi else indirizzi + altro.indirizzi
        return copy(
            indirizzi = primi.distinct(),
            piattaforma = piattaforma ?: altro.piattaforma,
            viaCavo = viaCavo || altro.viaCavo,
        )
    }

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
    /** R03: numero della risoluzione in corso; una risposta con un numero vecchio (arrivata dopo la scadenza) si ignora. */
    private var risoluzioneAttuale = 0
    private var ascoltoRisoluzione: NsdManager.ResolveListener? = null
    /** Attesa prima di riprovare dopo FAILURE_ALREADY_ACTIVE: 0,3 → 1 → 3 s, così una risoluzione rimasta appesa
     *  (prima di Android 14 non si può fermare) non fa girare la coda ogni 300 ms. */
    private var attesaGiaAttiva = 300L

    /** R03: se resolveService non risponde entro 5 secondi si passa al prossimo, invece di fermare la coda per sempre. */
    private val scadenzaRisoluzione = Runnable {
        if (!risolvendo) return@Runnable
        Log.w(TAG, "Risoluzione senza risposta: passo alla prossima")
        risoluzioneAttuale++
        risolvendo = false
        // Da Android 14 la si può anche fermare, così NsdManager non la considera ancora in corso.
        val ascolto = ascoltoRisoluzione
        ascoltoRisoluzione = null
        if (ascolto != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            runCatching { nsd.stopServiceResolution(ascolto) }
        }
        risolviProssimo()
    }

    /** In coda una volta sola per nome: lo stesso servizio annunciato più volte non allunga la coda. */
    private fun mettiInCoda(info: NsdServiceInfo) {
        if (daRisolvere.none { it.serviceName == info.serviceName }) daRisolvere.addLast(info)
    }

    /** Sulla rete del Tethering USB cerchiamo anche da soli (vedi [RicercaCavo]). */
    private val ricercaCavo = RicercaCavo(
        suTrovato = { trovato -> principale.post { if (ascoltatore != null || cavoSolo) aggiungi(trovato) } },
        suPerso = { nome -> principale.post { persoSulCavo(nome) } },
    )
    private var cavoSolo = false

    /** Collaudo 24: gli indirizzi visti sul cavo per ogni nome, per toglierli quando il cavo lo perde. */
    private val indirizziCavo = HashMap<String, Set<String>>()
    /** I nomi che NsdManager vede adesso sul Wi-Fi (tra onServiceResolved e onServiceLost). */
    private val visteWiFi = HashSet<String>()

    /** Ogni computer trovato (sul thread principale), per chi aspetta un computer preciso (la sessione che si ricollega). */
    var suTrovato: ((ComputerTrovato) -> Unit)? = null

    /** Un computer trovato da una delle due ricerche: se c'è già (stesso nome) si uniscono gli indirizzi. */
    private fun aggiungi(trovato: ComputerTrovato) {
        suTrovato?.invoke(trovato)
        if (trovato.viaCavo) {
            indirizziCavo[trovato.nome] = indirizziCavo[trovato.nome].orEmpty() + trovato.indirizzi
        } else {
            visteWiFi.add(trovato.nome)
        }
        val indice = computer.indexOfFirst { it.nome == trovato.nome }
        if (indice < 0) {
            computer.add(trovato)
        } else {
            val unito = if (trovato.viaCavo) computer[indice].unitoA(trovato) else trovato.unitoA(computer[indice])
            if (unito != computer[indice]) computer[indice] = unito
        }
    }

    /**
     * Il cavo non vede più quel computer: se è ancora sul Wi-Fi la voce torna «Wi-Fi» senza gli indirizzi del cavo,
     * altrimenti sparisce.
     */
    private fun persoSulCavo(nome: String) {
        val delCavo = indirizziCavo.remove(nome).orEmpty()
        val indice = computer.indexOfFirst { it.nome == nome && it.viaCavo }
        if (indice < 0) return
        val voce = computer[indice]
        val restano = voce.indirizzi.filter { it !in delCavo }
        if (nome !in visteWiFi || restano.isEmpty()) {
            Log.i(TAG, "Cavo: tolgo $nome dalla lista")
            computer.removeAt(indice)
        } else {
            Log.i(TAG, "Cavo: $nome resta solo sul Wi-Fi")
            computer[indice] = voce.copy(indirizzi = restano, viaCavo = false)
        }
    }

    fun avvia() {
        ricercaCavo.avvia()
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
                    // Senza Wi-Fi NsdManager può non partire: la ricerca sul cavo continua.
                    cavoSolo = true
                    // Riprovo da solo: spesso è il Wi-Fi che si sta accendendo.
                    principale.postDelayed({ if (stato == Stato.ERRORE) avvia() }, 3_000)
                }
            }

            override fun onStopDiscoveryFailed(tipo: String, errore: Int) = Unit

            override fun onServiceFound(info: NsdServiceInfo) {
                principale.post {
                    mettiInCoda(info)
                    risolviProssimo()
                }
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                val nome = nomeLeggibile(info.serviceName)
                principale.post {
                    visteWiFi.remove(nome)
                    computer.removeAll { it.nome == nome && !it.viaCavo }
                    // Visto anche sul cavo: resta, solo con gli indirizzi del cavo (finché il cavo lo vede).
                    val indice = computer.indexOfFirst { it.nome == nome && it.viaCavo }
                    if (indice >= 0) {
                        val delCavo = indirizziCavo[nome].orEmpty()
                        val restano = computer[indice].indirizzi.filter { it in delCavo }
                        if (restano.isEmpty()) computer.removeAt(indice) else computer[indice] = computer[indice].copy(indirizzi = restano)
                    }
                }
            }
        }
        ascoltatore = nuovo
        try {
            nsd.discoverServices(Servizio.TIPO_BONJOUR, NsdManager.PROTOCOL_DNS_SD, nuovo)
        } catch (e: Exception) {
            Log.w(TAG, "Ricerca non partita", e)
            ascoltatore = null
            stato = Stato.ERRORE
            cavoSolo = true
        }
    }

    fun ferma() {
        ricercaCavo.ferma()
        cavoSolo = false
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
        val numero = ++risoluzioneAttuale
        // I callback arrivano su un thread di NsdManager: tutto il resto si fa sul thread principale.
        val ascolto = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, errore: Int) {
                principale.post {
                    if (numero != risoluzioneAttuale || !risolvendo) return@post
                    principale.removeCallbacks(scadenzaRisoluzione)
                    ascoltoRisoluzione = null
                    risolvendo = false
                    // Già in corso: si riprova tra poco.
                    if (errore == NsdManager.FAILURE_ALREADY_ACTIVE) {
                        mettiInCoda(info)
                        principale.postDelayed({ risolviProssimo() }, attesaGiaAttiva)
                        attesaGiaAttiva = minOf(attesaGiaAttiva * 3, 3_000L)
                    } else {
                        risolviProssimo()
                    }
                }
            }

            override fun onServiceResolved(info: NsdServiceInfo) {
                val trovato = daRisolto(info)
                principale.post {
                    // Arrivata dopo la scadenza: il computer vale lo stesso (onServiceFound di solito non si ripete),
                    // ma la coda è già andata avanti e non si tocca.
                    if (numero != risoluzioneAttuale || !risolvendo) {
                        if (trovato != null && ascoltatore != null) aggiungi(trovato)
                        return@post
                    }
                    principale.removeCallbacks(scadenzaRisoluzione)
                    ascoltoRisoluzione = null
                    risolvendo = false
                    attesaGiaAttiva = 300L
                    if (trovato != null && ascoltatore != null) aggiungi(trovato)
                    risolviProssimo()
                }
            }
        }
        ascoltoRisoluzione = ascolto
        principale.removeCallbacks(scadenzaRisoluzione)
        principale.postDelayed(scadenzaRisoluzione, SCADENZA_RISOLUZIONE_MS)
        try {
            nsd.resolveService(info, ascolto)
        } catch (e: Exception) {
            principale.removeCallbacks(scadenzaRisoluzione)
            ascoltoRisoluzione = null
            risolvendo = false
            Log.w(TAG, "Risoluzione non riuscita", e)
        }
    }

    @Suppress("DEPRECATION")
    private fun daRisolto(info: NsdServiceInfo): ComputerTrovato? {
        // Solo IPv4, come nel QR code: gli indirizzi IPv6 di collegamento locale danno problemi su molti router.
        // Da Android 14 un computer può avere più indirizzi, e il primo può essere IPv6.
        val indirizzi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            info.hostAddresses.filterIsInstance<Inet4Address>()
        } else {
            listOfNotNull(info.host as? Inet4Address)
        }.mapNotNull { it.hostAddress }.distinct()
        if (indirizzi.isEmpty()) return null
        val attributi = try { info.attributes } catch (e: Exception) { emptyMap<String, ByteArray>() }
        val piattaforma = when (attributi["p"]?.toString(Charsets.UTF_8)) {
            "mac" -> Piattaforma.MAC
            "windows" -> Piattaforma.WINDOWS
            else -> null
        }
        return ComputerTrovato(
            nome = nomeLeggibile(info.serviceName),
            indirizzi = indirizzi,
            porta = if (info.port > 0) info.port else Servizio.PORTA_PREDEFINITA,
            piattaforma = piattaforma,
        )
    }

    companion object {
        private const val TAG = "WebcamLR"
        private const val SCADENZA_RISOLUZIONE_MS = 5_000L

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
