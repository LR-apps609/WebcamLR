import CryptoKit
import Foundation

/// Collegamento sicuro, versione 2 del protocollo (Documenti/Protocollo.md, «Collegamento sicuro»).
/// Solo CryptoKit: ECDSA e ECDH P-256, HKDF-SHA256, AES-256-GCM. Gli stessi calcoli di Sicurezza.cs.
public enum Sicurezza {
    public static let versioneSicura = 2
    public static let lunghezzaChiavePubblica = 65
    public static let lunghezzaFirma = 64

    /// I primi 16 byte di SHA-256 della chiave pubblica, in base64url senza «=».
    public static func impronta(_ chiavePubblica: Data) -> String {
        base64URL(Data(SHA256.hash(data: chiavePubblica)).prefix(16))
    }

    /// 16 byte casuali per il QR code: chi li rimanda ha visto lo schermo del computer.
    public static func nuovoGettone() -> String {
        base64URL(SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) })
    }

    /// T = SHA-256("WebcamLR v2" ‖ chiave telefono ‖ identità telefono ‖ chiave computer ‖ identità computer).
    public static func trascrizione(chiaveTelefono: Data, identitaTelefono: Data,
                                    chiaveComputer: Data, identitaComputer: Data) -> Data {
        var hash = SHA256()
        hash.update(data: Data("WebcamLR v2".utf8))
        hash.update(data: chiaveTelefono)
        hash.update(data: identitaTelefono)
        hash.update(data: chiaveComputer)
        hash.update(data: identitaComputer)
        return Data(hash.finalize())
    }

    /// Le 4 cifre da confrontare sui due schermi alla prima volta.
    public static func codice(_ trascrizione: Data) -> String {
        let impronta = Array(SHA256.hash(data: Data("WebcamLR codice".utf8) + trascrizione))
        let numero = impronta.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%04u", numero % 10000)
    }

    /// Le due chiavi AES della sessione, una per direzione.
    public static func chiaviSessione(segreto: Data, trascrizione: Data)
        -> (telefonoComputer: SymmetricKey, computerTelefono: SymmetricKey) {
        func deriva(_ info: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: segreto), salt: trascrizione,
                                   info: Data(info.utf8), outputByteCount: 32)
        }
        return (deriva("WebcamLR v2 telefono-computer"), deriva("WebcamLR v2 computer-telefono"))
    }

    /// Verifica una firma ECDSA P-256 / SHA-256 in formato r ‖ s; falso anche se la chiave non è valida.
    public static func verificaFirma(chiavePubblica: Data, dati: Data, firma: Data) -> Bool {
        guard let chiave = try? P256.Signing.PublicKey(x963Representation: chiavePubblica),
              let valore = try? P256.Signing.ECDSASignature(rawRepresentation: firma) else { return false }
        return chiave.isValidSignature(valore, for: dati)
    }

    public static func base64URL(_ dati: Data) -> String {
        dati.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    static func daBase64(_ testo: String, lunghezza: Int) throws -> Data {
        guard let dati = Data(base64Encoded: testo), dati.count == lunghezza else {
            throw ErroreProtocollo.contenutoNonValido
        }
        return dati
    }
}

/// La coppia di chiavi di firma permanente di un dispositivo.
public struct IdentitaDispositivo {
    private let chiave: P256.Signing.PrivateKey

    public init() {
        chiave = P256.Signing.PrivateKey()
    }

    /// Da una chiave salvata con `datiDaSalvare` (32 byte, da tenere nel Portachiavi).
    public init(datiSalvati: Data) throws {
        chiave = try P256.Signing.PrivateKey(rawRepresentation: datiSalvati)
    }

    public var datiDaSalvare: Data { chiave.rawRepresentation }

    /// Chiave pubblica, 65 byte X9.63.
    public var pubblica: Data { chiave.publicKey.x963Representation }

    public var impronta: String { Sicurezza.impronta(pubblica) }

    /// Firma ECDSA SHA-256, formato r ‖ s di 64 byte.
    public func firma(_ dati: Data) throws -> Data {
        try chiave.signature(for: dati).rawRepresentation
    }
}

