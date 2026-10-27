package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Capacita
import it.lrapps.webcamlr.protocollo.Codec
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.Filtri
import it.lrapps.webcamlr.protocollo.FormatoSupportato
import it.lrapps.webcamlr.protocollo.FormatoVideo
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.MotiviPausa
import it.lrapps.webcamlr.protocollo.Regolazioni
import it.lrapps.webcamlr.protocollo.Scritta
import it.lrapps.webcamlr.protocollo.StatoTelefono
import it.lrapps.webcamlr.protocollo.Temperatura
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** La logica pura dell'app Android (senza Android): si prova con Android Studio o con un progetto JVM. */
class LogicaTest {

    // LimitiGratis

    @Test
    fun gratisToglieIComandiPro() {
        val comando = Comando(
            filtro = Filtri.CINEMA, regolazioni = Regolazioni(luminosita = 0.5), sfondo = ModiSfondo.SOSTITUITO, pelle = 0.4,
            inquadratura = true, scritta = Scritta("Ledion"), doppiaVista = true, iso = 400.0, tempo = 60, bianco = 4000,
            zoom = 2.0, specchia = true, luceVolto = true, audio = true,
        )
        val gratis = LimitiGratis.soloGratis(comando)
        assertNull(gratis.filtro)
        assertNull(gratis.regolazioni)
        assertNull(gratis.sfondo)
        assertNull(gratis.pelle)
        assertNull(gratis.inquadratura)
        assertNull(gratis.scritta)
        assertNull(gratis.doppiaVista)
        assertNull(gratis.iso)
        assertNull(gratis.tempo)
        assertNull(gratis.bianco)
        assertEquals(2.0, gratis.zoom)
        assertEquals(true, gratis.specchia)
        assertEquals(true, gratis.luceVolto)
        assertEquals(true, gratis.audio)
    }

    @Test
    fun gratisLasciaSpegnere() {
        val spegni = Comando(
            filtro = Filtri.NATURALE, regolazioni = Regolazioni(0.0, 0.0, 0.0, 0.0), sfondo = ModiSfondo.SFOCATO, pelle = 0.0,
            inquadratura = false, scritta = Scritta(""), iso = 0.0, tempo = 0, bianco = 0,
        )
        assertEquals(spegni, LimitiGratis.soloGratis(spegni))
    }

    @Test
    fun gratisFormatiFinoA720p30() {
        val formati = listOf(FormatoSupportato(3840, 2160, 30), FormatoSupportato(1920, 1080, 60), FormatoSupportato(1280, 720, 60))
        assertEquals(listOf(FormatoSupportato(1280, 720, 30)), LimitiGratis.formati(formati))
    }

    // Formato

    @Test
    fun richiestaScendePrimaDiFpsPoiDiRisoluzione() {
        val massimi = mapOf((3840 to 2160) to 30, (1920 to 1080) to 60, (1280 to 720) to 60)
        val fps = { l: Int, a: Int -> massimi[l to a] ?: 0 }
        assertEquals(FormatoScelto(3840, 2160, 30, Codec.HEVC), FormatoRichiesto.da(FormatoVideo(Codec.HEVC, 3840, 2160, 60), fps))
        assertEquals(FormatoScelto(1920, 1080, 60, Codec.H264), FormatoRichiesto.da(FormatoVideo(Codec.H264, 1080, 1920, 60), fps))
        // 4K a 15 fps soli: meglio 1080p.
        val lento = { l: Int, a: Int -> if (l == 3840) 15 else 30 }
        assertEquals(FormatoScelto(1920, 1080, 30, Codec.H264), FormatoRichiesto.da(FormatoVideo(Codec.H264, 3840, 2160, 30), lento))
        assertNull(FormatoRichiesto.da(FormatoVideo(Codec.H264, 0, 0, 30), fps))
        assertNull(FormatoRichiesto.da(FormatoVideo(Codec.H264, 1920, 1080, -5), fps))
    }

