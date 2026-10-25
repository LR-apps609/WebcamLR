import AVFoundation
import Observation
import Stile
import SwiftUI

@main
struct WebcamLRMacApp: App {
    static let idPrincipale = "principale"

    @NSApplicationDelegateAdaptor(DelegatoApp.self) private var delegato

    @State private var ricevitore: Ricevitore
    @State private var fotocamera: AttivazioneFotocamera
    @State private var riprese: Riprese

    init() {
        let ricevitore = Ricevitore()
        let fotocamera = AttivazioneFotocamera()
        _ricevitore = State(initialValue: ricevitore)
        _fotocamera = State(initialValue: fotocamera)
        // Foto e registrazioni dal telefono scelto per la webcam (P21).
        let riprese = Riprese(schermo: { ricevitore.schermo })
        _riprese = State(initialValue: riprese)
        // P21: se l'utente sceglie un altro telefono, la registrazione in corso si ferma e si salva.
        ricevitore.primaDelCambioTelefono = { [weak riprese] in riprese?.telefonoCambiato() }
        // Il telefono che si registrava se n'è andato (non tornato in 15 secondi, o scollegato): si chiude e si salva.
        ricevitore.primaDiDimenticareLoScelto = { [weak riprese] in
            riprese?.fermaRegistrazione(avvisoSalvata: String(localized: "Telefono non più collegato: registrazione salvata in Filmati › WebcamLR"))
        }
        // ⌘Q durante una registrazione: prima si chiude il file, altrimenti il .mov resta senza fine e non si apre.
        DelegatoApp.primaDiUscire = { [weak riprese] fatto in
            guard let riprese, riprese.registra else { return false }
            Self.aspettaFineRegistrazione(riprese, fatto)
            riprese.fermaRegistrazione()
            return true
        }
        Caratteri.registra()
        Notifiche.condivise.prepara()
        // Visibile in rete da subito, prima di qualsiasi finestra: anche quando WebcamLR si apre
        // all'avvio del Mac senza finestre, o con la finestra principale chiusa l'ultima volta.
        // Così il QR code è pronto appena compare.
        ricevitore.avvia()
        // Microfono del telefono (P20): lo stato del driver si controlla da subito, anche a finestra chiusa.
        ricevitore.avviaMicrofono()
        // Una versione nuova sul sito (versione.json): all'avvio e ogni 6 ore, in silenzio se non c'è rete.
        ControlloAggiornamenti.condiviso.avvia()
        // Webcam virtuale collegata da subito (P19), non quando compare la finestra: le app di chiamata
        // ricevono il video anche se la finestra principale non si è mai aperta o è stata chiusa.
        if fotocamera.disponibile {
            Self.collegaWebcamVirtuale(ricevitore)
        }
        // Si riparte sempre con la finestra completa: la vista pulita non resta da una volta all'altra.
        UserDefaults.standard.set(false, forKey: Preferenze.vistaPulita)
        // Lo specchio solo dell'anteprima non c'è più (1.14): «Specchia» è uno solo, del telefono.
        Preferenze.vecchieSpecchio.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    var body: some Scene {
        // Una finestra sola: «Apri WebcamLR» la riporta davanti invece di aprirne un'altra.
        Window("WebcamLR", id: Self.idPrincipale) {
            ContenutoPrincipale(ricevitore: ricevitore, fotocamera: fotocamera, riprese: riprese)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            ComandiWebcamLR()
        }

        Window("Finestra mini", id: FinestraMini.id) {
            FinestraMini(ricevitore: ricevitore)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 400, height: 225)
        .defaultPosition(.topTrailing)

        // Gobbo (pacchetto funzioni): dal pulsante «Gobbo» nel pannello degli effetti.
        Window("Gobbo", id: FinestraGobbo.id) {
            FinestraGobbo(ricevitore: ricevitore)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 520, height: 640)

        // Sezione App (0.12): dal pulsante «Aiuto» della finestra principale.
        Window("App e assistenza", id: FinestraApp.id) {
            FinestraApp(ricevitore: ricevitore)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 600)

        Settings {
            Impostazioni(ricevitore: ricevitore)
        }
    }

    /// `Riprese.fermaRegistrazione` non ha un completamento, ma a file chiuso (salvato o no) mostra sempre un
    /// `avviso`: è quello il segnale. Un avviso che sparisce da solo (diventa nil) non conta: si aspetta il prossimo.
    @MainActor
    private static func aspettaFineRegistrazione(_ riprese: Riprese, _ fatto: @escaping @MainActor () -> Void) {
        withObservationTracking {
            _ = riprese.avviso
        } onChange: {
            Task { @MainActor in
                if riprese.avviso == nil {
                    aspettaFineRegistrazione(riprese, fatto)
                } else {
                    fatto()
                }
            }
        }
    }

    /// Per mettere le immagini nella webcam virtuale serve il permesso della fotocamera. Si chiede una volta
    /// sola, all'avvio, e solo se macOS non ha ancora una risposta: se è negato non si richiede (macOS non
    /// mostrerebbe comunque la domanda) e il collegamento parte lo stesso, perché «IN ONDA» funziona anche così.
    /// Le immagini riprendono da sole quando il permesso c'è: UscitaWebcam riprova ogni 2 secondi.
    private static func collegaWebcamVirtuale(_ ricevitore: Ricevitore) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            Task { @MainActor in
                _ = await AVCaptureDevice.requestAccess(for: .video)
                ricevitore.collegaWebcamVirtuale()
            }
        default:
            ricevitore.collegaWebcamVirtuale()
        }
    }
}

