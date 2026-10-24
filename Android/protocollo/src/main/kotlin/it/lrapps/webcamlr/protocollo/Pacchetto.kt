package it.lrapps.webcamlr.protocollo

/** Un errore del protocollo: la connessione va chiusa. */
class ErroreProtocollo(messaggio: String) : Exception(messaggio)

enum class TipoPacchetto(val valore: Int) {
    CONTROLLO(1),
    VIDEO(2),
    AUDIO(3);

    companion object {
        fun da(valore: Int): TipoPacchetto? = entries.firstOrNull { it.valore == valore }
    }
}

/** Un pacchetto: 6 byte di intestazione (tipo, flag, lunghezza big-endian) e il contenuto. */
class Pacchetto(val tipo: TipoPacchetto, val flag: Int = 0, val contenuto: ByteArray) {

    fun codificato(): ByteArray {
        val dati = ByteArray(LUNGHEZZA_INTESTAZIONE + contenuto.size)
        dati[0] = tipo.valore.toByte()
        dati[1] = flag.toByte()
        scriviIntero32(contenuto.size.toLong(), dati, 2)
        System.arraycopy(contenuto, 0, dati, LUNGHEZZA_INTESTAZIONE, contenuto.size)
        return dati
    }

    override fun equals(other: Any?): Boolean =
        other is Pacchetto && other.tipo == tipo && other.flag == flag && other.contenuto.contentEquals(contenuto)

    override fun hashCode(): Int = (tipo.hashCode() * 31 + flag) * 31 + contenuto.contentHashCode()

    override fun toString(): String = "Pacchetto($tipo, flag=$flag, ${contenuto.size} byte)"

    companion object {
        const val LUNGHEZZA_INTESTAZIONE = 6
        const val LUNGHEZZA_MASSIMA = 16 * 1024 * 1024

        internal fun scriviIntero32(valore: Long, dati: ByteArray, da: Int) {
            for (i in 0 until 4) dati[da + i] = (valore ushr (8 * (3 - i))).toByte()
        }

        internal fun intero64(valore: ULong): ByteArray =
            ByteArray(8) { i -> (valore shr (8 * (7 - i))).toByte() }

        internal fun leggiIntero64(dati: ByteArray, da: Int): ULong {
            var valore = 0uL
            for (i in 0 until 8) valore = (valore shl 8) or (dati[da + i].toULong() and 0xFFu)
            return valore
        }
    }
}

/** Raccoglie i byte che arrivano dalla connessione e restituisce i pacchetti completi. */
class LettorePacchetti {
    private var buffer = ByteArray(64 * 1024)
    private var inizio = 0
    private var fine = 0

    fun aggiungi(dati: ByteArray, da: Int = 0, quanti: Int = dati.size) {
        if (quanti == 0) return
        if (fine + quanti > buffer.size) {
            val presenti = fine - inizio
            if (presenti + quanti > buffer.size) {
                var capienza = buffer.size
                while (capienza < presenti + quanti) capienza *= 2
                val nuovo = ByteArray(capienza)
                System.arraycopy(buffer, inizio, nuovo, 0, presenti)
                buffer = nuovo
            } else {
                System.arraycopy(buffer, inizio, buffer, 0, presenti)
            }
            inizio = 0
            fine = presenti
        }
        System.arraycopy(dati, da, buffer, fine, quanti)
        fine += quanti
    }

    /** Il prossimo pacchetto completo, oppure `null` se servono altri byte. */
    fun prossimo(): Pacchetto? {
        val presenti = fine - inizio
        if (presenti < Pacchetto.LUNGHEZZA_INTESTAZIONE) return null
        val tipoGrezzo = buffer[inizio].toInt() and 0xFF
        val flag = buffer[inizio + 1].toInt() and 0xFF
        var lunghezza = 0L
        for (i in 2 until 6) lunghezza = (lunghezza shl 8) or (buffer[inizio + i].toLong() and 0xFF)

        val tipo = TipoPacchetto.da(tipoGrezzo) ?: throw ErroreProtocollo("Tipo di pacchetto sconosciuto: $tipoGrezzo")
        if (lunghezza > Pacchetto.LUNGHEZZA_MASSIMA) throw ErroreProtocollo("Pacchetto troppo grande: $lunghezza byte")
        if (presenti < Pacchetto.LUNGHEZZA_INTESTAZIONE + lunghezza) return null

        val da = inizio + Pacchetto.LUNGHEZZA_INTESTAZIONE
        val contenuto = buffer.copyOfRange(da, da + lunghezza.toInt())
        inizio = da + lunghezza.toInt()
        if (inizio == fine) {
            inizio = 0
            fine = 0
        }
        return Pacchetto(tipo, flag, contenuto)
    }
}

/** Un fotogramma video compresso (Annex B) con il suo timestamp in microsecondi. */
class FotogrammaVideo(
    val timestamp: ULong,
    val chiave: Boolean,
    val conParametri: Boolean,
    val dati: ByteArray,
) {
    val pacchetto: Pacchetto
        get() {
            var flag = 0
            if (chiave) flag = flag or FLAG_CHIAVE
            if (conParametri) flag = flag or FLAG_PARAMETRI
            return Pacchetto(TipoPacchetto.VIDEO, flag, Pacchetto.intero64(timestamp) + dati)
        }

    override fun equals(other: Any?): Boolean =
        other is FotogrammaVideo && other.timestamp == timestamp && other.chiave == chiave &&
            other.conParametri == conParametri && other.dati.contentEquals(dati)

    override fun hashCode(): Int = timestamp.hashCode() * 31 + dati.contentHashCode()

    companion object {
        const val FLAG_CHIAVE = 1 shl 0
        const val FLAG_PARAMETRI = 1 shl 1

        fun da(pacchetto: Pacchetto): FotogrammaVideo {
            if (pacchetto.tipo != TipoPacchetto.VIDEO || pacchetto.contenuto.size < 8) {
                throw ErroreProtocollo("Pacchetto video non valido")
            }
            return FotogrammaVideo(
                timestamp = Pacchetto.leggiIntero64(pacchetto.contenuto, 0),
                chiave = pacchetto.flag and FLAG_CHIAVE != 0,
                conParametri = pacchetto.flag and FLAG_PARAMETRI != 0,
                dati = pacchetto.contenuto.copyOfRange(8, pacchetto.contenuto.size),
            )
        }
    }
}

/**
 * Un pacchetto audio AAC-LC grezzo (senza ADTS), con il timestamp del primo campione in microsecondi,
 * sullo stesso orologio del video. La configurazione viaggia nel messaggio `formato-audio`.
 */
class PacchettoAudio(val timestamp: ULong, val dati: ByteArray) {
    val pacchetto: Pacchetto
        get() = Pacchetto(TipoPacchetto.AUDIO, 0, Pacchetto.intero64(timestamp) + dati)

    override fun equals(other: Any?): Boolean =
        other is PacchettoAudio && other.timestamp == timestamp && other.dati.contentEquals(dati)

    override fun hashCode(): Int = timestamp.hashCode() * 31 + dati.contentHashCode()

    companion object {
        fun da(pacchetto: Pacchetto): PacchettoAudio {
            if (pacchetto.tipo != TipoPacchetto.AUDIO || pacchetto.contenuto.size < 8) {
                throw ErroreProtocollo("Pacchetto audio non valido")
            }
            return PacchettoAudio(
                timestamp = Pacchetto.leggiIntero64(pacchetto.contenuto, 0),
                dati = pacchetto.contenuto.copyOfRange(8, pacchetto.contenuto.size),
            )
        }
    }
}
