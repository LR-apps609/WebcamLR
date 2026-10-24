import AVFoundation
import Network
import Stile
import SwiftUI
import WebcamLRProtocollo

extension ComputerTrovato {
    /// Un computer letto dal QR code o scritto a mano (funzione 2). 1.10: tutti gli indirizzi del QR code si provano
    /// insieme, il primo subito e gli altri a breve distanza; vince il primo che risponde.
    init?(associazione: Associazione) {
        guard let primo = associazione.indirizzi.first, let porta = NWEndpoint.Port(rawValue: associazione.porta) else {
            return nil
        }
        var visti: Set<String> = [primo]
        let altri = associazione.indirizzi.dropFirst().filter { visti.insert($0).inserted }
        self.init(id: "qr-\(primo):\(associazione.porta)", nome: associazione.nome, piattaforma: nil,
                  endpoint: .hostPort(host: NWEndpoint.Host(primo), port: porta),
                  impronta: associazione.impronta, gettone: associazione.gettone,
                  altriIndirizzi: altri.map { NWEndpoint.hostPort(host: NWEndpoint.Host($0), port: porta) })
    }
}

/// 1.10: la fotocamera del lettore QR, una sola per tutta l'app. Si prepara (configurata ma spenta) mentre la lista
/// dei computer è visibile, se il permesso c'è già: aprendo il lettore parte subito, senza schermate in mezzo.
/// Configurata ma spenta non accende l'indicatore verde della fotocamera. Tutto il lavoro sulla sessione avviene
/// sulla coda `coda`; i QR code arrivano sul thread principale.
final class FotocameraQR: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    static let condivisa = FotocameraQR()

    let sessione = AVCaptureSession()
    /// Il testo di un QR code inquadrato, a ogni fotogramma in cui si vede.
    @MainActor var suTesto: ((String) -> Void)?

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.lettoreqr", qos: .userInitiated)
    private let uscita = AVCaptureMetadataOutput()
    /// Solo su `coda`.
    private var configurata = false

    static var disponibile: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Configura la sessione senza accenderla, solo se il permesso c'è già: da qui iOS non chiede nulla.
    func prepara() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        coda.async { self.configura() }
    }

    func avvia() {
        coda.async {
            self.configura()
            if self.configurata && !self.sessione.isRunning { self.sessione.startRunning() }
        }
    }

    /// Spegne la fotocamera del lettore; la configurazione resta, per la prossima volta.
    func ferma() {
        coda.async {
            if self.sessione.isRunning { self.sessione.stopRunning() }
        }
    }

    /// Come `ferma`, ma ritorna quando è spenta: la fotocamera della sessione si accende solo dopo.
    func fermaEAspetta() async {
        await withCheckedContinuation { (continuazione: CheckedContinuation<Void, Never>) in
            coda.async {
                if self.sessione.isRunning { self.sessione.stopRunning() }
                continuazione.resume()
            }
        }
    }

    /// Solo su `coda`.
    private func configura() {
        guard !configurata, AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let dispositivo = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let ingresso = try? AVCaptureDeviceInput(device: dispositivo) else { return }
        sessione.beginConfiguration()
        defer { sessione.commitConfiguration() }
        // 720p basta per un QR code sullo schermo, e la fotocamera parte prima.
        if sessione.canSetSessionPreset(.hd1280x720) { sessione.sessionPreset = .hd1280x720 }
        guard sessione.canAddInput(ingresso) else { return }
        sessione.addInput(ingresso)
        guard sessione.canAddOutput(uscita) else {
            sessione.removeInput(ingresso)
            return
        }
        sessione.addOutput(uscita)
        uscita.setMetadataObjectsDelegate(self, queue: .main)
        if uscita.availableMetadataObjectTypes.contains(.qr) { uscita.metadataObjectTypes = [.qr] }
        configurata = true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        var trovato: String?
        for oggetto in metadataObjects {
            if let codice = oggetto as? AVMetadataMachineReadableCodeObject, let testo = codice.stringValue {
                trovato = testo
                break
            }
        }
        guard let testo = trovato else { return }
        // Il delegato è registrato sulla coda principale.
        MainActor.assumeIsolated {
            guard let suTesto = self.suTesto else { return }
            suTesto(testo)
        }
    }
}

/// Foglio che inquadra il QR code mostrato dal computer. 1.10: con il permesso già concesso la fotocamera parte
/// all'apertura; letto il QR code il collegamento parte subito, con una vibrazione e la spunta, e il foglio si chiude.
struct FoglioLettoreQR: View {
    /// Chiamata appena il QR code è letto, prima che il foglio si chiuda.
    let suLettura: (Associazione) -> Void
    @Environment(\.dismiss) private var chiudi
    @State private var avviso: String?
    @State private var permessoChiesto = AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined
    @State private var permessoFotocamera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    /// Il QR code letto: da qui il riquadro diventa una spunta e le altre letture non contano.
    @State private var letto: Associazione?

