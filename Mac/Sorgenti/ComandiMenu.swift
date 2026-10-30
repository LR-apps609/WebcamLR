import AppKit
import SwiftUI

/// La barra dei menu secondo le regole di macOS (passo 8): ogni comando ha la sua voce e la voce fa scoprire il tasto.
/// - WebcamLR: «Informazioni su WebcamLR», «Verifica aggiornamenti…» e «Impostazioni…» ⌘, (apre il pannello
///   «Impostazioni» della finestra principale: è l'unico posto delle impostazioni);
/// - Vista: Essenziale, Completo, Finestra mini e Riempi l'inquadratura (Viste.swift);
/// - Video: foto, registrazione, specchio, sfondo, obiettivi, zoom, fuoco, vista pulita e «Scollega…»;
/// - Aiuto: guida (⌘?), domande frequenti, «Il telefono non trova il Mac?» e «Segnala un bug…».
/// Le scorciatoie valgono anche con la finestra mini davanti. Nella finestra principale ⌘C e i tasti singoli
/// (1–4, +, −, F) li prende prima la finestra (MonitorTastiera), che lascia passare i tasti dei campi di testo.
struct ComandiWebcamLR: Commands {
    let ricevitore: Ricevitore
    let riprese: Riprese

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            VoceInformazioni()
            VoceVerificaAggiornamenti()
        }
        // Senza la scena `Settings` la voce non c'è: la mettiamo noi, con ⌘,, verso il pannello della finestra.
        CommandGroup(replacing: .appSettings) {
            VoceImpostazioni()
        }
        CommandGroup(before: .toolbar) {
            VociMenuVista(ricevitore: ricevitore)
        }
        CommandMenu("Video") {
            VociMenuVideo(ricevitore: ricevitore, riprese: riprese)
        }
        CommandGroup(replacing: .help) {
            VociMenuAiuto()
        }
    }
}

// MARK: - Richieste alla finestra principale

/// Quello che i menu (barra dei menu, icona vicino all'orologio, voci dentro la finestra) chiedono alla finestra
/// principale: aprire il pannello «Impostazioni» su una pagina, mostrare il foglio di un aggiornamento.
/// La finestra le prende appena compare, o subito se è già aperta, e le azzera (ContenutoPrincipale).
@Observable
@MainActor
final class RichiesteFinestra {
    static let condivise = RichiesteFinestra()

    /// Il pannello da aprire: `.some(nil)` per l'elenco, `.some(pagina)` per una pagina; nil se non c'è niente da fare.
    var impostazioni: PaginaImpostazioni?? = nil
    /// «Verifica aggiornamenti…» ha trovato una versione nuova: il foglio «Aggiornamento disponibile».
    var aggiornamento: ControlloAggiornamenti.Versione?
}

/// «Impostazioni…» (⌘,) da qualsiasi parte: porta davanti la finestra principale e apre il pannello, sull'elenco o
/// su una pagina (per esempio «Microfono» da «Installa…»).
@MainActor
func apriImpostazioniWebcamLR(_ pagina: PaginaImpostazioni? = nil, apri: OpenWindowAction) {
    NSApp.activate(ignoringOtherApps: true)
    apri(id: WebcamLRMacApp.idPrincipale)
    RichiesteFinestra.condivise.impostazioni = .some(pagina)
}

/// «Verifica aggiornamenti…» (M18): legge subito il file del sito e risponde sempre. Una versione nuova apre il foglio
/// di sempre nella finestra principale; altrimenti un avviso di macOS dice che è l'ultima o che non si è potuto
/// controllare, e cosa fare.
@MainActor
func verificaAggiornamenti(apri: OpenWindowAction) async {
    switch await ControlloAggiornamenti.condiviso.verificaOra() {
    case .nuova(let versione):
        NSApp.activate(ignoringOtherApps: true)
        apri(id: WebcamLRMacApp.idPrincipale)
        RichiesteFinestra.condivise.aggiornamento = versione
    case .aggiornata:
        let versione = "\(ControlloAggiornamenti.versioneApp) (\(ControlloAggiornamenti.buildApp))"
        mostraAvvisoAggiornamenti(String(localized: "WebcamLR è aggiornata"),
                                  dettaglio: String(localized: "Hai già l'ultima versione: \(versione)."))
    case .nonRaggiungibile:
        mostraAvvisoAggiornamenti(String(localized: "Non riesco a controllare gli aggiornamenti"),
                                  dettaglio: String(localized: "Controlla la connessione a Internet e riprova."))
    }
}

