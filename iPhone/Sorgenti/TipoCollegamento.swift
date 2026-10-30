import Foundation
import Network

/// Come è collegato l'iPhone al computer (1.2, Documenti/Protocollo.md «Tipo di collegamento attivo»).
/// Si ricava dal percorso di rete della connessione: nessun messaggio nuovo nel protocollo.
enum TipoCollegamento: String, Equatable, Sendable {
    case wifi
    case cavoUSB
    case wifiDiretto
    case cavoDiRete
    case hotspot

    var testo: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .cavoUSB: String(localized: "Cavo USB")
        case .wifiDiretto: String(localized: "Wi-Fi diretto")
        case .cavoDiRete: String(localized: "Cavo di rete")
        // Come in iOS e nel glossario.
        case .hotspot: String(localized: "Hotspot personale")
        }
    }

    /// Bug 8: la parola corta per la riga di stato di «In onda» («IN ONDA · ZOOM · WI-FI»): Wi-Fi o USB, come
    /// lo dice la gente. Le strade meno comuni con la loro parola più corta.
    var testoBreve: String {
        switch self {
        case .wifi, .wifiDiretto: "Wi-Fi"
        case .cavoUSB: "USB"
        case .cavoDiRete: String(localized: "Cavo di rete")
        case .hotspot: String(localized: "Hotspot")
        }
    }

    var simbolo: String {
        switch self {
        case .wifi: "wifi"
        case .cavoUSB: "cable.connector"
        case .wifiDiretto: "point.3.connected.trianglepath.dotted"
        case .cavoDiRete: "network"
        case .hotspot: "personalhotspot"
        }
    }

    /// Senza fili: con un collegamento debole il cavo USB è più stabile.
    var senzaFili: Bool {
        switch self {
        case .wifi, .wifiDiretto, .hotspot: true
        case .cavoUSB, .cavoDiRete: false
        }
    }

    /// Il consiglio quando il collegamento è debole e ne esiste uno migliore; `nil` se si è già sul cavo.
    var consiglioSeDebole: String? {
        switch self {
        case .wifi, .hotspot: String(localized: "Con il cavo USB è più stabile")
        case .wifiDiretto: String(localized: "Con il cavo USB o sulla stessa rete Wi-Fi è più stabile")
        case .cavoUSB, .cavoDiRete: nil
        }
    }

    /// Dal percorso di una connessione già aperta. `awdl` = Wi-Fi diretto; `bridge`/`ap` e gli indirizzi
    /// 172.20.10.x = Hotspot personale; il cavo USB (127.0.0.1) lo decide chi accetta la connessione.
    static func da(_ percorso: NWPath) -> TipoCollegamento? {
        if let remoto = percorso.remoteEndpoint, eIndirizzoHotspot(remoto) { return .hotspot }
        if let usata = percorso.availableInterfaces.first {
            if usata.name.hasPrefix("awdl") || usata.name.hasPrefix("llw") { return .wifiDiretto }
            if usata.name.hasPrefix("bridge") || usata.name.hasPrefix("ap") { return .hotspot }
            switch usata.type {
            case .wifi: return .wifi
            case .wiredEthernet: return .cavoDiRete
            case .loopback: return .cavoUSB
            default: break
            }
        }
        if percorso.usesInterfaceType(.wifi) { return .wifi }
        if percorso.usesInterfaceType(.wiredEthernet) { return .cavoDiRete }
        if percorso.usesInterfaceType(.loopback) { return .cavoUSB }
        return nil
    }

    /// L'Hotspot personale dell'iPhone usa sempre la rete 172.20.10.0/28.
    private static func eIndirizzoHotspot(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint, case let .ipv4(indirizzo) = host else { return false }
        let byte = [UInt8](indirizzo.rawValue)
        return byte.count == 4 && byte[0] == 172 && byte[1] == 20 && byte[2] == 10 && byte[3] < 16
    }
}
