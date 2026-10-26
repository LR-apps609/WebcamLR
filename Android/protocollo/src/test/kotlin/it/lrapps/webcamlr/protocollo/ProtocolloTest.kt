package it.lrapps.webcamlr.protocollo

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Gli stessi casi di Protocollo/Tests (Swift) e Windows/WebcamLR.Protocollo.Test (C#). */
class ProtocolloTest {

    private fun json(messaggio: Messaggio) = CodificaMessaggi.comePacchetto(messaggio).contenuto.toString(Charsets.UTF_8)

    private fun decodifica(testo: String) = CodificaMessaggi.decodifica(testo.toByteArray(Charsets.UTF_8))

    @Test
    fun intestazioneBigEndian() {
        val dati = Pacchetto(TipoPacchetto.VIDEO, 3, ByteArray(258) { 7 }).codificato()
        assertContentEquals(byteArrayOf(2, 3, 0, 0, 1, 2), dati.copyOf(6))
        assertEquals(264, dati.size)
    }

    @Test
    fun letturaAPezzi() {
        val primo = Pacchetto(TipoPacchetto.CONTROLLO, 0, "abc".toByteArray())
        val secondo = Pacchetto(TipoPacchetto.AUDIO, 0, byteArrayOf(1, 2, 3, 4))
        val flusso = primo.codificato() + secondo.codificato()

        val lettore = LettorePacchetti()
        val letti = mutableListOf<Pacchetto>()
        for (byte in flusso) {
            lettore.aggiungi(byteArrayOf(byte))
            while (true) letti.add(lettore.prossimo() ?: break)
        }
        assertEquals(listOf(primo, secondo), letti)
    }

    @Test
    fun letturaDiPacchettiGrandiCheAllarganoIlBuffer() {
        val grande = Pacchetto(TipoPacchetto.VIDEO, 1, ByteArray(300_000) { (it % 251).toByte() })
        val lettore = LettorePacchetti()
        val flusso = grande.codificato() + grande.codificato()
        var posizione = 0
        val letti = mutableListOf<Pacchetto>()
        while (posizione < flusso.size) {
            val quanti = minOf(7_777, flusso.size - posizione)
            lettore.aggiungi(flusso, posizione, quanti)
            posizione += quanti
            while (true) letti.add(lettore.prossimo() ?: break)
        }
        assertEquals(listOf(grande, grande), letti)
    }

    @Test
    fun tipoSconosciutoChiudeLaConnessione() {
        val lettore = LettorePacchetti()
        lettore.aggiungi(byteArrayOf(9, 0, 0, 0, 0, 0))
        assertFailsWith<ErroreProtocollo> { lettore.prossimo() }
    }

    @Test
    fun pacchettoTroppoGrandeChiudeLaConnessione() {
        val lettore = LettorePacchetti()
        lettore.aggiungi(byteArrayOf(2, 0, 0x01, 0, 0, 1))
        assertFailsWith<ErroreProtocollo> { lettore.prossimo() }
    }

    @Test
    fun fotogrammaVideo() {
        val fotogramma = FotogrammaVideo(0x0102030405060708uL, chiave = true, conParametri = true, dati = byteArrayOf(0, 0, 0, 1, 0x65))
        val pacchetto = fotogramma.pacchetto
        assertEquals(3, pacchetto.flag)
        assertContentEquals(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8), pacchetto.contenuto.copyOf(8))
        assertEquals(fotogramma, FotogrammaVideo.da(pacchetto))
    }

    /** Lo stesso JSON, carattere per carattere, di testCiaoComeNelDocumento (Swift) e CiaoComeNelDocumento (C#). */
    @Test
    fun ciaoComeNelDocumento() {
        val messaggio = Ciao(versione = 1, nome = "iPhone di Ledion", piattaforma = Piattaforma.IPHONE, versioneApp = "0.1")
        val atteso = """{"nome":"iPhone di Ledion","piattaforma":"iphone","tipo":"ciao","versione":1,"versioneApp":"0.1"}"""
        assertEquals(atteso, json(messaggio))
        assertEquals(messaggio, decodifica(atteso))
        // Il C# scrive «tipo» per primo: l'ordine dei campi in lettura non conta.
        assertEquals(messaggio, decodifica("""{"tipo":"ciao","versione":1,"nome":"iPhone di Ledion","piattaforma":"iphone","versioneApp":"0.1"}"""))
    }

    @Test
    fun ciaoDiAndroid() {
        val json = json(Ciao(nome = "Galaxy S24 di Ledion", piattaforma = Piattaforma.ANDROID, versioneApp = "0.1"))
        assertEquals("""{"nome":"Galaxy S24 di Ledion","piattaforma":"android","tipo":"ciao","versione":2,"versioneApp":"0.1"}""", json)
    }

    /** Lo stesso JSON di «ComandoManualeComeNelDocumento»: i campi assenti non si scrivono. */
    @Test
    fun comandoManualeComeNelDocumento() {
        assertEquals("""{"iso":400,"tempo":50,"tipo":"comando"}""", json(Comando(iso = 400.0, tempo = 50)))
        assertEquals(Comando(iso = 400.0, tempo = 50), decodifica("""{"iso":400,"tempo":50,"tipo":"comando"}"""))
    }

    @Test
    fun capacitaComeNelDocumento() {
        val capacita = Capacita(listOf("principale", "frontale"), 5.0, true, isoMinimo = 34.0, isoMassimo = 3264.0)
        val atteso = """{"isoMassimo":3264,"isoMinimo":34,"obiettivi":["principale","frontale"],"tipo":"capacita","torcia":true,"zoomMassimo":5}"""
        assertEquals(atteso, json(capacita))
        assertEquals(capacita, decodifica(atteso))
    }

    @Test
    fun comandoComeNelDocumento() {
        assertEquals("""{"bianco":4300,"esposizione":0.3,"tipo":"comando"}""", json(Comando(esposizione = 0.3, bianco = 4300)))
        assertEquals(Comando(esposizione = 0.3, bianco = 4300), decodifica("""{"bianco":4300,"esposizione":0.3,"tipo":"comando"}"""))
    }

    @Test
    fun valoriEnumeratiComeNelDocumento() {
        val stato = json(StatoTelefono(78, false, Temperatura.MOLTO_CALDA, "principale"))
        assertTrue("\"temperatura\":\"molto-calda\"" in stato)
        assertTrue("\"inCarica\":false" in stato)
        assertTrue("\"codec\":\"h264\"" in json(FormatoVideo(Codec.H264, 1920, 1080, 30)))
    }

    @Test
    fun andataERitorno() {
        val messaggi = listOf(
            Benvenuto(nome = "PC-STUDIO", piattaforma = Piattaforma.WINDOWS),
            FormatoVideo(Codec.H264, 1920, 1080, 30),
            FormatoVideo(Codec.HEVC, 3840, 2160, 30),
            StatoTelefono(78, false, Temperatura.MOLTO_CALDA, "principale"),
            StatoTelefono(-1, true, Temperatura.NORMALE, "frontale"),
            Ping(123u),
            Pong(123u, 456u),
            Ping(ULong.MAX_VALUE),
            Latenza(38),
            Capacita(listOf("grandangolo", "principale"), 10.0, true, 32.0, 3072.0),
            Capacita(listOf("principale"), 1.5, false),
            Comando(iso = 400.0, tempo = 60),
            Comando(obiettivo = "tele", zoom = 1.5, torcia = false, esposizione = -0.5, bianco = 0, fuoco = "continuo"),
            InOnda(true, "Zoom"),
            InOnda(false),
            Comando(regolazioni = Regolazioni(nitidezza = -1.0), scritta = Scritta.NESSUNA),
            StatoTelefono(
                40, false, Temperatura.NORMALE, "frontale", Filtri.BIANCO_NERO, Regolazioni(0.0, 0.0, 0.0, 0.0),
                ModiSfondo.SOSTITUITO, 1.0, 0.5, true, false, Scritta("Ledion"), true, false, true,
                MotiviPausa.FACCIA_IN_GIU, StatoGobbo(false, 1.0), specchia = false, zoom = 2.0, torcia = true,
                esposizione = 0.5, bianco = 4300, iso = 400.0, tempo = 60,
            ),
            Comando(specchia = false),
            Capacita(listOf("principale"), 5.0, true, specchia = true),
            Capacita(listOf("principale"), 5.0, true, pro = false),
            Capacita(
                listOf("principale"), 2.0, false, filtri = Filtri.TUTTI, pelle = true, inquadratura = true, luceVolto = true,
                scritta = true, postura = true, gobbo = true, formati = listOf(FormatoSupportato(1280, 720, 60)),
            ),
            Anteprima(true),
            Gobbo(attivo = false),
            Gobbo(velocita = 3.0, dimensione = DimensioniGobbo.GRANDE, posizione = 0.0),
            FormatoAudio(),
            Arrivederci,
            Stretta(2, "AQ==", "Aw==", "Ag=="),
            Prova("AQ==", "gettone"),
            Approvazione("0042"),
        )
        for (messaggio in messaggi) {
            assertEquals(messaggio, CodificaMessaggi.daPacchetto(CodificaMessaggi.comePacchetto(messaggio)))
        }
    }

    /** Lo stesso JSON, carattere per carattere, di testComandoEffettiComeNelDocumento (Swift) e ComandoEffettiComeNelDocumento (C#). */
    @Test
    fun comandoEffettiComeNelDocumento() {
        val comando = Comando(
            filtro = Filtri.CINEMA,
            regolazioni = Regolazioni(luminosita = 0.25, contrasto = -0.5, saturazione = 0.75, nitidezza = 0.0),
            sfondo = ModiSfondo.SFOCATO, intensitaSfondo = 0.5, pelle = 0.25, inquadratura = true, luceVolto = true,
            scritta = Scritta("Ledion", "Sviluppatore"), doppiaVista = false, postura = true, audio = true,
        )
        val atteso = """{"audio":true,"doppiaVista":false,"filtro":"cinema","inquadratura":true,"intensitaSfondo":0.5,"luceVolto":true,"pelle":0.25,"postura":true,"regolazioni":{"contrasto":-0.5,"luminosita":0.25,"nitidezza":0,"saturazione":0.75},"scritta":{"nome":"Ledion","ruolo":"Sviluppatore"},"sfondo":"sfocato","tipo":"comando"}"""
        assertEquals(atteso, json(comando))
        assertEquals(comando, decodifica(atteso))
    }

    @Test
    fun gobboComeNelDocumento() {
        val gobbo = Gobbo("Buongiorno a tutti.\nOggi parliamo del progetto.", 1.5, true, DimensioniGobbo.MEDIA)
        val atteso = """{"attivo":true,"dimensione":"media","testo":"Buongiorno a tutti.\nOggi parliamo del progetto.","tipo":"gobbo","velocita":1.5}"""
        assertEquals(atteso, json(gobbo))
        assertEquals(gobbo, decodifica(atteso))
    }

    @Test
    fun statoConEffettiComeNelDocumento() {
        val stato = StatoTelefono(
            80, true, Temperatura.NORMALE, "principale", filtro = Filtri.NATURALE,
            pausa = MotiviPausa.NESSUNA_APP, gobbo = StatoGobbo(true, 0.25),
        )
        val atteso = """{"batteria":80,"filtro":"naturale","gobbo":{"attivo":true,"posizione":0.25},"inCarica":true,"obiettivo":"principale","pausa":"nessuna-app","temperatura":"normale","tipo":"stato"}"""
        assertEquals(atteso, json(stato))
        assertEquals(stato, decodifica(atteso))
    }

    @Test
    fun capacitaEffettiComeNelDocumento() {
        val capacita = Capacita(
            listOf("principale"), 5.0, true, filtri = listOf(Filtri.NATURALE, Filtri.CINEMA), sfondo = true,
            doppiaVista = false, audio = true,
            formati = listOf(FormatoSupportato(1920, 1080, 60), FormatoSupportato(3840, 2160, 30)),
        )
        val atteso = """{"audio":true,"doppiaVista":false,"filtri":["naturale","cinema"],"formati":[{"altezza":1080,"fpsMassimo":60,"larghezza":1920},{"altezza":2160,"fpsMassimo":30,"larghezza":3840}],"obiettivi":["principale"],"sfondo":true,"tipo":"capacita","torcia":true,"zoomMassimo":5}"""
        assertEquals(atteso, json(capacita))
        assertEquals(capacita, decodifica(atteso))
    }

    /** Lo stesso JSON, carattere per carattere, di testSpecchioComeNelDocumento (Swift) e SpecchioComeNelDocumento (C#). */
    @Test
    fun specchioComeNelDocumento() {
        assertEquals("""{"specchia":true,"tipo":"comando"}""", json(Comando(specchia = true)))
        assertEquals(Comando(specchia = true), decodifica("""{"tipo":"comando","specchia":true}"""))

        val stato = StatoTelefono(
            80, true, Temperatura.NORMALE, "frontale", specchia = true, zoom = 1.5, torcia = false,
            esposizione = -0.5, bianco = 0, iso = 0.0, tempo = 0,
        )
        val attesoStato = """{"batteria":80,"bianco":0,"esposizione":-0.5,"inCarica":true,"iso":0,"obiettivo":"frontale","specchia":true,"temperatura":"normale","tempo":0,"tipo":"stato","torcia":false,"zoom":1.5}"""
        assertEquals(attesoStato, json(stato))
        assertEquals(stato, decodifica(attesoStato))

        val capacita = Capacita(listOf("frontale"), 5.0, false, specchia = true)
        val attesoCapacita = """{"obiettivi":["frontale"],"specchia":true,"tipo":"capacita","torcia":false,"zoomMassimo":5}"""
        assertEquals(attesoCapacita, json(capacita))
        assertEquals(capacita, decodifica(attesoCapacita))
    }

    /** Lo stesso JSON, carattere per carattere, di testProComeNelDocumento (Swift) e ProComeNelDocumento (C#). */
    @Test
    fun proComeNelDocumento() {
        val capacita = Capacita(listOf("frontale"), 5.0, false, specchia = true, pro = true)
        val atteso = """{"obiettivi":["frontale"],"pro":true,"specchia":true,"tipo":"capacita","torcia":false,"zoomMassimo":5}"""
        assertEquals(atteso, json(capacita))
        assertEquals(capacita, decodifica(atteso))
        val vecchio = decodifica("""{"tipo":"capacita","obiettivi":["frontale"],"zoomMassimo":5,"torcia":false}""") as Capacita
        assertEquals(null, vecchio.pro)
    }

    /** Lo stesso JSON, carattere per carattere, di testSceltaCollegamentoComeNelDocumento (Swift) e SceltaCollegamentoComeNelDocumento (C#). */
    @Test
    fun sceltaCollegamentoComeNelDocumento() {
        val capacita = Capacita(listOf("frontale"), 5.0, false, sceltaCollegamento = true)
        val attesoCapacita = """{"obiettivi":["frontale"],"sceltaCollegamento":true,"tipo":"capacita","torcia":false,"zoomMassimo":5}"""
        assertEquals(attesoCapacita, json(capacita))
        assertEquals(capacita, decodifica(attesoCapacita))

        val comando = Comando(collegamento = PreferenzeCollegamento.CAVO)
        val attesoComando = """{"collegamento":"cavo","tipo":"comando"}"""
        assertEquals(attesoComando, json(comando))
        assertEquals(comando, decodifica(attesoComando))

        val collegamento = StatoCollegamento(
            StradeCollegamento.WIFI, PreferenzeCollegamento.AUTOMATICO,
            listOf(
                StradaCollegamento(StradeCollegamento.WIFI, 38), StradaCollegamento(StradeCollegamento.CAVO, 9),
                StradaCollegamento(StradeCollegamento.HOTSPOT),
            ),
        )
        val stato = StatoTelefono(80, true, Temperatura.NORMALE, "frontale", collegamento = collegamento)
        val attesoStato = """{"batteria":80,"collegamento":{"attivo":"wifi","preferenza":"automatico","strade":[{"ms":38,"tipo":"wifi"},{"ms":9,"tipo":"cavo"},{"tipo":"hotspot"}]},"inCarica":true,"obiettivo":"frontale","temperatura":"normale","tipo":"stato"}"""
        assertEquals(attesoStato, json(stato))
        assertEquals(stato, decodifica(attesoStato))
        assertEquals(StradeCollegamento.CAVO, collegamento.piuVeloce)

        // Valori sconosciuti e «strade» assente: il messaggio si legge lo stesso.
        val futuro = decodifica(
            """{"tipo":"stato","batteria":80,"inCarica":true,"temperatura":"normale","obiettivo":"frontale","collegamento":{"attivo":"satellite","preferenza":"telepatia"}}""",
        ) as StatoTelefono
        assertEquals(StatoCollegamento("satellite", "telepatia", emptyList()), futuro.collegamento)
        assertNull(futuro.collegamento?.piuVeloce)
    }

    /** Lo stesso JSON, carattere per carattere, di testProspettivaComeNelDocumento (Swift) e ProspettivaComeNelDocumento (C#). */
    @Test
    fun prospettivaComeNelDocumento() {
        val inOnda = InOnda(false, selezionato = false)
        val atteso = """{"attivo":false,"selezionato":false,"tipo":"in-onda"}"""
        assertEquals(atteso, json(inOnda))
        assertEquals(inOnda, decodifica(atteso))
        assertEquals("""{"tipo":"usa-prospettiva"}""", json(UsaProspettiva))
        assertEquals(UsaProspettiva, decodifica("""{"tipo":"usa-prospettiva"}"""))
    }

    @Test
    fun anteprimaEFormatoAudioComeNelDocumento() {
        assertEquals("""{"tipo":"anteprima","visibile":false}""", json(Anteprima(false)))
        val formato = """{"canali":1,"codec":"aac-lc","configurazione":"EYg=","frequenza":48000,"tipo":"formato-audio"}"""
        assertEquals(formato, json(FormatoAudio()))
        assertEquals(FormatoAudio(), decodifica(formato))
    }

    /** I telefoni vecchi mandano `stato` senza i campi nuovi; valori futuri e campi sconosciuti non sono errori. */
    @Test
    fun messaggiVecchiSenzaCampiNuovi() {
        assertEquals(
            StatoTelefono(50, false, Temperatura.CALDA, "tele"),
            decodifica("""{"tipo":"stato","batteria":50,"inCarica":false,"temperatura":"calda","obiettivo":"tele"}"""),
        )
        assertEquals(Comando(filtro = "futuro"), decodifica("""{"tipo":"comando","filtro":"futuro","nuovo":{"a":1}}"""))
        assertFailsWith<ErroreProtocollo> { decodifica("""{"tipo":"comando","scritta":"Ledion"}""") }
    }

    @Test
    fun pacchettoAudio() {
        val audio = PacchettoAudio(0x0102030405060708uL, byteArrayOf(0x21, 0x10, 0x04))
        val pacchetto = audio.pacchetto
        assertEquals(TipoPacchetto.AUDIO, pacchetto.tipo)
        assertEquals(0, pacchetto.flag)
        assertContentEquals(byteArrayOf(3, 0, 0, 0, 0, 11, 1, 2, 3, 4, 5, 6, 7, 8, 0x21, 0x10, 0x04), pacchetto.codificato())
        assertEquals(audio, PacchettoAudio.da(pacchetto))

        val lettore = LettorePacchetti()
        lettore.aggiungi(pacchetto.codificato())
        assertEquals(audio, PacchettoAudio.da(lettore.prossimo()!!))
        assertFailsWith<ErroreProtocollo> { PacchettoAudio.da(Pacchetto(TipoPacchetto.AUDIO, 0, byteArrayOf(1, 2, 3))) }
        assertFailsWith<ErroreProtocollo> { PacchettoAudio.da(Pacchetto(TipoPacchetto.VIDEO, 0, pacchetto.contenuto)) }
        assertContentEquals(byteArrayOf(0x11, 0x88.toByte()), FormatoAudio.CONFIGURAZIONE_AAC_48K_MONO)
    }

    @Test
    fun tipoDiMessaggioSconosciutoSiIgnora() {
        assertEquals(Sconosciuto("futuro"), decodifica("""{"tipo":"futuro","x":1}"""))
    }

    /** Protocollo.md, «Valori sconosciuti»: gli stessi casi dei test Swift e C#. */
    @Test
    fun valoriSconosciutiNonFermanoIlMessaggio() {
        assertEquals(
            StatoTelefono(64, true, Temperatura.NORMALE, "macro", pausa = "riunione", sfondo = "spiaggia"),
            decodifica(
                """{"tipo":"stato","batteria":64,"inCarica":true,"temperatura":"rovente","obiettivo":"macro","pausa":"riunione","sfondo":"spiaggia","nuovo":{"a":[1,2]}}""",
            ),
        )
        val capacita = decodifica(
            """{"tipo":"capacita","obiettivi":["frontale","periscopio"],"zoomMassimo":5,"torcia":false,"pro":true,"futuro":7}""",
        ) as Capacita
        assertEquals(listOf("frontale", "periscopio"), capacita.obiettivi)
        assertEquals(5.0, capacita.zoomMassimo)
        assertEquals(true, capacita.pro)
        assertEquals(
            FormatoVideo(Codec.H264, 1920, 1080, 30),
            decodifica("""{"tipo":"formato","codec":"av1","larghezza":1920,"altezza":1080,"fps":30}"""),
        )
        assertEquals(
            Ciao(2, "Telefono", Piattaforma.SCONOSCIUTA, "3.0"),
            decodifica("""{"tipo":"ciao","versione":2,"nome":"Telefono","piattaforma":"visore","versioneApp":"3.0"}"""),
        )
        assertEquals(
            Benvenuto(2, "PC", Piattaforma.SCONOSCIUTA),
            decodifica("""{"tipo":"benvenuto","versione":2,"nome":"PC","piattaforma":"linux"}"""),
        )
        assertEquals(Sconosciuto("teletrasporto"), decodifica("""{"tipo":"teletrasporto","destinazione":"Marte"}"""))
    }

    @Test
    fun campiInPiuSiIgnorano() {
        assertEquals(Latenza(12), decodifica("""{"tipo":"latenza","ms":12,"nuovo":{"a":[1,2,{"b":null}]}}"""))
    }

    @Test
    fun messaggiNonValidiSonoErrori() {
        assertFailsWith<ErroreProtocollo> { decodifica("""{"tipo":"latenza"}""") }
        assertFailsWith<ErroreProtocollo> { decodifica("""{"tipo":"latenza","ms":"dodici"}""") }
        assertFailsWith<ErroreProtocollo> { decodifica("""{"ms":12}""") }
        assertFailsWith<ErroreProtocollo> { decodifica("""[1,2]""") }
        assertFailsWith<ErroreProtocollo> { decodifica("""{"tipo":"ciao",""") }
    }

    @Test
    fun testiConCaratteriSpeciali() {
        val messaggio = InOnda(true, "Studio \"A\" / Zoom\nè")
        val testo = json(messaggio)
        assertEquals("""{"app":"Studio \"A\" / Zoom\nè","attivo":true,"tipo":"in-onda"}""", testo)
        assertEquals(messaggio, decodifica(testo))
        assertEquals(InOnda(true, "Zoom"), decodifica("""{"tipo":"in-onda","attivo":true,"app":"Zoom"}"""))
    }
}

