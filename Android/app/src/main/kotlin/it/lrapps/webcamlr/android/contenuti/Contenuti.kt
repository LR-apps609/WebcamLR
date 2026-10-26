package it.lrapps.webcamlr.android.contenuti

import java.text.Normalizer

/**
 * Domande frequenti (1.4), dentro l'app e senza Internet. Gli stessi `id` e lo stesso tono di
 * Stile/Sources/Stile/DomandeFrequenti.swift, con le risposte scritte per Android, in italiano e in inglese
 * (l'inglese per ogni lingua diversa dall'italiano, come su iPhone e Mac).
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
    fun tutte(inglese: Boolean): List<DomandaFrequente> = if (inglese) inglesi else italiane

    fun risposta(id: String, inglese: Boolean = false): DomandaFrequente? = tutte(inglese).firstOrNull { it.id == id }

    private val italiane = listOf(
        DomandaFrequente(
            "non-trova", "Il telefono non trova il computer",
            "Apri WebcamLR sul computer. Controlla che telefono e computer siano sulla stessa rete Wi-Fi (non quella «ospiti») e che sul telefono i dati mobili non abbiano preso il posto del Wi-Fi. Se ancora non compare, usa il QR code del computer o il tethering USB.",
            listOf("cerca", "lista", "vuota", "compare", "trovato", "android"),
        ),
        DomandaFrequente(
            "rete-ospiti", "In hotel, in ufficio o a scuola non si collega",
            "Molte reti pubbliche tengono i dispositivi separati: sono online ma non possono parlarsi. Collega il telefono al computer con il cavo e attiva il tethering USB, oppure attiva l'hotspot del telefono e collega il computer a quello.",
            listOf("albergo", "hotel", "ufficio", "scuola", "università", "pubblica", "isolamento", "hotspot"),
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
            "Guarda il pallino e le tacche nella riga in alto: toccala per i «Dettagli» con «Ottimo», «Buono» o «Debole». Con «Debole» avvicinati al router, usa la rete a 5 GHz, ferma i download, oppure usa il tethering USB.",
            listOf("lag", "latenza", "lento", "scatti", "ms", "millisecondi", "blocca"),
        ),
        DomandaFrequente(
            "zoom-teams", "Zoom, Teams o Meet non vedono WebcamLR",
            "Nelle impostazioni video dell'app scegli «WebcamLR» come videocamera: funziona in qualsiasi app, da Zoom a Teams, Meet, FaceTime e OBS. Se non c'è, chiudi e riapri l'app della chiamata dopo aver aperto WebcamLR. Sul Mac serve la versione con la webcam virtuale (in arrivo: richiede l'account sviluppatore Apple); su Windows c'è già, con la webcam virtuale di WebcamLR. Per il microfono del telefono: sul Mac scegli «WebcamLR (microfono)»; su Windows passa da un cavo audio virtuale (per esempio VB-CABLE) e nell'app scegli «CABLE Output».",
            listOf("zoom", "teams", "meet", "facetime", "obs", "videocamera", "webcam virtuale", "microfono", "audio"),
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
            "Aspetta qualche secondo: il video parte dal primo fotogramma completo. Controlla che il video non sia in pausa (il pulsante «Pausa» in «In onda»). Su Windows, se sul telefono hai scelto HEVC, serve «Estensioni video HEVC» di Microsoft Store: altrimenti scegli H.264 in Impostazioni › Video avanzato.",
            listOf("nero", "schermo", "niente", "hevc", "vuoto", "pausa"),
        ),
        DomandaFrequente(
            "firewall", "Su Windows non si collega mai",
            "Al primo avvio Windows chiede il permesso per le reti: va consentito per le reti private. Controlla anche che la rete del PC sia «privata» (Impostazioni › Rete e Internet › Wi-Fi › proprietà). Con il tethering USB vale anche per la rete del cavo, in Rete e Internet › Ethernet.",
            listOf("windows", "firewall", "defender", "rete pubblica", "tethering"),
        ),
        DomandaFrequente(
            "qualita", "Come ottengo la qualità migliore?",
            "Metti il telefono in orizzontale su un supporto, usa la fotocamera posteriore (è la migliore), una buona luce davanti a te e il tethering USB o un Wi-Fi a 5 GHz. In Impostazioni › Video avanzato scegli risoluzione e fotogrammi al secondo: gratis fino a 720p a 30 fps, con WebcamLR Pro fino al 4K e a 60 fps.",
            listOf("qualità", "nitido", "4k", "1080p", "720p", "risoluzione", "luce"),
        ),
        DomandaFrequente(
            "privacy", "Il mio video passa da Internet?",
            "No. Il video va dal telefono al computer solo sulla tua rete o sul cavo, cifrato con chiavi nuove a ogni collegamento. WebcamLR non ha account, non registra e non raccoglie dati. Google Play serve solo per comprare WebcamLR Pro.",
            listOf("privacy", "sicuro", "internet", "cloud", "dati", "google"),
        ),
        DomandaFrequente(
            "aggiorna", "«Aggiorna WebcamLR sul computer»: cosa devo fare?",
            "Sul computer c'è una versione vecchia di WebcamLR, che non usa ancora il collegamento cifrato. Scarica l'ultima versione dal sito di WebcamLR e installala sopra quella vecchia: i tuoi telefoni restano. Poi riapri WebcamLR su tutti e due.",
            listOf("aggiornare", "versione", "vecchia", "aggiornamento", "scarica"),
        ),
        DomandaFrequente(
            "huawei", "Funziona sui telefoni senza servizi Google (Huawei)?",
            "Sì. Ricerca del computer, lettura del QR code, video e sicurezza sono tutti del sistema o dentro l'app. Senza Google Play manca solo l'acquisto di WebcamLR Pro: il resto funziona uguale.",
            listOf("huawei", "honor", "google", "gms", "appgallery", "play store"),
        ),
        DomandaFrequente(
            "costo", "WebcamLR è gratis?",
            "Sì: la versione gratuita resta gratis per sempre, fino a 720p a 30 fps, senza filigrana, senza pubblicità e senza account. WebcamLR Pro si paga una volta sola, senza abbonamento: 14,99 € (il prezzo può cambiare secondo il paese e lo store) e aggiunge 1080p, 4K, 60 fps, effetti e controlli Pro. Si compra sul telefono, dall'App Store o da Google Play, e sblocca anche il computer collegato: sul Mac e su Windows non c'è niente da comprare. «Ripristina acquisti» lo riporta su un telefono nuovo con lo stesso account Google.",
            listOf("prezzo", "gratis", "pro", "abbonamento", "filigrana", "pubblicità", "acquisto", "ripristina"),
        ),
    )

    private val inglesi = listOf(
        DomandaFrequente(
            "non-trova", "The phone can’t find the computer",
            "Open WebcamLR on the computer. Check that the phone and the computer are on the same Wi-Fi network (not the “guest” one) and that mobile data hasn’t taken over from Wi-Fi on the phone. If it still doesn’t show up, use the computer’s QR code or USB tethering.",
            listOf("search", "list", "empty", "found", "android"),
        ),
        DomandaFrequente(
            "rete-ospiti", "It won’t connect at a hotel, office or school",
            "Many public networks keep devices apart: they are online but can’t talk to each other. Connect the phone to the computer with a cable and turn on USB tethering, or turn on the phone’s hotspot and connect the computer to it.",
            listOf("hotel", "office", "school", "university", "public", "isolation", "hotspot"),
        ),
        DomandaFrequente(
            "cavo", "How do I connect with a USB cable?",
            "Connect the phone to the computer with the cable, then on the phone open Settings › Network & internet › Hotspot & tethering › USB tethering (on Xiaomi: Settings › Connection & sharing; on Samsung: Connections › Mobile Hotspot and Tethering). A small network is created over the cable: the computer shows up in the list as usual, and “USB cable” appears at the top. It’s the most stable connection and it charges the phone too. On Windows it just works. On a Mac it works with newer phones; if the Mac doesn’t see the new network, use Wi-Fi or the phone’s hotspot.",
            listOf("usb", "cable", "usb-c", "wire", "tethering"),
        ),
        DomandaFrequente(
            "codice", "Why does the computer ask me for a code?",
            "This phone is connecting for the first time. Check that the 4 digits are the same on the phone and on the computer, then choose “Allow”. From then on it connects without asking. With the QR code no code is needed.",
            listOf("4 digits", "allow", "pairing", "confirm"),
        ),
        DomandaFrequente(
            "identita", "“The computer’s identity has changed”: what does it mean?",
            "The phone remembers every computer it has used. If a computer with the same name shows up different, the phone stops to be safe. It happens if you reinstalled WebcamLR on the computer: connect again with the QR code. If you haven’t changed anything, don’t connect.",
            listOf("security", "changed", "different"),
        ),
        DomandaFrequente(
            "ritardo", "The video lags or stutters",
            "Look at the dot and the bars in the line at the top: tap it for “Details” with “Excellent”, “Good” or “Weak”. With “Weak”, move closer to the router, use the 5 GHz network, stop downloads, or use USB tethering.",
            listOf("lag", "latency", "slow", "stutter", "ms", "milliseconds", "freeze"),
        ),
        DomandaFrequente(
            "zoom-teams", "Zoom, Teams or Meet don’t see WebcamLR",
            "In the app’s video settings choose “WebcamLR” as the camera: it works in any app, from Zoom to Teams, Meet, FaceTime and OBS. If it isn’t there, quit and reopen the call app after opening WebcamLR. On the Mac you need the version with the virtual webcam (coming soon: it requires an Apple developer account); on Windows it’s already there, with WebcamLR’s virtual webcam. For the phone’s microphone: on the Mac choose “WebcamLR (microfono)”; on Windows it goes through a virtual audio cable (for example VB-CABLE), and in the app you choose “CABLE Output”.",
            listOf("zoom", "teams", "meet", "facetime", "obs", "camera", "virtual webcam", "microphone", "audio"),
        ),
        DomandaFrequente(
            "schermo-spento", "The video stops when I turn off the screen",
            "WebcamLR keeps sending video with the screen off, with the “Video to computer” notice. On Xiaomi, Huawei, Oppo and others, battery saving may stop it anyway: in Settings › Apps › WebcamLR › Battery choose “No restrictions” (or “Unrestricted”), and on Xiaomi also turn on “Autostart”.",
            listOf("screen", "off", "lock", "battery", "xiaomi", "huawei", "miui", "hyperos", "saving"),
        ),
        DomandaFrequente(
            "caldo", "The phone gets warm",
            "That’s normal during long calls. WebcamLR dims the screen after 30 seconds and, if the phone gets very warm, lowers the quality by itself and tells you. Take off the case, keep the phone out of the sun and, if you can, don’t charge it during the call.",
            listOf("heat", "hot", "warm", "temperature"),
        ),
        DomandaFrequente(
            "batteria", "The battery drains fast",
            "Below 20% without a charger WebcamLR switches to 24 frames per second to last longer. For long calls plug in the charger, or the USB cable to the computer, which charges and streams at the same time.",
            listOf("battery", "charge", "drain"),
        ),
        DomandaFrequente(
            "nero", "The video is black on the computer",
            "Wait a few seconds: the video starts from the first complete frame. Check that the video isn’t paused (the “Pause” button in “Live”). On Windows, if you chose HEVC on the phone, you need “HEVC Video Extensions” from Microsoft Store: otherwise choose H.264 in Settings › Advanced video.",
            listOf("black", "screen", "nothing", "hevc", "empty", "pause"),
        ),
        DomandaFrequente(
            "firewall", "It never connects on Windows",
            "On first launch Windows asks for network permission: allow it for private networks. Also check that the PC’s network is “private” (Settings › Network & internet › Wi-Fi › properties). With USB tethering the same applies to the cable’s network, under Network & internet › Ethernet.",
            listOf("windows", "firewall", "defender", "public network", "tethering"),
        ),
        DomandaFrequente(
            "qualita", "How do I get the best quality?",
            "Put the phone in landscape on a stand, use the back camera (it’s the best one), good light in front of you and USB tethering or 5 GHz Wi-Fi. In Settings › Advanced video choose resolution and frame rate: free up to 720p at 30 fps, with WebcamLR Pro up to 4K and 60 fps.",
            listOf("quality", "sharp", "4k", "1080p", "720p", "resolution", "light"),
        ),
        DomandaFrequente(
            "privacy", "Does my video go over the Internet?",
            "No. The video goes from the phone to the computer only over your network or the cable, encrypted with new keys at every connection. WebcamLR has no accounts, doesn’t record and doesn’t collect data. Google Play is only used to buy WebcamLR Pro.",
            listOf("privacy", "secure", "internet", "cloud", "data", "google"),
        ),
        DomandaFrequente(
            "aggiorna", "“Update WebcamLR on the computer”: what should I do?",
            "The computer has an old version of WebcamLR that doesn’t use the encrypted connection yet. Download the latest version from the WebcamLR website and install it over the old one: your phones are kept. Then reopen WebcamLR on both.",
            listOf("update", "version", "old", "download"),
        ),
        DomandaFrequente(
            "huawei", "Does it work on phones without Google services (Huawei)?",
            "Yes. Finding the computer, reading the QR code, video and security are all part of the system or built into the app. Without Google Play only the WebcamLR Pro purchase is missing: everything else works the same.",
            listOf("huawei", "honor", "google", "gms", "appgallery", "play store"),
        ),
        DomandaFrequente(
            "costo", "Is WebcamLR free?",
            "Yes: the free version stays free forever, up to 720p at 30 fps, with no watermark, no ads and no account. WebcamLR Pro is a one-time purchase, with no subscription: €14.99 (the price may vary by country and store), and it adds 1080p, 4K, 60 fps, effects and Pro controls. You buy it on the phone, from the App Store or Google Play, and it also unlocks the connected computer: there’s nothing to buy on the Mac or on Windows. “Restore purchases” brings it back on a new phone with the same Google account.",
            listOf("price", "free", "pro", "subscription", "watermark", "ads", "purchase", "restore"),
        ),
    )
}

/** Una sezione della guida: titolo e passi brevi, in ordine (come Guida in SezioneApp.swift). */
data class SezioneGuida(val id: String, val titolo: String, val passi: List<String>)

