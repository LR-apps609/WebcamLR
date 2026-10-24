import AVFoundation
import CoreImage
import CoreMedia
import QuartzCore
import VideoToolbox
import WebcamLRProtocollo

/// Trasforma i fotogrammi H.264 (Annex B) in campioni che `AVSampleBufferDisplayLayer`
/// decodifica e mostra da solo, con il decodificatore hardware del Mac (funzione 4).
/// In parallelo decodifica anche con VideoToolbox e tiene l'ultima immagine in BGRA:
/// serve per le foto (funzione 35) e, dal round 2, per la webcam virtuale.
/// Tutto il lavoro avviene sulla sua coda.
/// Dalla P21 c'è uno `Schermo` per ogni telefono collegato (più uno vuoto quando non ce n'è nessuno):
/// la finestra mini e la webcam virtuale prendono le immagini di quello scelto (`UscitaMini`, `UscitaWebcam`).
final class Schermo: @unchecked Sendable {
    let livello = AVSampleBufferDisplayLayer()
    /// Ogni immagine decodificata, sulla coda dello schermo (webcam virtuale e finestra mini, round 2 e P21).
    /// Si cambia con `inviaImmagini(a:)`: si legge sulla coda, quindi si scrive solo lì.
    private var suImmagine: ((CVPixelBuffer) -> Void)?
    /// La registrazione si è chiusa da sola (formato cambiato, disco pieno): il file e se è stato salvato.
    /// Arriva con `avviaRegistrazione`; solo sulla coda.
    private var suRegistrazioneInterrotta: (@Sendable (URL, Bool) -> Void)?

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.schermo", qos: .userInteractive)
    private var formato: CMVideoFormatDescription?
    private var attendiChiave = true
    /// Dal messaggio `formato` del telefono (funzione 10).
    private var codec: Codec = .h264
    private var sessioneDecodifica: VTDecompressionSession?
    private var formatoDecodifica: CMVideoFormatDescription?
    private var ultimaImmagine: CVPixelBuffer?
    private var registratore: Registratore?
    /// In attesa della prima immagine a schermo di una sessione (1.11): si chiama una volta e si toglie.
    private var avvisoMostrato: (@Sendable () -> Void)?
    /// Creato una volta: un CIContext nuovo a ogni foto costava decine di millisecondi.
    private let contestoFoto = CIContext()

    init() {
        livello.videoGravity = .resizeAspect
        livello.backgroundColor = CGColor(gray: 0, alpha: 1)
        // Con «riempi» l'immagine va oltre i bordi: si taglia lì.
        livello.masksToBounds = true
    }

    /// Riempi (il video copre tutto, tagliando i bordi) o adatta (si vede intero, con bande nere). Funzione 30.
    /// Da chiamare sulla coda principale, come ogni modifica ai livelli.
    func imposta(riempi: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        livello.videoGravity = riempi ? .resizeAspectFill : .resizeAspect
        CATransaction.commit()
    }

    /// Dove mandare ogni immagine decodificata (webcam virtuale e finestra mini); nil per nessuno.
    func inviaImmagini(a destinatario: ((CVPixelBuffer) -> Void)?) {
        coda.async { self.suImmagine = destinatario }
    }

    /// Il telefono ha annunciato un formato: se il codec cambia, si riparte dal prossimo fotogramma chiave.
    func imposta(codec nuovo: Codec) {
        coda.async {
            guard nuovo != self.codec else { return }
            self.codec = nuovo
            self.formato = nil
            self.attendiChiave = true
        }
    }

    /// `mostrato`: chiamata (sulla coda dello schermo) appena un'immagine, da questo fotogramma o dai seguenti,
    /// è decodificata e passata al livello: chiude la misura dell'avvio (1.11).
    func mostra(_ fotogramma: FotogrammaVideo, mostrato: (@Sendable () -> Void)? = nil) {
        coda.async {
            if let mostrato { self.avvisoMostrato = mostrato }
            self.accoda(fotogramma)
        }
    }

    func svuota() {
        coda.async {
            self.livello.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            self.formato = nil
            self.attendiChiave = true
            self.chiudiDecodifica()
            self.ultimaImmagine = nil
            self.avvisoMostrato = nil
        }
    }

    /// L'ultima immagine ricevuta, per una foto; nil se non c'è ancora video.
    func fotografa(_ completamento: @escaping @Sendable (CGImage?) -> Void) {
        coda.async {
            guard let immagine = self.ultimaImmagine else { return completamento(nil) }
            let ci = CIImage(cvPixelBuffer: immagine)
            completamento(self.contestoFoto.createCGImage(ci, from: ci.extent))
        }
    }

