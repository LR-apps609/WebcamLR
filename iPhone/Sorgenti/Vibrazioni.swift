import UIKit

/// Vibrazioni leggere (round 2, novità 3): dicono cosa è successo senza guardare lo schermo.
@MainActor
enum Vibrazione {
    static func collegato() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func scollegato() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func cambioObiettivo() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func bloccoFuoco() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
