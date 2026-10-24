import Foundation
import Network
import WebcamLRProtocollo

/// La connessione TCP con il computer: legge e scrive pacchetti sulla propria coda.
/// Ai `ping` risponde da sola, senza passare dall'interfaccia, per misurare la latenza vera.
/// Protocollo 2 (Documenti/Protocollo.md, «Collegamento sicuro»): stretta di mano in chiaro, poi la prova
/// e tutto il resto cifrato. Si cifra sulla coda del collegamento subito prima di `send`, così l'ordine
/// dei contatori è quello di invio.
final class Collegamento: @unchecked Sendable {
    enum Evento: Sendable {
        /// Stretta di mano riuscita e prova spedita: ora si può mandare il `ciao`. `impronta` è quella del computer.
        case pronto(impronta: String)
        case messaggio(Messaggio)
        /// Come si è collegati (1.2): all'apertura e quando il percorso di rete cambia.
        case tipo(TipoCollegamento?)
        /// 1.10: con più indirizzi (QR code) la posizione di quello che ha risposto per primo, nell'ordine
        /// `[verso] + altri`: la volta dopo si prova per primo.
        case indirizzo(Int)
        case chiuso(errore: String?, motivo: MotivoChiusura)
    }

    enum MotivoChiusura: Sendable, Equatable {
        /// Rete persa, computer spento, dati rovinati: si può riprovare da soli.
        case rete
        /// Il computer ha chiuso di proposito («Scollega», oppure il collegamento non è stato consentito):
        /// non si riprova da soli.
        case dalComputer
        /// Il computer parla il protocollo 1: va aggiornato.
        case computerVecchio
        /// L'impronta del computer non è quella attesa: va riabbinato con il QR code.
        case identitaCambiata
        /// Il computer non ha dimostrato di avere la sua chiave.
        case identitaNonValida
        /// iOS non concede il permesso «Rete locale» (1.3).
        case permessoNegato
    }

    /// Chiamata sulla coda principale.
    var suEvento: (@MainActor (Evento) -> Void)?
    /// Chiamata quando un fotogramma è stato scartato: serve un fotogramma chiave.
    var suPerdita: (() -> Void)?
    /// Una volta al secondo, sulla coda del collegamento: fotogrammi scartati e se la rete era satura
    /// (quasi sempre fotogrammi in attesa). Serve alla qualità che segue la rete (round 2).
    var suSecondo: ((_ scartati: Int, _ saturo: Bool) -> Void)?

    /// La connessione in uso. Con più indirizzi (1.10) è la prima che risponde; prima della scelta è la prima della gara.
    /// Dopo l'`init`, solo sulla coda.
    private var connessione: NWConnection
    /// 1.10: tutte le connessioni in gara, una per indirizzo del QR code (sempre almeno una). Solo sulla coda.
    private var inGara: [NWConnection]
    private var avviateInGara = 0
    private var falliteInGara = 0
    /// La prima connessione pronta ha vinto: da qui c'è solo `connessione`.
    private var vincitriceScelta = false
    /// 1.6: connessione accettata dall'ascolto sul cavo USB (127.0.0.1), non aperta da qui.
    private let viaCavo: Bool
    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.collegamento", qos: .userInteractive)
    private var lettore = LettorePacchetti()
    private var videoInVolo = 0
    /// Si parte da un fotogramma chiave: dopo una riconnessione il codificatore può avere ancora fotogrammi intermedi.
    private var attendiChiave = true
    private var chiuso = false
    private var congedato = false
    private var pronto = false
    private var scartatiNelSecondo = 0
    private var inviatiNelSecondo = 0
    private var pieniNelSecondo = 0
    private var orologio: DispatchSourceTimer?
    /// Secondi dell'orologio senza nulla dal computer, che dopo il `benvenuto` manda un `ping` al secondo.
    private var secondiSenzaDati = 0
    /// L'ultimo tipo di collegamento notificato: si avvisa solo quando cambia.
    private var ultimoTipo: TipoCollegamento?

