// Copione del tester t10 (Stefano, curioso, ha Mac e PC): apre ogni menu della barra, prova le scorciatoie delle
// viste, tutte le pagine delle Impostazioni, il menu Aiuto e «App e assistenza», il gobbo, i profili, la lingua
// inglese. Annota nomi, voci grigie e finestre aperte, per confrontarle con l'app di Windows.

import XCTest

final class CopioneT10Stefano: CopioneCollaudo {

    private static let pagineImpostazioni = [
        "Fotocamera", "Effetti", "Sfondo", "Profili", "Qualità e collegamento", "Schermo", "Microfono", "Telefoni",
        "Sicurezza", "Uscite", "Schermata di attesa", "Gobbo", "Avvio e notifiche", "Registro del collegamento",
    ]

    // MARK: - Aiuti di questo copione

    /// I titoli delle finestre aperte, per le note.
    @MainActor private func finestre() -> String {
        app.windows.allElementsBoundByIndex.map { "«\($0.title)»" }.joined(separator: ", ")
    }

    /// Apre un menu della barra, fotografa e annota tutte le voci (titolo, grigia o no), poi lo chiude con Esc.
    @MainActor private func apriMenuDellaBarra(_ titolo: String, prefisso: String = "") {
        let voce = app.menuBars.firstMatch.menuBarItems[titolo]
        guard voce.exists else {
            nota("\(prefisso)Menu «\(titolo)»: non c'è nella barra dei menu")
            return
        }
        voce.click()
        aspettaUnPo(0.8)
        schermata("\(prefisso)menu \(titolo)")
        let voci = voce.descendants(matching: .menuItem).allElementsBoundByIndex.map { elemento -> String in
            let nome = elemento.title.isEmpty ? "(senza titolo)" : elemento.title
            return elemento.isEnabled ? nome : "\(nome) [grigia]"
        }
        nota("\(prefisso)Menu «\(titolo)»: \(voci.joined(separator: " | "))")
        tasto(XCUIKeyboardKey.escape.rawValue)
        // Un sottomenu aperto si chiude con un secondo Esc.
        tasto(XCUIKeyboardKey.escape.rawValue)
    }

    /// Sceglie una voce di un menu della barra. Dice se c'è riuscito.
    @discardableResult
    @MainActor private func scegliDalMenu(_ menu: String, _ titolo: String) -> Bool {
        let barra = app.menuBars.firstMatch.menuBarItems[menu]
        guard barra.exists else { nota("Menu «\(menu)» assente"); return false }
        barra.click()
        aspettaUnPo(0.5)
        let voce = barra.descendants(matching: .menuItem)[titolo]
        guard voce.exists else {
            nota("Menu «\(menu)»: la voce «\(titolo)» non c'è")
            tasto(XCUIKeyboardKey.escape.rawValue)
            return false
        }
        guard voce.isEnabled else {
            nota("Menu «\(menu)» › «\(titolo)»: grigia")
            tasto(XCUIKeyboardKey.escape.rawValue)
            return false
        }
        voce.click()
        aspettaUnPo(1.2)
        return true
    }

    // MARK: - Prove

    /// Tutti i menu della barra, uno per uno, e l'icona vicino all'orologio.
    @MainActor func test01_menuDellaBarra() {
        avviaPulito()
        attendi("Impostazioni")
        let titoli = app.menuBars.firstMatch.menuBarItems.allElementsBoundByIndex.map(\.title)
        nota("Menu nella barra: \(titoli.map { "«\($0)»" }.joined(separator: ", "))")
        for titolo in titoli where !titolo.isEmpty && titolo != "Apple" {
            apriMenuDellaBarra(titolo)
        }
        // L'icona nella barra dei menu (vicino all'orologio).
        let icone = app.statusItems.allElementsBoundByIndex
        nota("Icone nella barra dei menu di WebcamLR: \(icone.count)")
        if let icona = icone.first {
            icona.click()
            aspettaUnPo(0.8)
            fotografa("icona barra dei menu")
            let voci = app.descendants(matching: .menuItem).allElementsBoundByIndex
                .filter { $0.isHittable }.map(\.title)
            nota("Menu dell'icona: \(voci.joined(separator: " | "))")
            tasto(XCUIKeyboardKey.escape.rawValue)
        }
        fotografa("principale dopo i menu")
    }

