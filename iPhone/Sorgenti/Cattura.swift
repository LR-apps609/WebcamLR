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
        case .tele: String(localized: "Tele")
        case .frontale: String(localized: "Frontale")
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
        case .permessoNegato: String(localized: "WebcamLR non può usare la fotocamera: attivala in Impostazioni › WebcamLR.")
        case .obiettivoMancante: String(localized: "Questo obiettivo non c'è su questo iPhone: scegline un altro.")
        case .configurazione: String(localized: "La fotocamera non accetta questa risoluzione: scegline un'altra in Impostazioni e tocca «Riprova».")
        }
    }
}

/// P16: i valori della fotocamera per i «Controlli Pro», con i limiti dell'obiettivo attuale.
struct LetturaFotocamera: Equatable {
    var iso: Double
    var isoMinimo: Double
    var isoMassimo: Double
    /// Tempo di posa attuale, in secondi.
    var durata: Double
    var durataMinima: Double
    /// Già limitata alla durata di un fotogramma.
    var durataMassima: Double
    var esposizioneManuale: Bool
    var compensazioneMinima: Double
    var compensazioneMassima: Double
    /// Kelvin stimati dal bilanciamento attuale (anche automatico).
    var temperatura: Int
    var biancoManuale: Bool
    var posizioneLente: Double
    var fuocoManuale: Bool
}

/// Cosa è cambiato nella geometria dei fotogrammi: volti e maschere trovati prima non valgono più (1.14).
enum CambioGeometria: Sendable, Equatable {
    /// Obiettivo, formato o fotogrammi al secondo nuovi (anche lo stesso obiettivo riconfigurato).
    case configurazione
    /// Il telefono è stato girato: il fotogramma ha un altro orientamento.
    case rotazione
    /// Lo specchio dell'immagine inviata è cambiato dal vivo: il valore nuovo.
    case specchio(Bool)
}

