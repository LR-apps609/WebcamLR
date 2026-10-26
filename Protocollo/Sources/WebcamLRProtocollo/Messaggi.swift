import Foundation

// Valori enumerati: uno sconosciuto (o non testuale) non fa fallire il messaggio, diventa il ripiego
// del documento («Valori sconosciuti» in Protocollo.md). La codifica resta quella del `rawValue`.

public enum Piattaforma: String, Codable, Sendable {
    case iphone, android, mac, windows
    /// Un valore che questa versione non conosce: non si manda mai.
    case sconosciuta

    public init(from decoder: Decoder) throws {
        let valore = try? decoder.singleValueContainer().decode(String.self)
        self = valore.flatMap(Piattaforma.init(rawValue:)) ?? .sconosciuta
    }
}

public enum Codec: String, Codable, Sendable {
    case h264, hevc

    /// Un codec sconosciuto si legge come h264, il codec che tutti sanno fare.
    public init(from decoder: Decoder) throws {
        let valore = try? decoder.singleValueContainer().decode(String.self)
        self = valore.flatMap(Codec.init(rawValue:)) ?? .h264
    }
}

/// Gli stessi livelli di `ProcessInfo.ThermalState` su iOS.
public enum Temperatura: String, Codable, Sendable {
    case normale
    case calda
    case moltoCalda = "molto-calda"
    case critica

    /// Un livello sconosciuto si legge come normale.
    public init(from decoder: Decoder) throws {
        let valore = try? decoder.singleValueContainer().decode(String.self)
        self = valore.flatMap(Temperatura.init(rawValue:)) ?? .normale
    }
}

public struct Ciao: Codable, Equatable, Sendable {
    public var versione: Int
    public var nome: String
    public var piattaforma: Piattaforma
    public var versioneApp: String

    public init(versione: Int = Servizio.versioneProtocollo, nome: String, piattaforma: Piattaforma, versioneApp: String) {
        self.versione = versione
        self.nome = nome
        self.piattaforma = piattaforma
        self.versioneApp = versioneApp
    }
}

public struct Benvenuto: Codable, Equatable, Sendable {
    public var versione: Int
    public var nome: String
    public var piattaforma: Piattaforma

    public init(versione: Int = Servizio.versioneProtocollo, nome: String, piattaforma: Piattaforma) {
        self.versione = versione
        self.nome = nome
        self.piattaforma = piattaforma
    }
}

public struct FormatoVideo: Codable, Equatable, Sendable {
    public var codec: Codec
    public var larghezza: Int
    public var altezza: Int
    public var fps: Int

    public init(codec: Codec, larghezza: Int, altezza: Int, fps: Int) {
        self.codec = codec
        self.larghezza = larghezza
        self.altezza = altezza
        self.fps = fps
    }
}

public struct StatoTelefono: Codable, Equatable, Sendable {
    /// Da 0 a 100, oppure -1 se non nota.
    public var batteria: Int
    public var inCarica: Bool
    public var temperatura: Temperatura
    public var obiettivo: String

    // Effetti attuali (facoltativi): il computer li mostra, anche se sono stati cambiati sul telefono.
    public var filtro: String?
    public var regolazioni: Regolazioni?
    public var sfondo: String?
    public var intensitaSfondo: Double?
    public var pelle: Double?
    public var inquadratura: Bool?
    public var luceVolto: Bool?
    /// Nome vuoto = nessuna scritta.
    public var scritta: Scritta?
    public var doppiaVista: Bool?
    public var postura: Bool?
    /// Il microfono sta inviando audio.
    public var audio: Bool?
    /// Perché il telefono non manda video (`MotiviPausa`); assente = non è in pausa.
    public var pausa: String?
    public var gobbo: StatoGobbo?
    /// Il video inviato è specchiato: l'unica fonte di verità per i due lati (vedi «Specchio» nel documento).
    public var specchia: Bool?

    // Comandi della fotocamera attuali (facoltativi), anche se cambiati sul telefono: stessi valori di `Comando`.
    public var zoom: Double?
    public var torcia: Bool?
    public var esposizione: Double?
    public var bianco: Int?
    public var iso: Double?
    public var tempo: Int?
    /// La strada in uso, la preferenza e le strade disponibili (vedi «Scelta del collegamento» nel documento).
    public var collegamento: StatoCollegamento?