    @Test
    fun formatoEffettivoConLimiti() {
        val scelto = FormatoScelto(3840, 2160, 60, Codec.H264)
        // Gratis: 720p30.
        assertEquals(FormatoScelto(1280, 720, 30, Codec.H264), SceltaFormato.effettivo(scelto, null, RiduzioneCalore.NESSUNA, false, pro = false))
        // Pro: 4K solo a 30 e in HEVC se scelto sul telefono.
        assertEquals(FormatoScelto(3840, 2160, 30, Codec.HEVC), SceltaFormato.effettivo(scelto, null, RiduzioneCalore.NESSUNA, false, pro = true))
        // Chiesto dal computer: il codec resta.
        val richiesto = FormatoScelto(3840, 2160, 30, Codec.H264)
        assertEquals(richiesto, SceltaFormato.effettivo(scelto, richiesto, RiduzioneCalore.NESSUNA, false, pro = true))
        assertEquals(FormatoScelto(1920, 1080, 30, Codec.H264), SceltaFormato.effettivo(FormatoScelto(1920, 1080, 60, Codec.H264), null, RiduzioneCalore.A1080P30, false, true))
        assertEquals(FormatoScelto(1280, 720, 24, Codec.H264), SceltaFormato.effettivo(FormatoScelto(1920, 1080, 60, Codec.H264), null, RiduzioneCalore.A720P24, false, true))
        assertEquals(24, SceltaFormato.effettivo(FormatoScelto(1920, 1080, 30, Codec.H264), null, RiduzioneCalore.NESSUNA, true, true).fps)
    }

    @Test
    fun caloreScendeSubitoERisaleConCalma() {
        val calore = RegolatoreCalore()
        assertEquals(RiduzioneCalore.NESSUNA, calore.valuta(Temperatura.CALDA, true, 0))
        assertEquals(RiduzioneCalore.NESSUNA, calore.valuta(Temperatura.CALDA, true, 59_000))
        assertEquals(RiduzioneCalore.A30FPS, calore.valuta(Temperatura.CALDA, true, 60_000))
        assertEquals(RiduzioneCalore.A720P24, calore.valuta(Temperatura.CRITICA, true, 61_000))
        // Più fresco: si resta per due minuti, poi un gradino alla volta.
        assertEquals(RiduzioneCalore.A720P24, calore.valuta(Temperatura.NORMALE, true, 62_000))
        assertEquals(RiduzioneCalore.A720P24, calore.valuta(Temperatura.NORMALE, true, 181_000))
        assertEquals(RiduzioneCalore.A1080P30, calore.valuta(Temperatura.NORMALE, true, 182_000))
        assertEquals(RiduzioneCalore.A1080P30, calore.valuta(Temperatura.NORMALE, true, 300_000))
        assertEquals(RiduzioneCalore.A30FPS, calore.valuta(Temperatura.NORMALE, true, 302_000))
        assertEquals(RiduzioneCalore.NESSUNA, calore.valuta(Temperatura.NORMALE, true, 422_000))
        // Ancora caldo durante la risalita: si torna giù subito.
        assertEquals(RiduzioneCalore.A1080P30, calore.valuta(Temperatura.MOLTO_CALDA, true, 423_000))
        assertEquals(RiduzioneCalore.NESSUNA, calore.valuta(Temperatura.CRITICA, false, 424_000))
    }

    // Pausa

    private class OrologioFinto {
        var adesso = 0L
        val attese = mutableListOf<Pair<Long, () -> Unit>>()
        fun pianifica(ritardo: Long, azione: () -> Unit): Annullabile {
            val voce = (adesso + ritardo) to azione
            attese += voce
            return Annullabile { attese.remove(voce) }
        }
        fun avanza(ms: Long) {
            adesso += ms
            attese.filter { it.first <= adesso }.forEach { attese.remove(it); it.second() }
        }
    }

