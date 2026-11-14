// Collaudo 20 · t07 (Paolo, attento alla privacy): nega i permessi uno per uno, li toglie a metà, legge i testi
// sulla privacy (domande frequenti, «Segnala un bug» e i dati tecnici). Sul simulatore niente fotocamera né computer.

import XCTest

final class CopionePaolo: CopioneCollaudo {

    /// Le domande di iOS all'«Inizia», fotografate una per una e rifiutate tutte.
    @MainActor private func presentazioneRifiutando(_ quale: (Int, String) -> RispostaPermessi) {
        permessi = .nonRispondere
        attendi("presentazione.salta")
        toccaSePresente("presentazione.salta", secondi: 2)
        aspettaUnPo(1)
        fotografa("pagina dei permessi")
        tocca("presentazione.inizia")
        for numero in 1...3 {
            guard let domanda = attendiDomandaDiSistema(secondi: 6) else {
                nota("Domanda di sistema \(numero): non è comparsa")
                break
            }
            let titolo = domanda.label
            fotografa("domanda di sistema \(numero)")
            let risposta = quale(numero, titolo)
            nota("Domanda di sistema \(numero): «\(titolo)» → \(risposta == .nega ? "Non consentire" : "Consenti")")
            rispondiAlleDomandeDiSistema(risposta, quante: 1)
        }
        chiudiAvvisoPortachiavi()
    }

    @MainActor private func annotaAvvisi(_ dove: String) {
        for testo in ["Serve il permesso «Fotocamera»", "Serve il permesso «Microfono»", "Serve il permesso «Rete locale»",
                      "non può usare la fotocamera", "Microfono non consentito", "Apri Impostazioni"] {
            nota("\(dove): «\(testo)» \(esiste(testo) ? "C'È" : "non c'è")")
        }
    }

    /// Tutto negato: cosa dice la principale, il lettore QR, e poi le domande frequenti sulla privacy.
    @MainActor func test01_negaTutto() {
        avviaPulito()
        presentazioneRifiutando { _, _ in .nega }
        permessi = .nega
        aspettaUnPo(3)
        fotografa("principale dopo i rifiuti")
        annotaAvvisi("principale dopo i rifiuti")
        aspettaUnPo(15)
        fotografa("principale dopo 20 secondi")
        annotaAvvisi("principale dopo 20 secondi")
        scorri(giu: true)
        fotografa("principale in fondo")
        scorri(giu: false)
        if tocca("Inquadra il QR code del computer") {
            aspettaUnPo(2)
            fotografa("lettore QR con fotocamera negata")
            annotaAvvisi("lettore QR")
            chiudiFoglio()
        }
        // Riapertura: l'app ricorda di dire che manca il permesso?
        chiudiApp()
        avvia()
        aspettaUnPo(3)
        fotografa("riaperta con tutto negato")
        annotaAvvisi("riaperta")
    }

    /// Solo la fotocamera negata (microfono consentito), poi solo il microfono negato.
    @MainActor func test02_unoPerUno() {
        avviaPulito()
        presentazioneRifiutando { _, titolo in titolo.lowercased().contains("camera") || titolo.lowercased().contains("fotocamera") ? .nega : .concedi }
        permessi = .concedi
        aspettaUnPo(3)
        fotografa("solo fotocamera negata")
        annotaAvvisi("solo fotocamera negata")

        avviaPulito()
        presentazioneRifiutando { _, titolo in titolo.lowercased().contains("micro") ? .nega : .concedi }
        aspettaUnPo(3)
        fotografa("solo microfono negato")
        annotaAvvisi("solo microfono negato")
        if tocca("Impostazioni") {
            aspettaUnPo(1)
            fotografa("impostazioni con microfono negato")
            scorri(giu: true, volte: 2)
            fotografa("impostazioni in fondo con microfono negato")
            chiudiFoglio()
        }
    }

