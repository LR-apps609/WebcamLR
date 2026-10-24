package it.lrapps.webcamlr.protocollo

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Perché un collegamento si è chiuso: decide se riprovare da soli o fermarsi e spiegare. */
enum class MotivoChiusura {
    /** Rete persa, computer spento, dati rovinati: si può riprovare da soli. */
    RETE,

    /** Il computer ha chiuso di proposito («Scollega», o il collegamento non è stato consentito): non si riprova da soli. */
    DAL_COMPUTER,

    /** Il computer parla il protocollo 1: va aggiornato. */
    COMPUTER_VECCHIO,

    /** L'impronta del computer non è quella attesa: va riabbinato con il QR code. */
    IDENTITA_CAMBIATA,

    /** Il computer non ha dimostrato di avere la sua chiave. */
    IDENTITA_NON_VALIDA,
}

/** Gli eventi di un [Collegamento], dal suo thread: chi li riceve li porta sul thread dell'interfaccia. */
sealed interface EventoCollegamento {
    /** Stretta di mano riuscita e prova spedita; il `ciao` è già partito. `impronta` è quella del computer. */
    data class Pronto(val impronta: String, val codice: String, val interfaccia: String?) : EventoCollegamento

    /** Un messaggio dal computer (i `ping` hanno già avuto risposta, `arrivederci` chiude). */
    data class Ricevuto(val messaggio: Messaggio) : EventoCollegamento

    data class Chiuso(val errore: String?, val motivo: MotivoChiusura) : EventoCollegamento
}

/** I tempi del collegamento; nei test si accorciano. */
data class TempiCollegamento(
    /** Oltre questo tempo senza connessione TCP si rinuncia (per ogni indirizzo, tutti insieme). */
    val connessioneMs: Long = 8_000,
    /** Un computer versione 2 risponde alla stretta di mano subito; uno versione 1 mai. */
    val strettaMs: Long = 5_000,
    /** Dopo la prova, se il telefono è già fidato il `benvenuto` arriva subito. */
    val benvenutoMs: Long = 10_000,
    /** Il computer chiede all'utente e aspetta 60 secondi: qualche secondo in più per la rete. */
    val confermaMs: Long = 65_000,
    /** Dopo il `benvenuto` il computer manda un `ping` al secondo: senza nulla per questo tempo, collegamento perso. */
    val silenzioMs: Long = 6_000,
    val secondoMs: Long = 1_000,
)

/**
 * La connessione TCP con il computer, dal lato del telefono (Documenti/Protocollo.md): stretta di mano in chiaro,
 * poi prova, `ciao` e tutto il resto cifrato. Ai `ping` risponde da sola, senza passare dall'interfaccia,
 * per misurare la latenza vera. Gli stessi passi di iPhone/Sorgenti/Collegamento.swift.
 *
 * Tre thread: lettura, scrittura (cifra subito prima di scrivere, così i contatori seguono l'ordine di invio)
 * e un orologio per le attese. Il video passa da una coda corta: se la rete non sta al passo i fotogrammi
 * si scartano fino al prossimo fotogramma chiave.
 */
