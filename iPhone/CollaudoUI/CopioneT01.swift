// Copione del tester t01 (collaudo 20): Giulia, studentessa, prima volta, ha fretta. Salta la presentazione,
// tocca il primo pulsante che vede, concede o rifiuta i permessi di fretta. Si contano tocchi e secondi.

import XCTest

final class CopioneT01: CopioneCollaudo {

    private var inizio = Date()
    private var tocchi = 0

    private func cronometro(_ cosa: String) {
        nota(String(format: "[%.1f s, %d tocchi] %@", Date().timeIntervalSince(inizio), tocchi, cosa))
    }

    /// I pulsanti visibili, dall'alto in basso: quello che Giulia vede per primo.
    @MainActor private func pulsantiVisibili() -> [XCUIElement] {
        let tutti = app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable && !$0.frame.isEmpty }
        return tutti.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    @MainActor private func annotaPulsanti(_ dove: String) {
        let elenco = pulsantiVisibili().map { "«\($0.label)» [\($0.identifier)] y=\(Int($0.frame.minY))" }
        nota("Pulsanti visibili (\(dove)), dall'alto: " + elenco.joined(separator: "; "))
    }

    @MainActor private func toccaContando(_ etichetta: String) -> Bool {
        let fatto = tocca(etichetta)
        if fatto { tocchi += 1 }
        return fatto
    }

    /// Strada veloce: Salta, Inizia, Consenti, Consenti. Quanto ci vuole per arrivare alla schermata principale
    /// e che cosa le dice di fare. Poi «Mandami il link» e «Usa il cavo USB».
    @MainActor func test01_frettaConcedeTutto() {
        permessi = .nonRispondere
        avviaPulito()
        inizio = Date()
        attendi("presentazione.salta")
        fotografa("prima schermata")
        annotaPulsanti("prima pagina della presentazione")
        _ = toccaContando("presentazione.salta")
        fotografa("dopo salta")
        annotaPulsanti("dopo Salta")
        _ = toccaContando("presentazione.inizia")
        for numero in 1...2 {
            if let domanda = attendiDomandaDiSistema(secondi: 6) {
                fotografa("domanda \(numero)")
                nota("Domanda \(numero): «\(domanda.label)»")
                rispondiAlleDomandeDiSistema(.concedi, quante: 1)
                tocchi += 1
            } else {
                nota("Domanda \(numero): non comparsa")
            }
        }
        permessi = .concedi
        chiudiAvvisoPortachiavi()
        attendi("Cerco il tuo computer")
        cronometro("schermata principale «Cerco il tuo computer»")
        fotografa("principale subito")
        annotaPulsanti("principale subito")
        if attendi("Non trovo nessun computer", secondi: 25) {
            cronometro("«Non trovo nessun computer»")
            fotografa("principale non trovo")
            annotaPulsanti("principale non trovo")
            scorri(giu: true)
            fotografa("principale non trovo in fondo")
            annotaPulsanti("principale non trovo, in fondo")
            scorri(giu: false)
        }
        if toccaContando("Mandami il link per il computer") {
            aspettaUnPo(2)
            cronometro("foglio «Mandami il link»")
            fotografa("mandami il link")
            chiudiFoglio()
        }
        if toccaContando("Usa il cavo USB") {
            aspettaUnPo(1)
            cronometro("dopo «Usa il cavo USB»")
            fotografa("cavo USB")
            annotaPulsanti("dopo il cavo USB")
            chiudiFoglio()
            fotografa("dopo il cavo chiuso")
        }
        if toccaContando("Inquadra il QR code del computer") {
            aspettaUnPo(2)
            cronometro("lettore QR")
            fotografa("lettore QR")
            chiudiFoglio()
        }
    }