    // Collegamento sicuro: tutto letto e scritto solo sulla coda.
    private let stretta: StrettaTelefono
    /// Dal QR code, oppure salvata dopo il primo `benvenuto`; `nil` = prima volta dalla ricerca.
    private let improntaAttesa: String?
    private let gettone: String?
    /// Esiste dopo la stretta di mano: da lì in poi ogni pacchetto, nei due sensi, passa di qui.
    private var canale: CanaleCifrato?
    private var accolto = false
    /// Le 4 cifre calcolate qui dalla trascrizione: solo queste si mostrano, mai quelle ricevute.
    private var codiceConferma: String?
    /// Ogni nuova attesa del `benvenuto` annulla la precedente.
    private var attesaBenvenuto = 0

    /// Oltre questo tempo senza collegamento si rinuncia e si riprova (per esempio se Bonjour non risolve).
    private static let attesaMassima: DispatchTimeInterval = .seconds(8)
    /// Un computer versione 2 risponde alla stretta di mano subito; uno versione 1 mai.
    private static let attesaStretta: DispatchTimeInterval = .seconds(5)
    /// Dopo la prova, se il telefono è già fidato il `benvenuto` arriva subito.
    private static let attesaBenvenutoNormale = 10
    /// Il computer chiede all'utente e aspetta 60 secondi: qualche secondo in più per la rete.
    private static let attesaConferma = 65

    /// Computer spento, chiuso o fuori dal Wi-Fi senza che il TCP se ne accorga: si riprova invece di restare «Collegato».
    private static let secondiDiSilenzio = 6

    /// 1.10: come «happy eyeballs» (RFC 8305): il primo indirizzo subito, ogni altro dopo questo intervallo,
    /// o subito se il precedente fallisce. Il primo che risponde vince, gli altri si chiudono.
    private static let intervalloGara: DispatchTimeInterval = .milliseconds(150)

    /// Oltre questo numero di fotogrammi non ancora spediti, la rete è troppo lenta e si scarta.
    private static let massimoInVolo = 3

    /// `diretto`: il computer è stato trovato solo con il Wi-Fi diretto; altrimenti si resta sulla rete normale,
    /// che ha una latenza più stabile.
    /// `altri`: 1.10, gli altri indirizzi del QR code, provati in gara con il primo.
    /// Con un servizio Bonjour (`.service`) la `NWConnection` risolve nome e indirizzo e si collega in un passo solo:
    /// niente risoluzione a parte prima.
    init(verso endpoint: NWEndpoint, identita: IdentitaDispositivo, improntaAttesa: String?, gettone: String?,
         diretto: Bool = false, altri: [NWEndpoint] = []) {
        stretta = StrettaTelefono(identita: identita)
        self.improntaAttesa = improntaAttesa
        self.gettone = gettone
        viaCavo = false
        let prima = Self.nuovaConnessione(verso: endpoint, diretto: diretto)
        connessione = prima
        inGara = [prima] + altri.map { Self.nuovaConnessione(verso: $0, diretto: diretto) }
    }

    private static func nuovaConnessione(verso endpoint: NWEndpoint, diretto: Bool) -> NWConnection {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parametri = NWParameters(tls: nil, tcp: tcp)
        // Video in tempo reale: il Wi-Fi gli dà la priorità (round 2).
        parametri.serviceClass = .interactiveVideo
        // Wi-Fi diretto con il Mac (0.11) solo se serve davvero: fa saltare la radio tra due canali.
        parametri.includePeerToPeer = diretto
        return NWConnection(to: endpoint, using: parametri)
    }

    /// 1.6: una connessione già accettata dall'ascolto sul cavo USB. Stessa sessione sicura del Wi-Fi: il telefono
    /// manda per primo la `stretta`. Il nome del computer arriva nel `benvenuto`: lì la sessione salva o verifica
    /// il suo codice di sicurezza.
    init(accettata connessione: NWConnection, identita: IdentitaDispositivo) {
        stretta = StrettaTelefono(identita: identita)
        improntaAttesa = nil
        gettone = nil
        viaCavo = true
        self.connessione = connessione
        inGara = [connessione]
    }

    deinit {
        orologio?.cancel()
    }

    func avvia() {
        for candidata in inGara {
            candidata.stateUpdateHandler = { [weak self, weak candidata] stato in
                guard let self, let candidata else { return }
                self.statoCambiato(stato, di: candidata)
            }
            candidata.pathUpdateHandler = { [weak self, weak candidata] _ in
                guard let self, let candidata, candidata === self.connessione, self.pronto, !self.chiuso else { return }
                self.aggiornaTipo()
            }
        }
        coda.async { self.avviaProssima() }
        coda.asyncAfter(deadline: .now() + Self.attesaMassima) { [weak self] in
            guard let self, !self.pronto, !self.chiuso else { return }
            self.termina("Il computer non risponde: controlla che WebcamLR sia aperto sul computer, poi tocca «Riprova».")
        }
    }

