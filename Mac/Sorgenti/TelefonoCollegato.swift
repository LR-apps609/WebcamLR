import Foundation
import Observation
import Stile
import WebcamLRProtocollo

/// Un telefono collegato al Mac (P21 «Più telefoni insieme»): tutto ciò che prima il `Ricevitore` teneva
/// per «il» telefono. Resta lo stesso oggetto finché è lo stesso telefono (stesso codice di sicurezza, 1.1),
/// anche quando la sessione cambia: riconnessione, cavo al posto del Wi-Fi (1.9). Così il suo schermo,
/// i comandi, gli effetti e il gobbo restano dove sono.
///
/// Solo dati e piccole regole: chi decide (accettare, sostituire, scegliere quale va nella webcam) è il `Ricevitore`.
@Observable
@MainActor
final class TelefonoCollegato: Identifiable {
    /// `nonisolated`: soddisfa `Identifiable` (requisito non isolato) anche se la classe è sulla coda principale.
    nonisolated let id = UUID()
    /// Il codice di sicurezza del telefono (1.1): due telefoni con lo stesso nome restano diversi.
    let impronta: String
    /// Il suo video: decodifica, anteprima, foto e registrazione. Uno per telefono, così il passaggio
    /// alla webcam virtuale è immediato (l'altro telefono è già decodificato, niente fotogramma chiave da aspettare).
    let schermo: Schermo

    /// Il `ciao` dell'ultima sessione: nome, piattaforma, versione dell'app.
    var telefono: Ciao
    /// Come è collegato: Wi-Fi, cavo USB, Wi-Fi diretto, cavo di rete (1.2).
    var tipoCollegamento: TipoCollegamento?
    /// Collegato, in onda (solo quello nella webcam) o in riconnessione. Mai `nessunTelefono`: senza telefono
    /// l'oggetto non c'è più.
    var collegamento: FaseCollegamento = .collegato
    var statoTelefono: StatoTelefono?
    var statistiche = Statistiche()
    /// Secondi dall'ultima riga «Ricevuti» nel registro (ogni 10, con gli effetti accesi).
    @ObservationIgnored var secondiNumeri = 0
    /// Secondi dall'ultima riga «Da vetro a uscita» nel registro (ogni 30, mentre il video arriva).
    @ObservationIgnored var secondiRitardo = 0
    /// «Avvio: 0,9 s» della sessione attuale (1.11); nil finché il video non è a schermo.
    var tempoAvvio: String?
    /// La latenza di ogni secondo, al massimo gli ultimi 60, per il grafico (funzione 31).
    var storicoLatenza: [Int?] = []
    /// Cosa si può comandare; nil finché il telefono non lo dice.
    var capacita: Capacita?
    /// I comandi della fotocamera come li mostra il Mac: quelli mandati da qui, riallineati a ogni `stato` che li porta
    /// (dalla 1.14 il telefono rimanda zoom, torcia, esposizione, bianco, ISO e tempo attuali).
    var controlli = Ricevitore.Controlli()
    /// Gli effetti come li mostra il Mac, riallineati a ogni `stato` (pacchetto effetti).
    var effetti = Effetti()
    /// Il testo del gobbo già mandato a questo telefono; nil se non ne ha ancora ricevuto uno.
    var testoGobboInviato: String?
    /// Dall'ultimo `stato.gobbo`: scorre o no, e dove è arrivato (da 0 a 1).
    var gobboAttivo = false
    var posizioneGobbo = 0.0

