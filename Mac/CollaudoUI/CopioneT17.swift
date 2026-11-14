// Copione t17 (Chiara, podcaster) sul Mac: Impostazioni › Microfono senza telefono (microfono virtuale non
// installato sul Mac di GitHub), la riga del microfono nella colonna di destra, le domande frequenti; poi in inglese.

import XCTest

final class CopioneT17: CopioneCollaudo {

    @MainActor private func giro(_ prefisso: String, impostazioni: String, microfono: String, uscite: String) {
        attendi(impostazioni)
        fotografa("\(prefisso) principale")
        if tocca(impostazioni) {
            aspettaUnPo(1.5)
            if tocca(microfono, dentro: impostazioni) {
                aspettaUnPo(1.5)
                fotografa("\(prefisso) pannello microfono")
                scorri(giu: true, volte: 2, dentro: impostazioni)
                fotografa("\(prefisso) pannello microfono in fondo")
                toccaSePresente(prefisso == "it" ? "Indietro" : "Back", secondi: 2)
                aspettaUnPo(1)
            }
            if tocca(uscite, dentro: impostazioni) {
                aspettaUnPo(1.5)
                fotografa("\(prefisso) pannello uscite")
                toccaSePresente(prefisso == "it" ? "Indietro" : "Back", secondi: 2)
            }
        }
        fotografa("\(prefisso) fine")
    }

    @MainActor func test01_microfono() {
        avviaPulito()
        giro("it", impostazioni: "Impostazioni", microfono: "Microfono", uscite: "Uscite")
    }

    @MainActor func test02_microfonoInglese() {
        avviaPulito(lingua: .inglese)
        giro("en", impostazioni: "Settings", microfono: "Microphone", uscite: "Outputs")
    }
}
