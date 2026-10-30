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
                Modalità.Installa => Messaggio(scelta, Testi.S(
                    "Questo è il disinstallatore di WebcamLR: per installare scarica «WebcamLR-Setup.exe» dal sito.",
                    "This is the WebcamLR uninstaller: to install, download “WebcamLR-Setup.exe” from the website."), Fallito),
                _ => Disinstallazione.Esegui(scelta),
            };
            Registro.Scrivi($"Esito: {codice}");
            return codice;
        }
        catch (Exception errore)
        {
            Registro.Scrivi($"Errore: {errore}");
            return Messaggio(scelta, Testi.S(
                $"Qualcosa non ha funzionato: {errore.Message}\n\nIl registro è in {Percorsi.Registro}: mandalo a chi ti aiuta.",
                $"Something went wrong: {errore.Message}\n\nThe log is in {Percorsi.Registro}: send it to whoever is helping you."), Fallito);
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

    /// <summary>Le copie di WebcamLR aperte da questa cartella (anche solo con l'icona accanto all'orologio).</summary>
    private static List<(Process Processo, string? Percorso)> ProcessiWebcamLR()
    {
        var aperti = new List<(Process, string?)>();
        foreach (var processo in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(DatiProdotto.Eseguibile)))
        {
            string? percorso = null;
            try { percorso = processo.MainModule?.FileName; } catch (Exception) { }
            if (ChiusuraApp.DaChiudere(percorso, Percorsi.CartellaApp)) aperti.Add((processo, percorso));
            else processo.Dispose();
        }
        return aperti;
    }

    /// <summary>
    /// La riga da aggiungere alla domanda iniziale se WebcamLR è aperta (windows.md 1.7), o null. Se un'app usa il
    /// video lo dice la memoria condivisa della webcam; se non si legge, la frase lo dice come possibilità.
    /// </summary>
    public static string? TestoAppAperta()
    {
        var aperti = ProcessiWebcamLR();
        var aperta = aperti.Count > 0;
        foreach (var (processo, _) in aperti) processo.Dispose();
        var avviso = ChiusuraApp.Avviso(aperta, aperta && Installazione.WebcamRegistrata(), aperta ? VideoInUso() : null);
        Registro.Scrivi($"WebcamLR aperta: {avviso}");
        var registrazione = Testi.S(" Una registrazione in corso si chiude e si salva.", " A recording in progress is closed and saved.");
        return avviso switch
        {
            AvvisoAppAperta.ApertaVideoInUso => Testi.S(
                "WebcamLR è aperta e un'app sta usando il video: la chiudo prima di continuare e la chiamata perderà il video per qualche secondo.",
                "WebcamLR is open and an app is using the video: it will be closed first and the call will lose the video for a few seconds.") + registrazione,
            AvvisoAppAperta.ApertaForseVideoInUso => Testi.S(
                "WebcamLR è aperta: la chiudo prima di continuare. Se un'app sta usando il video, la chiamata lo perderà per qualche secondo.",
                "WebcamLR is open: it will be closed first. If an app is using the video, the call will lose it for a few seconds.") + registrazione,
            AvvisoAppAperta.Aperta => Testi.S("WebcamLR è aperta: la chiudo prima di continuare.", "WebcamLR is open: it will be closed first.") + registrazione,
            _ => null,
        };
    }

    /// <summary>
    /// Vero se un'app sta usando la webcam «WebcamLR» adesso, dal battito che la webcam scrive nella memoria condivisa
    /// (Windows 11: «Global\», Windows 10: «Local\»); null se la memoria non si apre.
    /// </summary>
    private static bool? VideoInUso()
    {
        try
        {
            using var memoria = MemoriaCondivisa.Apri() ?? MemoriaCondivisa.Apri(NomiAnello.Locale);
            return memoria?.Anello.InUso(Environment.TickCount64);
        }
        catch (Exception) { return null; }
    }

    /// <summary>
    /// Chiude WebcamLR se è aperta da questa cartella, altrimenti i file non si possono sostituire. Prima le chiede di
    /// uscire con «WebcamLR.exe --esci» (la copia aperta chiude e salva la registrazione ed esce, senza domande), poi
    /// aspetta fino a 15 secondi; solo se non è uscita la chiude a forza (ChiusuraApp).
    /// </summary>
    public static void ChiudiWebcamLR()
    {
        var aperti = ProcessiWebcamLR();
        if (aperti.Count == 0) return;
        try
        {
            Registro.Scrivi($"Chiudo WebcamLR (processi {string.Join(", ", aperti.Select(a => a.Processo.Id))})");
            var eseguibile = aperti.Select(a => a.Percorso).FirstOrDefault(p => p is not null && File.Exists(p)) ?? Percorsi.Eseguibile;
            var richiesta = false;
            var orologio = Stopwatch.StartNew();
            while (true)
            {
                var uscita = aperti.All(a => Uscito(a.Processo));
                switch (ChiusuraApp.Prossimo(uscita, richiesta, orologio.Elapsed))
                {
                    case PassoChiusura.Fatto:
                        Registro.Scrivi($"WebcamLR è uscita da sola in {orologio.Elapsed.TotalSeconds:0.0} s");
                        return;
                    case PassoChiusura.ChiediUscita:
                        // Anche se la richiesta non parte si aspettano i 15 secondi (1.7: mai a forza prima): l'utente
                        // può ancora uscire da sé, e la registrazione si salva.
                        if (!ChiediUscita(eseguibile)) Registro.Scrivi("Richiesta non mandata: aspetto comunque prima di chiudere a forza");
                        richiesta = true;
                        orologio.Restart();
                        break;
                    case PassoChiusura.Aspetta:
                        Thread.Sleep(200);
                        break;
                    case PassoChiusura.Forza:
                        Registro.Scrivi($"WebcamLR non è uscita in {ChiusuraApp.AttesaUscita.TotalSeconds:0} s: la chiudo a forza");
                        Forza(aperti);
                        return;
                }
            }
        }
        finally
        {
            foreach (var (processo, _) in aperti) processo.Dispose();
        }
    }

    private static bool Uscito(Process processo)
    {
        try { return processo.WaitForExit(0); }
        catch (Exception) { return true; }
    }

    /// <summary>Lancia «WebcamLR.exe --esci» senza aspettarlo: la copia nuova passa la richiesta a quella aperta ed esce.</summary>
    private static bool ChiediUscita(string eseguibile)
    {
        try
        {
            using var processo = Process.Start(new ProcessStartInfo(eseguibile, ChiusuraApp.ArgomentoEsci)
            {
                UseShellExecute = false,
                WorkingDirectory = Path.GetDirectoryName(eseguibile)!,
            });
            Registro.Scrivi($"Chiesto a WebcamLR di uscire ({eseguibile} {ChiusuraApp.ArgomentoEsci})");
            return processo is not null;
        }
        catch (Exception errore)
        {
            Registro.Scrivi($"Non riesco a chiedere a WebcamLR di uscire: {errore.Message}");
            return false;
        }
    }

    private static void Forza(List<(Process Processo, string? Percorso)> aperti)
    {
        foreach (var (processo, _) in aperti)
        {
            try
            {
                if (Uscito(processo)) continue;
                processo.Kill(entireProcessTree: true);
                processo.WaitForExit((int)ChiusuraApp.AttesaDopoForza.TotalMilliseconds);
            }
            catch (Exception errore) { Registro.Scrivi($"Non chiudo il processo {processo.Id}: {errore.Message}"); }
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
