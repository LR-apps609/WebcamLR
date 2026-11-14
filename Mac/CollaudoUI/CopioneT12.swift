// Copione t12 (Roberto) sul Mac: cosa dice il Mac di WebcamLR Pro senza telefono, dove si compra, quali comandi
// sono bloccati («Sostituito», sfondi, profili) e che testo hanno.

import XCTest

final class CopioneT12: CopioneCollaudo {

    @MainActor func test01_proSulMac() {
        avviaPulito()
        attendi("Impostazioni")
        fotografa("principale")
        if tocca("WebcamLR") {
            aspettaUnPo(1)
            fotografa("menu WebcamLR")
            if tocca("WebcamLR Pro") {
                aspettaUnPo(2)
                fotografa("finestra pro")
                scorri(giu: true, volte: 2)
                fotografa("finestra pro in fondo")
                tasto("w", con: .command)
                aspettaUnPo(1)
            } else {
                tasto(XCUIKeyboardKey.escape.rawValue)
            }
        }
        // Le pagine del pannello con comandi Pro.
        if tocca("Impostazioni") {
            aspettaUnPo(1.5)
            for pagina in ["Effetti", "Sfondo", "Profili", "Qualità e collegamento", "Schermo"] {
                if tocca(pagina, dentro: "Impostazioni") {
                    aspettaUnPo(1.5)
                    fotografa("pannello \(pagina)")
                    scorri(giu: true, volte: 2, dentro: "Impostazioni")
                    fotografa("pannello \(pagina) in fondo")
                    if pagina == "Effetti", toccaSePresente("Sostituito", secondi: 2) {
                        aspettaUnPo(1.5)
                        fotografa("clic su Sostituito")
                        tasto(XCUIKeyboardKey.escape.rawValue)
                    }
                    toccaSePresente("Indietro", secondi: 2)
                    aspettaUnPo(1)
                }
            }
        }
        fotografa("fine")
    }
}