    public init(batteria: Int, inCarica: Bool, temperatura: Temperatura, obiettivo: String,
                filtro: String? = nil, regolazioni: Regolazioni? = nil, sfondo: String? = nil,
                intensitaSfondo: Double? = nil, pelle: Double? = nil, inquadratura: Bool? = nil,
                luceVolto: Bool? = nil, scritta: Scritta? = nil, doppiaVista: Bool? = nil,
                postura: Bool? = nil, audio: Bool? = nil, pausa: String? = nil, gobbo: StatoGobbo? = nil,
                specchia: Bool? = nil, zoom: Double? = nil, torcia: Bool? = nil, esposizione: Double? = nil,
                bianco: Int? = nil, iso: Double? = nil, tempo: Int? = nil, collegamento: StatoCollegamento? = nil) {
        self.batteria = batteria
        self.inCarica = inCarica
        self.temperatura = temperatura
        self.obiettivo = obiettivo
        self.filtro = filtro
        self.regolazioni = regolazioni
        self.sfondo = sfondo
        self.intensitaSfondo = intensitaSfondo
        self.pelle = pelle
        self.inquadratura = inquadratura
        self.luceVolto = luceVolto
        self.scritta = scritta
        self.doppiaVista = doppiaVista
        self.postura = postura
        self.audio = audio
        self.pausa = pausa
        self.gobbo = gobbo
        self.specchia = specchia
        self.zoom = zoom
        self.torcia = torcia
        self.esposizione = esposizione
        self.bianco = bianco
        self.iso = iso
        self.tempo = tempo
        self.collegamento = collegamento
    }
}

public struct Ping: Codable, Equatable, Sendable {
    /// Orologio del computer, in microsecondi.
    public var t: UInt64

    public init(t: UInt64) {
        self.t = t
    }
}

public struct Pong: Codable, Equatable, Sendable {
    /// Copiato dal `ping`.
    public var t: UInt64
    /// Orologio del telefono, in microsecondi.
    public var telefono: UInt64

    public init(t: UInt64, telefono: UInt64) {
        self.t = t
        self.telefono = telefono
    }
}

public struct Latenza: Codable, Equatable, Sendable {
    /// Latenza misurata dal computer, in millisecondi.
    public var ms: Int

    public init(ms: Int) {
        self.ms = ms
    }
}

/// Cosa il computer può comandare su questo telefono.
public struct Capacita: Codable, Equatable, Sendable {
    public var obiettivi: [String]
    public var zoomMassimo: Double
    public var torcia: Bool
    /// Limiti della sensibilità manuale dell'obiettivo attuale.
    public var isoMinimo: Double?
    public var isoMassimo: Double?
    /// Filtri disponibili (`Filtri`), nell'ordine in cui mostrarli.
    public var filtri: [String]?
    /// Sfondo sfocato o sostituito.
    public var sfondo: Bool?
    public var pelle: Bool?
    public var inquadratura: Bool?
    public var luceVolto: Bool?
    public var scritta: Bool?
    /// Volto e scrivania con due obiettivi insieme (serve la multicamera).
    public var doppiaVista: Bool?
    public var postura: Bool?
    public var gobbo: Bool?
    /// Microfono disponibile.
    public var audio: Bool?
    /// Risoluzioni dell'obiettivo attuale con i fotogrammi al secondo massimi.
    public var formati: [FormatoSupportato]?
    /// Il telefono sa specchiare il video inviato dal vivo, su `comando.specchia`.
    public var specchia: Bool?
    /// WebcamLR Pro è sbloccato su questo telefono (vedi «WebcamLR Pro» nel documento). Assente = gratis.
    public var pro: Bool?
    /// Il telefono sa cambiare strada e accetta `comando.collegamento`.
    public var sceltaCollegamento: Bool?

    public init(obiettivi: [String], zoomMassimo: Double, torcia: Bool, isoMinimo: Double? = nil, isoMassimo: Double? = nil,
                filtri: [String]? = nil, sfondo: Bool? = nil, pelle: Bool? = nil, inquadratura: Bool? = nil,
                luceVolto: Bool? = nil, scritta: Bool? = nil, doppiaVista: Bool? = nil, postura: Bool? = nil,
                gobbo: Bool? = nil, audio: Bool? = nil, formati: [FormatoSupportato]? = nil, specchia: Bool? = nil,
                pro: Bool? = nil, sceltaCollegamento: Bool? = nil) {
        self.obiettivi = obiettivi
        self.zoomMassimo = zoomMassimo
        self.torcia = torcia
        self.isoMinimo = isoMinimo
        self.isoMassimo = isoMassimo
        self.filtri = filtri
        self.sfondo = sfondo
        self.pelle = pelle
        self.inquadratura = inquadratura
        self.luceVolto = luceVolto
        self.scritta = scritta
        self.doppiaVista = doppiaVista
        self.postura = postura
        self.gobbo = gobbo
        self.audio = audio
        self.formati = formati
        self.specchia = specchia
        self.pro = pro
        self.sceltaCollegamento = sceltaCollegamento
    }
}

