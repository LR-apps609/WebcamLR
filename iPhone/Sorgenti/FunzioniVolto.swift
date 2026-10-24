import CoreGraphics
import Foundation
import Observation
import WebcamLRProtocollo

/// Le funzioni che seguono il volto: inquadratura automatica (P04) e luce sul volto (P08).
/// Si cambiano dal telefono («In onda», Impostazioni) o dal computer (`comando`); le scelte restano salvate
/// sul telefono (protocollo: al ricollegamento il computer non le rimanda, le legge dal primo `stato`).
@Observable
@MainActor
final class FunzioniVolto {
    /// Chiavi di `UserDefaults`, le stesse delle Impostazioni (`SezioneAssistente`).
    enum Chiave {
        static let inquadratura = "inquadraturaAutomatica"
        static let luceVolto = "luceVolto"
    }

    private(set) var inquadratura: Bool
    private(set) var luceVolto: Bool

    /// Una scelta è cambiata (dal telefono o dal computer): la sessione manda subito uno `stato`.
    @ObservationIgnored var suCambio: (() -> Void)?

    /// Sempre nella pipeline; spento non costa nulla.
    let effettoInquadratura = InquadraturaAutomatica()

    @ObservationIgnored private weak var sessione: SessioneTelefono?
    @ObservationIgnored private var osservatoreImpostazioni: NSObjectProtocol?
    /// Tra `avvia` e `ferma`.
    @ObservationIgnored private var inFunzione = false
    /// Legge i volti dell'analisi 5 volte al secondo, solo se una funzione li usa.
    @ObservationIgnored private var compitoVolti: Task<Void, Never>?
    private static let consumatore = "assistente"

    // Luce sul volto: punto levigato, ultimo punto mandato alla fotocamera e quando.
    @ObservationIgnored private var puntoLuce: CGPoint?
    @ObservationIgnored private var puntoApplicato: CGPoint?
    @ObservationIgnored private var ultimaLuce: TimeInterval = 0
    @ObservationIgnored private var ultimoVoltoLuce: TimeInterval = 0

    init() {
        let valori = UserDefaults.standard
        let inquadraturaSalvata = valori.bool(forKey: Chiave.inquadratura)
        inquadratura = inquadraturaSalvata
        luceVolto = valori.bool(forKey: Chiave.luceVolto)
        effettoInquadratura.acceso = inquadraturaSalvata
    }

    /// Una volta, quando nasce la sessione.
    func collega(a sessione: SessioneTelefono) {
        self.sessione = sessione
        sessione.effetti.aggiungi(effettoInquadratura)
    }

