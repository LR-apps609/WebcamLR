import AppKit
import Combine
import ServiceManagement
import Stile
import SwiftUI

/// Impostazioni (⌘,, funzione 35): avvio al login, notifiche, specchia di serie;
/// dalla 0.10 anche la sicurezza: il codice di sicurezza del Mac e i telefoni fidati.
struct Impostazioni: View {
    let ricevitore: Ricevitore
    @AppStorage(Preferenze.notifiche) private var notifiche = true
    @AppStorage(Preferenze.specchiaDiSerie) private var specchiaDiSerie = false
    @AppStorage(Preferenze.specchia) private var specchia = false
    @AppStorage(Preferenze.wifiDiretto) private var wifiDiretto = false
    /// Lo stato vero dell'elemento di login, riletto da macOS quando la finestra compare e quando l'app torna attiva
    /// (non nell'inizializzazione della vista, che SwiftUI ripete spesso: è una domanda al sistema).
    @State private var statoAvvio: SMAppService.Status = .notRegistered
    @State private var erroreAvvio: String?
    @State private var notificheNegate = false

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

            Section("Anteprima") {
                Toggle("Specchia di serie", isOn: $specchiaDiSerie)
                Text("A ogni apertura l'anteprima parte specchiata, come in uno specchio. Vale solo qui sul Mac: le altre app ricevono il video dritto.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
            }

            Section("Collegamento") {
                Toggle("Wi-Fi diretto, anche senza router", isOn: $wifiDiretto)
                Text("Per collegare l'iPhone dove non c'è una rete in comune, come con AirDrop. Lascialo spento se non serve: tiene occupata la radio Wi-Fi e la latenza diventa meno stabile.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
            }

            sicurezza
        }
        .onChange(of: wifiDiretto) {
            ricevitore.riavviaAscolto()
        }
        .formStyle(.grouped)
        .tint(Tema.ciano)
        .frame(width: 480, height: 600)
        .preferredColorScheme(.dark)
        .onAppear { aggiorna() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Al ritorno dalle Impostazioni di Sistema lo stato può essere cambiato.
            aggiorna()
        }
        .onChange(of: specchiaDiSerie) {
            specchia = specchiaDiSerie
        }
        .onChange(of: notifiche) {
            if notifiche { Notifiche.condivise.chiediPermesso() }
            aggiorna()
        }
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
