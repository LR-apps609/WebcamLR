import CoreMedia
import Foundation
import VideoToolbox
import WebcamLRProtocollo

/// Comprime i fotogrammi in H.264 con il codificatore hardware dell'iPhone (funzione 3).
/// Le chiamate arrivano dalla coda di cattura; le uscite dal thread di VideoToolbox.
final class Codificatore: @unchecked Sendable {
    /// Ogni fotogramma compresso, pronto da spedire.
    var suFotogramma: ((FotogrammaVideo) -> Void)?
    /// Nuove dimensioni o fotogrammi al secondo (altro obiettivo, telefono girato, nuovo collegamento):
    /// va comunicato al computer con un messaggio `formato`. Parametri: larghezza, altezza, fps.
    var suNuovoFormato: ((Int, Int, Int) -> Void)?

    private var sessione: VTCompressionSession?
    private var larghezza: Int32 = 0
    private var altezza: Int32 = 0
    private let blocco = NSLock()
    private var fps = 30
    private var chiaveRichiesta = true

    func imposta(fps: Int) {
        blocco.withLock {
            self.fps = fps
            larghezza = 0 // ricrea la sessione al prossimo fotogramma
        }
    }

    /// Il prossimo fotogramma sarà un fotogramma chiave (dopo una perdita o un nuovo collegamento).
    func richiediFotogrammaChiave() {
        blocco.withLock { chiaveRichiesta = true }
    }

    func codifica(_ campione: CMSampleBuffer) {
        guard let immagine = CMSampleBufferGetImageBuffer(campione) else { return }
        let l = Int32(CVPixelBufferGetWidth(immagine))
        let a = Int32(CVPixelBufferGetHeight(immagine))

        let (sessioneAttuale, forzaChiave, nuovoFormato): (VTCompressionSession?, Bool, Int?) = blocco.withLock {
            var nuovoFormato: Int?
            if self.sessione == nil || l != larghezza || a != altezza {
                creaSessione(larghezza: l, altezza: a)
                chiaveRichiesta = true
                nuovoFormato = fps
            }
            let forza = chiaveRichiesta
            chiaveRichiesta = false
            return (self.sessione, forza, nuovoFormato)
        }
        guard let sessione = sessioneAttuale else { return }
        if let nuovoFormato { suNuovoFormato?(Int(l), Int(a), nuovoFormato) }

        let proprieta: CFDictionary? = forzaChiave ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(sessione,
                                        imageBuffer: immagine,
                                        presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(campione),
                                        duration: .invalid,
                                        frameProperties: proprieta,
                                        infoFlagsOut: nil) { [weak self] stato, _, compresso in
            guard stato == noErr, let compresso else { return }
            self?.consegna(compresso)
        }
    }

    func chiudi() {
        blocco.withLock {
            if let sessione {
                VTCompressionSessionCompleteFrames(sessione, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(sessione)
            }
            sessione = nil
            larghezza = 0
            altezza = 0
        }
    }

    /// Va chiamata con `blocco` preso.
    private func creaSessione(larghezza l: Int32, altezza a: Int32) {
        if let sessione { VTCompressionSessionInvalidate(sessione) }
        sessione = nil
        larghezza = l
        altezza = a

        var creata: VTCompressionSession?
        let esito = VTCompressionSessionCreate(allocator: nil, width: l, height: a,
                                               codecType: kCMVideoCodecType_H264,
                                               encoderSpecification: nil, imageBufferAttributes: nil,
                                               compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                               compressionSessionOut: &creata)
        guard esito == noErr, let nuova = creata else { return }

        let pixel = Double(l) * Double(a)
        // Circa 6 Mbit/s a 1080p30, in proporzione per le altre risoluzioni e i 60 fps.
        let bitrate = Int(pixel / (1920 * 1080) * 6_000_000 * (fps > 30 ? 1.5 : 1))
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(nuova)
        sessione = nuova
    }

    /// Da AVCC (lunghezze di 4 byte) ad Annex B, con SPS e PPS davanti ai fotogrammi chiave.
    private func consegna(_ campione: CMSampleBuffer) {
        let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: false) as? [[String: Any]]
        let chiave = !(allegati?.first?[kCMSampleAttachmentKey_NotSync as String] as? Bool ?? false)

        var unita: [Data] = []
        if chiave, let formato = CMSampleBufferGetFormatDescription(campione) {
            var conteggio = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formato, parameterSetIndex: 0,
                                                               parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                                                               parameterSetCountOut: &conteggio, nalUnitHeaderLengthOut: nil)
            for indice in 0..<conteggio {
                var puntatore: UnsafePointer<UInt8>?
                var dimensione = 0
                let esito = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formato, parameterSetIndex: indice,
                                                                               parameterSetPointerOut: &puntatore,
                                                                               parameterSetSizeOut: &dimensione,
                                                                               parameterSetCountOut: nil,
                                                                               nalUnitHeaderLengthOut: nil)
                if esito == noErr, let puntatore {
                    unita.append(Data(bytes: puntatore, count: dimensione))
                }
            }
        }
        let conParametri = !unita.isEmpty

        guard let datiBlocco = CMSampleBufferGetDataBuffer(campione) else { return }
        let totale = CMBlockBufferGetDataLength(datiBlocco)
        var dati = Data(count: totale)
        let copiato = dati.withUnsafeMutableBytes { destinazione in
            CMBlockBufferCopyDataBytes(datiBlocco, atOffset: 0, dataLength: totale, destination: destinazione.baseAddress!)
        }
        guard copiato == kCMBlockBufferNoErr else { return }

        var posizione = 0
        while posizione + 4 <= totale {
            let lunghezza = Int(dati[posizione]) << 24 | Int(dati[posizione + 1]) << 16
                | Int(dati[posizione + 2]) << 8 | Int(dati[posizione + 3])
            posizione += 4
            guard lunghezza > 0, posizione + lunghezza <= totale else { break }
            unita.append(dati.subdata(in: posizione..<(posizione + lunghezza)))
            posizione += lunghezza
        }

        let istante = CMSampleBufferGetPresentationTimeStamp(campione)
        suFotogramma?(FotogrammaVideo(timestamp: Orologio.microsecondi(daSecondi: istante.seconds),
                                      chiave: chiave, conParametri: conParametri,
                                      dati: AnnexB.unisci(unita)))
    }
}
