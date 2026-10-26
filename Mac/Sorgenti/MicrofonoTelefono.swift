import AudioToolbox
import CoreAudio
import Foundation
import os.log
import WebcamLRProtocollo

/// Il microfono del telefono sul Mac (P20): decodifica l'AAC-LC dei pacchetti di tipo 3 e mette i campioni
/// nella memoria condivisa che il driver «WebcamLR (microfono)» legge dentro coreaudiod
/// (Mac/Microfono, Documenti/Microfono Mac.md).
///
/// Sincronia con il video: ogni frame ha il timestamp del primo campione sull'orologio dei fotogrammi.
/// Con la stessa differenza di orologi del video (il `pong` più rapido) diventa l'istante di cattura sul Mac;
/// il frame va ascoltato a cattura + ritardo, dove il ritardo è la latenza del video (60–300 ms):
/// così voce e labbra arrivano insieme. Il ritardo fa anche da riserva contro i ritardi della rete.
/// Tutto il lavoro sulla sua coda.
final class MicrofonoTelefono: @unchecked Sendable {
    /// Il driver nel sistema: non installato, oppure installato e forse in uso da un'app.
    enum Installazione: Equatable, Sendable {
        case nonInstallato
        case installato(inUso: Bool)
    }

    /// Ritardo minimo: la riserva contro i salti della rete (anche se il video arriva prima).
    static let ritardoMinimo: Int64 = 60_000
    /// Oltre, meglio un po' fuori sincrono che una voce in ritardo di mezzo secondo.
    static let ritardoMassimo: Int64 = 300_000
    /// Prima che arrivi una misura della latenza del video.
    static let ritardoPredefinito: Int64 = 70_000
    /// Il ritardo cambia solo per differenze maggiori: ogni cambio è un piccolo salto (con dissolvenza).
    static let isteresiRitardo: Int64 = 20_000
    /// Un frame entro 10 ms dal punto atteso va attaccato al precedente: niente buchi per i decimali degli orologi.
    static let tolleranza: UInt64 = 480
    /// Il driver legge al massimo fino a «adesso»: si scrive almeno 2 ms più avanti.
    static let margine: UInt64 = 96
    /// Uguali a quelli di Mac/Microfono/Comune/AnelloMicrofono.h (il ponte con il C mostra solo funzioni).
    static let uidDispositivo = "it.lrapps.webcamlr.microfono.dispositivo"
    static let capacita: UInt64 = 32_768
    static let frequenza: Float64 = 48_000
    /// Correzione fissa del ritardo del decodificatore AAC, in campioni. Da misurare con la prova del battito
    /// di mani (checklist P20): se la voce arriva sempre dopo le labbra, qui va un numero positivo.
    static let correzioneDecodifica: UInt64 = 0

