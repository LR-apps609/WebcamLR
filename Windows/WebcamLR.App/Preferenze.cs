namespace WebcamLR;

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
