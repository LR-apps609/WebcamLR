import SwiftUI

/// Colori della famiglia WebcamLR, uguali in tutte le app (bozza grafica, «Fondamenta»).
public enum Tema {
    public static let fondo = Color(esadecimale: 0x0F1413)
    public static let barraLaterale = Color(esadecimale: 0x141B1A)
    public static let pannello = Color(esadecimale: 0x1B2321)
    public static let pannelloScuro = Color(esadecimale: 0x16201F)
    public static let pannelloChiaro = Color(esadecimale: 0x232D2A)
    public static let linea = Color(esadecimale: 0x2F3A37)
    public static let lineaTenue = Color(esadecimale: 0x2A3431)
    public static let bordo = Color(esadecimale: 0x3C4844)
    public static let testo = Color(esadecimale: 0xE3E8E5)
    public static let testoSecondario = Color(esadecimale: 0x97A39F)
    public static let testoChiaro = Color(esadecimale: 0xC2CCC8)
    public static let testoTenue = Color(esadecimale: 0xB3BDB9)

    /// Azioni e selezione.
    public static let ciano = Color(esadecimale: 0x6CBCC4)
    public static let cianoChiaro = Color(esadecimale: 0x8FD0D6)
    public static let cianoTenue = Color(esadecimale: 0x1D3436)

    /// Solo quando il video è davvero in onda o si registra.
    public static let tally = Color(esadecimale: 0xEF5A4C)
    public static let tallyPieno = Color(esadecimale: 0xC8372D)
    public static let tallyTenue = Color(esadecimale: 0x3A1916)
    public static let tallyTesto = Color(esadecimale: 0xFFB4AB)

    /// Avvisi.
    public static let ambra = Color(esadecimale: 0xE2A54B)
    public static let ambraTenue = Color(esadecimale: 0x3A2E1A)
    public static let ambraTesto = Color(esadecimale: 0xF0C27A)

    /// Collegato.
    public static let verde = Color(esadecimale: 0x6FC28C)
}

extension Color {
    public init(esadecimale: UInt32) {
        self.init(
            red: Double(esadecimale >> 16 & 0xFF) / 255,
            green: Double(esadecimale >> 8 & 0xFF) / 255,
            blue: Double(esadecimale & 0xFF) / 255
        )
    }
}
