package it.lrapps.webcamlr.protocollo

/**
 * Qualità del collegamento in parole, uguale su iPhone, Mac e Windows (Stile/Sources/Stile/Qualita.swift).
 * Sotto i 100 ms la latenza è buona per una chiamata; anche con poca latenza, se si salta è debole.
 */
enum class QualitaCollegamento(val testo: String, val tacche: Int) {
    OTTIMA("Ottimo", 3),
    BUONA("Buono", 2),
    DEBOLE("Debole", 1);

    companion object {
        /** `perdite`: fotogrammi saltati negli ultimi secondi. */
        fun da(latenzaMs: Int, perdite: Int = 0): QualitaCollegamento = when {
            latenzaMs >= 150 || perdite >= 10 -> DEBOLE
            latenzaMs >= 80 || perdite > 0 -> BUONA
            else -> OTTIMA
        }
    }
}

/**
 * La qualità che segue la rete (come Codificatore.swift): se si scarta o la rete è satura il bitrate scende
 * del 30%; dopo 3 secondi puliti risale del 10% della qualità scelta, fino a quella.
 * Mai sotto un quinto della qualità scelta, né sotto 500 kbit/s.
 *
 * Qualità a scelta ([livello], Protocollo.md): con Alta e Massima la discesa si ferma alla soglia di [NumeriQualita]
 * (il bitrate di Auto) e va sotto solo se la rete non regge nemmeno quella per [SECONDI_ALLA_SOGLIA] secondi di fila.
 */
class AdattamentoRete {
    var fattore = 1.0
        private set
    private var secondiPuliti = 0
    /** Secondi di fila con scarti o rete satura mentre si è già alla soglia (o sotto). */
    private var secondiAllaSoglia = 0

    /** Uno dei [LivelliQualita]; uno sconosciuto vale "auto". Non cambia [fattore]: vale dal prossimo secondo. */
    var livello: String = LivelliQualita.AUTO
        set(valore) {
            field = LivelliQualita.normalizza(valore)
        }

    fun azzera() {
        fattore = 1.0
        secondiPuliti = 0
        secondiAllaSoglia = 0
    }

    /** Una volta al secondo. Ritorna `true` se la rete è debole (bitrate ben sotto quello di Auto). */
    fun secondo(scartati: Int, saturo: Boolean): Boolean {
        val soglia = NumeriQualita.soglia(livello)
        if (scartati > 0 || saturo) {
            secondiPuliti = 0
            val giu = fattore * 0.7
            when {
                giu >= soglia -> fattore = giu
                fattore > soglia -> fattore = soglia
                else -> {
                    // Già alla soglia: si scende ancora solo se la rete non la regge per qualche secondo di fila.
                    secondiAllaSoglia++
                    if (secondiAllaSoglia >= SECONDI_ALLA_SOGLIA) fattore = maxOf(giu, FATTORE_MINIMO)
                }
            }
        } else {
            secondiAllaSoglia = 0
            if (fattore < 1) {
                secondiPuliti++
                if (secondiPuliti >= 3) {
                    fattore = minOf(fattore + 0.1, 1.0)
                    secondiPuliti = 0
                }
            }
        }
        return fattore * NumeriQualita.moltiplicatore(livello) < 0.6
    }

    /** Il bitrate da usare ora, partendo da quello della qualità scelta. */
    fun bitrate(base: Int): Int = maxOf(Math.round(base * fattore).toInt(), minOf(base, BITRATE_MINIMO))

    companion object {
        const val FATTORE_MINIMO = 0.2
        const val BITRATE_MINIMO = 500_000
        /** Alta e Massima: secondi di fila che la rete non regge la soglia, prima di scendere sotto. */
        const val SECONDI_ALLA_SOGLIA = 3

        /** Circa 6 Mbit/s a 1080p30, in proporzione per le altre risoluzioni e i 60 fps; HEVC il 40% in meno. */
        fun bitrateBase(larghezza: Int, altezza: Int, fps: Int, codec: Codec): Int {
            val pixel = larghezza.toDouble() * altezza
            return (pixel / (1920 * 1080) * 6_000_000 * (if (fps > 30) 1.5 else 1.0) * (if (codec == Codec.HEVC) 0.6 else 1.0)).toInt()
        }
    }
}

