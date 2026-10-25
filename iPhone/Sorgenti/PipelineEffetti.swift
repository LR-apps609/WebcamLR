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
    /// Da coordinate del fotogramma d'origine (pixel, origine in basso a sinistra) a coordinate dell'immagine che
    /// riceve questo effetto: la somma delle `trasformazione(per:)` degli effetti prima (per esempio lo zoom
    /// dell'inquadratura). Volti e maschera vanno portati sull'immagine con questa (vedi `inImmagine`).
    var trasformazione: CGAffineTransform = .identity
}

/// In che punto della catena va un effetto (B2): sfondo → pelle → doppia vista → inquadratura → filtro → regolazioni → scritta.
/// `PipelineEffetti.aggiungi(_:fase:)` lo mette al posto giusto, qualunque sia l'ordine in cui si aggiungono.
/// Sfondo e pelle usano maschera e volti nelle coordinate del fotogramma intero: vanno prima dello zoom
/// dell'inquadratura. La scritta va dopo, così non si ritaglia.
enum FaseEffetto: Int, Comparable, Sendable {
    case sfondo = 10
    case pelle = 20
    /// Volto e scrivania (P09, `EffettoDoppiaVista`): ricompone il fotogramma, prima di zoom, colore e scritta.
    case doppiaVista = 24
    /// Inquadratura automatica (zoom digitale, `InquadraturaAutomatica`).
    case inquadratura = 25
    case filtro = 30
    case regolazioni = 35
    /// Scritte e logo: per ultime, sopra a tutto e mai toccate da filtri o sfocature.
    case scritta = 40

    static func < (a: FaseEffetto, b: FaseEffetto) -> Bool { a.rawValue < b.rawValue }
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
    /// Chiamata subito dopo `applica`, per lo stesso fotogramma: come l'effetto ha spostato i pixel (coordinate
    /// dell'ingresso → coordinate dell'uscita). Solo gli effetti geometrici (inquadratura) la cambiano; gli effetti
    /// dopo la ricevono in `InfoFotogramma.trasformazione` per mettere volti e maschera al posto giusto.
    func trasformazione(per contesto: InfoFotogramma) -> CGAffineTransform
    /// 1.14: sulla coda di cattura, prima del primo fotogramma con la geometria nuova (altro obiettivo, telefono
    /// girato, specchio cambiato dal vivo). Chi tiene uno stato legato alle coordinate (zoom, maschera mediata,
    /// centro del volto) lo adegua o lo azzera: volti e maschere vecchi l'analisi li ha già scartati.
    func geometriaCambiata(_ cambio: CambioGeometria)
    /// 1.14: cambia l'inquadratura o il contenuto del video (zoom, doppia vista, scritta): quando la resa è in
    /// affanno non si salta mai (il video non deve saltare tra zoom e niente zoom); si saltano solo gli effetti di
    /// aspetto (filtro, sfondo, pelle, regolazioni).
    var essenziale: Bool { get }
    /// 1.14: sposta solo i pixel (ritaglio e scala), senza toccare i colori. Se sono attivi solo effetti così, la
    /// resa usa un contesto senza gestione del colore, a 8 bit: costa molto meno (per esempio la sola inquadratura).
    var soloGeometria: Bool { get }
}

extension Effetto {
    var analisiNecessarie: Set<TipoAnalisi> { [] }
    var essenziale: Bool { false }
    var soloGeometria: Bool { false }
    func trasformazione(per contesto: InfoFotogramma) -> CGAffineTransform { .identity }
    func geometriaCambiata(_ cambio: CambioGeometria) {}
}

extension InfoFotogramma {
    /// Un rettangolo normalizzato di Vision (volti) in pixel dell'immagine che riceve l'effetto.
    func inImmagine(_ normalizzato: CGRect) -> CGRect {
        CGRect(x: normalizzato.minX * CGFloat(larghezza), y: normalizzato.minY * CGFloat(altezza),
               width: normalizzato.width * CGFloat(larghezza), height: normalizzato.height * CGFloat(altezza))
            .applying(trasformazione)
    }
}

/// Luminosità, contrasto, saturazione e nitidezza (le «regolazioni» del protocollo, P13). Tutti a 0: spento.
/// I valori vanno da -1 a 1; 0 lascia l'immagine com'è.
final class RegolazioniBase: Effetto, @unchecked Sendable {
    struct Valori: Equatable, Sendable {
        var luminosita: Double = 0
        var contrasto: Double = 0
        var saturazione: Double = 0
        var nitidezza: Double = 0
    }

    let nome = "Regolazioni"
    private let blocco = NSLock()
    private var interni = Valori()

