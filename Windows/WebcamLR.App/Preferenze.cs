using System.Text.Json;

namespace WebcamLR;

/// <summary>I comandi della fotocamera salvati per nome (funzione 23), come sul Mac.</summary>
public sealed record ProfiloFotocamera(string? Obiettivo, double Zoom, bool Torcia, double Esposizione,
    bool BiancoAutomatico, double Bianco, bool EsposizioneManuale, double Iso, int Tempo);

/// <summary>
/// Preferenze della finestra, in %LOCALAPPDATA%\WebcamLR: l'app non è pacchettizzata,
/// quindi ApplicationData non c'è. Un file per valore, così non serve un formato.
/// </summary>
public static class Preferenze
{
    private static readonly string Cartella =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WebcamLR");

    public static bool Specchia
    {
        get => Leggi("specchia") == "1";
        set => Scrivi("specchia", value ? "1" : "0");
    }

    public static Dictionary<string, ProfiloFotocamera> Profili
    {
        get
        {
            var testo = Leggi("profili.json");
            if (testo is null) return [];
            try { return JsonSerializer.Deserialize<Dictionary<string, ProfiloFotocamera>>(testo) ?? []; }
            catch (JsonException) { return []; }
        }
        set => Scrivi("profili.json", JsonSerializer.Serialize(value));
    }

    private static string? Leggi(string nome)
    {
        try { return File.ReadAllText(Path.Combine(Cartella, nome)).Trim(); }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    private static void Scrivi(string nome, string valore)
    {
        try
        {
            Directory.CreateDirectory(Cartella);
            File.WriteAllText(Path.Combine(Cartella, nome), valore);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
