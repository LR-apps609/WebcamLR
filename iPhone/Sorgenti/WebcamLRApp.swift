import Stile
import SwiftUI

@main
struct WebcamLRApp: App {
    init() {
        Caratteri.registra()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SchermataConnessione()
            }
            .tint(Tema.ciano)
            .preferredColorScheme(.dark)
        }
    }
}