    var valori: Valori {
        get { blocco.withLock { interni } }
        set {
            let limitati = Valori(luminosita: Self.limita(newValue.luminosita),
                                  contrasto: Self.limita(newValue.contrasto),
                                  saturazione: Self.limita(newValue.saturazione),
                                  nitidezza: Self.limita(newValue.nitidezza))
            blocco.withLock { interni = limitati }
        }
    }

    var attivo: Bool {
        valori != Valori()
    }

    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage {
        let attuali = valori
        var risultato = immagine
        if attuali.luminosita != 0 || attuali.contrasto != 0 || attuali.saturazione != 0 {
            // CIColorControls: luminosità -1…1 (troppo forte: se ne usa un quarto), contrasto e saturazione attorno a 1.
            risultato = risultato.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: attuali.luminosita * 0.25,
                kCIInputContrastKey: 1 + attuali.contrasto * 0.5,
                kCIInputSaturationKey: 1 + attuali.saturazione
            ])
        }
        if attuali.nitidezza > 0 {
            // Solo sulla luminanza: niente aloni colorati. Fino a 0,8 (oltre si vedono i bordi «disegnati»).
            risultato = risultato.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: attuali.nitidezza * 0.8
            ])
        } else if attuali.nitidezza < 0 {
            // Negativa: un velo morbido, al massimo 1,5 pixel a 1080p.
            let raggio = -attuali.nitidezza * 1.5 * Double(max(contesto.altezza, 1)) / 1080
            risultato = risultato.clampedToExtent().applyingGaussianBlur(sigma: raggio).cropped(to: immagine.extent)
        }
        return risultato
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
///   secondo si passa a `QualitaEffetti.ridotta`; se non basta, gli effetti di aspetto si sospendono per qualche
///   secondo (sempre di più se torna l'affanno). Quelli `essenziale` (inquadratura, doppia vista, scritta)
///   restano: il video non salta tra zoom e niente zoom. La cattura non si ferma mai per un effetto: al peggio
///   scarta qualche fotogramma in ritardo.
///
/// L'orientamento non cambia: la cattura consegna buffer già girati (e specchiati) dalla connessione, e
/// l'istante resta quello del fotogramma d'origine (lo passa chi chiama al codificatore).
///
/// Anteprima (`anteprimaConEffetti`, B2): con almeno un effetto attivo il telefono mostra i buffer elaborati
/// in `anteprima` (un `AVSampleBufferDisplayLayer` sopra l'anteprima grezza: lo stesso buffer che va al
/// codificatore, nessuna resa in più); senza effetti il livello si nasconde e resta l'anteprima grezza
/// (`AVCaptureVideoPreviewLayer`, il ritardo più basso, costo zero). Mai tutti e due visibili insieme, e con lo
/// stesso specchio (1.14). Il tocco per il fuoco passa per il rettangolo del video (`Cattura.puntoNelVideo`).
final class PipelineEffetti: @unchecked Sendable {
    /// Con effetti attivi l'anteprima del telefono mostra il video elaborato (vedi il commento della classe).
    static let anteprimaConEffetti = true

    /// Il video elaborato per l'anteprima del telefono e le istantanee per le miniature dei filtri.
    let anteprima = AnteprimaEffetti()

    /// Volti e persona, a frequenza ridotta e su un'altra coda.
    let analisi = AnalisiFotogramma()
    /// Sempre nell'elenco; spenta finché i valori sono a 0.
    let regolazioni = RegolazioniBase()

    private let blocco = NSLock()
    /// In ordine di applicazione. Protetto da `blocco`.
    private var elenco: [any Effetto] = []
    /// La fase di chi è stato aggiunto con `aggiungi(_:fase:)`. Protetto da `blocco`.
    private var fasi: [ObjectIdentifier: FaseEffetto] = [:]
    /// Protetti da `blocco`: i contesti si creano in sottofondo la prima volta che un effetto si accende.
    /// `pieno`: con la gestione del colore (lineare, mezza precisione); `geometrico`: senza, per i soli ritagli.
    private var contesti: (pieno: CIContext, geometrico: CIContext)?
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
    /// Fino a quando gli effetti di aspetto restano sospesi, e quante sospensioni di fila (la prossima dura di più).
    private var sospesiFino: TimeInterval = 0
    private var sospensioniDiFila = 0

    /// Senza effetti per circa 4 secondi si libera il pool (memoria).
    private static let fotogrammiPrimaDiLiberare = 120
    /// Buffer elaborati in giro al massimo (codificatore compreso): oltre si salta l'effetto, non si aspetta.
    private static let sogliaBuffer = 8

