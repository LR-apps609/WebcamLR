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
private struct VoceInformazioni: View {
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Button("Informazioni su WebcamLR") { apriFinestraApp(.informazioni, apri: apriFinestra) }
    }
}
