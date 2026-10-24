using System.Text.Json;

namespace WebcamLR.Setup;

/// <summary>Un runtime .NET richiesto da un file *.runtimeconfig.json: per esempio Microsoft.NETCore.App 8.0.0.</summary>
public sealed record RuntimeRichiesto(string Nome, string Versione)
{
    /// <summary>«8.0»: .NET accetta qualsiasi aggiornamento della stessa versione (rollForward predefinito, «Minor» sulle patch).</summary>
    public string Canale
    {
        get
        {
            var parti = Versione.Split('.');
            return parti.Length >= 2 ? $"{parti[0]}.{parti[1]}" : Versione;
        }
    }
}

/// <summary>
/// Quale .NET serve a WebcamLR e se c'è già. L'app e la sorgente della webcam (dentro Frame Server) usano il .NET
/// installato in «C:\Program Files\dotnet»: l'installatore legge i loro *.runtimeconfig.json dal pacchetto, così
/// non va aggiornato quando cambia la versione di .NET.
/// </summary>
public static class RequisitiRuntime
{
    /// <summary>I runtime elencati in un runtimeconfig.json («framework» o «frameworks»). Testo non valido: nessuno.</summary>
    public static IReadOnlyList<RuntimeRichiesto> Leggi(string json)
    {
        var risultato = new List<RuntimeRichiesto>();
        try
        {
            using var documento = JsonDocument.Parse(json, new JsonDocumentOptions { CommentHandling = JsonCommentHandling.Skip, AllowTrailingCommas = true });
            if (!documento.RootElement.TryGetProperty("runtimeOptions", out var opzioni)) return risultato;
            if (opzioni.TryGetProperty("framework", out var uno)) Aggiungi(uno);
            if (opzioni.TryGetProperty("frameworks", out var molti) && molti.ValueKind == JsonValueKind.Array)
                foreach (var f in molti.EnumerateArray()) Aggiungi(f);
        }
        catch (JsonException) { }
        return risultato;

        void Aggiungi(JsonElement f)
        {
            if (f.ValueKind != JsonValueKind.Object) return;
            var nome = f.TryGetProperty("name", out var n) ? n.GetString() : null;
            var versione = f.TryGetProperty("version", out var v) ? v.GetString() : null;
            if (!string.IsNullOrWhiteSpace(nome) && !string.IsNullOrWhiteSpace(versione)) risultato.Add(new RuntimeRichiesto(nome, versione));
        }
    }

    /// <summary>Gli stessi runtime una volta sola, la versione più alta per nome.</summary>
    public static IReadOnlyList<RuntimeRichiesto> Unisci(IEnumerable<RuntimeRichiesto> tutti) =>
        tutti.GroupBy(r => r.Nome, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.Aggregate((a, b) => Versioni.Confronta(a.Versione, b.Versione) >= 0 ? a : b))
            .OrderBy(r => r.Nome, StringComparer.Ordinal).ToList();

    /// <summary>
    /// Vero se in «dotnet\shared\&lt;nome&gt;» c'è una versione dello stesso canale (8.0.x) almeno pari a quella richiesta.
    /// </summary>
    public static bool Installato(RuntimeRichiesto richiesto, string cartellaDotnet)
    {
        var cartella = Path.Combine(cartellaDotnet, "shared", richiesto.Nome);
        if (!Directory.Exists(cartella)) return false;
        return Directory.GetDirectories(cartella).Select(Path.GetFileName).Any(v =>
            v is not null && !v.Contains('-') // le anteprime («9.0.0-preview…») non contano
            && new RuntimeRichiesto(richiesto.Nome, v).Canale == richiesto.Canale
            && Versioni.Confronta(v, richiesto.Versione) >= 0);
    }

    /// <summary>
    /// L'installatore ufficiale di Microsoft per quel runtime: i link aka.ms/dotnet/&lt;canale&gt;/… puntano sempre
    /// all'ultimo aggiornamento. Il runtime desktop contiene anche quello di base. Null se non è un runtime conosciuto.
    /// </summary>
    public static string? IndirizzoDownload(RuntimeRichiesto richiesto, string architettura)
    {
        var prodotto = richiesto.Nome switch
        {
            "Microsoft.NETCore.App" => "dotnet-runtime",
            "Microsoft.WindowsDesktop.App" => "windowsdesktop-runtime",
            "Microsoft.AspNetCore.App" => "aspnetcore-runtime",
            _ => null,
        };
        return prodotto is null ? null : $"https://aka.ms/dotnet/{richiesto.Canale}/{prodotto}-win-{architettura}.exe";
    }

    /// <summary>
    /// Da installare, nell'ordine: il runtime desktop basta anche per quello di base, quindi se servono tutti e due
    /// si scarica solo il primo.
    /// </summary>
    public static IReadOnlyList<RuntimeRichiesto> DaInstallare(IEnumerable<RuntimeRichiesto> mancanti)
    {
        var elenco = Unisci(mancanti);
        var desktop = elenco.FirstOrDefault(r => r.Nome == "Microsoft.WindowsDesktop.App");
        return elenco.Where(r => !(desktop is not null && r.Nome == "Microsoft.NETCore.App" && r.Canale == desktop.Canale)).ToList();
    }

    /// <summary>Codici d'uscita dell'installatore di Microsoft che vogliono dire «fatto» (3010 e 1641: serve il riavvio).</summary>
    public static bool InstallazioneRiuscita(int codice) => codice is 0 or 3010 or 1641;
}
