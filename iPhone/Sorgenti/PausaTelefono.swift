import CoreMotion
import Foundation
import Observation
import UIKit
import WebcamLRProtocollo

/// Le pause del video senza chiudere la sessione (protocollo, *Pausa intelligente*).
///
/// - P07 `faccia-in-giu`: l'iPhone appoggiato con lo schermo in giù (gravità z oltre 0,9 per più di un secondo)
///   mette in pausa; girato di nuovo (z sotto 0,7) riprende. La fotocamera resta accesa: la ripresa è immediata.
///   Si può spegnere nelle Impostazioni.
/// - `nessuna-app` (Qualità 18, pausa automatica): **decide il computer** con il messaggio `pausa-automatica`, perché
///   solo lui sa se un'app usa la webcam virtuale e se qualcuno guarda la sua finestra (Protocollo.md, «Pausa
///   automatica»). Con `attiva` vero la fotocamera si spegne del tutto (batteria e calore) e non si codifica nulla;
///   il collegamento resta vivo (`ping`, `stato`). Con falso, o con `in-onda` vero, si riaccende subito e il video
///   riparte da un fotogramma chiave. Il telefono non decide più da solo con `anteprima` e `in-onda` (la vecchia P10,
///   spenta il 27 ottobre: con l'Apple ID gratuito sul Mac nessuna app risultava mai in uso e il telefono si fermava
///   sempre). Un computer vecchio non manda `pausa-automatica`: il telefono non va mai in pausa per questo motivo.
/// - `sottofondo` (1.0 beta 2): WebcamLR non è più in primo piano (un'altra app, la schermata Home, lo schermo
///   bloccato). La sessione lo manda appena l'app passa in sottofondo, prima che iOS la sospenda; al ritorno riprende.
/// - `fotocamera-interrotta` (1.0 beta 2): iOS ha tolto la fotocamera all'app (chiamata, un'altra app che la usa,
///   telefono troppo caldo). La causa (`CausaInterruzione`) serve solo ai testi del telefono; al computer va il motivo.
///
/// Decide solo il motivo: cosa fermare e come riprendere lo fa `SessioneTelefono` (`pausaCambiata`).
@Observable
@MainActor
final class GestorePausa {
    enum Chiave {
        static let facciaInGiu = "pausaFacciaInGiu"
    }

    /// L'iPhone è a faccia in giù da più di un secondo.
    private(set) var facciaInGiu = false
    /// Pausa automatica chiesta dal computer: nessuna app usa la webcam e nessuno guarda il video.
    private(set) var nessunaApp = false
    /// Pausa chiesta con il pulsante «Pausa» di «In onda» (`utente` nel protocollo): resta finché non si riprende.
    private(set) var utente = false
    /// WebcamLR non è in primo piano: la fotocamera è ferma per forza.
    private(set) var sottofondo = false
    /// iOS ha tolto la fotocamera all'app, e perché; `nil` se la fotocamera è disponibile.
    private(set) var interruzione: CausaInterruzione?

    /// Il motivo da mandare in `stato.pausa` (`MotiviPausa`), `nil` se il video va. Se ne valgono più d'uno si dice
    /// prima ciò che l'utente non può togliere da qui: il sottofondo (il computer tollera il silenzio solo con questo
    /// motivo), poi la fotocamera tolta da iOS; poi «faccia in giù» e la pausa chiesta col pulsante, i gesti scelti
    /// dall'utente.
    var motivo: String? {
        if sottofondo { return MotiviPausa.sottofondo }
        if interruzione != nil { return MotiviPausa.fotocameraInterrotta }
        if facciaInGiu { return MotiviPausa.facciaInGiu }
        if utente { return MotiviPausa.utente }
        if nessunaApp { return MotiviPausa.nessunaApp }
        return nil
    }

    /// Pausa automatica: la fotocamera va spenta, non solo il video fermato.
    var fotocameraSpenta: Bool { nessunaApp }

    /// Il motivo è cambiato: la sessione ferma o riprende il video.
    @ObservationIgnored var suCambio: (() -> Void)?

    @ObservationIgnored private var inFunzione = false
    @ObservationIgnored private var movimento: CMMotionManager?
    @ObservationIgnored private var giuDa: TimeInterval?
    @ObservationIgnored private var osservatoreImpostazioni: NSObjectProtocol?

    /// Un'app usa la webcam con questo telefono (`in-onda` dal computer, in questo collegamento).
    @ObservationIgnored private var appInOnda = false

    /// Di serie accesa.
    static var facciaInGiuAbilitata: Bool {
        UserDefaults.standard.object(forKey: Chiave.facciaInGiu) as? Bool ?? true
    }

