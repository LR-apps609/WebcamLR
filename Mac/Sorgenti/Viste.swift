import AppKit
import SwiftUI

// Le tre viste della finestra principale (Documenti/Interfaccia finale.md, «Tre viste»):
// - «Essenziale»: il video grande, la barra sotto e «Impostazioni» in alto a destra (pannello che scorre da destra);
// - «Completo»: le colonne a sinistra e a destra, com'era prima;
// - «Schermo intero»: lo schermo intero di macOS con solo il video; «Esci» compare per qualche secondo quando si muove
//   il mouse o si preme un tasto, Esc esce.
// Si scelgono dal pulsante «Schermo» sotto il video e dal menu Vista (⌘1, ⌘2; ⌃⌘F è la voce di sistema).

/// La vista scelta, salvata in `Preferenze.vista`. Lo schermo intero non si salva: è uno stato della finestra.
enum VistaFinestra: String {
    case essenziale
    case completo
}

/// La finestra principale di AppKit, per lo schermo intero (dal pulsante «Schermo», da «Esci», da Esc e dal menu).
@MainActor
enum FinestraPrincipale {
    static var finestra: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WebcamLRMacApp.idPrincipale) == true }
    }

    /// La finestra principale si vede ed è quella in uso: un avviso dentro basta, senza notifica (M4).
    static var davanti: Bool {
        guard NSApp.isActive, let finestra else { return false }
        return finestra.isVisible && !finestra.isMiniaturized
    }

    static var aSchermoIntero: Bool {
        finestra?.styleMask.contains(.fullScreen) == true
    }

    static func alternaSchermoIntero() {
        finestra?.toggleFullScreen(nil)
    }

    /// Scegliendo «Essenziale» o «Completo» a schermo intero si torna nella finestra, con quella vista.
    static func esciDaSchermoIntero() {
        if aSchermoIntero { alternaSchermoIntero() }
    }
}

/// Dice quando la finestra che la ospita entra o esce dallo schermo intero, da qualunque parte arrivi il comando
/// (pulsante «Schermo», menu Vista, pulsante verde della finestra). Avvisa all'inizio del passaggio, così le colonne
/// spariscono insieme all'animazione di macOS.
struct OsservatoreSchermoIntero: NSViewRepresentable {
    let suCambio: @MainActor (Bool) -> Void

    final class Vista: NSView {
        var suCambio: (@MainActor (Bool) -> Void)?
        private var osservatori: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            osservatori.forEach { NotificationCenter.default.removeObserver($0) }
            osservatori = []
            guard let finestra = window else { return }
            let avvisi: [(Notification.Name, Bool)] = [(NSWindow.willEnterFullScreenNotification, true),
                                                       (NSWindow.didEnterFullScreenNotification, true),
                                                       (NSWindow.willExitFullScreenNotification, false),
                                                       (NSWindow.didExitFullScreenNotification, false)]
            for (nome, intero) in avvisi {
                let osservatore = NotificationCenter.default.addObserver(forName: nome, object: finestra, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.comunica(intero) }
                }
                osservatori.append(osservatore)
            }
            let intero = finestra.styleMask.contains(.fullScreen)
            // Fuori dall'aggiornamento delle viste: chi riceve cambia uno stato di SwiftUI.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.comunica(intero) }
            }
        }

        private func comunica(_ intero: Bool) {
            suCambio?(intero)
        }
    }

    func makeNSView(context: Context) -> Vista {
        let vista = Vista()
        vista.suCambio = suCambio
        return vista
    }

    func updateNSView(_ vista: Vista, context: Context) {
        vista.suCambio = suCambio
    }
}

/// Fino a quando resta visibile «Esci» a schermo intero. Un oggetto, non uno stato di SwiftUI: si sposta a ogni
/// movimento del mouse senza ridisegnare la finestra.
final class ScadenzaEsci {
    var data = Date.distantPast
}

/// Le voci del menu Vista: Essenziale (⌘1), Completo (⌘2), Finestra mini (⇧⌘M), Riempi l'inquadratura (⌥⌘F).
/// «Schermo intero» (⌃⌘F) è la voce che macOS mette da sé nello stesso menu: non si ripete.
struct VociMenuVista: View {
    let ricevitore: Ricevitore
    @AppStorage(Preferenze.vista) private var vista = VistaFinestra.essenziale
    @AppStorage(Preferenze.riempi) private var riempi = false
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        Toggle("Essenziale", isOn: scelta(.essenziale))
            .keyboardShortcut("1", modifiers: .command)
        Toggle("Completo", isOn: scelta(.completo))
            .keyboardShortcut("2", modifiers: .command)
        Divider()
        Toggle("Finestra mini", isOn: Binding(
            get: { ricevitore.miniAperta },
            set: { _ in alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra) }))
            .keyboardShortcut("m", modifiers: [.command, .shift])
        Toggle("Riempi l'inquadratura", isOn: $riempi)
            .keyboardShortcut("f", modifiers: [.command, .option])
        Divider()
    }

    /// Spuntata la vista attuale; scegliendola dal menu si esce anche dallo schermo intero.
    private func scelta(_ voce: VistaFinestra) -> Binding<Bool> {
        Binding(get: { vista == voce }, set: { _ in
            vista = voce
            FinestraPrincipale.esciDaSchermoIntero()
        })
    }
}