    /// Livello del microfono da 0 a 1, una decina di volte al secondo, sulla coda principale.
    /// Da impostare una volta, prima che arrivi l'audio.
    var suLivello: (@MainActor (Double) -> Void)?

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.microfono", qos: .userInteractive)
    private let registro = Logger(subsystem: "it.lrapps.webcamlr.mac", category: "microfono")
    private var convertitore: AudioConverterRef?
    private var formato = FormatoAudio()
    /// Dove andrà il prossimo frame se arriva puntuale (indice della linea del tempo comune); nil dopo un salto.
    private var cursore: UInt64?
    private var ritardo = MicrofonoTelefono.ritardoPredefinito
    /// Ultimo tentativo di collegarsi alla memoria condivisa (microsecondi), per non riprovare a ogni frame.
    private var ultimoTentativo: UInt64 = 0
    private var campioni = [Float](repeating: 0, count: FormatoAudio.campioniPerPacchetto * 2)
    private var sommaQuadrati: Float = 0
    private var campioniMisurati = 0
    private var ultimoLivello: UInt64 = 0
    /// La descrizione del frame per il decodificatore: deve restare allo stesso indirizzo durante la chiamata.
    private let descrizione = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)

    init() {
        descrizione.initialize(to: AudioStreamPacketDescription())
    }

    deinit {
        if let convertitore { AudioConverterDispose(convertitore) }
        descrizione.deallocate()
    }

    // MARK: - Dalla sessione

    /// `formato-audio` del telefono: il decodificatore si rifà al prossimo frame.
    func imposta(formato nuovo: FormatoAudio) {
        coda.async {
            guard nuovo != self.formato || self.convertitore == nil else { return }
            self.formato = nuovo
            self.chiudiConvertitore()
            self.cursore = nil
        }
    }

    /// Un pacchetto di tipo 3. `scarto`: la differenza tra gli orologi del video (nil se non c'è ancora un `pong`);
    /// `latenzaVideoMs`: la latenza del video dell'ultimo secondo.
    func ricevi(_ pacchetto: PacchettoAudio, scarto: Int64?, latenzaVideoMs: Int?) {
        coda.async { self.elabora(pacchetto, scarto: scarto, latenzaVideoMs: latenzaVideoMs) }
    }

    /// Sessione chiusa o microfono spento: si ricomincia da capo al prossimo frame.
    func ferma() {
        coda.async {
            self.chiudiConvertitore()
            self.cursore = nil
            self.sommaQuadrati = 0
            self.campioniMisurati = 0
            self.mandaLivello(0)
        }
    }

    // MARK: - Driver nel sistema

    /// Cerca «WebcamLR (microfono)» tra i dispositivi audio e guarda se un'app lo sta usando.
    /// Fuori dalla coda principale: CoreAudio può metterci un attimo.
    static func leggiInstallazione() -> Installazione {
        var indirizzo = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                   mScope: kAudioObjectPropertyScopeGlobal,
                                                   mElement: kAudioObjectPropertyElementMain)
        var uid = uidDispositivo as CFString
        var dispositivo = AudioObjectID(kAudioObjectUnknown)
        var dimensione = UInt32(MemoryLayout<AudioObjectID>.size)
        let esito = withUnsafePointer(to: &uid) { puntatoreUID in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &indirizzo,
                                       UInt32(MemoryLayout<CFString>.size), puntatoreUID, &dimensione, &dispositivo)
        }
        guard esito == noErr, dispositivo != AudioObjectID(kAudioObjectUnknown) else { return .nonInstallato }
        var inUso: UInt32 = 0
        dimensione = UInt32(MemoryLayout<UInt32>.size)
        indirizzo.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        let letto = AudioObjectGetPropertyData(dispositivo, &indirizzo, 0, nil, &dimensione, &inUso)
        return .installato(inUso: letto == noErr && inUso != 0)
    }

    // MARK: - Versione e rimozione (Impostazioni)

    /// Come è andata «Rimuovi il microfono…».
    enum EsitoRimozione: Equatable, Sendable {
        case riuscita
        /// Il microfono non si può togliere dall'app (installato da una versione di prima, senza il servizio di
        /// rimozione, o aiutante con la firma locale): serve Strumenti/Rimuovi microfono.command.
        case serveLoScript
        /// Il dettaglio tecnico (un percorso con l'errore, oppure «rifiutato»).
        case nonRiuscita(String)
    }

    /// La versione del microfono installato secondo l'aiutante («1.0 (2)»); nil se l'aiutante non risponde
    /// o è di una versione che non la dice. Fuori dalla coda principale: aspetta la risposta.
    static func leggiVersioneInstallata() -> String? {
        var testo = [CChar](repeating: 0, count: 64)
        let riuscito = testo.withUnsafeMutableBufferPointer { buffer in
            microfono_leggi_versione(buffer.baseAddress, buffer.count)
        }
        guard riuscito else { return nil }
        let versione = testo.withUnsafeBufferPointer { buffer in String(cString: buffer.baseAddress!) }
        return versione.isEmpty ? nil : versione
    }

    /// Chiede al LaunchDaemon di rimozione (root) di togliere driver, aiutante e LaunchDaemon e di riavviare l'audio.
    /// Fuori dalla coda principale: dura qualche secondo.
    static func disinstalla() -> EsitoRimozione {
        var errore = [CChar](repeating: 0, count: 512)
        let esito = errore.withUnsafeMutableBufferPointer { buffer in
            microfono_disinstalla(buffer.baseAddress, buffer.count)
        }
        let dettaglio = errore.withUnsafeBufferPointer { buffer in String(cString: buffer.baseAddress!) }
        switch esito.rawValue {
        case MicrofonoRimozioneRiuscita.rawValue:
            return .riuscita
        case MicrofonoRimozioneServizioAssente.rawValue, MicrofonoRimozioneFirmaLocale.rawValue:
            return .serveLoScript
        default:
            return .nonRiuscita(dettaglio)
        }
    }

    // MARK: - Decodifica e posto nel tempo

    private func elabora(_ pacchetto: PacchettoAudio, scarto: Int64?, latenzaVideoMs: Int?) {
        guard !pacchetto.dati.isEmpty else { return }
        let quanti = decodifica(pacchetto.dati)
        guard quanti > 0 else { return }
        misuraLivello(quanti)

        // Senza differenza di orologi non si sa quando è stato catturato: solo il livello.
        guard let scarto else { return }
        aggiornaRitardo(latenzaVideoMs)

        let adessoMicro = Orologio.adesso()
        if !microfono_collegato() {
            guard adessoMicro &- ultimoTentativo > 2_000_000 else { return }
            ultimoTentativo = adessoMicro
            guard microfono_collega() else { return }
            registro.info("Memoria del microfono collegata")
            cursore = nil
        }

        // Valori dalla rete: aritmetica senza trabocchi che fermerebbero l'app (un orologio assurdo esce dal guard qui sotto).
        let cattura = Int64(truncatingIfNeeded: pacchetto.timestamp) &- scarto
        let ascolto = cattura &+ ritardo
        guard ascolto > 0 else { return }
        var posizione = Self.indiceAnello(UInt64(ascolto)) + Self.correzioneDecodifica
        // Puntuale (entro 10 ms): attaccato al precedente, senza buchi né sovrapposizioni.
        if let cursore {
            let distanza = posizione > cursore ? posizione - cursore : cursore - posizione
            if distanza <= Self.tolleranza { posizione = cursore }
        }

        let adesso = Self.indiceAnello(adessoMicro)
        var inizio = 0
        if posizione < adesso + Self.margine {
            // In ritardo: la parte già passata non serve più.
            let saltati = adesso + Self.margine - posizione
            guard saltati < UInt64(quanti) else {
                cursore = nil
                return
            }
            inizio = Int(saltati)
            posizione += saltati
        }
        // Troppo avanti (orologi impazziti): fuori dalla memoria condivisa.
        guard posizione < adesso + Self.capacita / 2 else {
            cursore = nil
            return
        }
        campioni.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            microfono_scrivi(posizione, base + inizio, UInt32(quanti - inizio))
        }
        cursore = posizione + UInt64(quanti - inizio)
    }

    /// Il ritardo segue la latenza del video, dentro 60–300 ms, e cambia solo oltre i 20 ms di differenza.
    private func aggiornaRitardo(_ latenzaVideoMs: Int?) {
        guard let latenzaVideoMs else { return }
        let voluto = min(max(Int64(latenzaVideoMs) * 1000, Self.ritardoMinimo), Self.ritardoMassimo)
        if abs(voluto - ritardo) > Self.isteresiRitardo {
            ritardo = voluto
        }
    }

    /// 48 campioni ogni millisecondo, come anello_indice_da_microsecondi in AnelloMicrofono.h.
    static func indiceAnello(_ microsecondi: UInt64) -> UInt64 {
        microsecondi / 1000 * 48 + (microsecondi % 1000) * 48 / 1000
    }

    /// Un frame AAC-LC → campioni Float32 mono in `campioni`. Restituisce quanti (di solito 1024; 0 se non va).
    private func decodifica(_ dati: Data) -> Int {
        guard let convertitore = convertitore ?? creaConvertitore() else { return 0 }
        descrizione.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                           mDataByteSize: UInt32(dati.count))
        var ingresso = IngressoDecodifica(byte: UInt32(dati.count), descrizione: descrizione)
        // Tutto lo spazio di `campioni`: ricampionando da 44,1 kHz un frame dà più di 1024 campioni, e con un limite
        // di 1024 il resto si accumulava nel convertitore finché non saltava un frame intero (un buco nella voce).
        var campioniUsciti = UInt32(campioni.count)
        let esito: OSStatus = dati.withUnsafeBytes { grezzi in
            ingresso.dati = grezzi.baseAddress
            return campioni.withUnsafeMutableBufferPointer { uscita in
                var lista = AudioBufferList(mNumberBuffers: 1,
                                            mBuffers: AudioBuffer(mNumberChannels: 1,
                                                                  mDataByteSize: UInt32(uscita.count * MemoryLayout<Float>.size),
                                                                  mData: UnsafeMutableRawPointer(uscita.baseAddress)))
                return withUnsafeMutablePointer(to: &ingresso) { puntatore in
                    AudioConverterFillComplexBuffer(convertitore, MicrofonoTelefono.fornisci, puntatore,
                                                    &campioniUsciti, &lista, nil)
                }
            }
        }
        // «Niente più dati» è la nostra risposta quando il frame è già stato consegnato: non è un errore.
        guard esito == noErr || esito == MicrofonoTelefono.finiti else {
            registro.error("Decodifica AAC non riuscita: \(esito)")
            chiudiConvertitore()
            return 0
        }
        return Int(min(campioniUsciti, UInt32(campioni.count)))
    }

    private struct IngressoDecodifica {
        var dati: UnsafeRawPointer?
        var byte: UInt32
        var descrizione: UnsafeMutablePointer<AudioStreamPacketDescription>
        var consegnato = false

        init(byte: UInt32, descrizione: UnsafeMutablePointer<AudioStreamPacketDescription>) {
            self.byte = byte
            self.descrizione = descrizione
        }
    }

    /// 'fini': il frame è già stato dato al decodificatore.
    private static let finiti: OSStatus = 0x6669_6E69

    /// Il decodificatore chiede dati: un frame solo, poi «finiti».
    private static let fornisci: AudioConverterComplexInputDataProc = { _, pacchetti, lista, descrizioni, contesto in
        guard let contesto else { return MicrofonoTelefono.finiti }
        let ingresso = contesto.assumingMemoryBound(to: IngressoDecodifica.self)
        guard !ingresso.pointee.consegnato, let dati = ingresso.pointee.dati else {
            pacchetti.pointee = 0
            return MicrofonoTelefono.finiti
        }
        ingresso.pointee.consegnato = true
        pacchetti.pointee = 1
        lista.pointee.mNumberBuffers = 1
        lista.pointee.mBuffers.mNumberChannels = 1
        lista.pointee.mBuffers.mDataByteSize = ingresso.pointee.byte
        lista.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: dati)
        // AAC ha frame di lunghezza variabile: il decodificatore vuole la descrizione.
        descrizioni?.pointee = ingresso.pointee.descrizione
        return noErr
    }

    private func creaConvertitore() -> AudioConverterRef? {
        guard formato.codec == FormatoAudio.aacLC else {
            registro.error("Codec audio non gestito: \(self.formato.codec, privacy: .public)")
            return nil
        }
        let canali = UInt32(max(formato.canali, 1))
        let frequenza = Float64(formato.frequenza > 0 ? formato.frequenza : 48_000)
        var ingresso = AudioStreamBasicDescription(mSampleRate: frequenza, mFormatID: kAudioFormatMPEG4AAC,
                                                   mFormatFlags: 0, mBytesPerPacket: 0,
                                                   mFramesPerPacket: UInt32(FormatoAudio.campioniPerPacchetto),
                                                   mBytesPerFrame: 0, mChannelsPerFrame: canali,
                                                   mBitsPerChannel: 0, mReserved: 0)
        // Sempre mono a 48 kHz: il driver ha un solo canale. Se il telefono manda stereo, il convertitore mescola.
        var uscita = AudioStreamBasicDescription(mSampleRate: Self.frequenza, mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                                 mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var nuovo: AudioConverterRef?
        let esito = AudioConverterNew(&ingresso, &uscita, &nuovo)
        guard esito == noErr, let nuovo else {
            registro.error("Decodificatore AAC non creato: \(esito)")
            return nil
        }
        // L'AudioSpecificConfig del telefono come «magic cookie» del decodificatore.
        if let configurazione = Data(base64Encoded: formato.configurazione), !configurazione.isEmpty {
            let esitoCookie = configurazione.withUnsafeBytes { byte in
                AudioConverterSetProperty(nuovo, kAudioConverterDecompressionMagicCookie,
                                          UInt32(configurazione.count), byte.baseAddress!)
            }
            if esitoCookie != noErr {
                // Per AAC-LC 48 kHz mono basta la descrizione qui sopra: si va avanti lo stesso.
                registro.info("Configurazione AAC non accettata: \(esitoCookie)")
            }
        }
        // Una frequenza diversa (per esempio 44,1 kHz) si ricampiona: qualità alta, è poco audio.
        var qualita = UInt32(kAudioConverterQuality_High)
        AudioConverterSetProperty(nuovo, kAudioConverterSampleRateConverterQuality,
                                  UInt32(MemoryLayout<UInt32>.size), &qualita)
        convertitore = nuovo
        return nuovo
    }

    private func chiudiConvertitore() {
        if let convertitore { AudioConverterDispose(convertitore) }
        convertitore = nil
    }

    // MARK: - Livello

    private func misuraLivello(_ quanti: Int) {
        for indice in 0..<quanti {
            sommaQuadrati += campioni[indice] * campioni[indice]
        }
        campioniMisurati += quanti
        let adesso = Orologio.adesso()
        guard adesso &- ultimoLivello >= 100_000, campioniMisurati > 0 else { return }
        ultimoLivello = adesso
        let rms = (sommaQuadrati / Float(campioniMisurati)).squareRoot()
        sommaQuadrati = 0
        campioniMisurati = 0
        // Da -60 dB (0) a 0 dB (1).
        let decibel = 20 * log10(max(rms, 0.000_001))
        mandaLivello(Double(min(max((decibel + 60) / 60, 0), 1)))
    }

    private func mandaLivello(_ livello: Double) {
        let destinatario = suLivello
        DispatchQueue.main.async {
            MainActor.assumeIsolated { destinatario?(livello) }
        }
    }
}
