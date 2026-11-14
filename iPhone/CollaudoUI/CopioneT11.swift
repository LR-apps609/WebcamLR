// Copione t11 (Marta, cieca, usa VoiceOver): per ogni schermata raggiungibile senza computer, schermata, albero e
// controllo di accessibilità di Xcode (performAccessibilityAudit). Ogni problema trovato finisce in note.txt;
// il controllo non fa fallire il test, così si arriva in fondo.

import XCTest

final class CopioneT11: CopioneCollaudo {

    /// Controllo di accessibilità della schermata attuale: annota ogni problema (tipo, elemento, descrizione).
    @MainActor func controlla(_ nome: String) {
        fotografa(nome)
        var problemi: [String] = []
        do {
            try app.performAccessibilityAudit(for: .all) { problema in
                let elemento = problema.element.map { "\($0.elementType.rawValue) «\($0.label)» id=\($0.identifier)" } ?? "(nessun elemento)"
                problemi.append("[\(problema.auditType.rawValue)] \(problema.compactDescription) · \(elemento) · \(problema.detailedDescription)")
                return true
            }
        } catch {
            problemi.append("controllo non riuscito: \(error)")
        }
        nota("CONTROLLO \(nome): \(problemi.count) problemi\n" + problemi.joined(separator: "\n"))
        // Pulsanti senza nome e immagini annunciate: elenco di tutti i pulsanti e immagini con etichetta e identificatore.
        let pulsanti = app.buttons.allElementsBoundByIndex.map { "pulsante «\($0.label)» id=\($0.identifier)" }
        let immagini = app.images.allElementsBoundByIndex.map { "immagine «\($0.label)» id=\($0.identifier)" }
        nota("ELEMENTI \(nome):\n" + (pulsanti + immagini).joined(separator: "\n"))
    }

    @MainActor func test01_presentazione() {
        permessi = .nonRispondere
        avviaPulito()
        attendi("presentazione.avanti.webcam")
        controlla("presentazione 1")
        tocca("presentazione.avanti.webcam")
        controlla("presentazione 2")
        tocca("presentazione.avanti.computer")
        controlla("presentazione 3")
        tocca("presentazione.avanti.impostazioni")
        controlla("presentazione 4")
        permessi = .concedi
        tocca("presentazione.inizia")
        for _ in 0..<2 { if attendiDomandaDiSistema(secondi: 5) != nil { rispondiAlleDomandeDiSistema() } }
        chiudiAvvisoPortachiavi()
        attendi("Cerco il tuo computer")
        controlla("principale cerco")
        if esiste("Non trovo nessun computer", secondi: 25) { controlla("principale non trovo") }
    }

    @MainActor func test02_principaleEFogli() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        if tocca("Sblocca WebcamLR Pro") {
            aspettaUnPo(4)
            controlla("foglio pro")
            chiudiFoglio()
        }
        if tocca("Inquadra il QR code del computer") {
            aspettaUnPo(2)
            controlla("lettore QR")
            chiudiFoglio()
        }
        if tocca("Usa il cavo USB") {
            controlla("cavo USB")
            chiudiFoglio()
        }
        if tocca("Collega a mano (indirizzo)") {
            controlla("collega a mano")
            scrivi("abc", nelCampo: "192.168.1.20")
            toccaSePresente("Collega")
            aspettaUnPo(1)
            controlla("indirizzo non valido")
            toccaSePresente("Annulla")
        }
    }

    @MainActor func test03_impostazioni() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        tocca("Impostazioni")
        attendi("Fine")
        controlla("impostazioni")
        scorri(giu: true, volte: 2)
        controlla("impostazioni in fondo")
        scorri(giu: false, volte: 3)
        if tocca("App e assistenza") {
            controlla("app e assistenza")
            if tocca("Segnala un bug") { controlla("segnala un bug"); indietro() }
            if tocca("Domande frequenti") { controlla("domande frequenti"); indietro() }
            indietro()
        }
        if tocca("Registro del collegamento") { controlla("registro"); indietro() }
    }

    @MainActor func test04_caratteriGrandi() {
        avviaPulito(caratteriGrandi: true)
        superaPresentazione()
        attendi("Cerco il tuo computer")
        controlla("XXXL principale")
        if tocca("Impostazioni") { controlla("XXXL impostazioni") }
    }
}
