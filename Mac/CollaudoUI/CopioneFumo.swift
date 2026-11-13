// Copione «fumo» del Mac: la finestra principale senza telefoni, il pannello Impostazioni con tutte le pagine,
// il menu «Aiuto» con la finestra «App e assistenza» e il menu «WebcamLR». Schermata e albero per ciascuna.
// Il Mac di GitHub non ha telefoni né fotocamera: si annota che cosa mostra l'app senza.

import XCTest

final class CopioneFumo: CopioneCollaudo {

    /// Le pagine del pannello Impostazioni, con la riga di dettaglio che le distingue (alcuni titoli, come «Sfondo» e
    /// «Schermo», sono anche pulsanti sotto il video).
    private static let pagineImpostazioni: [(titolo: String, dettaglio: String)] = [
        ("Fotocamera", "Obiettivo, zoom, esposizione, messa a fuoco"),
        ("Effetti", "Filtro, regolazioni, ritocco, scritta e logo"),
        ("Sfondo", "Nessuno, sfocatura o un'immagine"),
        ("Profili", "Profili pronti e profili salvati"),
        ("Qualità e collegamento", "Qualità video, Wi-Fi o USB, numeri"),
        ("Schermo", "Riempi l'inquadratura, finestra mini, barra dei menu"),
        ("Microfono", "Il microfono del telefono sul Mac"),
        ("Telefoni", "Collegati, fidati, collegane un altro"),
        ("Sicurezza", "Codice di questo Mac, telefoni fidati"),
        ("Uscite", "Webcam virtuale, microfono, NDI"),
        ("Schermata di attesa", "Cosa vedono le app quando il video non c'è"),
        ("Gobbo", "Un testo che scorre sul telefono"),
        ("Avvio e notifiche", "Apri all'avvio del Mac, notifiche"),
        ("Registro del collegamento", "Gli ultimi eventi, da copiare"),
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
            guard tocca(pagina.dettaglio) else { continue }
            fotografa("impostazioni \(pagina.titolo)")
            scorri(giu: true, volte: 2)
            fotografa("impostazioni \(pagina.titolo) in fondo")
            tocca("Indietro")
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
                    if tocca(scheda) {
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
