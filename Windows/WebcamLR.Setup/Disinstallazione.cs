using System.Diagnostics;
using Microsoft.Win32;
using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// Toglie WebcamLR: prima, con il permesso dell'amministratore, la webcam (se c'è) e la regola del firewall; poi il
/// collegamento, la voce in «App installate» e i file. Le impostazioni dell'utente (cartella AppData\Roaming) e i
/// registri restano: una reinstallazione li ritrova. La fotocamera vera del PC non si tocca mai.
/// </summary>
internal static class Disinstallazione
{
    public static int Esegui(Argomenti scelta)
    {
        var p = Program.Percorsi;
        if (!scelta.Silenzioso)
        {
            var domanda = Testi.S("Disinstallo WebcamLR da questo PC, con la webcam per le altre app?",
                "Uninstall WebcamLR from this PC, together with the webcam for other apps?");
            // Se WebcamLR è aperta (1.7), prima lo si dice: la chiamata perde il video, la registrazione si salva.
            var aperta = Program.TestoAppAperta();
            if (!FunzioniWindows.Conferma(aperta is null ? domanda : $"{aperta}\n\n{domanda}")) return Program.Annullato;
        }

        Program.ChiudiWebcamLR();

        // 1. Webcam e firewall: vanno tolti finché c'è il loro installatore, che sta nella cartella dell'app.
        string? avviso = null;
        if (File.Exists(p.InstallatoreWebcam))
        {
            var codice = Program.EseguiDaAmministratore(p.InstallatoreWebcam, $"disinstalla {ValoriDisinstallazione.Tra(p.Eseguibile)}");
            if (codice == CodiciInstallazione.Annullata && Installazione.WebcamRegistrata())
                avviso = Testi.S("La webcam «WebcamLR» è rimasta, perché Windows non ha avuto il permesso di toglierla. "
                                 + "Reinstalla WebcamLR e disinstallala di nuovo rispondendo «Sì» alla richiesta di Windows.",
                                 "The “WebcamLR” webcam is still there, because Windows didn’t get permission to remove it. "
                                 + "Reinstall WebcamLR and uninstall it again, answering “Yes” when Windows asks.");
            else if (codice != CodiciInstallazione.Riuscita && codice != CodiciInstallazione.Annullata)
                Registro.Scrivi($"Webcam e firewall: {CodiciInstallazione.Descrivi(codice, LinguaAttesa.Italiano)}");
        }

        // 2. Menu Start e «App installate».
        try { File.Delete(p.Collegamento); } catch (Exception errore) { Registro.Scrivi($"Collegamento: {errore.Message}"); }
        try { Registry.CurrentUser.DeleteSubKeyTree(DatiProdotto.ChiaveDisinstallazione, throwOnMissingSubKey: false); }
        catch (Exception errore) { Registro.Scrivi($"Registro: {errore.Message}"); }
        FunzioniWindows.AvvisaShell();

        // 3. I file. Questo programma è nella cartella da cancellare e non può cancellare sé stesso mentre gira:
        //    si cancella tutto il resto, poi un «cmd» staccato aspetta due secondi che questo processo sia chiuso
        //    e toglie la cartella.
        var questo = Environment.ProcessPath;
        var daQui = questo is not null && Path.GetDirectoryName(questo)!.Equals(p.CartellaApp.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        if (Directory.Exists(p.CartellaApp))
        {
            foreach (var file in Directory.EnumerateFiles(p.CartellaApp, "*", SearchOption.AllDirectories))
            {
                if (daQui && string.Equals(file, questo, StringComparison.OrdinalIgnoreCase)) continue;
                try { File.Delete(file); } catch (Exception) { }
            }
            if (daQui)
            {
                var comando = $"/d /c timeout /t 2 /nobreak >nul & rd /s /q \"{p.CartellaApp}\"";
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
            }
        }

        return Program.Messaggio(scelta, Testi.S("WebcamLR è stata disinstallata.", "WebcamLR has been uninstalled.")
                                         + (avviso is null ? "" : $"\n\n{avviso}"), Program.Fatto);
    }
}
