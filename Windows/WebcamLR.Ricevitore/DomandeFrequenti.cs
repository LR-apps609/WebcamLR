using System.Globalization;
using System.Text;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Domande frequenti (1.4), dentro l'app e senza Internet: gli stessi testi di Stile/Sources/Stile/DomandeFrequenti.swift.
/// </summary>
public sealed record DomandaFrequente(string Id, string Domanda, string Risposta, IReadOnlyList<string> Parole)
{
    /// <summary>Vero se domanda, risposta o parole contengono tutte le parole cercate, senza badare a maiuscole e accenti.</summary>
    public bool Corrisponde(string ricerca)
    {
        var parti = Normalizza(ricerca).Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parti.Length == 0) return true;
        var testo = Normalizza(string.Join(" ", new[] { Domanda, Risposta }.Concat(Parole)));
        return parti.All(testo.Contains);
    }

    internal static string Normalizza(string testo)
    {
        var scomposto = testo.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var risultato = new StringBuilder(scomposto.Length);
        foreach (var carattere in scomposto)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(carattere) != UnicodeCategory.NonSpacingMark) risultato.Append(carattere);
        }
        return risultato.ToString();
    }
}

public static class DomandeFrequenti
{
    public static readonly IReadOnlyList<DomandaFrequente> Tutte =
    [
        new("non-trova", "L'iPhone non trova il computer",
            "Apri WebcamLR sul computer. Controlla che iPhone e computer siano sulla stessa rete Wi-Fi (non quella «ospiti»). Sull'iPhone: Impostazioni › Privacy e sicurezza › Rete locale › WebcamLR attivo. Se ancora non compare, usa il QR code del computer o il cavo USB.",
            ["cerca", "lista", "vuota", "compare", "trovato"]),
        new("rete-locale", "Cos'è il permesso «Rete locale»?",
            "È il permesso che iOS chiede per cercare i computer in casa tua. Senza, WebcamLR non può vedere il computer. Lo attivi in Impostazioni › Privacy e sicurezza › Rete locale. WebcamLR non usa la rete per nient'altro.",
            ["permesso", "privacy", "negato"]),
        new("rete-ospiti", "In hotel, in ufficio o a scuola non si collega",
            "Molte reti pubbliche tengono i dispositivi separati: sono online ma non possono parlarsi. Usa il cavo USB, oppure attiva l'Hotspot personale dell'iPhone e collega il computer a quello.",
            ["albergo", "hotel", "ufficio", "scuola", "università", "pubblica", "isolamento"]),
        new("cavo", "Come mi collego con il cavo USB?",
            "Collega l'iPhone al computer con il cavo e apri WebcamLR su tutti e due: il collegamento parte da solo e in alto compare «Cavo USB». Su Windows serve l'app gratuita «Dispositivi Apple» di Microsoft Store. Il cavo è la scelta più stabile e intanto ricarica il telefono.",
            ["usb", "cavo", "lightning", "usb-c", "filo"]),
        new("codice", "Perché il computer mi chiede un codice?",
            "È la prima volta che quell'iPhone si collega. Controlla che le 4 cifre siano uguali sull'iPhone e sul computer, poi scegli «Consenti». Dalla volta dopo si collega senza domande. Con il QR code il codice non serve.",
            ["4 cifre", "consentire", "abbinamento", "conferma"]),
        new("identita", "«L'identità del computer è cambiata»: cosa vuol dire?",
            "L'iPhone ricorda ogni computer usato. Se un computer con lo stesso nome si presenta diverso, l'iPhone si ferma per sicurezza. Succede se hai reinstallato WebcamLR sul computer: collegati di nuovo con il QR code. Se non hai cambiato niente, non collegarti.",
            ["sicurezza", "cambiata", "diverso"]),
        new("ritardo", "Il video è in ritardo o va a scatti",
            "Guarda l'indicatore in alto: «Ottimo», «Buono» o «Debole». Con «Debole» avvicinati al router, usa la rete a 5 GHz, ferma i download, oppure usa il cavo USB. Il Wi-Fi diretto, se acceso sul Mac, può rendere la latenza meno stabile: spegnilo se non serve.",
            ["lag", "latenza", "lento", "scatti", "ms", "millisecondi", "blocca"]),
        new("zoom-teams", "Zoom, Teams o Meet non vedono WebcamLR",
            "Nelle impostazioni video dell'app scegli «WebcamLR» come videocamera. Se non c'è, chiudi e riapri l'app della chiamata dopo aver aperto WebcamLR. Sul Mac la webcam virtuale richiede l'account sviluppatore Apple a pagamento; su Windows arriva con un prossimo aggiornamento.",
            ["zoom", "teams", "meet", "facetime", "obs", "videocamera", "webcam virtuale"]),
        new("caldo", "L'iPhone si scalda",
            "È normale durante le chiamate lunghe. WebcamLR oscura lo schermo dopo 30 secondi e, se il telefono scalda molto, abbassa da sola la qualità e lo dice. Togli la custodia, tieni l'iPhone lontano dal sole e, se puoi, non caricarlo durante la chiamata.",
            ["calore", "caldo", "scotta", "temperatura"]),
        new("batteria", "La batteria scende in fretta",
            "Sotto il 20% senza caricatore WebcamLR passa a 24 fotogrammi al secondo per durare di più. Per chiamate lunghe collega il caricatore, o il cavo USB al computer, che carica e trasmette insieme.",
            ["batteria", "carica", "consumo"]),
        new("nero", "Sul computer il video è nero",
            "Aspetta qualche secondo: il video parte dal primo fotogramma completo. Su Windows, se sull'iPhone hai scelto HEVC, serve «Estensioni video HEVC» di Microsoft Store: altrimenti scegli H.264 nelle impostazioni dell'iPhone.",
            ["nero", "schermo", "niente", "hevc", "vuoto"]),
        new("firewall", "Su Windows non si collega mai",
            "Al primo avvio Windows chiede il permesso per le reti: va consentito per le reti private. Controlla anche che la rete del PC sia «privata» (Impostazioni › Rete e Internet › Wi-Fi › proprietà). Con il cavo USB il firewall non conta.",
            ["windows", "firewall", "defender", "rete pubblica"]),
        new("qualita", "Come ottengo la qualità migliore?",
            "Metti l'iPhone in orizzontale su un supporto, usa la fotocamera posteriore (è la migliore), una buona luce davanti a te e il cavo USB o un Wi-Fi a 5 GHz. In Impostazioni puoi scegliere risoluzione e fotogrammi al secondo.",
            ["qualità", "nitido", "4k", "1080p", "risoluzione", "luce"]),
        new("privacy", "Il mio video passa da Internet?",
            "No. Il video va dall'iPhone al computer solo sulla tua rete o sul cavo, cifrato con chiavi nuove a ogni collegamento. WebcamLR non ha account obbligatori, non registra e non raccoglie dati.",
            ["privacy", "sicuro", "internet", "cloud", "dati"]),
        new("costo", "WebcamLR è gratis?",
            "Sì: oggi tutte le funzioni sono gratis, senza filigrana né pubblicità. WebcamLR Pro, in arrivo, aggiungerà funzioni per chi vuole di più.",
            ["prezzo", "gratis", "pro", "abbonamento", "filigrana", "pubblicità"]),
    ];

    public static DomandaFrequente? Risposta(string id) => Tutte.FirstOrDefault(d => d.Id == id);

    public static IEnumerable<DomandaFrequente> Cerca(string ricerca) => Tutte.Where(d => d.Corrisponde(ricerca));
}
