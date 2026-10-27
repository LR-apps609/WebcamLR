package it.lrapps.webcamlr.android.sessione

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.RectF
import android.hardware.display.DisplayManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Size
import android.view.Display
import android.view.OrientationEventListener
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import it.lrapps.webcamlr.android.BuildConfig
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.acquisti.NegozioPro
import it.lrapps.webcamlr.android.audio.CodificatoreAudio
import it.lrapps.webcamlr.android.dati.ComputerConosciuti
import it.lrapps.webcamlr.android.dati.IdentitaTelefono
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.effetti.AnalisiImmagine
import it.lrapps.webcamlr.android.effetti.GraficaEffetti
import it.lrapps.webcamlr.android.logica.Annullabile
import it.lrapps.webcamlr.android.logica.ControlloPostura
import it.lrapps.webcamlr.android.logica.DecisorePausa
import it.lrapps.webcamlr.android.logica.FormatoRichiesto
import it.lrapps.webcamlr.android.logica.FormatoScelto
import it.lrapps.webcamlr.android.logica.FunzioniDisponibili
import it.lrapps.webcamlr.android.logica.LimitiGratis
import it.lrapps.webcamlr.android.logica.ModelloEffetti
import it.lrapps.webcamlr.android.logica.PreferenzeCollegamento
import it.lrapps.webcamlr.android.logica.RegolaCollegamento
import it.lrapps.webcamlr.android.logica.RegolatoreCalore
import it.lrapps.webcamlr.android.logica.RicetteFiltri
import it.lrapps.webcamlr.android.logica.RiduzioneCalore
import it.lrapps.webcamlr.android.logica.SceltaFormato
import it.lrapps.webcamlr.android.logica.SeguiLuce
import it.lrapps.webcamlr.android.logica.SfondiPronti
import it.lrapps.webcamlr.android.logica.StatoEffetti
import it.lrapps.webcamlr.android.logica.Strada
import it.lrapps.webcamlr.android.logica.VoltiTrovati
import it.lrapps.webcamlr.android.logica.limita
import it.lrapps.webcamlr.android.rete.CercaComputer
import it.lrapps.webcamlr.android.rete.ComputerTrovato
import it.lrapps.webcamlr.android.rete.RicercaCavo
import it.lrapps.webcamlr.android.rete.StradeRete
import it.lrapps.webcamlr.android.sistema.AscoltoCalore
import it.lrapps.webcamlr.android.sistema.Orologio
import it.lrapps.webcamlr.android.sistema.RegistroCollegamento
import it.lrapps.webcamlr.android.sistema.SensoreGravita
import it.lrapps.webcamlr.android.sistema.StatoDispositivo
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.android.video.Cattura
import it.lrapps.webcamlr.android.video.Codificatore
import it.lrapps.webcamlr.android.video.Geometria
import it.lrapps.webcamlr.android.video.ObiettivoAndroid
import it.lrapps.webcamlr.android.video.ParametriEffetti
import it.lrapps.webcamlr.android.video.ParametriGeometria
import it.lrapps.webcamlr.android.video.Renderizzatore
import it.lrapps.webcamlr.protocollo.AdattamentoRete
import it.lrapps.webcamlr.protocollo.Anteprima
import it.lrapps.webcamlr.protocollo.Approvazione
import it.lrapps.webcamlr.protocollo.Benvenuto
import it.lrapps.webcamlr.protocollo.Capacita
import it.lrapps.webcamlr.protocollo.Ciao
import it.lrapps.webcamlr.protocollo.Collegamento
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.ErroreCollegamento
import it.lrapps.webcamlr.protocollo.EventoCollegamento
import it.lrapps.webcamlr.protocollo.Filtri
import it.lrapps.webcamlr.protocollo.FormatoVideo
import it.lrapps.webcamlr.protocollo.InOnda
import it.lrapps.webcamlr.protocollo.Latenza
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.MotiviPausa
import it.lrapps.webcamlr.protocollo.MotivoChiusura
import it.lrapps.webcamlr.protocollo.Piattaforma
import it.lrapps.webcamlr.protocollo.Sicurezza
import it.lrapps.webcamlr.protocollo.StatoCollegamento
import it.lrapps.webcamlr.protocollo.StatoTelefono
import it.lrapps.webcamlr.protocollo.StradaCollegamento
import it.lrapps.webcamlr.protocollo.Temperatura
import it.lrapps.webcamlr.protocollo.TipoCollegamento
import it.lrapps.webcamlr.protocollo.UsaProspettiva
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** La sessione in corso, una alla volta: la tiene il processo, così continua anche a schermo spento. */
object Sessioni {
    var attuale by mutableStateOf<SessioneTelefono?>(null)
        internal set
}

/** I comandi della fotocamera come sono adesso (gli stessi di `stato`). */
data class ControlliFotocamera(
    val zoom: Double = 1.0,
    val torcia: Boolean = false,
    val esposizione: Double = 0.0,
    val bianco: Int = 0,
    val iso: Double = 0.0,
    val tempo: Int = 0,
)

/**
 * Una sessione con un computer: collegamento, fotocamera, effetti, microfono, pause e stato del telefono (come
 * SessioneTelefono.swift). Tutto sul thread principale.
 *
 * Per l'interfaccia (ui/Ponte.kt): gli stati di Compose di sempre (`stato`, `zoom`, `torciaAccesa`…) e i flussi nuovi
 * ([specchiato], [sfondo], [audioRichiesto], [pausa], [dimensioniVideo], [effetti], [funzioni], [controlli],
 * [avvisoPostura], [avvioSecondi], [riduzioneCalore], [audioInviato], [avvisoMicrofono], [permessoMicrofonoDaChiedere]).
 * I comandi Pro, l'inquadratura, la luce sul volto e la postura passano da [applica], come quelli del computer.
 */
class SessioneTelefono(context: Context, computerIniziale: ComputerTrovato, private val inizioTocco: Long = SystemClock.elapsedRealtime()) {

    sealed interface Stato {
        data object Collegamento : Stato
        data object Collegato : Stato
        data class Riconnessione(val tentativo: Int) : Stato
        data object Chiusa : Stato
        data class Errore(val descrizione: String) : Stato
    }

    private val app = context.applicationContext
    private val principale = Handler(Looper.getMainLooper())
    private val ambito = MainScope()
    /** Lavori lenti fuori dal thread principale (immagini degli effetti). */
    private val lavori = Executors.newSingleThreadExecutor { r -> Thread(r, "webcamlr-lavori").apply { isDaemon = true } }

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
    /**
     * Con più telefoni (`in-onda.selezionato`): vero = questo telefono è quello nella webcam. `null` = il computer non
     * lo manda (computer vecchio): si fa come con un telefono solo.
     */
    var selezionato by mutableStateOf<Boolean?>(null)
        private set
    /** «PRONTA · CAM 2»: collegato, ma nella webcam c'è l'altro telefono. Solo se il computer lo dice. */
    val prontaCam2: Boolean
        get() = stato == Stato.Collegato && selezionato == false
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
    /** Il telefono è molto caldo: 1080p30 o 720p24 (vedi [riduzioneCalore]). */
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
    var titoloErrore by mutableStateOf(Testi.testo(R.string.errore_interrotto))
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
    /** La strada verso il computer come la riceve il computer (`stato.collegamento`): in uso, preferenza, strade. */
    var statoCollegamento by mutableStateOf<StatoCollegamento?>(null)
        private set

    val batteriaBassa: Boolean get() = batteria in 0..19 && !inCarica

    // Flussi per l'interfaccia

    private val specchiatoInterno = MutableStateFlow(Impostazioni.specchioSalvato)
    /** 1.14: lo specchio del video inviato (e dell'anteprima, che è il video inviato). Uno solo, dal vivo. */
    val specchiato: StateFlow<Boolean> = specchiatoInterno.asStateFlow()

    private val effettiInterni = MutableStateFlow(Impostazioni.effetti())
    /** Gli effetti attuali (salvati sul telefono). */
    val effetti: StateFlow<StatoEffetti> = effettiInterni.asStateFlow()

    private val sfondoInterno = MutableStateFlow(effettiInterni.value.sfondo)
    /** Lo sfondo attuale (`ModiSfondo`). */
    val sfondo: StateFlow<String> = sfondoInterno.asStateFlow()

    private val funzioniInterne = MutableStateFlow(FunzioniDisponibili())
    /** Cosa sa fare questo telefono (lo stesso che arriva al computer in `capacita`). */
    val funzioni: StateFlow<FunzioniDisponibili> = funzioniInterne.asStateFlow()

    private val audioRichiestoInterno = MutableStateFlow(false)
    /** «Microfono al computer» chiesto, dal telefono o dal computer (vale per questa sessione). */
    val audioRichiesto: StateFlow<Boolean> = audioRichiestoInterno.asStateFlow()
    private val audioInviatoInterno = MutableStateFlow(false)
    /** Il computer sta ricevendo l'audio (microfono acceso, collegati, non in pausa). */
    val audioInviato: StateFlow<Boolean> = audioInviatoInterno.asStateFlow()
    private val avvisoMicrofonoInterno = MutableStateFlow<String?>(null)
    /** Una frase breve se il microfono non si può usare, con cosa fare (sparisce da sola). */
    val avvisoMicrofono: StateFlow<String?> = avvisoMicrofonoInterno.asStateFlow()
    private val permessoMicrofonoInterno = MutableStateFlow(false)
    /** Serve il permesso del microfono: l'interfaccia lo chiede e poi chiama [permessoMicrofonoCambiato]. */
    val permessoMicrofonoDaChiedere: StateFlow<Boolean> = permessoMicrofonoInterno.asStateFlow()

    private val pausaInterna = MutableStateFlow<String?>(null)
    /** Il motivo della pausa (`MotiviPausa`), `null` se il video va. */
    val pausa: StateFlow<String?> = pausaInterna.asStateFlow()

    private val dimensioniInterne = MutableStateFlow(Size(0, 0))
    /** Le dimensioni del video inviato, già girato (1080×1920 in verticale); 0×0 = non ancora note. */
    val dimensioniVideo: StateFlow<Size> = dimensioniInterne.asStateFlow()

    private val controlliInterni = MutableStateFlow(ControlliFotocamera())
    val controlli: StateFlow<ControlliFotocamera> = controlliInterni.asStateFlow()

    private val avvisoPosturaInterno = MutableStateFlow<ControlloPostura.Avviso?>(null)
    /** P11: il promemoria della postura da mostrare ora; sparisce da solo dopo 7 secondi. */
    val avvisoPostura: StateFlow<ControlloPostura.Avviso?> = avvisoPosturaInterno.asStateFlow()

    private val avvioInterno = MutableStateFlow<Double?>(null)
    /** 1.11/1.14: secondi dal tocco al primo fotogramma spedito («Avvio: 1,4 s»). */
    val avvioSecondi: StateFlow<Double?> = avvioInterno.asStateFlow()

    private val caloreInterno = MutableStateFlow(RiduzioneCalore.NESSUNA)
    /** Il gradino attuale della riduzione per il calore. */
    val riduzioneCalore: StateFlow<RiduzioneCalore> = caloreInterno.asStateFlow()

    /** WebcamLR Pro sbloccato (copia di [NegozioPro.pro]). */
    var pro = NegozioPro.pro.value
        private set

    val renderizzatore = Renderizzatore(anteprimaDelVideo = true)
    private val cattura = Cattura(app)
    val obiettivi: List<ObiettivoAndroid> get() = cattura.obiettivi
    val haTorcia: Boolean get() = cattura.haTorcia && obiettivo?.frontale != true

