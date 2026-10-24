package it.lrapps.webcamlr.protocollo

/**
 * JSON minimo, scritto a mano per avere lo stesso testo dell'implementazione Swift
 * (`JSONEncoder` con `.sortedKeys` e `.withoutEscapingSlashes`): chiavi in ordine alfabetico,
 * nessuno spazio, numeri interi senza «.0», «/» non protetta, caratteri non ASCII scritti così come sono.
 */
internal object Json {

    /** Un numero letto dal JSON, tenuto come testo: si converte solo quando si sa che tipo serve. */
    class Numero(val testo: String) {
        fun comeDouble(): Double = testo.toDoubleOrNull() ?: throw ErroreProtocollo("Numero non valido: $testo")

        fun comeLong(): Long = testo.toLongOrNull()
            ?: comeDouble().let { if (it == Math.floor(it) && Math.abs(it) < 9.0e15) it.toLong() else null }
            ?: throw ErroreProtocollo("Intero non valido: $testo")

        fun comeInt(): Int {
            val valore = comeLong()
            if (valore < Int.MIN_VALUE || valore > Int.MAX_VALUE) throw ErroreProtocollo("Intero troppo grande: $testo")
            return valore.toInt()
        }

        fun comeULong(): ULong = testo.toULongOrNull() ?: comeLong().also {
            if (it < 0) throw ErroreProtocollo("Intero negativo: $testo")
        }.toULong()

        override fun equals(other: Any?) = other is Numero && other.testo == testo
        override fun hashCode() = testo.hashCode()
        override fun toString() = testo
    }

    // MARK: scrittura

    fun scrivi(valore: Any?): String = StringBuilder().also { scrivi(valore, it) }.toString()

    private fun scrivi(valore: Any?, uscita: StringBuilder) {
        when (valore) {
            null -> uscita.append("null")
            is String -> scriviTesto(valore, uscita)
            is Boolean -> uscita.append(if (valore) "true" else "false")
            is Int, is Long, is Short, is Byte -> uscita.append(valore.toString())
            is UInt, is ULong -> uscita.append(valore.toString())
            is Double -> uscita.append(numero(valore))
            is Float -> uscita.append(numero(valore.toDouble()))
            is Numero -> uscita.append(valore.testo)
            is Map<*, *> -> {
                uscita.append('{')
                // Come `.sortedKeys` di Swift: ordine dei caratteri, i campi a null non si scrivono.
                val chiavi = valore.keys.map { it as String }.filter { valore[it] != null }.sorted()
                chiavi.forEachIndexed { indice, chiave ->
                    if (indice > 0) uscita.append(',')
                    scriviTesto(chiave, uscita)
                    uscita.append(':')
                    scrivi(valore[chiave], uscita)
                }
                uscita.append('}')
            }
            is List<*> -> {
                uscita.append('[')
                valore.forEachIndexed { indice, elemento ->
                    if (indice > 0) uscita.append(',')
                    scrivi(elemento, uscita)
                }
                uscita.append(']')
            }
            else -> throw IllegalArgumentException("Valore JSON non previsto: ${valore::class}")
        }
    }

    /** 5.0 → «5», 0.3 → «0.3», come Swift e .NET. */
    internal fun numero(valore: Double): String {
        if (valore.isNaN() || valore.isInfinite()) throw IllegalArgumentException("Numero non rappresentabile in JSON")
        if (valore == Math.rint(valore) && Math.abs(valore) < 1e15) {
            val intero = valore.toLong()
            return if (intero == 0L && 1.0 / valore < 0) "-0" else intero.toString()
        }
        return valore.toString()
    }

    private fun scriviTesto(testo: String, uscita: StringBuilder) {
        uscita.append('"')
        for (carattere in testo) {
            when (carattere) {
                '"' -> uscita.append("\\\"")
                '\\' -> uscita.append("\\\\")
                '\n' -> uscita.append("\\n")
                '\r' -> uscita.append("\\r")
                '\t' -> uscita.append("\\t")
                '\b' -> uscita.append("\\b")
                '\u000C' -> uscita.append("\\f")
                else -> if (carattere < ' ') {
                    uscita.append("\\u").append(String.format("%04x", carattere.code))
                } else {
                    uscita.append(carattere)
                }
            }
        }
        uscita.append('"')
    }

