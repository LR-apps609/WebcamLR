import Foundation

/// La strada preferita tra Wi-Fi e cavo USB (Interfaccia finale, regola «Automatico»), scelta nelle Impostazioni
/// del telefono (Collegamento) o dal computer (`comando.collegamento`). I valori sono quelli del protocollo.
///
/// - Automatico: la strada si sceglie all'inizio (la più veloce disponibile) e poi resta. Si cambia solo se quella in
///   uso si stacca, o se si attacca il cavo durante il Wi-Fi (un passaggio). Mai per la latenza. Dopo un cambio,
///   per 30 secondi niente cambi automatici (anche se il cavo va e viene).
/// - Wi-Fi o Cavo USB: resta quella; se si stacca si usa l'altra solo per non perdere il video, e si torna appena
///   possibile.
enum PreferenzaCollegamento: String, CaseIterable, Identifiable, Sendable {
    case automatico
    case wifi
    case cavo

    var id: String { rawValue }

    /// La chiave di `UserDefaults`, la stessa di Impostazioni › Collegamento.
    static let chiave = "preferenzaCollegamento"

    /// Dopo un cambio di strada, niente cambi automatici per questi secondi.
    static let pausaDopoCambio: TimeInterval = 30

    /// La scelta salvata; un valore sconosciuto vale «Automatico».
    static var salvata: PreferenzaCollegamento {
        PreferenzaCollegamento(rawValue: UserDefaults.standard.string(forKey: chiave) ?? "") ?? .automatico
    }

    var testo: String {
        switch self {
        case .automatico: String(localized: "Automatico")
        case .wifi: "Wi-Fi"
        case .cavo: String(localized: "Cavo USB")
        }
    }
}

extension TipoCollegamento {
    /// Il nome della strada nel protocollo (`stato.collegamento.attivo` e `strade[].tipo`).
    var nomeProtocollo: String {
        switch self {
        case .wifi: "wifi"
        case .cavoUSB: "cavo"
        case .hotspot: "hotspot"
        case .wifiDiretto: "wifiDiretto"
        case .cavoDiRete: "rete"
        }
    }

    /// L'ordine delle strade nello `stato`: prima quelle senza fili, il cavo USB per ultimo.
    static let ordineProtocollo = ["wifi", "wifiDiretto", "hotspot", "rete", "cavo"]
}
