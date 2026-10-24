package it.lrapps.webcamlr.android.sessione

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.OrientationEventListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import it.lrapps.webcamlr.android.BuildConfig
import it.lrapps.webcamlr.android.dati.ComputerConosciuti
import it.lrapps.webcamlr.android.dati.IdentitaTelefono
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.rete.ComputerTrovato
import it.lrapps.webcamlr.android.sistema.Orologio
import it.lrapps.webcamlr.android.sistema.RegistroCollegamento
import it.lrapps.webcamlr.android.sistema.StatoDispositivo
import it.lrapps.webcamlr.android.video.Cattura
import it.lrapps.webcamlr.android.video.Codificatore
import it.lrapps.webcamlr.android.video.ObiettivoAndroid
import it.lrapps.webcamlr.android.video.Renderizzatore
import it.lrapps.webcamlr.protocollo.AdattamentoRete
import it.lrapps.webcamlr.protocollo.Approvazione
import it.lrapps.webcamlr.protocollo.Benvenuto
import it.lrapps.webcamlr.protocollo.Capacita
import it.lrapps.webcamlr.protocollo.Ciao
import it.lrapps.webcamlr.protocollo.Collegamento
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.EventoCollegamento
import it.lrapps.webcamlr.protocollo.FormatoVideo
import it.lrapps.webcamlr.protocollo.InOnda
import it.lrapps.webcamlr.protocollo.Latenza
import it.lrapps.webcamlr.protocollo.MotivoChiusura
import it.lrapps.webcamlr.protocollo.Piattaforma
import it.lrapps.webcamlr.protocollo.Sicurezza
import it.lrapps.webcamlr.protocollo.StatoTelefono
import it.lrapps.webcamlr.protocollo.Temperatura
import it.lrapps.webcamlr.protocollo.TipoCollegamento

/** La sessione in corso, una alla volta: la tiene il processo, così continua anche a schermo spento. */
object Sessioni {
    var attuale by mutableStateOf<SessioneTelefono?>(null)
        internal set
}

/**
 * Una sessione con un computer: collegamento, fotocamera, codifica e stato del telefono (come SessioneTelefono.swift).
 * Lo stato si legge e si cambia sul thread principale; Compose lo osserva.
 */
class SessioneTelefono(context: Context, computerIniziale: ComputerTrovato) {

    sealed interface Stato {
        data object Collegamento : Stato
        data object Collegato : Stato
        data class Riconnessione(val tentativo: Int) : Stato
        data object Chiusa : Stato
        data class Errore(val descrizione: String) : Stato
    }

    private val app = context.applicationContext
    private val principale = Handler(Looper.getMainLooper())

