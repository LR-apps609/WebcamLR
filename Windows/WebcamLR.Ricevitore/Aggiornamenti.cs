using System.Net.Http.Headers;
using System.Text.Json;

namespace WebcamLR.Ricevitore;

/// <summary>Il contenuto di <c>versione.json</c> (formato in Documenti/Pubblicazione.md). Solo <c>versione</c> è obbligatoria.</summary>
/// <param name="Data">«2026-10-25».</param>
/// <param name="Pagina">La pagina da aprire con «Scarica».</param>
/// <param name="Novita">Le novità, in poche righe.</param>
public sealed record VersionePubblicata(string Versione, int? Build, string? Data, string? Pagina, string? Novita)
{
    /// <summary>«1.0.1 (3)».</summary>
    public string Testo => Build is int build ? $"{Versione} ({build})" : Versione;

    /// <summary>La pagina da aprire: quella del file se è un indirizzo https, altrimenti la pagina di download del sito.</summary>
    public Uri Indirizzo =>
        Uri.TryCreate(Pagina, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps ? uri : new Uri(InfoApp.Download);

    /// <summary>«25 ottobre 2026» da «2026-10-25»; il testo com'è se non è una data.</summary>
    public string? DataLeggibile =>
        Data is null ? null
        : DateTime.TryParseExact(Data, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out var giorno)
            ? giorno.ToString("d MMMM yyyy", System.Globalization.CultureInfo.GetCultureInfo("it-IT"))
            : Data;
}

/// <summary>
/// Controlla se c'è una versione nuova di WebcamLR, come il Mac (Mac/Sorgenti/ControlloAggiornamenti.swift): all'avvio
/// e ogni 6 ore legge il file pubblico <c>versione.json</c> del sito e lo confronta con la versione dell'app. Niente rete,
/// file assente o sbagliato: non dice niente. Non scarica e non installa nulla: «Scarica» apre la pagina nel browser.
/// Il file può avere un oggetto <c>"windows"</c> con gli stessi campi, per una numerazione propria del PC: se c'è,
/// vale quello.
/// </summary>
public static class Aggiornamenti
{
    public static readonly Uri Indirizzo = new(InfoApp.VersioneRecente);
    public static readonly TimeSpan Intervallo = TimeSpan.FromHours(6);
    /// <summary>Il file è di poche righe: oltre, non è il file giusto.</summary>
    public const int DimensioneMassima = 64 * 1024;

    /// <summary>Il file letto, oppure null se non è valido (JSON sbagliato, versione assente o senza numeri).</summary>
    public static VersionePubblicata? Leggi(string json)
    {
        try
        {
            using var documento = JsonDocument.Parse(json);
            if (documento.RootElement.ValueKind != JsonValueKind.Object) return null;
            var radice = documento.RootElement;
            if (radice.TryGetProperty("windows", out var windows) && windows.ValueKind == JsonValueKind.Object
                && Da(windows) is { } propria)
            {
                return propria;
            }
            return Da(radice);
        }
        catch (JsonException) { return null; }
    }

    private static VersionePubblicata? Da(JsonElement oggetto)
    {
        if (Testo(oggetto, "versione") is not { Length: > 0 } versione || !char.IsAsciiDigit(versione[0])) return null;
        int? build = null;
        if (oggetto.TryGetProperty("build", out var b))
        {
            if (b.ValueKind == JsonValueKind.Number && b.TryGetInt32(out var numero)) build = numero;
            else if (b.ValueKind == JsonValueKind.String && int.TryParse(b.GetString(), out var dalTesto)) build = dalTesto;
        }
        return new VersionePubblicata(versione, build, Testo(oggetto, "data"), Testo(oggetto, "pagina"), Testo(oggetto, "novita", 2000));
    }

    private static string? Testo(JsonElement oggetto, string nome, int massimo = 200) =>
        oggetto.TryGetProperty(nome, out var valore) && valore.ValueKind == JsonValueKind.String
            ? (valore.GetString() is { } testo && testo.Length > massimo ? testo[..massimo] : valore.GetString())
            : null;

    /// <summary>Prima la versione, numero per numero («1.10» viene dopo «1.9», «1.0» è uguale a «1.0.0»), poi la build.</summary>
    public static bool PiuRecente(VersionePubblicata letta, string versione, int build)
    {
        var confronto = Confronta(letta.Versione, versione);
        if (confronto != 0) return confronto > 0;
        return letta.Build is int nuova && nuova > build;
    }

    /// <summary>1 se <paramref name="a"/> è più recente di <paramref name="b"/>, -1 se è più vecchia, 0 se sono uguali.</summary>
    public static int Confronta(string a, string b)
    {
        var numeriA = Numeri(a);
        var numeriB = Numeri(b);
        for (var i = 0; i < Math.Max(numeriA.Count, numeriB.Count); i++)
        {
            var x = i < numeriA.Count ? numeriA[i] : 0;
            var y = i < numeriB.Count ? numeriB[i] : 0;
            if (x != y) return x > y ? 1 : -1;
        }
        return 0;
    }

    /// <summary>«1.0.1 (3)» → [1, 0, 1]: solo i numeri prima di uno spazio o di altro testo.</summary>
    private static List<int> Numeri(string versione)
    {
        var parte = versione.Split(' ', 2)[0];
        return parte.Split('.').Select(pezzo =>
        {
            var cifre = new string(pezzo.TakeWhile(char.IsAsciiDigit).Take(9).ToArray());
            return int.TryParse(cifre, out var n) ? n : 0;
        }).ToList();
    }

    /// <summary>
    /// Il file del sito, senza cache; null per qualsiasi errore (rete, 404, troppo grande, contenuto sbagliato).
    /// Da chiamare fuori dal thread dell'interfaccia.
    /// </summary>
    public static async Task<VersionePubblicata?> ScaricaAsync(HttpClient client, CancellationToken annulla = default)
    {
        try
        {
            using var richiesta = new HttpRequestMessage(HttpMethod.Get, Indirizzo);
            richiesta.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            richiesta.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };
            using var tempo = CancellationTokenSource.CreateLinkedTokenSource(annulla);
            tempo.CancelAfter(TimeSpan.FromSeconds(15));
            using var risposta = await client.SendAsync(richiesta, HttpCompletionOption.ResponseHeadersRead, tempo.Token).ConfigureAwait(false);
            if (!risposta.IsSuccessStatusCode || risposta.Content.Headers.ContentLength > DimensioneMassima) return null;
            await using var flusso = await risposta.Content.ReadAsStreamAsync(tempo.Token).ConfigureAwait(false);
            var buffer = new byte[DimensioneMassima + 1];
            var letti = 0;
            int n;
            while (letti < buffer.Length && (n = await flusso.ReadAsync(buffer.AsMemory(letti), tempo.Token).ConfigureAwait(false)) > 0) letti += n;
            if (letti > DimensioneMassima) return null;
            return Leggi(System.Text.Encoding.UTF8.GetString(buffer, 0, letti));
        }
        catch (Exception) { return null; }
    }
}
