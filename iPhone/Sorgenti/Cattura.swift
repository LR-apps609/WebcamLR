import AVFoundation
import WebcamLRProtocollo

/// Gli obiettivi che l'utente può scegliere (funzione 17).
enum Obiettivo: String, CaseIterable, Identifiable, Sendable {
    case grandangolo, principale, tele, frontale

    var id: String { rawValue }

    var etichetta: String {
        switch self {
        case .grandangolo: "0,5×"
        case .principale: "1×"
        case .tele: "Tele"
        case .frontale: "Frontale"
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

    /// Calcolati una volta sola: cercare i dispositivi costa qualche millisecondo a ogni chiamata.
    static let disponibili: [Obiettivo] = Obiettivo.allCases.filter { $0.dispositivo != nil }

    /// Da chiamare all'avvio: cerca gli obiettivi fuori dal thread principale.
    static func prepara() {
        DispatchQueue.global(qos: .userInitiated).async { _ = disponibili }
    }
}

enum ErroreCattura: LocalizedError {
    case permessoNegato
    case obiettivoMancante
    case configurazione

    var errorDescription: String? {
        switch self {
        case .permessoNegato: "WebcamLR non può usare la fotocamera: attivala in Impostazioni › WebcamLR."
        case .obiettivoMancante: "Questo obiettivo non c'è su questo iPhone: scegline un altro."
        case .configurazione: "La fotocamera non accetta questa risoluzione: scegline un'altra in Impostazioni e tocca «Riprova»."
        }
    }
}

/// Cattura il video dalla fotocamera e consegna i fotogrammi al codificatore.
/// Tutto il lavoro avviene sulla coda `coda`; `anteprima` si mostra nell'interfaccia.
final class Cattura: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sessione = AVCaptureSession()
    /// L'immagine grezza della fotocamera, senza effetti: il ritardo più basso.
    // TODO: con `PipelineEffetti.anteprimaConEffetti` mostrare sopra i buffer elaborati (vedi PipelineEffetti).
    let anteprima: AVCaptureVideoPreviewLayer
    /// Chiamata sulla coda di cattura per ogni fotogramma (buffer 420v, già girato e specchiato dalla connessione).
    /// Chi la riceve passa il buffer a `PipelineEffetti.elabora` e poi al codificatore.
    var suFotogramma: ((CMSampleBuffer) -> Void)?

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.cattura", qos: .userInteractive)
    private let uscita = AVCaptureVideoDataOutput()
    private var ingresso: AVCaptureDeviceInput?
    private var coordinatore: AVCaptureDevice.RotationCoordinator?
    private var osservazioni: [NSKeyValueObservation] = []
    private var osservatoreScena: NSObjectProtocol?
    private var osservatoreErrori: NSObjectProtocol?
    /// La cattura deve andare (configurata e non fermata). Solo su `coda`.
    private var attiva = false
    /// ISO o tempo manuali dal computer: il tocco e il fuoco continuo non toccano l'esposizione. Solo su `coda`.
    private var esposizioneBloccata = false
    /// Fuoco ed esposizione bloccati con il tocco lungo (round 2): la scena che cambia non li sblocca. Solo su `coda`.
    private var aeafBloccati = false
    /// Cresce a ogni tocco: un blocco rimasto in attesa non scatta dopo un tocco più recente. Solo su `coda`.
    private var generazioneFuoco = 0

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
            self?.fuocoContinuo(ancheSeBloccati: false)
        }
        // I servizi multimediali di iOS ripartiti da capo fermano la cattura: si riavvia, se doveva andare.
        osservatoreErrori = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                                   object: sessione, queue: nil) { [weak self] notifica in
            guard let self,
                  (notifica.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset else { return }
            self.coda.async {
                if self.attiva && !self.sessione.isRunning { self.sessione.startRunning() }
            }
        }
    }

    deinit {
        if let osservatoreScena { NotificationCenter.default.removeObserver(osservatoreScena) }
        if let osservatoreErrori { NotificationCenter.default.removeObserver(osservatoreErrori) }
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
    func configura(obiettivo: Obiettivo, larghezza: Int32, altezza: Int32, fps: Int, specchia: Bool = false,
                   stabilizzazione: Bool = false) async throws {
        guard await Self.chiediPermesso() else { throw ErroreCattura.permessoNegato }
        guard let dispositivo = obiettivo.dispositivo else { throw ErroreCattura.obiettivoMancante }
        try await withCheckedThrowingContinuation { (continuazione: CheckedContinuation<Void, Error>) in
            coda.async {
                do {
                    try self.applica(dispositivo: dispositivo, larghezza: larghezza, altezza: altezza, fps: fps)
                    self.specchia(specchia)
                    self.stabilizza(stabilizzazione)
                    self.attiva = true
                    if !self.sessione.isRunning { self.sessione.startRunning() }
                    continuazione.resume()
                } catch {
                    continuazione.resume(throwing: error)
                }
            }
        }
    }

    /// Specchia l'immagine inviata al computer (funzione 25); l'anteprima sul telefono non cambia.
    private func specchia(_ attivo: Bool) {
        guard let connessione = uscita.connection(with: .video), connessione.isVideoMirroringSupported else { return }
        connessione.automaticallyAdjustsVideoMirroring = false
        connessione.isVideoMirrored = attivo
    }

    /// Stabilizzazione (round 2): spenta di serie perché trattiene qualche fotogramma e aggiunge ritardo;
    /// «Standard» a scelta nelle impostazioni.
    private func stabilizza(_ attiva: Bool) {
        guard let connessione = uscita.connection(with: .video), connessione.isVideoStabilizationSupported else { return }
        connessione.preferredVideoStabilizationMode = attiva ? .standard : .off
    }

    func ferma() {
        coda.async {
            self.attiva = false
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
            // Un tocco sblocca anche fuoco ed esposizione bloccati.
            self.aeafBloccati = false
            self.generazioneFuoco += 1
            do {
                try dispositivo.lockForConfiguration()
                if dispositivo.isFocusPointOfInterestSupported && dispositivo.isFocusModeSupported(.autoFocus) {
                    dispositivo.focusPointOfInterest = puntoDispositivo
                    dispositivo.focusMode = .autoFocus
                }
                if !self.esposizioneBloccata, dispositivo.isExposurePointOfInterestSupported,
                   dispositivo.isExposureModeSupported(.autoExpose) {
                    dispositivo.exposurePointOfInterest = puntoDispositivo
                    dispositivo.exposureMode = .autoExpose
                }
                // Se poi la scena cambia molto, torna al fuoco continuo.
                dispositivo.isSubjectAreaChangeMonitoringEnabled = true
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Tocco lungo (round 2): fuoco ed esposizione sul punto, poi bloccati come nella Fotocamera.
    /// L'esposizione manuale dal computer resta com'è.
    func bloccaFuocoEdEsposizione(suPuntoDellAnteprima punto: CGPoint) {
        let puntoDispositivo = anteprima.captureDevicePointConverted(fromLayerPoint: punto)
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            self.aeafBloccati = true
            self.generazioneFuoco += 1
            let generazione = self.generazioneFuoco
            do {
                try dispositivo.lockForConfiguration()
                dispositivo.isSubjectAreaChangeMonitoringEnabled = false
                if dispositivo.isFocusPointOfInterestSupported && dispositivo.isFocusModeSupported(.autoFocus) {
                    dispositivo.focusPointOfInterest = puntoDispositivo
                    dispositivo.focusMode = .autoFocus
                }
                if !self.esposizioneBloccata, dispositivo.isExposurePointOfInterestSupported,
                   dispositivo.isExposureModeSupported(.autoExpose) {
                    dispositivo.exposurePointOfInterest = puntoDispositivo
                    dispositivo.exposureMode = .autoExpose
                }
                dispositivo.unlockForConfiguration()
            } catch {}
            // Il tempo di mettere a fuoco ed esporre sul punto, poi si blocca.
            self.coda.asyncAfter(deadline: .now() + 0.8) {
                guard self.aeafBloccati, self.generazioneFuoco == generazione,
                      let attuale = self.ingresso?.device else { return }
                do {
                    try attuale.lockForConfiguration()
                    if attuale.isFocusModeSupported(.locked) { attuale.focusMode = .locked }
                    if !self.esposizioneBloccata, attuale.isExposureModeSupported(.locked) {
                        attuale.exposureMode = .locked
                    }
                    attuale.unlockForConfiguration()
                } catch {}
            }
        }
    }

    /// Torna al fuoco e all'esposizione automatici continui.
    /// `ancheSeBloccati` falso: quando la scena cambia, ma fuoco ed esposizione bloccati restano tali.
    func fuocoContinuo(ancheSeBloccati: Bool = true) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            if self.aeafBloccati && !ancheSeBloccati { return }
            self.aeafBloccati = false
            self.generazioneFuoco += 1
            do {
                try dispositivo.lockForConfiguration()
                if dispositivo.isFocusModeSupported(.continuousAutoFocus) { dispositivo.focusMode = .continuousAutoFocus }
                if !self.esposizioneBloccata, dispositivo.isExposureModeSupported(.continuousAutoExposure) {
                    dispositivo.exposureMode = .continuousAutoExposure
                }
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Zoom fluido dentro l'obiettivo scelto (funzione 22), al massimo 10×.
    /// `scorrevole`: arriva al fattore con una rampa invece di saltare (comandi dal computer, round 2);
    /// il pizzico sullo schermo resta diretto.
    func zoom(_ fattore: CGFloat, scorrevole: Bool = false) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            let limitato = min(max(fattore, dispositivo.minAvailableVideoZoomFactor),
                               min(dispositivo.maxAvailableVideoZoomFactor, 10))
            do {
                try dispositivo.lockForConfiguration()
                if scorrevole {
                    // Velocità in raddoppi al secondo: da 1× a 4× in mezzo secondo circa.
                    dispositivo.ramp(toVideoZoomFactor: limitato, withRate: 4)
                } else {
                    if dispositivo.isRampingVideoZoom { dispositivo.cancelVideoZoomRamp() }
                    dispositivo.videoZoomFactor = limitato
                }
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Compensazione dell'esposizione in stop (funzione 19), entro i limiti dell'obiettivo.
    func esposizione(_ stop: Float) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            let limitato = min(max(stop, dispositivo.minExposureTargetBias), dispositivo.maxExposureTargetBias)
            do {
                try dispositivo.lockForConfiguration()
                dispositivo.setExposureTargetBias(limitato, completionHandler: nil)
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// ISO e tempo di posa manuali (funzione 19). `iso` 0 = automatico; `tempo` è il denominatore
    /// (60 = 1/60 s), 0 = automatico. Entrambi a 0: si torna all'esposizione automatica continua.
    func esposizioneManuale(iso: Float, tempo: Int) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            do {
                try dispositivo.lockForConfiguration()
                defer { dispositivo.unlockForConfiguration() }
                if iso <= 0 && tempo <= 0 || !dispositivo.isExposureModeSupported(.custom) {
                    self.esposizioneBloccata = false
                    if dispositivo.isExposureModeSupported(.continuousAutoExposure) {
                        dispositivo.exposureMode = .continuousAutoExposure
                    }
                    return
                }
                let formato = dispositivo.activeFormat
                let isoScelto = iso > 0 ? min(max(iso, formato.minISO), formato.maxISO) : AVCaptureDevice.currentISO
                var durata = tempo > 0 ? CMTime(value: 1, timescale: CMTimeScale(tempo)) : AVCaptureDevice.currentExposureDuration
                if tempo > 0 {
                    if CMTimeCompare(durata, formato.minExposureDuration) < 0 { durata = formato.minExposureDuration }
                    if CMTimeCompare(durata, formato.maxExposureDuration) > 0 { durata = formato.maxExposureDuration }
                    // Oltre la durata di un fotogramma iOS abbasserebbe i fotogrammi al secondo: il video rallenta.
                    let fotogramma = dispositivo.activeVideoMinFrameDuration
                    if fotogramma.isValid, CMTimeCompare(durata, fotogramma) > 0 { durata = fotogramma }
                }
                dispositivo.setExposureModeCustom(duration: durata, iso: isoScelto, completionHandler: nil)
                self.esposizioneBloccata = true
            } catch {}
        }
    }

    /// Limiti ISO dell'obiettivo attuale, per i comandi dal computer.
    var limitiISO: (minimo: Double, massimo: Double)? {
        guard let formato = ingresso?.device.activeFormat else { return nil }
        return (Double(formato.minISO), Double(formato.maxISO))
    }

    /// Bilanciamento del bianco in kelvin (funzione 20); 0 = automatico.
    func bianco(kelvin: Int) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            do {
                try dispositivo.lockForConfiguration()
                defer { dispositivo.unlockForConfiguration() }
                if kelvin == 0 || !dispositivo.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                    if dispositivo.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        dispositivo.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    return
                }
                let valori = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(kelvin), tint: 0)
                var guadagni = dispositivo.deviceWhiteBalanceGains(for: valori)
                let massimo = dispositivo.maxWhiteBalanceGain
                guadagni.redGain = min(max(guadagni.redGain, 1), massimo)
                guadagni.greenGain = min(max(guadagni.greenGain, 1), massimo)
                guadagni.blueGain = min(max(guadagni.blueGain, 1), massimo)
                dispositivo.setWhiteBalanceModeLocked(with: guadagni, completionHandler: nil)
            } catch {}
        }
    }

    /// Lo zoom massimo che ha senso offrire con l'obiettivo attuale.
    var zoomMassimo: Double {
        Double(min(ingresso?.device.maxAvailableVideoZoomFactor ?? 1, 10))
    }

    var haTorcia: Bool {
        ingresso?.device.hasTorch ?? false
    }

    // MARK: Formati (richieste `formato` dal computer)

    /// I fotogrammi al secondo massimi dell'obiettivo attuale a questa risoluzione (in orizzontale), 0 se non c'è.
    func fpsMassimo(larghezza: Int32, altezza: Int32) -> Int {
        guard let dispositivo = ingresso?.device else { return 0 }
        return Self.fpsMassimo(di: dispositivo, larghezza: larghezza, altezza: altezza)
    }

    /// Per `capacita.formati`: 720p, 1080p e 4K dell'obiettivo attuale, con i fotogrammi al secondo massimi (fino a 60).
    var formatiSupportati: [FormatoSupportato] {
        guard let dispositivo = ingresso?.device else { return [] }
        let risoluzioni: [(Int32, Int32)] = [(1280, 720), (1920, 1080), (3840, 2160)]
        return risoluzioni.compactMap { larghezza, altezza in
            let fps = Self.fpsMassimo(di: dispositivo, larghezza: larghezza, altezza: altezza)
            return fps > 0 ? FormatoSupportato(larghezza: Int(larghezza), altezza: Int(altezza), fpsMassimo: fps) : nil
        }
    }

    private static func fpsMassimo(di dispositivo: AVCaptureDevice, larghezza: Int32, altezza: Int32) -> Int {
        var massimo: Double = 0
        for formato in dispositivo.formats {
            let dimensioni = CMVideoFormatDescriptionGetDimensions(formato.formatDescription)
            guard dimensioni.width == larghezza, dimensioni.height == altezza else { continue }
            for intervallo in formato.videoSupportedFrameRateRanges { massimo = max(massimo, intervallo.maxFrameRate) }
        }
        return min(Int(massimo.rounded(.down)), 60)
    }

    // MARK: Luce sul volto (P08)

    /// Esposizione automatica con priorità al volto. `punto`: centro del volto nel fotogramma inviato,
    /// normalizzato con l'origine in alto a sinistra; `nil` spegne la funzione (punto al centro, scelta del sistema).
    /// Con ISO o tempo manuali, AE/AF bloccati o dopo un tocco (esposizione non più continua) non cambia nulla:
    /// le scelte dell'utente vincono.
    func esponiSulVolto(_ punto: CGPoint?) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            let libera = !self.esposizioneBloccata && !self.aeafBloccati
                && dispositivo.exposureMode == .continuousAutoExposure
            if punto != nil && !libera { return }
            let puntoDispositivo = punto.map { self.puntoDelSensore(dalFotogramma: $0) } ?? CGPoint(x: 0.5, y: 0.5)
            do {
                try dispositivo.lockForConfiguration()
                // Esposizione guidata dai volti di iOS: prima si toglie la scelta automatica, poi la si accende
                // (nell'altro ordine iOS solleva un'eccezione). Spenta: torna a decidere il sistema.
                if punto != nil {
                    dispositivo.automaticallyAdjustsFaceDrivenAutoExposureEnabled = false
                    dispositivo.isFaceDrivenAutoExposureEnabled = true
                } else {
                    dispositivo.automaticallyAdjustsFaceDrivenAutoExposureEnabled = true
                }
                if libera, dispositivo.isExposurePointOfInterestSupported {
                    dispositivo.exposurePointOfInterest = puntoDispositivo
                    // Il punto nuovo vale solo dopo aver impostato di nuovo il modo.
                    dispositivo.exposureMode = .continuousAutoExposure
                }
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Solo su `coda`. Dal fotogramma inviato (già girato, forse specchiato) alle coordinate del sensore usate da
    /// `exposurePointOfInterest`: le conversioni dell'uscita tengono conto di rotazione e specchio.
    private func puntoDelSensore(dalFotogramma punto: CGPoint) -> CGPoint {
        let intero = uscita.outputRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1)).standardized
        guard intero.width > 0, intero.height > 0 else { return punto }
        let lato = min(intero.width, intero.height) * 0.02
        let attorno = CGRect(x: intero.minX + punto.x * intero.width - lato / 2,
                             y: intero.minY + punto.y * intero.height - lato / 2, width: lato, height: lato)
        let convertito = uscita.metadataOutputRectConverted(fromOutputRect: attorno).standardized
        return CGPoint(x: min(max(convertito.midX, 0), 1), y: min(max(convertito.midY, 0), 1))
    }

    private func applica(dispositivo: AVCaptureDevice, larghezza: Int32, altezza: Int32, fps: Int) throws {
        sessione.beginConfiguration()
        defer { sessione.commitConfiguration() }

        if let ingresso {
            sessione.removeInput(ingresso)
            // Se il nuovo ingresso non si aggiunge, non resta un riferimento a uno già tolto dalla sessione.
            self.ingresso = nil
        }
        let nuovo = try AVCaptureDeviceInput(device: dispositivo)
        guard sessione.canAddInput(nuovo) else { throw ErroreCattura.configurazione }
        sessione.addInput(nuovo)
        ingresso = nuovo
        // Un obiettivo nuovo parte con fuoco ed esposizione automatici.
        aeafBloccati = false
        generazioneFuoco += 1
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
        // Anche lo stesso obiettivo riconfigurato (caldo, batteria) riparte senza blocco AE/AF.
        if dispositivo.isFocusModeSupported(.continuousAutoFocus) { dispositivo.focusMode = .continuousAutoFocus }
        if !esposizioneBloccata, dispositivo.isExposureModeSupported(.continuousAutoExposure) {
            dispositivo.exposureMode = .continuousAutoExposure
        }
        // Luce bassa automatica (round 2), dove l'iPhone la supporta.
        if dispositivo.isLowLightBoostSupported {
            dispositivo.automaticallyEnablesLowLightBoostWhenAvailable = true
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
        // Prima i formati 420v che permettono gli effetti video di sistema (Ritratto, Luce da studio).
        let video420 = adatti.filter { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange }
        return video420.first { $0.isPortraitEffectSupported } ?? video420.first ?? adatti.first
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
