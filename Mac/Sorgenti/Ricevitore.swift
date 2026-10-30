import AppKit
import AVFoundation
import Foundation
import Network
import Observation
import Stile
import WebcamLRProtocollo

/// Il cuore dell'app Mac: si annuncia in rete, accetta i telefoni e tiene lo stato per l'interfaccia.
/// Dalla P21 «Più telefoni insieme» tiene fino a `massimoTelefoni` telefoni diversi (`TelefonoCollegato`), ognuno
/// con il suo video; uno solo, quello `attivo`, va nella webcam virtuale, nel microfono, nella finestra mini,
/// nelle foto e nei comandi del pannello. Con un telefono solo tutto è come prima.
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
    /// Con l'ultima pausa «sottofondo» (Protocollo.md, «Pausa intelligente»): quanto si aspetta il telefono, muto
    /// o caduto, prima di dimenticarlo. Lo stesso tempo chiude la sessione muta (`SessioneComputer.silenzioSottofondo`).
    static let attesaSottofondo: Duration = .seconds(600)

    /// Quanti telefoni diversi insieme (P21). Il codice regge di più; per ora due.
    nonisolated static let massimoTelefoni = 2

    private let uscitaWebcam = UscitaWebcam()
    /// La finestra mini: un livello solo, con le immagini del telefono scelto (P21).
    private let uscitaMini = UscitaMini()
    /// Al posto del video quando non c'è nessun telefono: un riquadro nero.
    private let schermoVuoto = Schermo()
    /// Il microfono del telefono verso «WebcamLR (microphone)» (P20): segue il telefono scelto (P21).
    private let microfono = MicrofonoTelefono()
    /// Il driver del microfono nel sistema: installato? un'app lo usa? Riletto ogni 2 secondi.
    private(set) var installazioneMicrofono: MicrofonoTelefono.Installazione = .nonInstallato
    /// L'utente vuole il microfono del telefono acceso (resta da una volta all'altra).
    private(set) var microfonoAcceso = UserDefaults.standard.bool(forKey: Preferenze.microfonoTelefono)
    /// Nell'ultimo secondo è arrivato audio dal telefono scelto.
    private(set) var audioInArrivo = false
    /// Da 0 a 1, per l'indicatore di livello.
    private(set) var livelloMicrofono = 0.0
    @ObservationIgnored private var compitoMicrofono: Task<Void, Never>?
    private(set) var rete: StatoRete = .fermo

    /// I telefoni collegati (o in riconnessione), nell'ordine in cui sono arrivati.
    private(set) var telefoni: [TelefonoCollegato] = []
    /// Il telefono scelto per webcam, microfono, finestra mini, foto e comandi («Nella webcam»).
    private(set) var idAttivo: UUID?
    /// I posti per le sessioni, controllati prima del `benvenuto` (P21).
    private let posti = PostiTelefoni(massimo: Ricevitore.massimoTelefoni)
    /// Un avviso sul telefono sopra il video per qualche secondo: «Già collegati due telefoni», «Lezione» con la frontale.
    private(set) var avvisoTelefoni: String?
    @ObservationIgnored private var compitoAvvisoTelefoni: Task<Void, Never>?
    /// Passo 7 (mac.md 14): da `attesaPrimoTelefono` la rete è pronta (ascolto aperto, un indirizzo) e nessun telefono
    /// è arrivato. Sotto il QR compare «Il telefono non trova il Mac?» con il firewall e la Rete locale.
    private(set) var nessunTelefonoDaTempo = false
    @ObservationIgnored private var compitoAttesaTelefono: Task<Void, Never>?
    static let attesaPrimoTelefono: Duration = .seconds(30)
    /// Il nome del telefono che non è tornato (15 secondi, o 10 minuti in sottofondo): un banner fisso sopra il video,
    /// finché non lo chiudi o quel telefono si ricollega. A finestra chiusa c'è anche la notifica.
    private(set) var telefonoNonTornato: String?
    /// Quando ogni telefono rifiutato è stato annunciato: dal cavo riprova da solo, l'avviso no.
    @ObservationIgnored private var ultimiRifiuti: [String: ContinuousClock.Instant] = [:]
    /// Chiamato quando l'utente sceglie un altro telefono, mentre quello di prima è ancora lo scelto:
    /// le Riprese chiudono e salvano la registrazione in corso (P21, come su Windows).
    @ObservationIgnored var primaDelCambioTelefono: (@MainActor () -> Void)?
    /// Chiamato quando il telefono scelto se ne va del tutto (non tornato in 15 secondi, o «Scollega»):
    /// le Riprese chiudono e salvano la registrazione, che altrimenti resterebbe «in corso» senza immagini.
    @ObservationIgnored var primaDiDimenticareLoScelto: (@MainActor () -> Void)?
    /// Chiamato quando il telefono scelto va in pausa «sottofondo»: può restare via fino a 10 minuti, quindi le Riprese
    /// chiudono e salvano la registrazione in corso invece di lasciarla aperta senza immagini.
    @ObservationIgnored var sceltoInSottofondo: (@MainActor () -> Void)?
    /// Prima di un comando che ferma la registrazione (punto 7): le Riprese chiedono se stai registrando
    /// (`Riprese.confermaSeFerma`). Vero se il comando può andare avanti.
    @ObservationIgnored var primaDiUnComandoCheFerma: (@MainActor (Riprese.ComandoCheFerma) -> Bool)?
    /// Stai registrando (le Riprese): «Scollega» chiede prima (punto 8).
    @ObservationIgnored var staRegistrando: (@MainActor () -> Bool)?

    /// Il telefono scelto; se la scelta non vale più, il primo.
    var attivo: TelefonoCollegato? {
        telefoni.first { $0.id == idAttivo } ?? telefoni.first
    }

    /// Gli altri telefoni collegati (con due telefoni: quello della miniatura).
    var altri: [TelefonoCollegato] {
        let scelto = attivo
        return telefoni.filter { $0 !== scelto }
    }

    // Lo stato del telefono scelto, come prima della P21: l'interfaccia lo legge da qui.

    var collegamento: FaseCollegamento { attivo?.collegamento ?? .nessunTelefono }
    var telefono: Ciao? { attivo?.telefono }
    /// Come è collegato il telefono scelto: Wi-Fi, cavo USB, Wi-Fi diretto, cavo di rete (1.2).
    var tipoCollegamento: TipoCollegamento? { attivo?.tipoCollegamento }
    var statoTelefono: StatoTelefono? { attivo?.statoTelefono }
    /// Il telefono scelto è in pausa «sottofondo»: niente «Riconnessione» per 10 minuti, anche se tace o cade.
    var inSottofondo: Bool { attivo?.inSottofondo ?? false }
    var statistiche: Statistiche { attivo?.statistiche ?? Statistiche() }
    /// «Avvio: 0,9 s» (1.11); nil finché il video non è a schermo.
    var tempoAvvio: String? { attivo?.tempoAvvio }
    /// La latenza di ogni secondo, al massimo gli ultimi 60, per il grafico (funzione 31).
    var storicoLatenza: [Int?] { attivo?.storicoLatenza ?? [] }
    /// Cosa si può comandare sul telefono scelto; nil finché il telefono non lo dice.
    var capacita: Capacita? { attivo?.capacita }
    /// I comandi della fotocamera del telefono scelto: quelli mandati da qui, riallineati allo `stato` del telefono.
    var controlli: Controlli {
        get { attivo?.controlli ?? Controlli() }
        set { attivo?.controlli = newValue }
    }
    /// Gli effetti come li mostra il Mac (pacchetto effetti). Con gli effetti sul computer (`effettiSulComputer`) sono
    /// quelli del motore del Mac (`effettiComputer`, salvati nelle preferenze del Mac): l'interfaccia legge e scrive
    /// qui, e il motore li applica subito. Solo «Volto e scrivania» e la postura restano del telefono.
    /// Senza gli effetti sul computer: quelli del telefono scelto, come prima.
    var effetti: Effetti {
        get {
            guard Self.effettiSulComputer else { return attivo?.effetti ?? Effetti() }
            var risultato = effettiComputer
            risultato.doppiaVista = attivo?.effetti.doppiaVista ?? false
            risultato.postura = attivo?.effetti.postura ?? false
            return risultato
        }
        set {
            guard Self.effettiSulComputer else {
                attivo?.effetti = newValue
                return
            }
            attivo?.effetti.doppiaVista = newValue.doppiaVista
            attivo?.effetti.postura = newValue.postura
            var delComputer = newValue
            delComputer.doppiaVista = false
            delComputer.postura = false
            if delComputer != effettiComputer { effettiComputer = delComputer }
        }
    }

    /// L'interruttore interno (MotoreEffetti.swift): vero = gli effetti di immagine li fa il Mac. Allora i comandi
    /// degli effetti di immagine non vanno più al telefono, che alla prima `capacita` riceve `comando.effettiSulComputer`
    /// e fa da telecomando (`decidiEffetti`), o, se è di prima, l'ordine di spegnere i suoi (`spegniEffettiDelTelefono`);
    /// le immagini caricate restano sul Mac (niente pacchetto immagine).
    nonisolated static var effettiSulComputer: Bool { MotoreEffetti.effettiSulComputer }

    /// Gli effetti del motore del Mac, con gli stessi campi che il telefono mostrava: restano da una volta all'altra.
    var effettiComputer: Effetti = Ricevitore.leggiEffettiComputer() {
        didSet {
            if let dati = try? JSONEncoder().encode(effettiComputer) {
                UserDefaults.standard.set(dati, forKey: Preferenze.effettiComputer)
            }
            aggiornaMotore()
        }
    }

    /// Le scelte salvate; la prima volta il calore a 0,3, come lo propone il telefono.
    private static func leggiEffettiComputer() -> Effetti {
        if let dati = UserDefaults.standard.data(forKey: Preferenze.effettiComputer),
           let salvati = try? JSONDecoder().decode(Effetti.self, from: dati) {
            return salvati
        }
        var nuovi = Effetti()
        nuovi.calore = 0.3
        return nuovi
    }
    /// Il gobbo preparato sul Mac: il testo resta anche senza telefono, e va al telefono scelto. Testo, velocità e
    /// dimensione restano nelle preferenze da un avvio all'altro (passo 9, M25).
    var gobbo: GobboComputer = Ricevitore.leggiGobbo() {
        didSet {
            guard gobbo != oldValue, let dati = try? JSONEncoder().encode(gobbo) else { return }
            UserDefaults.standard.set(dati, forKey: Preferenze.gobbo)
        }
    }

    /// Il gobbo salvato; la prima volta vuoto, con velocità e dimensione di serie.
    private static func leggiGobbo() -> GobboComputer {
        guard let dati = UserDefaults.standard.data(forKey: Preferenze.gobbo),
              let salvato = try? JSONDecoder().decode(GobboComputer.self, from: dati) else { return GobboComputer() }
        return salvato
    }
    /// Il testo del gobbo già mandato al telefono scelto; nil se non ne ha ancora ricevuto uno.
    var testoGobboInviato: String? { attivo?.testoGobboInviato }
    /// Dall'ultimo `stato.gobbo`: scorre o no, e dove è arrivato (da 0 a 1).
    var gobboAttivo: Bool { attivo?.gobboAttivo ?? false }
    var posizioneGobbo: Double { attivo?.posizioneGobbo ?? 0 }
    /// Lo schermo del telefono scelto: l'anteprima grande, le foto, la registrazione.
    var schermo: Schermo { attivo?.schermo ?? schermoVuoto }
    /// Il livello della finestra mini.
    var livelloMini: AVSampleBufferDisplayLayer { uscitaMini.livello }

    /// La finestra mini è aperta (funzione 21).
    private(set) var miniAperta = false
    /// La finestra principale mostra il video (aperta, non ridotta a icona né coperta del tutto).
    @ObservationIgnored private var principaleVisibile = false
    /// La miniatura dell'altro telefono si vede nell'anteprima (P21).
    @ObservationIgnored private var miniaturaVisibile = false
    /// Riempi o adatta (funzione 30), per gli schermi creati dopo.
    @ObservationIgnored private var riempi = false
    /// La webcam virtuale è collegata (`collegaWebcamVirtuale`): solo allora le immagini le vanno mandate.
    @ObservationIgnored private var webcamCollegata = false

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
    /// Il cavo è in pausa perché questo telefono (codice di sicurezza) preferisce il Wi-Fi (scelta del collegamento):
    /// riparte quando la sua preferenza cambia o quando il suo Wi-Fi si perde, per non perdere il video.
    @ObservationIgnored private var cavoInPausaPer: String?
    /// In «Automatico», dopo un cambio di strada, per quanto non si cambia di nuovo da soli (niente sbalzi).
    static let pausaCambioStrada: Duration = .seconds(30)

    /// Una riga del registro del collegamento (1.5).
    struct VoceRegistro: Identifiable, Equatable {
        let id: Int
        let ora: Date
        let testo: String
        /// Il telefono dell'evento, solo quando ne sono collegati più di uno (P21).
        var telefono: String?

        /// «14:02:31  iPhone di Ledion · Collegato via Wi-Fi»: per «Copia» e «Segnala un bug».
        var riga: String {
            let ora = ora.formatted(date: .omitted, time: .standard)
            guard let telefono else { return "\(ora)  \(testo)" }
            return "\(ora)  \(telefono) · \(testo)"
        }
    }

    /// Il registro come testo, dal più vecchio al più recente: si allega a «Segnala un bug» (passo 9, punto 23).
    var registroComeTesto: String {
        registro.map(\.riga).joined(separator: "\n")
    }

    /// Quante righe tiene il registro: solo in memoria, si svuota alla chiusura dell'app.
    static let righeRegistro = 50
    /// Gli ultimi eventi del collegamento, il più vecchio per primo.
    private(set) var registro: [VoceRegistro] = []
    @ObservationIgnored private var prossimaVoce = 0

    /// `telefono`: di chi è l'evento; il nome compare solo con più telefoni collegati (P21).
    /// `annuncio`: la frase breve che VoiceOver dice per lo stesso evento (passo 6, M22).
    func registra(_ testo: String, di telefono: TelefonoCollegato? = nil, annuncio: String? = nil) {
        if let annuncio { Annuncio.di(annuncio) }
        let nome = telefoni.count > 1 ? telefono?.telefono.nome : nil
        registro.append(VoceRegistro(id: prossimaVoce, ora: Date(), testo: testo, telefono: nome))
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
        // Le scelte salvate degli effetti al motore del Mac (il `didSet` non scatta con il valore iniziale).
        aggiornaMotore()
    }

    /// Pronto ad accogliere un telefono: ascolto aperto, almeno un indirizzo, nessun telefono collegato.
    var prontoSenzaTelefoni: Bool {
        guard telefoni.isEmpty, !indirizzi.isEmpty, case .visibile = rete else { return false }
        return true
    }

    /// Passo 7 (mac.md 14): a ogni cambio di rete o di telefoni. Pronto senza telefoni: dopo 30 secondi
    /// `nessunTelefonoDaTempo`; altrimenti si ricomincia da capo.
    private func controllaAttesaTelefono() {
        guard prontoSenzaTelefoni else {
            compitoAttesaTelefono?.cancel()
            compitoAttesaTelefono = nil
            if nessunTelefonoDaTempo { nessunTelefonoDaTempo = false }
            return
        }
        guard compitoAttesaTelefono == nil, !nessunTelefonoDaTempo else { return }
        compitoAttesaTelefono = Task { [weak self] in
            try? await Task.sleep(for: Ricevitore.attesaPrimoTelefono)
            guard let self, !Task.isCancelled else { return }
            self.compitoAttesaTelefono = nil
            if self.prontoSenzaTelefoni { self.nessunTelefonoDaTempo = true }
        }
    }

    /// Wi-Fi cambiato, cavo collegato: il QR code si rifà con i nuovi indirizzi.
    func aggiornaIndirizzi() {
        let nuovi = IndirizziLocali.ipv4(tipi: tipiInterfacce)
        guard nuovi != indirizzi else { return }
        indirizzi = nuovi
        controllaAttesaTelefono()
        registra(nuovi.isEmpty ? String(localized: "Il Mac non è su nessuna rete") : String(localized: "Rete cambiata: \(nuovi.joined(separator: ", "))"))
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
        registra(String(localized: "Annuncio in rete rinnovato per la rete nuova"))
        riavviaAscolto()
    }

    /// Risveglio dallo stop (1.12): ascolto e annuncio Bonjour da capo, cavo subito, indirizzi riletti.
    private func risvegliato() {
        registra(String(localized: "Risveglio dallo stop: ascolto, annuncio e cavo ripartono"))
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

    /// «Rimuovi» nei telefoni fidati (Impostazioni › Sicurezza e «Telefoni conosciuti»): prima chiede (punto 8).
    func chiediERimuoviFidato(_ telefono: TelefonoFidato) {
        guard Domanda.conferma(String(localized: "Rimuovere «\(telefono.nome)» dai telefoni fidati?"),
                               dettaglio: String(localized: "La prossima volta dovrai confermarlo con il codice."),
                               pulsante: String(localized: "Rimuovi")) else { return }
        rimuoviFidato(telefono)
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
        var tempo = 50
    }

    private var listener: NWListener?
    /// Collegamenti arrivati ma non ancora accettati (stretta di mano, prova, fiducia): non toccano i telefoni
    /// collegati finché non sono accettati, così nessuno sulla rete può farli cadere. Qui solo per tenerli in vita.
    private var candidati: [ObjectIdentifier: SessioneComputer] = [:]
    /// Il candidato che aspetta la risposta dell'utente: una domanda alla volta.
    private var inConferma: ObjectIdentifier?
    private var compitoInOnda: Task<Void, Never>?
    /// Un'app sta usando la webcam virtuale.
    private(set) var webcamInUso = false
    /// Le firme delle app che usano la webcam virtuale (proprietà «appl» dell'estensione), per la riga
    /// delle app sotto il video («In uso da Zoom»). Vuoto se nessuna, o con una webcam virtuale di prima senza la
    /// proprietà: allora `webcamInUso` dice solo che un'app la usa, e la riga dice «In uso da un'altra app».
    private(set) var appWebcam: [String] = []
    /// Finché un telefono è collegato macOS non mette l'app in sospensione (App Nap, funzione 20).
    @ObservationIgnored private var attivitaCollegamento: NSObjectProtocol?

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
        // Ogni schermo manda già le sue immagini (creaSchermo): da qui la webcam prende quelle del telefono scelto.
        webcamCollegata = true
        aggiornaUscite()
        compitoInOnda?.cancel()
        compitoInOnda = Task { [weak self] in
            while !Task.isCancelled {
                // La lettura passa da CoreMediaIO e può richiedere tempo: fuori dalla coda principale.
                let letto = await Task.detached(priority: .utility) { () -> (Bool, UscitaWebcam.Formato?, [String], Int?) in
                    let attivo = UscitaWebcam.leggiInOnda() ?? false
                    let app = attivo ? (UscitaWebcam.leggiApp() ?? []) : []
                    // L'attesa dentro la webcam virtuale fino alla consegna alle app (da vetro a uscita).
                    let attesa = attivo ? UscitaWebcam.leggiAttesaEstensione() : nil
                    return (attivo, attivo ? UscitaWebcam.leggiFormato() : nil, app, attesa)
                }.value
                guard let self, !Task.isCancelled else { return }
                self.uscitaWebcam.imposta(inOnda: letto.0, attesaEstensioneMs: letto.3)
                // Il nome dell'app prima dello stato: la riga «In onda su Zoom» del registro lo usa.
                if letto.2 != self.appWebcam { self.appWebcam = letto.2 }
                self.aggiornaInOnda(letto.0)
                self.aggiornaFormatoWebcam(letto.1)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Il formato scelto dall'app che usa la webcam virtuale (P12), nil se nessuna la usa.
    /// - 4K: l'estensione riceve 3840×2160 solo se l'app la usa in 4K e il telefono manda il 4K.
    /// - 60 fps: se l'app li vuole e il telefono ne manda meno, glieli chiede una volta con `formato`
    ///   (dal computer è una richiesta, Documenti/Protocollo.md), con la stessa risoluzione e lo stesso codec.
    ///   Il telefono può non seguirla: allora l'estensione ripete le immagini e il ritmo dell'uscita resta 60.
    private func aggiornaFormatoWebcam(_ formato: UscitaWebcam.Formato?) {
        uscitaWebcam.imposta(quattroK: (formato?.altezza ?? 0) >= 2160)
        guard let formato else {
            telefoni.forEach { $0.fpsChiesti = nil }
            return
        }
        // Solo il telefono nella webcam (P21).
        guard formato.fps > 30, let telefono = attivo, let attuale = telefono.formatoTelefono,
              attuale.fps < formato.fps, let sessione = telefono.sessione else { return }
        // Il 4K resta a 30 fps (1.14): a 60 è troppo per il Wi-Fi e scalda il telefono.
        guard min(attuale.larghezza, attuale.altezza) < 2160 else { return }
        // Per non chiedere a vuoto: con `capacita.formati` si chiede al massimo ciò che il telefono sa fare
        // a questa risoluzione; risoluzione non elencata = non ci arriva.
        let fps = Self.fpsPossibili(formato.fps, larghezza: attuale.larghezza, altezza: attuale.altezza,
                                    formati: capacita?.formati)
        guard fps > attuale.fps, telefono.fpsChiesti != fps else { return }
        telefono.fpsChiesti = fps
        registra(String(localized: "Un'app usa la webcam a \(formato.fps) fps: chiesti al telefono \(fps) fps"), di: telefono)
        let richiesta = FormatoVideo(codec: attuale.codec, larghezza: attuale.larghezza, altezza: attuale.altezza, fps: fps)
        telefono.formatoChiesto = richiesta
        sessione.chiedi(richiesta)
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
                        self.registra(String(localized: "Microfono virtuale non trovato nel sistema"))
                    } else if case .nonInstallato = self.installazioneMicrofono {
                        self.registra(String(localized: "Microfono virtuale presente nel sistema"))
                    }
                    self.installazioneMicrofono = letta
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Il telefono scelto sa mandare l'audio (`capacita.audio`).
    var telefonoMandaAudio: Bool {
        telefonoAttivo && capacita?.audio == true
    }

    /// L'interruttore «Microfono del telefono»: lo dice al telefono con `comando.audio`.
    func impostaMicrofono(_ acceso: Bool) {
        cambiaMicrofono(acceso)
        registra(acceso ? String(localized: "Microfono del telefono acceso") : String(localized: "Microfono del telefono spento"))
        if telefonoMandaAudio, let telefono = attivo {
            telefono.sessione?.comanda(Comando(audio: acceso))
            telefono.audioComandato = acceso
        }
    }

    /// Il microfono è stato acceso o spento sul telefono scelto (`stato.audio` è cambiato): l'interruttore del Mac
    /// lo segue, così l'audio non viene scartato qui e non si aspetta un audio che non arriverà.
    private func microfonoDalTelefono(_ acceso: Bool, telefono: TelefonoCollegato) {
        telefono.audioComandato = acceso
        guard acceso != microfonoAcceso else { return }
        cambiaMicrofono(acceso)
        registra(acceso ? String(localized: "Microfono acceso dal telefono") : String(localized: "Microfono spento dal telefono"), di: telefono)
    }

    private func cambiaMicrofono(_ acceso: Bool) {
        microfonoAcceso = acceso
        UserDefaults.standard.set(acceso, forKey: Preferenze.microfonoTelefono)
        if !acceso {
            microfono.ferma()
            audioInArrivo = false
            livelloMicrofono = 0
        }
    }

    /// Con l'interruttore acceso, chiede l'audio a ogni sessione nuova del telefono scelto appena dice di saperlo
    /// fare, e al telefono appena scelto (P21: il microfono segue la webcam).
    private func chiediAudioSeServe() {
        guard microfonoAcceso, telefonoMandaAudio, let telefono = attivo, !telefono.audioComandato else { return }
        telefono.audioComandato = true
        telefono.sessione?.comanda(Comando(audio: true))
    }

    /// La finestra mini si è aperta o chiusa: lo schermo le manda le immagini solo mentre è aperta.
    func mostraMini(_ aperta: Bool) {
        miniAperta = aperta
        aggiornaUscite()
        if let attivo { segnalaAnteprima(attivo) }
    }

    /// Riempi o adatta (funzione 30): per tutti gli schermi, anche quelli dei telefoni che arriveranno.
    func imposta(riempi: Bool) {
        self.riempi = riempi
        schermoVuoto.imposta(riempi: riempi)
        uscitaMini.imposta(riempi: riempi)
        telefoni.forEach { $0.schermo.imposta(riempi: riempi) }
    }

    // MARK: - Pausa intelligente

    /// Dalla finestra principale: il video si vede o no (finestra chiusa, ridotta a icona, coperta, app nascosta).
    /// La vista pulita conta come visibile: è sempre il video.
    func aggiornaVisibilitaPrincipale(_ visibile: Bool) {
        guard visibile != principaleVisibile else { return }
        principaleVisibile = visibile
        telefoni.forEach { segnalaAnteprima($0) }
    }

    /// Dall'anteprima (P21): la miniatura dell'altro telefono compare o sparisce.
    func aggiornaVisibilitaMiniatura(_ visibile: Bool) {
        guard visibile != miniaturaVisibile else { return }
        miniaturaVisibile = visibile
        altri.forEach { segnalaAnteprima($0) }
    }

    /// Qualcuno guarda il video di quel telefono sul Mac. Il telefono scelto: finestra principale visibile
    /// o finestra mini aperta. Gli altri (P21): solo se si vede la loro miniatura. Dal 27 ottobre il telefono non va
    /// più in pausa per questo (il video continua finché WebcamLR per Mac è aperta, anche ridotta a icona): si manda
    /// ancora per i telefoni di prima, che dopo 10 secondi senza anteprima e senza app potevano fermarsi.
    private func anteprimaVisibile(per telefono: TelefonoCollegato) -> Bool {
        if telefono === attivo { return principaleVisibile || miniAperta }
        return principaleVisibile && miniaturaVisibile
    }

    /// Manda `anteprima` al telefono quando cambia; `sempre` subito dopo il `benvenuto`.
    /// Solo i telefoni di prima del 27 ottobre ne tengono conto (pausa «nessuna app» dopo 10 secondi).
    private func segnalaAnteprima(_ telefono: TelefonoCollegato, sempre: Bool = false) {
        let visibile = anteprimaVisibile(per: telefono)
        guard sempre || visibile != telefono.anteprimaSegnalata else { return }
        let cambiata = telefono.anteprimaSegnalata != nil && visibile != telefono.anteprimaSegnalata
        telefono.anteprimaSegnalata = visibile
        guard let sessione = telefono.sessione else { return }
        sessione.segnalaAnteprima(visibile)
        if cambiata { registra(visibile ? String(localized: "Anteprima di nuovo visibile") : String(localized: "Anteprima nascosta"), di: telefono) }
    }

    /// Il testo calmo sopra il video quando il telefono è in pausa (`stato.pausa`). «Nessuna app» resta per i telefoni
    /// di prima del 27 ottobre: quelli nuovi non vanno più in pausa da soli (solo faccia in giù, dall'utente, calore…).
    /// Anche fuori dalla coda principale: la schermata di attesa (`StatoAttesa.sottotitolo`) si disegna su altre code.
    nonisolated static func testoPausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.sottofondo: String(localized: "WebcamLR è in sottofondo sul telefono: riaprila per riprendere")
        case MotiviPausa.fotocameraInterrotta: String(localized: "La fotocamera del telefono è in pausa (chiamata, altra app o calore)")
        case MotiviPausa.facciaInGiu: String(localized: "Il telefono è a faccia in giù. Giralo per riprendere.")
        case MotiviPausa.nessunaApp: String(localized: "Nessuna app usa la webcam. Il video riprende da solo appena serve.")
        case MotiviPausa.utente: String(localized: "In pausa dal telefono. Riprendi dal telefono.")
        default: String(localized: "Il telefono ha messo in pausa il video.")
        }
    }

    /// Il telefono scelto è collegato, in onda o no.
    var telefonoAttivo: Bool {
        attivo?.collegato ?? false
    }

    /// L'app che usa la webcam, se è una sola e dell'elenco: «In onda · Zoom» (M8), menu della barra e del Dock.
    var nomeAppInOnda: String? {
        AppCompatibile.nomeUnico(firme: appWebcam)
    }

    /// Dalla webcam virtuale: un'app la sta usando o no (proprietà personalizzata «inon»).
    private func aggiornaInOnda(_ inUso: Bool) {
        guard inUso != webcamInUso else { return }
        webcamInUso = inUso
        // Nel registro e per VoiceOver solo con un telefono: senza, le app vedono la schermata d'attesa.
        if attivo != nil {
            let testo: String
            if !inUso {
                testo = String(localized: "Non più in onda")
            } else if let nome = nomeAppInOnda {
                testo = String(localized: "In onda su \(nome)")
            } else {
                testo = String(localized: "In onda")
            }
            registra(testo, annuncio: testo)
        }
        for telefono in telefoni {
            aggiornaStatoInOnda(telefono)
            segnalaInOnda(telefono)
        }
    }

    /// «In onda» solo per il telefono nella webcam (P21); durante la riconnessione lo stato resta quello.
    private func aggiornaStatoInOnda(_ telefono: TelefonoCollegato) {
        guard telefono.collegamento != .riconnessione else { return }
        telefono.collegamento = telefono === attivo && webcamInUso ? .inOnda(app: nil) : .collegato
    }

    /// Manda `in-onda` al telefono quando cambia (il rosso «IN ONDA» sul telefono); `sempre` dopo il `benvenuto`.
    /// `in-onda` porta anche `selezionato` (Più telefoni: la prospettiva): si rimanda quando cambia l'uno o l'altro,
    /// così ogni telefono sa se è la CAM 1 (nella webcam) o la CAM 2.
    private func segnalaInOnda(_ telefono: TelefonoCollegato, sempre: Bool = false) {
        let selezionato = telefono === attivo
        let inOnda = selezionato && webcamInUso
        guard sempre || inOnda != telefono.inOndaSegnalato || selezionato != telefono.selezioneSegnalata else { return }
        telefono.inOndaSegnalato = inOnda
        telefono.selezioneSegnalata = selezionato
        telefono.sessione?.segnala(InOnda(attivo: inOnda, selezionato: selezionato))
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
            controllaAttesaTelefono()
            registra(String(localized: "Ascolto non riuscito: \(error.localizedDescription)"))
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
            controllaAttesaTelefono()
            let diretto = UserDefaults.standard.bool(forKey: Preferenze.wifiDiretto) ? String(localized: ", Wi-Fi diretto acceso") : ""
            registra(String(localized: "Visibile in rete sulla porta \(Int(listener?.port?.rawValue ?? 0))\(diretto)"))
            aggiornaIndirizzi()
            indirizziAnnunciati = indirizzi
            attesaRiapertura = .seconds(1)
        case .failed(let errore):
            listener?.cancel()
            listener = nil
            if portaFissa, case .posix(.EADDRINUSE) = errore {
                registra(String(localized: "Porta \(Int(Servizio.portaPredefinita)) occupata: ne uso un'altra"))
                avvia(porta: nil)
            } else {
                rete = .errore(errore.localizedDescription)
                controllaAttesaTelefono()
                registra(String(localized: "Ascolto caduto: \(errore.localizedDescription)"))
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

    // MARK: - Telefoni

    /// Ogni collegamento resta un candidato finché non è accettato (stretta di mano, prova, fiducia):
    /// fino ad allora non tocca i telefoni collegati, così nessuno sulla rete può farli cadere.
    /// Accettato: se è un telefono già collegato (stesso codice di sicurezza) ne sostituisce la sessione,
    /// altrimenti diventa un telefono in più (P21), finché ci sono posti.
    private func accetta(_ connessione: NWConnection, arrivo: UInt64) {
        // Prima la sessione (la stretta di mano può cominciare), poi la riga del registro.
        avviaCandidato(TrasportoRete(connessione), arrivo: arrivo)
        registra(String(localized: "Collegamento in arrivo dalla rete"))
    }

    /// Un canale aperto dal client usbmux: stessa strada della rete (stretta di mano, fiducia, candidati).
    /// Se il telefono è già collegato in Wi-Fi, il cavo prende il suo posto quando è accettato.
    private func accettaCavo(_ descrittore: Int32, canale: ClienteUSB.Canale) {
        let identita = avviaCandidato(TrasportoSocket(descrittore: descrittore), arrivo: Orologio.adesso())
        canaliCavo[identita] = canale
    }

    @discardableResult
    private func avviaCandidato(_ trasporto: TrasportoSessione, arrivo: UInt64) -> ObjectIdentifier {
        let nuova = SessioneComputer(trasporto: trasporto, microfono: microfono, uscitaWebcam: uscitaWebcam,
                                     abbinamento: abbinamento, posti: posti, arrivo: arrivo)
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

    /// Il cavo messo in pausa per la preferenza Wi-Fi del telefono riparte (preferenza cambiata o Wi-Fi perso).
    private func riprendiCavoPerPreferenza(_ motivo: String, di telefono: TelefonoCollegato) {
        guard cavoInPausaPer == telefono.impronta else { return }
        cavoInPausaPer = nil
        registra(motivo, di: telefono)
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

    /// Il telefono di cui `identita` è la sessione attuale.
    private func telefonoDellaSessione(_ identita: ObjectIdentifier) -> TelefonoCollegato? {
        telefoni.first { telefono in telefono.sessione.map { ObjectIdentifier($0) == identita } ?? false }
    }

    /// Un nuovo `Schermo` per un telefono in più, con le uscite verso webcam e finestra mini.
    private func creaSchermo() -> Schermo {
        let schermo = Schermo()
        schermo.imposta(riempi: riempi)
        let id = ObjectIdentifier(schermo)
        let uscitaWebcam = self.uscitaWebcam
        let uscitaMini = self.uscitaMini
        // Ogni schermo manda sempre: lasciano passare solo quello scelto (sotto lucchetto, vedi le due classi).
        schermo.inviaImmagini { immagine, cattura in
            uscitaWebcam.invia(immagine, cattura: cattura, da: id)
            uscitaMini.mostra(immagine, da: id)
        }
        return schermo
    }

    /// I posti per le sessioni (controllati prima del `benvenuto`) seguono l'elenco dei telefoni.
    private func aggiornaPosti() {
        posti.aggiorna(Set(telefoni.map(\.impronta)))
    }

    /// Eventi di un collegamento non ancora accettato: la domanda all'utente, la chiusura, l'accettazione.
    /// Vero se l'evento è finito qui.
    private func gestisciCandidato(_ evento: SessioneComputer.Evento, da identita: ObjectIdentifier) -> Bool {
        guard let candidato = candidati[identita] else { return false }
        switch evento {
        case .ciao(let ciao, let impronta, _):
            candidati[identita] = nil
            if inConferma == identita { inConferma = nil }
            // Consentito: il cavo non va più in pausa se questa sessione finisce.
            pausaCavo.remove(identita)
            if let esistente = telefoni.first(where: { $0.impronta == impronta }) {
                let dalCavo = canaliCavo[identita] != nil
                // La scelta del collegamento del telefono (`stato.collegamento.preferenza`); nil = telefono vecchio.
                let preferenza = esistente.preferenzaCollegamento
                // In sottofondo la sessione di prima può essere ancora aperta ma muta: quella nuova vince sempre.
                if let attuale = esistente.sessione, attuale !== candidato, esistente.collegamento != .riconnessione,
                   !esistente.inSottofondo {
                    let attualeDalCavo = vieneDalCavo(attuale)
                    // Lo stesso telefono (1.1). Precedenza (1.9, ridotta): se è già collegato via cavo e il cavo
                    // funziona, un collegamento dalla rete non lo sostituisce: si chiude quello nuovo.
                    // Tranne quando il telefono preferisce il Wi-Fi: allora torna al Wi-Fi e il cavo va in pausa.
                    if attualeDalCavo, !dalCavo, preferenza != PreferenzeCollegamento.wifi {
                        registra(String(localized: "Collegamento dalla rete chiuso: il telefono resta sul cavo USB"), di: esistente)
                        candidato.chiudi()
                        return true
                    }
                    if !attualeDalCavo, dalCavo {
                        // Il telefono preferisce il Wi-Fi: il cavo resta in pausa finché serve (Wi-Fi perso) o
                        // finché la preferenza cambia.
                        if preferenza == PreferenzeCollegamento.wifi {
                            registra(String(localized: "Cavo USB in pausa: il telefono preferisce il Wi-Fi"), di: esistente)
                            pausaCavo.insert(identita)
                            cavoInPausaPer = esistente.impronta
                            candidato.chiudi()
                            return true
                        }
                        // «Automatico»: dopo un cambio di strada, 30 secondi senza cambiare di nuovo (il cavo che va
                        // e viene). Il client del cavo riprova con l'attesa che cresce: passa dopo la pausa.
                        if preferenza == PreferenzeCollegamento.automatico, let ultimo = esistente.ultimoCambioStrada,
                           ContinuousClock.now - ultimo < Self.pausaCambioStrada {
                            registra(String(localized: "Cavo USB rimandato: la strada è appena cambiata"), di: esistente)
                            candidato.chiudi()
                            return true
                        }
                    }
                }
                // Il cavo funziona: se più avanti si chiude, il client riprova di nuovo ogni 2 secondi
                // (chiuso prima di qui, invece, il telefono ha rifiutato il cavo e l'attesa cresce).
                if let canale = canaliCavo[identita] { cavo.strettaRiuscita(canale) }
                // Prende il posto della sessione di prima (anche il cavo al posto del Wi-Fi).
                if let vecchia = esistente.sessione, vecchia !== candidato {
                    // Dal cavo al Wi-Fi per la preferenza del telefono: il cavo non si ripresenta ogni 2 secondi.
                    if vieneDalCavo(vecchia), !dalCavo, preferenza == PreferenzeCollegamento.wifi {
                        pausaCavo.insert(ObjectIdentifier(vecchia))
                        cavoInPausaPer = esistente.impronta
                    }
                    vecchia.chiudi()
                }
                // Strada cambiata (anche dopo una caduta): da qui partono i 30 secondi di «Automatico».
                if (esistente.tipoCollegamento == .cavoUSB) != dalCavo { esistente.ultimoCambioStrada = .now }
                esistente.sessione = candidato
                // Da qui il suo video va al suo schermo; quello delle sessioni chiuse sopra non più.
                candidato.diventaAttuale(schermo: esistente.schermo)
                return false
            }
            // Un telefono diverso: non scalza quelli collegati (P21), diventa un telefono in più.
            guard telefoni.count < Self.massimoTelefoni else {
                // Di solito le sessioni lo fermano prima del `benvenuto` (PostiTelefoni); qui il caso raro
                // di due telefoni nuovi accettati nello stesso istante.
                avvisaPostiPieni(ciao.nome)
                candidato.chiudi()
                return true
            }
            // WebcamLR Pro: due telefoni insieme solo se quello nella webcam l'ha sbloccato (`capacita.pro`).
            guard telefoni.isEmpty || proAttivo else {
                avvisaSecondoTelefonoSenzaPro(ciao.nome)
                candidato.chiudi()
                return true
            }
            if let canale = canaliCavo[identita] { cavo.strettaRiuscita(canale) }
            let nuovo = TelefonoCollegato(impronta: impronta, telefono: ciao, schermo: creaSchermo())
            nuovo.sessione = candidato
            telefoni.append(nuovo)
            controllaAttesaTelefono()
            aggiornaPosti()
            candidato.diventaAttuale(schermo: nuovo.schermo)
            if idAttivo == nil || telefoni.count == 1 {
                // Il primo telefono va nella webcam, come sempre.
                scegliAttivo(nuovo, precedente: nil)
            } else {
                registra(String(localized: "Secondo telefono collegato: «\(attivo?.telefono.nome ?? "")» resta nella webcam"), di: nuovo)
                aggiornaUscite()
            }
            return false
        case .conferma(let nome, let codice):
            // C'è già una domanda aperta per un altro telefono: per sicurezza si rifiuta,
            // così nessuno può cambiare la domanda sotto il cursore dell'utente.
            guard inConferma == nil else {
                candidato.rispondi(consentito: false)
                return true
            }
            inConferma = identita
            registra(String(localized: "Telefono nuovo, «\(nome)»: chiedo conferma con il codice"))
            // Un telefono del cavo non consentito (o senza risposta) non deve ripresentarsi ogni 2 secondi.
            if canaliCavo[identita] != nil { pausaCavo.insert(identita) }
            // Prima la notifica (solo se WebcamLR è in secondo piano), poi l'app davanti con la domanda.
            Notifiche.condivise.richiestaConsenso(nome)
            finestraConferma.mostra(nome: nome, codice: codice) { [weak self] consentito in
                self?.rispondiConferma(consentito, da: identita)
            }
        case .confermaFinita:
            if inConferma == identita { chiudiConferma() }
        case .rifiutata(let nome):
            // Posti pieni (P21): la sessione ha già mandato l'`arrivederci` e si chiude da sola. Sul cavo
            // il client riprova con l'attesa che cresce (2, 4… 30 secondi): appena un posto si libera, entra.
            avvisaPostiPieni(nome)
        case .chiusa:
            candidati[identita] = nil
            registra(String(localized: "Collegamento chiuso prima di essere accettato"))
            chiusaSessione(identita)
            // Il telefono se n'è andato mentre si aspettava la conferma: la domanda sparisce.
            if inConferma == identita { chiudiConferma() }
        default:
            break
        }
        return true
    }

    /// «Già collegati due telefoni»: l'avviso sul Mac (e la notifica, se WebcamLR è in secondo piano).
    /// Lo stesso telefono che riprova dal cavo non ripete l'avviso per un minuto.
    private func avvisaPostiPieni(_ nome: String) {
        let adesso = ContinuousClock.now
        if let ultimo = ultimiRifiuti[nome], adesso - ultimo < .seconds(60) { return }
        ultimiRifiuti[nome] = adesso
        mostraAvviso(String(localized: "Già collegati due telefoni: per collegare «\(nome)» scollega uno dei due."),
                     registro: String(localized: "«\(nome)» non collegato: già collegati \(Self.massimoTelefoni) telefoni"))
        Notifiche.condivise.postiPieni(nome)
    }

    /// Un secondo telefono con il primo senza WebcamLR Pro: lo si dice, al massimo una volta al minuto per telefono.
    private func avvisaSecondoTelefonoSenzaPro(_ nome: String) {
        let adesso = ContinuousClock.now
        if let ultimo = ultimiRifiuti[nome], adesso - ultimo < .seconds(60) { return }
        ultimiRifiuti[nome] = adesso
        mostraAvviso(String(localized: "Due telefoni insieme sono di WebcamLR Pro: sbloccalo sull'iPhone nella webcam per collegare anche «\(nome)»."),
                     registro: String(localized: "«\(nome)» non collegato: due telefoni insieme sono di WebcamLR Pro"))
    }

    /// La X sul banner «… non è tornato».
    func chiudiAvvisoNonTornato() {
        telefonoNonTornato = nil
    }

    /// Da chiamare nei comandi dell'interfaccia che cambiano il video del telefono (obiettivo, qualità, profilo,
    /// «Nella webcam», «Usa prospettiva», tasti 1–4, «Usa questa prospettiva» toccato sul telefono): mentre registri
    /// chiede prima di fermare la registrazione. Vero se il comando può andare avanti. I cambi fatti sul telefono
    /// stesso (obiettivo, girarlo) non si possono fermare: chiudono il file e lo salvano.
    func confermaSeFerma(_ comando: Riprese.ComandoCheFerma) -> Bool {
        primaDiUnComandoCheFerma?(comando) ?? true
    }

    /// Un avviso in ambra sopra il video, che sparisce da solo dopo 8 secondi: un fatto finito. Finisce anche nel
    /// registro (passo 6), con la frase dell'avviso o con `registro`, più breve.
    func mostraAvviso(_ testo: String, registro rigaRegistro: String? = nil) {
        registra(rigaRegistro ?? testo)
        avvisoTelefoni = testo
        compitoAvvisoTelefoni?.cancel()
        compitoAvvisoTelefoni = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            self.avvisoTelefoni = nil
        }
    }

    // MARK: - Scelta del telefono nella webcam (P21)

    /// «Nella webcam»: questo telefono va nella webcam virtuale, nel microfono, nella finestra mini,
    /// nell'anteprima grande, nelle foto e nei comandi del pannello. Subito: il suo schermo decodifica già.
    func scegli(_ telefono: TelefonoCollegato) {
        guard telefono !== attivo, telefoni.contains(where: { $0 === telefono }) else { return }
        let precedente = attivo
        primaDelCambioTelefono?()
        registra(String(localized: "«\(telefono.telefono.nome)» nella webcam"))
        scegliAttivo(telefono, precedente: precedente)
    }

    /// Cambia il telefono scelto e sposta uscite, microfono, «in onda» e anteprima.
    private func scegliAttivo(_ nuovo: TelefonoCollegato?, precedente: TelefonoCollegato?) {
        idAttivo = nuovo?.id
        aggiornaUscite()
        // Le regole Pro del motore seguono il telefono nella webcam.
        aggiornaMotore()
        // Il microfono: il telefono di prima smette di mandare l'audio, quello nuovo lo manda se l'interruttore è acceso.
        if let precedente, precedente !== nuovo {
            precedente.sessione?.usaMicrofono(false)
            if precedente.audioComandato {
                precedente.sessione?.comanda(Comando(audio: false))
                precedente.audioComandato = false
            }
            precedente.fpsChiesti = nil
        }
        microfono.ferma()
        audioInArrivo = false
        livelloMicrofono = 0
        if let nuovo {
            nuovo.sessione?.usaMicrofono(true)
            audioInArrivo = microfonoAcceso && nuovo.statistiche.pacchettiAudio > 0
        }
        chiediAudioSeServe()
        // Solo il telefono nella webcam è «in onda» (il rosso sul telefono); gli altri contano come visibili
        // solo se si vede la loro miniatura (pausa intelligente).
        for telefono in telefoni {
            aggiornaStatoInOnda(telefono)
            segnalaInOnda(telefono)
            segnalaAnteprima(telefono)
        }
    }

    /// Webcam virtuale e finestra mini prendono le immagini dello schermo del telefono scelto.
    private func aggiornaUscite() {
        let scelto = attivo.map { ObjectIdentifier($0.schermo) }
        uscitaWebcam.scegli(webcamCollegata ? scelto : nil)
        uscitaMini.scegli(miniAperta ? scelto : nil)
        // Il motore effetti lavora solo per il telefono nella webcam: l'altro si vede com'è nella sua miniatura.
        let sceltoOra = attivo
        for telefono in telefoni {
            telefono.schermo.motore.abilita(Self.effettiSulComputer && telefono === sceltoOra)
        }
    }

    /// Comandi della fotocamera verso il telefono scelto. Per un attimo lo `stato` non sovrascrive i valori appena mandati.
    func comanda(_ comando: Comando) {
        guard let telefono = attivo else { return }
        telefono.segnaComando(comando)
        telefono.sessione?.comanda(comando)
    }

    // MARK: - Specchia e Sfondo (1.14; sfondi pronti e immagini dal Mac)

    /// Il telefono scelto sa specchiare dal vivo (`capacita.specchia`); con gli effetti sul computer specchia il Mac,
    /// per qualsiasi telefono.
    var specchioDisponibile: Bool {
        telefonoAttivo && (Self.effettiSulComputer || capacita?.specchia == true)
    }

    /// Il video che arriva è specchiato: segue `stato.specchia` (dopo un clic qui, per un attimo, la scelta appena fatta).
    var specchiato: Bool { effetti.specchia }

    /// «Specchia» e «Sfondo» valgono solo con la fotocamera frontale: con un obiettivo posteriore (`stato.obiettivo`
    /// diverso da «frontale») il telefono non specchia e spegne lo sfondo, e li riprende tornando alla frontale. Qui i
    /// due pulsanti sotto il video restano grigi, con «Solo con la fotocamera frontale».
    /// Lo stesso con gli effetti sul computer: il motore del Mac non specchia e non fa lo sfondo (`conFrontale`).
    var soloFrontaleBloccati: Bool {
        guard telefonoAttivo, capacita != nil, let obiettivo = statoTelefono?.obiettivo else { return false }
        return obiettivo != Self.obiettivoFrontale
    }

    /// L'obiettivo frontale nel protocollo (`stato.obiettivo`).
    static let obiettivoFrontale = "frontale"

    /// Effetti sul computer: specchio e sfondo del motore solo con la fotocamera frontale (o finché il telefono non
    /// ha detto l'obiettivo, per non mostrare lo sfondo vero all'inizio della sessione).
    private static func conFrontale(_ telefono: TelefonoCollegato?) -> Bool {
        guard let obiettivo = telefono?.statoTelefono?.obiettivo else { return true }
        return obiettivo == obiettivoFrontale
    }

    /// «Specchia»: lo chiede al telefono, che specchia il video inviato (anche quello delle app) e lo conferma in `stato`.
    func alternaSpecchio() {
        guard specchioDisponibile, !soloFrontaleBloccati, let telefono = attivo else { return }
        if Self.effettiSulComputer {
            // Lo specchio del motore: uno solo, uguale per la finestra, le app, le foto e la registrazione.
            effettiComputer.specchia.toggle()
            registra(effettiComputer.specchia ? String(localized: "Specchia: acceso") : String(localized: "Specchia: spento"), di: telefono)
            return
        }
        telefono.effetti.specchia.toggle()
        registra(telefono.effetti.specchia ? String(localized: "Specchia: acceso") : String(localized: "Specchia: spento"), di: telefono)
        mandaEffetto(Effetti.chiaveSpecchia) { Comando(specchia: $0.specchia) }
    }

    /// Il telefono scelto sa sfocare lo sfondo (`capacita.sfondo`).
    var sfondoDisponibile: Bool {
        telefonoAttivo && (Self.effettiSulComputer || capacita?.sfondo == true)
    }

    /// Lo sfondo è sfocato (non «sostituito»).
    var sfondoSfocato: Bool { effetti.sfondo == ModiSfondo.sfocato }

    /// L'ultimo livello di sfocatura scelto dal menu di «Sfondo»; resta da una volta all'altra.
    var livelloSfocatura: LivelloSfocatura = Ricevitore.leggiLivelloSfocatura() {
        didSet { UserDefaults.standard.set(livelloSfocatura.rawValue, forKey: Preferenze.livelloSfocatura) }
    }

    private static func leggiLivelloSfocatura() -> LivelloSfocatura {
        UserDefaults.standard.string(forKey: Preferenze.livelloSfocatura).flatMap(LivelloSfocatura.init(rawValue:)) ?? .medio
    }

    /// Il livello con la spunta nel menu: con lo sfondo sfocato quello più vicino all'intensità che il telefono
    /// conferma (`stato.intensitaSfondo`), altrimenti l'ultimo scelto.
    var livelloSfocaturaAttuale: LivelloSfocatura {
        sfondoSfocato ? LivelloSfocatura.vicino(a: effetti.intensitaSfondo) : livelloSfocatura
    }

    /// Sfocato o sostituito: il pulsante «Sfondo» sotto il video è acceso.
    var sfondoAcceso: Bool { effetti.sfondo != ModiSfondo.nessuno }

    /// Sul telefono è accesa la sfocatura del sistema (`stato.sfocaturaSistema`: su iPhone «Ritratto» negli Effetti video
    /// di Apple). La accende e la regola solo il telefono: «Sfondo» la mostra accesa come «Sfocatura del telefono» e i
    /// livelli Poco, Medio, Tanto sono grigi. Uno sfondo sostituito si sceglie ancora (il telefono chiede di spegnere Ritratto).
    var sfocaturaSistema: Bool { telefonoAttivo && statoTelefono?.sfocaturaSistema == true }

    /// Sul telefono è accesa la luce del sistema (`stato.luceSistema`: su iPhone «Luce da studio»): «Luce sul volto»
    /// diventa «Luce del telefono», accesa e grigia, come la sfocatura.
    var luceSistema: Bool { telefonoAttivo && statoTelefono?.luceSistema == true }

    /// La sfocatura del sistema conta per «Sfondo» solo se lo sfondo non è sostituito: allora vale lo sfondo scelto.
    var sfocaturaDelTelefono: Bool { sfocaturaSistema && effetti.sfondo != ModiSfondo.sostituito }

    /// Ogni 10 secondi, mentre sul telefono c'è uno sfondo o un effetto del sistema (come il telefono con le sue
    /// «Prestazioni»): i numeri ricevuti dal Mac nel registro, fotogrammi reali e Mbit/s in arrivo.
    private func registraNumeri(_ numeri: Statistiche, di telefono: TelefonoCollegato) {
        // Una volta al secondo, con o senza effetti: se il video si è fermato più di 150 ms, dove (telefono, rete, Mac).
        let pause = telefono.schermo.prendiPause()
        if max(pause.telefono, pause.arrivo, pause.mostrate) >= 150_000 {
            registra(String(localized: "Pausa nel video: \(Int(pause.telefono / 1000)) ms tra due catture sul telefono · \(Int(pause.arrivo / 1000)) ms tra due arrivi · \(Int(pause.mostrate / 1000)) ms tra due immagini mostrate"),
                     di: telefono)
        }
        let stato = telefono.statoTelefono
        let effettiAccesi = (telefono === attivo ? effetti.sfondo : telefono.effetti.sfondo) != ModiSfondo.nessuno
            || stato?.sfocaturaSistema == true || stato?.luceSistema == true
        guard effettiAccesi, telefono.sessione != nil else {
            telefono.secondiNumeri = 0
            return
        }
        telefono.secondiNumeri += 1
        guard telefono.secondiNumeri >= 10 else { return }
        telefono.secondiNumeri = 0
        let velocita = Lingua.decimali(String(format: "%.1f", numeri.megabitAlSecondo))
        registra(String(localized: "Ricevuti: \(numeri.fps) fps · \(velocita) Mbit/s"), di: telefono)
    }

    /// Ogni 30 secondi, mentre il video arriva: le tappe del ritardo da vetro a uscita (Protocollo.md, «Latenza») e il
    /// ritardo dell'audio nel registro. È la riga da mandare dopo una prova (Documenti/Prove webcam virtuale.md).
    private func registraRitardo(_ numeri: Statistiche, di telefono: TelefonoCollegato, scelto: Bool) {
        guard numeri.latenzaMs != nil, numeri.fps > 0 else {
            telefono.secondiRitardo = 0
            return
        }
        telefono.secondiRitardo += 1
        guard telefono.secondiRitardo >= 30 else { return }
        telefono.secondiRitardo = 0
        let arrivo = RitardoVetro.testo(numeri.arrivoMs)
        let finestra = RitardoVetro.testo(numeri.anteprimaMs)
        let webcam = RitardoVetro.testo(numeri.webcamMs)
        let estensione = RitardoVetro.testo(scelto ? uscitaWebcam.attesaEstensione : nil)
        let audio = RitardoVetro.testo(scelto && microfonoAcceso && audioInArrivo ? microfono.ritardoMs : nil)
        registra(String(localized: "Da vetro a uscita: arrivo \(arrivo) · finestra \(finestra) · webcam \(webcam) (attesa nella webcam \(estensione)) · audio \(audio)"),
                 di: telefono)
        // La riserva di riproduzione (Schermo.swift): quanto si trattiene il video per farlo uscire regolare, e quante
        // immagini sono comunque uscite in ritardo (scatti rimasti) in questi 30 secondi.
        let riserva = telefono.schermo.prendiRiserva()
        registra(String(localized: "Riserva per la fluidità: \(riserva.ms) ms · immagini in ritardo \(riserva.inRitardo)"),
                 di: telefono)
    }

    /// Gli sfondi pronti del telefono scelto (`capacita.sfondiPronti`), nel suo ordine: solo quelli di cui il Mac ha
    /// la miniatura (un id sconosciuto, da un telefono più nuovo, non si mostra).
    /// Con gli effetti sul computer: tutti, dalle immagini grandi del Mac («Sfondi/grandi»).
    var sfondiPronti: [String] {
        if Self.effettiSulComputer { return SfondiPronti.tutti }
        var visti = Set<String>()
        return (capacita?.sfondiPronti ?? []).filter { SfondiPronti.tutti.contains($0) && visti.insert($0).inserted }
    }

    /// Il telefono scelto accetta le immagini dal Mac (`capacita.immagini`): «Carica un'immagine…» e il logo.
    /// Mai mandarle a un telefono che non lo dice: chiuderebbe la connessione.
    /// Con gli effetti sul computer le immagini restano sul Mac: si caricano sempre.
    var immaginiDisponibili: Bool {
        Self.effettiSulComputer || (telefonoAttivo && capacita?.immagini == true)
    }

    /// «La tua immagine» si mostra se il Mac ne ha una copia (e il telefono la può ricevere) o se il telefono ne ha una.
    /// Con gli effetti sul computer basta la copia del Mac.
    var immaginePersonaleDisponibile: Bool {
        if Self.effettiSulComputer { return ImmaginiComputer.condivise.improntaSfondo != nil }
        return (ImmaginiComputer.condivise.improntaSfondo != nil && capacita?.immagini == true)
            || statoTelefono?.immaginePersonale != nil
    }

    /// Con lo sfondo sostituito, l'immagine che il telefono mostra: un id sconosciuto (o assente) vale il primo pronto.
    var immagineSfondoAttuale: String? {
        guard effetti.sfondo == ModiSfondo.sostituito else { return nil }
        let pronti = sfondiPronti
        if let id = effetti.immagineSfondo, id == SfondiPronti.personale || pronti.contains(id) { return id }
        return pronti.first
    }

    /// Per VoiceOver e l'aiuto del pulsante: «Nessuno», «Sfocatura: Medio», «Libreria».
    var descrizioneSfondo: String {
        if sfocaturaDelTelefono { return String(localized: "Sfocatura del telefono") }
        return switch effetti.sfondo {
        case ModiSfondo.sfocato: String(localized: "Sfocatura: \(livelloSfocaturaAttuale.nome)")
        case ModiSfondo.sostituito: immagineSfondoAttuale.map { SfondiComputer.nome($0) } ?? String(localized: "Sostituito")
        default: String(localized: "Nessuno")
        }
    }

    /// Diagnosi nascosta (⌥ clic su «Sfondo»): con lo sfondo acceso il video mostra la maschera della persona in
    /// bianco e nero, per uno screenshot. Si toglie allo stesso modo.
    func alternaMascheraVisibile() {
        let visibile = !StatoMotoreEffetti.condiviso.mascheraVisibile
        StatoMotoreEffetti.condiviso.mascheraVisibile = visibile
        registra(visibile ? String(localized: "Diagnosi: il video mostra la maschera della persona (⌥ clic su «Sfondo» per tornare)")
                 : String(localized: "Diagnosi: il video torna normale"))
    }

    /// «Sfondo»: un clic spegne lo sfondo acceso, o riaccende l'ultima scelta: la sfocatura con l'ultimo livello,
    /// o l'ultimo sfondo (se c'è ancora e se il telefono ha Pro; altrimenti la sfocatura, che è gratis).
    func alternaSfondo() {
        guard sfondoDisponibile, !soloFrontaleBloccati, let telefono = attivo else { return }
        if sfondoAcceso {
            scegliNessunSfondo()
            return
        }
        // La sfocatura del telefono si spegne solo sul telefono, e la nostra non si accende sopra (mai due sfocature).
        guard !sfocaturaSistema else { return }
        let ultima = ImmaginiComputer.condivise.ultimaScelta
        let ancoraDisponibile = ultima == SfondiPronti.personale ? immaginePersonaleDisponibile : sfondiPronti.contains(ultima)
        if ultima != ImmaginiComputer.sceltaSfocatura, !bloccoPro, ancoraDisponibile {
            scegliImmagineSfondo(ultima)
        } else {
            mandaSfocatura(livelloSfocatura, a: telefono)
        }
    }

    /// «Nessuno» dal menu di «Sfondo».
    func scegliNessunSfondo() {
        if Self.effettiSulComputer {
            effettiComputer.sfondo = ModiSfondo.nessuno
            return
        }
        guard sfondoDisponibile, let telefono = attivo else { return }
        telefono.effetti.sfondo = ModiSfondo.nessuno
        mandaEffetto(Effetti.chiaveSfondo) { Comando(sfondo: $0.sfondo) }
    }

    /// Poco, Medio o Tanto dal menu di «Sfondo»: lo ricorda e accende la sfocatura con quel livello.
    func scegliLivelloSfocatura(_ livello: LivelloSfocatura) {
        // Con la sfocatura del telefono i livelli sono grigi: si regola sul telefono.
        guard !sfocaturaSistema else { return }
        livelloSfocatura = livello
        ImmaginiComputer.condivise.ultimaScelta = ImmaginiComputer.sceltaSfocatura
        guard sfondoDisponibile, let telefono = attivo else { return }
        mandaSfocatura(livello, a: telefono)
    }

    /// Uno sfondo pronto o «La tua immagine» (`SfondiPronti.personale`), di WebcamLR Pro: con un telefono gratis non
    /// parte (il telefono lo ignorerebbe). La tua immagine, se il telefono ne ha un'altra (impronta diversa in
    /// `stato.immaginePersonale`), si rimanda prima del `comando`.
    func scegliImmagineSfondo(_ id: String) {
        guard sfondoDisponibile, !bloccoPro, let telefono = attivo else { return }
        if Self.effettiSulComputer {
            // Lo sfondo lo mette il motore del Mac: niente da mandare al telefono.
            guard id != SfondiPronti.personale || ImmaginiComputer.condivise.improntaSfondo != nil else { return }
            ImmaginiComputer.condivise.ultimaScelta = id
            var nuovi = effettiComputer
            nuovi.sfondo = ModiSfondo.sostituito
            nuovi.immagineSfondo = id
            effettiComputer = nuovi
            return
        }
        if id == SfondiPronti.personale {
            let immagini = ImmaginiComputer.condivise
            let sulTelefono = telefono.statoTelefono?.immaginePersonale
            if let impronta = immagini.improntaSfondo, impronta != sulTelefono, telefono.capacita?.immagini == true,
               let dati = immagini.datiSfondo() {
                // Prima il pacchetto, poi il `comando`: sulla stessa sessione arrivano in quest'ordine.
                telefono.sessione?.mandaImmagine(PacchettoImmagine(uso: .sfondo, dati: dati))
                registra(String(localized: "La tua immagine mandata al telefono"), di: telefono)
            } else if sulTelefono == nil {
                // Né una copia da mandare né un'immagine sul telefono: non c'è niente da mostrare.
                return
            }
        }
        ImmaginiComputer.condivise.ultimaScelta = id
        telefono.effetti.sfondo = ModiSfondo.sostituito
        telefono.effetti.immagineSfondo = id
        mandaEffetto(Effetti.chiaveSfondo) { Comando(sfondo: $0.sfondo, immagineSfondo: $0.immagineSfondo) }
    }

    /// «Carica un'immagine…»: ridotta (lato lungo 1920, JPEG), salvata nella cartella dell'app (resta tra i riavvii)
    /// e mandata al telefono scelto, che la mette subito come sfondo. Senza `capacita.immagini` o senza Pro resta solo
    /// salvata, per quando servirà.
    func caricaImmagineSfondo(da url: URL) async {
        let dati = await Task.detached(priority: .userInitiated) {
            RiduzioneImmagine.riduci(url, latoMassimo: 1920, png: false)
        }.value
        guard let dati else {
            mostraAvviso(String(localized: "Non riesco ad aprire questa immagine: prova con un JPEG, un PNG o un HEIC."))
            return
        }
        do {
            try ImmaginiComputer.condivise.salvaSfondo(dati)
        } catch {
            mostraAvviso(String(localized: "Non riesco a salvare l'immagine sul Mac."))
            return
        }
        registra(String(localized: "Immagine dello sfondo caricata"))
        scegliImmagineSfondo(SfondiPronti.personale)
    }

    /// Il telefono scelto ha un logo per la scritta (`stato.logo`); con gli effetti sul computer, il Mac ne ha uno.
    var logoSulTelefono: Bool {
        Self.effettiSulComputer ? ImmaginiComputer.condivise.improntaLogo != nil : statoTelefono?.logo != nil
    }

    /// «Carica logo…»: PNG con la trasparenza, lato lungo 512. Salvato anche sul Mac, poi mandato al telefono scelto
    /// (solo con `capacita.immagini` e Pro: un telefono gratis lo scarterebbe).
    func caricaLogo(da url: URL) async {
        let dati = await Task.detached(priority: .userInitiated) {
            RiduzioneImmagine.riduci(url, latoMassimo: 512, png: true)
        }.value
        guard let dati else {
            mostraAvviso(String(localized: "Non riesco ad aprire questo logo: serve un'immagine PNG."))
            return
        }
        do {
            try ImmaginiComputer.condivise.salvaLogo(dati)
        } catch {
            mostraAvviso(String(localized: "Non riesco a salvare il logo sul Mac."))
            return
        }
        if Self.effettiSulComputer {
            // Il logo lo mette il motore del Mac.
            registra(String(localized: "Logo caricato"))
            aggiornaMotore()
            return
        }
        guard immaginiDisponibili, !bloccoPro, let telefono = attivo else { return }
        telefono.sessione?.mandaImmagine(PacchettoImmagine(uso: .logo, dati: dati))
        registra(String(localized: "Logo mandato al telefono"), di: telefono)
    }

    /// «Togli logo»: il telefono lo cancella (`comando.togliLogo`). La copia sul Mac resta.
    func togliLogo() {
        if Self.effettiSulComputer {
            // Il logo è del Mac: si cancella la sua copia.
            ImmaginiComputer.condivise.togliLogo()
            registra(String(localized: "Logo tolto"))
            aggiornaMotore()
            return
        }
        guard immaginiDisponibili, let telefono = attivo else { return }
        telefono.sessione?.comanda(Comando(togliLogo: true))
        registra(String(localized: "Logo tolto dal telefono"), di: telefono)
    }

    /// Sfondo sfocato con l'intensità del livello, in un solo `comando`. Anche l'intensità ha la precedenza sullo
    /// `stato` per un attimo, come lo sfondo: altrimenti uno `stato` già in viaggio rimetterebbe quella di prima.
    private func mandaSfocatura(_ livello: LivelloSfocatura, a telefono: TelefonoCollegato) {
        if Self.effettiSulComputer {
            var nuovi = effettiComputer
            nuovi.sfondo = ModiSfondo.sfocato
            nuovi.intensitaSfondo = livello.intensita
            effettiComputer = nuovi
            return
        }
        telefono.effetti.sfondo = ModiSfondo.sfocato
        telefono.effetti.intensitaSfondo = livello.intensita
        telefono.inviiInAttesa[Effetti.chiaveIntensitaSfondo]?.cancel()
        telefono.inviiInAttesa[Effetti.chiaveIntensitaSfondo] = nil
        telefono.modificheEffetti[Effetti.chiaveIntensitaSfondo] = .now
        mandaEffetto(Effetti.chiaveSfondo) { Comando(sfondo: $0.sfondo, intensitaSfondo: $0.intensitaSfondo) }
    }

    // MARK: - Effetti sul computer (MotoreEffetti.swift)

    /// Cosa si può comandare, per le sezioni degli effetti: con gli effetti sul computer gli effetti di immagine li sa
    /// fare il Mac con qualsiasi telefono (filtri, sfondo con gli sfondi pronti, pelle, luce, inquadratura, scritta e
    /// logo, calore, specchio); il resto (doppia vista, postura, gobbo, fotocamera, Pro) è del telefono.
    var capacitaEffetti: Capacita? {
        guard var nuove = capacita else { return nil }
        guard Self.effettiSulComputer else { return nuove }
        nuove.filtri = Filtri.tutti
        nuove.sfondo = true
        nuove.pelle = true
        nuove.inquadratura = true
        nuove.luceVolto = true
        nuove.scritta = true
        nuove.calore = true
        nuove.specchia = true
        nuove.immagini = true
        nuove.sfondiPronti = SfondiPronti.tutti
        return nuove
    }

    /// Le scelte di `effettiComputer` al motore, con le regole di WebcamLR Pro del telefono nella webcam
    /// (`capacita.pro`): gratis sfocatura, calore, luce sul volto e specchio; il resto solo con Pro. Con un telefono
    /// che non ha ancora mandato la `capacita` valgono solo le gratuite; senza telefono non c'è video da elaborare.
    private func aggiornaMotore() {
        guard Self.effettiSulComputer else {
            StatoMotoreEffetti.condiviso.imposta(ImpostazioniMotore())
            return
        }
        let scelti = effettiComputer
        let pro = attivo == nil || attivo?.capacita?.pro == true
        // Con la fotocamera posteriore niente specchio né sfondo (si riprendono tornando alla frontale).
        let frontale = Self.conFrontale(attivo)
        var motore = ImpostazioniMotore()
        motore.calore = scelti.calore
        motore.specchia = scelti.specchia && frontale
        // Con «Luce da studio» o «Ritratto» del telefono accesi, le nostre restano spente: mai due.
        motore.luceVolto = scelti.luceVolto && !luceSistema
        if frontale, (scelti.sfondo == ModiSfondo.sfocato && !sfocaturaSistema) || (scelti.sfondo == ModiSfondo.sostituito && pro) {
            motore.sfondo = scelti.sfondo
            motore.intensitaSfondo = scelti.intensitaSfondo
            motore.immagineSfondo = scelti.sfondo == ModiSfondo.sostituito ? immagineSfondoAttuale : nil
        }
        if pro {
            motore.filtro = scelti.filtro
            motore.luminosita = scelti.luminosita
            motore.contrasto = scelti.contrasto
            motore.saturazione = scelti.saturazione
            motore.nitidezza = scelti.nitidezza
            motore.pelle = scelti.pelle
            motore.inquadratura = scelti.inquadratura
            let scritta = scelti.scrittaDaInviare
            motore.nome = scritta.nome
            motore.ruolo = scritta.ruolo ?? ""
            motore.logo = ImmaginiComputer.condivise.improntaLogo != nil
        }
        StatoMotoreEffetti.condiviso.imposta(motore)
        aggiornaImmaginiMotore(sfondo: motore.sfondo == ModiSfondo.sostituito ? motore.immagineSfondo : nil, logo: motore.logo)
        // I pulsanti dei telefoni telecomando seguono specchio, sfondo e luce.
        for telefono in telefoni { mandaStatoEffetti(a: telefono) }
    }

    /// Quale sfondo e quale logo il motore ha già (o sta leggendo): si rileggono solo quando cambiano.
    @ObservationIgnored private var sfondoNelMotore: String?
    @ObservationIgnored private var logoNelMotore: String?

    /// Legge in sottofondo l'immagine dello sfondo (le immagini grandi del Mac, «Sfondi/grandi», o la tua immagine
    /// salvata) e il logo, e li passa al motore. Fino ad allora il motore usa il fondo di `Tema`.
    private func aggiornaImmaginiMotore(sfondo id: String?, logo: Bool) {
        let immagini = ImmaginiComputer.condivise
        if let id {
            let personale = id == SfondiPronti.personale
            let chiave = personale ? "\(id)-\(immagini.improntaSfondo ?? "")" : id
            // Anche se il motore non ce l'ha: una lettura scartata (scelta cambiata intanto) si rifà alla prossima volta.
            if chiave != sfondoNelMotore || StatoMotoreEffetti.condiviso.istantanea().sfondo?.id != id {
                sfondoNelMotore = chiave
                let dati = personale ? immagini.datiSfondo() : nil
                let url = personale ? nil : Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "Sfondi/grandi")
                Task.detached(priority: .userInitiated) {
                    let immagine = RiduzioneImmagine.leggi(dati: dati, url: url, latoMassimo: 1920)
                    // Un'altra scelta arrivata intanto vince: questa non si mette più.
                    guard StatoMotoreEffetti.condiviso.impostazioni.immagineSfondo == id else { return }
                    StatoMotoreEffetti.condiviso.impostaSfondo(id: id, immagine: immagine)
                }
            }
        }
        let chiaveLogo = logo ? immagini.improntaLogo : nil
        if chiaveLogo != logoNelMotore {
            logoNelMotore = chiaveLogo
            let dati = chiaveLogo == nil ? nil : immagini.datiLogo()
            Task.detached(priority: .userInitiated) {
                let immagine = dati.flatMap { RiduzioneImmagine.leggi(dati: $0, url: nil, latoMassimo: 512) }
                StatoMotoreEffetti.condiviso.impostaLogo(immagine)
            }
        }
    }

    /// Alla prima `capacita` di ogni sessione, con gli effetti sul computer (Protocollo.md, «Effetti sul computer»):
    /// un telefono con `capacita.effettiSulComputer` riceve `comando.effettiSulComputer` (spegne tutta la sua pipeline
    /// effetti e manda il video com'è) e poi `effetti`, per i suoi pulsanti; uno di prima riceve il `comando` che spegne
    /// i suoi effetti di immagine (`spegniEffettiDelTelefono`).
    private func decidiEffetti(_ telefono: TelefonoCollegato) {
        guard Self.effettiSulComputer, telefono.effettiSulComputer == nil, let sessione = telefono.sessione,
              let capacita = telefono.capacita else { return }
        guard capacita.effettiSulComputer == true else {
            telefono.effettiSulComputer = false
            spegniEffettiDelTelefono(telefono)
            return
        }
        telefono.effettiSulComputer = true
        sessione.comanda(Comando(effettiSulComputer: true))
        registra(String(localized: "Effetti di immagine sul Mac: il telefono manda il video com'è"), di: telefono)
        mandaStatoEffetti(a: telefono, sempre: true)
    }

    /// Specchio, sfondo e luce sul volto come li fa il motore per questo telefono: le stesse regole di `aggiornaMotore`
    /// (Pro del telefono per lo sfondo sostituito; mai due sfocature o due luci con Ritratto o Luce da studio accesi;
    /// specchio e sfondo solo con la frontale).
    private func statoEffetti(di telefono: TelefonoCollegato) -> StatoEffettiComputer {
        let scelti = effettiComputer
        let stato = telefono.statoTelefono
        let frontale = Self.conFrontale(telefono)
        var sfondo = ModiSfondo.nessuno
        if frontale && scelti.sfondo == ModiSfondo.sfocato && stato?.sfocaturaSistema != true {
            sfondo = ModiSfondo.sfocato
        } else if frontale && scelti.sfondo == ModiSfondo.sostituito && telefono.capacita?.pro == true {
            sfondo = ModiSfondo.sostituito
        }
        return StatoEffettiComputer(specchia: scelti.specchia && frontale, sfondo: sfondo,
                                    luceVolto: scelti.luceVolto && stato?.luceSistema != true)
    }

    /// `effetti` a un telefono telecomando, solo quando cambia (`sempre`: anche se non cambia, come risposta).
    private func mandaStatoEffetti(a telefono: TelefonoCollegato, sempre: Bool = false) {
        guard Self.effettiSulComputer, telefono.effettiSulComputer == true, let sessione = telefono.sessione else { return }
        let stato = statoEffetti(di: telefono)
        guard sempre || stato != telefono.effettiInviati else { return }
        telefono.effettiInviati = stato
        sessione.mandaEffetti(stato)
    }

    /// `chiedi-effetto`: un tocco su Specchia, Sfoca o Luce del telefono, come i pulsanti del Mac (tutti e tre gratis).
    /// «sfocato» accende la sfocatura con l'ultimo livello scelto sul Mac, ma non sopra Ritratto del telefono (mai due
    /// sfocature); la luce non si accende sopra Luce da studio. Un altro `sfondo` si ignora; specchio e sfondo si
    /// ignorano anche con la fotocamera posteriore, come i pulsanti grigi del Mac. La risposta è sempre un
    /// `effetti`, anche se non cambia nulla.
    private func applica(_ richiesta: RichiestaEffetto, da telefono: TelefonoCollegato) {
        guard Self.effettiSulComputer, telefono.effettiSulComputer == true else { return }
        let stato = telefono.statoTelefono
        let frontale = Self.conFrontale(telefono)
        var nuovi = effettiComputer
        if let specchia = richiesta.specchia, frontale { nuovi.specchia = specchia }
        if let luce = richiesta.luceVolto, !luce || stato?.luceSistema != true { nuovi.luceVolto = luce }
        if frontale, richiesta.sfondo == ModiSfondo.nessuno {
            nuovi.sfondo = ModiSfondo.nessuno
        } else if frontale, richiesta.sfondo == ModiSfondo.sfocato, stato?.sfocaturaSistema != true {
            nuovi.sfondo = ModiSfondo.sfocato
            nuovi.intensitaSfondo = livelloSfocatura.intensita
        }
        guard nuovi != effettiComputer else {
            mandaStatoEffetti(a: telefono, sempre: true)
            return
        }
        registra(String(localized: "Effetti cambiati dal telefono"), di: telefono)
        // Il `didSet` aggiorna il motore e manda `effetti` ai telefoni telecomando a cui è cambiato; a questo sempre,
        // una volta sola (l'ultimo mandato si dimentica prima).
        telefono.effettiInviati = nil
        effettiComputer = nuovi
    }

    /// Per un telefono di prima, con gli effetti sul computer: un solo `comando` che spegne i suoi effetti di immagine
    /// (sfondo, filtro, regolazioni, pelle, calore, luce sul volto, scritta e logo, specchio, inquadratura), così
    /// niente si fa due volte. Doppia vista e postura restano come sono.
    private func spegniEffettiDelTelefono(_ telefono: TelefonoCollegato) {
        guard Self.effettiSulComputer, let sessione = telefono.sessione else { return }
        let spenti = Comando(filtro: Filtri.naturale,
                             regolazioni: Regolazioni(luminosita: 0, contrasto: 0, saturazione: 0, nitidezza: 0),
                             sfondo: ModiSfondo.nessuno, pelle: 0, inquadratura: false, luceVolto: false,
                             scritta: .nessuna, specchia: false, togliLogo: true, calore: 0)
        sessione.comanda(spenti)
        registra(String(localized: "Effetti di immagine sul Mac: spenti sul telefono"), di: telefono)
    }

    /// Ogni secondo, con le statistiche di un telefono: gli avvisi del motore subito (qualità scesa, Vision in errore),
    /// e ogni 30 secondi, mentre lavora, i suoi tempi.
    private func registraMotore(_ misure: MotoreEffetti.Misure, note: [MotoreEffetti.Nota], di telefono: TelefonoCollegato) {
        for nota in note {
            switch nota {
            case .livello(let livello, let visionMs, let resaMs, let fotogrammaMs, let persi):
                registra(String(localized: "Effetti: il Mac non regge \(fotogrammaMs) ms a fotogramma (Vision \(visionMs) ms, resa \(resaMs) ms, persi \(persi)): \(livello.descrizione)"),
                         di: telefono)
            case .erroreVision(let errore, let totale):
                registra(String(localized: "Effetti: Vision non riuscita (\(totale) in tutto): \(errore)"), di: telefono)
            case .poolEsaurito(let totale):
                registra(String(localized: "Effetti: buffer di uscita esauriti, fotogramma non elaborato (\(totale) in tutto)"),
                         di: telefono)
            case .maschera(let larghezza, let altezza, let fotogrammaLarghezza, let fotogrammaAltezza, let livello):
                registra(String(localized: "Effetti: maschera di Vision \(larghezza)×\(altezza), fotogramma \(fotogrammaLarghezza)×\(fotogrammaAltezza) (\(livello.descrizione))"),
                         di: telefono)
            case .bordoSemplice:
                registra(String(localized: "Effetti: Core Image su questo Mac non regge i conti del guided filter: bordo della persona semplice"),
                         di: telefono)
            }
        }
        guard let effettiMs = misure.effettiMs else {
            telefono.secondiMotore = 0
            return
        }
        telefono.secondiMotore += 1
        guard telefono.secondiMotore >= 30 else { return }
        telefono.secondiMotore = 0
        let vision = misure.visionMs.map { Lingua.decimali(String(format: "%.1f ms", $0)) } ?? "—"
        let resa = misure.resaMs.map { Lingua.decimali(String(format: "%.1f ms", $0)) } ?? "—"
        // «con la maschera di prima»: fotogrammi resi con l'ultima maschera perché Vision era occupata (normale a
        // gruppi di arrivo); «scartati»: persi dalla resa, che non teneva il ritmo.
        registra(String(localized: "Effetti sul Mac: \(effettiMs) ms (Vision \(vision), resa \(resa); \(misure.livello.descrizione)) · scartati \(misure.scartati) · con la maschera di prima \(misure.maschereRiusate)"),
                 di: telefono)
        // La zona persona (solo con lo sfondo acceso): con la stanza vuota «con volto o corpo» deve restare fermo e
        // «adesso» dire nessuna persona; se sale, Vision trova volti o corpi falsi e lì la zona si apre.
        let zona = misure.zona
        if zona.analisi > 0 {
            let adesso = zona.presenza > 0.5 ? String(localized: "persona dentro") : String(localized: "nessuna persona")
            registra(String(localized: "Zona persona (dall'avvio): analisi \(zona.analisi) · con volto o corpo \(zona.conProve) · errori di Vision \(zona.errori) · adesso \(adesso)"),
                     di: telefono)
        }
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
        case "grandangolo": String(localized: "0,5×")
        case "principale": "1×"
        case "tele": String(localized: "Tele")
        case "frontale": String(localized: "Frontale")
        default: obiettivo.capitalized
        }
    }

    /// Nome completo di un obiettivo, come nel glossario: «Grandangolo 0,5×», «Principale 1×».
    static func nome(obiettivo: String) -> String {
        switch obiettivo {
        case "grandangolo": String(localized: "Grandangolo 0,5×")
        case "principale": String(localized: "Principale 1×")
        case "tele": String(localized: "Tele")
        case "frontale": String(localized: "Frontale")
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
    /// Vale per il telefono scelto in quel momento, anche se intanto se ne sceglie un altro.
    /// Con gli effetti sul computer partono solo «Volto e scrivania» e la postura: gli altri li applica già il motore
    /// del Mac (il valore è in `effetti`, cioè in `effettiComputer`).
    func mandaEffetto(_ chiave: String, attesa: Duration? = nil, _ comando: @escaping (Effetti) -> Comando) {
        if Self.effettiSulComputer, !Effetti.chiaviDelTelefono.contains(chiave) { return }
        guard let telefono = attivo else { return }
        telefono.modificheEffetti[chiave] = .now
        telefono.inviiInAttesa[chiave]?.cancel()
        telefono.inviiInAttesa[chiave] = nil
        guard let attesa else {
            telefono.sessione?.comanda(comando(telefono.effetti))
            return
        }
        telefono.inviiInAttesa[chiave] = Task { [weak telefono] in
            try? await Task.sleep(for: attesa)
            guard let telefono, !Task.isCancelled else { return }
            telefono.inviiInAttesa[chiave] = nil
            telefono.modificheEffetti[chiave] = .now
            telefono.sessione?.comanda(comando(telefono.effetti))
        }
    }

    /// Le quattro regolazioni insieme: quelle di prima di «Azzera», per «Annulla» e ⌘Z.
    struct ValoriRegolazioni: Equatable {
        var luminosita = 0.0
        var contrasto = 0.0
        var saturazione = 0.0
        var nitidezza = 0.0
    }

    /// Dopo «Azzera», per 8 secondi: i valori di prima. Il pannello dice «Regolazioni azzerate» con «Annulla».
    private(set) var regolazioniPrimaDiAzzerare: ValoriRegolazioni?
    @ObservationIgnored private var compitoAzzerate: Task<Void, Never>?
    /// L'`undoManager` della finestra dove si è premuto «Azzera»: «Annulla» nel pannello toglie anche la voce di ⌘Z.
    @ObservationIgnored private weak var annullaAzzera: UndoManager?
    /// Il telefono azzerato (nil con gli effetti sul computer): i valori di prima tornano solo a lui.
    @ObservationIgnored private weak var telefonoAzzerato: TelefonoCollegato?

    /// «Regolazioni azzerate · Annulla» si vede: da poco azzerate, nessun cursore toccato dopo e nella webcam
    /// lo stesso telefono di allora.
    var azzeramentoAnnullabile: Bool {
        regolazioniPrimaDiAzzerare != nil && valoriRegolazioni == ValoriRegolazioni()
            && regolazioniDi(telefonoAzzerato)
    }

    /// Le regolazioni di adesso sono di `telefono` (preso con `destinatarioRegolazioni`): con un altro telefono nella
    /// webcam, o quello andato via, «Annulla» e ⌘Z non rimettono i suoi valori all'altro.
    private func regolazioniDi(_ telefono: TelefonoCollegato?) -> Bool {
        Self.effettiSulComputer || (telefono != nil && telefono === attivo)
    }

    private var destinatarioRegolazioni: TelefonoCollegato? { Self.effettiSulComputer ? nil : attivo }

    var valoriRegolazioni: ValoriRegolazioni {
        let attuali = effetti
        return ValoriRegolazioni(luminosita: attuali.luminosita, contrasto: attuali.contrasto,
                                 saturazione: attuali.saturazione, nitidezza: attuali.nitidezza)
    }

    /// «Azzera» delle regolazioni: tutte e quattro a 0 in un solo comando (M27). Si può tornare indietro per
    /// 8 secondi con «Annulla» nel pannello, e con ⌘Z (Modifica › Annulla) finché la finestra lo ricorda.
    func azzeraRegolazioni(annulla undoManager: UndoManager?) {
        let prima = valoriRegolazioni
        guard prima != ValoriRegolazioni() else { return }
        let telefono = destinatarioRegolazioni
        impostaRegolazioni(ValoriRegolazioni())
        regolazioniPrimaDiAzzerare = prima
        telefonoAzzerato = telefono
        compitoAzzerate?.cancel()
        compitoAzzerate = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            self.regolazioniPrimaDiAzzerare = nil
        }
        annullaAzzera = undoManager
        undoManager?.registerUndo(withTarget: self) { [weak undoManager, weak telefono] ricevitore in
            MainActor.assumeIsolated {
                // Nella webcam ora c'è un altro telefono: i valori di prima non sono suoi, niente da rimettere.
                guard ricevitore.regolazioniDi(telefono) else { return }
                ricevitore.rimettiRegolazioni(prima)
                // Ripeti (⇧⌘Z): azzera di nuovo, e di nuovo si può annullare.
                undoManager?.registerUndo(withTarget: ricevitore) { [weak undoManager, weak telefono] ricevitore in
                    MainActor.assumeIsolated {
                        guard ricevitore.regolazioniDi(telefono) else { return }
                        ricevitore.azzeraRegolazioni(annulla: undoManager)
                    }
                }
                undoManager?.setActionName(String(localized: "Azzera regolazioni"))
            }
        }
        undoManager?.setActionName(String(localized: "Azzera regolazioni"))
    }

    /// «Annulla» accanto a «Regolazioni azzerate»: i valori di prima tornano, e ⌘Z non ha più niente da rifare.
    func annullaAzzeramento() {
        guard azzeramentoAnnullabile, let prima = regolazioniPrimaDiAzzerare else { return }
        annullaAzzera?.removeAllActions(withTarget: self)
        annullaAzzera = nil
        rimettiRegolazioni(prima)
    }

    private func rimettiRegolazioni(_ valori: ValoriRegolazioni) {
        compitoAzzerate?.cancel()
        compitoAzzerate = nil
        regolazioniPrimaDiAzzerare = nil
        telefonoAzzerato = nil
        impostaRegolazioni(valori)
    }

    /// Le quattro regolazioni in un solo comando (o nel motore del Mac, con gli effetti sul computer).
    private func impostaRegolazioni(_ valori: ValoriRegolazioni) {
        if Self.effettiSulComputer {
            var nuovi = effettiComputer
            nuovi.luminosita = valori.luminosita
            nuovi.contrasto = valori.contrasto
            nuovi.saturazione = valori.saturazione
            nuovi.nitidezza = valori.nitidezza
            effettiComputer = nuovi
            return
        }
        guard let telefono = attivo else { return }
        let chiavi = [Effetti.chiaveLuminosita, Effetti.chiaveContrasto, Effetti.chiaveSaturazione, Effetti.chiaveNitidezza]
        for chiave in chiavi {
            telefono.inviiInAttesa[chiave]?.cancel()
            telefono.inviiInAttesa[chiave] = nil
            telefono.modificheEffetti[chiave] = .now
        }
        telefono.effetti.luminosita = valori.luminosita
        telefono.effetti.contrasto = valori.contrasto
        telefono.effetti.saturazione = valori.saturazione
        telefono.effetti.nitidezza = valori.nitidezza
        telefono.sessione?.comanda(Comando(regolazioni: Regolazioni(luminosita: valori.luminosita, contrasto: valori.contrasto,
                                                                   saturazione: valori.saturazione, nitidezza: valori.nitidezza)))
    }

    // MARK: - Gobbo (pacchetto funzioni)

    /// Il telefono scelto sa fare il gobbo.
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
        guard gobboDisponibile, let telefono = attivo else { return }
        if telefono.gobboAttivo {
            comandaGobbo(Gobbo(attivo: false), a: telefono)
            telefono.gobboAttivo = false
        } else if testoGobboCambiato {
            guard !gobbo.testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            mandaTestoGobbo(attivo: true)
        } else {
            comandaGobbo(Gobbo(attivo: true), a: telefono)
            telefono.gobboAttivo = true
        }
    }

    /// Manda testo, velocità e dimensione insieme: il gobbo riparte dall'inizio, fermo o in movimento.
    func mandaTestoGobbo(attivo inMovimento: Bool) {
        guard gobboDisponibile, let telefono = attivo else { return }
        let testo = testoGobboDaInviare
        comandaGobbo(Gobbo(testo: testo, velocita: gobbo.velocita, attivo: inMovimento, dimensione: gobbo.dimensione), a: telefono)
        telefono.testoGobboInviato = testo
        telefono.gobboAttivo = inMovimento
        telefono.posizioneGobbo = 0
        registra(String(localized: "Gobbo: testo mandato al telefono (\(testo.count) caratteri)"), di: telefono)
    }

    /// «Dall'inizio»: con un testo nuovo lo manda, altrimenti salta all'inizio.
    func gobboDallInizio() {
        guard gobboDisponibile, let telefono = attivo else { return }
        if testoGobboCambiato {
            mandaTestoGobbo(attivo: telefono.gobboAttivo)
        } else {
            comandaGobbo(Gobbo(posizione: 0), a: telefono)
            telefono.posizioneGobbo = 0
        }
    }

    private static let chiaveGobbo = "gobbo"

    /// Manda un `gobbo` cambiato da qui: per un attimo lo `stato` non sovrascrive «Avvia/Pausa» e la posizione
    /// (uno `stato` partito prima del comando direbbe ancora il valore vecchio).
    private func comandaGobbo(_ comando: Gobbo, a telefono: TelefonoCollegato) {
        telefono.modificheEffetti[Self.chiaveGobbo] = .now
        telefono.sessione?.mandaGobbo(comando)
    }

    /// Il gobbo è stato comandato da qui da poco: lo `stato` aspetta.
    private func gobboAppenaComandato(_ telefono: TelefonoCollegato) -> Bool {
        guard let ultima = telefono.modificheEffetti[Self.chiaveGobbo] else { return false }
        return ContinuousClock.now - ultima < Self.precedenzaLocale
    }

    /// Velocità e dimensione: il valore è già in `gobbo`; arrivano al telefono solo se ha già un testo
    /// (altrimenti partono insieme al testo).
    func mandaVelocitaGobbo() {
        guard let telefono = attivo else { return }
        telefono.inviiInAttesa["gobboVelocita"]?.cancel()
        telefono.inviiInAttesa["gobboVelocita"] = Task { [weak self, weak telefono] in
            try? await Task.sleep(for: Self.attesaCursori)
            guard let self, let telefono, !Task.isCancelled else { return }
            telefono.inviiInAttesa["gobboVelocita"] = nil
            guard telefono.collegato, telefono.capacita?.gobbo == true, telefono.testoGobboInviato != nil else { return }
            telefono.sessione?.mandaGobbo(Gobbo(velocita: self.gobbo.velocita))
        }
    }

    func mandaDimensioneGobbo() {
        guard gobboDisponibile, testoGobboInviato != nil else { return }
        attivo?.sessione?.mandaGobbo(Gobbo(dimensione: gobbo.dimensione))
    }

    // MARK: - Profili della fotocamera (funzione 23)

    private static let chiaveProfili = "profiliFotocamera"

    /// I comandi della fotocamera salvati per nome, sul Mac: valgono con qualsiasi telefono.
    private(set) var profili: [String: Controlli] = Ricevitore.leggiProfili()

    /// L'ultimo profilo pronto scelto nel pannello «Profilo» (`ProfiloPronto.id`, Profili.swift); resta da una volta
    /// all'altra. Se gli effetti del telefono non gli corrispondono più, il pannello dice «Personalizzato».
    var profiloPronto: String? = UserDefaults.standard.string(forKey: Preferenze.profiloPronto) {
        didSet { UserDefaults.standard.set(profiloPronto, forKey: Preferenze.profiloPronto) }
    }

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

    /// Manda al telefono scelto tutti i comandi del profilo in un solo messaggio.
    func applicaProfilo(_ nome: String) {
        guard let profilo = profili[nome], attivo != nil else { return }
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
        var nuovi = profilo
        nuovi.obiettivo = obiettivo
        nuovi.zoom = zoom
        // Se la torcia non è stata mandata, resta com'era.
        if capacita?.torcia != true { nuovi.torcia = torcia }
        nuovi.esposizioneManuale = manuale
        controlli = nuovi
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

    // MARK: - Scollega

    /// I tre pulsanti «Scollega» (in fondo ai controlli, Impostazioni › Telefoni, scheda del telefono) passano di
    /// qui (punto 8, M1). Se il telefono è in onda (un'app usa la webcam) o lo registri, prima chiede, con «Annulla»
    /// come pulsante predefinito; altrimenti scollega subito, come sempre. Senza telefono: quello nella webcam.
    func chiediEScollega(_ scelto: TelefonoCollegato? = nil) {
        guard let telefono = scelto ?? attivo else { return }
        // Webcam virtuale e registrazione mostrano solo il telefono nella webcam: scollegare l'altro non le tocca.
        let nellaWebcam = telefono === attivo
        let inOnda = nellaWebcam && webcamInUso
        let registra = nellaWebcam && (staRegistrando?() ?? false)
        if inOnda || registra {
            let nome = telefono.telefono.nome
            var frasi: [String] = []
            if inOnda {
                if let app = AppCompatibile.nomeUnico(firme: appWebcam) {
                    // «un sito nel browser» apre la frase: con la maiuscola.
                    let app = app.prefix(1).uppercased() + app.dropFirst()
                    frasi.append(String(localized: "\(app) resta senza video e non si ricollega da solo."))
                } else {
                    frasi.append(String(localized: "La chiamata resta senza video e il telefono non si ricollega da solo."))
                }
            } else {
                frasi.append(String(localized: "Il telefono non si ricollega da solo."))
            }
            if registra { frasi.append(String(localized: "La registrazione si ferma e si salva in Filmati › WebcamLR.")) }
            guard Domanda.conferma(String(localized: "Scollegare «\(nome)»?"), dettaglio: frasi.joined(separator: " "),
                                   pulsante: String(localized: "Scollega")) else { return }
        }
        scollega(telefono)
    }

    /// Chiusura voluta: il telefono riceve l'arrivederci e non si ricollega da solo.
    func scollega(_ telefono: TelefonoCollegato) {
        guard telefoni.contains(where: { $0 === telefono }) else { return }
        if telefono.sessione != nil { registra(String(localized: "Scollegato dal Mac"), di: telefono) }
        // Via cavo il Mac riaprirebbe il canale da solo: il cavo resta in pausa fino a «Collega via cavo».
        if let sessione = telefono.sessione, vieneDalCavo(sessione) { pausaCavo.insert(ObjectIdentifier(sessione)) }
        telefono.sessione?.chiudi()
        telefono.sessione = nil
        dimentica(telefono)
    }

    // MARK: - Eventi delle sessioni

    private func gestisci(_ evento: SessioneComputer.Evento, da identita: ObjectIdentifier) {
        if gestisciCandidato(evento, da: identita) { return }
        guard let telefono = telefonoDellaSessione(identita) else {
            // Una sessione sostituita (o chiusa per la precedenza del cavo) che finisce adesso.
            if case .chiusa = evento { chiusaSessione(identita) }
            return
        }
        let scelto = telefono === attivo
        switch evento {
        case .ciao(let ciao, _, let via):
            telefono.compitoAttesa?.cancel()
            telefono.compitoAttesa = nil
            // Per VoiceOver (M22): collegato la prima volta, «di nuovo collegato» dopo una riconnessione.
            let annuncio = telefono.primaSessione ? String(localized: "\(ciao.nome) collegato")
                : telefono.collegamento == .riconnessione ? String(localized: "\(ciao.nome) di nuovo collegato") : nil
            if telefono.primaSessione {
                // Il telefono che non era tornato si ricollega: il banner non serve più.
                if telefonoNonTornato == ciao.nome { telefonoNonTornato = nil }
                Notifiche.condivise.telefonoCollegato(ciao.nome)
            } else if let sessione = telefono.sessione {
                // Lo stesso telefono torna: forse con una sessione nuova, ripartita in automatico.
                // Gli si rimanda quello che il Mac mostra, così i due restano d'accordo.
                let attuali = telefono.controlli
                let comando = Comando(obiettivo: attuali.obiettivo, zoom: attuali.zoom, torcia: attuali.torcia, esposizione: attuali.esposizione,
                                      bianco: attuali.biancoAutomatico ? 0 : Int(attuali.bianco),
                                      iso: attuali.esposizioneManuale ? attuali.iso : 0,
                                      tempo: attuali.esposizioneManuale ? attuali.tempo : 0)
                // Come per i comandi dal pannello: il primo `stato` della sessione nuova, partito prima di questo
                // comando, non riporta indietro per un attimo i valori che il Mac mostra (1.14).
                telefono.segnaComando(comando)
                sessione.comanda(comando)
                // Gli effetti no: restano salvati sul telefono e tornano col primo `stato`. Il gobbo invece vive
                // sul telefono solo per la sessione: si rimanda completo, dalla posizione dell'ultimo `stato`.
                if let testo = telefono.testoGobboInviato {
                    sessione.mandaGobbo(Gobbo(testo: testo, velocita: gobbo.velocita, attivo: telefono.gobboAttivo,
                                              dimensione: gobbo.dimensione, posizione: telefono.posizioneGobbo))
                }
            }
            telefono.primaSessione = false
            registra(String(localized: "«\(ciao.nome)» collegato via \(via.testo)"), di: telefono, annuncio: annuncio)
            // Effetti sul computer: si decide alla prima `capacita` di questa sessione (`decidiEffetti`).
            telefono.effettiSulComputer = nil
            telefono.effettiInviati = nil
            // Sessione nuova: il formato arriva con il suo messaggio `formato`, la richiesta dei fps si può rifare.
            // Anche l'audio: si richiede con la prima `capacita` (o subito, se è lo stesso telefono di prima).
            telefono.formatoTelefono = nil
            telefono.formatoChiesto = nil
            telefono.audioComandato = false
            telefono.audioDalTelefono = nil
            telefono.fpsChiesti = nil
            if scelto {
                microfono.ferma()
                telefono.sessione?.usaMicrofono(true)
            }
            // La misura dell'avvio è di questa sessione: arriva con il suo primo fotogramma a schermo.
            telefono.tempoAvvio = nil
            telefono.telefono = ciao
            telefono.tipoCollegamento = via
            tieniSveglia(true)
            telefono.collegamento = .collegato
            aggiornaStatoInOnda(telefono)
            // Sessione nuova: `in-onda` e `anteprima` si rimandano sempre. L'`anteprima` subito dopo il `benvenuto`
            // (già partito dalla sessione): serve ai telefoni di prima del 27 ottobre, che senza anteprima e senza app
            // andavano in pausa; quelli nuovi continuano finché il Mac è aperto.
            segnalaInOnda(telefono, sempre: true)
            segnalaAnteprima(telefono, sempre: true)
            chiediAudioSeServe()
        case .conferma, .confermaFinita, .rifiutata:
            // Solo i candidati chiedono conferma o vengono rifiutati (sopra).
            break
        case .formato(let formato):
            telefono.formatoTelefono = formato
            registra(String(localized: "Formato: \(formato.codec == .hevc ? "HEVC" : "H.264") \(formato.larghezza)×\(formato.altezza) a \(formato.fps) fps"), di: telefono)
        case .stato(let stato):
            if stato.pausa != telefono.statoTelefono?.pausa {
                registraPausa(stato.pausa, di: telefono)
            }
            // I 10 minuti del sottofondo contano dall'inizio di questo motivo, non della pausa (che può essere cominciata
            // prima con un altro motivo).
            if stato.pausa == MotiviPausa.sottofondo {
                if !telefono.inSottofondo {
                    telefono.inizioSottofondo = .now
                    if scelto { sceltoInSottofondo?() }
                }
            } else {
                telefono.inizioSottofondo = nil
            }
            let obiettivoPrima = telefono.statoTelefono?.obiettivo
            let temperaturaPrima = telefono.statoTelefono?.temperatura ?? .normale
            telefono.statoTelefono = stato
            // Il telefono non preferisce più il Wi-Fi: il cavo messo in pausa per lui riparte.
            if telefono.preferenzaCollegamento != PreferenzeCollegamento.wifi {
                riprendiCavoPerPreferenza(String(localized: "Cavo USB di nuovo pronto: il telefono non preferisce più il Wi-Fi"), di: telefono)
            }
            controllaBatteria(stato, di: telefono)
            // L'avviso fisso sul caldo (passo 6) finisce nel registro quando compare o cambia.
            if let caldo = Self.testoCalore(stato.temperatura), caldo != Self.testoCalore(temperaturaPrima) {
                registra(caldo, di: telefono)
            }
            if telefono.controlli.obiettivo == stato.obiettivo { telefono.controlli.obiettivo = nil }
            telefono.allineaEffetti(stato)
            telefono.allineaControlli(stato, obiettivoPrima: obiettivoPrima)
            // La sfocatura e la luce del sistema del telefono (Ritratto, Luce da studio) spengono le nostre: mai due.
            if scelto { aggiornaMotore() }
            mandaStatoEffetti(a: telefono)
            // Microfono acceso o spento sul telefono: solo un cambiamento dentro la stessa sessione conta.
            // Il primo `stato` di una sessione no: lì vale l'interruttore del Mac, che chiede l'audio da sé.
            let audioPrima = telefono.audioDalTelefono
            telefono.audioDalTelefono = stato.audio
            if scelto, let audio = stato.audio, let audioPrima, audio != audioPrima {
                microfonoDalTelefono(audio, telefono: telefono)
            }
            if gobboAppenaComandato(telefono) {
                // Il comando appena partito può non essere ancora arrivato: si aspetta il prossimo `stato`.
            } else if let statoGobbo = stato.gobbo {
                telefono.gobboAttivo = statoGobbo.attivo
                telefono.posizioneGobbo = min(max(statoGobbo.posizione, 0), 1)
            } else {
                // Nessun gobbo sul telefono: fermo. La posizione resta, per un eventuale invio di nuovo.
                telefono.gobboAttivo = false
            }
        case .capacita(let nuove):
            telefono.capacita = nuove
            // Obiettivo senza ISO manuale: l'interruttore sparisce e torna il cursore dell'esposizione.
            if nuove.isoMinimo == nil { telefono.controlli.esposizioneManuale = false }
            chiediAudioSeServe()
            // Effetti sul computer: alla prima `capacita` della sessione, telecomando o spegnimento dei suoi effetti.
            decidiEffetti(telefono)
            // WebcamLR Pro (`capacita.pro`): le regole del motore effetti.
            if scelto { aggiornaMotore() }
            mandaStatoEffetti(a: telefono)
        case .statistiche(var nuove):
            // Il motore effetti del Mac (MotoreEffetti.swift): il suo tempo nelle «Tappe», gli avvisi nel registro.
            let motore = telefono.schermo.motore
            let misure = motore.misure()
            nuove.effettiMs = misure.effettiMs
            registraMotore(misure, note: motore.prendiNote(), di: telefono)
            telefono.statistiche = nuove
            telefono.contaFotogrammi(arrivati: nuove.fps)
            registraNumeri(nuove, di: telefono)
            registraRitardo(nuove, di: telefono, scelto: scelto)
            if scelto {
                audioInArrivo = nuove.pacchettiAudio > 0
                if !audioInArrivo { livelloMicrofono = 0 }
            }
            telefono.storicoLatenza.append(nuove.latenzaMs)
            if telefono.storicoLatenza.count > GraficoLatenza.secondi {
                telefono.storicoLatenza.removeFirst(telefono.storicoLatenza.count - GraficoLatenza.secondi)
            }
        case .avvio(let testo, let riga):
            telefono.tempoAvvio = testo
            registra(riga, di: telefono)
        case .silenzio:
            // In sottofondo il telefono può smettere anche i `ping`: resta «In pausa», non «Riconnessione».
            if telefono.inSottofondo {
                registra(String(localized: "Nessun dato da 3 secondi: il telefono è in sottofondo, lo aspetto fino a 10 minuti"), di: telefono)
                return
            }
            registra(String(localized: "Nessun dato da 3 secondi"), di: telefono,
                     annuncio: scelto && telefono.collegamento != .riconnessione ? String(localized: "Riconnessione in corso…") : nil)
            telefono.collegamento = .riconnessione
            // Preferenza Wi-Fi ma il Wi-Fi non risponde: il cavo, se c'è, serve a non perdere il video.
            riprendiCavoPerPreferenza(String(localized: "Il Wi-Fi non risponde: provo con il cavo USB"), di: telefono)
        case .usaProspettiva:
            // Dal telefono CAM 2: come «Usa prospettiva» qui. `scegli` rimanda `in-onda` a tutti.
            if !scelto {
                registra(String(localized: "Il telefono chiede di andare nella webcam"), di: telefono)
                // Mentre registri chiede prima anche qui (punto 7, come su Windows). La domanda fuori dalla gestione
                // del messaggio; dopo, il telefono deve essere ancora collegato e non già nella webcam (`scegli`).
                Task { @MainActor [weak self, weak telefono] in
                    guard let self, let telefono, self.confermaSeFerma(.telefono) else { return }
                    self.scegli(telefono)
                }
            }
        case .chiediEffetto(let richiesta):
            applica(richiesta, da: telefono)
        case .ripresa:
            registra(String(localized: "I dati arrivano di nuovo"), di: telefono,
                     annuncio: scelto && telefono.collegamento == .riconnessione
                        ? String(localized: "\(telefono.telefono.nome) di nuovo collegato") : nil)
            telefono.collegamento = .collegato
            aggiornaStatoInOnda(telefono)
        case .chiusa:
            telefono.sessione = nil
            telefono.formatoTelefono = nil
            telefono.formatoChiesto = nil
            telefono.audioComandato = false
            telefono.fpsChiesti = nil
            if scelto {
                audioInArrivo = false
                livelloMicrofono = 0
                microfono.ferma()
            }
            registra(String(localized: "Collegamento chiuso"), di: telefono,
                     annuncio: scelto && !telefono.inSottofondo && telefono.collegamento != .riconnessione
                        ? String(localized: "Riconnessione in corso…") : nil)
            chiusaSessione(identita)
            telefono.collegamento = .riconnessione
            riprendiCavoPerPreferenza(String(localized: "Il Wi-Fi non risponde: provo con il cavo USB"), di: telefono)
            telefono.statistiche.fps = 0
            telefono.statistiche.megabitAlSecondo = 0
            // In sottofondo la pausa resta a schermo (scheda, finestra, webcam) e il telefono ha 10 minuti dall'inizio
            // della pausa per tornare; altrimenti i soliti 15 secondi.
            let sottofondo = telefono.inSottofondo
            var attesa = Self.attesaRiconnessione
            if sottofondo {
                let passato = telefono.inizioSottofondo.map { ContinuousClock.now - $0 } ?? .zero
                attesa = max(Self.attesaSottofondo - passato, Self.attesaRiconnessione)
                registra(String(localized: "Il telefono è in sottofondo: lo aspetto fino a 10 minuti"), di: telefono)
            }
            telefono.compitoAttesa?.cancel()
            telefono.compitoAttesa = Task { [weak self, weak telefono] in
                try? await Task.sleep(for: attesa)
                guard let self, let telefono, !Task.isCancelled, telefono.sessione == nil else { return }
                Notifiche.condivise.telefonoPerso(telefono.telefono.nome)
                self.registra(sottofondo ? String(localized: "Il telefono non è tornato entro 10 minuti")
                              : String(localized: "Il telefono non è tornato entro 15 secondi"), di: telefono,
                              annuncio: String(localized: "\(telefono.telefono.nome) non è tornato. Riapri WebcamLR sul telefono."))
                // Anche con la finestra in primo piano, dove la notifica non arriva: il banner fisso lo dice
                // (la riga qui sopra resta nel registro).
                self.telefonoNonTornato = telefono.telefono.nome
                self.dimentica(telefono)
            }
        }
    }

    /// «Consenti» o «Non consentire»: vale solo per la sessione che l'ha chiesto.
    private func rispondiConferma(_ consentito: Bool, da identita: ObjectIdentifier) {
        Notifiche.condivise.ritiraRichiestaConsenso()
        guard inConferma == identita else { return }
        inConferma = nil
        registra(consentito ? String(localized: "Telefono consentito") : String(localized: "Telefono non consentito"))
        candidati[identita]?.rispondi(consentito: consentito)
    }

    private func chiudiConferma() {
        inConferma = nil
        finestraConferma.chiudi()
        Notifiche.condivise.ritiraRichiestaConsenso()
    }

    /// Una riga nel registro a ogni inizio (o cambio di motivo) e fine di pausa: il motivo e, alla fine, quanto è durata.
    private func registraPausa(_ nuova: String?, di telefono: TelefonoCollegato) {
        if let nuova {
            if telefono.inizioPausa == nil { telefono.inizioPausa = .now }
            let testo = String(localized: "Il telefono è in pausa: \(Self.testoPausa(nuova))")
            registra(testo, di: telefono, annuncio: telefono === attivo ? testo : nil)
        } else {
            let secondi = telefono.inizioPausa.map { Int((ContinuousClock.now - $0).components.seconds) } ?? 0
            telefono.inizioPausa = nil
            registra(String(localized: "Il video riprende dopo \(secondi) s di pausa"), di: telefono,
                     annuncio: telefono === attivo ? String(localized: "Il video riprende") : nil)
        }
    }

    /// Una notifica sola quando la batteria scende al 20% senza caricatore (funzione 22), per ogni telefono.
    private func controllaBatteria(_ stato: StatoTelefono, di telefono: TelefonoCollegato) {
        if stato.inCarica || stato.batteria > 25 {
            telefono.avvisoBatteriaDato = false
        } else if stato.batteria >= 0, stato.batteria <= 20, !telefono.avvisoBatteriaDato {
            telefono.avvisoBatteriaDato = true
            if let testo = Self.testoBatteria(stato) { registra(testo, di: telefono) }
            Notifiche.condivise.batteriaBassa(telefono.telefono.nome, percentuale: stato.batteria)
        }
    }

    /// L'avviso fisso sul caldo (funzione 33): resta sopra il video finché il telefono è molto caldo; nil se va bene.
    static func testoCalore(_ temperatura: Temperatura) -> String? {
        switch temperatura {
        case .critica:
            String(localized: "Il telefono è troppo caldo: il video può fermarsi. Toglilo dal sole o dalla custodia.")
        case .moltoCalda:
            String(localized: "Il telefono è molto caldo: la qualità può calare. Toglilo dal sole o dalla custodia.")
        default:
            nil
        }
    }

    /// L'avviso fisso sulla batteria: al 20% o meno senza caricatore, finché non lo colleghi; nil altrimenti.
    static func testoBatteria(_ stato: StatoTelefono) -> String? {
        guard stato.batteria >= 0, stato.batteria <= 20, !stato.inCarica else { return nil }
        return String(localized: "Batteria del telefono al \(stato.batteria)%: collega il caricatore.")
    }

    /// Niente App Nap né timer rallentati mentre arriva il video: la latenza resta costante (funzione 20).
    /// Si tiene anche durante la riconnessione, fino a quando l'ultimo telefono viene dimenticato.
    private func tieniSveglia(_ sveglia: Bool) {
        if sveglia, attivitaCollegamento == nil {
            attivitaCollegamento = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical], reason: "Video dal telefono in tempo reale")
        } else if !sveglia, let attivita = attivitaCollegamento {
            ProcessInfo.processInfo.endActivity(attivita)
            attivitaCollegamento = nil
        }
    }

    /// Il telefono non c'è più (scollegato o non tornato): via dall'elenco. Se era quello nella webcam,
    /// ci va l'altro, se c'è.
    private func dimentica(_ telefono: TelefonoCollegato) {
        let eraScelto = telefono === attivo
        if eraScelto { primaDiDimenticareLoScelto?() }
        telefono.annullaInvii()
        telefono.schermo.inviaImmagini(a: nil)
        telefono.schermo.svuota()
        telefoni.removeAll { $0 === telefono }
        controllaAttesaTelefono()
        aggiornaPosti()
        // Un posto libero: chi è stato rifiutato può ripresentarsi subito con il suo avviso.
        ultimiRifiuti = [:]
        if eraScelto {
            scegliAttivo(telefoni.first, precedente: nil)
        } else {
            aggiornaUscite()
        }
        if telefoni.isEmpty {
            tieniSveglia(false)
            miniaturaVisibile = false
        }
    }
}
