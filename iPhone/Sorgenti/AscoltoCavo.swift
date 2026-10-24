import Foundation
import Network
import Observation
import UIKit

/// Costanti del collegamento via cavo USB (Documenti/Protocollo.md, «Collegamento via cavo USB»).
enum CavoUSB {
    /// L'iPhone ascolta qui, solo su 127.0.0.1: il computer ci arriva attraverso usbmux e il cavo.
    static let porta: UInt16 = 52741
}

/// Collegamento via cavo USB (1.6), lato iPhone: mentre l'app è aperta e non c'è una sessione (dalla 1.9 anche durante
/// una sessione Wi-Fi, per passare al cavo), resta in ascolto
/// su 127.0.0.1:52741. Solo l'indirizzo locale: dalla rete non si raggiunge, solo dal cavo attraverso usbmux.
/// La connessione che arriva va a `suConnessione`, che apre la stessa sessione sicura del Wi-Fi.
@Observable
@MainActor
final class AscoltoCavo {
    /// Vero quando l'ascolto è davvero attivo (per la scheda «Via cavo USB»).
    private(set) var inAscolto = false

    /// Una connessione dal cavo, non ancora avviata: chi la riceve la avvia o la chiude.
    @ObservationIgnored var suConnessione: (@MainActor (NWConnection) -> Void)?

    @ObservationIgnored private var ascoltatore: NWListener?
    /// Chi usa l'ascolto lo vuole acceso (nessuna sessione attiva, schermata visibile…).
    @ObservationIgnored private var desiderato = false
    /// iOS può togliere l'ascolto all'app in sottofondo: si ferma lì e si riaccende al ritorno.
    @ObservationIgnored private var appAttiva = true
    @ObservationIgnored private var osservatori: [NSObjectProtocol] = []
    @ObservationIgnored private var compitoRiavvio: Task<Void, Never>?

    /// Gli osservatori si registrano al primo uso, non nell'`init`: come `@State` di una vista, l'`init` può essere
    /// chiamato più volte e le copie scartate lascerebbero osservatori registrati per sempre.
    private func osservaApp() {
        guard osservatori.isEmpty else { return }
        appAttiva = UIApplication.shared.applicationState != .background
        let centro = NotificationCenter.default
        osservatori.append(centro.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cambiaApp(attiva: false) }
        })
        osservatori.append(centro.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cambiaApp(attiva: true) }
        })
    }

    /// Acceso o spento da chi lo usa; l'ascolto parte solo se anche l'app è in primo piano.
    func imposta(attivo: Bool) {
        osservaApp()
        desiderato = attivo
        aggiorna()
    }

    private func cambiaApp(attiva: Bool) {
        appAttiva = attiva
        aggiorna()
    }

    private func aggiorna() {
        let serve = desiderato && appAttiva
        if serve && ascoltatore == nil {
            avvia()
        } else if !serve && ascoltatore != nil {
            ferma()
            RegistroCollegamento.condiviso.aggiungi("Ascolto sul cavo USB fermato")
        }
    }

    private func avvia() {
        compitoRiavvio?.cancel()
        compitoRiavvio = nil
        guard let porta = NWEndpoint.Port(rawValue: CavoUSB.porta) else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parametri = NWParameters(tls: nil, tcp: tcp)
        // Solo 127.0.0.1 e solo l'interfaccia locale: nessun altro dispositivo della rete può collegarsi.
        parametri.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: porta)
        parametri.requiredInterfaceType = .loopback
        parametri.includePeerToPeer = false
        parametri.allowLocalEndpointReuse = true

        let nuovo: NWListener
        do {
            nuovo = try NWListener(using: parametri)
        } catch {
            RegistroCollegamento.condiviso.aggiungi("Ascolto sul cavo USB non riuscito: riprovo")
            pianificaRiavvio()
            return
        }
        let identita = ObjectIdentifier(nuovo)
        nuovo.newConnectionHandler = { [weak self] connessione in
            Task { @MainActor in self?.accogli(connessione, da: identita) }
        }
        nuovo.stateUpdateHandler = { [weak self] stato in
            Task { @MainActor in self?.statoCambiato(stato, da: identita) }
        }
        ascoltatore = nuovo
        nuovo.start(queue: .main)
    }

    private func ferma() {
        compitoRiavvio?.cancel()
        compitoRiavvio = nil
        ascoltatore?.newConnectionHandler = nil
        ascoltatore?.stateUpdateHandler = nil
        ascoltatore?.cancel()
        ascoltatore = nil
        if inAscolto { inAscolto = false }
    }

    private func statoCambiato(_ stato: NWListener.State, da identita: ObjectIdentifier) {
        guard let attuale = ascoltatore, ObjectIdentifier(attuale) == identita else { return }
        switch stato {
        case .ready:
            // Se iOS non avesse usato la porta richiesta, il computer non ci troverebbe: si chiude e si riprova.
            guard attuale.port?.rawValue == CavoUSB.porta else {
                ferma()
                RegistroCollegamento.condiviso.aggiungi("Ascolto sul cavo USB su una porta sbagliata: riprovo")
                pianificaRiavvio()
                return
            }
            if !inAscolto { inAscolto = true }
            RegistroCollegamento.condiviso.aggiungi("In ascolto sul cavo USB (porta \(CavoUSB.porta))")
        case .failed, .waiting:
            // Per esempio la porta occupata o l'ascolto tolto da iOS: si riprova tra poco.
            ferma()
            RegistroCollegamento.condiviso.aggiungi("Ascolto sul cavo USB interrotto: riprovo")
            pianificaRiavvio()
        default:
            break
        }
    }

    private func pianificaRiavvio() {
        compitoRiavvio?.cancel()
        compitoRiavvio = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.compitoRiavvio = nil
            self.aggiorna()
        }
    }

    private func accogli(_ connessione: NWConnection, da identita: ObjectIdentifier) {
        // Per sicurezza, oltre ai parametri: solo connessioni da questo stesso iPhone (usbmux arriva da 127.0.0.1).
        guard let attuale = ascoltatore, ObjectIdentifier(attuale) == identita,
              Self.eLocale(connessione.endpoint), let destinatario = suConnessione else {
            connessione.cancel()
            return
        }
        RegistroCollegamento.condiviso.aggiungi("Collegamento in arrivo dal cavo USB")
        destinatario(connessione)
    }

    private static func eLocale(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let indirizzo):
            return indirizzo.isLoopback
        case .ipv6(let indirizzo):
            return indirizzo.isLoopback || indirizzo.asIPv4?.isLoopback == true
        case .name(let nome, _):
            return nome == "localhost" || nome == "127.0.0.1"
        @unknown default:
            return false
        }
    }
}