/// Cifra e decifra i pacchetti dopo la stretta di mano: AES-256-GCM, un contatore per direzione.
/// Chi usa `cifra` deve scrivere i pacchetti nello stesso ordine in cui li cifra.
public final class CanaleCifrato: @unchecked Sendable {
    public static let flagCifrato: UInt8 = 0x80
    public static let lunghezzaEtichetta = 16

    private let chiaveInvio: SymmetricKey
    private let chiaveRicezione: SymmetricKey
    private let blocco = NSLock()
    private var contatoreInvio: UInt64 = 0
    private var contatoreRicezione: UInt64 = 0

    public init(chiaveInvio: SymmetricKey, chiaveRicezione: SymmetricKey) {
        self.chiaveInvio = chiaveInvio
        self.chiaveRicezione = chiaveRicezione
    }

    public func cifra(_ chiaro: Pacchetto) throws -> Pacchetto {
        let flag = chiaro.flag | Self.flagCifrato
        blocco.lock()
        defer { blocco.unlock() }
        let scatola = try AES.GCM.seal(chiaro.contenuto, using: chiaveInvio,
                                       nonce: try AES.GCM.Nonce(data: Self.nonce(contatoreInvio)),
                                       authenticating: Data([chiaro.tipo.rawValue, flag]))
        contatoreInvio += 1
        return Pacchetto(tipo: chiaro.tipo, flag: flag, contenuto: scatola.ciphertext + scatola.tag)
    }

    /// Un pacchetto ripetuto, mancante o alterato è un errore: la connessione va chiusa.
    public func decifra(_ cifrato: Pacchetto) throws -> Pacchetto {
        guard cifrato.flag & Self.flagCifrato != 0,
              cifrato.contenuto.count >= Self.lunghezzaEtichetta else { throw ErroreProtocollo.contenutoNonValido }
        let divisione = cifrato.contenuto.endIndex - Self.lunghezzaEtichetta
        blocco.lock()
        defer { blocco.unlock() }
        let scatola = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: Self.nonce(contatoreRicezione)),
                                            ciphertext: cifrato.contenuto[cifrato.contenuto.startIndex..<divisione],
                                            tag: cifrato.contenuto[divisione...])
        guard let chiaro = try? AES.GCM.open(scatola, using: chiaveRicezione,
                                             authenticating: Data([cifrato.tipo.rawValue, cifrato.flag])) else {
            throw ErroreProtocollo.contenutoNonValido
        }
        contatoreRicezione += 1
        return Pacchetto(tipo: cifrato.tipo, flag: cifrato.flag & ~Self.flagCifrato, contenuto: chiaro)
    }

    /// 4 byte a zero ‖ contatore a 64 bit big-endian.
    public static func nonce(_ contatore: UInt64) -> Data {
        Data([0, 0, 0, 0] + Pacchetto.byteBigEndian(contatore))
    }
}

/// Cosa resta della stretta di mano: il canale e chi c'è dall'altra parte.
public struct SessioneSicura: Sendable {
    public let canale: CanaleCifrato
    /// La chiave pubblica di firma dell'altro dispositivo.
    public let identitaAltro: Data
    public let trascrizione: Data
    /// Le 4 cifre da confrontare alla prima volta.
    public let codice: String

    public var improntaAltro: String { Sicurezza.impronta(identitaAltro) }
}

/// La stretta di mano dal lato del telefono.
public struct StrettaTelefono {
    private let identita: IdentitaDispositivo
    private let effimera = P256.KeyAgreement.PrivateKey()

    public init(identita: IdentitaDispositivo) {
        self.identita = identita
    }

    public var apertura: Stretta {
        Stretta(versione: Sicurezza.versioneSicura, chiave: effimera.publicKey.x963Representation.base64EncodedString(),
                identita: identita.pubblica.base64EncodedString())
    }

