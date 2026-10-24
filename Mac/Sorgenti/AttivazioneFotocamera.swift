import Foundation
import Observation
import SystemExtensions

/// Chiede a macOS di attivare la webcam virtuale (funzione 11).
@Observable
@MainActor
final class AttivazioneFotocamera: NSObject {
    enum Stato: Equatable {
        case nonAttiva
        case inCorso
        case daApprovare
        case riavvioNecessario
        case attiva
        case errore(String)
    }

    static let identificativo = "it.lrapps.webcamlr.mac.fotocamera"

    private(set) var stato: Stato = .nonAttiva

    /// Falso quando l'app è costruita senza account sviluppatore a pagamento
    /// (project-senza-account.yml): la webcam virtuale non è dentro l'app.
    let disponibile: Bool = FileManager.default.fileExists(
        atPath: Bundle.main.bundleURL
            .appending(path: "Contents/Library/SystemExtensions/\(AttivazioneFotocamera.identificativo).systemextension")
            .path(percentEncoded: false)
    )

    func attiva() {
        stato = .inCorso
        let richiesta = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identificativo, queue: .main)
        richiesta.delegate = self
        OSSystemExtensionManager.shared.submitRequest(richiesta)
    }

    fileprivate func termina(_ nuovo: Stato) {
        stato = nuovo
    }

    nonisolated static func spiegazione(_ errore: Error) -> String {
        guard let errore = errore as? OSSystemExtensionError else { return generica }
        switch errore.code {
        case .unsupportedParentBundleLocation:
            return "Sposta WebcamLR nella cartella Applicazioni e riaprila."
        case .missingEntitlement:
            return "Manca il permesso per installare la webcam virtuale: serve l'account sviluppatore Apple a pagamento."
        case .extensionNotFound:
            return "La webcam virtuale non è dentro l'app: ricostruisci il progetto."
        case .codeSignatureInvalid, .validationFailed:
            return "Firma non valida: controlla il team in Strumenti/team.txt e ricostruisci."
        case .forbiddenBySystemPolicy:
            return "macOS ha bloccato l'estensione: controlla Impostazioni di Sistema › Privacy e sicurezza."
        default:
            return generica
        }
    }

    nonisolated private static let generica = "La webcam virtuale non si è attivata: riapri WebcamLR e riprova."
}

extension AttivazioneFotocamera: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in self.termina(.daApprovare) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let nuovo: Stato = result == .willCompleteAfterReboot ? .riavvioNecessario : .attiva
        Task { @MainActor in self.termina(nuovo) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let spiegazione = Self.spiegazione(error)
        Task { @MainActor in self.termina(.errore(spiegazione)) }
    }
}
