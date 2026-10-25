using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// «WebcamLR-Setup.exe» (con il pacchetto dell'app dentro) installa; «Disinstalla WebcamLR.exe» (lo stesso programma
/// senza pacchetto, accanto all'app) disinstalla. Argomenti in <see cref="Argomenti"/>.
/// Tutti e due girano come l'utente, senza amministratore: l'app va nella cartella dell'utente. Il permesso
/// dell'amministratore lo chiede una volta sola WebcamLR.Webcam.Installa.exe, per la webcam e il firewall.
/// Codice d'uscita: 0 fatto, 1 annullato, 2 errore. Registro in «%LOCALAPPDATA%\WebcamLR\Installazione.txt».
/// </summary>
internal static class Program
{
    public const int Fatto = 0, Annullato = 1, Fallito = 2;

    public static string Versione { get; } =
        typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0]
        ?? typeof(Program).Assembly.GetName().Version?.ToString(2) ?? "?";

    public static Percorsi Percorsi { get; } = new(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        Environment.GetFolderPath(Environment.SpecialFolder.Programs),
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles));

    [STAThread]
    private static int Main(string[] argomenti)
    {
        using var pacchetto = typeof(Program).Assembly.GetManifestResourceStream(DatiProdotto.RisorsaPacchetto);
        var scelta = Argomenti.Leggi(argomenti, haPacchetto: pacchetto is not null);
        Registro.Scrivi($"— {DatiProdotto.Nome} {Versione} · {Environment.ProcessPath} {string.Join(' ', argomenti)} (Windows {Environment.OSVersion.Version})");
        try
        {
            var codice = scelta.Modalità switch
            {
                Modalità.Installa when pacchetto is not null => Installazione.Esegui(pacchetto, scelta),
                Modalità.Installa => Messaggio(scelta, "Questo è il disinstallatore di WebcamLR: per installare scarica «WebcamLR-Setup.exe» dal sito.", Fallito),
                _ => Disinstallazione.Esegui(scelta),
            };
            Registro.Scrivi($"Esito: {codice}");
            return codice;
        }
        catch (Exception errore)
        {
            Registro.Scrivi($"Errore: {errore}");
            return Messaggio(scelta, $"Qualcosa non ha funzionato: {errore.Message}\n\nIl registro è in {Percorsi.Registro}: mandalo a chi ti aiuta.", Fallito);
        }
    }

    public static int Messaggio(Argomenti scelta, string testo, int codice)
    {
        Registro.Scrivi(testo);
        if (!scelta.Silenzioso)
        {
            if (codice == Fatto) FunzioniWindows.Informa(testo); else FunzioniWindows.Errore(testo);
        }
        return codice;
    }

    /// <summary>
    /// Chiude WebcamLR se è aperta da questa cartella (anche solo con l'icona accanto all'orologio), altrimenti
    /// i file non si possono sostituire. Prima con gentilezza, poi a forza dopo 5 secondi.
    /// </summary>
    public static void ChiudiWebcamLR()
    {
        foreach (var processo in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(DatiProdotto.Eseguibile)))
        {
            using (processo)
            {
                try
                {
                    var percorso = processo.MainModule?.FileName;
                    if (percorso is not null && !percorso.StartsWith(Percorsi.CartellaApp, StringComparison.OrdinalIgnoreCase)) continue;
                    Registro.Scrivi($"Chiudo WebcamLR (processo {processo.Id})");
                    if (!processo.CloseMainWindow() || !processo.WaitForExit(5000)) processo.Kill(entireProcessTree: true);
                    processo.WaitForExit(5000);
                }
                catch (Exception errore) { Registro.Scrivi($"Non chiudo il processo {processo.Id}: {errore.Message}"); }
            }
        }
    }

    /// <summary>Lancia un programma e ne aspetta il codice d'uscita (-1 se non parte).</summary>
    public static int Esegui(string file, string argomenti)
    {
        try
        {
            using var processo = Process.Start(new ProcessStartInfo(file, argomenti) { UseShellExecute = false, CreateNoWindow = true });
            if (processo is null) return -1;
            processo.WaitForExit();
            Registro.Scrivi($"{Path.GetFileName(file)} {argomenti}: {processo.ExitCode}");
            return processo.ExitCode;
        }
        catch (Exception errore)
        {
            Registro.Scrivi($"{Path.GetFileName(file)} non parte: {errore.Message}");
            return -1;
        }
    }

    /// <summary>
    /// Lancia un programma chiedendo il permesso dell'amministratore (la finestra blu di Windows) e ne aspetta il
    /// codice d'uscita. <see cref="CodiciInstallazione.Annullata"/> se l'utente dice no; -1 se non parte.
    /// </summary>
    public static int EseguiDaAmministratore(string file, string argomenti)
    {
        try
        {
            using var processo = Process.Start(new ProcessStartInfo(file, argomenti)
            {
                UseShellExecute = true,
                Verb = "runas",
                WorkingDirectory = Path.GetDirectoryName(file)!,
            });
            if (processo is null) return -1;
            processo.WaitForExit();
            Registro.Scrivi($"{Path.GetFileName(file)} {argomenti} (amministratore): {processo.ExitCode}");
            return processo.ExitCode;
        }
        catch (Win32Exception errore) when (errore.NativeErrorCode == CodiciInstallazione.Annullata)
        {
            Registro.Scrivi($"{Path.GetFileName(file)} {argomenti}: permesso negato dall'utente");
            return CodiciInstallazione.Annullata;
        }
        catch (Exception errore)
        {
            Registro.Scrivi($"{Path.GetFileName(file)} non parte: {errore.Message}");
            return -1;
        }
    }
}

/// <summary>«%LOCALAPPDATA%\WebcamLR\Installazione.txt», accanto al registro del filtro DirectShow.</summary>
internal static class Registro
{
    public static void Scrivi(string testo)
    {
        try
        {
            var file = Program.Percorsi.Registro;
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.AppendAllText(file, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {testo}{Environment.NewLine}");
        }
        catch (Exception) { }
    }
}
