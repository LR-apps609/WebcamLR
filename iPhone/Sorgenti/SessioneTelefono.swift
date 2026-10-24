import CoreMedia
import Foundation
import Network
import Observation
import UIKit
import WebcamLRProtocollo

/// Un valore letto e scritto da più code.
final class Protetto<Valore>: @unchecked Sendable {
    private let blocco = NSLock()
    private var interno: Valore

    init(_ valore: Valore) {
        interno = valore
    }

    var valore: Valore {
        get { blocco.withLock { interno } }
        set { blocco.withLock { interno = newValue } }
    }
}

/// Una sessione con un computer: collegamento, fotocamera, codifica e stato del telefono (round 1).
@Observable
@MainActor
final class SessioneTelefono {
    enum Stato: Equatable {
        case collegamento
        case collegato
        case riconnessione(tentativo: Int)
        case chiusa
        case errore(String)
    }

    static let tentativiMassimi = 5

    /// Con il cavo USB il nome vero arriva nel `benvenuto` (1.6).
    private(set) var computer: ComputerTrovato
    let cattura = Cattura()

    private(set) var stato: Stato = .collegamento
    private(set) var latenzaMs: Int?
    /// Un'app sul computer sta usando la webcam: il rosso «IN ONDA».
    private(set) var inOnda: InOnda?
    private(set) var larghezza = 0
    private(set) var altezza = 0
    private(set) var fps = 30
    private(set) var codec: Codec = .h264
    /// Come si è collegati (1.2): Wi-Fi, cavo USB, Wi-Fi diretto…; `nil` finché non si sa.
    private(set) var tipoCollegamento: TipoCollegamento?
    private(set) var obiettivo: Obiettivo = .principale
    let obiettiviDisponibili = Obiettivo.disponibili
    private(set) var torciaAccesa = false
    /// Zoom dentro l'obiettivo scelto: 1 = nessuno.
    private(set) var zoom: CGFloat = 1
    /// Comandati dal computer; si riapplicano quando cambia l'obiettivo.
    private(set) var esposizione: Double = 0
    private(set) var bianco = 0
    /// Esposizione manuale dal computer: 0 = automatico.
    private(set) var iso: Double = 0
    private(set) var tempo = 0
    /// Ultimo punto toccato per il fuoco, nelle coordinate dello schermo (per il riquadro giallo).
    private(set) var puntoFuoco: CGPoint?
    private var compitoFuoco: Task<Void, Never>?
    /// Fuoco ed esposizione bloccati con il tocco lungo: «AE/AF bloccati» (round 2).
    private(set) var aeafBloccati = false
    /// Da quando si cerca di ritrovare il computer perso: i secondi nel banner (round 2).
    private(set) var inizioRiconnessione: Date?
    private(set) var batteria = -1
    private(set) var temperatura: Temperatura = .normale
    private(set) var inCarica = false
    /// Il telefono è molto caldo: 720p e meno fotogrammi finché non torna normale (funzione 31).
    private(set) var qualitaRidotta = false
    /// Batteria sotto il 20% senza caricatore: 24 fps finché non si ricarica (round 2, novità 17).
    private(set) var risparmioBatteria = false
    /// La rete non regge la qualità scelta: il bitrate è sceso da solo (round 2, novità 4).
    private(set) var reteDebole = false
    /// Fotogrammi scartati negli ultimi 5 secondi, per la qualità del collegamento in parole.
    private(set) var perditeRecenti = 0
    @ObservationIgnored private var perditeUltimiSecondi: [Int] = []
    /// Il computer chiede all'utente di consentire questo iPhone: il codice di conferma, uguale sui due schermi (0.10).
    private(set) var codiceConferma: String?
    /// Titolo del pannello d'errore: dice se non ci si è mai collegati, se il computer va aggiornato…
    private(set) var titoloErrore = "Collegamento interrotto"
    /// Riprovare non serve (l'identità del computer è cambiata): si torna ai computer e si usa il QR code.
    private(set) var erroreDefinitivo = false
    /// La domanda frequente che spiega l'errore (1.4), per il link «Perché succede?».
    private(set) var domandaErrore: String?
    /// La causa probabile quando non ci si riesce a collegare, con la sua azione (1.3).
    private(set) var diagnosi: Diagnosi?
    /// Almeno un `benvenuto` in questa sessione: prima il computer non è «perso», non ci si è ancora collegati.
    private(set) var giaCollegato = false
    /// L'ultima latenza nota, che resta anche dopo la chiusura: serve a «Segnala un bug».
    private(set) var ultimaLatenzaMs: Int?
    /// L'impronta del computer dopo la stretta di mano: si salva tra i computer conosciuti al `benvenuto`.
    @ObservationIgnored private var improntaComputer: String?
    /// 1.11: dall'avvio della sessione al primo fotogramma spedito, per la modalità avanzata («Avvio: 1,4 s»).
    private(set) var tempoAvvio: TimeInterval?
    /// 1.11: da quando si misura il prossimo «primo fotogramma» e come lo si dice nel registro; `nil` = niente da misurare.
    @ObservationIgnored private var misura: (inizio: Date, testo: String, avvio: Bool)?
    /// 1.11: sessione preparata durante il conto alla rovescia del ricollegamento: collegamento sicuro e fotocamera
    /// partono, ma il `ciao` (e quindi il video) aspetta `conferma()`.
    @ObservationIgnored private var ciaoTrattenuto = false
    /// Il collegamento attuale è pronto e aspetta solo il `ciao` trattenuto.
    @ObservationIgnored private var ciaoInAttesa = false

    /// Avviso batteria (funzione 33): sotto il 20% e non in carica.
    var batteriaBassa: Bool {
        batteria >= 0 && batteria < 20 && !inCarica
    }
    var oscurato = false

    private let codificatore = Codificatore()
    /// Effetti e analisi tra la cattura e il codificatore (P02). Senza effetti attivi il fotogramma passa intatto.
    let effetti = PipelineEffetti()
    /// Inquadratura automatica, luce sul volto e postura (P04, P08, P11).
    let funzioni: FunzioniVolto
    /// P05: luce del volto e dello sfondo per «Prova la webcam»; spenta non costa nulla.
    let sonda = SondaLuce()
    /// 1.5: gli eventi del collegamento, per la modalità avanzata.
    private var registro: RegistroCollegamento { RegistroCollegamento.condiviso }
    private let identitaTelefono = IdentitaTelefono.condivisa
    private let destinazione = Protetto<Collegamento?>(nil)
    private var collegamento: Collegamento?
    private var compitoStato: Task<Void, Never>?
    private var tentativi = 0
    private var chiusaDallUtente = false
    /// La fotocamera è configurata e in funzione con le impostazioni attuali.
    @ObservationIgnored private var fotocameraPronta = false
    /// P03: le impostazioni video con cui la fotocamera è partita l'ultima volta, per capire alla chiusura
    /// delle Impostazioni aperte da «In onda» se serve riconfigurarla.
    @ObservationIgnored private var impostazioniApplicate: ImpostazioniVideo?
    /// L'accensione della fotocamera partita all'apertura, mentre il collegamento si apre.
    @ObservationIgnored private var compitoFotocamera: Task<Void, Never>?
    /// Il prossimo tentativo di ricollegamento in attesa.
    @ObservationIgnored private var compitoRiprova: Task<Void, Never>?
    /// Quando la rete torna si riprova subito, senza aspettare il tentativo successivo.
    @ObservationIgnored private var monitorRete: NWPathMonitor?
    /// Osservata: senza rete il banner lo dice, invece di «Computer perso».
    private(set) var reteDisponibile = true
    /// 1.6: sessione via cavo senza collegamento: si aspetta che il computer riapra la connessione sul cavo.
    /// Mentre è vero la schermata dei computer tiene acceso l'ascolto e passa qui la connessione (`accogli`).
    private(set) var attendeCavo = false
    /// La connessione dal cavo arrivata e non ancora usata.
    @ObservationIgnored private var connessioneCavo: NWConnection?
    @ObservationIgnored private var compitoAttesaCavo: Task<Void, Never>?
    /// Senza cavo per tanto tempo ci si ferma e lo si dice; l'ascolto resta acceso.
    private static let attesaCavo: Duration = .seconds(20)

    /// 1.9: un collegamento dal cavo arrivato durante una sessione Wi-Fi. Fa la sua stretta di mano a parte,
    /// senza toccare il video sul Wi-Fi; al `benvenuto` dello stesso computer il video passa a lui.
    @ObservationIgnored private var candidato: Collegamento?
    /// Diventa vero quando il candidato prende il posto del Wi-Fi: prima non conta per il bitrate né per le perdite.
    @ObservationIgnored private var inUsoCandidato: Protetto<Bool>?
    @ObservationIgnored private var improntaCandidato: String?
    @ObservationIgnored private var tipoCandidato: TipoCollegamento?
    /// Il Wi-Fi si è chiuso mentre il candidato si collegava (di solito l'`arrivederci` del computer, che ha già
    /// accettato il cavo): si decide quando si sa com'è andato il cavo.
    @ObservationIgnored private var chiusuraRinviata: (errore: String?, motivo: Collegamento.MotivoChiusura, inAttesaDiConferma: Bool)?
    @ObservationIgnored private var candidatiFalliti = 0
    /// Il cavo porta a un altro computer, o non è riuscito più volte: in questa sessione resta il Wi-Fi.
    private var cavoEscluso = false
    /// Il computer raggiunto in Wi-Fi prima di passare al cavo: se il cavo si stacca lo si cerca lì.
    @ObservationIgnored private var computerWiFi: ComputerTrovato?
    /// 1.9: il cavo si è staccato e si prova il Wi-Fi, mentre il cavo può ancora tornare (per il banner).
    private(set) var daCavoAlWiFi = false

