// Copione t05 del Mac (Francesca, impiegata: WebcamLR ogni giorno per Zoom/Teams, vuole zero passi).
// Secondo e terzo avvio dopo il primo (l'app ricorda? riparte dalla schermata giusta? ripropone qualcosa?),
// Impostazioni › Avvio e notifiche, telefoni fidati (elenco e rimozione).
// Il Mac di GitHub non ha telefoni: i telefoni fidati si mettono con un argomento di avvio (`-telefoniFidati`,
// dominio degli argomenti di UserDefaults), come se l'app li avesse già salvati.

import XCTest

final class CopioneT05: CopioneCollaudo {

    /// Due telefoni fidati finti: impronta → nome, come li salva l'app (Preferenze.telefoniFidati).
    private static let fidatiFinti = "{ \"A1B2C3D4E5F60718\" = \"iPhone di Francesca\"; \"0F0E0D0C0B0A0908\" = \"iPad di casa\"; }"

    // MARK: - Aiuti del tester t05

    /// Esce come fa una persona: ⌘Q. Se compare una domanda la fotografa e risponde «Esci da WebcamLR».
    @MainActor private func esciConComandoQ(_ quando: String) {
        app.typeKey("q", modifierFlags: .command)
        let limite = Date().addingTimeInterval(10)
        while app.state != .notRunning && Date() < limite {
            if app.dialogs.firstMatch.exists || app.sheets.firstMatch.exists {
                fotografa("\(quando) domanda all'uscita")
                nota("\(quando): ⌘Q apre una domanda: \(testiDelleDomande())")
                if !toccaSePresente("Esci da WebcamLR", secondi: 1) { toccaSePresente("Esci", secondi: 1) }
            }
            aspettaUnPo(0.5)
        }
        if app.state != .notRunning {
            nota("\(quando): dopo ⌘Q l'app è ancora aperta dopo 10 s (stato \(app.state.rawValue)): la chiudo io")
            fotografa("\(quando) ancora aperta dopo cmd q")
            app.terminate()
        } else {
            nota("\(quando): ⌘Q chiude l'app")
        }
    }

