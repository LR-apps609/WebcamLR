import AppKit
import Foundation
import Observation

/// Foto e registrazioni dal Mac (funzione 35), condivise da finestra e tastiera.
/// Tutto sulla coda principale; il lavoro sul video lo fa lo `Schermo` sulla sua coda.
@Observable
@MainActor
final class Riprese {
    /// Con meno di questi minuti di spazio al ritmo attuale compare «Spazio quasi finito» (funzione 37, punto 5).
    static let minutiMinimi = 10
    /// Il ritmo del file prima di poterlo misurare (i primi 10 secondi): circa 16 Mbit/s, il 1080p.
    static let byteAlSecondoIniziali: Int64 = 2_000_000

    /// Una frase breve dopo una foto o una registrazione (un fatto finito): sparisce da sola dopo 4 o 8 secondi.
    private(set) var avviso: String?
    /// Il file della foto o della registrazione di cui parla `avviso`: sotto la frase c'è «Mostra nel Finder» (punto 18).
    private(set) var fileAvviso: URL?
    /// Quando è iniziata la registrazione in corso; nil se non si registra.
    private(set) var inizioRegistrazione: Date?
    /// I secondi registrati finora, aggiornati ogni secondo: il menu nella barra dei menu si ridisegna con loro.
    private(set) var secondiRegistrati = 0
    /// Byte già scritti nel file della registrazione, aggiornati ogni secondo.
    private(set) var dimensioneRegistrazione: Int64 = 0
    /// I minuti di registrazione che restano sul disco al ritmo attuale, solo quando sono meno di `minutiMinimi`.
    private(set) var minutiRimasti: Int?
    /// Cresce di uno a ogni scatto riuscito: l'anteprima lo guarda per il lampo bianco (funzione 27).
    private(set) var lampo = 0
    /// I secondi che mancano alla foto con il timer (funzione 36); nil se non c'è un timer.
    private(set) var contoAllaRovescia: Int?

    /// Lo schermo del telefono scelto per la webcam (P21: uno per telefono), letto a ogni foto e registrazione.
    private let schermoScelto: @MainActor () -> Schermo
    /// Lo schermo su cui è partita la registrazione: si ferma lì anche se intanto il telefono scelto è cambiato.
    /// Il file è il video compresso così come arriva, quindi è di un solo telefono: se l'utente ne sceglie
    /// un altro, la registrazione si chiude e si salva (P21, come su Windows; vedi `telefonoCambiato()`).
    @ObservationIgnored private var schermoRegistrazione: Schermo?
    @ObservationIgnored private var fileRegistrazione: URL?
    @ObservationIgnored private var compitoRegistrazione: Task<Void, Never>?
    @ObservationIgnored private var compitoAvviso: Task<Void, Never>?
    @ObservationIgnored private var compitoTimer: Task<Void, Never>?
    /// «Spazio quasi finito» è già stato notificato per la registrazione in corso: una volta sola.
    @ObservationIgnored private var spazioNotificato = false
    /// La domanda di `confermaSeFerma` è aperta.
    @ObservationIgnored private var domandaAperta = false
    private let suonoScatto: NSSound?
    /// WebcamLR Pro: foto e registrazione solo se il telefono nella webcam l'ha sbloccato (`Ricevitore.proAttivo`).
    /// Vale anche per le scorciatoie (⌘T, ⇧⌘T, ⌘C, ⌘R), che non passano dai pulsanti.
    @ObservationIgnored var consentite: @MainActor () -> Bool = { true }
    /// Scrive una riga nel registro del collegamento (passo 6: ogni avviso finisce anche lì). La imposta l'app.
    @ObservationIgnored var annota: @MainActor (String) -> Void = { _ in }

    init(schermo: @escaping @MainActor () -> Schermo) {
        schermoScelto = schermo
        // Il nome del tipo, non `Self`: in una classe `Self` passa da `self`, non ancora inizializzato qui.
        suonoScatto = Riprese.caricaSuonoScatto()
    }

    var registra: Bool { inizioRegistrazione != nil }

