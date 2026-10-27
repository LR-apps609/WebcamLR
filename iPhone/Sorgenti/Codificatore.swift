import CoreMedia
import Foundation
import VideoToolbox
import WebcamLRProtocollo

/// Comprime i fotogrammi in H.264 o HEVC con il codificatore hardware dell'iPhone (funzione 3).
/// Il 4K va in HEVC quando lo sceglie il telefono (vedi `SessioneTelefono.formatoEffettivo`).
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
    /// Al prossimo fotogramma codificato si manda di nuovo `formato` (nuova sessione di codifica o nuovo collegamento).
    private var formatoDaAnnunciare = true
    /// Qualità che segue la rete (round 2): il bitrate della qualità scelta, quello in uso e la frazione
    /// che la rete permette. Si cambia sulla sessione viva, senza ricrearla.
    private var bitrateBase = 0
    private var bitrateApplicato = 0
    private var fattoreRete: Double = 1
    private var secondiPuliti = 0
    /// Qualità ed efficienza (27 ottobre): sul cavo (USB o di rete) il bitrate di riferimento sale del 50%.
    private var cavo = false
    /// La sessione attuale usa il controllo del bitrate a bassa latenza di VideoToolbox.
    private var bassaLatenza = false
    /// Con la bassa latenza il codificatore non mette fotogrammi chiave da solo (GOP infinito): se ne chiede uno
    /// ogni `intervalloChiave` secondi, come faceva `MaxKeyFrameIntervalDuration`. Istante dell'ultimo, in secondi.
    private var ultimaChiave: Double?
    private static let intervalloChiave = 2.0
    /// La sessione attuale ha già consegnato almeno un fotogramma.
    private var sessioneProvata = false
    /// Una sessione a bassa latenza si è guastata prima del primo fotogramma (formato che quel codificatore non
    /// regge): fino al prossimo cambio di formato o codec si usa la codifica di prima, senza ricreare a vuoto.
    private var senzaBassaLatenza = false

    /// Mai sotto un quinto della qualità scelta, né sotto 500 kbit/s.
    private static let fattoreMinimo = 0.2
    private static let bitrateMinimo = 500_000

    func imposta(fps: Int, codec: Codec) {
        blocco.withLock {
            self.fps = fps
            self.codec = codec
            senzaBassaLatenza = false
            larghezza = 0 // ricrea la sessione al prossimo fotogramma
        }
    }

    /// Nuovo collegamento con la fotocamera già accesa: al prossimo fotogramma il computer riceve di nuovo `formato`
    /// e un fotogramma chiave (con SPS e PPS). 1.11: la sessione di codifica già pronta si tiene, non si ricrea.
    func ricomincia() {
        blocco.withLock {
            formatoDaAnnunciare = true
            chiaveRichiesta = true
        }
    }

    /// 1.11: prima del `benvenuto` la fotocamera va già ma non si codifica nulla. Con il primo fotogramma si crea
    /// la sessione di codifica (la parte lenta), così il primo fotogramma utile si codifica subito.
    func prepara(_ campione: CMSampleBuffer) {
        guard let immagine = CMSampleBufferGetImageBuffer(campione) else { return }
        let l = Int32(CVPixelBufferGetWidth(immagine))
        let a = Int32(CVPixelBufferGetHeight(immagine))
        blocco.withLock {
            guard sessione == nil || l != larghezza || a != altezza else { return }
            creaSessione(larghezza: l, altezza: a)
            chiaveRichiesta = true
            formatoDaAnnunciare = true
        }
    }

    /// Bug 3: l'app va in sottofondo o torna in primo piano. iOS toglie il codificatore hardware alle app in
    /// sottofondo e la sessione di codifica resta invalidata: al prossimo fotogramma se ne crea una nuova (con
    /// `formato` e fotogramma chiave per il computer), invece di scoprirlo da un errore.
    func ricreaAlProssimo() {
        blocco.withLock { larghezza = 0 }
    }

    /// Il prossimo fotogramma sarà un fotogramma chiave (dopo una perdita o un nuovo collegamento).
    func richiediFotogrammaChiave() {
        blocco.withLock { chiaveRichiesta = true }
    }

    /// Qualità ed efficienza: il collegamento è sul cavo (USB o di rete) o senza fili. Cambia il bitrate di
    /// riferimento sulla sessione viva, senza ricrearla.
    func impostaCavo(_ nuovo: Bool) {
        blocco.withLock {
            guard nuovo != cavo else { return }
            cavo = nuovo
            guard larghezza > 0 else { return }
            bitrateBase = Self.bitrateDiRiferimento(larghezza: larghezza, altezza: altezza, fps: fps, codec: codec,
                                                    cavo: cavo)
            applicaBitrate()
        }
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
        VTSessionSetProperty(sessione, key: kVTCompressionPropertyKey_DataRateLimits, value: Self.limitiPicchi(nuovo))
        bitrateApplicato = nuovo
    }

    /// 1.14: tetto ai picchi, una volta e mezza il bitrate medio in ogni secondo (in byte). Senza, un fotogramma
    /// chiave in 4K arriva a 1-2 MB in un colpo e satura il Wi-Fi (e il bitrate scende per niente).
    private static func limitiPicchi(_ bitrate: Int) -> CFArray {
        [NSNumber(value: Double(bitrate) * 1.5 / 8), NSNumber(value: 1.0)] as CFArray
    }

    func codifica(_ campione: CMSampleBuffer) {
        guard let immagine = CMSampleBufferGetImageBuffer(campione) else { return }
        codifica(immagine, istante: CMSampleBufferGetPresentationTimeStamp(campione))
    }

    /// Il buffer da comprimere (quello della cattura, o quello uscito da `PipelineEffetti`) con l'istante
    /// del fotogramma d'origine.
    func codifica(_ immagine: CVPixelBuffer, istante: CMTime) {
        let l = Int32(CVPixelBufferGetWidth(immagine))
        let a = Int32(CVPixelBufferGetHeight(immagine))

        let (sessioneAttuale, forzaChiave, nuovoFormato): (VTCompressionSession?, Bool, Int?) = blocco.withLock {
            var nuovoFormato: Int?
            if self.sessione == nil || l != larghezza || a != altezza {
                creaSessione(larghezza: l, altezza: a)
                chiaveRichiesta = true
                formatoDaAnnunciare = true
            }
            if formatoDaAnnunciare && self.sessione != nil {
                formatoDaAnnunciare = false
                nuovoFormato = fps
            }
            // Bassa latenza: un fotogramma chiave ogni `intervalloChiave` secondi lo chiediamo noi.
            let secondi = istante.seconds
            if bassaLatenza, secondi.isFinite,
               ultimaChiave.map({ secondi < $0 || secondi - $0 >= Self.intervalloChiave }) ?? true {
                chiaveRichiesta = true
            }
            let forza = chiaveRichiesta
            chiaveRichiesta = false
            if forza, secondi.isFinite { ultimaChiave = secondi }
            return (self.sessione, forza, nuovoFormato)
        }
        guard let sessione = sessioneAttuale else { return }
        if let nuovoFormato { suNuovoFormato?(Int(l), Int(a), nuovoFormato, blocco.withLock { codec }) }

        let proprieta: CFDictionary? = forzaChiave ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil
        let esito = VTCompressionSessionEncodeFrame(sessione,
                                                    imageBuffer: immagine,
                                                    presentationTimeStamp: istante,
                                                    duration: .invalid,
                                                    frameProperties: proprieta,
                                                    infoFlagsOut: nil) { [weak self] stato, _, compresso in
            guard stato == noErr else {
                // Bug 3: l'errore può arrivare anche qui, con `EncodeFrame` riuscito (sessione invalidata in
                // sottofondo, codificatore guasto): senza ricrearla il video resterebbe fermo per sempre.
                self?.sessioneGuasta(sessione)
                return
            }
            guard let compresso else { return }
            self?.sessioneRiuscita(sessione)
            self?.consegna(compresso)
        }
        // Dopo il ritorno dal sottofondo iOS può invalidare la sessione (kVTInvalidSessionErr, -12903) o il
        // codificatore può non essere disponibile: con qualsiasi errore la si ricrea al prossimo fotogramma.
        if esito != noErr {
            sessioneGuasta(sessione)
        }
    }

    /// La sessione di codifica non funziona più: se è ancora quella in uso, al prossimo fotogramma se ne crea una
    /// nuova (con `formato` e fotogramma chiave). Da qualsiasi thread.
    private func sessioneGuasta(_ guasta: VTCompressionSession) {
        blocco.withLock {
            guard self.sessione === guasta else { return }
            if bassaLatenza && !sessioneProvata && !senzaBassaLatenza {
                senzaBassaLatenza = true
                RegistroCollegamento.scrivi(String(localized: "Codifica a bassa latenza non riuscita: torno a quella normale"))
            }
            larghezza = 0
        }
    }

    /// Un fotogramma è uscito dalla sessione: da qui un suo guasto non dipende dalla bassa latenza.
    private func sessioneRiuscita(_ riuscita: VTCompressionSession) {
        blocco.withLock {
            if !sessioneProvata, self.sessione === riuscita { sessioneProvata = true }
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

        // Qualità ed efficienza: il codificatore a bassa latenza di VideoToolbox (iOS 14.5+), pensato per le
        // videochiamate: nessun fotogramma trattenuto, controllo del bitrate fotogramma per fotogramma, solo profili
        // High (H.264). Apple lo documenta per H.264; per HEVC si prova lo stesso e, se nessun codificatore lo
        // accetta, si crea la sessione di prima.
        let tipo = codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        let specificaBassaLatenza = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue] as CFDictionary
        var creata: VTCompressionSession?
        var esito: OSStatus = -1
        if !senzaBassaLatenza {
            esito = VTCompressionSessionCreate(allocator: nil, width: l, height: a, codecType: tipo,
                                               encoderSpecification: specificaBassaLatenza, imageBufferAttributes: nil,
                                               compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                               compressionSessionOut: &creata)
        }
        let conBassaLatenza = esito == noErr && creata != nil
        if !conBassaLatenza {
            creata = nil
            esito = VTCompressionSessionCreate(allocator: nil, width: l, height: a, codecType: tipo,
                                               encoderSpecification: nil, imageBufferAttributes: nil,
                                               compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                                               compressionSessionOut: &creata)
        }
        guard esito == noErr, let nuova = creata else { return }
        bassaLatenza = conBassaLatenza
        sessioneProvata = false
        ultimaChiave = nil

        bitrateBase = Self.bitrateDiRiferimento(larghezza: l, altezza: a, fps: fps, codec: codec, cavo: cavo)
        // Se la rete era già lenta si parte dal bitrate che reggeva.
        let bitrate = max(Int(Double(bitrateBase) * fattoreRete), min(bitrateBase, Self.bitrateMinimo))
        bitrateApplicato = bitrate
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: codec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_DataRateLimits, value: Self.limitiPicchi(bitrate))
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        // Con la bassa latenza vale il GOP infinito del codificatore: i fotogrammi chiave periodici li chiede
        // `codifica` (vedi `intervalloChiave`). Senza, ci pensa questa proprietà.
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                             value: Self.intervalloChiave as CFNumber)
        // Nessun fotogramma trattenuto dentro il codificatore. Qualità ed efficienza: la velocità non passa più
        // davanti alla qualità (il codificatore hardware regge il tempo reale anche così, e il controllo a bassa
        // latenza tiene già basso il ritardo). Se un iPhone non le supporta, l'errore si ignora.
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanFalse)
        VTSessionSetProperty(nuova, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
        let megabit = (Double(bitrateBase) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
        RegistroCollegamento.scrivi(conBassaLatenza
                                    ? String(localized: "Codifica a bassa latenza, \(megabit) Mbit/s")
                                    : String(localized: "Codifica senza bassa latenza, \(megabit) Mbit/s"))
        VTCompressionSessionPrepareToEncodeFrames(nuova)
        sessione = nuova
    }

    /// Qualità ed efficienza (27 ottobre): il bitrate (bit/s) con la rete che regge. Il video va solo dal telefono al
    /// computer, in rete locale o sul cavo: si può spendere. H.264 a 30 fps: 720p 8, 1080p 16, 4K 40 Mbit/s, in
    /// mezzo in proporzione ai pixel (fuori, in proporzione al punto più vicino); 60 fps ×1,5 (1080p60 = 24 Mbit/s),
    /// sotto i 30 fps in proporzione (24 fps ×0,8); HEVC ×0,65; sul cavo ×1,5. Poi `adattaAllaRete` scende se serve.
    static func bitrateDiRiferimento(larghezza: Int32, altezza: Int32, fps: Int, codec: Codec, cavo: Bool) -> Int {
        let pixel = max(Double(larghezza) * Double(altezza), 1)
        let punti: [(pixel: Double, bitrate: Double)] = [(1280 * 720, 8_000_000), (1920 * 1080, 16_000_000),
                                                         (3840 * 2160, 40_000_000)]
        let a30: Double
        if pixel <= punti[0].pixel {
            a30 = punti[0].bitrate * pixel / punti[0].pixel
        } else if pixel >= punti[2].pixel {
            a30 = punti[2].bitrate * pixel / punti[2].pixel
        } else {
            let (da, a) = pixel <= punti[1].pixel ? (punti[0], punti[1]) : (punti[1], punti[2])
            a30 = da.bitrate + (a.bitrate - da.bitrate) * (pixel - da.pixel) / (a.pixel - da.pixel)
        }
        let perFps = fps > 30 ? 1 + 0.5 * min(Double(fps - 30) / 30, 1) : Double(max(fps, 1)) / 30
        let perCodec = codec == .hevc ? 0.65 : 1
        let perCavo = cavo ? 1.5 : 1
        return Int(a30 * perFps * perCodec * perCavo)
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
        // Un fotogramma vuoto non si spedisce (e `baseAddress` di un Data vuoto può essere nil).
        guard totale > 0 else { return }
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
