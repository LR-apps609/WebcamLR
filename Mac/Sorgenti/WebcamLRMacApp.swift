import SwiftUI

@main
struct WebcamLRMacApp: App {
    @State private var annuncio = AnnuncioInRete()
    @State private var fotocamera = AttivazioneFotocamera()

    var body: some Scene {
        WindowGroup("WebcamLR") {
            ContenutoPrincipale(annuncio: annuncio, fotocamera: fotocamera)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear { annuncio.avvia() }
        }
        .defaultSize(width: 1280, height: 800)

        MenuBarExtra("WebcamLR", systemImage: "video") {
            MenuBarra(annuncio: annuncio, fotocamera: fotocamera)
                .preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)
    }
}
