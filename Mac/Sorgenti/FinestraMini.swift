import AppKit
import Stile
import SwiftUI

/// Finestra mini (funzione 21): lo stesso video in una finestrella 16:9 sempre in primo piano,
/// su tutte le scrivanie, da tenere in un angolo. Si sposta trascinando il video.
/// Con due telefoni (P21) mostra quello scelto per la webcam. In alto a destra lo stato (M10): la pillola a misura piena
/// in onda e in riconnessione, e il punto con il tempo mentre registri.
struct FinestraMini: View {
    static let id = "mini"

    let ricevitore: Ricevitore
    let riprese: Riprese
    @AppStorage(Preferenze.riempi) private var riempi = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Com'è arrivato, come nella finestra principale: «Specchia» lo fa il telefono (1.14).
            VistaSchermo(livello: ricevitore.livelloMini)
            if ricevitore.telefono == nil {
                Text("Nessun telefono")
                    .font(.etichetta(16))
                    .foregroundStyle(Tema.testoSecondario)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let motivo = ricevitore.statoTelefono?.pausa {
                // In pausa (sottofondo, fotocamera interrotta, faccia in giù, dal telefono…): calma, come nella finestra
                // principale (mai in rosso), con il motivo sotto.
                VStack(spacing: 4) {
                    Label("In pausa", systemImage: "pause.circle")
                        .font(.etichetta(16))
                        .foregroundStyle(Tema.testoTenue)
                    Text(Ricevitore.testoPausa(motivo))
                        .font(.corpo(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tema.pannelloScuro.opacity(0.9))
                .help(Ricevitore.testoPausa(motivo))
                .accessibilityElement(children: .combine)
            }
            // Nella finestra piccola (192 punti) prima si toglie il nome dell'app, poi il tempo va sotto la pillola.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    tempoRegistrazione
                    pillola(conApp: true)
                }
                HStack(spacing: 6) {
                    tempoRegistrazione
                    pillola(conApp: false)
                }
                VStack(alignment: .trailing, spacing: 6) {
                    pillola(conApp: false)
                    tempoRegistrazione
                }
            }
            .padding(8)
        }
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
    /// In onda e in riconnessione, a misura piena (M10); in sottofondo niente «Riconnessione»: resta la pausa.
    @ViewBuilder private func pillola(conApp: Bool) -> some View {
        switch ricevitore.collegamento {
        case .riconnessione where ricevitore.inSottofondo:
            EmptyView()
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
        HStack(spacing: 6) {
            Circle()
                .fill(Tema.tally)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                Text(verbatim: Riprese.testoDurata(secondi))
                    .font(.numeri(13))
                    .monospacedDigit()
            }
        }
        .modifier(StileChipVideo())
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