object Guida {
    fun sezioni(inglese: Boolean): List<SezioneGuida> = if (inglese) inglesi else italiane

    private val italiane = listOf(
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
            "Quando un'app usa il video, sul telefono e sul computer compare «In onda» col pallino corallo.",
        )),
        SezioneGuida("in-onda", "Durante la chiamata", listOf(
            "Tocca la riga in alto per i «Dettagli»: qualità, formato, batteria e temperatura.",
            "I pulsanti a destra: Specchia, Sfoca sfondo, Microfono, Torcia, Pausa e Impostazioni; «Scollega» in fondo.",
            "Effetti, Assistente e Controlli Pro si aprono dalle Impostazioni. Profili ed effetti si scelgono anche sul computer.",
        )),
        SezioneGuida("inquadratura", "Inquadrarsi bene", listOf(
            "Metti il telefono in orizzontale, all'altezza degli occhi, su un supporto.",
            "Accendi griglia e livella nelle impostazioni: la linea diventa verde quando è dritto.",
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

    private val inglesi = listOf(
        SezioneGuida("inizia", "The first connection", listOf(
            "Open WebcamLR on the computer: it makes itself visible on the network.",
            "On the phone, on the same Wi-Fi network as the computer, tap the computer’s name.",
            "The first time, the computer asks you to confirm: check that the code is the same on both screens.",
            "From then on the phone reconnects by itself as soon as you open the app.",
        )),
        SezioneGuida("qr", "With the QR code", listOf(
            "If the computer doesn’t show up, open “Connect with QR code” on the computer.",
            "On the phone tap “Scan the computer’s QR code” and point the camera at it.",
            "It’s also the safest way: the QR code contains the computer’s security code.",
        )),
        SezioneGuida("cavo", "With a USB cable", listOf(
            "Connect the phone to the computer with a data cable (not a charge-only one).",
            "On the phone turn on USB tethering in the network settings (Hotspot & tethering).",
            "The computer shows up in the list as usual and “USB cable” appears at the top: it’s the most stable connection.",
        )),
        SezioneGuida("chiamate", "Using it in Zoom, Meet and Teams", listOf(
            "In the call app open the video settings.",
            "Choose “WebcamLR” as the camera.",
            "When an app uses the video, “Live” with the coral dot appears on the phone and on the computer.",
        )),
        SezioneGuida("in-onda", "During the call", listOf(
            "Tap the line at the top for “Details”: quality, format, battery and temperature.",
            "The buttons on the right: Mirror, Blur background, Microphone, Flashlight, Pause and Settings; “Disconnect” at the bottom.",
            "Effects, Assistant and Pro controls open from Settings. Profiles and effects can also be chosen on the computer.",
        )),
        SezioneGuida("inquadratura", "Framing yourself well", listOf(
            "Put the phone in landscape, at eye level, on a stand.",
            "Turn on the grid and the level in settings: the line turns green when it’s straight.",
            "Tap the preview to focus, press and hold for AE/AF Lock.",
            "Double-tap to switch between the back and front camera.",
        )),
        SezioneGuida("batteria", "Battery, heat and screen off", listOf(
            "During calls the screen dims by itself: it saves battery and the phone stays cooler.",
            "The video keeps going even if you turn off the screen; on Xiaomi and Huawei remove the battery restrictions for WebcamLR.",
            "For long calls plug in the charger.",
            "If the phone gets very warm, WebcamLR lowers the quality by itself and tells you.",
        )),
        SezioneGuida("problemi", "If it won’t connect", listOf(
            "The phone and the computer must be on the same Wi-Fi network (not the “guest” one).",
            "On Windows allow WebcamLR on private networks when the system asks.",
            "At hotels or offices, where the network keeps devices apart, use USB tethering or the phone’s hotspot.",
            "Still nothing? Open “FAQ”, use the QR code, or “Report a bug”.",
        )),
    )
}

/** Contenuti della sezione App, uguali su tutte le piattaforme (Stile/SezioneApp.swift). */
object InfoApp {
    /** Vuoto = «Segnala un bug» usa la condivisione di sistema invece della mail. */
    const val EMAIL_ASSISTENZA = ""
    const val SITO = "https://lr-apps609.github.io/WebcamLR/"
    const val PRIVACY = "https://lr-apps609.github.io/WebcamLR/privacy.html"
    const val AIUTO = "https://lr-apps609.github.io/WebcamLR/aiuto.html"
    /** La pagina per scaricare WebcamLR sul computer (la presentazione la manda con «Mandami il link»). */
    const val DOWNLOAD = "https://lr-apps609.github.io/WebcamLR/download.html"
    /** L'indirizzo da leggere e scrivere a mano, nella presentazione. */
    const val INDIRIZZO_BREVE = "lr-apps609.github.io/WebcamLR"
    val altreAppLR = listOf("OrbitLR", "GateLR")

    /** `intestazione`: «— Dati tecnici —» nella lingua dell'app (R.string.dati_tecnici_intestazione). */
    fun testoSegnalazione(descrizione: String, datiTecnici: List<Pair<String, String>>?, intestazione: String): String {
        val righe = mutableListOf(descrizione.trim())
        if (!datiTecnici.isNullOrEmpty()) {
            righe += ""
            righe += intestazione
            righe += datiTecnici.map { "${it.first}: ${it.second}" }
        }
        return righe.joinToString("\n")
    }
}
