import AVFoundation
import CoreMedia
import Foundation
import WebcamLRProtocollo

/// P20: il microfono del telefono in AAC-LC 48 kHz mono (protocollo, «Audio»).
///
/// - Ingresso: i `CMSampleBuffer` PCM di `AVCaptureAudioDataOutput`, nella **stessa** `AVCaptureSession` del video:
///   gli istanti sono sullo stesso orologio dei fotogrammi e si convertono come quelli del video
///   (`Orologio.microsecondi(daSecondi:)` dell'istante di presentazione).
/// - Codifica: `AVAudioConverter` (l'encoder AAC di sistema di AudioToolbox), circa 64 kbit/s, con il
///   ricampionamento a 48 kHz e il passaggio a mono se il microfono dà altro. Nessuna libreria esterna.
/// - Uscita: un `PacchettoAudio` per ogni frame AAC di 1024 campioni, senza ADTS. Istante = primo campione del
///   frame: inizio del flusso + (k × 1024 − 2112) campioni, perché l'encoder AAC di Apple antepone 2112 campioni
///   di innesco (priming): così il campione decodificato cade sull'istante in cui è stato catturato.
/// - Un buco nell'ingresso (pausa, riconfigurazione, microfono riacceso) o un formato nuovo fa ripartire il flusso:
///   `flusso` cresce e il collegamento rimanda `formato-audio` prima del pacchetto successivo.
///
/// Tutto sulla coda dell'audio della cattura, un buffer alla volta.
final class CodificatoreAudio: @unchecked Sendable {
    /// Sulla coda dell'audio: il pacchetto e il numero del flusso a cui appartiene.
    var suPacchetto: ((PacchettoAudio, _ flusso: Int) -> Void)?

    static let frequenza: Double = 48_000
    static let campioniPerPacchetto = Int64(FormatoAudio.campioniPerPacchetto)
    /// Campioni di innesco dell'encoder AAC di Apple.
    static let campioniInnesco: Int64 = 2112
    /// Oltre questo scarto tra l'istante atteso e quello vero si riparte con un flusso nuovo.
    private static let scartoMassimo: Double = 0.04

    // Solo sulla coda dell'audio.
    private var convertitore: AVAudioConverter?
    private var formatoIngresso: AVAudioFormat?
    private var formatoUscita: AVAudioFormat?
    /// La descrizione del PCM d'ingresso come l'ha data la cattura.
    private var asbdIngresso: AudioStreamBasicDescription?
    private var inizio: Double = 0
    private var campioniEntrati: Int64 = 0
    private var pacchettiUsciti: Int64 = 0
    private var flusso = 0

    /// Dalla coda dell'audio, per ogni buffer del microfono.
    func codifica(_ campione: CMSampleBuffer) {
        guard let descrizione = CMSampleBufferGetFormatDescription(campione),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(descrizione)?.pointee else { return }
        let fotogrammi = CMSampleBufferGetNumSamples(campione)
        let istante = CMSampleBufferGetPresentationTimeStamp(campione)
        guard fotogrammi > 0, istante.isValid, asbd.mSampleRate > 0 else { return }
        let secondi = istante.seconds

        // Formato nuovo, o buco nel tempo: si riparte da capo.
        // Si confronta con la descrizione arrivata l'ultima volta, non con quella di `AVAudioFormat`: AVAudioFormat
        // può normalizzare i flag (per esempio interleaved/non interleaved col mono) e allora ogni buffer
        // sembrerebbe un formato nuovo, con un convertitore e un flusso nuovi ogni 20 ms.
        if formatoIngresso == nil || asbdIngresso.map({ !Self.stessoFormato($0, asbd) }) ?? true {
            guard preparaConvertitore(asbd, descrizione: descrizione) else { return }
            ricomincia(da: secondi)
        } else {
            let atteso = inizio + Double(campioniEntrati) / asbd.mSampleRate
            if abs(secondi - atteso) > Self.scartoMassimo {
                convertitore?.reset()
                ricomincia(da: secondi)
            }
        }
        guard let convertitore, let formatoIngresso, let formatoUscita,
              let pcm = AVAudioPCMBuffer(pcmFormat: formatoIngresso, frameCapacity: AVAudioFrameCount(fotogrammi)) else { return }
        pcm.frameLength = AVAudioFrameCount(fotogrammi)
        let esitoCopia = CMSampleBufferCopyPCMDataIntoAudioBufferList(campione, at: 0, frameCount: Int32(fotogrammi),
                                                                      into: pcm.mutableAudioBufferList)
        guard esitoCopia == noErr else { return }
        campioniEntrati += Int64(fotogrammi)

        // Un riferimento, non una `var` catturata: con l'SDK di iOS 18 il blocco d'ingresso può essere `@Sendable`,
        // e lì modificare una variabile catturata non compila.
        let fornito = Protetto(false)
        while true {
            let uscita = AVAudioCompressedBuffer(format: formatoUscita, packetCapacity: 1,
                                                 maximumPacketSize: max(convertitore.maximumOutputPacketSize, 1536))
            var errore: NSError?
            let esito = convertitore.convert(to: uscita, error: &errore) { _, statoIngresso in
                if fornito.valore {
                    statoIngresso.pointee = .noDataNow
                    return nil
                }
                fornito.valore = true
                statoIngresso.pointee = .haveData
                return pcm
            }
            if esito == .error { return }
            if uscita.packetCount > 0 { consegna(uscita) }
            if esito != .haveData { break }
        }
    }