    /// Le registrazioni fermate il cui file si sta ancora chiudendo (pulsante, menu del Dock, telefono cambiato):
    /// all'uscita si aspettano anche queste, altrimenti ⌘Q subito dopo «Ferma» lascerebbe il .mov senza fine.
    @ObservationIgnored private var fileInChiusura = 0
    @ObservationIgnored private var dopoLaChiusura: [@MainActor () -> Void] = []

    /// Un file fermato si sta ancora chiudendo.
    var chiudeFile: Bool { fileInChiusura > 0 }

    /// Chiama `fatto` quando nessun file fermato si sta più chiudendo: subito, se non ce ne sono.
    func quandoFileChiusi(_ fatto: @escaping @MainActor () -> Void) {
        guard fileInChiusura > 0 else {
            fatto()
            return
        }
        dopoLaChiusura.append(fatto)
    }

    private func fileChiuso() {
        fileInChiusura = max(0, fileInChiusura - 1)
        guard fileInChiusura == 0 else { return }
        let attese = dopoLaChiusura
        dopoLaChiusura = []
        attese.forEach { $0() }
    }

    // MARK: - Foto

    /// Foto dal computer: salva in Immagini › WebcamLR e lo dice, con «Mostra nel Finder» (punto 18).
    func scattaFoto() {
        guard proPresente() else { return }
        schermoScelto().fotografa { immagine in
            Task { @MainActor in
                guard let immagine else {
                    self.mostra(Fotografia.Errore.nessunVideo.localizedDescription)
                    return
                }
                // Lampo e suono subito; il PNG si scrive fuori dalla coda principale, così i clic restano pronti.
                self.scatto()
                let esito = await Task.detached(priority: .userInitiated) {
                    Result { try Fotografia.salva(immagine) }
                }.value
                switch esito {
                case .success(let file):
                    self.mostra(String(localized: "Foto salvata in Immagini › WebcamLR."), file: file)
                case .failure:
                    self.mostra(Fotografia.Errore.salvataggio.localizedDescription)
                }
            }
        }
    }

    /// Copia il fotogramma attuale negli appunti (⌘C, funzione 26), da incollare in qualsiasi app.
    func copiaFotogramma() {
        guard proPresente() else { return }
        schermoScelto().fotografa { immagine in
            Task { @MainActor in
                guard let immagine else {
                    self.mostra(Fotografia.Errore.nessunVideo.localizedDescription)
                    return
                }
                let foto = NSImage(cgImage: immagine, size: NSSize(width: immagine.width, height: immagine.height))
                let appunti = NSPasteboard.general
                appunti.clearContents()
                if appunti.writeObjects([foto]) {
                    self.scatto()
                    self.mostra(String(localized: "Fotogramma copiato: incollalo dove vuoi"))
                } else {
                    self.mostra(String(localized: "Non riesco a copiare il fotogramma: riprova."))
                }
            }
        }
    }