    init() {
        elenco = [regolazioni]
        fasi[ObjectIdentifier(regolazioni)] = .regolazioni
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

    /// Aggiunge un effetto al posto della sua fase: prima del primo effetto di una fase successiva (gli effetti
    /// aggiunti senza fase non contano e restano dove sono), altrimenti in fondo. È l'unico punto che decide
    /// l'ordine: chi aggiunge un effetto dice solo la sua fase.
    func aggiungi(_ effetto: any Effetto, fase: FaseEffetto) {
        blocco.withLock {
            guard !elenco.contains(where: { $0 === effetto }) else { return }
            fasi[ObjectIdentifier(effetto)] = fase
            let posizione = elenco.firstIndex { esistente in
                guard let altra = fasi[ObjectIdentifier(esistente)] else { return false }
                return altra > fase
            } ?? elenco.count
            elenco.insert(effetto, at: posizione)
        }
    }

    func rimuovi(_ effetto: any Effetto) {
        blocco.withLock {
            elenco.removeAll { $0 === effetto }
            fasi[ObjectIdentifier(effetto)] = nil
        }
    }

    // MARK: Fotogrammi (solo sulla coda di cattura)

    /// 1.14: la geometria dei fotogrammi è cambiata (`Cattura.suCambioGeometria`, sulla coda di cattura): l'analisi
    /// scarta i risultati vecchi e gli effetti adeguano il loro stato prima del prossimo fotogramma.
    func geometriaCambiata(_ cambio: CambioGeometria) {
        analisi.nuovaGenerazione()
        for effetto in effetti { effetto.geometriaCambiata(cambio) }
    }

    /// Il buffer da codificare. Senza effetti attivi è `ingresso` stesso.
    /// Con effetti attivi lo stesso buffer va anche all'anteprima del telefono (`anteprima`).
    func elabora(_ ingresso: CVPixelBuffer, istante: CMTime) -> CVPixelBuffer {
        anteprima.considera(ingresso)
        let (uscita, conEffetti) = applicaEffetti(ingresso, istante: istante)
        if conEffetti {
            anteprima.mostra(uscita)
        } else {
            anteprima.spegni()
        }
        return uscita
    }

    /// Il buffer da codificare e se c'era almeno un effetto attivo (anche se poi è stato saltato).
    private func applicaEffetti(_ ingresso: CVPixelBuffer, istante: CMTime) -> (CVPixelBuffer, Bool) {
        let attivi = effetti.filter { $0.attivo }
        var richieste = Set<TipoAnalisi>()
        for effetto in attivi { richieste.formUnion(effetto.analisiNecessarie) }
        analisi.considera(ingresso, istante: istante, ancheSenzaConsumatori: richieste)

        guard !attivi.isEmpty else {
            liberaSeInutile()
            return (ingresso, false)
        }
        fotogrammiSenzaEffetti = 0
        misuraTempoFotogramma(istante)

        let adesso = ProcessInfo.processInfo.systemUptime
        // In affanno: restano solo gli effetti essenziali (inquadratura, doppia vista, scritta).
        let sospesi = adesso < sospesiFino
        let daApplicare = sospesi ? attivi.filter { $0.essenziale } : attivi
        guard !daApplicare.isEmpty else { return (ingresso, true) }
        let geometrico = daApplicare.allSatisfy { $0.soloGeometria }
        guard let pronti = contestiPronti() else { return (ingresso, true) }
        guard let uscita = bufferDiUscita(come: ingresso) else { return (ingresso, true) }
        Self.copiaAllegatiColore(da: ingresso, a: uscita)

        let originale = CIImage(cvPixelBuffer: ingresso)
        let estensione = originale.extent
        let info = InfoFotogramma(istante: istante,
                                  larghezza: CVPixelBufferGetWidth(ingresso),
                                  altezza: CVPixelBufferGetHeight(ingresso),
                                  qualita: qualita,
                                  volti: analisi.ultimiVolti,
                                  maschera: analisi.ultimaMaschera)
        var immagine = originale
        var infoEffetto = info
        for effetto in daApplicare {
            immagine = effetto.applica(immagine, contesto: infoEffetto)
            let spostamento = effetto.trasformazione(per: infoEffetto)
            if !spostamento.isIdentity {
                infoEffetto.trasformazione = infoEffetto.trasformazione.concatenating(spostamento)
            }
        }
        // 1.14: sopra un nero opaco grande quanto il fotogramma: ogni pixel del buffer (riusato dal pool) si scrive a
        // ogni fotogramma, anche se un effetto lasciasse un bordo vuoto o trasparente.
        immagine = immagine.cropped(to: estensione).composited(over: Self.nero.cropped(to: estensione))

        let destinazione = CIRenderDestination(pixelBuffer: uscita)
        // Solo ritagli: nessuna conversione di colore (YCbCr → RGB → YCbCr con la matrice degli allegati).
        destinazione.colorSpace = geometrico ? nil : Self.spazioUscita
        do {
            let compito = try (geometrico ? pronti.geometrico : pronti.pieno).startTask(toRender: immagine, to: destinazione)
            _ = try compito.waitUntilCompleted()
        } catch {
            return (ingresso, true)
        }
        regolaQualita(durata: ProcessInfo.processInfo.systemUptime - adesso, adesso: adesso,
                      siPuoSospendere: !sospesi && daApplicare.contains { !$0.essenziale })
        return (uscita, true)
    }

    /// Prima del `benvenuto` non si codifica nulla, ma le analisi chieste (per esempio «Prova la webcam») vanno.
    /// Con effetti attivi si elabora lo stesso, solo per l'anteprima del telefono: l'utente li vede da subito.
    func osserva(_ ingresso: CVPixelBuffer, istante: CMTime) {
        if effetti.contains(where: { $0.attivo }) {
            _ = elabora(ingresso, istante: istante)
            return
        }
        anteprima.considera(ingresso)
        anteprima.spegni()
        analisi.considera(ingresso, istante: istante, ancheSenzaConsumatori: [])
    }

    // MARK: Interni

    private static let spazioUscita = CGColorSpace(name: CGColorSpace.itur_709)
    private static let nero = CIImage(color: CIColor(red: 0, green: 0, blue: 0))

    /// Solo matrice YCbCr, primarie e curva di trasferimento, come la cattura: il codificatore e Core Image le usano.
    /// 1.14: non tutti gli allegati (`CVBufferPropagateAttachments`): un'apertura pulita (`CleanAperture`) o un
    /// rapporto dei pixel pensati per il fotogramma della cattura, applicati dall'anteprima o dal decodificatore al
    /// fotogramma già zoomato, lo taglierebbero o lo sposterebbero.
    private static let chiaviColore: [CFString] = [kCVImageBufferYCbCrMatrixKey, kCVImageBufferColorPrimariesKey,
                                                   kCVImageBufferTransferFunctionKey]

    private static func copiaAllegatiColore(da ingresso: CVPixelBuffer, a uscita: CVPixelBuffer) {
        for chiave in chiaviColore {
            if let valore = CVBufferCopyAttachment(ingresso, chiave, nil) {
                CVBufferSetAttachment(uscita, chiave, valore, .shouldPropagate)
            } else {
                CVBufferRemoveAttachment(uscita, chiave)
            }
        }
        // I buffer del pool si riusano: niente geometria rimasta da prima.
        CVBufferRemoveAttachment(uscita, kCVImageBufferCleanApertureKey)
        CVBufferRemoveAttachment(uscita, kCVImageBufferPixelAspectRatioKey)
    }

    /// I contesti se sono pronti; altrimenti li prepara in sottofondo e intanto il video passa intatto.
    private func contestiPronti() -> (pieno: CIContext, geometrico: CIContext)? {
        let (pronti, daPreparare): ((pieno: CIContext, geometrico: CIContext)?, Bool) = blocco.withLock {
            if let contesti { return (contesti, false) }
            if contestoInPreparazione { return (nil, false) }
            contestoInPreparazione = true
            return (nil, true)
        }
        if daPreparare {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let pieno = Self.creaContesto()
                let geometrico = Self.creaContestoGeometrico()
                guard let self else { return }
                self.blocco.withLock {
                    self.contesti = (pieno, geometrico)
                    self.contestoInPreparazione = false
                }
            }
        }
        return pronti
    }