/// Un avviso di macOS con il solo «OK» (messo da macOS, nella lingua del Mac).
@MainActor
private func mostraAvvisoAggiornamenti(_ frase: String, dettaglio: String) {
    let avviso = NSAlert()
    avviso.alertStyle = .informational
    avviso.messageText = frase
    avviso.informativeText = dettaglio
    NSApp.activate(ignoringOtherApps: true)
    avviso.runModal()
}

// MARK: - Menu WebcamLR

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

/// «Verifica aggiornamenti…» (M18), subito sotto «Informazioni su WebcamLR», come nelle app del Mac.
private struct VoceVerificaAggiornamenti: View {
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Button("Verifica aggiornamenti…") {
            let apri = apriFinestra
            Task { @MainActor in await verificaAggiornamenti(apri: apri) }
        }
    }
}

/// «Impostazioni…» ⌘,: il pannello «Impostazioni» della finestra principale, non una finestra a parte.
private struct VoceImpostazioni: View {
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Button("Impostazioni…") { apriImpostazioniWebcamLR(apri: apriFinestra) }
            .keyboardShortcut(",")
    }
}

// MARK: - Menu Aiuto

/// Il menu Aiuto: le stesse pagine del pulsante «Aiuto» della finestra, nella finestra «App e assistenza».
private struct VociMenuAiuto: View {
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Button("Guida di WebcamLR") { apriFinestraApp(.guida, apri: apriFinestra) }
            .keyboardShortcut("?", modifiers: .command)
        Button("Domande frequenti") { apriFinestraApp(.domande, apri: apriFinestra) }
        Button("Il telefono non trova il Mac?") { apriDomandaFrequente("non-trova", apri: apriFinestra) }
        Divider()
        Button("Segnala un bug…") { apriFinestraApp(.segnala, apri: apriFinestra) }
    }
}

// MARK: - Menu Video

/// Le voci sono una vista: seguono lo stato del ricevitore (grigie senza telefono, «Registra» o «Ferma la
/// registrazione», l'obiettivo spuntato). Fanno quello che fanno i pulsanti e i tasti della finestra, con le stesse
/// domande (cambiare obiettivo mentre registri, «Scollega» in onda).
private struct VociMenuVideo: View {
    let ricevitore: Ricevitore
    let riprese: Riprese
    @AppStorage(Preferenze.vistaPulita) private var vistaPulita = false
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        // In gruppi: così ogni blocco resta sotto i 10 elementi.
        Group {
            // ⌘T come in Photo Booth.
            Button("Foto") { riprese.scattaFoto() }
                .keyboardShortcut("t")
                .disabled(ricevitore.telefono == nil)
            // Con il timer partito lo annulla, anche se intanto il telefono se n'è andato.
            Button(riprese.contoAllaRovescia == nil ? "Foto tra 3 secondi" : "Annulla il timer") { riprese.scattaConTimer() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(ricevitore.telefono == nil && riprese.contoAllaRovescia == nil)
            // ⌘C: nei campi di testo vince «Copia» del menu Composizione (viene prima); nella finestra principale lo
            // prende MonitorTastiera.
            Button("Copia il fotogramma") { riprese.copiaFotogramma() }
                .keyboardShortcut("c")
                .disabled(ricevitore.telefono == nil)
            Button(riprese.registra ? "Ferma la registrazione" : "Registra") { riprese.alternaRegistrazione() }
                .keyboardShortcut("r")
                .disabled(!riprese.registra && !ricevitore.telefonoAttivo)
        }
        Divider()
        Group {
            Toggle("Specchia", isOn: Binding(get: { specchioUsabile && ricevitore.specchiato },
                                             set: { _ in ricevitore.alternaSpecchio() }))
                .disabled(!specchioUsabile)
            Menu("Sfondo") {
                VociMenuSfondo(ricevitore: ricevitore) { apriFinestraApp(.pro, apri: apriFinestra) }
            }
            .disabled(!sfondoUsabile)
        }
        Divider()
        Group {
            menuObiettivo
            Button("Zoom avanti") { ricevitore.cambiaZoom(di: Ricevitore.passoZoom) }
                .keyboardShortcut("+", modifiers: [])
                .disabled(!zoomUsabile)
            Button("Zoom indietro") { ricevitore.cambiaZoom(di: -Ricevitore.passoZoom) }
                .keyboardShortcut("-", modifiers: [])
                .disabled(!zoomUsabile)
            Button("Messa a fuoco automatica") { ricevitore.fuocoAutomatico() }
                .keyboardShortcut("f", modifiers: [])
                .disabled(!ricevitore.telefonoAttivo)
        }
        Divider()
        Group {
            Toggle("Vista pulita", isOn: $vistaPulita)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            // Passa dalla domanda di sempre (in onda o mentre registri chiede prima).
            Button("Scollega…") { ricevitore.chiediEScollega() }
                .disabled(ricevitore.telefono == nil)
        }
    }

