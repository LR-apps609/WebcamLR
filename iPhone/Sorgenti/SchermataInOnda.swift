import AVFoundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Schermata «In onda» (bozza grafica, iPhone 3) e schermo oscurato (iPhone 6).
/// La sessione nasce in `SchermataConnessione` quando si sceglie il computer: così la fotocamera
/// e il collegamento si creano una volta sola, anche se SwiftUI ricostruisce questa vista.
struct SchermataInOnda: View {
    let sessione: SessioneTelefono
    @Environment(\.dismiss) private var chiudi
    @Environment(\.verticalSizeClass) private var classeVerticale
    @State private var zoomIniziale: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaFotocamera(livello: sessione.cattura.anteprima)
                .ignoresSafeArea()
                .gesture(SpatialTapGesture().onEnded { tocco in
                    sessione.metteAFuoco(tocco.location)
                })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { valore in
                        if zoomIniziale == nil { zoomIniziale = sessione.zoom }
                        sessione.impostaZoom((zoomIniziale ?? 1) * valore.magnification)
                    }
                    .onEnded { _ in zoomIniziale = nil })
            if let punto = sessione.puntoFuoco {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(esadecimale: 0xF3C969), lineWidth: 2)
                    .frame(width: 84, height: 84)
                    .position(punto)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            GrigliaTerzi()
                .ignoresSafeArea()

            sovrapposizioni
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if sessione.oscurato {
                SchermoOscurato(sessione: sessione)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { sessione.avvia() }
        .onDisappear { sessione.termina() }
    }

    private var sovrapposizioni: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    PillolaStato(statoPillola, testo: testoPillola)
                    if sessione.stato == .collegato {
                        Chip { telemetria }
                    }
                    Spacer(minLength: 0)
                    Chip {
                        Text(testoBatteria)
                    }
                }
                if sessione.qualitaRidotta {
                    Chip { Text("Telefono molto caldo: qualità ridotta a 720p").foregroundStyle(Tema.ambraTesto) }
                }
                if sessione.batteriaBassa {
                    Chip { Text("Batteria \(sessione.batteria)%: collega il caricatore").foregroundStyle(Tema.ambraTesto) }
                }
                if classeVerticale == .regular {
                    Chip { Text("Gira l'iPhone in orizzontale per un'inquadratura larga") }
                }
                Spacer()
                if case .errore(let descrizione) = sessione.stato {
                    pannelloErrore(descrizione)
                }
                Spacer()
                HStack {
                    Spacer()
                    SelettoreObiettivo(sessione: sessione)
                    Spacer()
                }
            }
            barraComandi
        }
    }

    private var telemetria: some View {
        HStack(spacing: 10) {
            Text(sessione.larghezza > 0 ? "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps)" : "—")
            Text(sessione.latenzaMs.map { "\($0) ms" } ?? "— ms")
                .foregroundStyle(Tema.cianoChiaro)
            Text("Wi-Fi")
            if sessione.zoom > 1.05 {
                Text(String(format: "%.1f×", sessione.zoom).replacingOccurrences(of: ".", with: ","))
            }
            // Esposizione manuale dal computer: la luce non si adatta più da sola.
            // Il tempo mostrato è quello usato: mai più lungo di un fotogramma.
            if sessione.iso > 0 || sessione.tempo > 0 {
                Text([sessione.iso > 0 ? "ISO \(Int(sessione.iso))" : nil,
                      sessione.tempo > 0 ? "1/\(max(sessione.tempo, sessione.fps))" : nil].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(Tema.ambraTesto)
            }
        }
    }

    private var barraComandi: some View {
        VStack(spacing: 10) {
            PulsanteTondo("Microfono, dal round 5", icona: "mic.slash") {}
                .disabled(true)
                .opacity(0.4)
            PulsanteTondo("Torcia", icona: sessione.torciaAccesa ? "flashlight.on.fill" : "flashlight.off.fill",
                          attivo: sessione.torciaAccesa) {
                sessione.cambiaTorcia()
            }
            .disabled(!sessione.torciaDisponibile)
            .opacity(sessione.torciaDisponibile ? 1 : 0.4)
            // Gli effetti video di iOS (Ritratto, Luce da studio): il pannello è quello di sistema.
            PulsanteTondo("Effetti video", icona: "person.and.background.dotted") {
                AVCaptureDevice.showSystemUserInterface(.videoEffects)
            }
            Button {} label: {
                Text("PRO")
                    .font(.titolo(17))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Tema.pannelloChiaro, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(true)
            .opacity(0.4)
            .accessibilityLabel("Controlli pro, dal round 4")
            PulsanteTondo("Oscura lo schermo", icona: "moon.fill") {
                withAnimation { sessione.oscurato = true }
            }
            Button {
                chiudi()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Tema.bordo))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scollega")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Tema.fondo.opacity(0.82), in: RoundedRectangle(cornerRadius: 30))
        .frame(maxHeight: .infinity)
    }

    private func pannelloErrore(_ descrizione: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collegamento interrotto")
                .font(.titolo(24))
            Text(descrizione)
                .font(.subheadline)
                .foregroundStyle(Tema.testoTenue)
            HStack {
                Button("Riprova") { sessione.riprova() }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Tema.ciano, in: Capsule())
                    .foregroundStyle(Tema.fondo)
                Button("Torna ai computer") { chiudi() }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Tema.fondo.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Tema.testo)
    }

    private var statoPillola: StatoCollegamento {
        switch sessione.stato {
        case .collegato where sessione.inOnda != nil: .inOnda(app: sessione.inOnda?.app)
        case .collegato: .collegato
        case .collegamento, .riconnessione: .riconnessione
        case .chiusa, .errore: .nessunTelefono
        }
    }

    private var testoPillola: String {
        switch sessione.stato {
        case .collegato where sessione.inOnda != nil: sessione.inOnda?.app.map { "In onda · \($0)" } ?? "In onda"
        case .collegato: "Collegato · \(sessione.computer.nome)"
        case .collegamento: "Collegamento…"
        case .riconnessione(let tentativo): "Riconnessione \(tentativo)/\(SessioneTelefono.tentativiMassimi)"
        case .chiusa, .errore: "Scollegato"
        }
    }

    private var testoBatteria: String {
        let batteria = sessione.batteria >= 0 ? "\(sessione.batteria)%" : "—"
        return "\(batteria) · temperatura \(sessione.temperatura.descrizione)"
    }
}