    /// Le viste con le scorciatoie: ⌘1, ⌘2, ⇧⌘P, ⇧⌘M, ⌥⌘F, ⌃⌘F, ⌘, e Esc; poi ⌘W.
    @MainActor func test02_vistEScorciatoie() {
        avviaPulito()
        attendi("Impostazioni")
        fotografa("partenza")
        tasto("1", con: .command)
        aspettaUnPo(1.5)
        fotografa("⌘1 essenziale")
        tasto("2", con: .command)
        aspettaUnPo(1.5)
        fotografa("⌘2 completo")
        tasto("p", con: [.command, .shift])
        aspettaUnPo(1.5)
        fotografa("⇧⌘P vista pulita")
        tasto(XCUIKeyboardKey.escape.rawValue)
        aspettaUnPo(1)
        fotografa("vista pulita dopo Esc")
        if !esiste("Impostazioni") {
            nota("Esc non esce dalla vista pulita: la ritolgo con ⇧⌘P")
            tasto("p", con: [.command, .shift])
            aspettaUnPo(1)
        }
        tasto("m", con: [.command, .shift])
        aspettaUnPo(2)
        nota("Dopo ⇧⌘M finestre: \(finestre())")
        fotografa("⇧⌘M finestra mini")
        tasto(XCUIKeyboardKey.escape.rawValue)
        aspettaUnPo(1)
        nota("Finestra mini, dopo Esc finestre: \(finestre())")
        fotografa("mini dopo Esc")
        tasto("m", con: [.command, .shift])
        aspettaUnPo(1.5)
        nota("Dopo il secondo ⇧⌘M finestre: \(finestre())")
        tasto("f", con: [.command, .option])
        aspettaUnPo(1)
        fotografa("⌥⌘F riempi")
        tasto("f", con: [.command, .option])
        tasto("f", con: [.command, .control])
        aspettaUnPo(3)
        fotografa("⌃⌘F schermo intero")
        tasto(XCUIKeyboardKey.escape.rawValue)
        aspettaUnPo(3)
        fotografa("schermo intero dopo Esc")
        tasto(",", con: .command)
        aspettaUnPo(1.5)
        fotografa("⌘, impostazioni")
        tasto(XCUIKeyboardKey.escape.rawValue)
        aspettaUnPo(1)
        fotografa("impostazioni dopo Esc")
        // Scorciatoie che senza telefono dovrebbero non fare niente (o dire perché).
        for (tasto1, mod, nome) in [("t", XCUIElement.KeyModifierFlags.command, "⌘T foto"),
                                    ("r", XCUIElement.KeyModifierFlags.command, "⌘R registra")] {
            tasto(tasto1, con: mod)
            aspettaUnPo(1)
            fotografa("\(nome) senza telefono")
        }
        tasto("w", con: .command)
        aspettaUnPo(1.5)
        nota("Dopo ⌘W finestre: \(finestre())")
        fotografa("dopo ⌘W")
        // Come la si riapre? Dal menu Finestra, se c'è la voce.
        if scegliDalMenu("Finestra", "WebcamLR") {
            nota("Menu Finestra › WebcamLR: finestre \(finestre())")
            fotografa("riaperta da Finestra")
        }
    }

    /// Ogni pagina del pannello Impostazioni: schermata in alto e albero (con tutti i testi, anche sotto il bordo).
    @MainActor func test03_impostazioni() {
        avviaPulito()
        attendi("Impostazioni")
        tocca("Impostazioni")
        fotografa("impostazioni elenco")
        for pagina in Self.pagineImpostazioni {
            guard tocca(pagina, dentro: "Impostazioni") else { continue }
            aspettaUnPo(0.8)
            fotografa("pagina \(pagina)")
            tocca("Indietro", dentro: "Impostazioni")
        }
        tocca("Chiudi le impostazioni")
    }

