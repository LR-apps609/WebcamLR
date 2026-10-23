import Foundation
import Network
import Observation
import WebcamLRProtocollo

/// Pubblica `_webcamlr._tcp` in rete locale, così i telefoni trovano il Mac (funzione 1).
@Observable
@MainActor
final class AnnuncioInRete {
    enum Stato: Equatable {
        case fermo
        case visibile(porta: UInt16)
        case errore(String)
    }

    private(set) var stato: Stato = .fermo
    private var listener: NWListener?

    func avvia(porta: NWEndpoint.Port? = NWEndpoint.Port(rawValue: Servizio.portaPredefinita)) {
        guard listener == nil else { return }
        do {
            let parametri = NWParameters.tcp
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

            listener.stateUpdateHandler = { [weak self] nuovo in
                Task { @MainActor in self?.aggiorna(nuovo, portaFissa: porta != nil) }
            }
            // Round 1: qui arriverà la sessione con il telefono (ciao, benvenuto, video).
            listener.newConnectionHandler = { connessione in
                connessione.cancel()
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            stato = .errore(error.localizedDescription)
        }
    }

    func ferma() {
        listener?.cancel()
        listener = nil
        stato = .fermo
    }

    private func aggiorna(_ nuovo: NWListener.State, portaFissa: Bool) {
        switch nuovo {
        case .ready:
            stato = .visibile(porta: listener?.port?.rawValue ?? 0)
        case .failed(let errore):
            listener?.cancel()
            listener = nil
            if portaFissa, case .posix(.EADDRINUSE) = errore {
                // Porta 52740 occupata: ne usa una qualsiasi, che viaggia nell'annuncio.
                avvia(porta: nil)
            } else {
                stato = .errore(errore.localizedDescription)
            }
        default:
            break
        }
    }
}
