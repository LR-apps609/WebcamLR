import SafariServices
import Stile
import SwiftUI
import UIKit

/// G1.2: ciò che porterebbe fuori da WebcamLR. In diretta uscire dall'app ferma il video (iOS non lascia la
/// fotocamera alle app in sottofondo): le Impostazioni di iOS si aprono solo dopo una domanda; le pagine del sito
/// si aprono dentro l'app (`VistaSafari`), così l'app resta in primo piano.
enum ImpostazioniIOS {
    /// Le Impostazioni di iOS alla pagina di WebcamLR (lingua, permessi).
    static func apri() {
        guard let indirizzo = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(indirizzo)
    }
}

extension View {
    /// G1.2: la domanda prima di aprire le Impostazioni di iOS in diretta.
    func domandaPrimaDelleImpostazioniIOS(isPresented: Binding<Bool>) -> some View {
        alert("Vuoi aprire le Impostazioni di iOS?", isPresented: isPresented) {
            Button("Apri") { ImpostazioniIOS.apri() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il video si ferma finché non torni in WebcamLR.")
        }
    }
}

/// Una pagina del sito da aprire dentro l'app.
struct PaginaWeb: Identifiable {
    let indirizzo: URL
    var id: String { indirizzo.absoluteString }
}

/// G1.2: Privacy e sito in un foglio di Safari dentro l'app, con i colori di WebcamLR.
struct VistaSafari: UIViewControllerRepresentable {
    let indirizzo: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safari = SFSafariViewController(url: indirizzo)
        safari.preferredControlTintColor = UIColor(Tema.accento)
        safari.dismissButtonStyle = .done
        return safari
    }

    func updateUIViewController(_ safari: SFSafariViewController, context: Context) {}
}
