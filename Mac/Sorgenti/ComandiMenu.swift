import SwiftUI

/// Il menu «Video» nella barra dei menu dell'app: le scorciatoie con ⌘ valgono anche
/// quando i pulsanti della finestra non si vedono (vista pulita, finestra mini in primo piano).
struct ComandiWebcamLR: Commands {
    let ricevitore: Ricevitore
    let riprese: Riprese

    var body: some Commands {
        CommandMenu("Video") {
            VociMenuVideo(ricevitore: ricevitore, riprese: riprese)
        }
    }
}

/// Le voci sono una vista: così seguono lo stato del ricevitore (attive o no, «Registra» o «Ferma»).
private struct VociMenuVideo: View {
    let ricevitore: Ricevitore
    let riprese: Riprese
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra
    @AppStorage(Preferenze.specchia) private var specchia = false
    @AppStorage(Preferenze.vistaPulita) private var vistaPulita = false
    @AppStorage(Preferenze.riempi) private var riempi = false

    var body: some View {
        // ⌘T come in Photo Booth.
        Button("Foto") { riprese.scattaFoto() }
            .keyboardShortcut("t")
            .disabled(ricevitore.telefono == nil)
        Button(riprese.contoAllaRovescia == nil ? "Foto tra 3 secondi" : "Annulla il timer") { riprese.scattaConTimer() }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(ricevitore.telefono == nil)
        // ⌘C lo gestisce la finestra principale (MonitorTastiera): qui niente scorciatoia,
        // così ⌘C nei campi di testo resta «Copia» del menu Composizione.
        Button("Copia il fotogramma") { riprese.copiaFotogramma() }
            .disabled(ricevitore.telefono == nil)

        Divider()

        Button(riprese.registra ? "Ferma la registrazione" : "Registra") { riprese.alternaRegistrazione() }
            .keyboardShortcut("r")
            .disabled(!riprese.registra && !ricevitore.telefonoAttivo)

        Divider()

        Toggle("Specchia", isOn: $specchia)
        Toggle("Riempi il riquadro", isOn: $riempi)
            .keyboardShortcut("f", modifiers: [.command, .option])
        Toggle("Vista pulita", isOn: $vistaPulita)
            .keyboardShortcut("p", modifiers: [.command, .shift])

        Divider()

        Button(ricevitore.miniAperta ? "Chiudi la finestra mini" : "Finestra mini") {
            alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
        }
        .keyboardShortcut("m", modifiers: [.command, .option])
    }
}
