// Copione t12 (Roberto): vuole comprare WebcamLR Pro ma diffida. Pagina Pro senza App Store, poi con una sessione
// StoreKit di prova (SKTestSession con iPhone/WebcamLR.storekit, solo dai test: l'app non cambia): acquisto,
// annullamento, «Chiedi di acquistare», ripristino di un acquisto fatto altrove, rimborso, acquisto non riuscito.

import StoreKit
import StoreKitTest
import XCTest

final class CopioneT12: CopioneCollaudo {

    /// La configurazione StoreKit del progetto (la stessa di ▶ in Xcode), trovata accanto a questo file.
    @MainActor private func sessioneStoreKit() -> SKTestSession? {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("WebcamLR.storekit")
        do {
            let sessione = try SKTestSession(contentsOf: file)
            sessione.resetToDefaultState()
            sessione.clearTransactions()
            sessione.disableDialogs = true
            sessione.askToBuyEnabled = false
            sessione.failTransactionsEnabled = false
            return sessione
        } catch {
            nota("SKTestSession non creata da \(file.path): \(error)")
            return nil
        }
    }

    private func transazioni(_ sessione: SKTestSession) -> String {
        sessione.allTransactions().map { "#\($0.identifier) \($0.productIdentifier) askToBuy=\($0.pendingAskToBuyConfirmation)" }
            .joined(separator: "; ")
    }

    /// Apre la pagina Pro dalla pillola in cima («Sblocca WebcamLR Pro» o «WebcamLR Pro attivo»).
    @MainActor private func apriProDallaPillola() {
        if !toccaSePresente("Sblocca WebcamLR Pro", secondi: 4) {
            toccaSePresente("WebcamLR Pro attivo", secondi: 2)
        }
        aspettaUnPo(2)
    }

    @MainActor private func fotografaPagina(_ nome: String, volte: Int = 2) {
        fotografa("\(nome) 1")
        for i in 0..<volte {
            scorri(giu: true)
            fotografa("\(nome) \(i + 2)")
        }
        scorri(giu: false, volte: volte + 1)
    }

