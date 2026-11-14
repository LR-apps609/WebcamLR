// Copione t19 (Emma, inglese): il Mac in inglese. Finestra principale, tutti i menu della barra, le 14 pagine di
// Impostazioni, la finestra «App e assistenza» con le schede e «Segnala un bug».

import XCTest

final class CopioneT19: CopioneCollaudo {

    private static let pagine = [
        "Camera", "Effects", "Background", "Profiles", "Quality and connection", "Screen", "Microphone", "Phones",
        "Security", "Outputs", "Waiting screen", "Teleprompter", "Startup and notifications", "Connection log",
    ]

    /// Finestra principale e ogni menu della barra dei menu, in inglese.
    @MainActor func test01_finestraEMenu() {
        permessi = .concedi
        avviaPulito(lingua: .inglese)
        aspettaUnPo(3)
        if attendiDomandaDiSistema(secondi: 4) != nil {
            fotografa("en domanda di sistema")
            rispondiAlleDomandeDiSistema(.concedi)
        }
        attendi("Settings")
        fotografa("en finestra principale")
        let voci = app.menuBars.menuBarItems.allElementsBoundByIndex
        nota("Menu della barra: \(voci.map { "«\($0.title)»" }.joined(separator: ", "))")
        for (i, voce) in voci.enumerated() where i > 0 {
            let titolo = voce.title
            voce.click()
            aspettaUnPo(0.8)
            fotografa("en menu \(i) \(titolo)")
            let elementi = voce.menuItems.allElementsBoundByIndex.map { $0.title }.filter { !$0.isEmpty }
            nota("Menu «\(titolo)»: \(elementi.joined(separator: " | "))")
            tasto(XCUIKeyboardKey.escape.rawValue)
        }
        // Il menu nella barra in alto a destra (se c'è).
        let extra = app.statusItems.allElementsBoundByIndex
        nota("Elementi nella barra di stato: \(extra.count)")
        if let primo = extra.first {
            primo.click()
            aspettaUnPo(1)
            fotografa("en menu barra di stato")
            let elementi = primo.menuItems.allElementsBoundByIndex.map { $0.title }.filter { !$0.isEmpty }
            nota("Barra di stato: \(elementi.joined(separator: " | "))")
            tasto(XCUIKeyboardKey.escape.rawValue)
        }
    }

    /// Le 14 pagine di Impostazioni in inglese.
    @MainActor func test02_impostazioni() {
        avviaPulito(lingua: .inglese)
        attendi("Settings")
        tocca("Settings")
        fotografa("en impostazioni elenco")
        for pagina in Self.pagine {
            guard tocca(pagina, dentro: "Settings") else { continue }
            fotografa("en imp \(pagina)")
            scorri(giu: true, volte: 2, dentro: "Settings")
            fotografa("en imp \(pagina) in fondo")
            if !toccaSePresente("Back", dentro: "Settings") { toccaSePresente("Back") }
        }
        toccaSePresente("Close settings")
        fotografa("en impostazioni chiuse")
    }

    /// Menu Aiuto e finestra «App e assistenza»: Guida, Pro, Domande frequenti, Segnala un bug, Informazioni.
    @MainActor func test03_aiuto() {
        avviaPulito(lingua: .inglese)
        attendi("Settings")
        guard tocca("Help") else { return }
        fotografa("en menu help")
        guard tocca("Guide") else { return }
        aspettaUnPo(1.5)
        fotografa("en guida")
        scorri(giu: true, volte: 3)
        fotografa("en guida in fondo")
        for scheda in ["WebcamLR Pro", "FAQ", "Report a bug", "About"] {
            if toccaSePresente(scheda, dentro: "Sidebar") || toccaSePresente(scheda, dentro: "Barra laterale") || tocca(scheda) {
                aspettaUnPo(1.5)
                fotografa("en app \(scheda)")
                scorri(giu: true, volte: 3)
                fotografa("en app \(scheda) in fondo")
                if scheda == "Report a bug" {
                    scorri(giu: false, volte: 3)
                    let campo = app.textViews.firstMatch
                    if campo.waitForExistence(timeout: 2) {
                        campo.click()
                        campo.typeText("The video freezes after one minute")
                        aspettaUnPo(1)
                        fotografa("en segnala scritto")
                    } else {
                        nota("Segnala un bug: nessun campo di testo")
                    }
                }
            }
        }
        tasto("w", con: .command)
        fotografa("en fine")
    }
}
