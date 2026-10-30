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
/// si legge dalla forma: videocamera vuota senza telefono, piena se collegato, piena con un punto in onda, piena con un
/// punto vuoto (un cerchietto) in riconnessione, cerchio della registrazione mentre registri.
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
            case .riconnessione where !ricevitore.inSottofondo:
                // In sottofondo il telefono può tacere: è una pausa, non una riconnessione (resta «collegato»).
                Image(nsImage: Self.riconnessione)
                    .accessibilityLabel("WebcamLR, riconnessione in corso")
            case .collegato, .riconnessione:
                Image(systemName: "video.fill")
                    .accessibilityLabel("WebcamLR, telefono collegato")
            case .nessunTelefono:
                Image(systemName: "video")
                    .accessibilityLabel("WebcamLR, nessun telefono")
            }
        }
    }

    /// «video.fill» con un punto pieno in alto a destra: in onda.
    private static let inOnda = conPunto(pieno: true)

    /// «video.fill» con un punto vuoto (un cerchietto) in alto a destra: riconnessione, diversa da «collegato».
    private static let riconnessione = conPunto(pieno: false)

    /// «video.fill» con un punto in alto a destra, disegnato in nero e segnato come modello: resta monocromatico.
    private static func conPunto(pieno: Bool) -> NSImage {
        let simbolo = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) ?? NSImage()
        let lato = simbolo.size
        let punto: CGFloat = 5
        let dimensione = NSSize(width: ceil(lato.width + punto + 1), height: ceil(max(lato.height, 16)))
        let immagine = NSImage(size: dimensione, flipped: false) { area in
            let origine = NSPoint(x: 0, y: ((area.height - lato.height) / 2).rounded())
            simbolo.draw(at: origine, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.black.set()
            let cerchio = NSRect(x: area.width - punto, y: area.height - punto - 1, width: punto, height: punto)
            if pieno {
                NSBezierPath(ovalIn: cerchio).fill()
            } else {
                // Il bordo dentro il riquadro del punto: stessa misura del punto pieno.
                let bordo = NSBezierPath(ovalIn: cerchio.insetBy(dx: 0.6, dy: 0.6))
                bordo.lineWidth = 1.2
                bordo.stroke()
            }
            return true
        }
        immagine.isTemplate = true
        return immagine
    }
}
