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
    var suNuovoFormato: ((Int, Int, Int, Codec) -> Void)?

    private var sessione: VTCompressionSession?
    private var larghezza: Int32 = 0
    private var altezza: Int32 = 0
    private let blocco = NSLock()
    private var fps = 30
    /// H.264 di serie; HEVC a scelta nelle impostazioni (funzione 10).
    private var codec: Codec = .h264
    private var chiaveRichiesta = true
    /// Qualità che segue la rete (round 2): il bitrate della qualità scelta, quello in uso e la frazione
    /// che la rete permette. Si cambia sulla sessione viva, senza ricrearla.
    private var bitrateBase = 0
    private var bitrateApplicato = 0
    private var fattoreRete: Double = 1
    private var secondiPuliti = 0

    /// Mai sotto un quinto della qualità scelta, né sotto 500 kbit/s.
    private static let fattoreMinimo = 0.2
    private static let bitrateMinimo = 500_000

    func imposta(fps: Int, codec: Codec) {
        blocco.withLock {
            self.fps = fps
            self.codec = codec
            larghezza = 0 // ricrea la sessione al prossimo fotogramma
        }
    }

    /// Nuovo collegamento con la fotocamera già accesa: si ricrea la sessione al prossimo fotogramma,
    /// così il computer riceve di nuovo `formato` e un fotogramma chiave.
    func ricomincia() {
        blocco.withLock { larghezza = 0 }
    }

    /// Il prossimo fotogramma sarà un fotogramma chiave (dopo una perdita o un nuovo collegamento).
    func richiediFotogrammaChiave() {
        blocco.withLock { chiaveRichiesta = true }
    }

    /// Nuovo collegamento: si riparte dalla qualità scelta.
    func azzeraRete() {
        blocco.withLock {
            fattoreRete = 1
            secondiPuliti = 0
            applicaBitrate()
        }
    }

    /// Chiamata una volta al secondo dal collegamento. Se si scarta o la rete è satura il bitrate
    /// scende del 30%; dopo 3 secondi puliti risale del 10% della qualità scelta, fino a quella.
    /// Ritorna `true` se la rete è debole (bitrate ben sotto la qualità scelta).
    func adattaAllaRete(scartati: Int, saturo: Bool) -> Bool {
        return blocco.withLock { () -> Bool in
            if scartati > 0 || saturo {
                fattoreRete = max(fattoreRete * 0.7, Self.fattoreMinimo)
                secondiPuliti = 0
            } else if fattoreRete < 1 {
                secondiPuliti += 1
                if secondiPuliti >= 3 {
                    fattoreRete = min(fattoreRete + 0.1, 1)
                    secondiPuliti = 0
                }
            }
            applicaBitrate()
            return fattoreRete < 0.6
        }
    }

    /// Va chiamata con `blocco` preso.
    private func applicaBitrate() {
        guard let sessione, bitrateBase > 0 else { return }
        let nuovo = max(Int(Double(bitrateBase) * fattoreRete), min(bitrateBase, Self.bitrateMinimo))
        guard nuovo != bitrateApplicato else { return }
        VTSessionSetProperty(sessione, key: kVTCompressionPropertyKey_AverageBitRate, value: nuovo as CFNumber)
        bitrateApplicato = nuovo
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
        if let nuovoFormato { suNuovoFormato?(Int(l), Int(a), nuovoFormato, blocco.withLock { codec }) }

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
                                               codecType: codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
                                               encoderSpecification: nil, imageBufferAttributes: nil,
                                               compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                               compressionSessionOut: &creata)
        guard esito == noErr, let nuova = creata else { return }

        let pixel = Double(l) * Double(a)
        // Circa 6 Mbit/s a 1080p30, in proporzione per le altre risoluzioni e i 60 fps.
        // HEVC dà la stessa qualità con circa il 40% di dati in meno.
        bitrateBase = Int(pixel / (1920 * 1080) * 6_000_000 * (fps > 30 ? 1.5 : 1) * (codec == .hevc ? 0.6 : 1))
        // Se la rete era già lenta si parte dal bitrate che reggeva.
        let bitrate = max(Int(Double(bitrateBase) * fattoreRete), min(bitrateBase, Self.bitrateMinimo))
        bitrateApplicato = bitrate
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: codec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2 as CFNumber)
        // Round 2: velocità prima della qualità, e nessun fotogramma trattenuto dentro il codificatore.
        // Se un iPhone non le supporta, l'errore si ignora: resta la codifica di prima.
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(nuova)
        sessione = nuova
    }

    /// Da AVCC (lunghezze di 4 byte) ad Annex B, con SPS e PPS davanti ai fotogrammi chiave.
    private func consegna(_ campione: CMSampleBuffer) {
        let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: false) as? [[String: Any]]
        let chiave = !(allegati?.first?[kCMSampleAttachmentKey_NotSync as String] as? Bool ?? false)

        var unita: [Data] = []
        if chiave, let formato = CMSampleBufferGetFormatDescription(campione) {
            // H.264: SPS e PPS; HEVC: VPS, SPS e PPS. Stessa forma della funzione, nomi diversi.
            let hevc = CMFormatDescriptionGetMediaSubType(formato) == kCMVideoCodecType_HEVC
            func leggiParametri(_ formato: CMFormatDescription, _ indice: Int,
                                _ puntatore: UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
                                _ dimensione: UnsafeMutablePointer<Int>?,
                                _ conteggio: UnsafeMutablePointer<Int>?,
                                _ intestazione: UnsafeMutablePointer<Int32>?) -> OSStatus {
                hevc
                    ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formato, parameterSetIndex: indice,
                                                                         parameterSetPointerOut: puntatore,
                                                                         parameterSetSizeOut: dimensione,
                                                                         parameterSetCountOut: conteggio,
                                                                         nalUnitHeaderLengthOut: intestazione)
                    : CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formato, parameterSetIndex: indice,
                                                                         parameterSetPointerOut: puntatore,
                                                                         parameterSetSizeOut: dimensione,
                                                                         parameterSetCountOut: conteggio,
                                                                         nalUnitHeaderLengthOut: intestazione)
            }
            var conteggio = 0
            _ = leggiParametri(formato, 0, nil, nil, &conteggio, nil)
            for indice in 0..<conteggio {
                var puntatore: UnsafePointer<UInt8>?
                var dimensione = 0
                let esito = leggiParametri(formato, indice, &puntatore, &dimensione, nil, nil)
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