    /// All'avvio della sessione.
    func avvia() {
        guard !inFunzione else { return }
        inFunzione = true
        aggiornaMovimento()
        osservatoreImpostazioni = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.aggiornaMovimento() }
        }
    }

    /// Alla fine della sessione: niente più sensori né richiami.
    func ferma() {
        guard inFunzione else { return }
        inFunzione = false
        if let osservatoreImpostazioni { NotificationCenter.default.removeObserver(osservatoreImpostazioni) }
        osservatoreImpostazioni = nil
        // In silenzio: la sessione si sta chiudendo, non c'è nulla da riprendere.
        facciaInGiu = false
        utente = false
        sottofondo = false
        interruzione = nil
        nuovoCollegamento()
        aggiornaMovimento()
    }

    // MARK: - Pausa chiesta dall'utente

    /// Il pulsante «Pausa» di «In onda»: il video si ferma, il collegamento resta aperto (come a faccia in giù).
    func impostaPausaUtente(_ attiva: Bool) {
        guard inFunzione, attiva != utente else { return }
        utente = attiva
        suCambio?()
    }

    // MARK: - Sottofondo e fotocamera interrotta (1.0 beta 2)

    /// L'app perde (`true`) o ritrova (`false`) il primo piano.
    func impostaSottofondo(_ attivo: Bool) {
        guard inFunzione, attivo != sottofondo else { return }
        sottofondo = attivo
        suCambio?()
    }

    /// iOS ha tolto la fotocamera (`causa`) o l'ha restituita (`nil`).
    func impostaInterruzione(_ causa: CausaInterruzione?) {
        guard inFunzione, causa != interruzione else { return }
        interruzione = causa
        suCambio?()
    }

    // MARK: - Pausa automatica (Qualità 18)

    /// Messaggio `pausa-automatica` dal computer. Vero: nessuna app usa la webcam e nessuno guarda il video da un po',
    /// la fotocamera si spegne. Falso: il video serve di nuovo, si riprende subito.
    func pausaAutomatica(_ attiva: Bool) {
        // Un'app che usa la webcam vince sempre: in onda non si va in pausa, anche se i messaggi si incrociano.
        let nuova = attiva && inFunzione && !appInOnda
        guard nuova != nessunaApp else { return }
        nessunaApp = nuova
        suCambio?()
    }

    /// Messaggio `in-onda` dal computer. Un'app che apre la webcam toglie subito la pausa automatica, anche prima del
    /// `pausa-automatica` falso che il computer manda comunque.
    func inOnda(_ attivo: Bool) {
        appInOnda = attivo
        guard attivo, nessunaApp else { return }
        nessunaApp = false
        suCambio?()
    }

    /// Nuovo `benvenuto` dopo una connessione nuova: si riparte come se il computer non avesse detto nulla (dopo il
    /// `benvenuto` manda subito il suo `pausa-automatica`). In silenzio: la sessione riaccende da sé la fotocamera per
    /// il video. Non si chiama al passaggio dal Wi-Fi al cavo: stesso computer, che rimanda comunque il suo valore.
    func nuovoCollegamento() {
        appInOnda = false
        if nessunaApp { nessunaApp = false }
    }

    // MARK: - Faccia in giù (P07)

    /// I sensori solo mentre la sessione va e la funzione è accesa; cinque letture al secondo bastano.
    private func aggiornaMovimento() {
        let serve = inFunzione && Self.facciaInGiuAbilitata
        if serve, movimento == nil {
            let nuovo = CMMotionManager()
            guard nuovo.isDeviceMotionAvailable else { return }
            nuovo.deviceMotionUpdateInterval = 0.2
            nuovo.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] dati, _ in
                guard let z = dati?.gravity.z else { return }
                Task { @MainActor in self?.gravita(z) }
            }
            movimento = nuovo
        } else if !serve, let attuale = movimento {
            attuale.stopDeviceMotionUpdates()
            movimento = nil
            giuDa = nil
            if facciaInGiu {
                facciaInGiu = false
                suCambio?()
            }
        }
    }

    /// z = +1 con lo schermo verso il basso, -1 steso a faccia in su.
    private func gravita(_ z: Double) {
        guard movimento != nil else { return }
        let adesso = ProcessInfo.processInfo.systemUptime
        if z > 0.9 {
            if giuDa == nil { giuDa = adesso }
            if !facciaInGiu, let inizio = giuDa, adesso - inizio >= 1 {
                facciaInGiu = true
                suCambio?()
            }
        } else {
            giuDa = nil
            if facciaInGiu && z < 0.7 {
                facciaInGiu = false
                suCambio?()
            }
        }
    }
}

/// Perché iOS ha tolto la fotocamera a WebcamLR: decide il testo sul telefono. Al computer va solo
/// `fotocamera-interrotta`.
enum CausaInterruzione: Equatable, Sendable {
    /// Una chiamata ha preso il microfono (e con lui la sessione della fotocamera).
    case chiamata
    /// Un'altra app usa la fotocamera, o più app sono in primo piano insieme.
    case altraApp
    /// Il telefono è troppo caldo: iOS ha spento la fotocamera.
    case calore
    /// Un motivo che iOS non dice o che questa versione non conosce.
    case altro
}

extension Vibrazione {
    /// P07: il video si ferma (iPhone a faccia in giù): si sente anche senza guardare.
    static func pausa() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func ripresa() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
