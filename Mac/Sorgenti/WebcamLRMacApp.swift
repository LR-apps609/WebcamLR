import AVFoundation
import CoreServices
import Stile
import SwiftUI

@main
struct WebcamLRMacApp: App {
    static let idPrincipale = "principale"

    @NSApplicationDelegateAdaptor(DelegatoApp.self) private var delegato

    @State private var ricevitore: Ricevitore
    @State private var fotocamera: AttivazioneFotocamera
    @State private var riprese: Riprese
    /// L'icona nella barra dei menu (passo 6): accesa di serie.
    @AppStorage(Preferenze.iconaBarraMenu) private var iconaBarraMenu = true

    init() {
        // Prima di tutto il resto, che scrive già nelle preferenze: la vista di partenza (Essenziale o Completo).
        Preferenze.preparaVista()
        let ricevitore = Ricevitore()
        let fotocamera = AttivazioneFotocamera()
        _ricevitore = State(initialValue: ricevitore)
        _fotocamera = State(initialValue: fotocamera)
        // Foto e registrazioni dal telefono scelto per la webcam (P21).
        let riprese = Riprese(schermo: { ricevitore.schermo })
        // WebcamLR Pro: foto e registrazione solo con un telefono nella webcam che l'ha sbloccato.
        riprese.consentite = { ricevitore.proAttivo }
        // Passo 6: gli avvisi di foto e registrazione finiscono anche nel registro del collegamento.
        riprese.annota = { [weak ricevitore] testo in ricevitore?.registra(testo) }
        _riprese = State(initialValue: riprese)
        // P21: se l'utente sceglie un altro telefono, la registrazione in corso si ferma e si salva.
        ricevitore.primaDelCambioTelefono = { [weak riprese] in riprese?.telefonoCambiato() }
        // Punto 7: obiettivo, qualità, profilo e telefono nella webcam chiedono prima di fermare la registrazione.
        ricevitore.primaDiUnComandoCheFerma = { [weak riprese] comando in riprese?.confermaSeFerma(comando) ?? true }
        // Punto 8: «Scollega» chiede prima anche mentre registri.
        ricevitore.staRegistrando = { [weak riprese] in riprese?.registra ?? false }
        // Il telefono che si registrava se n'è andato (non tornato in 15 secondi, o scollegato): si chiude e si salva.
        ricevitore.primaDiDimenticareLoScelto = { [weak riprese] in
            riprese?.fermaRegistrazione(avvisoSalvata: String(localized: "Telefono non più collegato: registrazione salvata in Filmati › WebcamLR"))
        }
        // Il telefono che si registrava è in sottofondo: può restare via fino a 10 minuti, si chiude e si salva subito.
        ricevitore.sceltoInSottofondo = { [weak riprese] in
            riprese?.fermaRegistrazione(avvisoSalvata: String(localized: "Il telefono è in sottofondo: registrazione fermata e salvata in Filmati › WebcamLR"))
        }
        // ⌘Q, «Esci» e menu del Dock: il delegato guarda chi usa la webcam, i telefoni e la registrazione.
        DelegatoApp.ricevitore = ricevitore
        DelegatoApp.riprese = riprese
        Caratteri.registra()
        Notifiche.condivise.prepara()
        // Visibile in rete da subito, prima di qualsiasi finestra: anche quando WebcamLR si apre
        // all'avvio del Mac senza finestre, o con la finestra principale chiusa l'ultima volta.
        // Così il QR code è pronto appena compare.
        ricevitore.avvia()
        // Schermata di attesa (webcam virtuale e finestra): segue il Ricevitore da subito, non solo dalle Impostazioni.
        OsservatoreAttesa.condiviso.osserva(ricevitore)
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
            ComandiWebcamLR(ricevitore: ricevitore)
        }