    private func accoda(_ fotogramma: FotogrammaVideo) {
        let unita = AnnexB.unita(in: fotogramma.dati)
        let hevc = codec == .hevc
        let tipo: (Data) -> UInt8 = hevc ? AnnexB.tipoHEVC : AnnexB.tipoH264

        if hevc {
            if let vps = unita.first(where: { tipo($0) == 32 }),
               let sps = unita.first(where: { tipo($0) == 33 }),
               let pps = unita.first(where: { tipo($0) == 34 }),
               let nuovo = Self.descrizioneHEVC(vps: vps, sps: sps, pps: pps) {
                formato = nuovo
            }
        } else if let sps = unita.first(where: { tipo($0) == 7 }),
                  let pps = unita.first(where: { tipo($0) == 8 }),
                  let nuovo = Self.descrizione(sps: sps, pps: pps) {
            formato = nuovo
        }

        if livello.sampleBufferRenderer.status == .failed {
            livello.sampleBufferRenderer.flush()
            attendiChiave = true
        }
        if attendiChiave {
            guard fotogramma.chiave else { return }
            attendiChiave = false
        }

        // Solo le unità con l'immagine: parametri e delimitatori stanno nel formato.
        let esclusi: Set<UInt8> = hevc ? [32, 33, 34, 35] : [7, 8, 9]
        let immagine = unita.filter { !esclusi.contains(tipo($0)) }
        guard let formatoAttuale = formato, !immagine.isEmpty,
              let campione = Self.campione(immagine, formato: formatoAttuale, chiave: fotogramma.chiave) else { return }
        livello.sampleBufferRenderer.enqueue(campione)
        registra(campione, formato: formatoAttuale, fotogramma: fotogramma)
        decodificaInImmagine(campione, formato: formatoAttuale)
        // Il livello mostra subito (DisplayImmediately) e la decodifica parallela è sincrona: l'immagine c'è.
        if let avviso = avvisoMostrato {
            avvisoMostrato = nil
            avviso()
        }
    }

    // MARK: - Registrazione (funzione 35)

    /// Inizia a salvare il video così come arriva, già compresso: niente perdita di qualità.
    /// `suInterruzione`: il file si è chiuso da solo (formato cambiato, disco pieno), con il file e se è stato salvato.
    func avviaRegistrazione(in file: URL, suInterruzione: @escaping @Sendable (URL, Bool) -> Void) {
        coda.async {
            self.registratore = Registratore(file: file)
            self.suRegistrazioneInterrotta = suInterruzione
        }
    }

    /// Chiude il file; `completamento` riceve il file, oppure nil se non è stato registrato nulla.
    func fermaRegistrazione(_ completamento: @escaping @Sendable (URL?) -> Void) {
        coda.async {
            guard let registratore = self.registratore else { return completamento(nil) }
            self.registratore = nil
            registratore.chiudi(completamento)
        }
    }

    private func registra(_ campione: CMSampleBuffer, formato: CMVideoFormatDescription, fotogramma: FotogrammaVideo) {
        guard let registratore else { return }
        if !registratore.aggiungi(campione, formato: formato, fotogramma: fotogramma) {
            // Il formato è cambiato (altro obiettivo, telefono girato) o il disco è pieno: il file si chiude qui,
            // e Riprese lo deve sapere, altrimenti continuerebbe a mostrare «Ferma».
            self.registratore = nil
            let file = registratore.file
            let avviso = suRegistrazioneInterrotta
            registratore.chiudi { fileSalvato in avviso?(file, fileSalvato != nil) }
        }
    }

    // MARK: - Decodifica in immagini

    private func decodificaInImmagine(_ campione: CMSampleBuffer, formato: CMVideoFormatDescription) {
        if sessioneDecodifica == nil || !CMFormatDescriptionEqual(formato, otherFormatDescription: formatoDecodifica) {
            creaDecodifica(formato)
        }
        guard let sessione = sessioneDecodifica else { return }
        // Sincrona: l'immagine arriva prima che la chiamata finisca, sulla stessa coda.
        let esito = VTDecompressionSessionDecodeFrame(sessione, sampleBuffer: campione, flags: [], infoFlagsOut: nil) {
            [weak self] stato, _, immagine, _, _ in
            guard stato == noErr, let immagine, let self else { return }
            self.ultimaImmagine = immagine
            self.suImmagine?(immagine)
        }
        // Dopo lo stop del Mac la sessione può non valere più: senza rifarla foto, finestra mini
        // e webcam virtuale resterebbero ferme sull'ultima immagine. Si rifà al prossimo fotogramma.
        if Int(esito) == Int(kVTInvalidSessionErr) { chiudiDecodifica() }
    }

