import Darwin
import Foundation

/// usbmux scritto da zero (1.8), come descritto in Documenti/Protocollo.md, «Collegamento via cavo USB».
/// Le librerie esistenti (libimobiledevice, usbmuxd) sono LGPL o GPL: qui solo codice nostro e di sistema.
///
/// Ogni messaggio: intestazione di 16 byte in little-endian (lunghezza totale, versione 1, tipo 8 = plist,
/// etichetta), poi un plist XML. Dopo un `Connect` riuscito lo stesso socket diventa il canale verso l'iPhone.
///
/// Tutto con socket BSD bloccanti, sempre fuori dalla coda principale: le chiamate sono poche e piccole.
enum Usbmux {
    /// Il socket Unix del servizio di Apple (in realtà /private/var/run/usbmuxd: vedi l'eccezione in base.yml).
    static let percorso = "/var/run/usbmuxd"
    /// La porta su cui l'app dell'iPhone ascolta, solo su 127.0.0.1 (raggiungibile solo dal cavo).
    static let portaTelefono: UInt16 = 52741

    private static let versione: UInt32 = 1
    private static let tipoPlist: UInt32 = 8
    /// Oltre questa dimensione un messaggio di usbmux non è credibile: si chiude.
    private static let lunghezzaMassima = 1 << 20

    /// I campi comuni a ogni richiesta.
    static func richiesta(_ tipo: String) -> [String: Any] {
        [
            "MessageType": tipo,
            "ClientVersionString": "WebcamLR",
            "ProgName": "WebcamLR",
            "kLibUSBMuxVersion": 3
        ]
    }

    /// Intestazione di 16 byte in little-endian più il plist XML.
    static func codifica(_ contenuto: [String: Any], etichetta: UInt32) -> Data? {
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: contenuto, format: .xml, options: 0) else {
            return nil
        }
        var dati = Data(capacity: 16 + plist.count)
        for valore in [UInt32(16 + plist.count), versione, tipoPlist, etichetta] {
            withUnsafeBytes(of: valore.littleEndian) { dati.append(contentsOf: $0) }
        }
        dati.append(plist)
        return dati
    }

    /// Un socket collegato a usbmuxd, oppure nil (servizio assente o bloccato dal sandbox).
    static func apri() -> Int32? {
        let descrittore = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descrittore >= 0 else { return nil }
        var indirizzo = sockaddr_un()
        indirizzo.sun_family = sa_family_t(AF_UNIX)
        let byte = Array(percorso.utf8)
        let entra = withUnsafeMutableBytes(of: &indirizzo.sun_path) { spazio -> Bool in
            // Resta almeno uno zero finale: sockaddr_un() parte tutto a zero.
            guard byte.count < spazio.count else { return false }
            spazio.copyBytes(from: byte)
            return true
        }
        let lunghezza = socklen_t(MemoryLayout<sockaddr_un>.size)
        indirizzo.sun_len = UInt8(lunghezza)
        guard entra else {
            close(descrittore)
            return nil
        }
        let esito = withUnsafePointer(to: &indirizzo) { puntatore in
            puntatore.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descrittore, $0, lunghezza) }
        }
        guard esito == 0 else {
            close(descrittore)
            return nil
        }
        // Se l'altro lato chiude mentre si scrive: un errore, non il segnale SIGPIPE che chiuderebbe l'app.
        var uno: Int32 = 1
        setsockopt(descrittore, SOL_SOCKET, SO_NOSIGPIPE, &uno, socklen_t(MemoryLayout<Int32>.size))
        return descrittore
    }

    static func scrivi(_ dati: Data, su descrittore: Int32) -> Bool {
        dati.withUnsafeBytes { grezzi -> Bool in
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
    }

    /// Esattamente `quanti` byte, oppure nil se il socket si chiude, scade o sbaglia.
    static func leggi(_ quanti: Int, da descrittore: Int32) -> [UInt8]? {
        guard quanti > 0 else { return [] }
        var byte = [UInt8](repeating: 0, count: quanti)
        var letti = 0
        while letti < quanti {
            let giaLetti = letti
            let n = byte.withUnsafeMutableBytes { spazio -> Int in
                guard let base = spazio.baseAddress else { return -1 }
                return recv(descrittore, base + giaLetti, quanti - giaLetti, 0)
            }
            if n > 0 {
                letti += n
            } else if n < 0, errno == EINTR {
                continue
            } else {
                return nil
            }
        }
        return byte
    }

    /// Un messaggio intero; legge solo i suoi byte, così dopo un `Connect` nulla del canale va perso.
    static func leggiMessaggio(da descrittore: Int32) -> [String: Any]? {
        guard let intestazione = leggi(16, da: descrittore) else { return nil }
        let lunghezza = Int(intestazione[0]) | Int(intestazione[1]) << 8 | Int(intestazione[2]) << 16 | Int(intestazione[3]) << 24
        guard lunghezza >= 16, lunghezza <= lunghezzaMassima,
              let corpo = leggi(lunghezza - 16, da: descrittore) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: Data(corpo), options: [], format: nil)
        return plist as? [String: Any]
    }

    /// `Connect` verso la porta dell'iPhone su un socket nuovo. Se la risposta è `Result` con `Number` 0,
    /// il socket è il canale TCP verso l'app dell'iPhone; altrimenti (app chiusa, iPhone bloccato o non
    /// autorizzato) nil.
    static func collega(dispositivo: Int, porta: UInt16, etichetta: UInt32) -> Int32? {
        guard let descrittore = apri() else { return nil }
        // La risposta arriva subito; 5 secondi bastano anche con un iPhone lento.
        var attesa = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descrittore, SOL_SOCKET, SO_RCVTIMEO, &attesa, socklen_t(MemoryLayout<timeval>.size))
        var contenuto = richiesta("Connect")
        contenuto["DeviceID"] = dispositivo
        // In ordine di rete: 52741 (0xCE05) diventa 0x05CE = 1486. `bigEndian` sul Mac (little-endian) scambia i byte.
        contenuto["PortNumber"] = Int(porta.bigEndian)
        guard let dati = codifica(contenuto, etichetta: etichetta), scrivi(dati, su: descrittore),
              let risposta = leggiMessaggio(da: descrittore),
              (risposta["MessageType"] as? String) == "Result",
              (risposta["Number"] as? Int) == 0 else {
            close(descrittore)
            return nil
        }
        // Da qui il socket è il canale: niente più scadenza in lettura (le letture le guida la DispatchSource).
        var nessuna = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(descrittore, SOL_SOCKET, SO_RCVTIMEO, &nessuna, socklen_t(MemoryLayout<timeval>.size))
        return descrittore
    }
}

