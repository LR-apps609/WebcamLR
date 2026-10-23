import Foundation
import Network
import Observation
import WebcamLRProtocollo

struct ComputerTrovato: Identifiable, Hashable {
    let id: String
    let nome: String
    let piattaforma: Piattaforma?
    let endpoint: NWEndpoint
}

extension ComputerTrovato {
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

    func avvia() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Servizio.tipoBonjour, domain: nil), using: NWParameters())
        browser.stateUpdateHandler = { [weak self] nuovo in
            Task { @MainActor in self?.aggiorna(nuovo) }
        }
        browser.browseResultsChangedHandler = { [weak self] risultati, _ in
            let trovati = risultati.compactMap(ComputerTrovato.init(risultato:)).sorted { $0.nome < $1.nome }
            Task { @MainActor in self?.computer = trovati }
        }
        browser.start(queue: .main)
        self.browser = browser
        stato = .inCerca
    }

    func ferma() {
        browser?.cancel()
        browser = nil
        stato = .fermo
    }

    private func aggiorna(_ nuovo: NWBrowser.State) {
        switch nuovo {
        case .ready:
            stato = .inCerca
        case .waiting(let errore), .failed(let errore):
            // -65570 = kDNSServiceErr_PolicyDenied: l'utente non ha concesso la rete locale.
            if case .dns(let codice) = errore, codice == -65570 {
                stato = .permessoNegato
            } else {
                stato = .errore(errore.localizedDescription)
            }
        default:
            break
        }
    }
}