    // MARK: lettura

    /** Oggetti → Map, liste → List, numeri → [Numero], poi String, Boolean e null. */
    fun leggi(testo: String): Any? {
        val lettore = Lettore(testo)
        lettore.spazi()
        val valore = lettore.valore(0)
        lettore.spazi()
        if (!lettore.finito) throw ErroreProtocollo("JSON non valido: testo dopo la fine")
        return valore
    }

    private class Lettore(private val testo: String) {
        private var posizione = 0
        val finito get() = posizione >= testo.length

        fun spazi() {
            while (posizione < testo.length && testo[posizione] in " \t\n\r") posizione++
        }

        private fun errore(): Nothing = throw ErroreProtocollo("JSON non valido alla posizione $posizione")

        private fun prossimo(): Char = if (posizione < testo.length) testo[posizione++] else errore()

        fun valore(profondita: Int): Any? {
            if (profondita > 32) errore()
            if (finito) errore()
            return when (val carattere = testo[posizione]) {
                '{' -> oggetto(profondita)
                '[' -> lista(profondita)
                '"' -> testo()
                't' -> parola("true", true)
                'f' -> parola("false", false)
                'n' -> parola("null", null)
                else -> if (carattere == '-' || carattere in '0'..'9') numero() else errore()
            }
        }

        private fun parola(attesa: String, valore: Any?): Any? {
            if (!testo.startsWith(attesa, posizione)) errore()
            posizione += attesa.length
            return valore
        }

        private fun oggetto(profondita: Int): Map<String, Any?> {
            posizione++
            val risultato = LinkedHashMap<String, Any?>()
            spazi()
            if (!finito && testo[posizione] == '}') {
                posizione++
                return risultato
            }
            while (true) {
                spazi()
                if (finito || testo[posizione] != '"') errore()
                val chiave = testo()
                spazi()
                if (prossimo() != ':') errore()
                spazi()
                val valore = valore(profondita + 1)
                // Come Swift e .NET: con chiavi ripetute vale la prima.
                if (!risultato.containsKey(chiave)) risultato[chiave] = valore
                spazi()
                when (prossimo()) {
                    ',' -> continue
                    '}' -> return risultato
                    else -> errore()
                }
            }
        }

        private fun lista(profondita: Int): List<Any?> {
            posizione++
            val risultato = ArrayList<Any?>()
            spazi()
            if (!finito && testo[posizione] == ']') {
                posizione++
                return risultato
            }
            while (true) {
                spazi()
                risultato.add(valore(profondita + 1))
                spazi()
                when (prossimo()) {
                    ',' -> continue
                    ']' -> return risultato
                    else -> errore()
                }
            }
        }

        private fun testo(): String {
            posizione++ // virgolette di apertura
            val risultato = StringBuilder()
            while (true) {
                val carattere = prossimo()
                when {
                    carattere == '"' -> return risultato.toString()
                    carattere == '\\' -> when (prossimo()) {
                        '"' -> risultato.append('"')
                        '\\' -> risultato.append('\\')
                        '/' -> risultato.append('/')
                        'b' -> risultato.append('\b')
                        'f' -> risultato.append('\u000C')
                        'n' -> risultato.append('\n')
                        'r' -> risultato.append('\r')
                        't' -> risultato.append('\t')
                        'u' -> {
                            if (posizione + 4 > testo.length) errore()
                            val codice = testo.substring(posizione, posizione + 4).toIntOrNull(16) ?: errore()
                            posizione += 4
                            risultato.append(codice.toChar())
                        }
                        else -> errore()
                    }
                    carattere < ' ' -> errore()
                    else -> risultato.append(carattere)
                }
            }
        }

        private fun numero(): Numero {
            val inizio = posizione
            if (testo[posizione] == '-') posizione++
            var cifre = 0
            while (posizione < testo.length && testo[posizione] in "0123456789.eE+-") {
                posizione++
                cifre++
            }
            if (cifre == 0) errore()
            val numero = testo.substring(inizio, posizione)
            if (numero.toDoubleOrNull() == null) errore()
            return Numero(numero)
        }
    }
}