class AnnexBTest {
    @Test
    fun divisioneEUnione() {
        val sps = byteArrayOf(0x67, 1, 2)
        val pps = byteArrayOf(0x68, 3)
        val idr = byteArrayOf(0x65, 4, 0, 0, 2, 5)
        val dati = AnnexB.unisci(listOf(sps, pps)) + byteArrayOf(0, 0, 1) + idr
        val unita = AnnexB.unita(dati)
        assertEquals(3, unita.size)
        assertContentEquals(sps, unita[0])
        assertContentEquals(pps, unita[1])
        assertContentEquals(idr, unita[2])
        assertEquals(listOf(7, 8, 5), unita.map(AnnexB::tipoH264))
    }

    @Test
    fun tipiHEVC() {
        assertEquals(32, AnnexB.tipoHEVC(byteArrayOf(0x40, 0x01))) // VPS
        assertEquals(33, AnnexB.tipoHEVC(byteArrayOf(0x42, 0x01))) // SPS
        assertEquals(34, AnnexB.tipoHEVC(byteArrayOf(0x44, 0x01))) // PPS
        assertEquals(19, AnnexB.tipoHEVC(byteArrayOf(0x26, 0x01))) // IDR
    }
}

class AssociazioneTest {
    @Test
    fun qrComeNelDocumento() {
        val associazione = Associazione(listOf("192.168.1.20", "10.0.0.5"), nome = "MacBook Air")
        assertEquals("webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=MacBook%20Air&v=2", associazione.testo)
        assertEquals(associazione, Associazione.leggi(associazione.testo))
    }

