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
                    ricevitore.avvia()
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

        Settings {
            Impostazioni()
        }

        MenuBarExtra("WebcamLR", systemImage: "video") {
            MenuBarra(ricevitore: ricevitore, fotocamera: fotocamera)
                .preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)
    }
}
