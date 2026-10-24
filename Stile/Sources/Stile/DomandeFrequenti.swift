import Foundation

/// Domande frequenti (1.4): dentro l'app, senza bisogno di Internet. Gli stessi testi sono in
/// Windows/WebcamLR.Ricevitore/DomandeFrequenti.cs. Ogni errore dell'app può portare alla sua risposta con `id`.
public struct DomandaFrequente: Identifiable, Sendable {
    public let id: String
    public let domanda: String
    public let risposta: String
    /// Parole in più per la ricerca (sinonimi che le persone scrivono davvero).
    public let parole: [String]

    /// Vero se la domanda contiene tutte le parole cercate, ignorando maiuscole e accenti.
    public func corrisponde(_ ricerca: String) -> Bool {
        let parti = Self.normalizza(ricerca).split(separator: " ")
        guard !parti.isEmpty else { return true }
        let testo = Self.normalizza(([domanda, risposta] + parole).joined(separator: " "))
        return parti.allSatisfy { testo.contains($0) }
    }

    static func normalizza(_ testo: String) -> String {
        testo.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
    }
}

public enum DomandeFrequenti {
    public static let tutte: [DomandaFrequente] = [
        DomandaFrequente(
            id: "non-trova",
            domanda: String(localized: "Il telefono non trova il computer", bundle: .stile),
            risposta: String(localized: "Apri WebcamLR sul computer. Controlla che telefono e computer siano sulla stessa rete Wi-Fi (non quella «ospiti»). Sull'iPhone: Impostazioni › Privacy e sicurezza › Rete locale › WebcamLR attivo. Se ancora non compare, usa il QR code del computer o il cavo USB.", bundle: .stile),
            parole: ["cerca", "lista", "vuota", "compare", "trovato", "iphone", "android"]),
        DomandaFrequente(
            id: "rete-locale",
            domanda: String(localized: "Cos'è il permesso «Rete locale»?", bundle: .stile),
            risposta: String(localized: "È il permesso che iOS chiede sull'iPhone per cercare i computer in casa tua. Senza, WebcamLR non può vedere il computer. Lo attivi in Impostazioni › Privacy e sicurezza › Rete locale. WebcamLR non usa la rete per nient'altro.", bundle: .stile),
            parole: ["permesso", "privacy", "negato", "iphone", "ios"]),
        DomandaFrequente(
            id: "rete-ospiti",
            domanda: String(localized: "In hotel, in ufficio o a scuola non si collega", bundle: .stile),
            risposta: String(localized: "Molte reti pubbliche tengono i dispositivi separati: sono online ma non possono parlarsi. Usa il cavo USB, oppure attiva l'hotspot del telefono (sull'iPhone «Hotspot personale») e collega il computer a quello.", bundle: .stile),
            parole: ["albergo", "hotel", "ufficio", "scuola", "università", "pubblica", "isolamento", "hotspot"]),
        DomandaFrequente(
            id: "cavo",
            domanda: String(localized: "Come mi collego con il cavo USB?", bundle: .stile),
            risposta: String(localized: "Con l'iPhone: collegalo al computer con il cavo e apri WebcamLR su tutti e due; il collegamento parte da solo e in alto compare «Cavo USB». Su Windows serve l'app gratuita «Dispositivi Apple» di Microsoft Store. Se sei già collegato in Wi-Fi, il video passa al cavo da solo, senza fermarsi; se stacchi il cavo torna al Wi-Fi. Con Android: collega il cavo, sul telefono attiva «Tethering USB» (Impostazioni › Hotspot e tethering) e scegli il computer, o usa il QR code; sul Mac funziona solo con alcuni telefoni. Il cavo è la scelta più stabile e intanto ricarica il telefono.", bundle: .stile),
            parole: ["usb", "cavo", "lightning", "usb-c", "filo", "tethering", "android", "iphone"]),
        DomandaFrequente(
            id: "codice",
            domanda: String(localized: "Perché il computer mi chiede un codice?", bundle: .stile),
            risposta: String(localized: "È la prima volta che quel telefono si collega. Controlla che le 4 cifre siano uguali sul telefono e sul computer, poi scegli «Consenti». Dalla volta dopo si collega senza domande. Con il QR code il codice non serve.", bundle: .stile),
            parole: ["4 cifre", "consentire", "abbinamento", "conferma"]),
        DomandaFrequente(
            id: "identita",
            domanda: String(localized: "«L'identità del computer è cambiata»: cosa vuol dire?", bundle: .stile),
            risposta: String(localized: "Il telefono ricorda ogni computer usato. Se un computer con lo stesso nome si presenta diverso, il telefono si ferma per sicurezza. Succede se hai reinstallato WebcamLR sul computer: collegati di nuovo con il QR code. Se non hai cambiato niente, non collegarti.", bundle: .stile),
            parole: ["sicurezza", "cambiata", "diverso"]),
        DomandaFrequente(
            id: "ritardo",
            domanda: String(localized: "Il video è in ritardo o va a scatti", bundle: .stile),
            risposta: String(localized: "Guarda l'indicatore in alto: «Ottimo», «Buono» o «Debole». Con «Debole» avvicinati al router, usa la rete a 5 GHz, ferma i download, oppure usa il cavo USB. Il Wi-Fi diretto, se acceso sul Mac, può rendere la latenza meno stabile: spegnilo se non serve.", bundle: .stile),
            parole: ["lag", "latenza", "lento", "scatti", "ms", "millisecondi", "blocca"]),
        DomandaFrequente(
            id: "zoom-teams",
            domanda: String(localized: "Zoom, Teams o Meet non vedono WebcamLR", bundle: .stile),
            risposta: String(localized: "Nelle impostazioni video dell'app scegli «WebcamLR» come videocamera. Se non c'è, chiudi e riapri l'app della chiamata dopo aver aperto WebcamLR. Sul Mac la webcam virtuale richiede l'account sviluppatore Apple a pagamento; su Windows arriva con un prossimo aggiornamento.", bundle: .stile),
            parole: ["zoom", "teams", "meet", "facetime", "obs", "videocamera", "webcam virtuale"]),
        DomandaFrequente(
            id: "caldo",
            domanda: String(localized: "Il telefono si scalda", bundle: .stile),
            risposta: String(localized: "È normale durante le chiamate lunghe. WebcamLR oscura lo schermo dopo 30 secondi e, se il telefono scalda molto, abbassa da sola la qualità e lo dice. Togli la custodia, tieni il telefono lontano dal sole e, se puoi, non caricarlo durante la chiamata.", bundle: .stile),
            parole: ["calore", "caldo", "scotta", "temperatura"]),
        DomandaFrequente(
            id: "batteria",
            domanda: String(localized: "La batteria scende in fretta", bundle: .stile),
            risposta: String(localized: "Sotto il 20% senza caricatore WebcamLR passa a 24 fotogrammi al secondo per durare di più. Per chiamate lunghe collega il caricatore, o il cavo USB al computer, che carica e trasmette insieme.", bundle: .stile),
            parole: ["batteria", "carica", "consumo"]),
        DomandaFrequente(
            id: "nero",
            domanda: String(localized: "Sul computer il video è nero", bundle: .stile),
            risposta: String(localized: "Aspetta qualche secondo: il video parte dal primo fotogramma completo. Su Windows, se sul telefono hai scelto HEVC, serve «Estensioni video HEVC» di Microsoft Store: altrimenti scegli H.264 nelle impostazioni del telefono.", bundle: .stile),
            parole: ["nero", "schermo", "niente", "hevc", "vuoto"]),
        DomandaFrequente(
            id: "firewall",
            domanda: String(localized: "Su Windows non si collega mai", bundle: .stile),
            risposta: String(localized: "Al primo avvio Windows chiede il permesso per le reti: va consentito per le reti private. Controlla anche che la rete del PC sia «privata» (Impostazioni › Rete e Internet › Wi-Fi › proprietà). Con il Tethering USB di Android vale anche per la rete del cavo, in Rete e Internet › Ethernet. Con il cavo dell'iPhone il firewall non conta.", bundle: .stile),
            parole: ["windows", "firewall", "defender", "rete pubblica", "tethering"]),
        DomandaFrequente(
            id: "qualita",
            domanda: String(localized: "Come ottengo la qualità migliore?", bundle: .stile),
            risposta: String(localized: "Metti il telefono in orizzontale su un supporto, usa la fotocamera posteriore (è la migliore), una buona luce davanti a te e il cavo USB o un Wi-Fi a 5 GHz. In Impostazioni puoi scegliere risoluzione e fotogrammi al secondo.", bundle: .stile),
            parole: ["qualità", "nitido", "4k", "1080p", "risoluzione", "luce"]),
        DomandaFrequente(
            id: "privacy",
            domanda: String(localized: "Il mio video passa da Internet?", bundle: .stile),
            risposta: String(localized: "No. Il video va dal telefono al computer solo sulla tua rete o sul cavo, cifrato con chiavi nuove a ogni collegamento. WebcamLR non ha account obbligatori, non registra e non raccoglie dati.", bundle: .stile),
            parole: ["privacy", "sicuro", "internet", "cloud", "dati"]),
        DomandaFrequente(
            id: "aggiorna",
            domanda: String(localized: "«Aggiorna WebcamLR sul computer»: cosa devo fare?", bundle: .stile),
            risposta: String(localized: "Sul computer c'è una versione vecchia di WebcamLR, che non usa ancora il collegamento cifrato. Scarica l'ultima versione dal sito di WebcamLR e installala sopra quella vecchia: i tuoi telefoni restano. Poi riapri WebcamLR su tutti e due.", bundle: .stile),
            parole: ["aggiornare", "versione", "vecchia", "aggiornamento", "scarica"]),
        DomandaFrequente(
            id: "costo",
            domanda: String(localized: "WebcamLR è gratis?", bundle: .stile),
            risposta: String(localized: "Sì: oggi tutte le funzioni sono gratis, senza filigrana né pubblicità. WebcamLR Pro, in arrivo, aggiungerà funzioni per chi vuole di più.", bundle: .stile),
            parole: ["prezzo", "gratis", "pro", "abbonamento", "filigrana", "pubblicità"])
    ]

    public static func risposta(_ id: String) -> DomandaFrequente? {
        tutte.first { $0.id == id }
    }
}