    var stato by mutableStateOf<Stato>(Stato.Collegamento)
        private set
    var computer by mutableStateOf(computerIniziale)
        private set
    var latenzaMs by mutableStateOf<Int?>(null)
        private set
    /** L'ultima latenza nota, che resta anche dopo la chiusura: serve a «Segnala un bug». */
    var ultimaLatenzaMs by mutableStateOf<Int?>(null)
        private set
    /** Un'app sul computer sta usando la webcam: il rosso «IN ONDA». */
    var inOnda by mutableStateOf<InOnda?>(null)
        private set
    var formato by mutableStateOf<FormatoVideo?>(null)
        private set
    var tipoCollegamento by mutableStateOf<TipoCollegamento?>(null)
        private set
    var obiettivo by mutableStateOf<ObiettivoAndroid?>(null)
        private set
    var torciaAccesa by mutableStateOf(false)
        private set
    var zoom by mutableStateOf(1.0)
        private set
    var iso by mutableStateOf(0.0)
        private set
    var tempo by mutableStateOf(0)
        private set
    var aeafBloccati by mutableStateOf(false)
        private set
    var batteria by mutableStateOf(-1)
        private set
    var inCarica by mutableStateOf(false)
        private set
    var temperatura by mutableStateOf(Temperatura.NORMALE)
        private set
    /** Il telefono è molto caldo: 720p e meno fotogrammi finché non torna normale (funzione 31). */
    var qualitaRidotta by mutableStateOf(false)
        private set
    /** Batteria sotto il 20% senza caricatore: 24 fps finché non si ricarica (novità 17). */
    var risparmioBatteria by mutableStateOf(false)
        private set
    /** La rete non regge la qualità scelta: il bitrate è sceso da solo (novità 4). */
    var reteDebole by mutableStateOf(false)
        private set
    /** Fotogrammi scartati negli ultimi 5 secondi, per la qualità del collegamento in parole. */
    var perditeRecenti by mutableStateOf(0)
        private set
    /** Il computer chiede di consentire questo telefono: il codice di conferma, uguale sui due schermi. */
    var codiceConferma by mutableStateOf<String?>(null)
        private set
    var titoloErrore by mutableStateOf("Collegamento interrotto")
        private set
    /** Riprovare non serve (identità del computer cambiata): si torna ai computer e si usa il QR code. */
    var erroreDefinitivo by mutableStateOf(false)
        private set
    /** La domanda frequente che spiega l'errore, per il link «Perché succede?». */
    var domandaErrore by mutableStateOf<String?>(null)
        private set
    var giaCollegato by mutableStateOf(false)
        private set
    /** Da quando (SystemClock.elapsedRealtime) si cerca di ritrovare il computer, per i secondi nel banner. */
    var inizioRiconnessione by mutableStateOf<Long?>(null)
        private set
    var reteDisponibile by mutableStateOf(true)
        private set
    /** Lo schermo è oscurato (funzione 32): il video continua. */
    var oscurato by mutableStateOf(false)

    val batteriaBassa: Boolean get() = batteria in 0..19 && !inCarica

    val renderizzatore = Renderizzatore()
    private val cattura = Cattura(app)
    val obiettivi: List<ObiettivoAndroid> get() = cattura.obiettivi
    val haTorcia: Boolean get() = cattura.haTorcia

    private val adattamento = AdattamentoRete()
    private val codificatore = Codificatore(
        suFotogramma = { fotogramma -> destinazione?.inviaVideo(fotogramma) },
        suErrore = { tipo -> principale.post { erroreCodifica(tipo) } },
    )

    /** Il collegamento che riceve il video: esiste solo dopo il `benvenuto`. Letto dal thread del codificatore. */
    @Volatile private var destinazione: Collegamento? = null
    private var collegamento: Collegamento? = null
    private var tentativi = 0
    private var chiusaDallUtente = false
    private var fotocameraPronta = false
    private var codificaAttiva = false
    private var improntaComputer: String? = null
    private val perditeUltimiSecondi = ArrayDeque<Int>()

    private var bloccoSveglia: PowerManager.WakeLock? = null
    private var bloccoWiFi: WifiManager.WifiLock? = null
    private var ascoltoRete: ConnectivityManager.NetworkCallback? = null
    private val orientamento = object : OrientationEventListener(app) {
        override fun onOrientationChanged(gradi: Int) {
            if (gradi == ORIENTATION_UNKNOWN) return
            val attuale = renderizzatore.rotazioneTelefono
            // Un po' di isteresi: si cambia solo quando si è ben dentro il nuovo quarto.
            val distanza = minOf(Math.floorMod(gradi - attuale, 360), Math.floorMod(attuale - gradi, 360))
            if (distanza > 55) renderizzatore.rotazioneTelefono = ((gradi + 45) / 90 % 4) * 90
        }
    }

    private val registro = RegistroCollegamento

    // Ciclo di vita

