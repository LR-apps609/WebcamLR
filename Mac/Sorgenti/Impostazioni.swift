import AppKit
import Combine
import ServiceManagement
import Stile
import SwiftUI
import UniformTypeIdentifiers

// Le pagine del pannello «Impostazioni» che prima stavano nella finestra a parte di ⌘, (funzione 35). Dal passo 8 le
// impostazioni sono in un posto solo, il pannello della finestra principale (PannelloImpostazioni.swift):
// - «Avvio e notifiche»: apri all'avvio del Mac, notifiche (l'icona nella barra dei menu sta in «Schermo»);
// - «Microfono»: sotto l'interruttore, l'installazione e la rimozione del microfono del telefono;
// - «Schermata di attesa» (WebcamLR Pro, AttesaWebcam.swift);
// - «Sicurezza»: il codice di sicurezza del Mac e i telefoni fidati (dalla 0.10).
// Il Wi-Fi diretto è in «Qualità e collegamento», con la sua spiegazione.

// MARK: - Avvio e notifiche

struct PaginaAvvio: View {
    @AppStorage(Preferenze.notifiche) private var notifiche = true
    /// Lo stato vero dell'elemento di login, riletto da macOS quando la pagina compare e quando l'app torna attiva
    /// (non nell'inizializzazione della vista, che SwiftUI ripete spesso: è una domanda al sistema).
    @State private var statoAvvio: SMAppService.Status = .notRegistered
    @State private var erroreAvvio: String?
    @State private var notificheNegate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            Toggle(isOn: Binding(
                get: { statoAvvio == .enabled || statoAvvio == .requiresApproval },
                set: { cambiaAvvio($0) })) {
                Text("Apri WebcamLR all'avvio del Mac")
                    .font(.stile(.corpo, .corpoEvidente))
            }
            .toggleStyle(.switch)
            testoAvvio
        }
        Divider().overlay(Tema.lineaTenue)
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            Toggle(isOn: $notifiche) {
                Text("Mostra le notifiche")
                    .font(.stile(.corpo, .corpoEvidente))
            }
            .toggleStyle(.switch)
            Nota(testo: String(localized: "Telefono collegato o perso e batteria bassa, solo quando WebcamLR non è in primo piano; «Registrazione salvata» sempre."))
            if notifiche && notificheNegate {
                HStack(alignment: .firstTextBaseline, spacing: Spazi.stretto) {
                    NotaAvviso(testo: String(localized: "macOS le blocca: attivale in Impostazioni di Sistema › Notifiche."))
                    Spacer(minLength: Spazi.minimo)
                    Button("Apri") { apriImpostazioniNotifiche() }
                        .buttonStyle(StileSecondario())
                }
            }
        }
        .onAppear { aggiorna() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Al ritorno dalle Impostazioni di Sistema lo stato può essere cambiato.
            aggiorna()
        }
        .onChange(of: notifiche) {
            if notifiche { Notifiche.condivise.chiediPermesso() }
            aggiorna()
        }
    }

    @ViewBuilder private var testoAvvio: some View {
        switch statoAvvio {
        case .enabled:
            Nota(testo: String(localized: "WebcamLR si apre da sola quando accedi al Mac, pronta per il telefono."))
        case .requiresApproval:
            HStack(alignment: .firstTextBaseline, spacing: Spazi.stretto) {
                NotaAvviso(testo: String(localized: "Da approvare in Impostazioni di Sistema › Generali › Elementi login."))
                Spacer(minLength: Spazi.minimo)
                Button("Apri") { SMAppService.openSystemSettingsLoginItems() }
                    .buttonStyle(StileSecondario())
            }
        case .notFound:
            NotaAvviso(testo: String(localized: "macOS non trova l'app: spostala in Applicazioni e riprova."))
        default:
            Nota(testo: String(localized: "Spento: WebcamLR si apre solo quando la scegli tu."))
        }
        if let erroreAvvio {
            NotaAvviso(testo: erroreAvvio)
        }
    }

    /// SMAppService.mainApp funziona anche nella sandbox e con l'Apple ID gratuito.
    private func cambiaAvvio(_ attivo: Bool) {
        do {
            if attivo {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            erroreAvvio = nil
        } catch {
            erroreAvvio = attivo
                ? String(localized: "Non sono riuscito ad attivare l'avvio automatico: riprova, oppure aggiungi WebcamLR in Impostazioni di Sistema › Generali › Elementi login.")
                : String(localized: "Non sono riuscito a spegnere l'avvio automatico: riprova, oppure togli WebcamLR in Impostazioni di Sistema › Generali › Elementi login.")
        }
        statoAvvio = SMAppService.mainApp.status
    }

    private func aggiorna() {
        statoAvvio = SMAppService.mainApp.status
        Task { @MainActor in
            notificheNegate = await Notifiche.condivise.negate()
        }
    }

    private func apriImpostazioniNotifiche() {
        if let indirizzo = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(indirizzo)
        }
    }
}

