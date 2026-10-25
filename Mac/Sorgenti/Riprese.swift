import AppKit
import Foundation
import Observation

/// Foto e registrazioni dal Mac (funzione 35), condivise da finestra e tastiera.
/// Tutto sulla coda principale; il lavoro sul video lo fa lo `Schermo` sulla sua coda.
@Observable
@MainActor
final class Riprese {
    /// Sotto questa soglia di spazio libero compare l'avviso durante la registrazione (funzione 37).
    static let spazioMinimo: Int64 = 2_000_000_000

    /// Una frase breve dopo una foto o una registrazione; sparisce da sola.
    private(set) var avviso: String?
    /// Quando è iniziata la registrazione in corso; nil se non si registra.
    private(set) var inizioRegistrazione: Date?
    /// Byte già scritti nel file della registrazione, aggiornati ogni secondo.
    private(set) var dimensioneRegistrazione: Int64 = 0
    /// Byte liberi sul disco della registrazione, solo quando sono meno di `spazioMinimo`.
    private(set) var spazioScarso: Int64?
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
    private let suonoScatto: NSSound?
    /// WebcamLR Pro: foto e registrazione solo se il telefono nella webcam l'ha sbloccato (`Ricevitore.proAttivo`).
    /// Vale anche per le scorciatoie (⌘T, ⇧⌘T, ⌘C, ⌘R), che non passano dai pulsanti.
    @ObservationIgnored var consentite: @MainActor () -> Bool = { true }

    init(schermo: @escaping @MainActor () -> Schermo) {
        schermoScelto = schermo
        // Il nome del tipo, non `Self`: in una classe `Self` passa da `self`, non ancora inizializzato qui.
        suonoScatto = Riprese.caricaSuonoScatto()
    }

    var registra: Bool { inizioRegistrazione != nil }

    // MARK: - Foto

    /// Foto dal computer: salva in Immagini › WebcamLR e la mostra nel Finder.
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
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    self.mostra(String(localized: "Foto salvata in Immagini › WebcamLR"))
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
            schermo.avviaRegistrazione(in: file) { [weak self] file, salvato in
                Task { @MainActor in self?.registrazioneInterrotta(file, salvato: salvato) }
            }
            schermoRegistrazione = schermo
            fileRegistrazione = file
            inizioRegistrazione = .now
            dimensioneRegistrazione = 0
            spazioScarso = nil
            controllaSpazio()
            compitoRegistrazione?.cancel()
            compitoRegistrazione = Task { [weak self] in
                var secondi = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    secondi += 1
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
    /// `fatto`: chiamata a file chiuso, salvato o no (serve all'uscita con ⌘Q).
    func fermaRegistrazione(avvisoSalvata: String? = nil, fatto: (@MainActor () -> Void)? = nil) {
        guard registra else { fatto?(); return }
        compitoRegistrazione?.cancel()
        compitoRegistrazione = nil
        inizioRegistrazione = nil
        fileRegistrazione = nil
        spazioScarso = nil
        let schermo = schermoRegistrazione ?? schermoScelto()
        schermoRegistrazione = nil
        schermo.fermaRegistrazione { file in
            Task { @MainActor in
                if let file {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    self.mostra(avvisoSalvata ?? String(localized: "Registrazione salvata in Filmati › WebcamLR"))
                    Notifiche.condivise.registrazioneSalvata(file)
                } else {
                    self.mostra(String(localized: "Registrazione troppo breve, niente da salvare: riprova e registra per qualche secondo."))
                }
                fatto?()
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
    /// la registrazione è finita, il pulsante torna «Registra» e si dice che fine ha fatto il file.
    private func registrazioneInterrotta(_ file: URL, salvato: Bool) {
        // Solo se è ancora questa la registrazione in corso (non una fermata e già ripartita).
        if fileRegistrazione == file {
            compitoRegistrazione?.cancel()
            compitoRegistrazione = nil
            inizioRegistrazione = nil
            fileRegistrazione = nil
            schermoRegistrazione = nil
            spazioScarso = nil
        }
        if salvato {
            mostra(String(localized: "Il video è cambiato: registrazione fermata e salvata in Filmati › WebcamLR"))
            Notifiche.condivise.registrazioneSalvata(file)
        } else {
            mostra(String(localized: "Registrazione interrotta: controlla lo spazio sul disco e riprova."))
        }
    }

    /// Dimensione del file in scrittura (funzione 37). Si legge dal disco ogni volta, senza cache.
    private func leggiDimensione() {
        guard let file = fileRegistrazione,
              let attributi = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)),
              let byte = attributi[.size] as? NSNumber else { return }
        dimensioneRegistrazione = byte.int64Value
    }

    /// Spazio libero «per le cose importanti», lo stesso numero che usa il Finder (funzione 37).
    private func controllaSpazio() {
        guard let file = fileRegistrazione else { return }
        var cartella = file.deletingLastPathComponent()
        cartella.removeAllCachedResourceValues()
        guard let valori = try? cartella.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let liberi = valori.volumeAvailableCapacityForImportantUsage else { return }
        spazioScarso = liberi < Self.spazioMinimo ? liberi : nil
    }

    // MARK: - Utilità

    static func testoByte(_ byte: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byte, countStyle: .file)
    }

    func mostra(_ testo: String) {
        compitoAvviso?.cancel()
        avviso = testo
        compitoAvviso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            self.avviso = nil
        }
    }
}