    fun avvia() {
        chiusaDallUtente = false
        tentativi = 0
        Sessioni.attuale = this
        mantieniSveglio(true)
        ServizioInOnda.avvia(app)
        if (orientamento.canDetectOrientation()) orientamento.enable()
        osservaRete()
        misuraStato()
        regolaQualita()
        obiettivo = obiettivi.firstOrNull { it.nome == Impostazioni.obiettivo } ?: obiettivi.firstOrNull { it.nome == "principale" }
            ?: obiettivi.firstOrNull()
        // La fotocamera si accende subito, mentre il collegamento si apre: al `benvenuto` il video è pronto.
        avviaFotocamera()
        collega()
    }

    fun termina() {
        if (!chiusaDallUtente) registro.aggiungi("Scollegato da ${computer.nome}")
        chiusaDallUtente = true
        principale.removeCallbacksAndMessages(null)
        destinazione = null
        collegamento?.chiudi()
        collegamento = null
        fermaCodifica()
        cattura.chiudiEAspetta()
        cattura.termina()
        renderizzatore.ferma()
        orientamento.disable()
        smettiDiOsservareRete()
        mantieniSveglio(false)
        ServizioInOnda.ferma(app)
        inizioRiconnessione = null
        stato = Stato.Chiusa
        if (Sessioni.attuale === this) Sessioni.attuale = null
    }

    fun riprova() {
        tentativi = 0
        erroreDefinitivo = false
        destinazione = null
        collegamento?.chiudi()
        collegamento = null
        if (!fotocameraPronta) avviaFotocamera()
        collega()
    }

    // Comandi dell'interfaccia

    fun scegli(nuovo: ObiettivoAndroid) {
        if (nuovo == obiettivo) return
        obiettivo = nuovo
        Impostazioni.obiettivo = nuovo.nome
        torciaAccesa = false
        zoom = 1.0
        aeafBloccati = false
        avviaFotocamera()
    }

    /** Doppio tocco: frontale ↔ posteriore. */
    fun cambiaFotocamera() {
        val nuovo = if (obiettivo?.frontale == true) obiettivi.firstOrNull { it.nome == "principale" } else obiettivi.firstOrNull { it.frontale }
        if (nuovo != null) scegli(nuovo)
    }

    fun impostaZoom(fattore: Double) {
        zoom = fattore.coerceIn(1.0, maxOf(1.0, cattura.zoomMassimo))
        cattura.impostaZoom(zoom)
    }

    fun cambiaTorcia() {
        if (!cattura.haTorcia) return
        torciaAccesa = !torciaAccesa
        cattura.impostaTorcia(torciaAccesa)
    }

    /** Specchia il video inviato (Impostazioni › «Specchia l'immagine inviata»), subito. */
    fun aggiornaSpecchio() {
        renderizzatore.specchiaCodifica = (obiettivo?.frontale == true) xor Impostazioni.specchia
    }

    /** Tocco sull'anteprima, in coordinate 0–1 dell'anteprima; `rotazioneSchermo` come quella del renderizzatore. */
    fun metteAFuoco(x: Float, y: Float, blocca: Boolean) {
        val (sx, sy) = puntoSulSensore(x, y, renderizzatore.rotazioneSchermo, cattura.orientamentoSensore, obiettivo?.frontale == true)
        cattura.metteAFuoco(sx, sy, blocca)
        aeafBloccati = blocca
    }

    // Collegamento

