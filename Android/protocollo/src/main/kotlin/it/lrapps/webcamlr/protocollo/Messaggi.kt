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

/**
 * `batteria` da 0 a 100, oppure -1 se non nota. Gli effetti (facoltativi) sono quelli attuali,
 * anche se cambiati sul telefono: il computer li mostra.
 */
data class StatoTelefono(
    val batteria: Int,
    val inCarica: Boolean,
    val temperatura: Temperatura,
    val obiettivo: String,
    val filtro: String? = null,
    val regolazioni: Regolazioni? = null,
    val sfondo: String? = null,
    val intensitaSfondo: Double? = null,
    val pelle: Double? = null,
    val inquadratura: Boolean? = null,
    val luceVolto: Boolean? = null,
    /** Nome vuoto = nessuna scritta. */
    val scritta: Scritta? = null,
    val doppiaVista: Boolean? = null,
    val postura: Boolean? = null,
    /** Il microfono sta inviando audio. */
    val audio: Boolean? = null,
    /** Perché il telefono non manda video ([MotiviPausa]); null = non è in pausa. */
    val pausa: String? = null,
    val gobbo: StatoGobbo? = null,
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
    /** Filtri disponibili ([Filtri]), nell'ordine in cui mostrarli. */
    val filtri: List<String>? = null,
    /** Sfondo sfocato o sostituito. */
    val sfondo: Boolean? = null,
    val pelle: Boolean? = null,
    val inquadratura: Boolean? = null,
    val luceVolto: Boolean? = null,
    val scritta: Boolean? = null,
    /** Volto e scrivania con due obiettivi insieme (serve la multicamera). */
    val doppiaVista: Boolean? = null,
    val postura: Boolean? = null,
    val gobbo: Boolean? = null,
    /** Microfono disponibile. */
    val audio: Boolean? = null,
    /** Risoluzioni dell'obiettivo attuale con i fotogrammi al secondo massimi. */
    val formati: List<FormatoSupportato>? = null,
) : Messaggio {
    override val tipo get() = "capacita"
}

/** Comandi della fotocamera e degli effetti dal computer: si applicano solo i campi presenti. */
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
    /** Uno dei [Filtri]; "naturale" = nessun filtro. */
    val filtro: String? = null,
    val regolazioni: Regolazioni? = null,
    /** Uno dei [ModiSfondo]. */
    val sfondo: String? = null,
    /** Da 0 a 1. */
    val intensitaSfondo: Double? = null,
    /** Ritocco della pelle, da 0 (spento) a 1. */
    val pelle: Double? = null,
    /** Inquadratura automatica che segue il volto. */
    val inquadratura: Boolean? = null,
    /** Esposizione con priorità al volto. */
    val luceVolto: Boolean? = null,
    /** Sottopancia; nome vuoto = togli la scritta. */
    val scritta: Scritta? = null,
    val doppiaVista: Boolean? = null,
    /** Promemoria della postura sul telefono. */
    val postura: Boolean? = null,
    /** Microfono acceso o spento. */
    val audio: Boolean? = null,
) : Messaggio {
    override val tipo get() = "comando"
}

/** Un'app sta usando davvero la webcam virtuale: l'unico caso in cui si mostra il rosso. */
data class InOnda(val attivo: Boolean, val app: String? = null) : Messaggio {
    override val tipo get() = "in-onda"
}

/** La finestra di anteprima del computer è visibile: qualcuno sta guardando. */
data class Anteprima(val visibile: Boolean) : Messaggio {
    override val tipo get() = "anteprima"
}

/** Il gobbo: testo che scorre sullo schermo del telefono. Si applicano solo i campi presenti. */
data class Gobbo(
    /** Al massimo [LUNGHEZZA_MASSIMA] caratteri; il telefono taglia il resto. */
    val testo: String? = null,
    /** Righe al secondo, da 0.5 a 3. */
    val velocita: Double? = null,
    val attivo: Boolean? = null,
    /** Una delle [DimensioniGobbo]. */
    val dimensione: String? = null,
    /** Da 0 (inizio) a 1 (fine): salta a quel punto. */
    val posizione: Double? = null,
) : Messaggio {
    override val tipo get() = "gobbo"

    companion object {
        const val LUNGHEZZA_MASSIMA = 20_000
        const val VELOCITA_MINIMA = 0.5
        const val VELOCITA_MASSIMA = 3.0
    }
}