class Collegamento(
    private val indirizzi: List<String>,
    private val porta: Int,
    identita: Firmatario,
    /** Dal QR code, oppure salvata dopo il primo `benvenuto`; `null` = prima volta dalla ricerca. */
    private val improntaAttesa: String?,
    private val gettone: String?,
    private val ciao: Ciao,
    /** L'orologio del telefono in microsecondi, lo stesso dei timestamp dei fotogrammi. */
    private val orologio: () -> ULong,
    private val suEvento: (EventoCollegamento) -> Unit,
    private val tempi: TempiCollegamento = TempiCollegamento(),
    /** Per esempio la priorità video sul Wi-Fi; chiamata prima di `connect`. */
    private val preparaSocket: (Socket) -> Unit = {},
) {
    /** Una volta al secondo: fotogrammi scartati e se la rete era satura (quasi sempre fotogrammi in attesa). */
    @Volatile
    var suSecondo: ((scartati: Int, saturo: Boolean) -> Unit)? = null

    /** Chiamata quando un fotogramma è stato scartato: serve un fotogramma chiave. */
    @Volatile
    var suPerdita: (() -> Unit)? = null

    private val stretta = StrettaTelefono(identita)
    private val chiuso = AtomicBoolean(false)
    private val orologioAttese: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "webcamlr-attese").apply { isDaemon = true }
    }
    private val coda = LinkedBlockingDeque<DaSpedire>()
    private val videoInCoda = AtomicInteger(0)

    @Volatile private var socket: Socket? = null
    @Volatile private var canale: CanaleCifrato? = null
    @Volatile private var accolto = false
    @Volatile private var congedato = false
    @Volatile private var codiceConferma: String? = null
    @Volatile private var ultimoDato = System.nanoTime()
    @Volatile private var attendiChiave = true
    private var attesaBenvenuto: ScheduledFuture<*>? = null

    private val scartatiNelSecondo = AtomicInteger(0)
    private val inviatiNelSecondo = AtomicInteger(0)
    private val pieniNelSecondo = AtomicInteger(0)

    private sealed interface DaSpedire {
        class Chiaro(val pacchetto: Pacchetto) : DaSpedire
        class Cifrato(val pacchetto: Pacchetto, val video: Boolean) : DaSpedire
        object Fine : DaSpedire
    }

    val eChiuso: Boolean get() = chiuso.get()

    fun avvia() {
        Thread({ apri() }, "webcamlr-collegamento").apply { isDaemon = true }.start()
    }

    /** Chiusura voluta: `arrivederci` cifrato, poi la connessione si chiude (al massimo dopo un secondo). */
    fun chiudi() {
        if (chiuso.get()) return
        if (canale != null) {
            coda.offer(DaSpedire.Cifrato(CodificaMessaggi.comePacchetto(Arrivederci), video = false))
            coda.offer(DaSpedire.Fine)
            pianifica(1_000) { termina(null, null, avvisa = false) }
        } else {
            termina(null, null, avvisa = false)
        }
    }

    fun invia(messaggio: Messaggio) {
        if (chiuso.get() || canale == null) return
        coda.offer(DaSpedire.Cifrato(CodificaMessaggi.comePacchetto(messaggio), video = false))
    }

    /**
     * Spedisce un fotogramma, oppure lo scarta se la rete non sta al passo.
     * Dopo uno scarto aspetta il prossimo fotogramma chiave, altrimenti il video si rovina.
     */
    fun inviaVideo(fotogramma: FotogrammaVideo) {
        if (chiuso.get() || canale == null) return
        if (attendiChiave && !fotogramma.chiave) return
        val inCoda = videoInCoda.get()
        if (inCoda >= MASSIMO_IN_VOLO && !fotogramma.chiave) {
            attendiChiave = true
            scartatiNelSecondo.incrementAndGet()
            suPerdita?.invoke()
            return
        }
        attendiChiave = false
        inviatiNelSecondo.incrementAndGet()
        if (inCoda >= MASSIMO_IN_VOLO - 1) pieniNelSecondo.incrementAndGet()
        videoInCoda.incrementAndGet()
        coda.offer(DaSpedire.Cifrato(fotogramma.pacchetto, video = true))
    }

    /** Il flusso audio per cui questo collegamento ha già mandato `formato-audio`. */
    private var flussoAudio: Int? = null

    /**
     * Un pacchetto audio AAC (protocollo, «Audio»), solo dopo il `benvenuto`. Prima del primo pacchetto di ogni
     * flusso (e su ogni collegamento nuovo) parte `formato-audio`, nella stessa coda: l'ordine è garantito.
     * L'audio non si scarta con la rete lenta: è poco (circa 8 kB al secondo) e un buco si sente più di un
     * fotogramma perso. Come `inviaAudio` di iPhone/Sorgenti/Collegamento.swift.
     */
    fun inviaAudio(pacchetto: PacchettoAudio, flusso: Int, formato: FormatoAudio = FormatoAudio()) {
        if (chiuso.get() || canale == null || !accolto) return
        synchronized(this) {
            if (flussoAudio != flusso) {
                flussoAudio = flusso
                coda.offer(DaSpedire.Cifrato(CodificaMessaggi.comePacchetto(formato), video = false))
            }
            coda.offer(DaSpedire.Cifrato(pacchetto.pacchetto, video = false))
        }
    }

    // Connessione

    private fun apri() {
        val aperto = connetti() ?: run {
            termina("Il computer non risponde: controlla che WebcamLR sia aperto sul computer, poi tocca «Riprova».", null)
            return
        }
        if (chiuso.get()) {
            chiudiSilenzioso(aperto)
            return
        }
        socket = aperto
        Thread({ scrivi(aperto.getOutputStream()) }, "webcamlr-scrittura").apply { isDaemon = true }.start()
        try {
            orologioAttese.scheduleAtFixedRate({ chiudiSecondo() }, tempi.secondoMs, tempi.secondoMs, TimeUnit.MILLISECONDS)
        } catch (e: RejectedExecutionException) {
            return // chiuso nel frattempo
        }
        // Il primo pacchetto, l'unico che il telefono manda in chiaro.
        coda.offer(DaSpedire.Chiaro(CodificaMessaggi.comePacchetto(stretta.apertura)))
        pianifica(tempi.strettaMs) {
            if (!chiuso.get() && canale == null) termina(null, MotivoChiusura.COMPUTER_VECCHIO)
        }
        leggi(aperto.getInputStream())
    }

    /** 1.10: tutti gli indirizzi insieme, vince il primo che risponde. */
    private fun connetti(): Socket? {
        if (indirizzi.isEmpty()) return null
        val vincitore = java.util.concurrent.atomic.AtomicReference<Socket?>(null)
        val finiti = java.util.concurrent.CountDownLatch(indirizzi.size)
        val trovato = java.util.concurrent.CountDownLatch(1)
        for (indirizzo in indirizzi) {
            Thread({
                val prova = Socket()
                try {
                    preparaSocket(prova)
                    prova.tcpNoDelay = true
                    prova.connect(InetSocketAddress(indirizzo, porta), tempi.connessioneMs.toInt())
                    if (vincitore.compareAndSet(null, prova)) trovato.countDown() else chiudiSilenzioso(prova)
                } catch (e: Exception) {
                    chiudiSilenzioso(prova)
                } finally {
                    finiti.countDown()
                    if (finiti.count == 0L) trovato.countDown()
                }
            }, "webcamlr-connessione").apply { isDaemon = true }.start()
        }
        trovato.await(tempi.connessioneMs + 500, TimeUnit.MILLISECONDS)
        // Se nessuno ha vinto entro il tempo, quelli in ritardo si chiudono da soli (il posto è già preso).
        if (vincitore.get() == null) vincitore.compareAndSet(null, Socket())
        val socket = vincitore.get()
        return if (socket != null && socket.isConnected) socket else null
    }

    private fun scrivi(uscita: OutputStream) {
        try {
            while (true) {
                val elemento = coda.take()
                when (elemento) {
                    is DaSpedire.Fine -> {
                        uscita.flush()
                        termina(null, null, avvisa = false)
                        return
                    }
                    is DaSpedire.Chiaro -> uscita.write(elemento.pacchetto.codificato())
                    is DaSpedire.Cifrato -> {
                        val attuale = canale ?: continue
                        try {
                            uscita.write(attuale.cifra(elemento.pacchetto).codificato())
                        } finally {
                            if (elemento.video) videoInCoda.decrementAndGet()
                        }
                    }
                }
                if (coda.isEmpty()) uscita.flush()
            }
        } catch (e: InterruptedException) {
            // chiusura
        } catch (e: IOException) {
            termina(null, null)
        }
    }

    private fun leggi(ingresso: InputStream) {
        val lettore = LettorePacchetti()
        val buffer = ByteArray(64 * 1024)
        try {
            while (!chiuso.get()) {
                val letti = ingresso.read(buffer)
                if (letti < 0) break
                if (letti == 0) continue
                ultimoDato = System.nanoTime()
                lettore.aggiungi(buffer, 0, letti)
                while (!chiuso.get()) {
                    val pacchetto = lettore.prossimo() ?: break
                    gestisci(pacchetto)
                }
            }
            termina(null, null)
        } catch (e: ErroreProtocollo) {
            termina("Il computer ha mandato dati non validi: tocca «Riprova», e se succede ancora riapri WebcamLR sul computer.", null)
        } catch (e: IOException) {
            termina(null, null)
        }
    }

    // Stretta di mano

    /** Prima del canale cifrato arriva solo la stretta di mano del computer, in chiaro. */
    private fun gestisciStretta(pacchetto: Pacchetto) {
        val messaggio = try {
            if (pacchetto.tipo != TipoPacchetto.CONTROLLO || pacchetto.flag and CanaleCifrato.FLAG_CIFRATO != 0) null
            else CodificaMessaggi.daPacchetto(pacchetto)
        } catch (e: ErroreProtocollo) {
            null
        }
        if (messaggio == null) {
            termina("Il computer ha mandato dati non validi: tocca «Riprova», e se succede ancora riapri WebcamLR sul computer.", null)
            return
        }
        // Un computer versione 1 parte subito con i `ping` in chiaro, senza stretta di mano.
        if (messaggio !is Stretta || messaggio.versione != Sicurezza.VERSIONE_SICURA) {
            termina(null, MotivoChiusura.COMPUTER_VECCHIO)
            return
        }
        val (sessione, prova) = try {
            // Il gettone del QR code va solo al computer di cui si è verificata l'impronta.
            stretta.completa(messaggio, if (improntaAttesa == null) null else gettone)
        } catch (e: Exception) {
            termina(null, MotivoChiusura.IDENTITA_NON_VALIDA)
            return
        }
        val impronta = sessione.improntaAltro
        if (improntaAttesa != null && improntaAttesa != impronta) {
            termina(null, MotivoChiusura.IDENTITA_CAMBIATA)
            return
        }
        codiceConferma = sessione.codice
        canale = sessione.canale
        coda.offer(DaSpedire.Cifrato(CodificaMessaggi.comePacchetto(prova), video = false))
        coda.offer(DaSpedire.Cifrato(CodificaMessaggi.comePacchetto(ciao), video = false))
        attendiBenvenuto(tempi.benvenutoMs)
        val interfaccia = try {
            socket?.localAddress?.let { java.net.NetworkInterface.getByInetAddress(it)?.name }
        } catch (e: Exception) {
            null
        }
        suEvento(EventoCollegamento.Pronto(impronta, sessione.codice, interfaccia))
    }

    /** Senza `benvenuto` entro il tempo si chiude; un'`approvazione` allunga l'attesa. */
    @Synchronized
    private fun attendiBenvenuto(millisecondi: Long) {
        attesaBenvenuto?.cancel(false)
        attesaBenvenuto = pianifica(millisecondi) {
            if (!chiuso.get() && !accolto) {
                termina("Il computer non ha risposto in tempo: controlla che WebcamLR sia aperto sul computer, poi tocca «Riprova».", null)
            }
        }
    }

    private fun gestisci(ricevuto: Pacchetto) {
        val attuale = canale
        if (attuale == null) {
            gestisciStretta(ricevuto)
            return
        }
        // Un pacchetto ripetuto, mancante o alterato chiude il collegamento.
        val pacchetto = try {
            attuale.decifra(ricevuto)
        } catch (e: ErroreProtocollo) {
            termina("Dati non validi dal computer: collegamento chiuso per sicurezza. Tocca «Riprova».", null)
            return
        }
        if (pacchetto.tipo != TipoPacchetto.CONTROLLO) return
        val messaggio = try {
            CodificaMessaggi.daPacchetto(pacchetto)
        } catch (e: ErroreProtocollo) {
            return
        }
        when (messaggio) {
            is Ping -> invia(Pong(messaggio.t, orologio()))
            is Arrivederci -> {
                congedato = true
                termina(null, MotivoChiusura.DAL_COMPUTER)
            }
            is Approvazione -> {
                // Il codice deve essere quello calcolato qui: chi sta in mezzo potrebbe inoltrare quello del computer.
                if (messaggio.codice != codiceConferma) {
                    termina(null, MotivoChiusura.IDENTITA_NON_VALIDA)
                    return
                }
                attendiBenvenuto(tempi.confermaMs)
                suEvento(EventoCollegamento.Ricevuto(messaggio))
            }
            is Benvenuto -> {
                accolto = true
                synchronized(this) { attesaBenvenuto?.cancel(false) }
                suEvento(EventoCollegamento.Ricevuto(messaggio))
            }
            is Sconosciuto -> Unit
            else -> suEvento(EventoCollegamento.Ricevuto(messaggio))
        }
    }

    /** Il bilancio di ogni secondo di invio, e il controllo del silenzio. */
    private fun chiudiSecondo() {
        if (chiuso.get()) return
        if (accolto && (System.nanoTime() - ultimoDato) / 1_000_000 >= tempi.silenzioMs) {
            termina(null, null)
            return
        }
        val inviati = inviatiNelSecondo.getAndSet(0)
        val pieni = pieniNelSecondo.getAndSet(0)
        val scartati = scartatiNelSecondo.getAndSet(0)
        // Satura: più di metà dei fotogrammi è partita con la coda quasi piena.
        val saturo = inviati > 0 && pieni * 2 > inviati
        try {
            suSecondo?.invoke(scartati, saturo)
        } catch (e: Exception) {
            // chi ascolta non deve fermare l'orologio
        }
    }

    /** Chiude tutto una volta sola. `avvisa` falso: chiusura chiesta da chi usa il collegamento, nessun evento. */
    private fun termina(errore: String?, motivo: MotivoChiusura?, avvisa: Boolean = true) {
        if (!chiuso.compareAndSet(false, true)) return
        socket?.let { chiudiSilenzioso(it) }
        coda.clear()
        coda.offer(DaSpedire.Fine)
        orologioAttese.shutdownNow()
        if (avvisa) {
            suEvento(EventoCollegamento.Chiuso(errore, motivo ?: if (congedato) MotivoChiusura.DAL_COMPUTER else MotivoChiusura.RETE))
        }
    }

    /** Un'attesa sull'orologio; dopo la chiusura non si pianifica più nulla. */
    private fun pianifica(millisecondi: Long, azione: () -> Unit): ScheduledFuture<*>? = try {
        orologioAttese.schedule(azione, millisecondi, TimeUnit.MILLISECONDS)
    } catch (e: RejectedExecutionException) {
        null
    }

    private fun chiudiSilenzioso(socket: Socket) {
        try {
            socket.close()
        } catch (e: IOException) {
            // già chiuso
        }
    }

    companion object {
        /** Oltre questo numero di fotogrammi non ancora spediti la rete è troppo lenta e si scarta. */
        const val MASSIMO_IN_VOLO = 3
    }
}
