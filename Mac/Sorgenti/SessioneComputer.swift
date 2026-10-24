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

/// La connessione con un telefono, lato computer (round 1). Dalla 1.8 i byte passano da un `TrasportoSessione`:
/// una NWConnection per la rete, o il socket usbmux per il cavo USB; tutto il resto è identico.
/// Legge i pacchetti sulla propria coda, misura la latenza e manda il video allo `Schermo`.
/// Protocollo 2 (0.10): stretta di mano, poi tutto cifrato; il telefono passa solo se fidato, con il gettone
/// del QR code o confermato dall'utente. Stesso ordine di Windows/WebcamLR.Ricevitore/SessioneComputer.cs.
final class SessioneComputer: @unchecked Sendable {
    enum Evento: Sendable {
        /// Il telefono è stato accettato; il `benvenuto` parte subito dopo. `impronta`: il codice di sicurezza
        /// del telefono (1.1): è quello che dice se è «lo stesso telefono», non il nome. `via`: come è collegato (1.2).
        case ciao(Ciao, impronta: String, via: TipoCollegamento)
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
        /// Il primo fotogramma è a schermo (1.11): «Avvio: 0,9 s» e la riga con le tappe per il registro.
        case avvio(testo: String, riga: String)
    }

    /// Tempo per la stretta di mano, la prova e il «ciao» (in microsecondi); per la conferma dell'utente vale `attesaConferma`.
    static let attesaStretta: UInt64 = 10_000_000
    static let attesaConferma: TimeInterval = 60

    /// Chiamata sulla coda principale.
    var suEvento: (@MainActor (Evento) -> Void)?

    private let trasporto: TrasportoSessione
    private let schermo: Schermo
    private let abbinamento: Abbinamento
    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.sessione", qos: .userInteractive)
    private var lettore = LettorePacchetti()
    private var timer: DispatchSourceTimer?
    private var chiusa = false
    /// Quando la connessione è arrivata: da qui partono l'attesa della stretta di mano e la misura dell'avvio.
    private let inizio: UInt64
    /// Avvio rapido misurato (1.11), solo sulla coda della sessione.
    private var avvio: MisuraAvvio
    /// Il primo fotogramma video è già passato allo schermo con la richiesta di avvisare quando è mostrato.
    private var primoVideoInviato = false
    /// Wi-Fi, cavo USB, cavo di rete, Wi-Fi diretto…: lo dice il trasporto quando è pronto (1.2).
    private var via: TipoCollegamento = .wifi

    // Solo la sessione attuale del Ricevitore manda il video allo schermo. Una sessione accettata ma chiusa
    // a favore di un'altra (precedenza del cavo, 1.9) o sostituita può aver già spedito il `benvenuto`:
    // i suoi fotogrammi non devono arrivare allo schermo insieme a quelli della sessione attuale.
    private enum StatoVideo {
        case inAttesa
        case attuale
        case esclusa
    }
    /// Scritto dalla coda principale (`diventaAttuale`, `chiudi`), letto sulla coda della sessione. Il lucchetto
    /// resta chiuso anche mentre i fotogrammi passano allo schermo: dopo `chiudi()` non ne parte più nessuno.
    private let bloccoVideo = NSLock()
    private var statoVideo = StatoVideo.inAttesa
    /// Fotogrammi arrivati prima che il Ricevitore renda attuale la sessione (di solito nessuno), dall'ultimo
    /// fotogramma chiave. Solo sulla coda della sessione.
    private var videoInAttesa: [FotogrammaVideo] = []

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

    /// `arrivo`: quando il listener (o il cavo) ha consegnato la connessione, nell'orologio del protocollo.
    init(trasporto: TrasportoSessione, schermo: Schermo, abbinamento: Abbinamento, arrivo: UInt64 = Orologio.adesso()) {
        self.trasporto = trasporto
        self.schermo = schermo
        self.abbinamento = abbinamento
        inizio = arrivo
        avvio = MisuraAvvio(arrivo: arrivo)
    }

    func avvia() {
        // Il timer parte subito: anche una connessione che non arriva mai a «pronta» si chiude dopo 10 secondi.
        coda.async { self.avviaTimer() }
        trasporto.avvia(coda: coda, suPronto: { [weak self] in
            guard let self else { return }
            self.via = self.trasporto.via
            self.ricevi()
        }, suFine: { [weak self] in
            self?.termina()
        })
    }

    func chiudi() {
        bloccoVideo.lock()
        statoVideo = .esclusa
        bloccoVideo.unlock()
        coda.async { self.chiudiConArrivederci() }
    }

    /// Dal Ricevitore, sulla coda principale: è la sessione del telefono attuale, il suo video va a schermo.
    func diventaAttuale() {
        bloccoVideo.lock()
        if statoVideo == .inAttesa { statoVideo = .attuale }
        bloccoVideo.unlock()
        coda.async { self.mandaVideoInAttesa() }
    }