    /** Lo stesso testo di «QRSicuroComeNelDocumento» in Swift e C#. */
    @Test
    fun qrSicuroComeNelDocumento() {
        val associazione = Associazione(listOf("192.168.1.20"), nome = "MacBook Air", versione = 2,
            impronta = "837DWUtYbfrElEqZA-g3UQ", gettone = "q_1-Zx")
        assertEquals("webcamlr://collega?h=192.168.1.20&p=52740&n=MacBook%20Air&v=2&k=837DWUtYbfrElEqZA-g3UQ&g=q_1-Zx", associazione.testo)
        assertEquals(associazione, Associazione.leggi(associazione.testo))
        assertNull(Associazione.leggi("webcamlr://collega?h=1.2.3.4&v=1")!!.impronta)
    }

    @Test
    fun nomeConCaratteriSpeciali() {
        val associazione = Associazione(listOf("192.168.1.20"), nome = "Studio & Casa+1")
        assertEquals("webcamlr://collega?h=192.168.1.20&p=52740&n=Studio%20%26%20Casa%2B1&v=2", associazione.testo)
        assertEquals("Studio & Casa+1", Associazione.leggi(associazione.testo)?.nome)
        val accentato = Associazione(listOf("192.168.1.20"), nome = "PC di Niccolò")
        assertEquals("PC di Niccolò", Associazione.leggi(accentato.testo)?.nome)
    }

    @Test
    fun altriQRSiIgnorano() {
        assertNull(Associazione.leggi("https://example.com"))
        assertNull(Associazione.leggi("webcamlr://collega?p=52740"))
    }

    @Test
    fun indirizzoScritto() {
        assertEquals(52740, Associazione.daIndirizzoScritto(" 192.168.1.20 ")?.porta)
        assertEquals(52741, Associazione.daIndirizzoScritto("192.168.1.20:52741")?.porta)
        assertNull(Associazione.daIndirizzoScritto("192.168.1"))
        assertNull(Associazione.daIndirizzoScritto("192.168.1.300"))
        assertNull(Associazione.daIndirizzoScritto("ciao"))
        assertNull(Associazione.daIndirizzoScritto("192.168.1.20:0"))
    }
}