    private static let nonDiWebcamLR = "Questo QR code non è di WebcamLR: inquadra quello sul computer."

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if !permessoChiesto {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if permessoFotocamera && FotocameraQR.disponibile {
                    AnteprimaQR()
                        .ignoresSafeArea()
                    mirino
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !permessoFotocamera {
                    VStack(spacing: 14) {
                        Text("Per leggere il QR code serve la fotocamera. Consentila in Impostazioni › WebcamLR, oppure chiudi e scrivi l'indirizzo che il computer mostra sotto il QR code.")
                            .multilineTextAlignment(.center)
                        if let impostazioni = URL(string: UIApplication.openSettingsURLString) {
                            Link("Apri Impostazioni", destination: impostazioni)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Questo iPhone non può leggere i QR code da qui. Chiudi e scrivi l'indirizzo che il computer mostra sotto il QR code.")
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Solo sopra il lettore: senza fotocamera c'è già il testo che dice cosa fare.
                if permessoChiesto && permessoFotocamera {
                    Text(testoInBasso)
                        .font(letto == nil ? Font.subheadline : Font.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(letto == nil ? Tema.testo : Tema.cianoChiaro)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Tema.fondo.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .background(Tema.fondo)
            .onAppear {
                FotocameraQR.condivisa.suTesto = { testo in leggi(testo) }
                if permessoFotocamera { FotocameraQR.condivisa.avvia() }
            }
            .task {
                // Prima volta: iOS chiede il permesso qui, poi la fotocamera parte subito.
                guard !permessoChiesto else { return }
                permessoFotocamera = await Cattura.chiediPermesso()
                permessoChiesto = true
                if permessoFotocamera { FotocameraQR.condivisa.avvia() }
            }
            .onDisappear {
                FotocameraQR.condivisa.suTesto = nil
                FotocameraQR.condivisa.ferma()
            }
            .navigationTitle("QR code del computer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { chiudi() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var testoInBasso: String {
        if let letto { return "QR code letto: mi collego a \(letto.nome)…" }
        return avviso ?? "Inquadra il QR code nel menu di WebcamLR sul computer."
    }

    /// Il riquadro dove inquadrare; letto il QR code diventa una spunta ciano.
    private var mirino: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(letto == nil ? Tema.testo.opacity(0.7) : Tema.ciano, lineWidth: letto == nil ? 2 : 4)
                .frame(width: 240, height: 240)
            if letto != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(Tema.ciano)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: letto != nil)
        .accessibilityHidden(true)
    }

    private func leggi(_ testo: String) {
        guard letto == nil else { return }
        guard let associazione = Associazione(testo: testo) else {
            if avviso != Self.nonDiWebcamLR { avviso = Self.nonDiWebcamLR }
            return
        }
        letto = associazione
        Vibrazione.qrLetto()
        FotocameraQR.condivisa.ferma()
        // Il collegamento parte ora, mentre si vede la spunta: il foglio si chiude subito dopo.
        suLettura(associazione)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            chiudi()
        }
    }
}

/// L'anteprima della fotocamera del lettore, che resta dritta quando si gira l'iPhone.
private struct AnteprimaQR: UIViewRepresentable {
    func makeUIView(context: Context) -> VistaAnteprimaQR {
        let vista = VistaAnteprimaQR()
        vista.collega(FotocameraQR.condivisa.sessione)
        return vista
    }

    func updateUIView(_ vista: VistaAnteprimaQR, context: Context) {}
}

private final class VistaAnteprimaQR: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var coordinatore: AVCaptureDevice.RotationCoordinator?
    private var osservazione: NSKeyValueObservation?

    func collega(_ sessione: AVCaptureSession) {
        guard let livello = layer as? AVCaptureVideoPreviewLayer else { return }
        livello.session = sessione
        livello.videoGravity = .resizeAspectFill
        guard let dispositivo = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        let nuovo = AVCaptureDevice.RotationCoordinator(device: dispositivo, previewLayer: livello)
        coordinatore = nuovo
        osservazione = nuovo.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak livello] coordinatore, _ in
            let angolo = coordinatore.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                if let connessione = livello?.connection, connessione.isVideoRotationAngleSupported(angolo) {
                    connessione.videoRotationAngle = angolo
                }
            }
        }
    }
}