    /// Permessi concessi, poi tolti mentre l'app è aperta (come da Impostazioni di iOS: iOS chiude l'app).
    @MainActor func test03_revocaAMeta() {
        avviaPulito()
        superaPresentazione()
        aspettaUnPo(3)
        fotografa("principale con tutto concesso")
        app.resetAuthorizationStatus(for: .camera)
        aspettaUnPo(2)
        nota("Dopo la revoca della fotocamera lo stato dell'app è \(app.state.rawValue) (1 = non in esecuzione, 4 = in primo piano)")
        permessi = .nonRispondere
        app.activate()
        aspettaUnPo(3)
        if let domanda = attendiDomandaDiSistema(secondi: 6) {
            fotografa("dopo la revoca, domanda")
            nota("Dopo la revoca l'app richiede: «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.nega, quante: 1)
        } else {
            nota("Dopo la revoca e la riapertura iOS non chiede di nuovo la fotocamera")
        }
        aspettaUnPo(2)
        fotografa("dopo la revoca della fotocamera")
        annotaAvvisi("dopo la revoca")
        if tocca("Inquadra il QR code del computer") {
            aspettaUnPo(2)
            if let domanda = attendiDomandaDiSistema(secondi: 4) {
                fotografa("lettore QR dopo la revoca, domanda")
                nota("Il lettore QR richiede: «\(domanda.label)»")
                rispondiAlleDomandeDiSistema(.nega, quante: 1)
            }
            aspettaUnPo(1)
            fotografa("lettore QR dopo la revoca")
            annotaAvvisi("lettore QR dopo la revoca")
            chiudiFoglio()
        }
    }

    /// I testi sulla privacy: domande frequenti (ricerca «privacy», «dati», «Google»), «Segnala un bug» con i dati
    /// tecnici e il registro, la condivisione.
    @MainActor func test04_testiPrivacy() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        guard tocca("Impostazioni") else { return }
        attendi("Fine")
        guard tocca("App e assistenza") else { return }
        fotografa("app e assistenza")
        scorri(giu: true, volte: 2)
        fotografa("app e assistenza in fondo")
        scorri(giu: false, volte: 2)
        if tocca("Domande frequenti") {
            fotografa("domande frequenti")
            for parola in ["privacy", "Google", "dati"] {
                let campo = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
                if campo.exists {
                    premi(campo)
                    if let valore = campo.value as? String, !valore.isEmpty, valore != campo.placeholderValue {
                        campo.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: valore.count))
                    }
                    campo.typeText(parola)
                    aspettaUnPo(1)
                    fotografa("domande frequenti cerca \(parola)")
                    nota("Domande frequenti, ricerca «\(parola)»: \(app.staticTexts.allElementsBoundByIndex.prefix(12).map { $0.label }.joined(separator: " | "))")
                } else {
                    nota("Domande frequenti: nessun campo di ricerca")
                    break
                }
            }
            if toccaSePresente("Il mio video passa da Internet?", secondi: 2) {
                fotografa("risposta video passa da internet")
            }
            indietro()
        }
        if tocca("Segnala un bug") {
            fotografa("segnala un bug")
            scorri(giu: true)
            fotografa("segnala un bug in fondo")
            nota("Segnala un bug, testi: \(app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | "))")
            scrivi("Paolo prova la privacy", nelCampo: "Descrizione del problema")
            toccaSePresente("Fine", secondi: 1)
            if toccaSePresente("Invia la segnalazione", secondi: 3) {
                aspettaUnPo(3)
                fotografa("condivisione della segnalazione")
                let condivisione = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                nota("Condivisione aperta: \(app.otherElements["ActivityListView"].exists || condivisione.exists)")
                // «Copia» mette il testo intero negli appunti: lo si legge nel copione (simulatore).
                if toccaSePresente("Copy", secondi: 3) || toccaSePresente("Copia", secondi: 1) {
                    aspettaUnPo(1)
                    let testo = UIPasteboard.general.string ?? "(appunti vuoti o non leggibili)"
                    nota("TESTO INTERO DELLA SEGNALAZIONE:\n\(testo)")
                } else {
                    nota("Nella condivisione non trovo «Copia»")
                    fotografa("condivisione senza copia")
                    chiudiFoglio()
                }
            }
        }
    }
}
