import CoreText
import Foundation
import SwiftUI

/// Barlow Condensed (titoli, etichette di stato), Barlow (testo) e IBM Plex Mono (numeri tecnici),
/// tutti con licenza SIL Open Font License (file OFL-*.txt nella cartella Caratteri; Barlow e Barlow Condensed
/// sono della stessa famiglia e hanno la stessa licenza).
public enum Caratteri {
    private static let file = [
        "BarlowCondensed-Bold",
        "BarlowCondensed-SemiBold",
        "Barlow-Regular",
        "Barlow-Medium",
        "Barlow-SemiBold",
        "IBMPlexMono-Regular",
        "IBMPlexMono-Medium"
    ]

    /// Da chiamare una volta all'avvio dell'app, prima di mostrare qualsiasi testo.
    public static func registra() {
        for nome in file {
            guard let url = Bundle.module.url(forResource: nome, withExtension: "ttf", subdirectory: "Caratteri") else {
                assertionFailure("Carattere mancante: \(nome)")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// I sette file di carattere con il nome della tabella (`caratteri` in Documenti/token.json). Servono quando uno stile
/// di testo va scritto con un altro peso della stessa famiglia: la misura resta quella dello stile.
public enum Carattere: String, CaseIterable, Sendable {
    /// Barlow Condensed Bold.
    case titoli = "BarlowCondensed-Bold"
    /// Barlow Condensed SemiBold.
    case etichette = "BarlowCondensed-SemiBold"
    /// Barlow Regular.
    case corpo = "Barlow-Regular"
    /// Barlow Medium.
    case corpoEvidente = "Barlow-Medium"
    /// Barlow SemiBold.
    case corpoForte = "Barlow-SemiBold"
    /// IBM Plex Mono Regular.
    case numeri = "IBMPlexMono-Regular"
    /// IBM Plex Mono Medium.
    case numeriEvidenti = "IBMPlexMono-Medium"
}

extension StileTesto {
    /// Lo stile con un altro carattere (per esempio `corpo` in Barlow Medium): stessa misura e stessa crescita con
    /// Dynamic Type.
    public func font(_ carattere: Carattere) -> Font {
        .custom(carattere.rawValue, size: misura, relativeTo: relativoA)
    }
}

extension Font {
    /// Uno degli otto stili di testo: `.font(.stile(.corpo))`.
    public static func stile(_ stile: StileTesto) -> Font {
        stile.font
    }

    /// Uno stile di testo con un altro carattere: `.font(.stile(.corpo, .corpoEvidente))`.
    public static func stile(_ stile: StileTesto, _ carattere: Carattere) -> Font {
        stile.font(carattere)
    }
}

// Le funzioni qui sotto prendono una misura scritta a mano: restano solo per ciò che sta fuori dalla scala dei
// testi (il conto alla rovescia della foto, il gobbo, il marchio, i disegni della presentazione). Tutto il resto
// usa `.stile(_:)` o `.stileTesto(_:)` (Documenti/Stile.md).
extension Font {
    /// Titoli grandi, come «Scegli il computer».
    public static func titolo(_ dimensione: CGFloat) -> Font {
        .custom("BarlowCondensed-Bold", size: dimensione)
    }

    /// Etichette in maiuscolo e stati, come «IN ONDA» o «VIDEO».
    public static func etichetta(_ dimensione: CGFloat) -> Font {
        .custom("BarlowCondensed-SemiBold", size: dimensione)
    }

    /// Testo normale in Barlow, come le righe dei pannelli del Mac.
    public static func corpo(_ dimensione: CGFloat = 13) -> Font {
        .custom("Barlow-Regular", size: dimensione)
    }

    /// Testo in evidenza in Barlow, come il nome di un telefono o di un pulsante.
    public static func corpoEvidente(_ dimensione: CGFloat = 13) -> Font {
        .custom("Barlow-Medium", size: dimensione)
    }

    /// Testo forte in Barlow, come il nome di un profilo scelto.
    public static func corpoForte(_ dimensione: CGFloat = 13) -> Font {
        .custom("Barlow-SemiBold", size: dimensione)
    }

    /// Numeri tecnici, come un timecode: «38 ms · 1080p30».
    public static func numeri(_ dimensione: CGFloat = 12) -> Font {
        .custom("IBMPlexMono-Regular", size: dimensione)
    }

    public static func numeriEvidenti(_ dimensione: CGFloat = 12) -> Font {
        .custom("IBMPlexMono-Medium", size: dimensione)
    }
}
