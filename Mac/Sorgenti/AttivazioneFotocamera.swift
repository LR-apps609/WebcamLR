import AppKit
import AVFoundation
import Foundation
import Observation
import SystemExtensions

/// Chiede a macOS di attivare (o rimuovere) la webcam virtuale (funzione 11).
/// Compila anche senza account a pagamento: lì `disponibile` è falso e non parte nessuna richiesta.
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

    private enum Richiesta {
        case controllo
        case attivazione
        case rimozione
    }

    static let identificativo = "it.lrapps.webcamlr.mac.fotocamera"

    private(set) var stato: Stato = .nonAttiva
    /// Passo 7 (mac.md 15): macOS nega la fotocamera a WebcamLR, e senza permesso le immagini non entrano nella webcam
    /// virtuale (le app vedono solo l'attesa). Riletto ogni volta che WebcamLR torna in primo piano.
    private(set) var fotocameraNegata = false
    @ObservationIgnored private var osservatoreAttivazione: NSObjectProtocol?
    /// Le richieste in corso, per sapere a cosa risponde macOS. Tenute in vita finché non finiscono,
    /// così l'identificativo non passa a una richiesta nuova.
    @ObservationIgnored private var richieste: [ObjectIdentifier: (richiesta: OSSystemExtensionRequest, tipo: Richiesta)] = [:]

    /// Falso quando l'app è costruita senza account sviluppatore a pagamento
    /// (project-senza-account.yml): la webcam virtuale non è dentro l'app.
    let disponibile: Bool = FileManager.default.fileExists(
        atPath: Bundle.main.bundleURL
            .appending(path: "Contents/Library/SystemExtensions/\(AttivazioneFotocamera.identificativo).systemextension")
            .path(percentEncoded: false)
    )

    /// macOS attiva le estensioni di sistema solo da un'app nella cartella Applicazioni.
    static var inApplicazioni: Bool {
        Bundle.main.bundleURL.path(percentEncoded: false).hasPrefix("/Applications/")
    }

    /// Dove si approva la webcam virtuale, con le parole delle Impostazioni di Sistema.
    static var doveApprovare: String {
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) {
            return String(localized: "Impostazioni di Sistema › Generali › Elementi di login ed estensioni › Estensioni videocamera (ⓘ): accendi WebcamLR e premi Fine.")
        }
        return String(localized: "Impostazioni di Sistema › Privacy e sicurezza: in basso premi «Consenti» accanto a WebcamLR.")
    }

    override init() {
        super.init()
        // Il permesso della fotocamera si cambia in Impostazioni di Sistema: al ritorno nell'app si rilegge.
        controllaPermesso()
        osservatoreAttivazione = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controllaPermesso()
            }
        }
        // All'apertura: se la webcam virtuale è già attiva lo si mostra subito, e si chiede a macOS
        // di installare la versione dentro quest'app (dopo un aggiornamento) senza domande all'utente.
        guard disponibile, Self.inApplicazioni else { return }
        invia(OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: Self.identificativo, queue: .main), tipo: .controllo)
    }

    func attiva() {
        guard Self.inApplicazioni else {
            stato = .errore(String(localized: "Sposta WebcamLR nella cartella Applicazioni e riaprila: macOS attiva la webcam virtuale solo da lì."))
            return
        }
        stato = .inCorso
        invia(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identificativo, queue: .main), tipo: .attivazione)
    }

    /// Da fare prima di cestinare l'app, altrimenti «WebcamLR» può restare negli elenchi delle videocamere.
    func rimuovi() {
        stato = .inCorso
        invia(OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.identificativo, queue: .main), tipo: .rimozione)
    }

    /// Solo con la webcam virtuale dentro l'app (account a pagamento): senza, il permesso non serve a niente.
    func controllaPermesso() {
        let permesso = AVCaptureDevice.authorizationStatus(for: .video)
        let negata = disponibile && (permesso == .denied || permesso == .restricted)
        if negata != fotocameraNegata { fotocameraNegata = negata }
    }

    /// M15: «Ricontrolla» dopo l'approvazione in Impostazioni di Sistema, se lo stato non è cambiato da solo.
    func ricontrolla() {
        guard disponibile, Self.inApplicazioni else { return }
        invia(OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: Self.identificativo, queue: .main), tipo: .controllo)
    }

    /// Apre il pannello in cui si approva l'estensione.
    func apriImpostazioni() {
        let nuove = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
        let indirizzo = nuove ? "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
                              : "x-apple.systempreferences:com.apple.preference.security?General"
        if let url = URL(string: indirizzo) {
            NSWorkspace.shared.open(url)
        }
    }

    private func invia(_ richiesta: OSSystemExtensionRequest, tipo: Richiesta) {
        richieste[ObjectIdentifier(richiesta)] = (richiesta, tipo)
        richiesta.delegate = self
        OSSystemExtensionManager.shared.submitRequest(richiesta)
    }

    fileprivate func trovate(_ attive: Bool, daApprovare: Bool) {
        if attive {
            stato = .attiva
            // Stesso numero di build: macOS risponde subito. Numero diverso: sostituisce la vecchia versione.
            invia(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identificativo, queue: .main), tipo: .attivazione)
        } else if daApprovare {
            // Una richiesta di un'apertura precedente aspetta ancora: se ne fa una nuova,
            // così quando l'utente approva l'app lo viene a sapere.
            stato = .daApprovare
            invia(OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.identificativo, queue: .main), tipo: .attivazione)
        } else if stato == .daApprovare {
            // «Ricontrolla» e macOS non la conosce più (approvazione rifiutata o tolta): si torna ad «Attiva».
            stato = .nonAttiva
        }
    }

    fileprivate func serveApprovazione() {
        // Le Impostazioni si aprono da sole solo dopo «Attiva la webcam virtuale», non all'apertura dell'app.
        let dalPulsante = stato == .inCorso
        stato = .daApprovare
        if dalPulsante { apriImpostazioni() }
    }

    fileprivate func finita(_ risultato: OSSystemExtensionRequest.Result, richiesta: ObjectIdentifier) {
        let tipo = richieste.removeValue(forKey: richiesta)?.tipo
        switch tipo {
        case .controllo, nil:
            break
        case .attivazione:
            stato = risultato == .willCompleteAfterReboot ? .riavvioNecessario : .attiva
        case .rimozione:
            stato = risultato == .willCompleteAfterReboot ? .riavvioNecessario : .nonAttiva
        }
    }

    fileprivate func fallita(_ spiegazione: String, richiesta: ObjectIdentifier) {
        let tipo = richieste.removeValue(forKey: richiesta)?.tipo
        // Il controllo all'apertura non disturba: se non riesce, resta il pulsante «Attiva».
        guard tipo != .controllo else { return }
        stato = .errore(spiegazione)
    }

    nonisolated static func spiegazione(_ errore: Error) -> String {
        guard let errore = errore as? OSSystemExtensionError else { return generica }
        switch errore.code {
        case .unsupportedParentBundleLocation:
            return String(localized: "Sposta WebcamLR nella cartella Applicazioni e riaprila.")
        case .missingEntitlement:
            return String(localized: "Questa versione dell'app non può installare la webcam virtuale: scarica WebcamLR dal sito.")
        case .extensionNotFound:
            return String(localized: "La webcam virtuale non è dentro l'app: ricostruisci il progetto.")
        case .codeSignatureInvalid, .validationFailed:
            return String(localized: "Firma non valida: controlla il team in Strumenti/team.txt e ricostruisci.")
        case .forbiddenBySystemPolicy:
            return String(localized: "macOS ha bloccato l'estensione: controlla Impostazioni di Sistema › Privacy e sicurezza.")
        case .requestCanceled:
            return String(localized: "Richiesta annullata: premi di nuovo «Attiva la webcam virtuale».")
        case .requestSuperseded:
            return String(localized: "Un'altra richiesta ha preso il posto di questa: riprova tra qualche secondo.")
        case .authorizationRequired:
            return String(localized: "Serve la password di un amministratore del Mac: riprova e inseriscila quando macOS la chiede.")
        default:
            return generica
        }
    }

    nonisolated private static let generica = String(localized: "La webcam virtuale non si è attivata: riapri WebcamLR e riprova.")
}

// Le risposte arrivano sulla coda principale (queue: .main nelle richieste): si gestiscono subito,
// nell'ordine in cui arrivano.
extension AttivazioneFotocamera: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        MainActor.assumeIsolated { self.serveApprovazione() }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let id = ObjectIdentifier(request)
        MainActor.assumeIsolated { self.finita(result, richiesta: id) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let id = ObjectIdentifier(request)
        let spiegazione = Self.spiegazione(error)
        MainActor.assumeIsolated { self.fallita(spiegazione, richiesta: id) }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        let attive = properties.contains { $0.isEnabled && !$0.isUninstalling }
        let daApprovare = properties.contains { $0.isAwaitingUserApproval && !$0.isUninstalling }
        MainActor.assumeIsolated { self.trovate(attive, daApprovare: daApprovare) }
    }
}
