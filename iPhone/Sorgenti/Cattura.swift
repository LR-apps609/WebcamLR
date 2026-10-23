import AVFoundation
import WebcamLRProtocollo

/// Gli obiettivi che l'utente può scegliere (funzione 17).
enum Obiettivo: String, CaseIterable, Identifiable, Sendable {
    case grandangolo, principale, tele, frontale

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .grandangolo: "0,5"
        case .principale: "1×"
        case .tele: "Tele"
        case .frontale: "Front."
        }
    }

    var tipo: AVCaptureDevice.DeviceType {
        switch self {
        case .grandangolo: .builtInUltraWideCamera
        case .principale, .frontale: .builtInWideAngleCamera
        case .tele: .builtInTelephotoCamera
        }
    }

    var posizione: AVCaptureDevice.Position {
        self == .frontale ? .front : .back
    }

    var dispositivo: AVCaptureDevice? {
        AVCaptureDevice.default(tipo, for: .video, position: posizione)
    }

    static var disponibili: [Obiettivo] {
        allCases.filter { $0.dispositivo != nil }
    }
}

enum ErroreCattura: LocalizedError {
    case permessoNegato
    case obiettivoMancante
    case configurazione

    var errorDescription: String? {
        switch self {
        case .permessoNegato: "WebcamLR non può usare la fotocamera: attivala in Impostazioni › WebcamLR."
        case .obiettivoMancante: "Questo obiettivo non c'è su questo iPhone."
        case .configurazione: "La fotocamera non accetta questa configurazione."
        }
    }
}

