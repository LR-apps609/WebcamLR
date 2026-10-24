import AppKit
import Combine
import ServiceManagement
import Stile
import SwiftUI

/// Impostazioni (⌘,, funzione 35): avvio al login, notifiche, specchia di serie.
struct Impostazioni: View {
    @AppStorage(Preferenze.notifiche) private var notifiche = true
    @AppStorage(Preferenze.specchiaDiSerie) private var specchiaDiSerie = false
    @AppStorage(Preferenze.specchia) private var specchia = false
    /// Lo stato vero dell'elemento di login, riletto da macOS ogni volta che serve.
    @State private var statoAvvio: SMAppService.Status = SMAppService.mainApp.status
    @State private var erroreAvvio: String?
    @State private var notificheNegate = false

    var body: some View {
        Form {
            Section {
                Toggle("Apri WebcamLR all'avvio del Mac", isOn: Binding(
                    get: { statoAvvio == .enabled || statoAvvio == .requiresApproval },
                    set: { cambiaAvvio($0) }))
                testoAvvio
            }

            Section {
                Toggle("Notifiche", isOn: $notifiche)
                Text("Telefono collegato o perso e batteria bassa, solo quando WebcamLR non è in primo piano; «registrazione salvata» sempre.")
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

            Section {
                Toggle("Specchia di serie", isOn: $specchiaDiSerie)
                Text("A ogni apertura l'anteprima parte specchiata, come in uno specchio. Vale solo qui sul Mac: le altre app ricevono il video dritto.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
            }
        }
        .formStyle(.grouped)
        .tint(Tema.ciano)
        .frame(width: 480, height: 440)
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

    @ViewBuilder private var testoAvvio: some View {
        switch statoAvvio {
        case .enabled:
            Text("WebcamLR si apre da sola quando accedi al Mac, pronta per l'iPhone.")
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
            erroreAvvio = error.localizedDescription
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