/// Il cavo USB sul Mac (1.8): tiene una connessione `Listen` con usbmuxd, e per ogni iPhone collegato via USB
/// prova `Connect` verso la porta 52741 ogni 2 secondi, finché l'app sull'iPhone risponde. Il socket riuscito
/// va al Ricevitore, che ne fa una sessione come quelle della rete (stretta di mano, fiducia, candidati).
@MainActor
final class ClienteUSB {
    enum Stato: Equatable {
        /// Nessun iPhone sul cavo.
        case nessunIPhone
        /// usbmuxd non si raggiunge: di solito il sandbox, senza l'eccezione per /private/var/run/usbmuxd.
        case servizioAssente
        /// Un iPhone è collegato con il cavo, ma WebcamLR sull'iPhone non risponde (chiusa, o iPhone da sbloccare).
        case inAttesaApp
        /// Collegamento via cavo sospeso: dopo «Scollega» sul Mac o un telefono non consentito.
        case inPausa
        /// Una sessione via cavo è aperta.
        case collegato
    }

    /// Chi ha aperto una sessione via cavo, per dire al client quando finisce.
    struct Canale: Equatable {
        let dispositivo: Int
        fileprivate let generazione: Int
    }

    /// Ogni quanto si riprova `Connect` mentre l'iPhone è collegato ma l'app non ascolta.
    static let intervallo: Duration = .seconds(2)

    var suStato: ((Stato) -> Void)?
    /// Un canale pronto: il socket (che passa a chi lo riceve) e da dove viene.
    var suCanale: ((Int32, Canale) -> Void)?
    /// Una riga per il registro del collegamento.
    var suRegistro: ((String) -> Void)?

    private(set) var stato: Stato = .nessunIPhone

    private struct Dispositivo {
        let generazione: Int
        var tentativoInCorso = false
        var sessioneAperta = false
        var inPausa = false
        var riprovaInAttesa = false
        var tentativiFalliti = 0
        /// La connessione `Listen` è ricominciata mentre questa sessione era aperta: se usbmuxd non rimanda
        /// l'iPhone con `Attached`, alla fine della sessione lo si dimentica invece di riprovare per sempre.
        var orfano = false
    }

    private enum EventoAscolto: Sendable {
        case servizio(raggiungibile: Bool)
        case attaccato(Int)
        case staccato(Int)
        /// La connessione con usbmuxd è caduta: si riparte da zero (usbmuxd rimanda gli iPhone collegati).
        case ricomincia
    }

