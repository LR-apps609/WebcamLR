import AppKit
import Stile
import SwiftUI

/// Finestra mini (funzione 21): lo stesso video in una finestrella 16:9 sempre in primo piano,
/// su tutte le scrivanie, da tenere in un angolo. Si sposta trascinando il video.
/// Con due telefoni (P21) mostra quello scelto per la webcam. In alto a destra lo stato (M10): la pillola a misura piena
/// in onda e in riconnessione, e il punto con il tempo mentre registri.
/// Passo 8: doppio clic sul video riapre la finestra principale (M20); clic destro: Apri WebcamLR, Riempi
/// l'inquadratura, Chiudi la finestra mini (M19).
struct FinestraMini: View {
    static let id = "mini"

    let ricevitore: Ricevitore
    let riprese: Riprese
    @AppStorage(Preferenze.riempi) private var riempi = false
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Com'è arrivato, come nella finestra principale: «Specchia» lo fa il telefono (1.14).
            VistaSchermo(livello: ricevitore.livelloMini)
            if ricevitore.telefono == nil {
                Text("Nessun telefono")
                    .font(.stile(.sezione))
                    .foregroundStyle(Tema.testoSecondario)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let motivo = ricevitore.statoTelefono?.pausa {
                // In pausa (sottofondo, fotocamera interrotta, faccia in giù, dal telefono…): calma, come nella finestra
                // principale (mai in rosso), con il motivo sotto.
                VStack(spacing: Spazi.minimo) {
                    Label("In pausa", systemImage: "pause.circle")
                        .font(.stile(.sezione))
                        .foregroundStyle(Tema.testoTenue)
                    Text(Ricevitore.testoPausa(motivo))
                        .font(.stile(.nota))
                        .foregroundStyle(Tema.testoSecondario)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, Spazi.piccolo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tema.pannelloScuro.opacity(Veli.forte))
                .help(Ricevitore.testoPausa(motivo))
                .accessibilityElement(children: .combine)
            }
            // Nella finestra piccola (192 punti) prima si toglie il nome dell'app, poi il tempo va sotto la pillola.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spazi.stretto) {
                    tempoRegistrazione
                    pillola(conApp: true)
                }
                HStack(spacing: Spazi.stretto) {
                    tempoRegistrazione
                    pillola(conApp: false)
                }
                VStack(alignment: .trailing, spacing: Spazi.stretto) {
                    pillola(conApp: false)
                    tempoRegistrazione
                }
            }
            .padding(Spazi.stretto)
        }
        .contextMenu {
            Button("Apri WebcamLR") { apriPrincipale() }
            Toggle("Riempi l'inquadratura", isOn: $riempi)
            Divider()
            Button("Chiudi la finestra mini") { chiudiFinestra(id: FinestraMini.id) }
        }
        .background(OsservatoreDoppioClic { apriPrincipale() })
        .frame(minWidth: 192, idealWidth: 400, maxWidth: .infinity, minHeight: 108, idealHeight: 225, maxHeight: .infinity)
        .background(.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .background(AccessoFinestra { finestra in
            // .windowLevel di SwiftUI c'è solo da macOS 15: qui si passa dalla finestra AppKit.
            finestra.level = .floating
            finestra.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
            finestra.contentAspectRatio = NSSize(width: 16, height: 9)
            finestra.isMovableByWindowBackground = true
            finestra.titlebarAppearsTransparent = true
            finestra.titleVisibility = .hidden
            finestra.backgroundColor = .black
            finestra.standardWindowButton(.miniaturizeButton)?.isHidden = true
            finestra.standardWindowButton(.zoomButton)?.isHidden = true
        })
        .onAppear {
            ricevitore.imposta(riempi: riempi)
            ricevitore.mostraMini(true)
        }
        // Anche qui: con la finestra principale chiusa ⌥⌘F deve valere lo stesso.
        .onChange(of: riempi) { ricevitore.imposta(riempi: riempi) }
        .onDisappear { ricevitore.mostraMini(false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Finestra mini di WebcamLR")
    }
}

extension FinestraMini {
    /// La finestra principale davanti (la mini resta sopra: è sempre in primo piano).
    private func apriPrincipale() {
        NSApp.activate(ignoringOtherApps: true)
        apriFinestra(id: WebcamLRMacApp.idPrincipale)
    }

    /// In onda e in riconnessione, a misura piena (M10); in sottofondo niente «Riconnessione»: resta la pausa.
    @ViewBuilder private func pillola(conApp: Bool) -> some View {
        switch ricevitore.collegamento {
        case .riconnessione where ricevitore.inSottofondo:
            EmptyView()
        case .inOnda where ricevitore.statoTelefono?.pausa != nil:
            // Telefono in pausa con un'app sulla webcam: «In pausa» in ambra, niente corallo (come la finestra principale).
            PillolaStato(.riconnessione, testo: String(localized: "In pausa"))
        case .inOnda:
            PillolaStato(.inOnda(app: conApp ? ricevitore.nomeAppInOnda : nil))
        case .riconnessione:
            PillolaStato(.riconnessione)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var tempoRegistrazione: some View {
        if let inizio = riprese.inizioRegistrazione {
            registrazione(da: inizio)
        }
    }

    /// Il punto corallo (tally) e il tempo, come sul pulsante «Registra» della finestra principale.
    private func registrazione(da inizio: Date) -> some View {
        HStack(spacing: Spazi.stretto) {
            Circle()
                .fill(Tema.tally)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                Text(verbatim: Riprese.testoDurata(secondi))
                    .font(.stile(.numeri))
                    .monospacedDigit()
            }
        }
        .chipInformativo()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Registrazione in corso")
    }
}

/// Apre la finestra mini se è chiusa, la chiude se è aperta (dal pulsante della finestra e da ⇧⌘M).
@MainActor
func alternaFinestraMini(_ ricevitore: Ricevitore, apri: OpenWindowAction, chiudi: DismissWindowAction) {
    if ricevitore.miniAperta {
        chiudi(id: FinestraMini.id)
    } else {
        apri(id: FinestraMini.id)
    }
}

/// Il doppio clic nella finestra che ospita la vista (finestra mini, M20). Un osservatore di AppKit e non un gesto di
/// SwiftUI: il video è una vista AppKit che sposta la finestra quando lo si trascina, e il gesto non arriverebbe.
struct OsservatoreDoppioClic: NSViewRepresentable {
    let azione: () -> Void

    final class Vista: NSView {
        var azione: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] evento in
                guard let self, evento.clickCount == 2, let finestra = self.window, evento.window === finestra,
                      let azione = self.azione else { return evento }
                azione()
                return nil
            }
        }
    }

    func makeNSView(context: Context) -> Vista {
        let vista = Vista()
        vista.azione = azione
        return vista
    }

    func updateNSView(_ vista: Vista, context: Context) {
        vista.azione = azione
    }
}

/// Mette mano alla finestra AppKit che ospita una vista SwiftUI (livello, spazi, proporzioni),
/// per ciò che SwiftUI non offre su macOS 14.
struct AccessoFinestra: NSViewRepresentable {
    let configura: (NSWindow) -> Void

    final class Vista: NSView {
        var configura: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { configura?(window) }
        }
    }

    func makeNSView(context: Context) -> Vista {
        let vista = Vista()
        vista.configura = configura
        return vista
    }

    func updateNSView(_ vista: Vista, context: Context) {
        vista.configura = configura
    }
}