    /// Le stesse regole dei pulsanti sotto il video: telefono collegato che lo sa fare, fotocamera frontale.
    private var specchioUsabile: Bool {
        ricevitore.telefonoAttivo && ricevitore.capacita != nil && ricevitore.specchioDisponibile
            && !ricevitore.soloFrontaleBloccati
    }

    private var sfondoUsabile: Bool {
        ricevitore.telefonoAttivo && ricevitore.capacita != nil && ricevitore.sfondoDisponibile
            && !ricevitore.soloFrontaleBloccati
    }

    private var zoomUsabile: Bool {
        ricevitore.telefonoAttivo && (ricevitore.capacita?.zoomMassimo ?? 1) > 1
    }

    /// Gli obiettivi del telefono nell'ordine in cui li elenca, con i tasti 1–4; spuntato quello in uso.
    private var menuObiettivo: some View {
        let elenco = ricevitore.telefonoAttivo ? Array((ricevitore.capacita?.obiettivi ?? []).prefix(4)) : []
        let attuale = ricevitore.controlli.obiettivo ?? ricevitore.statoTelefono?.obiettivo
        return Menu("Obiettivo") {
            ForEach(Array(elenco.enumerated()), id: \.offset) { indice, obiettivo in
                Toggle(Ricevitore.nome(obiettivo: obiettivo), isOn: Binding(
                    get: { obiettivo == attuale },
                    set: { _ in scegli(obiettivo, attuale: attuale) }))
                    .keyboardShortcut(KeyEquivalent(Character("\(indice + 1)")), modifiers: [])
            }
        }
        .disabled(elenco.isEmpty)
    }

    /// Come il tasto: l'obiettivo di adesso non cambia niente; un altro, mentre registri, chiede prima (punto 7).
    /// La domanda dopo il clic, fuori dall'aggiornamento del menu.
    private func scegli(_ obiettivo: String, attuale: String?) {
        guard obiettivo != attuale else { return }
        Task { @MainActor in
            guard ricevitore.confermaSeFerma(.obiettivo) else { return }
            ricevitore.scegliObiettivo(obiettivo)
        }
    }
}

// MARK: - Clic destro sul video (M19)

/// Il clic destro sul video della finestra principale: Foto, Copia il fotogramma, Registra, Vista pulita e Riempi
/// l'inquadratura. Le stesse voci del menu Video, con le stesse regole.
struct VociContestualiVideo: View {
    let ricevitore: Ricevitore
    let riprese: Riprese
    @AppStorage(Preferenze.vistaPulita) private var vistaPulita = false
    @AppStorage(Preferenze.riempi) private var riempi = false

    var body: some View {
        Button("Foto") { riprese.scattaFoto() }
            .disabled(ricevitore.telefono == nil)
        Button("Copia il fotogramma") { riprese.copiaFotogramma() }
            .disabled(ricevitore.telefono == nil)
        Button(riprese.registra ? "Ferma la registrazione" : "Registra") { riprese.alternaRegistrazione() }
            .disabled(!riprese.registra && !ricevitore.telefonoAttivo)
        Divider()
        Toggle("Vista pulita", isOn: $vistaPulita)
        Toggle("Riempi l'inquadratura", isOn: $riempi)
    }
}
