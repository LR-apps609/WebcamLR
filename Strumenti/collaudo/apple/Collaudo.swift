// Banco di prova di WebcamLR (collaudo-20): la piccola libreria per scrivere i copioni dei tester.
// Un solo file per iPhone e Mac (#if os): lo usano i target CollaudoUI-iPhone (iPhone/project.yml) e
// CollaudoUI-Mac (Mac/project-senza-account.yml). Istruzioni in Strumenti/collaudo/apple/LEGGIMI.md.
//
// Ogni copione è una classe figlia di `CopioneCollaudo`, in un file per tester, con metodi
// `@MainActor func test…()`. Esempio:
//
//     final class CopioneMario: CopioneCollaudo {
//         @MainActor func test01_impostazioni() {
//             avviaPulito()
//             superaPresentazione()          // solo iPhone
//             tocca("Impostazioni")
//             fotografa("impostazioni")      // schermata + albero
//             nota("La riga Pro dice «Sblocca»")
//         }
//     }
//
// Lo stato pulito: il banco (Strumenti/collaudo/apple/esegui.sh) cancella il simulatore (iPhone) o i dati
// dell'app (Mac) prima di OGNI metodo di test. `avviaPulito()` quindi parte davvero da zero la prima volta in un
// metodo; le volte successive, nello stesso metodo, azzera solo i permessi (iPhone) e riapre l'app.

import XCTest

/// Come rispondere alle domande di sistema sui permessi (fotocamera, microfono, rete locale).
enum RispostaPermessi {
    /// «Consenti» / «Allow».
    case concedi
    /// «Non consentire» / «Don't Allow».
    case nega
    /// Lascia la domanda aperta: la gestisce il copione (per fotografarla, per esempio).
    case nonRispondere
}

/// La lingua dell'app (il simulatore e il Mac di GitHub sono in inglese: di serie l'app si apre in italiano).
enum LinguaCollaudo {
    case italiano, inglese

