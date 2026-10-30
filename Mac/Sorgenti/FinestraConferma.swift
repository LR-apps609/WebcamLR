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
        pannello.title = String(localized: "Consentire «\(nome)»?")
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
        VStack(spacing: Spazi.medio) {
            LogoWebcamLR(lato: 36)
            Text("Consentire «\(nome)»?")
                .font(.stile(.titoloGrande))
                .foregroundStyle(Tema.testo)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Controlla che sul telefono compaia lo stesso codice")
                .foregroundStyle(Tema.testoChiaro)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Il codice da confrontare con il telefono: grande di proposito, fuori dalla scala dei testi.
            Text(codice.map(String.init).joined(separator: " "))
                .font(.numeriEvidenti(46))
                .foregroundStyle(Tema.accento)
                .textSelection(.enabled)
                .accessibilityLabel("Codice di conferma \(codice.map(String.init).joined(separator: " "))")
            Text("Se il codice è diverso, o non conosci questo telefono, scegli «Non consentire».")
                .font(.stile(.corpo))
                .foregroundStyle(Tema.testoSecondario)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spazi.stretto) {
                Button {
                    risposta(false)
                } label: {
                    Text("Non consentire").frame(maxWidth: .infinity)
                }
                .buttonStyle(StileSecondario())
                .keyboardShortcut(.cancelAction)
                Button {
                    risposta(true)
                } label: {
                    Text("Consenti").frame(maxWidth: .infinity)
                }
                .buttonStyle(StilePrimario())
            }
            .padding(.top, Spazi.minimo)
        }
        // Testo nostro in Barlow (Documenti/Stile.md, «Barlow o sistema»).
        .font(.stile(.corpo))
        .padding(.horizontal, Spazi.largo)
        .padding(.top, Spazi.ampio)
        .padding(.bottom, Spazi.largo)
        .frame(width: 400)
        .background(Tema.fondo)
        .preferredColorScheme(.dark)
    }
}
