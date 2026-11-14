// Copione «fumo» del Mac: la finestra principale senza telefoni, il pannello Impostazioni con tutte le pagine,
// il menu «Aiuto» con la finestra «App e assistenza» e il menu «WebcamLR». Schermata e albero per ciascuna.
// Il Mac di GitHub non ha telefoni né fotocamera: si annota che cosa mostra l'app senza.

import XCTest

final class CopioneFumo: CopioneCollaudo {

    /// Le pagine del pannello Impostazioni. I titoli «Sfondo» e «Schermo» sono anche pulsanti sotto il video: per questo
    /// si cercano dentro il pannello (`dentro: "Impostazioni"`, il gruppo con quell'etichetta). Le ultime righe stanno
    /// sotto il bordo della finestra: `tocca` scorre il pannello fin lì.
    private static let pagineImpostazioni = [
        "Fotocamera", "Effetti", "Sfondo", "Profili", "Qualità e collegamento", "Schermo", "Microfono", "Telefoni",
        "Sicurezza", "Uscite", "Schermata di attesa", "Gobbo", "Avvio e notifiche", "Registro del collegamento",
    ]

    /// Primo avvio pulito: la finestra principale, le eventuali domande di sistema, la finestra tutta.
    @MainActor func test01_primoAvvio() {
        permessi = .nonRispondere
        avviaPulito()
        aspettaUnPo(3)
        if let domanda = attendiDomandaDiSistema(secondi: 5) {
            fotografa("domanda di sistema")
            nota("Domanda di sistema all'avvio: «\(domanda.label)»")
            rispondiAlleDomandeDiSistema(.concedi)
        } else {
            nota("All'avvio nessuna domanda di sistema (rete locale, fotocamera) è comparsa.")
        }
        permessi = .concedi
        let finestre = app.windows.allElementsBoundByIndex.map { "«\($0.title)»" }
        nota("Finestre aperte all'avvio: \(finestre.joined(separator: ", "))")
        attendi("Impostazioni")
        fotografa("finestra principale")
    }

    /// Il pannello Impostazioni e ogni sua pagina, con «Indietro» tra una e l'altra.
    @MainActor func test02_impostazioni() {
        avviaPulito()
        attendi("Impostazioni")
        tocca("Impostazioni")
        fotografa("impostazioni elenco")
        for pagina in Self.pagineImpostazioni {
            guard tocca(pagina, dentro: "Impostazioni") else { continue }
            fotografa("impostazioni \(pagina)")
            scorri(giu: true, volte: 2, dentro: "Impostazioni")
            fotografa("impostazioni \(pagina) in fondo")
            tocca("Indietro", dentro: "Impostazioni")
        }
        tocca("Chiudi le impostazioni")
        fotografa("impostazioni chiuse")
    }

    /// Il menu «Aiuto» e la finestra «App e assistenza» con le sue schede; poi il menu «WebcamLR».
    @MainActor func test03_aiutoEApp() {
        avviaPulito()
        attendi("Impostazioni")
        if tocca("Aiuto") {
            fotografa("menu aiuto")
            if tocca("Guida") {
                aspettaUnPo(1.5)
                fotografa("app e assistenza guida")
                for scheda in ["WebcamLR Pro", "Domande frequenti", "Segnala un bug", "Informazioni"] {
                    if tocca(scheda, dentro: "Barra laterale") {
                        aspettaUnPo(1)
                        fotografa("app e assistenza \(scheda)")
                    }
                }
                // Chiude «App e assistenza» (⌘W) e torna alla finestra principale.
                tasto("w", con: .command)
            }
        }
        if tocca("WebcamLR") {
            fotografa("menu WebcamLR")
            tasto(XCUIKeyboardKey.escape.rawValue)
        }
        fotografa("principale alla fine")
    }

    /// La stessa app in inglese.
    @MainActor func test04_inglese() {
        avviaPulito(lingua: .inglese)
        attendi("Settings")
        fotografa("en finestra principale")
        if tocca("Settings") {
            fotografa("en impostazioni")
            if !toccaSePresente("Close settings") { tasto(XCUIKeyboardKey.escape.rawValue) }
        }
        if tocca("Help") {
            fotografa("en menu aiuto")
            tasto(XCUIKeyboardKey.escape.rawValue)
        }
    }
}
