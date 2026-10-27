import Stile
import SwiftUI

@main
struct WebcamLRApp: App {
    init() {
        Caratteri.registra()
        // 1.11: il momento dell'apertura, per misurare quanto ci vuole ad avere il video.
        _ = MisuraAvvio.aperturaApp
        // Portachiavi e obiettivi letti in sottofondo: al tocco su «Collega» sono già pronti.
        IdentitaTelefono.prepara()
        Obiettivo.prepara()
        // Dal 27 ottobre la qualità si sceglie solo sul computer: le scelte salvate di prima non valgono più.
        ImpostazioniVideo.cancellaChiaviVecchie()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SchermataConnessione()
            }
            .tint(Tema.ciano)
            .preferredColorScheme(.dark)
            // WebcamLR Pro: l'ascolto delle transazioni parte all'apertura (acquisti approvati, rimborsi,
            // In famiglia) e resta acceso finché l'app è viva.
            .task { NegozioPro.condiviso.avvia() }
        }
    }
}
