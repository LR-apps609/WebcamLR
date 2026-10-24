package it.lrapps.webcamlr.android.contenuti

import java.text.Normalizer

/**
 * Domande frequenti (1.4), dentro l'app e senza Internet. Gli stessi `id` e lo stesso tono di
 * Stile/Sources/Stile/DomandeFrequenti.swift, con le risposte scritte per Android.
 */
data class DomandaFrequente(val id: String, val domanda: String, val risposta: String, val parole: List<String> = emptyList()) {
    /** Vero se la domanda contiene tutte le parole cercate, ignorando maiuscole e accenti. */
    fun corrisponde(ricerca: String): Boolean {
        val parti = normalizza(ricerca).split(' ').filter { it.isNotBlank() }
        if (parti.isEmpty()) return true
        val testo = normalizza((listOf(domanda, risposta) + parole).joinToString(" "))
        return parti.all { it in testo }
    }

    companion object {
        fun normalizza(testo: String): String =
            Normalizer.normalize(testo.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
    }
}

object DomandeFrequenti {
    val tutte = listOf(
        DomandaFrequente(
            "non-trova", "Il telefono non trova il computer",
            "Apri WebcamLR sul computer. Controlla che telefono e computer siano sulla stessa rete Wi-Fi (non quella «ospiti») e che sul telefono i dati mobili non abbiano preso il posto del Wi-Fi. Se ancora non compare, usa il QR code del computer o il tethering USB.",
            listOf("cerca", "lista", "vuota", "compare", "trovato"),
        ),
        DomandaFrequente(
            "rete-ospiti", "In hotel, in ufficio o a scuola non si collega",
            "Molte reti pubbliche tengono i dispositivi separati: sono online ma non possono parlarsi. Collega il telefono al computer con il cavo e attiva il tethering USB, oppure attiva l'hotspot del telefono e collega il computer a quello.",
            listOf("albergo", "hotel", "ufficio", "scuola", "università", "pubblica", "isolamento"),
        ),
        DomandaFrequente(
            "cavo", "Come mi collego con il cavo USB?",
            "Collega il telefono al computer con il cavo, poi sul telefono apri Impostazioni › Rete e Internet › Hotspot e tethering › Tethering USB (su Xiaomi: Impostazioni › Connessione e condivisione; su Samsung: Connessioni › Router Wi-Fi e tethering). Si crea una piccola rete sul cavo: il computer compare nella lista come sempre, e in alto vedrai «Cavo USB». È il collegamento più stabile e intanto ricarica il telefono. Su Windows funziona da solo. Sul Mac funziona con i telefoni più recenti; se il Mac non vede la nuova rete, usa il Wi-Fi o l'hotspot del telefono.",
            listOf("usb", "cavo", "usb-c", "filo", "tethering"),
        ),
        DomandaFrequente(
            "codice", "Perché il computer mi chiede un codice?",
            "È la prima volta che questo telefono si collega. Controlla che le 4 cifre siano uguali sul telefono e sul computer, poi scegli «Consenti». Dalla volta dopo si collega senza domande. Con il QR code il codice non serve.",
            listOf("4 cifre", "consentire", "abbinamento", "conferma"),
        ),
        DomandaFrequente(
            "identita", "«L'identità del computer è cambiata»: cosa vuol dire?",
            "Il telefono ricorda ogni computer usato. Se un computer con lo stesso nome si presenta diverso, il telefono si ferma per sicurezza. Succede se hai reinstallato WebcamLR sul computer: collegati di nuovo con il QR code. Se non hai cambiato niente, non collegarti.",
            listOf("sicurezza", "cambiata", "diverso"),
        ),
        DomandaFrequente(
            "ritardo", "Il video è in ritardo o va a scatti",
            "Guarda l'indicatore in alto: «Ottimo», «Buono» o «Debole». Con «Debole» avvicinati al router, usa la rete a 5 GHz, ferma i download, oppure usa il tethering USB.",
            listOf("lag", "latenza", "lento", "scatti", "ms", "millisecondi", "blocca"),
        ),
        DomandaFrequente(
            "zoom-teams", "Zoom, Teams o Meet non vedono WebcamLR",
            "Nelle impostazioni video dell'app scegli «WebcamLR» come videocamera. Se non c'è, chiudi e riapri l'app della chiamata dopo aver aperto WebcamLR. Sul Mac la webcam virtuale richiede l'account sviluppatore Apple a pagamento; su Windows arriva con un prossimo aggiornamento.",
            listOf("zoom", "teams", "meet", "facetime", "obs", "videocamera", "webcam virtuale"),
        ),
        DomandaFrequente(
            "schermo-spento", "Il video si ferma quando spengo lo schermo",
            "WebcamLR continua a mandare il video a schermo spento, con l'avviso «Video al computer». Su Xiaomi, Huawei, Oppo e altri il risparmio energetico può fermarlo lo stesso: in Impostazioni › App › WebcamLR › Batteria scegli «Nessuna restrizione» (o «Senza limiti»), e su Xiaomi attiva anche «Avvio automatico».",
            listOf("schermo", "spento", "blocco", "batteria", "xiaomi", "huawei", "miui", "hyperos", "risparmio"),
        ),
        DomandaFrequente(
            "caldo", "Il telefono si scalda",
            "È normale durante le chiamate lunghe. WebcamLR oscura lo schermo dopo 30 secondi e, se il telefono scalda molto, abbassa da sola la qualità e lo dice. Togli la custodia, tieni il telefono lontano dal sole e, se puoi, non caricarlo durante la chiamata.",
            listOf("calore", "caldo", "scotta", "temperatura"),
        ),
        DomandaFrequente(
            "batteria", "La batteria scende in fretta",
            "Sotto il 20% senza caricatore WebcamLR passa a 24 fotogrammi al secondo per durare di più. Per chiamate lunghe collega il caricatore, o il cavo USB al computer, che carica e trasmette insieme.",
            listOf("batteria", "carica", "consumo"),
        ),
        DomandaFrequente(
            "nero", "Sul computer il video è nero",
            "Aspetta qualche secondo: il video parte dal primo fotogramma completo. Su Windows, se sul telefono hai scelto HEVC, serve «Estensioni video HEVC» di Microsoft Store: altrimenti scegli H.264 nelle impostazioni del telefono.",
            listOf("nero", "schermo", "niente", "hevc", "vuoto"),
        ),
        DomandaFrequente(
            "firewall", "Su Windows non si collega mai",
            "Al primo avvio Windows chiede il permesso per le reti: va consentito per le reti private. Controlla anche che la rete del PC sia «privata» (Impostazioni › Rete e Internet › Wi-Fi › proprietà).",
            listOf("windows", "firewall", "defender", "rete pubblica"),
        ),
        DomandaFrequente(
            "qualita", "Come ottengo la qualità migliore?",
            "Metti il telefono in orizzontale su un supporto, usa la fotocamera posteriore (è la migliore), una buona luce davanti a te e il tethering USB o un Wi-Fi a 5 GHz. In Impostazioni puoi scegliere risoluzione e fotogrammi al secondo.",
            listOf("qualità", "nitido", "4k", "1080p", "risoluzione", "luce"),
        ),
        DomandaFrequente(
            "privacy", "Il mio video passa da Internet?",
            "No. Il video va dal telefono al computer solo sulla tua rete o sul cavo, cifrato con chiavi nuove a ogni collegamento. WebcamLR non ha account obbligatori, non registra e non raccoglie dati, e non usa i servizi Google.",
            listOf("privacy", "sicuro", "internet", "cloud", "dati", "google"),
        ),
        DomandaFrequente(
            "aggiorna", "«Aggiorna WebcamLR sul computer»: cosa devo fare?",
            "Sul computer c'è una versione vecchia di WebcamLR, che non usa ancora il collegamento cifrato. Scarica l'ultima versione dal sito di WebcamLR e installala sopra quella vecchia: i tuoi telefoni restano. Poi riapri WebcamLR su tutti e due.",
            listOf("aggiornare", "versione", "vecchia", "aggiornamento", "scarica"),
        ),
        DomandaFrequente(
            "huawei", "Funziona sui telefoni senza servizi Google (Huawei)?",
            "Sì. WebcamLR per Android non usa i servizi Google: ricerca del computer, lettura del QR code, video e sicurezza sono tutti del sistema o dentro l'app.",
            listOf("huawei", "honor", "google", "gms", "appgallery", "play store"),
        ),
        DomandaFrequente(
            "costo", "WebcamLR è gratis?",
            "Sì: oggi tutte le funzioni sono gratis, senza filigrana né pubblicità. WebcamLR Pro, in arrivo, aggiungerà funzioni per chi vuole di più.",
            listOf("prezzo", "gratis", "pro", "abbonamento", "filigrana", "pubblicità"),
        ),
    )

