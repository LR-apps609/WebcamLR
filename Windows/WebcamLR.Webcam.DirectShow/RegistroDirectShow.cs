namespace WebcamLR.Webcam.DirectShow;

/// <summary>
/// Registro del filtro in «%LOCALAPPDATA%\WebcamLR\Registro webcam DirectShow.txt», accanto agli altri file
/// dell'app: il filtro gira dentro Zoom, Chrome, OBS…, come l'utente, e non può scrivere in «C:\ProgramData» senza
/// permessi in più. Ogni riga dice in quale app (processo) gira. Mai più di 256 KB; un errore di scrittura non deve
/// mai disturbare l'app che usa la webcam.
/// </summary>
internal static class RegistroDirectShow
{
    private const long Massimo = 256 * 1024;
    private static readonly object Blocco = new();
    private static readonly string Processo = NomeProcesso();

    public static string Percorso { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WebcamLR", NomiWebcam.FileRegistroDirectShow);

    public static void Scrivi(string testo)
    {
        try
        {
            lock (Blocco)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(Percorso)!);
                var file = new FileInfo(Percorso);
                if (file.Exists && file.Length > Massimo) file.Delete();
                File.AppendAllText(Percorso,
                    $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{Processo} {Environment.ProcessId}, {IntPtr.Size * 8} bit] {testo}{Environment.NewLine}");
            }
        }
        catch (Exception) { }
    }

    private static string NomeProcesso()
    {
        try { return Path.GetFileName(Environment.ProcessPath) ?? "?"; }
        catch (Exception) { return "?"; }
    }
}
