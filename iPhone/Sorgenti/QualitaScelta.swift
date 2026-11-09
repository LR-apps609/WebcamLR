import Foundation
import WebcamLRProtocollo

/// Qualità 15 (Documenti/Protocollo.md, «Qualità a scelta»): la qualità del flusso la sceglie il computer con
/// `comando.qualita`. Il bitrate di Alta e Massima lo fa `Codificatore`; qui la risoluzione di Massima, che
/// `SessioneTelefono.formatoEffettivo` mette al posto di quella chiesta con `formato`.
enum QualitaScelta {
    /// Il formato di «Massima» tra `formati` (dell'obiettivo verso cui si va, già con i limiti della versione
    /// gratuita): quello con più pixel e, a parità, con più fps. In orizzontale, come i formati della fotocamera.
    /// `nil` se l'obiettivo non dichiara formati: allora vale il formato chiesto, come in Auto.
    static func formatoMassimo(_ formati: [FormatoSupportato]) -> (larghezza: Int32, altezza: Int32, fps: Int)? {
        let migliore = formati.filter { $0.fpsMassimo > 0 }.max { a, b in
            let (pixelA, pixelB) = (a.larghezza * a.altezza, b.larghezza * b.altezza)
            return pixelA != pixelB ? pixelA < pixelB : a.fpsMassimo < b.fpsMassimo
        }
        guard let migliore else { return nil }
        return (Int32(max(migliore.larghezza, migliore.altezza)), Int32(min(migliore.larghezza, migliore.altezza)),
                min(migliore.fpsMassimo, 60))
    }

    /// Il nome per il registro e i Dettagli: «Auto», «Alta», «Massima».
    static func nome(_ livello: String) -> String {
        switch LivelliQualita.normalizza(livello) {
        case LivelliQualita.alta: String(localized: "Alta")
        case LivelliQualita.massima: String(localized: "Massima")
        default: String(localized: "Auto")
        }
    }

    /// «Alta» o «Massima» accanto alla qualità inviata (Impostazioni); `nil` in Auto, quella di sempre.
    static func nomeSeScelta(_ livello: String) -> String? {
        LivelliQualita.normalizza(livello) == LivelliQualita.auto ? nil : nome(livello)
    }
}