    @Test
    fun maiPausaNessunaApp() {
        // Decisione del 27 ottobre: il telefono non va più in pausa perché nessuna app usa la webcam.
        val orologio = OrologioFinto()
        var cambi = 0
        val pausa = DecisorePausa(orologio::pianifica) { cambi++ }
        pausa.avvia()
        pausa.inOnda(false)
        pausa.anteprima(false)
        orologio.avanza(60_000)
        assertNull(pausa.motivo)
        assertFalse(pausa.fotocameraSpenta)
        assertEquals(0, cambi)
        pausa.nuovoCollegamento()
        pausa.anteprima(false)
        orologio.avanza(60_000)
        assertNull(pausa.motivo)
    }

    @Test
    fun pausaFacciaInGiuEUtente() {
        val orologio = OrologioFinto()
        val pausa = DecisorePausa(orologio::pianifica) {}
        pausa.avvia()
        pausa.gravita(0.95, 0)
        pausa.gravita(0.95, 900)
        assertNull(pausa.motivo)
        pausa.gravita(0.95, 1_000)
        assertEquals(MotiviPausa.FACCIA_IN_GIU, pausa.motivo)
        pausa.impostaPausaUtente(true)
        assertEquals(MotiviPausa.FACCIA_IN_GIU, pausa.motivo)
        pausa.gravita(0.8, 1_200)
        assertEquals(MotiviPausa.FACCIA_IN_GIU, pausa.motivo, "Isteresi: sotto 0,7 si riprende")
        pausa.gravita(0.2, 1_400)
        assertEquals(MotiviPausa.UTENTE, pausa.motivo)
        pausa.impostaPausaUtente(false)
        assertNull(pausa.motivo)
        pausa.gravita(Double.NaN, 2_000)
        pausa.facciaInGiuAbilitata = false
        pausa.gravita(1.0, 3_000)
        pausa.gravita(1.0, 9_000)
        assertNull(pausa.motivo)
    }

    // Effetti

    @Test
    fun effettiNeiLimitiEValoriSconosciuti() {
        val comando = Comando(
            filtro = "arcobaleno", regolazioni = Regolazioni(luminosita = 7.0, contrasto = Double.NaN), sfondo = "spazio",
            intensitaSfondo = Double.POSITIVE_INFINITY, pelle = -3.0, scritta = Scritta("L".repeat(100) + "\n", "R".repeat(100)),
        )
        val stato = ModelloEffetti.applica(StatoEffetti(), comando)
        assertEquals(Filtri.NATURALE, stato.filtro)
        assertEquals(1.0, stato.luminosita)
        assertEquals(0.0, stato.contrasto)
        assertEquals(ModiSfondo.NESSUNO, stato.sfondo)
        assertEquals(0.5, stato.intensitaSfondo)
        assertEquals(0.0, stato.pelle)
        assertEquals(StatoEffetti.LUNGHEZZA_NOME, stato.nomeScritta.length)
        assertEquals(StatoEffetti.LUNGHEZZA_RUOLO, stato.ruoloScritta.length)
        // Solo i campi presenti.
        val dopo = ModelloEffetti.applica(stato.copy(sfondo = ModiSfondo.SFOCATO), Comando(regolazioni = Regolazioni(saturazione = 0.5)))
        assertEquals(1.0, dopo.luminosita)
        assertEquals(0.5, dopo.saturazione)
        assertEquals(ModiSfondo.SFOCATO, dopo.sfondo)
    }