/** Dal telefono: com'è codificato l'audio dei pacchetti di tipo 3. `configurazione`: AudioSpecificConfig in base64. */
data class FormatoAudio(
    val codec: String = AAC_LC,
    /** Campioni al secondo (48000). */
    val frequenza: Int = 48_000,
    val canali: Int = 1,
    val configurazione: String = java.util.Base64.getEncoder().encodeToString(CONFIGURAZIONE_AAC_48K_MONO),
) : Messaggio {
    override val tipo get() = "formato-audio"

    companion object {
        const val AAC_LC = "aac-lc"

        /** Campioni in ogni pacchetto AAC-LC (21,33 ms a 48 kHz). */
        const val CAMPIONI_PER_PACCHETTO = 1024

        /** AudioSpecificConfig di AAC-LC, 48 kHz, mono: 0x11 0x88. */
        val CONFIGURAZIONE_AAC_48K_MONO: ByteArray get() = byteArrayOf(0x11, 0x88.toByte())
    }
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

/** Correzioni dell'immagine, ognuna da -1 a 1 (0 = neutra). */
data class Regolazioni(
    val luminosita: Double? = null,
    val contrasto: Double? = null,
    val saturazione: Double? = null,
    val nitidezza: Double? = null,
)

/** Sottopancia: nome e, se c'è, ruolo. */
data class Scritta(val nome: String, val ruolo: String? = null) {
    companion object {
        /** Da mandare per togliere la scritta. */
        val NESSUNA = Scritta("")
    }
}

/** Dove è arrivato il gobbo sul telefono; `posizione` da 0 a 1. */
data class StatoGobbo(val attivo: Boolean, val posizione: Double)

/** Una risoluzione che il telefono sa inviare, con i fotogrammi al secondo massimi. */
data class FormatoSupportato(val larghezza: Int, val altezza: Int, val fpsMassimo: Int)

/** Filtri del telefono. Un filtro sconosciuto si tratta come "naturale". */
object Filtri {
    const val NATURALE = "naturale"
    const val CALDO = "caldo"
    const val FREDDO = "freddo"
    const val LUMINOSO = "luminoso"
    const val CINEMA = "cinema"
    const val VIVIDO = "vivido"
    const val TENUE = "tenue"
    const val BIANCO_NERO = "bianco-nero"
    const val SEPPIA = "seppia"
    const val NOTTE = "notte"
    val TUTTI = listOf(NATURALE, CALDO, FREDDO, LUMINOSO, CINEMA, VIVIDO, TENUE, BIANCO_NERO, SEPPIA, NOTTE)
}

object ModiSfondo {
    const val NESSUNO = "nessuno"
    const val SFOCATO = "sfocato"
    const val SOSTITUITO = "sostituito"
}

/** Perché il telefono è in pausa. Un motivo sconosciuto si mostra come una pausa qualsiasi. */
object MotiviPausa {
    const val FACCIA_IN_GIU = "faccia-in-giu"
    const val NESSUNA_APP = "nessuna-app"
    const val UTENTE = "utente"
}

object DimensioniGobbo {
    const val PICCOLA = "piccola"
    const val MEDIA = "media"
    const val GRANDE = "grande"
}

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
                "filtro" to messaggio.filtro, "regolazioni" to messaggio.regolazioni?.let(::campi),
                "sfondo" to messaggio.sfondo, "intensitaSfondo" to messaggio.intensitaSfondo,
                "pelle" to messaggio.pelle, "inquadratura" to messaggio.inquadratura,
                "luceVolto" to messaggio.luceVolto, "scritta" to messaggio.scritta?.let(::campi),
                "doppiaVista" to messaggio.doppiaVista, "postura" to messaggio.postura, "audio" to messaggio.audio,
                "pausa" to messaggio.pausa,
                "gobbo" to messaggio.gobbo?.let { mapOf("attivo" to it.attivo, "posizione" to it.posizione) },
            )
            is Ping -> mapOf("t" to messaggio.t)
            is Pong -> mapOf("t" to messaggio.t, "telefono" to messaggio.telefono)
            is Latenza -> mapOf("ms" to messaggio.ms)
            is Capacita -> mapOf(
                "obiettivi" to messaggio.obiettivi, "zoomMassimo" to messaggio.zoomMassimo, "torcia" to messaggio.torcia,
                "isoMinimo" to messaggio.isoMinimo, "isoMassimo" to messaggio.isoMassimo,
                "filtri" to messaggio.filtri, "sfondo" to messaggio.sfondo, "pelle" to messaggio.pelle,
                "inquadratura" to messaggio.inquadratura, "luceVolto" to messaggio.luceVolto,
                "scritta" to messaggio.scritta, "doppiaVista" to messaggio.doppiaVista, "postura" to messaggio.postura,
                "gobbo" to messaggio.gobbo, "audio" to messaggio.audio,
                "formati" to messaggio.formati?.map {
                    mapOf("larghezza" to it.larghezza, "altezza" to it.altezza, "fpsMassimo" to it.fpsMassimo)
                },
            )
            is Comando -> mapOf(
                "obiettivo" to messaggio.obiettivo, "zoom" to messaggio.zoom, "torcia" to messaggio.torcia,
                "esposizione" to messaggio.esposizione, "bianco" to messaggio.bianco, "fuoco" to messaggio.fuoco,
                "iso" to messaggio.iso, "tempo" to messaggio.tempo,
                "filtro" to messaggio.filtro, "regolazioni" to messaggio.regolazioni?.let(::campi),
                "sfondo" to messaggio.sfondo, "intensitaSfondo" to messaggio.intensitaSfondo,
                "pelle" to messaggio.pelle, "inquadratura" to messaggio.inquadratura,
                "luceVolto" to messaggio.luceVolto, "scritta" to messaggio.scritta?.let(::campi),
                "doppiaVista" to messaggio.doppiaVista, "postura" to messaggio.postura, "audio" to messaggio.audio,
            )
            is InOnda -> mapOf("attivo" to messaggio.attivo, "app" to messaggio.app)
            is Anteprima -> mapOf("visibile" to messaggio.visibile)
            is Gobbo -> mapOf(
                "testo" to messaggio.testo, "velocita" to messaggio.velocita, "attivo" to messaggio.attivo,
                "dimensione" to messaggio.dimensione, "posizione" to messaggio.posizione,
            )
            is FormatoAudio -> mapOf(
                "codec" to messaggio.codec, "frequenza" to messaggio.frequenza,
                "canali" to messaggio.canali, "configurazione" to messaggio.configurazione,
            )
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

    private fun campi(regolazioni: Regolazioni): Map<String, Any?> = mapOf(
        "luminosita" to regolazioni.luminosita, "contrasto" to regolazioni.contrasto,
        "saturazione" to regolazioni.saturazione, "nitidezza" to regolazioni.nitidezza,
    )

    private fun campi(scritta: Scritta): Map<String, Any?> = mapOf("nome" to scritta.nome, "ruolo" to scritta.ruolo)

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
                filtro = campi.testoOpzionale("filtro"),
                regolazioni = campi.oggettoOpzionale("regolazioni")?.let(::regolazioni),
                sfondo = campi.testoOpzionale("sfondo"),
                intensitaSfondo = campi.decimaleOpzionale("intensitaSfondo"),
                pelle = campi.decimaleOpzionale("pelle"),
                inquadratura = campi.booleanoOpzionale("inquadratura"),
                luceVolto = campi.booleanoOpzionale("luceVolto"),
                scritta = campi.oggettoOpzionale("scritta")?.let(::scritta),
                doppiaVista = campi.booleanoOpzionale("doppiaVista"),
                postura = campi.booleanoOpzionale("postura"),
                audio = campi.booleanoOpzionale("audio"),
                pausa = campi.testoOpzionale("pausa"),
                gobbo = campi.oggettoOpzionale("gobbo")?.let { StatoGobbo(it.booleano("attivo"), it.decimale("posizione")) },
            )
            "ping" -> Ping(campi.naturale("t"))
            "pong" -> Pong(campi.naturale("t"), campi.naturale("telefono"))
            "latenza" -> Latenza(campi.intero("ms"))
            "capacita" -> Capacita(
                campi.listaTesti("obiettivi"), campi.decimale("zoomMassimo"), campi.booleano("torcia"),
                campi.decimaleOpzionale("isoMinimo"), campi.decimaleOpzionale("isoMassimo"),
                filtri = campi.listaTestiOpzionale("filtri"),
                sfondo = campi.booleanoOpzionale("sfondo"),
                pelle = campi.booleanoOpzionale("pelle"),
                inquadratura = campi.booleanoOpzionale("inquadratura"),
                luceVolto = campi.booleanoOpzionale("luceVolto"),
                scritta = campi.booleanoOpzionale("scritta"),
                doppiaVista = campi.booleanoOpzionale("doppiaVista"),
                postura = campi.booleanoOpzionale("postura"),
                gobbo = campi.booleanoOpzionale("gobbo"),
                audio = campi.booleanoOpzionale("audio"),
                formati = campi.listaOggettiOpzionale("formati")?.map {
                    FormatoSupportato(it.intero("larghezza"), it.intero("altezza"), it.intero("fpsMassimo"))
                },
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
                filtro = campi.testoOpzionale("filtro"),
                regolazioni = campi.oggettoOpzionale("regolazioni")?.let(::regolazioni),
                sfondo = campi.testoOpzionale("sfondo"),
                intensitaSfondo = campi.decimaleOpzionale("intensitaSfondo"),
                pelle = campi.decimaleOpzionale("pelle"),
                inquadratura = campi.booleanoOpzionale("inquadratura"),
                luceVolto = campi.booleanoOpzionale("luceVolto"),
                scritta = campi.oggettoOpzionale("scritta")?.let(::scritta),
                doppiaVista = campi.booleanoOpzionale("doppiaVista"),
                postura = campi.booleanoOpzionale("postura"),
                audio = campi.booleanoOpzionale("audio"),
            )
            "in-onda" -> InOnda(campi.booleano("attivo"), campi.testoOpzionale("app"))
            "anteprima" -> Anteprima(campi.booleano("visibile"))
            "gobbo" -> Gobbo(
                testo = campi.testoOpzionale("testo"),
                velocita = campi.decimaleOpzionale("velocita"),
                attivo = campi.booleanoOpzionale("attivo"),
                dimensione = campi.testoOpzionale("dimensione"),
                posizione = campi.decimaleOpzionale("posizione"),
            )
            "formato-audio" -> FormatoAudio(
                campi.testo("codec"), campi.intero("frequenza"), campi.intero("canali"), campi.testo("configurazione"),
            )
            "arrivederci" -> Arrivederci
            "stretta" -> Stretta(
                campi.intero("versione"), campi.testo("chiave"), campi.testo("identita"), campi.testoOpzionale("firma"),
            )
            "prova" -> Prova(campi.testo("firma"), campi.testoOpzionale("gettone"))
            "approvazione" -> Approvazione(campi.testo("codice"))
            else -> Sconosciuto(tipo)
        }
    }

    private fun regolazioni(campi: Campi) = Regolazioni(
        luminosita = campi.decimaleOpzionale("luminosita"),
        contrasto = campi.decimaleOpzionale("contrasto"),
        saturazione = campi.decimaleOpzionale("saturazione"),
        nitidezza = campi.decimaleOpzionale("nitidezza"),
    )

    private fun scritta(campi: Campi) = Scritta(campi.testo("nome"), campi.testoOpzionale("ruolo"))

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
        fun listaTestiOpzionale(nome: String): List<String>? = nodo[nome]?.let { listaTesti(nome) }

        @Suppress("UNCHECKED_CAST")
        private fun comeOggetto(valore: Any?, nome: String): Campi =
            Campi(valore as? Map<String, Any?> ?: throw ErroreProtocollo("$nome non è un oggetto"))

        fun oggettoOpzionale(nome: String): Campi? = nodo[nome]?.let { comeOggetto(it, nome) }

        fun listaOggettiOpzionale(nome: String): List<Campi>? = nodo[nome]?.let { valore ->
            val lista = valore as? List<*> ?: throw ErroreProtocollo("$nome non è un elenco")
            lista.map { comeOggetto(it, nome) }
        }
    }
}