    /// 1.12: il computer fidato non risponde più (WebcamLR chiuso o riaperto sul computer, rete cambiata): niente errore,
    /// «In attesa di …» con calma, e ci si ricollega da soli quando torna.
    private(set) var inAttesaDelComputer = false
    /// Dopo un `arrivederci` si riprova solo quando il computer sparisce e ricompare nella ricerca (WebcamLR riaperto):
    /// se l'ha scollegato l'utente sul computer resta annunciato, e l'iPhone non si impone.
    private(set) var soloAlRitorno = false
    /// La ricerca Bonjour di questo computer mentre lo si aspetta.
    @ObservationIgnored private var ricercaAttesa: NWBrowser?
    @ObservationIgnored private var inizioRicercaAttesa = Date()
    /// Il computer si vede nella ricerca; `nil` finché la ricerca non ha detto nulla.
    @ObservationIgnored private var computerVisibile: Bool?
    /// Quanti tentativi a tempo dall'inizio dell'attesa: l'intervallo cresce (`attesePerTentativo`).
    @ObservationIgnored private var tentativiInAttesa = 0
    /// Mai due tentativi in attesa a meno di 2 secondi: niente raffiche quando ricerca e rete cambiano insieme.
    @ObservationIgnored private var ultimoTentativoInAttesa: Date?
    /// In sottofondo non si riprova e non si cerca: batteria.
    @ObservationIgnored private var inPrimoPiano = true
    @ObservationIgnored private var osservatoriApp: [NSObjectProtocol] = []
    /// Dopo un po' di attesa lo schermo può tornare a spegnersi da solo.
    @ObservationIgnored private var compitoSchermo: Task<Void, Never>?
    /// Interfacce e router della rete attuale: se cambiano (altro Wi-Fi, Hotspot personale) si riprova subito.
    @ObservationIgnored private var firmaRete: String?
    private static let attesePerTentativo: [Duration] = [.seconds(5), .seconds(10), .seconds(20), .seconds(40), .seconds(60)]

    var viaCavo: Bool { computer.cavo }

    /// 1.9: durante una sessione Wi-Fi l'ascolto sul cavo resta acceso, anche mentre ci si ricollega o dopo un errore
    /// da cui si può riprovare. Serve un codice di sicurezza noto: il cavo si usa solo se porta allo stesso computer.
    var accettaCavo: Bool {
        guard !viaCavo, !chiusaDallUtente, !cavoEscluso, improntaAttesaCavo != nil else { return false }
        switch stato {
        case .collegato, .riconnessione:
            return true
        case .collegamento:
            // Mentre il computer chiede di confermare il codice, il telefono non è ancora fidato: niente cavo.
            return codiceConferma == nil
        case .errore:
            return !erroreDefinitivo
        case .chiusa:
            return false
        }
    }

    /// Il codice di sicurezza del computer di questa sessione: quello verificato, altrimenti QR code o computer conosciuti.
    private var improntaAttesaCavo: String? {
        if giaCollegato, let impronta = improntaComputer { return impronta }
        return computer.impronta ?? ComputerConosciuti.impronta(di: computer.nome)
    }

    /// 1.6: una sessione dal cavo USB, con la connessione già accettata dall'ascolto su 127.0.0.1.
    convenience init(cavo connessione: NWConnection) {
        self.init(computer: .viaCavo())
        connessioneCavo = connessione
    }

    init(computer: ComputerTrovato) {
        self.computer = computer
        funzioni = FunzioniVolto()
        let codificatore = self.codificatore
        let destinazione = self.destinazione
        let effetti = self.effetti
        let sonda = self.sonda
        cattura.suFotogramma = { campione in
            guard let immagine = CMSampleBufferGetImageBuffer(campione) else { return }
            let istante = CMSampleBufferGetPresentationTimeStamp(campione)
            sonda.considera(immagine, analisi: effetti.analisi)
            // Finché il computer non accoglie l'iPhone l'anteprima va, ma non si codifica nulla.
            // 1.11: intanto si prepara la sessione di codifica, così il primo fotogramma utile parte subito.
            guard destinazione.valore != nil else {
                codificatore.prepara(campione)
                // Le analisi chieste (volti, persona) vanno anche prima del collegamento.
                effetti.osserva(immagine, istante: istante)
                return
            }
            // P02: senza effetti attivi `elabora` ritorna lo stesso buffer, senza copie né attese.
            codificatore.codifica(effetti.elabora(immagine, istante: istante), istante: istante)
        }
        codificatore.suFotogramma = { fotogramma in
            destinazione.valore?.inviaVideo(fotogramma)
        }
        codificatore.suNuovoFormato = { [weak self] larghezza, altezza, fps, codec in
            destinazione.valore?.invia(.formato(FormatoVideo(codec: codec, larghezza: larghezza, altezza: altezza, fps: fps)))
            Task { @MainActor in
                self?.larghezza = larghezza
                self?.altezza = altezza
                self?.fps = fps
                self?.codec = codec
                self?.registro.aggiungi("Video \(larghezza)×\(altezza), \(fps) fps, \(codec.nome)")
            }
        }
        funzioni.collega(a: self)
        funzioni.suCambio = { [weak self] in self?.aggiornaStato() }
    }

    // MARK: - Ciclo di vita

    /// `primaDellaFotocamera`: 1.10, si aspetta prima di accendere la fotocamera (il lettore QR la deve lasciare);
    /// il collegamento parte subito lo stesso.
    /// `origine`: 1.11, da dove si misura il tempo fino al video. `trattieniCiao`: 1.11, sessione preparata durante
    /// il conto alla rovescia: tutto parte, ma il computer accoglie l'iPhone solo dopo `conferma()`.
    func avvia(origine: OrigineAvvio = .tocco, trattieniCiao: Bool = false,
               primaDellaFotocamera: (@MainActor () async -> Void)? = nil) {
        misura = (origine.inizio, origine.testo, true)
        ciaoTrattenuto = trattieniCiao
        chiusaDallUtente = false
        tentativi = 0
        inizioRiconnessione = nil
        erroreDefinitivo = false
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let salvato = Obiettivo(rawValue: UserDefaults.standard.string(forKey: "obiettivo") ?? ""),
           obiettiviDisponibili.contains(salvato) {
            obiettivo = salvato
        }
        collega()
        funzioni.avvia()
        // Sul cavo la rete non conta: niente «Nessuna rete» nel banner.
        if !viaCavo { avviaMonitorRete() }
        // Batteria e temperatura prima di accendere la fotocamera: così parte già con i fotogrammi giusti,
        // senza una seconda configurazione subito dopo.
        misuraStato()
        _ = regolaQualita()
        // La fotocamera si accende subito, mentre il collegamento si apre: al `benvenuto` il video è pronto.
        compitoFotocamera = Task {
            if let primaDellaFotocamera { await primaDellaFotocamera() }
            await avviaFotocamera(segnalaErrori: false)
        }
    }

    /// 1.11: fine del conto alla rovescia: il `ciao` trattenuto parte ora (o appena il collegamento è pronto).
    func conferma() {
        guard ciaoTrattenuto else { return }
        ciaoTrattenuto = false
        guard ciaoInAttesa, let collegamento else { return }
        ciaoInAttesa = false
        inviaCiao(su: collegamento)
    }

    func termina() {
        if !chiusaDallUtente {
            registro.aggiungi(ciaoTrattenuto ? "Ricollegamento a \(computer.nome) annullato" : "Scollegato da \(computer.nome)")
        }
        chiusaDallUtente = true
        ciaoTrattenuto = false
        misura = nil
        esciDallAttesa()
        for osservatore in osservatoriApp { NotificationCenter.default.removeObserver(osservatore) }
        osservatoriApp = []
        compitoStato?.cancel()
        compitoRiprova?.cancel()
        compitoFotocamera?.cancel()
        compitoAttesaCavo?.cancel()
        compitoAttesaCavo = nil
        attendeCavo = false
        connessioneCavo?.cancel()
        connessioneCavo = nil
        candidato?.chiudi()
        candidato = nil
        inUsoCandidato = nil
        chiusuraRinviata = nil
        daCavoAlWiFi = false
        fotocameraPronta = false
        monitorRete?.cancel()
        monitorRete = nil
        destinazione.valore = nil
        collegamento?.chiudi()
        collegamento = nil
        cattura.torcia(false)
        cattura.ferma()
        codificatore.chiudi()
        funzioni.ferma()
        UIApplication.shared.isIdleTimerDisabled = false
        inizioRiconnessione = nil
        stato = .chiusa
    }

