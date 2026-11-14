// Copione t05 dell'iPhone (Francesca, impiegata: WebcamLR ogni giorno per Zoom/Teams, vuole zero passi).
// Che cosa fa l'app quando si riapre: secondo e terzo avvio dopo il primo (presentazione? permessi? schermata?),
// ritorno dallo sfondo (Home e di nuovo l'app). Il simulatore non ha computer: si guarda che cosa mostra senza.

import XCTest

final class CopioneT05: CopioneCollaudo {

    /// Riapre senza cancellare niente e misura quanto ci vuole a vedere la schermata principale.
    @MainActor private func riapri(_ quale: String) {
        permessi = .nonRispondere
        let inizio = Date()
        avvia()
        let presentazione = esiste("presentazione.salta", secondi: 2) || esiste("presentazione.inizia")
            || esiste("presentazione.avanti.webcam")
        let principale = esiste("Cerco il tuo computer", secondi: 8) || esiste("Non trovo nessun computer")
        nota(String(format: "%@: presentazione %@, principale %@ (%.1f s)", quale, presentazione ? "SÌ" : "no",
                    principale ? "sì" : "NO", Date().timeIntervalSince(inizio)))
        if let domanda = attendiDomandaDiSistema(secondi: 3) {
            fotografa("\(quale) domanda di sistema")
            nota("\(quale): domanda di sistema «\(domanda.label)» (di nuovo?)")
            rispondiAlleDomandeDiSistema(.concedi)
        } else {
            nota("\(quale): nessuna domanda di sistema")
        }
        permessi = .concedi
        if app.alerts.firstMatch.exists { chiudiAvvisoPortachiavi() }
    }

    /// Primo avvio (presentazione saltata come Francesca: «Salta», «Inizia», Consenti), poi chiude e riapre due volte;
    /// nel secondo cambia una cosa nelle Impostazioni e controlla che al terzo sia rimasta.
    @MainActor func test01_treAvvii() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        fotografa("avvio1 principale")

        riapri("Avvio 2")
        fotografa("avvio2 principale")
        if tocca("Impostazioni") {
            attendi("Fine")
            fotografa("avvio2 impostazioni")
            let interruttori = app.switches.allElementsBoundByIndex.prefix(20)
                .map { "«\($0.label)»=\($0.value.map { "\($0)" } ?? "?")" }
            nota("Avvio 2, interruttori nelle Impostazioni: \(interruttori.joined(separator: ", "))")
            // Il primo interruttore che si trova (si annota quale): al terzo avvio deve essere com'è stato lasciato.
            if let primo = app.switches.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                nota("Avvio 2: cambio «\(primo.label)» (era \(primo.value.map { "\($0)" } ?? "?"))")
                primo.tap()
                aspettaUnPo(1)
                nota("Avvio 2: ora «\(primo.label)» = \(primo.value.map { "\($0)" } ?? "?")")
                fotografa("avvio2 impostazioni cambiate")
            }
            chiudiFoglio()
        }

        riapri("Avvio 3")
        fotografa("avvio3 principale")
        if tocca("Impostazioni") {
            attendi("Fine")
            let interruttori = app.switches.allElementsBoundByIndex.prefix(20)
                .map { "«\($0.label)»=\($0.value.map { "\($0)" } ?? "?")" }
            nota("Avvio 3, interruttori nelle Impostazioni: \(interruttori.joined(separator: ", "))")
            fotografa("avvio3 impostazioni")
            chiudiFoglio()
        }
    }

    /// Francesca va su un'altra app (Home) e torna dopo un po': che cosa vede? E dopo i 15 secondi di «Non trovo nessun
    /// computer», tornando dall'app riparte la ricerca o resta l'avviso?
    @MainActor func test02_ritornoDalloSfondo() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        fotografa("principale")
        if esiste("Non trovo nessun computer", secondi: 25) {
            fotografa("non trovo nessun computer")
        }
        XCUIDevice.shared.press(.home)
        aspettaUnPo(5)
        app.activate()
        aspettaUnPo(1.5)
        nota("Tornata dallo sfondo: «Cerco il tuo computer» \(esiste("Cerco il tuo computer")), "
             + "«Non trovo nessun computer» \(esiste("Non trovo nessun computer"))")
        fotografa("tornata dallo sfondo")
        aspettaUnPo(5)
        fotografa("tornata dallo sfondo dopo 5 s")

        // Chiusa dal selettore delle app (qui: terminata) e riaperta dall'icona.
        riapri("Dopo la chiusura")
        fotografa("riaperta")
        if esiste("Non trovo nessun computer", secondi: 25) {
            fotografa("riaperta non trovo")
            scorri(giu: true)
            fotografa("riaperta non trovo in fondo")
        }
    }
}