// MARK: - Microfono del telefono (P20)

/// Stato del microfono virtuale, con «Installa…» se manca e «Rimuovi il microfono…» se c'è (pagina «Microfono»).
/// L'app è nel sandbox e non può scrivere in /Library: installa il pacchetto (o lo script) con la password del Mac;
/// toglie il LaunchDaemon di rimozione, che risponde solo a questa app (Mac/Microfono/Aiuto/main.c).
struct SezioneInstallazioneMicrofono: View {
    let ricevitore: Ricevitore
    /// Microfono del telefono: la versione installata (nil se non si sa), la rimozione in corso e il suo esito.
    @State private var versioneMicrofono: String?
    @State private var confermaRimozione = false
    @State private var rimozioneInCorso = false
    @State private var esitoMicrofono: String?
    @State private var esitoMicrofonoAvviso = false
    /// Il microfono non si toglie dall'app (installato prima del servizio di rimozione): si offre lo script.
    @State private var serveScriptRimozione = false

    private var microfonoInstallato: Bool {
        if case .installato = ricevitore.installazioneMicrofono { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            if microfonoInstallato {
                Label {
                    if let versioneMicrofono {
                        Text("Microfono installato · versione \(versioneMicrofono)")
                    } else {
                        Text("Microfono installato")
                    }
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Tema.accento)
                }
                .font(.stile(.corpo, .corpoEvidente))
                Nota(testo: String(localized: "Zoom, Meet, Teams e le altre app vedono «WebcamLR (microphone)». Se non ti serve più, toglilo da qui: l'audio del Mac si ferma per un attimo."))
                HStack(spacing: Spazi.stretto) {
                    if rimozioneInCorso {
                        ProgressView()
                            .controlSize(.small)
                        Text("Rimozione in corso…")
                            .font(.stile(.nota))
                            .foregroundStyle(Tema.testoSecondario)
                    }
                    Spacer(minLength: Spazi.minimo)
                    Button("Rimuovi il microfono…") { confermaRimozione = true }
                        .buttonStyle(StileDistruttivo())
                        .disabled(rimozioneInCorso)
                }
            } else {
                Label("Microfono non installato", systemImage: "mic.slash")
                    .font(.stile(.corpo, .corpoEvidente))
                Nota(testo: String(localized: "Per usare il microfono del telefono nelle app di chiamata serve «WebcamLR (microphone)». Si installa una volta, con la password del Mac: scegli «WebcamLR Microfono.pkg» (nel dmg) oppure «Installa microfono.command» (cartella Strumenti)."))
                HStack {
                    Spacer()
                    Button("Installa…") { apriInstallazione(rimozione: false) }
                        .buttonStyle(StileSecondario())
                }
            }
            if let esitoMicrofono {
                if esitoMicrofonoAvviso {
                    NotaAvviso(testo: esitoMicrofono)
                } else {
                    Nota(testo: esitoMicrofono)
                }
            }
            if serveScriptRimozione {
                HStack {
                    Spacer()
                    Button("Apri «Rimuovi microfono.command»…") { apriInstallazione(rimozione: true) }
                        .buttonStyle(StileSecondario())
                }
            }
        }
        .task(id: microfonoInstallato) {
            guard microfonoInstallato else {
                versioneMicrofono = nil
                return
            }
            versioneMicrofono = await Task.detached(priority: .utility) { MicrofonoTelefono.leggiVersioneInstallata() }.value
        }
        .confirmationDialog("Rimuovere il microfono di WebcamLR?", isPresented: $confermaRimozione) {
            Button("Rimuovi", role: .destructive) { rimuoviMicrofono() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("«WebcamLR (microphone)» sparisce da tutte le app e l'audio del Mac si ferma per un attimo. Potrai reinstallarlo quando vuoi.")
        }
    }

