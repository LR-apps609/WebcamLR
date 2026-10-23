import CoreMediaIO
import Foundation
import IOKit.audio
import os.log

// Webcam virtuale WebcamLR (funzione 11). Per ora manda un'immagine di prova:
// fondo scuro e una barra ciano che scorre. Al round 2 riceverà il video dall'app.

private let larghezza: Int32 = 1920
private let altezza: Int32 = 1080
private let fotogrammiAlSecondo: Int32 = 30
private let registro = Logger(subsystem: "it.lrapps.webcamlr.mac.fotocamera", category: "fotocamera")

// Identificativi fissi: le app ricordano la webcam scelta tra un avvio e l'altro.
private let idDispositivo = UUID(uuidString: "6F1D2C64-1B8E-4C5A-9E0A-57C3B1A4D2E1")!
private let idFlusso = UUID(uuidString: "9A2B7E10-3C4D-4F6A-8B1E-2D5C6A7B8C90")!

final class SorgenteDispositivo: NSObject, CMIOExtensionDeviceSource {
    private(set) var dispositivo: CMIOExtensionDevice!
    private var sorgenteFlusso: SorgenteFlusso!
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
        sorgenteFlusso = SorgenteFlusso(nome: "WebcamLR · video", id: idFlusso, formato: formato, dispositivo: dispositivo)
        do {
            try dispositivo.addStream(sorgenteFlusso.flusso)
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

    func avviaInvio() {
        guard poolBuffer != nil else { return }
        utentiAttivi += 1
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
    }

    private func inviaFotogramma() {
        var buffer: CVPixelBuffer?
        let esito = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, poolBuffer, attributiBuffer, &buffer)
        guard esito == kCVReturnSuccess, let buffer else {
            registro.error("Buffer video esauriti: \(esito)")
            return
        }
        disegnaProva(in: buffer)

        var tempi = CMSampleTimingInfo()
        tempi.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
        var campione: CMSampleBuffer?
        let creato = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true,
                                                        makeDataReadyCallback: nil, refcon: nil,
                                                        formatDescription: descrizioneVideo, sampleTiming: &tempi,
                                                        sampleBufferOut: &campione)
        guard creato == noErr, let campione else { return }
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

    init(nome: String, id: UUID, formato: CMIOExtensionStreamFormat, dispositivo: CMIOExtensionDevice) {
        self.dispositivo = dispositivo
        self.formato = formato
        super.init()
        flusso = CMIOExtensionStream(localizedName: nome, streamID: id, direction: .source, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] {
        [formato]
    }

    var activeFormatIndex: Int = 0

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let proprieta = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            proprieta.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            proprieta.frameDuration = CMTime(value: 1, timescale: fotogrammiAlSecondo)
        }
        return proprieta
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let indice = streamProperties.activeFormatIndex {
            activeFormatIndex = indice
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        (dispositivo.source as? SorgenteDispositivo)?.avviaInvio()
    }

    func stopStream() throws {
        (dispositivo.source as? SorgenteDispositivo)?.fermaInvio()
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
