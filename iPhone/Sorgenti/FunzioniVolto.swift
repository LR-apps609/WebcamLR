import Foundation
import Observation
import WebcamLRProtocollo

/// Le funzioni che seguono il volto: inquadratura automatica (P04).
/// Si cambiano dal telefono («In onda», Impostazioni) o dal computer (`comando`); le scelte restano salvate
/// sul telefono (protocollo: al ricollegamento il computer non le rimanda, le legge dal primo `stato`).
@Observable
@MainActor
final class FunzioniVolto {
    /// Chiavi di `UserDefaults`, le stesse delle Impostazioni (`SezioneAssistente`).
    enum Chiave {
        static let inquadratura = "inquadraturaAutomatica"
    }

    private(set) var inquadratura: Bool

    /// Una scelta è cambiata (dal telefono o dal computer): la sessione manda subito uno `stato`.
    @ObservationIgnored var suCambio: (() -> Void)?

    /// Sempre nella pipeline; spento non costa nulla.
    let effettoInquadratura = InquadraturaAutomatica()

    @ObservationIgnored private weak var sessione: SessioneTelefono?
    @ObservationIgnored private var osservatoreImpostazioni: NSObjectProtocol?

    init() {
        let valori = UserDefaults.standard
        let inquadraturaSalvata = valori.bool(forKey: Chiave.inquadratura)
        inquadratura = inquadraturaSalvata
        effettoInquadratura.acceso = inquadraturaSalvata
    }

    /// Una volta, quando nasce la sessione.
    func collega(a sessione: SessioneTelefono) {
        self.sessione = sessione
        sessione.effetti.aggiungi(effettoInquadratura)
    }

    /// All'avvio della sessione: da qui le Impostazioni cambiate (anche dal foglio aperto da «In onda») valgono subito.
    func avvia() {
        guard osservatoreImpostazioni == nil else { return }
        rileggiImpostazioni()
        osservatoreImpostazioni = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rileggiImpostazioni() }
        }
    }

    /// Alla fine della sessione.
    func ferma() {
        if let osservatoreImpostazioni { NotificationCenter.default.removeObserver(osservatoreImpostazioni) }
        osservatoreImpostazioni = nil
    }

    // MARK: - Scelte

    func impostaInquadratura(_ attiva: Bool) {
        guard attiva != inquadratura else { return }
        inquadratura = attiva
        UserDefaults.standard.set(attiva, forKey: Chiave.inquadratura)
        effettoInquadratura.acceso = attiva
        suCambio?()
    }

    // MARK: - Protocollo

    /// I campi di `comando` di queste funzioni; gli altri li applica la sessione.
    func applica(_ comando: Comando) {
        if let attiva = comando.inquadratura { impostaInquadratura(attiva) }
    }

    /// In ogni `stato` tutte le funzioni dichiarate in `capacita` (regola del protocollo).
    func completa(_ stato: inout StatoTelefono) {
        stato.inquadratura = inquadratura
    }

    func completa(_ capacita: inout Capacita) {
        capacita.inquadratura = true
    }

    // MARK: - Interni

    private func rileggiImpostazioni() {
        let valori = UserDefaults.standard
        impostaInquadratura(valori.bool(forKey: Chiave.inquadratura))
    }
}