    /// Foto con il timer di 3 secondi (funzione 36); se il timer è già partito, lo annulla.
    func scattaConTimer() {
        guard contoAllaRovescia == nil else { return annullaTimer() }
        guard proPresente() else { return }
        compitoTimer = Task { [weak self] in
            for secondi in [3, 2, 1] {
                self?.contoAllaRovescia = secondi
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.contoAllaRovescia = nil
            self?.scattaFoto()
        }
    }

    func annullaTimer() {
        compitoTimer?.cancel()
        compitoTimer = nil
        contoAllaRovescia = nil
    }

    /// Senza WebcamLR Pro lo dice al posto della foto o della registrazione.
    private func proPresente() -> Bool {
        guard consentite() else {
            mostra(String(localized: "Foto e registrazione sono di WebcamLR Pro: si sblocca dall'iPhone, in WebcamLR › App › WebcamLR Pro."))
            return false
        }
        return true
    }

    /// Lampo sull'anteprima e suono dello scatto (funzione 27).
    private func scatto() {
        lampo += 1
        if let suonoScatto {
            suonoScatto.stop()
            suonoScatto.play()
        }
    }

    /// Il suono dello scatto di macOS (quello delle istantanee dello schermo), letto dai file di sistema:
    /// la sandbox permette di leggerli. Se in questa versione di macOS non c'è, la foto resta muta.
    nonisolated private static func caricaSuonoScatto() -> NSSound? {
        let cartella = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/"
        for nome in ["Grab.aif", "Shutter.aif"] {
            let percorso = cartella + nome
            if FileManager.default.fileExists(atPath: percorso),
               let suono = NSSound(contentsOfFile: percorso, byReference: true) {
                return suono
            }
        }
        return nil
    }

    // MARK: - Registrazione

    func alternaRegistrazione() {
        if registra { fermaRegistrazione() } else { avviaRegistrazione() }
    }

    func avviaRegistrazione() {
        guard !registra, proPresente() else { return }
        do {
            let file = try Fotografia.nuovaRegistrazione()
            let schermo = schermoScelto()
            schermo.avviaRegistrazione(in: file) { [weak self] file, esito in
                Task { @MainActor in self?.registrazioneInterrotta(file, esito: esito) }
            }
            schermoRegistrazione = schermo
            fileRegistrazione = file
            inizioRegistrazione = .now
            secondiRegistrati = 0
            annota(String(localized: "Registrazione iniziata"))
            Annuncio.di(String(localized: "Registrazione iniziata"))
            dimensioneRegistrazione = 0
            minutiRimasti = nil
            spazioNotificato = false
            controllaSpazio()
            compitoRegistrazione?.cancel()
            compitoRegistrazione = Task { [weak self] in
                var secondi = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    secondi += 1
                    self.secondiRegistrati = secondi
                    self.leggiDimensione()
                    // Lo spazio libero cambia piano: basta guardarlo ogni 5 secondi.
                    if secondi % 5 == 0 { self.controllaSpazio() }
                }
            }
        } catch {
            mostra(Fotografia.Errore.registrazione.localizedDescription)
        }
    }

    /// Ferma e salva. `avvisoSalvata` sostituisce la frase di sempre quando a fermare non è l'utente.
    /// `perUscita` (⌘Q, M5): niente avviso nella finestra, resta solo la notifica «Registrazione salvata».
    /// `fatto`: chiamata a file chiuso, salvato o no, e con la notifica già consegnata a macOS (serve all'uscita).
    func fermaRegistrazione(avvisoSalvata: String? = nil, perUscita: Bool = false, fatto: (@MainActor () -> Void)? = nil) {
        guard registra else { fatto?(); return }
        compitoRegistrazione?.cancel()
        compitoRegistrazione = nil
        inizioRegistrazione = nil
        fileRegistrazione = nil
        minutiRimasti = nil
        let schermo = schermoRegistrazione ?? schermoScelto()
        schermoRegistrazione = nil
        fileInChiusura += 1
        schermo.fermaRegistrazione { file in
            Task { @MainActor in
                self.fileChiuso()
                if let file {
                    if !perUscita {
                        self.mostra(avvisoSalvata ?? String(localized: "Registrazione salvata in Filmati › WebcamLR"), file: file)
                        Annuncio.di(String(localized: "Registrazione salvata"))
                    }
                    Notifiche.condivise.registrazioneSalvata(file, poi: fatto)
                } else {
                    if !perUscita {
                        let testo = String(localized: "Registrazione troppo breve, niente da salvare: riprova e registra per qualche secondo.")
                        self.mostra(testo)
                        Annuncio.di(testo)
                    }
                    fatto?()
                }
            }
        }
    }

    /// Dal Ricevitore, prima che «Nella webcam» passi a un altro telefono (P21): la registrazione è di un solo
    /// video, quindi si chiude e si salva, come su Windows; l'utente può farne partire una nuova sul telefono
    /// scelto. Anche il timer della foto si annulla, così non scatta sul telefono nuovo.
    func telefonoCambiato() {
        annullaTimer()
        fermaRegistrazione(avvisoSalvata: String(localized: "Hai cambiato telefono: registrazione fermata e salvata in Filmati › WebcamLR"))
    }

