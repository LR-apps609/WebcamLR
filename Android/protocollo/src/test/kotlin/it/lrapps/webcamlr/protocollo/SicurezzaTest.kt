package it.lrapps.webcamlr.protocollo

import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Collegamento sicuro (versione 2): gli stessi casi di SicurezzaTests.swift e SicurezzaTest.cs. */
class SicurezzaTest {

    private class Risultato(
        val telefono: SessioneSicura,
        val computer: SessioneSicura,
        val prova: Prova,
        val idTelefono: IdentitaDispositivo,
        val idComputer: IdentitaDispositivo,
    )

    private fun strettaCompleta(gettone: String? = null): Risultato {
        val idTelefono = IdentitaDispositivo.nuova()
        val idComputer = IdentitaDispositivo.nuova()
        val telefono = StrettaTelefono(idTelefono)
        val computer = StrettaComputer(idComputer)
        // Come in rete: i messaggi passano per il JSON.
        val apertura = CodificaMessaggi.daPacchetto(CodificaMessaggi.comePacchetto(telefono.apertura)) as Stretta
        val (risposta, sessioneComputer) = computer.rispondi(apertura)
        val rispostaInRete = CodificaMessaggi.daPacchetto(CodificaMessaggi.comePacchetto(risposta)) as Stretta
        val (sessioneTelefono, prova) = telefono.completa(rispostaInRete, gettone)
        return Risultato(sessioneTelefono, sessioneComputer, prova, idTelefono, idComputer)
    }

    @Test
    fun strettaDiManoECanaleNelleDueDirezioni() {
        val risultato = strettaCompleta(gettone = "gettone")
        assertEquals(risultato.idComputer.impronta, risultato.telefono.improntaAltro)
        assertEquals(risultato.idTelefono.impronta, risultato.computer.improntaAltro)
        assertEquals(risultato.computer.codice, risultato.telefono.codice)
        assertEquals(4, risultato.telefono.codice.length)
        assertTrue(StrettaComputer.provaValida(risultato.prova, risultato.computer))
        assertEquals("gettone", risultato.prova.gettone)

        val video = FotogrammaVideo(123u, true, true, byteArrayOf(0, 0, 0, 1, 0x65, 1, 2, 3)).pacchetto
        val ciao = CodificaMessaggi.comePacchetto(Ciao(nome = "Pixel di Ledion", piattaforma = Piattaforma.ANDROID, versioneApp = "0.1"))
        val videoCifrato = risultato.telefono.canale.cifra(video)
        val ciaoCifrato = risultato.telefono.canale.cifra(ciao)
        assertEquals(video.flag or CanaleCifrato.FLAG_CIFRATO, videoCifrato.flag)
        assertEquals(video.contenuto.size + 16, videoCifrato.contenuto.size)
        assertEquals(video, risultato.computer.canale.decifra(videoCifrato))
        assertEquals(ciao, risultato.computer.canale.decifra(ciaoCifrato))

        val ping = CodificaMessaggi.comePacchetto(Ping(42u))
        assertEquals(ping, risultato.telefono.canale.decifra(risultato.computer.canale.cifra(ping)))
    }