        Window("Finestra mini", id: FinestraMini.id) {
            FinestraMini(ricevitore: ricevitore, riprese: riprese)
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

        // Passo 6 (M7): lo stato anche a finestra chiusa. Si toglie con l'interruttore (o trascinandola via con ⌘).
        MenuBarExtra(isInserted: $iconaBarraMenu) {
            MenuBarra(ricevitore: ricevitore, riprese: riprese)
        } label: {
            IconaBarra(ricevitore: ricevitore, riprese: riprese)
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

/// WebcamLR resta aperta anche a finestra chiusa (il telefono la ritrova e il QR è pronto): un clic sull'icona nel Dock
/// riapre la finestra. Il menu del Dock e l'icona nella barra dei menu (MenuBarra.swift) dicono lo stato.
final class DelegatoApp: NSObject, NSApplicationDelegate {
    /// Le imposta WebcamLRMacApp. Statiche: l'adattatore del delegato non è ancora pronto nell'`init` dell'app.
    @MainActor static weak var ricevitore: Ricevitore?
    @MainActor static weak var riprese: Riprese?
    /// L'uscita è decisa (confermata, o senza niente da chiedere): la finestra che si chiude non avvisa più.
    @MainActor private(set) static var uscitaInCorso = false
    /// Il tetto di sicurezza per chiudere la registrazione all'uscita: di solito basta meno di un secondo.
    static let tettoChiusuraRegistrazione: Duration = .seconds(30)
    /// La risposta a `applicationShouldTerminate` è già partita (file chiuso o tempo scaduto): una volta sola.
    @MainActor private var uscitaRisposta = true
    /// «Chiudo la registrazione…» mentre il file si chiude all'uscita.
    @MainActor private var avvisoChiusura: NSAlert?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘Q, «Esci da WebcamLR» e «Esci» nel Dock: se un'app usa la webcam, un telefono è collegato o stai
    /// registrando, prima chiede (pulsante predefinito «Annulla»). Con il logout, il riavvio o lo spegnimento del
    /// Mac non chiede niente. La registrazione si chiude davvero prima di uscire: niente .mov senza fine.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // Un secondo ⌘Q mentre il file si chiude: la prima uscita è già in corso e risponderà lei. Senza questo,
            // con `registra` già falso, si uscirebbe subito con il file a metà.
            guard uscitaRisposta else { return .terminateCancel }
            if !Self.chiusuraDelSistema(), let domanda = Self.domandaUscita() {
                guard Self.confermaUscita(domanda) else { return .terminateCancel }
            }
            Self.uscitaInCorso = true
            // Rilette dopo la domanda: intanto la registrazione può essersi fermata da sola. Anche un file fermato
            // un attimo prima (con «Ferma» o dal Dock) e non ancora chiuso si aspetta.
            guard let riprese = Self.riprese, riprese.registra || riprese.chiudeFile else { return .terminateNow }
            return chiudiRegistrazioneEdEsci(riprese, app: sender)
        }
    }

    /// Ferma la registrazione e risponde ad AppKit a file chiuso (e notifica «Registrazione salvata» consegnata),
    /// con «Chiudo la registrazione…» a schermo. Mai bloccati: dopo il tetto di sicurezza si esce lo stesso.
    @MainActor
    private func chiudiRegistrazioneEdEsci(_ riprese: Riprese, app: NSApplication) -> NSApplication.TerminateReply {
        uscitaRisposta = false
        mostraChiusuraRegistrazione()
        let rispondi: @MainActor () -> Void = { [weak self] in
            guard let self, !self.uscitaRisposta else { return }
            self.uscitaRisposta = true
            self.avvisoChiusura?.window.orderOut(nil)
            self.avvisoChiusura = nil
            app.reply(toApplicationShouldTerminate: true)
        }
        // `fatto` e `quandoFileChiusi` arrivano dopo, a file chiuso, mai prima di `.terminateLater`: con `registra`
        // vero `fatto` passa da un Task, e senza registrazione c'è almeno un file ancora in chiusura.
        if riprese.registra {
            riprese.fermaRegistrazione(perUscita: true, fatto: { riprese.quandoFileChiusi(rispondi) })
        } else {
            riprese.quandoFileChiusi(rispondi)
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.tettoChiusuraRegistrazione)
            rispondi()
        }
        return .terminateLater
    }

    /// Un avviso di macOS senza pulsanti, con la rotella: sparisce quando WebcamLR esce.
    @MainActor
    private func mostraChiusuraRegistrazione() {
        let avviso = NSAlert()
        avviso.messageText = String(localized: "Chiudo la registrazione…")
        avviso.informativeText = String(localized: "WebcamLR esce appena il file è salvato in Filmati › WebcamLR.")
        let rotella = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        rotella.style = .spinning
        rotella.isIndeterminate = true
        rotella.startAnimation(nil)
        avviso.accessoryView = rotella
        avviso.layout()
        // Niente da premere: il file si chiude da solo. Senza pulsanti NSAlert ne mette uno «OK»: si nasconde.
        avviso.buttons.forEach { $0.isHidden = true }
        avviso.window.center()
        NSApp.activate(ignoringOtherApps: true)
        avviso.window.makeKeyAndOrderFront(nil)
        avvisoChiusura = avviso
    }

    /// Il Mac si spegne, si riavvia o l'utente esce dall'account: l'evento «quit» porta il motivo (`kAEQuitReason`).
    /// ⌘Q e il menu non mandano eventi; «Esci» nel Dock sì, ma senza motivo.
    @MainActor
    private static func chiusuraDelSistema() -> Bool {
        guard let evento = NSAppleEventManager.shared().currentAppleEvent,
              evento.eventClass == AEEventClass(kCoreEventClass),
              evento.eventID == AEEventID(kAEQuitApplication),
              let motivo = evento.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.typeCodeValue else { return false }
        let motiviDelSistema: [OSType] = [OSType(kAELogOut), OSType(kAEReallyLogOut), OSType(kAEShowRestartDialog),
                                          OSType(kAEShowShutdownDialog), OSType(kAERestart), OSType(kAEShutDown)]
        return motiviDelSistema.contains(motivo)
    }

