import AppKit
import Stile
import SwiftUI

/// «Consentire «…»?» (0.10): un telefono nuovo, senza il QR code, chiede di collegarsi.
/// Un pannello AppKit sempre in primo piano: compare anche con la finestra principale chiusa,
/// e si chiude da solo quando scade il tempo o il telefono se ne va.
@MainActor
final class FinestraConferma {
    private var pannello: NSPanel?

    func mostra(nome: String, codice: String, risposta: @escaping @MainActor (Bool) -> Void) {
        chiudi()
        let vista = VistaConferma(nome: nome, codice: codice) { [weak self] consentito in
            self?.chiudi()
            risposta(consentito)
        }
        let controllore = NSHostingController(rootView: vista)
        let pannello = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                               styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        pannello.contentViewController = controllore
        pannello.setContentSize(controllore.view.fittingSize)
        pannello.title = "Consentire «\(nome)»?"
        pannello.titleVisibility = .hidden
        pannello.titlebarAppearsTransparent = true
        pannello.isMovableByWindowBackground = true
        pannello.isFloatingPanel = true
        // Di serie un pannello sparisce quando l'app non è attiva: qui deve restare visibile.
        pannello.hidesOnDeactivate = false
        pannello.level = .floating
        pannello.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        pannello.isReleasedWhenClosed = false
        pannello.appearance = NSAppearance(named: .darkAqua)
        pannello.backgroundColor = NSColor(Tema.fondo)
        pannello.center()
        self.pannello = pannello

        NSApp.activate(ignoringOtherApps: true)
        pannello.makeKeyAndOrderFront(nil)
    }

    func chiudi() {
        guard let pannello else { return }
        self.pannello = nil
        pannello.orderOut(nil)
        pannello.close()
    }
}

private struct VistaConferma: View {
    let nome: String
    let codice: String
    let risposta: (Bool) -> Void

    var body: some View {
        VStack(spacing: 14) {
            LogoWebcamLR(lato: 36)
            Text("Consentire «\(nome)»?")
                .font(.titolo(26))
                .foregroundStyle(Tema.testo)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Controlla che sul telefono compaia lo stesso codice")
                .foregroundStyle(Tema.testoChiaro)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(codice.map(String.init).joined(separator: " "))
                .font(.numeriEvidenti(46))
                .foregroundStyle(Tema.ciano)
                .textSelection(.enabled)
                .accessibilityLabel("Codice di conferma \(codice.map(String.init).joined(separator: " "))")
            Text("Se il codice è diverso, o non conosci questo telefono, scegli «Non consentire».")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    risposta(false)
                } label: {
                    Text("Non consentire").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    risposta(true)
                } label: {
                    Text("Consenti").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Tema.ciano)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 400)
        .background(Tema.fondo)
        .preferredColorScheme(.dark)
    }
}
