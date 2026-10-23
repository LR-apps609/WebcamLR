import AVFoundation
import CoreMedia
import WebcamLRProtocollo

/// Trasforma i fotogrammi H.264 (Annex B) in campioni che `AVSampleBufferDisplayLayer`
/// decodifica e mostra da solo, con il decodificatore hardware del Mac (funzione 4).
/// Tutto il lavoro avviene sulla sua coda.
final class Schermo: @unchecked Sendable {
    let livello = AVSampleBufferDisplayLayer()

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.schermo", qos: .userInteractive)
    private var formato: CMVideoFormatDescription?
    private var attendiChiave = true

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
        guard let formato, !immagine.isEmpty, let campione = Self.campione(immagine, formato: formato) else { return }
        livello.sampleBufferRenderer.enqueue(campione)
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
    private static func campione(_ unita: [Data], formato: CMVideoFormatDescription) -> CMSampleBuffer? {
        var avcc = Data()
        for nal in unita {
            let lunghezza = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: lunghezza) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }

        var blocco: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: avcc.count, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: avcc.count,
                                                 flags: 0, blockBufferOut: &blocco) == kCMBlockBufferNoErr,
              let blocco else { return nil }
        let copiato = avcc.withUnsafeBytes { byte in
            CMBlockBufferReplaceDataBytes(with: byte.baseAddress!, blockBuffer: blocco, offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copiato == kCMBlockBufferNoErr else { return nil }

        var campione: CMSampleBuffer?
        var dimensione = avcc.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: blocco, formatDescription: formato,
                                        sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &dimensione,
                                        sampleBufferOut: &campione) == noErr,
              let campione else { return nil }

        if let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: true),
           CFArrayGetCount(allegati) > 0 {
            let allegato = unsafeBitCast(CFArrayGetValueAtIndex(allegati, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(allegato,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return campione
    }
}
