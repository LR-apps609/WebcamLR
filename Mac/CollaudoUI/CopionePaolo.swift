// Collaudo 20 · t07 (Paolo, attento alla privacy) sul Mac: nega ogni domanda di sistema, poi guarda cosa dice l'app
// (Avvio e notifiche, Telefoni, Sicurezza) e legge i testi sulla privacy (domande frequenti, «Segnala un bug»).

import XCTest

final class CopionePaolo: CopioneCollaudo {

    /// Primo avvio: ogni domanda di sistema (rete locale, notifiche) fotografata e rifiutata.
    @MainActor func test01_negaTutto() {
        permessi = .nonRispondere
        avviaPulito()
        aspettaUnPo(3)
        var numero = 0
        while numero < 3, let domanda = attendiDomandaDiSistema(secondi: 6) {
            numero += 1
            fotografa("domanda di sistema \(numero)")
            nota("Domanda di sistema \(numero): «\(domanda.label)», pulsanti \(domanda.buttons.allElementsBoundByIndex.map { $0.label })")
            if !rispondiAlleDomandeDiSistema(.nega, quante: 1) { break }
        }
        if numero == 0 { nota("All'avvio nessuna domanda di sistema") }
        permessi = .nega
        attendi("Impostazioni")
        fotografa("principale dopo i rifiuti")
        guard tocca("Impostazioni") else { return }
        for pagina in ["Avvio e notifiche", "Telefoni", "Sicurezza"] {
            guard tocca(pagina, dentro: "Impostazioni") else { continue }
            aspettaUnPo(1)
            fotografa("impostazioni \(pagina)")
            scorri(giu: true, volte: 2, dentro: "Impostazioni")
            fotografa("impostazioni \(pagina) in fondo")
            tocca("Indietro", dentro: "Impostazioni")
        }
        tocca("Chiudi le impostazioni")
    }

    /// Domande frequenti (privacy, dati, Google) e «Segnala un bug» con i dati tecnici.
    @MainActor func test02_testiPrivacy() {
        avviaPulito()
        attendi("Impostazioni")
        guard tocca("Aiuto") else { return }
        guard tocca("Domande frequenti") else { return }
        aspettaUnPo(1.5)
        fotografa("domande frequenti")
        let campo = app.searchFields.firstMatch.exists ? app.searchFields.firstMatch : app.textFields.firstMatch
        for parola in ["privacy", "Google", "dati"] {
            guard campo.exists else { nota("Domande frequenti: nessun campo di ricerca"); break }
            campo.click()
            campo.typeKey("a", modifierFlags: .command)
            campo.typeText(parola)
            aspettaUnPo(1)
            fotografa("domande frequenti cerca \(parola)")
        }
        if tocca("Segnala un bug", dentro: "Barra laterale") {
            aspettaUnPo(1)
            fotografa("segnala un bug")
            scorri(giu: true, volte: 2)
            fotografa("segnala un bug in fondo")
        }
        tasto("w", con: .command)
    }
}
