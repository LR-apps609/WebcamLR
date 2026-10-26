import Foundation
import Network
import Observation

/// Cosa sa l'iPhone della propria rete (1.3), per la diagnosi automatica: c'è il Wi-Fi? solo cellulare?
/// il permesso «Rete locale» è stato negato? Un solo NWPathMonitor per tutta l'app.
@Observable
@MainActor
final class StatoRete {
    static let condiviso = StatoRete()

    /// Falso finché il primo percorso non è arrivato: prima non si diagnostica nulla.
    private(set) var noto = false
    private(set) var wifi = false
    private(set) var cavoDiRete = false
    /// L'Hotspot personale dell'iPhone è acceso (interfaccia `bridge`): il computer può essere lì.
    private(set) var hotspot = false
    private(set) var cellulare = false
    /// Visto dalla ricerca dei computer (errore -65570 di Bonjour) o da un collegamento rifiutato.
    var permessoNegato = false

    @ObservationIgnored private var monitor: NWPathMonitor?

    /// Nessuna rete su cui può esserci un computer: né Wi-Fi, né cavo di rete, né hotspot.
    var senzaReteLocale: Bool {
        noto && !wifi && !cavoDiRete && !hotspot
    }

    func avvia() {
        guard monitor == nil else { return }
        let nuovo = NWPathMonitor()
        nuovo.pathUpdateHandler = { [weak self] percorso in
            let interfacce = percorso.availableInterfaces
            let wifi = interfacce.contains { $0.type == .wifi && !$0.name.hasPrefix("awdl") && !$0.name.hasPrefix("llw") }
            let cavo = interfacce.contains { $0.type == .wiredEthernet }
            let hotspot = interfacce.contains { $0.name.hasPrefix("bridge") }
            let cellulare = interfacce.contains { $0.type == .cellular }
            Task { @MainActor in
                self?.aggiorna(wifi: wifi, cavo: cavo, hotspot: hotspot, cellulare: cellulare)
            }
        }
        nuovo.start(queue: .main)
        monitor = nuovo
    }

    private func aggiorna(wifi: Bool, cavo: Bool, hotspot: Bool, cellulare: Bool) {
        let prima = noto ? descrizione : ""
        if !noto { noto = true }
        // Si assegna solo ciò che cambia: l'interfaccia non si ridisegna per niente.
        if self.wifi != wifi { self.wifi = wifi }
        if cavoDiRete != cavo { cavoDiRete = cavo }
        if self.hotspot != hotspot { self.hotspot = hotspot }
        if self.cellulare != cellulare { self.cellulare = cellulare }
        // 1.5: nel registro solo i cambiamenti.
        let dopo = descrizione
        if dopo != prima { RegistroCollegamento.condiviso.aggiungi(String(localized: "Rete dell'iPhone: \(dopo)")) }
    }

    private var descrizione: String {
        var parti: [String] = []
        if wifi { parti.append("Wi-Fi") }
        if cavoDiRete { parti.append(String(localized: "cavo di rete")) }
        if hotspot { parti.append(String(localized: "Hotspot personale")) }
        if cellulare { parti.append(String(localized: "cellulare")) }
        return parti.isEmpty ? String(localized: "nessuna") : parti.joined(separator: ", ")
    }
}