/// Comandi della fotocamera e degli effetti dal computer: si applicano solo i campi presenti.
public struct Comando: Codable, Equatable, Sendable {
    public var obiettivo: String?
    public var zoom: Double?
    public var torcia: Bool?
    /// Compensazione dell'esposizione in stop, da -2 a +2.
    public var esposizione: Double?
    /// Kelvin da 2500 a 7500; 0 = automatico.
    public var bianco: Int?
    /// Per ora solo "continuo".
    public var fuoco: String?
    /// ISO manuale; 0 = automatico.
    public var iso: Double?
    /// Tempo di posa come denominatore (60 = 1/60 s); 0 = automatico.
    public var tempo: Int?
    /// Uno dei `Filtri`; "naturale" = nessun filtro.
    public var filtro: String?
    public var regolazioni: Regolazioni?
    /// Uno dei `ModiSfondo`.
    public var sfondo: String?
    /// Da 0 a 1.
    public var intensitaSfondo: Double?
    /// Ritocco della pelle, da 0 (spento) a 1.
    public var pelle: Double?
    /// Inquadratura automatica che segue il volto.
    public var inquadratura: Bool?
    /// Esposizione con priorità al volto.
    public var luceVolto: Bool?
    /// Sottopancia; nome vuoto = togli la scritta.
    public var scritta: Scritta?
    public var doppiaVista: Bool?
    /// Promemoria della postura sul telefono.
    public var postura: Bool?
    /// Microfono acceso o spento.
    public var audio: Bool?
    /// Specchia il video inviato (quello che vedono le app); il telefono conferma in `stato.specchia`.
    public var specchia: Bool?
    /// La strada preferita (`PreferenzeCollegamento`); il telefono conferma in `stato.collegamento`.
    public var collegamento: String?

    public init(obiettivo: String? = nil, zoom: Double? = nil, torcia: Bool? = nil,
                esposizione: Double? = nil, bianco: Int? = nil, fuoco: String? = nil,
                iso: Double? = nil, tempo: Int? = nil,
                filtro: String? = nil, regolazioni: Regolazioni? = nil, sfondo: String? = nil,
                intensitaSfondo: Double? = nil, pelle: Double? = nil, inquadratura: Bool? = nil,
                luceVolto: Bool? = nil, scritta: Scritta? = nil, doppiaVista: Bool? = nil,
                postura: Bool? = nil, audio: Bool? = nil, specchia: Bool? = nil, collegamento: String? = nil) {
        self.iso = iso
        self.tempo = tempo
        self.obiettivo = obiettivo
        self.zoom = zoom
        self.torcia = torcia
        self.esposizione = esposizione
        self.bianco = bianco
        self.fuoco = fuoco
        self.filtro = filtro
        self.regolazioni = regolazioni
        self.sfondo = sfondo
        self.intensitaSfondo = intensitaSfondo
        self.pelle = pelle
        self.inquadratura = inquadratura
        self.luceVolto = luceVolto
        self.scritta = scritta
        self.doppiaVista = doppiaVista
        self.postura = postura
        self.audio = audio
        self.specchia = specchia
        self.collegamento = collegamento
    }
}

/// Un'app sta usando davvero la webcam virtuale: l'unico caso in cui si mostra il rosso.
public struct InOnda: Codable, Equatable, Sendable {
    public var attivo: Bool
    /// Il nome dell'app, se il computer lo conosce.
    public var app: String?

    public init(attivo: Bool, app: String? = nil) {
        self.attivo = attivo
        self.app = app
    }
}

/// La finestra di anteprima del computer è visibile: qualcuno sta guardando.
public struct Anteprima: Codable, Equatable, Sendable {
    public var visibile: Bool

    public init(visibile: Bool) {
        self.visibile = visibile
    }
}

