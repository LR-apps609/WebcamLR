import AVFoundation
import Foundation
import Observation
import WebcamLRProtocollo

/// Gli effetti sull'immagine scelti sul telefono o dal computer (B2): filtro e regolazioni (P13).
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

    /// La sessione manda uno `stato` con i valori nuovi.
    @ObservationIgnored var suCambiamento: (() -> Void)?

    @ObservationIgnored private let effettoFiltro = EffettoFiltro()
    @ObservationIgnored private weak var pipeline: PipelineEffetti?
    @ObservationIgnored private var compitoNotifica: Task<Void, Never>?

    private enum Chiave {
        static let filtro = "effetti.filtro"
        static let luminosita = "effetti.luminosita"
        static let contrasto = "effetti.contrasto"
        static let saturazione = "effetti.saturazione"
        static let nitidezza = "effetti.nitidezza"
    }

    init() {
        let valori = UserDefaults.standard
        filtro = RicetteFiltri.normalizzato(valori.string(forKey: Chiave.filtro) ?? Filtri.naturale)
        regolazioni = RegolazioniBase.Valori(luminosita: valori.double(forKey: Chiave.luminosita),
                                             contrasto: valori.double(forKey: Chiave.contrasto),
                                             saturazione: valori.double(forKey: Chiave.saturazione),
                                             nitidezza: valori.double(forKey: Chiave.nitidezza))
        ContestiEffetti.prepara()
    }

    /// Mette gli effetti nella pipeline, ognuno nella sua fase, con i valori salvati.
    func collega(_ pipeline: PipelineEffetti) {
        self.pipeline = pipeline
        pipeline.aggiungi(effettoFiltro, fase: .filtro)
        effettoFiltro.filtro = filtro
        pipeline.regolazioni.valori = regolazioni
    }

    /// Almeno un effetto visibile è acceso (per il pulsante «Effetti» in ciano).
    var qualcosaAttivo: Bool {
        filtro != Filtri.naturale || regolazioni != RegolazioniBase.Valori()
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
        if cambiatoQualcosa { cambiato() }
        return cambiatoQualcosa
    }

    /// Un telefono che sa fare gli effetti manda sempre in `stato` tutti quelli che dichiara in `capacita`.
    func completa(_ stato: inout StatoTelefono) {
        stato.filtro = filtro
        stato.regolazioni = Regolazioni(luminosita: regolazioni.luminosita, contrasto: regolazioni.contrasto,
                                        saturazione: regolazioni.saturazione, nitidezza: regolazioni.nitidezza)
    }

    func completa(_ capacita: inout Capacita) {
        capacita.filtri = Filtri.tutti
    }

    // MARK: Interni

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
    }

    private static func limita(_ valore: Double, _ minimo: Double, _ massimo: Double) -> Double {
        valore.isFinite ? min(max(valore, minimo), massimo) : 0
    }
}
