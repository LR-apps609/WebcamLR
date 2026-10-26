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
    /// <summary>L'app gratuita «Dispositivi Apple» su Microsoft Store: installa il servizio per il cavo USB (1.7).</summary>
    public const string DispositiviApple = "ms-windows-store://pdp/?productid=9NP83LWLPZ9K";
    public static string SuggerimentoCavo => TestiRicevitore.T("App_SuggerimentoCavo");

    public static IReadOnlyList<string> VantaggiPro =>
    [
        TestiRicevitore.T("App_VantaggioPro1"),
        TestiRicevitore.T("App_VantaggioPro2"),
        TestiRicevitore.T("App_VantaggioPro3"),
        TestiRicevitore.T("App_VantaggioPro4"),
        TestiRicevitore.T("App_VantaggioPro5"),
    ];

    public static readonly IReadOnlyList<string> AltreAppLR = ["OrbitLR", "GateLR"];
}

public sealed record SezioneGuida(string Titolo, IReadOnlyList<string> Passi);

/// <summary>La guida, con i passi pensati per chi usa Windows.</summary>
public static class Guida
{
    public static IReadOnlyList<SezioneGuida> Sezioni =>
    [
        new(TestiRicevitore.T("Guida_PrimoCollegamento"),
        [
            TestiRicevitore.T("Guida_PrimoCollegamento1"),
            TestiRicevitore.T("Guida_PrimoCollegamento2"),
            TestiRicevitore.T("Guida_PrimoCollegamento3"),
            TestiRicevitore.T("Guida_PrimoCollegamento4"),
        ]),
        new(TestiRicevitore.T("Guida_QrCode"),
        [
            TestiRicevitore.T("Guida_QrCode1"),
            TestiRicevitore.T("Guida_QrCode2"),
            TestiRicevitore.T("Guida_QrCode3"),
        ]),
        new(TestiRicevitore.T("Guida_Chiamate"),
        [
            TestiRicevitore.T("Guida_Chiamate1"),
            TestiRicevitore.T("Guida_Chiamate2"),
            TestiRicevitore.T("Guida_Chiamate3"),
        ]),
        new(TestiRicevitore.T("Guida_Comandi"),
        [
            TestiRicevitore.T("Guida_Comandi1"),
            TestiRicevitore.T("Guida_Comandi2"),
            TestiRicevitore.T("Guida_Comandi3"),
        ]),
        new(TestiRicevitore.T("Guida_NonSiCollega"),
        [
            TestiRicevitore.T("Guida_NonSiCollega1"),
            TestiRicevitore.T("Guida_NonSiCollega2"),
            TestiRicevitore.T("Guida_NonSiCollega3"),
            TestiRicevitore.T("Guida_NonSiCollega4"),
            TestiRicevitore.T("Guida_NonSiCollega5"),
            TestiRicevitore.T("Guida_NonSiCollega6"),
            TestiRicevitore.T("Guida_NonSiCollega7"),
        ]),
    ];
}

/// <summary>«Segnala un bug»: la descrizione dell'utente e, se vuole, i dati tecnici. Mai video o immagini.</summary>
public static class SegnalazioneBug
{
    public static string Oggetto => TestiRicevitore.T("Bug_Oggetto");

    public static string Testo(string descrizione, IReadOnlyList<(string Nome, string Valore)>? datiTecnici)
    {
        var righe = new List<string> { descrizione.Trim() };
        if (datiTecnici is { Count: > 0 })
        {
            righe.Add("");
            righe.Add(TestiRicevitore.T("Bug_DatiTecnici"));
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