/// Senza icona nella barra in alto: WebcamLR resta aperta anche a finestra chiusa (il telefono la ritrova
/// e il QR è pronto) e un clic sull'icona nel Dock riapre la finestra.
final class DelegatoApp: NSObject, NSApplicationDelegate {
    /// Prima di uscire (la imposta WebcamLRMacApp): chiude la registrazione in corso e chiama la funzione
    /// a file chiuso. Falso se non c'è niente da chiudere. Statica: l'adattatore del delegato non è ancora
    /// pronto nell'`init` dell'app.
    @MainActor static var primaDiUscire: (@MainActor (@escaping @MainActor () -> Void) -> Bool)?
    /// La risposta a `applicationShouldTerminate` è già partita (file chiuso o tempo scaduto): una volta sola.
    @MainActor private var uscitaRisposta = true

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let primaDiUscire = Self.primaDiUscire else { return .terminateNow }
            uscitaRisposta = false
            let rispondi: @MainActor () -> Void = { [weak self] in
                guard let self, !self.uscitaRisposta else { return }
                self.uscitaRisposta = true
                sender.reply(toApplicationShouldTerminate: true)
            }
            guard primaDiUscire(rispondi) else {
                uscitaRisposta = true
                return .terminateNow
            }
            // Mai bloccati: se il file non si chiude in 10 secondi si esce lo stesso.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                rispondi()
            }
            return .terminateLater
        }
    }

    /// Conta la finestra principale, non le altre: con la finestra mini (sempre in primo piano) o le
    /// Impostazioni aperte `hasVisibleWindows` è vero e il clic sul Dock prima non riapriva niente.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            let principaleVisibile = sender.windows.contains { finestra in
                finestra.isVisible && finestra.identifier?.rawValue.hasPrefix(WebcamLRMacApp.idPrincipale) == true
            }
            // Se la finestra è già aperta, openWindow la porta solo davanti: nessun doppione.
            if !principaleVisibile {
                Self.apriFinestraPrincipale(sender)
            }
        }
        return true
    }

    /// Riapre la finestra principale anche se in questo avvio non è mai comparsa (WebcamLR aperta all'accesso
    /// al Mac, o con la finestra chiusa l'ultima volta). Di solito c'è già `apriFinestraPrincipale`: la imposta
    /// il menu dell'app appena costruito (ComandiMenu.swift), poi la finestra stessa. Se non ci fosse ancora:
    /// prima la finestra di AppKit ancora in memoria (chiusa o nel Dock), poi la voce «WebcamLR» del menu Finestra,
    /// che SwiftUI crea per ogni `Window` e che apre la finestra come openWindow.
    @MainActor
    private static func apriFinestraPrincipale(_ app: NSApplication) {
        if let apri = Notifiche.condivise.apriFinestraPrincipale {
            apri()
            return
        }
        if let finestra = app.windows.first(where: { $0.identifier?.rawValue.hasPrefix(WebcamLRMacApp.idPrincipale) == true }) {
            if finestra.isMiniaturized { finestra.deminiaturize(nil) }
            finestra.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
            return
        }
        if let voce = app.windowsMenu?.items.first(where: { $0.title == "WebcamLR" && $0.action != nil }),
           let azione = voce.action {
            _ = app.sendAction(azione, to: voce.target, from: voce)
        }
    }
}