    private val adattamento = AdattamentoRete()
    /** Dopo una pausa (o un collegamento nuovo) si salta fino al primo fotogramma chiave. */
    private val attendiChiave = AtomicBoolean(true)
    private val codificatore = Codificatore(
        suFotogramma = { fotogramma ->
            val verso = destinazione
            if (verso != null && !(attendiChiave.get() && !fotogramma.chiave)) {
                attendiChiave.set(false)
                verso.inviaVideo(fotogramma)
            }
        },
        suErrore = { tipo -> principale.post { erroreCodifica(tipo) } },
    )
    private val codificatoreAudio = CodificatoreAudio(
        suPacchetto = { pacchetto, flusso -> destinazione?.inviaAudio(pacchetto, flusso) },
        suErrore = { motivo -> principale.post { microfonoFermo(motivo) } },
    )
    private val analisi = AnalisiImmagine(app)
    private val grafica = GraficaEffetti(app)
    private val pausaDecisa = DecisorePausa(
        pianifica = { ritardo, azione ->
            val compito = Runnable { azione() }
            principale.postDelayed(compito, ritardo)
            Annullabile { principale.removeCallbacks(compito) }
        },
        suCambio = { pausaCambiata() },
    )
    private val gravita = SensoreGravita(app) { giu, adesso -> pausaDecisa.gravita(giu, adesso) }
    private val calore = AscoltoCalore(app) { caloreCambiato() }
    private val regolatoreCalore = RegolatoreCalore()
    private val seguiLuce = SeguiLuce()
    private val postura = ControlloPostura()

    /** Il collegamento che riceve il video: esiste solo dopo il `benvenuto`. Letto dal thread del codificatore. */
    @Volatile private var destinazione: Collegamento? = null
    private var collegamento: Collegamento? = null
    private var tentativi = 0
    private var chiusaDallUtente = false
    private var fotocameraPronta = false
    /** La fotocamera si sta accendendo: al `benvenuto` non si riaccende, il codificatore parte quando è pronta. */
    private var fotocameraInAvvio = false
    /**
     * L'errore mostrato viene dal telefono (fotocamera chiusa dal sistema o presa da un'altra app, codificatore
     * fermo), non dal collegamento: il collegamento può essere ancora aperto. Si riprende senza ricollegarsi.
     */
    private var erroreLocale = false
    /** `capacita.formati` per obiettivo e codec: si calcolano una volta (MediaCodecList costa). */
    private val formatiNoti = HashMap<String, List<it.lrapps.webcamlr.protocollo.FormatoSupportato>>()
    private var codificaAttiva = false
    private var improntaComputer: String? = null
    private val perditeUltimiSecondi = ArrayDeque<Int>()
    /** Il formato chiesto dal computer con `formato`: vale per questa sessione, sopra le Impostazioni. */
    private var formatoRichiesto: FormatoScelto? = null
    private var esposizione = 0.0
    private var bianco = 0
    private var effettiGpu = false
    private var microfonoNegato = false
    private var misuraAvvio = true
    private var logoCaricato: Bitmap? = null
    private var ricercaRiconnessione: CercaComputer? = null

    // Le strade verso il computer (Documenti/Interfaccia finale.md, regola «Automatico»).
    private val regola = RegolaCollegamento()
    /** L'interfaccia del telefono del collegamento in uso (`wlan0`, `rndis0`…): finché è accesa, la strada c'è. */
    private var interfacciaAttiva: String? = null
    /** Le strade che raggiungono il computer adesso. */
    private var stradeNote: Set<Strada> = emptySet()
    /** L'ultima latenza misurata su ogni strada (`stato.collegamento.strade[].ms`). */
    private val msPerStrada = HashMap<Strada, Int>()
    /**
     * Il passaggio dal vivo all'altra strada: un secondo collegamento allo stesso computer (stessa impronta). Quando
     * il computer lo accetta (`benvenuto`) il video passa lì senza fermarsi e il vecchio si chiude.
     */
    private var candidato: Collegamento? = null
    private var stradaCandidato: Strada? = null
    private var tipoCandidato: TipoCollegamento? = null
    private var interfacciaCandidato: String? = null
    private var candidatoPronto = false
    /** Il vecchio collegamento chiuso durante un passaggio: si decide cosa fare quando il nuovo finisce. */
    private var chiusuraRinviata: ChiusuraRinviata? = null

    private class ChiusuraRinviata(val errore: ErroreCollegamento?, val motivo: MotivoChiusura, val inAttesaDiConferma: Boolean)

    private var bloccoSveglia: PowerManager.WakeLock? = null
    private var bloccoWiFi: WifiManager.WifiLock? = null
    private var ascoltoRete: ConnectivityManager.NetworkCallback? = null
    private val orientamento = object : OrientationEventListener(app) {
        override fun onOrientationChanged(gradi: Int) {
            if (gradi == ORIENTATION_UNKNOWN) return
            val attuale = renderizzatore.rotazioneTelefono
            // Un po' di isteresi: si cambia solo quando si è ben dentro il nuovo quarto (sempre al primo valore).
            val distanza = minOf(Math.floorMod(gradi - attuale, 360), Math.floorMod(attuale - gradi, 360))
            if (distanza > 55 || !renderizzatore.rotazioneNota) rotazioneCambiata(((gradi + 45) / 90 % 4) * 90)
        }
    }

    private val registro = RegistroCollegamento

    /** Le scelte fatte dall'interfaccia nelle Impostazioni (stesse chiavi dell'iPhone) valgono subito. */
    private val ascoltoImpostazioni = SharedPreferences.OnSharedPreferenceChangeListener { _, chiave ->
        principale.post { impostazioneCambiata(chiave) }
    }

    init {
        renderizzatore.rotazioneNota = false
        renderizzatore.rotazioneTelefono = rotazioneIniziale()
        renderizzatore.suAnalisi = { immagine, specchiata, rotazione ->
            analisi.analizza(immagine, specchiata, rotazione) { renderizzatore.analisiFinita() }
        }
        analisi.suMaschera = { dati, l, a, specchiata, rotazione -> renderizzatore.impostaMaschera(dati, l, a, specchiata, rotazione) }
        analisi.suVolti = { volti ->
            renderizzatore.volti = volti
            principale.post { voltiAggiornati(volti) }
        }
    }

    // Ciclo di vita

    fun avvia() {
        chiusaDallUtente = false
        tentativi = 0
        Sessioni.attuale = this
        mantieniSveglio(true)
        ServizioInOnda.avvia(app)
        if (orientamento.canDetectOrientation()) orientamento.enable()
        // 1.14: se il verso non arriva (sensore assente) si parte con quello dello schermo.
        principale.postDelayed({ renderizzatore.rotazioneNota = true }, 800)
        osservaRete()
        misuraStato()
        regolaQualita()
        pausaDecisa.facciaInGiuAbilitata = Impostazioni.pausaFacciaInGiu
        pausaDecisa.avvia()
        gravita.avvia()
        calore.avvia()
        Impostazioni.file.registerOnSharedPreferenceChangeListener(ascoltoImpostazioni)
        NegozioPro.aggiorna()
        ambito.launch { NegozioPro.pro.collect { proCambiato(it) } }
        obiettivo = obiettivi.firstOrNull { it.nome == Impostazioni.obiettivo } ?: obiettivi.firstOrNull { it.nome == "principale" }
            ?: obiettivi.firstOrNull()
        analisi.prepara { principale.post { aggiornaFunzioni() } }
        regola.impostaPreferenza(Impostazioni.collegamento)
        // La ricerca resta accesa per tutta la sessione: trova gli indirizzi dell'altra strada (cavo o Wi-Fi).
        avviaRicercaRiconnessione()
        principale.post(controlloStrade)
        // La fotocamera si accende subito, mentre il collegamento si apre: al `benvenuto` il video è pronto.
        avviaFotocamera()
        collega()
    }

    fun termina() {
        if (!chiusaDallUtente) registro.aggiungi(Testi.testo(R.string.registro_scollegato, computer.nome))
        chiusaDallUtente = true
        principale.removeCallbacksAndMessages(null)
        destinazione = null
        collegamento?.chiudi()
        collegamento = null
        chiudiCandidato()
        fermaRicercaRiconnessione()
        codificatoreAudio.ferma()
        fermaCodifica()
        cattura.chiudiEAspetta()
        cattura.termina()
        renderizzatore.ferma()
        analisi.termina()
        orientamento.disable()
        gravita.ferma()
        calore.ferma()
        pausaDecisa.ferma()
        runCatching { Impostazioni.file.unregisterOnSharedPreferenceChangeListener(ascoltoImpostazioni) }
        smettiDiOsservareRete()
        mantieniSveglio(false)
        ServizioInOnda.ferma(app)
        ambito.cancel()
        lavori.shutdown()
        inizioRiconnessione = null
        stato = Stato.Chiusa
        if (Sessioni.attuale === this) Sessioni.attuale = null
    }

    fun riprova() {
        if (chiusaDallUtente) return
        // Errore della fotocamera o del video con il collegamento ancora aperto: basta riaccendere la fotocamera.
        if (erroreLocale && collegamento != null) {
            riprendiDopoErroreLocale()
            return
        }
        tentativi = 0
        erroreDefinitivo = false
        destinazione = null
        collegamento?.chiudi()
        collegamento = null
        chiudiCandidato()
        if (!fotocameraPronta && !fotocameraInAvvio) avviaFotocamera()
        collega()
    }

    /**
     * L'app torna in primo piano (MainActivity.onStart). Mentre era in sottofondo il sistema può aver chiuso la
     * fotocamera (un'altra app l'ha presa, risparmio energetico) o fermato il codificatore: si riaccende tutto senza
     * ricollegarsi, così non resta uno stato incastrato. Si richiede anche il servizio in primo piano (se Android non
     * l'aveva lasciato partire, adesso può).
     */
    fun tornataInPrimoPiano() {
        if (chiusaDallUtente) return
        ServizioInOnda.avvia(app)
        when {
            erroreLocale && collegamento != null -> riprendiDopoErroreLocale()
            stato !is Stato.Errore && !fotocameraPronta && !fotocameraInAvvio && !pausaDecisa.fotocameraSpenta -> {
                registro.aggiungi(Testi.testo(R.string.registro_fotocamera_riaccesa))
                avviaFotocamera()
            }
        }
    }

    /** Dopo un errore della fotocamera o del video, con il collegamento aperto: stato di prima e fotocamera da capo. */
    private fun riprendiDopoErroreLocale() {
        erroreLocale = false
        if (stato is Stato.Errore) {
            stato = when {
                destinazione != null -> Stato.Collegato
                tentativi > 0 -> Stato.Riconnessione(tentativi)
                else -> Stato.Collegamento
            }
        }
        registro.aggiungi(Testi.testo(R.string.registro_fotocamera_riaccesa))
        if (destinazione != null) {
            principale.removeCallbacks(statoPeriodico)
            principale.post(statoPeriodico)
        }
        avviaFotocamera()
    }

    // Comandi dell'interfaccia

    fun scegli(nuovo: ObiettivoAndroid) {
        if (nuovo == obiettivo) return
        obiettivo = nuovo
        Impostazioni.obiettivo = nuovo.nome
        torciaAccesa = false
        zoom = 1.0
        aeafBloccati = false
        geometriaCambiata()
        aggiornaControlli()
        avviaFotocamera()
    }

    /** Doppio tocco: frontale ↔ posteriore. */
    /**
     * «Usa questa prospettiva» (telefono CAM 2): chiede al computer di andare nella webcam. Si manda solo a un computer
     * che conosce la scelta (ha mandato `selezionato`); la scelta si mostra quando arriva il nuovo `in-onda`.
     */
    fun usaProspettiva() {
        if (selezionato != false) return
        val verso = collegamento ?: return
        verso.invia(UsaProspettiva)
        registro.aggiungi(Testi.testo(R.string.registro_usa_prospettiva))
    }