    @MainActor private func prepara() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        aspettaUnPo(1)
    }

    /// Senza configurazione StoreKit (come nel fumo): cosa vede Roberto, «Riprova», «Ripristina acquisti».
    @MainActor func test01_senzaStoreKit() {
        prepara()
        fotografa("principale senza pro")
        apriProDallaPillola()
        fotografa("pro subito")
        aspettaUnPo(12)
        fotografaPagina("pro dopo 14 s")
        if toccaSePresente("Riprova", secondi: 2) {
            fotografa("riprova subito")
            aspettaUnPo(12)
            fotografa("riprova dopo 12 s")
        } else {
            nota("Nessun «Riprova» sulla pagina Pro dopo 14 s")
        }
        if tocca("Ripristina acquisti") {
            fotografa("ripristina subito")
            aspettaUnPo(4)
            fotografa("ripristina 4 s")
            aspettaUnPo(10)
            fotografa("ripristina 14 s")
            if let domanda = attendiDomandaDiSistema(secondi: 2) {
                nota("Ripristina: domanda di sistema «\(domanda.label)» \(domanda.buttons.allElementsBoundByIndex.map { $0.label })")
                fotografa("ripristina domanda di sistema")
            }
        }
        chiudiFoglio()
        aspettaUnPo(1)
        tocca("Impostazioni")
        attendi("Fine")
        fotografa("impostazioni riga pro")
        if tocca("WebcamLR Pro") {
            aspettaUnPo(3)
            fotografa("pro dalle impostazioni")
        }
    }

    /// Acquisto riuscito (finestre di StoreKit spente: approvato da solo), poi riapertura e rimborso.
    @MainActor func test02_acquistoERimborso() {
        guard let sessione = sessioneStoreKit() else { return }
        prepara()
        apriProDallaPillola()
        aspettaUnPo(5)
        fotografaPagina("pro con storekit")
        if tocca("Sblocca Pro") {
            fotografa("acquisto subito")
            if attendi("Pro attivo", secondi: 20) {
                fotografaPagina("acquisto riuscito", volte: 1)
            }
        }
        nota("Transazioni dopo l'acquisto: \(transazioni(sessione))")
        chiudiFoglio()
        aspettaUnPo(1)
        fotografa("principale con pro")
        tocca("Impostazioni")
        attendi("Fine")
        fotografa("impostazioni con pro")
        toccaSePresente("Fine")
        aspettaUnPo(1)

        // Chiusa e riaperta: Pro resta?
        chiudiApp()
        avvia()
        aspettaUnPo(4)
        fotografa("riaperta dopo acquisto")

        // Rimborso (come Apple dopo una richiesta su reportaproblem.apple.com).
        for t in sessione.allTransactions() {
            do { try sessione.refundTransaction(identifier: t.identifier) } catch { nota("Rimborso non riuscito: \(error)") }
        }
        aspettaUnPo(6)
        fotografa("dopo rimborso, senza riaprire")
        apriProDallaPillola()
        aspettaUnPo(3)
        fotografa("pro dopo rimborso")
        chiudiFoglio()
        chiudiApp()
        avvia()
        aspettaUnPo(4)
        fotografa("riaperta dopo rimborso")
        sessione.clearTransactions()
    }

    /// Roberto apre il foglio di acquisto e annulla. Con le finestre di StoreKit accese si cerca «Annulla/Cancel»;
    /// poi lo stesso esito simulato con il codice d'errore «paymentCancelled».
    @MainActor func test03_annulla() {
        guard let sessione = sessioneStoreKit() else { return }
        sessione.disableDialogs = false
        prepara()
        apriProDallaPillola()
        aspettaUnPo(5)
        if tocca("Sblocca Pro") {
            aspettaUnPo(4)
            fotografa("foglio di acquisto")
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            var annullato = false
            for radice in [app, springboard] {
                for nome in ["Cancel", "Annulla", "Close", "Chiudi"] where !annullato {
                    let pulsante = radice.buttons[nome]
                    if pulsante.waitForExistence(timeout: 1) {
                        nota("Foglio di acquisto: tocco «\(nome)»")
                        pulsante.tap()
                        annullato = true
                    }
                }
            }
            if !annullato {
                nota("Foglio di acquisto: nessun «Annulla» trovato. Pulsanti dell'app: \(app.buttons.allElementsBoundByIndex.prefix(20).map { $0.label }); SpringBoard: \(springboard.buttons.allElementsBoundByIndex.prefix(20).map { $0.label })")
            }
            aspettaUnPo(3)
            fotografa("dopo annulla")
        }
        nota("Transazioni dopo l'annullamento: \(transazioni(sessione))")

        // Lo stesso come errore del negozio: SKError.paymentCancelled e poi una rete che cade.
        sessione.disableDialogs = true
        sessione.failTransactionsEnabled = true
        sessione.failureError = .paymentCancelled
        if toccaSePresente("Sblocca Pro", secondi: 3) {
            aspettaUnPo(5)
            fotografa("errore paymentCancelled")
        }
        sessione.failureError = .cloudServiceNetworkConnectionFailed
        if toccaSePresente("Sblocca Pro", secondi: 3) {
            aspettaUnPo(5)
            fotografa("errore rete durante acquisto")
        }
        sessione.failTransactionsEnabled = false
        nota("Transazioni alla fine: \(transazioni(sessione))")
    }

    /// «Chiedi di acquistare» (In famiglia): in attesa, poi approvato dal genitore.
    @MainActor func test04_chiediDiAcquistare() {
        guard let sessione = sessioneStoreKit() else { return }
        sessione.askToBuyEnabled = true
        prepara()
        apriProDallaPillola()
        aspettaUnPo(5)
        if tocca("Sblocca Pro") {
            aspettaUnPo(6)
            fotografaPagina("chiedi di acquistare in attesa", volte: 1)
        }
        nota("Transazioni in attesa: \(transazioni(sessione))")
        for t in sessione.allTransactions() where t.pendingAskToBuyConfirmation {
            do { try sessione.approveAskToBuyTransaction(identifier: t.identifier) } catch { nota("Approvazione non riuscita: \(error)") }
        }
        aspettaUnPo(8)
        fotografa("chiedi di acquistare approvato")
        sessione.clearTransactions()
    }

    /// Ripristino: prima senza acquisti («Nessun acquisto…»), poi con un acquisto fatto «su un altro iPhone»
    /// (comprato fuori dall'app con lo stesso Apple ID), a app appena installata.
    @MainActor func test05_ripristino() {
        guard let sessione = sessioneStoreKit() else { return }
        prepara()
        apriProDallaPillola()
        aspettaUnPo(5)
        if tocca("Ripristina acquisti") {
            aspettaUnPo(6)
            fotografa("ripristino senza acquisti")
        }
        chiudiFoglio()
        chiudiApp()

        do { try sessione.buyProduct(productIdentifier: "it.lrapps.webcamlr.pro") } catch { nota("Acquisto «da un altro iPhone» non riuscito: \(error)") }
        nota("Transazioni dopo l'acquisto altrove: \(transazioni(sessione))")
        avvia()
        aspettaUnPo(5)
        fotografa("aperta dopo acquisto altrove")
        apriProDallaPillola()
        aspettaUnPo(3)
        fotografa("pro dopo acquisto altrove, prima del ripristino")
        if tocca("Ripristina acquisti") {
            aspettaUnPo(6)
            fotografa("ripristino con acquisto")
            if let domanda = attendiDomandaDiSistema(secondi: 2) {
                nota("Ripristina: domanda di sistema «\(domanda.label)»")
                fotografa("ripristino domanda di sistema")
            }
        }
        sessione.clearTransactions()
    }
}
