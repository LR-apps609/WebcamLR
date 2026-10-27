import Foundation

/// La lingua in cui macOS mostra WebcamLR (P22): italiano, la lingua di partenza, o inglese.
/// I testi stanno in Risorse/Localizable.xcstrings; qui solo ciò che il catalogo non fa da sé: i numeri.
enum Lingua {
    /// Vero quando macOS ha scelto l'inglese per l'app (lingua del Mac, o quella scelta per WebcamLR in
    /// Impostazioni di Sistema › Generali › Lingua e zona › Applicazioni).
    static let inglese: Bool = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true

    /// Decimali con la virgola in italiano («0,5×», come da glossario), con il punto in inglese («0.5×»).
    /// `testo` arriva con il punto (String(format:)); in italiano diventa virgola, come prima del P22.
    static func decimali(_ testo: String) -> String {
        inglese ? testo : testo.replacingOccurrences(of: ".", with: ",")
    }

    /// «1080p · 30 fps», «4K · 30 fps»: uguale in tutte le lingue.
    static func risoluzione(altezza: Int, fps: Int) -> String {
        String(format: "%@ · %d fps", nomeRisoluzione(altezza: altezza), fps)
    }

    /// «720p», «1080p», «4K»: gli stessi nomi del telefono (prova 2: il Mac scriveva «2160p»).
    /// `altezza` è il lato corto.
    static func nomeRisoluzione(altezza: Int) -> String {
        altezza >= 2160 ? "4K" : "\(altezza)p"
    }

    /// Per le migliaia: «20.000» in italiano, «20,000» in inglese.
    static var formatoNumeri: Locale {
        Locale(identifier: inglese ? "en_US" : "it_IT")
    }
}
