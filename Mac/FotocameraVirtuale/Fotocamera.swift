import CoreMediaIO
import Foundation
import IOKit.audio
import os.log

// Webcam virtuale WebcamLR (funzione 11). Ha due flussi:
// - «video», in uscita: quello che vedono Zoom, FaceTime e le altre app;
// - «ingresso», in entrata: l'app WebcamLR ci mette le immagini dell'iPhone (UscitaWebcam.swift).
// Senza immagini recenti dall'app manda un'immagine di prova: fondo scuro e una barra ciano che scorre.

private let larghezza: Int32 = 1920
private let altezza: Int32 = 1080
private let fotogrammiAlSecondo: Int32 = 30
private let registro = Logger(subsystem: "it.lrapps.webcamlr.mac.fotocamera", category: "fotocamera")

// Identificativi fissi: le app ricordano la webcam scelta tra un avvio e l'altro.
private let idDispositivo = UUID(uuidString: "6F1D2C64-1B8E-4C5A-9E0A-57C3B1A4D2E1")!
private let idFlusso = UUID(uuidString: "9A2B7E10-3C4D-4F6A-8B1E-2D5C6A7B8C90")!
private let idFlussoIngresso = UUID(uuidString: "3E8C1F42-7A6B-4D19-B2C5-0F9E8D7C6B5A")!
/// Oltre questo tempo senza immagini dall'app si torna all'immagine di prova.
private let validitaImmagineApp: UInt64 = 1_000_000_000

final class SorgenteDispositivo: NSObject, CMIOExtensionDeviceSource {
    private(set) var dispositivo: CMIOExtensionDevice!
    private var sorgenteFlusso: SorgenteFlusso!
    private var sorgenteIngresso: SorgenteFlusso!
    private var ingressoAttivo = false
    // Lette e scritte solo su codaTimer.
    private var ultimaDaApp: CVPixelBuffer?
    private var istanteDaApp: UInt64 = 0
    private var utentiAttivi: UInt32 = 0
    private var timer: DispatchSourceTimer?
    private let codaTimer = DispatchQueue(label: "fotocamera.timer", qos: .userInteractive)
    private var descrizioneVideo: CMFormatDescription!
    private var poolBuffer: CVPixelBufferPool!
    private let attributiBuffer: NSDictionary = [kCVPixelBufferPoolAllocationThresholdKey: 5]
    private var rigaBarra: Int = 0

    init(nome: String) {
        super.init()
        dispositivo = CMIOExtensionDevice(localizedName: nome, deviceID: idDispositivo, legacyDeviceID: nil, source: self)

        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA,
                                       width: larghezza, height: altezza, extensions: nil,
                                       formatDescriptionOut: &descrizioneVideo)
        let attributiPixel: NSDictionary = [
            kCVPixelBufferWidthKey: larghezza,
            kCVPixelBufferHeightKey: altezza,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributiPixel, &poolBuffer)

