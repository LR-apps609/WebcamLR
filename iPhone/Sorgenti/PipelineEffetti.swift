import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal
import Vision

// MARK: - Effetti

/// Quanto può costare un effetto in questo fotogramma. `ridotta`: la resa è rimasta indietro rispetto ai
/// fotogrammi al secondo, l'effetto usi la sua via più leggera (meno raggio di sfocatura, niente passaggi extra).
enum QualitaEffetti: Sendable {
    case piena
    case ridotta
}

/// Cosa sa un effetto del fotogramma che sta trasformando.
struct InfoFotogramma {
    /// Istante di presentazione del fotogramma (quello che arriva al codificatore).
    let istante: CMTime
    /// Dimensioni del fotogramma, già girato dritto dalla cattura.
    let larghezza: Int
    let altezza: Int
    let qualita: QualitaEffetti
    /// Gli ultimi volti trovati (vedi `AnalisiFotogramma`), se un consumatore li ha chiesti. Possono essere di
    /// qualche fotogramma prima: `volti.istante` dice di quale.
    let volti: VoltiRilevati?
    /// L'ultima maschera della persona, se qualcuno l'ha chiesta.
    let maschera: MascheraPersona?
}

/// Un effetto sul video inviato al computer. Si chiama sulla coda di cattura, un fotogramma alla volta:
/// `attivo` e `applica` devono essere veloci e non bloccare. I valori cambiati dall'interfaccia (thread
/// principale) vanno protetti con un blocco dentro l'effetto, come fa `RegolazioniBase`.
protocol Effetto: AnyObject, Sendable {
    /// Per il registro e per chi elenca gli effetti.
    var nome: String { get }
    /// Spento, l'effetto non costa nulla: se nessun effetto è attivo il fotogramma passa intatto.
    var attivo: Bool { get }
    /// Le analisi che servono a questo effetto mentre è attivo (volti, persona): la pipeline le chiede da sola.
    var analisiNecessarie: Set<TipoAnalisi> { get }
    /// Ritorna l'immagine trasformata. Le dimensioni restano quelle dell'ingresso: ciò che esce dai bordi si taglia.
    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage
}

extension Effetto {
    var analisiNecessarie: Set<TipoAnalisi> { [] }
}

/// Luminosità, contrasto e saturazione (base delle future «regolazioni»). Tutti a 0: spento.
/// I valori vanno da -1 a 1; 0 lascia l'immagine com'è.
final class RegolazioniBase: Effetto, @unchecked Sendable {
    struct Valori: Equatable, Sendable {
        var luminosita: Double = 0
        var contrasto: Double = 0
        var saturazione: Double = 0
    }

    let nome = "Regolazioni"
    private let blocco = NSLock()
    private var interni = Valori()

    var valori: Valori {
        get { blocco.withLock { interni } }
        set {
            let limitati = Valori(luminosita: Self.limita(newValue.luminosita),
                                  contrasto: Self.limita(newValue.contrasto),
                                  saturazione: Self.limita(newValue.saturazione))
            blocco.withLock { interni = limitati }
        }
    }

    var attivo: Bool {
        valori != Valori()
    }

    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage {
        let attuali = valori
        // CIColorControls: luminosità -1…1 (troppo forte: se ne usa un quarto), contrasto e saturazione attorno a 1.
        return immagine.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: attuali.luminosita * 0.25,
            kCIInputContrastKey: 1 + attuali.contrasto * 0.5,
            kCIInputSaturationKey: 1 + attuali.saturazione
        ])
    }

    private static func limita(_ valore: Double) -> Double {
        valore.isFinite ? min(max(valore, -1), 1) : 0
    }
}

// MARK: - Pipeline

