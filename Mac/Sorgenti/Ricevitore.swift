import Foundation
import Network
import Observation
import Stile
import WebcamLRProtocollo

/// Il cuore dell'app Mac: si annuncia in rete, accetta un telefono e tiene lo stato per l'interfaccia.
@Observable
@MainActor
final class Ricevitore {
    enum StatoRete: Equatable {
        case fermo
        case visibile(porta: UInt16)
        case errore(String)
    }

    /// Dopo una caduta, quanto si aspetta che il telefono torni prima di dire «nessun telefono».
    static let attesaRiconnessione: Duration = .seconds(15)

    let schermo = Schermo()
    private let uscitaWebcam = UscitaWebcam()
    private(set) var rete: StatoRete = .fermo
    private(set) var collegamento: StatoCollegamento = .nessunTelefono
    private(set) var telefono: Ciao?
    /// Il codice di sicurezza del telefono attuale (1.1): due telefoni con lo stesso nome restano diversi.
    @ObservationIgnored private var improntaTelefono: String?
    /// Come è collegato il telefono attuale: Wi-Fi, cavo USB, Wi-Fi diretto, cavo di rete (1.2).
    private(set) var tipoCollegamento: TipoCollegamento?
    private(set) var statoTelefono: StatoTelefono?
    private(set) var statistiche = Statistiche()
    /// La latenza di ogni secondo, al massimo gli ultimi 60, per il grafico (funzione 31).
    private(set) var storicoLatenza: [Int?] = []
    /// Cosa si può comandare sul telefono collegato; nil finché il telefono non lo dice.
    private(set) var capacita: Capacita?
    /// Gli ultimi valori comandati da qui (il telefono non li rimanda indietro).
    var controlli = Controlli()
    /// La finestra mini è aperta (funzione 21).
    private(set) var miniAperta = false

    /// Collegamento sicuro (0.10): l'identità del Mac, i telefoni fidati e il gettone del QR code.
    let abbinamento: Abbinamento
    /// Il codice di sicurezza di questo Mac, come lo vede il telefono (impronta della chiave).
    let improntaMac: String
    /// Copie per l'interfaccia, aggiornate quando l'abbinamento cambia: il QR code si rifà da solo.
    private(set) var gettone: String
    private(set) var telefoniFidati: [TelefonoFidato]
    private let finestraConferma = FinestraConferma()
    /// Gli indirizzi IPv4 del Mac per il QR code, riletti solo quando la rete cambia.
    private(set) var indirizzi: [String] = IndirizziLocali.ipv4()
    private let monitorRete = NWPathMonitor()
    /// Il cavo USB (1.8): il client usbmux apre i canali verso l'iPhone, qui diventano sessioni come le altre.
    private let cavo = ClienteUSB()
    /// Per la diagnosi: un iPhone sul cavo senza l'app aperta, il cavo in pausa…
    private(set) var statoCavo: ClienteUSB.Stato = .nessunIPhone
    /// Le sessioni (candidate o attuale) arrivate dal cavo, con il canale da restituire al client quando finiscono.
    @ObservationIgnored private var canaliCavo: [ObjectIdentifier: ClienteUSB.Canale] = [:]
    /// Sessioni del cavo che, finendo, mettono il cavo in pausa: «Scollega» sul Mac o un telefono non consentito.
    /// Senza pausa il client riaprirebbe il canale dopo 2 secondi e la domanda tornerebbe all'infinito.
    @ObservationIgnored private var pausaCavo: Set<ObjectIdentifier> = []

