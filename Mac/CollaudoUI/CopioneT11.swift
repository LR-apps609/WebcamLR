// Copione t11 (Marta, cieca, usa VoiceOver e la tastiera): finestra principale (QR code e indirizzo scritto),
// pannello Impostazioni, «App e assistenza». Per ogni schermata: fotografia, albero, controllo di accessibilità
// di Xcode (ogni problema in note.txt) e un giro col tasto Tab che annota dove va il fuoco.

import XCTest

final class CopioneT11: CopioneCollaudo {

    @MainActor func controlla(_ nome: String) {
        fotografa(nome)
        var problemi: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { problema in
                let elemento = problema.element.map { "\($0.elementType.rawValue) «\($0.label)» titolo=«\($0.title)» id=\($0.identifier)" } ?? "(nessun elemento)"
                problemi.append("[\(problema.auditType.rawValue)] \(problema.compactDescription) · \(elemento) · \(problema.detailedDescription)")
                return true
            }
        } catch {
            problemi.append("controllo non riuscito: \(error)")
        }
        nota("CONTROLLO \(nome): \(problemi.count) problemi\n" + problemi.joined(separator: "\n"))
        let pulsanti = app.buttons.allElementsBoundByIndex.map { "pulsante «\($0.label)» titolo=«\($0.title)» id=\($0.identifier)" }
        let immagini = app.images.allElementsBoundByIndex.map { "immagine «\($0.label)» titolo=«\($0.title)» id=\($0.identifier)" }
        nota("ELEMENTI \(nome):\n" + (pulsanti + immagini).joined(separator: "\n"))
    }

    /// Preme Tab `volte` volte e annota l'elemento con il fuoco della tastiera dopo ogni pressione.
    @MainActor func giroTab(_ nome: String, volte: Int = 14) {
        var righe: [String] = []
        let fuoco = NSPredicate(format: "hasKeyboardFocus == true")
        for numero in 1...volte {
            app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
            aspettaUnPo(0.4)
            let e = app.descendants(matching: .any).matching(fuoco).firstMatch
            righe.append(e.exists ? "Tab \(numero): \(e.elementType.rawValue) «\(e.label)» titolo=«\(e.title)» id=\(e.identifier)" : "Tab \(numero): nessun elemento con il fuoco")
        }
        nota("TAB \(nome):\n" + righe.joined(separator: "\n"))
        schermata("\(nome) dopo i Tab")
    }

    @MainActor func test01_principale() {
        avviaPulito()
        aspettaUnPo(3)
        rispondiAlleDomandeDiSistema(.concedi)
        attendi("Impostazioni")
        aspettaUnPo(3)
        controlla("finestra principale")
        giroTab("finestra principale")
    }

    @MainActor func test02_impostazioni() {
        avviaPulito()
        attendi("Impostazioni")
        tasto(",", con: .command)
        aspettaUnPo(1)
        controlla("impostazioni elenco")
        giroTab("impostazioni elenco", volte: 10)
        for pagina in ["Fotocamera", "Qualità e collegamento", "Telefoni", "Sicurezza", "Avvio e notifiche"] {
            guard tocca(pagina, dentro: "Impostazioni") else { continue }
            controlla("impostazioni \(pagina)")
            tocca("Indietro", dentro: "Impostazioni")
        }
        app.typeKey(.escape, modifierFlags: [])
        aspettaUnPo()
        fotografa("dopo Esc sulle impostazioni")
        nota("Dopo Esc il pannello Impostazioni c'è ancora: \(esiste("Chiudi le impostazioni"))")
    }

    @MainActor func test03_aiuto() {
        avviaPulito()
        attendi("Impostazioni")
        if tocca("Aiuto") {
            if tocca("Guida") {
                aspettaUnPo(1.5)
                controlla("app e assistenza guida")
                for scheda in ["Domande frequenti", "Segnala un bug"] where tocca(scheda, dentro: "Barra laterale") {
                    aspettaUnPo(1)
                    controlla("app e assistenza \(scheda)")
                }
            }
        }
    }
}