    private fun collega() {
        if (chiusaDallUtente) return
        stato = if (tentativi == 0) Stato.Collegamento else Stato.Riconnessione(tentativi)
        registro.aggiungi(
            if (tentativi == 0) "Collegamento a ${computer.nome}…"
            else "Nuovo tentativo $tentativi/$TENTATIVI_MASSIMI con ${computer.nome}",
        )
        codiceConferma = null
        improntaComputer = null
        val ciao = Ciao(
            versione = Sicurezza.VERSIONE_SICURA,
            nome = StatoDispositivo.nomeTelefono(app),
            piattaforma = Piattaforma.ANDROID,
            versioneApp = BuildConfig.VERSION_NAME,
        )
        lateinit var nuovo: Collegamento
        nuovo = Collegamento(
            indirizzi = computer.indirizzi,
            porta = computer.porta,
            identita = IdentitaTelefono.condivisa(app),
            // Protocollo 2: l'impronta attesa viene dal QR code, altrimenti dai computer conosciuti.
            improntaAttesa = computer.impronta ?: ComputerConosciuti.impronta(computer.nome),
            gettone = computer.gettone,
            ciao = ciao,
            orologio = Orologio::adesso,
            suEvento = { evento -> principale.post { gestisci(evento, nuovo) } },
            // Priorità video sul Wi-Fi (DSCP CS5 → coda «video» del Wi-Fi).
            preparaSocket = { socket -> runCatching { socket.trafficClass = 0xA0 } },
        )
        nuovo.suPerdita = { codificatore.richiediFotogrammaChiave() }
        nuovo.suSecondo = { scartati, saturo ->
            val debole = synchronized(adattamento) {
                val debole = adattamento.secondo(scartati, saturo)
                if (codificatore.bitrateBase > 0) codificatore.impostaBitrate(adattamento.bitrate(codificatore.bitrateBase))
                debole
            }
            principale.post { registraSecondo(scartati, debole) }
        }
        synchronized(adattamento) { adattamento.azzera() }
        perditeUltimiSecondi.clear()
        perditeRecenti = 0
        reteDebole = false
        collegamento = nuovo
        nuovo.avvia()
    }

    private fun gestisci(evento: EventoCollegamento, da: Collegamento) {
        if (da !== collegamento || chiusaDallUtente) return
        when (evento) {
            is EventoCollegamento.Pronto -> {
                improntaComputer = evento.impronta
                tipoCollegamento = TipoCollegamento.daInterfaccia(evento.interfaccia) ?: TipoCollegamento.WIFI
                registro.aggiungi("Collegamento sicuro riuscito, codice di sicurezza ${evento.impronta.take(8)}")
                tipoCollegamento?.let { registro.aggiungi("Collegamento via ${it.testo}") }
            }
            is EventoCollegamento.Ricevuto -> when (val messaggio = evento.messaggio) {
                is Approvazione -> {
                    codiceConferma = messaggio.codice
                    registro.aggiungi("Il computer chiede di confermare il codice")
                }
                is Benvenuto -> accolto(da, messaggio)
                is Latenza -> {
                    latenzaMs = messaggio.ms
                    ultimaLatenzaMs = messaggio.ms
                }
                is Comando -> applica(messaggio)
                is InOnda -> inOnda = if (messaggio.attivo) messaggio else null
                else -> Unit
            }
            is EventoCollegamento.Chiuso -> {
                val inAttesaDiConferma = codiceConferma != null
                codiceConferma = null
                collegamento = null
                destinazione = null
                principale.removeCallbacks(statoPeriodico)
                fermaCodifica()
                latenzaMs = null
                inOnda = null
                tipoCollegamento = null
                gestisciChiusura(evento.errore, evento.motivo, inAttesaDiConferma)
            }
        }
    }

    private fun accolto(da: Collegamento, benvenuto: Benvenuto) {
        codiceConferma = null
        giaCollegato = true
        // Da ora questo computer è conosciuto: la prossima volta la sua impronta deve essere la stessa.
        improntaComputer?.let { ComputerConosciuti.salva(it, computer.nome) }
        tentativi = 0
        stato = Stato.Collegato
        inizioRiconnessione = null
        registro.aggiungi("Collegato a ${computer.nome} (${benvenuto.piattaforma.valore})")
        Impostazioni.ultimoComputer = computer.nome
        destinazione = da
        principale.removeCallbacks(statoPeriodico)
        principale.post(statoPeriodico)
        if (fotocameraPronta) avviaCodifica()
    }

