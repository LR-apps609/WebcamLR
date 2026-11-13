package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.android.logica.Indirizzi.Errore
import it.lrapps.webcamlr.android.logica.Indirizzi.Esito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Collaudo 20 (t13 B3, B4, B7): ogni indirizzo sbagliato ha il suo errore; i link impossibili non partono. */
class IndirizziTest {
    private fun errore(scritto: String) = (Indirizzi.leggiScritto(scritto) as? Esito.NonValido)?.errore

    @Test
    fun indirizziGiusti() {
        val semplice = Indirizzi.leggiScritto("  192.168.1.20 ") as Esito.Valido
        assertEquals(listOf("192.168.1.20"), semplice.associazione.indirizzi)
        assertEquals(52740, semplice.associazione.porta)
        val conPorta = Indirizzi.leggiScritto("10.0.2.2:52741") as Esito.Valido
        assertEquals(52741, conPorta.associazione.porta)
    }

    @Test
    fun laPortaSbagliataNonParlaDellIndirizzo() {
        for (scritto in listOf("10.0.2.2:99999", "10.0.2.2:0", "10.0.2.2:", "10.0.2.2:abc", "10.0.2.2:52740:1", "10.0.2.2:-1")) {
            assertEquals(Errore.PORTA, errore(scritto), scritto)
        }
    }

    @Test
    fun ogniErroreIlSuo() {
        assertEquals(Errore.VUOTO, errore("   "))
        assertEquals(Errore.CON_PROTOCOLLO, errore("http://10.0.2.2:52740"))
        assertEquals(Errore.IPV6, errore("fe80::1"))
        assertEquals(Errore.IPV6, errore("[::1]:52740"))
        assertEquals(Errore.IPV6, errore("2001:db8:0:0:0:0:0:1"))
        assertEquals(Errore.NOME, errore("localhost"))
        assertEquals(Errore.NOME, errore("pc.local"))
        assertEquals(Errore.NUMERI, errore("999.1.1.1"))
        assertEquals(Errore.NUMERI, errore("10.0.2"))
        assertEquals(Errore.NUMERI, errore("10.0.2.2.5"))
        assertEquals(Errore.NUMERI, errore("10.0.2.2 52740"))
        assertEquals(Errore.NUMERI, errore("-10.0.2.2"))
    }

    @Test
    fun indirizziCheNonSonoDiUnComputer() {
        for (scritto in listOf("0.0.0.0", "255.255.255.255", "127.0.0.1", "224.0.0.251", "0.1.2.3")) {
            assertEquals(Errore.NON_DI_UN_COMPUTER, errore(scritto), scritto)
        }
    }

    @Test
    fun linkBuoniECattivi() {
        val buono = assertNotNull(Indirizzi.leggiLink("webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=PC&v=2"))
        assertEquals(listOf("192.168.1.20", "10.0.0.5"), buono.indirizzi)
        // Senza porta: la predefinita, come sempre.
        assertEquals(52740, assertNotNull(Indirizzi.leggiLink("webcamlr://collega?h=192.168.1.20&n=PC")).porta)
        // Un indirizzo impossibile si toglie, gli altri restano.
        assertEquals(listOf("10.0.0.5"), assertNotNull(Indirizzi.leggiLink("webcamlr://collega?h=0.0.0.0,10.0.0.5&n=PC")).indirizzi)
        for (link in listOf(
            "webcamlr://collega", "webcamlr://collega?h=", "webcamlr://collega?x=1&y=2", "webcamlr://collega?h=%ZZ&n=Rotto",
            "webcamlr://collega?h=999.999.999.999", "webcamlr://collega?h=ciao%20mondo", "webcamlr://collega?h=10.0.2.2&p=0",
            "webcamlr://collega?h=10.0.2.2&p=99999", "webcamlr://collega?h=255.255.255.255",
        )) {
            assertNull(Indirizzi.leggiLink(link), link)
            assertTrue(Indirizzi.sembraUnLink(link), link)
        }
        assertTrue(Indirizzi.sembraUnLink("WEBCAMLR://COLLEGA?H=1"))
        assertEquals(false, Indirizzi.sembraUnLink("https://esempio.it"))
    }

    @Test
    fun ilNomeDiRipiegoEUnIndirizzoUsabile() {
        val link = assertNotNull(Indirizzi.leggiLink("webcamlr://collega?h=0.0.0.0,10.0.0.5"))
        assertEquals("10.0.0.5", link.nome)
    }
}
