import SwiftUI

/// Il menu «Video» nella barra dei menu dell'app: le scorciatoie con ⌘ valgono anche
/// quando i pulsanti della finestra non si vedono (vista pulita, finestra mini in primo piano).
/// Dalla 0.12 anche la sezione App: nel menu WebcamLR e al posto del menu Aiuto di serie.
struct ComandiWebcamLR: Commands {
    let ricevitore: Ricevitore
    let riprese: Riprese

    var body: some Commands {
        CommandMenu("Video") {
            VociMenuVideo(ricevitore: ricevitore, riprese: riprese)
        }
        CommandGroup(replacing: .appInfo) {
            VociMenuApp()
        }
        CommandGroup(replacing: .help) {
            VociMenuAiuto()
        }
    }
}

/// Nel menu WebcamLR: «Informazioni su WebcamLR» apre la scheda della sezione App, poi Pro e account.
private struct VociMenuApp: View {
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Button("Informazioni su WebcamLR") { apriFinestraApp(.informazioni, apri: apriFinestra) }
        Button("WebcamLR Pro e account…") { apriFinestraApp(.pro, apri: apriFinestra) }
    }
}

/// Il menu Aiuto: la guida e «Segnala un bug», nella finestra «App e assistenza».
private struct VociMenuAiuto: View {
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Button("Guida di WebcamLR") { apriFinestraApp(.guida, apri: apriFinestra) }
            .keyboardShortcut("?", modifiers: .command)
        Button("Segnala un bug…") { apriFinestraApp(.segnala, apri: apriFinestra) }
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
