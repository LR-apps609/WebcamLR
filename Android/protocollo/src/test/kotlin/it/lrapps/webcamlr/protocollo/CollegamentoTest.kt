package it.lrapps.webcamlr.protocollo

import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Il collegamento del telefono contro un computer simulato su 127.0.0.1, che parla il protocollo 2
 * come Mac e Windows (stretta di mano, prova, `approvazione`, `benvenuto`, `ping`).
 */
class CollegamentoTest {

    /** Come si comporta il computer simulato. */
    private enum class Modo { FIDATO, CHIEDE_CONFERMA, RIFIUTA, VERSIONE_1, MUTO }

    private class ComputerSimulato(val modo: Modo, val identita: IdentitaDispositivo = IdentitaDispositivo.nuova()) {
        val server = ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())
        val porta get() = server.localPort
        val ricevuti = LinkedBlockingQueue<Messaggio>()
        val video = LinkedBlockingQueue<FotogrammaVideo>()
        val audio = LinkedBlockingQueue<PacchettoAudio>()
        /** I tipi ricevuti dopo la stretta di mano, in ordine («audio» per i pacchetti di tipo 3). */
        val ordine = java.util.concurrent.ConcurrentLinkedQueue<String>()
        @Volatile var prova: Prova? = null
        @Volatile var provaValida = false
        @Volatile var codice: String? = null
        @Volatile var socket: Socket? = null
        @Volatile var sessione: SessioneSicura? = null

        init {
            Thread({ servi() }, "computer-simulato").apply { isDaemon = true }.start()
        }

        fun manda(messaggio: Messaggio) {
            val attuale = sessione ?: return
            synchronized(this) {
                socket?.getOutputStream()?.write(attuale.canale.cifra(CodificaMessaggi.comePacchetto(messaggio)).codificato())
            }
        }

        /** Un messaggio di controllo scritto a mano, anche non valido: come da un computer più nuovo. */
        fun mandaJson(testo: String) {
            val attuale = sessione ?: return
            synchronized(this) {
                val pacchetto = Pacchetto(TipoPacchetto.CONTROLLO, 0, testo.toByteArray(Charsets.UTF_8))
                socket?.getOutputStream()?.write(attuale.canale.cifra(pacchetto).codificato())
            }
        }

        private fun servi() {
            try {
                val connessione = server.accept()
                socket = connessione
                val ingresso = connessione.getInputStream()
                val lettore = LettorePacchetti()
                val buffer = ByteArray(65536)
                if (modo == Modo.VERSIONE_1) {
                    connessione.getOutputStream().write(CodificaMessaggi.comePacchetto(Ping(1u)).codificato())
                }
                while (true) {
                    val letti = ingresso.read(buffer)
                    if (letti < 0) return
                    lettore.aggiungi(buffer, 0, letti)
                    while (true) {
                        val pacchetto = lettore.prossimo() ?: break
                        gestisci(pacchetto)
                    }
                }
            } catch (e: Exception) {
                // il test chiude il server
            }
        }

        private fun gestisci(pacchetto: Pacchetto) {
            val attuale = sessione
            if (attuale == null) {
                val apertura = CodificaMessaggi.daPacchetto(pacchetto) as Stretta
                if (modo == Modo.VERSIONE_1 || modo == Modo.MUTO) return
                val (risposta, nuova) = StrettaComputer(identita).rispondi(apertura)
                socket!!.getOutputStream().write(CodificaMessaggi.comePacchetto(risposta).codificato())
                codice = nuova.codice
                sessione = nuova
                return
            }
            val chiaro = attuale.canale.decifra(pacchetto)
            if (chiaro.tipo == TipoPacchetto.VIDEO) {
                video.add(FotogrammaVideo.da(chiaro))
                return
            }
            if (chiaro.tipo == TipoPacchetto.AUDIO) {
                // Prima l'ordine, poi la coda: il test legge l'ordine dopo aver ricevuto dalla coda.
                ordine.add("audio")
                audio.add(PacchettoAudio.da(chiaro))
                return
            }
            val messaggio = CodificaMessaggi.daPacchetto(chiaro)
            ricevuti.add(messaggio)
            ordine.add(messaggio.tipo)
            when (messaggio) {
                is Prova -> {
                    prova = messaggio
                    provaValida = StrettaComputer.provaValida(messaggio, attuale)
                }
                is Ciao -> when (modo) {
                    Modo.FIDATO -> {
                        manda(Benvenuto(nome = "PC-STUDIO", piattaforma = Piattaforma.WINDOWS))
                        manda(Ping(777u))
                    }
                    Modo.CHIEDE_CONFERMA -> {
                        manda(Approvazione(attuale.codice))
                        Thread {
                            Thread.sleep(300)
                            manda(Benvenuto(nome = "PC-STUDIO", piattaforma = Piattaforma.WINDOWS))
                        }.start()
                    }
                    Modo.RIFIUTA -> manda(Arrivederci)
                    else -> Unit
                }
                else -> Unit
            }
        }

