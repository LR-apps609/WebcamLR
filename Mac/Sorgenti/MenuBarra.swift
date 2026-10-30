import AppKit
import SwiftUI

/// Il menu dell'icona di WebcamLR nella barra dei menu (passo 6, M7): lo stato anche a finestra chiusa.
/// Accesa di serie, si spegne in Impostazioni › Schermo. Funziona senza account a pagamento.
/// Le righe di stato sono le stesse del menu del Dock.
struct MenuBarra: View {
    let ricevitore: Ricevitore
    let riprese: Riprese
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        // `secondiRegistrati` cambia ogni secondo: letto qui, il tempo di «Registrazione 12:31» resta giusto.
        let _ = riprese.secondiRegistrati
        ForEach(DelegatoApp.righeStato(ricevitore: ricevitore, riprese: riprese), id: \.self) { riga in
            Text(riga)
        }
        if riprese.registra {
            Button("Ferma la registrazione") { riprese.fermaRegistrazione() }
        }
        Divider()
        Button("Mostra WebcamLR") {
            NSApp.activate(ignoringOtherApps: true)
            apriFinestra(id: WebcamLRMacApp.idPrincipale)
        }
        // Il pannello «Impostazioni» della finestra principale (passo 8), come ⌘, nel menu dell'app.
        Button("Impostazioni…") { apriImpostazioniWebcamLR(apri: apriFinestra) }
        .keyboardShortcut(",")
        Divider()
        // Passa da `applicationShouldTerminate`: se un'app usa il video o registri, prima chiede.
        Button("Esci da WebcamLR") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// L'icona: un modello (template) monocromatico, che macOS colora come le altre icone della barra. Senza colore lo stato
/// si legge dalla forma: videocamera vuota senza telefono, piena se collegato, piena con un punto in onda, cerchio
/// della registrazione mentre registri.
struct IconaBarra: View {
    let ricevitore: Ricevitore
    let riprese: Riprese

    var body: some View {
        if riprese.registra {
            Image(systemName: "record.circle")
                .accessibilityLabel("WebcamLR, registrazione in corso")
        } else {
            switch ricevitore.collegamento {
            case .inOnda:
                Image(nsImage: Self.inOnda)
                    .accessibilityLabel("WebcamLR, in onda")
            case .collegato, .riconnessione:
                Image(systemName: "video.fill")
                    .accessibilityLabel("WebcamLR, telefono collegato")
            case .nessunTelefono:
                Image(systemName: "video")
                    .accessibilityLabel("WebcamLR, nessun telefono")
            }
        }
    }

    /// «video.fill» con un punto in alto a destra, disegnato in nero e segnato come modello: resta monocromatico.
    private static let inOnda: NSImage = {
        let simbolo = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) ?? NSImage()
        let lato = simbolo.size
        let punto: CGFloat = 5
        let dimensione = NSSize(width: ceil(lato.width + punto + 1), height: ceil(max(lato.height, 16)))
        let immagine = NSImage(size: dimensione, flipped: false) { area in
            let origine = NSPoint(x: 0, y: ((area.height - lato.height) / 2).rounded())
            simbolo.draw(at: origine, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.black.set()
            NSBezierPath(ovalIn: NSRect(x: area.width - punto, y: area.height - punto - 1,
                                        width: punto, height: punto)).fill()
            return true
        }
        immagine.isTemplate = true
        return immagine
    }()
}
