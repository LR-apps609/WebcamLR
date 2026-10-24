import AppKit
import SwiftUI

/// Tasti singoli per la finestra principale (funzione 25): 1–4, + e −, F.
/// Valgono solo quando quella finestra è in primo piano e nessun campo di testo sta ricevendo i tasti;
/// altrimenti il tasto prosegue come sempre. `gestisci` restituisce vero se ha usato il tasto.
struct MonitorTastiera: NSViewRepresentable {
    let gestisci: (NSEvent) -> Bool

    final class Vista: NSView {
        var gestisci: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evento in
                guard let self, let finestra = self.window, evento.window === finestra, finestra.isKeyWindow,
                      !(finestra.firstResponder is NSText), let gestisci = self.gestisci else { return evento }
                return gestisci(evento) ? nil : evento
            }
        }
    }

    func makeNSView(context: Context) -> Vista {
        let vista = Vista()
        vista.gestisci = gestisci
        return vista
    }

    func updateNSView(_ vista: Vista, context: Context) {
        vista.gestisci = gestisci
    }
}