/// Il gobbo: testo che scorre sullo schermo del telefono. Si applicano solo i campi presenti.
public struct Gobbo: Codable, Equatable, Sendable {
    /// Al massimo `Gobbo.lunghezzaMassima` caratteri; il telefono taglia il resto.
    public var testo: String?
    /// Righe al secondo, da 0.5 a 3.
    public var velocita: Double?
    public var attivo: Bool?
    /// Una delle `DimensioniGobbo`.
    public var dimensione: String?
    /// Da 0 (inizio) a 1 (fine): salta a quel punto.
    public var posizione: Double?

    public static let lunghezzaMassima = 20_000
    public static let velocitaMinima = 0.5
    public static let velocitaMassima = 3.0

    public init(testo: String? = nil, velocita: Double? = nil, attivo: Bool? = nil,
                dimensione: String? = nil, posizione: Double? = nil) {
        self.testo = testo
        self.velocita = velocita
        self.attivo = attivo
        self.dimensione = dimensione
        self.posizione = posizione
    }
}

/// Dal telefono: com'è codificato l'audio dei pacchetti di tipo 3.
public struct FormatoAudio: Codable, Equatable, Sendable {
    /// Per ora solo `FormatoAudio.aacLC`.
    public var codec: String
    /// Campioni al secondo (48000).
    public var frequenza: Int
    public var canali: Int
    /// AudioSpecificConfig (ISO 14496-3) in base64.
    public var configurazione: String

    public static let aacLC = "aac-lc"
    /// AudioSpecificConfig di AAC-LC, 48 kHz, mono: 0x11 0x88.
    public static let configurazioneAAC48kMono = Data([0x11, 0x88])
    /// Campioni in ogni pacchetto AAC-LC (21,33 ms a 48 kHz).
    public static let campioniPerPacchetto = 1024

    public init(codec: String = FormatoAudio.aacLC, frequenza: Int = 48_000, canali: Int = 1,
                configurazione: String = FormatoAudio.configurazioneAAC48kMono.base64EncodedString()) {
        self.codec = codec
        self.frequenza = frequenza
        self.canali = canali
        self.configurazione = configurazione
    }
}

/// Correzioni dell'immagine, ognuna da -1 a 1 (0 = neutra).
public struct Regolazioni: Codable, Equatable, Sendable {
    public var luminosita: Double?
    public var contrasto: Double?
    public var saturazione: Double?
    public var nitidezza: Double?

    public init(luminosita: Double? = nil, contrasto: Double? = nil, saturazione: Double? = nil, nitidezza: Double? = nil) {
        self.luminosita = luminosita
        self.contrasto = contrasto
        self.saturazione = saturazione
        self.nitidezza = nitidezza
    }
}

/// Sottopancia: nome e, se c'è, ruolo.
public struct Scritta: Codable, Equatable, Sendable {
    public var nome: String
    public var ruolo: String?

    public init(nome: String, ruolo: String? = nil) {
        self.nome = nome
        self.ruolo = ruolo
    }

    /// Da mandare per togliere la scritta.
    public static let nessuna = Scritta(nome: "")
}

/// Dove è arrivato il gobbo sul telefono.
public struct StatoGobbo: Codable, Equatable, Sendable {
    public var attivo: Bool
    /// Da 0 a 1.
    public var posizione: Double

    public init(attivo: Bool, posizione: Double) {
        self.attivo = attivo
        self.posizione = posizione
    }
}

/// Una risoluzione che il telefono sa inviare, con i fotogrammi al secondo massimi.
public struct FormatoSupportato: Codable, Equatable, Sendable {
    public var larghezza: Int
    public var altezza: Int
    public var fpsMassimo: Int

    public init(larghezza: Int, altezza: Int, fpsMassimo: Int) {
        self.larghezza = larghezza
        self.altezza = altezza
        self.fpsMassimo = fpsMassimo
    }
}

/// Come il telefono è collegato e come può esserlo (vedi «Scelta del collegamento» nel documento).
public struct StatoCollegamento: Codable, Equatable, Sendable {
    /// La strada in uso (`StradeCollegamento`); un nome sconosciuto si mostra come generico.
    public var attivo: String
    /// `PreferenzeCollegamento`; una sconosciuta vale come automatico.
    public var preferenza: String
    /// Le strade disponibili ora; se manca vale come elenco vuoto.
    public var strade: [StradaCollegamento]