    @Test
    fun spegniProTieneLoSfondoSfocato() {
        val pieno = StatoEffetti(filtro = Filtri.SEPPIA, sfondo = ModiSfondo.SFOCATO, pelle = 0.5, nomeScritta = "Ledion", inquadratura = true, luceVolto = true)
        val gratis = ModelloEffetti.spegniPro(pieno)
        assertEquals(Filtri.NATURALE, gratis.filtro)
        assertEquals(ModiSfondo.SFOCATO, gratis.sfondo)
        assertEquals(0.0, gratis.pelle)
        assertEquals("", gratis.nomeScritta)
        assertFalse(gratis.inquadratura)
        assertTrue(gratis.luceVolto)
        assertEquals(ModiSfondo.NESSUNO, ModelloEffetti.spegniPro(pieno.copy(sfondo = ModiSfondo.SOSTITUITO)).sfondo)
    }

    @Test
    fun statoECapacitaDiconoSoloCioCheSiSaFare() {
        val effetti = StatoEffetti(nomeScritta = " Ledion ", ruoloScritta = "  ")
        val senzaAnalisi = FunzioniDisponibili(sfondo = false, volti = false)
        val stato = ModelloEffetti.completa(StatoTelefono(80, true, Temperatura.NORMALE, "frontale"), effetti, senzaAnalisi)
        assertNull(stato.sfondo)
        assertNull(stato.inquadratura)
        assertEquals(Scritta("Ledion", null), stato.scritta)
        assertEquals(Filtri.NATURALE, stato.filtro)
        val capacita = ModelloEffetti.completa(Capacita(listOf("frontale"), 5.0, false), senzaAnalisi)
        assertNull(capacita.sfondo)
        assertNull(capacita.luceVolto)
        assertEquals(Filtri.TUTTI, capacita.filtri)
        val conAnalisi = ModelloEffetti.completa(Capacita(listOf("frontale"), 5.0, false), FunzioniDisponibili(sfondo = true, volti = true, audio = true))
        assertEquals(true, conAnalisi.sfondo)
        assertEquals(true, conAnalisi.inquadratura)
        assertEquals(true, conAnalisi.audio)
    }

    // Volti

    @Test
    fun inquadraturaSegueIlVoltoETornaIndietro() {
        val inquadratura = Inquadratura()
        inquadratura.acceso = true
        val volto = Rettangolo(0.6f, 0.3f, 0.7f, 0.45f)
        var riquadro = Inquadratura.Riquadro()
        var t = 0L
        repeat(120) {
            t += 33
            riquadro = inquadratura.passo(VoltiTrovati(listOf(volto), t, false), false, t, 0.033f)
        }
        assertTrue(riquadro.zoom > 1.3f, "zoom ${riquadro.zoom}")
        assertTrue(riquadro.x > 0.55f)
        // Specchio: lo stesso volto, specchiato.
        inquadratura.specchioCambiato()
        assertTrue(inquadratura.uscito.x < 0.45f, "specchiato: ${inquadratura.uscito.x}")
        inquadratura.acceso = false
        repeat(400) {
            t += 33
            riquadro = inquadratura.passo(null, false, t, 0.033f)
        }
        assertTrue(riquadro.intero)
        assertFalse(inquadratura.attivo)
    }

    @Test
    fun riquadroTieneIlVoltoSopraIlCentro() {
        val riquadro = Inquadratura.riquadroPer(listOf(Rettangolo(0.45f, 0.4f, 0.55f, 0.55f)))
        assertTrue(riquadro.y > 0.475f)
        val (x, y) = riquadro.primaDelloZoom(0.5f, 0.5f)
        assertEquals(riquadro.x, x)
        assertEquals(riquadro.y, y)
    }

    @Test
    fun luceSulVoltoLevigataEDiRado() {
        val luce = SeguiLuce()
        val volto = Rettangolo(0.4f, 0.3f, 0.6f, 0.5f)
        assertTrue(luce.considera(volto, 0) is SeguiLuce.Esponi)
        assertNull(luce.considera(volto, 200))
        assertNull(luce.considera(volto, 700), "fermo: niente di nuovo prima di 3 secondi")
        assertNotNull(luce.considera(volto, 3_100))
        assertNull(luce.considera(null, 4_000))
        assertEquals(SeguiLuce.Lascia, luce.considera(null, 5_200))
    }

