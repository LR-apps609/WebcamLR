import AppKit
import Foundation
import Network
import Observation
import Stile
import WebcamLRProtocollo

/// Il cuore dell'app Mac: si annuncia in rete, accetta un telefono e tiene lo stato per l'interfaccia.
@Observable
@MainActor
final class Ricevitore {
    enum StatoRete: Equatable {
        case fermo
        case visibile(porta: UInt16)
        case errore(String)
    }

    /// Dopo una caduta, quanto si aspetta che il telefono torni prima di dire «nessun telefono».
    static let attesaRiconnessione: Duration = .seconds(15)

    let schermo = Schermo()
    private let uscitaWebcam = UscitaWebcam()
    /// Il microfono del telefono verso «WebcamLR (microfono)» (P20).
    private let microfono = MicrofonoTelefono()
    /// Il driver del microfono nel sistema: installato? un'app lo usa? Riletto ogni 2 secondi.
    private(set) var installazioneMicrofono: MicrofonoTelefono.Installazione = .nonInstallato
    /// L'utente vuole il microfono del telefono acceso (resta da una volta all'altra).
    private(set) var microfonoAcceso = UserDefaults.standard.bool(forKey: Preferenze.microfonoTelefono)
    /// Nell'ultimo secondo è arrivato audio dal telefono.
    private(set) var audioInArrivo = false
    /// Da 0 a 1, per l'indicatore di livello.
    private(set) var livelloMicrofono = 0.0
    /// `comando.audio = true` già mandato alla sessione attuale.
    @ObservationIgnored private var audioComandato = false
    @ObservationIgnored private var compitoMicrofono: Task<Void, Never>?
    private(set) var rete: StatoRete = .fermo
    private(set) var collegamento: StatoCollegamento = .nessunTelefono
    private(set) var telefono: Ciao?
    /// Il codice di sicurezza del telefono attuale (1.1): due telefoni con lo stesso nome restano diversi.
    @ObservationIgnored private var improntaTelefono: String?
    /// Come è collegato il telefono attuale: Wi-Fi, cavo USB, Wi-Fi diretto, cavo di rete (1.2).
    private(set) var tipoCollegamento: TipoCollegamento?
    private(set) var statoTelefono: StatoTelefono?
    private(set) var statistiche = Statistiche()
    /// «Avvio: 0,9 s» del collegamento attuale (1.11), per la modalità avanzata; nil finché il video non è a schermo.
    private(set) var tempoAvvio: String?
    /// La latenza di ogni secondo, al massimo gli ultimi 60, per il grafico (funzione 31).
    private(set) var storicoLatenza: [Int?] = []
    /// Cosa si può comandare sul telefono collegato; nil finché il telefono non lo dice.
    private(set) var capacita: Capacita?
    /// Gli ultimi valori comandati da qui (il telefono non li rimanda indietro).
    var controlli = Controlli()
    /// Gli effetti come li mostra il Mac: comandati da qui e riallineati a ogni `stato` del telefono,
    /// così le modifiche fatte sul telefono si vedono anche qui (pacchetto effetti).
    var effetti = Effetti()
    /// Quando ogni effetto è stato cambiato da qui: per un attimo lo `stato` del telefono non lo sovrascrive,
    /// altrimenti un cursore trascinato tornerebbe indietro al valore di uno `stato` partito prima del comando.
    @ObservationIgnored private var modificheEffetti: [String: ContinuousClock.Instant] = [:]
    /// I comandi in attesa di partire (cursori e testi: uno solo ogni ~100 ms), per chiave.
    @ObservationIgnored private var inviiInAttesa: [String: Task<Void, Never>] = [:]
    /// Il gobbo preparato sul Mac: il testo resta anche senza telefono.
    var gobbo = GobboComputer()
    /// Il testo del gobbo già mandato al telefono attuale; nil se non ne ha ancora ricevuto uno.
    private(set) var testoGobboInviato: String?
    /// Dall'ultimo `stato.gobbo`: scorre o no, e dove è arrivato (da 0 a 1).
    private(set) var gobboAttivo = false
    private(set) var posizioneGobbo = 0.0
    /// La finestra mini è aperta (funzione 21).
    private(set) var miniAperta = false
    /// La finestra principale mostra il video (aperta, non ridotta a icona né coperta del tutto).
    @ObservationIgnored private var principaleVisibile = false
    /// L'ultimo `anteprima` deciso, per mandarlo solo quando cambia (pausa intelligente).
    @ObservationIgnored private var anteprimaSegnalata: Bool?

    /// Collegamento sicuro (0.10): l'identità del Mac, i telefoni fidati e il gettone del QR code.
    let abbinamento: Abbinamento
    /// Il codice di sicurezza di questo Mac, come lo vede il telefono (impronta della chiave).
    let improntaMac: String
    /// Copie per l'interfaccia, aggiornate quando l'abbinamento cambia: il QR code si rifà da solo.
    private(set) var gettone: String
    private(set) var telefoniFidati: [TelefonoFidato]
    private let finestraConferma = FinestraConferma()
    /// Gli indirizzi IPv4 del Mac per il QR code, riletti solo quando la rete cambia.
    private(set) var indirizzi: [String] = IndirizziLocali.ipv4()
    private let monitorRete = NWPathMonitor()
    /// Il tipo di ogni interfaccia di rete (Wi-Fi, cavo) dall'ultimo percorso: decide l'ordine nel QR code.
    @ObservationIgnored private var tipiInterfacce: [String: NWInterface.InterfaceType] = [:]
    /// La seconda lettura degli indirizzi dopo un cambio di rete.
    @ObservationIgnored private var compitoReteAssestata: Task<Void, Never>?
    /// Gli indirizzi con cui l'ascolto (e l'annuncio Bonjour) è partito l'ultima volta: se cambiano si rinnova (1.12).
    @ObservationIgnored private var indirizziAnnunciati: [String]?
    /// L'avviso di macOS al risveglio dallo stop (1.12).
    @ObservationIgnored private var osservatoreRisveglio: NSObjectProtocol?
    /// Il prossimo tentativo di riaprire un ascolto caduto, e quanto aspettare (cresce fino a 30 secondi).
    @ObservationIgnored private var compitoRiapertura: Task<Void, Never>?
    @ObservationIgnored private var attesaRiapertura: Duration = .seconds(1)
    /// Il cavo USB (1.8): il client usbmux apre i canali verso l'iPhone, qui diventano sessioni come le altre.
    private let cavo = ClienteUSB()
    /// Per la diagnosi: un iPhone sul cavo senza l'app aperta, il cavo in pausa…
    private(set) var statoCavo: ClienteUSB.Stato = .nessunIPhone
    /// Le sessioni (candidate o attuale) arrivate dal cavo, con il canale da restituire al client quando finiscono.
    @ObservationIgnored private var canaliCavo: [ObjectIdentifier: ClienteUSB.Canale] = [:]
    /// Sessioni del cavo che, finendo, mettono il cavo in pausa: «Scollega» sul Mac o un telefono non consentito.
    /// Senza pausa il client riaprirebbe il canale dopo 2 secondi e la domanda tornerebbe all'infinito.
    @ObservationIgnored private var pausaCavo: Set<ObjectIdentifier> = []

