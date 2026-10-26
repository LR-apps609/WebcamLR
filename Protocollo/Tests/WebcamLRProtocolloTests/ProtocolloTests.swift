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
        // Versione 1 esplicita, come in C# e nel documento: il valore predefinito ora è 2.
        let messaggio = Messaggio.ciao(Ciao(versione: 1, nome: "iPhone di Ledion", piattaforma: .iphone, versioneApp: "0.1"))
        let json = String(decoding: try Pacchetto(messaggio: messaggio).contenuto, as: UTF8.self)
        XCTAssertEqual(json, #"{"nome":"iPhone di Ledion","piattaforma":"iphone","tipo":"ciao","versione":1,"versioneApp":"0.1"}"#)
    }

    /// Lo stesso JSON di «ComandoManualeComeNelDocumento» in C#: i campi assenti non si scrivono.
    func testComandoManualeComeNelDocumento() throws {
        let messaggio = Messaggio.comando(Comando(iso: 400, tempo: 50))
        let json = String(decoding: try Pacchetto(messaggio: messaggio).contenuto, as: UTF8.self)
        XCTAssertEqual(json, #"{"iso":400,"tempo":50,"tipo":"comando"}"#)
    }

    /// Lo stesso JSON di «CapacitaComeNelDocumento» in C#.
    func testCapacitaComeNelDocumento() throws {
        let messaggio = Messaggio.capacita(Capacita(obiettivi: ["principale", "frontale"], zoomMassimo: 5, torcia: true,
                                                    isoMinimo: 34, isoMassimo: 3264))
        let json = String(decoding: try Pacchetto(messaggio: messaggio).contenuto, as: UTF8.self)
        XCTAssertEqual(json, #"{"isoMassimo":3264,"isoMinimo":34,"obiettivi":["principale","frontale"],"tipo":"capacita","torcia":true,"zoomMassimo":5}"#)
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
            .comando(Comando(regolazioni: Regolazioni(nitidezza: -1), scritta: Scritta.nessuna)),
            .stato(StatoTelefono(batteria: 40, inCarica: false, temperatura: .normale, obiettivo: "frontale",
                                 filtro: Filtri.biancoNero, regolazioni: Regolazioni(luminosita: 0, contrasto: 0, saturazione: 0, nitidezza: 0),
                                 sfondo: ModiSfondo.sostituito, intensitaSfondo: 1, pelle: 0.5, inquadratura: true,
                                 luceVolto: false, scritta: Scritta(nome: "Ledion"), doppiaVista: true, postura: false,
                                 audio: true, pausa: MotiviPausa.facciaInGiu, gobbo: StatoGobbo(attivo: false, posizione: 1),
                                 specchia: false, zoom: 2, torcia: true, esposizione: 0.5, bianco: 4300, iso: 400, tempo: 60)),
            .comando(Comando(specchia: false)),
            .capacita(Capacita(obiettivi: ["principale"], zoomMassimo: 5, torcia: true, specchia: true)),
            .capacita(Capacita(obiettivi: ["principale"], zoomMassimo: 5, torcia: true, pro: false)),
            .anteprima(Anteprima(visibile: true)),
            .gobbo(Gobbo(attivo: false)),
            .gobbo(Gobbo(velocita: 3, dimensione: DimensioniGobbo.grande, posizione: 0)),
            .formatoAudio(FormatoAudio()),
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

    private func json(_ messaggio: Messaggio) throws -> String {
        String(decoding: try Pacchetto(messaggio: messaggio).contenuto, as: UTF8.self)
    }

    /// Lo stesso JSON di «ComandoEffettiComeNelDocumento» in C# e Kotlin.
    func testComandoEffettiComeNelDocumento() throws {
        let comando = Comando(filtro: Filtri.cinema,
                              regolazioni: Regolazioni(luminosita: 0.25, contrasto: -0.5, saturazione: 0.75, nitidezza: 0),
                              sfondo: ModiSfondo.sfocato, intensitaSfondo: 0.5, pelle: 0.25, inquadratura: true,
                              luceVolto: true, scritta: Scritta(nome: "Ledion", ruolo: "Sviluppatore"),
                              doppiaVista: false, postura: true, audio: true)
        let atteso = #"{"audio":true,"doppiaVista":false,"filtro":"cinema","inquadratura":true,"intensitaSfondo":0.5,"luceVolto":true,"pelle":0.25,"postura":true,"regolazioni":{"contrasto":-0.5,"luminosita":0.25,"nitidezza":0,"saturazione":0.75},"scritta":{"nome":"Ledion","ruolo":"Sviluppatore"},"sfondo":"sfocato","tipo":"comando"}"#
        XCTAssertEqual(try json(.comando(comando)), atteso)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(atteso.utf8)).messaggio(), .comando(comando))
    }

    /// Lo stesso JSON di «GobboComeNelDocumento» in C# e Kotlin.
    func testGobboComeNelDocumento() throws {
        let gobbo = Gobbo(testo: "Buongiorno a tutti.\nOggi parliamo del progetto.", velocita: 1.5, attivo: true,
                          dimensione: DimensioniGobbo.media)
        let atteso = #"{"attivo":true,"dimensione":"media","testo":"Buongiorno a tutti.\nOggi parliamo del progetto.","tipo":"gobbo","velocita":1.5}"#
        XCTAssertEqual(try json(.gobbo(gobbo)), atteso)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(atteso.utf8)).messaggio(), .gobbo(gobbo))
    }

    /// Lo stesso JSON di «StatoConEffettiComeNelDocumento» in C# e Kotlin.
    func testStatoConEffettiComeNelDocumento() throws {
        let stato = StatoTelefono(batteria: 80, inCarica: true, temperatura: .normale, obiettivo: "principale",
                                  filtro: Filtri.naturale, pausa: MotiviPausa.nessunaApp,
                                  gobbo: StatoGobbo(attivo: true, posizione: 0.25))
        let atteso = #"{"batteria":80,"filtro":"naturale","gobbo":{"attivo":true,"posizione":0.25},"inCarica":true,"obiettivo":"principale","pausa":"nessuna-app","temperatura":"normale","tipo":"stato"}"#
        XCTAssertEqual(try json(.stato(stato)), atteso)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(atteso.utf8)).messaggio(), .stato(stato))
    }

    /// Lo stesso JSON di «CapacitaEffettiComeNelDocumento» in C# e Kotlin.
    func testCapacitaEffettiComeNelDocumento() throws {
        let capacita = Capacita(obiettivi: ["principale"], zoomMassimo: 5, torcia: true,
                                filtri: [Filtri.naturale, Filtri.cinema], sfondo: true, doppiaVista: false, audio: true,
                                formati: [FormatoSupportato(larghezza: 1920, altezza: 1080, fpsMassimo: 60),
                                          FormatoSupportato(larghezza: 3840, altezza: 2160, fpsMassimo: 30)])
        let atteso = #"{"audio":true,"doppiaVista":false,"filtri":["naturale","cinema"],"formati":[{"altezza":1080,"fpsMassimo":60,"larghezza":1920},{"altezza":2160,"fpsMassimo":30,"larghezza":3840}],"obiettivi":["principale"],"sfondo":true,"tipo":"capacita","torcia":true,"zoomMassimo":5}"#
        XCTAssertEqual(try json(.capacita(capacita)), atteso)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(atteso.utf8)).messaggio(), .capacita(capacita))
    }

    /// Lo stesso JSON di «SpecchioComeNelDocumento» in C# e Kotlin: specchio e comandi della fotocamera in `stato`.
    func testSpecchioComeNelDocumento() throws {
        let comando = Comando(specchia: true)
        XCTAssertEqual(try json(.comando(comando)), #"{"specchia":true,"tipo":"comando"}"#)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(#"{"tipo":"comando","specchia":true}"#.utf8)).messaggio(),
                       .comando(comando))

        let stato = StatoTelefono(batteria: 80, inCarica: true, temperatura: .normale, obiettivo: "frontale",
                                  specchia: true, zoom: 1.5, torcia: false, esposizione: -0.5, bianco: 0, iso: 0, tempo: 0)
        let attesoStato = #"{"batteria":80,"bianco":0,"esposizione":-0.5,"inCarica":true,"iso":0,"obiettivo":"frontale","specchia":true,"temperatura":"normale","tempo":0,"tipo":"stato","torcia":false,"zoom":1.5}"#
        XCTAssertEqual(try json(.stato(stato)), attesoStato)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(attesoStato.utf8)).messaggio(), .stato(stato))

        let capacita = Capacita(obiettivi: ["frontale"], zoomMassimo: 5, torcia: false, specchia: true)
        let attesoCapacita = #"{"obiettivi":["frontale"],"specchia":true,"tipo":"capacita","torcia":false,"zoomMassimo":5}"#
        XCTAssertEqual(try json(.capacita(capacita)), attesoCapacita)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(attesoCapacita.utf8)).messaggio(), .capacita(capacita))
    }

    /// Lo stesso JSON di «ProComeNelDocumento» in C# e Kotlin: `capacita.pro`.
    func testProComeNelDocumento() throws {
        let capacita = Capacita(obiettivi: ["frontale"], zoomMassimo: 5, torcia: false, specchia: true, pro: true)
        let atteso = #"{"obiettivi":["frontale"],"pro":true,"specchia":true,"tipo":"capacita","torcia":false,"zoomMassimo":5}"#
        XCTAssertEqual(try json(.capacita(capacita)), atteso)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(atteso.utf8)).messaggio(), .capacita(capacita))
        // Un telefono senza il campo (vecchio o gratis) si legge come «non Pro».
        let vecchio = try Pacchetto(tipo: .controllo,
                                    contenuto: Data(#"{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false}"#.utf8)).messaggio()
        guard case .capacita(let letta) = vecchio else { return XCTFail("Atteso capacita") }
        XCTAssertNil(letta.pro)
    }

    /// Lo stesso JSON di «SceltaCollegamentoComeNelDocumento» in C# e Kotlin: capacità, comando e stato del collegamento.
    func testSceltaCollegamentoComeNelDocumento() throws {
        let capacita = Capacita(obiettivi: ["frontale"], zoomMassimo: 5, torcia: false, sceltaCollegamento: true)
        let attesoCapacita = #"{"obiettivi":["frontale"],"sceltaCollegamento":true,"tipo":"capacita","torcia":false,"zoomMassimo":5}"#
        XCTAssertEqual(try json(.capacita(capacita)), attesoCapacita)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(attesoCapacita.utf8)).messaggio(), .capacita(capacita))

        let comando = Comando(collegamento: PreferenzeCollegamento.cavo)
        let attesoComando = #"{"collegamento":"cavo","tipo":"comando"}"#
        XCTAssertEqual(try json(.comando(comando)), attesoComando)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(attesoComando.utf8)).messaggio(), .comando(comando))

        let collegamento = StatoCollegamento(attivo: StradeCollegamento.wifi, preferenza: PreferenzeCollegamento.automatico,
                                             strade: [StradaCollegamento(tipo: StradeCollegamento.wifi, ms: 38),
                                                      StradaCollegamento(tipo: StradeCollegamento.cavo, ms: 9),
                                                      StradaCollegamento(tipo: StradeCollegamento.hotspot)])
        let stato = StatoTelefono(batteria: 80, inCarica: true, temperatura: .normale, obiettivo: "frontale",
                                  collegamento: collegamento)
        let attesoStato = #"{"batteria":80,"collegamento":{"attivo":"wifi","preferenza":"automatico","strade":[{"ms":38,"tipo":"wifi"},{"ms":9,"tipo":"cavo"},{"tipo":"hotspot"}]},"inCarica":true,"obiettivo":"frontale","temperatura":"normale","tipo":"stato"}"#
        XCTAssertEqual(try json(.stato(stato)), attesoStato)
        XCTAssertEqual(try Pacchetto(tipo: .controllo, contenuto: Data(attesoStato.utf8)).messaggio(), .stato(stato))
        XCTAssertEqual(collegamento.piuVeloce, StradeCollegamento.cavo)

        // Valori sconosciuti e `strade` assente: il messaggio si legge lo stesso.
        let futuro = try Pacchetto(tipo: .controllo, contenuto: Data(#"{"tipo":"stato","batteria":80,"inCarica":true,"temperatura":"normale","obiettivo":"frontale","collegamento":{"attivo":"satellite","preferenza":"telepatia"}}"#.utf8)).messaggio()
        guard case .stato(let letto) = futuro else { return XCTFail("Atteso stato") }
        XCTAssertEqual(letto.collegamento, StatoCollegamento(attivo: "satellite", preferenza: "telepatia", strade: []))
        XCTAssertNil(letto.collegamento?.piuVeloce)
    }

    func testAnteprimaEFormatoAudioComeNelDocumento() throws {
        XCTAssertEqual(try json(.anteprima(Anteprima(visibile: false))), #"{"tipo":"anteprima","visibile":false}"#)
        XCTAssertEqual(try json(.formatoAudio(FormatoAudio())),
                       #"{"canali":1,"codec":"aac-lc","configurazione":"EYg=","frequenza":48000,"tipo":"formato-audio"}"#)
    }

    /// I telefoni vecchi mandano `stato` e `capacita` senza i campi nuovi: si leggono lo stesso.
    func testMessaggiVecchiSenzaCampiNuovi() throws {
        let stato = Pacchetto(tipo: .controllo, contenuto: Data(#"{"tipo":"stato","batteria":50,"inCarica":false,"temperatura":"calda","obiettivo":"tele"}"#.utf8))
        XCTAssertEqual(try stato.messaggio(), .stato(StatoTelefono(batteria: 50, inCarica: false, temperatura: .calda, obiettivo: "tele")))
        let comando = Pacchetto(tipo: .controllo, contenuto: Data(#"{"tipo":"comando","filtro":"futuro","nuovo":{"a":1}}"#.utf8))
        XCTAssertEqual(try comando.messaggio(), .comando(Comando(filtro: "futuro")))
    }

    func testPacchettoAudio() throws {
        let audio = PacchettoAudio(timestamp: 0x0102030405060708, dati: Data([0x21, 0x10, 0x04]))
        let pacchetto = audio.pacchetto
        XCTAssertEqual(pacchetto.tipo, .audio)
        XCTAssertEqual(pacchetto.flag, 0)
        XCTAssertEqual(Array(pacchetto.codificato()), [3, 0, 0, 0, 0, 11, 1, 2, 3, 4, 5, 6, 7, 8, 0x21, 0x10, 0x04])
        XCTAssertEqual(try PacchettoAudio(pacchetto: pacchetto), audio)

        var lettore = LettorePacchetti()
        lettore.aggiungi(pacchetto.codificato())
        let letto = try XCTUnwrap(try lettore.prossimo())
        XCTAssertEqual(try PacchettoAudio(pacchetto: letto), audio)
        XCTAssertThrowsError(try PacchettoAudio(pacchetto: Pacchetto(tipo: .audio, contenuto: Data([1, 2, 3]))))
        XCTAssertThrowsError(try PacchettoAudio(pacchetto: Pacchetto(tipo: .video, contenuto: pacchetto.contenuto)))
        XCTAssertEqual(Array(FormatoAudio.configurazioneAAC48kMono), [0x11, 0x88])
    }

    func testTipoDiMessaggioSconosciutoSiIgnora() throws {
        let pacchetto = Pacchetto(tipo: .controllo, contenuto: Data(#"{"tipo":"futuro","x":1}"#.utf8))
        XCTAssertEqual(try pacchetto.messaggio(), .sconosciuto("futuro"))
    }

    /// «Valori sconosciuti» in Protocollo.md: gli stessi casi dei test C# e Kotlin.
    func testValoriSconosciutiNonFermanoIlMessaggio() throws {
        func messaggio(_ json: String) throws -> Messaggio {
            try Pacchetto(tipo: .controllo, contenuto: Data(json.utf8)).messaggio()
        }
        XCTAssertEqual(try messaggio(#"{"tipo":"stato","batteria":64,"inCarica":true,"temperatura":"rovente","obiettivo":"macro","pausa":"riunione","sfondo":"spiaggia","nuovo":{"a":[1,2]}}"#),
                       .stato(StatoTelefono(batteria: 64, inCarica: true, temperatura: .normale, obiettivo: "macro",
                                            sfondo: "spiaggia", pausa: "riunione")))
        guard case .capacita(let capacita) = try messaggio(#"{"tipo":"capacita","obiettivi":["frontale","periscopio"],"zoomMassimo":5,"torcia":false,"pro":true,"futuro":7}"#) else {
            return XCTFail("Non è una capacita")
        }
        XCTAssertEqual(capacita.obiettivi, ["frontale", "periscopio"])
        XCTAssertEqual(capacita.zoomMassimo, 5)
        XCTAssertEqual(capacita.pro, true)
        XCTAssertEqual(try messaggio(#"{"tipo":"formato","codec":"av1","larghezza":1920,"altezza":1080,"fps":30}"#),
                       .formato(FormatoVideo(codec: .h264, larghezza: 1920, altezza: 1080, fps: 30)))
        XCTAssertEqual(try messaggio(#"{"tipo":"ciao","versione":2,"nome":"Telefono","piattaforma":"visore","versioneApp":"3.0"}"#),
                       .ciao(Ciao(versione: 2, nome: "Telefono", piattaforma: .sconosciuta, versioneApp: "3.0")))
        XCTAssertEqual(try messaggio(#"{"tipo":"benvenuto","versione":2,"nome":"PC","piattaforma":"linux"}"#),
                       .benvenuto(Benvenuto(versione: 2, nome: "PC", piattaforma: .sconosciuta)))
        XCTAssertEqual(try messaggio(#"{"tipo":"teletrasporto","destinazione":"Marte"}"#), .sconosciuto("teletrasporto"))
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
        XCTAssertEqual(associazione.testo, "webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=MacBook%20Air&v=2")
        XCTAssertEqual(Associazione(testo: associazione.testo), associazione)
    }

    /// Lo stesso testo di «QRSicuroComeNelDocumento» in C#.
    func testQRSicuroComeNelDocumento() {
        let associazione = Associazione(indirizzi: ["192.168.1.20"], nome: "MacBook Air", versione: 2,
                                        impronta: "837DWUtYbfrElEqZA-g3UQ", gettone: "q_1-Zx")
        XCTAssertEqual(associazione.testo,
                       "webcamlr://collega?h=192.168.1.20&p=52740&n=MacBook%20Air&v=2&k=837DWUtYbfrElEqZA-g3UQ&g=q_1-Zx")
        XCTAssertEqual(Associazione(testo: associazione.testo), associazione)
    }

    func testNomeConCaratteriSpeciali() {
        let associazione = Associazione(indirizzi: ["192.168.1.20"], nome: "Studio & Casa+1")
        XCTAssertEqual(associazione.testo, "webcamlr://collega?h=192.168.1.20&p=52740&n=Studio%20%26%20Casa%2B1&v=2")
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