/**
 * I numeri della qualità a scelta (Protocollo.md, «Qualità a scelta»), gli stessi di Codificatore.swift. Il bitrate di
 * Auto è quello di sempre (BitrateVideo sull'app, `bitrateDiRiferimento` sull'iPhone); Alta e Massima lo moltiplicano,
 * con un tetto, e non scendono sotto quello di Auto finché la rete regge.
 */
object NumeriQualita {
    /** Il tetto del bitrate in tutti i livelli: oltre, nessun Wi-Fi di casa lo regge e il computer non vede differenza. */
    const val TETTO = 80_000_000

    fun moltiplicatore(livello: String): Double = when (livello) {
        LivelliQualita.ALTA -> 1.5
        LivelliQualita.MASSIMA -> 2.0
        else -> 1.0
    }

    /** Il fattore sotto cui la rete fa scendere solo se non regge: con Alta e Massima il bitrate di Auto. */
    fun soglia(livello: String): Double =
        if (moltiplicatore(livello) > 1.0) 1.0 / moltiplicatore(livello) else AdattamentoRete.FATTORE_MINIMO

    /** Il bitrate del livello, da quello di Auto (con il cavo già compreso), entro il tetto. */
    fun bitrate(diAuto: Int, livello: String): Int =
        minOf((diAuto * moltiplicatore(LivelliQualita.normalizza(livello))).toLong(), TETTO.toLong()).toInt()

    /**
     * Il formato di Massima tra i `formati` dell'obiettivo (già con i limiti della versione gratuita): quello con più
     * pixel e, a parità, con più fps (al massimo 60). `null` se non ce n'è nessuno: allora vale il formato chiesto.
     * Come `QualitaScelta.formatoMassimo` dell'iPhone.
     */
    fun formatoMassimo(formati: List<FormatoSupportato>): FormatoSupportato? =
        formati.filter { it.fpsMassimo > 0 }
            .maxWithOrNull(compareBy<FormatoSupportato>({ it.larghezza.toLong() * it.altezza }, { it.fpsMassimo }))
            ?.let { FormatoSupportato(maxOf(it.larghezza, it.altezza), minOf(it.larghezza, it.altezza), minOf(it.fpsMassimo, 60)) }
}

/** Come è collegato il telefono al computer (1.2): si ricava dall'interfaccia di rete usata, nessun messaggio nuovo. */
enum class TipoCollegamento(val testo: String, val senzaFili: Boolean) {
    WIFI("Wi-Fi", true),
    CAVO_USB("Cavo USB", false),
    WIFI_DIRETTO("Wi-Fi diretto", true),
    CAVO_DI_RETE("Cavo di rete", false),
    HOTSPOT("Hotspot", true);

    /** Il consiglio quando il collegamento è debole e ne esiste uno migliore; `null` se si è già sul cavo. */
    val consiglioSeDebole: String?
        get() = when (this) {
            WIFI, HOTSPOT -> "Con il cavo USB è più stabile"
            WIFI_DIRETTO -> "Con il cavo USB o sulla stessa rete Wi-Fi è più stabile"
            CAVO_USB, CAVO_DI_RETE -> null
        }

    companion object {
        /**
         * Dal nome dell'interfaccia Android della connessione: `rndis`/`ncm`/`usb` = tethering USB (il cavo),
         * `ap`/`swlan`/`softap` = hotspot del telefono, `p2p` = Wi-Fi Direct, `eth` = cavo di rete; il resto Wi-Fi.
         */
        fun daInterfaccia(nome: String?): TipoCollegamento? {
            val pulito = nome?.lowercase() ?: return null
            return when {
                pulito.startsWith("rndis") || pulito.startsWith("ncm") || pulito.startsWith("usb") -> CAVO_USB
                pulito.startsWith("ap") || pulito.startsWith("swlan") || pulito.startsWith("softap") -> HOTSPOT
                pulito.startsWith("p2p") -> WIFI_DIRETTO
                pulito.startsWith("eth") -> CAVO_DI_RETE
                pulito.startsWith("wlan") || pulito.startsWith("wifi") -> WIFI
                pulito.startsWith("lo") -> null
                else -> WIFI
            }
        }
    }
}
