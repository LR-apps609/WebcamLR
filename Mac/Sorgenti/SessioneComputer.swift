import Foundation
import Network
import WebcamLRProtocollo

/// Numeri mostrati sotto l'anteprima, aggiornati ogni secondo.
struct Statistiche: Equatable, Sendable {
    var larghezza = 0
    var altezza = 0
    var fps = 0
    var megabitAlSecondo = 0.0
    var latenzaMs: Int?
    var codec: Codec = .h264
}

/// La connessione con un telefono, lato computer (round 1).
/// Legge i pacchetti sulla propria coda, misura la latenza e manda il video allo `Schermo`.
/// Protocollo 2 (0.10): stretta di mano, poi tutto cifrato; il telefono passa solo se fidato, con il gettone
/// del QR code o confermato dall'utente. Stesso ordine di Windows/WebcamLR.Ricevitore/SessioneComputer.cs.
final class SessioneComputer: @unchecked Sendable {
    enum Evento: Sendable {
        /// Il telefono è stato accettato; il `benvenuto` parte subito dopo.
        case ciao(Ciao)
        /// Il telefono non è fidato: bisogna chiedere all'utente, mostrando il codice di conferma.
        case conferma(nome: String, codice: String)
        /// La domanda non serve più (tempo scaduto): la finestra si chiude da sola.
        case confermaFinita
        case formato(FormatoVideo)
        case stato(StatoTelefono)
        case capacita(Capacita)
        case statistiche(Statistiche)
        /// Nessun dato da 3 secondi.
        case silenzio
        case ripresa
        case chiusa
    }

    /// Tempo per la stretta di mano, la prova e il «ciao» (in microsecondi); per la conferma dell'utente vale `attesaConferma`.
    static let attesaStretta: UInt64 = 10_000_000
    static let attesaConferma: TimeInterval = 60

    /// Chiamata sulla coda principale.
    var suEvento: (@MainActor (Evento) -> Void)?

    private let connessione: NWConnection
    private let schermo: Schermo
    private let abbinamento: Abbinamento
    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.sessione", qos: .userInteractive)
    private var lettore = LettorePacchetti()
    private var timer: DispatchSourceTimer?
    private var chiusa = false
    private let inizio = Orologio.adesso()

    // Collegamento sicuro: tutto solo sulla coda della sessione.
    private var sicura: SessioneSicura?
    private var provato = false
    private var gettoneProva: String?
    private var accettato = false
    /// Il `ciao` ricevuto, mentre si aspetta la risposta dell'utente.
    private var ciaoInAttesa: Ciao?
    private var inAccettazione = false
    private var scadenzaConferma: DispatchWorkItem?

    // Latenza: differenza tra gli orologi dal pong più rapido tra gli ultimi 10.
    private var misure: [(andataRitorno: UInt64, scarto: Int64)] = []
    private var latenzeUltimoSecondo: [Int] = []
    private var ultimaLatenza: Int?

    private var fotogrammiUltimoSecondo = 0
    private var byteUltimoSecondo = 0
    private var formato: FormatoVideo?
    private var ultimoPacchetto = Orologio.adesso()
    private var inSilenzio = false

    init(connessione: NWConnection, schermo: Schermo, abbinamento: Abbinamento) {
        self.connessione = connessione
        self.schermo = schermo
        self.abbinamento = abbinamento
    }

    func avvia() {
        connessione.stateUpdateHandler = { [weak self] stato in
            guard let self else { return }
            switch stato {
            case .ready:
                self.ricevi()
            case .failed, .cancelled:
                self.termina()
            default:
                break
            }
        }
        // Il timer parte subito: anche una connessione che non arriva mai a «pronta» si chiude dopo 10 secondi.
        coda.async { self.avviaTimer() }
        connessione.start(queue: coda)
    }

    func chiudi() {
        coda.async { self.chiudiConArrivederci() }
    }

    /// La risposta dell'utente alla domanda «Consentire …?».
    func rispondi(consentito: Bool) {
        coda.async { self.concludiConferma(consentito) }
    }

    /// Comandi della fotocamera verso il telefono (round 4).
    func comanda(_ comando: Comando) {
        coda.async { self.invia(.comando(comando)) }
    }

    /// Dice al telefono se un'app sta usando la webcam virtuale (il rosso «IN ONDA»).
    func segnala(_ inOnda: InOnda) {
        coda.async { self.invia(.inOnda(inOnda)) }
    }

    // MARK: - Ricezione