    public init(attivo: String, preferenza: String, strade: [StradaCollegamento] = []) {
        self.attivo = attivo
        self.preferenza = preferenza
        self.strade = strade
    }

    private enum CodingKeys: String, CodingKey {
        case attivo, preferenza, strade
    }

    public init(from decoder: Decoder) throws {
        let contenitore = try decoder.container(keyedBy: CodingKeys.self)
        attivo = try contenitore.decode(String.self, forKey: .attivo)
        preferenza = try contenitore.decode(String.self, forKey: .preferenza)
        strade = try contenitore.decodeIfPresent([StradaCollegamento].self, forKey: .strade) ?? []
    }

    /// La strada con la latenza più bassa tra quelle misurate: solo un'informazione («più veloce ora»).
    public var piuVeloce: String? {
        strade.filter { $0.ms != nil }.min { $0.ms! < $1.ms! }?.tipo
    }
}

/// Una strada per arrivare al computer, con l'ultima latenza misurata su di essa (assente se mai misurata).
public struct StradaCollegamento: Codable, Equatable, Sendable {
    public var tipo: String
    public var ms: Int?

    public init(tipo: String, ms: Int? = nil) {
        self.tipo = tipo
        self.ms = ms
    }
}

/// Le strade di `StatoCollegamento.attivo` e `StradaCollegamento.tipo`.
public enum StradeCollegamento {
    public static let wifi = "wifi"
    public static let cavo = "cavo"
    public static let hotspot = "hotspot"
    public static let wifiDiretto = "wifiDiretto"
    public static let rete = "rete"
}

/// Le preferenze di `comando.collegamento` e `StatoCollegamento.preferenza`. Una sconosciuta vale come automatico.
public enum PreferenzeCollegamento {
    public static let automatico = "automatico"
    public static let wifi = "wifi"
    public static let cavo = "cavo"
    public static let tutte = [automatico, wifi, cavo]
}

/// Filtri del telefono. Un filtro sconosciuto si tratta come "naturale".
public enum Filtri {
    public static let naturale = "naturale"
    public static let caldo = "caldo"
    public static let freddo = "freddo"
    public static let luminoso = "luminoso"
    public static let cinema = "cinema"
    public static let vivido = "vivido"
    public static let tenue = "tenue"
    public static let biancoNero = "bianco-nero"
    public static let seppia = "seppia"
    public static let notte = "notte"
    public static let tutti = [naturale, caldo, freddo, luminoso, cinema, vivido, tenue, biancoNero, seppia, notte]
}

public enum ModiSfondo {
    public static let nessuno = "nessuno"
    public static let sfocato = "sfocato"
    public static let sostituito = "sostituito"
}

/// Perché il telefono è in pausa. Un motivo sconosciuto si mostra come una pausa qualsiasi.
public enum MotiviPausa {
    public static let facciaInGiu = "faccia-in-giu"
    public static let nessunaApp = "nessuna-app"
    public static let utente = "utente"
}

public enum DimensioniGobbo {
    public static let piccola = "piccola"
    public static let media = "media"
    public static let grande = "grande"
}

/// Stretta di mano del collegamento sicuro (versione 2), in chiaro: byte in base64.
public struct Stretta: Codable, Equatable, Sendable {
    public var versione: Int
    /// Chiave pubblica ECDH effimera, 65 byte.
    public var chiave: String
    /// Chiave pubblica di firma permanente, 65 byte.
    public var identita: String
    /// Solo dal computer: la sua firma sulla trascrizione.
    public var firma: String?

    public init(versione: Int, chiave: String, identita: String, firma: String? = nil) {
        self.versione = versione
        self.chiave = chiave
        self.identita = identita
        self.firma = firma
    }
}

/// Dal telefono, già cifrata: la sua firma sulla trascrizione, e il gettone se viene dal QR code.
public struct Prova: Codable, Equatable, Sendable {
    public var firma: String
    public var gettone: String?

    public init(firma: String, gettone: String? = nil) {
        self.firma = firma
        self.gettone = gettone
    }
}

/// Dal computer: il telefono non è ancora fidato, l'utente deve confermare con questo codice.
public struct Approvazione: Codable, Equatable, Sendable {
    public var codice: String

    public init(codice: String) {
        self.codice = codice
    }
}