    private func rimuoviMicrofono() {
        rimozioneInCorso = true
        esitoMicrofono = nil
        serveScriptRimozione = false
        Task { @MainActor in
            let esito = await Task.detached(priority: .userInitiated) { MicrofonoTelefono.disinstalla() }.value
            rimozioneInCorso = false
            switch esito {
            case .riuscita:
                esitoMicrofonoAvviso = false
                esitoMicrofono = String(localized: "Microfono rimosso. Se un'app di chiamata lo mostra ancora, chiudila e riaprila.")
                versioneMicrofono = nil
            case .serveLoScript:
                esitoMicrofonoAvviso = true
                esitoMicrofono = String(localized: "Questo microfono non si può togliere dall'app (è stato installato da una versione precedente): apri «Rimuovi microfono.command» nella cartella Strumenti e inserisci la password del Mac.")
                serveScriptRimozione = true
            case .nonRiuscita(let dettaglio):
                esitoMicrofonoAvviso = true
                esitoMicrofono = String(localized: "Non sono riuscito a togliere tutto (\(dettaglio)). Prova con «Rimuovi microfono.command» nella cartella Strumenti.")
                serveScriptRimozione = true
            }
        }
    }

    /// Fa scegliere il pacchetto o lo script e lo apre macOS (Installer o Terminale, che chiedono la password).
    /// Il file scelto nel pannello è l'unico che il sandbox lascia aprire.
    private func apriInstallazione(rimozione: Bool) {
        let pannello = NSOpenPanel()
        pannello.allowsMultipleSelection = false
        pannello.canChooseDirectories = false
        var tipi: [UTType] = []
        if let comando = UTType(filenameExtension: "command") { tipi.append(comando) }
        if !rimozione, let pacchetto = UTType(filenameExtension: "pkg") { tipi.append(pacchetto) }
        pannello.allowedContentTypes = tipi
        pannello.message = rimozione
            ? String(localized: "Scegli «Rimuovi microfono.command» nella cartella Strumenti di WebcamLR")
            : String(localized: "Scegli «WebcamLR Microfono.pkg» (nel dmg) oppure «Installa microfono.command» (cartella Strumenti)")
        guard pannello.runModal() == .OK, let file = pannello.url else { return }
        if !NSWorkspace.shared.open(file) {
            esitoMicrofonoAvviso = true
            esitoMicrofono = String(localized: "macOS non ha aperto il file: aprilo con un doppio clic dal Finder.")
        }
    }
}

// MARK: - Schermata di attesa (WebcamLR Pro)

/// Cosa vedono le app di chiamata (e la finestra) quando il video del telefono non c'è. Senza WebcamLR Pro sbloccato
/// sul telefono vale sempre la schermata di WebcamLR.
struct PaginaSchermataAttesa: View {
    let ricevitore: Ricevitore
    /// La schermata di attesa scelta (vale solo con Pro) e l'anteprima dell'immagine personale.
    @State private var stileAttesa = AttesaWebcam.condivisa.sceltaUtente
    @State private var immaginePersonale = AttesaWebcam.condivisa.immaginePersonale
    @State private var erroreImmagine: String?

    private var pro: Bool { ricevitore.proAttivo }

