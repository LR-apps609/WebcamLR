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
 */
class AdattamentoRete {
    var fattore = 1.0
        private set
    private var secondiPuliti = 0

    fun azzera() {
        fattore = 1.0
        secondiPuliti = 0
    }

    /** Una volta al secondo. Ritorna `true` se la rete è debole (bitrate ben sotto la qualità scelta). */
    fun secondo(scartati: Int, saturo: Boolean): Boolean {
        if (scartati > 0 || saturo) {
            fattore = maxOf(fattore * 0.7, FATTORE_MINIMO)
            secondiPuliti = 0
        } else if (fattore < 1) {
            secondiPuliti++
            if (secondiPuliti >= 3) {
                fattore = minOf(fattore + 0.1, 1.0)
                secondiPuliti = 0
            }
        }
        return fattore < 0.6
    }

    /** Il bitrate da usare ora, partendo da quello della qualità scelta. */
    fun bitrate(base: Int): Int = maxOf((base * fattore).toInt(), minOf(base, BITRATE_MINIMO))

    companion object {
        const val FATTORE_MINIMO = 0.2
        const val BITRATE_MINIMO = 500_000

        /** Circa 6 Mbit/s a 1080p30, in proporzione per le altre risoluzioni e i 60 fps; HEVC il 40% in meno. */
        fun bitrateBase(larghezza: Int, altezza: Int, fps: Int, codec: Codec): Int {
            val pixel = larghezza.toDouble() * altezza
            return (pixel / (1920 * 1080) * 6_000_000 * (if (fps > 30) 1.5 else 1.0) * (if (codec == Codec.HEVC) 0.6 else 1.0)).toInt()
        }
    }
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
