namespace WebcamLR.Webcam;

/// <summary>
/// Registro della sorgente in «C:\ProgramData\WebcamLR\Registro webcam.txt»: la sorgente gira dentro Frame Server,
/// senza finestra, e questo è l'unico modo per capire cosa succede sul PC di Ledion. Mai più di 256 KB: oltre,
/// si ricomincia. Un errore di scrittura non deve mai disturbare la webcam.
/// </summary>
internal static class RegistroWebcam
{
    private const long Massimo = 256 * 1024;
    private static readonly object Blocco = new();

    public static string Percorso { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        NomiWebcam.SottocartellaRegistro, NomiWebcam.FileRegistro);

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
                    $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{Environment.ProcessId}] {testo}{Environment.NewLine}");
            }
        }
        catch (Exception) { }
    }
}