    var body: some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            Picker(selection: Binding(get: { pro ? stileAttesa : .webcamLR }, set: { scegliStile($0) })) {
                Text("WebcamLR").tag(StileAttesa.webcamLR)
                Text("Schermo nero").tag(StileAttesa.nero)
                Text("Immagine personale…").tag(StileAttesa.immagine)
                Text("Ultima immagine sfocata").tag(StileAttesa.sfocata)
            } label: {
                HStack(spacing: Spazi.stretto) {
                    Text("Schermata di attesa")
                        .font(.stile(.corpo, .corpoEvidente))
                    SegnoPro()
                }
            }
            .disabled(!pro)
            if pro && stileAttesa == .immagine {
                rigaImmagine
            }
            if pro {
                Nota(testo: String(localized: "Quello che vedono Zoom e le altre app quando il video del telefono non c'è: telefono non collegato, collegamento interrotto, pausa. Con WebcamLR per Mac chiusa le app vedono sempre la schermata di WebcamLR."))
            } else {
                Label("Sblocca WebcamLR Pro sull'iPhone", systemImage: "lock")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
            }
            if let erroreImmagine {
                NotaAvviso(testo: erroreImmagine)
            }
        }
    }

    /// L'anteprima dell'immagine personale, «Scegli l'immagine…» e il trascinamento.
    private var rigaImmagine: some View {
        HStack(spacing: Spazi.piccolo) {
            Group {
                if let immaginePersonale {
                    Image(decorative: immaginePersonale, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Tema.pannelloScuro
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: Raggi.piccolo))
            .overlay(RoundedRectangle(cornerRadius: Raggi.piccolo).stroke(Tema.linea))
            VStack(alignment: .leading, spacing: Spazi.minimo) {
                Button("Scegli l'immagine…") { scegliImmagine() }
                    .buttonStyle(StileSecondario())
                Nota(testo: String(localized: "Oppure trascinala qui. Riempie tutto il riquadro: i bordi in più restano fuori."))
            }
        }
        // Il trascinamento funziona anche senza il permesso di aprire i file scelti (sandbox): arriva una copia.
        .onDrop(of: [UTType.image], isTargeted: nil) { fornitori in
            guard let fornitore = fornitori.first else { return false }
            fornitore.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { dati, _ in
                guard let dati else { return }
                Task { @MainActor in
                    if usaImmagine(dati) { applicaStile(.immagine) }
                }
            }
            return true
        }
    }

    /// «Immagine personale…» senza un'immagine già scelta apre subito la scelta del file; se si annulla, resta lo stile di prima.
    private func scegliStile(_ nuovo: StileAttesa) {
        guard pro else { return }
        if nuovo == .immagine && immaginePersonale == nil {
            // Fuori dall'aggiornamento del menu: il pannello è modale.
            Task { @MainActor in
                if scegliImmagine() { applicaStile(.immagine) }
            }
            return
        }
        applicaStile(nuovo)
    }

    private func applicaStile(_ nuovo: StileAttesa) {
        stileAttesa = nuovo
        AttesaWebcam.condivisa.scegli(nuovo)
    }

    /// Il pannello per scegliere un'immagine (JPEG, PNG, HEIC…). Vero se l'immagine è stata presa.
    @discardableResult
    private func scegliImmagine() -> Bool {
        let pannello = NSOpenPanel()
        pannello.allowedContentTypes = [.image]
        pannello.allowsMultipleSelection = false
        pannello.canChooseDirectories = false
        pannello.message = String(localized: "L'immagine da mostrare nella webcam quando il video del telefono non c'è")
        guard pannello.runModal() == .OK, let file = pannello.url else { return false }
        guard let dati = try? Data(contentsOf: file) else {
            erroreImmagine = String(localized: "Non riesco a leggere questo file: prova a trascinarlo qui.")
            return false
        }
        return usaImmagine(dati)
    }

    /// Copia l'immagine nel contenitore dell'app e la usa subito.
    private func usaImmagine(_ dati: Data) -> Bool {
        guard AttesaWebcam.condivisa.salvaImmagine(dati) else {
            erroreImmagine = String(localized: "Questa immagine non si apre: prova con un file JPEG, PNG o HEIC.")
            return false
        }
        erroreImmagine = nil
        immaginePersonale = AttesaWebcam.condivisa.immaginePersonale
        return true
    }
}

// MARK: - Sicurezza

/// Collegamento sicuro (0.10): come la scheda «Sicurezza» di Windows. Il codice di sicurezza di questo Mac e i telefoni
/// fidati, con «Rimuovi» (che chiede prima). Gli stessi telefoni del foglio «Telefoni conosciuti».
struct PaginaSicurezza: View {
    let ricevitore: Ricevitore

    var body: some View {
        Nota(testo: String(localized: "Il video e i comandi viaggiano cifrati. I telefoni nuovi si collegano solo con il QR code di questo Mac o dopo che li confermi con il codice di conferma."))
        VStack(alignment: .leading, spacing: Spazi.minimo) {
            Text("Codice di sicurezza di questo Mac")
                .font(.stile(.corpo, .corpoEvidente))
            Text(ricevitore.improntaMac)
                .font(.stile(.numeri))
                .foregroundStyle(Tema.testoTenue)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        Divider().overlay(Tema.lineaTenue)
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            Text("Telefoni fidati")
                .font(.stile(.corpo, .corpoEvidente))
            if ricevitore.telefoniFidati.isEmpty {
                Nota(testo: String(localized: "Nessun telefono fidato, per ora."))
            } else {
                ForEach(ricevitore.telefoniFidati) { telefono in
                    HStack(spacing: Spazi.stretto) {
                        Label(telefono.nome, systemImage: "iphone")
                            .lineLimit(1)
                        Spacer(minLength: Spazi.minimo)
                        Button("Rimuovi") { ricevitore.chiediERimuoviFidato(telefono) }
                            .buttonStyle(StileDistruttivo())
                            .accessibilityLabel("Rimuovi \(telefono.nome)")
                    }
                }
            }
            Nota(testo: String(localized: "Telefoni fidati: si collegano senza domande. Un telefono rimosso dovrà essere confermato di nuovo."))
        }
    }
}

// MARK: - Componenti

/// Una frase in ambra: qualcosa da sistemare, con cosa fare.
private struct NotaAvviso: View {
    let testo: String

    var body: some View {
        Text(testo)
            .font(.stile(.corpo))
            .foregroundStyle(Tema.ambra)
            .fixedSize(horizontal: false, vertical: true)
    }
}
