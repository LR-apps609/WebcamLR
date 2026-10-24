using System.Diagnostics;
using Microsoft.Win32;
using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// Toglie WebcamLR: prima la webcam (se c'è), poi il collegamento, la voce in «App installate» e i file.
/// Le impostazioni dell'utente (cartella AppData) e i registri in ProgramData restano: una reinstallazione li ritrova.
/// </summary>
internal static class Disinstallazione
{
    public static int Esegui(Argomenti scelta)
    {
        var p = Program.Percorsi;
        if (!scelta.Silenzioso && !FunzioniWindows.Conferma("Disinstallo WebcamLR da questo PC, con la webcam per le altre app?"))
            return Program.Annullato;

        Program.ChiudiWebcamLR();

        // 1. La webcam: va tolta finché c'è il suo installatore, che sta nella cartella dell'app.
        if (Installazione.WebcamRegistrata() && File.Exists(p.InstallatoreWebcam))
        {
            var codice = Program.Esegui(p.InstallatoreWebcam, "rimuovi");
            if (codice != CodiciInstallazione.Riuscita) Registro.Scrivi($"Webcam: {CodiciInstallazione.Descrivi(codice)}");
        }

        // 2. Menu Start e «App installate».
        try { File.Delete(p.Collegamento); } catch (Exception errore) { Registro.Scrivi($"Collegamento: {errore.Message}"); }
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            radice.DeleteSubKeyTree(DatiProdotto.ChiaveDisinstallazione, throwOnMissingSubKey: false);
        }
        catch (Exception errore) { Registro.Scrivi($"Registro: {errore.Message}"); }
        FunzioniWindows.AvvisaShell();

        // 3. I file. Questo programma è nella cartella da cancellare e non può cancellare sé stesso mentre gira:
        //    si cancella tutto il resto, poi un «cmd» staccato aspetta due secondi che questo processo sia chiuso
        //    e toglie la cartella. Se non ci riesce, quello che resta si cancella al riavvio.
        var questo = Environment.ProcessPath;
        var daQui = questo is not null && Path.GetDirectoryName(questo)!.Equals(p.CartellaApp.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        if (Directory.Exists(p.CartellaApp))
        {
            foreach (var file in Directory.EnumerateFiles(p.CartellaApp, "*", SearchOption.AllDirectories))
            {
                if (daQui && string.Equals(file, questo, StringComparison.OrdinalIgnoreCase)) continue;
                try { File.Delete(file); }
                catch (Exception) { FunzioniWindows.MoveFileExW(file, null, FunzioniWindows.MOVEFILE_DELAY_UNTIL_REBOOT); }
            }
            if (daQui)
            {
                FunzioniWindows.MoveFileExW(questo!, null, FunzioniWindows.MOVEFILE_DELAY_UNTIL_REBOOT);
                var comando = $"/d /c timeout /t 2 /nobreak >nul & rd /s /q \"{p.CartellaApp}\" & rd \"{p.CartellaProdotto}\"";
                try
                {
                    Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "cmd.exe"), comando)
                    {
                        UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Path.GetTempPath(),
                    });
                }
                catch (Exception errore) { Registro.Scrivi($"Pulizia finale: {errore.Message}"); }
            }
            else
            {
                Installazione.CancellaCartella(p.CartellaApp);
                try { if (!Directory.EnumerateFileSystemEntries(p.CartellaProdotto).Any()) Directory.Delete(p.CartellaProdotto); } catch (Exception) { }
            }
        }

        return Program.Messaggio(scelta, "WebcamLR è stata disinstallata.", Program.Fatto);
    }
}
