import AVFoundation
import Foundation
import Observation
import UIKit
import WebcamLRProtocollo

/// Gli effetti sull'immagine scelti sul telefono o dal computer (B2): filtro e regolazioni (P13), sfondo (P14),
/// ritocco della pelle (P15).
///
/// - Tiene i valori mostrati dall'interfaccia, li salva (UserDefaults: gli effetti restano sul telefono, dice
///   il protocollo) e li passa agli effetti della pipeline, che girano sulla coda di cattura.
/// - `applica(_:)` prende i campi degli effetti di un `comando`; `completa(_:)` riempie `stato` e `capacita`.
/// - A ogni cambiamento, da qualsiasi parte arrivi, chiama `suCambiamento` (al massimo 4 volte al secondo,
///   sempre con i valori finali): la sessione manda subito uno `stato`.
@Observable
@MainActor
final class EffettiVisivi {
    /// Uno dei `Filtri`; `naturale` = nessun filtro.
    private(set) var filtro = Filtri.naturale
    /// Luminosità, contrasto, saturazione e nitidezza, da -1 a 1.
    private(set) var regolazioni = RegolazioniBase.Valori()
    /// Uno dei `ModiSfondo`.
    private(set) var sfondo = ModiSfondo.nessuno
    /// Da 0 a 1: quanto sfocare, o quanto è netto il bordo dello sfondo sostituito.
    private(set) var intensitaSfondo = 0.5
    /// Quale immagine con «sostituito».
    private(set) var sfondoScelto = SfondoPronto.studio
    /// La foto scelta con «La tua foto» (anche per la sua miniatura nel foglio).
    private(set) var fotoSfondo: UIImage?
    var haFotoSfondo: Bool { fotoSfondo != nil }
    /// «Ritratto» di iOS (Effetti video) è acceso per WebcamLR: lo sfondo è già sfocato dal sistema.
    private(set) var ritrattoDiSistema = false
    /// Ritocco della pelle, da 0 (spento) a 1.
    private(set) var pelle = 0.0
    /// L'ultima intensità usata, per riaccendere il ritocco come l'utente l'aveva lasciato (di serie 0,3).
    private(set) var ultimaPelle = 0.3
    nonisolated static let pelleDiSerie = 0.3

    /// La sessione manda uno `stato` con i valori nuovi.
    @ObservationIgnored var suCambiamento: (() -> Void)?

    @ObservationIgnored private let effettoFiltro = EffettoFiltro()
    @ObservationIgnored private let effettoSfondo = EffettoSfondo()
    @ObservationIgnored private let effettoPelle = EffettoPelle()
    @ObservationIgnored private var compitoRitratto: Task<Void, Never>?
    @ObservationIgnored private weak var pipeline: PipelineEffetti?
    @ObservationIgnored private var compitoNotifica: Task<Void, Never>?

    private enum Chiave {
        static let filtro = "effetti.filtro"
        static let luminosita = "effetti.luminosita"
        static let contrasto = "effetti.contrasto"
        static let saturazione = "effetti.saturazione"
        static let nitidezza = "effetti.nitidezza"
        static let sfondo = "effetti.sfondo"
        static let intensitaSfondo = "effetti.intensitaSfondo"
        static let sfondoScelto = "effetti.sfondoScelto"
        static let pelle = "effetti.pelle"
        static let ultimaPelle = "effetti.ultimaPelle"
    }

