import Foundation
import WebcamLRProtocollo

/// Il formato chiesto dal computer con `formato` (per esempio i 60 fps per un'app che usa la webcam a 60),
/// adattato a ciò che l'obiettivo attuale sa fare. Vale per la sessione: le Impostazioni non cambiano, e
/// cambiandole sul telefono la richiesta decade.
struct FormatoRichiesto: Equatable {
    /// Sempre in orizzontale, come i formati della fotocamera.
    let larghezza: Int32
    let altezza: Int32
    let fps: Int
    let codec: Codec

    private static let risoluzioni: [(Int32, Int32)] = [(3840, 2160), (1920, 1080), (1280, 720)]

    /// Come vuole il protocollo: se l'obiettivo non ce la fa scendono prima gli fps, poi la risoluzione.
    /// La risoluzione si riconosce dal lato lungo (il computer può chiedere anche in verticale).
    /// `nil` se la richiesta non ha senso o l'obiettivo non ha nessuna di queste risoluzioni.
    static func da(_ richiesta: FormatoVideo, fpsMassimo: (Int32, Int32) -> Int) -> FormatoRichiesto? {
        let lato = max(richiesta.larghezza, richiesta.altezza)
        guard lato > 0, richiesta.fps > 0 else { return nil }
        let voluti = min(max(richiesta.fps, 15), 60)
        // La risoluzione chiesta o la prima più piccola, poi quelle sotto.
        let inizio = risoluzioni.firstIndex { Int($0.0) <= lato } ?? risoluzioni.count - 1
        for (larghezza, altezza) in risoluzioni[inizio...] {
            let massimo = fpsMassimo(larghezza, altezza)
            guard massimo > 0 else { continue }
            let fps = min(voluti, massimo)
            // Sotto i 24 fps (o sotto quelli chiesti, se meno) conviene scendere di risoluzione.
            if fps >= min(voluti, 24) {
                return FormatoRichiesto(larghezza: larghezza, altezza: altezza, fps: fps, codec: richiesta.codec)
            }
        }
        return nil
    }
}
