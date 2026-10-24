import Foundation

/// Contenuti della sezione App (0.12), uguali su iPhone e Mac. Windows ha gli stessi testi in SezioneApp.cs.
public enum InfoApp {
    /// Assistenza e segnalazioni: da confermare con Ledion (Documenti/Cosa serve da Ledion.md).
    /// Vuoto = «Segnala un bug» usa la condivisione di sistema invece della mail.
    public static let emailAssistenza = ""
    public static let sito = URL(string: "https://lr-apps609.github.io/WebcamLR/")!
    public static let privacy = URL(string: "https://lr-apps609.github.io/WebcamLR/privacy.html")!
    public static let aiuto = URL(string: "https://lr-apps609.github.io/WebcamLR/aiuto.html")!

    public static var versione: String {
        let breve = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(breve) (\(build))"
    }

    /// Cosa aggiunge WebcamLR Pro. Ciò che non è qui resta gratis.
    public static let vantaggiPro = [
        "Video in 4K e a 60 fotogrammi",
        "Controlli manuali: ISO, tempo, bianco",
        "Profili salvati per ogni situazione",
        "Effetti: sfondo sfocato e luce da studio",
        "Più telefoni collegati insieme"
    ]

    public static let altreAppLR = ["OrbitLR", "GateLR"]
}

/// Una sezione della guida: titolo e passi brevi, in ordine.
public struct SezioneGuida: Identifiable, Sendable {
    public let id: String
    public let titolo: String
    public let simbolo: String
    public let passi: [String]
}

public enum Guida {
    public static let sezioni: [SezioneGuida] = [
        SezioneGuida(id: "inizia", titolo: "Il primo collegamento", simbolo: "wifi", passi: [
            "Apri WebcamLR sul computer: si fa trovare da solo sulla rete.",
            "Sull'iPhone, stessa rete Wi-Fi del computer, tocca il nome del computer.",
            "La prima volta il computer chiede di confermare: controlla che il codice sia lo stesso sui due schermi.",
            "Dalla volta dopo l'iPhone si ricollega da solo appena apri l'app."
        ]),
        SezioneGuida(id: "qr", titolo: "Con il QR code", simbolo: "qrcode.viewfinder", passi: [
            "Se il computer non compare, sul computer apri «Collega con QR code».",
            "Sull'iPhone tocca «Inquadra il QR code del computer» e inquadralo.",
            "È anche il modo più sicuro: il QR contiene il codice di sicurezza del computer."
        ]),
        SezioneGuida(id: "chiamate", titolo: "Usarla in Zoom, Meet e Teams", simbolo: "video", passi: [
            "Nell'app della chiamata apri le impostazioni video.",
            "Come videocamera scegli «WebcamLR».",
            "Quando un'app usa il video, sull'iPhone e sul computer compare «In onda» in rosso."
        ]),
        SezioneGuida(id: "inquadratura", titolo: "Inquadrarsi bene", simbolo: "camera.viewfinder", passi: [
            "Metti l'iPhone in orizzontale, all'altezza degli occhi, su un supporto.",
            "Accendi griglia e livella nelle impostazioni: la linea diventa verde quando è dritto.",
            "Tieni premuto sull'anteprima per il Blocco AE/AF: messa a fuoco ed esposizione restano ferme.",
            "Doppio tocco per passare dalla fotocamera posteriore alla frontale."
        ]),
        SezioneGuida(id: "batteria", titolo: "Batteria e calore", simbolo: "battery.75percent", passi: [
            "Durante le chiamate lo schermo si oscura da solo: si risparmia batteria e il telefono scalda meno.",
            "Per chiamate lunghe collega il caricatore.",
            "Se l'iPhone scalda molto, WebcamLR abbassa da sola la qualità e lo dice."
        ]),
        SezioneGuida(id: "problemi", titolo: "Se non si collega", simbolo: "questionmark.circle", passi: [
            "iPhone e computer devono essere sulla stessa rete Wi-Fi (non quella «ospiti»).",
            "Sull'iPhone: Impostazioni › Privacy e sicurezza › Rete locale › WebcamLR attivo.",
            "Su Windows consenti WebcamLR nelle reti private quando il sistema lo chiede.",
            "In hotel o in ufficio, dove la rete blocca i dispositivi tra loro, attiva l'hotspot dell'iPhone e collega il computer a quello.",
            "Con un Mac basta anche avere Wi-Fi e Bluetooth accesi su tutti e due: si trovano senza router, come con AirDrop.",
            "Con il cavo: collega l'iPhone al computer e attiva l'hotspot personale; il collegamento passa dal cavo ed è il più stabile.",
            "Ancora niente? Usa il QR code, oppure «Segnala un bug»."
        ])
    ]
}

/// Il testo di «Segnala un bug»: la descrizione dell'utente e i dati tecnici, se li vuole includere.
public enum SegnalazioneBug {
    public static func testo(descrizione: String, datiTecnici: [(String, String)]?) -> String {
        var righe = [descrizione.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let datiTecnici, !datiTecnici.isEmpty {
            righe.append("")
            righe.append("— Dati tecnici —")
            righe.append(contentsOf: datiTecnici.map { "\($0.0): \($0.1)" })
        }
        return righe.joined(separator: "\n")
    }

    public static let oggetto = "WebcamLR: segnalazione"
}