/// Tra la cattura e il codificatore: riceve ogni fotogramma e ritorna quello da codificare.
///
/// - Nessun effetto attivo: ritorna lo stesso buffer, intatto (nessuna copia, nessun ritardo).
/// - Effetti attivi: li applica in ordine con un solo `CIContext` su Metal, e scrive in un buffer nuovo
///   (stesso formato pixel della cattura, IOSurface, stessi allegati di colore) preso da un pool.
/// - Tutto sulla coda di cattura, in modo sincrono. Se la resa resta indietro rispetto ai fotogrammi al
///   secondo si passa a `QualitaEffetti.ridotta`; se non basta, gli effetti si sospendono per qualche
///   secondo e il video passa intatto: la cattura non si ferma mai per un effetto.
///
/// L'orientamento non cambia: la cattura consegna buffer già girati (e specchiati) dalla connessione, e
/// l'istante resta quello del fotogramma d'origine (lo passa chi chiama al codificatore).
///
/// Anteprima (`anteprimaConEffetti`): per ora sul telefono si vede l'immagine grezza
/// (`AVCaptureVideoPreviewLayer`, il ritardo più basso). Quando gli effetti avranno un'interfaccia
/// l'idea è: con `anteprimaConEffetti` vero e almeno un effetto attivo, mostrare i buffer elaborati in un
/// `AVSampleBufferDisplayLayer` sopra l'anteprima grezza (stesso buffer che va al codificatore, nessuna resa
/// in più); senza effetti si torna all'anteprima grezza. Il tocco per il fuoco continua a usare il livello grezzo.
final class PipelineEffetti: @unchecked Sendable {
    /// Nota di progetto, non ancora usata: vedi il commento della classe.
    // TODO: anteprima con effetti (AVSampleBufferDisplayLayer) quando gli effetti avranno un'interfaccia.
    static let anteprimaConEffetti = false

    /// Volti e persona, a frequenza ridotta e su un'altra coda.
    let analisi = AnalisiFotogramma()
    /// Sempre nell'elenco; spenta finché i valori sono a 0.
    let regolazioni = RegolazioniBase()

    private let blocco = NSLock()
    /// In ordine di applicazione. Protetto da `blocco`.
    private var elenco: [any Effetto] = []
    /// Protetti da `blocco`: il contesto si crea in sottofondo la prima volta che un effetto si accende.
    private var contesto: CIContext?
    private var contestoInPreparazione = false

    // Solo sulla coda di cattura.
    private var pool: CVPixelBufferPool?
    private var formatoPool: (formato: OSType, larghezza: Int, altezza: Int)?
    private var fotogrammiSenzaEffetti = 0
    private var ultimoIstante: CMTime = .invalid
    /// La durata di un fotogramma: il tempo a disposizione per la resa.
    private var tempoFotogramma: Double = 1.0 / 30
    /// Media mobile del tempo di resa, in secondi.
    private var mediaResa: Double = 0
    private var qualita: QualitaEffetti = .piena
    private var fotogrammiVeloci = 0
    private var sospesiFino: TimeInterval = 0

    /// Senza effetti per circa 4 secondi si libera il pool (memoria).
    private static let fotogrammiPrimaDiLiberare = 120
    /// Buffer elaborati in giro al massimo (codificatore compreso): oltre si salta l'effetto, non si aspetta.
    private static let sogliaBuffer = 8

    init() {
        elenco = [regolazioni]
    }

    // MARK: Elenco degli effetti (da qualsiasi thread)

    var effetti: [any Effetto] {
        blocco.withLock { elenco }
    }

    /// Aggiunge un effetto in fondo (si applica dopo quelli già presenti), o nella posizione data.
    func aggiungi(_ effetto: any Effetto, in posizione: Int? = nil) {
        blocco.withLock {
            guard !elenco.contains(where: { $0 === effetto }) else { return }
            if let posizione {
                elenco.insert(effetto, at: min(max(posizione, 0), elenco.count))
            } else {
                elenco.append(effetto)
            }
        }
    }

    func rimuovi(_ effetto: any Effetto) {
        blocco.withLock { elenco.removeAll { $0 === effetto } }
    }

    // MARK: Fotogrammi (solo sulla coda di cattura)