    /// Lo `Schermo` ha chiuso il file da solo (telefono girato, altro formato, disco pieno):
    /// la registrazione è finita, il pulsante torna «Registra» e si dice perché e che fine ha fatto il file (M6).
    /// Con il disco pieno o un errore di scrittura il file resta fino all'ultimo frammento (punto 5); a finestra
    /// non davanti lo dice anche una notifica (M4).
    private func registrazioneInterrotta(_ file: URL, esito: InterruzioneRegistrazione) {
        // Solo se è ancora questa la registrazione in corso (non una fermata e già ripartita).
        if fileRegistrazione == file {
            compitoRegistrazione?.cancel()
            compitoRegistrazione = nil
            inizioRegistrazione = nil
            fileRegistrazione = nil
            schermoRegistrazione = nil
            minutiRimasti = nil
        }
        Annuncio.di(String(localized: "Registrazione interrotta"))
        let durata = Self.testoDurata(esito.secondi)
        let testo: String
        switch (esito.causa, esito.salvato) {
        case (.formatoCambiato, true):
            mostra(String(localized: "Il video è cambiato: registrazione fermata e salvata in Filmati › WebcamLR"), file: file)
            Notifiche.condivise.registrazioneSalvata(file)
            return
        case (.formatoCambiato, false):
            testo = String(localized: "Il video è cambiato: registrazione fermata, niente da salvare. Riprova.")
        case (.discoPieno, true):
            testo = String(localized: "Disco pieno: registrazione fermata. I primi \(durata) sono salvati in Filmati › WebcamLR.")
        case (.discoPieno, false):
            testo = String(localized: "Disco pieno: registrazione fermata, niente da salvare. Libera spazio e riprova.")
        case (.erroreScrittura, true):
            testo = String(localized: "Errore di scrittura sul disco: registrazione fermata. I primi \(durata) sono salvati in Filmati › WebcamLR.")
        case (.erroreScrittura, false):
            testo = String(localized: "Errore di scrittura sul disco: registrazione fermata, niente da salvare. Controlla il disco e riprova.")
        }
        mostra(testo, file: esito.salvato ? file : nil)
        Notifiche.condivise.registrazioneInterrotta(testo, file: esito.salvato ? file : nil)
    }

    /// «12:40», o «1:02:40» oltre l'ora: la durata salvata, come il tempo sul pulsante Registra.
    static func testoDurata(_ secondi: Int) -> String {
        let ore = secondi / 3600
        let minuti = secondi / 60 % 60
        return ore > 0 ? String(format: "%d:%02d:%02d", ore, minuti, secondi % 60)
                       : String(format: "%02d:%02d", minuti, secondi % 60)
    }

    // MARK: - Comandi che fermano la registrazione (punto 7)

    /// I comandi che cambiano il video del telefono, e quindi chiudono il file della registrazione.
    enum ComandoCheFerma {
        case obiettivo, qualita, profilo, telefono
    }

    /// L'unico punto di passaggio prima di un comando che ferma la registrazione: se non registri dice sì subito;
    /// se registri chiede (Annulla è il pulsante predefinito) e, se confermi, ferma e salva prima del comando, così
    /// il file si chiude bene e non a metà di un cambio. Vero se il comando può andare avanti.
    func confermaSeFerma(_ comando: ComandoCheFerma) -> Bool {
        guard registra else { return true }
        // Durante `runModal` girano anche i compiti in coda (un tasto 1–4 premuto due volte, una richiesta dal
        // telefono): una seconda domanda sopra la prima no, quel comando si annulla (come su Windows).
        guard !domandaAperta else { return false }
        domandaAperta = true
        defer { domandaAperta = false }
        let domanda: String
        let pulsante: String
        switch comando {
        case .obiettivo:
            domanda = String(localized: "Cambiare obiettivo ferma la registrazione e la salva. Continuare?")
            pulsante = String(localized: "Cambia")
        case .qualita:
            domanda = String(localized: "Cambiare qualità ferma la registrazione e la salva. Continuare?")
            pulsante = String(localized: "Cambia")
        case .profilo:
            domanda = String(localized: "Applicare un profilo ferma la registrazione e la salva. Continuare?")
            pulsante = String(localized: "Applica")
        case .telefono:
            domanda = String(localized: "Cambiare telefono ferma la registrazione e la salva. Continuare?")
            pulsante = String(localized: "Cambia")
        }
        guard Domanda.conferma(domanda, pulsante: pulsante) else { return false }
        // Intanto la registrazione può essersi fermata da sola: `fermaRegistrazione` allora non fa niente.
        fermaRegistrazione()
        return true
    }

