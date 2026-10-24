import Foundation
import WebcamLRProtocollo

/// Avvio rapido misurato (1.11): il tempo dall'arrivo della connessione (accettata dal listener, o canale del
/// cavo aperto) al primo fotogramma decodificato e mostrato, con le tappe in mezzo per capire dove si perde tempo.
/// Stessa logica e stesse frasi di Windows/WebcamLR.Ricevitore/MisuraAvvio.cs (provata lì con i test).
/// Si usa solo sulla coda della sessione; ogni tappa conta solo la prima volta.
struct MisuraAvvio: Sendable {
    /// Orologio del protocollo, in microsecondi.
    let arrivo: UInt64
    private var stretta: UInt64?
    private var benvenuto: UInt64?
    private var primoFotogramma: UInt64?
    private var mostrato: UInt64?
    private var conConferma = false

    init(arrivo: UInt64) {
        self.arrivo = arrivo
    }

    /// Risposta alla stretta di mano spedita.
    mutating func segnaStretta(_ adesso: UInt64 = Orologio.adesso()) {
        if stretta == nil { stretta = adesso }
    }

    /// Telefono accettato, `benvenuto` spedito.
    mutating func segnaBenvenuto(_ adesso: UInt64 = Orologio.adesso()) {
        if benvenuto == nil { benvenuto = adesso }
    }

    /// Arrivato il primo fotogramma video.
    mutating func segnaPrimoFotogramma(_ adesso: UInt64 = Orologio.adesso()) {
        if primoFotogramma == nil { primoFotogramma = adesso }
    }

    /// L'utente ha dovuto confermare il telefono: il tempo comprende la sua risposta.
    mutating func segnaConferma() {
        conConferma = true
    }

    /// Il primo fotogramma è a schermo. Vero solo la prima volta: allora va scritto nel registro.
    mutating func segnaMostrato(_ adesso: UInt64 = Orologio.adesso()) -> Bool {
        guard mostrato == nil else { return false }
        mostrato = adesso
        return true
    }

    /// «Avvio: 0,9 s», per la modalità avanzata; nil finché il video non è a schermo.
    var testo: String? {
        durata(mostrato).map { Self.testo(microsecondi: $0) }
    }

    /// La riga del registro: il totale e le tappe in millisecondi dall'arrivo.
    var riga: String? {
        guard let totale = durata(mostrato) else { return nil }
        var tappe: [String] = []
        if let valore = durata(stretta) { tappe.append(String(localized: "stretta di mano \(Self.millisecondi(valore))")) }
        if let valore = durata(benvenuto) { tappe.append(String(localized: "benvenuto \(Self.millisecondi(valore))")) }
        if let valore = durata(primoFotogramma) { tappe.append(String(localized: "primo fotogramma \(Self.millisecondi(valore))")) }
        tappe.append(String(localized: "a schermo \(Self.millisecondi(totale))"))
        let riga = "\(Self.testo(microsecondi: totale)) (\(tappe.joined(separator: " · ")))"
        return conConferma ? String(localized: "\(riga), con la conferma dell'utente") : riga
    }

    /// Secondi con un decimale e la virgola: «Avvio: 0,9 s»; sotto il decimo «Avvio: 0,1 s».
    /// In inglese (P22) il catalogo dei testi mette il punto: «Startup: 0.9 s».
    static func testo(microsecondi: UInt64) -> String {
        let decimi = max(1, Int((Double(microsecondi) / 100_000).rounded()))
        return String(localized: "Avvio: \(decimi / 10),\(decimi % 10) s")
    }

    private static func millisecondi(_ microsecondi: UInt64) -> String {
        "\(Int((Double(microsecondi) / 1000).rounded())) ms"
    }

    private func durata(_ tappa: UInt64?) -> UInt64? {
        guard let tappa else { return nil }
        return tappa - min(tappa, arrivo)
    }
}
