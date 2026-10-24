import CoreMotion
import Foundation
import Observation
import UIKit
import WebcamLRProtocollo

/// Le pause del video senza chiudere la sessione (protocollo, *Pausa intelligente*).
///
/// - P07 `faccia-in-giu`: l'iPhone appoggiato con lo schermo in giù (gravità z oltre 0,9 per più di un secondo)
///   mette in pausa; girato di nuovo (z sotto 0,7) riprende. La fotocamera resta accesa: la ripresa è immediata.
///   Si può spegnere nelle Impostazioni.
///
/// Decide solo il motivo: cosa fermare e come riprendere lo fa `SessioneTelefono` (`pausaCambiata`).
@Observable
@MainActor
final class GestorePausa {
    enum Chiave {
        static let facciaInGiu = "pausaFacciaInGiu"
    }

    /// L'iPhone è a faccia in giù da più di un secondo.
    private(set) var facciaInGiu = false

    /// Il motivo da mandare in `stato.pausa` (`MotiviPausa`), `nil` se il video va.
    var motivo: String? {
        if facciaInGiu { return MotiviPausa.facciaInGiu }
        return nil
    }

    /// Il motivo è cambiato: la sessione ferma o riprende il video.
    @ObservationIgnored var suCambio: (() -> Void)?

    @ObservationIgnored private var inFunzione = false
    @ObservationIgnored private var movimento: CMMotionManager?
    @ObservationIgnored private var giuDa: TimeInterval?
    @ObservationIgnored private var osservatoreImpostazioni: NSObjectProtocol?

    /// Di serie accesa.
    static var facciaInGiuAbilitata: Bool {
        UserDefaults.standard.object(forKey: Chiave.facciaInGiu) as? Bool ?? true
    }

    /// All'avvio della sessione.
    func avvia() {
        guard !inFunzione else { return }
        inFunzione = true
        aggiornaMovimento()
        osservatoreImpostazioni = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.aggiornaMovimento() }
        }
    }

    /// Alla fine della sessione: niente più sensori né richiami.
    func ferma() {
        guard inFunzione else { return }
        inFunzione = false
        if let osservatoreImpostazioni { NotificationCenter.default.removeObserver(osservatoreImpostazioni) }
        osservatoreImpostazioni = nil
        // In silenzio: la sessione si sta chiudendo, non c'è nulla da riprendere.
        facciaInGiu = false
        aggiornaMovimento()
    }

    // MARK: - Faccia in giù (P07)

    /// I sensori solo mentre la sessione va e la funzione è accesa; cinque letture al secondo bastano.
    private func aggiornaMovimento() {
        let serve = inFunzione && Self.facciaInGiuAbilitata
        if serve, movimento == nil {
            let nuovo = CMMotionManager()
            guard nuovo.isDeviceMotionAvailable else { return }
            nuovo.deviceMotionUpdateInterval = 0.2
            nuovo.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] dati, _ in
                guard let z = dati?.gravity.z else { return }
                Task { @MainActor in self?.gravita(z) }
            }
            movimento = nuovo
        } else if !serve, let attuale = movimento {
            attuale.stopDeviceMotionUpdates()
            movimento = nil
            giuDa = nil
            if facciaInGiu {
                facciaInGiu = false
                suCambio?()
            }
        }
    }

    /// z = +1 con lo schermo verso il basso, -1 steso a faccia in su.
    private func gravita(_ z: Double) {
        guard movimento != nil else { return }
        let adesso = ProcessInfo.processInfo.systemUptime
        if z > 0.9 {
            if giuDa == nil { giuDa = adesso }
            if !facciaInGiu, let inizio = giuDa, adesso - inizio >= 1 {
                facciaInGiu = true
                suCambio?()
            }
        } else {
            giuDa = nil
            if facciaInGiu && z < 0.7 {
                facciaInGiu = false
                suCambio?()
            }
        }
    }
}

extension Vibrazione {
    /// P07: il video si ferma (iPhone a faccia in giù): si sente anche senza guardare.
    static func pausa() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func ripresa() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
