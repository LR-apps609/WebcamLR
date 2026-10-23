import Foundation

public enum Piattaforma: String, Codable, Sendable {
    case iphone, android, mac, windows
}

public enum Codec: String, Codable, Sendable {
    case h264, hevc
}

/// Gli stessi livelli di `ProcessInfo.ThermalState` su iOS.
public enum Temperatura: String, Codable, Sendable {
    case normale
    case calda
    case moltoCalda = "molto-calda"
    case critica
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

    public init(batteria: Int, inCarica: Bool, temperatura: Temperatura, obiettivo: String) {
        self.batteria = batteria
        self.inCarica = inCarica
        self.temperatura = temperatura
        self.obiettivo = obiettivo
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

    public init(obiettivi: [String], zoomMassimo: Double, torcia: Bool, isoMinimo: Double? = nil, isoMassimo: Double? = nil) {
        self.obiettivi = obiettivi
        self.zoomMassimo = zoomMassimo
        self.torcia = torcia
        self.isoMinimo = isoMinimo
        self.isoMassimo = isoMassimo
    }
}

/// Comandi della fotocamera dal computer: si applicano solo i campi presenti.
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

    public init(obiettivo: String? = nil, zoom: Double? = nil, torcia: Bool? = nil,
                esposizione: Double? = nil, bianco: Int? = nil, fuoco: String? = nil,
                iso: Double? = nil, tempo: Int? = nil) {
        self.iso = iso
        self.tempo = tempo
        self.obiettivo = obiettivo
        self.zoom = zoom
        self.torcia = torcia
        self.esposizione = esposizione
        self.bianco = bianco
        self.fuoco = fuoco
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
    case arrivederci
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
        case .arrivederci: "arrivederci"
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
        case "arrivederci": self = .arrivederci
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
