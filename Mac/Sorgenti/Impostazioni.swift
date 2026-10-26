import AppKit
import Combine
import ServiceManagement
import Stile
import SwiftUI
import UniformTypeIdentifiers

/// Impostazioni (⌘,, funzione 35): avvio al login, notifiche, Wi-Fi diretto;
/// dalla 0.10 anche la sicurezza: il codice di sicurezza del Mac e i telefoni fidati;
/// con WebcamLR Pro la schermata di attesa della webcam (AttesaWebcam.swift);
/// il microfono del telefono: stato, versione, «Installa…» e «Rimuovi il microfono…» (Documenti/Microfono Mac.md).
@MainActor
struct Impostazioni: View {
    let ricevitore: Ricevitore
    @AppStorage(Preferenze.notifiche) private var notifiche = true
    @AppStorage(Preferenze.wifiDiretto) private var wifiDiretto = false
    /// Lo stato vero dell'elemento di login, riletto da macOS quando la finestra compare e quando l'app torna attiva
    /// (non nell'inizializzazione della vista, che SwiftUI ripete spesso: è una domanda al sistema).
    @State private var statoAvvio: SMAppService.Status = .notRegistered
    @State private var erroreAvvio: String?
    @State private var notificheNegate = false
    /// La schermata di attesa scelta (vale solo con Pro) e l'anteprima dell'immagine personale.
    @State private var stileAttesa = AttesaWebcam.condivisa.sceltaUtente
    @State private var immaginePersonale = AttesaWebcam.condivisa.immaginePersonale
    @State private var erroreImmagine: String?
    /// Microfono del telefono: la versione installata (nil se non si sa), la rimozione in corso e il suo esito.
    @State private var versioneMicrofono: String?
    @State private var confermaRimozione = false
    @State private var rimozioneInCorso = false
    @State private var esitoMicrofono: String?
    @State private var esitoMicrofonoAvviso = false
    /// Il microfono non si toglie dall'app (installato prima del servizio di rimozione): si offre lo script.
    @State private var serveScriptRimozione = false

    /// SwiftUI costruisce le Impostazioni già all'avvio dell'app (la scena `Settings`): da qui parte anche chi passa
    /// alla schermata di attesa lo stato dei telefoni. Chiamarlo più volte non raddoppia nulla.
    @MainActor
    init(ricevitore: Ricevitore) {
        self.ricevitore = ricevitore
        OsservatoreAttesa.condiviso.osserva(ricevitore)
    }

