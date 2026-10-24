package it.lrapps.webcamlr.protocollo

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import org.junit.Assume.assumeTrue

/**
 * Il telefono Kotlin contro un ricevitore vero (per esempio il cuore del ricevitore Windows, in C#), già in ascolto
 * su 127.0.0.1. Si salta se manca la variabile WEBCAMLR_RICEVITORE = "<porta> <impronta> <gettone o ->".
 * Esempio: WEBCAMLR_RICEVITORE="52740 837DWUtYbfrElEqZA-g3UQ q_1-Zx" gradle :protocollo:test --tests '*Interoperabilita*'
 */
class InteroperabilitaTest {

    @Test
    fun sessioneConUnRicevitoreVero() {
        val impostazione = System.getenv("WEBCAMLR_RICEVITORE")
        assumeTrue("WEBCAMLR_RICEVITORE non impostata", !impostazione.isNullOrBlank())
        val (porta, impronta, gettone) = impostazione!!.trim().split(" ")
        val conQr = gettone != "-"

        val eventi = LinkedBlockingQueue<EventoCollegamento>()
        val collegamento = Collegamento(
            listOf("127.0.0.1"), porta.toInt(), IdentitaDispositivo.nuova(),
            improntaAttesa = if (conQr) impronta else null, gettone = if (conQr) gettone else null,
            ciao = Ciao(nome = "Android di prova", piattaforma = Piattaforma.ANDROID, versioneApp = "0.1"),
            orologio = { (System.nanoTime() / 1000).toULong() },
            suEvento = { eventi.add(it) },
        )
        collegamento.avvia()
        val pronto = assertIs<EventoCollegamento.Pronto>(eventi.poll(10, TimeUnit.SECONDS))
        assertEquals(impronta, pronto.impronta)
        var evento = eventi.poll(70, TimeUnit.SECONDS)
        if (!conQr) {
            assertEquals(pronto.codice, assertIs<Approvazione>(assertIs<EventoCollegamento.Ricevuto>(evento).messaggio).codice)
            evento = eventi.poll(70, TimeUnit.SECONDS)
        }
        assertEquals("PC di prova", assertIs<Benvenuto>(assertIs<EventoCollegamento.Ricevuto>(evento).messaggio).nome)

        collegamento.invia(FormatoVideo(Codec.H264, 1280, 720, 30))
        collegamento.invia(Capacita(listOf("principale", "frontale"), 8.0, true))
        collegamento.invia(StatoTelefono(77, false, Temperatura.NORMALE, "principale"))
        // Un fotogramma chiave finto (SPS, PPS, IDR) e qualche fotogramma intermedio, 30 al secondo per 2 secondi.
        val chiave = AnnexB.unisci(listOf(byteArrayOf(0x67, 0x42, 0, 0x1F), byteArrayOf(0x68, 0xCE.toByte()), byteArrayOf(0x65, 1, 2, 3)))
        repeat(60) { indice ->
            val adesso = (System.nanoTime() / 1000).toULong()
            collegamento.inviaVideo(
                if (indice % 30 == 0) FotogrammaVideo(adesso, chiave = true, conParametri = true, dati = chiave)
                else FotogrammaVideo(adesso, chiave = false, conParametri = false, dati = AnnexB.unisci(listOf(byteArrayOf(0x41, indice.toByte())))),
            )
            Thread.sleep(33)
        }
        collegamento.chiudi()
        Thread.sleep(500)
    }
}