    func riprova() {
        if misura == nil { misura = (Date(), "da «Riprova»", false) }
        // «Riprova ora» anche durante l'attesa: si riparte con i tentativi di sempre, poi di nuovo in attesa.
        esciDallAttesa()
        tentativi = 0
        erroreDefinitivo = false
        chiusuraRinviata = nil
        daCavoAlWiFi = false
        // Il vecchio collegamento può essere ancora aperto (per esempio dopo un errore della fotocamera).
        destinazione.valore = nil
        collegamento?.chiudi()
        collegamento = nil
        collega()
        // Dopo un errore la fotocamera è spenta: si riaccende mentre il collegamento si apre.
        if !fotocameraPronta {
            compitoFotocamera = Task { await avviaFotocamera(segnalaErrori: false) }
        }
    }

    /// 1.6: il computer ha riaperto la connessione sul cavo mentre questa sessione l'aspettava.
    /// 1.9: durante una sessione Wi-Fi la connessione dal cavo diventa un candidato (`provaCavo`).
    /// Falso se non serve: chi la riceve la chiude.
    func accogli(_ connessione: NWConnection) -> Bool {
        guard !chiusaDallUtente else { return false }
        guard viaCavo else { return provaCavo(connessione) }
        guard attendeCavo else { return false }
        connessioneCavo?.cancel()
        connessioneCavo = connessione
        riprova()
        return true
    }

    /// 1.9: il cavo collegato durante una sessione Wi-Fi. Stessa sessione sicura (il telefono manda per primo la
    /// `stretta`), su un collegamento a parte: il video continua sul Wi-Fi finché il cavo non è accettato.
    private func provaCavo(_ connessione: NWConnection) -> Bool {
        guard accettaCavo, candidato == nil else { return false }
        registro.aggiungi("Cavo USB collegato: provo a passare al cavo")
        let nuovo = Collegamento(accettata: connessione, identita: identitaTelefono)
        let identita = ObjectIdentifier(nuovo)
        nuovo.suEvento = { [weak self] evento in
            self?.gestisci(evento, da: identita)
        }
        // Finché non prende il posto del Wi-Fi il candidato non manda video: i suoi conti non devono
        // toccare il codificatore.
        let inUso = Protetto(false)
        let codificatore = self.codificatore
        nuovo.suPerdita = {
            guard inUso.valore else { return }
            codificatore.richiediFotogrammaChiave()
        }
        nuovo.suSecondo = { [weak self] scartati, saturo in
            guard inUso.valore else { return }
            let debole = codificatore.adattaAllaRete(scartati: scartati, saturo: saturo)
            Task { @MainActor in self?.registraSecondo(scartati: scartati, debole: debole) }
        }
        candidato = nuovo
        inUsoCandidato = inUso
        improntaCandidato = nil
        tipoCandidato = nil
        nuovo.avvia()
        return true
    }

    // MARK: - Comandi dell'interfaccia

    func scegli(_ nuovo: Obiettivo) {
        guard nuovo != obiettivo else { return }
        obiettivo = nuovo
        torciaAccesa = false
        zoom = 1
        aeafBloccati = false
        puntoFuoco = nil
        Vibrazione.cambioObiettivo()
        UserDefaults.standard.set(nuovo.rawValue, forKey: "obiettivo")
        Task { await avviaFotocamera() }
    }

    /// P03: chiamata alla chiusura delle Impostazioni aperte da «In onda». Risoluzione, fotogrammi, formato,
    /// specchio e stabilizzazione cambiati: la fotocamera si riconfigura una volta sola, come quando si scalda
    /// (il computer riceve un nuovo `formato` e un fotogramma chiave). «Riduci la qualità se si scalda» e
    /// «Risparmio batteria» valgono subito. Se la fotocamera è spenta (attesa, errore) le impostazioni nuove
    /// si leggono alla prossima accensione.
    func applicaImpostazioni() {
        let qualitaCambiata = regolaQualita()
        guard fotocameraPronta, !chiusaDallUtente else { return }
        if qualitaCambiata || ImpostazioniVideo.salvate() != impostazioniApplicate {
            registro.aggiungi("Impostazioni cambiate da «In onda»: riconfiguro la fotocamera")
            Task { await avviaFotocamera() }
        }
    }