    /** Il collegamento si è chiuso: si riprova, oppure ci si ferma dicendo perché e cosa fare. */
    private fun gestisciChiusura(errore: String?, motivo: MotivoChiusura, inAttesaDiConferma: Boolean) {
        registro.aggiungi("Collegamento chiuso: ${motivo.perRegistro}" + (errore?.let { " ($it)" } ?: ""))
        val nome = computer.nome
        // Chiuso mentre si aspettava la conferma: il computer ha detto no, o nessuno ha risposto.
        if (inAttesaDiConferma && (motivo == MotivoChiusura.RETE || motivo == MotivoChiusura.DAL_COMPUTER)) {
            fermaConErrore("Collegamento non confermato",
                "Il collegamento non è stato consentito su $nome. Tocca «Riprova» e conferma sul computer.", domanda = "codice")
            return
        }
        when (motivo) {
            MotivoChiusura.RETE -> Unit
            MotivoChiusura.DAL_COMPUTER -> {
                fermaConErrore(if (giaCollegato) "Collegamento interrotto" else "Non riesco a collegarmi a $nome",
                    "$nome ha chiuso il collegamento. Tocca «Riprova» per collegarti di nuovo.")
                return
            }
            MotivoChiusura.COMPUTER_VECCHIO -> {
                fermaConErrore("Aggiorna WebcamLR sul computer",
                    "Su $nome c'è una versione di WebcamLR senza collegamento sicuro. Aggiornala dal sito di WebcamLR, poi tocca «Riprova».",
                    domanda = "aggiorna")
                return
            }
            MotivoChiusura.IDENTITA_CAMBIATA -> {
                if (Impostazioni.ultimoComputer == nome) Impostazioni.ultimoComputer = null
                fermaConErrore("Computer da collegare di nuovo",
                    "$nome non è più lo stesso computer per il telefono (per esempio dopo averlo reinstallato). Tocca «Torna ai computer» e collegalo di nuovo con «Inquadra il QR code del computer».",
                    definitivo = true, domanda = "identita")
                return
            }
            MotivoChiusura.IDENTITA_NON_VALIDA -> {
                fermaConErrore("Collegamento non sicuro",
                    "$nome non ha superato il controllo di sicurezza. Tocca «Riprova», oppure torna ai computer e collegati con il QR code.",
                    domanda = "identita")
                return
            }
        }
        // Senza rete non si consumano tentativi: si riparte appena torna.
        if (!reteDisponibile) {
            if (inizioRiconnessione == null) inizioRiconnessione = SystemClock.elapsedRealtime()
            stato = Stato.Riconnessione(maxOf(tentativi, 1))
            return
        }
        if (tentativi < TENTATIVI_MASSIMI) {
            if (inizioRiconnessione == null) inizioRiconnessione = SystemClock.elapsedRealtime()
            tentativi++
            stato = Stato.Riconnessione(tentativi)
            // Il primo tentativo quasi subito (spesso è solo un attimo di Wi-Fi), poi ogni 2 secondi.
            principale.postDelayed({
                if (!chiusaDallUtente && collegamento == null && stato is Stato.Riconnessione) collega()
            }, if (tentativi == 1) 500L else 2_000L)
        } else if (!giaCollegato && computer.annunciato) {
            fermaConErrore("La rete tiene separati i dispositivi",
                "Il computer si vede ma non risponde: molte reti di hotel, uffici e scuole non fanno parlare i dispositivi tra loro. Su Windows può essere il firewall: consenti WebcamLR per le reti private. Oppure usa il tethering USB o l'hotspot del telefono.",
                domanda = "rete-ospiti")
        } else {
            fermaConErrore(if (giaCollegato) "Collegamento interrotto" else "Non riesco a collegarmi a $nome",
                errore ?: "Il computer non risponde: controlla che WebcamLR sia aperto sul computer e che siate sulla stessa rete Wi-Fi, poi tocca «Riprova».",
                domanda = if (giaCollegato) null else "non-trova")
        }
    }