extension Temperatura {
    var descrizione: String {
        switch self {
        case .normale: "ok"
        case .calda: "calda"
        case .moltoCalda: "molto calda"
        case .critica: "critica"
        }
    }
}

/// Riquadro scuro semitrasparente per i dati tecnici sopra il video.
private struct Chip<Contenuto: View>: View {
    @ViewBuilder let contenuto: Contenuto

    var body: some View {
        HStack(spacing: 8) { contenuto }
            .font(.numeri(12.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Tema.fondo.opacity(0.72), in: Capsule())
    }
}

private struct SelettoreObiettivo: View {
    let sessione: SessioneTelefono

    var body: some View {
        HStack(spacing: 6) {
            ForEach(sessione.obiettiviDisponibili) { obiettivo in
                let scelto = obiettivo == sessione.obiettivo
                Button {
                    sessione.scegli(obiettivo)
                } label: {
                    Text(obiettivo.etichetta)
                        .font(.numeriEvidenti(scelto ? 14 : 13))
                        .foregroundStyle(scelto ? Tema.fondo : .white)
                        .frame(minWidth: scelto ? 44 : 40, minHeight: scelto ? 44 : 40)
                        .padding(.horizontal, obiettivo == .frontale || obiettivo == .tele ? 6 : 0)
                        .background(scelto ? Tema.testo : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scelto ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Tema.fondo.opacity(0.72), in: Capsule())
    }
}

/// Linee dei terzi, come nel mirino della bozza.
private struct GrigliaTerzi: View {
    var body: some View {
        GeometryReader { area in
            Path { linee in
                for frazione in [1.0 / 3, 2.0 / 3] {
                    linee.move(to: CGPoint(x: area.size.width * frazione, y: 0))
                    linee.addLine(to: CGPoint(x: area.size.width * frazione, y: area.size.height))
                    linee.move(to: CGPoint(x: 0, y: area.size.height * frazione))
                    linee.addLine(to: CGPoint(x: area.size.width, y: area.size.height * frazione))
                }
            }
            .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Schermo nero durante l'uso (funzione 32): il video continua, lo schermo non consuma.
private struct SchermoOscurato: View {
    let sessione: SessioneTelefono

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(colorePunto)
                        .frame(width: 9, height: 9)
                    Text(testoStato)
                        .font(.etichetta(22))
                }
                HStack(spacing: 16) {
                    Text(sessione.latenzaMs.map { "\($0) ms" } ?? "— ms")
                    Text(sessione.larghezza > 0 ? "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps)" : "—")
                    Text(sessione.batteria >= 0 ? "batteria \(sessione.batteria)%" : "batteria —")
                    Text("temperatura \(sessione.temperatura.descrizione)")
                }
                .font(.numeri(13))
                Text("Tocca due volte per riaccendere lo schermo")
                    .font(.footnote)
                    .padding(.top, 18)
            }
            .foregroundStyle(Color(esadecimale: 0x8B9792))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation { sessione.oscurato = false }
        }
        .accessibilityAction(named: "Riaccendi lo schermo") {
            sessione.oscurato = false
        }
    }

    /// Anche a schermo spento il rosso compare solo quando un'app usa davvero la webcam.
    private var colorePunto: Color {
        guard sessione.stato == .collegato else { return Tema.ambra.opacity(0.7) }
        return sessione.inOnda != nil ? Tema.tally : Tema.verde.opacity(0.7)
    }

    private var testoStato: String {
        guard sessione.stato == .collegato else { return "Riconnessione…" }
        return sessione.inOnda != nil ? "In onda su \(sessione.computer.nome)" : "Collegato a \(sessione.computer.nome)"
    }
}

/// Mostra il livello di anteprima della fotocamera dentro SwiftUI.
private struct AnteprimaFotocamera: UIViewRepresentable {
    let livello: AVCaptureVideoPreviewLayer

    final class Vista: UIView {
        var livello: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let livello { layer.addSublayer(livello) }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            livello?.frame = bounds
        }
    }

    func makeUIView(context: Context) -> Vista {
        let vista = Vista()
        vista.backgroundColor = .black
        vista.livello = livello
        return vista
    }

    func updateUIView(_ vista: Vista, context: Context) {
        if vista.livello !== livello { vista.livello = livello }
    }
}
