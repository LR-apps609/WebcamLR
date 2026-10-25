namespace WebcamLR.Setup;

public enum Modalità
{
    Installa,
    Disinstalla,
}

/// <summary>
/// Cosa deve fare l'installatore. Senza argomenti installa (se ha il pacchetto) o disinstalla (se è il disinstallatore
/// copiato accanto all'app). «/disinstalla» lo scrive Windows da UninstallString; «/silenzioso» non fa domande
/// (per gli amministratori di rete: con la webcam solo se c'è anche «/webcam»).
/// Accetta anche i nomi inglesi più comuni (/uninstall, /quiet, /S), che gli strumenti di distribuzione usano da soli.
/// </summary>
public sealed record Argomenti(Modalità Modalità, bool Silenzioso, bool Webcam)
{
    public static Argomenti Leggi(IEnumerable<string> argomenti, bool haPacchetto)
    {
        var modalità = haPacchetto ? Modalità.Installa : Modalità.Disinstalla;
        bool silenzioso = false, webcam = false;
        foreach (var grezzo in argomenti)
        {
            var a = grezzo.Trim().TrimStart('/', '-').ToLowerInvariant();
            switch (a)
            {
                case "disinstalla" or "uninstall" or "x": modalità = Modalità.Disinstalla; break;
                case "installa" or "install" or "i": modalità = Modalità.Installa; break;
                case "silenzioso" or "quiet" or "q" or "s" or "silent": silenzioso = true; break;
                case "webcam": webcam = true; break;
            }
        }
        return new Argomenti(modalità, silenzioso, webcam);
    }
}

/// <summary>Confronto tra versioni «1.0», «1.0.1», «1.10»: numero per numero, non come testo.</summary>
public static class Versioni
{
    public static int Confronta(string? a, string? b) => Leggi(a).CompareTo(Leggi(b));

    private static Version Leggi(string? testo)
    {
        var parti = (testo ?? "").Split('.', StringSplitOptions.TrimEntries)
            .Select(p => int.TryParse(p, out var n) && n >= 0 ? n : 0).Concat(Enumerable.Repeat(0, 4)).Take(4).ToArray();
        return new Version(parti[0], parti[1], parti[2], parti[3]);
    }
}
