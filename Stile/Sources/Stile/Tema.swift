import SwiftUI

/// Colori della famiglia WebcamLR, uguali in tutte le app: l'identità di LR Apps dal logo del 25 ottobre
/// (Strumenti/genera_icone.py). Fondo verde scuro, superfici e accenti nei toni di salvia, testo quasi bianco
/// appena verde. Il corallo del logo è il colore del tally: solo «in onda» e registrazione.
/// Windows ha gli stessi valori in App.xaml (da allineare quando riprende).
///
/// Contrasti misurati (WCAG, testo normale ≥ 4,5:1) su `pannelloChiaro` #22352F, la superficie più chiara
/// con testo sopra: `testo` 11,0 · `testoTenue` 7,0 · `testoSecondario` 5,7 · `ciano` (accento azioni) 7,5 ·
/// `verde` 6,6 · `ambra` 6,6 · `tally` 4,5. Bianco su `tallyPieno` 5,2.
public enum Tema {
    /// La sfumatura del logo, dall'angolo in alto a sinistra a quello in basso a destra.
    public static let sfumaturaChiara = Color(esadecimale: 0x30453E)
    public static let sfumaturaScura = Color(esadecimale: 0x0D1B18)

    /// Fondo della finestra.
    public static let fondo = Color(esadecimale: 0x13211D)
    /// Colonne laterali.
    public static let barraLaterale = Color(esadecimale: 0x172824)
    public static let pannello = Color(esadecimale: 0x1A2B26)
    public static let pannelloScuro = Color(esadecimale: 0x15241F)
    public static let pannelloChiaro = Color(esadecimale: 0x22352F)
    public static let linea = Color(esadecimale: 0x2E443D)
    public static let lineaTenue = Color(esadecimale: 0x283C36)
    public static let bordo = Color(esadecimale: 0x3A524A)
    public static let testo = Color(esadecimale: 0xE6EEEA)
    /// Testo secondario, in salvia.
    public static let testoSecondario = Color(esadecimale: 0x9DB0A7)
    public static let testoChiaro = Color(esadecimale: 0xC9D5CF)
    public static let testoTenue = Color(esadecimale: 0xB4C2BB)

    /// I toni di salvia dei quadratini del logo, per superfici e segni (non per il testo piccolo).
    public static let salvia = Color(esadecimale: 0x8FA199)
    public static let salviaChiara = Color(esadecimale: 0xB2BFB7)
    public static let salviaScura = Color(esadecimale: 0x627A71)
    public static let salviaTenue = Color(esadecimale: 0xACBAB2)

    /// Accento di azioni e selezione: menta salvia chiara (7,5:1 su `pannelloChiaro`).
    /// Il nome «ciano» resta per compatibilità con il codice di iPhone e Mac: il colore non è più ciano.
    public static let ciano = Color(esadecimale: 0x9FD0B6)
    /// Accento più chiaro, per il testo di un elemento scelto.
    public static let cianoChiaro = Color(esadecimale: 0xB9E2CB)
    /// Fondo di un elemento scelto.
    public static let cianoTenue = Color(esadecimale: 0x1F3D33)
    /// Lo stesso accento con il nome nuovo, per il codice scritto da qui in avanti.
    public static var accento: Color { ciano }
    public static var accentoChiaro: Color { cianoChiaro }
    public static var accentoTenue: Color { cianoTenue }

    /// Il corallo del logo: solo quando il video è davvero in onda o si registra.
    public static let tally = Color(esadecimale: 0xE67A67)
    /// Fondo pieno della pillola «IN ONDA», con il testo bianco sopra.
    public static let tallyPieno = Color(esadecimale: 0xB84A3A)
    public static let tallyTenue = Color(esadecimale: 0x3A221D)
    public static let tallyTesto = Color(esadecimale: 0xF6B9AD)

    /// Avvisi, in un'ambra calda che sta bene con il verde.
    public static let ambra = Color(esadecimale: 0xE3B162)
    public static let ambraTenue = Color(esadecimale: 0x38301E)
    public static let ambraTesto = Color(esadecimale: 0xF0CD8C)

    /// Collegato: verde salvia, mai rosso.
    public static let verde = Color(esadecimale: 0x86C79C)
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