    /// 1.14: per i soli ritagli (inquadratura): niente gestione del colore e lavoro a 8 bit. I valori passano come
    /// sono, quindi i colori restano quelli della cattura; costa una frazione del contesto pieno.
    private static func creaContestoGeometrico() -> CIContext {
        let opzioni: [CIContextOption: Any] = [
            .cacheIntermediates: false,
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .workingFormat: NSNumber(value: CIFormat.RGBA8.rawValue)
        ]
        if let dispositivo = MTLCreateSystemDefaultDevice(), let codaComandi = dispositivo.makeCommandQueue() {
            return CIContext(mtlCommandQueue: codaComandi, options: opzioni)
        }
        return CIContext(options: opzioni)
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

    /// Più lento di un fotogramma: qualità ridotta. Ancora più lento con la qualità ridotta: effetti di aspetto
    /// sospesi per 3 secondi, poi 6, 12, fino a 30 se l'affanno torna subito. Torna alla qualità piena (e la prossima
    /// sospensione torna a 3 secondi) dopo un paio di secondi ben sotto il tempo a disposizione.
    /// `siPuoSospendere`: falso se ci sono solo effetti essenziali (non si sospendono mai).
    private func regolaQualita(durata: TimeInterval, adesso: TimeInterval, siPuoSospendere: Bool) {
        mediaResa = mediaResa == 0 ? durata : mediaResa * 0.8 + durata * 0.2
        switch qualita {
        case .piena:
            if mediaResa > tempoFotogramma {
                qualita = .ridotta
                fotogrammiVeloci = 0
            }
        case .ridotta:
            if mediaResa > tempoFotogramma * 1.5 && siPuoSospendere {
                sospesiFino = adesso + min(3 * pow(2, Double(sospensioniDiFila)), 30)
                sospensioniDiFila = min(sospensioniDiFila + 1, 4)
                mediaResa = 0
                fotogrammiVeloci = 0
            } else if mediaResa < tempoFotogramma * 0.5 {
                fotogrammiVeloci += 1
                if fotogrammiVeloci >= 60 {
                    qualita = .piena
                    fotogrammiVeloci = 0
                    sospensioniDiFila = 0
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

/// Analisi Vision a frequenza ridotta (10 al secondo), su una coda sua: la cattura non aspetta mai.
/// Gira solo se qualcuno la chiede (`richiedi`) o se un effetto attivo ne ha bisogno; i risultati restano
/// in `ultimiVolti` e `ultimaMaschera`, con l'istante del fotogramma da cui vengono.
final class AnalisiFotogramma: @unchecked Sendable {
    /// Secondi minimi tra due analisi (1.14: a tempo, non a fotogrammi: 10 analisi al secondo a 24, 30 o 60 fps).
    var intervallo: TimeInterval {
        get { blocco.withLock { intervalloInterno } }
        set { blocco.withLock { intervalloInterno = max(0.02, newValue) } }
    }

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.analisi", qos: .userInitiated)
    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var intervalloInterno: TimeInterval = 0.1
    private var consumatori: [TipoAnalisi: Set<String>] = [:]
    /// Istante (secondi) dell'ultimo fotogramma mandato all'analisi.
    private var ultimaAnalisi: Double?
    private var inCorso = false
    /// 1.14: cresce a ogni cambio di geometria (obiettivo, rotazione, specchio): un'analisi partita prima non vale.
    private var generazione = 0
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

    /// 1.14: la geometria dei fotogrammi è cambiata: volti e maschera trovati prima puntano nel posto sbagliato.
    /// Si scartano subito, e anche il risultato dell'analisi in corso.
    func nuovaGenerazione() {
        blocco.withLock {
            generazione += 1
            volti = nil
            maschera = nil
            ultimaAnalisi = nil
        }
    }

    /// Dalla coda di cattura, per ogni fotogramma. Ritorna subito: l'analisi, se tocca, va sulla sua coda.
    /// Se la precedente non è finita questo fotogramma si salta.
    func considera(_ immagine: CVPixelBuffer, istante: CMTime, ancheSenzaConsumatori extra: Set<TipoAnalisi>) {
        let secondi = istante.seconds
        let (tipi, generazioneAttuale): (Set<TipoAnalisi>, Int) = blocco.withLock {
            var tipi = extra
            for (tipo, nomi) in consumatori where !nomi.isEmpty { tipi.insert(tipo) }
            guard !tipi.isEmpty else {
                ultimaAnalisi = nil
                return ([], generazione)
            }
            guard !inCorso else { return ([], generazione) }
            if let ultima = ultimaAnalisi, secondi.isFinite, secondi >= ultima, secondi - ultima < intervalloInterno {
                return ([], generazione)
            }
            ultimaAnalisi = secondi.isFinite ? secondi : nil
            inCorso = true
            return (tipi, generazione)
        }
        guard !tipi.isEmpty else { return }
        coda.async { [weak self] in
            self?.analizza(immagine, istante: istante, tipi: tipi, generazione: generazioneAttuale)
        }
    }

    /// Solo su `coda`. Il buffer della cattura si tiene per pochi millisecondi.
    private func analizza(_ immagine: CVPixelBuffer, istante: CMTime, tipi: Set<TipoAnalisi>, generazione: Int) {
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
            // Partita prima di un cambio di geometria: il risultato non vale più.
            guard generazione == self.generazione else { return }
            if let nuoviVolti { volti = nuoviVolti }
            if let nuovaMaschera { maschera = nuovaMaschera }
        }
    }
}