    private fun fermaConErrore(titolo: String, descrizione: String, definitivo: Boolean = false, domanda: String? = null) {
        principale.removeCallbacksAndMessages(null)
        inizioRiconnessione = null
        titoloErrore = titolo
        erroreDefinitivo = definitivo
        domandaErrore = domanda
        registro.aggiungi("Fermo: $titolo")
        // Lo schermo oscurato coprirebbe il pannello con «Riprova»: si riaccende.
        oscurato = false
        stato = Stato.Errore(descrizione)
    }

    private fun registraSecondo(scartati: Int, debole: Boolean) {
        perditeUltimiSecondi.addLast(scartati)
        if (perditeUltimiSecondi.size > 5) perditeUltimiSecondi.removeFirst()
        val somma = perditeUltimiSecondi.sum()
        if (somma != perditeRecenti) perditeRecenti = somma
        if (debole != reteDebole) reteDebole = debole
    }

    // Fotocamera e codifica

    private fun dimensioniVolute(): Triple<Int, Int, Int> {
        var (larghezza, altezza) = Impostazioni.dimensioni
        var fps = Impostazioni.fps
        if (qualitaRidotta) {
            larghezza = minOf(larghezza, 1280)
            altezza = minOf(altezza, 720)
            fps = minOf(fps, 24)
        }
        if (risparmioBatteria) fps = minOf(fps, 24)
        return Triple(larghezza, altezza, fps)
    }

    private fun avviaFotocamera() {
        val scelto = obiettivo ?: run {
            fermaConErrore("Fotocamera non disponibile", "Il telefono non ha una fotocamera utilizzabile da WebcamLR.")
            return
        }
        fotocameraPronta = false
        val ricodifica = codificaAttiva
        fermaCodifica()
        val (larghezza, altezza, fps) = dimensioniVolute()
        // La fotocamera smette di scrivere prima che la vecchia superficie si butti.
        cattura.chiudiEAspetta()
        val superficie = try {
            val dimensione = cattura.dimensionePer(scelto, larghezza, altezza)
            renderizzatore.avvia(dimensione.width, dimensione.height, cattura.orientamentoDi(scelto))
        } catch (e: Exception) {
            fermaConErrore("Fotocamera non disponibile", "La fotocamera non si è accesa: tocca «Riprova», e se succede ancora riavvia il telefono.")
            return
        }
        aggiornaSpecchio()
        cattura.apri(scelto, fps, listOf(superficie)) { errore ->
            principale.post {
                if (chiusaDallUtente) return@post
                if (errore != null) {
                    if (stato !is Stato.Errore) {
                        titoloErrore = "Fotocamera non disponibile"
                        erroreDefinitivo = false
                        domandaErrore = null
                        oscurato = false
                        stato = Stato.Errore(errore)
                    }
                    return@post
                }
                fotocameraPronta = true
                // I comandi del computer restano anche cambiando obiettivo.
                if (zoom != 1.0) cattura.impostaZoom(zoom)
                if (torciaAccesa) cattura.impostaTorcia(true)
                if (iso != 0.0 || tempo != 0) cattura.impostaManuale(iso, tempo)
                if (destinazione != null || ricodifica) avviaCodifica()
                aggiornaStato()
            }
        }
    }

    /** Crea il codificatore per questo collegamento: il computer riceve `formato`, `capacita` e un fotogramma chiave. */
    private fun avviaCodifica() {
        val verso = destinazione ?: return
        fermaCodifica()
        val (larghezza, altezza, fps) = dimensioniVolute()
        try {
            val superficie = codificatore.avvia(larghezza, altezza, fps, Impostazioni.codecScelto) { base ->
                synchronized(adattamento) { adattamento.bitrate(base) }
            }
            val effettivo = codificatore.formato ?: return
            renderizzatore.impostaCodifica(superficie, effettivo.larghezza, effettivo.altezza)
            codificaAttiva = true
            formato = effettivo
            verso.invia(effettivo)
            inviaCapacita()
            registro.aggiungi("Video ${effettivo.larghezza}×${effettivo.altezza}, ${effettivo.fps} fps, ${nomeCodec(effettivo)}")
        } catch (e: Exception) {
            fermaConErrore("Video non disponibile",
                "Il codificatore video del telefono non è partito: scegli un'altra risoluzione o H.264 in Impostazioni, poi tocca «Riprova».")
        }
    }

