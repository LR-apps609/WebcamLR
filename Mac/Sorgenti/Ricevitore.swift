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

    struct Controlli: Equatable {
        /// L'obiettivo appena scelto da qui, finché il telefono non conferma.
        var obiettivo: String?
        var zoom = 1.0
        var torcia = false
        var esposizione = 0.0
        var biancoAutomatico = true
        var bianco = 5000.0
    }

    private var listener: NWListener?
    private var sessione: SessioneComputer?
    private var compitoAttesa: Task<Void, Never>?
    private var compitoInOnda: Task<Void, Never>?
    /// Un'app sta usando la webcam virtuale.
    private var webcamInUso = false

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
            if telefono?.nome != ciao.nome { controlli = Controlli() }
            telefono = ciao
            collegamento = webcamInUso ? .inOnda(app: nil) : .collegato
            sessione.segnala(InOnda(attivo: webcamInUso))
        case .formato:
            break
        case .stato(let stato):
            statoTelefono = stato
            if controlli.obiettivo == stato.obiettivo { controlli.obiettivo = nil }
        case .capacita(let nuove):
            capacita = nuove
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
                self.dimentica()
            }
        }
    }

    private func dimentica() {
        telefono = nil
        statoTelefono = nil
        statistiche = Statistiche()
        capacita = nil
        controlli = Controlli()
        collegamento = .nessunTelefono
        schermo.svuota()
    }
}
