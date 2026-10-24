import CoreMotion
import Foundation
import Observation

/// Livella (round 2, novità 12): quanto il telefono è storto rispetto all'orizzonte.
/// Legge la gravità dieci volte al secondo sulla coda principale, solo quando la livella è accesa.
@Observable
final class Livella {
    /// Gradi dal dritto più vicino (in verticale o in orizzontale), da -45 a 45, a mezzi gradi.
    /// `nil` quando il telefono è steso sul tavolo e la livella non ha senso.
    private(set) var scostamento: Double?
    /// Si crea solo quando serve: SwiftUI può creare più volte questo oggetto.
    @ObservationIgnored private var movimento: CMMotionManager?

    /// Entro ±1° la linea diventa verde.
    var dritto: Bool {
        guard let scostamento else { return false }
        return abs(scostamento) <= 1
    }

    func avvia() {
        guard movimento == nil else { return }
        let nuovo = CMMotionManager()
        guard nuovo.isDeviceMotionAvailable else { return }
        nuovo.deviceMotionUpdateInterval = 1.0 / 10
        nuovo.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] dati, _ in
            guard let gravita = dati?.gravity else { return }
            self?.aggiorna(x: gravita.x, y: gravita.y)
        }
        movimento = nuovo
    }

    func ferma() {
        movimento?.stopDeviceMotionUpdates()
        movimento = nil
        scostamento = nil
    }

    private func aggiorna(x: Double, y: Double) {
        let nuovo: Double?
        if (x * x + y * y).squareRoot() < 0.5 {
            nuovo = nil
        } else {
            // 0° col telefono dritto in verticale, ±90° in orizzontale; positivo se ruotato in senso orario.
            let angolo = atan2(x, -y) * 180 / Double.pi
            var resto = angolo.truncatingRemainder(dividingBy: 90)
            if resto > 45 { resto -= 90 } else if resto < -45 { resto += 90 }
            nuovo = (resto * 2).rounded() / 2
        }
        // Si assegna solo se cambia, così la vista si ridisegna di rado.
        if nuovo != scostamento { scostamento = nuovo }
    }
}
