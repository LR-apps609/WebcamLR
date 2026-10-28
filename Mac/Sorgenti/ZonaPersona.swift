import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// La «zona persona» per lo sfondo (sfocato o sostituito): la maschera di Vision (`VNGeneratePersonSegmentationRequest`)
/// prende per persona anche ciò che le somiglia (un orsacchiotto di peluche, un mucchio di vestiti scuri e il piumone
/// nelle prove di Ledion), che così restava nitido. Qui, 4 volte al secondo e su una coda propria, Vision separa le
/// persone una per una (`VNGeneratePersonInstanceMaskRequest`, macOS 14) e cerca volti (`VNDetectFaceRectanglesRequest`)
/// e corpi umani (`VNDetectHumanRectanglesRequest`). La loro maschera, allargata e morbida (copre il movimento tra
/// un'analisi e l'altra), moltiplica la maschera di Vision di ogni fotogramma: ciò che sta fuori va con lo sfondo.
///
/// Le regole (simulate in Python prima di scriverle, con istanze false a intermittenza, volto visto al 70%, testa
/// girata per 3 s, persona sdraiata, volto senza istanze):
/// - è persona un'istanza che copre buona parte di un volto o di un corpo trovato (`quotaVolto`, `quotaCorpo`), oppure
///   un'istanza che sta per almeno metà nella zona dell'analisi prima (la stessa persona che ha girato la testa) fino a
///   `conferma` dopo l'ultimo volto o corpo visto. Un'istanza senza prove e fuori dalla zona è un oggetto: mai «tutte»;
/// - un volto o un corpo senza nessuna istanza che lo copra: la zona di prima se ha meno di `zonaValida`, altrimenti i
///   rettangoli del volto (allargato verso il busto) e del corpo. Mai «nessun limite»: prima, con `zona = nil` a ogni
///   analisi senza istanze, i falsi positivi di Vision tornavano nitidi per un quarto di secondo e poi sparivano;
/// - senza nessuno inquadrato la maschera è zero (tutto sfondo), anche prima della prima analisi. Per entrare servono
///   un volto o un corpo in `confermePerEntrare` analisi di fila (un falso corpo isolato sui vestiti non apre la zona);
///   la zona entra ed esce con una dissolvenza di `dissolvenza`. Una persona già dentro esce solo dopo
///   `senzaPersonaDopo` senza nessuna prova né istanza della sua zona.
///
/// Si usa dalla coda di resa del `MotoreEffetti` (`applica`), che passa il fotogramma: l'analisi parte da sola quando
/// serve e non fa mai aspettare la resa (si usa sempre l'ultima zona pronta). Nessuno stato del motore: se non viene
/// chiamata per più di un secondo e mezzo (sfondo spento, telefono cambiato) riparte da capo.
final class ZonaPersona: @unchecked Sendable {
    /// Ogni quanto si rifà l'analisi (µs): 4 volte al secondo.
    private static let intervallo: UInt64 = 250_000
    /// Una persona già dentro, senza più prove né istanze da così (µs), esce in `dissolvenza`.
    private static let senzaPersonaDopo: UInt64 = 500_000
    private static let dissolvenza: UInt64 = 250_000
    /// Per quanto (µs) dopo l'ultimo volto o corpo visto un'istanza senza prove resta persona, se sta nella zona di prima
    /// (la segue da un'analisi all'altra). 30 s: chi è sdraiato a letto, di spalle o con la testa girata a lungo può non
    /// avere volto né corpo riconosciuti per molti secondi, e non deve finire nella sfocatura. Un oggetto non entra
    /// così: per entrare servono comunque `confermePerEntrare` prove.
    private static let conferma: UInt64 = 30_000_000
    /// Un volto o un corpo senza istanze: per quanto (µs) vale ancora la zona fatta con le istanze.
    private static let zonaValida: UInt64 = 1_000_000
    /// Analisi di fila con un volto o un corpo per far entrare una persona (dopo la prima analisi di una generazione).
    private static let confermePerEntrare = 2
    /// Una pausa più lunga di così (µs) tra due chiamate: si riparte da capo.
    private static let ripartenza: UInt64 = 1_500_000
    /// Dopo tante analisi fallite di fila (volti e corpi E istanze) la zona non si usa più fino alla ripartenza: la
    /// maschera resta com'è. Un errore solo delle istanze non conta: restano volti e corpi.
    private static let erroriMassimi = 3
    /// Quanto si allarga la zona: sigma della sfocatura in parti del lato lungo della maschera delle istanze. Con il
    /// guadagno 5 la zona resta piena fino a circa 0,7 sigma fuori dalla persona e sparisce verso 2 sigma.
    /// 0,03: un peluche a 20 px dalla persona resta nitido per il 6% (con 0,05 per il 23%, a mezzaluna).
    private static let allargamento: CGFloat = 0.03
    private static let guadagno: CGFloat = 5
    /// La griglia con cui si riconosce la stessa persona da un'analisi all'altra (lato, in celle).
    private static let latoGriglia = 48
    /// Un'istanza senza prove è la persona di prima se almeno questa parte della sua area stava nella zona di prima.
    private static let quotaDentro = 0.5
    /// Un volto (un corpo) prova un'istanza se l'istanza ne copre almeno questa parte del rettangolo.
    private static let quotaVolto = 0.25
    private static let quotaCorpo = 0.15
    /// La misura (qualsiasi: `applica` la porta a quella della maschera) della zona fatta con i rettangoli.
    private static let misuraRettangoli = CGRect(x: 0, y: 0, width: 256, height: 256)