    @Test
    fun posturaUnAvvisoOgniTreMinuti() {
        val postura = ControlloPostura()
        val vicino = Rettangolo(0.2f, 0.1f, 0.8f, 0.7f)
        assertNull(postura.considera(vicino, true, 0))
        assertEquals(ControlloPostura.Avviso.VICINO, postura.considera(vicino, true, 10_001))
        assertNull(postura.considera(null, true, 20_000))
        assertNull(postura.considera(null, true, 26_000), "fuori, ma l'ultimo avviso è recente")
        assertNull(postura.considera(null, false, 400_000), "non in onda: niente «fuori»")
    }

    // Filtri

    @Test
    fun curvaMonotonaEIdentita() {
        val identita = RicetteFiltri.tabella(floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1f))
        for (i in 0..255) assertTrue(kotlin.math.abs((identita[i].toInt() and 0xFF) - i) <= 1)
        for (filtro in Filtri.TUTTI) {
            val tabella = RicetteFiltri.tabella(RicetteFiltri.ricetta(filtro).curva)
            for (i in 1..255) assertTrue((tabella[i].toInt() and 0xFF) >= (tabella[i - 1].toInt() and 0xFF), "$filtro a $i")
        }
        assertTrue(RicetteFiltri.ricetta(Filtri.NATURALE).neutra)
        assertFalse(RicetteFiltri.ricetta(Filtri.CINEMA).neutra)
    }

    // Geometria dell'anteprima

    @Test
    fun anteprimaVideoInteroConLeBande() {
        // Video 1920×1080 in una vista verticale 1080×2400, senza rotazione: bande sopra e sotto.
        val r = it.lrapps.webcamlr.android.video.Geometria.rettangoloVideoNellaVista(1080f, 2400f, 1920, 1080, 0)
        assertEquals(0f, r[0])
        assertEquals(1080f, r[2])
        assertEquals(607.5f, r[3] - r[1], 0.01f)
        assertNull(it.lrapps.webcamlr.android.video.Geometria.anteprimaAlVideo(0.5f, 0.05f, 1080f, 2400f, 1920, 1080, 0))
        val centro = it.lrapps.webcamlr.android.video.Geometria.anteprimaAlVideo(0.5f, 0.5f, 1080f, 2400f, 1920, 1080, 0)!!
        assertEquals(0.5f, centro.first, 0.001f)
        assertEquals(0.5f, centro.second, 0.001f)
        // Girato di 90° in senso orario: l'angolo in alto a destra della vista è quello in alto a sinistra del video.
        val angolo = it.lrapps.webcamlr.android.video.Geometria.anteprimaAlVideo(1f, 0f, 1080f, 1920f, 1920, 1080, 90)!!
        assertEquals(0f, angolo.first, 0.001f)
        assertEquals(0f, angolo.second, 0.001f)
    }

    @Test
    fun anteprimaCheRiempieLoSchermo() {
        // Video 1080×1920 in una vista 1080×2400: ingrandito fino all'altezza, i lati escono dallo schermo.
        val g = it.lrapps.webcamlr.android.video.Geometria
        val r = g.rettangoloVideoNellaVista(1080f, 2400f, 1080, 1920, 0, riempi = true)
        assertEquals(0f, r[1], 0.01f)
        assertEquals(2400f, r[3], 0.01f)
        assertEquals(1350f, r[2] - r[0], 0.01f)
        // Il bordo sinistro dello schermo è già dentro il video: (1350 − 1080) / 2 = 135 px tagliati, cioè il 10 %.
        val sinistra = g.anteprimaAlVideo(0f, 0.5f, 1080f, 2400f, 1080, 1920, 0, riempi = true)!!
        assertEquals(0.1f, sinistra.first, 0.001f)
        assertEquals(0.5f, sinistra.second, 0.001f)
    }

    @Test
    fun videoEFotocameraAndataERitorno() {
        val p = it.lrapps.webcamlr.android.video.ParametriGeometria(1920, 1080, 270, true, 90, true, 1920, 1080)
        val (cx, cy) = it.lrapps.webcamlr.android.video.Geometria.videoAllaFotocamera(0.3f, 0.6f, p)
        val (vx, vy) = it.lrapps.webcamlr.android.video.Geometria.fotocameraAlVideo(cx, cy, p)
        assertEquals(0.3f, vx, 0.001f)
        assertEquals(0.6f, vy, 0.001f)
    }

    // DNS multicast

    @Test
    fun dnsLeggeUnaRispostaCompressa() {
        val risposta = rispostaFinta()
        val trovati = DnsMulticast.leggi(risposta, "_webcamlr._tcp.local")
        assertEquals(1, trovati.size)
        val pc = trovati[0]
        assertEquals("PC di Ledion", pc.nome)
        assertEquals(52740, pc.porta)
        assertEquals(listOf("192.168.42.10"), pc.indirizzi)
        assertEquals("windows", pc.testo["p"])
        assertEquals("2", pc.testo["v"])
        // Rovinato: nessuna eccezione.
        assertEquals(emptyList(), DnsMulticast.leggi(risposta.copyOf(40), "_webcamlr._tcp.local"))
        assertEquals(emptyList(), DnsMulticast.leggi(ByteArray(3), "_webcamlr._tcp.local"))
        // La domanda inizia con l'intestazione e una domanda.
        val domanda = DnsMulticast.domanda("_webcamlr._tcp.local")
        assertEquals(1, domanda[5].toInt())
        assertEquals(12, domanda[domanda.size - 3].toInt())
    }

    /** Una risposta come la manda Bonjour: PTR, SRV, TXT e A, con i nomi compressi. */
    private fun rispostaFinta(): ByteArray {
        val uscita = java.io.ByteArrayOutputStream()
        fun u16(v: Int) { uscita.write(v shr 8); uscita.write(v and 0xFF) }
        fun etichette(vararg parti: String) { parti.forEach { val b = it.toByteArray(); uscita.write(b.size); uscita.write(b) } }
        u16(0); u16(0x8400); u16(0); u16(4); u16(0); u16(0)
        // PTR _webcamlr._tcp.local → PC di Ledion._webcamlr._tcp.local
        val inizioServizio = uscita.size()
        etichette("_webcamlr", "_tcp", "local"); uscita.write(0)
        u16(12); u16(1); u16(0); u16(120)
        val istanza = java.io.ByteArrayOutputStream().apply { val b = "PC di Ledion".toByteArray(); write(b.size); write(b); write(0xC0); write(inizioServizio) }.toByteArray()
        u16(istanza.size)
        val inizioIstanza = uscita.size()
        uscita.write(istanza)
        // SRV
        uscita.write(0xC0); uscita.write(inizioIstanza)
        u16(33); u16(0x8001); u16(0); u16(120)
        val bersaglio = java.io.ByteArrayOutputStream().apply { write(2); write("pc".toByteArray()); write(5); write("local".toByteArray()); write(0) }.toByteArray()
        u16(6 + bersaglio.size); u16(0); u16(0); u16(52740)
        val inizioBersaglio = uscita.size()
        uscita.write(bersaglio)
        // TXT
        uscita.write(0xC0); uscita.write(inizioIstanza)
        u16(16); u16(0x8001); u16(0); u16(120)
        u16(14); uscita.write(3); uscita.write("v=2".toByteArray()); uscita.write(9); uscita.write("p=windows".toByteArray().copyOf(9))
        // A
        uscita.write(0xC0); uscita.write(inizioBersaglio)
        u16(1); u16(0x8001); u16(0); u16(120); u16(4)
        uscita.write(byteArrayOf(192.toByte(), 168.toByte(), 42, 10))
        return uscita.toByteArray()
    }
}