    /// Rifiuta per sbaglio fotocamera e microfono. Che cosa le dice l'app? Dove rimedia?
    @MainActor func test02_rifiutaPerSbaglio() {
        permessi = .nonRispondere
        avviaPulito()
        inizio = Date()
        _ = toccaContando("presentazione.salta")
        _ = toccaContando("presentazione.inizia")
        for numero in 1...2 {
            if let domanda = attendiDomandaDiSistema(secondi: 6) {
                nota("Domanda \(numero): «\(domanda.label)» → Non consentire")
                rispondiAlleDomandeDiSistema(.nega, quante: 1)
            }
        }
        permessi = .nega
        chiudiAvvisoPortachiavi()
        attendi("Cerco il tuo computer")
        cronometro("principale dopo aver rifiutato tutto")
        fotografa("principale dopo il rifiuto")
        nota("C'è un avviso sulla fotocamera nella principale? \(esiste("fotocamera") ? "sì, un testo contiene «fotocamera»" : "nessun testo con «fotocamera»")")
        if attendi("Non trovo nessun computer", secondi: 25) {
            fotografa("non trovo dopo il rifiuto")
            scorri(giu: true)
            fotografa("non trovo dopo il rifiuto in fondo")
            scorri(giu: false)
        }
        if toccaContando("Inquadra il QR code del computer") {
            aspettaUnPo(2)
            cronometro("lettore QR senza permesso")
            fotografa("lettore QR senza permesso")
            annotaPulsanti("lettore QR senza permesso")
            chiudiFoglio()
        }
        // Le Impostazioni dell'app: c'è un posto per i permessi?
        if toccaContando("Impostazioni") {
            attendi("Fine")
            fotografa("impostazioni dopo il rifiuto")
            nota("Nelle Impostazioni un testo «Fotocamera»: \(esiste("Fotocamera")); «permess»: \(esiste("ermess"))")
            scorri(giu: true, volte: 2)
            fotografa("impostazioni dopo il rifiuto in fondo")
            chiudiFoglio()
        }
        // Chiude e riapre (come farebbe Giulia): l'app richiede? spiega?
        avvia()
        aspettaUnPo(2)
        fotografa("riaperta dopo il rifiuto")
        nota("Riaperta: domanda di sistema presente? \(domandaDiSistema() != nil)")
        // Infine «Apri Impostazioni» dal lettore QR: dove porta (l'app va in secondo piano?).
        if toccaSePresente("Inquadra il QR code del computer", secondi: 4) {
            aspettaUnPo(2)
            if toccaSePresente("Apri Impostazioni", secondi: 3) {
                aspettaUnPo(2)
                nota("Dopo «Apri Impostazioni» lo stato dell'app è \(app.state.rawValue) (4 = in primo piano, 3 = secondo piano)")
                let impostazioni = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
                nota("Impostazioni di iOS in primo piano: \(impostazioni.state == .runningForeground)")
                schermata("dopo apri impostazioni")
            } else {
                nota("Nel lettore QR senza permesso non c'è «Apri Impostazioni»")
            }
        }
    }

    /// Fotocamera sì, microfono no (tocca «Non consentire» sulla seconda domanda senza leggere).
    @MainActor func test03_microfonoRifiutato() {
        permessi = .nonRispondere
        avviaPulito()
        tocca("presentazione.salta")
        tocca("presentazione.inizia")
        if let domanda = attendiDomandaDiSistema(secondi: 6) {
            nota("Domanda 1: «\(domanda.label)» → Consenti")
            rispondiAlleDomandeDiSistema(.concedi, quante: 1)
        }
        if let domanda = attendiDomandaDiSistema(secondi: 6) {
            nota("Domanda 2: «\(domanda.label)» → Non consentire")
            rispondiAlleDomandeDiSistema(.nega, quante: 1)
        }
        permessi = .concedi
        chiudiAvvisoPortachiavi()
        attendi("Cerco il tuo computer")
        fotografa("principale microfono rifiutato")
        nota("Nella principale un testo «microfono»: \(esiste("icrofono"))")
        if tocca("Impostazioni") {
            attendi("Fine")
            fotografa("impostazioni microfono rifiutato")
            if toccaSePresente("Microfono", secondi: 3) {
                aspettaUnPo(1)
                fotografa("pagina microfono")
                indietro()
            } else {
                nota("Nelle Impostazioni nessuna voce «Microfono» visibile subito")
            }
            chiudiFoglio()
        }
    }

    /// Tocca il primo pulsante che vede, ogni volta, per cinque volte: dove finisce? (Pro in mezzo?)
    @MainActor func test04_primoPulsanteCheVede() {
        permessi = .concedi
        avviaPulito()
        inizio = Date()
        attendi("presentazione.salta")
        for passo in 1...6 {
            aspettaUnPo(1)
            let pulsanti = pulsantiVisibili()
            annotaPulsanti("passo \(passo)")
            guard let primo = pulsanti.first else { nota("Passo \(passo): nessun pulsante"); break }
            nota("Passo \(passo): tocco «\(primo.label)» [\(primo.identifier)]")
            primo.tap()
            tocchi += 1
            aspettaUnPo(1.5)
            rispondiAlleDomandeDiSistema(.concedi)
            chiudiAvvisoPortachiavi()
            cronometro("dopo il passo \(passo)")
            fotografa("passo \(passo) dopo \(primo.label)")
        }
    }

    /// Il foglio Pro, aperto per sbaglio dalla pillola in alto: si capisce come uscirne? Torna a collegarsi?
    @MainActor func test05_proPerSbaglio() {
        avviaPulito()
        superaPresentazione()
        attendi("Cerco il tuo computer")
        if tocca("Sblocca WebcamLR Pro") {
            aspettaUnPo(3)
            fotografa("pro per sbaglio")
            annotaPulsanti("foglio Pro")
            scorri(giu: true)
            fotografa("pro per sbaglio in fondo")
            chiudiFoglio()
            fotografa("dopo aver chiuso il Pro")
            nota("Tornata alla ricerca: \(esiste("Cerco il tuo computer") || esiste("Non trovo nessun computer"))")
        }
    }
}