    /// Il buffer da codificare. Senza effetti attivi è `ingresso` stesso.
    func elabora(_ ingresso: CVPixelBuffer, istante: CMTime) -> CVPixelBuffer {
        let attivi = effetti.filter { $0.attivo }
        var richieste = Set<TipoAnalisi>()
        for effetto in attivi { richieste.formUnion(effetto.analisiNecessarie) }
        analisi.considera(ingresso, istante: istante, ancheSenzaConsumatori: richieste)

        guard !attivi.isEmpty else {
            liberaSeInutile()
            return ingresso
        }
        fotogrammiSenzaEffetti = 0
        misuraTempoFotogramma(istante)

        let adesso = ProcessInfo.processInfo.systemUptime
        guard adesso >= sospesiFino else { return ingresso }
        guard let contesto = contestoPronto() else { return ingresso }
        guard let uscita = bufferDiUscita(come: ingresso) else { return ingresso }
        // Matrice YCbCr, primarie e curva di trasferimento come la cattura: il codificatore e Core Image le usano.
        CVBufferPropagateAttachments(ingresso, uscita)

        let originale = CIImage(cvPixelBuffer: ingresso)
        let estensione = originale.extent
        let info = InfoFotogramma(istante: istante,
                                  larghezza: CVPixelBufferGetWidth(ingresso),
                                  altezza: CVPixelBufferGetHeight(ingresso),
                                  qualita: qualita,
                                  volti: analisi.ultimiVolti,
                                  maschera: analisi.ultimaMaschera)
        var immagine = originale
        for effetto in attivi {
            immagine = effetto.applica(immagine, contesto: info)
        }
        immagine = immagine.cropped(to: estensione)

        let destinazione = CIRenderDestination(pixelBuffer: uscita)
        if let spazio = Self.spazioUscita { destinazione.colorSpace = spazio }
        do {
            let compito = try contesto.startTask(toRender: immagine, to: destinazione)
            _ = try compito.waitUntilCompleted()
        } catch {
            return ingresso
        }
        regolaQualita(durata: ProcessInfo.processInfo.systemUptime - adesso, adesso: adesso)
        return uscita
    }

    /// Prima del `benvenuto` non si codifica nulla, ma le analisi chieste (per esempio «Prova la webcam») vanno.
    func osserva(_ ingresso: CVPixelBuffer, istante: CMTime) {
        analisi.considera(ingresso, istante: istante, ancheSenzaConsumatori: [])
    }

    // MARK: Interni

    private static let spazioUscita = CGColorSpace(name: CGColorSpace.itur_709)