        fun chiudi() {
            try {
                socket?.close()
                server.close()
            } catch (e: Exception) {
                // già chiuso
            }
        }
    }

    private val daChiudere = mutableListOf<() -> Unit>()

    @AfterTest
    fun pulisci() = daChiudere.forEach { it() }

    private val tempiBrevi = TempiCollegamento(connessioneMs = 2_000, strettaMs = 1_000, benvenutoMs = 2_000, confermaMs = 3_000, silenzioMs = 1_500, secondoMs = 200)

    private fun collega(
        computer: ComputerSimulato,
        improntaAttesa: String? = null,
        gettone: String? = null,
        indirizzi: List<String> = listOf("127.0.0.1"),
    ): Pair<Collegamento, LinkedBlockingQueue<EventoCollegamento>> {
        val eventi = LinkedBlockingQueue<EventoCollegamento>()
        val collegamento = Collegamento(
            indirizzi, computer.porta, IdentitaDispositivo.nuova(), improntaAttesa, gettone,
            Ciao(nome = "Pixel di prova", piattaforma = Piattaforma.ANDROID, versioneApp = "0.1"),
            orologio = { 424242u }, suEvento = { eventi.add(it) }, tempi = tempiBrevi,
        )
        daChiudere.add { collegamento.chiudi(); computer.chiudi() }
        collegamento.avvia()
        return collegamento to eventi
    }

    private fun LinkedBlockingQueue<EventoCollegamento>.prossimo(): EventoCollegamento =
        poll(5, TimeUnit.SECONDS) ?: error("Nessun evento entro 5 secondi")

    private inline fun <reified T : Messaggio> LinkedBlockingQueue<Messaggio>.attendi(): T {
        val fine = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < fine) {
            val messaggio = poll(100, TimeUnit.MILLISECONDS) ?: continue
            if (messaggio is T) return messaggio
        }
        error("Il computer non ha ricevuto ${T::class.simpleName}")
    }

    @Test
    fun telefonoFidatoArrivaAlBenvenutoERispondeAiPing() {
        val computer = ComputerSimulato(Modo.FIDATO)
        val (collegamento, eventi) = collega(computer)

        val pronto = assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
        assertEquals(computer.identita.impronta, pronto.impronta)
        assertEquals(computer.codice, pronto.codice)
        val benvenuto = assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo())
        assertEquals("PC-STUDIO", (benvenuto.messaggio as Benvenuto).nome)

        val ciao = computer.ricevuti.attendi<Ciao>()
        assertEquals(Piattaforma.ANDROID, ciao.piattaforma)
        assertEquals(2, ciao.versione)
        assertTrue(computer.provaValida)
        // Il gettone va solo a un computer di cui si conosce l'impronta.
        assertEquals(null, computer.prova?.gettone)

        val pong = computer.ricevuti.attendi<Pong>()
        assertEquals(Pong(777u, 424242u), pong)

        val spedito = java.util.concurrent.CountDownLatch(1)
        collegamento.suPrimoFotogramma = { spedito.countDown() }
        // Video: si parte da un fotogramma chiave, quelli prima si saltano.
        collegamento.inviaVideo(FotogrammaVideo(1u, chiave = false, conParametri = false, dati = byteArrayOf(0, 0, 0, 1, 0x41)))
        collegamento.inviaVideo(FotogrammaVideo(2u, chiave = true, conParametri = true, dati = byteArrayOf(0, 0, 0, 1, 0x67, 0, 0, 0, 1, 0x65)))
        collegamento.inviaVideo(FotogrammaVideo(3u, chiave = false, conParametri = false, dati = byteArrayOf(0, 0, 0, 1, 0x41)))
        val primo = assertNotNull(computer.video.poll(5, TimeUnit.SECONDS))
        assertTrue(spedito.await(5, TimeUnit.SECONDS), "suPrimoFotogramma dopo il primo fotogramma spedito")
        assertEquals(2uL, primo.timestamp)
        assertTrue(primo.chiave)
        assertEquals(3uL, assertNotNull(computer.video.poll(5, TimeUnit.SECONDS)).timestamp)

        collegamento.invia(StatoTelefono(80, true, Temperatura.NORMALE, "principale"))
        assertEquals(80, computer.ricevuti.attendi<StatoTelefono>().batteria)

        collegamento.chiudi()
        computer.ricevuti.attendi<Arrivederci>()
    }

    @Test
    fun conLaReteSaturaAncheIFotogrammiChiaveHannoUnTetto() {
        val m = Collegamento.MASSIMO_IN_VOLO
        assertEquals(Collegamento.SceltaVideo.SALTA, Collegamento.sceltaVideo(0, chiave = false, attendiChiave = true))
        assertEquals(Collegamento.SceltaVideo.SPEDISCI, Collegamento.sceltaVideo(0, chiave = true, attendiChiave = true))
        assertEquals(Collegamento.SceltaVideo.SCARTA, Collegamento.sceltaVideo(m, chiave = false, attendiChiave = false))
        // Il fotogramma chiave passa con la coda piena, ma non oltre il doppio.
        assertEquals(Collegamento.SceltaVideo.SPEDISCI, Collegamento.sceltaVideo(m, chiave = true, attendiChiave = true))
        assertEquals(Collegamento.SceltaVideo.SCARTA, Collegamento.sceltaVideo(m * 2, chiave = true, attendiChiave = true))
        assertEquals(Collegamento.SceltaVideo.SPEDISCI, Collegamento.sceltaVideo(m - 1, chiave = false, attendiChiave = false))
    }

    @Test
    fun audioDopoIlBenvenutoConFormatoAudioPrimaDiOgniFlusso() {
        val computer = ComputerSimulato(Modo.FIDATO)
        val (collegamento, eventi) = collega(computer)
        // Prima del `benvenuto` l'audio non parte.
        collegamento.inviaAudio(PacchettoAudio(1u, byteArrayOf(1)), flusso = 1)
        assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
        assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo())

        collegamento.inviaAudio(PacchettoAudio(10u, byteArrayOf(1, 2)), flusso = 1)
        collegamento.inviaAudio(PacchettoAudio(20u, byteArrayOf(3)), flusso = 1)
        collegamento.inviaAudio(PacchettoAudio(30u, byteArrayOf(4)), flusso = 2)
        val formato = computer.ricevuti.attendi<FormatoAudio>()
        assertEquals("aac-lc", formato.codec)
        assertEquals("EYg=", formato.configurazione)
        assertEquals(10uL, assertNotNull(computer.audio.poll(5, TimeUnit.SECONDS)).timestamp)
        assertEquals(20uL, assertNotNull(computer.audio.poll(5, TimeUnit.SECONDS)).timestamp)
        assertEquals(30uL, assertNotNull(computer.audio.poll(5, TimeUnit.SECONDS)).timestamp)
        val sequenza = computer.ordine.filter { it == "audio" || it == "formato-audio" }
        assertEquals(listOf("formato-audio", "audio", "audio", "formato-audio", "audio"), sequenza)
    }

    @Test
    fun primaVoltaIlComputerChiedeLaConfermaConLoStessoCodice() {
        val computer = ComputerSimulato(Modo.CHIEDE_CONFERMA)
        val (_, eventi) = collega(computer)
        val pronto = assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
        val approvazione = assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo()).messaggio as Approvazione
        assertEquals(pronto.codice, approvazione.codice)
        assertEquals(4, approvazione.codice.length)
        assertIs<Benvenuto>(assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo()).messaggio)
    }

    @Test
    fun conIlQrCodeIlGettoneArrivaAlComputerGiusto() {
        val computer = ComputerSimulato(Modo.FIDATO)
        val (_, eventi) = collega(computer, improntaAttesa = computer.identita.impronta, gettone = "q_1-Zx")
        assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
        assertEquals("q_1-Zx", computer.ricevuti.attendi<Prova>().gettone)
    }

    @Test
    fun identitaDiversaDaQuellaAttesaSiFerma() {
        val computer = ComputerSimulato(Modo.FIDATO)
        val (_, eventi) = collega(computer, improntaAttesa = IdentitaDispositivo.nuova().impronta, gettone = "q_1-Zx")
        assertEquals(MotivoChiusura.IDENTITA_CAMBIATA, assertIs<EventoCollegamento.Chiuso>(eventi.prossimo()).motivo)
        assertFalse(computer.ricevuti.any { it is Prova })
    }

    @Test
    fun computerVersione1VaAggiornato() {
        val computer = ComputerSimulato(Modo.VERSIONE_1)
        val (_, eventi) = collega(computer)
        assertEquals(MotivoChiusura.COMPUTER_VECCHIO, assertIs<EventoCollegamento.Chiuso>(eventi.prossimo()).motivo)
    }

    @Test
    fun computerCheNonRispondeAllaStrettaVaAggiornato() {
        val computer = ComputerSimulato(Modo.MUTO)
        val (_, eventi) = collega(computer)
        assertEquals(MotivoChiusura.COMPUTER_VECCHIO, assertIs<EventoCollegamento.Chiuso>(eventi.prossimo()).motivo)
    }

    @Test
    fun arrivederciDalComputerNonSiRiprova() {
        val computer = ComputerSimulato(Modo.RIFIUTA)
        val (_, eventi) = collega(computer)
        assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
        assertEquals(MotivoChiusura.DAL_COMPUTER, assertIs<EventoCollegamento.Chiuso>(eventi.prossimo()).motivo)
    }

    /** Protocollo.md, «Valori sconosciuti»: tipo sconosciuto e messaggio illeggibile si saltano, il collegamento resta. */
    @Test
    fun valoriSconosciutiNonChiudonoIlCollegamento() {
        val computer = ComputerSimulato(Modo.FIDATO)
        val (_, eventi) = collega(computer)
        assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
        assertIs<Benvenuto>(assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo()).messaggio)

        computer.mandaJson("""{"tipo":"teletrasporto","destinazione":"Marte"}""")
        computer.mandaJson("""{"tipo":"comando","zoom":"tanto"}""")
        computer.mandaJson("""{"tipo":"comando","sfondo":"spiaggia","zoom":2,"nuovo":{"a":1}}""")
        computer.mandaJson("""{"tipo":"formato","codec":"av1","larghezza":1920,"altezza":1080,"fps":30}""")
        computer.manda(Ping(888u))

        assertEquals(Comando(sfondo = "spiaggia", zoom = 2.0), assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo()).messaggio)
        assertEquals(FormatoVideo(Codec.H264, 1920, 1080, 30), assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo()).messaggio)
        // Il telefono risponde ancora ai ping (il primo pong è per il ping dopo il benvenuto).
        assertEquals(Pong(777u, 424242u), computer.ricevuti.attendi<Pong>())
        assertEquals(Pong(888u, 424242u), computer.ricevuti.attendi<Pong>())
    }

    @Test
    fun silenzioDopoIlBenvenutoEUnaReteCaduta() {
        val computer = ComputerSimulato(Modo.FIDATO)
        val (_, eventi) = collega(computer)
        assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
        assertIs<EventoCollegamento.Ricevuto>(eventi.prossimo())
        // Il computer simulato manda un solo ping: dopo 1,5 secondi di silenzio il collegamento è perso.
        val chiuso = assertIs<EventoCollegamento.Chiuso>(eventi.poll(5, TimeUnit.SECONDS))
        assertEquals(MotivoChiusura.RETE, chiuso.motivo)
    }

    @Test
    fun nessunComputerAllIndirizzo() {
        val libera = ServerSocket(0).use { it.localPort }
        val eventi = LinkedBlockingQueue<EventoCollegamento>()
        val collegamento = Collegamento(
            listOf("127.0.0.1"), libera, IdentitaDispositivo.nuova(), null, null,
            Ciao(nome = "Pixel", piattaforma = Piattaforma.ANDROID, versioneApp = "0.1"),
            orologio = { 0u }, suEvento = { eventi.add(it) }, tempi = tempiBrevi,
        )
        collegamento.avvia()
        val chiuso = assertIs<EventoCollegamento.Chiuso>(eventi.prossimo())
        assertEquals(MotivoChiusura.RETE, chiuso.motivo)
        assertNotNull(chiuso.errore)
    }

    @Test
    fun piuIndirizziVinceQuelloCheRisponde() {
        val computer = ComputerSimulato(Modo.FIDATO)
        // 192.0.2.1 è riservato alla documentazione: non risponde mai.
        val (_, eventi) = collega(computer, indirizzi = listOf("192.0.2.1", "127.0.0.1"))
        assertIs<EventoCollegamento.Pronto>(eventi.prossimo())
    }
}

