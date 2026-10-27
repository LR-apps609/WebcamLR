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

/// Le qualità che l'iPhone sa fare con l'obiettivo attuale, per le Impostazioni (seconda prova, bug A): sono le
/// stesse di `capacita.formati` che il computer riceve e mostra in «Qualità video», con gli stessi nomi (720p,
/// 1080p, 4K). La sessione le salva a ogni `capacita` (`salva`); prima del primo collegamento valgono le tre comuni.
/// Le scelte Pro sono le stesse del computer: tutto ciò che supera 720p a 30 fps.
enum QualitaTelefono {
    struct Voce: Identifiable, Equatable {
        /// Come in `UserDefaults` «risoluzione»: «720p», «1080p» o «4K».
        let chiave: String
        let fpsMassimo: Int

        var id: String { chiave }
        /// Solo 720p è della versione gratuita.
        var pro: Bool { chiave != "720p" }
    }

    private static let chiaveSalvata = "qualitaTelefono"
    private static let ordine = ["720p", "1080p", "4K"]

    /// Il nome di una risoluzione dal lato corto, come sul computer; `nil` per le altre.
    static func nome(latoCorto: Int) -> String? {
        switch latoCorto {
        case 720: "720p"
        case 1080: "1080p"
        case 2160: "4K"
        default: nil
        }
    }

    /// I formati appena mandati al computer, tutti (anche quelli Pro: il telefono li mostra marcati PRO).
    static func salva(_ formati: [FormatoSupportato]) {
        guard !formati.isEmpty else { return }
        var elenco: [String: Int] = [:]
        for formato in formati {
            guard let nome = nome(latoCorto: min(formato.larghezza, formato.altezza)) else { continue }
            elenco[nome] = max(elenco[nome] ?? 0, formato.fpsMassimo)
        }
        UserDefaults.standard.set(elenco, forKey: chiaveSalvata)
    }

    /// Dalla più piccola alla più grande.
    static func salvate() -> [Voce] {
        let elenco = UserDefaults.standard.dictionary(forKey: chiaveSalvata) as? [String: Int] ?? [:]
        let voci = ordine.compactMap { chiave in elenco[chiave].map { Voce(chiave: chiave, fpsMassimo: $0) } }
        guard voci.isEmpty else { return voci }
        return [Voce(chiave: "720p", fpsMassimo: 60), Voce(chiave: "1080p", fpsMassimo: 60),
                Voce(chiave: "4K", fpsMassimo: Cattura.fpsMassimo4K)]
    }
}
