import AVFoundation
import Foundation
import Observation

/// Qualità 10: «Ritratto» di macOS (Centro di Controllo › Effetti video) insieme alla sfocatura di WebcamLR sfoca lo
/// sfondo due volte. Quando la webcam virtuale è in uso e la sfocatura di WebcamLR è accesa, sotto il video compare un
/// avviso discreto (`Avviso`, tono informazione) che lo dice e spiega come spegnerne uno; una volta per avvio, con
/// «Non mostrare più».
///
/// Che cosa si può sapere con le API pubbliche (macOS 12+, tutte osservabili con KVO):
/// - `AVCaptureDevice.isPortraitEffectEnabled` (della classe) è la scelta dell'utente **per l'app che la legge**: qui dice
///   se Ritratto è acceso per WebcamLR, non per Zoom o Meet. Siccome WebcamLR non usa una fotocamera, nel Centro di
///   Controllo non compare e il valore resta quasi sempre falso.
/// - `isPortraitEffectActive` (del dispositivo) è vero quando quella scelta è accesa e il formato attivo lo supporta:
///   anche questo è dell'app che lo legge.
/// - `AVCaptureDeviceFormat.isPortraitEffectSupported` invece è del formato, uguale per tutti: se nessun formato della
///   webcam virtuale WebcamLR lo supporta, Ritratto non si può accendere su WebcamLR in nessuna app.
/// Quindi: «acceso» quando uno dei primi due è vero (certo); «forse» quando la webcam virtuale supporta Ritratto, o non
/// si vede da qui (sandbox senza il diritto della fotocamera) su un Mac con Apple silicon, dove Ritratto c'è; «spento»
/// quando i formati dicono di no o il Mac è Intel. Con «forse» l'avviso parla al condizionale.
@MainActor @Observable
final class RitrattoSistema {
    static let condiviso = RitrattoSistema()

    enum Stato: Equatable {
        /// Ritratto non si può accendere sulla webcam WebcamLR.
        case spento
        /// Si può accendere nell'app di videochiamata, ma da qui non si vede se lo è.
        case forse
        /// Acceso (visto da questo processo).
        case acceso
    }

    /// `AVCaptureDevice.isPortraitEffectEnabled`: Ritratto acceso per WebcamLR.
    private(set) var accesoPerWebcamLR = false
    /// `isPortraitEffectActive` della webcam virtuale WebcamLR, vista da questo processo.
    private(set) var attivoSullaWebcam = false
    /// Almeno un formato della webcam virtuale ha `isPortraitEffectSupported`; nil se la webcam non si vede da qui.
    private(set) var supportatoDallaWebcam: Bool?

    /// L'avviso da mostrare adesso.
    private(set) var avvisoVisibile = false

    var stato: Stato {
        if accesoPerWebcamLR || attivoSullaWebcam { return .acceso }
        if let supportato = supportatoDallaWebcam { return supportato ? .forse : .spento }
        return Self.appleSilicon ? .forse : .spento
    }

    /// «Non mostrare più», per sempre su questo Mac.
    private var nonMostrarePiu = UserDefaults.standard.bool(forKey: Preferenze.nonMostrareRitratto)
    /// Già mostrato e poi sparito (chiuso, o la causa non c'è più) in questo avvio: non torna fino al prossimo.
    private var finitoInQuestoAvvio = false
    /// L'ultima condizione arrivata dalla finestra: webcam in uso e sfocatura di WebcamLR accesa.
    private var condizione = false
    @ObservationIgnored private var chiusuraRitardata: Task<Void, Never>?
    @ObservationIgnored private var osservatoreClasse: OsservatoreClasse?
    @ObservationIgnored private var osservazioneDispositivo: NSKeyValueObservation?
    @ObservationIgnored private var dispositivo: AVCaptureDevice?

    private init() {
        osservatoreClasse = OsservatoreClasse { [weak self] in
            Task { @MainActor in self?.rileggi() }
        }
        rileggi()
    }

    /// La finestra dice se la webcam virtuale è in uso con la sfocatura di WebcamLR accesa.
    func valuta(webcamInUsoConSfocatura: Bool) {
        condizione = webcamInUsoConSfocatura
        if condizione { rileggi() }
        aggiornaAvviso()
    }

    /// La X dell'avviso: sparisce per questo avvio.
    func chiudi() {
        chiusuraRitardata?.cancel()
        avvisoVisibile = false
        finitoInQuestoAvvio = true
    }

    /// «Non mostrare più».
    func nonMostrarePiuAvviso() {
        nonMostrarePiu = true
        UserDefaults.standard.set(true, forKey: Preferenze.nonMostrareRitratto)
        chiudi()
    }

    private func aggiornaAvviso() {
        guard !nonMostrarePiu, !finitoInQuestoAvvio else {
            avvisoVisibile = false
            return
        }
        if condizione && stato != .spento {
            chiusuraRitardata?.cancel()
            chiusuraRitardata = nil
            avvisoVisibile = true
        } else if avvisoVisibile, chiusuraRitardata == nil {
            // La webcam si ferma un attimo quando l'app cambia formato: l'avviso sparisce solo se la causa manca da 3 s,
            // e allora non torna più in questo avvio.
            chiusuraRitardata = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                self.chiusuraRitardata = nil
                guard !(self.condizione && self.stato != .spento) else { return }
                self.chiudi()
            }
        }
    }

    /// Rilegge i valori di AVFoundation e, la prima volta che la webcam virtuale si vede, si mette in ascolto del suo
    /// `isPortraitEffectActive`.
    private func rileggi() {
        accesoPerWebcamLR = AVCaptureDevice.isPortraitEffectEnabled
        if dispositivo == nil, let trovato = AVCaptureDevice(uniqueID: UscitaWebcam.uidDispositivo) {
            dispositivo = trovato
            osservazioneDispositivo = trovato.observe(\.isPortraitEffectActive, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.rileggi() }
            }
        }
        if let dispositivo {
            attivoSullaWebcam = dispositivo.isPortraitEffectActive
            supportatoDallaWebcam = dispositivo.formats.contains { $0.isPortraitEffectSupported }
        } else {
            attivoSullaWebcam = false
            supportatoDallaWebcam = nil
        }
        aggiornaAvviso()
    }

    /// Ritratto sul Mac c'è solo con Apple silicon.
    private static let appleSilicon: Bool = {
        var valore: Int32 = 0
        var dimensione = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &valore, &dimensione, nil, 0) == 0 && valore == 1
    }()
}

/// KVO su una proprietà della classe: `AVCaptureDevice.isPortraitEffectEnabled` si osserva sull'oggetto classe, con il
/// nome della proprietà in Objective-C («portraitEffectEnabled»). La chiamata arriva su un thread qualsiasi.
private final class OsservatoreClasse: NSObject {
    private static let chiave = "portraitEffectEnabled"
    private let cambiato: @Sendable () -> Void

    init(cambiato: @escaping @Sendable () -> Void) {
        self.cambiato = cambiato
        super.init()
        (AVCaptureDevice.self as AnyObject).addObserver(self, forKeyPath: Self.chiave, options: [.new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == Self.chiave { cambiato() }
    }

    deinit {
        (AVCaptureDevice.self as AnyObject).removeObserver(self, forKeyPath: Self.chiave)
    }
}