    fun cambiaFotocamera() {
        val nuovo = if (obiettivo?.frontale == true) obiettivi.firstOrNull { it.nome == "principale" } else obiettivi.firstOrNull { it.frontale }
        if (nuovo != null) scegli(nuovo)
    }

    fun impostaZoom(fattore: Double) {
        if (!fattore.isFinite()) return
        zoom = fattore.coerceIn(1.0, maxOf(1.0, cattura.zoomMassimo))
        cattura.impostaZoom(zoom)
        aggiornaControlli()
        // 1.14: il computer segue lo zoom del telefono, dopo l'ultimo movimento.
        principale.removeCallbacks(statoDopoZoom)
        principale.postDelayed(statoDopoZoom, 400)
    }

    private val statoDopoZoom = Runnable { if (destinazione != null) aggiornaStato() }

    fun cambiaTorcia() {
        if (!haTorcia) return
        torciaAccesa = !torciaAccesa
        cattura.impostaTorcia(torciaAccesa)
        aggiornaControlli()
        if (destinazione != null) aggiornaStato()
    }

    /** Compensazione dell'esposizione dal telefono, da -2 a +2 stop. */
    fun impostaEsposizione(stop: Double) = applica(Comando(esposizione = stop))

    /**
     * 1.14: «Specchia», dal telefono o dal computer (`comando.specchia`). Vale subito, senza riavviare la fotocamera:
     * cambia lo specchio finale del video inviato (e quindi dell'anteprima). Resta salvato sul telefono.
     */
    fun impostaSpecchio(attivo: Boolean) {
        if (Impostazioni.specchioSalvato != attivo) Impostazioni.specchioSalvato = attivo
        if (attivo == specchiatoInterno.value) return
        specchiatoInterno.value = attivo
        renderizzatore.specchiaCodifica = (obiettivo?.frontale == true) xor attivo
        renderizzatore.inquadratura.specchioCambiato()
        seguiLuce.azzera()
        registro.aggiungi(Testi.testo(if (attivo) R.string.registro_specchiata else R.string.registro_non_specchiata))
        aggiornaStato()
    }

    /** Lo specchio come è salvato (per chi lo ha cambiato nelle preferenze). */
    fun aggiornaSpecchio() = impostaSpecchio(Impostazioni.specchioSalvato)

    /** «Sfoca sfondo» a un tocco e il foglio degli effetti: `nessuno`, `sfocato`, `sostituito` (Pro). */
    fun scegliSfondo(modo: String) = applica(Comando(sfondo = modo))

    /** L'immagine per lo sfondo sostituito: uno di [SfondiPronti]; accende anche «sostituito» (Pro). */
    fun scegliImmagineSfondo(scelto: String) {
        if (!pro) return
        val valido = if (scelto == SfondiPronti.FOTO && !grafica.haFotoSfondo) SfondiPronti.STUDIO else scelto
        if (valido !in SfondiPronti.TUTTI) return
        cambiaEffetti(effettiInterni.value.copy(sfondoScelto = valido, sfondo = ModiSfondo.SOSTITUITO))
    }

    /** «La tua foto» per lo sfondo (dall'interfaccia, già letta): si salva ridotta e si usa subito. */
    fun usaFotoSfondo(immagine: Bitmap) {
        inSottofondo {
            if (grafica.salvaFotoSfondo(immagine)) principale.post { scegliImmagineSfondo(SfondiPronti.FOTO); caricaSfondo() }
        }
    }

    /** Un lavoro lento fuori dal thread principale; dopo la chiusura della sessione non parte più. */
    private fun inSottofondo(lavoro: () -> Unit) {
        if (chiusaDallUtente) return
        runCatching { lavori.execute(lavoro) }
    }

    /** Il logo (dall'interfaccia, già letto), oppure `null` per toglierlo. */
    fun usaLogo(immagine: Bitmap?) {
        inSottofondo {
            grafica.salvaLogo(immagine)
            val nuovo = grafica.caricaLogo()
            principale.post {
                logoCaricato = nuovo
                if (nuovo != null && !effettiInterni.value.mostraLogo) cambiaEffetti(effettiInterni.value.copy(mostraLogo = true)) else aggiornaSovrapposizioni()
            }
        }
    }

    val haLogo: Boolean get() = grafica.haLogo
    val haFotoSfondo: Boolean get() = grafica.haFotoSfondo

    fun impostaMostraLogo(mostra: Boolean) {
        if (mostra && !pro) return
        cambiaEffetti(effettiInterni.value.copy(mostraLogo = mostra))
    }

    /** Il pulsante «Pausa» di «In onda»: il video si ferma, il collegamento resta aperto. */
    fun impostaPausaUtente(attiva: Boolean) = pausaDecisa.impostaPausaUtente(attiva)

    /** Mentre si guarda il video sul telefono senza nessuno al computer (per esempio «Prova la webcam»): niente pausa. */
    fun trattieniPausa(attiva: Boolean) = pausaDecisa.trattieni(attiva)

    fun nascondiAvvisoPostura() {
        avvisoPosturaInterno.value = null
    }

    /**
     * Tocco sull'anteprima, in coordinate 0–1 della vista dell'anteprima. L'anteprima è il video inviato girato per lo
     * schermo e ingrandito fino a riempirlo (i bordi in più tagliati): si toglie il ritaglio e la rotazione, poi lo zoom
     * dell'inquadratura, poi si va sul sensore.
     */
    fun metteAFuoco(x: Float, y: Float, blocca: Boolean) {
        val (lv, av) = renderizzatore.dimensioniAnteprima
        val (l, a) = renderizzatore.dimensioniVideo
        val relativa = Math.floorMod(renderizzatore.rotazioneSchermo - renderizzatore.rotazioneTelefono, 360)
        val nelVideo = Geometria.anteprimaAlVideo(x, y, lv.toFloat(), av.toFloat(), l, a, relativa, riempi = true) ?: return
        val (vx, vy) = renderizzatore.inquadratura.uscito.primaDelloZoom(nelVideo.first, nelVideo.second)
        val parametri = parametriGeometria() ?: return
        val (cx, cy) = Geometria.videoAllaFotocamera(vx, vy, parametri)
        cattura.metteAFuocoNelFotogramma(cx, cy, blocca)
        aeafBloccati = blocca
    }

    /**
     * La parte del video che si vede nella vista dell'anteprima (pixel), per griglia e livella solo sul video: con
     * l'anteprima che riempie lo schermo è tutta la vista (il video, più grande, esce dai bordi).
     */
    fun rettangoloVideo(larghezzaVista: Float, altezzaVista: Float): RectF {
        val (l, a) = renderizzatore.dimensioniVideo
        val relativa = Math.floorMod(renderizzatore.rotazioneSchermo - renderizzatore.rotazioneTelefono, 360)
        val r = Geometria.rettangoloVideoNellaVista(larghezzaVista, altezzaVista, l, a, relativa, riempi = true)
        return RectF(maxOf(r[0], 0f), maxOf(r[1], 0f), minOf(r[2], larghezzaVista), minOf(r[3], altezzaVista))
    }

    /**
     * Le Impostazioni video (risoluzione, fps, codec) sono cambiate: la fotocamera si riconfigura una volta sola e il
     * formato chiesto dal computer non vale più.
     */
    fun applicaImpostazioni() {
        formatoRichiesto = null
        regolaQualita()
        if (fotocameraPronta && !chiusaDallUtente) {
            registro.aggiungi(Testi.testo(R.string.registro_riconfiguro))
            avviaFotocamera()
        }
    }

    /** «Microfono al computer», dal telefono o da `comando.audio`. Senza permesso lo chiede l'interfaccia. */
    fun impostaAudio(acceso: Boolean) {
        if (acceso == audioRichiestoInterno.value) return
        if (acceso && !permessoMicrofono()) {
            if (microfonoNegato) {
                mostraAvvisoMicrofono(Testi.testo(R.string.microfono_non_consentito))
                aggiornaStato()
            } else {
                // L'interfaccia mostra la domanda di Android; poi [permessoMicrofonoCambiato].
                permessoMicrofonoInterno.value = true
            }
            return
        }
        audioRichiestoInterno.value = acceso
        registro.aggiungi(Testi.testo(if (acceso) R.string.registro_microfono_acceso else R.string.registro_microfono_spento))
        aggiornaMicrofono()
        aggiornaStato()
    }

    /** La risposta alla domanda del permesso del microfono. */
    fun permessoMicrofonoCambiato(concesso: Boolean) {
        permessoMicrofonoInterno.value = false
        microfonoNegato = !concesso
        if (concesso) {
            ServizioInOnda.aggiorna(app)
            impostaAudio(true)
        } else {
            mostraAvvisoMicrofono(Testi.testo(R.string.microfono_non_consentito))
            aggiornaFunzioni()
            aggiornaStato()
        }
    }

    // Collegamento

    private fun collega() {
        if (chiusaDallUtente) return
        stato = if (tentativi == 0) Stato.Collegamento else Stato.Riconnessione(tentativi)
        registro.aggiungi(
            if (tentativi == 0) Testi.testo(R.string.registro_collegamento_a, computer.nome)
            else Testi.testo(R.string.registro_nuovo_tentativo, tentativi, TENTATIVI_MASSIMI, computer.nome),
        )
        codiceConferma = null
        improntaComputer = null
        interfacciaAttiva = null
        chiudiCandidato()
        // La strada scelta dall'utente per prima, se raggiunge il computer; dal terzo tentativo tutte, per non restare
        // senza video. In automatico tutti gli indirizzi insieme: vince il più veloce.
        val interfacce = StradeRete.interfacce()
        val perStrada = computer.indirizzi.groupBy { StradeRete.strada(it, interfacce) }
        val preferita = regola.stradaIniziale(perStrada.keys.filterNotNull().toSet())
        val indirizzi = if (preferita != null && tentativi < 3) perStrada[preferita].orEmpty() else computer.indirizzi
        lateinit var nuovo: Collegamento
        nuovo = Collegamento(
            indirizzi = indirizzi,
            porta = computer.porta,
            identita = IdentitaTelefono.condivisa(app),
            // Protocollo 2: l'impronta attesa viene dal QR code, altrimenti dai computer conosciuti.
            improntaAttesa = computer.impronta ?: ComputerConosciuti.impronta(computer.nome),
            gettone = computer.gettone,
            ciao = nuovoCiao(),
            orologio = Orologio::adesso,
            suEvento = { evento -> principale.post { gestisci(evento, nuovo) } },
            // Priorità video sul Wi-Fi (DSCP CS5 → coda «video» del Wi-Fi).
            preparaSocket = { socket -> runCatching { socket.trafficClass = 0xA0 } },
        )
        preparaCollegamento(nuovo)
        synchronized(adattamento) { adattamento.azzera() }
        perditeUltimiSecondi.clear()
        perditeRecenti = 0
        reteDebole = false
        collegamento = nuovo
        nuovo.avvia()
    }

    private fun nuovoCiao() = Ciao(
        versione = Sicurezza.VERSIONE_SICURA,
        nome = StatoDispositivo.nomeTelefono(app),
        piattaforma = Piattaforma.ANDROID,
        versioneApp = BuildConfig.VERSION_NAME,
    )

