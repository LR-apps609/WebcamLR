import Foundation

/// Il contenuto del QR code che il computer mostra per farsi trovare senza Bonjour (funzione 2).
/// Formato in Documenti/Protocollo.md: `webcamlr://collega?h=<indirizzi>&p=<porta>&n=<nome>&v=1`.
public struct Associazione: Equatable, Sendable {
    public var indirizzi: [String]
    public var porta: UInt16
    public var nome: String
    public var versione: Int

    public init(indirizzi: [String], porta: UInt16 = Servizio.portaPredefinita, nome: String,
                versione: Int = Servizio.versioneProtocollo) {
        self.indirizzi = indirizzi
        self.porta = porta
        self.nome = nome
        self.versione = versione
    }

    public var testo: String {
        var componenti = URLComponents()
        componenti.scheme = "webcamlr"
        componenti.host = "collega"
        // URLComponents non codifica «&», «+» e «=» nei valori: un nome come «Studio & Casa» romperebbe il QR.
        var consentiti = CharacterSet.urlQueryAllowed
        consentiti.remove(charactersIn: "&+=#")
        func codifica(_ valore: String) -> String {
            valore.addingPercentEncoding(withAllowedCharacters: consentiti) ?? valore
        }
        componenti.percentEncodedQueryItems = [
            URLQueryItem(name: "h", value: indirizzi.map(codifica).joined(separator: ",")),
            URLQueryItem(name: "p", value: String(porta)),
            URLQueryItem(name: "n", value: codifica(nome)),
            URLQueryItem(name: "v", value: String(versione))
        ]
        return componenti.string ?? ""
    }

    /// Legge un QR code di WebcamLR; `nil` se non lo è.
    public init?(testo: String) {
        guard let componenti = URLComponents(string: testo),
              componenti.scheme == "webcamlr", componenti.host == "collega" else { return nil }
        let valori = Dictionary((componenti.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { primo, _ in primo }
        let indirizzi = (valori["h"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        guard !indirizzi.isEmpty else { return nil }
        self.indirizzi = indirizzi
        porta = UInt16(valori["p"] ?? "") ?? Servizio.portaPredefinita
        nome = valori["n"].flatMap { $0.isEmpty ? nil : $0 } ?? indirizzi[0]
        versione = Int(valori["v"] ?? "") ?? Servizio.versioneProtocollo
    }

    /// Un indirizzo scritto a mano: `192.168.1.20` oppure `192.168.1.20:52741`.
    public init?(indirizzoScritto: String) {
        let pulito = indirizzoScritto.trimmingCharacters(in: .whitespacesAndNewlines)
        let parti = pulito.split(separator: ":", omittingEmptySubsequences: false)
        guard parti.count <= 2, let host = parti.first, Self.eIPv4(String(host)) else { return nil }
        var porta = Servizio.portaPredefinita
        if parti.count == 2 {
            guard let scritta = UInt16(parti[1]), scritta > 0 else { return nil }
            porta = scritta
        }
        self.init(indirizzi: [String(host)], porta: porta, nome: String(host))
    }

    static func eIPv4(_ testo: String) -> Bool {
        let numeri = testo.split(separator: ".", omittingEmptySubsequences: false)
        return numeri.count == 4 && numeri.allSatisfy { parte in
            !parte.isEmpty && parte.count <= 3 && parte.allSatisfy(\.isNumber) && (Int(parte) ?? 256) <= 255
        }
    }
}
