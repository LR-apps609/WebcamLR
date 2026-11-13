package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.android.logica.RegolaRiconnessione.Lettura
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Collaudo 20 (t08 B1–B3, t13 B5–B6). */
class RegolaRiconnessioneTest {
    @Test
    fun iPrimiCinqueTentativiSonoQuelliDiPrima() {
        assertEquals(listOf(500L, 1_000L, 2_000L, 2_000L, 3_000L), (1..5).map { RegolaRiconnessione.attesaMs(it) })
        assertEquals(8_500L, (1..5).sumOf { RegolaRiconnessione.attesaMs(it) })
    }

    @Test
    fun poiLAttesaCresceFinoAlTetto() {
        assertEquals(listOf(5_000L, 10_000L, 15_000L, 15_000L), (6..9).map { RegolaRiconnessione.attesaMs(it) })
        assertEquals(RegolaRiconnessione.ATTESA_MASSIMA_MS, RegolaRiconnessione.attesaMs(10_000))
    }

    @Test
    fun giaCollegatoNonSiArrendeMai() {
        assertTrue(RegolaRiconnessione.continua(4, giaCollegato = false))
        assertFalse(RegolaRiconnessione.continua(5, giaCollegato = false))
        assertTrue(RegolaRiconnessione.continua(5, giaCollegato = true))
        assertTrue(RegolaRiconnessione.continua(500, giaCollegato = true))
    }

    @Test
    fun laRetePersaDuranteLaConfermaNonEUnNo() {
        // t08 B2 e B3: niente arrivederci, niente tempo scaduto.
        assertEquals(Lettura.ALTRO, RegolaRiconnessione.leggi(dalComputer = false, tempoScaduto = false, accolto = false, msDallaRichiestaDelCodice = 12_000))
    }

    @Test
    fun noVeroETempoScaduto() {
        assertEquals(Lettura.RIFIUTATO_IN_CONFERMA, RegolaRiconnessione.leggi(true, false, false, 8_000))
        // Il computer chiude la domanda dopo 60 s con lo stesso arrivederci: è un tempo scaduto (t13 B6).
        assertEquals(Lettura.CONFERMA_SENZA_RISPOSTA, RegolaRiconnessione.leggi(true, false, false, 60_200))
        assertEquals(Lettura.CONFERMA_SENZA_RISPOSTA, RegolaRiconnessione.leggi(false, true, false, 65_000))
    }

    @Test
    fun arrivederciSenzaCodiceEPrimaDelBenvenuto() {
        // t13 B5: il computer non accetta il telefono (rifiutato da poco, un altro telefono senza Pro…).
        assertEquals(Lettura.NON_ACCETTATO, RegolaRiconnessione.leggi(true, false, false, null))
        // Dopo il benvenuto è il solito «Scollega» dal computer.
        assertEquals(Lettura.ALTRO, RegolaRiconnessione.leggi(true, false, true, null))
        assertEquals(Lettura.ALTRO, RegolaRiconnessione.leggi(false, true, false, null))
    }
}