    /// La risposta dell'utente alla domanda «Consentire …?».
    func rispondi(consentito: Bool) {
        coda.async { self.concludiConferma(consentito) }
    }

    /// Comandi della fotocamera verso il telefono (round 4).
    func comanda(_ comando: Comando) {
        coda.async { self.invia(.comando(comando)) }
    }

    /// Chiede al telefono un formato (P12: i 60 fps per la webcam virtuale). Dal computer `formato` è una richiesta:
    /// il telefono risponde con il formato effettivo, oppure la ignora.
    func chiedi(_ formato: FormatoVideo) {
        coda.async { self.invia(.formato(formato)) }
    }

    /// Dice al telefono se un'app sta usando la webcam virtuale (il rosso «IN ONDA»).
    func segnala(_ inOnda: InOnda) {
        coda.async { self.invia(.inOnda(inOnda)) }
    }

    // MARK: - Ricezione

    private func ricevi() {
        trasporto.ricevi(massimo: 256 * 1024) { [weak self] dati, finito in
            guard let self else { return }
            if let dati, !dati.isEmpty {
                self.lettore.aggiungi(dati)
                do {
                    while !self.chiusa, let pacchetto = try self.lettore.prossimo() {
                        try self.gestisci(pacchetto)
                    }
                } catch {
                    // Stretta di mano mancante, prova non valida, pacchetto alterato o fuori ordine: si chiude.
                    self.trasporto.annulla()
                    return
                }
            }
            if finito {
                self.trasporto.annulla()
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
            avvio.segnaStretta()
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
            avvio.segnaPrimoFotogramma(adesso)
            // Un fotogramma chiave rende inutili quelli prima: in attesa si tiene solo da lì.
            if fotogramma.chiave { videoInAttesa.removeAll() }
            videoInAttesa.append(fotogramma)
            if videoInAttesa.count > 600 { videoInAttesa.removeAll() }
            mandaVideoInAttesa()
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
            trasporto.annulla()
        default:
            break
        }
    }

    /// Sulla coda della sessione: i fotogrammi in attesa vanno allo schermo solo se la sessione è quella attuale.
    private func mandaVideoInAttesa() {
        bloccoVideo.lock()
        defer { bloccoVideo.unlock() }
        switch statoVideo {
        case .inAttesa:
            return
        case .esclusa:
            videoInAttesa.removeAll()
            return
        case .attuale:
            break
        }
        for fotogramma in videoInAttesa {
            if primoVideoInviato {
                schermo.mostra(fotogramma)
            } else {
                // Il primo: lo schermo avvisa quando la prima immagine di questa sessione è decodificata e mostrata.
                primoVideoInviato = true
                schermo.mostra(fotogramma) { [weak self] in
                    guard let self else { return }
                    let mostrato = Orologio.adesso()
                    self.coda.async { self.primaImmagineMostrata(mostrato) }
                }
            }
        }
        videoInAttesa.removeAll()
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
            trasporto.annulla()
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
        avvio.segnaConferma()
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
        notifica(.ciao(ciao, impronta: sicura.improntaAltro, via: via))
        // Il nome già letto all'avvio: Host.current() qui poteva ritardare il benvenuto.
        invia(.benvenuto(Benvenuto(nome: NomeMac.attuale, piattaforma: .mac)))
        avvio.segnaBenvenuto()
    }

    /// Avvio rapido misurato (1.11): la prima immagine di questa sessione è a schermo.
    private func primaImmagineMostrata(_ adesso: UInt64) {
        guard !chiusa, avvio.segnaMostrato(adesso), let testo = avvio.testo, let riga = avvio.riga else { return }
        notifica(.avvio(testo: testo, riga: riga))
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
                trasporto.annulla()
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
            trasporto.annulla()
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
        trasporto.invia(pacchetto.codificato(), poi: nil)
    }

    /// Chiude dopo aver spedito l'arrivederci (cifrato): il telefono capisce che è voluto e non si ricollega.
    private func chiudiConArrivederci() {
        guard !chiusa, let sicura,
              let pacchetto = try? sicura.canale.cifra(Pacchetto(messaggio: .arrivederci)) else {
            self.trasporto.annulla()
            return
        }
        let trasporto = self.trasporto
        trasporto.invia(pacchetto.codificato()) {
            trasporto.annulla()
        }
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

    /// Sulla coda principale, nello stesso ordine in cui gli eventi sono nati (la coda principale è FIFO):
    /// «ciao» arriva sempre prima di «formato» e del resto, senza aspettare il giro di un Task (1.11).
    private func notifica(_ evento: Evento) {
        let destinatario = suEvento
        DispatchQueue.main.async {
            MainActor.assumeIsolated { destinatario?(evento) }
        }
    }
}
