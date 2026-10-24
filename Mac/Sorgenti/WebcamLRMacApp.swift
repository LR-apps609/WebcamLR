import AVFoundation
import Stile
import SwiftUI

@main
struct WebcamLRMacApp: App {
    static let idPrincipale = "principale"

    @NSApplicationDelegateAdaptor(DelegatoApp.self) private var delegato

    @State private var ricevitore: Ricevitore
    @State private var fotocamera = AttivazioneFotocamera()
    @State private var riprese: Riprese

    init() {
        let ricevitore = Ricevitore()
        _ricevitore = State(initialValue: ricevitore)
        _riprese = State(initialValue: Riprese(schermo: ricevitore.schermo))
        Caratteri.registra()
        Notifiche.condivise.prepara()
        // Visibile in rete da subito, prima di qualsiasi finestra: anche quando WebcamLR si apre
        // all'avvio del Mac senza finestre, o con la finestra principale chiusa l'ultima volta.
        // Così il QR code è pronto appena compare.
        ricevitore.avvia()
        // Specchia di serie (funzione 35): se è stato scelto, vale a ogni apertura.
        if let diSerie = UserDefaults.standard.object(forKey: Preferenze.specchiaDiSerie) as? Bool {
            UserDefaults.standard.set(diSerie, forKey: Preferenze.specchia)
        }
    }

    var body: some Scene {
        // Una finestra sola: «Apri WebcamLR» la riporta davanti invece di aprirne un'altra.
        Window("WebcamLR", id: Self.idPrincipale) {
            ContenutoPrincipale(ricevitore: ricevitore, fotocamera: fotocamera, riprese: riprese)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear {
                    if fotocamera.disponibile {
                        // Per mettere le immagini nella webcam virtuale serve il permesso della fotocamera.
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            ricevitore.collegaWebcamVirtuale()
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            ComandiWebcamLR()
        }

        Window("Finestra mini", id: FinestraMini.id) {
            FinestraMini(ricevitore: ricevitore)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 400, height: 225)
        .defaultPosition(.topTrailing)

        // Sezione App (0.12): dal pulsante «Aiuto» della finestra principale.
        Window("App e assistenza", id: FinestraApp.id) {
            FinestraApp(ricevitore: ricevitore)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 600)

        Settings {
            Impostazioni(ricevitore: ricevitore)
        }
    }
}

/// Senza icona nella barra in alto: WebcamLR resta aperta anche a finestra chiusa (il telefono la ritrova
/// e il QR è pronto) e un clic sull'icona nel Dock riapre la finestra.
final class DelegatoApp: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Conta la finestra principale, non le altre: con la finestra mini (sempre in primo piano) o le
    /// Impostazioni aperte `hasVisibleWindows` è vero e il clic sul Dock prima non riapriva niente.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            let principaleVisibile = sender.windows.contains { finestra in
                finestra.isVisible && finestra.identifier?.rawValue.hasPrefix(WebcamLRMacApp.idPrincipale) == true
            }
            // Se la finestra è già aperta, openWindow la porta solo davanti: nessun doppione.
            if !principaleVisibile {
                Notifiche.condivise.apriFinestraPrincipale?()
            }
        }
        return true
    }
}
