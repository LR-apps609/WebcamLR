// Copione t17 (Chiara, podcaster) sull'iPhone: il microfono. La pagina dei permessi della presentazione, la domanda di
// iOS per il microfono negata (fotocamera concessa), cosa dicono poi la schermata principale, le Impostazioni e le
// domande frequenti sul microfono; lo stesso in inglese. «In onda» (dove sta il pulsante «Microfono al computer») qui
// non si raggiunge: niente fotocamera vera.

import XCTest

final class CopioneT17: CopioneCollaudo {

    /// Risponde alle domande di iOS: «Consenti» alla fotocamera, «Non consentire» al microfono.
    @MainActor private func negaSoloMicrofono() {
        for _ in 0..<3 {
            guard let domanda = attendiDomandaDiSistema(secondi: 5) else { break }
            let microfono = domanda.label.localizedCaseInsensitiveContains("micro")
            fotografa(microfono ? "domanda iOS microfono" : "domanda iOS altra")
            rispondiAlleDomandeDiSistema(microfono ? .nega : .concedi, quante: 1)
        }
    }

    @MainActor private func giroMicrofono(_ prefisso: String, impostazioni: String, assistenza: String, domande: String, parola: String) {
        // La presentazione fino alla pagina dei permessi.
        fotografa("\(prefisso) presentazione 1")
        for avanti in ["presentazione.avanti.webcam", "presentazione.avanti.computer", "presentazione.avanti.impostazioni"] {
            if toccaSePresente(avanti, secondi: 3) { aspettaUnPo(1.2) }
        }
        fotografa("\(prefisso) pagina dei permessi")
        if esiste("presentazione.permesso.microfono", secondi: 2) {
            if let riga = trova("presentazione.permesso.microfono", secondi: 1) {
                nota("\(prefisso): riga del permesso microfono «\(riga.label)» valore «\(String(describing: riga.value))»")
            }
        } else {
            nota("\(prefisso): nella pagina dei permessi non trovo presentazione.permesso.microfono")
        }
        tocca("presentazione.inizia")
        negaSoloMicrofono()
        aspettaUnPo(2)
        chiudiAvvisoPortachiavi()
        fotografa("\(prefisso) principale con microfono negato")
        for testo in ["Serve il permesso «Microfono»", "Microphone permission needed", "Microfono non consentito", "Microphone not allowed"] {
            if esiste(testo, secondi: 1) { nota("\(prefisso): a schermo «\(testo)»") }
        }
        // Impostazioni: c'è qualcosa sul microfono?
        if tocca(impostazioni) {
            aspettaUnPo(1.5)
            fotografa("\(prefisso) impostazioni")
            for i in 1...4 {
                scorri(giu: true)
                fotografa("\(prefisso) impostazioni giu \(i)")
            }
            nota("\(prefisso): «\(parola)» nelle Impostazioni: \(esiste(parola, secondi: 1))")
            if tocca(assistenza) {
                aspettaUnPo(1.5)
                fotografa("\(prefisso) app e assistenza")
                if tocca(domande) {
                    aspettaUnPo(1.5)
                    fotografa("\(prefisso) domande frequenti")
                    for i in 1...6 {
                        if let voce = trova(parola, secondi: 1) {
                            nota("\(prefisso): domanda sul microfono «\(voce.label)»")
                            _ = premi(voce)
                            aspettaUnPo(1.5)
                            fotografa("\(prefisso) domanda microfono aperta")
                            break
                        }
                        scorri(giu: true)
                        fotografa("\(prefisso) domande frequenti giu \(i)")
                    }
                }
            }
        }
    }

    @MainActor func test01_microfonoNegato() {
        permessi = .nonRispondere
        avviaPulito()
        giroMicrofono("it", impostazioni: "Impostazioni", assistenza: "App e assistenza", domande: "Domande frequenti", parola: "microfono")
    }

    @MainActor func test02_microfonoNegatoInglese() {
        permessi = .nonRispondere
        avviaPulito(lingua: .inglese)
        giroMicrofono("en", impostazioni: "Settings", assistenza: "App and support", domande: "FAQ", parola: "microphone")
    }
}