    func metteAFuoco(_ punto: CGPoint) {
        cattura.metteAFuoco(suPuntoDellAnteprima: punto)
        aeafBloccati = false
        puntoFuoco = punto
        compitoFuoco?.cancel()
        compitoFuoco = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.puntoFuoco = nil
        }
    }

    /// Tocco lungo: blocca fuoco ed esposizione sul punto; il riquadro resta finché un tocco non sblocca.
    func bloccaFuocoEdEsposizione(_ punto: CGPoint) {
        cattura.bloccaFuocoEdEsposizione(suPuntoDellAnteprima: punto)
        compitoFuoco?.cancel()
        puntoFuoco = punto
        aeafBloccati = true
        Vibrazione.bloccoFuoco()
    }

    /// Doppio tocco sull'anteprima (round 2): frontale ↔ posteriore.
    func cambiaFotocamera() {
        let nuovo: Obiettivo = obiettivo == .frontale ? .principale : .frontale
        guard obiettiviDisponibili.contains(nuovo) else { return }
        scegli(nuovo)
    }

    func impostaZoom(_ fattore: CGFloat, scorrevole: Bool = false) {
        zoom = min(max(fattore, 1), 10)
        cattura.zoom(zoom, scorrevole: scorrevole)
    }

    func cambiaTorcia() {
        torciaAccesa.toggle()
        cattura.torcia(torciaAccesa)
    }

    var torciaDisponibile: Bool {
        obiettivo != .frontale
    }

    // MARK: - Collegamento

    private func collega() {
        compitoRiprova?.cancel()
        compitoRiprova = nil
        compitoAttesaCavo?.cancel()
        compitoAttesaCavo = nil
        let nuovo: Collegamento
        if viaCavo {
            // Sul cavo è il computer ad aprire la connessione: senza, la si aspetta.
            guard let accettata = connessioneCavo else {
                aspettaCavo()
                return
            }
            connessioneCavo = nil
            attendeCavo = false
            stato = tentativi == 0 && !giaCollegato ? .collegamento : .riconnessione(tentativo: 1)
            registro.aggiungi("Collegamento dal cavo USB…")
            // Il nome del computer non si sa ancora: il codice di sicurezza si verifica al `benvenuto`.
            nuovo = Collegamento(accettata: accettata, identita: identitaTelefono)
        } else {
            stato = tentativi == 0 ? .collegamento : .riconnessione(tentativo: tentativi)
            if !inAttesaDelComputer {
                registro.aggiungi(tentativi == 0
                                  ? "Collegamento a \(computer.nome)…"
                                  : "Nuovo tentativo \(tentativi)/\(Self.tentativiMassimi) con \(computer.nome)")
            }
            // Protocollo 2: l'impronta attesa viene dal QR code, altrimenti dai computer conosciuti.
            nuovo = Collegamento(verso: computer.endpoint, identita: identitaTelefono,
                                 improntaAttesa: computer.impronta ?? ComputerConosciuti.impronta(di: computer.nome),
                                 gettone: computer.gettone, diretto: computer.diretto,
                                 altri: computer.altriIndirizzi)
        }
        codiceConferma = nil
        improntaComputer = nil
        ciaoInAttesa = false
        let identita = ObjectIdentifier(nuovo)
        nuovo.suEvento = { [weak self] evento in
            self?.gestisci(evento, da: identita)
        }
        nuovo.suPrimoFotogramma = { [weak self] in
            Task { @MainActor in self?.primoFotogrammaSpedito(da: identita) }
        }
        let codificatore = self.codificatore
        nuovo.suPerdita = {
            codificatore.richiediFotogrammaChiave()
        }
        // Una volta al secondo: il bitrate segue la rete, l'interfaccia riceve solo il riassunto.
        nuovo.suSecondo = { [weak self] scartati, saturo in
            let debole = codificatore.adattaAllaRete(scartati: scartati, saturo: saturo)
            Task { @MainActor in self?.registraSecondo(scartati: scartati, debole: debole) }
        }
        codificatore.azzeraRete()
        perditeUltimiSecondi = []
        perditeRecenti = 0
        reteDebole = false
        collegamento = nuovo
        nuovo.avvia()
    }

    private func gestisci(_ evento: Collegamento.Evento, da identita: ObjectIdentifier) {
        if let candidato, ObjectIdentifier(candidato) == identita {
            gestisciCandidato(evento, candidato: candidato)
            return
        }
        guard let collegamento, ObjectIdentifier(collegamento) == identita else { return }
        switch evento {
        case .pronto(let impronta):
            // Stretta di mano riuscita e prova già spedita: il `ciao` parte cifrato.
            improntaComputer = impronta
            registro.aggiungi("Collegamento sicuro riuscito, codice di sicurezza \(String(impronta.prefix(8)))")
            // 1.12: dopo l'attesa la fotocamera è spenta: si riaccende ora che il computer c'è, insieme al `ciao`.
            accendiFotocameraInAnticipo()
            // 1.11: durante il conto alla rovescia il `ciao` aspetta: il computer accoglie l'iPhone solo alla fine.
            if ciaoTrattenuto {
                ciaoInAttesa = true
                registro.aggiungi("Pronto: il video parte alla fine del conto alla rovescia")
            } else {
                inviaCiao(su: collegamento)
            }

        case .messaggio(.approvazione(let approvazione)):
            // Prima volta con questo computer: l'utente conferma sul computer, con lo stesso codice.
            codiceConferma = approvazione.codice
            registro.aggiungi("Il computer chiede di confermare il codice")
            Vibrazione.richiestaConferma()

        case .messaggio(.benvenuto(let benvenuto)):
            if viaCavo {
                // 1.6: il nome arriva ora. Un computer conosciuto deve avere lo stesso codice di sicurezza di sempre.
                let nome = benvenuto.nome.isEmpty ? computer.nome : benvenuto.nome
                if let salvata = ComputerConosciuti.impronta(di: nome), let impronta = improntaComputer, salvata != impronta {
                    self.collegamento = nil
                    destinazione.valore = nil
                    collegamento.chiudi()
                    codiceConferma = nil
                    // Il `chiuso` di questo collegamento non arriva più qui: si pulisce come lì.
                    latenzaMs = nil
                    inOnda = nil
                    tipoCollegamento = nil
                    computer = .viaCavo(nome: nome, piattaforma: benvenuto.piattaforma)
                    if UserDefaults.standard.string(forKey: Ricollegamento.chiaveUltimoComputer) == nome {
                        UserDefaults.standard.removeObject(forKey: Ricollegamento.chiaveUltimoComputer)
                    }
                    fermaConErrore(titolo: "Computer da collegare di nuovo",
                                   descrizione: "\(nome) non è più lo stesso computer per l'iPhone (per esempio dopo averlo reinstallato). Collegalo di nuovo con il QR code, oppure toglilo dai computer conosciuti nella sezione App e ricollega il cavo.",
                                   definitivo: true, domanda: "identita")
                    return
                }
                computer = .viaCavo(nome: nome, piattaforma: benvenuto.piattaforma)
            } else if !computer.annunciato, computer.impronta == nil, !benvenuto.nome.isEmpty,
                      benvenuto.nome != computer.nome {
                // Indirizzo scritto a mano: finora il nome era l'indirizzo. Con il nome vero funzionano i computer
                // conosciuti, il ricollegamento all'avvio e l'attesa (che cerca il computer per nome nella ricerca);
                // prima «Apri WebcamLR su «192.168.1.20»» restava per sempre nella lista. Se quel nome ha già un
                // altro codice di sicurezza, resta l'indirizzo: un computer conosciuto non si sovrascrive mai.
                let salvata = ComputerConosciuti.impronta(di: benvenuto.nome)
                if salvata == nil || salvata == improntaComputer {
                    computer = computer.conNome(benvenuto.nome, piattaforma: benvenuto.piattaforma)
                }
            }
            codiceConferma = nil
            giaCollegato = true
            daCavoAlWiFi = false
            // Da ora questo computer è conosciuto: la prossima volta la sua impronta deve essere la stessa.
            if let impronta = improntaComputer {
                ComputerConosciuti.salva(impronta, per: computer.nome)
            }
            tentativi = 0
            esciDallAttesa()
            UIApplication.shared.isIdleTimerDisabled = true
            stato = .collegato
            registro.aggiungi("Collegato a \(computer.nome)")
            inizioRiconnessione = nil
            Vibrazione.collegato()
            // Al prossimo avvio ci si ricollega da soli a questo computer, se Bonjour lo trova.
            UserDefaults.standard.set(computer.nome, forKey: Ricollegamento.chiaveUltimoComputer)
            // 1.11: la sessione di codifica si tiene: prima di aprire la destinazione si chiedono `formato` e
            // fotogramma chiave, così il primo fotogramma per questo collegamento non arriva prima del `formato`.
            codificatore.ricomincia()
            destinazione.valore = collegamento
            avviaStatoPeriodico()
            Task { await preparaVideo() }

        case .messaggio(.latenza(let latenza)):
            latenzaMs = latenza.ms
            ultimaLatenzaMs = latenza.ms

        case .messaggio(.comando(let comando)):
            applica(comando)

        case .messaggio(.inOnda(let nuovo)):
            inOnda = nuovo.attivo ? nuovo : nil

        case .messaggio:
            break

        case .tipo(let tipo):
            tipoCollegamento = tipo
            if let tipo { registro.aggiungi("Collegamento via \(tipo.testo)") }

        case .indirizzo(let posizione):
            // 1.10: l'indirizzo del QR code che ha risposto per primo diventa il primo da provare.
            computer = computer.conPrimo(posizione)
            registro.aggiungi("Risponde l'indirizzo \(Self.testo(computer.endpoint))")

        case .chiuso(let errore, let motivo):
            let inAttesaDiConferma = codiceConferma != nil
            codiceConferma = nil
            self.collegamento = nil
            destinazione.valore = nil
            compitoStato?.cancel()
            // 1.9: chiuso mentre si passa al cavo (di solito l'`arrivederci` del computer, che ha già accettato
            // il cavo): niente errore né cambi di stato finché non si sa com'è andato il cavo.
            // Solo dopo il `ciao` sul cavo (impronta verificata): il computer lascia il Wi-Fi solo da lì. Prima è
            // una caduta del Wi-Fi qualsiasi e si tratta come sempre, senza restare «Collegato» senza video.
            if candidato != nil && improntaCandidato != nil && !chiusaDallUtente {
                chiusuraRinviata = (errore, motivo, inAttesaDiConferma)
                registro.aggiungi("Wi-Fi chiuso durante il passaggio al cavo USB (\(motivo.perRegistro))")
                return
            }
            latenzaMs = nil
            inOnda = nil
            tipoCollegamento = nil
            guard !chiusaDallUtente else { return }
            gestisciChiusura(errore: errore, motivo: motivo, inAttesaDiConferma: inAttesaDiConferma)
        }
    }

    /// 1.11: il primo fotogramma è partito verso il computer: quanto ci è voluto, nel registro e in modalità avanzata.
    private func primoFotogrammaSpedito(da identita: ObjectIdentifier) {
        guard let collegamento, ObjectIdentifier(collegamento) == identita, let attuale = misura else { return }
        misura = nil
        let adesso = Date()
        let secondi = adesso.timeIntervalSince(attuale.inizio)
        if attuale.avvio { tempoAvvio = secondi }
        var riga = "Primo fotogramma spedito: \(MisuraAvvio.testo(secondi)) \(attuale.testo)"
        if !MisuraAvvio.primoVideoMisurato {
            MisuraAvvio.primoVideoMisurato = true
            if attuale.inizio != MisuraAvvio.aperturaApp {
                riga += ", \(MisuraAvvio.testo(adesso.timeIntervalSince(MisuraAvvio.aperturaApp))) dall'apertura dell'app"
            }
        }
        registro.aggiungi(riga)
    }

    /// Il collegamento attuale si è chiuso: si riprova, si aspetta il cavo o ci si ferma dicendo perché.
    private func gestisciChiusura(errore: String?, motivo motivoRicevuto: Collegamento.MotivoChiusura,
                                  inAttesaDiConferma: Bool) {
        var motivo = motivoRicevuto
        // 1.9: cavo appena staccato. Se il computer non se n'è ancora accorto, rifiuta il Wi-Fi perché il telefono
        // «è sul cavo»: non è una chiusura voluta, si riprova.
        if daCavoAlWiFi && motivo == .dalComputer { motivo = .rete }
        registro.aggiungi("Collegamento chiuso: \(motivo.perRegistro)" + (errore.map { " (\($0))" } ?? ""))
        // Una vibrazione quando si perde il computer, non a ogni tentativo andato a vuoto.
        if (motivo != .rete || inizioRiconnessione == nil) && !inAttesaDelComputer { Vibrazione.scollegato() }
        let nome = computer.nome
        // Chiuso mentre si aspettava la conferma: il computer ha detto no, o nessuno ha risposto.
        // Riprovare da soli farebbe solo ricomparire la domanda.
        if inAttesaDiConferma && (motivo == .rete || motivo == .dalComputer) {
            fermaConErrore(titolo: "Collegamento non confermato",
                           descrizione: "Il collegamento non è stato consentito su \(nome). Tocca «Riprova» e conferma sul computer.",
                           domanda: "codice")
            return
        }
        switch motivo {
        case .rete:
            if viaCavo {
                // 1.6: sul cavo non si richiama il computer: si aspetta che riapra la connessione.
                guard let wifi = computerWiFi else {
                    aspettaCavo()
                    return
                }
                // 1.9: il computer era stato raggiunto in Wi-Fi: lo si cerca lì, con i tentativi di sempre,
                // mentre l'ascolto sul cavo resta acceso (se il cavo torna si ripassa al cavo).
                provaWiFiDopoCavo(wifi)
            }
            // Senza rete non si consumano tentativi: si riparte appena torna (`reteCambiata`).
            if !reteDisponibile {
                if inizioRiconnessione == nil { inizioRiconnessione = Date() }
                stato = .riconnessione(tentativo: max(tentativi, 1))
                // 1.12: in attesa la fotocamera resta spenta anche senza rete (si era accesa al collegamento sicuro).
                if inAttesaDelComputer { spegniFotocameraInAttesa() }
                return
            }
            // 1.12: in attesa ogni tentativo andato a vuoto programma il prossimo, sempre più distante.
            // Il computer c'era (è ricomparso) ma non risponde ancora: da qui si riprova anche a tempo.
            if inAttesaDelComputer {
                soloAlRitorno = false
                stato = .riconnessione(tentativo: max(tentativi, 1))
                spegniFotocameraInAttesa()
                programmaTentativoInAttesa()
                return
            }
        case .dalComputer:
            // 1.12: un computer fidato che chiude (WebcamLR chiuso sul computer, o «Scollega» lì): niente errore,
            // si aspetta che ricompaia nella ricerca e ci si ricollega da soli.
            if attesaPossibile {
                entraInAttesa(soloAlRitorno: true)
                return
            }
            fermaConErrore(titolo: giaCollegato ? "Collegamento interrotto" : "Non riesco a collegarmi a \(nome)",
                           descrizione: "\(nome) ha chiuso il collegamento. Tocca «Riprova» per collegarti di nuovo.")
            return
        case .computerVecchio:
            fermaConErrore(diagnosi: .computerVecchio(nome: nome))
            return
        case .permessoNegato:
            StatoRete.condiviso.permessoNegato = true
            fermaConErrore(diagnosi: .permessoReteLocale)
            return
        case .identitaCambiata:
            // Niente ricollegamento automatico a questo computer finché non lo si riabbina.
            if UserDefaults.standard.string(forKey: Ricollegamento.chiaveUltimoComputer) == nome {
                UserDefaults.standard.removeObject(forKey: Ricollegamento.chiaveUltimoComputer)
            }
            fermaConErrore(titolo: "Computer da collegare di nuovo",
                           descrizione: "\(nome) non è più lo stesso computer per l'iPhone (per esempio dopo averlo reinstallato). Tocca «Torna ai computer» e collegalo di nuovo con «Inquadra il QR code del computer».",
                           definitivo: true, domanda: "identita")
            return
        case .identitaNonValida:
            fermaConErrore(titolo: "Collegamento non sicuro",
                           descrizione: "\(nome) non ha superato il controllo di sicurezza. Tocca «Riprova», oppure torna ai computer e collegati con il QR code.",
                           domanda: "identita")
            return
        }
        // 1.9: dopo il cavo staccato si continua a provare il Wi-Fi almeno quanto si aspetterebbe il cavo.
        let secondiAttesaCavo = Double(Self.attesaCavo.components.seconds)
        let attesaCavoInCorso = daCavoAlWiFi
            && Date().timeIntervalSince(inizioRiconnessione ?? Date()) < secondiAttesaCavo
        if tentativi < Self.tentativiMassimi || attesaCavoInCorso {
            if inizioRiconnessione == nil { inizioRiconnessione = Date() }
            // 1.11: quanto ci vuole a riavere il video, nel registro (prima del primo video resta la misura dell'avvio).
            if misura == nil && giaCollegato { misura = (inizioRiconnessione ?? Date(), "dalla perdita del collegamento", false) }
            tentativi = min(tentativi + 1, Self.tentativiMassimi)
            stato = .riconnessione(tentativo: tentativi)
            // Il primo tentativo quasi subito (spesso è solo un attimo di Wi-Fi), poi ogni 2 secondi.
            let attesa: Duration = tentativi == 1 ? .milliseconds(500) : .seconds(2)
            compitoRiprova = Task { [weak self] in
                try? await Task.sleep(for: attesa)
                guard !Task.isCancelled, let self, !self.chiusaDallUtente, self.collegamento == nil else { return }
                self.collega()
            }
        } else if daCavoAlWiFi {
            fermaConErrore(titolo: "Cavo scollegato",
                           descrizione: "Ricollega il cavo: il collegamento riparte da solo. Oppure controlla che iPhone e computer siano sulla stessa rete Wi-Fi e tocca «Riprova».",
                           domanda: "cavo")
        } else if attesaPossibile && !StatoRete.condiviso.permessoNegato {
            // 1.12: un computer fidato che non risponde (spento, WebcamLR chiuso, altra rete): si aspetta con calma.
            entraInAttesa(soloAlRitorno: false)
        } else if let causa = Diagnosi.collegamento(giaCollegato: giaCollegato, annunciato: computer.annunciato,
                                                     piattaforma: computer.piattaforma, rete: StatoRete.condiviso) {
            // 1.3: invece di «non risponde», la causa probabile e cosa fare.
            fermaConErrore(diagnosi: causa)
        } else {
            fermaConErrore(titolo: giaCollegato ? "Collegamento interrotto" : "Non riesco a collegarmi a \(nome)",
                           descrizione: errore ?? "Il computer non risponde: controlla che WebcamLR sia aperto sul computer e che siate sulla stessa rete Wi-Fi, poi tocca «Riprova».",
                           domanda: giaCollegato ? nil : "non-trova")
        }
    }

    /// Ci si ferma: niente più tentativi da soli, il pannello dice cosa fare.
    /// `attendiCavo`: sul cavo, se il computer riapre la connessione si riparte da soli. Solo quando il cavo
    /// è stato scollegato: dopo un rifiuto o una chiusura voluta, il computer (che ritenta ogni 2 secondi)
    /// non deve ricollegarsi senza che l'utente lo chieda con «Riprova».
    private func fermaConErrore(titolo: String, descrizione: String, definitivo: Bool = false, domanda: String? = nil,
                                diagnosi: Diagnosi? = nil, attendiCavo: Bool = false) {
        compitoRiprova?.cancel()
        cattura.ferma()
        fotocameraPronta = false
        inizioRiconnessione = nil
        // Si misura di nuovo da «Riprova».
        misura = nil
        esciDallAttesa()
        titoloErrore = titolo
        erroreDefinitivo = definitivo
        self.diagnosi = diagnosi
        domandaErrore = domanda ?? diagnosi?.domanda
        registro.aggiungi("Fermo: \(titolo)")
        compitoAttesaCavo?.cancel()
        compitoAttesaCavo = nil
        attendeCavo = viaCavo && attendiCavo && !definitivo
        daCavoAlWiFi = false
        // Lo schermo oscurato coprirebbe il pannello con «Riprova»: si riaccende.
        oscurato = false
        stato = .errore(descrizione)
    }

    /// 1.6: sessione via cavo senza collegamento. Il computer riapre la connessione quando il cavo torna
    /// (o WebcamLR si riapre sul computer); dopo un po' senza, ci si ferma e lo si dice.
    private func aspettaCavo() {
        compitoAttesaCavo?.cancel()
        if giaCollegato && inizioRiconnessione == nil { inizioRiconnessione = Date() }
        stato = giaCollegato ? .riconnessione(tentativo: 1) : .collegamento
        if !attendeCavo {
            attendeCavo = true
            registro.aggiungi("Aspetto il computer sul cavo USB")
        }
        let attesa = SessioneTelefono.attesaCavo
        compitoAttesaCavo = Task { [weak self] in
            try? await Task.sleep(for: attesa)
            guard !Task.isCancelled, let self, self.collegamento == nil, !self.chiusaDallUtente else { return }
            self.fermaConErrore(titolo: self.giaCollegato ? "Cavo scollegato" : "Collegamento via cavo non riuscito",
                                descrizione: "Controlla il cavo e che WebcamLR sia aperto sul computer: appena il computer risponde, il collegamento riparte da solo.",
                                domanda: "cavo", attendiCavo: true)
        }
    }

    /// 1.9: il cavo si è staccato in una sessione nata in Wi-Fi. La sessione torna al computer Wi-Fi e usa i
    /// tentativi di sempre; intanto l'ascolto sul cavo resta acceso (`accettaCavo`): se il cavo torna, si ripassa lì.
    private func provaWiFiDopoCavo(_ wifi: ComputerTrovato) {
        registro.aggiungi("Cavo staccato: provo il Wi-Fi")
        compitoAttesaCavo?.cancel()
        compitoAttesaCavo = nil
        attendeCavo = false
        connessioneCavo?.cancel()
        connessioneCavo = nil
        computer = wifi
        daCavoAlWiFi = true
        tentativi = 0
        avviaMonitorRete()
    }

    /// «192.168.1.20:52740» per il registro.
    private static func testo(_ endpoint: NWEndpoint) -> String {
        if case let .hostPort(host, porta) = endpoint {
            return "\(host):\(porta.rawValue)"
        }
        return "\(endpoint)"
    }

    private func inviaCiao(su destinatario: Collegamento) {
        let versione = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        destinatario.invia(.ciao(Ciao(versione: Sicurezza.versioneSicura, nome: UIDevice.current.name,
                                      piattaforma: .iphone, versioneApp: versione)))
    }

    // MARK: - Passaggio al cavo (1.9)

    /// Gli eventi del candidato dal cavo. Finché non è accettato non toccano lo stato della sessione.
    private func gestisciCandidato(_ evento: Collegamento.Evento, candidato: Collegamento) {
        switch evento {
        case .pronto(let impronta):
            // Solo lo stesso computer della sessione Wi-Fi: un altro computer non riceve nemmeno il `ciao`.
            guard let attesa = improntaAttesaCavo, attesa == impronta else {
                scartaCandidato("sul cavo c'è un altro computer", escludi: true)
                return
            }
            improntaCandidato = impronta
            inviaCiao(su: candidato)

        case .messaggio(.benvenuto(let benvenuto)):
            passaAlCavo(benvenuto)

        case .messaggio(.approvazione):
            // Lo stesso computer, già collegato in Wi-Fi, conosce questo iPhone: una domanda vuol dire altro.
            scartaCandidato("il computer chiede una conferma", escludi: true)

        // Lo stesso computer (impronta verificata) può mandare i comandi prima del `benvenuto` (Windows li manda
        // dal thread dell'interfaccia): si applicano come sul Wi-Fi, invece di perderli.
        case .messaggio(.comando(let comando)) where improntaCandidato != nil:
            applica(comando)

        case .messaggio(.inOnda(let nuovo)) where improntaCandidato != nil:
            inOnda = nuovo.attivo ? nuovo : nil

        case .messaggio:
            break

        case .tipo(let tipo):
            tipoCandidato = tipo

        case .indirizzo:
            break

        case .chiuso(_, let motivo):
            let dopoStretta = improntaCandidato != nil
            self.candidato = nil
            inUsoCandidato = nil
            improntaCandidato = nil
            tipoCandidato = nil
            registro.aggiungi("Passaggio al cavo USB non riuscito (\(motivo.perRegistro)): resto sul Wi-Fi")
            candidatoNonRiuscito(dopoStretta: dopoStretta)
        }
    }

    /// Il candidato non serve: si chiude in silenzio e il Wi-Fi continua.
    private func scartaCandidato(_ perche: String, escludi: Bool) {
        guard let scartato = candidato else { return }
        // Tolto prima di chiuderlo: il suo `chiuso` non arriva più qui.
        candidato = nil
        inUsoCandidato = nil
        improntaCandidato = nil
        tipoCandidato = nil
        scartato.chiudi()
        registro.aggiungi("Cavo USB non usato: \(perche)")
        // Il computer ritenta ogni 2 secondi: con un altro computer sul cavo l'ascolto si spegne per questa sessione.
        if escludi { cavoEscluso = true }
        candidatoNonRiuscito(dopoStretta: false)
    }

    /// Dopo un candidato andato male: troppi tentativi spengono il cavo per questa sessione; se intanto il Wi-Fi
    /// si era chiuso, ora lo si tratta come sempre.
    private func candidatoNonRiuscito(dopoStretta: Bool) {
        candidatiFalliti += 1
        if candidatiFalliti >= 3 && !cavoEscluso {
            cavoEscluso = true
            registro.aggiungi("Cavo USB non riuscito più volte: resto sul Wi-Fi")
        }
        guard let rinviata = chiusuraRinviata else { return }
        chiusuraRinviata = nil
        latenzaMs = nil
        inOnda = nil
        tipoCollegamento = nil
        guard !chiusaDallUtente else { return }
        // Il computer aveva lasciato il Wi-Fi per il cavo, che poi non è riuscito: non è una chiusura voluta.
        let motivo: Collegamento.MotivoChiusura = rinviata.motivo == .dalComputer && dopoStretta ? .rete : rinviata.motivo
        gestisciChiusura(errore: rinviata.errore, motivo: motivo, inAttesaDiConferma: rinviata.inAttesaDiConferma)
    }

    /// Il computer ha accettato il cavo: il video passa al cavo senza fermare la fotocamera, il Wi-Fi si chiude
    /// in silenzio (i suoi eventi non arrivano più qui).
    private func passaAlCavo(_ benvenuto: Benvenuto) {
        guard let nuovo = candidato, let impronta = improntaCandidato else { return }
        let inUso = inUsoCandidato
        let tipoNuovo = tipoCandidato ?? .cavoUSB
        candidato = nil
        inUsoCandidato = nil
        improntaCandidato = nil
        tipoCandidato = nil
        chiusuraRinviata = nil
        candidatiFalliti = 0
        // Sul cavo non si misura: il video non si è mai fermato.
        misura = nil
        esciDallAttesa()
        let vecchio = collegamento
        // Con il Wi-Fi già chiuso dal computer (chiusura rinviata) lo stato è rimasto «collegato»: niente vibrazione.
        let eraCollegato = stato == .collegato
        let nome = benvenuto.nome.isEmpty ? computer.nome : benvenuto.nome
        if !computer.cavo { computerWiFi = computer }
        registro.aggiungi("Passo al cavo USB")

        compitoRiprova?.cancel()
        compitoRiprova = nil
        collegamento = nuovo
        inUso?.valore = true
        computer = .viaCavo(nome: nome, piattaforma: benvenuto.piattaforma)
        improntaComputer = impronta
        ComputerConosciuti.salva(impronta, per: nome)
        codiceConferma = nil
        daCavoAlWiFi = false
        giaCollegato = true
        tentativi = 0
        erroreDefinitivo = false
        diagnosi = nil
        domandaErrore = nil
        inizioRiconnessione = nil
        tipoCollegamento = tipoNuovo
        registro.aggiungi("Collegamento via \(tipoNuovo.testo)")
        codificatore.azzeraRete()
        perditeUltimiSecondi = []
        perditeRecenti = 0
        reteDebole = false
        stato = .collegato
        registro.aggiungi("Collegato a \(nome)")
        if !eraCollegato { Vibrazione.collegato() }
        // Da qui il codificatore scrive sul cavo. `preparaVideo` rifà `formato` e fotogramma chiave per la nuova
        // sessione del computer, senza riavviare la fotocamera (che si accende solo se era spenta per un errore).
        codificatore.ricomincia()
        destinazione.valore = nuovo
        vecchio?.chiudi()
        avviaStatoPeriodico()
        Task { await preparaVideo() }
    }

    /// Con una diagnosi titolo e spiegazione sono i suoi.
    private func fermaConErrore(diagnosi: Diagnosi) {
        fermaConErrore(titolo: diagnosi.titolo, descrizione: diagnosi.spiegazione, diagnosi: diagnosi)
    }

    private func registraSecondo(scartati: Int, debole: Bool) {
        perditeUltimiSecondi.append(scartati)
        if perditeUltimiSecondi.count > 5 { perditeUltimiSecondi.removeFirst() }
        let somma = perditeUltimiSecondi.reduce(0, +)
        // Si assegna solo se cambia, così l'interfaccia non si ridisegna ogni secondo.
        if somma != perditeRecenti { perditeRecenti = somma }
        if debole != reteDebole { reteDebole = debole }
    }

    /// Al `benvenuto`: se la fotocamera è già accesa basta un nuovo `formato` con un fotogramma chiave
    /// per questo collegamento, senza riconfigurarla (il video arriva prima); altrimenti si accende ora.
    private func preparaVideo() async {
        await compitoFotocamera?.value
        guard !chiusaDallUtente, collegamento != nil, stato == .collegato else { return }
        if fotocameraPronta {
            // `formato` e fotogramma chiave sono già chiesti (`codificatore.ricomincia()` prima della destinazione).
            inviaCapacita()
        } else {
            await avviaFotocamera()
        }
    }

    /// Avvia o riconfigura la fotocamera con le impostazioni salvate.
    /// `segnalaErrori` falso: accensione anticipata, un errore lo dirà il tentativo al `benvenuto`.
    private func avviaFotocamera(segnalaErrori: Bool = true) async {
        guard !chiusaDallUtente else { return }
        var (larghezzaRichiesta, altezzaRichiesta) = Self.dimensioniSalvate()
        var fpsRichiesti = UserDefaults.standard.object(forKey: "fps") as? Int ?? 30
        if qualitaRidotta {
            (larghezzaRichiesta, altezzaRichiesta) = (min(larghezzaRichiesta, 1280), min(altezzaRichiesta, 720))
            fpsRichiesti = min(fpsRichiesti, 24)
        }
        if risparmioBatteria {
            fpsRichiesti = min(fpsRichiesti, 24)
        }
        let impostazioni = ImpostazioniVideo.salvate()
        // Ricrea la sessione di codifica: il computer riceve un nuovo `formato` e un fotogramma chiave.
        let codec = Codec(rawValue: UserDefaults.standard.string(forKey: "codec") ?? "") ?? .h264
        codificatore.imposta(fps: fpsRichiesti, codec: codec)
        do {
            try await cattura.configura(obiettivo: obiettivo, larghezza: larghezzaRichiesta,
                                        altezza: altezzaRichiesta, fps: fpsRichiesti,
                                        specchia: UserDefaults.standard.bool(forKey: "specchia"),
                                        stabilizzazione: UserDefaults.standard.bool(forKey: "stabilizzazione"))
            // Chiusa mentre la fotocamera si accendeva: si spegne, altrimenti resterebbe accesa.
            // 1.12: lo stesso se intanto si è passati ad aspettare il computer, senza collegamento aperto.
            if chiusaDallUtente || (inAttesaDelComputer && collegamento == nil) {
                cattura.ferma()
                return
            }
            fotocameraPronta = true
            impostazioniApplicate = impostazioni
            // La riconfigurazione riparte con messa a fuoco ed esposizione automatiche: niente più «AE/AF bloccati».
            compitoFuoco?.cancel()
            aeafBloccati = false
            puntoFuoco = nil
            if torciaAccesa { cattura.torcia(true) }
            // Il cambio di formato (per esempio quando si scalda) riporta lo zoom del dispositivo a 1.
            if zoom != 1 { cattura.zoom(zoom) }
            if esposizione != 0 { cattura.esposizione(Float(esposizione)) }
            if bianco != 0 { cattura.bianco(kelvin: bianco) }
            if iso != 0 || tempo != 0 { cattura.esposizioneManuale(iso: Float(iso), tempo: tempo) }
            inviaCapacita()
            // Il computer vede subito il nuovo obiettivo, senza aspettare i 5 secondi dello stato.
            aggiornaStato()
        } catch {
            fotocameraPronta = false
            guard segnalaErrori, !chiusaDallUtente else { return }
            titoloErrore = "Fotocamera non disponibile"
            erroreDefinitivo = false
            domandaErrore = nil
            diagnosi = nil
            oscurato = false
            // I nostri errori dicono già cosa fare; quelli di sistema (fotocamera occupata) no.
            stato = .errore((error as? ErroreCattura)?.errorDescription
                            ?? "Un'altra app sta usando la fotocamera: chiudila e tocca «Riprova».")
        }
    }

    /// Comandi della fotocamera dal computer (round 4): solo i campi presenti.
    func applica(_ comando: Comando) {
        if let nome = comando.obiettivo, let nuovo = Obiettivo(rawValue: nome), obiettiviDisponibili.contains(nuovo) {
            scegli(nuovo)
        }
        if let fattore = comando.zoom {
            impostaZoom(CGFloat(fattore), scorrevole: true)
        }
        if let accesa = comando.torcia, accesa != torciaAccesa, torciaDisponibile {
            cambiaTorcia()
        }
        if let stop = comando.esposizione {
            esposizione = min(max(stop, -2), 2)
            cattura.esposizione(Float(esposizione))
        }
        if let kelvin = comando.bianco {
            bianco = kelvin == 0 ? 0 : min(max(kelvin, 2500), 7500)
            cattura.bianco(kelvin: bianco)
        }
        if comando.fuoco == "continuo" {
            cattura.fuocoContinuo()
            aeafBloccati = false
            puntoFuoco = nil
        }
        if comando.iso != nil || comando.tempo != nil {
            iso = max(comando.iso ?? iso, 0)
            tempo = max(comando.tempo ?? tempo, 0)
            cattura.esposizioneManuale(iso: Float(iso), tempo: tempo)
        }
        funzioni.applica(comando)
    }

    /// Dice al computer cosa può comandare con l'obiettivo attuale.
    private func inviaCapacita() {
        let limiti = cattura.limitiISO
        var capacita = Capacita(obiettivi: obiettiviDisponibili.map(\.rawValue),
                                zoomMassimo: cattura.zoomMassimo,
                                torcia: torciaDisponibile,
                                isoMinimo: limiti?.minimo, isoMassimo: limiti?.massimo)
        funzioni.completa(&capacita)
        collegamento?.invia(.capacita(capacita))
    }

    private static func dimensioniSalvate() -> (Int32, Int32) {
        switch UserDefaults.standard.string(forKey: "risoluzione") ?? "1080p" {
        case "720p": (1280, 720)
        case "4K": (3840, 2160)
        default: (1920, 1080)
        }
    }

    /// Batteria e temperatura al computer ogni 5 secondi.
    private func avviaStatoPeriodico() {
        compitoStato?.cancel()
        compitoStato = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.aggiornaStato()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func aggiornaStato() {
        misuraStato()
        var statoTelefono = StatoTelefono(batteria: batteria, inCarica: inCarica,
                                          temperatura: temperatura, obiettivo: obiettivo.rawValue)
        funzioni.completa(&statoTelefono)
        collegamento?.invia(.stato(statoTelefono))
        if regolaQualita() { Task { await avviaFotocamera() } }
    }

    /// Batteria, carica e temperatura. Si assegna solo ciò che cambia: l'interfaccia non si ridisegna ogni 5 secondi.
    private func misuraStato() {
        let dispositivo = UIDevice.current
        let nuovaBatteria = dispositivo.batteryLevel < 0 ? -1 : Int((dispositivo.batteryLevel * 100).rounded())
        let nuovaTemperatura: Temperatura = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .normale
        case .fair: .calda
        case .serious: .moltoCalda
        case .critical: .critica
        @unknown default: .normale
        }
        let nuovaCarica = dispositivo.batteryState == .charging || dispositivo.batteryState == .full
        if nuovaBatteria != batteria { batteria = nuovaBatteria }
        if nuovaTemperatura != temperatura { temperatura = nuovaTemperatura }
        if nuovaCarica != inCarica { inCarica = nuovaCarica }
    }

    // MARK: - Rete

    private func avviaMonitorRete() {
        guard monitorRete == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] percorso in
            let disponibile = percorso.status == .satisfied
            // 1.12: interfacce e router: cambiano passando a un altro Wi-Fi o all'Hotspot personale.
            let interfacce = percorso.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            let router = percorso.gateways.map { "\($0)" }.sorted().joined(separator: ",")
            let firma = interfacce + "|" + router
            Task { @MainActor in self?.reteCambiata(disponibile: disponibile, firma: firma) }
        }
        monitor.start(queue: .main)
        monitorRete = monitor
    }

    /// La rete è tornata (o è cambiata, 1.12) mentre si cercava il computer: si riprova subito, da capo con i tentativi.
    private func reteCambiata(disponibile: Bool, firma: String) {
        let tornata = disponibile && !reteDisponibile
        let cambiata = disponibile && firmaRete != nil && firmaRete != firma
        firmaRete = firma
        if disponibile != reteDisponibile {
            reteDisponibile = disponibile
            registro.aggiungi(disponibile ? "Rete tornata" : "Rete persa")
        }
        guard tornata || cambiata, !chiusaDallUtente, collegamento == nil else { return }
        if inAttesaDelComputer {
            // Nuova rete: la ricerca riparte da capo, e i tentativi tornano frequenti.
            tentativiInAttesa = 0
            ultimoTentativoInAttesa = nil
            ricercaAttesa?.cancel()
            ricercaAttesa = nil
            computerVisibile = nil
            avviaRicercaAttesa()
            if !soloAlRitorno { provaInAttesa("rete cambiata") }
            return
        }
        guard case .riconnessione = stato else { return }
        tentativi = 1
        collega()
    }

    // MARK: - In attesa del computer (1.12)

    /// Si può aspettare con calma solo un computer fidato, raggiunto in Wi-Fi e già collegato in questa sessione.
    /// Il cavo ha la sua attesa (`aspettaCavo`).
    private var attesaPossibile: Bool {
        !viaCavo && !daCavoAlWiFi && giaCollegato && ComputerConosciuti.impronta(di: computer.nome) != nil
    }

    private func entraInAttesa(soloAlRitorno: Bool) {
        compitoRiprova?.cancel()
        compitoRiprova = nil
        let eraInAttesa = inAttesaDelComputer
        inAttesaDelComputer = true
        self.soloAlRitorno = soloAlRitorno
        if inizioRiconnessione == nil { inizioRiconnessione = Date() }
        tentativi = max(tentativi, 1)
        stato = .riconnessione(tentativo: tentativi)
        spegniFotocameraInAttesa()
        if !eraInAttesa {
            tentativiInAttesa = 0
            registro.aggiungi(soloAlRitorno
                              ? "\(computer.nome) ha chiuso: mi ricollego quando WebcamLR si riapre"
                              : "In attesa di \(computer.nome): mi ricollego appena risponde")
            // Dopo due minuti lo schermo torna a spegnersi da solo; riaprendo l'app si riprova subito.
            compitoSchermo?.cancel()
            compitoSchermo = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled, let self, self.inAttesaDelComputer else { return }
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        osservaApp()
        avviaRicercaAttesa()
        if !soloAlRitorno { programmaTentativoInAttesa() }
    }

    /// Batteria: mentre si aspetta la fotocamera è spenta; si riaccende appena il computer risponde
    /// (`accendiFotocameraInAnticipo` al collegamento sicuro). Un'accensione in corso si spegne da sé (`avviaFotocamera`).
    private func spegniFotocameraInAttesa() {
        guard fotocameraPronta else { return }
        cattura.ferma()
        fotocameraPronta = false
    }

    private func esciDallAttesa() {
        compitoSchermo?.cancel()
        compitoSchermo = nil
        ricercaAttesa?.cancel()
        ricercaAttesa = nil
        computerVisibile = nil
        tentativiInAttesa = 0
        ultimoTentativoInAttesa = nil
        if soloAlRitorno { soloAlRitorno = false }
        if inAttesaDelComputer { inAttesaDelComputer = false }
    }

    /// Il prossimo tentativo a tempo: 5, 10, 20, 40 secondi, poi ogni minuto.
    private func programmaTentativoInAttesa() {
        compitoRiprova?.cancel()
        compitoRiprova = nil
        guard inPrimoPiano else { return }
        let attesa = Self.attesePerTentativo[min(tentativiInAttesa, Self.attesePerTentativo.count - 1)]
        tentativiInAttesa += 1
        compitoRiprova = Task { [weak self] in
            try? await Task.sleep(for: attesa)
            guard !Task.isCancelled, let self else { return }
            self.provaInAttesa("nuovo tentativo")
        }
    }

    /// Un tentativo durante l'attesa, se ha senso: app in primo piano, nessun collegamento già aperto, non appena fatto.
    private func provaInAttesa(_ perche: String) {
        guard inAttesaDelComputer, inPrimoPiano, !chiusaDallUtente, collegamento == nil else { return }
        if let ultimo = ultimoTentativoInAttesa, Date().timeIntervalSince(ultimo) < 2 { return }
        ultimoTentativoInAttesa = Date()
        registro.aggiungi("Provo di nuovo \(computer.nome) (\(perche))")
        misura = (Date(), "dal tentativo", false)
        collega()
    }

    /// La ricerca Bonjour di questo computer: quando ricompare (WebcamLR riaperto, stessa rete di nuovo) si riprova subito.
    private func avviaRicercaAttesa() {
        guard ricercaAttesa == nil, inAttesaDelComputer, inPrimoPiano else { return }
        let nome = computer.nome
        let ricerca = NWBrowser(for: .bonjour(type: Servizio.tipoBonjour, domain: nil), using: NWParameters())
        ricerca.browseResultsChangedHandler = { [weak self, weak ricerca] risultati, _ in
            guard let ricerca else { return }
            let presente = risultati.contains(where: { risultato -> Bool in
                if case let .service(nomeServizio, _, _, _) = risultato.endpoint { return nomeServizio == nome }
                return false
            })
            Task { @MainActor in self?.computerVisto(presente, da: ricerca) }
        }
        ricerca.stateUpdateHandler = { [weak self, weak ricerca] stato in
            guard case .failed = stato, let ricerca else { return }
            Task { @MainActor in self?.ricercaAttesaFallita(ricerca) }
        }
        inizioRicercaAttesa = Date()
        computerVisibile = nil
        ricercaAttesa = ricerca
        ricerca.start(queue: .main)
    }

    private func computerVisto(_ presente: Bool, da ricerca: NWBrowser) {
        guard ricercaAttesa === ricerca, inAttesaDelComputer else { return }
        // Il primo risultato arriva quasi subito se il computer è già annunciato; più tardi vuol dire che è comparso.
        let prima: Bool? = computerVisibile ?? (Date().timeIntervalSince(inizioRicercaAttesa) > 1.5 ? false : nil)
        computerVisibile = presente
        guard presente else {
            if prima == true { registro.aggiungi("Non vedo più \(computer.nome)") }
            return
        }
        if prima == true { return }
        // Annunciato fin dall'inizio dopo un `arrivederci`: l'hanno scollegato sul computer, non ci si impone.
        if prima == nil && soloAlRitorno { return }
        tentativiInAttesa = 0
        provaInAttesa(prima == nil ? "si vede nella ricerca" : "è di nuovo nella ricerca")
    }

    private func ricercaAttesaFallita(_ ricerca: NWBrowser) {
        guard ricercaAttesa === ricerca else { return }
        ricerca.cancel()
        ricercaAttesa = nil
        computerVisibile = nil
        // Una ricerca fallita non riparte da sola: se ne avvia una nuova poco dopo.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.avviaRicercaAttesa()
        }
    }

    /// Gli osservatori dell'app si registrano alla prima attesa e si tolgono in `termina`.
    private func osservaApp() {
        guard osservatoriApp.isEmpty else { return }
        inPrimoPiano = UIApplication.shared.applicationState != .background
        let centro = NotificationCenter.default
        osservatoriApp.append(centro.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cambiaPrimoPiano(false) }
        })
        osservatoriApp.append(centro.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cambiaPrimoPiano(true) }
        })
    }

    /// In sottofondo l'attesa si ferma del tutto; tornando nell'app riparte e si riprova subito.
    private func cambiaPrimoPiano(_ attivo: Bool) {
        inPrimoPiano = attivo
        guard inAttesaDelComputer else { return }
        if attivo {
            tentativiInAttesa = 0
            ultimoTentativoInAttesa = nil
            avviaRicercaAttesa()
            if !soloAlRitorno {
                provaInAttesa("app di nuovo aperta")
                // Se un collegamento era già aperto, ci pensa lui; altrimenti si continua a tempo.
                if collegamento == nil && compitoRiprova == nil { programmaTentativoInAttesa() }
            }
        } else {
            compitoRiprova?.cancel()
            compitoRiprova = nil
            ricercaAttesa?.cancel()
            ricercaAttesa = nil
            computerVisibile = nil
        }
    }

    /// La fotocamera si riaccende appena il computer risponde, dopo l'eventuale accensione già in corso.
    private func accendiFotocameraInAnticipo() {
        guard !fotocameraPronta, !chiusaDallUtente else { return }
        let precedente = compitoFotocamera
        compitoFotocamera = Task { [weak self] in
            await precedente?.value
            guard let self, !self.fotocameraPronta, !self.chiusaDallUtente else { return }
            await self.avviaFotocamera(segnalaErrori: false)
        }
    }

    /// Scende a 720p quando è molto caldo; torna alla qualità scelta solo quando è di nuovo normale,
    /// così non salta avanti e indietro.
    /// Risparmio batteria (round 2): sotto il 20% e senza caricatore, 24 fps; si torna ai fotogrammi
    /// scelti col caricatore o dal 25%. Un solo riavvio della fotocamera anche se cambiano entrambi.
    /// Ritorna `true` se la fotocamera va riconfigurata.
    private func regolaQualita() -> Bool {
        var cambiata = false
        let attivo = UserDefaults.standard.object(forKey: "riduciSeCaldo") as? Bool ?? true
        let caldo = temperatura == .moltoCalda || temperatura == .critica
        if attivo && caldo && !qualitaRidotta {
            qualitaRidotta = true
            cambiata = true
        } else if qualitaRidotta && (temperatura == .normale || !attivo) {
            qualitaRidotta = false
            cambiata = true
        }

        let risparmioScelto = UserDefaults.standard.object(forKey: "risparmioBatteria") as? Bool ?? true
        if risparmioScelto && batteriaBassa && !risparmioBatteria {
            risparmioBatteria = true
            cambiata = true
        } else if risparmioBatteria && (!risparmioScelto || inCarica || batteria >= 25) {
            risparmioBatteria = false
            cambiata = true
        }

        return cambiata
    }
}