    /// Verifica la risposta del computer; poi va mandata la `Prova`, già cifrata.
    public func completa(_ risposta: Stretta, gettone: String? = nil) throws -> (sessione: SessioneSicura, prova: Prova) {
        guard risposta.versione == Sicurezza.versioneSicura, let firmaTesto = risposta.firma else {
            throw ErroreProtocollo.contenutoNonValido
        }
        let chiaveComputer = try Sicurezza.daBase64(risposta.chiave, lunghezza: Sicurezza.lunghezzaChiavePubblica)
        let identitaComputer = try Sicurezza.daBase64(risposta.identita, lunghezza: Sicurezza.lunghezzaChiavePubblica)
        let firma = try Sicurezza.daBase64(firmaTesto, lunghezza: Sicurezza.lunghezzaFirma)

        let trascrizione = Sicurezza.trascrizione(chiaveTelefono: effimera.publicKey.x963Representation,
                                                  identitaTelefono: identita.pubblica,
                                                  chiaveComputer: chiaveComputer, identitaComputer: identitaComputer)
        guard Sicurezza.verificaFirma(chiavePubblica: identitaComputer, dati: trascrizione, firma: firma) else {
            throw ErroreProtocollo.contenutoNonValido
        }
        let altra = try P256.KeyAgreement.PublicKey(x963Representation: chiaveComputer)
        let segreto = try effimera.sharedSecretFromKeyAgreement(with: altra).withUnsafeBytes { Data($0) }
        let chiavi = Sicurezza.chiaviSessione(segreto: segreto, trascrizione: trascrizione)
        let sessione = SessioneSicura(canale: CanaleCifrato(chiaveInvio: chiavi.telefonoComputer,
                                                            chiaveRicezione: chiavi.computerTelefono),
                                      identitaAltro: identitaComputer, trascrizione: trascrizione,
                                      codice: Sicurezza.codice(trascrizione))
        return (sessione, Prova(firma: try identita.firma(trascrizione).base64EncodedString(), gettone: gettone))
    }
}

/// La stretta di mano dal lato del computer.
public struct StrettaComputer {
    private let identita: IdentitaDispositivo
    private let effimera = P256.KeyAgreement.PrivateKey()

    public init(identita: IdentitaDispositivo) {
        self.identita = identita
    }

    public func rispondi(_ apertura: Stretta) throws -> (risposta: Stretta, sessione: SessioneSicura) {
        guard apertura.versione == Sicurezza.versioneSicura else { throw ErroreProtocollo.contenutoNonValido }
        let chiaveTelefono = try Sicurezza.daBase64(apertura.chiave, lunghezza: Sicurezza.lunghezzaChiavePubblica)
        let identitaTelefono = try Sicurezza.daBase64(apertura.identita, lunghezza: Sicurezza.lunghezzaChiavePubblica)
        // Un'identità che non è un punto valido della curva non potrà mai firmare la prova.
        _ = try P256.Signing.PublicKey(x963Representation: identitaTelefono)

        let trascrizione = Sicurezza.trascrizione(chiaveTelefono: chiaveTelefono, identitaTelefono: identitaTelefono,
                                                  chiaveComputer: effimera.publicKey.x963Representation,
                                                  identitaComputer: identita.pubblica)
        let altra = try P256.KeyAgreement.PublicKey(x963Representation: chiaveTelefono)
        let segreto = try effimera.sharedSecretFromKeyAgreement(with: altra).withUnsafeBytes { Data($0) }
        let chiavi = Sicurezza.chiaviSessione(segreto: segreto, trascrizione: trascrizione)
        let risposta = Stretta(versione: Sicurezza.versioneSicura,
                               chiave: effimera.publicKey.x963Representation.base64EncodedString(),
                               identita: identita.pubblica.base64EncodedString(),
                               firma: try identita.firma(trascrizione).base64EncodedString())
        let sessione = SessioneSicura(canale: CanaleCifrato(chiaveInvio: chiavi.computerTelefono,
                                                            chiaveRicezione: chiavi.telefonoComputer),
                                      identitaAltro: identitaTelefono, trascrizione: trascrizione,
                                      codice: Sicurezza.codice(trascrizione))
        return (risposta, sessione)
    }

    /// Il telefono possiede davvero la chiave che ha dichiarato.
    public static func provaValida(_ prova: Prova, sessione: SessioneSicura) -> Bool {
        guard let firma = try? Sicurezza.daBase64(prova.firma, lunghezza: Sicurezza.lunghezzaFirma) else { return false }
        return Sicurezza.verificaFirma(chiavePubblica: sessione.identitaAltro, dati: sessione.trascrizione, firma: firma)
    }
}
