import SwiftUI

@main
struct WebcamLRApp: App {
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
