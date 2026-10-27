import CryptoKit
import Foundation

public enum TipoPacchetto: UInt8, Sendable {
    case controllo = 1
    case video = 2
    case audio = 3
    /// Dal computer al telefono, solo se `capacita.immagini` (vedi `PacchettoImmagine`).
    case immagine = 4
}

public enum ErroreProtocollo: Error, Equatable {
    case tipoSconosciuto(UInt8)
    case troppoGrande(Int)
    case contenutoNonValido
}

/// Un pacchetto: 6 byte di intestazione (tipo, flag, lunghezza big-endian) e il contenuto.
public struct Pacchetto: Equatable, Sendable {
    public static let lunghezzaIntestazione = 6
    public static let lunghezzaMassima = 16 * 1024 * 1024

    public var tipo: TipoPacchetto
    public var flag: UInt8
    public var contenuto: Data

    public init(tipo: TipoPacchetto, flag: UInt8 = 0, contenuto: Data) {
        self.tipo = tipo
        self.flag = flag
        self.contenuto = contenuto
    }

    public func codificato() -> Data {
        var dati = Data(capacity: Self.lunghezzaIntestazione + contenuto.count)
        dati.append(tipo.rawValue)
        dati.append(flag)
        dati.append(contentsOf: Self.byteBigEndian(UInt32(contenuto.count)))
        dati.append(contenuto)
        return dati
    }

    static func byteBigEndian(_ valore: UInt32) -> [UInt8] {
        [UInt8(valore >> 24 & 0xFF), UInt8(valore >> 16 & 0xFF), UInt8(valore >> 8 & 0xFF), UInt8(valore & 0xFF)]
    }

    static func byteBigEndian(_ valore: UInt64) -> [UInt8] {
        (0..<8).reversed().map { UInt8(valore >> (UInt64($0) * 8) & 0xFF) }
    }
}

/// Raccoglie i byte che arrivano dalla connessione e restituisce i pacchetti completi.
public struct LettorePacchetti {
    private var buffer = Data()

    public init() {}

    public mutating func aggiungi(_ dati: Data) {
        buffer.append(dati)
    }

    /// Il prossimo pacchetto completo, oppure `nil` se servono altri byte.
    public mutating func prossimo() throws -> Pacchetto? {
        guard buffer.count >= Pacchetto.lunghezzaIntestazione else { return nil }
        let inizio = buffer.startIndex
        let tipoGrezzo = buffer[inizio]
        let flag = buffer[inizio + 1]
        let lunghezza = buffer[(inizio + 2)..<(inizio + 6)].reduce(0) { ($0 << 8) | Int($1) }

        guard let tipo = TipoPacchetto(rawValue: tipoGrezzo) else {
            throw ErroreProtocollo.tipoSconosciuto(tipoGrezzo)
        }
        guard lunghezza <= Pacchetto.lunghezzaMassima else {
            throw ErroreProtocollo.troppoGrande(lunghezza)
        }
        guard buffer.count >= Pacchetto.lunghezzaIntestazione + lunghezza else { return nil }

        let fine = inizio + Pacchetto.lunghezzaIntestazione + lunghezza
        let contenuto = Data(buffer[(inizio + Pacchetto.lunghezzaIntestazione)..<fine])
        buffer.removeSubrange(inizio..<fine)
        return Pacchetto(tipo: tipo, flag: flag, contenuto: contenuto)
    }
}

/// Un fotogramma video compresso (Annex B) con il suo timestamp in microsecondi.
public struct FotogrammaVideo: Equatable, Sendable {
    public static let flagChiave: UInt8 = 1 << 0
    public static let flagParametri: UInt8 = 1 << 1

    public var timestamp: UInt64
    public var chiave: Bool
    public var conParametri: Bool
    public var dati: Data

    public init(timestamp: UInt64, chiave: Bool, conParametri: Bool, dati: Data) {
        self.timestamp = timestamp
        self.chiave = chiave
        self.conParametri = conParametri
        self.dati = dati
    }

