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
    private(set) var statoTelefono: StatoTelefono?
    private(set) var statistiche = Statistiche()
    /// Cosa si può comandare sul telefono collegato; nil finché il telefono non lo dice.
    private(set) var capacita: Capacita?
    /// Gli ultimi valori comandati da qui (il telefono non li rimanda indietro).
    var controlli = Controlli()

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

    /// Collega le immagini dell'iPhone alla webcam virtuale (round 2, serve l'account a pagamento)
    /// e controlla ogni secondo se un'app la sta usando.
    func collegaWebcamVirtuale() {
        let uscita = uscitaWebcam
        schermo.suImmagine = { immagine in uscita.invia(immagine) }
        compitoInOnda?.cancel()
        compitoInOnda = Task { [weak self] in
            while !Task.isCancelled {
                self?.controllaInOnda()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Telefono collegato, in onda o no.
    var telefonoAttivo: Bool {
        switch collegamento {
        case .collegato, .inOnda: true
        default: false
        }
    }

    /// Legge dalla webcam virtuale se un'app la sta usando (proprietà personalizzata «inon»).
    private func controllaInOnda() {
        let attivo = UscitaWebcam.leggiInOnda() ?? false
        guard attivo != webcamInUso else { return }
        webcamInUso = attivo
        sessione?.segnala(InOnda(attivo: attivo))
        if telefonoAttivo { collegamento = attivo ? .inOnda(app: nil) : .collegato }
    }

    // MARK: - Rete

    /// Pubblica `_webcamlr._tcp` (funzione 1). Se la porta 52740 è occupata ne usa un'altra.
    func avvia(porta: NWEndpoint.Port? = NWEndpoint.Port(rawValue: Servizio.portaPredefinita)) {
        guard listener == nil else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let parametri = NWParameters(tls: nil, tcp: tcp)
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

    private func aggiorna(_ nuovo: NWListener.State, portaFissa: Bool) {
        switch nuovo {
        case .ready:
            rete = .visibile(porta: listener?.port?.rawValue ?? 0)
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
    /// (di solito è lo stesso telefono che si riconnette).
    private func accetta(_ connessione: NWConnection) {
        sessione?.chiudi()
        let nuova = SessioneComputer(connessione: connessione, schermo: schermo)
        let identita = ObjectIdentifier(nuova)
        nuova.suEvento = { [weak self] evento in
            self?.gestisci(evento, da: identita)
        }
        sessione = nuova
        nuova.avvia()
    }

    /// Comandi della fotocamera verso il telefono collegato (round 4).
    func comanda(_ comando: Comando) {
        sessione?.comanda(comando)
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
        sessione?.chiudi()
        sessione = nil
        compitoAttesa?.cancel()
        dimentica()
    }

    private func gestisci(_ evento: SessioneComputer.Evento, da identita: ObjectIdentifier) {
        guard let sessione, ObjectIdentifier(sessione) == identita else { return }
        switch evento {
        case .ciao(let ciao):
            compitoAttesa?.cancel()
            if telefono?.nome != ciao.nome {
                controlli = Controlli()
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
            tieniSveglia(true)
            collegamento = webcamInUso ? .inOnda(app: nil) : .collegato
            sessione.segnala(InOnda(attivo: webcamInUso))
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
        case .silenzio:
            collegamento = .riconnessione
        case .ripresa:
            collegamento = webcamInUso ? .inOnda(app: nil) : .collegato
        case .chiusa:
            self.sessione = nil
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
        statoTelefono = nil
        statistiche = Statistiche()
        capacita = nil
        controlli = Controlli()
        collegamento = .nessunTelefono
        schermo.svuota()
    }
}