    /// Una riga del registro del collegamento (1.5, modalità avanzata).
    struct VoceRegistro: Identifiable, Equatable {
        let id: Int
        let ora: Date
        let testo: String
    }

    /// Quante righe tiene il registro: solo in memoria, si svuota alla chiusura dell'app.
    static let righeRegistro = 50
    /// Gli ultimi eventi del collegamento, il più vecchio per primo.
    private(set) var registro: [VoceRegistro] = []
    @ObservationIgnored private var prossimaVoce = 0

    func registra(_ testo: String) {
        registro.append(VoceRegistro(id: prossimaVoce, ora: Date(), testo: testo))
        prossimaVoce += 1
        if registro.count > Self.righeRegistro {
            registro.removeFirst(registro.count - Self.righeRegistro)
        }
    }

    init() {
        let abbinamento = Abbinamento(identita: Portachiavi.identitaMac())
        self.abbinamento = abbinamento
        improntaMac = abbinamento.identita.impronta
        gettone = abbinamento.gettone
        telefoniFidati = abbinamento.fidati
        abbinamento.suCambio = { [weak self] in
            Task { @MainActor in self?.aggiornaAbbinamento() }
        }
        monitorRete.pathUpdateHandler = { [weak self] percorso in
            // Il tipo di ogni interfaccia (Wi-Fi, cavo), per l'ordine degli indirizzi nel QR code (1.10).
            var tipi: [String: NWInterface.InterfaceType] = [:]
            for interfaccia in percorso.availableInterfaces { tipi[interfaccia.name] = interfaccia.type }
            let tipiNoti = tipi
            // Il monitor lavora già sulla coda principale: niente salto in più, il QR si rifà subito.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tipiInterfacce = tipiNoti
                self.reteCambiata()
            }
        }
        monitorRete.start(queue: .main)
        // Dopo lo stop la rete riparte e Bonjour può non annunciare più il Mac: ascolto, annuncio e cavo da capo.
        osservatoreRisveglio = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.risvegliato()
            }
        }
        cavo.suStato = { [weak self] stato in self?.statoCavo = stato }
        cavo.suRegistro = { [weak self] testo in self?.registra(testo) }
        cavo.suCanale = { [weak self] descrittore, canale in
            guard let self else {
                close(descrittore)
                return
            }
            self.accettaCavo(descrittore, canale: canale)
        }
    }

    /// Wi-Fi cambiato, cavo collegato: il QR code si rifà con i nuovi indirizzi.
    func aggiornaIndirizzi() {
        let nuovi = IndirizziLocali.ipv4(tipi: tipiInterfacce)
        guard nuovi != indirizzi else { return }
        indirizzi = nuovi
        registra(nuovi.isEmpty ? "Il Mac non è su nessuna rete" : "Rete cambiata: \(nuovi.joined(separator: ", "))")
    }

    /// Anche l'ascolto può essere caduto (rete sparita, risveglio dallo stop): con la rete nuova si riprova
    /// da soli, senza aspettare «Riprova», che si vede solo quando nessun telefono è collegato.
    /// Gli indirizzi si rileggono subito e di nuovo poco dopo: l'indirizzo dal router può arrivare
    /// un attimo dopo l'avviso del cambio di rete (1.10).
    private func reteCambiata() {
        aggiornaIndirizzi()
        if listener == nil, case .errore = rete { avvia() }
        compitoReteAssestata?.cancel()
        compitoReteAssestata = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            self.aggiornaIndirizzi()
            self.rinnovaAnnuncioSeServe()
        }
    }

    /// Rete assestata con indirizzi diversi da quelli dell'annuncio: si riapre l'ascolto, che ripubblica
    /// il servizio Bonjour, così un telefono che sta già cercando trova subito il Mac sulla rete nuova (1.12).
    /// I telefoni collegati restano collegati: le loro connessioni non dipendono dall'ascolto.
    private func rinnovaAnnuncioSeServe() {
        // Insiemi, non elenchi: lo stesso indirizzo in un altro ordine (tipi delle interfacce appena noti) non è una rete nuova.
        guard listener != nil, porta != nil, let annunciati = indirizziAnnunciati,
              Set(annunciati) != Set(indirizzi), !indirizzi.isEmpty else { return }
        registra("Annuncio in rete rinnovato per la rete nuova")
        riavviaAscolto()
    }

    /// Risveglio dallo stop (1.12): ascolto e annuncio Bonjour da capo, cavo subito, indirizzi riletti.
    private func risvegliato() {
        registra("Risveglio dallo stop: ascolto, annuncio e cavo ripartono")
        aggiornaIndirizzi()
        riavviaAscolto()
        cavo.risveglio()
        // La rete può tornare qualche secondo dopo il risveglio: il cambio di percorso rifà il resto.
        reteCambiata()
    }

    private func aggiornaAbbinamento() {
        gettone = abbinamento.gettone
        telefoniFidati = abbinamento.fidati
    }

    /// Dalle impostazioni: il telefono dovrà essere confermato di nuovo.
    func rimuoviFidato(_ telefono: TelefonoFidato) {
        abbinamento.rimuovi(telefono.impronta)
    }

    struct Controlli: Equatable, Codable {
        /// L'obiettivo appena scelto da qui, finché il telefono non conferma.
        var obiettivo: String?
        var zoom = 1.0
        var torcia = false
        var esposizione = 0.0
        var biancoAutomatico = true
        var bianco = 5000.0
        var esposizioneManuale = false
        var iso = 400.0
        var tempo = 60
    }

    private var listener: NWListener?
    private var sessione: SessioneComputer?
    /// Collegamenti arrivati ma non ancora accettati (stretta di mano, prova, fiducia): non toccano il telefono
    /// attuale finché non sono accettati, così nessuno sulla rete può farlo cadere. Qui solo per tenerli in vita.
    private var candidati: [ObjectIdentifier: SessioneComputer] = [:]
    /// Il candidato che aspetta la risposta dell'utente: una domanda alla volta.
    private var inConferma: ObjectIdentifier?
    private var compitoAttesa: Task<Void, Never>?
    private var compitoInOnda: Task<Void, Never>?
    /// Un'app sta usando la webcam virtuale.
    private var webcamInUso = false
    /// Il formato che il telefono attuale dice di mandare (messaggio `formato`), per la richiesta dei 60 fps (P12).
    @ObservationIgnored private var formatoTelefono: FormatoVideo?
    /// I fps già chiesti al telefono attuale mentre la webcam è in uso: una richiesta sola per volta.
    @ObservationIgnored private var fpsChiesti: Int?
    /// Finché un telefono è collegato macOS non mette l'app in sospensione (App Nap, funzione 20).
    @ObservationIgnored private var attivitaCollegamento: NSObjectProtocol?
    /// La notifica della batteria bassa è già partita; si riarma col caricatore o sopra il 25%.
    @ObservationIgnored private var avvisoBatteriaDato = false

    /// La porta su cui il Mac ascolta, quando è visibile in rete (serve al QR code).
    var porta: UInt16? {
        if case .visibile(let porta) = rete { return porta }
        return nil
    }

    /// Collega le immagini del telefono alla webcam virtuale (serve l'account sviluppatore a pagamento)
    /// e controlla ogni secondo se un'app la sta usando, e con quale formato.
    /// Dalla P19 parte all'avvio dell'app (WebcamLRMacApp), non con la finestra: la webcam riceve il video
    /// anche a finestra chiusa. Chiamarla di nuovo non raddoppia nulla.
    func collegaWebcamVirtuale() {
        let uscita = uscitaWebcam
        schermo.inviaImmagini { immagine in uscita.invia(immagine) }
        compitoInOnda?.cancel()
        compitoInOnda = Task { [weak self] in
            while !Task.isCancelled {
                // La lettura passa da CoreMediaIO e può richiedere tempo: fuori dalla coda principale.
                let letto = await Task.detached(priority: .utility) { () -> (Bool, UscitaWebcam.Formato?) in
                    let attivo = UscitaWebcam.leggiInOnda() ?? false
                    return (attivo, attivo ? UscitaWebcam.leggiFormato() : nil)
                }.value
                guard let self, !Task.isCancelled else { return }
                self.aggiornaInOnda(letto.0)
                self.aggiornaFormatoWebcam(letto.1)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Il formato scelto dall'app che usa la webcam virtuale (P12), nil se nessuna la usa.
    /// - 4K: l'estensione riceve 3840×2160 solo con la modalità avanzata accesa e il telefono in 4K.
    /// - 60 fps: se l'app li vuole e il telefono ne manda meno, glieli chiede una volta con `formato`
    ///   (dal computer è una richiesta, Documenti/Protocollo.md), con la stessa risoluzione e lo stesso codec.
    ///   Il telefono può non seguirla: allora l'estensione ripete le immagini e il ritmo dell'uscita resta 60.
    private func aggiornaFormatoWebcam(_ formato: UscitaWebcam.Formato?) {
        let avanzata = UserDefaults.standard.bool(forKey: Preferenze.modalitaAvanzata)
        uscitaWebcam.imposta(quattroK: avanzata && (formato?.altezza ?? 0) >= 2160)
        guard let formato else {
            fpsChiesti = nil
            return
        }
        guard formato.fps > 30, let attuale = formatoTelefono, attuale.fps < formato.fps, let sessione else { return }
        // Per non chiedere a vuoto: con `capacita.formati` si chiede al massimo ciò che il telefono sa fare
        // a questa risoluzione; risoluzione non elencata = non ci arriva.
        let fps = Self.fpsPossibili(formato.fps, larghezza: attuale.larghezza, altezza: attuale.altezza,
                                    formati: capacita?.formati)
        guard fps > attuale.fps, fpsChiesti != fps else { return }
        fpsChiesti = fps
        registra("Un'app usa la webcam a \(formato.fps) fps: chiesti al telefono \(fps) fps")
        sessione.chiedi(FormatoVideo(codec: attuale.codec, larghezza: attuale.larghezza,
                                     altezza: attuale.altezza, fps: fps))
    }

    /// I fps da chiedere: quelli voluti, ma non oltre il massimo che il telefono dichiara per questa risoluzione
    /// (in orizzontale o in verticale). Senza `formati` il telefono non lo dice: si chiede e si guarda la risposta.
    static func fpsPossibili(_ voluti: Int, larghezza: Int, altezza: Int, formati: [FormatoSupportato]?) -> Int {
        guard let formati else { return voluti }
        let massimo = formati
            .filter { ($0.larghezza == larghezza && $0.altezza == altezza) || ($0.larghezza == altezza && $0.altezza == larghezza) }
            .map(\.fpsMassimo)
            .max() ?? 0
        return min(voluti, massimo)
    }

    // MARK: - Microfono del telefono (P20)

    /// All'avvio dell'app: il livello dal microfono e, ogni 2 secondi, lo stato del driver nel sistema.
    func avviaMicrofono() {
        microfono.suLivello = { [weak self] livello in
            // Spento da qui: un livello rimasto in coda non riaccende l'indicatore.
            guard let self, self.microfonoAcceso || livello == 0 else { return }
            self.livelloMicrofono = livello
        }
        compitoMicrofono?.cancel()
        compitoMicrofono = Task { [weak self] in
            while !Task.isCancelled {
                let letta = await Task.detached(priority: .utility) { MicrofonoTelefono.leggiInstallazione() }.value
                guard let self, !Task.isCancelled else { return }
                if letta != self.installazioneMicrofono {
                    if case .nonInstallato = letta {
                        self.registra("Microfono virtuale non trovato nel sistema")
                    } else if case .nonInstallato = self.installazioneMicrofono {
                        self.registra("Microfono virtuale presente nel sistema")
                    }
                    self.installazioneMicrofono = letta
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Il telefono collegato sa mandare l'audio (`capacita.audio`).
    var telefonoMandaAudio: Bool {
        telefonoAttivo && capacita?.audio == true
    }

    /// L'interruttore «Microfono del telefono»: lo dice al telefono con `comando.audio`.
    func impostaMicrofono(_ acceso: Bool) {
        microfonoAcceso = acceso
        UserDefaults.standard.set(acceso, forKey: Preferenze.microfonoTelefono)
        registra(acceso ? "Microfono del telefono acceso" : "Microfono del telefono spento")
        if telefonoMandaAudio {
            sessione?.comanda(Comando(audio: acceso))
            audioComandato = acceso
        }
        if !acceso {
            microfono.ferma()
            audioInArrivo = false
            livelloMicrofono = 0
        }
    }

    /// Con l'interruttore acceso, chiede l'audio a ogni sessione nuova appena il telefono dice di saperlo fare.
    private func chiediAudioSeServe() {
        guard microfonoAcceso, telefonoMandaAudio, !audioComandato else { return }
        audioComandato = true
        sessione?.comanda(Comando(audio: true))
    }

    /// La finestra mini si è aperta o chiusa: lo schermo le manda le immagini solo mentre è aperta.
    func mostraMini(_ aperta: Bool) {
        miniAperta = aperta
        schermo.mostraMini(aperta)
        segnalaAnteprima()
    }

    // MARK: - Pausa intelligente

    /// Dalla finestra principale: il video si vede o no (finestra chiusa, ridotta a icona, coperta, app nascosta).
    /// La vista pulita conta come visibile: è sempre il video.
    func aggiornaVisibilitaPrincipale(_ visibile: Bool) {
        guard visibile != principaleVisibile else { return }
        principaleVisibile = visibile
        segnalaAnteprima()
    }

    /// Qualcuno guarda il video sul Mac: finestra principale visibile o finestra mini aperta.
    private var anteprimaVisibile: Bool {
        principaleVisibile || miniAperta
    }

    /// Manda `anteprima` al telefono quando cambia; `sempre` subito dopo il `benvenuto`.
    /// Il telefono va in pausa solo se anche nessuna app usa la webcam, e solo dopo 10 secondi.
    private func segnalaAnteprima(sempre: Bool = false) {
        let visibile = anteprimaVisibile
        guard sempre || visibile != anteprimaSegnalata else { return }
        let cambiata = anteprimaSegnalata != nil && visibile != anteprimaSegnalata
        anteprimaSegnalata = visibile
        guard let sessione else { return }
        sessione.segnalaAnteprima(visibile)
        if cambiata { registra(visibile ? "Anteprima di nuovo visibile" : "Anteprima nascosta") }
    }

    /// Il testo calmo sopra il video quando il telefono è in pausa (`stato.pausa`).
    static func testoPausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.facciaInGiu: "Il telefono è a faccia in giù. Giralo per riprendere."
        case MotiviPausa.nessunaApp: "Nessuna app usa la webcam. Il video riprende da solo appena serve."
        case MotiviPausa.utente: "In pausa dal telefono. Riprendi dal telefono."
        default: "Il telefono ha messo in pausa il video."
        }
    }

    /// Telefono collegato, in onda o no.
    var telefonoAttivo: Bool {
        switch collegamento {
        case .collegato, .inOnda: true
        default: false
        }
    }

    /// Dalla webcam virtuale: un'app la sta usando o no (proprietà personalizzata «inon»).
    private func aggiornaInOnda(_ attivo: Bool) {
        guard attivo != webcamInUso else { return }
        webcamInUso = attivo
        sessione?.segnala(InOnda(attivo: attivo))
        if telefonoAttivo { collegamento = attivo ? .inOnda(app: nil) : .collegato }
    }

    // MARK: - Rete

    /// Pubblica `_webcamlr._tcp` (funzione 1). Se la porta 52740 è occupata ne usa un'altra.
    func avvia(porta: NWEndpoint.Port? = NWEndpoint.Port(rawValue: Servizio.portaPredefinita)) {
        // Il cavo non dipende dalla rete: parte comunque (una volta sola).
        cavo.avvia()
        guard listener == nil else { return }
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let parametri = NWParameters(tls: nil, tcp: tcp)
            // Wi-Fi diretto (0.11), solo se acceso nelle Impostazioni: annuncio e collegamento anche via AWDL,
            // come AirDrop, per quando non c'è una rete in comune. Spento di serie: tiene la radio
            // occupata anche su un altro canale e la latenza della rete normale diventa meno stabile.
            parametri.includePeerToPeer = UserDefaults.standard.bool(forKey: Preferenze.wifiDiretto)
            // Riaprendo l'ascolto (cambio del Wi-Fi diretto) la stessa porta deve restare disponibile.
            parametri.allowLocalEndpointReuse = true
            let listener: NWListener
            if let porta {
                listener = try NWListener(using: parametri, on: porta)
            } else {
                listener = try NWListener(using: parametri)
            }

            var txt = NWTXTRecord()
            txt["v"] = String(Servizio.versioneProtocollo)
            txt["p"] = "mac"
            listener.service = NWListener.Service(name: nil, type: Servizio.tipoBonjour, domain: nil, txtRecord: txt)

            let portaFissa = porta != nil
            listener.stateUpdateHandler = { [weak self, weak listener] nuovo in
                Task { @MainActor in
                    // Un ascolto già sostituito (riaperto dopo il risveglio o la rete nuova) non tocca quello attuale.
                    guard let self, let listener, self.listener === listener else { return }
                    self.aggiorna(nuovo, portaFissa: portaFissa)
                }
            }
            listener.newConnectionHandler = { [weak self] connessione in
                // L'istante dell'accettazione, per la misura dell'avvio (1.11). Il listener lavora già sulla
                // coda principale: la sessione parte subito, senza il giro di un Task.
                let arrivo = Orologio.adesso()
                MainActor.assumeIsolated {
                    guard let self else {
                        connessione.cancel()
                        return
                    }
                    self.accetta(connessione, arrivo: arrivo)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            rete = .errore(error.localizedDescription)
            registra("Ascolto non riuscito: \(error.localizedDescription)")
            programmaRiapertura()
        }
    }

    /// Riapre l'ascolto con le impostazioni nuove (Wi-Fi diretto). I telefoni già collegati restano collegati.
    func riavviaAscolto() {
        compitoRiapertura?.cancel()
        compitoRiapertura = nil
        listener?.cancel()
        listener = nil
        avvia()
    }

    private func aggiorna(_ nuovo: NWListener.State, portaFissa: Bool) {
        switch nuovo {
        case .ready:
            rete = .visibile(porta: listener?.port?.rawValue ?? 0)
            let diretto = UserDefaults.standard.bool(forKey: Preferenze.wifiDiretto) ? ", Wi-Fi diretto acceso" : ""
            registra("Visibile in rete sulla porta \(listener?.port?.rawValue ?? 0)\(diretto)")
            aggiornaIndirizzi()
            indirizziAnnunciati = indirizzi
            attesaRiapertura = .seconds(1)
        case .failed(let errore):
            listener?.cancel()
            listener = nil
            if portaFissa, case .posix(.EADDRINUSE) = errore {
                registra("Porta \(Servizio.portaPredefinita) occupata: ne uso un'altra")
                avvia(porta: nil)
            } else {
                rete = .errore(errore.localizedDescription)
                registra("Ascolto caduto: \(errore.localizedDescription)")
                programmaRiapertura()
            }
        default:
            break
        }
    }

    /// Ascolto caduto (porta morta, rete sparita): si riprova da soli dopo 1, 2, 4… fino a 30 secondi (1.12),
    /// oltre al tentativo a ogni cambio di rete e a «Riprova».
    private func programmaRiapertura() {
        compitoRiapertura?.cancel()
        let attesa = attesaRiapertura
        attesaRiapertura = min(attesaRiapertura * 2, .seconds(30))
        compitoRiapertura = Task { [weak self] in
            try? await Task.sleep(for: attesa)
            guard let self, !Task.isCancelled, self.listener == nil else { return }
            self.compitoRiapertura = nil
            self.avvia()
        }
    }

    // MARK: - Telefono

    /// Un telefono alla volta: un nuovo collegamento sostituisce il precedente
    /// (di solito è lo stesso telefono che si riconnette), ma solo quando è accettato.
    /// Fino ad allora resta un candidato; se si chiude prima, sparisce e basta.
    private func accetta(_ connessione: NWConnection, arrivo: UInt64) {
        // Prima la sessione (la stretta di mano può cominciare), poi la riga del registro.
        avviaCandidato(TrasportoRete(connessione), arrivo: arrivo)
        registra("Collegamento in arrivo dalla rete")
    }

    /// Un canale aperto dal client usbmux: stessa strada della rete (stretta di mano, fiducia, candidati).
    /// Se il telefono è già collegato in Wi-Fi, il cavo prende il suo posto quando è accettato.
    private func accettaCavo(_ descrittore: Int32, canale: ClienteUSB.Canale) {
        let identita = avviaCandidato(TrasportoSocket(descrittore: descrittore), arrivo: Orologio.adesso())
        canaliCavo[identita] = canale
    }

    @discardableResult
    private func avviaCandidato(_ trasporto: TrasportoSessione, arrivo: UInt64) -> ObjectIdentifier {
        let nuova = SessioneComputer(trasporto: trasporto, schermo: schermo, microfono: microfono,
                                     abbinamento: abbinamento, arrivo: arrivo)
        let identita = ObjectIdentifier(nuova)
        nuova.suEvento = { [weak self] evento in
            self?.gestisci(evento, da: identita)
        }
        candidati[identita] = nuova
        nuova.avvia()
        return identita
    }

    /// «Collega via cavo»: riprende il cavo dopo una pausa.
    func collegaCavo() {
        cavo.riprendi()
    }

    /// Una sessione è finita: se veniva dal cavo, il client lo sa e decide se riprovare.
    private func chiusaSessione(_ identita: ObjectIdentifier) {
        let pausa = pausaCavo.remove(identita) != nil
        guard let canale = canaliCavo.removeValue(forKey: identita) else { return }
        cavo.sessioneFinita(canale, pausa: pausa)
    }

    private func vieneDalCavo(_ sessione: SessioneComputer?) -> Bool {
        guard let sessione else { return false }
        return canaliCavo[ObjectIdentifier(sessione)] != nil
    }

    /// Eventi di un collegamento non ancora accettato: la domanda all'utente, la chiusura, l'accettazione.
    /// Vero se l'evento è finito qui.
    private func gestisciCandidato(_ evento: SessioneComputer.Evento, da identita: ObjectIdentifier) -> Bool {
        guard let candidato = candidati[identita] else { return false }
        switch evento {
        case .ciao(_, let impronta, _):
            candidati[identita] = nil
            if inConferma == identita { inConferma = nil }
            // Consentito: il cavo non va più in pausa se questa sessione finisce.
            pausaCavo.remove(identita)
            // E il cavo funziona: se più avanti si chiude, il client riprova di nuovo ogni 2 secondi
            // (chiuso prima di qui, invece, il telefono ha rifiutato il cavo e l'attesa cresce).
            if let canale = canaliCavo[identita] { cavo.strettaRiuscita(canale) }
            // Precedenza (1.9, ridotta): se lo stesso telefono è già collegato via cavo e il cavo funziona,
            // un collegamento dalla rete non lo sostituisce: si chiude quello nuovo.
            if let attuale = sessione, attuale !== candidato, vieneDalCavo(attuale), canaliCavo[identita] == nil,
               impronta == improntaTelefono, collegamento != .riconnessione {
                registra("Collegamento dalla rete chiuso: il telefono resta sul cavo USB")
                candidato.chiudi()
                return true
            }
            // Accettato: prende il posto del telefono attuale (anche il cavo al posto del Wi-Fi).
            // Il resto dell'evento come sempre.
            if let vecchia = sessione, vecchia !== candidato {
                // Un altro telefono prende il posto di quello sul cavo: il cavo va in pausa, altrimenti dopo
                // 2 secondi riaprirebbe il canale e scalzerebbe a sua volta il telefono appena scelto.
                if vieneDalCavo(vecchia), impronta != improntaTelefono { pausaCavo.insert(ObjectIdentifier(vecchia)) }
                vecchia.chiudi()
            }
            sessione = candidato
            // Da qui il suo video va a schermo; quello delle sessioni chiuse sopra non più.
            candidato.diventaAttuale()
            return false
        case .conferma(let nome, let codice):
            // C'è già una domanda aperta per un altro telefono: per sicurezza si rifiuta,
            // così nessuno può cambiare la domanda sotto il cursore dell'utente.
            guard inConferma == nil else {
                candidato.rispondi(consentito: false)
                return true
            }
            inConferma = identita
            registra("Telefono nuovo, «\(nome)»: chiedo conferma con il codice")
            // Un telefono del cavo non consentito (o senza risposta) non deve ripresentarsi ogni 2 secondi.
            if canaliCavo[identita] != nil { pausaCavo.insert(identita) }
            // Prima la notifica (solo se WebcamLR è in secondo piano), poi l'app davanti con la domanda.
            Notifiche.condivise.richiestaConsenso(nome)
            finestraConferma.mostra(nome: nome, codice: codice) { [weak self] consentito in
                self?.rispondiConferma(consentito, da: identita)
            }
        case .confermaFinita:
            if inConferma == identita { chiudiConferma() }
        case .chiusa:
            candidati[identita] = nil
            registra("Collegamento chiuso prima di essere accettato")
            chiusaSessione(identita)
            // Il telefono se n'è andato mentre si aspettava la conferma: la domanda sparisce.
            if inConferma == identita { chiudiConferma() }
        default:
            break
        }
        return true
    }

    /// Comandi della fotocamera verso il telefono collegato.
    func comanda(_ comando: Comando) {
        sessione?.comanda(comando)
    }

    // MARK: - Comandi rapidi (dal pannello e dai tasti, funzione 25)

    /// Passo dello zoom per i tasti + e −.
    static let passoZoom = 0.5

    /// Cambia obiettivo; lo zoom riparte da 1, come fa il telefono.
    func scegliObiettivo(_ obiettivo: String) {
        guard telefonoAttivo, capacita?.obiettivi.contains(obiettivo) == true else { return }
        controlli.obiettivo = obiettivo
        controlli.zoom = 1
        comanda(Comando(obiettivo: obiettivo))
    }

    /// L'obiettivo numero `indice` (da 0) nell'ordine in cui il telefono li elenca.
    func scegliObiettivo(numero indice: Int) {
        guard let obiettivi = capacita?.obiettivi, obiettivi.indices.contains(indice) else { return }
        scegliObiettivo(obiettivi[indice])
    }

    /// Zoom avanti o indietro di `passo`, entro i limiti dell'obiettivo attuale.
    func cambiaZoom(di passo: Double) {
        guard telefonoAttivo, let massimo = capacita?.zoomMassimo, massimo > 1 else { return }
        let nuovo = min(max(((controlli.zoom + passo) * 10).rounded() / 10, 1), massimo)
        guard nuovo != controlli.zoom else { return }
        controlli.zoom = nuovo
        comanda(Comando(zoom: nuovo))
    }

    func fuocoAutomatico() {
        guard telefonoAttivo else { return }
        comanda(Comando(fuoco: "continuo"))
    }

    /// Etichetta breve di un obiettivo, come sul telefono.
    static func etichetta(obiettivo: String) -> String {
        switch obiettivo {
        case "grandangolo": "0,5×"
        case "principale": "1×"
        case "tele": "Tele"
        case "frontale": "Frontale"
        default: obiettivo.capitalized
        }
    }

    /// Nome completo di un obiettivo, come nel glossario: «Grandangolo 0,5×», «Principale 1×».
    static func nome(obiettivo: String) -> String {
        switch obiettivo {
        case "grandangolo": "Grandangolo 0,5×"
        case "principale": "Principale 1×"
        case "tele": "Tele"
        case "frontale": "Frontale"
        default: obiettivo.capitalized
        }
    }

    // MARK: - Effetti (pacchetto funzioni)

    /// Quanto aspettano i cursori prima di mandare il comando: uno solo mentre si trascina, non uno per pixel.
    static let attesaCursori: Duration = .milliseconds(100)
    /// I testi (nome e ruolo della scritta) partono quando si smette di scrivere.
    static let attesaTesti: Duration = .milliseconds(600)
    /// Per quanto lo `stato` del telefono non sovrascrive un effetto appena cambiato da qui.
    static let precedenzaLocale: Duration = .milliseconds(1500)

    /// Un effetto è cambiato sul Mac (il valore è già in `effetti`): il comando parte subito, oppure dopo
    /// `attesa` se nel frattempo non cambia ancora. `comando` legge `effetti` al momento dell'invio.
    func mandaEffetto(_ chiave: String, attesa: Duration? = nil, _ comando: @escaping (Effetti) -> Comando) {
        modificheEffetti[chiave] = .now
        inviiInAttesa[chiave]?.cancel()
        inviiInAttesa[chiave] = nil
        guard let attesa else {
            comanda(comando(effetti))
            return
        }
        inviiInAttesa[chiave] = Task { [weak self] in
            try? await Task.sleep(for: attesa)
            guard let self, !Task.isCancelled else { return }
            self.inviiInAttesa[chiave] = nil
            self.modificheEffetti[chiave] = .now
            self.comanda(comando(self.effetti))
        }
    }

    /// «Azzera» delle regolazioni: tutte e quattro a 0 in un solo comando.
    func azzeraRegolazioni() {
        let chiavi = [Effetti.chiaveLuminosita, Effetti.chiaveContrasto, Effetti.chiaveSaturazione, Effetti.chiaveNitidezza]
        for chiave in chiavi {
            inviiInAttesa[chiave]?.cancel()
            inviiInAttesa[chiave] = nil
            modificheEffetti[chiave] = .now
        }
        effetti.luminosita = 0
        effetti.contrasto = 0
        effetti.saturazione = 0
        effetti.nitidezza = 0
        comanda(Comando(regolazioni: Regolazioni(luminosita: 0, contrasto: 0, saturazione: 0, nitidezza: 0)))
    }

    /// Lo `stato` del telefono porta gli effetti attuali, anche quelli cambiati sul telefono: l'interfaccia li segue,
    /// tranne quelli appena toccati da qui (il comando può non essere ancora arrivato).
    private func allineaEffetti(_ stato: StatoTelefono) {
        let adesso = ContinuousClock.now
        let recenti = Set(modificheEffetti.filter { adesso - $0.value < Self.precedenzaLocale }.keys)
            .union(inviiInAttesa.keys)
        func libero(_ chiave: String) -> Bool { !recenti.contains(chiave) }

        if let filtro = stato.filtro, libero(Effetti.chiaveFiltro) {
            // Un filtro sconosciuto si tratta come «naturale».
            effetti.filtro = Filtri.tutti.contains(filtro) || capacita?.filtri?.contains(filtro) == true ? filtro : Filtri.naturale
        }
        if let regolazioni = stato.regolazioni {
            if let valore = regolazioni.luminosita, libero(Effetti.chiaveLuminosita) { effetti.luminosita = valore }
            if let valore = regolazioni.contrasto, libero(Effetti.chiaveContrasto) { effetti.contrasto = valore }
            if let valore = regolazioni.saturazione, libero(Effetti.chiaveSaturazione) { effetti.saturazione = valore }
            if let valore = regolazioni.nitidezza, libero(Effetti.chiaveNitidezza) { effetti.nitidezza = valore }
        }
        if let sfondo = stato.sfondo, libero(Effetti.chiaveSfondo) {
            // Uno sfondo sconosciuto si tratta come «nessuno».
            effetti.sfondo = [ModiSfondo.sfocato, ModiSfondo.sostituito].contains(sfondo) ? sfondo : ModiSfondo.nessuno
        }
        if let valore = stato.intensitaSfondo, libero(Effetti.chiaveIntensitaSfondo) { effetti.intensitaSfondo = min(max(valore, 0), 1) }
        if let valore = stato.pelle, libero(Effetti.chiavePelle) { effetti.pelle = min(max(valore, 0), 1) }
        if let valore = stato.inquadratura, libero(Effetti.chiaveInquadratura) { effetti.inquadratura = valore }
        if let valore = stato.luceVolto, libero(Effetti.chiaveLuceVolto) { effetti.luceVolto = valore }
        if let scritta = stato.scritta, libero(Effetti.chiaveScritta) {
            // Nome vuoto = nessuna scritta: i campi restano come li ha scritti l'utente.
            if scritta.nome.isEmpty {
                effetti.scrittaMostrata = false
            } else {
                effetti.scrittaMostrata = true
                effetti.nome = scritta.nome
                effetti.ruolo = scritta.ruolo ?? ""
            }
        }
        if let valore = stato.doppiaVista, libero(Effetti.chiaveDoppiaVista) { effetti.doppiaVista = valore }
        if let valore = stato.postura, libero(Effetti.chiavePostura) { effetti.postura = valore }
    }

    /// Un altro telefono, o nessuno: effetti di serie e gobbo da rimandare (il testo resta nell'editor).
    private func azzeraEffettiEGobbo() {
        inviiInAttesa.values.forEach { $0.cancel() }
        inviiInAttesa = [:]
        modificheEffetti = [:]
        effetti = Effetti()
        testoGobboInviato = nil
        gobboAttivo = false
        posizioneGobbo = 0
    }

    // MARK: - Gobbo (pacchetto funzioni)

    /// Il telefono attuale sa fare il gobbo.
    var gobboDisponibile: Bool {
        telefonoAttivo && capacita?.gobbo == true
    }

    /// Il testo da mandare, già tagliato al massimo del protocollo (il telefono taglierebbe comunque).
    private var testoGobboDaInviare: String {
        String(gobbo.testo.prefix(Gobbo.lunghezzaMassima))
    }

    /// Nell'editor c'è un testo diverso da quello che ha il telefono.
    var testoGobboCambiato: Bool {
        testoGobboDaInviare != testoGobboInviato
    }

    /// «Avvia» o «Pausa». Avviando con un testo nuovo lo si manda tutto: un testo nuovo riparte dall'inizio.
    func avviaOFermaGobbo() {
        guard gobboDisponibile else { return }
        if gobboAttivo {
            comandaGobbo(Gobbo(attivo: false))
            gobboAttivo = false
        } else if testoGobboCambiato {
            guard !gobbo.testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            mandaTestoGobbo(attivo: true)
        } else {
            comandaGobbo(Gobbo(attivo: true))
            gobboAttivo = true
        }
    }

    /// Manda testo, velocità e dimensione insieme: il gobbo riparte dall'inizio, fermo o in movimento.
    func mandaTestoGobbo(attivo: Bool) {
        guard gobboDisponibile else { return }
        let testo = testoGobboDaInviare
        comandaGobbo(Gobbo(testo: testo, velocita: gobbo.velocita, attivo: attivo, dimensione: gobbo.dimensione))
        testoGobboInviato = testo
        gobboAttivo = attivo
        posizioneGobbo = 0
        registra("Gobbo: testo mandato al telefono (\(testo.count) caratteri)")
    }

    /// «Dall'inizio»: con un testo nuovo lo manda, altrimenti salta all'inizio.
    func gobboDallInizio() {
        guard gobboDisponibile else { return }
        if testoGobboCambiato {
            mandaTestoGobbo(attivo: gobboAttivo)
        } else {
            comandaGobbo(Gobbo(posizione: 0))
            posizioneGobbo = 0
        }
    }

    private static let chiaveGobbo = "gobbo"

    /// Manda un `gobbo` cambiato da qui: per un attimo lo `stato` non sovrascrive «Avvia/Pausa» e la posizione
    /// (uno `stato` partito prima del comando direbbe ancora il valore vecchio).
    private func comandaGobbo(_ comando: Gobbo) {
        modificheEffetti[Self.chiaveGobbo] = .now
        sessione?.mandaGobbo(comando)
    }

    /// Il gobbo è stato comandato da qui da poco: lo `stato` aspetta.
    private var gobboAppenaComandato: Bool {
        guard let ultima = modificheEffetti[Self.chiaveGobbo] else { return false }
        return ContinuousClock.now - ultima < Self.precedenzaLocale
    }

    /// Velocità e dimensione: il valore è già in `gobbo`; arrivano al telefono solo se ha già un testo
    /// (altrimenti partono insieme al testo).
    func mandaVelocitaGobbo() {
        inviiInAttesa["gobboVelocita"]?.cancel()
        inviiInAttesa["gobboVelocita"] = Task { [weak self] in
            try? await Task.sleep(for: Self.attesaCursori)
            guard let self, !Task.isCancelled else { return }
            self.inviiInAttesa["gobboVelocita"] = nil
            guard self.gobboDisponibile, self.testoGobboInviato != nil else { return }
            self.sessione?.mandaGobbo(Gobbo(velocita: self.gobbo.velocita))
        }
    }

    func mandaDimensioneGobbo() {
        guard gobboDisponibile, testoGobboInviato != nil else { return }
        sessione?.mandaGobbo(Gobbo(dimensione: gobbo.dimensione))
    }

    // MARK: - Profili della fotocamera (funzione 23)

    private static let chiaveProfili = "profiliFotocamera"

    /// I comandi della fotocamera salvati per nome, sul Mac: valgono con qualsiasi telefono.
    private(set) var profili: [String: Controlli] = Ricevitore.leggiProfili()

    func salvaProfilo(_ nome: String) {
        var salvati = controlli
        // Si salva l'obiettivo che si vede selezionato: quello in attesa di conferma, se c'è, altrimenti quello in uso.
        salvati.obiettivo = controlli.obiettivo ?? statoTelefono?.obiettivo
        profili[nome] = salvati
        scriviProfili()
    }

    func eliminaProfilo(_ nome: String) {
        profili[nome] = nil
        scriviProfili()
    }

    /// Manda al telefono tutti i comandi del profilo in un solo messaggio.
    func applicaProfilo(_ nome: String) {
        guard let profilo = profili[nome] else { return }
        var obiettivo = profilo.obiettivo
        if let scelto = obiettivo, capacita?.obiettivi.contains(scelto) != true { obiettivo = nil }
        let manuale = profilo.esposizioneManuale && capacita?.isoMinimo != nil
        // Stesso obiettivo: il massimo è noto. Se cambia, ci pensa il telefono con i limiti del nuovo.
        var zoom = profilo.zoom
        if obiettivo == nil || obiettivo == statoTelefono?.obiettivo, let massimo = capacita?.zoomMassimo {
            zoom = min(max(zoom, 1), max(massimo, 1))
        }
        comanda(Comando(obiettivo: obiettivo, zoom: zoom,
                        torcia: capacita?.torcia == true ? profilo.torcia : nil,
                        esposizione: profilo.esposizione,
                        bianco: profilo.biancoAutomatico ? 0 : Int(profilo.bianco),
                        iso: manuale ? profilo.iso : 0, tempo: manuale ? profilo.tempo : 0))
        let torcia = controlli.torcia
        controlli = profilo
        controlli.obiettivo = obiettivo
        controlli.zoom = zoom
        // Se la torcia non è stata mandata, resta com'era.
        if capacita?.torcia != true { controlli.torcia = torcia }
        controlli.esposizioneManuale = manuale
    }

    private static func leggiProfili() -> [String: Controlli] {
        guard let dati = UserDefaults.standard.data(forKey: chiaveProfili) else { return [:] }
        return (try? JSONDecoder().decode([String: Controlli].self, from: dati)) ?? [:]
    }

    private func scriviProfili() {
        if let dati = try? JSONEncoder().encode(profili) {
            UserDefaults.standard.set(dati, forKey: Self.chiaveProfili)
        }
    }

    /// Chiusura voluta: il telefono riceve l'arrivederci e non si ricollega da solo.
    func scollega() {
        if sessione != nil { registra("Scollegato dal Mac") }
        // Via cavo il Mac riaprirebbe il canale da solo: il cavo resta in pausa fino a «Collega via cavo».
        if let sessione, vieneDalCavo(sessione) { pausaCavo.insert(ObjectIdentifier(sessione)) }
        sessione?.chiudi()
        sessione = nil
        compitoAttesa?.cancel()
        dimentica()
    }

    private func gestisci(_ evento: SessioneComputer.Evento, da identita: ObjectIdentifier) {
        if gestisciCandidato(evento, da: identita) { return }
        guard let sessione, ObjectIdentifier(sessione) == identita else {
            // Una sessione sostituita (o chiusa per la precedenza del cavo) che finisce adesso.
            if case .chiusa = evento { chiusaSessione(identita) }
            return
        }
        switch evento {
        case .ciao(let ciao, let impronta, let via):
            compitoAttesa?.cancel()
            if telefono == nil || improntaTelefono != impronta {
                // Un altro telefono: niente di quello precedente (capacità, stato, grafico, avviso della batteria).
                controlli = Controlli()
                capacita = nil
                statoTelefono = nil
                storicoLatenza = []
                avvisoBatteriaDato = false
                // Gli effetti di un altro telefono arrivano con il suo primo `stato`; il testo del gobbo
                // resta nell'editor, ma questo telefono non l'ha ancora ricevuto.
                azzeraEffettiEGobbo()
            } else {
                // Lo stesso telefono torna: forse con una sessione nuova, ripartita in automatico.
                // Gli si rimanda quello che il Mac mostra, così i due restano d'accordo.
                let attuali = controlli
                sessione.comanda(Comando(obiettivo: attuali.obiettivo, zoom: attuali.zoom, torcia: attuali.torcia, esposizione: attuali.esposizione,
                                         bianco: attuali.biancoAutomatico ? 0 : Int(attuali.bianco),
                                         iso: attuali.esposizioneManuale ? attuali.iso : 0,
                                         tempo: attuali.esposizioneManuale ? attuali.tempo : 0))
                // Gli effetti no: restano salvati sul telefono e tornano col primo `stato`. Il gobbo invece vive
                // sul telefono solo per la sessione: si rimanda completo, dalla posizione dell'ultimo `stato`.
                if let testo = testoGobboInviato {
                    sessione.mandaGobbo(Gobbo(testo: testo, velocita: gobbo.velocita, attivo: gobboAttivo,
                                              dimensione: gobbo.dimensione, posizione: posizioneGobbo))
                }
            }
            registra("«\(ciao.nome)» collegato via \(via.testo)")
            // Sessione nuova: il formato arriva con il suo messaggio `formato`, la richiesta dei fps si può rifare.
            // Anche l'audio: si richiede con la prima `capacita` (o subito, se è lo stesso telefono di prima).
            formatoTelefono = nil
            audioComandato = false
            microfono.ferma()
            fpsChiesti = nil
            // La misura dell'avvio è di questa sessione: arriva con il suo primo fotogramma a schermo.
            tempoAvvio = nil
            if telefono == nil { Notifiche.condivise.telefonoCollegato(ciao.nome) }
            telefono = ciao
            improntaTelefono = impronta
            tipoCollegamento = via
            tieniSveglia(true)
            collegamento = webcamInUso ? .inOnda(app: nil) : .collegato
            sessione.segnala(InOnda(attivo: webcamInUso))
            // Subito dopo il `benvenuto` (già partito dalla sessione): se nessuno guarda e nessuna app usa
            // la webcam, il telefono può andare in pausa.
            segnalaAnteprima(sempre: true)
            chiediAudioSeServe()
        case .conferma, .confermaFinita:
            // Solo i candidati chiedono conferma (sopra).
            break
        case .formato(let formato):
            formatoTelefono = formato
            registra("Formato: \(formato.codec == .hevc ? "HEVC" : "H.264") \(formato.larghezza)×\(formato.altezza) a \(formato.fps) fps")
        case .stato(let stato):
            if stato.pausa != statoTelefono?.pausa {
                registra(stato.pausa.map { "Il telefono è in pausa (\($0))" } ?? "Il telefono riprende il video")
            }
            statoTelefono = stato
            controllaBatteria(stato)
            if controlli.obiettivo == stato.obiettivo { controlli.obiettivo = nil }
            allineaEffetti(stato)
            if gobboAppenaComandato {
                // Il comando appena partito può non essere ancora arrivato: si aspetta il prossimo `stato`.
            } else if let statoGobbo = stato.gobbo {
                gobboAttivo = statoGobbo.attivo
                posizioneGobbo = min(max(statoGobbo.posizione, 0), 1)
            } else {
                // Nessun gobbo sul telefono: fermo. La posizione resta, per un eventuale invio di nuovo.
                gobboAttivo = false
            }
        case .capacita(let nuove):
            capacita = nuove
            // Obiettivo senza ISO manuale: l'interruttore sparisce e torna il cursore dell'esposizione.
            if nuove.isoMinimo == nil { controlli.esposizioneManuale = false }
            chiediAudioSeServe()
        case .statistiche(let nuove):
            statistiche = nuove
            audioInArrivo = nuove.pacchettiAudio > 0
            if !audioInArrivo { livelloMicrofono = 0 }
            storicoLatenza.append(nuove.latenzaMs)
            if storicoLatenza.count > GraficoLatenza.secondi {
                storicoLatenza.removeFirst(storicoLatenza.count - GraficoLatenza.secondi)
            }
        case .avvio(let testo, let riga):
            tempoAvvio = testo
            registra(riga)
        case .silenzio:
            registra("Nessun dato da 3 secondi")
            collegamento = .riconnessione
        case .ripresa:
            registra("I dati arrivano di nuovo")
            collegamento = webcamInUso ? .inOnda(app: nil) : .collegato
        case .chiusa:
            self.sessione = nil
            formatoTelefono = nil
            audioComandato = false
            audioInArrivo = false
            livelloMicrofono = 0
            microfono.ferma()
            fpsChiesti = nil
            registra("Collegamento chiuso")
            chiusaSessione(identita)
            guard telefono != nil else {
                collegamento = .nessunTelefono
                return
            }
            collegamento = .riconnessione
            statistiche.fps = 0
            statistiche.megabitAlSecondo = 0
            compitoAttesa?.cancel()
            compitoAttesa = Task { [weak self] in
                try? await Task.sleep(for: Self.attesaRiconnessione)
                guard let self, !Task.isCancelled, self.sessione == nil else { return }
                if let nome = self.telefono?.nome { Notifiche.condivise.telefonoPerso(nome) }
                self.registra("Il telefono non è tornato entro 15 secondi")
                self.dimentica()
            }
        }
    }

    /// «Consenti» o «Non consentire»: vale solo per la sessione che l'ha chiesto.
    private func rispondiConferma(_ consentito: Bool, da identita: ObjectIdentifier) {
        Notifiche.condivise.ritiraRichiestaConsenso()
        guard inConferma == identita else { return }
        inConferma = nil
        registra(consentito ? "Telefono consentito" : "Telefono non consentito")
        candidati[identita]?.rispondi(consentito: consentito)
    }

    private func chiudiConferma() {
        inConferma = nil
        finestraConferma.chiudi()
        Notifiche.condivise.ritiraRichiestaConsenso()
    }

    /// Una notifica sola quando la batteria scende al 20% senza caricatore (funzione 22).
    private func controllaBatteria(_ stato: StatoTelefono) {
        if stato.inCarica || stato.batteria > 25 {
            avvisoBatteriaDato = false
        } else if stato.batteria >= 0, stato.batteria <= 20, !avvisoBatteriaDato, let nome = telefono?.nome {
            avvisoBatteriaDato = true
            Notifiche.condivise.batteriaBassa(nome, percentuale: stato.batteria)
        }
    }

    /// Niente App Nap né timer rallentati mentre arriva il video: la latenza resta costante (funzione 20).
    /// Si tiene anche durante la riconnessione, fino a quando il telefono viene dimenticato.
    private func tieniSveglia(_ sveglia: Bool) {
        if sveglia, attivitaCollegamento == nil {
            attivitaCollegamento = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical], reason: "Video dal telefono in tempo reale")
        } else if !sveglia, let attivita = attivitaCollegamento {
            ProcessInfo.processInfo.endActivity(attivita)
            attivitaCollegamento = nil
        }
    }

    private func dimentica() {
        tieniSveglia(false)
        avvisoBatteriaDato = false
        telefono = nil
        improntaTelefono = nil
        tipoCollegamento = nil
        statoTelefono = nil
        statistiche = Statistiche()
        tempoAvvio = nil
        storicoLatenza = []
        capacita = nil
        controlli = Controlli()
        azzeraEffettiEGobbo()
        collegamento = .nessunTelefono
        schermo.svuota()
    }
}