    private fun fermaCodifica() {
        // Prima si smette di disegnare sulla superficie, poi si ferma il codificatore.
        renderizzatore.impostaCodifica(null, 0, 0)
        codificatore.ferma()
        codificaAttiva = false
    }

    private fun erroreCodifica(tipo: String) {
        if (chiusaDallUtente || tipo == "transitorio") return
        registro.aggiungi("Codificatore fermo: lo riavvio")
        if (destinazione != null) avviaCodifica()
    }

    /** Comandi della fotocamera dal computer: solo i campi presenti. */
    private fun applica(comando: Comando) {
        comando.obiettivo?.let { nome -> obiettivi.firstOrNull { it.nome == nome }?.let { scegli(it) } }
        comando.zoom?.let { impostaZoom(it) }
        comando.torcia?.let { accesa -> if (accesa != torciaAccesa && cattura.haTorcia) cambiaTorcia() }
        comando.esposizione?.let { cattura.impostaEsposizione(it) }
        comando.bianco?.let { cattura.impostaBianco(if (it == 0) 0 else it.coerceIn(2500, 7500)) }
        if (comando.fuoco == "continuo") {
            cattura.fuocoContinuo()
            aeafBloccati = false
        }
        if (comando.iso != null || comando.tempo != null) {
            iso = maxOf(comando.iso ?: iso, 0.0)
            tempo = maxOf(comando.tempo ?: tempo, 0)
            cattura.impostaManuale(iso, tempo)
        }
    }

    /** Dice al computer cosa può comandare con l'obiettivo attuale. */
    private fun inviaCapacita() {
        val limiti = cattura.limitiIso
        destinazione?.invia(
            Capacita(
                obiettivi = obiettivi.map { it.nome },
                zoomMassimo = cattura.zoomMassimo,
                torcia = cattura.haTorcia,
                isoMinimo = limiti?.first,
                isoMassimo = limiti?.second,
            ),
        )
    }

    // Stato del telefono

    private val statoPeriodico = object : Runnable {
        override fun run() {
            aggiornaStato()
            principale.postDelayed(this, 5_000)
        }
    }

    private fun aggiornaStato() {
        misuraStato()
        destinazione?.invia(StatoTelefono(batteria, inCarica, temperatura, obiettivo?.nome ?: "principale"))
        if (regolaQualita()) avviaFotocamera()
    }

    private fun misuraStato() {
        val misura = StatoDispositivo.misura(app)
        if (misura.batteria != batteria) batteria = misura.batteria
        if (misura.inCarica != inCarica) inCarica = misura.inCarica
        if (misura.temperatura != temperatura) temperatura = misura.temperatura
    }

    /**
     * Scende a 720p e 24 fps quando è molto caldo e torna alla qualità scelta solo a temperatura normale; 24 fps con la
     * batteria sotto il 20% senza caricatore, fino al 25% o al caricatore. Vero se la fotocamera va riconfigurata.
     */
    private fun regolaQualita(): Boolean {
        var cambiata = false
        val caldo = temperatura == Temperatura.MOLTO_CALDA || temperatura == Temperatura.CRITICA
        if (Impostazioni.riduciSeCaldo && caldo && !qualitaRidotta) {
            qualitaRidotta = true
            cambiata = true
        } else if (qualitaRidotta && (temperatura == Temperatura.NORMALE || !Impostazioni.riduciSeCaldo)) {
            qualitaRidotta = false
            cambiata = true
        }
        if (Impostazioni.risparmioBatteria && batteriaBassa && !risparmioBatteria) {
            risparmioBatteria = true
            cambiata = true
        } else if (risparmioBatteria && (!Impostazioni.risparmioBatteria || inCarica || batteria >= 25)) {
            risparmioBatteria = false
            cambiata = true
        }
        return cambiata
    }

