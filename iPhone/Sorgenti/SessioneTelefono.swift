import Foundation
import Network
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
    private(set) var codec: Codec = .h264
    /// Come si è collegati (1.2): Wi-Fi, cavo USB, Wi-Fi diretto…; `nil` finché non si sa.
    private(set) var tipoCollegamento: TipoCollegamento?
    private(set) var obiettivo: Obiettivo = .principale
    let obiettiviDisponibili = Obiettivo.disponibili
    private(set) var torciaAccesa = false
    /// Zoom dentro l'obiettivo scelto: 1 = nessuno.
    private(set) var zoom: CGFloat = 1
    /// Comandati dal computer; si riapplicano quando cambia l'obiettivo.
    private(set) var esposizione: Double = 0
    private(set) var bianco = 0
    /// Esposizione manuale dal computer: 0 = automatico.
    private(set) var iso: Double = 0
    private(set) var tempo = 0
    /// Ultimo punto toccato per il fuoco, nelle coordinate dello schermo (per il riquadro giallo).
    private(set) var puntoFuoco: CGPoint?
    private var compitoFuoco: Task<Void, Never>?
    /// Fuoco ed esposizione bloccati con il tocco lungo: «AE/AF bloccati» (round 2).
    private(set) var aeafBloccati = false
    /// Da quando si cerca di ritrovare il computer perso: i secondi nel banner (round 2).
    private(set) var inizioRiconnessione: Date?
    private(set) var batteria = -1
    private(set) var temperatura: Temperatura = .normale
    private(set) var inCarica = false
    /// Il telefono è molto caldo: 720p e meno fotogrammi finché non torna normale (funzione 31).
    private(set) var qualitaRidotta = false
    /// Batteria sotto il 20% senza caricatore: 24 fps finché non si ricarica (round 2, novità 17).
    private(set) var risparmioBatteria = false
    /// La rete non regge la qualità scelta: il bitrate è sceso da solo (round 2, novità 4).
    private(set) var reteDebole = false
    /// Fotogrammi scartati negli ultimi 5 secondi, per la qualità del collegamento in parole.
    private(set) var perditeRecenti = 0
    @ObservationIgnored private var perditeUltimiSecondi: [Int] = []
    /// Il computer chiede all'utente di consentire questo iPhone: il codice di conferma, uguale sui due schermi (0.10).
    private(set) var codiceConferma: String?
    /// Titolo del pannello d'errore: dice se non ci si è mai collegati, se il computer va aggiornato…
    private(set) var titoloErrore = "Collegamento interrotto"
    /// Riprovare non serve (l'identità del computer è cambiata): si torna ai computer e si usa il QR code.
    private(set) var erroreDefinitivo = false
    /// La domanda frequente che spiega l'errore (1.4), per il link «Perché succede?».
    private(set) var domandaErrore: String?
    /// La causa probabile quando non ci si riesce a collegare, con la sua azione (1.3).
    private(set) var diagnosi: Diagnosi?
    /// Almeno un `benvenuto` in questa sessione: prima il computer non è «perso», non ci si è ancora collegati.
    private(set) var giaCollegato = false
    /// L'ultima latenza nota, che resta anche dopo la chiusura: serve a «Segnala un bug».
    private(set) var ultimaLatenzaMs: Int?
    /// L'impronta del computer dopo la stretta di mano: si salva tra i computer conosciuti al `benvenuto`.
    @ObservationIgnored private var improntaComputer: String?

    /// Avviso batteria (funzione 33): sotto il 20% e non in carica.
    var batteriaBassa: Bool {
        batteria >= 0 && batteria < 20 && !inCarica
    }
    var oscurato = false

    private let codificatore = Codificatore()
    private let identitaTelefono = IdentitaTelefono.condivisa
    private let destinazione = Protetto<Collegamento?>(nil)
    private var collegamento: Collegamento?
    private var compitoStato: Task<Void, Never>?
    private var tentativi = 0
    private var chiusaDallUtente = false
    /// La fotocamera è configurata e in funzione con le impostazioni attuali.
    @ObservationIgnored private var fotocameraPronta = false
    /// L'accensione della fotocamera partita all'apertura, mentre il collegamento si apre.
    @ObservationIgnored private var compitoFotocamera: Task<Void, Never>?
    /// Il prossimo tentativo di ricollegamento in attesa.
    @ObservationIgnored private var compitoRiprova: Task<Void, Never>?
    /// Quando la rete torna si riprova subito, senza aspettare il tentativo successivo.
    @ObservationIgnored private var monitorRete: NWPathMonitor?
    /// Osservata: senza rete il banner lo dice, invece di «Computer perso».
    private(set) var reteDisponibile = true

    init(computer: ComputerTrovato) {
        self.computer = computer
        let codificatore = self.codificatore
        let destinazione = self.destinazione
        cattura.suFotogramma = { campione in
            // Finché il computer non accoglie l'iPhone l'anteprima va, ma non si codifica nulla.
            guard destinazione.valore != nil else { return }
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
                self?.codec = codec
            }
        }
    }

    // MARK: - Ciclo di vita

    func avvia() {
        chiusaDallUtente = false
        tentativi = 0
        inizioRiconnessione = nil
        erroreDefinitivo = false
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let salvato = Obiettivo(rawValue: UserDefaults.standard.string(forKey: "obiettivo") ?? ""),
           obiettiviDisponibili.contains(salvato) {
            obiettivo = salvato
        }
        collega()
        avviaMonitorRete()
        // Batteria e temperatura prima di accendere la fotocamera: così parte già con i fotogrammi giusti,
        // senza una seconda configurazione subito dopo.
        misuraStato()
        _ = regolaQualita()
        // La fotocamera si accende subito, mentre il collegamento si apre: al `benvenuto` il video è pronto.
        compitoFotocamera = Task { await avviaFotocamera(segnalaErrori: false) }
    }

    func termina() {
        chiusaDallUtente = true
        compitoStato?.cancel()
        compitoRiprova?.cancel()
        compitoFotocamera?.cancel()
        fotocameraPronta = false
        monitorRete?.cancel()
        monitorRete = nil
        destinazione.valore = nil
        collegamento?.chiudi()
        collegamento = nil
        cattura.torcia(false)
        cattura.ferma()
        codificatore.chiudi()
        UIApplication.shared.isIdleTimerDisabled = false
        inizioRiconnessione = nil
        stato = .chiusa
    }

    func riprova() {
        tentativi = 0
        erroreDefinitivo = false
        // Il vecchio collegamento può essere ancora aperto (per esempio dopo un errore della fotocamera).
        destinazione.valore = nil
        collegamento?.chiudi()
        collegamento = nil
        collega()
        // Dopo un errore la fotocamera è spenta: si riaccende mentre il collegamento si apre.
        if !fotocameraPronta {
            compitoFotocamera = Task { await avviaFotocamera(segnalaErrori: false) }
        }
    }

    // MARK: - Comandi dell'interfaccia

    func scegli(_ nuovo: Obiettivo) {
        guard nuovo != obiettivo else { return }
        obiettivo = nuovo
        torciaAccesa = false
        zoom = 1
        aeafBloccati = false
        puntoFuoco = nil
        Vibrazione.cambioObiettivo()
        UserDefaults.standard.set(nuovo.rawValue, forKey: "obiettivo")
        Task { await avviaFotocamera() }
    }

    func metteAFuoco(_ punto: CGPoint) {
        cattura.metteAFuoco(suPuntoDellAnteprima: punto)
        aeafBloccati = false
        puntoFuoco = punto
        compitoFuoco?.cancel()
        compitoFuoco = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.puntoFuoco = nil
        }
    }

    /// Tocco lungo: blocca fuoco ed esposizione sul punto; il riquadro resta finché un tocco non sblocca.
    func bloccaFuocoEdEsposizione(_ punto: CGPoint) {
        cattura.bloccaFuocoEdEsposizione(suPuntoDellAnteprima: punto)
        compitoFuoco?.cancel()
        puntoFuoco = punto
        aeafBloccati = true
        Vibrazione.bloccoFuoco()
    }

    /// Doppio tocco sull'anteprima (round 2): frontale ↔ posteriore.
    func cambiaFotocamera() {
        let nuovo: Obiettivo = obiettivo == .frontale ? .principale : .frontale
        guard obiettiviDisponibili.contains(nuovo) else { return }
        scegli(nuovo)
    }

    func impostaZoom(_ fattore: CGFloat, scorrevole: Bool = false) {
        zoom = min(max(fattore, 1), 10)
        cattura.zoom(zoom, scorrevole: scorrevole)
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
        compitoRiprova?.cancel()
        compitoRiprova = nil
        stato = tentativi == 0 ? .collegamento : .riconnessione(tentativo: tentativi)
        // Protocollo 2: l'impronta attesa viene dal QR code, altrimenti dai computer conosciuti.
        let nuovo = Collegamento(verso: computer.endpoint, identita: identitaTelefono,
                                 improntaAttesa: computer.impronta ?? ComputerConosciuti.impronta(di: computer.nome),
                                 gettone: computer.gettone, diretto: computer.diretto)
        codiceConferma = nil
        improntaComputer = nil
        let identita = ObjectIdentifier(nuovo)
        nuovo.suEvento = { [weak self] evento in
            self?.gestisci(evento, da: identita)
        }
        let codificatore = self.codificatore
        nuovo.suPerdita = {
            codificatore.richiediFotogrammaChiave()
        }
        // Una volta al secondo: il bitrate segue la rete, l'interfaccia riceve solo il riassunto.
        nuovo.suSecondo = { [weak self] scartati, saturo in
            let debole = codificatore.adattaAllaRete(scartati: scartati, saturo: saturo)
            Task { @MainActor in self?.registraSecondo(scartati: scartati, debole: debole) }
        }
        codificatore.azzeraRete()
        perditeUltimiSecondi = []
        perditeRecenti = 0
        reteDebole = false
        collegamento = nuovo
        nuovo.avvia()
    }

    private func gestisci(_ evento: Collegamento.Evento, da identita: ObjectIdentifier) {
        guard let collegamento, ObjectIdentifier(collegamento) == identita else { return }
        switch evento {
        case .pronto(let impronta):
            // Stretta di mano riuscita e prova già spedita: il `ciao` parte cifrato.
            improntaComputer = impronta
            let versione = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
            collegamento.invia(.ciao(Ciao(versione: Sicurezza.versioneSicura, nome: UIDevice.current.name,
                                          piattaforma: .iphone, versioneApp: versione)))

        case .messaggio(.approvazione(let approvazione)):
            // Prima volta con questo computer: l'utente conferma sul computer, con lo stesso codice.
            codiceConferma = approvazione.codice
            Vibrazione.richiestaConferma()

        case .messaggio(.benvenuto(_)):
            codiceConferma = nil
            giaCollegato = true
            // Da ora questo computer è conosciuto: la prossima volta la sua impronta deve essere la stessa.
            if let impronta = improntaComputer {
                ComputerConosciuti.salva(impronta, per: computer.nome)
            }
            tentativi = 0
            stato = .collegato
            inizioRiconnessione = nil
            Vibrazione.collegato()
            // Al prossimo avvio ci si ricollega da soli a questo computer, se Bonjour lo trova.
            UserDefaults.standard.set(computer.nome, forKey: Ricollegamento.chiaveUltimoComputer)
            destinazione.valore = collegamento
            avviaStatoPeriodico()
            Task { await preparaVideo() }

        case .messaggio(.latenza(let latenza)):
            latenzaMs = latenza.ms
            ultimaLatenzaMs = latenza.ms

        case .messaggio(.comando(let comando)):
            applica(comando)

        case .messaggio(.inOnda(let nuovo)):
            inOnda = nuovo.attivo ? nuovo : nil

        case .messaggio:
            break

        case .tipo(let tipo):
            tipoCollegamento = tipo

        case .chiuso(let errore, let motivo):
            let inAttesaDiConferma = codiceConferma != nil
            codiceConferma = nil
            self.collegamento = nil
            destinazione.valore = nil
            compitoStato?.cancel()
            latenzaMs = nil
            inOnda = nil
            tipoCollegamento = nil
            guard !chiusaDallUtente else { return }
            // Una vibrazione quando si perde il computer, non a ogni tentativo andato a vuoto.
            if motivo != .rete || inizioRiconnessione == nil { Vibrazione.scollegato() }
            let nome = computer.nome
            // Chiuso mentre si aspettava la conferma: il computer ha detto no, o nessuno ha risposto.
            // Riprovare da soli farebbe solo ricomparire la domanda.
            if inAttesaDiConferma && (motivo == .rete || motivo == .dalComputer) {
                fermaConErrore(titolo: "Collegamento non confermato",
                               descrizione: "Il collegamento non è stato consentito su \(nome). Tocca «Riprova» e conferma sul computer.",
                               domanda: "codice")
                return
            }
            switch motivo {
            case .rete:
                // Senza rete non si consumano tentativi: si riparte appena torna (`reteCambiata`).
                if !reteDisponibile {
                    if inizioRiconnessione == nil { inizioRiconnessione = Date() }
                    stato = .riconnessione(tentativo: max(tentativi, 1))
                    return
                }
            case .dalComputer:
                fermaConErrore(titolo: giaCollegato ? "Collegamento interrotto" : "Non riesco a collegarmi a \(nome)",
                               descrizione: "\(nome) ha chiuso il collegamento. Tocca «Riprova» per collegarti di nuovo.")
                return
            case .computerVecchio:
                fermaConErrore(diagnosi: .computerVecchio(nome: nome))
                return
            case .permessoNegato:
                StatoRete.condiviso.permessoNegato = true
                fermaConErrore(diagnosi: .permessoReteLocale)
                return
            case .identitaCambiata:
                // Niente ricollegamento automatico a questo computer finché non lo si riabbina.
                if UserDefaults.standard.string(forKey: Ricollegamento.chiaveUltimoComputer) == nome {
                    UserDefaults.standard.removeObject(forKey: Ricollegamento.chiaveUltimoComputer)
                }
                fermaConErrore(titolo: "Computer da collegare di nuovo",
                               descrizione: "\(nome) non è più lo stesso computer per l'iPhone (per esempio dopo averlo reinstallato). Tocca «Torna ai computer» e collegalo di nuovo con «Inquadra il QR code del computer».",
                               definitivo: true, domanda: "identita")
                return
            case .identitaNonValida:
                fermaConErrore(titolo: "Collegamento non sicuro",
                               descrizione: "\(nome) non ha superato il controllo di sicurezza. Tocca «Riprova», oppure torna ai computer e collegati con il QR code.",
                               domanda: "identita")
                return
            }
            if tentativi < Self.tentativiMassimi {
                if inizioRiconnessione == nil { inizioRiconnessione = Date() }
                tentativi += 1
                stato = .riconnessione(tentativo: tentativi)
                // Il primo tentativo quasi subito (spesso è solo un attimo di Wi-Fi), poi ogni 2 secondi.
                let attesa: Duration = tentativi == 1 ? .milliseconds(500) : .seconds(2)
                compitoRiprova = Task { [weak self] in
                    try? await Task.sleep(for: attesa)
                    guard !Task.isCancelled, let self, !self.chiusaDallUtente, self.collegamento == nil else { return }
                    self.collega()
                }
            } else if let causa = Diagnosi.collegamento(giaCollegato: giaCollegato, annunciato: computer.annunciato,
                                                         piattaforma: computer.piattaforma, rete: StatoRete.condiviso) {
                // 1.3: invece di «non risponde», la causa probabile e cosa fare.
                fermaConErrore(diagnosi: causa)
            } else {
                fermaConErrore(titolo: giaCollegato ? "Collegamento interrotto" : "Non riesco a collegarmi a \(nome)",
                               descrizione: errore ?? "Il computer non risponde: controlla che WebcamLR sia aperto sul computer e che siate sulla stessa rete Wi-Fi, poi tocca «Riprova».",
                               domanda: giaCollegato ? nil : "non-trova")
            }
        }
    }

    /// Ci si ferma: niente più tentativi da soli, il pannello dice cosa fare.
    private func fermaConErrore(titolo: String, descrizione: String, definitivo: Bool = false, domanda: String? = nil,
                                diagnosi: Diagnosi? = nil) {
        compitoRiprova?.cancel()
        cattura.ferma()
        fotocameraPronta = false
        inizioRiconnessione = nil
        titoloErrore = titolo
        erroreDefinitivo = definitivo
        self.diagnosi = diagnosi
        domandaErrore = domanda ?? diagnosi?.domanda
        // Lo schermo oscurato coprirebbe il pannello con «Riprova»: si riaccende.
        oscurato = false
        stato = .errore(descrizione)
    }

    /// Con una diagnosi titolo e spiegazione sono i suoi.
    private func fermaConErrore(diagnosi: Diagnosi) {
        fermaConErrore(titolo: diagnosi.titolo, descrizione: diagnosi.spiegazione, diagnosi: diagnosi)
    }

    private func registraSecondo(scartati: Int, debole: Bool) {
        perditeUltimiSecondi.append(scartati)
        if perditeUltimiSecondi.count > 5 { perditeUltimiSecondi.removeFirst() }
        let somma = perditeUltimiSecondi.reduce(0, +)
        // Si assegna solo se cambia, così l'interfaccia non si ridisegna ogni secondo.
        if somma != perditeRecenti { perditeRecenti = somma }
        if debole != reteDebole { reteDebole = debole }
    }

    /// Al `benvenuto`: se la fotocamera è già accesa basta un nuovo `formato` con un fotogramma chiave
    /// per questo collegamento, senza riconfigurarla (il video arriva prima); altrimenti si accende ora.
    private func preparaVideo() async {
        await compitoFotocamera?.value
        guard !chiusaDallUtente, collegamento != nil, stato == .collegato else { return }
        if fotocameraPronta {
            codificatore.ricomincia()
            inviaCapacita()
        } else {
            await avviaFotocamera()
        }
    }

    /// Avvia o riconfigura la fotocamera con le impostazioni salvate.
    /// `segnalaErrori` falso: accensione anticipata, un errore lo dirà il tentativo al `benvenuto`.
    private func avviaFotocamera(segnalaErrori: Bool = true) async {
        guard !chiusaDallUtente else { return }
        var (larghezzaRichiesta, altezzaRichiesta) = Self.dimensioniSalvate()
        var fpsRichiesti = UserDefaults.standard.object(forKey: "fps") as? Int ?? 30
        if qualitaRidotta {
            (larghezzaRichiesta, altezzaRichiesta) = (min(larghezzaRichiesta, 1280), min(altezzaRichiesta, 720))
            fpsRichiesti = min(fpsRichiesti, 24)
        }
        if risparmioBatteria {
            fpsRichiesti = min(fpsRichiesti, 24)
        }
        // Ricrea la sessione di codifica: il computer riceve un nuovo `formato` e un fotogramma chiave.
        let codec = Codec(rawValue: UserDefaults.standard.string(forKey: "codec") ?? "") ?? .h264
        codificatore.imposta(fps: fpsRichiesti, codec: codec)
        do {
            try await cattura.configura(obiettivo: obiettivo, larghezza: larghezzaRichiesta,
                                        altezza: altezzaRichiesta, fps: fpsRichiesti,
                                        specchia: UserDefaults.standard.bool(forKey: "specchia"),
                                        stabilizzazione: UserDefaults.standard.bool(forKey: "stabilizzazione"))
            // Chiusa mentre la fotocamera si accendeva: si spegne, altrimenti resterebbe accesa.
            if chiusaDallUtente {
                cattura.ferma()
                return
            }
            fotocameraPronta = true
            // La riconfigurazione riparte con messa a fuoco ed esposizione automatiche: niente più «AE/AF bloccati».
            compitoFuoco?.cancel()
            aeafBloccati = false
            puntoFuoco = nil
            if torciaAccesa { cattura.torcia(true) }
            // Il cambio di formato (per esempio quando si scalda) riporta lo zoom del dispositivo a 1.
            if zoom != 1 { cattura.zoom(zoom) }
            if esposizione != 0 { cattura.esposizione(Float(esposizione)) }
            if bianco != 0 { cattura.bianco(kelvin: bianco) }
            if iso != 0 || tempo != 0 { cattura.esposizioneManuale(iso: Float(iso), tempo: tempo) }
            inviaCapacita()
            // Il computer vede subito il nuovo obiettivo, senza aspettare i 5 secondi dello stato.
            aggiornaStato()
        } catch {
            fotocameraPronta = false
            guard segnalaErrori, !chiusaDallUtente else { return }
            titoloErrore = "Fotocamera non disponibile"
            erroreDefinitivo = false
            domandaErrore = nil
            diagnosi = nil
            oscurato = false
            // I nostri errori dicono già cosa fare; quelli di sistema (fotocamera occupata) no.
            stato = .errore((error as? ErroreCattura)?.errorDescription
                            ?? "Un'altra app sta usando la fotocamera: chiudila e tocca «Riprova».")
        }
    }

    /// Comandi della fotocamera dal computer (round 4): solo i campi presenti.
    private func applica(_ comando: Comando) {
        if let nome = comando.obiettivo, let nuovo = Obiettivo(rawValue: nome), obiettiviDisponibili.contains(nuovo) {
            scegli(nuovo)
        }
        if let fattore = comando.zoom {
            impostaZoom(CGFloat(fattore), scorrevole: true)
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
            aeafBloccati = false
            puntoFuoco = nil
        }
        if comando.iso != nil || comando.tempo != nil {
            iso = max(comando.iso ?? iso, 0)
            tempo = max(comando.tempo ?? tempo, 0)
            cattura.esposizioneManuale(iso: Float(iso), tempo: tempo)
        }
    }

    /// Dice al computer cosa può comandare con l'obiettivo attuale.
    private func inviaCapacita() {
        let limiti = cattura.limitiISO
        collegamento?.invia(.capacita(Capacita(obiettivi: obiettiviDisponibili.map(\.rawValue),
                                               zoomMassimo: cattura.zoomMassimo,
                                               torcia: torciaDisponibile,
                                               isoMinimo: limiti?.minimo, isoMassimo: limiti?.massimo)))
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
        misuraStato()
        collegamento?.invia(.stato(StatoTelefono(batteria: batteria, inCarica: inCarica,
                                                 temperatura: temperatura, obiettivo: obiettivo.rawValue)))
        if regolaQualita() { Task { await avviaFotocamera() } }
    }

    /// Batteria, carica e temperatura. Si assegna solo ciò che cambia: l'interfaccia non si ridisegna ogni 5 secondi.
    private func misuraStato() {
        let dispositivo = UIDevice.current
        let nuovaBatteria = dispositivo.batteryLevel < 0 ? -1 : Int((dispositivo.batteryLevel * 100).rounded())
        let nuovaTemperatura: Temperatura = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .normale
        case .fair: .calda
        case .serious: .moltoCalda
        case .critical: .critica
        @unknown default: .normale
        }
        let nuovaCarica = dispositivo.batteryState == .charging || dispositivo.batteryState == .full
        if nuovaBatteria != batteria { batteria = nuovaBatteria }
        if nuovaTemperatura != temperatura { temperatura = nuovaTemperatura }
        if nuovaCarica != inCarica { inCarica = nuovaCarica }
    }

    // MARK: - Rete

    private func avviaMonitorRete() {
        guard monitorRete == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] percorso in
            let disponibile = percorso.status == .satisfied
            Task { @MainActor in self?.reteCambiata(disponibile: disponibile) }
        }
        monitor.start(queue: .main)
        monitorRete = monitor
    }

    /// La rete è tornata mentre si cercava il computer: si riprova subito, da capo con i tentativi.
    private func reteCambiata(disponibile: Bool) {
        let tornata = disponibile && !reteDisponibile
        if disponibile != reteDisponibile { reteDisponibile = disponibile }
        guard tornata, !chiusaDallUtente, collegamento == nil, case .riconnessione = stato else { return }
        tentativi = 1
        collega()
    }

    /// Scende a 720p quando è molto caldo; torna alla qualità scelta solo quando è di nuovo normale,
    /// così non salta avanti e indietro.
    /// Risparmio batteria (round 2): sotto il 20% e senza caricatore, 24 fps; si torna ai fotogrammi
    /// scelti col caricatore o dal 25%. Un solo riavvio della fotocamera anche se cambiano entrambi.
    /// Ritorna `true` se la fotocamera va riconfigurata.
    private func regolaQualita() -> Bool {
        var cambiata = false
        let attivo = UserDefaults.standard.object(forKey: "riduciSeCaldo") as? Bool ?? true
        let caldo = temperatura == .moltoCalda || temperatura == .critica
        if attivo && caldo && !qualitaRidotta {
            qualitaRidotta = true
            cambiata = true
        } else if qualitaRidotta && (temperatura == .normale || !attivo) {
            qualitaRidotta = false
            cambiata = true
        }

        let risparmioScelto = UserDefaults.standard.object(forKey: "risparmioBatteria") as? Bool ?? true
        if risparmioScelto && batteriaBassa && !risparmioBatteria {
            risparmioBatteria = true
            cambiata = true
        } else if risparmioBatteria && (!risparmioScelto || inCarica || batteria >= 25) {
            risparmioBatteria = false
            cambiata = true
        }

        return cambiata
    }
}