    /// La sessione attuale; nil durante la riconnessione.
    @ObservationIgnored var sessione: SessioneComputer?
    /// Il primo `ciao` di questo telefono non è ancora stato gestito: alla prima sessione non si rimanda nulla.
    @ObservationIgnored var primaSessione = true
    /// Quando ogni effetto è stato cambiato dal Mac: per un attimo lo `stato` non lo sovrascrive.
    @ObservationIgnored var modificheEffetti: [String: ContinuousClock.Instant] = [:]
    /// I comandi in attesa di partire (cursori e testi), per chiave.
    @ObservationIgnored var inviiInAttesa: [String: Task<Void, Never>] = [:]
    /// Il formato che il telefono dice di mandare, per la richiesta dei 60 fps (P12).
    @ObservationIgnored var formatoTelefono: FormatoVideo?
    /// I fps già chiesti mentre la webcam è in uso: una richiesta sola per volta.
    @ObservationIgnored var fpsChiesti: Int?
    /// `comando.audio = true` già mandato alla sessione attuale (P20).
    @ObservationIgnored var audioComandato = false
    /// L'ultimo `stato.audio` di questa sessione: se cambia, il microfono è stato acceso o spento sul telefono.
    @ObservationIgnored var audioDalTelefono: Bool?
    /// Fotogrammi attesi (dal `formato`) e arrivati negli ultimi secondi, per la qualità in parole come sul telefono.
    @ObservationIgnored private var fotogrammiRecenti: [(attesi: Int, arrivati: Int)] = []
    @ObservationIgnored private var primoSecondoVideo = true
    /// Fotogrammi mancati negli ultimi 5 secondi (stima: attesi meno arrivati, oltre un margine del 10%).
    private(set) var perditeRecenti = 0
    /// La notifica della batteria bassa è già partita; si riarma col caricatore o sopra il 25%.
    @ObservationIgnored var avvisoBatteriaDato = false
    /// L'attesa dei 15 secondi dopo una caduta.
    @ObservationIgnored var compitoAttesa: Task<Void, Never>?
    /// Gli ultimi `anteprima` e `in-onda` mandati, per mandarli solo quando cambiano (pausa intelligente).
    @ObservationIgnored var anteprimaSegnalata: Bool?
    @ObservationIgnored var inOndaSegnalato: Bool?
    /// L'ultimo `in-onda.selezionato` mandato: è il telefono nella webcam (CAM 1)?
    @ObservationIgnored var selezioneSegnalata: Bool?
    /// Quando la strada è cambiata l'ultima volta (cavo al posto del Wi-Fi o il contrario): in «Automatico» per
    /// `Ricevitore.pausaCambioStrada` non si cambia di nuovo da soli (Protocollo.md, «Scelta del collegamento»).
    @ObservationIgnored var ultimoCambioStrada: ContinuousClock.Instant?

    init(impronta: String, telefono: Ciao, schermo: Schermo) {
        self.impronta = impronta
        self.telefono = telefono
        self.schermo = schermo
    }

    /// La strada preferita dal telefono (`stato.collegamento.preferenza`, `PreferenzeCollegamento`): nil se il telefono
    /// non la dice (telefono vecchio, o senza la scelta del collegamento); una sconosciuta vale come automatico.
    var preferenzaCollegamento: String? {
        guard let preferenza = statoTelefono?.collegamento?.preferenza else { return nil }
        return PreferenzeCollegamento.tutte.contains(preferenza) ? preferenza : PreferenzeCollegamento.automatico
    }

    /// Collegato, in onda o no (non in riconnessione).
    var collegato: Bool {
        switch collegamento {
        case .collegato, .inOnda: true
        default: false
        }
    }

    // MARK: - Effetti

    /// Lo `stato` del telefono porta gli effetti attuali, anche quelli cambiati sul telefono: l'interfaccia li segue,
    /// tranne quelli appena toccati dal Mac (il comando può non essere ancora arrivato).
    func allineaEffetti(_ stato: StatoTelefono) {
        let adesso = ContinuousClock.now
        let recenti = Set(modificheEffetti.filter { adesso - $0.value < Ricevitore.precedenzaLocale }.keys)
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
        // Quale immagine: un id sconosciuto resta com'è, il Ricevitore lo mostra come il primo sfondo pronto.
        if let immagine = stato.immagineSfondo, libero(Effetti.chiaveSfondo) { effetti.immagineSfondo = immagine }
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
        // Lo specchio è uno solo, del telefono: il Mac mostra quello che il telefono dice di mandare.
        if let valore = stato.specchia, libero(Effetti.chiaveSpecchia) { effetti.specchia = valore }
    }

    // MARK: - Comandi della fotocamera

    /// Chiavi della precedenza dei comandi della fotocamera (come per gli effetti, in `modificheEffetti`).
    static let chiaveZoom = "zoom"
    static let chiaveTorcia = "torcia"
    static let chiaveEsposizione = "esposizione"
    static let chiaveBianco = "bianco"
    static let chiaveManuale = "isoTempo"

    /// Un comando della fotocamera parte dal Mac: per un attimo lo `stato` non sovrascrive quei valori.
    func segnaComando(_ comando: Comando) {
        let adesso = ContinuousClock.now
        if comando.zoom != nil || comando.obiettivo != nil { modificheEffetti[Self.chiaveZoom] = adesso }
        if comando.torcia != nil || comando.obiettivo != nil { modificheEffetti[Self.chiaveTorcia] = adesso }
        if comando.esposizione != nil { modificheEffetti[Self.chiaveEsposizione] = adesso }
        if comando.bianco != nil { modificheEffetti[Self.chiaveBianco] = adesso }
        if comando.iso != nil || comando.tempo != nil { modificheEffetti[Self.chiaveManuale] = adesso }
    }

