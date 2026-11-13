package it.lrapps.webcamlr.android.logica

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

/** Collaudo 20 (t13 B1): il tetto di «Segnala un bug». */
class TestoLiberoTest {
    @Test
    fun ilTestoCortoRestaUguale() {
        val testo = "Il video si ferma"
        assertSame(testo, TestoLibero.taglia(testo, TestoLibero.MASSIMO_SEGNALAZIONE))
    }

    @Test
    fun ilTestoEnormeSiTaglia() {
        val enorme = "a".repeat(300_000)
        assertEquals(TestoLibero.MASSIMO_SEGNALAZIONE, TestoLibero.taglia(enorme, TestoLibero.MASSIMO_SEGNALAZIONE).length)
    }

    @Test
    fun unEmojiNonSiSpezza() {
        val testo = "ab😀cd"
        assertEquals("ab", TestoLibero.taglia(testo, 3))
        assertEquals("ab😀", TestoLibero.taglia(testo, 4))
    }
}
