import Stile
import SwiftUI

@main
struct WebcamLRApp: App {
    init() {
        Caratteri.registra()
        // Portachiavi e obiettivi letti in sottofondo: al tocco su «Collega» sono già pronti.
        IdentitaTelefono.prepara()
        Obiettivo.prepara()
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
