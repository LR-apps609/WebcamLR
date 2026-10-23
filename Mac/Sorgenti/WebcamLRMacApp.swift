import Stile
import SwiftUI

@main
struct WebcamLRMacApp: App {
    @State private var ricevitore = Ricevitore()
    @State private var fotocamera = AttivazioneFotocamera()

    init() {
        Caratteri.registra()
    }

    var body: some Scene {
        WindowGroup("WebcamLR") {
            ContenutoPrincipale(ricevitore: ricevitore, fotocamera: fotocamera)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear {
                    ricevitore.avvia()
                    if fotocamera.disponibile { ricevitore.collegaWebcamVirtuale() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)

        MenuBarExtra("WebcamLR", systemImage: "video") {
            MenuBarra(ricevitore: ricevitore, fotocamera: fotocamera)
                .preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)
    }
}