    /// Il menu Aiuto voce per voce, il pulsante «Aiuto» della finestra, «App e assistenza» con le sue schede,
    /// «Informazioni su WebcamLR» e «Verifica aggiornamenti…».
    @MainActor func test04_aiuto() {
        avviaPulito()
        attendi("Impostazioni")
        for voce in ["Guida di WebcamLR", "Domande frequenti", "Il telefono non trova il Mac?", "Segnala un bug…"] {
            if scegliDalMenu("Aiuto", voce) {
                nota("Aiuto › \(voce): finestre \(finestre())")
                fotografa("aiuto \(voce)")
                tasto("w", con: .command)
            }
        }
        tasto("?", con: .command)
        aspettaUnPo(1.5)
        nota("⌘? finestre: \(finestre())")
        fotografa("⌘? guida")
        // Le schede della finestra «App e assistenza».
        for scheda in ["Guida", "WebcamLR Pro", "Domande frequenti", "Segnala un bug", "Informazioni"] {
            if tocca(scheda, dentro: "Barra laterale") {
                aspettaUnPo(1)
                fotografa("app e assistenza \(scheda)")
            }
        }
        // Un link nella guida o nelle domande: «Altre risposte sul sito» o simili.
        if toccaSePresente("Domande frequenti", dentro: "Barra laterale") {
            scrivi("firewall", nelCampo: "Cerca")
            aspettaUnPo(1)
            fotografa("domande cerca firewall")
            scrivi("zzzqqq", nelCampo: "Cerca")
            aspettaUnPo(1)
            fotografa("domande cerca senza risultati")
        }
        tasto("w", con: .command)
        // Il pulsante «Aiuto» della finestra principale (non il menu della barra).
        let pulsante = app.windows["WebcamLR"].descendants(matching: .any).matching(NSPredicate(format: "label == 'Aiuto' OR title == 'Aiuto'")).firstMatch
        if pulsante.exists {
            pulsante.click()
            aspettaUnPo(0.8)
            fotografa("pulsante Aiuto della finestra")
            let voci = app.windows["WebcamLR"].descendants(matching: .menuItem).allElementsBoundByIndex.map(\.title)
            nota("Pulsante «Aiuto» della finestra: \(voci.joined(separator: " | "))")
            tasto(XCUIKeyboardKey.escape.rawValue)
        } else {
            nota("Nella finestra principale non trovo un pulsante «Aiuto»")
        }
        if scegliDalMenu("WebcamLR", "Informazioni su WebcamLR") {
            nota("Informazioni: finestre \(finestre())")
            fotografa("informazioni su WebcamLR")
            tasto("w", con: .command)
        }
        if scegliDalMenu("WebcamLR", "Verifica aggiornamenti…") {
            aspettaUnPo(4)
            fotografa("verifica aggiornamenti")
            tasto(XCUIKeyboardKey.return.rawValue)
        }
    }

    /// Il gobbo (dalla pagina delle Impostazioni) e la pagina Profili, senza telefono.
    @MainActor func test05_gobboEProfili() {
        avviaPulito()
        attendi("Impostazioni")
        tocca("Impostazioni")
        if tocca("Gobbo", dentro: "Impostazioni") {
            fotografa("pagina gobbo")
            if tocca("Apri il gobbo") {
                aspettaUnPo(1.5)
                nota("Apri il gobbo: finestre \(finestre())")
                fotografa("finestra gobbo")
                let campo = app.windows["Gobbo"].textViews.firstMatch
                if campo.exists {
                    campo.click()
                    campo.typeText("Buongiorno a tutti, oggi vi parlo di WebcamLR. 1234 + - F")
                    aspettaUnPo(1)
                    fotografa("gobbo con testo")
                    nota("Testo nel gobbo dopo la scrittura (con 1, +, −, F che sono anche scorciatoie): «\(campo.value as? String ?? "?")»")
                } else {
                    nota("Nella finestra Gobbo non trovo il campo di testo")
                }
                tasto("w", con: .command)
            }
            tocca("Indietro", dentro: "Impostazioni")
        }
        if tocca("Profili", dentro: "Impostazioni") {
            fotografa("pagina profili")
            scorri(giu: true, volte: 2, dentro: "Impostazioni")
            fotografa("pagina profili in fondo")
        }
    }

    /// I menu della barra in inglese: stessi menu, nomi tradotti?
    @MainActor func test06_menuInglese() {
        avviaPulito(lingua: .inglese)
        attendi("Settings")
        let titoli = app.menuBars.firstMatch.menuBarItems.allElementsBoundByIndex.map(\.title)
        nota("EN menu nella barra: \(titoli.map { "«\($0)»" }.joined(separator: ", "))")
        for titolo in titoli where !titolo.isEmpty && titolo != "Apple" {
            apriMenuDellaBarra(titolo, prefisso: "EN ")
        }
        if tocca("Settings") {
            fotografa("EN impostazioni elenco")
        }
    }
}
