using System.Diagnostics;
using Microsoft.Win32;
using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// Toglie WebcamLR: prima, con il permesso dell'amministratore, la webcam (se c'è) e la regola del firewall; poi il
/// collegamento, la voce in «App installate» e i file. Le impostazioni dell'utente (cartella AppData\Roaming) e i
/// registri restano: una reinstallazione li ritrova. La fotocamera vera del PC non si tocca mai.
/// Le finestre (beta 4): le stesse Task Dialog dell'installatore (FinestraDomanda) al posto delle due MessageBox. Prima
/// «Disinstallare WebcamLR?» con «Disinstalla» (lo scudo se Windows chiederà il permesso) e «Annulla» predefinito; alla
/// fine «WebcamLR è stata disinstallata» con «Chiudi» e, se la webcam è rimasta, l'avviso nel piede. Le regole stanno in
/// PianoDisinstallazione (Setup.Logica).
/// </summary>
internal static class Disinstallazione
{
    public static int Esegui(Argomenti scelta)
    {
        var p = Program.Percorsi;
        var titolo = Testi.S($"Disinstallazione di {DatiProdotto.Nome}", $"{DatiProdotto.Nome} Uninstall");
        if (!scelta.Silenzioso)
        {
            var righe = new List<string>
            {
                Testi.S("Tolgo WebcamLR da questo PC, con la webcam per le altre app.",
                    "WebcamLR will be removed from this PC, together with the webcam for other apps."),
                Restano,
            };
            // Se WebcamLR è aperta (1.7), lo si dice: la chiamata perde il video, la registrazione si salva.
            if (Program.TestoAppAperta() is { } aperta) righe.Add(aperta);
            var risposta = FinestraDomanda.Chiedi(
                Testi.S("Disinstallare WebcamLR?", "Uninstall WebcamLR?"), string.Join("\n\n", righe),
                Testi.S("Disinstalla", "Uninstall"), Testi.S("Annulla", "Cancel"),
                scudoSulPrimo: PianoDisinstallazione.ServeAmministratore(File.Exists(p.InstallatoreWebcam)),
                titolo: titolo, predefinitoSecondo: PianoDisinstallazione.PredefinitoAnnulla);
            if (!risposta.Primo) return Program.Annullato;
        }

        Program.ChiudiWebcamLR();

        // 1. Webcam e firewall: vanno tolti finché c'è il loro installatore, che sta nella cartella dell'app.
        int? codice = null;
        if (File.Exists(p.InstallatoreWebcam))
            codice = Program.EseguiDaAmministratore(p.InstallatoreWebcam, $"disinstalla {ValoriDisinstallazione.Tra(p.Eseguibile)}");
        var esito = PianoDisinstallazione.Esito(codice, codice == CodiciInstallazione.Annullata && Installazione.WebcamRegistrata());
        string? avviso = null;
        if (esito == EsitoDisinstallazione.WebcamRimasta)
            avviso = Testi.S("La webcam «WebcamLR» è rimasta, perché Windows non ha avuto il permesso di toglierla. "
                             + "Reinstalla WebcamLR e disinstallala di nuovo rispondendo «Sì» alla richiesta di Windows.",
                             "The “WebcamLR” webcam is still there, because Windows didn’t get permission to remove it. "
                             + "Reinstall WebcamLR and uninstall it again, answering “Yes” when Windows asks.");
        else if (esito == EsitoDisinstallazione.Problema)
            Registro.Scrivi($"Webcam e firewall: {CodiciInstallazione.Descrivi(codice!.Value, LinguaAttesa.Italiano)}");

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

        var fatto = Testi.S("WebcamLR è stata disinstallata", "WebcamLR has been uninstalled");
        Registro.Scrivi(avviso is null ? fatto : $"{fatto}. {avviso}");
        if (!scelta.Silenzioso)
            FinestraDomanda.Informa(fatto, Restano, Testi.S("Chiudi", "Close"),
                piede: avviso, iconaPiede: FinestraDomanda.Piede.Avviso, titolo: titolo);
        return Program.Fatto;
    }

    /// <summary>Che cosa resta dopo: le impostazioni (AppData\Roaming), i telefoni fidati e le registrazioni (nei Video).</summary>
    private static string Restano => Testi.S("Le tue impostazioni, i telefoni fidati e le registrazioni restano.",
        "Your settings, trusted phones and recordings are kept.");
}
