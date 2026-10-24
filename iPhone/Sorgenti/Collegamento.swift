import Foundation
import Network
import WebcamLRProtocollo

/// La connessione TCP con il computer: legge e scrive pacchetti sulla propria coda.
/// Ai `ping` risponde da sola, senza passare dall'interfaccia, per misurare la latenza vera.
final class Collegamento: @unchecked Sendable {
    enum Evento: Sendable {
        case pronto
        case messaggio(Messaggio)
        /// `dalComputer`: il computer ha chiuso di proposito («Scollega»): non si riprova da soli.
        case chiuso(errore: String?, dalComputer: Bool)
    }

    /// Chiamata sulla coda principale.
    var suEvento: (@MainActor (Evento) -> Void)?
    /// Chiamata quando un fotogramma è stato scartato: serve un fotogramma chiave.
    var suPerdita: (() -> Void)?
    /// Una volta al secondo, sulla coda del collegamento: fotogrammi scartati e se la rete era satura
    /// (quasi sempre fotogrammi in attesa). Serve alla qualità che segue la rete (round 2).
    var suSecondo: ((_ scartati: Int, _ saturo: Bool) -> Void)?

    private let connessione: NWConnection
    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.collegamento", qos: .userInteractive)
    private var lettore = LettorePacchetti()
    private var videoInVolo = 0
    /// Si parte da un fotogramma chiave: dopo una riconnessione il codificatore può avere ancora fotogrammi intermedi.
    private var attendiChiave = true
    private var chiuso = false
    private var congedato = false
    private var pronto = false
    private var scartatiNelSecondo = 0
    private var inviatiNelSecondo = 0
    private var pieniNelSecondo = 0
    private var orologio: DispatchSourceTimer?

    /// Oltre questo tempo senza collegamento si rinuncia e si riprova (per esempio se Bonjour non risolve).
    private static let attesaMassima: DispatchTimeInterval = .seconds(8)

    /// Oltre questo numero di fotogrammi non ancora spediti, la rete è troppo lenta e si scarta.
    private static let massimoInVolo = 3

    init(verso endpoint: NWEndpoint) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parametri = NWParameters(tls: nil, tcp: tcp)
        // Video in tempo reale: il Wi-Fi gli dà la priorità (round 2).
        parametri.serviceClass = .interactiveVideo
        connessione = NWConnection(to: endpoint, using: parametri)
    }

    deinit {
        orologio?.cancel()
    }

    func avvia() {
        connessione.stateUpdateHandler = { [weak self] stato in
            guard let self else { return }
            switch stato {
            case .ready:
                self.pronto = true
                self.avviaOrologio()
                self.notifica(.pronto)
                self.ricevi()
            case .failed(let errore):
                self.termina(errore.localizedDescription)
            case .waiting(let errore):
                self.termina(errore.localizedDescription)
            case .cancelled:
                self.termina(nil)
            default:
                break
            }
        }
        connessione.start(queue: coda)
        coda.asyncAfter(deadline: .now() + Self.attesaMassima) { [weak self] in
            guard let self, !self.pronto, !self.chiuso else { return }
            self.termina("Il computer non risponde.")
        }
    }

    func chiudi() {
        coda.async {
            guard !self.chiuso else { return }
            guard let pacchetto = try? Pacchetto(messaggio: .arrivederci) else {
                self.connessione.cancel()
                return
            }
            // Chiude dopo aver spedito l'arrivederci, così il computer sa che è voluto.
            self.connessione.send(content: pacchetto.codificato(), completion: .contentProcessed { _ in
                self.connessione.cancel()
            })
        }
    }

    func invia(_ messaggio: Messaggio) {
        guard let pacchetto = try? Pacchetto(messaggio: messaggio) else { return }
        coda.async { self.spedisci(pacchetto) }
    }

    /// Spedisce un fotogramma, oppure lo scarta se la rete non sta al passo.
    /// Dopo uno scarto aspetta il prossimo fotogramma chiave, altrimenti il video si rovina.
    func inviaVideo(_ fotogramma: FotogrammaVideo) {
        coda.async {
            guard !self.chiuso else { return }
            if self.attendiChiave && !fotogramma.chiave { return }
            if self.videoInVolo >= Self.massimoInVolo && !fotogramma.chiave {
                self.attendiChiave = true
                self.scartatiNelSecondo += 1
                self.suPerdita?()
                return
            }
            self.attendiChiave = false
            self.inviatiNelSecondo += 1
            if self.videoInVolo >= Self.massimoInVolo - 1 { self.pieniNelSecondo += 1 }
            self.videoInVolo += 1
            self.connessione.send(content: fotogramma.pacchetto.codificato(), completion: .contentProcessed { [weak self] _ in
                self?.videoInVolo -= 1
            })
        }
    }

    /// Il bilancio di ogni secondo di invio, sulla coda del collegamento.
    private func avviaOrologio() {
        let nuovo = DispatchSource.makeTimerSource(queue: coda)
        nuovo.schedule(deadline: .now() + 1, repeating: 1.0)
        nuovo.setEventHandler { [weak self] in
            self?.chiudiSecondo()
        }
        nuovo.resume()
        orologio = nuovo
    }

    private func chiudiSecondo() {
        guard !chiuso else { return }
        // Satura: più di metà dei fotogrammi è partita con la coda quasi piena.
        let saturo = inviatiNelSecondo > 0 && pieniNelSecondo * 2 > inviatiNelSecondo
        suSecondo?(scartatiNelSecondo, saturo)
        scartatiNelSecondo = 0
        inviatiNelSecondo = 0
        pieniNelSecondo = 0
    }

    private func spedisci(_ pacchetto: Pacchetto) {
        guard !chiuso else { return }
        connessione.send(content: pacchetto.codificato(), completion: .contentProcessed { _ in })
    }

    private func ricevi() {
        connessione.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] dati, _, completo, errore in
            guard let self else { return }
            if let dati, !dati.isEmpty {
                self.lettore.aggiungi(dati)
                do {
                    while let pacchetto = try self.lettore.prossimo() {
                        self.gestisci(pacchetto)
                    }
                } catch {
                    self.connessione.cancel()
                    return
                }
            }
            if completo || errore != nil {
                self.connessione.cancel()
            } else {
                self.ricevi()
            }
        }
    }

    private func gestisci(_ pacchetto: Pacchetto) {
        guard pacchetto.tipo == .controllo, let messaggio = try? pacchetto.messaggio() else { return }
        switch messaggio {
        case .ping(let ping):
            spedisciMessaggio(.pong(Pong(t: ping.t, telefono: Orologio.adesso())))
        case .arrivederci:
            congedato = true
            connessione.cancel()
        case .sconosciuto:
            break
        default:
            notifica(.messaggio(messaggio))
        }
    }

    private func spedisciMessaggio(_ messaggio: Messaggio) {
        if let pacchetto = try? Pacchetto(messaggio: messaggio) {
            spedisci(pacchetto)
        }
    }

    private func termina(_ errore: String?) {
        guard !chiuso else { return }
        chiuso = true
        orologio?.cancel()
        orologio = nil
        connessione.cancel()
        notifica(.chiuso(errore: errore, dalComputer: congedato))
    }

    private func notifica(_ evento: Evento) {
        let destinatario = suEvento
        Task { @MainActor in destinatario?(evento) }
    }
}
