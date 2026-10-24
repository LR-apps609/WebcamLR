package it.lrapps.webcamlr.protocollo

import java.io.ByteArrayOutputStream

/**
 * Il contenuto del QR code che il computer mostra per farsi trovare senza mDNS (funzione 2).
 * Formato in Documenti/Protocollo.md: `webcamlr://collega?h=<indirizzi>&p=<porta>&n=<nome>&v=2&k=<impronta>&g=<gettone>`.
 */
data class Associazione(
    val indirizzi: List<String>,
    val porta: Int = Servizio.PORTA_PREDEFINITA,
    val nome: String,
    val versione: Int = Servizio.VERSIONE_PROTOCOLLO,
    /** Versione 2: impronta della chiave del computer (`k`), da verificare nella stretta di mano. */
    val impronta: String? = null,
    /** Versione 2: gettone di abbinamento (`g`), da rimandare nella prova. */
    val gettone: String? = null,
) {
    /** Come `Uri.EscapeDataString` di .NET: si lasciano solo lettere e cifre ASCII e `-_.~`. */
    val testo: String
        get() = buildString {
            append("webcamlr://collega?h=").append(indirizzi.joinToString(",") { codifica(it) })
            append("&p=").append(porta)
            append("&n=").append(codifica(nome))
            append("&v=").append(versione)
            // Impronta e gettone sono in base64url: nessun carattere da codificare.
            impronta?.let { append("&k=").append(it) }
            gettone?.let { append("&g=").append(it) }
        }

    companion object {
        private const val INIZIO = "webcamlr://collega?"

        /** Legge un QR code di WebcamLR; `null` se non lo è. */
        fun leggi(testo: String): Associazione? {
            val pulito = testo.trim()
            if (!pulito.startsWith(INIZIO)) return null
            val valori = LinkedHashMap<String, String>()
            for (coppia in pulito.substring(INIZIO.length).substringBefore('#').split('&')) {
                val uguale = coppia.indexOf('=')
                if (uguale <= 0) continue
                val nome = decodifica(coppia.substring(0, uguale)) ?: continue
                val valore = decodifica(coppia.substring(uguale + 1)) ?: continue
                valori.putIfAbsent(nome, valore)
            }
            val indirizzi = (valori["h"] ?: "").split(',').filter { it.isNotEmpty() }
            if (indirizzi.isEmpty()) return null
            val porta = valori["p"]?.toIntOrNull()?.takeIf { it in 1..65535 } ?: Servizio.PORTA_PREDEFINITA
            return Associazione(
                indirizzi = indirizzi,
                porta = porta,
                nome = valori["n"]?.takeIf { it.isNotEmpty() } ?: indirizzi[0],
                versione = valori["v"]?.toIntOrNull() ?: Servizio.VERSIONE_PROTOCOLLO,
                impronta = valori["k"]?.takeIf { it.isNotEmpty() },
                gettone = valori["g"]?.takeIf { it.isNotEmpty() },
            )
        }

        /** Un indirizzo scritto a mano: `192.168.1.20` oppure `192.168.1.20:52741`. */
        fun daIndirizzoScritto(scritto: String): Associazione? {
            val parti = scritto.trim().split(':')
            if (parti.size > 2 || !eIPv4(parti[0])) return null
            var porta = Servizio.PORTA_PREDEFINITA
            if (parti.size == 2) {
                porta = parti[1].toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
            }
            return Associazione(listOf(parti[0]), porta, parti[0])
        }

        internal fun eIPv4(testo: String): Boolean {
            val numeri = testo.split('.')
            return numeri.size == 4 && numeri.all { parte ->
                parte.isNotEmpty() && parte.length <= 3 && parte.all { it in '0'..'9' } && parte.toInt() <= 255
            }
        }

        private const val ESADECIMALE = "0123456789ABCDEF"

        internal fun codifica(valore: String): String = buildString {
            for (byte in valore.toByteArray(Charsets.UTF_8)) {
                val c = byte.toInt() and 0xFF
                val lascia = c in 'A'.code..'Z'.code || c in 'a'.code..'z'.code || c in '0'.code..'9'.code ||
                    c == '-'.code || c == '_'.code || c == '.'.code || c == '~'.code
                if (lascia) {
                    append(c.toChar())
                } else {
                    append('%').append(ESADECIMALE[c shr 4]).append(ESADECIMALE[c and 0xF])
                }
            }
        }

        /** Toglie la codifica %XX (UTF-8); il «+» resta «+», come in URLComponents e in .NET. */
        internal fun decodifica(valore: String): String? {
            if ('%' !in valore) return valore
            val uscita = ByteArrayOutputStream()
            var i = 0
            while (i < valore.length) {
                val c = valore[i]
                if (c == '%') {
                    if (i + 2 >= valore.length) return null
                    val byte = valore.substring(i + 1, i + 3).toIntOrNull(16) ?: return null
                    uscita.write(byte)
                    i += 3
                } else {
                    // Fino al prossimo «%»: così le coppie di surrogati restano intere.
                    val fine = valore.indexOf('%', i).let { if (it < 0) valore.length else it }
                    uscita.write(valore.substring(i, fine).toByteArray(Charsets.UTF_8))
                    i = fine
                }
            }
            return uscita.toString(Charsets.UTF_8.name())
        }
    }
}
