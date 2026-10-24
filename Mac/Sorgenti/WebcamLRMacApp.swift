import AVFoundation
import Stile
import SwiftUI

@main
struct WebcamLRMacApp: App {
    static let idPrincipale = "principale"

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
            ComandiWebcamLR(ricevitore: ricevitore, riprese: riprese)
        }

        Window("Finestra mini", id: FinestraMini.id) {
            FinestraMini(ricevitore: ricevitore)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 400, height: 225)
        .defaultPosition(.topTrailing)

        // Sezione App (0.12): dal menu WebcamLR, da Aiuto e dalla barra in alto.
        Window("App e assistenza", id: FinestraApp.id) {
            FinestraApp(ricevitore: ricevitore)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 600)

        Settings {
            Impostazioni(ricevitore: ricevitore)
        }

        MenuBarExtra {
            MenuBarra(ricevitore: ricevitore, fotocamera: fotocamera, riprese: riprese)
                .preferredColorScheme(.dark)
        } label: {
            IconaBarra(ricevitore: ricevitore)
        }
        .menuBarExtraStyle(.window)
    }
}
