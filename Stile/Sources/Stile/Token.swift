// File generato da Strumenti/genera_token.py da Documenti/token.json: non modificarlo a mano.
// Valori attivi: «beta4». Descrizione e regole in Documenti/Stile.md.

import SwiftUI

extension Tema {
    /// Sfumatura del logo, angolo in alto a sinistra.
    public static let sfumaturaChiara = Color(esadecimale: 0x30453E)
    /// Sfumatura del logo, angolo in basso a destra; base dei veli.
    public static let sfumaturaScura = Color(esadecimale: 0x0D1B18)
    /// Fondo della finestra (gradino 1 delle superfici).
    public static let fondo = Color(esadecimale: 0x13211D)
    /// Colonne laterali (gradino 2).
    public static let barraLaterale = Color(esadecimale: 0x1B2E28)
    /// Pannelli (gradino 3).
    public static let pannello = Color(esadecimale: 0x243A33)
    /// Pannello incassato.
    public static let pannelloScuro = Color(esadecimale: 0x15241F)
    /// Pannello rialzato (gradino 4); la superficie più chiara con testo sopra.
    public static let pannelloChiaro = Color(esadecimale: 0x2E4740)
    /// Separatori e bordi leggeri.
    public static let linea = Color(esadecimale: 0x2E443D)
    /// Separatori più deboli.
    public static let lineaTenue = Color(esadecimale: 0x283C36)
    /// Bordi di capsule e contorni.
    public static let bordo = Color(esadecimale: 0x3A524A)
    /// Testo principale, quasi bianco appena verde.
    public static let testo = Color(esadecimale: 0xE6EEEA)
    /// Testo secondario, in salvia.
    public static let testoSecondario = Color(esadecimale: 0x9DB0A7)
    /// Testo chiaro.
    public static let testoChiaro = Color(esadecimale: 0xC9D5CF)
    /// Testo tenue.
    public static let testoTenue = Color(esadecimale: 0xB4C2BB)
    /// Salvia del logo, per superfici e segni (non testo piccolo).
    public static let salvia = Color(esadecimale: 0x8FA199)
    /// Salvia chiara del logo.
    public static let salviaChiara = Color(esadecimale: 0xB2BFB7)
    /// Salvia scura del logo.
    public static let salviaScura = Color(esadecimale: 0x627A71)
    /// Salvia tenue del logo.
    public static let salviaTenue = Color(esadecimale: 0xACBAB2)
    /// Azioni e selezione: menta salvia chiara.
    public static let accento = Color(esadecimale: 0x9FD0B6)
    /// Testo di un elemento scelto.
    public static let accentoChiaro = Color(esadecimale: 0xB9E2CB)
    /// Fondo di un elemento scelto.
    public static let accentoTenue = Color(esadecimale: 0x1F3D33)
    /// Corallo del logo: solo «in onda» e registrazione.
    public static let tally = Color(esadecimale: 0xE67A67)
    /// Fondo pieno della pillola IN ONDA, testo bianco sopra.
    public static let tallyPieno = Color(esadecimale: 0xB84A3A)
    /// Fondo tenue del tally.
    public static let tallyTenue = Color(esadecimale: 0x3A221D)
    /// Testo sul fondo tenue del tally.
    public static let tallyTesto = Color(esadecimale: 0xF6B9AD)
    /// Avvisi.
    public static let ambra = Color(esadecimale: 0xE3B162)
    /// Fondo tenue degli avvisi.
    public static let ambraTenue = Color(esadecimale: 0x38301E)
    /// Testo sul fondo tenue degli avvisi.
    public static let ambraTesto = Color(esadecimale: 0xF0CD8C)
    /// Collegato: verde salvia, mai rosso.
    public static let verde = Color(esadecimale: 0x86C79C)

    // Contorni dei controlli: nuovi nomi, oggi con il valore di `linea` (la beta 4 li porta a 3:1).
    /// Contorno di pulsanti e campi su fondo e pannello (oggi è `linea`; beta 4 ≥ 3:1).
    public static let contornoControllo = Color(esadecimale: 0x6E877D)
    /// Contorno dei controlli su pannelloChiaro (oggi è `linea`).
    public static let contornoSuRialzato = Color(esadecimale: 0x7A9389)
    /// Contorno dei controlli sopra il video (oggi è `linea`).
    public static let contornoSuVideo = Color(esadecimale: 0xC9D5CF)
}

/// Spazi tra gli elementi, in punti: 4 · 8 · 12 · 16 · 24 · 32.
public enum Spazi {
    public static let minimo: CGFloat = 4
    public static let stretto: CGFloat = 8
    public static let piccolo: CGFloat = 12
    public static let medio: CGFloat = 16
    public static let largo: CGFloat = 24
    public static let ampio: CGFloat = 32
}