/// Un messaggio di controllo: JSON con il campo `tipo` più i campi del messaggio.
public enum Messaggio: Equatable, Sendable {
    case ciao(Ciao)
    case benvenuto(Benvenuto)
    case formato(FormatoVideo)
    case stato(StatoTelefono)
    case ping(Ping)
    case pong(Pong)
    case latenza(Latenza)
    case capacita(Capacita)
    case comando(Comando)
    case inOnda(InOnda)
    case anteprima(Anteprima)
    case gobbo(Gobbo)
    case formatoAudio(FormatoAudio)
    case arrivederci
    case stretta(Stretta)
    case prova(Prova)
    case approvazione(Approvazione)
    /// Un tipo che questa versione non conosce: si ignora.
    case sconosciuto(String)

    public var tipo: String {
        switch self {
        case .ciao: "ciao"
        case .benvenuto: "benvenuto"
        case .formato: "formato"
        case .stato: "stato"
        case .ping: "ping"
        case .pong: "pong"
        case .latenza: "latenza"
        case .capacita: "capacita"
        case .comando: "comando"
        case .inOnda: "in-onda"
        case .anteprima: "anteprima"
        case .gobbo: "gobbo"
        case .formatoAudio: "formato-audio"
        case .arrivederci: "arrivederci"
        case .stretta: "stretta"
        case .prova: "prova"
        case .approvazione: "approvazione"
        case .sconosciuto(let tipo): tipo
        }
    }
}

extension Messaggio: Codable {
    private enum Chiavi: String, CodingKey {
        case tipo
    }

    public init(from decoder: Decoder) throws {
        let contenitore = try decoder.container(keyedBy: Chiavi.self)
        switch try contenitore.decode(String.self, forKey: .tipo) {
        case "ciao": self = .ciao(try Ciao(from: decoder))
        case "benvenuto": self = .benvenuto(try Benvenuto(from: decoder))
        case "formato": self = .formato(try FormatoVideo(from: decoder))
        case "stato": self = .stato(try StatoTelefono(from: decoder))
        case "ping": self = .ping(try Ping(from: decoder))
        case "pong": self = .pong(try Pong(from: decoder))
        case "latenza": self = .latenza(try Latenza(from: decoder))
        case "capacita": self = .capacita(try Capacita(from: decoder))
        case "comando": self = .comando(try Comando(from: decoder))
        case "in-onda": self = .inOnda(try InOnda(from: decoder))
        case "anteprima": self = .anteprima(try Anteprima(from: decoder))
        case "gobbo": self = .gobbo(try Gobbo(from: decoder))
        case "formato-audio": self = .formatoAudio(try FormatoAudio(from: decoder))
        case "arrivederci": self = .arrivederci
        case "stretta": self = .stretta(try Stretta(from: decoder))
        case "prova": self = .prova(try Prova(from: decoder))
        case "approvazione": self = .approvazione(try Approvazione(from: decoder))
        case let altro: self = .sconosciuto(altro)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var contenitore = encoder.container(keyedBy: Chiavi.self)
        try contenitore.encode(tipo, forKey: .tipo)
        switch self {
        case .ciao(let m): try m.encode(to: encoder)
        case .benvenuto(let m): try m.encode(to: encoder)
        case .formato(let m): try m.encode(to: encoder)
        case .stato(let m): try m.encode(to: encoder)
        case .ping(let m): try m.encode(to: encoder)
        case .pong(let m): try m.encode(to: encoder)
        case .latenza(let m): try m.encode(to: encoder)
        case .capacita(let m): try m.encode(to: encoder)
        case .comando(let m): try m.encode(to: encoder)
        case .inOnda(let m): try m.encode(to: encoder)
        case .anteprima(let m): try m.encode(to: encoder)
        case .gobbo(let m): try m.encode(to: encoder)
        case .formatoAudio(let m): try m.encode(to: encoder)
        case .stretta(let m): try m.encode(to: encoder)
        case .prova(let m): try m.encode(to: encoder)
        case .approvazione(let m): try m.encode(to: encoder)
        case .arrivederci, .sconosciuto: break
        }
    }
}

extension Pacchetto {
    public init(messaggio: Messaggio) throws {
        let codificatore = JSONEncoder()
        codificatore.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.init(tipo: .controllo, contenuto: try codificatore.encode(messaggio))
    }

    public func messaggio() throws -> Messaggio {
        guard tipo == .controllo else { throw ErroreProtocollo.contenutoNonValido }
        return try JSONDecoder().decode(Messaggio.self, from: contenuto)
    }
}