    private var dispositivi: [Int: Dispositivo] = [:]
    private var servizioRaggiungibile = true
    private var avviato = false
    private var prossimaGenerazione = 1
    private var prossimaEtichetta: UInt32 = 10

    /// Da chiamare una volta: le chiamate successive non fanno nulla.
    func avvia() {
        guard !avviato else { return }
        avviato = true
        let avvisa: @Sendable (EventoAscolto) -> Void = { [weak self] evento in
            // La coda principale è in ordine (FIFO): «collegato» e «staccato» non si scambiano.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.gestisci(evento)
                }
            }
        }
        let filo = Thread { Self.ascolta(avvisa: avvisa) }
        filo.name = "it.lrapps.webcamlr.usbmux"
        filo.qualityOfService = .utility
        filo.start()
    }

    /// Dopo «Scollega» o un telefono non consentito, il cavo resta fermo finché l'iPhone non viene staccato
    /// e ricollegato, o finché l'utente non sceglie «Collega via cavo».
    func riprendi() {
        for (id, var dispositivo) in dispositivi where dispositivo.inPausa {
            dispositivo.inPausa = false
            dispositivo.tentativiFalliti = 0
            dispositivi[id] = dispositivo
            prova(id)
        }
        aggiornaStato()
    }

    /// La sessione aperta su quel canale è finita. `pausa`: non riprovare da soli (vedi `riprendi`).
    func sessioneFinita(_ canale: Canale, pausa: Bool) {
        guard var dispositivo = dispositivi[canale.dispositivo], dispositivo.generazione == canale.generazione else { return }
        if dispositivo.orfano {
            // Non più segnalato da usbmuxd: probabilmente staccato mentre `Listen` ricominciava.
            dispositivi.removeValue(forKey: canale.dispositivo)
            aggiornaStato()
            return
        }
        dispositivo.sessioneAperta = false
        dispositivo.tentativiFalliti = 0
        if pausa { dispositivo.inPausa = true }
        dispositivi[canale.dispositivo] = dispositivo
        if pausa {
            suRegistro?("Cavo USB in pausa: «Collega via cavo» o ricollega il cavo per riprendere")
        } else {
            // L'app sull'iPhone è andata in secondo piano o si è chiusa: si riprova finché torna.
            riprovaTra(canale.dispositivo)
        }
        aggiornaStato()
    }

    // MARK: - Eventi da usbmuxd

    private func gestisci(_ evento: EventoAscolto) {
        switch evento {
        case .servizio(let raggiungibile):
            if raggiungibile != servizioRaggiungibile {
                suRegistro?(raggiungibile ? "Servizio del cavo USB raggiunto"
                                          : "Servizio del cavo USB non raggiungibile: il cavo non si può usare")
            }
            servizioRaggiungibile = raggiungibile
        case .attaccato(let id):
            // Già noto (dopo un nuovo `Listen` usbmuxd rimanda gli iPhone collegati): non si ricomincia,
            // altrimenti si aprirebbe un secondo canale accanto alla sessione ancora aperta.
            if var noto = dispositivi[id] {
                noto.orfano = false
                dispositivi[id] = noto
                prova(id)
                break
            }
            dispositivi[id] = Dispositivo(generazione: prossimaGenerazione)
            prossimaGenerazione += 1
            suRegistro?("iPhone collegato con il cavo USB")
            prova(id)
        case .staccato(let id):
            // La sessione su quel cavo si chiude da sola: usbmuxd chiude il socket.
            if dispositivi.removeValue(forKey: id) != nil {
                suRegistro?("iPhone staccato dal cavo USB")
            }
        case .ricomincia:
            // Le sessioni aperte restano (se usbmuxd è ripartito, si chiudono da sole); il resto si dimentica.
            dispositivi = dispositivi.filter { $0.value.sessioneAperta }.mapValues { dispositivo in
                var orfano = dispositivo
                orfano.orfano = true
                return orfano
            }
        }
        aggiornaStato()
    }

    // MARK: - Connect

    private func prova(_ id: Int) {
        guard var dispositivo = dispositivi[id], !dispositivo.tentativoInCorso,
              !dispositivo.sessioneAperta, !dispositivo.inPausa else { return }
        dispositivo.tentativoInCorso = true
        dispositivi[id] = dispositivo
        let generazione = dispositivo.generazione
        let etichetta = prossimaEtichetta
        prossimaEtichetta &+= 1
        let porta = Usbmux.portaTelefono
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let descrittore = Usbmux.collega(dispositivo: id, porta: porta, etichetta: etichetta)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else {
                        if let descrittore { close(descrittore) }
                        return
                    }
                    self.esito(id, generazione: generazione, descrittore: descrittore)
                }
            }
        }
    }

    private func esito(_ id: Int, generazione: Int, descrittore: Int32?) {
        guard var dispositivo = dispositivi[id], dispositivo.generazione == generazione else {
            // Staccato (o ricollegato) nel frattempo.
            if let descrittore { close(descrittore) }
            return
        }
        dispositivo.tentativoInCorso = false
        if let descrittore {
            guard !dispositivo.inPausa else {
                close(descrittore)
                dispositivi[id] = dispositivo
                aggiornaStato()
                return
            }
            dispositivo.sessioneAperta = true
            dispositivo.tentativiFalliti = 0
            dispositivi[id] = dispositivo
            aggiornaStato()
            suRegistro?("Canale aperto sul cavo USB: aspetto WebcamLR sull'iPhone")
            suCanale?(descrittore, Canale(dispositivo: id, generazione: generazione))
        } else {
            dispositivo.tentativiFalliti += 1
            dispositivi[id] = dispositivo
            // Una riga sola, non una ogni 2 secondi.
            if dispositivo.tentativiFalliti == 1 {
                suRegistro?("iPhone sul cavo: WebcamLR non risponde, riprovo ogni 2 secondi")
            }
            riprovaTra(id)
            aggiornaStato()
        }
    }

    /// Un solo tentativo in attesa per iPhone, anche se più eventi chiedono di riprovare.
    private func riprovaTra(_ id: Int) {
        guard var dispositivo = dispositivi[id], !dispositivo.riprovaInAttesa else { return }
        dispositivo.riprovaInAttesa = true
        dispositivi[id] = dispositivo
        let generazione = dispositivo.generazione
        Task { [weak self] in
            try? await Task.sleep(for: Self.intervallo)
            guard let self, var attuale = self.dispositivi[id], attuale.generazione == generazione else { return }
            attuale.riprovaInAttesa = false
            self.dispositivi[id] = attuale
            self.prova(id)
        }
    }

    private func aggiornaStato() {
        let tutti = dispositivi.values
        let nuovo: Stato
        if tutti.contains(where: \.sessioneAperta) {
            nuovo = .collegato
        } else if tutti.contains(where: \.inPausa) {
            nuovo = .inPausa
        } else if tutti.contains(where: { $0.tentativiFalliti > 0 }) {
            nuovo = .inAttesaApp
        } else if !servizioRaggiungibile {
            nuovo = .servizioAssente
        } else {
            // Anche un iPhone appena collegato, con il primo tentativo in corso: tra un attimo si saprà.
            nuovo = .nessunIPhone
        }
        guard nuovo != stato else { return }
        stato = nuovo
        suStato?(nuovo)
    }

    // MARK: - Listen, su un filo suo

    /// Per sempre: apre la connessione con usbmuxd, chiede `Listen` e legge gli avvisi.
    /// Se usbmuxd non c'è o cade, riprova dopo qualche secondo.
    nonisolated private static func ascolta(avvisa: @escaping @Sendable (EventoAscolto) -> Void) {
        while true {
            guard let descrittore = Usbmux.apri() else {
                avvisa(.servizio(raggiungibile: false))
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            guard let richiesta = Usbmux.codifica(Usbmux.richiesta("Listen"), etichetta: 1),
                  Usbmux.scrivi(richiesta, su: descrittore) else {
                close(descrittore)
                avvisa(.servizio(raggiungibile: false))
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            avvisa(.servizio(raggiungibile: true))
            lettura: while let messaggio = Usbmux.leggiMessaggio(da: descrittore) {
                switch messaggio["MessageType"] as? String {
                case "Result":
                    // La risposta a Listen: diverso da 0 = rifiutato, si riprova da capo.
                    if let numero = messaggio["Number"] as? Int, numero != 0 { break lettura }
                case "Attached":
                    // Solo i collegamenti via cavo: usbmuxd segnala anche gli iPhone in Wi-Fi (sincronizzazione).
                    guard let id = messaggio["DeviceID"] as? Int,
                          let proprieta = messaggio["Properties"] as? [String: Any],
                          (proprieta["ConnectionType"] as? String) == "USB" else { continue }
                    avvisa(.attaccato(id))
                case "Detached":
                    if let id = messaggio["DeviceID"] as? Int { avvisa(.staccato(id)) }
                default:
                    break
                }
            }
            close(descrittore)
            avvisa(.ricomincia)
            Thread.sleep(forTimeInterval: 2)
        }
    }
}
