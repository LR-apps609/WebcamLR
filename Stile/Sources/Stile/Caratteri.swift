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
