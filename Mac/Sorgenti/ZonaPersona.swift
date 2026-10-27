import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// La «zona persona» per lo sfondo (sfocato o sostituito): la maschera di Vision (`VNGeneratePersonSegmentationRequest`)
/// prende per persona anche ciò che le somiglia (un orsacchiotto di peluche nella prova di Ledion), che così restava
/// nitido. Qui, 4 volte al secondo e su una coda propria, Vision separa le persone una per una
/// (`VNGeneratePersonInstanceMaskRequest`, macOS 14) e cerca volti (`VNDetectFaceRectanglesRequest`) e corpi umani
/// (`VNDetectHumanRectanglesRequest`). Si tengono solo le persone con un volto o un corpo umano dentro (se nessuna ne
/// ha, tutte: meglio una persona girata di spalle nitida che sfocata). La loro maschera, allargata e morbida (copre il
/// movimento tra un'analisi e l'altra), moltiplica la maschera di Vision di ogni fotogramma: ciò che sta fuori va con
/// lo sfondo. Se per più di mezzo secondo non c'è nessuna persona (né istanze, né volti, né corpi), la maschera va a
/// zero in un quarto di secondo: tutto sfondo.
///
/// Si usa dalla coda di resa del `MotoreEffetti` (`applica`), che passa il fotogramma: l'analisi parte da sola quando
/// serve e non fa mai aspettare la resa (si usa sempre l'ultima zona pronta). Nessuno stato del motore: se non viene
/// chiamata per più di un secondo e mezzo (sfondo spento, telefono cambiato) riparte da capo.
final class ZonaPersona: @unchecked Sendable {
    /// Ogni quanto si rifà l'analisi (µs): 4 volte al secondo.
    private static let intervallo: UInt64 = 250_000
    /// Senza nessuna persona da più di così (µs), la maschera scende a zero in `dissolvenza`.
    private static let senzaPersonaDopo: UInt64 = 500_000
    private static let dissolvenza: UInt64 = 250_000
    /// Una pausa più lunga di così (µs) tra due chiamate: si riparte da capo.
    private static let ripartenza: UInt64 = 1_500_000
    /// Dopo tanti errori di Vision di fila la zona non si usa più (fino alla ripartenza): la maschera resta com'è.
    private static let erroriMassimi = 3
    /// Quanto si allarga la zona: sigma della sfocatura in parti del lato lungo della maschera delle istanze. Con il
    /// guadagno 5 la zona resta piena fino a circa 0,7 sigma fuori dalla persona e sparisce verso 2 sigma.
    private static let allargamento: CGFloat = 0.05
    private static let guadagno: CGFloat = 5

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.effetti.persone", qos: .userInitiated)

    /// Protegge tutto ciò che è segnato «sotto `blocco`».
    private let blocco = NSLock()
    // Sotto `blocco`.
    private var generazione = 0
    private var occupata = false
    private var ultimaRichiesta: UInt64 = 0
    private var ultimoUso: UInt64 = 0
    /// Almeno un'analisi finita in questa generazione (prima la maschera passa com'è).
    private var analizzata = false
    /// L'ultimo istante (arrivo del fotogramma analizzato) in cui c'era una persona.
    private var ultimaPersona: UInt64 = 0
    /// La maschera delle persone vere (grigia, valori come sono), nil = nessun limite (Vision non sa separare le
    /// istanze ma ha visto un volto o un corpo).
    private var zona: CIImage?
    private var erroriDiFila = 0

    // Solo sulla coda.
    private let richiestaIstanze = VNGeneratePersonInstanceMaskRequest()
    private let richiestaVolti = VNDetectFaceRectanglesRequest()
    private let richiestaCorpi: VNDetectHumanRectanglesRequest = {
        let richiesta = VNDetectHumanRectanglesRequest()
        // Il corpo intero, non solo busto e testa: anche chi è sdraiato o lontano.
        richiesta.upperBodyOnly = false
        return richiesta
    }()

    /// Dalla coda di resa: `bassa` (la maschera piccola di Vision, già filtrata nel tempo) con solo le persone vere.
    /// `fotogramma` e `arrivo` (µs, `Orologio.adesso()`) servono a far partire l'analisi quando tocca.
    func applica(a bassa: CIImage, fotogramma: CVPixelBuffer, arrivo: UInt64) -> CIImage {
        let misura = bassa.extent
        guard misura.width > 0, misura.height > 0, !misura.isInfinite else { return bassa }
        var daAnalizzare: Int?
        let stato = blocco.withLock { () -> (analizzata: Bool, ultimaPersona: UInt64, zona: CIImage?, errori: Int) in
            if ultimoUso == 0 || arrivo < ultimoUso || arrivo - ultimoUso > Self.ripartenza {
                // Da capo: i risultati di un'analisi ancora in corso non valgono più.
                generazione += 1
                analizzata = false
                ultimaPersona = arrivo
                zona = nil
                erroriDiFila = 0
                occupata = false
                ultimaRichiesta = 0
            }
            ultimoUso = arrivo
            if !occupata, erroriDiFila < Self.erroriMassimi,
               ultimaRichiesta == 0 || arrivo < ultimaRichiesta || arrivo - ultimaRichiesta >= Self.intervallo {
                occupata = true
                ultimaRichiesta = arrivo
                daAnalizzare = generazione
            }
            return (analizzata, ultimaPersona, zona, erroriDiFila)
        }
        if let daAnalizzare {
            coda.async { self.analizza(fotogramma, arrivo: arrivo, generazione: daAnalizzare) }
        }
        guard stato.analizzata, stato.errori < Self.erroriMassimi else { return bassa }

        // Nessuna persona da troppo: la maschera scende a zero.
        let assenza = arrivo > stato.ultimaPersona ? arrivo - stato.ultimaPersona : 0
        var presenza: CGFloat = 1
        if assenza > Self.senzaPersonaDopo {
            presenza = max(0, 1 - CGFloat(assenza - Self.senzaPersonaDopo) / CGFloat(Self.dissolvenza))
        }
        var risultato = bassa
        if let zona = stato.zona {
            let misuraZona = zona.extent
            if misuraZona.width > 0, misuraZona.height > 0, !misuraZona.isInfinite {
                let sigma = max(misuraZona.width, misuraZona.height) * Self.allargamento
                let allargata = RicetteEffetti.lineare(
                    RicetteEffetti.grigio(zona).clampedToExtent().applyingGaussianBlur(sigma: Double(sigma))
                        .cropped(to: misuraZona),
                    pendenza: Self.guadagno, scostamento: 0)
                    .transformed(by: CGAffineTransform(translationX: -misuraZona.minX, y: -misuraZona.minY)
                        .concatenating(CGAffineTransform(scaleX: misura.width / misuraZona.width,
                                                         y: misura.height / misuraZona.height))
                        .concatenating(CGAffineTransform(translationX: misura.minX, y: misura.minY)))
                    .clampedToExtent()
                    .cropped(to: misura)
                risultato = RicetteEffetti.moltiplica(risultato, allargata).cropped(to: misura)
            }
        }
        if presenza < 0.999 {
            risultato = RicetteFiltriMac.scala(risultato, per: presenza).cropped(to: misura)
        }
        return risultato
    }

