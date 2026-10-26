namespace WebcamLR.Ricevitore;

/// <summary>Contenuti della sezione App (0.12): gli stessi testi di Stile/Sources/Stile/SezioneApp.swift.</summary>
public static class InfoApp
{
    /// <summary>Da confermare con Ledion. Vuoto = «Segnala un bug» copia il testo invece di aprire la mail.</summary>
    public const string EmailAssistenza = "";
    public const string Sito = "https://lr-apps609.github.io/WebcamLR/";
    public const string Privacy = "https://lr-apps609.github.io/WebcamLR/privacy.html";
    public const string Aiuto = "https://lr-apps609.github.io/WebcamLR/aiuto.html";
    /// <summary>La pagina per scaricare WebcamLR sul telefono e sul computer (il QR in fondo alla colonna di sinistra).</summary>
    public const string Download = "https://lr-apps609.github.io/WebcamLR/download.html";
    /// <summary>Il file con l'ultima versione pubblicata (Documenti/Pubblicazione.md), letto da «Aggiornamento disponibile».</summary>
    public const string VersioneRecente = "https://lr-apps609.github.io/WebcamLR/versione.json";
    /// <summary>La guida al microfono del telefono su Windows (W2): cavo audio virtuale, app di chiamata, OBS.</summary>
    public const string GuidaMicrofonoWindows = "https://github.com/LR-apps609/WebcamLR/blob/main/Documenti/Microfono%20Windows.md#usarlo-nelle-app-di-chiamata-e-in-obs";
    /// <summary>L'app gratuita «Dispositivi Apple» su Microsoft Store: installa il servizio per il cavo USB (1.7).</summary>
    public const string DispositiviApple = "ms-windows-store://pdp/?productid=9NP83LWLPZ9K";
    public const string SuggerimentoCavo = "Per il cavo USB con l'iPhone installa l'app gratuita «Dispositivi Apple» da Microsoft Store.";

    public static readonly IReadOnlyList<string> VantaggiPro =
    [
        "Video in 4K e a 60 fotogrammi",
        "Controlli manuali: ISO, tempo, bianco",
        "Profili salvati per ogni situazione",
        "Effetti: sfondo sfocato e luce da studio",
        "Più telefoni collegati insieme",
    ];

    public static readonly IReadOnlyList<string> AltreAppLR = ["OrbitLR", "GateLR"];
}

public sealed record SezioneGuida(string Titolo, IReadOnlyList<string> Passi);

/// <summary>La guida, con i passi pensati per chi usa Windows.</summary>
public static class Guida
{
    public static readonly IReadOnlyList<SezioneGuida> Sezioni =
    [
        new("Il primo collegamento",
        [
            "Apri WebcamLR sul PC: si fa trovare da solo sulla rete.",
            "Al primo avvio Windows chiede il permesso per le reti: consenti le reti private.",
            "Sul telefono, stessa rete Wi-Fi del PC, tocca il nome del PC.",
            "La prima volta il PC chiede di confermare: controlla che il codice sia lo stesso sui due schermi.",
        ]),
        new("Con il QR code",
        [
            "Se il PC non compare sul telefono, usa il QR code mostrato in questa finestra.",
            "Sul telefono tocca «Inquadra il QR code del computer» e inquadralo.",
            "È anche il modo più sicuro: il QR contiene il codice di sicurezza del PC.",
        ]),
        new("Usarla in Zoom, Meet e Teams",
        [
            "Nell'app della chiamata apri le impostazioni video.",
            "Come videocamera scegli «WebcamLR».",
            "Quando un'app usa il video, compare «In onda» in rosso.",
        ]),
        new("Comandi utili",
        [
            "1–4 cambiano obiettivo, + e − lo zoom, F11 schermo intero.",
            "«Finestra mini» tiene il video sopra le altre finestre.",
            "L'icona accanto all'orologio mostra lo stato: WebcamLR resta attiva anche a finestra chiusa.",
        ]),
        new("Se non si collega",
        [
            "Telefono e PC devono essere sulla stessa rete Wi-Fi (non quella «ospiti»).",
            "La rete del PC deve essere «privata»: Impostazioni › Rete e Internet › Wi-Fi › proprietà.",
            "Sull'iPhone: Impostazioni › Privacy e sicurezza › Rete locale › WebcamLR attivo.",
            "Dove la rete blocca i dispositivi tra loro, attiva l'hotspot del telefono e collega il PC a quello.",
            "Con il cavo USB: collega l'iPhone al PC e apri WebcamLR su tutti e due; in alto compare «Cavo USB». Serve l'app gratuita «Dispositivi Apple» di Microsoft Store. È il collegamento più stabile.",
            "Con il cavo e Android: sul telefono attiva «Tethering USB» e collegati come in Wi-Fi o con il QR code. Se Windows dice che la rete del cavo è «Pubblica», rendila privata.",
            "Ancora niente? Apri «Domande frequenti», usa il QR code, oppure «Segnala un bug».",
        ]),
    ];
}

/// <summary>«Segnala un bug»: la descrizione dell'utente e, se vuole, i dati tecnici. Mai video o immagini.</summary>
public static class SegnalazioneBug
{
    public const string Oggetto = "WebcamLR: segnalazione";

    public static string Testo(string descrizione, IReadOnlyList<(string Nome, string Valore)>? datiTecnici)
    {
        var righe = new List<string> { descrizione.Trim() };
        if (datiTecnici is { Count: > 0 })
        {
            righe.Add("");
            righe.Add("— Dati tecnici —");
            righe.AddRange(datiTecnici.Select(dato => $"{dato.Nome}: {dato.Valore}"));
        }
        return string.Join("\n", righe);
    }

    /// <summary>null se non c'è un indirizzo di assistenza.</summary>
    public static Uri? Mail(string indirizzo, string testo) =>
        string.IsNullOrWhiteSpace(indirizzo)
            ? null
            : new Uri($"mailto:{indirizzo}?subject={Uri.EscapeDataString(Oggetto)}&body={Uri.EscapeDataString(testo)}");
}