    /// I comandi della fotocamera seguono il telefono: pizzico, cambio di obiettivo, torcia spenta dalla frontale,
    /// ISO e tempo scelti sul telefono. Un telefono di prima della 1.14 non li manda: allora, a ogni cambio di obiettivo,
    /// zoom a 1 e torcia spenta, come fa il telefono. `obiettivoPrima`: quello dello `stato` precedente.
    func allineaControlli(_ stato: StatoTelefono, obiettivoPrima: String?) {
        let adesso = ContinuousClock.now
        func libero(_ chiave: String) -> Bool {
            guard let ultima = modificheEffetti[chiave] else { return true }
            return adesso - ultima >= Ricevitore.precedenzaLocale
        }
        let obiettivoCambiato = obiettivoPrima != nil && obiettivoPrima != stato.obiettivo
        if let zoom = stato.zoom {
            if libero(Self.chiaveZoom) { controlli.zoom = max(zoom, 1) }
        } else if obiettivoCambiato {
            controlli.zoom = 1
        }
        if let torcia = stato.torcia {
            if libero(Self.chiaveTorcia) { controlli.torcia = torcia }
        } else if obiettivoCambiato {
            controlli.torcia = false
        }
        if let esposizione = stato.esposizione, libero(Self.chiaveEsposizione) {
            controlli.esposizione = min(max(esposizione, -2), 2)
        }
        if let bianco = stato.bianco, libero(Self.chiaveBianco) {
            controlli.biancoAutomatico = bianco == 0
            if bianco != 0 { controlli.bianco = Double(min(max(bianco, 2500), 7500)) }
        }
        if let iso = stato.iso, let tempo = stato.tempo, libero(Self.chiaveManuale) {
            let manuale = iso > 0 && tempo > 0 && capacita?.isoMinimo != nil
            controlli.esposizioneManuale = manuale
            if manuale {
                controlli.iso = iso
                controlli.tempo = tempo
            }
        }
    }

    // MARK: - Qualità

    /// Ogni secondo, con le statistiche: quanti fotogrammi mancano rispetto al `formato` del telefono.
    /// Il telefono conta i fotogrammi che scarta; il Mac non li vede, ma vede quelli che non arrivano.
    /// In pausa o senza formato non si conta nulla.
    func contaFotogrammi(arrivati: Int) {
        guard let atteso = formatoTelefono?.fps, atteso > 0, statoTelefono?.pausa == nil, arrivati > 0 else {
            fotogrammiRecenti = []
            primoSecondoVideo = true
            if perditeRecenti != 0 { perditeRecenti = 0 }
            return
        }
        // Il primo secondo con il video (avvio, fine di una pausa) è quasi sempre incompleto: non conta.
        if primoSecondoVideo {
            primoSecondoVideo = false
            return
        }
        fotogrammiRecenti.append((attesi: atteso, arrivati: arrivati))
        if fotogrammiRecenti.count > 5 { fotogrammiRecenti.removeFirst(fotogrammiRecenti.count - 5) }
        let attesi = fotogrammiRecenti.reduce(0) { $0 + $1.attesi }
        let arrivatiTotale = fotogrammiRecenti.reduce(0) { $0 + $1.arrivati }
        // Margine del 10%: la misura al secondo oscilla (29, 31…) e un cambio di formato costa qualche fotogramma.
        let nuove = max(0, attesi - arrivatiTotale - attesi / 10)
        if nuove != perditeRecenti { perditeRecenti = nuove }
    }

    /// La qualità del collegamento in parole, con la stessa regola del telefono (latenza e fotogrammi persi).
    var qualita: QualitaCollegamento? {
        statistiche.latenzaMs.map { QualitaCollegamento(latenzaMs: $0, perdite: perditeRecenti) }
    }

    /// Il telefono se ne va: nessun comando in attesa parte più.
    func annullaInvii() {
        inviiInAttesa.values.forEach { $0.cancel() }
        inviiInAttesa = [:]
        compitoAttesa?.cancel()
        compitoAttesa = nil
    }
}

/// I posti per i telefoni collegati insieme (P21), letti dalle sessioni sulla loro coda prima del `benvenuto`:
/// un telefono in più quando i posti sono pieni riceve l'`arrivederci` senza essere mai stato «collegato».
/// Lo stesso telefono (stesso codice di sicurezza) ha sempre posto: è una riconnessione o il cavo.
/// Il `Ricevitore` lo aggiorna dalla coda principale a ogni cambio dell'elenco dei telefoni.
final class PostiTelefoni: @unchecked Sendable {
    let massimo: Int
    private let blocco = NSLock()
    private var impronte: Set<String> = []

    init(massimo: Int) {
        self.massimo = massimo
    }

    func aggiorna(_ nuove: Set<String>) {
        blocco.lock()
        impronte = nuove
        blocco.unlock()
    }

    func ammette(_ impronta: String) -> Bool {
        blocco.lock()
        defer { blocco.unlock() }
        return impronte.contains(impronta) || impronte.count < massimo
    }
}