    /// La foto di «La tua foto», nel contenitore dell'app (non nella libreria Foto).
    private nonisolated static var fileFotoSfondo: URL? {
        guard let cartella = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                          appropriateFor: nil, create: true) else { return nil }
        return cartella.appendingPathComponent("SfondoWebcamLR.jpg")
    }

    init() {
        let valori = UserDefaults.standard
        filtro = RicetteFiltri.normalizzato(valori.string(forKey: Chiave.filtro) ?? Filtri.naturale)
        regolazioni = RegolazioniBase.Valori(luminosita: valori.double(forKey: Chiave.luminosita),
                                             contrasto: valori.double(forKey: Chiave.contrasto),
                                             saturazione: valori.double(forKey: Chiave.saturazione),
                                             nitidezza: valori.double(forKey: Chiave.nitidezza))
        sfondo = Self.modoSfondo(valori.string(forKey: Chiave.sfondo) ?? ModiSfondo.nessuno)
        intensitaSfondo = Self.limita(valori.object(forKey: Chiave.intensitaSfondo) as? Double ?? 0.5, 0, 1)
        sfondoScelto = SfondoPronto(rawValue: valori.string(forKey: Chiave.sfondoScelto) ?? "") ?? .studio
        pelle = Self.limita(valori.double(forKey: Chiave.pelle), 0, 1)
        let ultima = valori.object(forKey: Chiave.ultimaPelle) as? Double ?? Self.pelleDiSerie
        ultimaPelle = ultima > 0.01 ? Self.limita(ultima, 0, 1) : Self.pelleDiSerie
        ContestiEffetti.prepara()
    }

    /// Mette gli effetti nella pipeline, ognuno nella sua fase, con i valori salvati.
    func collega(_ pipeline: PipelineEffetti) {
        self.pipeline = pipeline
        pipeline.aggiungi(effettoFiltro, fase: .filtro)
        effettoFiltro.filtro = filtro
        pipeline.regolazioni.valori = regolazioni
        pipeline.aggiungi(effettoSfondo, fase: .sfondo)
        pipeline.aggiungi(effettoPelle, fase: .pelle)
        effettoPelle.forza = pelle
        aggiornaSfondo()
        caricaFotoSfondo()
        controllaRitratto()
        // «Ritratto» si accende e si spegne dal Centro di Controllo: si guarda ogni 2 secondi, finché la
        // sessione (e con lei questo oggetto) esiste.
        compitoRitratto = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.controllaRitratto()
            }
        }
    }

    /// Almeno un effetto visibile è acceso (per il pulsante «Effetti» in ciano).
    var qualcosaAttivo: Bool {
        filtro != Filtri.naturale || regolazioni != RegolazioniBase.Valori() || sfondo != ModiSfondo.nessuno
            || pelle > 0
    }

    // MARK: Dal telefono

    func scegliFiltro(_ nuovo: String) {
        let normalizzato = RicetteFiltri.normalizzato(nuovo)
        guard normalizzato != filtro else { return }
        filtro = normalizzato
        effettoFiltro.filtro = normalizzato
        cambiato()
    }

    func impostaRegolazioni(_ nuove: RegolazioniBase.Valori) {
        let limitate = RegolazioniBase.Valori(luminosita: Self.limita(nuove.luminosita, -1, 1),
                                              contrasto: Self.limita(nuove.contrasto, -1, 1),
                                              saturazione: Self.limita(nuove.saturazione, -1, 1),
                                              nitidezza: Self.limita(nuove.nitidezza, -1, 1))
        guard limitate != regolazioni else { return }
        regolazioni = limitate
        pipeline?.regolazioni.valori = limitate
        cambiato()
    }

    func scegliSfondo(_ modo: String) {
        let normalizzato = Self.modoSfondo(modo)
        guard normalizzato != sfondo else { return }
        sfondo = normalizzato
        aggiornaSfondo()
        cambiato()
    }

    func impostaIntensitaSfondo(_ valore: Double) {
        let limitato = Self.limita(valore, 0, 1)
        guard limitato != intensitaSfondo else { return }
        intensitaSfondo = limitato
        aggiornaSfondo()
        cambiato()
    }

    /// Un'immagine per «sostituito»; sceglierla accende anche «sostituito».
    func scegliImmagineSfondo(_ scelto: SfondoPronto) {
        sfondoScelto = scelto == .foto && !haFotoSfondo ? .studio : scelto
        if sfondo != ModiSfondo.sostituito { sfondo = ModiSfondo.sostituito }
        aggiornaSfondo()
        cambiato()
    }

    /// «La tua foto»: i dati scelti con PhotosPicker. Si gira dritta, si riduce (lato lungo 1920 px) e si salva
    /// nel contenitore dell'app, fuori dal thread principale. Ritorna falso se non è un'immagine.
    func usaFotoSfondo(_ dati: Data) async -> Bool {
        let risultato = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let immagine = UIImage(data: dati), let ridotta = Self.ridotta(immagine, latoMassimo: 1920) else {
                return nil
            }
            if let file = Self.fileFotoSfondo, let jpeg = UIImage(cgImage: ridotta).jpegData(compressionQuality: 0.9) {
                try? jpeg.write(to: file, options: .atomic)
            }
            return ridotta
        }.value
        guard let risultato else { return false }
        effettoSfondo.impostaFoto(risultato)
        fotoSfondo = UIImage(cgImage: risultato)
        scegliImmagineSfondo(.foto)
        return true
    }

    /// Accende il ritocco con l'ultima intensità usata (la prima volta 0,3), o lo spegne.
    func accendiPelle(_ acceso: Bool) {
        impostaPelle(acceso ? ultimaPelle : 0)
    }

    func impostaPelle(_ valore: Double) {
        let limitato = Self.limita(valore, 0, 1)
        guard limitato != pelle else { return }
        pelle = limitato
        if limitato > 0.01 { ultimaPelle = limitato }
        effettoPelle.forza = limitato
        cambiato()
    }

    // MARK: Protocollo

    /// I campi degli effetti di un `comando` (solo quelli presenti). Ritorna vero se è cambiato qualcosa.
    @discardableResult
    func applica(_ comando: Comando) -> Bool {
        var cambiatoQualcosa = false
        if let nuovo = comando.filtro {
            let normalizzato = RicetteFiltri.normalizzato(nuovo)
            if normalizzato != filtro {
                filtro = normalizzato
                effettoFiltro.filtro = normalizzato
                cambiatoQualcosa = true
            }
        }
        if let parziali = comando.regolazioni {
            var nuove = regolazioni
            if let valore = parziali.luminosita { nuove.luminosita = Self.limita(valore, -1, 1) }
            if let valore = parziali.contrasto { nuove.contrasto = Self.limita(valore, -1, 1) }
            if let valore = parziali.saturazione { nuove.saturazione = Self.limita(valore, -1, 1) }
            if let valore = parziali.nitidezza { nuove.nitidezza = Self.limita(valore, -1, 1) }
            if nuove != regolazioni {
                regolazioni = nuove
                pipeline?.regolazioni.valori = nuove
                cambiatoQualcosa = true
            }
        }
        if let modo = comando.sfondo {
            let normalizzato = Self.modoSfondo(modo)
            if normalizzato != sfondo {
                sfondo = normalizzato
                cambiatoQualcosa = true
            }
        }
        if let valore = comando.intensitaSfondo {
            let limitato = Self.limita(valore, 0, 1)
            if limitato != intensitaSfondo {
                intensitaSfondo = limitato
                cambiatoQualcosa = true
            }
        }
        if let valore = comando.pelle {
            let limitato = Self.limita(valore, 0, 1)
            if limitato != pelle {
                pelle = limitato
                if limitato > 0.01 { ultimaPelle = limitato }
                effettoPelle.forza = limitato
                cambiatoQualcosa = true
            }
        }
        if cambiatoQualcosa {
            aggiornaSfondo()
            cambiato()
        }
        return cambiatoQualcosa
    }

    /// Un telefono che sa fare gli effetti manda sempre in `stato` tutti quelli che dichiara in `capacita`.
    func completa(_ stato: inout StatoTelefono) {
        stato.filtro = filtro
        stato.regolazioni = Regolazioni(luminosita: regolazioni.luminosita, contrasto: regolazioni.contrasto,
                                        saturazione: regolazioni.saturazione, nitidezza: regolazioni.nitidezza)
        stato.sfondo = sfondo
        stato.intensitaSfondo = intensitaSfondo
        stato.pelle = pelle
    }

    func completa(_ capacita: inout Capacita) {
        capacita.filtri = Filtri.tutti
        // La maschera della persona (Vision) c'è su tutti gli iPhone con iOS 17.
        capacita.sfondo = true
        capacita.pelle = true
    }

    // MARK: Interni

    private func aggiornaSfondo() {
        effettoSfondo.impostazioni = EffettoSfondo.Impostazioni(modo: sfondo, intensita: intensitaSfondo,
                                                                sfondo: sfondoScelto,
                                                                ritrattoDiSistema: ritrattoDiSistema)
    }

    private func controllaRitratto() {
        let acceso = AVCaptureDevice.isPortraitEffectEnabled
        guard acceso != ritrattoDiSistema else { return }
        ritrattoDiSistema = acceso
        aggiornaSfondo()
    }

    /// La foto salvata l'ultima volta, letta in sottofondo.
    private func caricaFotoSfondo() {
        Task { [weak self] in
            let foto = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let file = Self.fileFotoSfondo, let dati = try? Data(contentsOf: file),
                      let immagine = UIImage(data: dati) else { return nil }
                return Self.ridotta(immagine, latoMassimo: 1920)
            }.value
            guard let self else { return }
            guard let foto else {
                // Nessuna foto salvata: «La tua foto» non si può usare, si torna allo studio.
                if self.sfondoScelto == .foto {
                    self.sfondoScelto = .studio
                    self.aggiornaSfondo()
                }
                return
            }
            self.effettoSfondo.impostaFoto(foto)
            self.fotoSfondo = UIImage(cgImage: foto)
        }
    }

    /// L'immagine dritta (orientamento applicato) con il lato lungo al massimo `latoMassimo` pixel.
    private nonisolated static func ridotta(_ immagine: UIImage, latoMassimo: CGFloat) -> CGImage? {
        let misura = CGSize(width: immagine.size.width * immagine.scale, height: immagine.size.height * immagine.scale)
        guard misura.width > 0, misura.height > 0 else { return nil }
        let scala = min(1, latoMassimo / max(misura.width, misura.height))
        let finale = CGSize(width: (misura.width * scala).rounded(), height: (misura.height * scala).rounded())
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let disegnata = UIGraphicsImageRenderer(size: finale, format: formato).image { _ in
            immagine.draw(in: CGRect(origin: .zero, size: finale))
        }
        return disegnata.cgImage
    }

    private nonisolated static func modoSfondo(_ valore: String) -> String {
        [ModiSfondo.nessuno, ModiSfondo.sfocato, ModiSfondo.sostituito].contains(valore) ? valore : ModiSfondo.nessuno
    }

    /// Salva e avvisa la sessione, al massimo 4 volte al secondo (i cursori cambiano a ogni movimento del dito).
    private func cambiato() {
        guard compitoNotifica == nil else { return }
        compitoNotifica = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            self.compitoNotifica = nil
            self.salva()
            self.suCambiamento?()
        }
    }

    private func salva() {
        let valori = UserDefaults.standard
        valori.set(filtro, forKey: Chiave.filtro)
        valori.set(regolazioni.luminosita, forKey: Chiave.luminosita)
        valori.set(regolazioni.contrasto, forKey: Chiave.contrasto)
        valori.set(regolazioni.saturazione, forKey: Chiave.saturazione)
        valori.set(regolazioni.nitidezza, forKey: Chiave.nitidezza)
        valori.set(sfondo, forKey: Chiave.sfondo)
        valori.set(intensitaSfondo, forKey: Chiave.intensitaSfondo)
        valori.set(sfondoScelto.rawValue, forKey: Chiave.sfondoScelto)
        valori.set(pelle, forKey: Chiave.pelle)
        valori.set(ultimaPelle, forKey: Chiave.ultimaPelle)
    }

    private nonisolated static func limita(_ valore: Double, _ minimo: Double, _ massimo: Double) -> Double {
        valore.isFinite ? min(max(valore, minimo), massimo) : 0
    }
}
