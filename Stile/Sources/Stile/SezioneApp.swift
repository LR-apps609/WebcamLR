import Foundation

/// Contenuti della sezione App (0.12), uguali su iPhone e Mac. Windows ha gli stessi testi in SezioneApp.cs.
public enum InfoApp {
    /// Assistenza e segnalazioni: da confermare con Ledion (Documenti/Cosa serve da Ledion.md).
    /// Vuoto = «Segnala un bug» usa la condivisione di sistema invece della mail.
    public static let emailAssistenza = ""
    public static let sito = URL(string: "https://lr-apps609.github.io/WebcamLR/")!
    public static let privacy = URL(string: "https://lr-apps609.github.io/WebcamLR/privacy.html")!
    public static let aiuto = URL(string: "https://lr-apps609.github.io/WebcamLR/aiuto.html")!
    /// La pagina per scaricare l'app sul telefono (App Store e Google Play): il QR «App per il telefono» del Mac.
    public static let download = URL(string: "https://lr-apps609.github.io/WebcamLR/download.html")!
    /// L'ultima versione pubblicata, letta dal Mac per «Aggiornamento disponibile» (formato in Documenti/Pubblicazione.md).
    public static let versioneRecente = URL(string: "https://lr-apps609.github.io/WebcamLR/versione.json")!

    public static var versione: String {
        let breve = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(breve) (\(build))"
    }

    /// Cosa aggiunge WebcamLR Pro. Ciò che non è qui resta gratis.
    public static let vantaggiPro = [
        String(localized: "Video in 4K e a 60 fotogrammi", bundle: .stile),
        String(localized: "Controlli manuali: ISO, tempo, bianco", bundle: .stile),
        String(localized: "Profili salvati per ogni situazione", bundle: .stile),
        String(localized: "Effetti: sfondo sfocato e luce da studio", bundle: .stile),
        String(localized: "Più telefoni collegati insieme", bundle: .stile)
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
        SezioneGuida(id: "inizia", titolo: String(localized: "Il primo collegamento", bundle: .stile), simbolo: "wifi", passi: [
            String(localized: "Apri WebcamLR sul computer: si fa trovare da solo sulla rete.", bundle: .stile),
            String(localized: "Sul telefono, stessa rete Wi-Fi del computer, tocca il nome del computer.", bundle: .stile),
            String(localized: "La prima volta il computer chiede di confermare: controlla che il codice sia lo stesso sui due schermi.", bundle: .stile),
            String(localized: "Dalla volta dopo il telefono si ricollega da solo appena apri l'app.", bundle: .stile)
        ]),
        SezioneGuida(id: "qr", titolo: String(localized: "Con il QR code", bundle: .stile), simbolo: "qrcode.viewfinder", passi: [
            String(localized: "Se il computer non compare, sul computer apri «Collega con QR code».", bundle: .stile),
            String(localized: "Sul telefono tocca «Inquadra il QR code del computer» e inquadralo.", bundle: .stile),
            String(localized: "È anche il modo più sicuro: il QR contiene il codice di sicurezza del computer.", bundle: .stile)
        ]),
        SezioneGuida(id: "chiamate", titolo: String(localized: "Usarla in Zoom, Meet e Teams", bundle: .stile), simbolo: "video", passi: [
            String(localized: "Nell'app della chiamata apri le impostazioni video.", bundle: .stile),
            String(localized: "Come videocamera scegli «WebcamLR».", bundle: .stile),
            String(localized: "Quando un'app usa il video, sul telefono e sul computer compare «In onda» in rosso.", bundle: .stile)
        ]),
        SezioneGuida(id: "inquadratura", titolo: String(localized: "Inquadrarsi bene", bundle: .stile), simbolo: "camera.viewfinder", passi: [
            String(localized: "Metti il telefono in orizzontale, all'altezza degli occhi, su un supporto.", bundle: .stile),
            String(localized: "Accendi griglia e livella nelle impostazioni: la linea diventa verde quando è dritto.", bundle: .stile),
            String(localized: "Tieni premuto sull'anteprima per il Blocco AE/AF: messa a fuoco ed esposizione restano ferme.", bundle: .stile),
            String(localized: "Doppio tocco per passare dalla fotocamera posteriore alla frontale.", bundle: .stile)
        ]),
        SezioneGuida(id: "batteria", titolo: String(localized: "Batteria e calore", bundle: .stile), simbolo: "battery.75percent", passi: [
            String(localized: "Durante le chiamate lo schermo si oscura da solo: si risparmia batteria e il telefono scalda meno.", bundle: .stile),
            String(localized: "Per chiamate lunghe collega il caricatore.", bundle: .stile),
            String(localized: "Se il telefono scalda molto, WebcamLR abbassa da sola la qualità e lo dice.", bundle: .stile)
        ]),
        SezioneGuida(id: "problemi", titolo: String(localized: "Se non si collega", bundle: .stile), simbolo: "questionmark.circle", passi: [
            String(localized: "Telefono e computer devono essere sulla stessa rete Wi-Fi (non quella «ospiti»).", bundle: .stile),
            String(localized: "Sull'iPhone: Impostazioni › Privacy e sicurezza › Rete locale › WebcamLR attivo.", bundle: .stile),
            String(localized: "Su Windows consenti WebcamLR nelle reti private quando il sistema lo chiede.", bundle: .stile),
            String(localized: "In hotel o in ufficio, dove la rete blocca i dispositivi tra loro, attiva l'hotspot del telefono e collega il computer a quello.", bundle: .stile),
            String(localized: "Senza una rete in comune, con un Mac: accendi «Wi-Fi diretto» nelle Impostazioni di WebcamLR sul Mac; si trovano come con AirDrop. Spegnilo quando non serve: la latenza è più stabile.", bundle: .stile),
            String(localized: "Con il cavo USB: collega l'iPhone al computer e apri WebcamLR su tutti e due; in alto compare «Cavo USB». Su Windows serve l'app gratuita «Dispositivi Apple». È il collegamento più stabile.", bundle: .stile),
            String(localized: "Con il cavo e Android: sul telefono attiva «Tethering USB» e collegati come in Wi-Fi o con il QR code. Sul Mac funziona solo con alcuni telefoni.", bundle: .stile),
            String(localized: "Ancora niente? Apri «Domande frequenti», usa il QR code, oppure «Segnala un bug».", bundle: .stile)
        ])
    ]
}

/// Il testo di «Segnala un bug»: la descrizione dell'utente e i dati tecnici, se li vuole includere.
public enum SegnalazioneBug {
    public static func testo(descrizione: String, datiTecnici: [(String, String)]?) -> String {
        var righe = [descrizione.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let datiTecnici, !datiTecnici.isEmpty {
            righe.append("")
            righe.append(String(localized: "— Dati tecnici —", bundle: .stile))
            righe.append(contentsOf: datiTecnici.map { "\($0.0): \($0.1)" })
        }
        return righe.joined(separator: "\n")
    }

    public static let oggetto = String(localized: "WebcamLR: segnalazione", bundle: .stile)
}
