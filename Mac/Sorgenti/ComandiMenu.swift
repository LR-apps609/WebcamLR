import SwiftUI

/// La barra dei menu resta quella di serie di macOS: niente menu in più. Guida, domande frequenti,
/// «Segnala un bug», Pro e informazioni stanno nella finestra (pulsante «Aiuto» in alto);
/// le scorciatoie (⌘T, ⌘R, ⇧⌘M…) le gestisce la finestra principale.
struct ComandiWebcamLR: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            VoceInformazioni()
        }
        // Il menu Aiuto di serie porterebbe a una guida che non c'è: resta solo la ricerca di macOS.
        CommandGroup(replacing: .help) {}
    }
}

/// «Informazioni su WebcamLR» al solito posto, ma apre la nostra scheda.
/// Fa anche da aiutante per il clic sull'icona nel Dock (P19): SwiftUI costruisce il menu all'avvio, anche senza
/// finestre, e qui c'è già un `openWindow`. Così `apriFinestraPrincipale` è pronta anche se la finestra
/// principale non è mai comparsa in questo avvio (aperta all'accesso al Mac, o chiusa l'ultima volta).
private struct VoceInformazioni: View {
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        let _ = preparaRiapertura()
        Button("Informazioni su WebcamLR") { apriFinestraApp(.informazioni, apri: apriFinestra) }
    }

    /// Una volta sola: la finestra principale, quando compare, non la sostituisce (ContenutoPrincipale).
    /// Nessuno stato osservato cambia qui: rileggere il corpo della vista non ha effetti.
    private func preparaRiapertura() {
        guard Notifiche.condivise.apriFinestraPrincipale == nil else { return }
        let apri = apriFinestra
        Notifiche.condivise.apriFinestraPrincipale = { apri(id: WebcamLRMacApp.idPrincipale) }
    }
}
