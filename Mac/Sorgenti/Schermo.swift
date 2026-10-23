import AVFoundation
import CoreImage
import CoreMedia
import VideoToolbox
import WebcamLRProtocollo

/// Trasforma i fotogrammi H.264 (Annex B) in campioni che `AVSampleBufferDisplayLayer`
/// decodifica e mostra da solo, con il decodificatore hardware del Mac (funzione 4).
/// In parallelo decodifica anche con VideoToolbox e tiene l'ultima immagine in BGRA:
/// serve per le foto (funzione 35) e, dal round 2, per la webcam virtuale.
/// Tutto il lavoro avviene sulla sua coda.
final class Schermo: @unchecked Sendable {
    let livello = AVSampleBufferDisplayLayer()
    /// Ogni immagine decodificata, sulla coda dello schermo (per la webcam virtuale, round 2).
    var suImmagine: ((CVPixelBuffer) -> Void)?

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.schermo", qos: .userInteractive)
    private var formato: CMVideoFormatDescription?
    private var attendiChiave = true
    private var sessioneDecodifica: VTDecompressionSession?
    private var formatoDecodifica: CMVideoFormatDescription?
    private var ultimaImmagine: CVPixelBuffer?
    private var registratore: Registratore?

    init() {
        livello.videoGravity = .resizeAspect
        livello.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    func mostra(_ fotogramma: FotogrammaVideo) {
        coda.async { self.accoda(fotogramma) }
    }

    func svuota() {
        coda.async {
            self.livello.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            self.formato = nil
            self.attendiChiave = true
            self.chiudiDecodifica()
            self.ultimaImmagine = nil
        }
    }

    /// L'ultima immagine ricevuta, per una foto; nil se non c'è ancora video.
    func fotografa(_ completamento: @escaping @Sendable (CGImage?) -> Void) {
        coda.async {
            guard let immagine = self.ultimaImmagine else { return completamento(nil) }
            let ci = CIImage(cvPixelBuffer: immagine)
            completamento(CIContext().createCGImage(ci, from: ci.extent))
        }
    }

    private func accoda(_ fotogramma: FotogrammaVideo) {
        let unita = AnnexB.unita(in: fotogramma.dati)

        if let sps = unita.first(where: { AnnexB.tipoH264($0) == 7 }),
           let pps = unita.first(where: { AnnexB.tipoH264($0) == 8 }),
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

        // Solo le unità con l'immagine: SPS, PPS e delimitatori stanno nel formato.
        let immagine = unita.filter { ![7, 8, 9].contains(AnnexB.tipoH264($0)) }
        guard let formato, !immagine.isEmpty,
              let campione = Self.campione(immagine, formato: formato, chiave: fotogramma.chiave) else { return }
        livello.sampleBufferRenderer.enqueue(campione)
        registra(campione, formato: formato, fotogramma: fotogramma)
        decodificaInImmagine(campione, formato: formato)
    }

    // MARK: - Registrazione (funzione 35)

    /// Inizia a salvare il video così come arriva, già compresso: niente perdita di qualità.
    func avviaRegistrazione(in file: URL) {
        coda.async { self.registratore = Registratore(file: file) }
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
            // Il formato è cambiato (altro obiettivo, telefono girato): il file si chiude qui.
            self.registratore = nil
            registratore.chiudi { _ in }
        }
    }

    // MARK: - Decodifica in immagini

    private func decodificaInImmagine(_ campione: CMSampleBuffer, formato: CMVideoFormatDescription) {
        if sessioneDecodifica == nil || !CMFormatDescriptionEqual(formato, otherFormatDescription: formatoDecodifica) {
            creaDecodifica(formato)
        }
        guard let sessione = sessioneDecodifica else { return }
        // Sincrona: l'immagine arriva prima che la chiamata finisca, sulla stessa coda.
        VTDecompressionSessionDecodeFrame(sessione, sampleBuffer: campione, flags: [], infoFlagsOut: nil) {
            [weak self] stato, _, immagine, _, _ in
            guard stato == noErr, let immagine, let self else { return }
            self.ultimaImmagine = immagine
            self.suImmagine?(immagine)
        }
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
}

/// Scrive i fotogrammi H.264 in un file .mov senza ricomprimerli. Usato solo sulla coda dello `Schermo`.
private final class Registratore {
    private let file: URL
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
        guard let formato, CMFormatDescriptionEqual(formato, otherFormatDescription: nuovo) else { return false }
        guard let ingresso, ingresso.isReadyForMoreMediaData, let primo = primoTimestamp, fotogramma.timestamp >= primo else { return true }

        var tempi = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMTime(value: CMTimeValue(fotogramma.timestamp - primo), timescale: 1_000_000),
                                       decodeTimeStamp: .invalid)
        var copiaCreata: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: campione,
                                                    sampleTimingEntryCount: 1, sampleTimingArray: &tempi,
                                                    sampleBufferOut: &copiaCreata) == noErr,
              let copia = copiaCreata else { return true }
        ingresso.append(copia)
        return true
    }

    func chiudi(_ completamento: @escaping @Sendable (URL?) -> Void) {
        guard let scrittore, let ingresso, scrittore.status == .writing else { return completamento(nil) }
        ingresso.markAsFinished()
        let file = file
        scrittore.finishWriting {
            completamento(scrittore.status == .completed ? file : nil)
        }
    }
}