    /// Riapre come dal Dock, senza dati cancellati e SENZA `-ApplePersistenceIgnoreState`: macOS può riaprire le
    /// finestre come le aveva lasciate. Misura quanto ci vuole a vedere «Impostazioni».
    @MainActor private func riapri(_ quale: String, argomenti: [String] = []) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = LinguaCollaudo.italiano.argomenti + argomenti
        let inizio = Date()
        app.launch()
        let pronto = esiste("Impostazioni", secondi: 20)
        nota(String(format: "%@: finestra principale %@ in %.1f s", quale, pronto ? "pronta" : "NON pronta",
                    Date().timeIntervalSince(inizio)))
        if let domanda = attendiDomandaDiSistema(secondi: 3) {
            fotografa("\(quale) domanda di sistema")
            nota("\(quale): domanda di sistema «\(domanda.label)» (ancora una volta?)")
            rispondiAlleDomandeDiSistema(.concedi)
        } else {
            nota("\(quale): nessuna domanda di sistema")
        }
        aspettaUnPo(1.5)
    }

    /// Le finestre aperte e i fogli, nel registro.
    @MainActor private func annotaFinestre(_ quando: String) {
        let finestre = app.windows.allElementsBoundByIndex.map { "«\($0.title)» \(Int($0.frame.width))×\(Int($0.frame.height))" }
        nota("\(quando): \(finestre.count) finestre: \(finestre.joined(separator: ", ")); fogli \(app.sheets.count), "
             + "pannello Impostazioni aperto: \(app.buttons["Chiudi le impostazioni"].exists)")
    }

    /// Gli interruttori e le caselle visibili, con il loro valore (per vedere che cosa l'app ha ricordato).
    @MainActor private func annotaInterruttori(_ quando: String) {
        let tutti = app.switches.allElementsBoundByIndex + app.checkBoxes.allElementsBoundByIndex
        let righe = tutti.prefix(30).map { elemento -> String in
            let nome = elemento.label.isEmpty ? elemento.title : elemento.label
            return "«\(nome)»=\(elemento.value.map { "\($0)" } ?? "?")"
        }
        nota("\(quando): interruttori \(righe.joined(separator: ", "))")
    }

    /// I testi delle finestre di dialogo aperte (NSAlert).
    @MainActor private func testiDelleDomande() -> String {
        let contenitori = app.dialogs.allElementsBoundByIndex + app.sheets.allElementsBoundByIndex
        return contenitori.map { contenitore in
            let testi = contenitore.staticTexts.allElementsBoundByIndex.prefix(6).compactMap { $0.value as? String }
            let pulsanti = contenitore.buttons.allElementsBoundByIndex.prefix(6).map { $0.title.isEmpty ? $0.label : $0.title }
            return "\(testi) pulsanti \(pulsanti)"
        }.joined(separator: " / ")
    }

    /// Clic su un pulsante della finestra di dialogo aperta (NSAlert di `Domanda.conferma`).
    @MainActor @discardableResult
    private func rispondiDomanda(_ pulsante: String) -> Bool {
        for contenitore in [app.dialogs.firstMatch, app.sheets.firstMatch, app.alerts.firstMatch] where contenitore.exists {
            let bottone = contenitore.buttons[pulsante]
            if bottone.exists {
                bottone.click()
                aspettaUnPo()
                return true
            }
        }
        nota("Nessuna finestra di dialogo con «\(pulsante)»: \(testiDelleDomande())")
        return false
    }

    @MainActor private func apriPagina(_ pagina: String) -> Bool {
        if !app.buttons["Chiudi le impostazioni"].exists {
            guard tocca("Impostazioni") else { return false }
        } else {
            // Il pannello è già aperto, magari su un'altra pagina: torna all'elenco.
            toccaSePresente("Indietro", dentro: "Impostazioni", secondi: 1)
        }
        return tocca(pagina, dentro: "Impostazioni")
    }

    // MARK: - Prove

    /// Primo, secondo e terzo avvio come li fa Francesca: apre, chiude con ⌘Q, riapre. Nel secondo cambia due
    /// preferenze (notifiche spente, vista) e lascia aperto il pannello: il terzo le ricorda? Poi chiude la finestra
    /// (⌘W) e torna all'app dal Dock.
    @MainActor func test01_treAvvii() {
        permessi = .nonRispondere
        avviaPulito()
        aspettaUnPo(3)
        if let domanda = attendiDomandaDiSistema(secondi: 5) {
            fotografa("avvio1 domanda di sistema")
            nota("Avvio 1: domanda di sistema «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.concedi)
        } else {
            nota("Avvio 1: nessuna domanda di sistema")
        }
        permessi = .concedi
        attendi("Impostazioni")
        annotaFinestre("Avvio 1")
        fotografa("avvio1 principale")
        esciConComandoQ("Avvio 1")

        riapri("Avvio 2")
        annotaFinestre("Avvio 2")
        fotografa("avvio2 principale")
        // Francesca passa alla vista completa (⌘2 se c'è) e spegne le notifiche.
        tasto("2", con: .command)
        aspettaUnPo(1)
        fotografa("avvio2 dopo cmd 2")
        if apriPagina("Avvio e notifiche") {
            annotaInterruttori("Avvio 2, Avvio e notifiche prima")
            tocca("Mostra le notifiche", dentro: "Impostazioni")
            aspettaUnPo(1)
            annotaInterruttori("Avvio 2, Avvio e notifiche dopo il clic su notifiche")
            fotografa("avvio2 notifiche spente")
        }
        annotaFinestre("Avvio 2 prima di uscire")
        esciConComandoQ("Avvio 2")

        riapri("Avvio 3")
        annotaFinestre("Avvio 3")
        fotografa("avvio3 principale")
        if apriPagina("Avvio e notifiche") {
            annotaInterruttori("Avvio 3, Avvio e notifiche")
            fotografa("avvio3 avvio e notifiche")
            tocca("Chiudi le impostazioni")
        }

        // Chiude la finestra (⌘W, come il pallino rosso): l'app resta? Si torna con un clic sull'icona del Dock.
        tasto("w", con: .command)
        aspettaUnPo(2)
        nota("Dopo ⌘W: stato dell'app \(app.state.rawValue) (4 = in primo piano, 3 = dietro, 1 = chiusa), finestre \(app.windows.count)")
        fotografa("dopo cmd w")
        if app.state != .notRunning {
            app.activate()
            aspettaUnPo(2)
            nota("Dopo activate (come il Dock): finestre \(app.windows.count), «Impostazioni» visibile \(esiste("Impostazioni", secondi: 3))")
            fotografa("tornata dal dock")
        }
    }

    /// Impostazioni › Avvio e notifiche: «Apri WebcamLR all'avvio del Mac» acceso (app firmata «-», fuori da
    /// Applicazioni: che cosa dice?), le notifiche spente e riaccese (macOS chiede?), poi ⌘Q e riapertura.
    @MainActor func test02_avvioENotifiche() {
        avviaPulito()
        attendi("Impostazioni")
        guard apriPagina("Avvio e notifiche") else { return }
        fotografa("avvio e notifiche")
        annotaInterruttori("Pagina all'inizio")

        tocca("Apri WebcamLR all'avvio del Mac", dentro: "Impostazioni")
        aspettaUnPo(2)
        if let domanda = attendiDomandaDiSistema(secondi: 4) {
            fotografa("avvio automatico domanda di sistema")
            nota("Avvio automatico: domanda/avviso di sistema «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.concedi)
        }
        annotaInterruttori("Dopo il clic su «Apri all'avvio»")
        fotografa("avvio automatico acceso")
        for frase in ["Da approvare", "Non sono riuscito", "macOS non trova", "si apre da sola", "Spento"] where esiste(frase) {
            nota("Sotto l'interruttore: «\(frase)…»")
        }

        tocca("Mostra le notifiche", dentro: "Impostazioni")
        aspettaUnPo(1)
        fotografa("notifiche spente")
        permessi = .nonRispondere
        tocca("Mostra le notifiche", dentro: "Impostazioni")
        if let domanda = attendiDomandaDiSistema(secondi: 5) {
            fotografa("notifiche domanda di sistema")
            nota("Notifiche riaccese: domanda di sistema «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.concedi)
        } else {
            nota("Notifiche riaccese: nessuna domanda di sistema")
        }
        permessi = .concedi
        aspettaUnPo(1)
        annotaInterruttori("Dopo notifiche spente e riaccese")
        fotografa("notifiche riaccese")
        scorri(giu: true, volte: 2, dentro: "Impostazioni")
        fotografa("avvio e notifiche in fondo")

        esciConComandoQ("Avvio e notifiche")
        riapri("Riaperta")
        if apriPagina("Avvio e notifiche") {
            annotaInterruttori("Dopo la riapertura")
            fotografa("avvio e notifiche dopo la riapertura")
            // Lascia il Mac come prima: l'avvio automatico spento.
            if esiste("si apre da sola") || esiste("Da approvare") {
                tocca("Apri WebcamLR all'avvio del Mac", dentro: "Impostazioni")
                aspettaUnPo(1)
                annotaInterruttori("Spento alla fine")
            }
        }
    }

    /// I telefoni fidati: dove li vede Francesca (colonna, Impostazioni › Telefoni › «Telefoni fidati…», Sicurezza),
    /// «Rimuovi» con «Annulla» e poi davvero, e dopo la riapertura.
    @MainActor func test03_telefoniFidati() {
        avvia(argomenti: ["-telefoniFidati", Self.fidatiFinti])
        attendi("Impostazioni")
        fotografa("principale con due fidati")
        nota("Colonna: «iPhone di Francesca» visibile \(esiste("iPhone di Francesca")), «Non collegato» \(esiste("Non collegato"))")
        tasto("2", con: .command)
        aspettaUnPo(1)
        fotografa("completo con due fidati")
        nota("Vista completa: «iPhone di Francesca» visibile \(esiste("iPhone di Francesca"))")

        guard apriPagina("Telefoni") else { return }
        fotografa("impostazioni telefoni")
        if tocca("Telefoni fidati…", dentro: "Impostazioni") || tocca("Telefoni fidati") {
            aspettaUnPo(1)
            fotografa("foglio telefoni fidati")
            // Prima «Rimuovi» e poi «Annulla»: non deve togliere niente.
            if tocca("Rimuovi iPad di casa") {
                fotografa("domanda rimuovi ipad")
                nota("Domanda: \(testiDelleDomande())")
                rispondiDomanda("Annulla")
                nota("Dopo «Annulla»: «iPad di casa» c'è ancora \(esiste("iPad di casa"))")
                fotografa("dopo annulla")
            }
            if tocca("Rimuovi iPhone di Francesca") {
                rispondiDomanda("Rimuovi")
                aspettaUnPo(1)
                nota("Dopo «Rimuovi»: «iPhone di Francesca» c'è ancora \(esiste("iPhone di Francesca"))")
                fotografa("foglio dopo rimuovi iphone")
            }
            chiudiFoglio()
        }
        if apriPagina("Sicurezza") {
            fotografa("sicurezza")
            if tocca("Rimuovi iPad di casa") {
                rispondiDomanda("Rimuovi")
                aspettaUnPo(1)
                fotografa("sicurezza dopo rimuovi ipad")
                nota("Sicurezza dopo la rimozione: «Nessun telefono fidato» \(esiste("Nessun telefono fidato"))")
            }
        }
        esciConComandoQ("Telefoni fidati")
        riapri("Dopo la rimozione")
        fotografa("principale dopo la rimozione")
        nota("Dopo la riapertura: «iPhone di Francesca» \(esiste("iPhone di Francesca")), «iPad di casa» \(esiste("iPad di casa"))")
    }
}
