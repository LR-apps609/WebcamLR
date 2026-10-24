namespace WebcamLR.Setup;

/// <summary>Un valore da scrivere nella chiave di disinstallazione: testo (REG_SZ) o numero (REG_DWORD).</summary>
public sealed record ValoreRegistro(string Nome, object Valore)
{
    public bool ÈNumero => Valore is int;
}

/// <summary>
/// I valori della chiave <see cref="DatiProdotto.ChiaveDisinstallazione"/>, quelli che Windows legge per mostrare
/// WebcamLR in Impostazioni → App → App installate e per disinstallarla (documentazione «Uninstall Registry Key»).
/// </summary>
public static class ValoriDisinstallazione
{
    public const string ArgomentoDisinstalla = "/disinstalla";
    public const string ArgomentoSilenzioso = "/silenzioso";

    /// <param name="dimensioneByte">Lo spazio occupato dall'app: Windows lo vuole in KB (EstimatedSize).</param>
    /// <param name="data">Il giorno dell'installazione: Windows lo vuole come «aaaammgg» (InstallDate).</param>
    public static IReadOnlyList<ValoreRegistro> Crea(Percorsi percorsi, string versione, long dimensioneByte, DateTime data)
    {
        var disinstallatore = Tra(percorsi.Disinstallatore);
        var (maggiore, minore) = Parti(versione);
        return new List<ValoreRegistro>
        {
            new("DisplayName", DatiProdotto.Nome),
            new("DisplayVersion", versione),
            new("Publisher", DatiProdotto.Editore),
            new("DisplayIcon", percorsi.Eseguibile + ",0"),
            new("InstallLocation", percorsi.CartellaApp),
            new("UninstallString", $"{disinstallatore} {ArgomentoDisinstalla}"),
            new("QuietUninstallString", $"{disinstallatore} {ArgomentoDisinstalla} {ArgomentoSilenzioso}"),
            new("URLInfoAbout", DatiProdotto.Sito),
            new("HelpLink", DatiProdotto.Sito + "aiuto.html"),
            new("InstallDate", data.ToString("yyyyMMdd", System.Globalization.CultureInfo.InvariantCulture)),
            new("EstimatedSize", (int)Math.Clamp((dimensioneByte + 1023) / 1024, 0, int.MaxValue)),
            new("VersionMajor", maggiore),
            new("VersionMinor", minore),
            // Niente «Modifica» né «Ripristina»: per riparare si riavvia l'installatore.
            new("NoModify", 1),
            new("NoRepair", 1),
        };
    }

    /// <summary>Tra virgolette: il percorso contiene spazi («Program Files», «Disinstalla WebcamLR.exe»).</summary>
    public static string Tra(string percorso) => $"\"{percorso}\"";

    private static (int, int) Parti(string versione)
    {
        var parti = versione.Split('.');
        int Numero(int i) => i < parti.Length && int.TryParse(parti[i], out var n) ? n : 0;
        return (Numero(0), Numero(1));
    }
}
