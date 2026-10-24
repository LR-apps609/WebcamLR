import Foundation
import Network
import Observation
import WebcamLRProtocollo

struct ComputerTrovato: Identifiable, Hashable {
    let id: String
    let nome: String
    let piattaforma: Piattaforma?
    let endpoint: NWEndpoint
    /// Solo dal QR code (protocollo 2): l'impronta della chiave del computer, da verificare nella stretta di mano.
    var impronta: String? = nil
    /// Solo dal QR code: il gettone di abbinamento, da rimandare nella prova.
    var gettone: String? = nil
    /// Trovato solo con il Wi-Fi diretto (senza router): il collegamento userà anche quello.
    var diretto: Bool = false
}

extension ComputerTrovato {
    /// Trovato dalla ricerca (Bonjour): il computer è acceso e WebcamLR è aperto.
    var annunciato: Bool {
        if case .service = endpoint { return true }
        return false
    }

    init?(risultato: NWBrowser.Result) {
        guard case let .service(nome, _, _, _) = risultato.endpoint else { return nil }
        var piattaforma: Piattaforma?
        if case let .bonjour(txt) = risultato.metadata, let valore = txt["p"] {
            piattaforma = Piattaforma(rawValue: valore)
        }
        self.init(id: nome, nome: nome, piattaforma: piattaforma, endpoint: risultato.endpoint)
    }
}

/// Cerca in rete locale i computer che pubblicano `_webcamlr._tcp` (funzione 1).
@Observable
@MainActor
final class CercaComputer {
    enum Stato: Equatable {
        case fermo
        case inCerca
        case permessoNegato
        case errore(String)
    }

    private(set) var computer: [ComputerTrovato] = []
    private(set) var stato: Stato = .fermo
    private var browser: NWBrowser?
    /// Wi-Fi diretto (0.11), solo come ripiego: tiene la radio occupata anche su un altro canale,
    /// e con la rete normale disponibile renderebbe la latenza meno stabile.
    private var browserDiretto: NWBrowser?
    private var sullaRete: [ComputerTrovato] = []
    private var diretti: [ComputerTrovato] = []
    private var compitoRipiego: Task<Void, Never>?

    func avvia() {
        guard browser == nil else { return }
        let ricerca = NWBrowser(for: .bonjourWithTXTRecord(type: Servizio.tipoBonjour, domain: nil), using: NWParameters())
        ricerca.stateUpdateHandler = { [weak self] nuovo in
            Task { @MainActor in self?.aggiorna(nuovo) }
        }
        ricerca.browseResultsChangedHandler = { [weak self] risultati, _ in
            let trovati = risultati.compactMap(ComputerTrovato.init(risultato:))
            Task { @MainActor in
                self?.sullaRete = trovati
                self?.unisci()
            }
        }
        ricerca.start(queue: .main)
        browser = ricerca
        stato = .inCerca
        // Se dopo qualche secondo sulla rete non c'è nessuno, si cerca anche con il Wi-Fi diretto.
        compitoRipiego?.cancel()
        compitoRipiego = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.browser != nil, self.sullaRete.isEmpty else { return }
            self.avviaDiretto()
        }
    }

    private func avviaDiretto() {
        guard browserDiretto == nil else { return }
        let parametri = NWParameters()
        parametri.includePeerToPeer = true
        let ricerca = NWBrowser(for: .bonjourWithTXTRecord(type: Servizio.tipoBonjour, domain: nil), using: parametri)
        ricerca.browseResultsChangedHandler = { [weak self] risultati, _ in
            let trovati = risultati.compactMap(ComputerTrovato.init(risultato:)).map { computer -> ComputerTrovato in
                var diretto = computer
                diretto.diretto = true
                return diretto
            }
            Task { @MainActor in
                self?.diretti = trovati
                self?.unisci()
            }
        }
        ricerca.start(queue: .main)
        browserDiretto = ricerca
    }

    /// Un computer che si vede anche sulla rete normale si usa da lì, non con il Wi-Fi diretto.
    private func unisci() {
        let nomiSullaRete = Set(sullaRete.map(\.nome))
        let prima = Set(computer.map(\.nome))
        computer = (sullaRete + diretti.filter { !nomiSullaRete.contains($0.nome) }).sorted { $0.nome < $1.nome }
        // 1.5: nel registro chi compare e chi sparisce, non ogni aggiornamento della ricerca.
        let dopo = Set(computer.map(\.nome))
        for nome in dopo.subtracting(prima).sorted() { RegistroCollegamento.scrivi("Trovato \(nome)") }
        for nome in prima.subtracting(dopo).sorted() { RegistroCollegamento.scrivi("Non vedo più \(nome)") }
    }

    func ferma() {
        compitoRipiego?.cancel()
        compitoRipiego = nil
        browser?.cancel()
        browser = nil
        browserDiretto?.cancel()
        browserDiretto = nil
        sullaRete = []
        diretti = []
        stato = .fermo
    }

    private func aggiorna(_ nuovo: NWBrowser.State) {
        switch nuovo {
        case .ready:
            stato = .inCerca
            // La ricerca funziona: il permesso «Rete locale» c'è (serve alla diagnosi, 1.3).
            StatoRete.condiviso.permessoNegato = false
        case .waiting(let errore), .failed(let errore):
            // -65570 = kDNSServiceErr_PolicyDenied: l'utente non ha concesso la rete locale.
            if case .dns(let codice) = errore, codice == -65570 {
                if stato != .permessoNegato { RegistroCollegamento.scrivi("Ricerca ferma: permesso «Rete locale» negato") }
                stato = .permessoNegato
                StatoRete.condiviso.permessoNegato = true
            } else {
                stato = .errore(errore.localizedDescription)
            }
            // Una ricerca fallita non riparte da sola: se ne avvia una nuova poco dopo.
            if case .failed = nuovo {
                browser?.cancel()
                browser = nil
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, self.browser == nil, self.stato != .fermo else { return }
                    self.avvia()
                }
            }
        default:
            break
        }
    }
}
