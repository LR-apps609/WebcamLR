// Copione «fumo» dell'iPhone: ogni schermata raggiungibile senza computer, con schermata e albero per ciascuna.
// Serve anche da esempio per i copioni dei tester (un file per tester, una classe figlia di CopioneCollaudo).
// Il simulatore non ha fotocamera: si annota che cosa mostra l'app senza.

import XCTest

final class CopioneFumo: CopioneCollaudo {

    /// Primo avvio pulito: le quattro pagine della presentazione, le domande di iOS, la schermata principale
    /// («Cerco il tuo computer…» e, dopo 15 secondi, «Non trovo nessun computer»).
    @MainActor func test01_primoAvvio() {
        permessi = .nonRispondere
        avviaPulito()
        attendi("presentazione.avanti.webcam")
        fotografa("presentazione 1 webcam")
        tocca("presentazione.avanti.webcam")
        fotografa("presentazione 2 computer")
        tocca("presentazione.avanti.computer")
        fotografa("presentazione 3 impostazioni")
        tocca("presentazione.avanti.impostazioni")
        fotografa("presentazione 4 permessi")

        tocca("presentazione.inizia")
        for numero in 1...2 {
            guard let domanda = attendiDomandaDiSistema(secondi: 6) else {
                nota("Domanda di sistema \(numero): non è comparsa")
                continue
            }
            fotografa("domanda di sistema \(numero)")
            nota("Domanda di sistema \(numero): «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.concedi)
        }
        permessi = .concedi
        chiudiAvvisoPortachiavi()

        attendi("Cerco il tuo computer")
        fotografa("principale cerco il computer")
        if attendi("Non trovo nessun computer", secondi: 25) {
            fotografa("principale non trovo nessun computer")
            scorri(giu: true)
            fotografa("principale non trovo, in fondo")
        }
    }

    /// Le Impostazioni (dall'ingranaggio) e tutte le pagine dentro: WebcamLR Pro, App e assistenza (guida, domande,
    /// segnala un bug), registro del collegamento.
    @MainActor func test02_impostazioni() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        tocca("Impostazioni")
        attendi("Fine")
        fotografa("impostazioni")
        scorri(giu: true, volte: 2)
        fotografa("impostazioni in fondo")
        scorri(giu: false, volte: 3)

        if tocca("WebcamLR Pro") {
            aspettaUnPo(3)
            fotografa("impostazioni pro")
            scorri(giu: true)
            fotografa("impostazioni pro in fondo")
            indietro()
        }
        if tocca("App e assistenza") {
            fotografa("app e assistenza")
            if tocca("Guida") {
                fotografa("guida")
                scorri(giu: true, volte: 2)
                fotografa("guida più in basso")
                indietro()
            }
            if tocca("Domande frequenti") {
                fotografa("domande frequenti")
                indietro()
            }
            if tocca("Segnala un bug") {
                fotografa("segnala un bug")
                indietro()
            }
            indietro()
        }
        if tocca("Registro del collegamento") {
            fotografa("registro del collegamento")
            indietro()
        }
        chiudiFoglio()
        fotografa("principale dopo le impostazioni")
    }

    /// I pulsanti della schermata principale: la pillola Pro, il lettore del QR code (senza fotocamera),
    /// il cavo USB, «Collega a mano» con un indirizzo sbagliato e «Mandami il link».
    @MainActor func test03_pulsantiPrincipali() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")

        if tocca("Sblocca WebcamLR Pro") {
            fotografa("foglio pro")
            aspettaUnPo(5)
            fotografa("foglio pro dopo 5 secondi")
            chiudiFoglio()
        }
        if tocca("Inquadra il QR code del computer") {
            aspettaUnPo(2)
            fotografa("lettore QR senza fotocamera")
            nota("Lettore QR sul simulatore (nessuna fotocamera): vedi la schermata «lettore QR senza fotocamera».")
            chiudiFoglio()
        }
        if tocca("Usa il cavo USB") {
            fotografa("cavo USB")
        }
        if tocca("Collega a mano (indirizzo)") {
            fotografa("collega a mano")
            scrivi("abc", nelCampo: "192.168.1.20")
            tocca("Collega")
            aspettaUnPo(1)
            fotografa("indirizzo non valido")
            toccaSePresente("Annulla")
        }
        if tocca("Mandami il link per il computer") {
            aspettaUnPo(2)
            fotografa("condividi il link")
            chiudiFoglio()
        }
        fotografa("principale alla fine")
    }

    /// La stessa app in inglese e con il carattere più grande (Accessibilità XXXL).
    @MainActor func test04_ingleseCarattereGrande() {
        avviaPulito(lingua: .inglese, caratteriGrandi: true)
        attendi("presentazione.salta")
        fotografa("en XXXL presentazione 1")
        superaPresentazione()
        fotografa("en XXXL principale")
        if tocca("Settings") {
            fotografa("en XXXL impostazioni")
            scorri(giu: true, volte: 2)
            fotografa("en XXXL impostazioni in fondo")
            chiudiFoglio()
        }
    }
}
