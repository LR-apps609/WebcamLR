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
/// - P10 `nessuna-app`: nessuna app usa la webcam (`in-onda` falso) e la finestra del computer non mostra il video
///   (`anteprima` falsa) da più di `Servizio.secondiPrimaDellaPausa` secondi. Mai se in questo collegamento non è
///   arrivata nessuna `anteprima` (computer vecchio). Qui la fotocamera si spegne del tutto (batteria e calore) e si
///   riaccende appena `in-onda` o `anteprima` tornano vere. Durante «Prova la webcam» non si va in pausa.
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
    /// Nessuno guarda il video da più di 10 secondi.
    private(set) var nessunaApp = false
    /// Pausa chiesta con il pulsante «Pausa» di «In onda» (`utente` nel protocollo): resta finché non si riprende.
    private(set) var utente = false

    /// Il motivo da mandare in `stato.pausa` (`MotiviPausa`), `nil` se il video va. Se ne valgono più d'uno si dice
    /// prima «faccia in giù», poi la pausa chiesta col pulsante: sono i gesti scelti dall'utente.
    var motivo: String? {
        if facciaInGiu { return MotiviPausa.facciaInGiu }
        if utente { return MotiviPausa.utente }
        if nessunaApp { return MotiviPausa.nessunaApp }
        return nil
    }

    /// P10: la fotocamera va spenta, non solo il video fermato.
    var fotocameraSpenta: Bool { nessunaApp }

    /// Il motivo è cambiato: la sessione ferma o riprende il video.
    @ObservationIgnored var suCambio: (() -> Void)?

    @ObservationIgnored private var inFunzione = false
    @ObservationIgnored private var movimento: CMMotionManager?
    @ObservationIgnored private var giuDa: TimeInterval?
    @ObservationIgnored private var osservatoreImpostazioni: NSObjectProtocol?

    // Pausa intelligente: cosa ha detto il computer in questo collegamento.
    @ObservationIgnored private var anteprimaRicevuta = false
    @ObservationIgnored private var anteprimaVisibile = false
    @ObservationIgnored private var appInOnda = false
    @ObservationIgnored private var trattenuta = false
    @ObservationIgnored private var compitoNessunaApp: Task<Void, Never>?

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

    // MARK: - Pausa intelligente (P10)

    /// Messaggio `anteprima` dal computer.
    func anteprima(visibile: Bool) {
        anteprimaRicevuta = true
        anteprimaVisibile = visibile
        valutaNessunaApp()
    }

    /// Messaggio `in-onda` dal computer.
    func inOnda(_ attivo: Bool) {
        appInOnda = attivo
        valutaNessunaApp()
    }

    /// Nuovo `benvenuto` dopo una connessione nuova: si riparte come se il computer non avesse detto nulla
    /// (manderà subito la sua `anteprima`). In silenzio: la sessione riaccende da sé la fotocamera per il video.
    /// Non si chiama al passaggio dal Wi-Fi al cavo: stesso computer, la pausa resta.
    func nuovoCollegamento() {
        compitoNessunaApp?.cancel()
        compitoNessunaApp = nil
        anteprimaRicevuta = false
        anteprimaVisibile = false
        appInOnda = false
        if nessunaApp { nessunaApp = false }
    }

    /// «Prova la webcam» guarda il video sull'iPhone: intanto niente pausa per «nessuna app».
    func trattieni(_ attiva: Bool) {
        trattenuta = attiva
        valutaNessunaApp()
    }

    private func valutaNessunaApp() {
        let nessunoGuarda = inFunzione && anteprimaRicevuta && !anteprimaVisibile && !appInOnda && !trattenuta
        guard nessunoGuarda else {
            compitoNessunaApp?.cancel()
            compitoNessunaApp = nil
            if nessunaApp {
                nessunaApp = false
                suCambio?()
            }
            return
        }
        guard !nessunaApp, compitoNessunaApp == nil else { return }
        compitoNessunaApp = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Servizio.secondiPrimaDellaPausa))
            guard !Task.isCancelled, let self else { return }
            self.compitoNessunaApp = nil
            self.nessunaApp = true
            self.suCambio?()
        }
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

extension Vibrazione {
    /// P07: il video si ferma (iPhone a faccia in giù): si sente anche senza guardare.
    static func pausa() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func ripresa() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