/// Le impostazioni che cambiano la configurazione della fotocamera o del codificatore (P03).
private struct ImpostazioniVideo: Equatable {
    let risoluzione: String
    let fps: Int
    let codec: String
    let specchia: Bool
    let stabilizzazione: Bool

    /// Con gli stessi valori di serie di `SchermataImpostazioni`.
    static func salvate() -> ImpostazioniVideo {
        let valori = UserDefaults.standard
        return ImpostazioniVideo(risoluzione: valori.string(forKey: "risoluzione") ?? "1080p",
                                 fps: valori.object(forKey: "fps") as? Int ?? 30,
                                 codec: valori.string(forKey: "codec") ?? "h264",
                                 specchia: valori.bool(forKey: "specchia"),
                                 stabilizzazione: valori.bool(forKey: "stabilizzazione"))
    }
}

extension Collegamento.MotivoChiusura {
    /// Per il registro del collegamento (1.5).
    var perRegistro: String {
        switch self {
        case .rete: "rete persa o computer che non risponde"
        case .dalComputer: "chiuso dal computer"
        case .computerVecchio: "versione vecchia sul computer"
        case .identitaCambiata: "identità del computer cambiata"
        case .identitaNonValida: "controllo di sicurezza non superato"
        case .permessoNegato: "permesso «Rete locale» negato"
        }
    }
}