    var body: some View {
        Form {
            Section("Avvio") {
                Toggle("Apri WebcamLR all'avvio del Mac", isOn: Binding(
                    get: { statoAvvio == .enabled || statoAvvio == .requiresApproval },
                    set: { cambiaAvvio($0) }))
                testoAvvio
            }

            Section("Notifiche") {
                Toggle("Mostra le notifiche", isOn: $notifiche)
                Text("Telefono collegato o perso e batteria bassa, solo quando WebcamLR non è in primo piano; «Registrazione salvata» sempre.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
                if notifiche && notificheNegate {
                    HStack {
                        Text("macOS le blocca: attivale in Impostazioni di Sistema › Notifiche.")
                            .font(.callout)
                            .foregroundStyle(Tema.ambra)
                        Spacer()
                        Button("Apri") { apriImpostazioniNotifiche() }
                    }
                }
            }

            Section("Collegamento") {
                // L'ascolto si riapre qui, al clic, come nella colonna «Connessione»: con un `onChange` sul valore
                // l'interruttore della colonna, a Impostazioni aperte, lo riapriva due volte di fila.
                Toggle("Wi-Fi diretto, anche senza router", isOn: Binding(
                    get: { wifiDiretto },
                    set: { acceso in
                        wifiDiretto = acceso
                        ricevitore.riavviaAscolto()
                    }))
                Text("Per collegare l'iPhone dove non c'è una rete in comune, come con AirDrop. Lascialo spento se non serve: tiene occupata la radio Wi-Fi e la latenza diventa meno stabile.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
            }

            microfonoTelefono

            schermataAttesa

            sicurezza
        }
        .formStyle(.grouped)
        .tint(Tema.ciano)
        .frame(width: 480, height: 640)
        .preferredColorScheme(.dark)
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

    // MARK: - Microfono del telefono (P20)

    private var microfonoInstallato: Bool {
        if case .installato = ricevitore.installazioneMicrofono { return true }
        return false
    }

    /// Stato del microfono virtuale, con «Installa…» se manca e «Rimuovi il microfono…» se c'è.
    /// L'app è nel sandbox e non può scrivere in /Library: installa il pacchetto (o lo script) con la password del Mac;
    /// toglie il LaunchDaemon di rimozione, che risponde solo a questa app (Mac/Microfono/Aiuto/main.c).
    private var microfonoTelefono: some View {
        Section("Microfono del telefono") {
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
                Text("Zoom, Meet, Teams e le altre app vedono «WebcamLR (microfono)». Se non ti serve più, toglilo da qui: l'audio del Mac si ferma per un attimo.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
                HStack {
                    if rimozioneInCorso {
                        ProgressView()
                            .controlSize(.small)
                        Text("Rimozione in corso…")
                            .font(.callout)
                            .foregroundStyle(Tema.testoSecondario)
                    }
                    Spacer()
                    Button("Rimuovi il microfono…") { confermaRimozione = true }
                        .disabled(rimozioneInCorso)
                }
            } else {
                Label("Microfono non installato", systemImage: "mic.slash")
                Text("Per usare il microfono del telefono nelle app di chiamata serve «WebcamLR (microfono)». Si installa una volta, con la password del Mac: scegli «WebcamLR Microfono.pkg» (nel dmg) oppure «Installa microfono.command» (cartella Strumenti).")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
                HStack {
                    Spacer()
                    Button("Installa…") { apriInstallazione(rimozione: false) }
                }
            }
            if let esitoMicrofono {
                Text(esitoMicrofono)
                    .font(.callout)
                    .foregroundStyle(esitoMicrofonoAvviso ? Tema.ambra : Tema.testoSecondario)
            }
            if serveScriptRimozione {
                HStack {
                    Spacer()
                    Button("Apri «Rimuovi microfono.command»…") { apriInstallazione(rimozione: true) }
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
            Text("«WebcamLR (microfono)» sparisce da tutte le app e l'audio del Mac si ferma per un attimo. Potrai reinstallarlo quando vuoi.")
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

    // MARK: - Schermata di attesa (WebcamLR Pro)

    /// WebcamLR Pro sbloccato sul telefono: senza, vale sempre la schermata di WebcamLR.
    private var pro: Bool { ricevitore.proAttivo }

    /// Cosa vedono le app di chiamata (e la finestra) quando il video del telefono non c'è.
    private var schermataAttesa: some View {
        Section {
            Picker(selection: Binding(get: { pro ? stileAttesa : .webcamLR }, set: { scegliStile($0) })) {
                Text("WebcamLR").tag(StileAttesa.webcamLR)
                Text("Schermo nero").tag(StileAttesa.nero)
                Text("Immagine personale…").tag(StileAttesa.immagine)
                Text("Ultima immagine sfocata").tag(StileAttesa.sfocata)
            } label: {
                HStack(spacing: 6) {
                    Text("Schermata di attesa")
                    EtichettaPro()
                }
            }
            .disabled(!pro)
            if pro && stileAttesa == .immagine {
                rigaImmagine
            }
            if pro {
                Text("Quello che vedono Zoom e le altre app quando il video del telefono non c'è: telefono non collegato, collegamento interrotto, pausa. Con WebcamLR per Mac chiusa le app vedono sempre la schermata di WebcamLR.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
            } else {
                Label("Sblocca WebcamLR Pro sull'iPhone", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
            }
            if let erroreImmagine {
                Text(erroreImmagine)
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
            }
        }
    }

    /// L'anteprima dell'immagine personale, «Scegli l'immagine…» e il trascinamento.
    private var rigaImmagine: some View {
        HStack(spacing: 12) {
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
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Tema.linea))
            VStack(alignment: .leading, spacing: 4) {
                Button("Scegli l'immagine…") { scegliImmagine() }
                Text("Oppure trascinala qui. Riempie tutto il riquadro: i bordi in più restano fuori.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// Collegamento sicuro (0.10): come la scheda «Sicurezza» di Windows.
    private var sicurezza: some View {
        Section("Sicurezza") {
            Text("Il video e i comandi viaggiano cifrati. I telefoni nuovi si collegano solo con il QR code di questo Mac o dopo che li confermi con il codice di conferma.")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
            VStack(alignment: .leading, spacing: 4) {
                Text("Codice di sicurezza di questo Mac")
                Text(ricevitore.improntaMac)
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoTenue)
                    .textSelection(.enabled)
            }
            if ricevitore.telefoniFidati.isEmpty {
                Text("Nessun telefono fidato, per ora.")
                    .foregroundStyle(Tema.testoSecondario)
            } else {
                ForEach(ricevitore.telefoniFidati) { telefono in
                    HStack {
                        Label(telefono.nome, systemImage: "iphone")
                            .lineLimit(1)
                        Spacer()
                        Button("Rimuovi") { ricevitore.rimuoviFidato(telefono) }
                            .accessibilityLabel("Rimuovi \(telefono.nome)")
                    }
                }
            }
            Text("Telefoni fidati: si collegano senza domande. Un telefono rimosso dovrà essere confermato di nuovo.")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    @ViewBuilder private var testoAvvio: some View {
        switch statoAvvio {
        case .enabled:
            Text("WebcamLR si apre da sola quando accedi al Mac, pronta per il telefono.")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
        case .requiresApproval:
            HStack {
                Text("Da approvare in Impostazioni di Sistema › Generali › Elementi login.")
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
                Spacer()
                Button("Apri") { SMAppService.openSystemSettingsLoginItems() }
            }
        case .notFound:
            Text("macOS non trova l'app: spostala in Applicazioni e riprova.")
                .font(.callout)
                .foregroundStyle(Tema.ambra)
        default:
            Text("Spento: WebcamLR si apre solo quando la scegli tu.")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
        }
        if let erroreAvvio {
            Text(erroreAvvio)
                .font(.callout)
                .foregroundStyle(Tema.ambra)
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

/// «PRO» accanto a una funzione di WebcamLR Pro: piccolo, nell'accento salvia (mai corallo).
private struct EtichettaPro: View {
    var body: some View {
        Text("PRO")
            .font(.etichetta(11))
            .tracking(0.6)
            .foregroundStyle(Tema.fondo)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Tema.accento, in: Capsule())
            .accessibilityLabel("WebcamLR Pro")
    }
}