    /// Il contesto se è pronto; altrimenti lo prepara in sottofondo e intanto il video passa intatto.
    private func contestoPronto() -> CIContext? {
        let (pronto, daPreparare): (CIContext?, Bool) = blocco.withLock {
            if let contesto { return (contesto, false) }
            if contestoInPreparazione { return (nil, false) }
            contestoInPreparazione = true
            return (nil, true)
        }
        if daPreparare {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let nuovo = Self.creaContesto()
                guard let self else { return }
                self.blocco.withLock {
                    self.contesto = nuovo
                    self.contestoInPreparazione = false
                }
            }
        }
        return pronto
    }

    /// Un solo contesto per tutta la sessione, su Metal; niente cache delle immagini intermedie (video dal vivo).
    private static func creaContesto() -> CIContext {
        var opzioni: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let lineare = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) {
            opzioni[.workingColorSpace] = lineare
        }
        if let spazio = spazioUscita {
            opzioni[.outputColorSpace] = spazio
        }
        if let dispositivo = MTLCreateSystemDefaultDevice(), let codaComandi = dispositivo.makeCommandQueue() {
            return CIContext(mtlCommandQueue: codaComandi, options: opzioni)
        }
        return CIContext(options: opzioni)
    }

    /// Un buffer vuoto dal pool, con formato e dimensioni della cattura. `nil` se il pool è esaurito.
    private func bufferDiUscita(come ingresso: CVPixelBuffer) -> CVPixelBuffer? {
        let formato = CVPixelBufferGetPixelFormatType(ingresso)
        let larghezza = CVPixelBufferGetWidth(ingresso)
        let altezza = CVPixelBufferGetHeight(ingresso)
        if pool == nil || formatoPool?.formato != formato || formatoPool?.larghezza != larghezza
            || formatoPool?.altezza != altezza {
            pool = Self.creaPool(formato: formato, larghezza: larghezza, altezza: altezza)
            formatoPool = (formato, larghezza, altezza)
        }
        guard let pool else { return nil }
        let soglia = [kCVPixelBufferPoolAllocationThresholdKey as String: Self.sogliaBuffer] as CFDictionary
        var uscita: CVPixelBuffer?
        let esito = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, soglia, &uscita)
        guard esito == kCVReturnSuccess else { return nil }
        return uscita
    }

    private static func creaPool(formato: OSType, larghezza: Int, altezza: Int) -> CVPixelBufferPool? {
        let attributiBuffer: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: formato,
            kCVPixelBufferWidthKey as String: larghezza,
            kCVPixelBufferHeightKey as String: altezza,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let attributiPool: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
        var pool: CVPixelBufferPool?
        let esito = CVPixelBufferPoolCreate(kCFAllocatorDefault, attributiPool as CFDictionary,
                                            attributiBuffer as CFDictionary, &pool)
        return esito == kCVReturnSuccess ? pool : nil
    }

    /// La durata di un fotogramma dagli istanti consecutivi (tiene conto di 24, 30 e 60 fps senza chiederli).
    private func misuraTempoFotogramma(_ istante: CMTime) {
        defer { ultimoIstante = istante }
        guard ultimoIstante.isValid, istante.isValid else { return }
        let differenza = CMTimeSubtract(istante, ultimoIstante).seconds
        // Fuori da 15…120 fps è un salto (fotogrammi scartati, riconfigurazione): non conta.
        if differenza.isFinite, differenza >= 1.0 / 120, differenza <= 1.0 / 15 {
            tempoFotogramma = differenza
        }
    }

    /// Più lento di un fotogramma: qualità ridotta. Ancora più lento con la qualità ridotta: effetti sospesi
    /// per 3 secondi. Torna alla qualità piena dopo un paio di secondi ben sotto il tempo a disposizione.
    private func regolaQualita(durata: TimeInterval, adesso: TimeInterval) {
        mediaResa = mediaResa == 0 ? durata : mediaResa * 0.8 + durata * 0.2
        switch qualita {
        case .piena:
            if mediaResa > tempoFotogramma {
                qualita = .ridotta
                fotogrammiVeloci = 0
            }
        case .ridotta:
            if mediaResa > tempoFotogramma * 1.5 {
                sospesiFino = adesso + 3
                mediaResa = 0
                fotogrammiVeloci = 0
            } else if mediaResa < tempoFotogramma * 0.5 {
                fotogrammiVeloci += 1
                if fotogrammiVeloci >= 60 {
                    qualita = .piena
                    fotogrammiVeloci = 0
                }
            } else {
                fotogrammiVeloci = 0
            }
        }
    }

    private func liberaSeInutile() {
        guard pool != nil else { return }
        fotogrammiSenzaEffetti += 1
        if fotogrammiSenzaEffetti >= Self.fotogrammiPrimaDiLiberare {
            pool = nil
            formatoPool = nil
            fotogrammiSenzaEffetti = 0
            mediaResa = 0
            qualita = .piena
            ultimoIstante = .invalid
        }
    }
}

// MARK: - Analisi

/// Le analisi del fotogramma che più funzioni condividono (inquadratura automatica, luce sul viso, postura,
/// «Prova la webcam»…).
enum TipoAnalisi: Hashable, Sendable {
    /// Rettangoli dei volti (`VNDetectFaceRectanglesRequest`).
    case volti
    /// Maschera della persona (`VNGeneratePersonSegmentationRequest`), per sfondo e luce.
    case persona
}

/// Coordinate normalizzate 0…1 nel fotogramma già girato dritto, origine in basso a sinistra
/// (come Vision e Core Image: per un `CIImage` basta moltiplicare per l'estensione).
struct VoltiRilevati: Sendable {
    let rettangoli: [CGRect]
    /// Istante del fotogramma analizzato.
    let istante: CMTime
    /// `ProcessInfo.systemUptime` alla fine dell'analisi: per capire quanto è vecchio il risultato.
    let quando: TimeInterval
}

/// Maschera a un canale (8 bit, 255 = persona), più piccola del fotogramma: va scalata sull'estensione.
struct MascheraPersona: @unchecked Sendable {
    let maschera: CVPixelBuffer
    let istante: CMTime
    let quando: TimeInterval
}

