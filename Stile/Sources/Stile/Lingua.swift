import Foundation

extension Bundle {
    /// Le traduzioni di Stile nella stessa lingua che il sistema ha scelto per l'app (P22).
    ///
    /// Con `Bundle.module` da solo il pacchetto sceglierebbe per conto suo: con il telefono in francese
    /// l'app (che ripiega sull'inglese) mostrerebbe l'inglese e i testi di Stile l'italiano, la lingua
    /// di partenza del pacchetto. Qui si segue l'app: inglese solo se l'app è in inglese, altrimenti
    /// italiano. Un'app che non ha ancora l'inglese (oggi il Mac) resta quindi tutta in italiano.
    static let stile: Bundle = {
        let linguaApp = Bundle.main.preferredLocalizations.first ?? "it"
        let lingua = linguaApp.hasPrefix("en") ? "en" : "it"
        guard let percorso = Bundle.module.path(forResource: lingua, ofType: "lproj"),
              let traduzioni = Bundle(path: percorso) else { return .module }
        return traduzioni
    }()
}