    /// I conti per il registro, dall'inizio della sessione del motore.
    struct Misure: Sendable {
        var analisi = 0
        /// Analisi con almeno un volto o un corpo umano.
        var conProve = 0
        /// Analisi con un errore di Vision (anche solo delle istanze).
        var errori = 0
        /// Quanto conta la zona adesso: 0 = nessuna persona (tutto sfondo), 1 = persona dentro.
        var presenza: Double = 0
    }

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.effetti.persone", qos: .userInitiated)

    /// Protegge tutto ciò che è segnato «sotto `blocco`».
    private let blocco = NSLock()
    // Sotto `blocco`.
    private var generazione = 0
    private var occupata = false
    private var ultimaRichiesta: UInt64 = 0
    private var ultimoUso: UInt64 = 0
    /// Almeno un'analisi finita in questa generazione (prima la maschera è zero: tutto sfondo).
    private var analizzata = false
    /// Nessuna analisi ancora in questa generazione: per entrare basta una conferma (la persona davanti quando si
    /// accende lo sfondo non resta sfocata mezzo secondo).
    private var primaAnalisi = true
    /// C'è una persona: la zona vale (con le dissolvenze). Falso = maschera zero.
    private var presente = false
    /// Da quando la zona entra (arrivo, µs), per la dissolvenza in entrata.
    private var presenteDa: UInt64 = 0
    /// Il primo fotogramma analizzato senza la persona dopo uno con la persona (arrivo, µs; 0 = c'è). Si conta da qui
    /// e non dall'ultimo fotogramma con la persona: con un'analisi lenta (più di circa 170 ms) l'ultimo positivo
    /// sarebbe vecchio di oltre mezzo secondo anche con la persona sempre davanti.
    private var assenteDa: UInt64 = 0
    /// L'ultimo fotogramma analizzato con un volto o un corpo umano (arrivo, µs; 0 = mai in questa generazione).
    private var ultimaConferma: UInt64 = 0
    private var confermeDiFila = 0
    /// La maschera delle persone vere (grigia, valori come sono) e la stessa in una griglia `latoGriglia`² (per
    /// riconoscere la persona all'analisi dopo), con l'arrivo del fotogramma da cui viene.
    private var zona: CIImage?
    private var griglia: [Bool]?
    private var zonaQuando: UInt64 = 0
    /// La `zona` viene dalle istanze (falso: dai rettangoli di volti e corpi, che non si tengono oltre un'analisi).
    private var zonaDaIstanze = false
    private var erroriDiFila = 0
    private var conti = Misure()

    // Solo sulla coda.
    private let richiestaIstanze = VNGeneratePersonInstanceMaskRequest()
    private let richiestaVolti = VNDetectFaceRectanglesRequest()
    private let richiestaCorpi: VNDetectHumanRectanglesRequest = {
        let richiesta = VNDetectHumanRectanglesRequest()
        // Il corpo intero, non solo busto e testa: anche chi è sdraiato o lontano.
        richiesta.upperBodyOnly = false
        return richiesta
    }()

    /// Da capo alla prossima `applica`, come dopo una pausa lunga: il motore la chiama quando il video cambia misura
    /// (telefono girato, altro obiettivo) o si svuota. Senza, per un'analisi (250 ms o più) la zona del video di prima,
    /// stirata sulla misura nuova, avrebbe tagliato la persona. Da qualsiasi coda.
    func riparti() {
        blocco.withLock { ultimoUso = 0 }
    }

