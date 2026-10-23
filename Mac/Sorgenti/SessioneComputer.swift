import Foundation
import Network
import WebcamLRProtocollo

/// Numeri mostrati sotto l'anteprima, aggiornati ogni secondo.
struct Statistiche: Equatable, Sendable {
    var larghezza = 0
    var altezza = 0
    var fps = 0
    var megabitAlSecondo = 0.0
    var latenzaMs: Int?
}

/// La connessione con un telefono, lato computer (round 1).
/// Legge i pacchetti sulla propria coda, misura la latenza e manda il video allo `Schermo`.
final class SessioneComputer: @unchecked Sendable {
    enum Evento: Sendable {
        case ciao(Ciao)
        case formato(FormatoVideo)
        case stato(StatoTelefono)
        case statistiche(Statistiche)
        /// Nessun dato da 3 secondi.
        case silenzio
        case ripresa
        case chiusa
    }

    /// Chiamata sulla coda principale.
    var suEvento: (@MainActor (Evento) -> Void)?

    private let connessione: NWConnection
    private let schermo: Schermo
    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.sessione", qos: .userInteractive)
    private var lettore = LettorePacchetti()
    private var timer: DispatchSourceTimer?
    private var chiusa = false

    // Latenza: differenza tra gli orologi dal pong più rapido tra gli ultimi 10.
    private var misure: [(andataRitorno: UInt64, scarto: Int64)] = []
    private var latenzeUltimoSecondo: [Int] = []
    private var ultimaLatenza: Int?

    private var fotogrammiUltimoSecondo = 0
    private var byteUltimoSecondo = 0
    private var formato: FormatoVideo?
    private var ultimoPacchetto = Orologio.adesso()
    private var inSilenzio = false

    init(connessione: NWConnection, schermo: Schermo) {
        self.connessione = connessione
        self.schermo = schermo
    }

    func avvia() {
        connessione.stateUpdateHandler = { [weak self] stato in
            guard let self else { return }
            switch stato {
            case .ready:
                self.ricevi()
                self.avviaTimer()
            case .failed, .cancelled:
                self.termina()
            default:
                break
            }
        }
        connessione.start(queue: coda)
    }

    func chiudi() {
        coda.async {
            guard let pacchetto = try? Pacchetto(messaggio: .arrivederci) else {
                self.connessione.cancel()
                return
            }
            // Chiude dopo aver spedito l'arrivederci: il telefono capisce che è voluto e non si ricollega.
            self.connessione.send(content: pacchetto.codificato(), completion: .contentProcessed { _ in
                self.connessione.cancel()
            })
        }
    }

    // MARK: - Ricezione

    private func ricevi() {
        connessione.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] dati, _, completo, errore in
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
        let adesso = Orologio.adesso()
        ultimoPacchetto = adesso
        if inSilenzio {
            inSilenzio = false
            notifica(.ripresa)
        }

        switch pacchetto.tipo {
        case .controllo:
            guard let messaggio = try? pacchetto.messaggio() else { return }
            gestisci(messaggio, adesso: adesso)
        case .video:
            guard let fotogramma = try? FotogrammaVideo(pacchetto: pacchetto) else { return }
            schermo.mostra(fotogramma)
            fotogrammiUltimoSecondo += 1
            byteUltimoSecondo += pacchetto.contenuto.count
            if let scarto = miglioreScarto() {
                // Istante di cattura nell'orologio del computer.
                let cattura = Int64(fotogramma.timestamp) - scarto
                let latenza = Int((Int64(adesso) - cattura) / 1000)
                if latenza >= 0 && latenza < 10_000 {
                    latenzeUltimoSecondo.append(latenza)
                }
            }
        case .audio:
            break
        }
    }

    private func gestisci(_ messaggio: Messaggio, adesso: UInt64) {
        switch messaggio {
        case .ciao(let ciao):
            let nome = Host.current().localizedName ?? "Mac"
            invia(.benvenuto(Benvenuto(nome: nome, piattaforma: .mac)))
            notifica(.ciao(ciao))
        case .pong(let pong):
            guard adesso >= pong.t else { return }
            let andataRitorno = adesso - pong.t
            let scarto = Int64(pong.telefono) - Int64(pong.t + andataRitorno / 2)
            misure.append((andataRitorno, scarto))
            if misure.count > 10 { misure.removeFirst() }
        case .formato(let formato):
            self.formato = formato
            notifica(.formato(formato))
        case .stato(let stato):
            notifica(.stato(stato))
        case .arrivederci:
            connessione.cancel()
        default:
            break
        }
    }

    private func miglioreScarto() -> Int64? {
        misure.min { $0.andataRitorno < $1.andataRitorno }?.scarto
    }

    // MARK: - Ogni secondo

    private func avviaTimer() {
        let timer = DispatchSource.makeTimerSource(queue: coda)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.ogniSecondo() }
        timer.resume()
        self.timer = timer
    }

    private func ogniSecondo() {
        let adesso = Orologio.adesso()
        invia(.ping(Ping(t: adesso)))

        if !latenzeUltimoSecondo.isEmpty {
            let ordinate = latenzeUltimoSecondo.sorted()
            ultimaLatenza = ordinate[ordinate.count / 2]
            latenzeUltimoSecondo.removeAll()
        }
        if let ultimaLatenza {
            invia(.latenza(Latenza(ms: ultimaLatenza)))
        }

        notifica(.statistiche(Statistiche(larghezza: formato?.larghezza ?? 0,
                                          altezza: formato?.altezza ?? 0,
                                          fps: fotogrammiUltimoSecondo,
                                          megabitAlSecondo: Double(byteUltimoSecondo) * 8 / 1_000_000,
                                          latenzaMs: ultimaLatenza)))
        fotogrammiUltimoSecondo = 0
        byteUltimoSecondo = 0

        let silenzio = adesso - min(ultimoPacchetto, adesso)
        if silenzio > 10_000_000 {
            connessione.cancel()
        } else if silenzio > 3_000_000 && !inSilenzio {
            inSilenzio = true
            notifica(.silenzio)
        }
    }

    // MARK: - Utilità

    private func invia(_ messaggio: Messaggio) {
        guard !chiusa, let pacchetto = try? Pacchetto(messaggio: messaggio) else { return }
        connessione.send(content: pacchetto.codificato(), completion: .contentProcessed { _ in })
    }

    private func termina() {
        guard !chiusa else { return }
        chiusa = true
        timer?.cancel()
        timer = nil
        notifica(.chiusa)
    }

    private func notifica(_ evento: Evento) {
        let destinatario = suEvento
        Task { @MainActor in destinatario?(evento) }
    }
}
