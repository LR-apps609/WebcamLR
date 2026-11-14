// Copione t19 (Emma, inglese): tutte le schermate dell'iPhone raggiungibili senza computer, con l'app in inglese.
// Serve a cercare testi rimasti in italiano, traduzioni goffe, testi troncati, date e numeri nel formato sbagliato.

import XCTest

final class CopioneT19: CopioneCollaudo {

    /// Presentazione, domande di iOS e schermata principale in inglese.
    @MainActor func test01_presentazione() {
        permessi = .nonRispondere
        avviaPulito(lingua: .inglese)
        attendi("presentazione.avanti.webcam")
        fotografa("en presentazione 1")
        tocca("presentazione.avanti.webcam")
        fotografa("en presentazione 2")
        tocca("presentazione.avanti.computer")
        fotografa("en presentazione 3")
        tocca("presentazione.avanti.impostazioni")
        fotografa("en presentazione 4")
        tocca("presentazione.inizia")
        for numero in 1...2 {
            guard let domanda = attendiDomandaDiSistema(secondi: 6) else { continue }
            fotografa("en domanda di sistema \(numero)")
            nota("Domanda di sistema \(numero): «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.concedi, quante: 1)
        }
        permessi = .concedi
        chiudiAvvisoPortachiavi()
        attendi("Looking for your computer")
        fotografa("en principale cerco")
        if attendi("No computer found", secondi: 25) {
            fotografa("en principale non trovo")
            scorri(giu: true)
            fotografa("en principale non trovo in fondo")
            scorri(giu: false)
        }
    }

    /// Impostazioni in inglese e tutte le pagine dentro.
    @MainActor func test02_impostazioni() {
        avviaPulito(lingua: .inglese)
        superaPresentazione()
        attendi("Looking for your computer")
        tocca("Settings")
        attendi("Done")
        fotografa("en impostazioni 1")
        scorri(giu: true)
        fotografa("en impostazioni 2")
        scorri(giu: true)
        fotografa("en impostazioni 3")
        scorri(giu: true)
        fotografa("en impostazioni 4")
        scorri(giu: false, volte: 4)
        if tocca("WebcamLR Pro") {
            aspettaUnPo(4)
            fotografa("en pro 1")
            scorri(giu: true)
            fotografa("en pro 2")
            scorri(giu: true)
            fotografa("en pro 3")
            indietro()
        }
        if tocca("App and support") {
            fotografa("en app e assistenza 1")
            scorri(giu: true)
            fotografa("en app e assistenza 2")
            scorri(giu: false)
            if tocca("Guide") {
                for i in 1...5 { fotografa("en guida \(i)"); scorri(giu: true) }
                indietro()
            }
            if tocca("FAQ") {
                fotografa("en faq 1")
                for i in 2...6 { scorri(giu: true); fotografa("en faq \(i)") }
                indietro()
            }
            if tocca("Report a bug") {
                fotografa("en segnala vuoto")
                scrivi("The video freezes after a minute", nelCampo: nil)
                aspettaUnPo(1)
                fotografa("en segnala scritto")
                scorri(giu: true)
                fotografa("en segnala in fondo")
                indietro()
            }
            indietro()
        }
        if tocca("Connection log") {
            fotografa("en registro")
            indietro()
        }
        chiudiFoglio()
        fotografa("en principale dopo impostazioni")
    }

    /// Pulsanti della schermata principale: Pro, QR senza fotocamera, cavo, indirizzo sbagliato, link.
    @MainActor func test03_pulsanti() {
        avviaPulito(lingua: .inglese)
        superaPresentazione()
        attendi("Looking for your computer")
        if tocca("Unlock WebcamLR Pro") {
            aspettaUnPo(6)
            fotografa("en foglio pro")
            scorri(giu: true)
            fotografa("en foglio pro in fondo")
            chiudiFoglio()
        }
        if tocca("Scan the computer’s QR code") {
            aspettaUnPo(2)
            fotografa("en lettore qr")
            chiudiFoglio()
        }
        if tocca("Use the USB cable") {
            fotografa("en cavo usb")
            scorri(giu: true)
            fotografa("en cavo usb in fondo")
            chiudiFoglio()
        }
        if tocca("Connect manually (address)") {
            fotografa("en collega a mano")
            scrivi("abc", nelCampo: nil)
            toccaSePresente("Connect")
            aspettaUnPo(1)
            fotografa("en indirizzo non valido")
            toccaSePresente("Cancel")
        }
        if tocca("Connect manually (address)") {
            scrivi("10.255.255.1", nelCampo: nil)
            toccaSePresente("Connect")
            aspettaUnPo(12)
            fotografa("en indirizzo irraggiungibile")
            toccaSePresente("Cancel")
            toccaSePresente("OK")
        }
        if tocca("Send me the link for the computer") {
            aspettaUnPo(2)
            fotografa("en condividi link")
            chiudiFoglio()
        }
        fotografa("en principale fine")
    }

    /// Fotocamera e microfono negati: che cosa dice l'app in inglese.
    @MainActor func test04_permessiNegati() {
        permessi = .nega
        avviaPulito(lingua: .inglese)
        superaPresentazione()
        aspettaUnPo(2)
        fotografa("en permessi negati")
        scorri(giu: true)
        fotografa("en permessi negati in fondo")
    }
}
