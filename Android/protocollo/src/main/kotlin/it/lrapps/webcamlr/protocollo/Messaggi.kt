package it.lrapps.webcamlr.protocollo

enum class Piattaforma(val valore: String) {
    IPHONE("iphone"), ANDROID("android"), MAC("mac"), WINDOWS("windows");

    companion object {
        fun da(valore: String): Piattaforma =
            entries.firstOrNull { it.valore == valore } ?: throw ErroreProtocollo("Piattaforma sconosciuta: $valore")
    }
}

enum class Codec(val valore: String) {
    H264("h264"), HEVC("hevc");

    companion object {
        fun da(valore: String): Codec =
            entries.firstOrNull { it.valore == valore } ?: throw ErroreProtocollo("Codec sconosciuto: $valore")
    }
}

/** Gli stessi livelli dello stato termico di iOS (su Android: PowerManager.getCurrentThermalStatus). */
enum class Temperatura(val valore: String) {
    NORMALE("normale"), CALDA("calda"), MOLTO_CALDA("molto-calda"), CRITICA("critica");

    companion object {
        fun da(valore: String): Temperatura =
            entries.firstOrNull { it.valore == valore } ?: throw ErroreProtocollo("Temperatura sconosciuta: $valore")
    }
}

/** Un messaggio di controllo: JSON con il campo `tipo` più i campi del messaggio. */
sealed interface Messaggio {
    val tipo: String
}

data class Ciao(
    val versione: Int = Servizio.VERSIONE_PROTOCOLLO,
    val nome: String,
    val piattaforma: Piattaforma,
    val versioneApp: String,
) : Messaggio {
    override val tipo get() = "ciao"
}

data class Benvenuto(
    val versione: Int = Servizio.VERSIONE_PROTOCOLLO,
    val nome: String,
    val piattaforma: Piattaforma,
) : Messaggio {
    override val tipo get() = "benvenuto"
}

data class FormatoVideo(val codec: Codec, val larghezza: Int, val altezza: Int, val fps: Int) : Messaggio {
    override val tipo get() = "formato"
}

/** `batteria` da 0 a 100, oppure -1 se non nota. */
data class StatoTelefono(
    val batteria: Int,
    val inCarica: Boolean,
    val temperatura: Temperatura,
    val obiettivo: String,
) : Messaggio {
    override val tipo get() = "stato"
}

/** `t`: orologio del computer, in microsecondi. */
data class Ping(val t: ULong) : Messaggio {
    override val tipo get() = "ping"
}

/** `t` copiato dal `ping`; `telefono`: orologio del telefono, in microsecondi. */
data class Pong(val t: ULong, val telefono: ULong) : Messaggio {
    override val tipo get() = "pong"
}

/** Latenza misurata dal computer, in millisecondi. */
data class Latenza(val ms: Int) : Messaggio {
    override val tipo get() = "latenza"
}

/** Cosa il computer può comandare su questo telefono. */
data class Capacita(
    val obiettivi: List<String>,
    val zoomMassimo: Double,
    val torcia: Boolean,
    val isoMinimo: Double? = null,
    val isoMassimo: Double? = null,
) : Messaggio {
    override val tipo get() = "capacita"
}

/** Comandi della fotocamera dal computer: si applicano solo i campi presenti. */
data class Comando(
    val obiettivo: String? = null,
    val zoom: Double? = null,
    val torcia: Boolean? = null,
    /** Compensazione dell'esposizione in stop, da -2 a +2. */
    val esposizione: Double? = null,
    /** Kelvin da 2500 a 7500; 0 = automatico. */
    val bianco: Int? = null,
    /** Per ora solo "continuo". */
    val fuoco: String? = null,
    /** ISO manuale; 0 = automatico. */
    val iso: Double? = null,
    /** Tempo di posa come denominatore (60 = 1/60 s); 0 = automatico. */
    val tempo: Int? = null,
) : Messaggio {
    override val tipo get() = "comando"
}

/** Un'app sta usando davvero la webcam virtuale: l'unico caso in cui si mostra il rosso. */
data class InOnda(val attivo: Boolean, val app: String? = null) : Messaggio {
    override val tipo get() = "in-onda"
}

data object Arrivederci : Messaggio {
    override val tipo get() = "arrivederci"
}

