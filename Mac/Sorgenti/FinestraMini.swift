import AppKit
import Stile
import SwiftUI

/// Finestra mini (funzione 21): lo stesso video in una finestrella 16:9 sempre in primo piano,
/// su tutte le scrivanie, da tenere in un angolo. Si sposta trascinando il video.
struct FinestraMini: View {
    static let id = "mini"

    let ricevitore: Ricevitore
    @AppStorage(Preferenze.specchia) private var specchia = false
    @AppStorage(Preferenze.riempi) private var riempi = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VistaSchermo(livello: ricevitore.schermo.livelloMini)
                .scaleEffect(x: specchia ? -1 : 1, y: 1)
            if ricevitore.telefono == nil {
                Text("Nessun telefono")
                    .font(.etichetta(16))
                    .foregroundStyle(Tema.testoSecondario)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            switch ricevitore.collegamento {
            case .inOnda, .riconnessione:
                PillolaStato(ricevitore.collegamento)
                    .scaleEffect(0.75, anchor: .topTrailing)
                    .padding(8)
            default:
                EmptyView()
            }
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
            ricevitore.schermo.imposta(riempi: riempi)
            ricevitore.mostraMini(true)
        }
        // Anche qui: con la finestra principale chiusa ⌥⌘F deve valere lo stesso.
        .onChange(of: riempi) { ricevitore.schermo.imposta(riempi: riempi) }
        .onDisappear { ricevitore.mostraMini(false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Finestra mini di WebcamLR")
    }
}

/// Apre la finestra mini se è chiusa, la chiude se è aperta (dalla finestra, dal menu e dalla barra in alto).
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