class QualitaTest {
    @Test
    fun soglieComeSuMacEWindows() {
        assertEquals(QualitaCollegamento.OTTIMA, QualitaCollegamento.da(40))
        assertEquals(QualitaCollegamento.BUONA, QualitaCollegamento.da(80))
        assertEquals(QualitaCollegamento.BUONA, QualitaCollegamento.da(40, perdite = 1))
        assertEquals(QualitaCollegamento.DEBOLE, QualitaCollegamento.da(150))
        assertEquals(QualitaCollegamento.DEBOLE, QualitaCollegamento.da(20, perdite = 10))
    }

    @Test
    fun bitrateSegueLaRete() {
        val rete = AdattamentoRete()
        val base = AdattamentoRete.bitrateBase(1920, 1080, 30, Codec.H264)
        assertEquals(6_000_000, base)
        assertEquals(3_600_000, AdattamentoRete.bitrateBase(1920, 1080, 30, Codec.HEVC))
        assertFalse(rete.secondo(scartati = 2, saturo = false))
        assertEquals(4_200_000, rete.bitrate(base))
        assertTrue(rete.secondo(0, saturo = true)) // 0,49: debole
        repeat(20) { rete.secondo(1, false) }
        assertEquals(1_200_000, rete.bitrate(base)) // mai sotto un quinto
        repeat(3) { rete.secondo(0, false) }
        assertEquals(1_800_000, rete.bitrate(base))
        assertEquals(500_000, AdattamentoRete().apply { repeat(10) { secondo(1, false) } }.bitrate(1_000_000))
    }

    @Test
    fun tipoDiCollegamentoDallInterfaccia() {
        assertEquals(TipoCollegamento.WIFI, TipoCollegamento.daInterfaccia("wlan0"))
        assertEquals(TipoCollegamento.CAVO_USB, TipoCollegamento.daInterfaccia("rndis0"))
        assertEquals(TipoCollegamento.CAVO_USB, TipoCollegamento.daInterfaccia("ncm0"))
        assertEquals(TipoCollegamento.HOTSPOT, TipoCollegamento.daInterfaccia("ap0"))
        assertEquals(TipoCollegamento.WIFI_DIRETTO, TipoCollegamento.daInterfaccia("p2p-wlan0-0"))
        assertEquals(TipoCollegamento.CAVO_DI_RETE, TipoCollegamento.daInterfaccia("eth0"))
        assertEquals(null, TipoCollegamento.daInterfaccia(null))
    }
}
