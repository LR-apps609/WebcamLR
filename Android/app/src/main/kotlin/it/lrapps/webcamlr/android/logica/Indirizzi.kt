package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Associazione
import it.lrapps.webcamlr.protocollo.Servizio

/**
 * Collaudo 20 (t13 B3, B4, B7): l'indirizzo scritto a mano e il link `webcamlr://collega` si controllano prima di
 * accendere la fotocamera, e un errore dice la cosa sbagliata (la porta, il nome, «http://»…) invece di una frase sola.
 * Solo sul telefono Android: il formato del QR code resta quello di Documenti/Protocollo.md (`h` = indirizzi IPv4).
 */
object Indirizzi {
    /** Cosa c'è di sbagliato in un indirizzo scritto a mano; ogni caso ha il suo testo nell'interfaccia. */
    enum class Errore {
        /** Niente di scritto. */
        VUOTO,
        /** `http://…`: va scritto solo l'indirizzo. */
        CON_PROTOCOLLO,
        /** Un indirizzo IPv6 (`fe80::1`, `[::1]:52740`). */
        IPV6,
        /** Un nome (`localhost`, `pc.local`) al posto dei numeri. */
        NOME,
        /** Non sono quattro numeri da 0 a 255. */
        NUMERI,
        /** Quattro numeri giusti, ma non di un computer (0.0.0.0, 255.255.255.255, 127.x, multicast). */
        NON_DI_UN_COMPUTER,
        /** L'indirizzo va bene, la porta no (vuota, lettere, 0, oltre 65535, due porte). */
        PORTA,
    }

    /** L'esito: l'associazione con cui collegarsi, oppure l'errore. */
    sealed interface Esito {
        data class Valido(val associazione: Associazione) : Esito
        data class NonValido(val errore: Errore) : Esito
    }

    /** `192.168.1.20` oppure `192.168.1.20:52741`, con spazi intorno. */
    fun leggiScritto(scritto: String): Esito {
        val testo = scritto.trim()
        if (testo.isEmpty()) return Esito.NonValido(Errore.VUOTO)
        if ("://" in testo || testo.startsWith("http", ignoreCase = true) && ':' in testo) return Esito.NonValido(Errore.CON_PROTOCOLLO)
        if ('[' in testo || "::" in testo) return Esito.NonValido(Errore.IPV6)
        val parti = testo.split(':')
        val host = parti[0]
        if (parti.size > 2) {
            // Quattro numeri e poi due porte: è la porta a essere sbagliata. Altrimenti è un IPv6 scritto per intero.
            return Esito.NonValido(if (eIPv4(host)) Errore.PORTA else Errore.IPV6)
        }
        if (!eIPv4(host)) {
            val conLettere = host.any { it.isLetter() } && host.none { it.isWhitespace() }
            return Esito.NonValido(if (conLettere) Errore.NOME else Errore.NUMERI)
        }
        if (!diUnComputer(host)) return Esito.NonValido(Errore.NON_DI_UN_COMPUTER)
        var porta = Servizio.PORTA_PREDEFINITA
        if (parti.size == 2) {
            porta = portaValida(parti[1].trim()) ?: return Esito.NonValido(Errore.PORTA)
        }
        return Esito.Valido(Associazione(listOf(host), porta, host))
    }

    /**
     * Un link `webcamlr://collega` (fotocamera di sistema, altro lettore di QR code, lettore interno). `null` se non è di
     * WebcamLR, è incompleto o non porta a nessun computer: niente indirizzi IPv4 usabili in `h`, oppure una `p` scritta
     * ma non valida (prima si usava in silenzio la porta predefinita). Gli indirizzi inutilizzabili si tolgono.
     */
    fun leggiLink(testo: String): Associazione? {
        val associazione = Associazione.leggi(testo) ?: return null
        val portaScritta = parametro(testo.trim(), "p")
        if (portaScritta != null && portaValida(portaScritta) == null) return null
        val usabili = associazione.indirizzi.map { it.trim() }.filter { eIPv4(it) && diUnComputer(it) }.distinct()
        if (usabili.isEmpty()) return null
        val nome = if (associazione.nome == associazione.indirizzi[0]) usabili[0] else associazione.nome
        return associazione.copy(indirizzi = usabili, nome = nome)
    }

    /** Vero se il testo comincia come un link di WebcamLR (anche rovinato): merita un messaggio, non il silenzio. */
    fun sembraUnLink(testo: String): Boolean = testo.trim().startsWith("webcamlr:", ignoreCase = true)

    internal fun eIPv4(testo: String): Boolean {
        val numeri = testo.split('.')
        return numeri.size == 4 && numeri.all { parte ->
            parte.isNotEmpty() && parte.length <= 3 && parte.all { it in '0'..'9' } && parte.toInt() <= 255
        }
    }

    /** Né «qualsiasi» (0.x), né il telefono stesso (127.x), né multicast o broadcast (224 e oltre). */
    internal fun diUnComputer(ipv4: String): Boolean {
        val primo = ipv4.substringBefore('.').toIntOrNull() ?: return false
        return primo != 0 && primo != 127 && primo < 224
    }

    private fun portaValida(testo: String): Int? =
        testo.takeIf { it.isNotEmpty() && it.length <= 5 && it.all { c -> c in '0'..'9' } }?.toInt()?.takeIf { it in 1..65535 }

    /** Il valore grezzo di un parametro della query (senza decodifica: per la porta bastano le cifre). */
    private fun parametro(link: String, nome: String): String? {
        val query = link.substringAfter('?', "").substringBefore('#')
        for (coppia in query.split('&')) {
            val uguale = coppia.indexOf('=')
            if (uguale > 0 && coppia.substring(0, uguale) == nome) return coppia.substring(uguale + 1)
        }
        return null
    }
}