    // MARK: Analisi (coda propria)

    private func analizza(_ fotogramma: CVPixelBuffer, arrivo: UInt64, generazione voluta: Int) {
        let gestore = VNImageRequestHandler(cvPixelBuffer: fotogramma, orientation: .up, options: [:])
        // Volti e corpi con una chiamata, le istanze con un'altra: l'errore di una non fa perdere l'altra.
        var prove: [CGPoint] = []
        if (try? gestore.perform([richiestaVolti, richiestaCorpi])) != nil {
            for volto in richiestaVolti.results ?? [] {
                let r = volto.boundingBox
                prove += [CGPoint(x: r.midX, y: r.midY), CGPoint(x: r.midX, y: r.minY + r.height * 0.25),
                          CGPoint(x: r.minX + r.width * 0.3, y: r.midY), CGPoint(x: r.maxX - r.width * 0.3, y: r.midY)]
            }
            for corpo in richiestaCorpi.results ?? [] {
                let r = corpo.boundingBox
                // Busto: a metà in larghezza, nel terzo alto e a metà altezza.
                prove += [CGPoint(x: r.midX, y: r.maxY - r.height * 0.3), CGPoint(x: r.midX, y: r.midY)]
            }
        }
        var zonaNuova: CIImage?
        var persona = !prove.isEmpty
        var errore = false
        do {
            try gestore.perform([richiestaIstanze])
            if let osservazione = richiestaIstanze.results?.first, !osservazione.allInstances.isEmpty {
                persona = true
                let tutte = osservazione.allInstances
                let conProve = Self.istanze(in: osservazione.instanceMask, punti: prove).intersection(tutte)
                let scelte = conProve.isEmpty ? tutte : conProve
                let maschera = try osservazione.generateMask(forInstances: scelte)
                zonaNuova = CIImage(cvPixelBuffer: maschera, options: [.colorSpace: NSNull()])
            }
        } catch {
            errore = true
        }
        blocco.withLock {
            guard generazione == voluta else { return }
            occupata = false
            if errore {
                erroriDiFila += 1
                return
            }
            erroriDiFila = 0
            analizzata = true
            if persona {
                if arrivo > ultimaPersona { ultimaPersona = arrivo }
                // Volti o corpi senza istanze: nessun limite (la maschera di Vision com'è).
                zona = zonaNuova
            }
            // Nessuna persona: si tiene l'ultima zona; dopo mezzo secondo la maschera va comunque a zero.
        }
    }

    /// Le istanze (etichette 1…n nella maschera delle istanze, 0 = sfondo) sotto i punti dati (normalizzati, origine in
    /// basso a sinistra come Vision).
    private static func istanze(in etichette: CVPixelBuffer, punti: [CGPoint]) -> IndexSet {
        guard !punti.isEmpty, CVPixelBufferGetPixelFormatType(etichette) == kCVPixelFormatType_OneComponent8 else {
            return IndexSet()
        }
        let larghezza = CVPixelBufferGetWidth(etichette)
        let altezza = CVPixelBufferGetHeight(etichette)
        guard larghezza > 0, altezza > 0,
              CVPixelBufferLockBaseAddress(etichette, .readOnly) == kCVReturnSuccess else { return IndexSet() }
        defer { CVPixelBufferUnlockBaseAddress(etichette, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(etichette) else { return IndexSet() }
        let riga = CVPixelBufferGetBytesPerRow(etichette)
        let byte = base.assumingMemoryBound(to: UInt8.self)
        var trovate = IndexSet()
        for punto in punti where punto.x.isFinite && punto.y.isFinite {
            let x = min(max(Int(punto.x * CGFloat(larghezza)), 0), larghezza - 1)
            // Le righe del buffer partono dall'alto.
            let y = min(max(Int((1 - punto.y) * CGFloat(altezza)), 0), altezza - 1)
            let etichetta = Int(byte[y * riga + x])
            if etichetta > 0 { trovate.insert(etichetta) }
        }
        return trovate
    }
}