/** Stretta di mano del collegamento sicuro (versione 2), in chiaro: byte in base64. */
data class Stretta(
    val versione: Int,
    /** Chiave pubblica ECDH effimera, 65 byte. */
    val chiave: String,
    /** Chiave pubblica di firma permanente, 65 byte. */
    val identita: String,
    /** Solo dal computer: la sua firma sulla trascrizione. */
    val firma: String? = null,
) : Messaggio {
    override val tipo get() = "stretta"
}

/** Dal telefono, già cifrata: la sua firma sulla trascrizione, e il gettone se viene dal QR code. */
data class Prova(val firma: String, val gettone: String? = null) : Messaggio {
    override val tipo get() = "prova"
}

/** Dal computer: il telefono non è ancora fidato, l'utente deve confermare con questo codice. */
data class Approvazione(val codice: String) : Messaggio {
    override val tipo get() = "approvazione"
}

/** Un tipo che questa versione non conosce: si ignora. */
data class Sconosciuto(override val tipo: String) : Messaggio

/** Da messaggio a JSON e ritorno, con lo stesso testo di Swift (chiavi in ordine alfabetico). */
object CodificaMessaggi {

    fun json(messaggio: Messaggio): String = Json.scrivi(campi(messaggio))

    fun codifica(messaggio: Messaggio): ByteArray = json(messaggio).toByteArray(Charsets.UTF_8)

    fun comePacchetto(messaggio: Messaggio): Pacchetto = Pacchetto(TipoPacchetto.CONTROLLO, 0, codifica(messaggio))

    fun daPacchetto(pacchetto: Pacchetto): Messaggio {
        if (pacchetto.tipo != TipoPacchetto.CONTROLLO) throw ErroreProtocollo("Non è un pacchetto di controllo")
        return decodifica(pacchetto.contenuto)
    }

    private fun campi(messaggio: Messaggio): Map<String, Any?> {
        val campi: Map<String, Any?> = when (messaggio) {
            is Ciao -> mapOf(
                "versione" to messaggio.versione, "nome" to messaggio.nome,
                "piattaforma" to messaggio.piattaforma.valore, "versioneApp" to messaggio.versioneApp,
            )
            is Benvenuto -> mapOf(
                "versione" to messaggio.versione, "nome" to messaggio.nome, "piattaforma" to messaggio.piattaforma.valore,
            )
            is FormatoVideo -> mapOf(
                "codec" to messaggio.codec.valore, "larghezza" to messaggio.larghezza,
                "altezza" to messaggio.altezza, "fps" to messaggio.fps,
            )
            is StatoTelefono -> mapOf(
                "batteria" to messaggio.batteria, "inCarica" to messaggio.inCarica,
                "temperatura" to messaggio.temperatura.valore, "obiettivo" to messaggio.obiettivo,
            )
            is Ping -> mapOf("t" to messaggio.t)
            is Pong -> mapOf("t" to messaggio.t, "telefono" to messaggio.telefono)
            is Latenza -> mapOf("ms" to messaggio.ms)
            is Capacita -> mapOf(
                "obiettivi" to messaggio.obiettivi, "zoomMassimo" to messaggio.zoomMassimo, "torcia" to messaggio.torcia,
                "isoMinimo" to messaggio.isoMinimo, "isoMassimo" to messaggio.isoMassimo,
            )
            is Comando -> mapOf(
                "obiettivo" to messaggio.obiettivo, "zoom" to messaggio.zoom, "torcia" to messaggio.torcia,
                "esposizione" to messaggio.esposizione, "bianco" to messaggio.bianco, "fuoco" to messaggio.fuoco,
                "iso" to messaggio.iso, "tempo" to messaggio.tempo,
            )
            is InOnda -> mapOf("attivo" to messaggio.attivo, "app" to messaggio.app)
            is Stretta -> mapOf(
                "versione" to messaggio.versione, "chiave" to messaggio.chiave,
                "identita" to messaggio.identita, "firma" to messaggio.firma,
            )
            is Prova -> mapOf("firma" to messaggio.firma, "gettone" to messaggio.gettone)
            is Approvazione -> mapOf("codice" to messaggio.codice)
            Arrivederci, is Sconosciuto -> emptyMap()
        }
        return campi + ("tipo" to messaggio.tipo)
    }