/// Cattura il video dalla fotocamera e consegna i fotogrammi al codificatore.
/// Tutto il lavoro avviene sulla coda `coda`; `anteprima` si mostra nell'interfaccia.
final class Cattura: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sessione = AVCaptureSession()
    let anteprima: AVCaptureVideoPreviewLayer
    /// Chiamata sulla coda di cattura per ogni fotogramma.
    var suFotogramma: ((CMSampleBuffer) -> Void)?

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.cattura", qos: .userInteractive)
    private let uscita = AVCaptureVideoDataOutput()
    private var ingresso: AVCaptureDeviceInput?
    private var coordinatore: AVCaptureDevice.RotationCoordinator?
    private var osservazioni: [NSKeyValueObservation] = []
    private var osservatoreScena: NSObjectProtocol?

    override init() {
        anteprima = AVCaptureVideoPreviewLayer(session: sessione)
        anteprima.videoGravity = .resizeAspect
        super.init()
        uscita.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        uscita.alwaysDiscardsLateVideoFrames = true
        uscita.setSampleBufferDelegate(self, queue: coda)
        // Dopo un tocco per il fuoco: se la scena cambia molto, si torna al fuoco continuo.
        osservatoreScena = NotificationCenter.default.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                                                                  object: nil, queue: nil) { [weak self] _ in
            self?.fuocoContinuo()
        }
    }

    deinit {
        if let osservatoreScena { NotificationCenter.default.removeObserver(osservatoreScena) }
    }

    static func chiediPermesso() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Sceglie obiettivo, risoluzione e fotogrammi al secondo, poi avvia la cattura.
    func configura(obiettivo: Obiettivo, larghezza: Int32, altezza: Int32, fps: Int) async throws {
        guard await Self.chiediPermesso() else { throw ErroreCattura.permessoNegato }
        guard let dispositivo = obiettivo.dispositivo else { throw ErroreCattura.obiettivoMancante }
        try await withCheckedThrowingContinuation { (continuazione: CheckedContinuation<Void, Error>) in
            coda.async {
                do {
                    try self.applica(dispositivo: dispositivo, larghezza: larghezza, altezza: altezza, fps: fps)
                    if !self.sessione.isRunning { self.sessione.startRunning() }
                    continuazione.resume()
                } catch {
                    continuazione.resume(throwing: error)
                }
            }
        }
    }

    func ferma() {
        coda.async {
            if self.sessione.isRunning { self.sessione.stopRunning() }
        }
    }

    /// Torcia come luce di riempimento (funzione 26), solo sugli obiettivi posteriori.
    func torcia(_ accesa: Bool) {
        coda.async {
            guard let dispositivo = self.ingresso?.device, dispositivo.hasTorch else { return }
            do {
                try dispositivo.lockForConfiguration()
                dispositivo.torchMode = accesa ? .on : .off
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Tocco per mettere a fuoco ed esporre (funzione 21). `punto` è nelle coordinate dell'anteprima.
    func metteAFuoco(suPuntoDellAnteprima punto: CGPoint) {
        let puntoDispositivo = anteprima.captureDevicePointConverted(fromLayerPoint: punto)
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            do {
                try dispositivo.lockForConfiguration()
                if dispositivo.isFocusPointOfInterestSupported && dispositivo.isFocusModeSupported(.autoFocus) {
                    dispositivo.focusPointOfInterest = puntoDispositivo
                    dispositivo.focusMode = .autoFocus
                }
                if dispositivo.isExposurePointOfInterestSupported && dispositivo.isExposureModeSupported(.autoExpose) {
                    dispositivo.exposurePointOfInterest = puntoDispositivo
                    dispositivo.exposureMode = .autoExpose
                }
                // Se poi la scena cambia molto, torna al fuoco continuo.
                dispositivo.isSubjectAreaChangeMonitoringEnabled = true
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Torna al fuoco e all'esposizione automatici continui.
    func fuocoContinuo() {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            do {
                try dispositivo.lockForConfiguration()
                if dispositivo.isFocusModeSupported(.continuousAutoFocus) { dispositivo.focusMode = .continuousAutoFocus }
                if dispositivo.isExposureModeSupported(.continuousAutoExposure) { dispositivo.exposureMode = .continuousAutoExposure }
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Zoom fluido dentro l'obiettivo scelto (funzione 22), al massimo 10×.
    func zoom(_ fattore: CGFloat) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            let limitato = min(max(fattore, dispositivo.minAvailableVideoZoomFactor),
                               min(dispositivo.maxAvailableVideoZoomFactor, 10))
            do {
                try dispositivo.lockForConfiguration()
                dispositivo.videoZoomFactor = limitato
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    var haTorcia: Bool {
        ingresso?.device.hasTorch ?? false
    }

    private func applica(dispositivo: AVCaptureDevice, larghezza: Int32, altezza: Int32, fps: Int) throws {
        sessione.beginConfiguration()
        defer { sessione.commitConfiguration() }

        if let ingresso { sessione.removeInput(ingresso) }
        let nuovo = try AVCaptureDeviceInput(device: dispositivo)
        guard sessione.canAddInput(nuovo) else { throw ErroreCattura.configurazione }
        sessione.addInput(nuovo)
        ingresso = nuovo
        if !sessione.outputs.contains(uscita) {
            guard sessione.canAddOutput(uscita) else { throw ErroreCattura.configurazione }
            sessione.addOutput(uscita)
        }
        sessione.sessionPreset = .inputPriority

        let formato = Self.formato(di: dispositivo, larghezza: larghezza, altezza: altezza, fps: fps)
            ?? Self.formato(di: dispositivo, larghezza: 1920, altezza: 1080, fps: 30)
        try dispositivo.lockForConfiguration()
        if let formato {
            dispositivo.activeFormat = formato
            let massimo = formato.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
            let durata = CMTime(value: 1, timescale: CMTimeScale(min(Double(fps), massimo)))
            dispositivo.activeVideoMinFrameDuration = durata
            dispositivo.activeVideoMaxFrameDuration = durata
        }
        dispositivo.unlockForConfiguration()

        // Il coordinatore della rotazione lavora con il livello di anteprima: va creato sul thread principale.
        DispatchQueue.main.async { self.ruota(con: dispositivo) }
    }

    /// Il primo formato con le dimensioni e i fotogrammi richiesti, preferendo 420v.
    private static func formato(di dispositivo: AVCaptureDevice, larghezza: Int32, altezza: Int32, fps: Int) -> AVCaptureDevice.Format? {
        let adatti = dispositivo.formats.filter { formato in
            let dimensioni = CMVideoFormatDescriptionGetDimensions(formato.formatDescription)
            return dimensioni.width == larghezza && dimensioni.height == altezza
                && formato.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) }
        }
        return adatti.first { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange }
            ?? adatti.first
    }

    /// Tiene il video dritto rispetto all'orizzonte, comunque sia girato il telefono.
    private func ruota(con dispositivo: AVCaptureDevice) {
        osservazioni.removeAll()
        let coordinatore = AVCaptureDevice.RotationCoordinator(device: dispositivo, previewLayer: anteprima)
        self.coordinatore = coordinatore
        osservazioni.append(coordinatore.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinatore, _ in
            guard let self else { return }
            let angolo = coordinatore.videoRotationAngleForHorizonLevelCapture
            self.coda.async {
                if let connessione = self.uscita.connection(with: .video), connessione.isVideoRotationAngleSupported(angolo) {
                    connessione.videoRotationAngle = angolo
                }
            }
        })
        osservazioni.append(coordinatore.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinatore, _ in
            let angolo = coordinatore.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                if let connessione = self?.anteprima.connection, connessione.isVideoRotationAngleSupported(angolo) {
                    connessione.videoRotationAngle = angolo
                }
            }
        })
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        suFotogramma?(sampleBuffer)
    }
}