    /// I conti per il registro (la presenza è quella dell'ultimo fotogramma passato da `applica`). Da qualsiasi coda.
    func misure() -> Misure {
        blocco.withLock { conti }
    }

    /// Dalla coda di resa: `bassa` (la maschera piccola di Vision, già filtrata nel tempo) con solo le persone vere.
    /// `fotogramma` e `arrivo` (µs, `Orologio.adesso()`) servono a far partire l'analisi quando tocca.
    func applica(a bassa: CIImage, fotogramma: CVPixelBuffer, arrivo: UInt64) -> CIImage {
        let misura = bassa.extent
        guard misura.width > 0, misura.height > 0, !misura.isInfinite else { return bassa }
        var daAnalizzare: Int?
        let stato = blocco.withLock { () -> (analizzata: Bool, presenza: CGFloat, zona: CIImage?, errori: Int) in
            if ultimoUso == 0 || arrivo < ultimoUso || arrivo - ultimoUso > Self.ripartenza {
                // Da capo: i risultati di un'analisi ancora in corso non valgono più.
                generazione += 1
                analizzata = false
                primaAnalisi = true
                presente = false
                presenteDa = 0
                assenteDa = 0
                ultimaConferma = 0
                confermeDiFila = 0
                zona = nil
                griglia = nil
                zonaQuando = 0
                zonaDaIstanze = false
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
            let presenza = presenzaSottoBlocco(arrivo)
            conti.presenza = Double(presenza)
            return (analizzata, presenza, zona, erroriDiFila)
        }
        if let daAnalizzare {
            coda.async { self.analizza(fotogramma, arrivo: arrivo, generazione: daAnalizzare) }
        }
        // Vision non riesce più a separare nulla: la maschera com'è (come prima della zona).
        guard stato.errori < Self.erroriMassimi else { return bassa }
        // Prima della prima analisi, o nessuna persona: tutto sfondo. Mai lo sfondo nitido per errore.
        guard stato.analizzata, stato.presenza > 0.001 else {
            return RicetteFiltriMac.scala(bassa, per: 0).cropped(to: misura)
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
        if stato.presenza < 0.999 {
            risultato = RicetteFiltriMac.scala(risultato, per: stato.presenza).cropped(to: misura)
        }
        return risultato
    }

    /// Sotto `blocco`: quanto vale la zona per il fotogramma arrivato a `istante` (0…1), con le due dissolvenze.
    private func presenzaSottoBlocco(_ istante: UInt64) -> CGFloat {
        guard analizzata, presente else { return 0 }
        let durata = CGFloat(Self.dissolvenza)
        let entrata = istante > presenteDa ? min(1, CGFloat(istante - presenteDa) / durata) : 0
        var uscita: CGFloat = 1
        if assenteDa != 0, istante > assenteDa, istante - assenteDa > Self.senzaPersonaDopo {
            uscita = max(0, 1 - CGFloat(istante - assenteDa - Self.senzaPersonaDopo) / durata)
        }
        return min(entrata, uscita)
    }

    // MARK: Analisi (coda propria)

    private func analizza(_ fotogramma: CVPixelBuffer, arrivo: UInt64, generazione voluta: Int) {
        let (precedente, ultimaProva) = blocco.withLock { () -> ([Bool]?, UInt64) in
            generazione == voluta ? (griglia, ultimaConferma) : (nil, 0)
        }
        let gestore = VNImageRequestHandler(cvPixelBuffer: fotogramma, orientation: .up, options: [:])
        // Volti e corpi con una chiamata, le istanze con un'altra: l'errore di una non fa perdere l'altra.
        var volti: [CGRect] = []
        var corpi: [CGRect] = []
        var erroreProve = false
        do {
            try gestore.perform([richiestaVolti, richiestaCorpi])
            volti = (richiestaVolti.results ?? []).map(\.boundingBox)
            corpi = (richiestaCorpi.results ?? []).map(\.boundingBox)
        } catch {
            erroreProve = true
        }
        let conProve = !volti.isEmpty || !corpi.isEmpty
        // L'istanza senza prove resta persona solo poco dopo l'ultima prova (questa analisi compresa).
        let seguibile = conProve
            || (ultimaProva != 0 && arrivo >= ultimaProva && arrivo - ultimaProva < Self.conferma)
        var zonaIstanze: (immagine: CIImage, griglia: [Bool])?
        var erroreIstanze = false
        do {
            try gestore.perform([richiestaIstanze])
            if let osservazione = richiestaIstanze.results?.first, !osservazione.allInstances.isEmpty,
               let scelta = Self.scegli(etichette: osservazione.instanceMask, volti: volti, corpi: corpi,
                                        precedente: seguibile ? precedente : nil) {
                let scelte = scelta.istanze.intersection(osservazione.allInstances)
                if !scelte.isEmpty {
                    let maschera = try osservazione.generateMask(forInstances: scelte)
                    zonaIstanze = (CIImage(cvPixelBuffer: maschera, options: [.colorSpace: NSNull()]), scelta.griglia)
                }
            }
        } catch {
            erroreIstanze = true
        }
        blocco.withLock {
            guard generazione == voluta else { return }
            occupata = false
            conti.analisi += 1
            if erroreProve || erroreIstanze { conti.errori += 1 }
            if erroreProve && erroreIstanze {
                erroriDiFila += 1
                return
            }
            erroriDiFila = 0
            if conProve {
                conti.conProve += 1
                confermeDiFila += 1
                ultimaConferma = max(arrivo, 1)
            } else {
                confermeDiFila = 0
            }
            // La zona nuova: le istanze scelte; con un volto o un corpo ma senza istanze, la zona di prima se è
            // recente e fatta con le istanze, altrimenti i rettangoli di adesso (quelli di prima non seguirebbero la
            // persona che si muove). nil = si tiene quella che c'è.
            var nuova: (immagine: CIImage, griglia: [Bool])? = zonaIstanze
            if nuova == nil, conProve {
                let recente = zona != nil && zonaDaIstanze && zonaQuando != 0 && arrivo >= zonaQuando
                    && arrivo - zonaQuando < Self.zonaValida
                if !recente { nuova = Self.zonaRettangoli(volti: volti, corpi: corpi) }
            }
            let vista = zonaIstanze != nil || conProve
            if presente, assenteDa != 0, arrivo > assenteDa,
               arrivo - assenteDa >= Self.senzaPersonaDopo + Self.dissolvenza {
                // Uscita finita: la prossima persona deve entrare di nuovo (con le sue conferme).
                presente = false
                zona = nil
                griglia = nil
                zonaQuando = 0
                zonaDaIstanze = false
            }
            if presente {
                if vista {
                    if assenteDa != 0 {
                        // Torna durante l'uscita: si risale da dove si era, senza salti.
                        let attuale = presenzaSottoBlocco(arrivo)
                        presenteDa = arrivo - min(arrivo, UInt64(attuale * CGFloat(Self.dissolvenza)))
                        assenteDa = 0
                    }
                } else if assenteDa == 0 {
                    // Nessuna persona: si tiene l'ultima zona; dopo mezzo secondo la maschera scende comunque a zero.
                    assenteDa = max(arrivo, 1)
                }
            } else if conProve, confermeDiFila >= (primaAnalisi ? 1 : Self.confermePerEntrare) {
                presente = true
                presenteDa = arrivo
                assenteDa = 0
            }
            if presente, vista, let nuova {
                zona = nuova.immagine
                griglia = nuova.griglia
                zonaQuando = max(arrivo, 1)
                zonaDaIstanze = zonaIstanze != nil
            }
            primaAnalisi = false
            analizzata = true
        }
    }

    /// Le istanze (etichette 1…n nella maschera delle istanze, 0 = sfondo) che sono persone: quelle che coprono un volto
    /// o un corpo, e quelle che stanno per almeno metà nella zona `precedente` (nil = nessuna da seguire). Con la loro
    /// griglia. nil se le etichette sono in un formato inatteso. Rettangoli normalizzati, origine in basso a sinistra
    /// come Vision.
    private static func scegli(etichette: CVPixelBuffer, volti: [CGRect], corpi: [CGRect],
                               precedente: [Bool]?) -> (istanze: IndexSet, griglia: [Bool])? {
        guard CVPixelBufferGetPixelFormatType(etichette) == kCVPixelFormatType_OneComponent8 else { return nil }
        let larghezza = CVPixelBufferGetWidth(etichette)
        let altezza = CVPixelBufferGetHeight(etichette)
        guard larghezza > 0, altezza > 0,
              CVPixelBufferLockBaseAddress(etichette, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(etichette, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(etichette) else { return nil }
        let riga = CVPixelBufferGetBytesPerRow(etichette)
        let byte = base.assumingMemoryBound(to: UInt8.self)
        func etichetta(_ x: CGFloat, _ y: CGFloat) -> Int {
            guard x.isFinite, y.isFinite else { return 0 }
            let colonna = min(max(Int(x * CGFloat(larghezza)), 0), larghezza - 1)
            // Le righe del buffer partono dall'alto.
            let rigaPixel = min(max(Int((1 - y) * CGFloat(altezza)), 0), altezza - 1)
            return Int(byte[rigaPixel * riga + colonna])
        }

        var scelte = IndexSet()
        // Un rettangolo su una trama di 12 × 12 punti: le istanze che ne coprono almeno `quota`.
        func provate(_ rettangolo: CGRect, quota: Double) {
            let lato = 12
            var conta: [Int: Int] = [:]
            for j in 0..<lato {
                for i in 0..<lato {
                    let x = rettangolo.minX + rettangolo.width * (CGFloat(i) + 0.5) / CGFloat(lato)
                    let y = rettangolo.minY + rettangolo.height * (CGFloat(j) + 0.5) / CGFloat(lato)
                    let valore = etichetta(x, y)
                    if valore > 0 { conta[valore, default: 0] += 1 }
                }
            }
            for (valore, quanti) in conta where Double(quanti) >= quota * Double(lato * lato) {
                scelte.insert(valore)
            }
        }
        for volto in volti { provate(volto, quota: Self.quotaVolto) }
        for corpo in corpi { provate(corpo, quota: Self.quotaCorpo) }

        let lato = Self.latoGriglia
        var celle = [Int](repeating: 0, count: lato * lato)
        for gy in 0..<lato {
            for gx in 0..<lato {
                celle[gy * lato + gx] = etichetta((CGFloat(gx) + 0.5) / CGFloat(lato), (CGFloat(gy) + 0.5) / CGFloat(lato))
            }
        }
        if let precedente, precedente.count == celle.count {
            var area: [Int: Int] = [:]
            var dentro: [Int: Int] = [:]
            for (indice, valore) in celle.enumerated() where valore > 0 {
                area[valore, default: 0] += 1
                if precedente[indice] { dentro[valore, default: 0] += 1 }
            }
            for (valore, quanti) in area where Double(dentro[valore] ?? 0) >= Self.quotaDentro * Double(quanti) {
                scelte.insert(valore)
            }
        }
        return (scelte, celle.map { $0 > 0 && scelte.contains($0) })
    }

    /// La zona quando Vision vede un volto o un corpo ma nessuna istanza lo copre: i rettangoli dei corpi e, per ogni
    /// volto, una colonna tre volte più larga dal sopra della testa al fondo dell'immagine (il busto sotto il volto).
    private static func zonaRettangoli(volti: [CGRect], corpi: [CGRect]) -> (immagine: CIImage, griglia: [Bool]) {
        var rettangoli: [CGRect] = corpi.map { $0.insetBy(dx: -$0.width * 0.1, dy: -$0.height * 0.05) }
        for volto in volti {
            rettangoli.append(CGRect(x: volto.midX - volto.width * 1.5, y: 0,
                                     width: volto.width * 3, height: volto.maxY + volto.height * 0.5))
        }
        let unita = CGRect(x: 0, y: 0, width: 1, height: 1)
        let misura = Self.misuraRettangoli
        var immagine = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: misura)
        let bianco = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
        let lato = Self.latoGriglia
        var griglia = [Bool](repeating: false, count: lato * lato)
        for rettangolo in rettangoli {
            let dentro = rettangolo.intersection(unita)
            guard !dentro.isNull, dentro.width > 0, dentro.height > 0 else { continue }
            let inPixel = CGRect(x: dentro.minX * misura.width, y: dentro.minY * misura.height,
                                 width: dentro.width * misura.width, height: dentro.height * misura.height)
            immagine = bianco.cropped(to: inPixel).composited(over: immagine)
            for gy in 0..<lato {
                for gx in 0..<lato {
                    let centro = CGPoint(x: (CGFloat(gx) + 0.5) / CGFloat(lato), y: (CGFloat(gy) + 0.5) / CGFloat(lato))
                    if dentro.contains(centro) { griglia[gy * lato + gx] = true }
                }
            }
        }
        return (immagine.cropped(to: misura), griglia)
    }
}
