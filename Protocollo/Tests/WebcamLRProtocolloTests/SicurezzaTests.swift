import CryptoKit
import XCTest
@testable import WebcamLRProtocollo

/// Collegamento sicuro (versione 2): gli stessi casi di SicurezzaTest.cs.
final class SicurezzaTests: XCTestCase {
    private func strettaCompleta(gettone: String? = nil) throws
        -> (telefono: SessioneSicura, computer: SessioneSicura, prova: Prova,
            idTelefono: IdentitaDispositivo, idComputer: IdentitaDispositivo) {
        let idTelefono = IdentitaDispositivo()
        let idComputer = IdentitaDispositivo()
        let telefono = StrettaTelefono(identita: idTelefono)
        let computer = StrettaComputer(identita: idComputer)
        // Come in rete: i messaggi passano per il JSON.
        guard case .stretta(let apertura) = try Pacchetto(messaggio: .stretta(telefono.apertura)).messaggio() else {
            throw ErroreProtocollo.contenutoNonValido
        }
        let (risposta, sessioneComputer) = try computer.rispondi(apertura)
        guard case .stretta(let rispostaInRete) = try Pacchetto(messaggio: .stretta(risposta)).messaggio() else {
            throw ErroreProtocollo.contenutoNonValido
        }
        let (sessioneTelefono, prova) = try telefono.completa(rispostaInRete, gettone: gettone)
        return (sessioneTelefono, sessioneComputer, prova, idTelefono, idComputer)
    }

    func testStrettaDiManoECanaleNelleDueDirezioni() throws {
        let risultato = try strettaCompleta(gettone: "gettone")
        XCTAssertEqual(risultato.telefono.improntaAltro, risultato.idComputer.impronta)
        XCTAssertEqual(risultato.computer.improntaAltro, risultato.idTelefono.impronta)
        XCTAssertEqual(risultato.telefono.codice, risultato.computer.codice)
        XCTAssertEqual(risultato.telefono.codice.count, 4)
        XCTAssertTrue(StrettaComputer.provaValida(risultato.prova, sessione: risultato.computer))

        let video = FotogrammaVideo(timestamp: 123, chiave: true, conParametri: true,
                                    dati: Data([0, 0, 0, 1, 0x65, 1, 2, 3])).pacchetto
        let ciao = try Pacchetto(messaggio: .ciao(Ciao(nome: "iPhone di Ledion", piattaforma: .iphone, versioneApp: "0.10")))
        let videoCifrato = try risultato.telefono.canale.cifra(video)
        let ciaoCifrato = try risultato.telefono.canale.cifra(ciao)
        XCTAssertEqual(videoCifrato.flag, video.flag | CanaleCifrato.flagCifrato)
        XCTAssertEqual(videoCifrato.contenuto.count, video.contenuto.count + 16)
        XCTAssertEqual(try risultato.computer.canale.decifra(videoCifrato), video)
        XCTAssertEqual(try risultato.computer.canale.decifra(ciaoCifrato), ciao)

        let ping = try Pacchetto(messaggio: .ping(Ping(t: 42)))
        XCTAssertEqual(try risultato.telefono.canale.decifra(try risultato.computer.canale.cifra(ping)), ping)
    }

    func testPacchettoAlteratoORipetutoNonPassa() throws {
        let risultato = try strettaCompleta()
        let ping = try Pacchetto(messaggio: .ping(Ping(t: 1)))
        let primo = try risultato.computer.canale.cifra(ping)
        var alterato = primo
        alterato.contenuto[alterato.contenuto.startIndex] ^= 1
        XCTAssertThrowsError(try risultato.telefono.canale.decifra(alterato))
        XCTAssertEqual(try risultato.telefono.canale.decifra(primo), ping)
        XCTAssertThrowsError(try risultato.telefono.canale.decifra(primo))
        XCTAssertThrowsError(try risultato.telefono.canale.decifra(ping))
    }

    func testComputerFalsoNonPassa() throws {
        let telefono = StrettaTelefono(identita: IdentitaDispositivo())
        let intruso = StrettaComputer(identita: IdentitaDispositivo())
        var (risposta, _) = try intruso.rispondi(telefono.apertura)
        risposta.identita = IdentitaDispositivo().pubblica.base64EncodedString()
        XCTAssertThrowsError(try telefono.completa(risposta))
    }

    func testIdentitaSalvataERicaricata() throws {
        let originale = IdentitaDispositivo()
        let ricaricata = try IdentitaDispositivo(datiSalvati: originale.datiDaSalvare)
        XCTAssertEqual(originale.pubblica, ricaricata.pubblica)
        XCTAssertEqual(originale.impronta.count, 22)
        let firma = try ricaricata.firma(Data([1, 2, 3]))
        XCTAssertTrue(Sicurezza.verificaFirma(chiavePubblica: originale.pubblica, dati: Data([1, 2, 3]), firma: firma))
    }

    func testStrettaComeNelDocumento() throws {
        let json = String(decoding: try Pacchetto(messaggio: .stretta(Stretta(versione: 2, chiave: "AQ==", identita: "Aw==",
                                                                             firma: "Ag=="))).contenuto, as: UTF8.self)
        XCTAssertEqual(json, #"{"chiave":"AQ==","firma":"Ag==","identita":"Aw==","tipo":"stretta","versione":2}"#)
    }

    /// Gli stessi valori di SicurezzaTest.cs (ValoriDiRiferimentoUgualiInSwift).
    func testValoriDiRiferimentoUgualiInCSharp() throws {
        func riempi(_ resto: UInt8) -> Data { Data([0x04] + [UInt8](repeating: resto, count: 64)) }
        func esadecimale(_ dati: Data) -> String { dati.map { String(format: "%02X", $0) }.joined() }

        let trascrizione = Sicurezza.trascrizione(chiaveTelefono: riempi(0x11), identitaTelefono: riempi(0x22),
                                                  chiaveComputer: riempi(0x33), identitaComputer: riempi(0x44))
        let chiavi = Sicurezza.chiaviSessione(segreto: Data(repeating: 0x55, count: 32), trascrizione: trascrizione)
        let scatola = try AES.GCM.seal(Data("WebcamLR".utf8), using: chiavi.telefonoComputer,
                                       nonce: try AES.GCM.Nonce(data: CanaleCifrato.nonce(7)),
                                       authenticating: Data([1, 0x80]))

        XCTAssertEqual(esadecimale(trascrizione), "B14EE9D3F111558B44FEDEC6A6ADAAFFF75D268D60C2C0B9FB26F7E1879CB76E")
        XCTAssertEqual(Sicurezza.codice(trascrizione), "4696")
        XCTAssertEqual(esadecimale(chiavi.telefonoComputer.withUnsafeBytes { Data($0) }),
                       "2644007CCCF250E04349A82D07209ECF5613AA1C6E8B1CE4E9175731094EEB51")
        XCTAssertEqual(esadecimale(chiavi.computerTelefono.withUnsafeBytes { Data($0) }),
                       "D7A232B410AC8E6B2F46810DD8B950DD9E45ABAE9A1F053F16D1ED103EE83BAE")
        XCTAssertEqual(esadecimale(scatola.ciphertext + scatola.tag), "3FD81BED90DA56B2F53C604C8EA349FE5998F721DB3D0E80")
        XCTAssertEqual(Sicurezza.impronta(riempi(0x44)), "837DWUtYbfrElEqZA-g3UQ")
    }
}
