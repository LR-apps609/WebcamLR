import Darwin
import Foundation
import Network

/// Il canale di byte sotto una `SessioneComputer` (1.8). La sessione non sa da dove arrivano i byte:
/// - `TrasportoRete`: una NWConnection accettata dal listener (Wi-Fi, cavo di rete, Wi-Fi diretto);
/// - `TrasportoSocket`: il socket del cavo USB, già collegato all'iPhone attraverso usbmux.
///
/// Perché due: NWConnection non sa adottare un socket BSD già aperto, e con usbmux il canale verso l'iPhone
/// è proprio il socket su cui si è chiesto `Connect`. Per la rete resta NWConnection com'era, con le stesse
/// chiamate: la latenza del Wi-Fi non cambia.
///
/// Regola per tutti e due: ogni metodo si chiama sulla coda passata ad `avvia`, e lì arrivano anche le risposte.
protocol TrasportoSessione: AnyObject {
    /// Wi-Fi, cavo USB…: valido da quando `suPronto` è stato chiamato.
    var via: TipoCollegamento { get }
    /// `suPronto` quando si possono leggere e scrivere byte; `suFine` quando il canale è finito (anche più volte:
    /// la sessione lo tratta come idempotente).
    func avvia(coda: DispatchQueue, suPronto: @escaping () -> Void, suFine: @escaping () -> Void)
    /// Una lettura: i byte arrivati (al massimo `massimo`) e se il flusso è finito.
    func ricevi(massimo: Int, completamento: @escaping (Data?, Bool) -> Void)
    /// Spedisce tutti i byte; `poi` quando sono partiti (per chiudere dopo l'arrivederci).
    func invia(_ dati: Data, poi: (() -> Void)?)
    /// Chiude il canale; `suFine` arriva poco dopo.
    func annulla()
}

// MARK: - Rete

/// Una NWConnection, esattamente come prima della 1.8.
final class TrasportoRete: TrasportoSessione, @unchecked Sendable {
    private let connessione: NWConnection
    private(set) var via: TipoCollegamento = .wifi

    init(_ connessione: NWConnection) {
        self.connessione = connessione
    }

    func avvia(coda: DispatchQueue, suPronto: @escaping () -> Void, suFine: @escaping () -> Void) {
        connessione.stateUpdateHandler = { [weak self] stato in
            guard let self else { return }
            switch stato {
            case .ready:
                self.via = TipoCollegamento(percorso: self.connessione.currentPath)
                suPronto()
            case .failed, .cancelled:
                suFine()
            default:
                break
            }
        }
        connessione.start(queue: coda)
    }

    func ricevi(massimo: Int, completamento: @escaping (Data?, Bool) -> Void) {
        connessione.receive(minimumIncompleteLength: 1, maximumLength: massimo) { dati, _, completo, errore in
            completamento(dati, completo || errore != nil)
        }
    }

    func invia(_ dati: Data, poi: (() -> Void)?) {
        connessione.send(content: dati, completion: .contentProcessed { _ in poi?() })
    }

    func annulla() {
        connessione.cancel()
    }
}

// MARK: - Socket del cavo USB

/// Un socket BSD già collegato (il canale usbmux verso la porta 52741 dell'iPhone), letto con una
/// DispatchSource sulla coda della sessione. Il socket resta bloccante: si legge solo quando la sorgente dice
/// che ci sono byte (quindi `recv` torna subito con quelli che ci sono), e si scrive con un ciclo che spedisce
/// tutto. Dal Mac partono solo pochi messaggi piccoli (ping, latenza, comandi): la scrittura non pesa sulla coda;
/// `SO_SNDTIMEO` evita che un telefono bloccato la fermi per sempre.
final class TrasportoSocket: TrasportoSessione, @unchecked Sendable {
    let via: TipoCollegamento = .cavoUSB