    private func ricevi() {
        connessione.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] dati, _, completo, errore in
            guard let self else { return }
            if let dati, !dati.isEmpty {
                self.lettore.aggiungi(dati)
                do {
                    while !self.chiusa, let pacchetto = try self.lettore.prossimo() {
                        try self.gestisci(pacchetto)
                    }
                } catch {
                    // Stretta di mano mancante, prova non valida, pacchetto alterato o fuori ordine: si chiude.
                    self.connessione.cancel()
                    return
                }
            }
            if completo || errore != nil {
                self.connessione.cancel()
            } else {
                self.ricevi()
            }
        }
    }

    private func gestisci(_ ricevuto: Pacchetto) throws {
        guard let sicura else {
            // Prima di tutto la stretta di mano, in chiaro; qualsiasi altra cosa (anche un telefono
            // con il protocollo 1) chiude la connessione.
            guard ricevuto.tipo == .controllo, case .stretta(let apertura) = try ricevuto.messaggio() else {
                throw ErroreProtocollo.contenutoNonValido
            }
            let stretta = StrettaComputer(identita: abbinamento.identita)
            let (risposta, sessione) = try stretta.rispondi(apertura)
            invia(.stretta(risposta), inChiaro: true)
            self.sicura = sessione
            return
        }
        let pacchetto = try sicura.canale.decifra(ricevuto)
        guard accettato else {
            if pacchetto.tipo == .controllo {
                try primaDiEssereAccettato(try pacchetto.messaggio(), sicura: sicura)
            }
            return
        }

        let adesso = Orologio.adesso()
        ultimoPacchetto = adesso
        if inSilenzio {
            inSilenzio = false
            notifica(.ripresa)
        }

        switch pacchetto.tipo {
        case .controllo:
            guard let messaggio = try? pacchetto.messaggio() else { return }
            gestisci(messaggio, adesso: adesso)
        case .video:
            guard let fotogramma = try? FotogrammaVideo(pacchetto: pacchetto) else { return }
            schermo.mostra(fotogramma)
            fotogrammiUltimoSecondo += 1
            byteUltimoSecondo += pacchetto.contenuto.count
            if let scarto = miglioreScarto() {
                // Istante di cattura nell'orologio del computer.
                let cattura = Int64(fotogramma.timestamp) - scarto
                let latenza = Int((Int64(adesso) - cattura) / 1000)
                if latenza >= 0 && latenza < 10_000 {
                    latenzeUltimoSecondo.append(latenza)
                }
            }
        case .audio:
            break
        }
    }

    private func gestisci(_ messaggio: Messaggio, adesso: UInt64) {
        switch messaggio {
        case .ciao:
            // Già accettato: un secondo «ciao» non cambia nulla.
            break
        case .pong(let pong):
            guard adesso >= pong.t else { return }
            let andataRitorno = adesso - pong.t
            let scarto = Int64(pong.telefono) - Int64(pong.t + andataRitorno / 2)
            misure.append((andataRitorno, scarto))
            if misure.count > 10 { misure.removeFirst() }
        case .formato(let formato):
            self.formato = formato
            schermo.imposta(codec: formato.codec)
            notifica(.formato(formato))
        case .stato(let stato):
            notifica(.stato(stato))
        case .capacita(let capacita):
            notifica(.capacita(capacita))
        case .arrivederci:
            connessione.cancel()
        default:
            break
        }
    }

    // MARK: - Prova e abbinamento

    /// Prima del `benvenuto` contano solo la prova e il `ciao`; il video non arriva ancora.
    private func primaDiEssereAccettato(_ messaggio: Messaggio, sicura: SessioneSicura) throws {
        switch messaggio {
        case .prova(let prova) where !provato:
            guard StrettaComputer.provaValida(prova, sessione: sicura) else { throw ErroreProtocollo.contenutoNonValido }
            provato = true
            gettoneProva = prova.gettone
        case .ciao(let ciao) where provato:
            accetta(ciao, sicura: sicura)
        case .arrivederci:
            connessione.cancel()
        default:
            // Senza prova non si accetta nient'altro; in attesa della conferma il resto
            // (per esempio un «formato» in anticipo) si ignora.
            guard provato else { throw ErroreProtocollo.contenutoNonValido }
        }
    }

    private func accetta(_ ciao: Ciao, sicura: SessioneSicura) {
        guard !inAccettazione else { return }
        inAccettazione = true
        if abbinamento.fidato(sicura.improntaAltro) || abbinamento.usaGettone(gettoneProva) {
            completaAccettazione(ciao, sicura: sicura)
            return
        }
        // Telefono nuovo senza il QR code: lo stesso codice sui due schermi, e decide l'utente.
        invia(.approvazione(Approvazione(codice: sicura.codice)))
        ciaoInAttesa = ciao
        let scadenza = DispatchWorkItem { [weak self] in self?.concludiConferma(false) }
        scadenzaConferma = scadenza
        coda.asyncAfter(deadline: .now() + Self.attesaConferma, execute: scadenza)
        notifica(.conferma(nome: ciao.nome, codice: sicura.codice))
    }

    /// Sì → fidato e `benvenuto`; no, o 60 secondi senza risposta → `arrivederci` e chiusura.
    private func concludiConferma(_ consentito: Bool) {
        guard let ciao = ciaoInAttesa, let sicura, !chiusa else { return }
        ciaoInAttesa = nil
        scadenzaConferma?.cancel()
        scadenzaConferma = nil
        notifica(.confermaFinita)
        if consentito {
            completaAccettazione(ciao, sicura: sicura)
        } else {
            chiudiConArrivederci()
        }
    }

    private func completaAccettazione(_ ciao: Ciao, sicura: SessioneSicura) {
        abbinamento.fida(sicura.improntaAltro, nome: ciao.nome)
        ultimoPacchetto = Orologio.adesso()
        // Accettato e annunciato prima del benvenuto (come Windows): l'evento «ciao», che mette questa
        // sessione al posto di quella attuale, è in coda prima di formato, stato e capacità che seguono.
        accettato = true
        notifica(.ciao(ciao))
        // Il nome già letto all'avvio: Host.current() qui poteva ritardare il benvenuto.
        invia(.benvenuto(Benvenuto(nome: NomeMac.attuale, piattaforma: .mac)))
    }

    private func miglioreScarto() -> Int64? {
        misure.min { $0.andataRitorno < $1.andataRitorno }?.scarto
    }

    // MARK: - Ogni secondo

    private func avviaTimer() {
        guard !chiusa, self.timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: coda)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.ogniSecondo() }
        timer.resume()
        self.timer = timer
    }

    private func ogniSecondo() {
        let adesso = Orologio.adesso()
        guard accettato else {
            // Niente ping, statistiche né silenzio prima dell'accettazione. Senza stretta di mano, prova
            // e «ciao» entro 10 secondi si chiude; durante la conferma dell'utente si aspetta (fino a 60).
            if ciaoInAttesa == nil, adesso - min(inizio, adesso) > Self.attesaStretta {
                connessione.cancel()
            }
            return
        }
        invia(.ping(Ping(t: adesso)))

        if !latenzeUltimoSecondo.isEmpty {
            let ordinate = latenzeUltimoSecondo.sorted()
            ultimaLatenza = ordinate[ordinate.count / 2]
            latenzeUltimoSecondo.removeAll()
        }
        if let ultimaLatenza {
            invia(.latenza(Latenza(ms: ultimaLatenza)))
        }

        notifica(.statistiche(Statistiche(larghezza: formato?.larghezza ?? 0,
                                          altezza: formato?.altezza ?? 0,
                                          fps: fotogrammiUltimoSecondo,
                                          megabitAlSecondo: Double(byteUltimoSecondo) * 8 / 1_000_000,
                                          latenzaMs: ultimaLatenza,
                                          codec: formato?.codec ?? .h264)))
        fotogrammiUltimoSecondo = 0
        byteUltimoSecondo = 0

        let silenzio = adesso - min(ultimoPacchetto, adesso)
        if silenzio > 10_000_000 {
            connessione.cancel()
        } else if silenzio > 3_000_000 && !inSilenzio {
            inSilenzio = true
            notifica(.silenzio)
        }
    }

    // MARK: - Utilità

    /// Sempre sulla coda della sessione: si cifra subito prima di `send`, così l'ordine dei contatori
    /// è quello di spedizione. Dopo la stretta di mano nulla parte in chiaro.
    private func invia(_ messaggio: Messaggio, inChiaro: Bool = false) {
        guard !chiusa, var pacchetto = try? Pacchetto(messaggio: messaggio) else { return }
        if !inChiaro {
            guard let sicura, let cifrato = try? sicura.canale.cifra(pacchetto) else { return }
            pacchetto = cifrato
        }
        connessione.send(content: pacchetto.codificato(), completion: .contentProcessed { _ in })
    }

    /// Chiude dopo aver spedito l'arrivederci (cifrato): il telefono capisce che è voluto e non si ricollega.
    private func chiudiConArrivederci() {
        guard !chiusa, let sicura,
              let pacchetto = try? sicura.canale.cifra(Pacchetto(messaggio: .arrivederci)) else {
            self.connessione.cancel()
            return
        }
        let connessione = self.connessione
        connessione.send(content: pacchetto.codificato(), completion: .contentProcessed { _ in
            connessione.cancel()
        })
    }

    private func termina() {
        guard !chiusa else { return }
        chiusa = true
        timer?.cancel()
        timer = nil
        scadenzaConferma?.cancel()
        scadenzaConferma = nil
        ciaoInAttesa = nil
        notifica(.chiusa)
    }

    private func notifica(_ evento: Evento) {
        let destinatario = suEvento
        Task { @MainActor in destinatario?(evento) }
    }
}