        let durata = CMTime(value: 1, timescale: fotogrammiAlSecondo)
        let formato = CMIOExtensionStreamFormat(formatDescription: descrizioneVideo,
                                                maxFrameDuration: durata, minFrameDuration: durata,
                                                validFrameDurations: nil)
        sorgenteFlusso = SorgenteFlusso(nome: "WebcamLR · video", id: idFlusso, formato: formato,
                                        dispositivo: dispositivo, direzione: .source)
        sorgenteIngresso = SorgenteFlusso(nome: "WebcamLR · ingresso", id: idFlussoIngresso, formato: formato,
                                          dispositivo: dispositivo, direzione: .sink)
        segnalaInOnda()
        do {
            try dispositivo.addStream(sorgenteFlusso.flusso)
            try dispositivo.addStream(sorgenteIngresso.flusso)
        } catch {
            fatalError("Impossibile aggiungere il flusso video: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let proprieta = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            proprieta.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            proprieta.model = "WebcamLR"
        }
        return proprieta
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    /// Scrive nello spazio condiviso con l'app (App Group) se qualcuno sta usando la webcam:
    /// l'app mostra il rosso «IN ONDA» e lo dice all'iPhone.
    private func segnalaInOnda() {
        guard let gruppo = Bundle.main.object(forInfoDictionaryKey: "WebcamLRGruppo") as? String else { return }
        UserDefaults(suiteName: gruppo)?.set(utentiAttivi > 0, forKey: "inOnda")
    }

    func avviaInvio() {
        guard poolBuffer != nil else { return }
        utentiAttivi += 1
        segnalaInOnda()
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: codaTimer)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(fotogrammiAlSecondo), leeway: .seconds(0))
        timer.setEventHandler { [weak self] in self?.inviaFotogramma() }
        timer.resume()
        self.timer = timer
    }

    func fermaInvio() {
        if utentiAttivi > 1 {
            utentiAttivi -= 1
        } else {
            utentiAttivi = 0
            timer?.cancel()
            timer = nil
        }
        segnalaInOnda()
    }

    // MARK: - Ingresso dall'app

    func avviaIngresso(client: CMIOExtensionClient) {
        ingressoAttivo = true
        consuma(da: client)
    }

    func fermaIngresso() {
        ingressoAttivo = false
    }

    /// Prende le immagini che l'app mette nel flusso di ingresso, una dopo l'altra.
    private func consuma(da client: CMIOExtensionClient) {
        guard ingressoAttivo else { return }
        sorgenteIngresso.flusso.consumeSampleBuffer(from: client) { [weak self] campione, sequenza, _, _, _ in
            guard let self else { return }
            guard let campione, let immagine = CMSampleBufferGetImageBuffer(campione) else {
                // Niente di pronto o un errore: si riprova tra poco, senza girare a vuoto.
                self.codaTimer.asyncAfter(deadline: .now() + .milliseconds(10)) { self.consuma(da: client) }
                return
            }
            let adesso = DispatchTime.now().uptimeNanoseconds
            self.codaTimer.async {
                self.ultimaDaApp = immagine
                self.istanteDaApp = adesso
            }
            let uscita = CMIOExtensionScheduledOutput(sequenceNumber: sequenza, hostTimeInNanoseconds: adesso)
            self.sorgenteIngresso.flusso.notifyScheduledOutputChanged(uscita)
            self.consuma(da: client)
        }
    }

    // MARK: - Uscita verso le app

    private func inviaFotogramma() {
        if let immagine = ultimaDaApp, DispatchTime.now().uptimeNanoseconds - istanteDaApp < validitaImmagineApp {
            invia(immagine)
            return
        }
        ultimaDaApp = nil
        var bufferCreato: CVPixelBuffer?
        let esito = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, poolBuffer, attributiBuffer, &bufferCreato)
        guard esito == kCVReturnSuccess, let buffer = bufferCreato else {
            registro.error("Buffer video esauriti: \(esito)")
            return
        }
        disegnaProva(in: buffer)
        invia(buffer)
    }

    private func invia(_ buffer: CVPixelBuffer) {
        var descrizioneCreata: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                     formatDescriptionOut: &descrizioneCreata)
        guard let descrizione = descrizioneCreata else { return }
        var tempi = CMSampleTimingInfo()
        tempi.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
        var campioneCreato: CMSampleBuffer?
        let creato = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true,
                                                        makeDataReadyCallback: nil, refcon: nil,
                                                        formatDescription: descrizione, sampleTiming: &tempi,
                                                        sampleBufferOut: &campioneCreato)
        guard creato == noErr, let campione = campioneCreato else { return }
        sorgenteFlusso.flusso.send(campione, discontinuity: [],
                                   hostTimeInNanoseconds: UInt64(tempi.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
    }

    /// Fondo #0F1413 con una barra ciano #6CBCC4 alta 24 righe che scende.
    private func disegnaProva(in buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let righe = CVPixelBufferGetHeight(buffer)
        let byteRiga = CVPixelBufferGetBytesPerRow(buffer)
        // BGRA in memoria.
        let fondo: [UInt8] = [0x13, 0x14, 0x0F, 0xFF]
        let barra: [UInt8] = [0xC4, 0xBC, 0x6C, 0xFF]
        for riga in 0..<righe {
            let colore = (riga - rigaBarra + righe) % righe < 24 ? barra : fondo
            colore.withUnsafeBytes { memset_pattern4(base + riga * byteRiga, $0.baseAddress!, byteRiga) }
        }
        rigaBarra = (rigaBarra + 4) % righe
    }
}

final class SorgenteFlusso: NSObject, CMIOExtensionStreamSource {
    private(set) var flusso: CMIOExtensionStream!
    let dispositivo: CMIOExtensionDevice
    private let formato: CMIOExtensionStreamFormat

    let direzione: CMIOExtensionStream.Direction
    private var clientIngresso: CMIOExtensionClient?

    init(nome: String, id: UUID, formato: CMIOExtensionStreamFormat, dispositivo: CMIOExtensionDevice,
         direzione: CMIOExtensionStream.Direction) {
        self.dispositivo = dispositivo
        self.formato = formato
        self.direzione = direzione
        super.init()
        flusso = CMIOExtensionStream(localizedName: nome, streamID: id, direction: direzione, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] {
        [formato]
    }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        if direzione == .sink {
            return [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize,
                    .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
        }
        return [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let proprieta = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            proprieta.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            proprieta.frameDuration = CMTime(value: 1, timescale: fotogrammiAlSecondo)
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            proprieta.sinkBufferQueueSize = 1
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            proprieta.sinkBuffersRequiredForStartup = 1
        }
        return proprieta
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let indice = streamProperties.activeFormatIndex {
            activeFormatIndex = indice
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        if direzione == .sink { clientIngresso = client }
        return true
    }

    func startStream() throws {
        guard let sorgente = dispositivo.source as? SorgenteDispositivo else { return }
        if direzione == .sink {
            if let clientIngresso { sorgente.avviaIngresso(client: clientIngresso) }
        } else {
            sorgente.avviaInvio()
        }
    }

    func stopStream() throws {
        guard let sorgente = dispositivo.source as? SorgenteDispositivo else { return }
        if direzione == .sink {
            sorgente.fermaIngresso()
        } else {
            sorgente.fermaInvio()
        }
    }
}

final class SorgenteProvider: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var sorgenteDispositivo: SorgenteDispositivo!

    init(codaClient: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: codaClient)
        sorgenteDispositivo = SorgenteDispositivo(nome: "WebcamLR")
        do {
            try provider.addDevice(sorgenteDispositivo.dispositivo)
        } catch {
            fatalError("Impossibile aggiungere la webcam: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let proprieta = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            proprieta.manufacturer = "LR apps"
        }
        return proprieta
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