    /// Sulla coda: avvia la prossima connessione della gara e, se ne restano, programma quella dopo.
    private func avviaProssima() {
        guard !chiuso, !vincitriceScelta, avviateInGara < inGara.count else { return }
        let indice = avviateInGara
        avviateInGara += 1
        inGara[indice].start(queue: coda)
        guard avviateInGara < inGara.count else { return }
        coda.asyncAfter(deadline: .now() + Self.intervalloGara) { [weak self] in
            // Se nel frattempo la seguente è già partita (perché questa è fallita), non si avvia due volte.
            guard let self, self.avviateInGara == indice + 1 else { return }
            self.avviaProssima()
        }
    }

    /// Sulla coda: gli stati di ogni connessione della gara, poi solo quelli della connessione scelta.
    private func statoCambiato(_ stato: NWConnection.State, di candidata: NWConnection) {
        if vincitriceScelta {
            guard candidata === connessione else { return }
            switch stato {
            // I testi di sistema sono in inglese e non dicono cosa fare: ci pensa la sessione.
            case .failed(let errore), .waiting(let errore):
                termina(nil, motivo: Collegamento.ePermessoNegato(errore) ? MotivoChiusura.permessoNegato : nil)
            case .cancelled:
                termina(nil)
            default:
                break
            }
            return
        }
        guard !chiuso else { return }
        switch stato {
        case .ready:
            vincitriceScelta = true
            connessione = candidata
            let posizione = inGara.count > 1 ? inGara.firstIndex(where: { $0 === candidata }) : nil
            for altra in inGara where altra !== candidata {
                altra.stateUpdateHandler = nil
                altra.pathUpdateHandler = nil
                altra.cancel()
            }
            inGara = [candidata]
            if let posizione { notifica(.indirizzo(posizione)) }
            pronto = true
            aggiornaTipo()
            avviaOrologio()
            apriStretta()
            ricevi()
        case .failed(let errore), .waiting(let errore):
            // Questo indirizzo non risponde: si chiude e parte subito il prossimo. Solo se falliscono tutti si rinuncia.
            candidata.stateUpdateHandler = nil
            candidata.pathUpdateHandler = nil
            candidata.cancel()
            falliteInGara += 1
            if falliteInGara >= inGara.count {
                termina(nil, motivo: Collegamento.ePermessoNegato(errore) ? MotivoChiusura.permessoNegato : nil)
            } else {
                avviaProssima()
            }
        case .cancelled:
            // Prima della scelta si annulla solo da qui (`termina`): niente da fare.
            break
        default:
            break
        }
    }

    /// -65570 = kDNSServiceErr_PolicyDenied: l'utente non ha concesso la rete locale.
    private static func ePermessoNegato(_ errore: NWError) -> Bool {
        if case .dns(let codice) = errore, codice == -65570 { return true }
        return false
    }

    func chiudi() {
        coda.async {
            guard !self.chiuso else { return }
            // Nessun indirizzo ha ancora risposto: si chiude tutta la gara, come faceva l'annullamento della connessione.
            guard self.vincitriceScelta else {
                self.termina(nil)
                return
            }
            guard let canale = self.canale,
                  let chiaro = try? Pacchetto(messaggio: .arrivederci),
                  let cifrato = try? canale.cifra(chiaro) else {
                self.connessione.cancel()
                return
            }
            // Chiude dopo aver spedito l'arrivederci, così il computer sa che è voluto.
            self.connessione.send(content: cifrato.codificato(), completion: .contentProcessed { _ in
                self.connessione.cancel()
            })
            // Con la rete ferma l'invio può non finire mai: si chiude comunque.
            self.coda.asyncAfter(deadline: .now() + 1) { self.connessione.cancel() }
        }
    }

    func invia(_ messaggio: Messaggio) {
        guard let pacchetto = try? Pacchetto(messaggio: messaggio) else { return }
        coda.async { self.spedisci(pacchetto) }
    }