/// Analisi Vision a frequenza ridotta, su una coda sua: la cattura non aspetta mai.
/// Gira solo se qualcuno la chiede (`richiedi`) o se un effetto attivo ne ha bisogno; i risultati restano
/// in `ultimiVolti` e `ultimaMaschera`, con l'istante del fotogramma da cui vengono.
final class AnalisiFotogramma: @unchecked Sendable {
    /// Un fotogramma ogni `passo` (a 30 fps: 10 analisi al secondo).
    var passo: Int {
        get { blocco.withLock { passoInterno } }
        set { blocco.withLock { passoInterno = max(1, newValue) } }
    }

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.analisi", qos: .userInitiated)
    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var passoInterno = 3
    private var consumatori: [TipoAnalisi: Set<String>] = [:]
    private var contatore = 0
    private var inCorso = false
    private var volti: VoltiRilevati?
    private var maschera: MascheraPersona?
    // Solo su `coda`.
    private let gestore = VNSequenceRequestHandler()
    private let richiestaVolti = VNDetectFaceRectanglesRequest()
    private lazy var richiestaPersona: VNGeneratePersonSegmentationRequest = {
        let richiesta = VNGeneratePersonSegmentationRequest()
        richiesta.qualityLevel = .balanced
        richiesta.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return richiesta
    }()

    /// Un consumatore (per esempio "inquadratura") vuole questa analisi finché non chiama `rinuncia`.
    func richiedi(_ tipo: TipoAnalisi, per consumatore: String) {
        blocco.withLock { consumatori[tipo, default: []].insert(consumatore) }
    }

    func rinuncia(_ tipo: TipoAnalisi, per consumatore: String) {
        blocco.withLock {
            consumatori[tipo]?.remove(consumatore)
            if consumatori[tipo]?.isEmpty ?? true {
                consumatori[tipo] = nil
                // Nessuno la vuole più: un risultato vecchio non deve ricomparire alla prossima richiesta.
                switch tipo {
                case .volti: volti = nil
                case .persona: maschera = nil
                }
            }
        }
    }

    /// Gli ultimi volti trovati; `nil` se nessuno li ha chiesti o non è ancora finita la prima analisi.
    var ultimiVolti: VoltiRilevati? {
        blocco.withLock { volti }
    }

    var ultimaMaschera: MascheraPersona? {
        blocco.withLock { maschera }
    }

    /// Dalla coda di cattura, per ogni fotogramma. Ritorna subito: l'analisi, se tocca, va sulla sua coda.
    /// Se la precedente non è finita questo fotogramma si salta.
    func considera(_ immagine: CVPixelBuffer, istante: CMTime, ancheSenzaConsumatori extra: Set<TipoAnalisi>) {
        let tipi: Set<TipoAnalisi> = blocco.withLock {
            var tipi = extra
            for (tipo, nomi) in consumatori where !nomi.isEmpty { tipi.insert(tipo) }
            guard !tipi.isEmpty else {
                contatore = 0
                return []
            }
            contatore += 1
            guard contatore >= passoInterno, !inCorso else { return [] }
            contatore = 0
            inCorso = true
            return tipi
        }
        guard !tipi.isEmpty else { return }
        coda.async { [weak self] in
            self?.analizza(immagine, istante: istante, tipi: tipi)
        }
    }

    /// Solo su `coda`. Il buffer della cattura si tiene per pochi millisecondi.
    private func analizza(_ immagine: CVPixelBuffer, istante: CMTime, tipi: Set<TipoAnalisi>) {
        var richieste: [VNRequest] = []
        if tipi.contains(.volti) { richieste.append(richiestaVolti) }
        if tipi.contains(.persona) { richieste.append(richiestaPersona) }
        // La cattura consegna buffer già dritti: orientamento `.up`.
        let riuscita = (try? gestore.perform(richieste, on: immagine, orientation: .up)) != nil
        let quando = ProcessInfo.processInfo.systemUptime

        var nuoviVolti: VoltiRilevati?
        var nuovaMaschera: MascheraPersona?
        if riuscita, tipi.contains(.volti) {
            let rettangoli = (richiestaVolti.results ?? []).map(\.boundingBox)
            nuoviVolti = VoltiRilevati(rettangoli: rettangoli, istante: istante, quando: quando)
        }
        if riuscita, tipi.contains(.persona), let risultato = richiestaPersona.results?.first {
            nuovaMaschera = MascheraPersona(maschera: risultato.pixelBuffer, istante: istante, quando: quando)
        }

        blocco.withLock {
            inCorso = false
            if let nuoviVolti { volti = nuoviVolti }
            if let nuovaMaschera { maschera = nuovaMaschera }
        }
    }
}
