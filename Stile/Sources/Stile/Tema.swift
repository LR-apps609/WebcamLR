import SwiftUI

/// Colori della famiglia WebcamLR, uguali in tutte le app: l'identità di LR Apps dal logo del 25 ottobre
/// (Strumenti/genera_icone.py). Fondo verde scuro, superfici e accenti nei toni di salvia, testo quasi bianco
/// appena verde. Il corallo del logo è il colore del tally: solo «in onda» e registrazione.
///
/// I colori (`Tema.fondo`, `Tema.accento`…) stanno in Token.swift, generato da Strumenti/genera_token.py da
/// Documenti/token.json insieme a Windows, Android e al sito: si cambiano solo lì (tabella in Documenti/Stile.md).
/// I nomi di prima `ciano`, `cianoChiaro`, `cianoTenue` non ci sono più: si scrive `accento`, `accentoChiaro`, `accentoTenue`.
///
/// Contrasti misurati (WCAG, testo normale ≥ 4,5:1) su `pannelloChiaro` #22352F, la superficie più chiara
/// con testo sopra: `testo` 11,0 · `testoTenue` 7,0 · `testoSecondario` 5,7 · `accento` 7,5 ·
/// `verde` 6,6 · `ambra` 6,6 · `tally` 4,5. Bianco su `tallyPieno` 5,2.
public enum Tema {}

extension Color {
    public init(esadecimale: UInt32) {
        self.init(
            red: Double(esadecimale >> 16 & 0xFF) / 255,
            green: Double(esadecimale >> 8 & 0xFF) / 255,
            blue: Double(esadecimale & 0xFF) / 255
        )
    }
}