    /// Spedisce un fotogramma, oppure lo scarta se la rete non sta al passo.
    /// Dopo uno scarto aspetta il prossimo fotogramma chiave, altrimenti il video si rovina.
    func inviaVideo(_ fotogramma: FotogrammaVideo) {
        coda.async {
            guard !self.chiuso, let canale = self.canale else { return }
            if self.attendiChiave && !fotogramma.chiave { return }
            if self.videoInVolo >= Self.massimoInVolo && !fotogramma.chiave {
                self.attendiChiave = true
                self.scartatiNelSecondo += 1
                self.suPerdita?()
                return
            }
            // Cifrato qui, sulla coda, subito prima di spedirlo: il contatore segue l'ordine di invio.
            guard let cifrato = try? canale.cifra(fotogramma.pacchetto) else { return }
            self.attendiChiave = false
            self.inviatiNelSecondo += 1
            if self.videoInVolo >= Self.massimoInVolo - 1 { self.pieniNelSecondo += 1 }
            self.videoInVolo += 1
            self.connessione.send(content: cifrato.codificato(), completion: .contentProcessed { [weak self] _ in
                self?.videoInVolo -= 1
            })
        }
    }

    /// Sulla coda del collegamento: il tipo ricavato dal percorso attuale, se è cambiato.
    private func aggiornaTipo() {
        let tipo: TipoCollegamento?
        if viaCavo {
            tipo = .cavoUSB
        } else {
            guard let percorso = connessione.currentPath else { return }
            tipo = TipoCollegamento.da(percorso)
        }
        guard tipo != ultimoTipo else { return }
        ultimoTipo = tipo
        notifica(.tipo(tipo))
    }

    /// Il bilancio di ogni secondo di invio, sulla coda del collegamento.
    private func avviaOrologio() {
        let nuovo = DispatchSource.makeTimerSource(queue: coda)
        nuovo.schedule(deadline: .now() + 1, repeating: 1.0)
        nuovo.setEventHandler { [weak self] in
            self?.chiudiSecondo()
        }
        nuovo.resume()
        orologio = nuovo
    }

    private func chiudiSecondo() {
        guard !chiuso else { return }
        if accolto {
            secondiSenzaDati += 1
            if secondiSenzaDati >= Self.secondiDiSilenzio {
                termina(nil)
                return
            }
        }
        // Satura: più di metà dei fotogrammi è partita con la coda quasi piena.
        let saturo = inviatiNelSecondo > 0 && pieniNelSecondo * 2 > inviatiNelSecondo
        suSecondo?(scartatiNelSecondo, saturo)
        scartatiNelSecondo = 0
        inviatiNelSecondo = 0
        pieniNelSecondo = 0
    }

    // MARK: - Stretta di mano

    /// Il primo pacchetto, l'unico che il telefono manda in chiaro.
    private func apriStretta() {
        guard let pacchetto = try? Pacchetto(messaggio: .stretta(stretta.apertura)) else {
            termina("Collegamento sicuro non riuscito: tocca «Riprova».")
            return
        }
        connessione.send(content: pacchetto.codificato(), completion: .contentProcessed { _ in })
        // Un computer versione 1 non risponde mai alla stretta di mano.
        coda.asyncAfter(deadline: .now() + Self.attesaStretta) { [weak self] in
            guard let self, !self.chiuso, self.canale == nil else { return }
            self.termina(nil, motivo: .computerVecchio)
        }
    }

    /// Prima del canale cifrato arriva solo la stretta di mano del computer, in chiaro.
    private func gestisciStretta(_ pacchetto: Pacchetto) {
        guard pacchetto.tipo == .controllo, pacchetto.flag & CanaleCifrato.flagCifrato == 0,
              let messaggio = try? pacchetto.messaggio() else {
            termina("Il computer ha mandato dati non validi: tocca «Riprova», e se succede ancora riapri WebcamLR sul computer.")
            return
        }
        // Un computer versione 1 parte subito con i `ping` in chiaro, senza stretta di mano.
        guard case .stretta(let risposta) = messaggio, risposta.versione == Sicurezza.versioneSicura else {
            termina(nil, motivo: .computerVecchio)
            return
        }
        let completata: (sessione: SessioneSicura, prova: Prova)
        do {
            // Il gettone del QR code va solo al computer di cui si è verificata l'impronta.
            completata = try stretta.completa(risposta, gettone: improntaAttesa == nil ? nil : gettone)
        } catch {
            termina(nil, motivo: .identitaNonValida)
            return
        }
        let impronta = completata.sessione.improntaAltro
        if let attesa = improntaAttesa, attesa != impronta {
            termina(nil, motivo: .identitaCambiata)
            return
        }
        canale = completata.sessione.canale
        codiceConferma = completata.sessione.codice
        spedisciMessaggio(.prova(completata.prova))
        attendiBenvenuto(secondi: Self.attesaBenvenutoNormale)
        notifica(.pronto(impronta: impronta))
    }