/// Cattura il video dalla fotocamera e consegna i fotogrammi al codificatore.
/// Tutto il lavoro avviene sulla coda `coda`; `anteprima` si mostra nell'interfaccia.
final class Cattura: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate,
                     @unchecked Sendable {
    let sessione = AVCaptureSession()
    /// L'immagine grezza della fotocamera, senza effetti: il ritardo più basso. Specchiata come il video inviato
    /// (1.14): l'anteprima mostra sempre ciò che riceve il computer, con o senza effetti.
    let anteprima: AVCaptureVideoPreviewLayer
    /// Chiamata sulla coda di cattura per ogni fotogramma (buffer 420v, già girato e specchiato dalla connessione).
    /// Chi la riceve passa il buffer a `PipelineEffetti.elabora` e poi al codificatore.
    var suFotogramma: ((CMSampleBuffer) -> Void)?
    /// P20: chiamata sulla coda dell'audio per ogni buffer del microfono (PCM), solo col microfono acceso.
    var suAudio: ((CMSampleBuffer) -> Void)?
    /// 1.14: chiamata sulla coda di cattura quando la geometria dei fotogrammi cambia (configurazione, rotazione,
    /// specchio), prima del primo fotogramma con la geometria nuova: chi tiene volti, maschere o uno zoom li adegua.
    var suCambioGeometria: ((CambioGeometria) -> Void)?
    /// 1.14: chiamata sulla coda di cattura quando cambiano le dimensioni dei fotogrammi (già girati).
    var suNuoveDimensioni: ((CGSize) -> Void)?

    /// Le dimensioni dell'ultimo fotogramma consegnato, già girato (quelle del video inviato). Da qualsiasi thread.
    var dimensioni: CGSize { dimensioniUltime.valore }
    private let dimensioniUltime = Protetto(CGSize.zero)
    /// Specchio voluto per l'immagine inviata (e per l'anteprima). Da qualsiasi thread; si applica su `coda`.
    private let specchioVoluto = Protetto(false)
    /// Terza prova (punto E): lo specchio vale solo per la frontale. Con un obiettivo posteriore il video non è mai
    /// specchiato, anche con la preferenza accesa; tornando alla frontale la preferenza vale di nuovo.
    private var specchioEffettivo: Bool {
        specchioVoluto.valore && ingresso?.device.position == .front
    }

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.cattura", qos: .userInteractive)
    private let uscita = AVCaptureVideoDataOutput()
    /// P20: il microfono nella stessa sessione del video, così gli istanti sono sullo stesso orologio.
    private let codaAudio = DispatchQueue(label: "it.lrapps.webcamlr.audio", qos: .userInitiated)
    private let uscitaAudio = AVCaptureAudioDataOutput()
    /// Solo su `coda`.
    private var ingressoAudio: AVCaptureDeviceInput?
    /// L'ingresso video. Si scrive solo su `coda` (`applica`), ma si legge anche dal thread principale (`lettura`,
    /// `limitiISO`, `formatiSupportati`, Controlli Pro): per questo è protetto da un blocco.
    private var ingresso: AVCaptureDeviceInput? {
        get { bloccoIngresso.withLock { ingressoInterno } }
        set { bloccoIngresso.withLock { ingressoInterno = newValue } }
    }
    private let bloccoIngresso = NSLock()
    private var ingressoInterno: AVCaptureDeviceInput?
    /// Solo sul thread principale: il coordinatore della rotazione e il dispositivo per cui è stato creato.
    private var coordinatore: AVCaptureDevice.RotationCoordinator?
    private weak var dispositivoRotazione: AVCaptureDevice?
    private var osservazioni: [NSKeyValueObservation] = []
    /// L'ultimo angolo applicato all'uscita video. Solo su `coda`.
    private var angoloCattura: CGFloat?
    private var osservatoreScena: NSObjectProtocol?
    private var osservatoreErrori: NSObjectProtocol?
    /// Fine di un'interruzione (app di nuovo in primo piano, chiamata finita…): la sessione deve ripartire.
    private var osservatoreFineInterruzione: NSObjectProtocol?
    /// L'ultimo riavvio dopo un errore, per non riavviare in un giro senza fine. Solo su `coda`.
    private var ultimoRiavvio: TimeInterval = 0
    /// La cattura deve andare (configurata e non fermata). Solo su `coda`.
    private var attiva = false
    /// ISO o tempo manuali dal computer: il tocco e il fuoco continuo non toccano l'esposizione. Solo su `coda`.
    private var esposizioneBloccata = false
    /// Fuoco ed esposizione bloccati con il tocco lungo (round 2): la scena che cambia non li sblocca. Solo su `coda`.
    private var aeafBloccati = false
    /// Cresce a ogni tocco: un blocco rimasto in attesa non scatta dopo un tocco più recente. Solo su `coda`.
    private var generazioneFuoco = 0
    /// P16: messa a fuoco manuale dai «Controlli Pro»: la scena che cambia non la riporta all'automatica. Solo su `coda`.
    private var fuocoManualeAttivo = false

    override init() {
        anteprima = AVCaptureVideoPreviewLayer(session: sessione)
        // Seconda prova (bug E): l'anteprima riempie lo schermo come nella Fotocamera, tagliando i bordi solo a
        // video. Il video inviato al computer resta intero (lo dice anche un suggerimento in «In onda»).
        anteprima.videoGravity = .resizeAspectFill
        anteprima.backgroundColor = CGColor(gray: 0, alpha: 1)
        super.init()
        uscita.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        uscita.alwaysDiscardsLateVideoFrames = true
        uscita.setSampleBufferDelegate(self, queue: coda)
        uscitaAudio.setSampleBufferDelegate(self, queue: codaAudio)
        // L'audio dell'app lo configura `microfono(_:)`: la sessione non deve toccarlo da sola.
        sessione.automaticallyConfiguresApplicationAudioSession = false
        // Dopo un tocco per il fuoco: se la scena cambia molto, si torna al fuoco continuo.
        osservatoreScena = NotificationCenter.default.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification,
                                                                  object: nil, queue: nil) { [weak self] _ in
            self?.fuocoContinuo(ancheSeBloccati: false)
        }
        // Un errore ferma la cattura (servizi multimediali di iOS ripartiti da capo, fotocamera persa mentre l'app
        // era in sottofondo…): si riavvia, se doveva andare. Prima solo `mediaServicesWereReset`: dopo un altro
        // errore la sessione restava ferma per sempre e «In onda» mostrava l'ultimo fotogramma (bug 3).
        osservatoreErrori = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                                   object: sessione, queue: nil) { [weak self] notifica in
            guard let self else { return }
            let codice = (notifica.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            // Dopo un reset dei servizi subito; dopo gli altri errori un attimo di respiro.
            self.coda.asyncAfter(deadline: .now() + (codice == .mediaServicesWereReset ? 0 : 0.5)) {
                self.riavviaSeFerma()
            }
        }
        // Di solito AVFoundation riparte da sola a fine interruzione; se non succede, ci si pensa qui.
        osservatoreFineInterruzione = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: sessione, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.coda.asyncAfter(deadline: .now() + 0.3) { self.riavviaSeFerma() }
        }
    }

    deinit {
        if let osservatoreScena { NotificationCenter.default.removeObserver(osservatoreScena) }
        if let osservatoreErrori { NotificationCenter.default.removeObserver(osservatoreErrori) }
        if let osservatoreFineInterruzione { NotificationCenter.default.removeObserver(osservatoreFineInterruzione) }
    }

    /// Bug 3: l'app torna in primo piano. Se la cattura doveva andare ma è ferma (un errore mentre era in
    /// sottofondo, un'interruzione finita senza ripartenza) si riavvia. Se va già non cambia nulla.
    func riprendiSeServe() {
        coda.async { self.riavviaSeFerma(subito: true) }
    }

    /// Solo su `coda`. Al massimo un riavvio al secondo dopo un errore: se l'errore si ripete non si gira a vuoto.
    private func riavviaSeFerma(subito: Bool = false) {
        guard attiva, !sessione.isRunning, !sessione.isInterrupted else { return }
        let adesso = ProcessInfo.processInfo.systemUptime
        guard subito || adesso - ultimoRiavvio >= 1 else { return }
        ultimoRiavvio = adesso
        RegistroCollegamento.scrivi(String(localized: "Fotocamera ferma: la riavvio"))
        sessione.startRunning()
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
    /// Lo specchio è quello di `impostaSpecchio` (si può cambiare anche mentre la cattura va).
    func configura(obiettivo: Obiettivo, larghezza: Int32, altezza: Int32, fps: Int,
                   stabilizzazione: Bool = false) async throws {
        guard await Self.chiediPermesso() else { throw ErroreCattura.permessoNegato }
        guard let dispositivo = obiettivo.dispositivo else { throw ErroreCattura.obiettivoMancante }
        // 1.14: gli angoli della rotazione si leggono prima, così la connessione nuova esce già dritta dal primo
        // fotogramma (prima i primi fotogrammi uscivano in orizzontale: due sessioni di codifica, due `formato`).
        let angoli = await MainActor.run { self.preparaRotazione(per: dispositivo) }
        try await withCheckedThrowingContinuation { (continuazione: CheckedContinuation<Void, Error>) in
            coda.async {
                do {
                    try self.applica(dispositivo: dispositivo, larghezza: larghezza, altezza: altezza, fps: fps,
                                     angoli: angoli, stabilizzazione: stabilizzazione)
                    self.attiva = true
                    // Prima del primo fotogramma con la geometria nuova: volti e maschere vecchi non valgono più.
                    self.suCambioGeometria?(.configurazione)
                    if !self.sessione.isRunning { self.sessione.startRunning() }
                    continuazione.resume()
                } catch {
                    continuazione.resume(throwing: error)
                }
            }
        }
        // La connessione dell'anteprima è nuova: rotazione e specchio di nuovo (sul thread principale, come sempre).
        await MainActor.run { self.aggiornaAnteprima() }
    }

    /// Specchia l'immagine inviata al computer (funzione 25), dal vivo: si cambia lo specchio della connessione
    /// senza riconfigurare la sessione (niente riavvio, niente nuovo `formato`, AE/AF restano come sono).
    /// L'anteprima del telefono segue lo stesso specchio: mostra sempre ciò che riceve il computer.
    /// Chi tiene volti, maschere o uno zoom lo sa da `suCambioGeometria(.specchio)`, nello stesso istante.
    func impostaSpecchio(_ attivo: Bool) {
        specchioVoluto.valore = attivo
        coda.async {
            guard self.applicaSpecchio() else { return }
            self.suCambioGeometria?(.specchio(self.specchioEffettivo))
        }
    }

    /// Solo su `coda`. Lo specchio effettivo (voluto, e solo con la frontale) sull'uscita video e sull'anteprima.
    /// `true` se l'uscita è cambiata.
    @discardableResult
    private func applicaSpecchio() -> Bool {
        let attivo = specchioEffettivo
        specchiaAnteprima(attivo)
        guard let connessione = uscita.connection(with: .video), connessione.isVideoMirroringSupported else { return false }
        let prima = connessione.isVideoMirrored
        connessione.automaticallyAdjustsVideoMirroring = false
        connessione.isVideoMirrored = attivo
        return prima != attivo
    }

    /// L'anteprima grezza specchiata esattamente come il video inviato (niente specchio automatico della frontale).
    /// Seconda prova (bug C): con la fotocamera posteriore lo specchio della connessione dell'anteprima, girata dal
    /// coordinatore della rotazione, capovolgeva l'immagine sul telefono (il computer, che riceve l'uscita video,
    /// la vedeva giusta). Con la posteriore la connessione dell'anteprima resta senza specchio e si specchia il
    /// livello, in orizzontale sullo schermo; la frontale resta com'era (specchio della connessione).
    private func specchiaAnteprima(_ attivo: Bool) {
        // Senza connessione (fotocamera non ancora configurata) non si tocca nulla: ci pensa `aggiornaAnteprima`.
        guard let connessione = anteprima.connection else { return }
        let frontale = ingresso?.device.position == .front
        let sullaConnessione = attivo && frontale && connessione.isVideoMirroringSupported
        let specchioDelLivello = attivo && !sullaConnessione
        if connessione.isVideoMirroringSupported {
            connessione.automaticallyAdjustsVideoMirroring = false
            if connessione.isVideoMirrored != sullaConnessione { connessione.isVideoMirrored = sullaConnessione }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let trasformazione = specchioDelLivello ? CGAffineTransform(scaleX: -1, y: 1) : .identity
            guard self.anteprima.affineTransform() != trasformazione else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.anteprima.setAffineTransform(trasformazione)
            CATransaction.commit()
        }
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

    /// 1.14: il rettangolo del video dentro `contenitore`, con le sue proporzioni: come `.resizeAspect` (o
    /// `.resizeAspectFill` con `riempi`). Senza dimensioni, tutto il contenitore.
    static func rettangoloVideo(dimensioni: CGSize, in contenitore: CGRect, riempi: Bool = false) -> CGRect {
        guard dimensioni.width > 0, dimensioni.height > 0, contenitore.width > 0, contenitore.height > 0 else {
            return contenitore
        }
        let scalaX = contenitore.width / dimensioni.width
        let scalaY = contenitore.height / dimensioni.height
        let scala = riempi ? max(scalaX, scalaY) : min(scalaX, scalaY)
        let misura = CGSize(width: dimensioni.width * scala, height: dimensioni.height * scala)
        return CGRect(x: contenitore.midX - misura.width / 2, y: contenitore.midY - misura.height / 2,
                      width: misura.width, height: misura.height)
    }

    /// 1.14, tocco per il fuoco: da un punto dei livelli di anteprima (stessa cornice per quello grezzo e quello con
    /// gli effetti) al punto del video inviato, normalizzato con l'origine in alto a sinistra. Si passa per il
    /// rettangolo del video, non per il livello grezzo: l'anteprima mostra sempre il video inviato (stesso specchio).
    /// Un tocco sulle bande nere va al bordo più vicino. Sul thread principale.
    func puntoNelVideo(dalPuntoDellAnteprima punto: CGPoint) -> CGPoint {
        let video = Self.rettangoloVideo(dimensioni: dimensioni, in: anteprima.bounds,
                                         riempi: anteprima.videoGravity == .resizeAspectFill)
        guard video.width > 0, video.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: min(max((punto.x - video.minX) / video.width, 0), 1),
                       y: min(max((punto.y - video.minY) / video.height, 0), 1))
    }

    /// Tocco per mettere a fuoco ed esporre (funzione 21). `punto`: nel fotogramma della cattura (già girato e
    /// specchiato, prima degli effetti), normalizzato con l'origine in alto a sinistra (vedi `puntoNelVideo`).
    func metteAFuoco(suPuntoDelFotogramma punto: CGPoint) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            let puntoDispositivo = self.puntoDelSensore(dalFotogramma: punto)
            // Un tocco sblocca anche fuoco ed esposizione bloccati, e lascia la messa a fuoco manuale.
            self.aeafBloccati = false
            self.fuocoManualeAttivo = false
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
    /// L'esposizione manuale dal computer resta com'è. `punto` come in `metteAFuoco(suPuntoDelFotogramma:)`.
    func bloccaFuocoEdEsposizione(suPuntoDelFotogramma punto: CGPoint) {
        coda.async {
            guard let dispositivo = self.ingresso?.device else { return }
            let puntoDispositivo = self.puntoDelSensore(dalFotogramma: punto)
            self.aeafBloccati = true
            self.fuocoManualeAttivo = false
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
            if (self.aeafBloccati || self.fuocoManualeAttivo) && !ancheSeBloccati { return }
            self.aeafBloccati = false
            self.fuocoManualeAttivo = false
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
                // `clamping`: un `tempo` enorme dal computer non manda in crash la conversione a Int32 (poi si limita).
                var durata = tempo > 0 ? CMTime(value: 1, timescale: CMTimeScale(clamping: tempo))
                    : AVCaptureDevice.currentExposureDuration
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

    // MARK: Controlli Pro (P16)

    /// Messa a fuoco manuale: posizione della lente da 0 (vicino) a 1 (lontano), bloccata lì.
    /// Per tornare all'automatica: `fuocoContinuo()`.
    func fuocoManuale(_ posizione: Float) {
        coda.async {
            guard let dispositivo = self.ingresso?.device,
                  dispositivo.isLockingFocusWithCustomLensPositionSupported else { return }
            self.fuocoManualeAttivo = true
            self.generazioneFuoco += 1
            do {
                try dispositivo.lockForConfiguration()
                dispositivo.isSubjectAreaChangeMonitoringEnabled = false
                dispositivo.setFocusModeLocked(lensPosition: min(max(posizione, 0), 1), completionHandler: nil)
                dispositivo.unlockForConfiguration()
            } catch {}
        }
    }

    /// Cosa si può regolare a mano con l'obiettivo attuale, e i valori di adesso (anche quelli automatici).
    /// Letta dal thread principale, come `limitiISO`: sono proprietà osservabili del dispositivo.
    var lettura: LetturaFotocamera? {
        guard let dispositivo = ingresso?.device else { return nil }
        let formato = dispositivo.activeFormat
        var durataMassima = formato.maxExposureDuration.seconds
        // Mai oltre la durata di un fotogramma (come `esposizioneManuale`).
        let fotogramma = dispositivo.activeVideoMinFrameDuration
        if fotogramma.isValid, fotogramma.seconds > 0 { durataMassima = min(durataMassima, fotogramma.seconds) }
        let guadagni = dispositivo.deviceWhiteBalanceGains
        let temperatura = dispositivo.temperatureAndTintValues(for: guadagni).temperature
        return LetturaFotocamera(
            iso: Double(dispositivo.iso),
            isoMinimo: Double(formato.minISO),
            isoMassimo: Double(formato.maxISO),
            durata: dispositivo.exposureDuration.seconds,
            durataMinima: formato.minExposureDuration.seconds,
            durataMassima: durataMassima,
            esposizioneManuale: dispositivo.isExposureModeSupported(.custom),
            compensazioneMinima: Double(max(dispositivo.minExposureTargetBias, -2)),
            compensazioneMassima: Double(min(dispositivo.maxExposureTargetBias, 2)),
            temperatura: temperatura.isFinite ? Int(temperatura) : 0,
            biancoManuale: dispositivo.isLockingWhiteBalanceWithCustomDeviceGainsSupported,
            posizioneLente: Double(dispositivo.lensPosition),
            fuocoManuale: dispositivo.isLockingFocusWithCustomLensPositionSupported
        )
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

    /// Per `capacita.formati`: 720p, 1080p e 4K dell'obiettivo attuale, con i fotogrammi al secondo massimi (fino a 60;
    /// il 4K al massimo a 30, vedi `fpsMassimo4K`).
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
        return min(Int(massimo.rounded(.down)), larghezza >= 3840 ? fpsMassimo4K : 60)
    }

    /// 1.14: il 4K solo fino a 30 fps. A 60 fps sono 8 milioni di pixel da girare, elaborare e codificare 60 volte
    /// al secondo: il telefono si scalda in pochi minuti e il Wi-Fi non regge il bitrate.
    static let fpsMassimo4K = 30

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

    /// Solo su `coda`. Tutto dentro una sola configurazione: ingresso, formato, rotazione, specchio e stabilizzazione
    /// della connessione nuova valgono già per il primo fotogramma.
    private func applica(dispositivo: AVCaptureDevice, larghezza: Int32, altezza: Int32, fps: Int,
                         angoli: (cattura: CGFloat, anteprima: CGFloat), stabilizzazione: Bool) throws {
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
        fuocoManualeAttivo = false
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

        // Togliere e rimettere l'ingresso crea connessioni nuove, con l'angolo di serie (orizzontale): si girano
        // qui, prima di `commitConfiguration`, con gli angoli letti dal coordinatore. Così il primo fotogramma
        // esce già dritto.
        if let connessione = uscita.connection(with: .video), connessione.isVideoRotationAngleSupported(angoli.cattura) {
            connessione.videoRotationAngle = angoli.cattura
        }
        angoloCattura = angoli.cattura
        if let connessione = anteprima.connection, connessione.isVideoRotationAngleSupported(angoli.anteprima) {
            connessione.videoRotationAngle = angoli.anteprima
        }
        applicaSpecchio()
        stabilizza(stabilizzazione)
    }

    /// Il formato con le dimensioni e i fotogrammi richiesti, in 420v, con il campo visivo più largo: niente
    /// formati ritagliati. (1.14: non si preferiscono più i formati degli «Effetti video» di sistema, il pulsante
    /// non c'è più.)
    private static func formato(di dispositivo: AVCaptureDevice, larghezza: Int32, altezza: Int32, fps: Int) -> AVCaptureDevice.Format? {
        let adatti = dispositivo.formats.filter { formato in
            let dimensioni = CMVideoFormatDescriptionGetDimensions(formato.formatDescription)
            return dimensioni.width == larghezza && dimensioni.height == altezza
                && formato.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps) }
        }
        let video420 = adatti.filter { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange }
        // `max(by:)` tiene il primo a parità di campo visivo: l'ordine di iOS.
        return video420.max { $0.videoFieldOfView < $1.videoFieldOfView } ?? adatti.first
    }

    /// Solo sul thread principale. Tiene il video dritto rispetto all'orizzonte, comunque sia girato il telefono.
    /// Il coordinatore si crea solo quando cambia il dispositivo (lavora con il livello di anteprima). Ritorna gli
    /// angoli di adesso, da applicare dentro la configurazione.
    private func preparaRotazione(per dispositivo: AVCaptureDevice) -> (cattura: CGFloat, anteprima: CGFloat) {
        if let coordinatore, dispositivoRotazione === dispositivo {
            return (coordinatore.videoRotationAngleForHorizonLevelCapture, coordinatore.videoRotationAngleForHorizonLevelPreview)
        }
        osservazioni.removeAll()
        let coordinatore = AVCaptureDevice.RotationCoordinator(device: dispositivo, previewLayer: anteprima)
        self.coordinatore = coordinatore
        dispositivoRotazione = dispositivo
        // Senza `.initial`: gli angoli di adesso li applica `applica`; qui solo i cambi (telefono girato).
        osservazioni.append(coordinatore.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coordinatore, _ in
            guard let self else { return }
            let angolo = coordinatore.videoRotationAngleForHorizonLevelCapture
            self.coda.async {
                guard self.angoloCattura != angolo,
                      let connessione = self.uscita.connection(with: .video),
                      connessione.isVideoRotationAngleSupported(angolo) else { return }
                connessione.videoRotationAngle = angolo
                self.angoloCattura = angolo
                self.suCambioGeometria?(.rotazione)
            }
        })
        osservazioni.append(coordinatore.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinatore, _ in
            let angolo = coordinatore.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                if let connessione = self?.anteprima.connection, connessione.isVideoRotationAngleSupported(angolo) {
                    connessione.videoRotationAngle = angolo
                }
            }
        })
        return (coordinatore.videoRotationAngleForHorizonLevelCapture, coordinatore.videoRotationAngleForHorizonLevelPreview)
    }

    /// Solo sul thread principale, dopo una configurazione: la connessione dell'anteprima può essere nuova.
    private func aggiornaAnteprima() {
        if let coordinatore, let connessione = anteprima.connection {
            let angolo = coordinatore.videoRotationAngleForHorizonLevelPreview
            if connessione.isVideoRotationAngleSupported(angolo) { connessione.videoRotationAngle = angolo }
        }
        specchiaAnteprima(specchioEffettivo)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === uscitaAudio {
            suAudio?(sampleBuffer)
        } else {
            if let immagine = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let misura = CGSize(width: CVPixelBufferGetWidth(immagine), height: CVPixelBufferGetHeight(immagine))
                if misura != dimensioniUltime.valore {
                    dimensioniUltime.valore = misura
                    suNuoveDimensioni?(misura)
                    Self.registraAllegati(immagine)
                }
            }
            suFotogramma?(sampleBuffer)
        }
    }

    /// 1.14, per la righina a sinistra: nel registro misura e allegati geometrici del primo fotogramma di ogni
    /// misura nuova. La pipeline copia solo gli allegati di colore; se qui c'è un'apertura pulita o un rapporto dei
    /// pixel, è la prova che contavano.
    private static func registraAllegati(_ immagine: CVPixelBuffer) {
        let apertura = CVBufferCopyAttachment(immagine, kCVImageBufferCleanApertureKey, nil) != nil
        let rapporto = CVBufferCopyAttachment(immagine, kCVImageBufferPixelAspectRatioKey, nil) != nil
        let misura = String(localized: "Fotogrammi \(Int(CVPixelBufferGetWidth(immagine)))×\(Int(CVPixelBufferGetHeight(immagine)))")
        let testo = misura + (apertura ? String(localized: ", con apertura pulita") : "")
            + (rapporto ? String(localized: ", con rapporto dei pixel") : "")
        RegistroCollegamento.scrivi(testo)
    }

    // MARK: Microfono (P20)

    /// Aggiunge o toglie il microfono dalla sessione della fotocamera. `fatto` dice se ora è acceso.
    ///
    /// Sessione audio di iOS: `.playAndRecord` con modo `.videoRecording` (la taratura della videocamera, senza
    /// cancellazione dell'eco né controllo automatico del volume da telefonata), microfono interno preferito,
    /// rivolto dalla parte della fotocamera in uso, e `.mixWithOthers` per non fermare l'audio di altre app.
    /// Niente `.voiceChat`/`.videoChat`: la cancellazione dell'eco serve a chi riproduce l'altra persona, cioè
    /// l'app di chiamata sul computer, che la fa già sul suo ingresso; il telefono non riproduce nulla.
    /// Niente `.measurement`: toglie ogni elaborazione e il volume della voce resta troppo basso.
    /// Aggiungere o togliere un ingresso riconfigura la sessione: il video può saltare qualche fotogramma solo
    /// in quel momento; a microfono spento la cattura video è quella di sempre.
    func microfono(_ acceso: Bool, fatto: @escaping @Sendable (Bool) -> Void) {
        coda.async {
            if acceso {
                guard self.ingressoAudio == nil else {
                    fatto(true)
                    return
                }
                let posizione = self.ingresso?.device.position ?? .back
                guard Self.preparaSessioneAudio(verso: posizione == .front ? .front : .back),
                      let microfono = AVCaptureDevice.default(for: .audio),
                      let nuovo = try? AVCaptureDeviceInput(device: microfono) else {
                    fatto(false)
                    return
                }
                self.sessione.beginConfiguration()
                guard self.sessione.canAddInput(nuovo) else {
                    self.sessione.commitConfiguration()
                    fatto(false)
                    return
                }
                self.sessione.addInput(nuovo)
                if !self.sessione.outputs.contains(self.uscitaAudio) {
                    guard self.sessione.canAddOutput(self.uscitaAudio) else {
                        self.sessione.removeInput(nuovo)
                        self.sessione.commitConfiguration()
                        fatto(false)
                        return
                    }
                    self.sessione.addOutput(self.uscitaAudio)
                }
                self.sessione.commitConfiguration()
                self.ingressoAudio = nuovo
                fatto(true)
            } else {
                guard let attuale = self.ingressoAudio else {
                    fatto(false)
                    return
                }
                self.sessione.beginConfiguration()
                self.sessione.removeInput(attuale)
                self.sessione.removeOutput(self.uscitaAudio)
                self.sessione.commitConfiguration()
                self.ingressoAudio = nil
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                fatto(false)
            }
        }
    }

    private static func preparaSessioneAudio(verso: AVAudioSession.Orientation) -> Bool {
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.mixWithOthers])
            try? audio.setPreferredSampleRate(48_000)
            try audio.setActive(true)
        } catch {
            return false
        }
        if let interno = audio.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? audio.setPreferredInput(interno)
            if let fonte = interno.dataSources?.first(where: { $0.orientation == verso }) {
                try? interno.setPreferredDataSource(fonte)
            }
        }
        return true
    }
}