    /// La domanda prima di uscire: la frase principale e, se registri, quella sulla registrazione sotto.
    /// Nil se non c'è niente in corso: si esce subito, come prima.
    @MainActor
    private static func domandaUscita() -> (frase: String, dettaglio: String?)? {
        let registra = riprese?.registra ?? false
        let fraseRegistrazione = String(localized: "La registrazione si ferma e si salva in Filmati › WebcamLR.")
        var principale: String?
        if let ricevitore {
            if ricevitore.webcamInUso {
                if let nome = AppCompatibile.nomeUnico(firme: ricevitore.appWebcam) {
                    // «un sito nel browser» apre la frase: con la maiuscola.
                    let nome = nome.prefix(1).uppercased() + nome.dropFirst()
                    principale = String(localized: "\(nome) sta usando WebcamLR: se esci, la chiamata resta senza video.")
                } else {
                    principale = String(localized: "Un'app sta usando WebcamLR: se esci, la chiamata resta senza video.")
                }
            } else if ricevitore.telefoni.contains(where: { $0.collegato }) {
                principale = String(localized: "Un telefono è collegato: se esci, si scollega.")
            }
        }
        if let principale {
            return (frase: principale, dettaglio: registra ? fraseRegistrazione : nil)
        }
        guard registra else { return nil }
        return (frase: fraseRegistrazione, dettaglio: nil)
    }

    /// Avviso di macOS: «Annulla» è il pulsante predefinito (Invio), «Esci da WebcamLR» va scelto.
    @MainActor
    private static func confermaUscita(_ domanda: (frase: String, dettaglio: String?)) -> Bool {
        let avviso = NSAlert()
        avviso.alertStyle = .warning
        avviso.messageText = domanda.frase
        avviso.informativeText = domanda.dettaglio ?? ""
        avviso.addButton(withTitle: String(localized: "Annulla"))
        avviso.addButton(withTitle: String(localized: "Esci da WebcamLR"))
        NSApp.activate(ignoringOtherApps: true)
        return avviso.runModal() == .alertSecondButtonReturn
    }

    // MARK: - Menu del Dock

    /// Clic destro sull'icona nel Dock: lo stato in righe non cliccabili, «Ferma la registrazione» (solo se registri)
    /// e «Mostra WebcamLR». Sotto macOS aggiunge le sue voci (Opzioni, Mostra tutte le finestre, Esci).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        // Costruito sulla coda principale e restituito fuori: NSMenu non passa come risultato di `assumeIsolated`.
        var menuDock: NSMenu?
        MainActor.assumeIsolated {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for riga in Self.righeStato(ricevitore: Self.ricevitore, riprese: Self.riprese) {
                let voce = NSMenuItem(title: riga, action: nil, keyEquivalent: "")
                voce.isEnabled = false
                menu.addItem(voce)
            }
            menu.addItem(.separator())
            if Self.riprese?.registra == true {
                let ferma = NSMenuItem(title: String(localized: "Ferma la registrazione"),
                                       action: #selector(fermaRegistrazioneDalDock(_:)), keyEquivalent: "")
                ferma.target = self
                menu.addItem(ferma)
            }
            let mostra = NSMenuItem(title: String(localized: "Mostra WebcamLR"),
                                    action: #selector(mostraDalDock(_:)), keyEquivalent: "")
            mostra.target = self
            menu.addItem(mostra)
            menuDock = menu
        }
        return menuDock
    }

    /// «In onda su Zoom», «iPhone di Ledion collegato», «Riconnessione in corso…» o «Nessun telefono»;
    /// sotto, se registri, «Registrazione 12:31». Per il menu del Dock e per quello della barra dei menu.
    @MainActor
    static func righeStato(ricevitore: Ricevitore?, riprese: Riprese?) -> [String] {
        var righe: [String] = []
        if let ricevitore {
            switch ricevitore.collegamento {
            case .inOnda:
                if let nome = ricevitore.nomeAppInOnda {
                    righe.append(String(localized: "In onda su \(nome)"))
                } else {
                    righe.append(String(localized: "In onda"))
                }
            case .collegato:
                let nome = ricevitore.telefono?.nome ?? ""
                righe.append(String(localized: "\(nome) collegato"))
            case .riconnessione:
                righe.append(String(localized: "Riconnessione in corso…"))
            case .nessunTelefono:
                righe.append(String(localized: "Nessun telefono"))
            }
        }
        if let inizio = riprese?.inizioRegistrazione {
            let secondi = max(0, Int(Date.now.timeIntervalSince(inizio)))
            let tempo = String(format: "%02d:%02d", secondi / 60, secondi % 60)
            righe.append(String(localized: "Registrazione \(tempo)"))
        }
        return righe
    }

    @objc private func fermaRegistrazioneDalDock(_ voce: NSMenuItem) {
        MainActor.assumeIsolated {
            guard let riprese = Self.riprese else { return }
            riprese.fermaRegistrazione()
        }
    }

    @objc private func mostraDalDock(_ voce: NSMenuItem) {
        MainActor.assumeIsolated {
            NSApp.activate(ignoringOtherApps: true)
            Self.apriFinestraPrincipale(NSApp)
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