    /** Fotogramma chiave dopo uno scarto, «Avvio» e il bilancio di ogni secondo (solo del collegamento che riceve il video). */
    private fun preparaCollegamento(nuovo: Collegamento) {
        nuovo.suPerdita = { codificatore.richiediFotogrammaChiave() }
        nuovo.suPrimoFotogramma = { principale.post { primoFotogrammaSpedito(nuovo) } }
        nuovo.suSecondo = suSecondo@{ scartati, saturo ->
            // Un passaggio in corso non conta: il video va ancora sull'altro collegamento.
            if (destinazione !== nuovo) return@suSecondo
            val debole = synchronized(adattamento) {
                val debole = adattamento.secondo(scartati, saturo)
                if (codificatore.bitrateBase > 0) codificatore.impostaBitrate(adattamento.bitrate(codificatore.bitrateBase))
                debole
            }
            principale.post { registraSecondo(scartati, debole) }
        }
    }

    private fun gestisci(evento: EventoCollegamento, da: Collegamento) {
        if (da !== collegamento || chiusaDallUtente) return
        when (evento) {
            is EventoCollegamento.Pronto -> {
                improntaComputer = evento.impronta
                interfacciaAttiva = evento.interfaccia
                tipoCollegamento = TipoCollegamento.daInterfaccia(evento.interfaccia) ?: TipoCollegamento.WIFI
                registro.aggiungi(Testi.testo(R.string.registro_collegamento_sicuro, evento.impronta.take(8)))
                tipoCollegamento?.let { registro.aggiungi(Testi.testo(R.string.registro_collegamento_via, testoTipo(it))) }
            }
            is EventoCollegamento.Ricevuto -> when (val messaggio = evento.messaggio) {
                is Approvazione -> {
                    codiceConferma = messaggio.codice
                    registro.aggiungi(Testi.testo(R.string.registro_chiede_codice))
                }
                is Benvenuto -> accolto(da, messaggio)
                is Latenza -> {
                    val ms = messaggio.ms.coerceIn(0, 60_000)
                    latenzaMs = ms
                    ultimaLatenzaMs = ms
                    tipoCollegamento?.let { msPerStrada[stradaDi(it)] = ms }
                }
                is Comando -> applica(messaggio)
                is InOnda -> {
                    inOnda = if (messaggio.attivo) messaggio.copy(app = messaggio.app?.take(80)) else null
                    selezionato = messaggio.selezionato
                    pausaDecisa.inOnda(messaggio.attivo)
                }
                is Anteprima -> pausaDecisa.anteprima(messaggio.visibile)
                is FormatoVideo -> chiediFormato(messaggio)
                else -> Unit
            }
            is EventoCollegamento.Chiuso -> {
                val inAttesaDiConferma = codiceConferma != null
                if (candidato != null) {
                    // Durante un passaggio il computer chiude il vecchio collegamento quando accetta il nuovo: si
                    // decide quando il nuovo finisce, intanto il video resta com'è.
                    chiusuraRinviata = ChiusuraRinviata(evento.errore, evento.motivo, inAttesaDiConferma)
                    registro.aggiungi(Testi.testo(R.string.registro_vecchio_chiuso_nel_passaggio))
                    return
                }
                collegamentoChiuso(evento.errore, evento.motivo, inAttesaDiConferma)
            }
        }
    }

    /** Il collegamento in uso si è chiuso (e nessun passaggio lo sostituisce): video fermo, poi si riprova o ci si ferma. */
    private fun collegamentoChiuso(errore: ErroreCollegamento?, motivo: MotivoChiusura, inAttesaDiConferma: Boolean) {
        codiceConferma = null
        collegamento = null
        destinazione = null
        interfacciaAttiva = null
        principale.removeCallbacks(statoPeriodico)
        fermaCodifica()
        latenzaMs = null
        inOnda = null
        selezionato = null
        tipoCollegamento = null
        statoCollegamento = null
        aggiornaAudioInviato()
        gestisciChiusura(errore, motivo, inAttesaDiConferma)
    }

    private fun accolto(da: Collegamento, benvenuto: Benvenuto) {
        codiceConferma = null
        giaCollegato = true
        // Indirizzo scritto a mano: con il nome vero funzionano i computer conosciuti e la ricerca (se non è già di un altro).
        if (!computer.annunciato && computer.impronta == null && benvenuto.nome.isNotBlank() && benvenuto.nome != computer.nome) {
            val salvata = ComputerConosciuti.impronta(benvenuto.nome)
            if (salvata == null || salvata == improntaComputer) computer = computer.copy(nome = benvenuto.nome.take(100))
        }
        // Da ora questo computer è conosciuto: la prossima volta la sua impronta deve essere la stessa.
        improntaComputer?.let { ComputerConosciuti.salva(it, computer.nome) }
        tentativi = 0
        stato = Stato.Collegato
        inizioRiconnessione = null
        regola.collegato(stradaDi(tipoCollegamento ?: TipoCollegamento.WIFI), SystemClock.elapsedRealtime())
        registro.aggiungi(Testi.testo(R.string.registro_collegato, computer.nome, benvenuto.piattaforma.valore))
        Impostazioni.ultimoComputer = computer.nome
        // P10: connessione nuova, la pausa «nessuna app» riparte da capo (il computer rimanda `anteprima`).
        pausaDecisa.nuovoCollegamento()
        aggiornaPausa()
        attendiChiave.set(true)
        destinazione = da
        principale.removeCallbacks(statoPeriodico)
        principale.post(statoPeriodico)
        if (pausaDecisa.fotocameraSpenta) return
        if (fotocameraPronta) avviaCodifica() else if (!fotocameraInAvvio) avviaFotocamera()
        aggiornaMicrofono()
    }

    /** 1.11: il primo fotogramma è partito verso il computer: quanto ci è voluto dal tocco. */
    private fun primoFotogrammaSpedito(da: Collegamento) {
        if (da !== collegamento) return
        val secondi = (SystemClock.elapsedRealtime() - inizioTocco) / 1000.0
        if (misuraAvvio) {
            misuraAvvio = false
            avvioInterno.value = secondi
            registro.aggiungi(Testi.testo(R.string.registro_primo_fotogramma, "%.1f".format(Testi.locale, secondi)))
        } else {
            registro.aggiungi(Testi.testo(R.string.registro_primo_fotogramma_ricollegato))
        }
    }

    /** Il collegamento si è chiuso: si riprova, oppure ci si ferma dicendo perché e cosa fare. */
    private fun gestisciChiusura(tipoErrore: ErroreCollegamento?, motivo: MotivoChiusura, inAttesaDiConferma: Boolean) {
        val errore = tipoErrore?.let { descrizioneErrore(it) }
        registro.aggiungi(Testi.testo(R.string.registro_chiuso, motivo.perRegistro) + (errore?.let { " ($it)" } ?: ""))
        val nome = computer.nome
        // Chiuso mentre si aspettava la conferma: il computer ha detto no, o nessuno ha risposto.
        if (inAttesaDiConferma && (motivo == MotivoChiusura.RETE || motivo == MotivoChiusura.DAL_COMPUTER)) {
            fermaConErrore(Testi.testo(R.string.errore_non_confermato_titolo),
                Testi.testo(R.string.errore_non_confermato, nome), domanda = "codice")
            return
        }
        when (motivo) {
            MotivoChiusura.RETE -> Unit
            MotivoChiusura.DAL_COMPUTER -> {
                fermaConErrore(titoloInterrotto(nome), Testi.testo(R.string.errore_chiuso_dal_computer, nome))
                return
            }
            MotivoChiusura.COMPUTER_VECCHIO -> {
                fermaConErrore(Testi.testo(R.string.errore_aggiorna_titolo), Testi.testo(R.string.errore_aggiorna, nome), domanda = "aggiorna")
                return
            }
            MotivoChiusura.IDENTITA_CAMBIATA -> {
                if (Impostazioni.ultimoComputer == nome) Impostazioni.ultimoComputer = null
                fermaConErrore(Testi.testo(R.string.errore_identita_titolo), Testi.testo(R.string.errore_identita, nome),
                    definitivo = true, domanda = "identita")
                return
            }
            MotivoChiusura.IDENTITA_NON_VALIDA -> {
                fermaConErrore(Testi.testo(R.string.errore_non_sicuro_titolo), Testi.testo(R.string.errore_non_sicuro, nome), domanda = "identita")
                return
            }
        }
        // Mentre si riprova si cerca anche il computer (Wi-Fi e cavo): se cambia indirizzo o passa al cavo lo si ritrova.
        if (giaCollegato) avviaRicercaRiconnessione()
        // Senza rete non si consumano tentativi: si riparte appena torna (o appena compare il cavo).
        if (!reteDisponibile) {
            if (inizioRiconnessione == null) inizioRiconnessione = SystemClock.elapsedRealtime()
            stato = Stato.Riconnessione(maxOf(tentativi, 1))
            principale.removeCallbacks(controlloCavo)
            principale.postDelayed(controlloCavo, 3_000)
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
            fermaConErrore(Testi.testo(R.string.errore_rete_separata_titolo), Testi.testo(R.string.errore_rete_separata), domanda = "rete-ospiti")
        } else {
            fermaConErrore(titoloInterrotto(nome), errore ?: Testi.testo(R.string.errore_non_risponde),
                domanda = if (giaCollegato) null else "non-trova")
        }
    }

    /** Senza rete del telefono si guarda ogni 3 secondi se è comparso il cavo (il Tethering USB non è una «rete» per Android). */
    private val controlloCavo = object : Runnable {
        override fun run() {
            if (chiusaDallUtente || collegamento != null || stato !is Stato.Riconnessione) return
            if (RicercaCavo.interfacceDelCavo().isNotEmpty()) reteCambiata(true) else principale.postDelayed(this, 3_000)
        }
    }

    private fun avviaRicercaRiconnessione() {
        if (ricercaRiconnessione != null) return
        val ricerca = CercaComputer(app)
        ricerca.suTrovato = { trovato ->
            if (trovato.nome == computer.nome && !chiusaDallUtente) {
                val unito = if (trovato.viaCavo) computer.copy(indirizzi = (trovato.indirizzi + computer.indirizzi).distinct(), porta = trovato.porta)
                else computer.copy(indirizzi = (computer.indirizzi + trovato.indirizzi).distinct(), porta = trovato.porta)
                val nuoviIndirizzi = unito.indirizzi != computer.indirizzi || unito.porta != computer.porta
                computer = unito
                // Indirizzo nuovo mentre si aspetta il prossimo tentativo: si prova subito, da capo con i tentativi.
                if (nuoviIndirizzi && collegamento == null && stato !is Stato.Collegato) {
                    registro.aggiungi(Testi.testo(R.string.registro_ritrovato, computer.nome, trovato.indirizzi.joinToString()))
                    if (stato is Stato.Errore && !erroreDefinitivo) {
                        riprova()
                    } else if (stato is Stato.Riconnessione) {
                        tentativi = 1
                        collega()
                    }
                }
            }
        }
        ricercaRiconnessione = ricerca
        ricerca.avvia()
    }

    private fun fermaRicercaRiconnessione() {
        ricercaRiconnessione?.ferma()
        ricercaRiconnessione = null
    }

    /** «Collegamento interrotto» dopo essere stati collegati, altrimenti «Non riesco a collegarmi a …». */
    private fun titoloInterrotto(nome: String): String =
        if (giaCollegato) Testi.testo(R.string.errore_interrotto) else Testi.testo(R.string.errore_non_mi_collego, nome)

