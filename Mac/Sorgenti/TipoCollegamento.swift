import Network
import Stile
import SwiftUI

/// Come è collegato il telefono (1.2): si vede accanto alla qualità e nella scheda del telefono.
/// Il Mac lo ricava dal proprio lato, dal percorso della connessione accettata; nessun messaggio nuovo.
enum TipoCollegamento: Equatable, Sendable {
    case wifi
    case cavoUSB
    case wifiDiretto
    case cavoDiRete
    /// L'Hotspot personale dell'iPhone, via Wi-Fi o via cavo («iPhone USB»): macOS lo segna come rete a consumo.
    case hotspot

    /// Dal percorso di una NWConnection già pronta. `awdl0` (e `llw0`, la sua compagna) = Wi-Fi diretto.
    /// Una connessione che arriva dal client usbmux non passa di qui: è sempre `.cavoUSB`.
    /// Il Tethering USB di Android (NCM) arriva da una `en*` di tipo `wiredEthernet`, come un adattatore
    /// Ethernet USB (molti usano lo stesso driver NCM): non si distingue in modo sicuro, quindi resta
    /// «Cavo di rete». Su Windows invece la scheda RNDIS/NCM ha un nome riconoscibile e vale «Cavo USB».
    init(percorso: NWPath?) {
        guard let percorso, let interfaccia = percorso.availableInterfaces.first else {
            self = .wifi
            return
        }
        if interfaccia.name.hasPrefix("awdl") || interfaccia.name.hasPrefix("llw") {
            self = .wifiDiretto
            return
        }
        switch interfaccia.type {
        case .wiredEthernet:
            self = percorso.isExpensive ? .hotspot : .cavoDiRete
        case .wifi:
            self = percorso.isExpensive ? .hotspot : .wifi
        default:
            self = .wifi
        }
    }

    var testo: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .cavoUSB: "Cavo USB"
        case .wifiDiretto: "Wi-Fi diretto"
        case .cavoDiRete: "Cavo di rete"
        case .hotspot: "Hotspot"
        }
    }

    /// Simbolo SF accanto al testo.
    var simbolo: String {
        switch self {
        case .wifi: "wifi"
        case .cavoUSB: "cable.connector"
        case .wifiDiretto: "antenna.radiowaves.left.and.right"
        case .cavoDiRete: "network"
        case .hotspot: "personalhotspot"
        }
    }

    /// Un consiglio quando esiste un collegamento migliore e la qualità ne ha bisogno (nell'aiuto al passaggio).
    func consiglio(qualita: QualitaCollegamento?) -> String? {
        switch self {
        case .cavoUSB, .cavoDiRete:
            return nil
        case .wifi, .hotspot, .wifiDiretto:
            guard qualita == .debole else { return nil }
            return "Con il cavo USB il collegamento è più stabile e il telefono si ricarica."
        }
    }
}

/// «Wi-Fi», «Cavo USB»…: icona e parola, accanto alla qualità (1.2). Tenue, non ciano: è un'informazione, non un'azione.
struct IndicatoreCollegamento: View {
    let tipo: TipoCollegamento
    var qualita: QualitaCollegamento?

    init(_ tipo: TipoCollegamento, qualita: QualitaCollegamento? = nil) {
        self.tipo = tipo
        self.qualita = qualita
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tipo.simbolo)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(tipo.testo)
                .font(.etichetta(14))
                .lineLimit(1)
        }
        .foregroundStyle(Tema.testoTenue)
        .fixedSize()
        .help(tipo.consiglio(qualita: qualita) ?? "Collegato via \(tipo.testo)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Collegato via \(tipo.testo)")
    }
}