    fun decodifica(json: ByteArray): Messaggio {
        val testo = json.toString(Charsets.UTF_8)
        @Suppress("UNCHECKED_CAST")
        val nodo = Json.leggi(testo) as? Map<String, Any?> ?: throw ErroreProtocollo("Il messaggio non è un oggetto JSON")
        val campi = Campi(nodo)
        return when (val tipo = campi.testo("tipo")) {
            "ciao" -> Ciao(
                campi.intero("versione"), campi.testo("nome"),
                Piattaforma.da(campi.testo("piattaforma")), campi.testo("versioneApp"),
            )
            "benvenuto" -> Benvenuto(campi.intero("versione"), campi.testo("nome"), Piattaforma.da(campi.testo("piattaforma")))
            "formato" -> FormatoVideo(
                Codec.da(campi.testo("codec")), campi.intero("larghezza"), campi.intero("altezza"), campi.intero("fps"),
            )
            "stato" -> StatoTelefono(
                campi.intero("batteria"), campi.booleano("inCarica"),
                Temperatura.da(campi.testo("temperatura")), campi.testo("obiettivo"),
            )
            "ping" -> Ping(campi.naturale("t"))
            "pong" -> Pong(campi.naturale("t"), campi.naturale("telefono"))
            "latenza" -> Latenza(campi.intero("ms"))
            "capacita" -> Capacita(
                campi.listaTesti("obiettivi"), campi.decimale("zoomMassimo"), campi.booleano("torcia"),
                campi.decimaleOpzionale("isoMinimo"), campi.decimaleOpzionale("isoMassimo"),
            )
            "comando" -> Comando(
                obiettivo = campi.testoOpzionale("obiettivo"),
                zoom = campi.decimaleOpzionale("zoom"),
                torcia = campi.booleanoOpzionale("torcia"),
                esposizione = campi.decimaleOpzionale("esposizione"),
                bianco = campi.interoOpzionale("bianco"),
                fuoco = campi.testoOpzionale("fuoco"),
                iso = campi.decimaleOpzionale("iso"),
                tempo = campi.interoOpzionale("tempo"),
            )
            "in-onda" -> InOnda(campi.booleano("attivo"), campi.testoOpzionale("app"))
            "arrivederci" -> Arrivederci
            "stretta" -> Stretta(
                campi.intero("versione"), campi.testo("chiave"), campi.testo("identita"), campi.testoOpzionale("firma"),
            )
            "prova" -> Prova(campi.testo("firma"), campi.testoOpzionale("gettone"))
            "approvazione" -> Approvazione(campi.testo("codice"))
            else -> Sconosciuto(tipo)
        }
    }

    /** Lettura dei campi con i controlli di tipo: un campo obbligatorio mancante è un errore, come in Swift. */
    private class Campi(private val nodo: Map<String, Any?>) {
        private fun obbligatorio(nome: String): Any = nodo[nome] ?: throw ErroreProtocollo("Manca il campo $nome")

        fun testo(nome: String): String = obbligatorio(nome) as? String ?: throw ErroreProtocollo("$nome non è un testo")
        fun testoOpzionale(nome: String): String? = nodo[nome]?.let { testo(nome) }

        fun booleano(nome: String): Boolean = obbligatorio(nome) as? Boolean ?: throw ErroreProtocollo("$nome non è vero/falso")
        fun booleanoOpzionale(nome: String): Boolean? = nodo[nome]?.let { booleano(nome) }

        private fun numero(nome: String): Json.Numero =
            obbligatorio(nome) as? Json.Numero ?: throw ErroreProtocollo("$nome non è un numero")

        fun intero(nome: String): Int = numero(nome).comeInt()
        fun interoOpzionale(nome: String): Int? = nodo[nome]?.let { intero(nome) }
        fun naturale(nome: String): ULong = numero(nome).comeULong()
        fun decimale(nome: String): Double = numero(nome).comeDouble()
        fun decimaleOpzionale(nome: String): Double? = nodo[nome]?.let { decimale(nome) }

        fun listaTesti(nome: String): List<String> {
            val lista = obbligatorio(nome) as? List<*> ?: throw ErroreProtocollo("$nome non è un elenco")
            return lista.map { it as? String ?: throw ErroreProtocollo("$nome contiene un valore non testuale") }
        }
    }
}