    private let descrittore: Int32
    private var coda: DispatchQueue?
    private var sorgente: DispatchSourceRead?
    /// Una DispatchSource sospesa non si può rilasciare né cancellare senza riprenderla: lo si ricorda qui.
    private var sospesa = false
    private var inAttesa: ((Data?, Bool) -> Void)?
    private var buffer = [UInt8]()
    private var finito = false
    private var suFine: (() -> Void)?

    /// Il socket passa a questo oggetto, che lo chiude alla fine.
    init(descrittore: Int32) {
        self.descrittore = descrittore
    }

    func avvia(coda: DispatchQueue, suPronto: @escaping () -> Void, suFine: @escaping () -> Void) {
        self.coda = coda
        self.suFine = suFine
        var uno: Int32 = 1
        setsockopt(descrittore, SOL_SOCKET, SO_NOSIGPIPE, &uno, socklen_t(MemoryLayout<Int32>.size))
        var attesa = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descrittore, SOL_SOCKET, SO_SNDTIMEO, &attesa, socklen_t(MemoryLayout<timeval>.size))
        // Già collegato: pronto subito, ma sempre dalla coda, come NWConnection.
        coda.async { suPronto() }
    }

    func ricevi(massimo: Int, completamento: @escaping (Data?, Bool) -> Void) {
        guard !finito, let coda else { return }
        inAttesa = completamento
        if buffer.count != massimo { buffer = [UInt8](repeating: 0, count: massimo) }
        if let sorgente {
            if sospesa {
                sospesa = false
                sorgente.resume()
            }
            return
        }
        let descrittore = self.descrittore
        let nuova = DispatchSource.makeReadSource(fileDescriptor: descrittore, queue: coda)
        nuova.setEventHandler { [weak self] in self?.leggibile() }
        nuova.setCancelHandler { close(descrittore) }
        sorgente = nuova
        nuova.resume()
    }

    private func leggibile() {
        guard !finito else { return }
        guard let completamento = inAttesa else {
            // Nessuno sta leggendo: si sospende, altrimenti la sorgente scatterebbe di continuo.
            if !sospesa {
                sospesa = true
                sorgente?.suspend()
            }
            return
        }
        let descrittore = self.descrittore
        let letti = buffer.withUnsafeMutableBytes { recv(descrittore, $0.baseAddress, $0.count, 0) }
        if letti > 0 {
            inAttesa = nil
            completamento(Data(buffer[0..<letti]), false)
        } else if letti < 0, errno == EAGAIN || errno == EINTR {
            return
        } else {
            // 0 = l'iPhone ha chiuso (o il cavo è stato staccato); negativo = errore.
            inAttesa = nil
            completamento(nil, true)
        }
    }

    func invia(_ dati: Data, poi: (() -> Void)?) {
        guard !finito else { return }
        let descrittore = self.descrittore
        let riuscito = dati.withUnsafeBytes { grezzi -> Bool in
            guard let base = grezzi.baseAddress else { return true }
            var inviati = 0
            while inviati < grezzi.count {
                let n = send(descrittore, base + inviati, grezzi.count - inviati, 0)
                if n > 0 {
                    inviati += n
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
        guard riuscito else {
            annulla()
            return
        }
        poi?()
    }

    func annulla() {
        guard !finito else { return }
        finito = true
        inAttesa = nil
        if let sorgente {
            // Prima si riprende (se sospesa), poi si cancella: il gestore di cancellazione chiude il socket.
            if sospesa {
                sospesa = false
                sorgente.resume()
            }
            sorgente.cancel()
        } else {
            close(descrittore)
        }
        let fine = suFine
        suFine = nil
        if let coda {
            coda.async { fine?() }
        } else {
            fine?()
        }
    }

    deinit {
        // Se la sessione sparisce senza chiudere, il socket non resta aperto.
        if !finito {
            if let sorgente {
                if sospesa { sorgente.resume() }
                sorgente.cancel()
            } else {
                close(descrittore)
            }
        }
    }
}
