// Copione delle correzioni Mac del collaudo 20: rifà i flussi dei bug corretti e guarda il risultato.
// t05 B1 + t01 B6 (finestra dopo ⌘W, ⌘Q e riapertura; clic sul Dock), t05 B2 (Rimuovi nel foglio Telefoni fidati),
// A1 (schermo 1024×768: niente fuori dalla finestra), t01 B4 (aiuto dopo 30 s), A5 (scheda piena), t11 B10/B11,
// t05 B5 (nomi degli interruttori), t10 B9 (menu Video senza telefono).

import AppKit
import XCTest

final class CopioneCorrezioni: CopioneCollaudo {

    private static let fidatiFinti = "{ \"A1B2C3D4E5F60718\" = \"iPhone di Francesca\"; \"0F0E0D0C0B0A0908\" = \"iPad di casa\"; }"

    /// La finestra principale (identificatore «principale»), se c'è.
    @MainActor private var principale: XCUIElement {
        app.windows.matching(identifier: "principale").firstMatch
    }

    @MainActor private func annotaFinestre(_ quando: String) {
        let finestre = app.windows.allElementsBoundByIndex.map { "«\($0.title)» [\($0.identifier)]" }
        nota("\(quando): \(finestre.count) finestre \(finestre.joined(separator: ", ")); principale \(principale.exists)")
    }