    public var pacchetto: Pacchetto {
        var flag: UInt8 = 0
        if chiave { flag |= Self.flagChiave }
        if conParametri { flag |= Self.flagParametri }
        var contenuto = Data(Pacchetto.byteBigEndian(timestamp))
        contenuto.append(dati)
        return Pacchetto(tipo: .video, flag: flag, contenuto: contenuto)
    }

    public init(pacchetto: Pacchetto) throws {
        guard pacchetto.tipo == .video, pacchetto.contenuto.count >= 8 else {
            throw ErroreProtocollo.contenutoNonValido
        }
        let inizio = pacchetto.contenuto.startIndex
        timestamp = pacchetto.contenuto[inizio..<(inizio + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
        chiave = pacchetto.flag & Self.flagChiave != 0
        conParametri = pacchetto.flag & Self.flagParametri != 0
        dati = Data(pacchetto.contenuto[(inizio + 8)...])
    }
}

/// Un pacchetto audio AAC-LC grezzo (senza ADTS), con il timestamp del primo campione in microsecondi,
/// sullo stesso orologio del video. La configurazione viaggia nel messaggio `formato-audio`.
public struct PacchettoAudio: Equatable, Sendable {
    public var timestamp: UInt64
    public var dati: Data

    public init(timestamp: UInt64, dati: Data) {
        self.timestamp = timestamp
        self.dati = dati
    }

    public var pacchetto: Pacchetto {
        var contenuto = Data(Pacchetto.byteBigEndian(timestamp))
        contenuto.append(dati)
        return Pacchetto(tipo: .audio, flag: 0, contenuto: contenuto)
    }

    public init(pacchetto: Pacchetto) throws {
        guard pacchetto.tipo == .audio, pacchetto.contenuto.count >= 8 else {
            throw ErroreProtocollo.contenutoNonValido
        }
        let inizio = pacchetto.contenuto.startIndex
        timestamp = pacchetto.contenuto[inizio..<(inizio + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
        dati = Data(pacchetto.contenuto[(inizio + 8)...])
    }
}

/// A cosa serve l'immagine di un pacchetto di tipo 4.
public enum UsoImmagine: UInt8, Sendable {
    case sfondo = 1
    case logo = 2
}

/// Un'immagine dal computer al telefono (pacchetto di tipo 4): 1 byte `uso` seguito dai byte di un file JPEG o PNG.
public struct PacchettoImmagine: Equatable, Sendable {
    /// Byte massimi del file (8 MiB).
    public static let dimensioneMassima = 8 * 1024 * 1024

    public var uso: UsoImmagine
    public var dati: Data

    public init(uso: UsoImmagine, dati: Data) {
        self.uso = uso
        self.dati = dati
    }

    public var pacchetto: Pacchetto {
        var contenuto = Data([uso.rawValue])
        contenuto.append(dati)
        return Pacchetto(tipo: .immagine, flag: 0, contenuto: contenuto)
    }

    /// Un `uso` sconosciuto, un file vuoto o più grande di 8 MiB danno `contenutoNonValido`: il pacchetto si scarta.
    public init(pacchetto: Pacchetto) throws {
        let contenuto = pacchetto.contenuto
        guard pacchetto.tipo == .immagine, contenuto.count >= 2, contenuto.count - 1 <= Self.dimensioneMassima,
              let uso = UsoImmagine(rawValue: contenuto[contenuto.startIndex]) else {
            throw ErroreProtocollo.contenutoNonValido
        }
        self.uso = uso
        dati = Data(contenuto[(contenuto.startIndex + 1)...])
    }

    /// L'impronta di questo file, come in `stato.immaginePersonale` e `stato.logo`.
    public var impronta: String { Self.improntaDi(dati) }

    /// I primi 16 caratteri esadecimali minuscoli dello SHA-256 dei byte del file.
    public static func improntaDi(_ dati: Data) -> String {
        SHA256.hash(data: dati).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
