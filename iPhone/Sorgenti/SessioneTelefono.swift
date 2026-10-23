import Foundation
import Observation
import UIKit
import WebcamLRProtocollo

/// Un valore letto e scritto da più code.
final class Protetto<Valore>: @unchecked Sendable {
    private let blocco = NSLock()
    private var interno: Valore

    init(_ valore: Valore) {
        interno = valore
    }

    var valore: Valore {
        get { blocco.withLock { interno } }
        set { blocco.withLock { interno = newValue } }
    }
}

/// Una sessione con un computer: collegamento, fotocamera, codifica e stato del telefono (round 1).
@Observable
@MainActor
final class SessioneTelefono {
    enum Stato: Equatable {
        case collegamento
        case collegato
        case riconnessione(tentativo: Int)
        case chiusa
        case errore(String)
    }

    static let tentativiMassimi = 5

    let computer: ComputerTrovato
    let cattura = Cattura()

    private(set) var stato: Stato = .collegamento
    private(set) var latenzaMs: Int?
    /// Un'app sul computer sta usando la webcam: il rosso «IN ONDA».
    private(set) var inOnda: InOnda?
    private(set) var larghezza = 0
    private(set) var altezza = 0
    private(set) var fps = 30
    private(set) var obiettivo: Obiettivo = .principale
    let obiettiviDisponibili = Obiettivo.disponibili
    private(set) var torciaAccesa = false
    /// Zoom dentro l'obiettivo scelto: 1 = nessuno.
    private(set) var zoom: CGFloat = 1
    /// Comandati dal computer; si riapplicano quando cambia l'obiettivo.
    private(set) var esposizione: Double = 0
    private(set) var bianco = 0
    /// Ultimo punto toccato per il fuoco, nelle coordinate dello schermo (per il riquadro giallo).
    private(set) var puntoFuoco: CGPoint?
    private var compitoFuoco: Task<Void, Never>?
    private(set) var batteria = -1
    private(set) var temperatura: Temperatura = .normale
    private(set) var inCarica = false
    /// Il telefono è molto caldo: 720p e meno fotogrammi finché non torna normale (funzione 31).
    private(set) var qualitaRidotta = false

    /// Avviso batteria (funzione 33): sotto il 20% e non in carica.
    var batteriaBassa: Bool {
        batteria >= 0 && batteria < 20 && !inCarica
    }
    var oscurato = false

    private let codificatore = Codificatore()
    private let destinazione = Protetto<Collegamento?>(nil)
    private var collegamento: Collegamento?
    private var compitoStato: Task<Void, Never>?
    private var tentativi = 0
    private var chiusaDallUtente = false

    init(computer: ComputerTrovato) {
        self.computer = computer
        let codificatore = self.codificatore
        let destinazione = self.destinazione
        cattura.suFotogramma = { campione in
            codificatore.codifica(campione)
        }
        codificatore.suFotogramma = { fotogramma in
            destinazione.valore?.inviaVideo(fotogramma)
        }
        codificatore.suNuovoFormato = { [weak self] larghezza, altezza, fps, codec in
            destinazione.valore?.invia(.formato(FormatoVideo(codec: codec, larghezza: larghezza, altezza: altezza, fps: fps)))
            Task { @MainActor in
                self?.larghezza = larghezza
                self?.altezza = altezza
                self?.fps = fps
            }
        }
    }

    // MARK: - Ciclo di vita

    func avvia() {
        chiusaDallUtente = false
        tentativi = 0
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let salvato = Obiettivo(rawValue: UserDefaults.standard.string(forKey: "obiettivo") ?? ""),
           obiettiviDisponibili.contains(salvato) {
            obiettivo = salvato
        }
        collega()
    }

    func termina() {
        chiusaDallUtente = true
        compitoStato?.cancel()
        destinazione.valore = nil
        collegamento?.chiudi()
        collegamento = nil
        cattura.torcia(false)
        cattura.ferma()
        codificatore.chiudi()
        UIApplication.shared.isIdleTimerDisabled = false
        stato = .chiusa
    }

