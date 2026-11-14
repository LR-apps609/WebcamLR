// Copione delle correzioni iPhone del collaudo 20: rifà i flussi dei bug corretti e guarda il risultato.
// t01 B1 (fotocamera rifiutata), A2 (inglese XXXL), A3 (titolo sotto l'orologio), A4 (lettore QR sul simulatore),
// t03 B4 / t12 B1 (pagina Pro per Mac e Windows), t01 B3 (schede dei permessi), t07 B3 (registro nella segnalazione).

import XCTest

final class CopioneCorrezioni: CopioneCollaudo {

    /// t01 B1: fotocamera e microfono rifiutati: la principale lo dice con «Apri Impostazioni». Poi A3: scorrendo.
    @MainActor func test01_fotocameraRifiutata() {
        permessi = .nega
        avviaPulito()
        attendi("presentazione.salta")
        toccaSePresente("presentazione.salta", secondi: 2)
        fotografa("pagina dei permessi")
        // t01 B3: un tocco sulla scheda non dà il permesso; il testo lo dice.
        toccaSePresente("presentazione.permesso.microfono", secondi: 2)
        nota("t01 B3: «I permessi non si danno qui» \(esiste("I permessi non si danno qui"))")
        fotografa("scheda microfono toccata")
        superaPresentazione()
        attendi("Cerco il tuo computer")
        let avviso = app.descendants(matching: .any)["principale.fotocameraNegata"]
        let visto = avviso.waitForExistence(timeout: 5) || esiste("Serve il permesso «Fotocamera»")
        nota("t01 B1: avviso della fotocamera \(visto); «Apri Impostazioni» \(esiste("Apri Impostazioni"))")
        XCTAssertTrue(visto, "t01 B1: con la fotocamera rifiutata la principale non avvisa")
        fotografa("principale dopo il rifiuto")
        attendi("Non trovo nessun computer", secondi: 25)
        fotografa("principale non trovo con avviso")
        app.swipeUp()
        aspettaUnPo(1)
        fotografa("principale scorsa in fondo")
        // A3: a metà, il titolo passa sotto l'orologio.
        app.swipeDown()
        aspettaUnPo(0.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        aspettaUnPo(1)
        fotografa("principale scorsa a meta")
        // Riaperta: l'avviso c'è ancora.
        avvia()
        nota("Riaperta: avviso della fotocamera \(esiste("Serve il permesso «Fotocamera»", secondi: 5))")
        fotografa("riaperta dopo il rifiuto")
    }

    /// A2: inglese con Accessibilità XXXL: presentazione, principale, Pro, Impostazioni.
    @MainActor func test02_ingleseXXXL() {
        avviaPulito(lingua: .inglese, caratteriGrandi: true)
        attendi("presentazione.salta")
        fotografa("en XXXL presentazione 1")
        app.swipeUp()
        aspettaUnPo(1)
        fotografa("en XXXL presentazione 1 scorsa")
        superaPresentazione()
        fotografa("en XXXL principale")
        app.swipeUp()
        aspettaUnPo(1)
        fotografa("en XXXL principale scorsa")
        app.swipeDown()
        if toccaSePresente("Unlock WebcamLR Pro", secondi: 3) {
            aspettaUnPo(1.5)
            fotografa("en XXXL pro")
            chiudiFoglio()
        }
        if tocca("Settings") {
            fotografa("en XXXL impostazioni")
            scorri(giu: true, volte: 2)
            fotografa("en XXXL impostazioni in fondo")
            chiudiFoglio()
        }
    }

    /// t03 B4 e t12 B1: la pagina Pro parla del computer (Mac o PC), non solo del Mac.
    @MainActor func test03_paginaPro() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        guard tocca("Sblocca WebcamLR Pro") else { return }
        aspettaUnPo(2)
        fotografa("pro")
        nota("t03 B4: «comandi del computer» \(esiste("tutti i comandi del computer")), «comandi del Mac» \(esiste("tutti i comandi del Mac"))")
        scorri(giu: true, volte: 3)
        fotografa("pro in fondo")
        let sulMac = esiste("Sul Mac:")
        nota("t03 B4: «Sul computer:» \(esiste("Sul computer:")), «Sul Mac:» \(sulMac), «sul computer» (microfono) \(esiste("Microfono del telefono sul computer"))")
        XCTAssertFalse(sulMac, "t03 B4: la pagina Pro dell'iPhone dice ancora «Sul Mac:»")
        chiudiFoglio()
    }

    /// A4: il lettore QR sul simulatore (senza fotocamera) non mostra due testi che si contraddicono.
    @MainActor func test04_lettoreQRSenzaFotocamera() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        guard tocca("Inquadra il QR code del computer") else { return }
        aspettaUnPo(2)
        rispondiAlleDomandeDiSistema(.concedi)
        let nonPuo = esiste("non può leggere i QR code")
        let inquadra = esiste("Inquadra il QR code nella finestra")
        nota("A4: «non può leggere» \(nonPuo), «Inquadra il QR code nella finestra» \(inquadra)")
        XCTAssertFalse(nonPuo && inquadra, "A4: i due testi insieme")
        fotografa("lettore qr")
        chiudiFoglio()
    }

    /// t07 B3: in «Segnala un bug» il registro incluso si vede prima dell'invio e la nota dice che parte anche lui.
    @MainActor func test05_segnalaUnBug() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        guard tocca("Impostazioni") else { return }
        guard tocca("App e assistenza") else { return }
        guard tocca("Segnala un bug") else { return }
        aspettaUnPo(1)
        app.swipeDown()
        scorri(giu: true, volte: 2)
        fotografa("segnala un bug")
        let vedi = esiste("Vedi il registro incluso")
        nota("t07 B3: «Vedi il registro incluso» \(vedi); nota con il registro \(esiste("e il registro del collegamento"))")
        if vedi {
            toccaSePresente("Vedi il registro incluso")
            aspettaUnPo(1)
            fotografa("registro incluso aperto")
        }
    }
}
