// Copione del tester t01 (collaudo 20): Giulia apre WebcamLR sul MacBook per la prima volta, con fretta.
// Che cosa vede, che cosa capisce di dover fare con l'iPhone, dove clicca per primo.

import XCTest

final class CopioneT01: CopioneCollaudo {

    @MainActor private func annotaPulsanti(_ dove: String) {
        let finestra = app.windows.firstMatch
        let pulsanti = finestra.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && !$0.frame.isEmpty }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map { "«\($0.title.isEmpty ? $0.label : $0.title)» [\($0.identifier)] y=\(Int($0.frame.minY))" }
        nota("Pulsanti visibili (\(dove)), dall'alto: " + pulsanti.joined(separator: "; "))
    }

    /// Primo avvio: la finestra a 2 e a 10 secondi, poi i due aiuti per chi non sa da dove iniziare.
    @MainActor func test01_primoAvvioDiFretta() {
        permessi = .nonRispondere
        let inizio = Date()
        avviaPulito()
        aspettaUnPo(1)
        if let domanda = attendiDomandaDiSistema(secondi: 4) {
            fotografa("domanda di sistema")
            nota("Domanda di sistema all'avvio: «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.concedi)
        }
        permessi = .concedi
        nota(String(format: "Finestra pronta dopo %.1f s; finestre: %@", Date().timeIntervalSince(inizio),
                    app.windows.allElementsBoundByIndex.map { "«\($0.title)»" }.joined(separator: ", ")))
        fotografa("finestra principale")
        annotaPulsanti("primo avvio")
        nota("QR code in vista: \(esiste("QR code")); «tre passi»: \(esiste("tre passi")); «webcam virtuale»: \(esiste("webcam virtuale"))")
        aspettaUnPo(8)
        fotografa("finestra dopo 10 secondi")
        if tocca("Il telefono non trova il Mac?") {
            aspettaUnPo(1)
            fotografa("il telefono non trova il mac")
            annotaPulsanti("dopo «Il telefono non trova il Mac?»")
            tasto(XCUIKeyboardKey.escape.rawValue)
            toccaSePresente("Chiudi", secondi: 1)
        }
        if tocca("Non hai l'app? Scaricala") {
            aspettaUnPo(1)
            fotografa("non hai l'app")
            annotaPulsanti("dopo «Non hai l'app? Scaricala»")
            tasto(XCUIKeyboardKey.escape.rawValue)
            toccaSePresente("Chiudi", secondi: 1)
        }
        fotografa("principale alla fine")
    }

    /// Clic sul primo pulsante visibile, tre volte: dove finisce Giulia?
    @MainActor func test02_primoPulsanteCheVede() {
        avviaPulito()
        aspettaUnPo(2)
        for passo in 1...3 {
            let pulsanti = app.windows.firstMatch.buttons.allElementsBoundByIndex
                .filter { $0.exists && $0.isHittable && !$0.frame.isEmpty }
                .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            annotaPulsanti("passo \(passo)")
            guard let primo = pulsanti.first else { nota("Passo \(passo): nessun pulsante"); break }
            let nome = primo.title.isEmpty ? primo.label : primo.title
            nota("Passo \(passo): clic su «\(nome)» [\(primo.identifier)]")
            primo.click()
            aspettaUnPo(1.5)
            rispondiAlleDomandeDiSistema(.concedi)
            fotografa("passo \(passo) dopo \(nome)")
        }
    }
}