    /// All'avvio della sessione: da qui le Impostazioni cambiate (anche dal foglio aperto da «In onda») valgono subito.
    func avvia() {
        guard !inFunzione else { return }
        inFunzione = true
        rileggiImpostazioni()
        aggiornaLetturaVolti()
        osservatoreImpostazioni = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rileggiImpostazioni() }
        }
    }

    /// Alla fine della sessione.
    func ferma() {
        guard inFunzione else { return }
        inFunzione = false
        if let osservatoreImpostazioni { NotificationCenter.default.removeObserver(osservatoreImpostazioni) }
        osservatoreImpostazioni = nil
        aggiornaLetturaVolti()
    }

    // MARK: - Scelte

    func impostaInquadratura(_ attiva: Bool) {
        guard attiva != inquadratura else { return }
        inquadratura = attiva
        UserDefaults.standard.set(attiva, forKey: Chiave.inquadratura)
        effettoInquadratura.acceso = attiva
        suCambio?()
    }

    func impostaLuceVolto(_ attiva: Bool) {
        guard attiva != luceVolto else { return }
        luceVolto = attiva
        UserDefaults.standard.set(attiva, forKey: Chiave.luceVolto)
        if !attiva { lasciaLuce() }
        aggiornaLetturaVolti()
        suCambio?()
    }

    // MARK: - Protocollo

    /// I campi di `comando` di queste funzioni; gli altri li applica la sessione.
    func applica(_ comando: Comando) {
        if let attiva = comando.inquadratura { impostaInquadratura(attiva) }
        if let attiva = comando.luceVolto { impostaLuceVolto(attiva) }
    }

    /// In ogni `stato` tutte le funzioni dichiarate in `capacita` (regola del protocollo).
    func completa(_ stato: inout StatoTelefono) {
        stato.inquadratura = inquadratura
        stato.luceVolto = luceVolto
    }

    func completa(_ capacita: inout Capacita) {
        capacita.inquadratura = true
        capacita.luceVolto = true
    }

    // MARK: - Interni

    private func rileggiImpostazioni() {
        let valori = UserDefaults.standard
        impostaInquadratura(valori.bool(forKey: Chiave.inquadratura))
        impostaLuceVolto(valori.bool(forKey: Chiave.luceVolto))
    }

    /// Chiede i volti all'analisi e li legge solo mentre una funzione li usa: spente, nessun costo.
    private func aggiornaLetturaVolti() {
        let serve = inFunzione && luceVolto
        guard let analisi = sessione?.effetti.analisi else { return }
        if serve {
            analisi.richiedi(.volti, per: Self.consumatore)
            guard compitoVolti == nil else { return }
            compitoVolti = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, let self else { return }
                    self.leggiVolti()
                }
            }
        } else {
            analisi.rinuncia(.volti, per: Self.consumatore)
            compitoVolti?.cancel()
            compitoVolti = nil
        }
    }

    /// L'ultimo risultato dell'analisi, se è fresco (meno di un secondo): altrimenti la fotocamera è ferma
    /// (pausa, riconfigurazione) e non si decide nulla.
    private func leggiVolti() {
        guard let sessione else { return }
        let adesso = ProcessInfo.processInfo.systemUptime
        guard let volti = sessione.effetti.analisi.ultimiVolti, adesso - volti.quando < 1 else { return }
        // Il volto principale è il più grande (il più vicino).
        let principale = volti.rettangoli.max { $0.width * $0.height < $1.width * $1.height }
        if luceVolto { seguiLuce(principale, adesso: adesso, cattura: sessione.cattura) }
    }

    // MARK: - Luce sul volto (P08)

    /// Il punto dell'esposizione segue il volto: levigato, al massimo due volte al secondo e solo se il volto si è
    /// spostato abbastanza (o ogni 3 secondi, per un obiettivo appena cambiato). Senza volto per 2 secondi si torna
    /// al centro. Esposizione manuale, AE/AF bloccati e tocco li rispetta `Cattura.esponiSulVolto`.
    private func seguiLuce(_ volto: CGRect?, adesso: TimeInterval, cattura: Cattura) {
        guard let volto else {
            if puntoApplicato != nil, adesso - ultimoVoltoLuce > 2 {
                cattura.esponiSulVolto(nil)
                puntoApplicato = nil
                puntoLuce = nil
            }
            return
        }
        ultimoVoltoLuce = adesso
        // Analisi con l'origine in basso, la fotocamera in alto.
        let centro = CGPoint(x: volto.midX, y: 1 - volto.midY)
        let levigato = puntoLuce.map { CGPoint(x: $0.x + (centro.x - $0.x) * 0.35, y: $0.y + (centro.y - $0.y) * 0.35) } ?? centro
        puntoLuce = levigato
        guard adesso - ultimaLuce >= 0.5 else { return }
        let spostato = puntoApplicato.map { hypot($0.x - levigato.x, $0.y - levigato.y) > 0.06 } ?? true
        guard spostato || adesso - ultimaLuce >= 3 else { return }
        cattura.esponiSulVolto(levigato)
        puntoApplicato = levigato
        ultimaLuce = adesso
    }

    /// Spenta: punto al centro e scelta del sistema.
    private func lasciaLuce() {
        sessione?.cattura.esponiSulVolto(nil)
        puntoLuce = nil
        puntoApplicato = nil
    }
}