    @Test
    fun pacchettoAlteratoORipetutoNonPassa() {
        val risultato = strettaCompleta()
        val ping = CodificaMessaggi.comePacchetto(Ping(1u))
        val primo = risultato.computer.canale.cifra(ping)
        val alterato = Pacchetto(primo.tipo, primo.flag, primo.contenuto.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() })
        assertFailsWith<ErroreProtocollo> { risultato.telefono.canale.decifra(alterato) }
        assertEquals(ping, risultato.telefono.canale.decifra(primo))
        assertFailsWith<ErroreProtocollo> { risultato.telefono.canale.decifra(primo) }
        assertFailsWith<ErroreProtocollo> { risultato.telefono.canale.decifra(ping) }
    }

    @Test
    fun flagAlteratiNonPassano() {
        val risultato = strettaCompleta()
        val cifrato = risultato.computer.canale.cifra(CodificaMessaggi.comePacchetto(Ping(1u)))
        // I dati associati sono tipo e flag: cambiare il tipo rompe l'etichetta.
        assertFailsWith<ErroreProtocollo> { risultato.telefono.canale.decifra(Pacchetto(TipoPacchetto.VIDEO, cifrato.flag, cifrato.contenuto)) }
    }

    @Test
    fun computerFalsoNonPassa() {
        val telefono = StrettaTelefono(IdentitaDispositivo.nuova())
        val intruso = StrettaComputer(IdentitaDispositivo.nuova())
        val (risposta, _) = intruso.rispondi(telefono.apertura)
        val falsa = risposta.copy(identita = Sicurezza.base64(IdentitaDispositivo.nuova().pubblica))
        assertFailsWith<ErroreProtocollo> { telefono.completa(falsa) }
    }

    @Test
    fun provaDiUnAltraSessioneNonVale() {
        val primo = strettaCompleta()
        val secondo = strettaCompleta()
        assertFalse(StrettaComputer.provaValida(secondo.prova, primo.computer))
        assertFalse(StrettaComputer.provaValida(Prova("non-base64!"), primo.computer))
    }

    @Test
    fun chiaveFuoriDallaCurvaRifiutata() {
        val fuori = byteArrayOf(4) + ByteArray(64) { 0x11 }
        assertFailsWith<ErroreProtocollo> { Sicurezza.chiavePubblica(fuori) }
        val computer = StrettaComputer(IdentitaDispositivo.nuova())
        assertFailsWith<ErroreProtocollo> {
            computer.rispondi(Stretta(2, Sicurezza.base64(fuori), Sicurezza.base64(IdentitaDispositivo.nuova().pubblica)))
        }
    }

    @Test
    fun identitaSalvataERicaricata() {
        val originale = IdentitaDispositivo.nuova()
        val ricaricata = IdentitaDispositivo.daDatiSalvati(originale.datiDaSalvare)
        assertContentEquals(originale.pubblica, ricaricata.pubblica)
        assertEquals(22, originale.impronta.length)
        val firma = ricaricata.firma(byteArrayOf(1, 2, 3))
        assertEquals(64, firma.size)
        assertTrue(Sicurezza.verificaFirma(originale.pubblica, byteArrayOf(1, 2, 3), firma))
        assertFalse(Sicurezza.verificaFirma(originale.pubblica, byteArrayOf(1, 2, 4), firma))
    }

    @Test
    fun firmeDerEGrezzeSiConvertono() {
        // Valori con il bit alto acceso e con zeri davanti: i casi in cui DER aggiunge o toglie byte.
        val grezza = ByteArray(32) { if (it == 0) 0x80.toByte() else 1 } + ByteArray(32) { if (it < 2) 0 else 0x7F }
        assertContentEquals(grezza, Sicurezza.firmaGrezza(Sicurezza.firmaDer(grezza)))
        repeat(20) {
            val identita = IdentitaDispositivo.nuova()
            val dati = byteArrayOf(it.toByte())
            assertTrue(Sicurezza.verificaFirma(identita.pubblica, dati, identita.firma(dati)))
        }
    }

    @Test
    fun strettaComeNelDocumento() {
        val json = CodificaMessaggi.json(Stretta(versione = 2, chiave = "AQ==", identita = "Aw==", firma = "Ag=="))
        assertEquals("""{"chiave":"AQ==","firma":"Ag==","identita":"Aw==","tipo":"stretta","versione":2}""", json)
        assertTrue("gettone" !in CodificaMessaggi.json(Prova("AQ==")))
    }

    /** HKDF-SHA256, caso di prova 1 dell'RFC 5869. */
    @Test
    fun hkdfComeNellRfc() {
        val chiave = esadecimale("0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B0B")
        val sale = esadecimale("000102030405060708090A0B0C")
        val info = esadecimale("F0F1F2F3F4F5F6F7F8F9")
        assertEquals(
            "3CB25F25FAACD57A90434F64D0362F2A2D2D0A90CF1A5A4C5DB02D56ECC4C5BF34007208D5B887185865",
            esadecimale(Sicurezza.hkdf(chiave, sale, info, 42)),
        )
    }

    /** Gli stessi valori di SicurezzaTests.swift e SicurezzaTest.cs (ValoriDiRiferimentoUgualiInSwift). */
    @Test
    fun valoriDiRiferimentoUgualiInSwiftECSharp() {
        fun riempi(resto: Int) = byteArrayOf(4) + ByteArray(64) { resto.toByte() }

        val trascrizione = Sicurezza.trascrizione(riempi(0x11), riempi(0x22), riempi(0x33), riempi(0x44))
        val (telefonoComputer, computerTelefono) = Sicurezza.chiaviSessione(ByteArray(32) { 0x55 }, trascrizione)
        val cifrario = Cipher.getInstance("AES/GCM/NoPadding")
        cifrario.init(Cipher.ENCRYPT_MODE, SecretKeySpec(telefonoComputer, "AES"), GCMParameterSpec(128, CanaleCifrato.nonce(7u)))
        cifrario.updateAAD(byteArrayOf(1, 0x80.toByte()))
        val cifrato = cifrario.doFinal("WebcamLR".toByteArray())

        assertEquals("B14EE9D3F111558B44FEDEC6A6ADAAFFF75D268D60C2C0B9FB26F7E1879CB76E", esadecimale(trascrizione))
        assertEquals("4696", Sicurezza.codice(trascrizione))
        assertEquals("2644007CCCF250E04349A82D07209ECF5613AA1C6E8B1CE4E9175731094EEB51", esadecimale(telefonoComputer))
        assertEquals("D7A232B410AC8E6B2F46810DD8B950DD9E45ABAE9A1F053F16D1ED103EE83BAE", esadecimale(computerTelefono))
        assertEquals("3FD81BED90DA56B2F53C604C8EA349FE5998F721DB3D0E80", esadecimale(cifrato))
        assertEquals("837DWUtYbfrElEqZA-g3UQ", Sicurezza.impronta(riempi(0x44)))
    }

    /** Lo stesso calcolo passando dal canale: il pacchetto cifrato con il contatore 7 dà gli stessi byte. */
    @Test
    fun canaleDaGliStessiByteDelRiferimento() {
        fun riempi(resto: Int) = byteArrayOf(4) + ByteArray(64) { resto.toByte() }
        val trascrizione = Sicurezza.trascrizione(riempi(0x11), riempi(0x22), riempi(0x33), riempi(0x44))
        val (telefonoComputer, computerTelefono) = Sicurezza.chiaviSessione(ByteArray(32) { 0x55 }, trascrizione)
        val canale = CanaleCifrato(telefonoComputer, computerTelefono)
        var ultimo: Pacchetto? = null
        repeat(8) { ultimo = canale.cifra(Pacchetto(TipoPacchetto.CONTROLLO, 0, "WebcamLR".toByteArray())) }
        assertEquals(0x80, ultimo!!.flag)
        assertEquals("3FD81BED90DA56B2F53C604C8EA349FE5998F721DB3D0E80", esadecimale(ultimo!!.contenuto))
    }

    private fun esadecimale(dati: ByteArray) = dati.joinToString("") { "%02X".format(it.toInt() and 0xFF) }

    private fun esadecimale(testo: String) = ByteArray(testo.length / 2) { testo.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}