    var argomenti: [String] {
        switch self {
        case .italiano: return ["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        case .inglese: return ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        }
    }
}

class CopioneCollaudo: XCTestCase {
    /// L'app in prova (WebcamLR). Una sola per tutto il processo dei test.
    @MainActor static let applicazione = XCUIApplication()
    @MainActor var app: XCUIApplication { Self.applicazione }

    /// Come rispondere alle domande di sistema sui permessi. Si cambia quando si vuole, anche a metà copione.
    var permessi: RispostaPermessi = .concedi
    /// Secondi di attesa di serie per `tocca`.
    var attesaDiSerie: Double = 6

    private var numero = 0
    private var avviiInQuestoTest = 0

    @MainActor override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        numero = 0
        avviiInQuestoTest = 0
        permessi = .concedi
    }

    @MainActor override func tearDown() async throws {
        // L'ultima immagine sempre, anche dopo un errore: com'era lo schermo alla fine del copione.
        schermata("fine")
        if app.state != .notRunning { albero("fine") }
        try await super.tearDown()
    }

    // MARK: - Avvio

    /// Apre l'app (chiudendola prima, se è aperta).
    /// - lingua: `.italiano` (di serie) o `.inglese`.
    /// - caratteriGrandi: iPhone, carattere «Accessibilità XXXL». Sul Mac non c'è un equivalente (resta una nota).
    /// - argomenti: altri argomenti di avvio (per esempio `["-presentazione"]` sull'iPhone).
    @MainActor func avvia(lingua: LinguaCollaudo = .italiano, caratteriGrandi: Bool = false, argomenti: [String] = []) {
        if app.state != .notRunning { app.terminate() }
        var tutti = lingua.argomenti
        if caratteriGrandi {
            #if os(iOS)
            tutti += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            #else
            nota("Caratteri grandi: sul Mac non c'è un argomento di avvio equivalente, l'app si apre normale.")
            #endif
        }
        #if os(macOS)
        // Niente finestre riaperte dall'ultima volta: ogni avvio parte dalla finestra principale.
        tutti += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launchArguments = tutti + argomenti
        app.launch()
        avviiInQuestoTest += 1
        aspettaUnPo(1.5)
        rispondiAlleDomandeDiSistema()
    }

    /// Apre l'app da zero: dati cancellati (dal banco, prima di ogni metodo di test) e permessi da chiedere.
    /// Dalla seconda volta nello stesso metodo: sull'iPhone azzera fotocamera e microfono (i dati restano);
    /// sul Mac riapre soltanto. `-collaudoPulito YES` arriva comunque all'app, per quando saprà gestirlo.
    @MainActor func avviaPulito(lingua: LinguaCollaudo = .italiano, caratteriGrandi: Bool = false, argomenti: [String] = []) {
        if avviiInQuestoTest > 0 {
            if app.state != .notRunning { app.terminate() }
            #if os(iOS)
            app.resetAuthorizationStatus(for: .camera)
            app.resetAuthorizationStatus(for: .microphone)
            #endif
            nota("avviaPulito ripetuto nello stesso test: i dati salvati dall'app restano (solo il primo avvio è davvero pulito).")
        }
        avvia(lingua: lingua, caratteriGrandi: caratteriGrandi, argomenti: ["-collaudoPulito", "YES"] + argomenti)
    }

    /// Chiude l'app.
    @MainActor func chiudiApp() {
        if app.state != .notRunning { app.terminate() }
    }

    // MARK: - Prove: schermate, alberi, note

    /// Salva l'immagine dello schermo nei risultati, con un numero davanti al nome («03 impostazioni»).
    @MainActor func schermata(_ nome: String) {
        numero += 1
        let immagine = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        immagine.name = String(format: "%02d %@", numero, nome)
        immagine.lifetime = .keepAlways
        add(immagine)
    }

    /// Salva l'albero degli elementi (etichette, identificatori, tipi, posizioni): serve per scrivere i copioni.
    @MainActor func albero(_ nome: String) {
        let testo = XCTAttachment(string: app.debugDescription)
        testo.name = String(format: "%02d %@.albero", numero, nome)
        testo.lifetime = .keepAlways
        add(testo)
    }

    /// Schermata e albero insieme, con lo stesso numero.
    @MainActor func fotografa(_ nome: String) {
        schermata(nome)
        albero(nome)
    }

    /// Un'osservazione del tester: finisce nei risultati (note.txt del copione) e nel registro del test.
    @MainActor func nota(_ testo: String) {
        print("NOTA: \(testo)")
        let allegato = XCTAttachment(string: testo)
        allegato.name = String(format: "%02d nota", numero)
        allegato.lifetime = .keepAlways
        add(allegato)
    }

    // MARK: - Azioni

    /// Tocca (iPhone) o fa clic (Mac) sull'elemento con questa etichetta o questo identificatore: prima il testo
    /// esatto, poi un testo che lo contiene. Pulsanti, celle, voci di menu e link prima dei testi semplici.
    /// Se non lo trova segna un errore (il copione continua) e salva schermata e albero.
    @MainActor @discardableResult
    func tocca(_ etichetta: String, dentro contenitore: String? = nil, secondi: Double? = nil,
               file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let elemento = trovaScorrendo(etichetta, dentro: contenitore, secondi: secondi ?? attesaDiSerie) else {
            XCTFail("Non trovo «\(etichetta)» da toccare", file: file, line: line)
            fotografa("non trovo \(etichetta)")
            return false
        }
        premi(elemento)
        aspettaUnPo()
        rispondiAlleDomandeDiSistema()
        return true
    }

    /// Come `tocca`, ma senza errore se l'elemento non c'è: dice solo se l'ha toccato.
    @MainActor @discardableResult
    func toccaSePresente(_ etichetta: String, dentro contenitore: String? = nil, secondi: Double = 2) -> Bool {
        guard let elemento = trova(etichetta, dentro: contenitore, secondi: secondi) else { return false }
        premi(elemento)
        aspettaUnPo()
        rispondiAlleDomandeDiSistema()
        return true
    }

    /// Scrive un testo: nel campo con quell'etichetta/segnaposto/identificatore, se c'è, altrimenti dove c'è il cursore.
    @MainActor func scrivi(_ testo: String, nelCampo campo: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        if let campo {
            let predicato = NSPredicate(format: "identifier == %@ OR label == %@ OR placeholderValue == %@ OR title == %@",
                                        campo, campo, campo, campo)
            let tipi: [XCUIElement.ElementType] = [.textField, .secureTextField, .textView, .searchField]
            var trovato: XCUIElement?
            for tipo in tipi {
                let elemento = app.descendants(matching: tipo).matching(predicato).firstMatch
                if elemento.exists { trovato = elemento; break }
            }
            if trovato == nil {
                // Il primo campo di testo visibile (per esempio quello di un avviso).
                let primo = app.textFields.firstMatch
                if primo.exists { trovato = primo }
            }
            guard let elemento = trovato else {
                XCTFail("Non trovo il campo «\(campo)»", file: file, line: line)
                fotografa("non trovo il campo \(campo)")
                return
            }
            premi(elemento)
            elemento.typeText(testo)
        } else {
            app.typeText(testo)
        }
        aspettaUnPo(0.5)
    }

    /// Aspetta che compaia un testo (etichetta, identificatore o titolo che lo contiene). Se non compare segna un errore.
    @MainActor @discardableResult
    func attendi(_ testo: String, secondi: Double = 10, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        if esiste(testo, secondi: secondi) { return true }
        XCTFail("Dopo \(Int(secondi)) secondi non vedo «\(testo)»", file: file, line: line)
        fotografa("non vedo \(testo)")
        return false
    }

    /// Dice se un testo è sullo schermo (aspettando fino a `secondi`), senza errori.
    @MainActor func esiste(_ testo: String, secondi: Double = 0) -> Bool {
        let predicato = NSPredicate(format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR title CONTAINS[c] %@ OR value == %@",
                                    testo, testo, testo, testo)
        let limite = Date().addingTimeInterval(secondi)
        repeat {
            if app.descendants(matching: .any).matching(predicato).firstMatch.exists { return true }
            #if os(macOS)
            if !testiCheContengono(testo, in: app).isEmpty { return true }
            #endif
            if Date() >= limite { break }
            rispondiAlleDomandeDiSistema()
            aspettaUnPo(0.5)
        } while Date() < limite
        return false
    }

    /// Torna indietro: la freccia in alto a sinistra (iPhone) o «Indietro» / Esc (Mac).
    @MainActor func indietro() {
        #if os(iOS)
        let freccia = app.navigationBars.buttons.element(boundBy: 0)
        if freccia.exists && freccia.isHittable {
            freccia.tap()
        } else if !toccaSePresente("Indietro", secondi: 1) && !toccaSePresente("Back", secondi: 1) {
            nota("indietro(): nessuna freccia per tornare indietro")
        }
        #else
        if !toccaSePresente("Indietro", secondi: 1) && !toccaSePresente("Back", secondi: 1) {
            app.typeKey(.escape, modifierFlags: [])
        }
        #endif
        aspettaUnPo()
    }

    /// Chiude il foglio aperto: «Fine»/«Done» se c'è, altrimenti lo trascina giù (iPhone) o preme Esc (Mac).
    @MainActor func chiudiFoglio() {
        for nome in ["Fine", "Done", "Chiudi", "Close"] where toccaSePresente(nome, secondi: 0.5) { return }
        #if os(iOS)
        let alto = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let basso = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        alto.press(forDuration: 0.05, thenDragTo: basso)
        #else
        app.typeKey(.escape, modifierFlags: [])
        #endif
        aspettaUnPo()
    }

    /// Scorre il contenuto: `giu: true` per vedere ciò che sta sotto.
    /// `dentro`: il contenitore da scorrere (etichetta o identificatore), per esempio il pannello «Impostazioni» del Mac.
    @MainActor func scorri(giu: Bool = true, volte: Int = 1, dentro contenitore: String? = nil) {
        let radice = contenitore.flatMap { self.contenitore($0) }
        for _ in 0..<volte {
            #if os(iOS)
            let bersaglio = radice ?? app
            if giu { bersaglio.swipeUp() } else { bersaglio.swipeDown() }
            #else
            let bersaglio = radice ?? app.windows.firstMatch
            bersaglio.scroll(byDeltaX: 0, deltaY: giu ? -400 : 400)
            #endif
            aspettaUnPo(0.5)
        }
    }

    #if os(macOS)
    /// Una scorciatoia da tastiera sul Mac, per esempio `tasto(",", con: .command)` per le Impostazioni.
    @MainActor func tasto(_ tasto: String, con modificatori: XCUIElement.KeyModifierFlags = []) {
        app.typeKey(tasto, modifierFlags: modificatori)
        aspettaUnPo()
    }
    #endif

    /// Una pausa breve, per lasciare finire le animazioni.
    func aspettaUnPo(_ secondi: Double = 0.8) {
        Thread.sleep(forTimeInterval: secondi)
    }

    // MARK: - Domande di sistema (permessi)

    /// La domanda di sistema aperta, se c'è (iPhone: gli avvisi di SpringBoard; Mac: le finestre di sistema).
    @MainActor func domandaDiSistema() -> XCUIElement? {
        #if os(iOS)
        let avviso = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        return avviso.exists ? avviso : nil
        #else
        let centro = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        let finestra = centro.dialogs.firstMatch
        return finestra.exists ? finestra : nil
        #endif
    }

    /// Aspetta una domanda di sistema per `secondi`; la restituisce senza rispondere.
    @MainActor func attendiDomandaDiSistema(secondi: Double = 8) -> XCUIElement? {
        let limite = Date().addingTimeInterval(secondi)
        repeat {
            if let domanda = domandaDiSistema() { return domanda }
            aspettaUnPo(0.5)
        } while Date() < limite
        return nil
    }

    /// Risponde alla domanda di sistema aperta secondo `permessi` (o la risposta data qui). Dice se ha risposto.
    @MainActor @discardableResult
    func rispondiAlleDomandeDiSistema(_ risposta: RispostaPermessi? = nil) -> Bool {
        let scelta = risposta ?? permessi
        guard scelta != .nonRispondere else { return false }
        var risposto = false
        // Più domande di fila (fotocamera e poi microfono): al massimo tre.
        for _ in 0..<3 {
            guard let domanda = domandaDiSistema() else { break }
            let titolo = domanda.label
            let nomi = scelta == .concedi ? Self.nomiConsenti : Self.nomiNega
            var premuto = false
            for nome in nomi {
                let pulsante = domanda.buttons[nome]
                if pulsante.exists {
                    nota("Domanda di sistema «\(titolo)»: rispondo «\(nome)»")
                    premi(pulsante)
                    premuto = true
                    break
                }
            }
            if !premuto {
                nota("Domanda di sistema «\(titolo)» senza un pulsante noto: \(domanda.buttons.allElementsBoundByIndex.map { $0.label })")
                break
            }
            risposto = true
            aspettaUnPo(1)
        }
        return risposto
    }

    static let nomiConsenti = ["Allow", "Allow While Using App", "Allow Full Access", "OK", "Consenti",
                               "Consenti mentre usi l’app", "Consenti mentre usi l'app"]
    static let nomiNega = ["Don’t Allow", "Don't Allow", "Non consentire"]

    // MARK: - Ricerca degli elementi

    /// I tipi preferiti, in ordine: se la stessa etichetta è su un pulsante e su un testo, si tocca il pulsante.
    private static let tipiPreferiti: [XCUIElement.ElementType] = [
        .button, .link, .cell, .menuItem, .menuButton, .popUpButton, .tab, .radioButton, .checkBox, .switch,
        .outlineRow, .tableRow, .textField, .searchField, .staticText, .image, .other
    ]

    /// Cerca l'elemento per etichetta, identificatore o titolo, aspettando fino a `secondi`. Ordine: un controllo
    /// (pulsante, cella, voce di menu…) con il testo uguale, poi un controllo che lo contiene, poi un testo semplice
    /// uguale, poi uno che lo contiene. A parità, quello toccabile.
    @MainActor func trova(_ etichetta: String, dentro nomeContenitore: String? = nil, secondi: Double = 5) -> XCUIElement? {
        let esatto = NSPredicate(format: "identifier == %@ OR label == %@ OR title == %@ OR value == %@",
                                 etichetta, etichetta, etichetta, etichetta)
        let contiene = NSPredicate(format: "label CONTAINS[c] %@ OR title CONTAINS[c] %@", etichetta, etichetta)
        let limite = Date().addingTimeInterval(secondi)
        repeat {
            var radice: XCUIElement = app
            if let nomeContenitore {
                guard let trovato = contenitore(nomeContenitore) else {
                    if Date() >= limite { break }
                    aspettaUnPo(0.4)
                    continue
                }
                radice = trovato
            }
            let uguali = candidati(radice.descendants(matching: .any).matching(esatto))
            var simili = candidati(radice.descendants(matching: .any).matching(contiene))
            #if os(macOS)
            // Sul Mac i testi hanno solo il valore (niente etichetta): «contiene» si controlla qui.
            simili += testiCheContengono(etichetta, in: radice)
            #endif
            let gruppi = [uguali.filter { Self.controllo($0) }, simili.filter { Self.controllo($0) },
                          uguali.filter { !Self.controllo($0) }, simili.filter { !Self.controllo($0) }]
            // Prima uno toccabile (nell'ordine dei gruppi): una voce di un menu chiuso esiste ma non si tocca.
            for gruppo in gruppi {
                if let toccabile = gruppo.first(where: { $0.isHittable }) { return toccabile }
            }
            if let primo = gruppi.first(where: { !$0.isEmpty })?.first { return primo }
            if Date() >= limite { break }
            rispondiAlleDomandeDiSistema()
            aspettaUnPo(0.4)
        } while Date() < limite
        return nil
    }

    /// Come `trova`; se non c'è, scorre (prima in giù, poi in su) e riguarda: gli elenchi di SwiftUI creano le
    /// righe solo quando arrivano sullo schermo, quindi una riga in fondo non esiste finché non si scorre.
    @MainActor func trovaScorrendo(_ etichetta: String, dentro contenitore: String? = nil, secondi: Double = 5) -> XCUIElement? {
        if let elemento = trova(etichetta, dentro: contenitore, secondi: min(secondi, 3)) {
            #if os(macOS)
            // Sul Mac si scorre solo dentro un contenitore dato: scorrere la finestra intera non serve.
            if elemento.isHittable || contenitore == nil { return elemento }
            #else
            if elemento.isHittable { return elemento }
            #endif
        }
        for giu in [true, true, true, true, true, false, false, false, false, false, false, false, false] {
            #if os(macOS)
            if contenitore == nil { break }
            #endif
            scorri(giu: giu, dentro: contenitore)
            if let elemento = trova(etichetta, dentro: contenitore, secondi: 0), elemento.isHittable { return elemento }
        }
        return trova(etichetta, dentro: contenitore, secondi: max(0, secondi - 3))
    }

    /// Il contenitore con questa etichetta, identificatore o titolo: un gruppo, un elenco, una finestra, un foglio…
    /// (non un pulsante con lo stesso nome). Serve a `dentro:` quando un nome compare in più punti.
    @MainActor func contenitore(_ nome: String) -> XCUIElement? {
        let predicato = NSPredicate(format: "identifier == %@ OR label == %@ OR title == %@", nome, nome, nome)
        let tipi: [XCUIElement.ElementType] = [.group, .scrollView, .outline, .table, .collectionView, .sheet,
                                               .popover, .dialog, .window, .navigationBar, .other]
        for tipo in tipi {
            let elemento = app.descendants(matching: tipo).matching(predicato).firstMatch
            if elemento.exists { return elemento }
        }
        return nil
    }

    #if os(macOS)
    /// I testi sotto `radice` il cui valore contiene `testo` (al massimo 150 testi guardati).
    @MainActor private func testiCheContengono(_ testo: String, in radice: XCUIElement) -> [XCUIElement] {
        radice.staticTexts.allElementsBoundByIndex.prefix(150).filter { elemento in
            guard let valore = elemento.value as? String else { return false }
            return valore.localizedCaseInsensitiveContains(testo)
        }
    }
    #endif

    /// Un elemento che si tocca (prima di `.staticText` nell'elenco dei tipi preferiti).
    @MainActor private static func controllo(_ elemento: XCUIElement) -> Bool {
        guard let posto = tipiPreferiti.firstIndex(of: elemento.elementType),
              let testi = tipiPreferiti.firstIndex(of: .staticText) else { return false }
        return posto < testi
    }

    /// Gli elementi trovati (al massimo 30), ordinati per tipo preferito.
    @MainActor private func candidati(_ query: XCUIElementQuery) -> [XCUIElement] {
        let trovati = query.allElementsBoundByIndex.prefix(30).filter { $0.exists }
        func posto(_ elemento: XCUIElement) -> Int {
            Self.tipiPreferiti.firstIndex(of: elemento.elementType) ?? Self.tipiPreferiti.count
        }
        return trovati.sorted { posto($0) < posto($1) }
    }

    /// Tocca o fa clic; se l'elemento è fuori dallo schermo (iPhone) prova prima a scorrere fin lì.
    @MainActor func premi(_ elemento: XCUIElement) {
        #if os(iOS)
        if !elemento.isHittable {
            for giu in [true, true, true, true, false, false, false, false, false, false] where !elemento.isHittable {
                if giu { app.swipeUp() } else { app.swipeDown() }
            }
        }
        if elemento.isHittable {
            elemento.tap()
        } else {
            elemento.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        #else
        elemento.click()
        #endif
    }
}
