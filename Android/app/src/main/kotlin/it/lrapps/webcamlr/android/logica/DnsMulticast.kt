package it.lrapps.webcamlr.android.logica

import java.io.ByteArrayOutputStream

/**
 * Il minimo di DNS multicast (RFC 6762/6763) per cercare `_webcamlr._tcp` da soli sulla rete del Tethering USB, dove
 * su alcune versioni di Android NsdManager non cerca. Solo la domanda PTR e la lettura delle risposte (PTR, SRV, TXT,
 * A), con i nomi compressi. Kotlin puro: si prova sul computer.
 */
object DnsMulticast {
    const val PORTA = 5353
    const val INDIRIZZO = "224.0.0.251"

    private const val TIPO_A = 1
    private const val TIPO_PTR = 12
    private const val TIPO_TXT = 16
    private const val TIPO_SRV = 33

    /** Un computer trovato nelle risposte: il nome dell'istanza (senza il tipo), porta, indirizzi e il TXT. */
    data class Servizio(val nome: String, val porta: Int, val indirizzi: List<String>, val testo: Map<String, String>)

    /** La domanda PTR per il servizio, per esempio `_webcamlr._tcp.local`. */
    fun domanda(servizio: String): ByteArray {
        val uscita = ByteArrayOutputStream()
        // Intestazione: id 0, flag 0 (domanda), una domanda, nessuna risposta.
        uscita.write(byteArrayOf(0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        scriviNome(uscita, servizio)
        uscita.write(byteArrayOf(0, TIPO_PTR.toByte(), 0, 1)) // tipo PTR, classe IN
        return uscita.toByteArray()
    }

    private fun scriviNome(uscita: ByteArrayOutputStream, nome: String) {
        for (etichetta in nome.trimEnd('.').split('.')) {
            val byte = etichetta.toByteArray(Charsets.UTF_8)
            require(byte.size in 1..63) { "Etichetta DNS non valida" }
            uscita.write(byte.size)
            uscita.write(byte)
        }
        uscita.write(0)
    }

    private class Record(val nome: String, val tipo: Int, val dati: Int, val lunghezza: Int)

    /**
     * Legge un messaggio DNS e restituisce le istanze di `servizio` complete (con porta e almeno un indirizzo IPv4).
     * Un messaggio rovinato o di altri servizi dà una lista vuota, mai un'eccezione.
     */
    fun leggi(messaggio: ByteArray, servizio: String): List<Servizio> = try {
        leggiRecord(messaggio, servizio)
    } catch (e: IndexOutOfBoundsException) {
        emptyList()
    } catch (e: IllegalArgumentException) {
        emptyList()
    }

    private fun leggiRecord(m: ByteArray, servizio: String): List<Servizio> {
        if (m.size < 12) return emptyList()
        fun u16(i: Int) = ((m[i].toInt() and 0xFF) shl 8) or (m[i + 1].toInt() and 0xFF)
        val domande = u16(4)
        val totale = u16(6) + u16(8) + u16(10)
        var i = 12
        repeat(domande) {
            i = saltaNome(m, i) + 4
        }
        val record = mutableListOf<Record>()
        repeat(totale) {
            val (nome, dopo) = leggiNome(m, i)
            val tipo = u16(dopo)
            val lunghezza = u16(dopo + 8)
            val dati = dopo + 10
            require(dati + lunghezza <= m.size)
            record += Record(nome.lowercase(), tipo, dati, lunghezza)
            i = dati + lunghezza
        }
        val tipoServizio = servizio.trimEnd('.').lowercase()
        val istanze = record.filter { it.tipo == TIPO_PTR && it.nome == tipoServizio }.map { leggiNome(m, it.dati).first }.distinct()
        return istanze.mapNotNull { istanza ->
            val chiave = istanza.lowercase()
            val srv = record.firstOrNull { it.tipo == TIPO_SRV && it.nome == chiave } ?: return@mapNotNull null
            val porta = u16(srv.dati + 4)
            val bersaglio = leggiNome(m, srv.dati + 6).first.lowercase()
            val indirizzi = record.filter { it.tipo == TIPO_A && it.nome == bersaglio && it.lunghezza == 4 }
                .map { r -> (0 until 4).joinToString(".") { (m[r.dati + it].toInt() and 0xFF).toString() } }
                .distinct()
            if (indirizzi.isEmpty() || porta <= 0) return@mapNotNull null
            val testo = record.firstOrNull { it.tipo == TIPO_TXT && it.nome == chiave }?.let { leggiTesto(m, it.dati, it.lunghezza) }.orEmpty()
            val nome = if (istanza.length > tipoServizio.length && istanza.lowercase().endsWith(".$tipoServizio")) {
                istanza.substring(0, istanza.length - tipoServizio.length - 1)
            } else {
                istanza
            }
            Servizio(nome, porta, indirizzi, testo)
        }
    }

    private fun leggiTesto(m: ByteArray, inizio: Int, lunghezza: Int): Map<String, String> {
        val coppie = mutableMapOf<String, String>()
        var i = inizio
        while (i < inizio + lunghezza) {
            val n = m[i].toInt() and 0xFF
            val voce = String(m, i + 1, minOf(n, inizio + lunghezza - i - 1), Charsets.UTF_8)
            val uguale = voce.indexOf('=')
            if (uguale > 0) coppie[voce.substring(0, uguale).lowercase()] = voce.substring(uguale + 1)
            i += n + 1
        }
        return coppie
    }

    private fun saltaNome(m: ByteArray, inizio: Int): Int {
        var i = inizio
        while (true) {
            val n = m[i].toInt() and 0xFF
            when {
                n == 0 -> return i + 1
                n and 0xC0 == 0xC0 -> return i + 2
                else -> i += n + 1
            }
        }
    }

    /** Il nome a partire da `inizio` (con i puntatori della compressione) e dove continua il messaggio. */
    private fun leggiNome(m: ByteArray, inizio: Int): Pair<String, Int> {
        val etichette = mutableListOf<String>()
        var i = inizio
        var fine = -1
        var salti = 0
        while (true) {
            val n = m[i].toInt() and 0xFF
            when {
                n == 0 -> {
                    if (fine < 0) fine = i + 1
                    break
                }
                n and 0xC0 == 0xC0 -> {
                    if (fine < 0) fine = i + 2
                    require(++salti < 32) { "Troppi puntatori" }
                    i = ((n and 0x3F) shl 8) or (m[i + 1].toInt() and 0xFF)
                }
                else -> {
                    etichette += String(m, i + 1, n, Charsets.UTF_8)
                    i += n + 1
                }
            }
        }
        return etichette.joinToString(".") to fine
    }
}