    func riprova() {
        tentativi = 0
        // Il vecchio collegamento può essere ancora aperto (per esempio dopo un errore della fotocamera).
        destinazione.valore = nil
        collegamento?.chiudi()
        collegamento = nil
        collega()
    }

    // MARK: - Comandi dell'interfaccia

    func scegli(_ nuovo: Obiettivo) {
        guard nuovo != obiettivo else { return }
        obiettivo = nuovo
        torciaAccesa = false
        zoom = 1
        UserDefaults.standard.set(nuovo.rawValue, forKey: "obiettivo")
        Task { await avviaFotocamera() }
    }

    func metteAFuoco(_ punto: CGPoint) {
        cattura.metteAFuoco(suPuntoDellAnteprima: punto)
        puntoFuoco = punto
        compitoFuoco?.cancel()
        compitoFuoco = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.puntoFuoco = nil
        }
    }

    func impostaZoom(_ fattore: CGFloat) {
        zoom = min(max(fattore, 1), 10)
        cattura.zoom(zoom)
    }

    func cambiaTorcia() {
        torciaAccesa.toggle()
        cattura.torcia(torciaAccesa)
    }

    var torciaDisponibile: Bool {
        obiettivo != .frontale
    }

    // MARK: - Collegamento

    private func collega() {
        stato = tentativi == 0 ? .collegamento : .riconnessione(tentativo: tentativi)
        let nuovo = Collegamento(verso: computer.endpoint)
        let identita = ObjectIdentifier(nuovo)
        nuovo.suEvento = { [weak self] evento in
            self?.gestisci(evento, da: identita)
        }
        let codificatore = self.codificatore
        nuovo.suPerdita = {
            codificatore.richiediFotogrammaChiave()
        }
        collegamento = nuovo
        nuovo.avvia()
    }

    private func gestisci(_ evento: Collegamento.Evento, da identita: ObjectIdentifier) {
        guard let collegamento, ObjectIdentifier(collegamento) == identita else { return }
        switch evento {
        case .pronto:
            let versione = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
            collegamento.invia(.ciao(Ciao(nome: UIDevice.current.name, piattaforma: .iphone, versioneApp: versione)))

        case .messaggio(.benvenuto(_)):
            tentativi = 0
            stato = .collegato
            destinazione.valore = collegamento
            Task { await avviaFotocamera() }
            avviaStatoPeriodico()

        case .messaggio(.latenza(let latenza)):
            latenzaMs = latenza.ms

        case .messaggio(.comando(let comando)):
            applica(comando)

        case .messaggio(.inOnda(let nuovo)):
            inOnda = nuovo.attivo ? nuovo : nil

        case .messaggio:
            break

        case .chiuso(let errore, let dalComputer):
            self.collegamento = nil
            destinazione.valore = nil
            compitoStato?.cancel()
            latenzaMs = nil
            inOnda = nil
            guard !chiusaDallUtente else { return }
            if dalComputer {
                cattura.ferma()
                stato = .errore("Il computer ha chiuso il collegamento.")
                return
            }
            if tentativi < Self.tentativiMassimi {
                tentativi += 1
                stato = .riconnessione(tentativo: tentativi)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, !self.chiusaDallUtente, self.collegamento == nil else { return }
                    self.collega()
                }
            } else {
                cattura.ferma()
                stato = .errore(errore ?? "Il computer non risponde.")
            }
        }
    }

    /// Avvia o riconfigura la fotocamera con le impostazioni salvate.
    private func avviaFotocamera() async {
        var (larghezzaRichiesta, altezzaRichiesta) = Self.dimensioniSalvate()
        var fpsRichiesti = UserDefaults.standard.object(forKey: "fps") as? Int ?? 30
        if qualitaRidotta {
            (larghezzaRichiesta, altezzaRichiesta) = (min(larghezzaRichiesta, 1280), min(altezzaRichiesta, 720))
            fpsRichiesti = min(fpsRichiesti, 24)
        }
        // Ricrea la sessione di codifica: il computer riceve un nuovo `formato` e un fotogramma chiave.
        let codec = Codec(rawValue: UserDefaults.standard.string(forKey: "codec") ?? "") ?? .h264
        codificatore.imposta(fps: fpsRichiesti, codec: codec)
        do {
            try await cattura.configura(obiettivo: obiettivo, larghezza: larghezzaRichiesta,
                                        altezza: altezzaRichiesta, fps: fpsRichiesti)
            if torciaAccesa { cattura.torcia(true) }
            // Il cambio di formato (per esempio quando si scalda) riporta lo zoom del dispositivo a 1.
            if zoom != 1 { cattura.zoom(zoom) }
            if esposizione != 0 { cattura.esposizione(Float(esposizione)) }
            if bianco != 0 { cattura.bianco(kelvin: bianco) }
            inviaCapacita()
            // Il computer vede subito il nuovo obiettivo, senza aspettare i 5 secondi dello stato.
            aggiornaStato()
        } catch {
            stato = .errore(error.localizedDescription)
        }
    }

    /// Comandi della fotocamera dal computer (round 4): solo i campi presenti.
    private func applica(_ comando: Comando) {
        if let nome = comando.obiettivo, let nuovo = Obiettivo(rawValue: nome), obiettiviDisponibili.contains(nuovo) {
            scegli(nuovo)
        }
        if let fattore = comando.zoom {
            impostaZoom(CGFloat(fattore))
        }
        if let accesa = comando.torcia, accesa != torciaAccesa, torciaDisponibile {
            cambiaTorcia()
        }
        if let stop = comando.esposizione {
            esposizione = min(max(stop, -2), 2)
            cattura.esposizione(Float(esposizione))
        }
        if let kelvin = comando.bianco {
            bianco = kelvin == 0 ? 0 : min(max(kelvin, 2500), 7500)
            cattura.bianco(kelvin: bianco)
        }
        if comando.fuoco == "continuo" {
            cattura.fuocoContinuo()
        }
    }

    /// Dice al computer cosa può comandare con l'obiettivo attuale.
    private func inviaCapacita() {
        collegamento?.invia(.capacita(Capacita(obiettivi: obiettiviDisponibili.map(\.rawValue),
                                               zoomMassimo: cattura.zoomMassimo,
                                               torcia: torciaDisponibile)))
    }

    private static func dimensioniSalvate() -> (Int32, Int32) {
        switch UserDefaults.standard.string(forKey: "risoluzione") ?? "1080p" {
        case "720p": (1280, 720)
        case "4K": (3840, 2160)
        default: (1920, 1080)
        }
    }

    /// Batteria e temperatura al computer ogni 5 secondi.
    private func avviaStatoPeriodico() {
        compitoStato?.cancel()
        compitoStato = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.aggiornaStato()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func aggiornaStato() {
        let dispositivo = UIDevice.current
        batteria = dispositivo.batteryLevel < 0 ? -1 : Int((dispositivo.batteryLevel * 100).rounded())
        temperatura = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .normale
        case .fair: .calda
        case .serious: .moltoCalda
        case .critical: .critica
        @unknown default: .normale
        }
        inCarica = dispositivo.batteryState == .charging || dispositivo.batteryState == .full
        collegamento?.invia(.stato(StatoTelefono(batteria: batteria, inCarica: inCarica,
                                                 temperatura: temperatura, obiettivo: obiettivo.rawValue)))
        regolaQualita()
    }

    /// Scende a 720p quando è molto caldo; torna alla qualità scelta solo quando è di nuovo normale,
    /// così non salta avanti e indietro.
    private func regolaQualita() {
        let attivo = UserDefaults.standard.object(forKey: "riduciSeCaldo") as? Bool ?? true
        let caldo = temperatura == .moltoCalda || temperatura == .critica
        if attivo && caldo && !qualitaRidotta {
            qualitaRidotta = true
            Task { await avviaFotocamera() }
        } else if qualitaRidotta && (temperatura == .normale || !attivo) {
            qualitaRidotta = false
            Task { await avviaFotocamera() }
        }
    }
}
