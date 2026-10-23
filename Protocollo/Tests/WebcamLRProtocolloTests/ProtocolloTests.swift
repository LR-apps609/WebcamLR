import XCTest
@testable import WebcamLRProtocollo

final class ProtocolloTests: XCTestCase {
    func testIntestazioneBigEndian() {
        let dati = Pacchetto(tipo: .video, flag: 3, contenuto: Data(repeating: 7, count: 258)).codificato()
        XCTAssertEqual(Array(dati.prefix(6)), [2, 3, 0, 0, 1, 2])
        XCTAssertEqual(dati.count, 264)
    }

    func testLetturaAPezzi() throws {
        let primo = Pacchetto(tipo: .controllo, contenuto: Data("abc".utf8))
        let secondo = Pacchetto(tipo: .audio, contenuto: Data([1, 2, 3, 4]))
        let flusso = primo.codificato() + secondo.codificato()

        var lettore = LettorePacchetti()
        var letti: [Pacchetto] = []
        for byte in flusso {
            lettore.aggiungi(Data([byte]))
            while let pacchetto = try lettore.prossimo() {
                letti.append(pacchetto)
            }
        }
        XCTAssertEqual(letti, [primo, secondo])
    }

    func testTipoSconosciutoChiudeLaConnessione() {
        var lettore = LettorePacchetti()
        lettore.aggiungi(Data([9, 0, 0, 0, 0, 0]))
        XCTAssertThrowsError(try lettore.prossimo()) { errore in
            XCTAssertEqual(errore as? ErroreProtocollo, .tipoSconosciuto(9))
        }
    }

    func testFotogrammaVideo() throws {
        let fotogramma = FotogrammaVideo(timestamp: 0x0102030405060708, chiave: true, conParametri: true, dati: Data([0, 0, 0, 1, 0x65]))
        let pacchetto = fotogramma.pacchetto
        XCTAssertEqual(pacchetto.flag, 3)
        XCTAssertEqual(Array(pacchetto.contenuto.prefix(8)), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(try FotogrammaVideo(pacchetto: pacchetto), fotogramma)
    }

    func testCiaoComeNelDocumento() throws {
        let messaggio = Messaggio.ciao(Ciao(nome: "iPhone di Ledion", piattaforma: .iphone, versioneApp: "0.1"))
        let json = String(decoding: try Pacchetto(messaggio: messaggio).contenuto, as: UTF8.self)
        XCTAssertEqual(json, #"{"nome":"iPhone di Ledion","piattaforma":"iphone","tipo":"ciao","versione":1,"versioneApp":"0.1"}"#)
    }

    func testAndataERitorno() throws {
        let messaggi: [Messaggio] = [
            .benvenuto(Benvenuto(nome: "PC-STUDIO", piattaforma: .windows)),
            .formato(FormatoVideo(codec: .h264, larghezza: 1920, altezza: 1080, fps: 30)),
            .stato(StatoTelefono(batteria: 78, inCarica: false, temperatura: .moltoCalda, obiettivo: "principale")),
            .ping(Ping(t: 123)),
            .pong(Pong(t: 123, telefono: 456)),
            .latenza(Latenza(ms: 38)),
            .capacita(Capacita(obiettivi: ["grandangolo", "principale"], zoomMassimo: 10, torcia: true, isoMinimo: 32, isoMassimo: 3072)),
            .comando(Comando(iso: 400, tempo: 60)),
            .comando(Comando(obiettivo: "tele", zoom: 1.5, torcia: false, esposizione: -0.5, bianco: 0, fuoco: "continuo")),
            .inOnda(InOnda(attivo: true, app: "Zoom")),
            .inOnda(InOnda(attivo: false)),
            .arrivederci
        ]
        for messaggio in messaggi {
            XCTAssertEqual(try Pacchetto(messaggio: messaggio).messaggio(), messaggio)
        }
    }

    func testComandoComeNelDocumento() throws {
        let json = String(decoding: try Pacchetto(messaggio: .comando(Comando(esposizione: 0.3, bianco: 4300))).contenuto, as: UTF8.self)
        XCTAssertEqual(json, #"{"bianco":4300,"esposizione":0.3,"tipo":"comando"}"#)
    }

    func testTipoDiMessaggioSconosciutoSiIgnora() throws {
        let pacchetto = Pacchetto(tipo: .controllo, contenuto: Data(#"{"tipo":"futuro","x":1}"#.utf8))
        XCTAssertEqual(try pacchetto.messaggio(), .sconosciuto("futuro"))
    }
}

final class AnnexBTests: XCTestCase {
    func testDivisioneEUnione() {
        let sps = Data([0x67, 1, 2])
        let pps = Data([0x68, 3])
        let idr = Data([0x65, 4, 0, 0, 2, 5])
        var dati = AnnexB.unisci([sps, pps])
        dati.append(contentsOf: [0, 0, 1])
        dati.append(idr)
        XCTAssertEqual(AnnexB.unita(in: dati), [sps, pps, idr])
        XCTAssertEqual(AnnexB.unita(in: dati).map(AnnexB.tipoH264), [7, 8, 5])
    }

    func testTipiHEVC() {
        // Primo byte dell'intestazione HEVC: tipo nei bit 1–6.
        XCTAssertEqual(AnnexB.tipoHEVC(Data([0x40, 0x01])), 32) // VPS
        XCTAssertEqual(AnnexB.tipoHEVC(Data([0x42, 0x01])), 33) // SPS
        XCTAssertEqual(AnnexB.tipoHEVC(Data([0x44, 0x01])), 34) // PPS
        XCTAssertEqual(AnnexB.tipoHEVC(Data([0x26, 0x01])), 19) // IDR
    }
}

final class AssociazioneTests: XCTestCase {
    func testQRComeNelDocumento() {
        let associazione = Associazione(indirizzi: ["192.168.1.20", "10.0.0.5"], nome: "MacBook Air")
        XCTAssertEqual(associazione.testo, "webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=MacBook%20Air&v=1")
        XCTAssertEqual(Associazione(testo: associazione.testo), associazione)
    }

    func testNomeConCaratteriSpeciali() {
        let associazione = Associazione(indirizzi: ["192.168.1.20"], nome: "Studio & Casa+1")
        XCTAssertEqual(associazione.testo, "webcamlr://collega?h=192.168.1.20&p=52740&n=Studio%20%26%20Casa%2B1&v=1")
        XCTAssertEqual(Associazione(testo: associazione.testo)?.nome, "Studio & Casa+1")
    }

    func testAltriQRSiIgnorano() {
        XCTAssertNil(Associazione(testo: "https://example.com"))
        XCTAssertNil(Associazione(testo: "webcamlr://collega?p=52740"))
    }

    func testIndirizzoScritto() {
        XCTAssertEqual(Associazione(indirizzoScritto: " 192.168.1.20 ")?.porta, 52740)
        XCTAssertEqual(Associazione(indirizzoScritto: "192.168.1.20:52741")?.porta, 52741)
        XCTAssertNil(Associazione(indirizzoScritto: "192.168.1"))
        XCTAssertNil(Associazione(indirizzoScritto: "192.168.1.300"))
        XCTAssertNil(Associazione(indirizzoScritto: "ciao"))
    }
}