/// Raggi degli angoli, in punti. `capsula` su un quadrato fa il cerchio: SwiftUI limita il raggio a metà del lato corto.
public enum Raggi {
    /// Chip, segni.
    public static let piccolo: CGFloat = 6
    /// Pulsanti, campi.
    public static let controllo: CGFloat = 10
    /// Pannelli, fogli, avvisi.
    public static let pannello: CGFloat = 16
    /// Pillole; su un quadrato fa il cerchio (ogni sistema limita il raggio a metà del lato corto).
    public static let capsula: CGFloat = 999
}

/// Opacità comuni.
public enum Opacita {
    /// Controllo spento, su tutto e mai doppia.
    public static let spento: Double = 0.45
}

/// Veli sopra il video o sotto un foglio: `sfumaturaScura` con l'opacità del livello.
public enum Veli {
    public static let lieve: Double = 0.6
    public static let medio: Double = 0.8
    public static let forte: Double = 0.92
    public static let coloreLieve = Tema.sfumaturaScura.opacity(0.6)
    public static let coloreMedio = Tema.sfumaturaScura.opacity(0.8)
    public static let coloreForte = Tema.sfumaturaScura.opacity(0.92)
}

/// Gli stili di testo con nome. Misure: Mac e iPhone dalla tabella; crescono con Dynamic Type (`relativeTo:`).
/// Uso: `Text("IN ONDA").stileTesto(.statoGrande)`, oppure solo il carattere con `StileTesto.corpo.font`.
public enum StileTesto: CaseIterable {
    /// IN ONDA da lontano (schermo oscurato, vista pulita).
    case statoGrande
    /// Titolo di una schermata o di un foglio.
    case titoloGrande
    /// Titolo di un pannello o di un avviso.
    case titolo
    /// Etichetta di sezione.
    case sezione
    /// Nome di un pulsante o di un comando.
    case comando
    /// Testo normale.
    case corpo
    /// Note e spiegazioni sotto un controllo.
    case nota
    /// Numeri tecnici: «38 ms · 1080p30».
    case numeri
    /// Codice di conferma: cifre a spaziatura fissa, uguali su ogni piattaforma.
    case codice

    /// Nome PostScript del carattere (registrato da `Caratteri.registra()`).
    public var nomeCarattere: String {
        switch self {
        case .statoGrande: return "BarlowCondensed-Bold"
        case .titoloGrande: return "BarlowCondensed-Bold"
        case .titolo: return "BarlowCondensed-Bold"
        case .sezione: return "BarlowCondensed-SemiBold"
        case .comando: return "Barlow-SemiBold"
        case .corpo: return "Barlow-Regular"
        case .nota: return "Barlow-Regular"
        case .numeri: return "IBMPlexMono-Regular"
        case .codice: return "IBMPlexMono-Medium"
        }
    }

    /// Misura di partenza in punti (Mac sul Mac, telefono su iPhone).
    public var misura: CGFloat {
        switch self {
        case .statoGrande: return 56
        case .titoloGrande: return 28
        case .titolo: return 20
        case .sezione: return 13
        case .comando:
            #if os(macOS)
            return 14
            #else
            return 16
            #endif
        case .corpo:
            #if os(macOS)
            return 13
            #else
            return 16
            #endif
        case .nota:
            #if os(macOS)
            return 12
            #else
            return 13
            #endif
        case .numeri: return 12
        case .codice: return 46
        }
    }

    /// Lo stile di sistema con cui cresce per Dynamic Type.
    public var relativoA: Font.TextStyle {
        switch self {
        case .statoGrande: return .largeTitle
        case .titoloGrande: return .title
        case .titolo: return .title3
        case .sezione: return .caption
        case .comando: return .callout
        case .corpo: return .body
        case .nota: return .footnote
        case .numeri: return .caption
        case .codice: return .largeTitle
        }
    }

    /// Spaziatura tra le lettere, in punti.
    public var spaziatura: CGFloat {
        switch self {
        case .sezione: return 1.1
        default: return 0
        }
    }

    /// Vero se lo stile si scrive in maiuscolo.
    public var maiuscolo: Bool {
        switch self {
        case .sezione: return true
        default: return false
        }
    }

    public var font: Font {
        .custom(nomeCarattere, size: misura, relativeTo: relativoA)
    }
}

extension View {
    /// Carattere, spaziatura e maiuscolo di uno degli stili di testo.
    public func stileTesto(_ stile: StileTesto) -> some View {
        font(stile.font)
            .tracking(stile.spaziatura)
            .textCase(stile.maiuscolo ? Text.Case.uppercase : nil)
    }
}
