// Aiuti dei copioni solo per l'iPhone (la libreria comune è Strumenti/collaudo/apple/Collaudo.swift).

import XCTest

extension CopioneCollaudo {
    /// La presentazione della prima apertura, saltata: «Salta», poi «Inizia» e le domande di fotocamera e microfono
    /// (risposte secondo `permessi`). Alla fine si è sulla schermata principale «Cerco il tuo computer…».
    @MainActor func superaPresentazione(file: StaticString = #filePath, line: UInt = #line) {
        var presente = esiste("presentazione.salta", secondi: 4)
        if !presente { presente = esiste("presentazione.inizia", secondi: 1) }
        guard presente else {
            nota("superaPresentazione: la presentazione non c'è (già vista?)")
            return
        }
        toccaSePresente("presentazione.salta", secondi: 1)
        tocca("presentazione.inizia", file: file, line: line)
        // Fotocamera e microfono: due domande di iOS, una dopo l'altra.
        for _ in 0..<2 {
            if attendiDomandaDiSistema(secondi: 4) != nil { rispondiAlleDomandeDiSistema() }
        }
        aspettaUnPo(1.5)
        chiudiAvvisoPortachiavi()
    }

    /// L'avviso «L'iPhone non riesce a ricordare questo collegamento» (il Portachiavi non ha salvato l'identità):
    /// sul simulatore può comparire. Lo fotografa, lo annota e lo chiude.
    @MainActor func chiudiAvvisoPortachiavi() {
        let avviso = app.alerts.firstMatch
        guard avviso.waitForExistence(timeout: 2) else { return }
        fotografa("avviso dell'app: \(avviso.label)")
        nota("Avviso dell'app aperto: «\(avviso.label)»")
        let ok = avviso.buttons["OK"]
        if ok.exists { ok.tap() } else { avviso.buttons.firstMatch.tap() }
        aspettaUnPo()
    }
}
