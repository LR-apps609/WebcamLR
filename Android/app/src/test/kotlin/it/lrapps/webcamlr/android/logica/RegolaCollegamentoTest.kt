package it.lrapps.webcamlr.android.logica

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** La regola «Automatico» (Documenti/Interfaccia finale.md): niente sbalzi. */
class RegolaCollegamentoTest {
    private val wifi = setOf(Strada.WIFI)
    private val entrambe = setOf(Strada.WIFI, Strada.CAVO)
    private val cavo = setOf(Strada.CAVO)

    @Test
    fun ilCavoGiaPresenteAllInizioNonFaCambiare() {
        val regola = RegolaCollegamento()
        regola.disponibilita(entrambe)
        // Il Wi-Fi ha vinto la gara all'inizio: resta quello.
        regola.collegato(Strada.WIFI, 0)
        assertNull(regola.decidi(60_000))
    }

    @Test
    fun ilCavoAttaccatoDuranteIlWiFiFaUnPassaggio() {
        val regola = RegolaCollegamento()
        regola.disponibilita(wifi)
        regola.collegato(Strada.WIFI, 0)
        regola.disponibilita(entrambe)
        assertEquals(Strada.CAVO, regola.decidi(1_000))
        regola.collegato(Strada.CAVO, 1_000)
        // Sul cavo si resta, anche se il Wi-Fi c'è.
        assertNull(regola.decidi(120_000))
    }

    @Test
    fun maiPerLaLatenza() {
        val regola = RegolaCollegamento()
        regola.disponibilita(entrambe)
        regola.collegato(Strada.CAVO, 0)
        // Nessun ingresso per la latenza: con tutte e due le strade si resta sul cavo per sempre.
        for (adesso in listOf(1_000L, 31_000L, 600_000L)) assertNull(regola.decidi(adesso))
        assertEquals(Strada.CAVO, RegolaCollegamento.piuVeloce(mapOf(Strada.WIFI to 38, Strada.CAVO to 9)))
    }

    @Test
    fun laStradaPersaPassaSubitoAncheNellaPausa() {
        val regola = RegolaCollegamento()
        regola.disponibilita(wifi)
        regola.collegato(Strada.WIFI, 0)
        regola.disponibilita(entrambe)
        regola.collegato(Strada.CAVO, 1_000)
        // Il cavo si stacca due secondi dopo il passaggio: si torna al Wi-Fi subito, per non perdere il video.
        regola.disponibilita(wifi)
        assertEquals(Strada.WIFI, regola.decidi(3_000))
    }

    @Test
    fun dopoUnCambioTrentaSecondiDiPausaAncheSeIlCavoVaEViene() {
        val regola = RegolaCollegamento()
        regola.disponibilita(entrambe)
        regola.collegato(Strada.CAVO, 0)
        regola.disponibilita(wifi)
        regola.collegato(Strada.WIFI, 1_000)
        // Il cavo torna dopo 5 secondi: niente passaggio finché non finisce la pausa.
        regola.disponibilita(entrambe)
        assertNull(regola.decidi(6_000))
        assertNull(regola.decidi(30_999))
        assertEquals(Strada.CAVO, regola.decidi(31_000))
    }

    @Test
    fun laSceltaManualeRestaETornaAppenaPuo() {
        val regola = RegolaCollegamento()
        regola.disponibilita(entrambe)
        regola.collegato(Strada.CAVO, 0)
        assertTrue(regola.impostaPreferenza(PreferenzeCollegamento.WIFI))
        // La scelta dell'utente vale subito, senza pausa.
        assertEquals(Strada.WIFI, regola.decidi(1_000, sceltaUtente = true))
        regola.collegato(Strada.WIFI, 1_000)
        // Il Wi-Fi si stacca: il cavo solo per non perdere il video…
        regola.disponibilita(cavo)
        assertEquals(Strada.CAVO, regola.decidi(2_000))
        regola.collegato(Strada.CAVO, 2_000)
        // …e si torna al Wi-Fi appena c'è di nuovo, passata la pausa.
        regola.disponibilita(entrambe)
        assertNull(regola.decidi(10_000))
        assertEquals(Strada.WIFI, regola.decidi(32_000))
    }

    @Test
    fun tornareAdAutomaticoNonFaCambiare() {
        val regola = RegolaCollegamento()
        regola.disponibilita(entrambe)
        regola.impostaPreferenza(PreferenzeCollegamento.CAVO)
        regola.collegato(Strada.CAVO, 0)
        regola.impostaPreferenza(PreferenzeCollegamento.AUTOMATICO)
        assertNull(regola.decidi(60_000, sceltaUtente = true))
        assertNull(regola.decidi(60_000))
    }

    @Test
    fun treTentativiFallitiFermanoLaStradaFincheNonTorna() {
        val regola = RegolaCollegamento()
        regola.disponibilita(entrambe)
        regola.impostaPreferenza(PreferenzeCollegamento.WIFI)
        regola.collegato(Strada.CAVO, 0)
        regola.tentativoFallito(Strada.WIFI, 0)
        assertNull(regola.decidi(10_000))
        assertEquals(Strada.WIFI, regola.decidi(30_000))
        regola.tentativoFallito(Strada.WIFI, 30_000)
        regola.tentativoFallito(Strada.WIFI, 60_000)
        assertNull(regola.decidi(10_000_000))
        // Il Wi-Fi va via e torna: si riprova.
        regola.disponibilita(cavo)
        regola.disponibilita(entrambe)
        assertEquals(Strada.WIFI, regola.decidi(10_000_000))
    }

    @Test
    fun valoriSconosciutiNonCambianoNulla() {
        val regola = RegolaCollegamento()
        assertFalse(regola.impostaPreferenza("piccione"))
        assertEquals(PreferenzeCollegamento.AUTOMATICO, regola.preferenza)
        assertNull(PreferenzeCollegamento.valida("5g"))
    }

    @Test
    fun laStradaInizialeEQuellaSceltaSeRaggiungeIlComputer() {
        val regola = RegolaCollegamento()
        assertNull(regola.stradaIniziale(entrambe))
        regola.impostaPreferenza(PreferenzeCollegamento.CAVO)
        assertEquals(Strada.CAVO, regola.stradaIniziale(entrambe))
        assertNull(regola.stradaIniziale(wifi))
    }

    @Test
    fun sottoreti() {
        val telefono = Sottoreti.numero("192.168.42.129")!!
        assertTrue(Sottoreti.stessa(telefono, Sottoreti.numero("192.168.42.17")!!, 24))
        assertFalse(Sottoreti.stessa(telefono, Sottoreti.numero("192.168.1.20")!!, 24))
        assertNull(Sottoreti.numero("fe80::1"))
        assertNull(Sottoreti.numero("300.1.1.1"))
    }
}