    init() {
        let abbinamento = Abbinamento(identita: Portachiavi.identitaMac())
        self.abbinamento = abbinamento
        improntaMac = abbinamento.identita.impronta
        gettone = abbinamento.gettone
        telefoniFidati = abbinamento.fidati
        abbinamento.suCambio = { [weak self] in
            Task { @MainActor in self?.aggiornaAbbinamento() }
        }
        monitorRete.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.reteCambiata() }
        }
        monitorRete.start(queue: .main)
        cavo.suStato = { [weak self] stato in self?.statoCavo = stato }
        cavo.suCanale = { [weak self] descrittore, canale in
            guard let self else {
                close(descrittore)
                return
            }
            self.accettaCavo(descrittore, canale: canale)
        }
    }

    /// Wi-Fi cambiato, cavo collegato: il QR code si rifà con i nuovi indirizzi.
    func aggiornaIndirizzi() {
        let nuovi = IndirizziLocali.ipv4()
        if nuovi != indirizzi { indirizzi = nuovi }
    }

    /// Anche l'ascolto può essere caduto (rete sparita, risveglio dallo stop): con la rete nuova si riprova
    /// da soli, senza aspettare «Riprova», che si vede solo quando nessun telefono è collegato.
    private func reteCambiata() {
        aggiornaIndirizzi()
        if listener == nil, case .errore = rete { avvia() }
    }

    private func aggiornaAbbinamento() {
        gettone = abbinamento.gettone
        telefoniFidati = abbinamento.fidati
    }

    /// Dalle impostazioni: il telefono dovrà essere confermato di nuovo.
    func rimuoviFidato(_ telefono: TelefonoFidato) {
        abbinamento.rimuovi(telefono.impronta)
    }

    struct Controlli: Equatable, Codable {
        /// L'obiettivo appena scelto da qui, finché il telefono non conferma.
        var obiettivo: String?
        var zoom = 1.0
        var torcia = false
        var esposizione = 0.0
        var biancoAutomatico = true
        var bianco = 5000.0
        var esposizioneManuale = false
        var iso = 400.0
        var tempo = 60
    }

    private var listener: NWListener?
    private var sessione: SessioneComputer?
    /// Collegamenti arrivati ma non ancora accettati (stretta di mano, prova, fiducia): non toccano il telefono
    /// attuale finché non sono accettati, così nessuno sulla rete può farlo cadere. Qui solo per tenerli in vita.
    private var candidati: [ObjectIdentifier: SessioneComputer] = [:]
    /// Il candidato che aspetta la risposta dell'utente: una domanda alla volta.
    private var inConferma: ObjectIdentifier?
    private var compitoAttesa: Task<Void, Never>?
    private var compitoInOnda: Task<Void, Never>?
    /// Un'app sta usando la webcam virtuale.
    private var webcamInUso = false
    /// Finché un telefono è collegato macOS non mette l'app in sospensione (App Nap, funzione 20).
    @ObservationIgnored private var attivitaCollegamento: NSObjectProtocol?
    /// La notifica della batteria bassa è già partita; si riarma col caricatore o sopra il 25%.
    @ObservationIgnored private var avvisoBatteriaDato = false

    /// La porta su cui il Mac ascolta, quando è visibile in rete (serve al QR code).
    var porta: UInt16? {
        if case .visibile(let porta) = rete { return porta }
        return nil
    }

    /// Collega le immagini dell'iPhone alla webcam virtuale (serve l'account sviluppatore a pagamento)
    /// e controlla ogni secondo se un'app la sta usando.
    func collegaWebcamVirtuale() {
        let uscita = uscitaWebcam
        schermo.inviaImmagini { immagine in uscita.invia(immagine) }
        compitoInOnda?.cancel()
        compitoInOnda = Task { [weak self] in
            while !Task.isCancelled {
                // La lettura passa da CoreMediaIO e può richiedere tempo: fuori dalla coda principale.
                let attivo = await Task.detached(priority: .utility) { UscitaWebcam.leggiInOnda() ?? false }.value
                guard let self, !Task.isCancelled else { return }
                self.aggiornaInOnda(attivo)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// La finestra mini si è aperta o chiusa: lo schermo le manda le immagini solo mentre è aperta.
    func mostraMini(_ aperta: Bool) {
        miniAperta = aperta
        schermo.mostraMini(aperta)
    }

    /// Telefono collegato, in onda o no.
    var telefonoAttivo: Bool {
        switch collegamento {
        case .collegato, .inOnda: true
        default: false
        }
    }

    /// Dalla webcam virtuale: un'app la sta usando o no (proprietà personalizzata «inon»).
    private func aggiornaInOnda(_ attivo: Bool) {
        guard attivo != webcamInUso else { return }
        webcamInUso = attivo
        sessione?.segnala(InOnda(attivo: attivo))
        if telefonoAttivo { collegamento = attivo ? .inOnda(app: nil) : .collegato }
    }

    // MARK: - Rete

    /// Pubblica `_webcamlr._tcp` (funzione 1). Se la porta 52740 è occupata ne usa un'altra.
    func avvia(porta: NWEndpoint.Port? = NWEndpoint.Port(rawValue: Servizio.portaPredefinita)) {
        // Il cavo non dipende dalla rete: parte comunque (una volta sola).
        cavo.avvia()
        guard listener == nil else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let parametri = NWParameters(tls: nil, tcp: tcp)
            // Wi-Fi diretto (0.11), solo se acceso nelle Impostazioni: annuncio e collegamento anche via AWDL,
            // come AirDrop, per quando non c'è una rete in comune. Spento di serie: tiene la radio
            // occupata anche su un altro canale e la latenza della rete normale diventa meno stabile.
            parametri.includePeerToPeer = UserDefaults.standard.bool(forKey: Preferenze.wifiDiretto)
            // Riaprendo l'ascolto (cambio del Wi-Fi diretto) la stessa porta deve restare disponibile.
            parametri.allowLocalEndpointReuse = true
            let listener: NWListener
            if let porta {
                listener = try NWListener(using: parametri, on: porta)
            } else {
                listener = try NWListener(using: parametri)
            }

            var txt = NWTXTRecord()
            txt["v"] = String(Servizio.versioneProtocollo)
            txt["p"] = "mac"
            listener.service = NWListener.Service(name: nil, type: Servizio.tipoBonjour, domain: nil, txtRecord: txt)

            let portaFissa = porta != nil
            listener.stateUpdateHandler = { [weak self] nuovo in
                Task { @MainActor in self?.aggiorna(nuovo, portaFissa: portaFissa) }
            }
            listener.newConnectionHandler = { [weak self] connessione in
                Task { @MainActor in self?.accetta(connessione) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            rete = .errore(error.localizedDescription)
        }
    }

    /// Riapre l'ascolto con le impostazioni nuove (Wi-Fi diretto). I telefoni già collegati restano collegati.
    func riavviaAscolto() {
        listener?.cancel()
        listener = nil
        avvia()
    }

    private func aggiorna(_ nuovo: NWListener.State, portaFissa: Bool) {
        switch nuovo {
        case .ready:
            rete = .visibile(porta: listener?.port?.rawValue ?? 0)
            aggiornaIndirizzi()
        case .failed(let errore):
            listener?.cancel()
            listener = nil
            if portaFissa, case .posix(.EADDRINUSE) = errore {
                avvia(porta: nil)
            } else {
                rete = .errore(errore.localizedDescription)
            }
        default:
            break
        }
    }

    // MARK: - Telefono

    /// Un telefono alla volta: un nuovo collegamento sostituisce il precedente
    /// (di solito è lo stesso telefono che si riconnette), ma solo quando è accettato.
    /// Fino ad allora resta un candidato; se si chiude prima, sparisce e basta.
    private func accetta(_ connessione: NWConnection) {
        avviaCandidato(TrasportoRete(connessione))
    }

    /// Un canale aperto dal client usbmux: stessa strada della rete (stretta di mano, fiducia, candidati).
    /// Se il telefono è già collegato in Wi-Fi, il cavo prende il suo posto quando è accettato.
    private func accettaCavo(_ descrittore: Int32, canale: ClienteUSB.Canale) {
        let identita = avviaCandidato(TrasportoSocket(descrittore: descrittore))
        canaliCavo[identita] = canale
    }

    @discardableResult
    private func avviaCandidato(_ trasporto: TrasportoSessione) -> ObjectIdentifier {
        let nuova = SessioneComputer(trasporto: trasporto, schermo: schermo, abbinamento: abbinamento)
        let identita = ObjectIdentifier(nuova)
        nuova.suEvento = { [weak self] evento in
            self?.gestisci(evento, da: identita)
        }
        candidati[identita] = nuova
        nuova.avvia()
        return identita
    }

    /// «Collega via cavo»: riprende il cavo dopo una pausa.
    func collegaCavo() {
        cavo.riprendi()
    }

    /// Una sessione è finita: se veniva dal cavo, il client lo sa e decide se riprovare.
    private func chiusaSessione(_ identita: ObjectIdentifier) {
        let pausa = pausaCavo.remove(identita) != nil
        guard let canale = canaliCavo.removeValue(forKey: identita) else { return }
        cavo.sessioneFinita(canale, pausa: pausa)
    }

    private func vieneDalCavo(_ sessione: SessioneComputer?) -> Bool {
        guard let sessione else { return false }
        return canaliCavo[ObjectIdentifier(sessione)] != nil
    }

    /// Eventi di un collegamento non ancora accettato: la domanda all'utente, la chiusura, l'accettazione.
    /// Vero se l'evento è finito qui.
    private func gestisciCandidato(_ evento: SessioneComputer.Evento, da identita: ObjectIdentifier) -> Bool {
        guard let candidato = candidati[identita] else { return false }
        switch evento {
        case .ciao(_, let impronta, _):
            candidati[identita] = nil
            if inConferma == identita { inConferma = nil }
            // Consentito: il cavo non va più in pausa se questa sessione finisce.
            pausaCavo.remove(identita)
            // Precedenza (1.9, ridotta): se lo stesso telefono è già collegato via cavo e il cavo funziona,
            // un collegamento dalla rete non lo sostituisce: si chiude quello nuovo.
            if let attuale = sessione, attuale !== candidato, vieneDalCavo(attuale), canaliCavo[identita] == nil,
               impronta == improntaTelefono, collegamento != .riconnessione {
                candidato.chiudi()
                return true
            }
            // Accettato: prende il posto del telefono attuale (anche il cavo al posto del Wi-Fi).
            // Il resto dell'evento come sempre.
            if let vecchia = sessione, vecchia !== candidato { vecchia.chiudi() }
            sessione = candidato
            return false
        case .conferma(let nome, let codice):
            // C'è già una domanda aperta per un altro telefono: per sicurezza si rifiuta,
            // così nessuno può cambiare la domanda sotto il cursore dell'utente.
            guard inConferma == nil else {
                candidato.rispondi(consentito: false)
                return true
            }
            inConferma = identita
            // Un telefono del cavo non consentito (o senza risposta) non deve ripresentarsi ogni 2 secondi.
            if canaliCavo[identita] != nil { pausaCavo.insert(identita) }
            // Prima la notifica (solo se WebcamLR è in secondo piano), poi l'app davanti con la domanda.
            Notifiche.condivise.richiestaConsenso(nome)
            finestraConferma.mostra(nome: nome, codice: codice) { [weak self] consentito in
                self?.rispondiConferma(consentito, da: identita)
            }
        case .confermaFinita:
            if inConferma == identita { chiudiConferma() }
        case .chiusa:
            candidati[identita] = nil
            chiusaSessione(identita)
            // Il telefono se n'è andato mentre si aspettava la conferma: la domanda sparisce.
            if inConferma == identita { chiudiConferma() }
        default:
            break
        }
        return true
    }

    /// Comandi della fotocamera verso il telefono collegato.
    func comanda(_ comando: Comando) {
        sessione?.comanda(comando)
    }

    // MARK: - Comandi rapidi (dal pannello, dal menu e dai tasti, funzione 25)

    /// Passo dello zoom per i tasti + e −.
    static let passoZoom = 0.5

    /// Cambia obiettivo; lo zoom riparte da 1, come fa il telefono.
    func scegliObiettivo(_ obiettivo: String) {
        guard telefonoAttivo, capacita?.obiettivi.contains(obiettivo) == true else { return }
        controlli.obiettivo = obiettivo
        controlli.zoom = 1
        comanda(Comando(obiettivo: obiettivo))
    }

    /// L'obiettivo numero `indice` (da 0) nell'ordine in cui il telefono li elenca.
    func scegliObiettivo(numero indice: Int) {
        guard let obiettivi = capacita?.obiettivi, obiettivi.indices.contains(indice) else { return }
        scegliObiettivo(obiettivi[indice])
    }

    /// Zoom avanti o indietro di `passo`, entro i limiti dell'obiettivo attuale.
    func cambiaZoom(di passo: Double) {
        guard telefonoAttivo, let massimo = capacita?.zoomMassimo, massimo > 1 else { return }
        let nuovo = min(max(((controlli.zoom + passo) * 10).rounded() / 10, 1), massimo)
        guard nuovo != controlli.zoom else { return }
        controlli.zoom = nuovo
        comanda(Comando(zoom: nuovo))
    }

    func fuocoAutomatico() {
        guard telefonoAttivo else { return }
        comanda(Comando(fuoco: "continuo"))
    }

    /// Etichetta breve di un obiettivo, come sul telefono.
    static func etichetta(obiettivo: String) -> String {
        switch obiettivo {
        case "grandangolo": "0,5×"
        case "principale": "1×"
        case "tele": "Tele"
        case "frontale": "Frontale"
        default: obiettivo.capitalized
        }
    }

    /// Nome completo di un obiettivo, come nel glossario: «Grandangolo 0,5×», «Principale 1×».
    static func nome(obiettivo: String) -> String {
        switch obiettivo {
        case "grandangolo": "Grandangolo 0,5×"
        case "principale": "Principale 1×"
        case "tele": "Tele"
        case "frontale": "Frontale"
        default: obiettivo.capitalized
        }
    }

    // MARK: - Profili della fotocamera (funzione 23)

    private static let chiaveProfili = "profiliFotocamera"

    /// I comandi della fotocamera salvati per nome, sul Mac: valgono con qualsiasi telefono.
    private(set) var profili: [String: Controlli] = Ricevitore.leggiProfili()

    func salvaProfilo(_ nome: String) {
        var salvati = controlli
        // Si salva l'obiettivo che si vede selezionato: quello in attesa di conferma, se c'è, altrimenti quello in uso.
        salvati.obiettivo = controlli.obiettivo ?? statoTelefono?.obiettivo
        profili[nome] = salvati
        scriviProfili()
    }

    func eliminaProfilo(_ nome: String) {
        profili[nome] = nil
        scriviProfili()
    }

    /// Manda al telefono tutti i comandi del profilo in un solo messaggio.
    func applicaProfilo(_ nome: String) {
        guard let profilo = profili[nome] else { return }
        var obiettivo = profilo.obiettivo
        if let scelto = obiettivo, capacita?.obiettivi.contains(scelto) != true { obiettivo = nil }
        let manuale = profilo.esposizioneManuale && capacita?.isoMinimo != nil
        // Stesso obiettivo: il massimo è noto. Se cambia, ci pensa il telefono con i limiti del nuovo.
        var zoom = profilo.zoom
        if obiettivo == nil || obiettivo == statoTelefono?.obiettivo, let massimo = capacita?.zoomMassimo {
            zoom = min(max(zoom, 1), max(massimo, 1))
        }
        comanda(Comando(obiettivo: obiettivo, zoom: zoom,
                        torcia: capacita?.torcia == true ? profilo.torcia : nil,
                        esposizione: profilo.esposizione,
                        bianco: profilo.biancoAutomatico ? 0 : Int(profilo.bianco),
                        iso: manuale ? profilo.iso : 0, tempo: manuale ? profilo.tempo : 0))
        let torcia = controlli.torcia
        controlli = profilo
        controlli.obiettivo = obiettivo
        controlli.zoom = zoom
        // Se la torcia non è stata mandata, resta com'era.
        if capacita?.torcia != true { controlli.torcia = torcia }
        controlli.esposizioneManuale = manuale
    }

    private static func leggiProfili() -> [String: Controlli] {
        guard let dati = UserDefaults.standard.data(forKey: chiaveProfili) else { return [:] }
        return (try? JSONDecoder().decode([String: Controlli].self, from: dati)) ?? [:]
    }

    private func scriviProfili() {
        if let dati = try? JSONEncoder().encode(profili) {
            UserDefaults.standard.set(dati, forKey: Self.chiaveProfili)
        }
    }

    /// Chiusura voluta: il telefono riceve l'arrivederci e non si ricollega da solo.
    func scollega() {
        // Via cavo il Mac riaprirebbe il canale da solo: il cavo resta in pausa fino a «Collega via cavo».
        if let sessione, vieneDalCavo(sessione) { pausaCavo.insert(ObjectIdentifier(sessione)) }
        sessione?.chiudi()
        sessione = nil
        compitoAttesa?.cancel()
        dimentica()
    }

    private func gestisci(_ evento: SessioneComputer.Evento, da identita: ObjectIdentifier) {
        if gestisciCandidato(evento, da: identita) { return }
        guard let sessione, ObjectIdentifier(sessione) == identita else {
            // Una sessione sostituita (o chiusa per la precedenza del cavo) che finisce adesso.
            if case .chiusa = evento { chiusaSessione(identita) }
            return
        }
        switch evento {
        case .ciao(let ciao, let impronta, let via):
            compitoAttesa?.cancel()
            if telefono == nil || improntaTelefono != impronta {
                // Un altro telefono: niente di quello precedente (capacità, stato, grafico, avviso della batteria).
                controlli = Controlli()
                capacita = nil
                statoTelefono = nil
                storicoLatenza = []
                avvisoBatteriaDato = false
            } else {
                // Lo stesso telefono torna: forse con una sessione nuova, ripartita in automatico.
                // Gli si rimanda quello che il Mac mostra, così i due restano d'accordo.
                let attuali = controlli
                sessione.comanda(Comando(obiettivo: attuali.obiettivo, zoom: attuali.zoom, torcia: attuali.torcia, esposizione: attuali.esposizione,
                                         bianco: attuali.biancoAutomatico ? 0 : Int(attuali.bianco),
                                         iso: attuali.esposizioneManuale ? attuali.iso : 0,
                                         tempo: attuali.esposizioneManuale ? attuali.tempo : 0))
            }
            if telefono == nil { Notifiche.condivise.telefonoCollegato(ciao.nome) }
            telefono = ciao
            improntaTelefono = impronta
            tipoCollegamento = via
            tieniSveglia(true)
            collegamento = webcamInUso ? .inOnda(app: nil) : .collegato
            sessione.segnala(InOnda(attivo: webcamInUso))
        case .conferma, .confermaFinita:
            // Solo i candidati chiedono conferma (sopra).
            break
        case .formato:
            break
        case .stato(let stato):
            statoTelefono = stato
            controllaBatteria(stato)
            if controlli.obiettivo == stato.obiettivo { controlli.obiettivo = nil }
        case .capacita(let nuove):
            capacita = nuove
            // Obiettivo senza ISO manuale: l'interruttore sparisce e torna il cursore dell'esposizione.
            if nuove.isoMinimo == nil { controlli.esposizioneManuale = false }
        case .statistiche(let nuove):
            statistiche = nuove
            storicoLatenza.append(nuove.latenzaMs)
            if storicoLatenza.count > GraficoLatenza.secondi {
                storicoLatenza.removeFirst(storicoLatenza.count - GraficoLatenza.secondi)
            }
        case .silenzio:
            collegamento = .riconnessione
        case .ripresa:
            collegamento = webcamInUso ? .inOnda(app: nil) : .collegato
        case .chiusa:
            self.sessione = nil
            chiusaSessione(identita)
            guard telefono != nil else {
                collegamento = .nessunTelefono
                return
            }
            collegamento = .riconnessione
            statistiche.fps = 0
            statistiche.megabitAlSecondo = 0
            compitoAttesa?.cancel()
            compitoAttesa = Task { [weak self] in
                try? await Task.sleep(for: Self.attesaRiconnessione)
                guard let self, !Task.isCancelled, self.sessione == nil else { return }
                if let nome = self.telefono?.nome { Notifiche.condivise.telefonoPerso(nome) }
                self.dimentica()
            }
        }
    }

    /// «Consenti» o «Non consentire»: vale solo per la sessione che l'ha chiesto.
    private func rispondiConferma(_ consentito: Bool, da identita: ObjectIdentifier) {
        Notifiche.condivise.ritiraRichiestaConsenso()
        guard inConferma == identita else { return }
        inConferma = nil
        candidati[identita]?.rispondi(consentito: consentito)
    }

    private func chiudiConferma() {
        inConferma = nil
        finestraConferma.chiudi()
        Notifiche.condivise.ritiraRichiestaConsenso()
    }

    /// Una notifica sola quando la batteria scende al 20% senza caricatore (funzione 22).
    private func controllaBatteria(_ stato: StatoTelefono) {
        if stato.inCarica || stato.batteria > 25 {
            avvisoBatteriaDato = false
        } else if stato.batteria >= 0, stato.batteria <= 20, !avvisoBatteriaDato, let nome = telefono?.nome {
            avvisoBatteriaDato = true
            Notifiche.condivise.batteriaBassa(nome, percentuale: stato.batteria)
        }
    }

    /// Niente App Nap né timer rallentati mentre arriva il video: la latenza resta costante (funzione 20).
    /// Si tiene anche durante la riconnessione, fino a quando il telefono viene dimenticato.
    private func tieniSveglia(_ sveglia: Bool) {
        if sveglia, attivitaCollegamento == nil {
            attivitaCollegamento = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical], reason: "Video dall'iPhone in tempo reale")
        } else if !sveglia, let attivita = attivitaCollegamento {
            ProcessInfo.processInfo.endActivity(attivita)
            attivitaCollegamento = nil
        }
    }

    private func dimentica() {
        tieniSveglia(false)
        avvisoBatteriaDato = false
        telefono = nil
        improntaTelefono = nil
        tipoCollegamento = nil
        statoTelefono = nil
        statistiche = Statistiche()
        storicoLatenza = []
        capacita = nil
        controlli = Controlli()
        collegamento = .nessunTelefono
        schermo.svuota()
    }
}