    /** La frase per l'utente, con cosa fare, per un errore del collegamento. */
    private fun descrizioneErrore(errore: ErroreCollegamento): String = Testi.testo(
        when (errore) {
            ErroreCollegamento.NON_RISPONDE -> R.string.errore_computer_non_risponde
            ErroreCollegamento.IN_RITARDO -> R.string.errore_computer_in_ritardo
            ErroreCollegamento.DATI_NON_VALIDI -> R.string.errore_dati_non_validi
            ErroreCollegamento.DATI_NON_SICURI -> R.string.errore_dati_non_sicuri
        },
    )

    private fun fermaConErrore(titolo: String, descrizione: String, definitivo: Boolean = false, domanda: String? = null) {
        erroreLocale = false
        principale.removeCallbacks(statoPeriodico)
        principale.removeCallbacks(controlloCavo)
        inizioRiconnessione = null
        titoloErrore = titolo
        erroreDefinitivo = definitivo
        domandaErrore = domanda
        registro.aggiungi(Testi.testo(R.string.registro_fermo, titolo))
        if (definitivo) fermaRicercaRiconnessione()
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

    // Strade: Wi-Fi e cavo (regola «Automatico», Documenti/Interfaccia finale.md)

    /**
     * La preferenza della strada: «automatico», «wifi» o «cavo», dal telefono (Impostazioni) o dal computer
     * (`comando.collegamento`). Resta salvata; una scelta manuale vale subito, senza aspettare la pausa di 30 secondi.
     */
    fun impostaPreferenzaCollegamento(valore: String) {
        val valida = PreferenzeCollegamento.valida(valore) ?: return
        Impostazioni.impostaCollegamento(valida)
        if (!regola.impostaPreferenza(valida)) return
        registro.aggiungi(Testi.testo(R.string.registro_preferenza_collegamento, testoPreferenza(valida)))
        valutaStrade(sceltaUtente = true)
        aggiornaStato()
    }

    /** Ogni 2 secondi per tutta la sessione: quali strade raggiungono il computer, e se è il momento di cambiare. */
    private val controlloStrade = object : Runnable {
        override fun run() {
            if (chiusaDallUtente) return
            aggiornaStrade()
            principale.postDelayed(this, 2_000)
        }
    }

    private fun aggiornaStrade() {
        val interfacce = StradeRete.interfacce()
        val strade = HashSet<Strada>()
        for (indirizzo in computer.indirizzi) StradeRete.strada(indirizzo, interfacce)?.let { strade.add(it) }
        // La strada in uso c'è finché la sua interfaccia è accesa (anche se il computer sta su un'altra sottorete).
        val inUso = if (destinazione != null) tipoCollegamento?.let { stradaDi(it) } else null
        val nome = interfacciaAttiva
        if (inUso != null && nome != null) {
            if (StradeRete.accesa(nome, interfacce)) strade.add(inUso) else strade.remove(inUso)
        }
        regola.disponibilita(strade)
        if (strade != stradeNote) {
            stradeNote = strade
            aggiornaStato()
        }
        valutaStrade(sceltaUtente = false)
    }

    /** Se la regola lo dice, si apre il collegamento sull'altra strada; il video continua su quella di adesso. */
    private fun valutaStrade(sceltaUtente: Boolean) {
        if (chiusaDallUtente || candidato != null || stato != Stato.Collegato || destinazione == null || improntaComputer == null) return
        val verso = regola.decidi(SystemClock.elapsedRealtime(), sceltaUtente) ?: return
        avviaCandidato(verso)
    }

    /** Un secondo collegamento allo stesso computer sull'altra strada: solo con la stessa impronta, senza gettone. */
    private fun avviaCandidato(strada: Strada) {
        val impronta = improntaComputer ?: return
        val interfacce = StradeRete.interfacce()
        val indirizzi = computer.indirizzi.filter { StradeRete.strada(it, interfacce) == strada }
        if (indirizzi.isEmpty()) return
        registro.aggiungi(Testi.testo(R.string.registro_passaggio_provo, testoStrada(strada)))
        lateinit var nuovo: Collegamento
        nuovo = Collegamento(
            indirizzi = indirizzi,
            porta = computer.porta,
            identita = IdentitaTelefono.condivisa(app),
            improntaAttesa = impronta,
            gettone = null,
            ciao = nuovoCiao(),
            orologio = Orologio::adesso,
            suEvento = { evento -> principale.post { gestisciCandidato(evento, nuovo) } },
            preparaSocket = { socket -> runCatching { socket.trafficClass = 0xA0 } },
        )
        preparaCollegamento(nuovo)
        candidato = nuovo
        stradaCandidato = strada
        tipoCandidato = null
        interfacciaCandidato = null
        candidatoPronto = false
        nuovo.avvia()
    }

    /** Gli eventi del collegamento sull'altra strada: finché il computer non lo accetta non toccano la sessione. */
    private fun gestisciCandidato(evento: EventoCollegamento, da: Collegamento) {
        if (da !== candidato || chiusaDallUtente) return
        when (evento) {
            is EventoCollegamento.Pronto -> {
                // La stretta di mano ha già verificato l'impronta: è lo stesso computer, che riceve il `ciao`.
                candidatoPronto = true
                interfacciaCandidato = evento.interfaccia
                tipoCandidato = TipoCollegamento.daInterfaccia(evento.interfaccia)
                    ?: if (stradaCandidato == Strada.CAVO) TipoCollegamento.CAVO_USB else TipoCollegamento.WIFI
            }
            is EventoCollegamento.Ricevuto -> when (val messaggio = evento.messaggio) {
                is Benvenuto -> passaAlCandidato(da)
                // Lo stesso computer conosce già questo telefono: una domanda vuol dire altro, si resta dove si è.
                is Approvazione -> scartaCandidato()
                // Comandi arrivati prima del `benvenuto` (Windows li manda subito): valgono come sull'altra strada.
                is Comando -> applica(messaggio)
                is InOnda -> {
                    inOnda = if (messaggio.attivo) messaggio.copy(app = messaggio.app?.take(80)) else null
                    selezionato = messaggio.selezionato
                    pausaDecisa.inOnda(messaggio.attivo)
                }
                is Anteprima -> pausaDecisa.anteprima(messaggio.visibile)
                else -> Unit
            }
            is EventoCollegamento.Chiuso -> candidatoFinito(dopoStretta = candidatoPronto)
        }
    }

    /** Il candidato non serve (il computer chiede una conferma): si chiude in silenzio e si resta dove si è. */
    private fun scartaCandidato() {
        val scartato = candidato ?: return
        val dopoStretta = candidatoPronto
        // Tolto prima di chiuderlo: la sua chiusura non arriva più qui.
        candidato = null
        scartato.chiudi()
        candidatoFinito(dopoStretta)
    }

    /** Il passaggio non è riuscito: si resta sulla strada di prima; se intanto quella si era chiusa, si riprova come sempre. */
    private fun candidatoFinito(dopoStretta: Boolean) {
        val strada = stradaCandidato
        dimenticaCandidato()
        if (strada != null) {
            regola.tentativoFallito(strada, SystemClock.elapsedRealtime())
            val prima = tipoCollegamento?.let { testoTipo(it) } ?: testoStrada(strada.altra)
            registro.aggiungi(Testi.testo(R.string.registro_passaggio_non_riuscito, testoStrada(strada), prima))
        }
        val rinviata = chiusuraRinviata ?: return
        chiusuraRinviata = null
        if (chiusaDallUtente) return
        // Il computer aveva lasciato il collegamento vecchio per il nuovo, che poi non è riuscito: non è una chiusura voluta.
        val motivo = if (rinviata.motivo == MotivoChiusura.DAL_COMPUTER && dopoStretta) MotivoChiusura.RETE else rinviata.motivo
        collegamentoChiuso(rinviata.errore, motivo, rinviata.inAttesaDiConferma)
    }

    /**
     * Il computer ha accettato l'altra strada: il video passa lì senza fermare fotocamera e codificatore. Prima
     * `formato` e `capacita` sul collegamento nuovo, poi i fotogrammi da un fotogramma chiave; il vecchio si chiude.
     */
    private fun passaAlCandidato(nuovo: Collegamento) {
        val strada = stradaCandidato ?: return
        val tipoNuovo = tipoCandidato ?: if (strada == Strada.CAVO) TipoCollegamento.CAVO_USB else TipoCollegamento.WIFI
        val interfacciaNuova = interfacciaCandidato
        val vecchio = collegamento
        dimenticaCandidato()
        chiusuraRinviata = null
        collegamento = nuovo
        tipoCollegamento = tipoNuovo
        interfacciaAttiva = interfacciaNuova
        codiceConferma = null
        tentativi = 0
        giaCollegato = true
        erroreDefinitivo = false
        inizioRiconnessione = null
        latenzaMs = null
        synchronized(adattamento) { adattamento.azzera() }
        perditeUltimiSecondi.clear()
        perditeRecenti = 0
        reteDebole = false
        stato = Stato.Collegato
        regola.collegato(strada, SystemClock.elapsedRealtime())
        registro.aggiungi(Testi.testo(R.string.registro_passaggio_fatto, testoTipo(tipoNuovo)))
        // Il computer rimanda `anteprima` alla sessione nuova: la pausa «nessuna app» riparte da capo.
        pausaDecisa.nuovoCollegamento()
        aggiornaPausa()
        if (codificaAttiva) {
            formato?.let { nuovo.invia(it) }
            inviaCapacita(nuovo)
            attendiChiave.set(true)
            destinazione = nuovo
            codificatore.richiediFotogrammaChiave(subito = true)
        } else {
            destinazione = nuovo
            if (!pausaDecisa.fotocameraSpenta) {
                if (fotocameraPronta) avviaCodifica() else if (!fotocameraInAvvio) avviaFotocamera()
            }
        }
        vecchio?.chiudi()
        principale.removeCallbacks(statoPeriodico)
        principale.post(statoPeriodico)
        aggiornaMicrofono()
    }

    private fun chiudiCandidato() {
        val vecchio = candidato
        dimenticaCandidato()
        chiusuraRinviata = null
        vecchio?.chiudi()
    }

    private fun dimenticaCandidato() {
        candidato = null
        stradaCandidato = null
        tipoCandidato = null
        interfacciaCandidato = null
        candidatoPronto = false
    }

    /** `stato.collegamento`: la strada in uso, la preferenza e le strade che raggiungono il computer, con la latenza. */
    private fun costruisciStatoCollegamento(): StatoCollegamento? {
        val tipo = tipoCollegamento ?: return null
        val strade = stradeNote + stradaDi(tipo)
        return StatoCollegamento(
            attivo = valoreAttivo(tipo),
            preferenza = regola.preferenza,
            strade = Strada.entries.filter { it in strade }.map { StradaCollegamento(it.valore, msPerStrada[it]) },
        )
    }


    // Fotocamera e codifica

    /** Il formato con cui partire: Impostazioni o computer, poi calore, batteria, Pro (720p30 senza) e 4K. */
    private fun formatoEffettivo(): FormatoScelto {
        val (larghezza, altezza) = Impostazioni.dimensioni
        val impostazioni = FormatoScelto(larghezza, altezza, Impostazioni.fps, Impostazioni.codecScelto)
        return SceltaFormato.effettivo(impostazioni, formatoRichiesto, caloreInterno.value, risparmioBatteria, pro)
    }

    /** Il video esce in verticale con il telefono in verticale, come sull'iPhone. */
    private val verticale: Boolean get() = renderizzatore.rotazioneTelefono % 180 == 0

    private fun avviaFotocamera() {
        if (chiusaDallUtente || pausaDecisa.fotocameraSpenta) return
        erroreLocale = false
        val scelto = obiettivo ?: run {
            fermaConErrore(Testi.testo(R.string.errore_fotocamera_titolo), Testi.testo(R.string.errore_nessuna_fotocamera))
            return
        }
        fotocameraPronta = false
        val ricodifica = codificaAttiva
        fermaCodifica()
        val formatoVoluto = formatoEffettivo()
        // La fotocamera smette di scrivere prima che la vecchia superficie si butti.
        cattura.chiudiEAspetta()
        val superficie = try {
            val dimensione = cattura.dimensionePer(scelto, formatoVoluto.larghezza, formatoVoluto.altezza)
            cattura.larghezzaFlusso = dimensione.width
            cattura.altezzaFlusso = dimensione.height
            renderizzatore.avvia(dimensione.width, dimensione.height, cattura.orientamentoDi(scelto))
        } catch (e: Exception) {
            fermaConErrore(Testi.testo(R.string.errore_fotocamera_titolo), Testi.testo(R.string.errore_fotocamera_spenta))
            return
        }
        if (!effettiGpu) {
            effettiGpu = renderizzatore.effettiDisponibili
            aggiornaFunzioni()
        }
        impostaVideo(formatoVoluto.larghezza, formatoVoluto.altezza)
        renderizzatore.specchiaCodifica = (scelto.frontale) xor specchiatoInterno.value
        applicaEffettiAlRenderizzatore()
        caricaSfondo()
        fotocameraInAvvio = true
        cattura.apri(scelto, formatoVoluto.fps, listOf(superficie)) { errore ->
            principale.post {
                fotocameraInAvvio = false
                if (chiusaDallUtente) return@post
                if (errore != null) {
                    // La fotocamera non c'è più (anche dopo essere stata pronta: chiusa dal sistema o presa da
                    // un'altra app mentre WebcamLR era in sottofondo). Il codificatore non riceverebbe più nulla:
                    // si ferma, e al ritorno in primo piano (o con «Riprova») si riaccende tutto.
                    fotocameraPronta = false
                    fermaCodifica()
                    cattura.chiudi()
                    aggiornaMicrofono()
                    registro.aggiungi(Testi.testo(R.string.registro_fotocamera_persa, errore))
                    if (stato !is Stato.Errore) {
                        erroreLocale = true
                        titoloErrore = Testi.testo(R.string.errore_fotocamera_titolo)
                        erroreDefinitivo = false
                        domandaErrore = null
                        oscurato = false
                        stato = Stato.Errore(errore)
                    }
                    return@post
                }
                fotocameraPronta = true
                aeafBloccati = false
                // I comandi restano anche cambiando obiettivo o formato.
                if (zoom != 1.0) cattura.impostaZoom(zoom)
                if (torciaAccesa) cattura.impostaTorcia(true)
                if (esposizione != 0.0) cattura.impostaEsposizione(esposizione)
                if (bianco != 0) cattura.impostaBianco(bianco)
                if (iso != 0.0 || tempo != 0) cattura.impostaManuale(iso, tempo)
                seguiLuce.azzera()
                if (destinazione != null || ricodifica) avviaCodifica()
                aggiornaMicrofono()
                aggiornaStato()
            }
        }
    }

    /** Le dimensioni del video inviato secondo il verso del telefono (renderizzatore, sovrapposizioni, interfaccia). */
    private fun impostaVideo(larghezza: Int, altezza: Int) {
        val l = if (verticale) minOf(larghezza, altezza) else maxOf(larghezza, altezza)
        val a = if (verticale) maxOf(larghezza, altezza) else minOf(larghezza, altezza)
        renderizzatore.impostaVideo(l, a)
        if (dimensioniInterne.value.width != l || dimensioniInterne.value.height != a) {
            dimensioniInterne.value = Size(l, a)
            aggiornaSovrapposizioni()
        }
    }

    /** Crea il codificatore per questo collegamento: il computer riceve `formato`, `capacita` e un fotogramma chiave. */
    private fun avviaCodifica() {
        val verso = destinazione ?: return
        if (!renderizzatore.rotazioneNota) {
            // 1.14: il primo `formato` ha già il verso giusto (al massimo 800 ms dall'avvio).
            principale.postDelayed({ if (destinazione === verso && !codificaAttiva && fotocameraPronta) avviaCodifica() }, 100)
            return
        }
        fermaCodifica()
        val voluto = formatoEffettivo()
        try {
            val superficie = codificatore.avvia(voluto.larghezza, voluto.altezza, voluto.fps, voluto.codec, verticale) { base ->
                synchronized(adattamento) { adattamento.bitrate(base) }
            }
            val effettivo = codificatore.formato ?: return
            attendiChiave.set(true)
            // Prima `formato` e `capacita`, poi i fotogrammi: nella coda del collegamento restano in quest'ordine.
            formato = effettivo
            verso.invia(effettivo)
            inviaCapacita()
            impostaVideo(effettivo.larghezza, effettivo.altezza)
            renderizzatore.impostaCodifica(superficie, effettivo.larghezza, effettivo.altezza)
            codificaAttiva = true
            registro.aggiungi("Video ${effettivo.larghezza}×${effettivo.altezza}, ${effettivo.fps} fps, ${nomeCodec(effettivo)}")
        } catch (e: Exception) {
            // Per esempio il codificatore hardware tolto dal sistema mentre l'app era in sottofondo: si riprova al
            // ritorno in primo piano (o con «Riprova») senza ricollegarsi.
            fermaCodifica()
            fermaConErrore(Testi.testo(R.string.errore_video_titolo), Testi.testo(R.string.errore_video))
            erroreLocale = true
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
        registro.aggiungi(Testi.testo(R.string.registro_codificatore_fermo))
        if (destinazione != null) avviaCodifica()
    }

    /** Il telefono è stato girato: subito il verso del video; se passa da verticale a orizzontale, un codificatore nuovo. */
    private fun rotazioneCambiata(nuova: Int) {
        val primaVerticale = verticale
        val prima = renderizzatore.rotazioneTelefono
        renderizzatore.rotazioneTelefono = nuova
        renderizzatore.rotazioneNota = true
        if (prima == nuova) return
        principale.post {
            if (chiusaDallUtente) return@post
            geometriaCambiata()
            if (primaVerticale != verticale) {
                principale.removeCallbacks(nuovoVerso)
                principale.postDelayed(nuovoVerso, 400)
            }
        }
    }

    /** Dopo un attimo fermo nel verso nuovo: dimensioni nuove, `formato` nuovo e fotogramma chiave. */
    private val nuovoVerso = Runnable {
        if (chiusaDallUtente) return@Runnable
        val voluto = formatoEffettivo()
        impostaVideo(voluto.larghezza, voluto.altezza)
        if (codificaAttiva && destinazione != null) avviaCodifica()
    }

    /** Specchio, obiettivo o rotazione cambiati: maschera, inquadratura e luce ripartono dal fotogramma nuovo. */
    private fun geometriaCambiata() {
        renderizzatore.inquadratura.azzera()
        renderizzatore.dimenticaMaschera()
        renderizzatore.volti = null
        analisi.dimentica()
        seguiLuce.azzera()
    }

    /** Il computer chiede un altro formato: se l'obiettivo lo sa fare si riconfigura, altrimenti si dice quello vero. */
    private fun chiediFormato(richiesta: FormatoVideo) {
        registro.aggiungi(Testi.testo(R.string.registro_computer_chiede, richiesta.larghezza, richiesta.altezza, richiesta.fps, nomeCodec(richiesta)))
        val scelto = obiettivo
        if (scelto != null) {
            val nuovo = FormatoRichiesto.da(richiesta) { l, a -> cattura.fpsMassimo(scelto, l, a) { ll, aa -> codificatore.fpsMassimo(ll, aa, richiesta.codec) } }
            if (nuovo != null) {
                formatoRichiesto = nuovo
                val atteso = formatoEffettivo()
                val attuale = formato
                val uguale = attuale != null && maxOf(attuale.larghezza, attuale.altezza) == atteso.larghezza &&
                    attuale.fps == atteso.fps && attuale.codec == atteso.codec
                if (!uguale && fotocameraPronta && !chiusaDallUtente) {
                    avviaFotocamera()
                    return
                }
            }
        }
        // Niente da cambiare, o non si può: il formato effettivo.
        formato?.let { collegamento?.invia(it) }
    }

    /** Comandi della fotocamera e degli effetti, dal computer o dall'interfaccia: solo i campi presenti, nei limiti. */
    fun applica(ricevuto: Comando) {
        // Senza WebcamLR Pro i campi che accenderebbero una funzione Pro si ignorano; lo `stato` dopo riallinea il computer.
        val comando = if (pro) ricevuto else LimitiGratis.soloGratis(ricevuto)
        val ignorato = comando != ricevuto
        comando.obiettivo?.let { nome -> obiettivi.firstOrNull { it.nome == nome }?.let { scegli(it) } }
        comando.zoom?.let { impostaZoom(it) }
        comando.torcia?.let { accesa -> if (accesa != torciaAccesa && haTorcia) cambiaTorcia() }
        comando.esposizione?.let {
            esposizione = limita(it, -2.0, 2.0, 0.0)
            cattura.impostaEsposizione(esposizione)
        }
        comando.bianco?.let {
            bianco = if (it == 0) 0 else it.coerceIn(2500, 7500)
            cattura.impostaBianco(bianco)
        }
        if (comando.fuoco == "continuo") {
            cattura.fuocoContinuo()
            aeafBloccati = false
        }
        if (comando.iso != null || comando.tempo != null) {
            val massimo = cattura.limitiIso?.second ?: 100_000.0
            iso = limita(comando.iso ?: iso, 0.0, massimo, 0.0)
            // Anche il limite in alto: lo `stato` non rimanda mai al computer valori assurdi.
            tempo = (comando.tempo ?: tempo).coerceIn(0, 100_000)
            cattura.impostaManuale(iso, tempo)
        }
        val effettiNuovi = ModelloEffetti.applica(effettiInterni.value, comando)
        if (effettiNuovi != effettiInterni.value) cambiaEffetti(effettiNuovi)
        comando.specchia?.let { impostaSpecchio(it) }
        comando.audio?.let { impostaAudio(it) }
        comando.collegamento?.let { impostaPreferenzaCollegamento(it) }
        aggiornaControlli()
        if (ignorato) registro.aggiungi(Testi.testo(R.string.registro_pro_ignorato))
        if (ignorato || comando.esposizione != null || comando.bianco != null || comando.iso != null || comando.tempo != null) aggiornaStato()
    }

    // Effetti

    /** Effetti cambiati (dal telefono, dal computer o dalle Impostazioni): GPU e analisi subito, `stato` e salvataggio dopo un attimo. */
    private fun cambiaEffetti(nuovi: StatoEffetti) {
        val prima = effettiInterni.value
        if (nuovi == prima) return
        effettiInterni.value = nuovi
        sfondoInterno.value = nuovi.sfondo
        applicaEffettiAlRenderizzatore()
        if (!nuovi.luceVolto && prima.luceVolto) {
            seguiLuce.azzera()
            cattura.esponiSulVolto(null)
        }
        if (!nuovi.postura) {
            postura.azzera()
            avvisoPosturaInterno.value = null
        }
        if (nuovi.sfondo == ModiSfondo.SOSTITUITO && (prima.sfondo != ModiSfondo.SOSTITUITO || nuovi.sfondoScelto != prima.sfondoScelto)) caricaSfondo()
        if (nuovi.nomeScritta != prima.nomeScritta || nuovi.ruoloScritta != prima.ruoloScritta || nuovi.mostraLogo != prima.mostraLogo) {
            aggiornaSovrapposizioni()
        }
        principale.removeCallbacks(effettiDaSalvare)
        principale.postDelayed(effettiDaSalvare, 250)
    }

    private val effettiDaSalvare = Runnable {
        Impostazioni.salvaEffetti(effettiInterni.value)
        aggiornaStato()
    }

    /** L'istantanea degli effetti per la GPU e cosa deve cercare l'analisi. */
    private fun applicaEffettiAlRenderizzatore() {
        val e = effettiInterni.value
        val f = funzioniInterne.value
        val sfondo = when {
            !f.sfondo -> ParametriEffetti.Sfondo.NESSUNO
            e.sfondo == ModiSfondo.SFOCATO -> ParametriEffetti.Sfondo.SFOCATO
            e.sfondo == ModiSfondo.SOSTITUITO -> ParametriEffetti.Sfondo.SOSTITUITO
            else -> ParametriEffetti.Sfondo.NESSUNO
        }
        renderizzatore.effetti = if (!effettiGpu) ParametriEffetti() else ParametriEffetti(
            ricetta = if (e.filtro == Filtri.NATURALE) null else RicetteFiltri.ricetta(e.filtro),
            luminosita = e.luminosita.toFloat(),
            contrasto = e.contrasto.toFloat(),
            saturazione = e.saturazione.toFloat(),
            nitidezza = e.nitidezza.toFloat(),
            sfondo = sfondo,
            intensitaSfondo = e.intensitaSfondo.toFloat(),
            pelle = e.pelle.toFloat(),
            luceVolto = e.luceVolto && f.volti,
        )
        renderizzatore.inquadratura.acceso = e.inquadratura && f.volti
        analisi.vuoleMaschera = sfondo != ParametriEffetti.Sfondo.NESSUNO
        analisi.vuoleVolti = f.volti && (e.inquadratura || e.luceVolto || e.postura)
        renderizzatore.analisiRichiesta = analisi.vuoleMaschera || analisi.vuoleVolti
    }

    /** L'immagine dello sfondo sostituito, letta fuori dal thread principale. */
    private fun caricaSfondo() {
        val e = effettiInterni.value
        if (e.sfondo != ModiSfondo.SOSTITUITO) return
        val scelto = e.sfondoScelto
        val renderizzatore = renderizzatore
        inSottofondo {
            val immagine = grafica.sfondo(scelto) ?: grafica.sfondo(SfondiPronti.STUDIO)
            renderizzatore.impostaSfondo(immagine)
        }
    }

    /** Sottopancia e logo per le dimensioni attuali del video, disegnati fuori dal thread principale. */
    private fun aggiornaSovrapposizioni() {
        val e = effettiInterni.value
        val dimensioni = dimensioniInterne.value
        if (dimensioni.width <= 0 || !effettiGpu) return
        val nome = if (funzioniInterne.value.scritta) e.nomeScritta else ""
        val ruolo = e.ruoloScritta
        val mostraLogo = e.mostraLogo
        val logoNoto = logoCaricato
        inSottofondo {
            val logo = if (mostraLogo) logoNoto ?: grafica.caricaLogo()?.also { letto -> principale.post { logoCaricato = letto } } else null
            renderizzatore.impostaSovrapposizioni(grafica.sovrapposizioni(nome, ruolo, logo, dimensioni.width, dimensioni.height))
        }
    }

    /** I volti dell'analisi (circa 12 al secondo): luce sul volto e postura. */
    private fun voltiAggiornati(volti: VoltiTrovati) {
        if (chiusaDallUtente) return
        val e = effettiInterni.value
        val specchia = renderizzatore.specchiaCodifica
        val principaleVolto = volti.principale(specchia)
        val adesso = SystemClock.elapsedRealtime()
        if (e.luceVolto) {
            when (val azione = seguiLuce.considera(principaleVolto, adesso)) {
                is SeguiLuce.Esponi -> parametriGeometria()?.let { p ->
                    val r = azione.volto
                    cattura.esponiSulVolto(Geometria.rettangoloAllaFotocamera(r.sinistra, r.alto, r.destra, r.basso, p))
                }
                SeguiLuce.Lascia -> cattura.esponiSulVolto(null)
                null -> Unit
            }
        }
        if (e.postura) {
            postura.considera(principaleVolto, stato == Stato.Collegato && inOnda != null, adesso)?.let { avviso ->
                avvisoPosturaInterno.value = avviso
                vibra(30)
                principale.removeCallbacks(nascondiPostura)
                principale.postDelayed(nascondiPostura, 7_000)
            }
        }
    }

    private val nascondiPostura = Runnable { avvisoPosturaInterno.value = null }

    private fun parametriGeometria(): ParametriGeometria? {
        val scelto = obiettivo ?: return null
        val (l, a) = renderizzatore.dimensioniVideo
        return ParametriGeometria(
            larghezzaFotocamera = renderizzatore.larghezzaFotocamera,
            altezzaFotocamera = renderizzatore.altezzaFotocamera,
            orientamentoSensore = cattura.orientamentoSensore,
            frontale = scelto.frontale,
            rotazioneTelefono = renderizzatore.rotazioneTelefono,
            specchia = renderizzatore.specchiaCodifica,
            larghezzaVideo = l,
            altezzaVideo = a,
        )
    }

    /** Cosa si può dichiarare al computer: GPU, modelli dell'analisi, microfono. */
    private fun aggiornaFunzioni() {
        if (chiusaDallUtente) return
        val microfono = app.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE) && !microfonoNegato
        val nuove = FunzioniDisponibili(
            filtri = effettiGpu,
            sfondo = effettiGpu && analisi.mascheraDisponibile,
            pelle = effettiGpu,
            scritta = effettiGpu,
            volti = effettiGpu && analisi.voltiDisponibili,
            audio = microfono,
        )
        if (nuove == funzioniInterne.value) return
        funzioniInterne.value = nuove
        applicaEffettiAlRenderizzatore()
        aggiornaSovrapposizioni()
        if (destinazione != null) {
            inviaCapacita()
            aggiornaStato()
        }
    }

    /** Una scelta cambiata nel file delle impostazioni dall'interfaccia (stesse chiavi dell'iPhone). */
    private fun impostazioneCambiata(chiave: String?) {
        if (chiusaDallUtente) return
        val salvati = Impostazioni.effetti()
        val attuali = effettiInterni.value
        when (chiave) {
            Impostazioni.CHIAVE_INQUADRATURA -> if (salvati.inquadratura != attuali.inquadratura) applica(Comando(inquadratura = salvati.inquadratura))
            Impostazioni.CHIAVE_LUCE_VOLTO -> if (salvati.luceVolto != attuali.luceVolto) applica(Comando(luceVolto = salvati.luceVolto))
            Impostazioni.CHIAVE_POSTURA -> if (salvati.postura != attuali.postura) applica(Comando(postura = salvati.postura))
            Impostazioni.CHIAVE_FACCIA_IN_GIU -> pausaDecisa.facciaInGiuAbilitata = Impostazioni.pausaFacciaInGiu
            Impostazioni.CHIAVE_SPECCHIO -> aggiornaSpecchio()
            Impostazioni.CHIAVE_COLLEGAMENTO -> impostaPreferenzaCollegamento(Impostazioni.collegamento)
        }
        // Per esempio l'inquadratura senza Pro: la scelta salvata torna al valore vero.
        val vero = effettiInterni.value
        if (chiave in listOf(Impostazioni.CHIAVE_INQUADRATURA, Impostazioni.CHIAVE_LUCE_VOLTO, Impostazioni.CHIAVE_POSTURA) &&
            (salvati.inquadratura != vero.inquadratura || salvati.luceVolto != vero.luceVolto || salvati.postura != vero.postura)
        ) {
            Impostazioni.salvaEffetti(vero)
        }
    }

    // Pausa (P07, P10)

    /**
     * Il motivo della pausa è cambiato. In pausa nessun fotogramma va al codificatore; `ping`, `pong` e `stato`
     * continuano. Alla ripresa, come vuole il protocollo, prima lo `stato` senza `pausa`, poi `formato` e il video da un
     * fotogramma chiave.
     */
    private fun pausaCambiata() {
        if (chiusaDallUtente) return
        val eraInPausa = pausaInterna.value != null
        aggiornaPausa()
        val inPausa = pausaInterna.value != null
        postura.azzera()
        if (inPausa && !eraInPausa) {
            registro.aggiungi(Testi.testo(R.string.registro_pausa, pausaInterna.value.orEmpty()))
            if (pausaDecisa.facciaInGiu) vibra(80)
            aggiornaStato()
        } else if (!inPausa && eraInPausa) {
            registro.aggiungi(Testi.testo(R.string.registro_pausa_finita))
            aggiornaStato()
            attendiChiave.set(true)
            if (fotocameraPronta && codificaAttiva) {
                formato?.let { destinazione?.invia(it) }
                codificatore.richiediFotogrammaChiave(subito = true)
            }
            vibra(30)
        } else {
            aggiornaStato()
        }
        renderizzatore.codificaInPausa = inPausa
        // P10: senza nessuno che guarda la fotocamera si spegne (batteria e calore); alla ripresa si riaccende.
        if (pausaDecisa.fotocameraSpenta && fotocameraPronta) {
            fermaCodifica()
            cattura.chiudiEAspetta()
            fotocameraPronta = false
            registro.aggiungi(Testi.testo(R.string.registro_fotocamera_spenta))
        } else if (!pausaDecisa.fotocameraSpenta && !fotocameraPronta && stato == Stato.Collegato) {
            avviaFotocamera()
        }
        aggiornaMicrofono()
    }

    private fun aggiornaPausa() {
        val motivo = pausaDecisa.motivo
        pausaInterna.value = motivo
        renderizzatore.codificaInPausa = motivo != null
    }

    // Microfono (P20)

    private fun permessoMicrofono(): Boolean =
        ContextCompat.checkSelfPermission(app, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    /** Il microfono va solo se serve davvero: chiesto, fotocamera accesa, collegati e niente pausa. */
    private fun aggiornaMicrofono() {
        val serve = audioRichiestoInterno.value && !chiusaDallUtente && fotocameraPronta && pausaInterna.value == null && permessoMicrofono()
        if (serve && !codificatoreAudio.inFunzione) codificatoreAudio.avvia() else if (!serve && codificatoreAudio.inFunzione) codificatoreAudio.ferma()
        aggiornaAudioInviato()
    }

    private fun aggiornaAudioInviato() {
        val inviando = codificatoreAudio.inFunzione && stato == Stato.Collegato && pausaInterna.value == null
        if (inviando != audioInviatoInterno.value) {
            audioInviatoInterno.value = inviando
            if (destinazione != null) aggiornaStato()
        }
    }

    private fun microfonoFermo(motivo: String) {
        if (chiusaDallUtente) return
        registro.aggiungi(Testi.testo(R.string.registro_microfono_non_disponibile, motivo))
        audioRichiestoInterno.value = false
        mostraAvvisoMicrofono(Testi.testo(R.string.microfono_non_disponibile, motivo))
        aggiornaAudioInviato()
        aggiornaStato()
    }

    private fun mostraAvvisoMicrofono(testo: String) {
        avvisoMicrofonoInterno.value = testo
        principale.removeCallbacks(nascondiAvvisoMicrofono)
        principale.postDelayed(nascondiAvvisoMicrofono, 6_000)
    }

    private val nascondiAvvisoMicrofono = Runnable { avvisoMicrofonoInterno.value = null }

    // WebcamLR Pro

    /**
     * Acquisto, ripristino o rimborso, anche a sessione aperta: il computer lo sa subito (`capacita.pro`), gli effetti
     * Pro si spengono se Pro non c'è più e, se cambia il formato possibile (720p30 ↔ quello scelto), la fotocamera si
     * riconfigura una volta.
     */
    private fun proCambiato(nuovo: Boolean) {
        if (nuovo == pro || chiusaDallUtente) return
        val prima = formatoEffettivo()
        pro = nuovo
        if (!nuovo) spegniFunzioniPro()
        val dopo = formatoEffettivo()
        if (prima != dopo && fotocameraPronta) {
            avviaFotocamera()
        } else {
            inviaCapacita()
            aggiornaStato()
        }
    }

    /** Senza Pro restano specchio, sfondo sfocato, luce sul volto, postura, microfono, zoom, torcia e compensazione. */
    private fun spegniFunzioniPro() {
        cambiaEffetti(ModelloEffetti.spegniPro(effettiInterni.value))
        if (iso != 0.0 || tempo != 0) {
            iso = 0.0
            tempo = 0
            cattura.impostaManuale(0.0, 0)
        }
        if (bianco != 0) {
            bianco = 0
            cattura.impostaBianco(0)
        }
        aggiornaControlli()
        registro.aggiungi(Testi.testo(R.string.registro_pro_spento))
    }

    // Stato del telefono

    /**
     * Le qualità che il telefono sa fare davvero con l'obiettivo e il codec attuali, senza i limiti di Pro: le stesse
     * di `capacita.formati` (il computer le mostra con gli stessi nomi), così le Impostazioni offrono le stesse scelte.
     * `null` finché non c'è un obiettivo. Dal thread principale.
     */
    fun formatiPossibili(): List<it.lrapps.webcamlr.protocollo.FormatoSupportato>? {
        val scelto = obiettivo ?: return null
        val codec = Impostazioni.codecScelto
        return formatiNoti.getOrPut("${scelto.idFotocamera}/${scelto.nome}/${codec.valore}") {
            cattura.formatiSupportati(scelto) { l, a -> codificatore.fpsMassimo(l, a, codec) }
        }
    }

    /** Dice al computer cosa può comandare con l'obiettivo attuale. */
    private fun inviaCapacita(verso: Collegamento? = destinazione) {
        if (verso == null) return
        val limiti = cattura.limitiIso
        val possibili = formatiPossibili()
        val formati = possibili?.let { tutti -> if (pro) tutti else LimitiGratis.formati(tutti) }
        // Gratis: anche le qualità che il Pro sbloccherebbe, così il computer le mostra grigie con «PRO» come qui.
        val formatiPro = if (pro || possibili.isNullOrEmpty()) null else LimitiGratis.formatiPro(possibili)
        val base = Capacita(
            obiettivi = obiettivi.map { it.nome },
            zoomMassimo = cattura.zoomMassimo,
            torcia = haTorcia,
            isoMinimo = limiti?.first,
            isoMassimo = limiti?.second,
            formati = formati?.takeIf { it.isNotEmpty() },
            specchia = true,
            pro = pro,
            // Sa passare tra Wi-Fi e cavo e accetta `comando.collegamento`.
            sceltaCollegamento = true,
            formatiPro = formatiPro,
        )
        verso.invia(ModelloEffetti.completa(base, funzioniInterne.value))
    }

    private val statoPeriodico = object : Runnable {
        override fun run() {
            aggiornaStato()
            principale.postDelayed(this, 5_000)
        }
    }

    private fun aggiornaStato() {
        misuraStato()
        val strade = costruisciStatoCollegamento()
        statoCollegamento = strade
        destinazione?.let { verso ->
            val base = StatoTelefono(
                batteria = batteria,
                inCarica = inCarica,
                temperatura = temperatura,
                obiettivo = obiettivo?.nome ?: "principale",
                audio = audioInviatoInterno.value,
                pausa = pausaInterna.value,
                specchia = specchiatoInterno.value,
                zoom = zoom,
                torcia = torciaAccesa,
                esposizione = esposizione,
                bianco = bianco,
                iso = iso,
                tempo = tempo,
                collegamento = strade,
            )
            verso.invia(ModelloEffetti.completa(base, effettiInterni.value, funzioniInterne.value))
        }
        if (regolaQualita() && fotocameraPronta) avviaFotocamera()
    }

    private fun aggiornaControlli() {
        controlliInterni.value = ControlliFotocamera(zoom, torciaAccesa, esposizione, bianco, iso, tempo)
    }

    private fun caloreCambiato() {
        if (chiusaDallUtente) return
        misuraStato()
        if (regolaQualita() && fotocameraPronta) avviaFotocamera()
        if (destinazione != null) aggiornaStato()
    }

    private fun misuraStato() {
        val misura = StatoDispositivo.misura(app)
        if (misura.batteria != batteria) batteria = misura.batteria
        if (misura.inCarica != inCarica) inCarica = misura.inCarica
        if (misura.temperatura != temperatura) temperatura = misura.temperatura
    }

    /**
     * 1.14: il calore a gradini con isteresi ([RegolatoreCalore]); 24 fps con la batteria sotto il 20% senza caricatore,
     * fino al 25% o al caricatore. Vero se la fotocamera va riconfigurata.
     */
    private fun regolaQualita(): Boolean {
        var cambiata = false
        val nuova = regolatoreCalore.valuta(temperatura, Impostazioni.riduciSeCaldo, SystemClock.elapsedRealtime())
        if (nuova != caloreInterno.value) {
            registro.aggiungi(Testi.testo(if (nuova > caloreInterno.value) R.string.registro_caldo else R.string.registro_fresco, nuova.perRegistro))
            caloreInterno.value = nuova
            cambiata = true
        }
        val ridotta = nuova >= RiduzioneCalore.A1080P30
        if (ridotta != qualitaRidotta) qualitaRidotta = ridotta
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

    /** Il verso del telefono prima del primo valore del sensore: quello dello schermo (uguale se l'app gira con il telefono). */
    private fun rotazioneIniziale(): Int {
        val schermo = try {
            (app.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager).getDisplay(Display.DEFAULT_DISPLAY)?.rotation ?: Surface.ROTATION_0
        } catch (e: Exception) {
            Surface.ROTATION_0
        }
        val gradi = when (schermo) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
        return (360 - gradi) % 360
    }

    private fun vibra(millisecondi: Long) {
        try {
            @Suppress("DEPRECATION")
            val vibratore = app.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
            if (vibratore.hasVibrator()) vibratore.vibrate(VibrationEffect.createOneShot(millisecondi, VibrationEffect.DEFAULT_AMPLITUDE))
        } catch (e: Exception) {
            // nessuna vibrazione: non importa
        }
    }

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

    /** C'è una rete del telefono, oppure il cavo (il Tethering USB non è una rete per ConnectivityManager). */
    private fun reteOCavo(connessioni: ConnectivityManager): Boolean =
        connessioni.activeNetwork != null || RicercaCavo.interfacceDelCavo().isNotEmpty()

    private fun osservaRete() {
        val connessioni = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val ascolto = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(rete: Network) {
                principale.post { reteCambiata(true) }
            }

            override fun onLost(rete: Network) {
                principale.post { reteCambiata(reteOCavo(connessioni)) }
            }
        }
        reteDisponibile = reteOCavo(connessioni)
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
            registro.aggiungi(Testi.testo(if (disponibile) R.string.registro_rete_tornata else R.string.registro_rete_persa))
        }
        if (tornata && !chiusaDallUtente && collegamento == null && stato is Stato.Riconnessione) {
            tentativi = 1
            collega()
        }
    }

    companion object {
        const val TENTATIVI_MASSIMI = 5

        fun nomeCodec(formato: FormatoVideo) = if (formato.codec.valore == "hevc") "HEVC" else "H.264"

        /** Il nome della qualità come sul computer e nelle Impostazioni: «720p», «1080p», «4K» (dal lato corto). */
        fun nomeQualita(larghezza: Int, altezza: Int): String {
            val corto = minOf(larghezza, altezza)
            return if (corto >= 2160) "4K" else "${corto}p"
        }

        /** «Wi-Fi», «Cavo USB»… nella lingua dell'app, per il registro (nell'interfaccia: testoTipoCollegamento). */
        fun testoTipo(tipo: TipoCollegamento): String = Testi.testo(
            when (tipo) {
                TipoCollegamento.WIFI -> R.string.collegamento_wifi
                TipoCollegamento.CAVO_USB -> R.string.collegamento_cavo_usb
                TipoCollegamento.WIFI_DIRETTO -> R.string.collegamento_wifi_diretto
                TipoCollegamento.CAVO_DI_RETE -> R.string.collegamento_cavo_rete
                TipoCollegamento.HOTSPOT -> R.string.collegamento_hotspot
            },
        )

        /** Il cavo è il Tethering USB; tutto il resto (Wi-Fi, hotspot, Wi-Fi diretto, cavo di rete) è la rete. */
        fun stradaDi(tipo: TipoCollegamento): Strada = if (tipo == TipoCollegamento.CAVO_USB) Strada.CAVO else Strada.WIFI

        /** `stato.collegamento.attivo` (Protocollo.md). */
        fun valoreAttivo(tipo: TipoCollegamento): String = when (tipo) {
            TipoCollegamento.WIFI -> "wifi"
            TipoCollegamento.CAVO_USB -> "cavo"
            TipoCollegamento.HOTSPOT -> "hotspot"
            TipoCollegamento.WIFI_DIRETTO -> "wifiDiretto"
            TipoCollegamento.CAVO_DI_RETE -> "rete"
        }

        /** «Wi-Fi» o «Cavo USB» nella lingua dell'app, per il registro. */
        fun testoStrada(strada: Strada): String =
            Testi.testo(if (strada == Strada.CAVO) R.string.collegamento_cavo_usb else R.string.collegamento_wifi)

        /** «Automatico», «Wi-Fi» o «Cavo USB» nella lingua dell'app, per il registro. */
        fun testoPreferenza(preferenza: String): String = PreferenzeCollegamento.strada(preferenza)?.let { testoStrada(it) }
            ?: Testi.testo(R.string.collegamento_automatico)

        /**
         * Da un punto dell'anteprima della fotocamera (0–1, y verso il basso; lettore QR) al punto sul sensore: si toglie
         * la rotazione dello schermo, lo specchio della frontale e l'orientamento del sensore.
         */
        fun puntoSulSensore(x: Float, y: Float, rotazioneSchermo: Int, orientamentoSensore: Int, frontale: Boolean): Pair<Float, Float> {
            var punto = Geometria.antiorario(x, y, rotazioneSchermo)
            if (frontale) punto = (1f - punto.first) to punto.second
            return Geometria.antiorario(punto.first, punto.second, orientamentoSensore)
        }
    }
}

private val MotivoChiusura.perRegistro: String
    get() = Testi.testo(
        when (this) {
            MotivoChiusura.RETE -> R.string.registro_motivo_rete
            MotivoChiusura.DAL_COMPUTER -> R.string.registro_motivo_dal_computer
            MotivoChiusura.COMPUTER_VECCHIO -> R.string.registro_motivo_computer_vecchio
            MotivoChiusura.IDENTITA_CAMBIATA -> R.string.registro_motivo_identita_cambiata
            MotivoChiusura.IDENTITA_NON_VALIDA -> R.string.registro_motivo_identita_non_valida
        },
    )

/** Il gradino del calore in parole, per il registro. */
private val RiduzioneCalore.perRegistro: String
    get() = Testi.testo(
        when (this) {
            RiduzioneCalore.NESSUNA -> R.string.registro_calore_nessuna
            RiduzioneCalore.A30FPS -> R.string.registro_calore_30fps
            RiduzioneCalore.A1080P30 -> R.string.registro_calore_1080p30
            RiduzioneCalore.A720P24 -> R.string.registro_calore_720p24
        },
    )