    /// Senza `benvenuto` entro il tempo si chiude; un'`approvazione` allunga l'attesa.
    private func attendiBenvenuto(secondi: Int) {
        attesaBenvenuto += 1
        let numero = attesaBenvenuto
        coda.asyncAfter(deadline: .now() + .seconds(secondi)) { [weak self] in
            guard let self, !self.chiuso, !self.accolto, self.attesaBenvenuto == numero else { return }
            self.termina("Il computer non ha risposto in tempo: controlla che WebcamLR sia aperto sul computer, poi tocca «Riprova».")
        }
    }

    // MARK: - Invio e ricezione

    /// Ogni pacchetto dopo la stretta di mano esce cifrato; prima del canale non esce nulla.
    private func spedisci(_ pacchetto: Pacchetto) {
        guard !chiuso, let canale = canale, let cifrato = try? canale.cifra(pacchetto) else { return }
        connessione.send(content: cifrato.codificato(), completion: .contentProcessed { _ in })
    }

    private func ricevi() {
        connessione.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] dati, _, completo, errore in
            guard let self, !self.chiuso else { return }
            if let dati, !dati.isEmpty {
                self.secondiSenzaDati = 0
                self.lettore.aggiungi(dati)
                do {
                    while !self.chiuso, let pacchetto = try self.lettore.prossimo() {
                        self.gestisci(pacchetto)
                    }
                } catch {
                    self.termina("Il computer ha mandato dati non validi: tocca «Riprova», e se succede ancora riapri WebcamLR sul computer.")
                    return
                }
            }
            if self.chiuso { return }
            if completo || errore != nil {
                self.connessione.cancel()
            } else {
                self.ricevi()
            }
        }
    }

    private func gestisci(_ ricevuto: Pacchetto) {
        guard let canale = canale else {
            gestisciStretta(ricevuto)
            return
        }
        // Un pacchetto ripetuto, mancante o alterato chiude il collegamento.
        guard let pacchetto = try? canale.decifra(ricevuto) else {
            termina("Dati non validi dal computer: collegamento chiuso per sicurezza. Tocca «Riprova».")
            return
        }
        guard pacchetto.tipo == .controllo, let messaggio = try? pacchetto.messaggio() else { return }
        switch messaggio {
        case .ping(let ping):
            spedisciMessaggio(.pong(Pong(t: ping.t, telefono: Orologio.adesso())))
        case .arrivederci:
            congedato = true
            connessione.cancel()
        case .approvazione(let approvazione):
            // Il codice deve essere quello calcolato qui: chi sta in mezzo potrebbe inoltrare quello del computer.
            guard approvazione.codice == codiceConferma else {
                termina(nil, motivo: .identitaNonValida)
                return
            }
            // Il computer chiede all'utente: niente fretta finché non risponde.
            attendiBenvenuto(secondi: Self.attesaConferma)
            notifica(.messaggio(messaggio))
        case .benvenuto:
            accolto = true
            notifica(.messaggio(messaggio))
        case .sconosciuto:
            break
        default:
            notifica(.messaggio(messaggio))
        }
    }

    private func spedisciMessaggio(_ messaggio: Messaggio) {
        if let pacchetto = try? Pacchetto(messaggio: messaggio) {
            spedisci(pacchetto)
        }
    }

    private func termina(_ errore: String?, motivo: MotivoChiusura? = nil) {
        guard !chiuso else { return }
        chiuso = true
        orologio?.cancel()
        orologio = nil
        for candidata in inGara where candidata !== connessione { candidata.cancel() }
        connessione.cancel()
        notifica(.chiuso(errore: errore, motivo: motivo ?? (congedato ? .dalComputer : .rete)))
    }

    private func notifica(_ evento: Evento) {
        let destinatario = suEvento
        Task { @MainActor in destinatario?(evento) }
    }
}
