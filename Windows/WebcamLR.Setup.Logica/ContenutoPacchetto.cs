using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// Il pacchetto (lo zip dentro l'installatore) ha quello che serve? Lo controlla la build, prima di includerlo,
/// e l'installatore, prima di toccare il PC. I nomi delle voci usano «/» come nello zip.
/// </summary>
public static class ContenutoPacchetto
{
    public static readonly IReadOnlyList<string> Obbligatori = new[]
    {
        DatiProdotto.Eseguibile,
        DatiProdotto.Disinstallatore,
        "WebcamLR.runtimeconfig.json",
        $"{NomiWebcam.CartellaAccantoAllApp}/{NomiWebcam.FileInstallatore}",
        $"{NomiWebcam.CartellaAccantoAllApp}/{NomiWebcam.FileSorgente}",
        $"{NomiWebcam.CartellaAccantoAllApp}/{NomiWebcam.FileComHost}",
    };

    /// <summary>Le voci obbligatorie che mancano (vuoto: va bene).</summary>
    public static IReadOnlyList<string> Mancanti(IEnumerable<string> voci)
    {
        var presenti = new HashSet<string>(voci.Select(Normalizza), StringComparer.OrdinalIgnoreCase);
        return Obbligatori.Where(o => !presenti.Contains(o)).ToList();
    }

    /// <summary>
    /// Il percorso dove estrarre una voce, o null se la voce uscirebbe dalla cartella («..\», percorsi assoluti):
    /// un pacchetto rovinato non deve poter scrivere altrove in Programmi.
    /// </summary>
    public static string? Destinazione(string cartella, string voce)
    {
        var relativa = Normalizza(voce);
        if (relativa.Length == 0 || relativa.StartsWith('/') || relativa.Contains(':')) return null;
        var parti = relativa.Split('/');
        if (parti.Any(p => p is ".." or "." || p.Length == 0)) return null;
        return cartella.TrimEnd('\\', '/') + "\\" + string.Join('\\', parti);
    }

    public static string Normalizza(string voce) => voce.Replace('\\', '/');
}