    /// Come un clic sull'icona nel Dock con l'app già aperta: macOS manda all'app l'evento «riapri».
    @MainActor private func cliccaNelDock() {
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: "it.lrapps.webcamlr.mac").first?.bundleURL else {
            nota("Clic sul Dock: non trovo l'app in esecuzione")
            return
        }
        let fatto = expectation(description: "riapri")
        let configurazione = NSWorkspace.OpenConfiguration()
        configurazione.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configurazione) { _, errore in
            if let errore { print("openApplication: \(errore)") }
            fatto.fulfill()
        }
        wait(for: [fatto], timeout: 15)
        aspettaUnPo(2)
    }

    /// ⌘Q come una persona; se l'app resta aperta la chiude il banco.
    @MainActor private func esciConComandoQ() {
        app.typeKey("q", modifierFlags: .command)
        let limite = Date().addingTimeInterval(10)
        while app.state != .notRunning && Date() < limite { aspettaUnPo(0.5) }
        if app.state != .notRunning {
            nota("Dopo ⌘Q l'app è ancora aperta: la chiudo io")
            app.terminate()
        }
    }

    /// Riapre come dal Dock: senza `-ApplePersistenceIgnoreState`, macOS ripristina le finestre come le aveva lasciate.
    @MainActor private func riapriComeDalDock() {
        app.launchArguments = LinguaCollaudo.italiano.argomenti
        app.launch()
        aspettaUnPo(2)
        rispondiAlleDomandeDiSistema(.concedi)
    }

    // MARK: - Prove

    /// t05 B1 e t01 B6: finestra chiusa (⌘W), ⌘Q, riapertura: la finestra principale deve esserci. Poi ⌘W e clic sul Dock.
    @MainActor func test01_finestraDopoRiapertura() {
        avviaPulito()
        attendi("Collega il telefono in tre passi", secondi: 20)
        annotaFinestre("Primo avvio")
        tasto("w", con: .command)
        aspettaUnPo(1.5)
        annotaFinestre("Dopo ⌘W")
        fotografa("dopo cmd w")
        esciConComandoQ()
        riapriComeDalDock()
        let tornata = principale.waitForExistence(timeout: 8)
        annotaFinestre("Riaperta dopo ⌘W e ⌘Q")
        XCTAssertTrue(tornata, "t05 B1: riaperta l'app, la finestra principale non c'è")
        fotografa("riaperta dopo cmd w e cmd q")

        // Riapertura semplice (finestra aperta all'uscita): c'è ancora, una sola.
        esciConComandoQ()
        riapriComeDalDock()
        XCTAssertTrue(principale.waitForExistence(timeout: 8), "Riaperta con la finestra lasciata aperta: niente finestra")
        nota("Riaperta con la finestra aperta: finestre principali \(app.windows.matching(identifier: "principale").count)")

        // t01 B6: chiusa la finestra, il clic sul Dock la riporta.
        tasto("w", con: .command)
        aspettaUnPo(1.5)
        annotaFinestre("Di nuovo dopo ⌘W")
        cliccaNelDock()
        let dalDock = principale.waitForExistence(timeout: 8)
        annotaFinestre("Dopo il clic sul Dock")
        XCTAssertTrue(dalDock, "t01 B6: il clic sul Dock non riapre la finestra")
        fotografa("dopo il clic sul dock")
    }

    /// t05 B2: «Rimuovi» nel foglio «Telefoni fidati»: domanda, «Annulla» non toglie, «Rimuovi» toglie.
    @MainActor func test02_rimuoviDalFoglio() {
        avvia(argomenti: ["-telefoniFidati", Self.fidatiFinti])
        attendi("Impostazioni")
        guard tocca("Impostazioni"), tocca("Telefoni", dentro: "Impostazioni") else { return }
        guard tocca("Telefoni fidati…", dentro: "Impostazioni") || tocca("Telefoni fidati") else { return }
        aspettaUnPo(1)
        fotografa("foglio telefoni fidati")
        tocca("Rimuovi iPad di casa")
        aspettaUnPo(1)
        fotografa("domanda rimuovi ipad")
        let annulla = app.buttons["Annulla"]
        XCTAssertTrue(annulla.waitForExistence(timeout: 3), "t05 B2: nessuna domanda dopo «Rimuovi»")
        if annulla.exists { annulla.click() }
        aspettaUnPo(1)
        nota("Dopo «Annulla»: «iPad di casa» c'è ancora \(esiste("iPad di casa"))")
        tocca("Rimuovi iPad di casa")
        aspettaUnPo(1)
        let rimuovi = app.buttons.matching(NSPredicate(format: "label == %@ OR title == %@", "Rimuovi", "Rimuovi")).firstMatch
        XCTAssertTrue(rimuovi.waitForExistence(timeout: 3), "t05 B2: nessun «Rimuovi» nella domanda")
        if rimuovi.exists { rimuovi.click() }
        aspettaUnPo(1.5)
        fotografa("foglio dopo rimuovi ipad")
        let ancora = app.buttons["Rimuovi iPad di casa"].exists
        nota("Dopo «Rimuovi»: «iPad di casa» nel foglio \(ancora), «iPhone di Francesca» \(app.buttons["Rimuovi iPhone di Francesca"].exists)")
        XCTAssertFalse(ancora, "t05 B2: «iPad di casa» è ancora nel foglio dopo «Rimuovi»")
        chiudiFoglio()
    }

    /// A1, t01 B4, A5, t11 B10 e B11: primo avvio sul Mac di GitHub (1024×768), aspettando l'aiuto dei 30 secondi.
    @MainActor func test03_schermoBassoEAiuto() {
        avviaPulito()
        attendi("Collega il telefono in tre passi", secondi: 20)
        fotografa("primo avvio")
        let finestra = principale.frame
        nota("Finestra principale \(finestra)")
        // B10: il QR è un'immagine con nome (e l'indirizzo).
        let qr = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "QR code per collegare")).firstMatch
        nota("t11 B10: immagine del QR \(qr.exists) «\(qr.exists ? qr.label : "")»")
        XCTAssertTrue(qr.exists, "t11 B10: il QR non è un elemento immagine")
        // t01 B4: dopo 30 s l'aiuto neutro.
        let aiuto = esiste("Non vedo ancora il telefono", secondi: 40)
        nota("t01 B4: «Non vedo ancora il telefono» dopo 30 s \(aiuto); vecchio riquadro firewall \(esiste("Controlla il firewall"))")
        fotografa("dopo 40 secondi")
        // A1: niente fuori dalla finestra.
        for nome in ["Specchia", "Schermo", "Non hai l'app? Scaricala"] {
            let elemento = app.buttons[nome].firstMatch
            if elemento.exists {
                nota("A1: «\(nome)» \(elemento.frame), cliccabile \(elemento.isHittable)")
                XCTAssertLessThanOrEqual(elemento.frame.maxY, finestra.maxY + 1, "A1: «\(nome)» esce dalla finestra")
            }
        }
        let disponibile = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@ OR label BEGINSWITH %@",
                                                                 "Disponibile per", "Disponibile per")).firstMatch
        if disponibile.exists {
            nota("A1: «Disponibile per…» \(disponibile.frame); t11 B11 etichetta «\(disponibile.label)» valore «\(disponibile.value ?? "")»")
            XCTAssertLessThanOrEqual(disponibile.frame.maxY, finestra.maxY + 1, "A1: «Disponibile per…» esce dalla finestra")
        } else {
            nota("A1: «Disponibile per…» non trovato")
        }
        // A1: il pannello Impostazioni intero, fino a «Registro del collegamento».
        if tocca("Impostazioni") {
            aspettaUnPo(1)
            fotografa("pannello impostazioni")
            if let registro = trova("Registro del collegamento", dentro: "Impostazioni", secondi: 3) {
                nota("A1: «Registro del collegamento» \(registro.frame), cliccabile \(registro.isHittable)")
                XCTAssertTrue(registro.isHittable, "A1: «Registro del collegamento» non si clicca")
            }
            // t05 B5: gli interruttori hanno un nome.
            if tocca("Avvio e notifiche", dentro: "Impostazioni") {
                let nomi = app.switches.allElementsBoundByIndex.map { "«\($0.label.isEmpty ? $0.title : $0.label)»" }
                nota("t05 B5: interruttori \(nomi.joined(separator: ", "))")
                XCTAssertTrue(app.switches["Mostra le notifiche"].exists, "t05 B5: l'interruttore delle notifiche non ha nome")
                fotografa("avvio e notifiche")
            }
        }
    }

    /// t10 B9: nel menu Video, senza telefono, «Sfondo» e «Obiettivo» sono grigi.
    @MainActor func test04_menuVideoSenzaTelefono() {
        avviaPulito()
        attendi("Impostazioni")
        let video = app.menuBars.menuBarItems["Video"]
        guard video.waitForExistence(timeout: 5) else { nota("Menu Video non trovato"); return }
        video.click()
        aspettaUnPo(1)
        fotografa("menu video")
        for nome in ["Sfondo", "Obiettivo", "Foto", "Zoom avanti"] {
            let voce = app.menuItems[nome].firstMatch
            nota("t10 B9: «\(nome)» c'è \(voce.exists), attiva \(voce.exists && voce.isEnabled)")
            if nome == "Sfondo" || nome == "Obiettivo" {
                XCTAssertFalse(voce.exists && voce.isEnabled, "t10 B9: «\(nome)» attiva senza telefono")
            }
        }
        app.typeKey(.escape, modifierFlags: [])
    }
}
