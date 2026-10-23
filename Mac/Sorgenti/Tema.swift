import SwiftUI

/// Colori della famiglia WebcamLR: gli stessi dell'app iPhone e della bozza grafica.
enum Tema {
    static let fondo = Color(esadecimale: 0x0F1413)
    static let barraLaterale = Color(esadecimale: 0x141B1A)
    static let pannello = Color(esadecimale: 0x1B2321)
    static let linea = Color(esadecimale: 0x2A3431)
    static let testo = Color(esadecimale: 0xE3E8E5)
    static let testoSecondario = Color(esadecimale: 0x97A39F)
    /// Azioni e selezione.
    static let ciano = Color(esadecimale: 0x6CBCC4)
    /// Solo quando il video è davvero in onda o si registra.
    static let tally = Color(esadecimale: 0xEF5A4C)
    static let ambra = Color(esadecimale: 0xE2A54B)
    static let verde = Color(esadecimale: 0x6FC28C)

    static let numeri = Font.system(size: 12, design: .monospaced)
}

extension Color {
    init(esadecimale: UInt32) {
        self.init(
            red: Double(esadecimale >> 16 & 0xFF) / 255,
            green: Double(esadecimale >> 8 & 0xFF) / 255,
            blue: Double(esadecimale & 0xFF) / 255
        )
    }
}