    // MARK: - Interni

    private func preparaConvertitore(_ asbd: AudioStreamBasicDescription, descrizione: CMAudioFormatDescription) -> Bool {
        convertitore = nil
        formatoIngresso = nil
        asbdIngresso = nil
        let ingresso = AVAudioFormat(cmAudioFormatDescription: descrizione)
        var aac = AudioStreamBasicDescription(mSampleRate: Self.frequenza, mFormatID: kAudioFormatMPEG4AAC,
                                              mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue), mBytesPerPacket: 0,
                                              mFramesPerPacket: UInt32(Self.campioniPerPacchetto), mBytesPerFrame: 0,
                                              mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        guard let uscita = AVAudioFormat(streamDescription: &aac),
              let nuovo = AVAudioConverter(from: ingresso, to: uscita) else { return false }
        nuovo.downmix = true
        // Non tutte le velocità sono accettate: se 64 kbit/s non va, resta quella dell'encoder.
        if let ammesse = nuovo.applicableEncodeBitRates?.map(\.intValue), !ammesse.isEmpty {
            nuovo.bitRate = ammesse.min { abs($0 - 64_000) < abs($1 - 64_000) } ?? 64_000
        }
        convertitore = nuovo
        formatoIngresso = ingresso
        formatoUscita = uscita
        asbdIngresso = asbd
        return true
    }

    private static func stessoFormato(_ a: AudioStreamBasicDescription, _ b: AudioStreamBasicDescription) -> Bool {
        a.mSampleRate == b.mSampleRate && a.mFormatID == b.mFormatID && a.mFormatFlags == b.mFormatFlags
            && a.mChannelsPerFrame == b.mChannelsPerFrame && a.mBitsPerChannel == b.mBitsPerChannel
            && a.mBytesPerFrame == b.mBytesPerFrame
    }

    private func ricomincia(da secondi: Double) {
        inizio = secondi
        campioniEntrati = 0
        pacchettiUsciti = 0
        flusso += 1
    }

    private func consegna(_ uscita: AVAudioCompressedBuffer) {
        let base = uscita.data.assumingMemoryBound(to: UInt8.self)
        for indice in 0..<Int(uscita.packetCount) {
            let dati: Data
            if let descrizioni = uscita.packetDescriptions {
                let descrizione = descrizioni[indice]
                guard descrizione.mDataByteSize > 0 else { continue }
                dati = Data(bytes: base + Int(descrizione.mStartOffset), count: Int(descrizione.mDataByteSize))
            } else {
                guard uscita.byteLength > 0 else { continue }
                dati = Data(bytes: base, count: Int(uscita.byteLength))
            }
            let campione = pacchettiUsciti * Self.campioniPerPacchetto - Self.campioniInnesco
            pacchettiUsciti += 1
            let secondi = inizio + Double(campione) / Self.frequenza
            suPacchetto?(PacchettoAudio(timestamp: Orologio.microsecondi(daSecondi: secondi), dati: dati), flusso)
        }
    }
}

/// P20: il permesso del microfono (NSMicrophoneUsageDescription in `project.yml`).
enum MicrofonoPermesso {
    case concesso
    case daChiedere
    case negato

    static var attuale: MicrofonoPermesso {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .concesso
        case .undetermined: .daChiedere
        default: .negato
        }
    }

    /// Mostra la richiesta di iOS (solo la prima volta) e dice se è stato concesso.
    static func chiedi() async -> Bool {
        await withCheckedContinuation { continuazione in
            AVAudioApplication.requestRecordPermission { concesso in
                continuazione.resume(returning: concesso)
            }
        }
    }
}
