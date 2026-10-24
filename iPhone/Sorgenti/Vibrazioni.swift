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

    /// Il computer chiede di confermare il collegamento (0.10): si guarda il codice sui due schermi.
    static func richiestaConferma() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 1.10: il QR code è stato letto e il collegamento parte.
    static func qrLetto() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func cambioObiettivo() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func bloccoFuoco() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