    fun risposta(id: String): DomandaFrequente? = tutte.firstOrNull { it.id == id }
}

/** Una sezione della guida: titolo e passi brevi, in ordine (come Guida in SezioneApp.swift). */
data class SezioneGuida(val id: String, val titolo: String, val passi: List<String>)

object Guida {
    val sezioni = listOf(
        SezioneGuida("inizia", "Il primo collegamento", listOf(
            "Apri WebcamLR sul computer: si fa trovare da solo sulla rete.",
            "Sul telefono, sulla stessa rete Wi-Fi del computer, tocca il nome del computer.",
            "La prima volta il computer chiede di confermare: controlla che il codice sia lo stesso sui due schermi.",
            "Dalla volta dopo il telefono si ricollega da solo appena apri l'app.",
        )),
        SezioneGuida("qr", "Con il QR code", listOf(
            "Se il computer non compare, sul computer apri «Collega con QR code».",
            "Sul telefono tocca «Inquadra il QR code del computer» e inquadralo.",
            "È anche il modo più sicuro: il QR contiene il codice di sicurezza del computer.",
        )),
        SezioneGuida("cavo", "Con il cavo USB", listOf(
            "Collega il telefono al computer con un cavo dati (non solo di ricarica).",
            "Sul telefono attiva il tethering USB nelle impostazioni di rete (Hotspot e tethering).",
            "Il computer compare nella lista come sempre e in alto vedrai «Cavo USB»: è il collegamento più stabile.",
        )),
        SezioneGuida("chiamate", "Usarla in Zoom, Meet e Teams", listOf(
            "Nell'app della chiamata apri le impostazioni video.",
            "Come videocamera scegli «WebcamLR».",
            "Quando un'app usa il video, sul telefono e sul computer compare «In onda» in rosso.",
        )),
        SezioneGuida("inquadratura", "Inquadrarsi bene", listOf(
            "Metti il telefono in orizzontale, all'altezza degli occhi, su un supporto.",
            "Accendi la griglia nelle impostazioni per allineare l'inquadratura.",
            "Tocca l'anteprima per mettere a fuoco, tieni premuto per il Blocco AE/AF.",
            "Doppio tocco per passare dalla fotocamera posteriore alla frontale.",
        )),
        SezioneGuida("batteria", "Batteria, calore e schermo spento", listOf(
            "Durante le chiamate lo schermo si oscura da solo: si risparmia batteria e il telefono scalda meno.",
            "Il video continua anche se spegni lo schermo; su Xiaomi e Huawei togli le restrizioni della batteria per WebcamLR.",
            "Per chiamate lunghe collega il caricatore.",
            "Se il telefono scalda molto, WebcamLR abbassa da sola la qualità e lo dice.",
        )),
        SezioneGuida("problemi", "Se non si collega", listOf(
            "Telefono e computer devono essere sulla stessa rete Wi-Fi (non quella «ospiti»).",
            "Su Windows consenti WebcamLR nelle reti private quando il sistema lo chiede.",
            "In hotel o in ufficio, dove la rete blocca i dispositivi tra loro, usa il tethering USB o l'hotspot del telefono.",
            "Ancora niente? Apri «Domande frequenti», usa il QR code, oppure «Segnala un bug».",
        )),
    )
}

/** Contenuti della sezione App, uguali su tutte le piattaforme (Stile/SezioneApp.swift). */
object InfoApp {
    /** Vuoto = «Segnala un bug» usa la condivisione di sistema invece della mail. */
    const val EMAIL_ASSISTENZA = ""
    const val SITO = "https://lr-apps609.github.io/WebcamLR/"
    const val PRIVACY = "https://lr-apps609.github.io/WebcamLR/privacy.html"
    val altreAppLR = listOf("OrbitLR", "GateLR")

    fun testoSegnalazione(descrizione: String, datiTecnici: List<Pair<String, String>>?): String {
        val righe = mutableListOf(descrizione.trim())
        if (!datiTecnici.isNullOrEmpty()) {
            righe += ""
            righe += "— Dati tecnici —"
            righe += datiTecnici.map { "${it.first}: ${it.second}" }
        }
        return righe.joinToString("\n")
    }

    const val OGGETTO_SEGNALAZIONE = "WebcamLR: segnalazione"
}