    private func creaDecodifica(_ formato: CMVideoFormatDescription) {
        chiudiDecodifica()
        let attributi: NSDictionary = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        var nuova: VTDecompressionSession?
        let esito = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formato,
                                                 decoderSpecification: nil, imageBufferAttributes: attributi,
                                                 outputCallback: nil, decompressionSessionOut: &nuova)
        if esito == noErr {
            sessioneDecodifica = nuova
            formatoDecodifica = formato
        }
    }

    private func chiudiDecodifica() {
        if let sessioneDecodifica { VTDecompressionSessionInvalidate(sessioneDecodifica) }
        sessioneDecodifica = nil
        formatoDecodifica = nil
    }

    private static func descrizione(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var formato: CMVideoFormatDescription?
        let esito = sps.withUnsafeBytes { bytesSPS in
            pps.withUnsafeBytes { bytesPPS in
                let puntatori = [
                    bytesSPS.bindMemory(to: UInt8.self).baseAddress!,
                    bytesPPS.bindMemory(to: UInt8.self).baseAddress!
                ]
                let dimensioni = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: puntatori, parameterSetSizes: dimensioni,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &formato)
            }
        }
        return esito == noErr ? formato : nil
    }

    private static func descrizioneHEVC(vps: Data, sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var formato: CMVideoFormatDescription?
        let esito = vps.withUnsafeBytes { bytesVPS in
            sps.withUnsafeBytes { bytesSPS in
                pps.withUnsafeBytes { bytesPPS in
                    let puntatori = [
                        bytesVPS.bindMemory(to: UInt8.self).baseAddress!,
                        bytesSPS.bindMemory(to: UInt8.self).baseAddress!,
                        bytesPPS.bindMemory(to: UInt8.self).baseAddress!
                    ]
                    let dimensioni = [vps.count, sps.count, pps.count]
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: 3,
                        parameterSetPointers: puntatori, parameterSetSizes: dimensioni,
                        nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &formato)
                }
            }
        }
        return esito == noErr ? formato : nil
    }

    /// Da Annex B ad AVCC: ogni unità preceduta dalla sua lunghezza in 4 byte.
    private static func campione(_ unita: [Data], formato: CMVideoFormatDescription, chiave: Bool) -> CMSampleBuffer? {
        var avcc = Data()
        for nal in unita {
            let lunghezza = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: lunghezza) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }

        var bloccoCreato: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: avcc.count, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: avcc.count,
                                                 flags: 0, blockBufferOut: &bloccoCreato) == kCMBlockBufferNoErr,
              let blocco = bloccoCreato else { return nil }
        let copiato = avcc.withUnsafeBytes { byte in
            CMBlockBufferReplaceDataBytes(with: byte.baseAddress!, blockBuffer: blocco, offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copiato == kCMBlockBufferNoErr else { return nil }

        var campioneCreato: CMSampleBuffer?
        var dimensione = avcc.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: blocco, formatDescription: formato,
                                        sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &dimensione,
                                        sampleBufferOut: &campioneCreato) == noErr,
              let campione = campioneCreato else { return nil }

        if let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: true),
           CFArrayGetCount(allegati) > 0 {
            let allegato = unsafeBitCast(CFArrayGetValueAtIndex(allegati, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(allegato,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            // I fotogrammi non chiave vanno segnati: serve al file registrato per andare avanti e indietro.
            if !chiave {
                CFDictionarySetValue(allegato,
                                     Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                     Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return campione
    }

    /// Da mostrare appena arriva, senza orologio di presentazione: è il modo con meno latenza.
    static func mostraSubito(_ campione: CMSampleBuffer) {
        guard let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: true),
              CFArrayGetCount(allegati) > 0 else { return }
        let allegato = unsafeBitCast(CFArrayGetValueAtIndex(allegati, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(allegato,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
}

/// La finestra mini (funzione 21): un livello solo per tutti i telefoni, che riceve le immagini già decodificate
/// dello schermo scelto (P21), senza una seconda decodifica e senza aspettare il prossimo fotogramma chiave.
/// Ogni `Schermo` chiama `mostra` dalla sua coda: il lucchetto lascia passare solo la sorgente scelta,
/// così durante un cambio due schermi non mettono mai immagini nel livello insieme.
final class UscitaMini: @unchecked Sendable {
    let livello = AVSampleBufferDisplayLayer()
    private let blocco = NSLock()
    /// Lo schermo che va nella finestra mini; nil a finestra chiusa.
    private var sorgente: ObjectIdentifier?
    private var formato: CMVideoFormatDescription?

    init() {
        livello.videoGravity = .resizeAspect
        livello.backgroundColor = CGColor(gray: 0, alpha: 1)
        livello.masksToBounds = true
    }

    /// Come `Schermo.imposta(riempi:)`, sulla coda principale.
    func imposta(riempi: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        livello.videoGravity = riempi ? .resizeAspectFill : .resizeAspect
        CATransaction.commit()
    }

    /// Quale schermo mostrare; nil = finestra chiusa (o nessun telefono): il livello si svuota.
    /// Cambiando telefono l'ultima immagine resta finché arriva la prima del nuovo (un fotogramma).
    func scegli(_ nuova: ObjectIdentifier?) {
        blocco.lock()
        defer { blocco.unlock() }
        guard nuova != sorgente else { return }
        sorgente = nuova
        if nuova == nil {
            livello.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            formato = nil
        }
    }

    /// Dalla coda di uno `Schermo`: l'immagine appena decodificata, così com'è (BGRA su IOSurface).
    func mostra(_ immagine: CVPixelBuffer, da: ObjectIdentifier) {
        blocco.lock()
        defer { blocco.unlock() }
        guard da == sorgente else { return }
        let descrizione: CMVideoFormatDescription
        if let attuale = formato, CMVideoFormatDescriptionMatchesImageBuffer(attuale, imageBuffer: immagine) {
            descrizione = attuale
        } else {
            var creata: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: immagine,
                                                               formatDescriptionOut: &creata) == noErr,
                  let nuova = creata else { return }
            formato = nuova
            descrizione = nuova
        }
        var tempi = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                       decodeTimeStamp: .invalid)
        var campioneCreato: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: immagine,
                                                       formatDescription: descrizione, sampleTiming: &tempi,
                                                       sampleBufferOut: &campioneCreato) == noErr,
              let campione = campioneCreato else { return }
        Schermo.mostraSubito(campione)
        if livello.sampleBufferRenderer.status == .failed {
            livello.sampleBufferRenderer.flush()
        }
        livello.sampleBufferRenderer.enqueue(campione)
    }
}

/// Scrive i fotogrammi H.264 in un file .mov senza ricomprimerli. Usato solo sulla coda dello `Schermo`.
private final class Registratore {
    let file: URL
    private var scrittore: AVAssetWriter?
    private var ingresso: AVAssetWriterInput?
    private var formato: CMVideoFormatDescription?
    private var primoTimestamp: UInt64?

    init(file: URL) {
        self.file = file
    }

    /// Falso quando il formato cambia: la registrazione va chiusa.
    func aggiungi(_ campione: CMSampleBuffer, formato nuovo: CMVideoFormatDescription, fotogramma: FotogrammaVideo) -> Bool {
        if scrittore == nil {
            // Il file comincia da un fotogramma chiave.
            guard fotogramma.chiave, let scrittoreCreato = try? AVAssetWriter(outputURL: file, fileType: .mov) else { return true }
            let ingressoCreato = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: nuovo)
            ingressoCreato.expectsMediaDataInRealTime = true
            guard scrittoreCreato.canAdd(ingressoCreato) else { return true }
            scrittoreCreato.add(ingressoCreato)
            // Se non parte (per esempio il file esiste già), startSession solleverebbe un'eccezione.
            guard scrittoreCreato.startWriting() else { return true }
            scrittoreCreato.startSession(atSourceTime: .zero)
            scrittore = scrittoreCreato
            ingresso = ingressoCreato
            formato = nuovo
            primoTimestamp = fotogramma.timestamp
        }
        // Disco pieno o errore di scrittura: lo scrittore non accetta più nulla, la registrazione va chiusa.
        if scrittore?.status == .failed { return false }
        guard let formatoFile = formato, CMFormatDescriptionEqual(formatoFile, otherFormatDescription: nuovo) else { return false }
        guard let ingressoAttivo = ingresso, ingressoAttivo.isReadyForMoreMediaData, let primo = primoTimestamp, fotogramma.timestamp >= primo else { return true }

        var tempi = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMTime(value: CMTimeValue(fotogramma.timestamp - primo), timescale: 1_000_000),
                                       decodeTimeStamp: .invalid)
        var copiaCreata: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: campione,
                                                    sampleTimingEntryCount: 1, sampleTimingArray: &tempi,
                                                    sampleBufferOut: &copiaCreata) == noErr,
              let copia = copiaCreata else { return true }
        ingressoAttivo.append(copia)
        return true
    }

    func chiudi(_ completamento: @escaping @Sendable (URL?) -> Void) {
        guard let scrittore, let ingresso, scrittore.status == .writing else {
            // Un file iniziato e poi fallito non si apre: meglio non lasciarlo sul disco (magari già pieno).
            if scrittore?.status == .failed { try? FileManager.default.removeItem(at: file) }
            return completamento(nil)
        }
        ingresso.markAsFinished()
        let file = self.file
        scrittore.finishWriting {
            completamento(scrittore.status == .completed ? file : nil)
        }
    }
}