    /// Dimensione del file in scrittura (funzione 37). Si legge dal disco ogni volta, senza cache.
    private func leggiDimensione() {
        guard let file = fileRegistrazione,
              let attributi = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)),
              let byte = attributi[.size] as? NSNumber else { return }
        dimensioneRegistrazione = byte.int64Value
    }

    /// Spazio libero «per le cose importanti», lo stesso numero che usa il Finder (funzione 37), in minuti al ritmo
    /// attuale del file. Sotto `minutiMinimi` l'avviso nella finestra e, a finestra non davanti, una notifica (M4).
    private func controllaSpazio() {
        guard let file = fileRegistrazione, let inizio = inizioRegistrazione else { return }
        var cartella = file.deletingLastPathComponent()
        cartella.removeAllCachedResourceValues()
        guard let valori = try? cartella.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let liberi = valori.volumeAvailableCapacityForImportantUsage else { return }
        // Il ritmo si misura dopo 10 secondi: prima il file ha solo l'intestazione e qualche frammento.
        let secondi = Int64(Date.now.timeIntervalSince(inizio))
        let byteAlSecondo = secondi >= 10 && dimensioneRegistrazione > 0
            ? max(dimensioneRegistrazione / secondi, 1) : Self.byteAlSecondoIniziali
        let minuti = Int(max(liberi, 0) / byteAlSecondo / 60)
        minutiRimasti = minuti < Self.minutiMinimi ? minuti : nil
        if let testo = testoSpazio, !spazioNotificato {
            spazioNotificato = true
            annota(testo)
            Notifiche.condivise.spazioQuasiFinito(testo)
        }
    }

    /// «Spazio quasi finito: restano circa 8 minuti», quando lo spazio sta finendo durante la registrazione.
    var testoSpazio: String? {
        guard let minuti = minutiRimasti else { return nil }
        return minuti < 2 ? String(localized: "Spazio quasi finito: resta circa un minuto")
                          : String(localized: "Spazio quasi finito: restano circa \(minuti) minuti")
    }

    // MARK: - Utilità

    static func testoByte(_ byte: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byte, countStyle: .file)
    }

    /// Con `file` sotto la frase c'è «Mostra nel Finder» (punto 18), e l'avviso resta di più per lasciare il tempo
    /// del clic.
    /// Ogni avviso finisce anche nel registro (passo 6).
    func mostra(_ testo: String, file: URL? = nil) {
        annota(testo)
        compitoAvviso?.cancel()
        avviso = testo
        fileAvviso = file
        compitoAvviso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(file == nil ? 4 : 8))
            guard let self, !Task.isCancelled else { return }
            self.avviso = nil
            self.fileAvviso = nil
        }
    }

    /// «Mostra nel Finder» sotto l'avviso: il Finder si apre solo se lo chiedi.
    func mostraNelFinder() {
        guard let file = fileAvviso else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}

/// Le domande prima di un gesto che non si disfa (punti 7 e 8): un avviso di macOS con «Annulla» come pulsante
/// predefinito (Invio annulla), il comando va scelto. Lo stesso aspetto della domanda di ⌘Q.
@MainActor
enum Domanda {
    /// Vero se l'utente sceglie `pulsante`.
    static func conferma(_ domanda: String, dettaglio: String? = nil, pulsante: String) -> Bool {
        let avviso = NSAlert()
        avviso.alertStyle = .warning
        avviso.messageText = domanda
        avviso.informativeText = dettaglio ?? ""
        avviso.addButton(withTitle: String(localized: "Annulla"))
        avviso.addButton(withTitle: pulsante)
        return avviso.runModal() == .alertSecondButtonReturn
    }
}