    // Sistema

    /** Processore e Wi-Fi svegli mentre si manda il video, anche a schermo spento. */
    private fun mantieniSveglio(attivo: Boolean) {
        if (attivo) {
            val energia = app.getSystemService(Context.POWER_SERVICE) as PowerManager
            bloccoSveglia = energia.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "WebcamLR:video").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L)
            }
            val wifi = app.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            @Suppress("DEPRECATION")
            val modo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            bloccoWiFi = wifi?.createWifiLock(modo, "WebcamLR:video")?.apply {
                setReferenceCounted(false)
                runCatching { acquire() }
            }
        } else {
            runCatching { bloccoSveglia?.release() }
            runCatching { bloccoWiFi?.release() }
            bloccoSveglia = null
            bloccoWiFi = null
        }
    }

    private fun osservaRete() {
        val connessioni = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val ascolto = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(rete: Network) {
                principale.post { reteCambiata(true) }
            }

            override fun onLost(rete: Network) {
                principale.post { reteCambiata(connessioni.activeNetwork != null) }
            }
        }
        reteDisponibile = connessioni.activeNetwork != null
        try {
            connessioni.registerDefaultNetworkCallback(ascolto)
            ascoltoRete = ascolto
        } catch (e: Exception) {
            ascoltoRete = null
        }
    }

    private fun smettiDiOsservareRete() {
        val connessioni = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        ascoltoRete?.let { runCatching { connessioni.unregisterNetworkCallback(it) } }
        ascoltoRete = null
    }

    /** La rete è tornata mentre si cercava il computer: si riprova subito, da capo con i tentativi. */
    private fun reteCambiata(disponibile: Boolean) {
        val tornata = disponibile && !reteDisponibile
        if (disponibile != reteDisponibile) {
            reteDisponibile = disponibile
            registro.aggiungi(if (disponibile) "Rete tornata" else "Rete persa")
        }
        if (tornata && !chiusaDallUtente && collegamento == null && stato is Stato.Riconnessione) {
            tentativi = 1
            collega()
        }
    }

    companion object {
        const val TENTATIVI_MASSIMI = 5

        fun nomeCodec(formato: FormatoVideo) = if (formato.codec.valore == "hevc") "HEVC" else "H.264"

        /**
         * Da un punto dell'anteprima (0–1, y verso il basso) al punto sul sensore: si toglie la rotazione dello schermo,
         * lo specchio della frontale e l'orientamento del sensore. Il ritaglio dell'anteprima si trascura.
         */
        fun puntoSulSensore(x: Float, y: Float, rotazioneSchermo: Int, orientamentoSensore: Int, frontale: Boolean): Pair<Float, Float> {
            // Ruotare l'immagine di 90° in senso orario porta (x, y) in (1 − y, x); per tornare indietro si fa il contrario.
            fun antiorario(punto: Pair<Float, Float>, gradi: Int): Pair<Float, Float> {
                var (px, py) = punto
                repeat(Math.floorMod(gradi, 360) / 90) {
                    val nx = py
                    val ny = 1f - px
                    px = nx
                    py = ny
                }
                return px to py
            }
            var punto = antiorario(x to y, rotazioneSchermo)
            if (frontale) punto = (1f - punto.first) to punto.second
            return antiorario(punto, orientamentoSensore)
        }
    }
}

private val MotivoChiusura.perRegistro: String
    get() = when (this) {
        MotivoChiusura.RETE -> "rete persa o computer che non risponde"
        MotivoChiusura.DAL_COMPUTER -> "chiuso dal computer"
        MotivoChiusura.COMPUTER_VECCHIO -> "versione vecchia sul computer"
        MotivoChiusura.IDENTITA_CAMBIATA -> "identità del computer cambiata"
        MotivoChiusura.IDENTITA_NON_VALIDA -> "controllo di sicurezza non superato"
    }
