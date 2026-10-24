using System.Diagnostics;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// Installa o aggiorna WebcamLR: .NET se manca, i file in «C:\Program Files\WebcamLR\App», il collegamento nel menu Start,
/// la voce in «App installate» e, a richiesta, la webcam per le altre app (Windows 11).
/// </summary>
internal static class Installazione
{
    public static int Esegui(Stream flusso, Argomenti scelta)
    {
        var p = Program.Percorsi;
        using var zip = new ZipArchive(flusso, ZipArchiveMode.Read);

        var mancanti = ContenutoPacchetto.Mancanti(zip.Entries.Select(e => e.FullName));
        if (mancanti.Count > 0)
            return Program.Messaggio(scelta, $"Questo installatore è incompleto (manca {string.Join(", ", mancanti)}). Scaricalo di nuovo dal sito.", Program.Fallito);

        // 1. Che cosa c'è già.
        var installata = VersioneInstallata();
        if (!scelta.Silenzioso)
        {
            var v = Program.Versione;
            var domanda = installata switch
            {
                null => $"Installo WebcamLR {v} in:\n{p.CartellaApp}\n\nContinuare?",
                _ when Versioni.Confronta(installata, v) < 0 => $"Aggiorno WebcamLR da {installata} a {v}. Le tue impostazioni e i telefoni fidati restano.\n\nContinuare?",
                _ when Versioni.Confronta(installata, v) == 0 => $"WebcamLR {v} è già installata. La installo di nuovo (ripara i file)?",
                _ => $"Sul PC c'è una versione più recente di WebcamLR ({installata}). Installare comunque la {v}?",
            };
            if (!FunzioniWindows.Conferma(domanda)) return Program.Annullato;
        }

        // 2. .NET, prima di tutto il resto: senza, WebcamLR e la webcam non partono.
        PreparaDotNet(zip, scelta);

        // 3. I file.
        Program.ChiudiWebcamLR();
        var dimensione = Estrai(zip, p.CartellaApp);
        Registro.Scrivi($"Estratti {dimensione / 1024} KB in {p.CartellaApp}");

        // 4. Menu Start e «App installate».
        var hr = FunzioniWindows.CreaCollegamento(p.Collegamento, p.Eseguibile, p.CartellaApp, "Il telefono come webcam per il computer");
        Registro.Scrivi($"Collegamento {p.Collegamento}: 0x{hr:X8}");
        ScriviDisinstallazione(p, dimensione);
        FunzioniWindows.AvvisaShell();

        // 5. La webcam per le altre app.
        var avvisoWebcam = Webcam(p, scelta);

        if (scelta.Silenzioso) return Program.Fatto;
        var fine = "WebcamLR è installata: la trovi nel menu Start."
                   + (avvisoWebcam is null ? "" : $"\n\nWebcam per le altre app: {avvisoWebcam}")
                   + "\n\nAprirla adesso?";
        if (FunzioniWindows.Chiedi(fine)) ApriDaUtente(p.Eseguibile);
        return Program.Fatto;
    }

    private static string? VersioneInstallata()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var chiave = radice.OpenSubKey(DatiProdotto.ChiaveDisinstallazione);
            return chiave?.GetValue("DisplayVersion") as string;
        }
        catch (Exception) { return null; }
    }

    // ——— .NET ———

    private static void PreparaDotNet(ZipArchive zip, Argomenti scelta)
    {
        var richiesti = RequisitiRuntime.Unisci(zip.Entries
            .Where(e => e.FullName.EndsWith(".runtimeconfig.json", StringComparison.OrdinalIgnoreCase))
            .SelectMany(e =>
            {
                using var lettore = new StreamReader(e.Open());
                return RequisitiRuntime.Leggi(lettore.ReadToEnd());
            }));
        var cartellaDotnet = CartellaDotNet();
        var mancanti = RequisitiRuntime.DaInstallare(richiesti.Where(r => !RequisitiRuntime.Installato(r, cartellaDotnet)));
        Registro.Scrivi($".NET richiesto: {string.Join(", ", richiesti)}; da installare: {string.Join(", ", mancanti)} (cartella {cartellaDotnet})");
        if (mancanti.Count == 0) return;

        var nomi = string.Join(" e ", mancanti.Select(r => $".NET {r.Canale}"));
        if (!scelta.Silenzioso && !FunzioniWindows.Chiedi(
                $"WebcamLR ha bisogno di {nomi} di Microsoft (gratuito, circa 30 MB), che su questo PC manca.\n\n"
                + "Lo scarico da Microsoft e lo installo adesso?"))
        {
            FunzioniWindows.Avvisa($"Senza {nomi} WebcamLR non parte. Puoi installarlo dopo da https://dotnet.microsoft.com/download (Runtime per Windows x64).");
            return;
        }
        var architettura = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "arm64" : "x64";
        foreach (var runtime in mancanti)
        {
            var indirizzo = RequisitiRuntime.IndirizzoDownload(runtime, architettura);
            if (indirizzo is null) continue;
            var file = Path.Combine(Path.GetTempPath(), "WebcamLR-installazione", Path.GetFileName(new Uri(indirizzo).AbsolutePath));
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(file)!);
                Registro.Scrivi($"Scarico {indirizzo}");
                using (var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) })
                using (var risposta = client.GetAsync(indirizzo, HttpCompletionOption.ResponseHeadersRead).GetAwaiter().GetResult())
                {
                    risposta.EnsureSuccessStatusCode();
                    using var uscita = File.Create(file);
                    risposta.Content.CopyToAsync(uscita).GetAwaiter().GetResult();
                }
                var codice = Program.Esegui(file, scelta.Silenzioso ? "/install /quiet /norestart" : "/install /passive /norestart");
                if (!RequisitiRuntime.InstallazioneRiuscita(codice))
                    Program.Messaggio(scelta, $"L'installazione di .NET {runtime.Canale} non è riuscita (codice {codice}). Installalo da https://dotnet.microsoft.com/download e riapri WebcamLR.", Program.Fallito);
            }
            catch (Exception errore)
            {
                Program.Messaggio(scelta, $"Non riesco a scaricare .NET {runtime.Canale} ({errore.Message}). Controlla la connessione, oppure installalo da https://dotnet.microsoft.com/download.", Program.Fallito);
            }
            finally { try { File.Delete(file); } catch (Exception) { } }
        }
    }

    /// <summary>«C:\Program Files\dotnet», o «…\dotnet\x64» per un'app x64 su un PC ARM64 (lì .NET x64 sta a parte).</summary>
    private static string CartellaDotNet()
    {
        var cartella = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "dotnet");
        return RuntimeInformation.OSArchitecture == Architecture.Arm64 && RuntimeInformation.ProcessArchitecture == Architecture.X64
            ? Path.Combine(cartella, "x64") : cartella;
    }

    // ——— File ———

    /// <summary>
    /// Estrae il pacchetto in una cartella pulita: la versione vecchia si sposta da parte e si cancella alla fine,
    /// così non restano file di versioni precedenti. Se non si può spostare (un file aperto), si sovrascrive.
    /// Restituisce i byte scritti.
    /// </summary>
    private static long Estrai(ZipArchive zip, string cartella)
    {
        string? vecchia = null;
        if (Directory.Exists(cartella))
        {
            vecchia = $"{cartella}.vecchia-{DateTime.Now:yyyyMMddHHmmss}";
            try { Directory.Move(cartella, vecchia); }
            catch (Exception errore)
            {
                Registro.Scrivi($"La cartella vecchia non si sposta ({errore.Message}): sovrascrivo i file");
                vecchia = null;
            }
        }

        Directory.CreateDirectory(cartella);
        long totale = 0;
        foreach (var voce in zip.Entries)
        {
            if (voce.FullName.EndsWith('/')) continue; // cartella
            var destinazione = ContenutoPacchetto.Destinazione(cartella, voce.FullName)
                ?? throw new InvalidDataException($"Voce non valida nel pacchetto: {voce.FullName}");
            Directory.CreateDirectory(Path.GetDirectoryName(destinazione)!);
            try { voce.ExtractToFile(destinazione, overwrite: true); }
            catch (IOException)
            {
                // Aperto da qualcuno: lo si rinomina (si può anche se è aperto) e si cancella al riavvio.
                var spostato = $"{destinazione}.vecchio-{DateTime.Now:yyyyMMddHHmmss}";
                File.Move(destinazione, spostato);
                FunzioniWindows.MoveFileExW(spostato, null, FunzioniWindows.MOVEFILE_DELAY_UNTIL_REBOOT);
                voce.ExtractToFile(destinazione, overwrite: true);
            }
            totale += voce.Length;
        }

        if (vecchia is not null) CancellaCartella(vecchia);
        return totale;
    }

    /// <summary>Cancella una cartella; quello che è ancora aperto si cancella al riavvio.</summary>
    public static void CancellaCartella(string cartella)
    {
        try { Directory.Delete(cartella, recursive: true); return; }
        catch (Exception) { }
        foreach (var file in Directory.EnumerateFiles(cartella, "*", SearchOption.AllDirectories))
        {
            try { File.Delete(file); }
            catch (Exception) { FunzioniWindows.MoveFileExW(file, null, FunzioniWindows.MOVEFILE_DELAY_UNTIL_REBOOT); }
        }
        foreach (var sotto in Directory.EnumerateDirectories(cartella, "*", SearchOption.AllDirectories).OrderByDescending(d => d.Length).Append(cartella))
        {
            try { Directory.Delete(sotto); }
            catch (Exception) { FunzioniWindows.MoveFileExW(sotto, null, FunzioniWindows.MOVEFILE_DELAY_UNTIL_REBOOT); }
        }
    }

    private static void ScriviDisinstallazione(Percorsi p, long dimensione)
    {
        using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        using var chiave = radice.CreateSubKey(DatiProdotto.ChiaveDisinstallazione, writable: true);
        foreach (var valore in ValoriDisinstallazione.Crea(p, Program.Versione, dimensione, DateTime.Now))
            chiave.SetValue(valore.Nome, valore.Valore, valore.ÈNumero ? RegistryValueKind.DWord : RegistryValueKind.String);
        Registro.Scrivi($"Scritto HKLM\\{DatiProdotto.ChiaveDisinstallazione}");
    }

    // ——— Webcam ———

    /// <summary>
    /// Se la webcam era già installata la si aggiorna da sola (la sorgente nuova deve combaciare con l'app nuova);
    /// altrimenti si chiede. Restituisce un avviso da mostrare, o null.
    /// </summary>
    private static string? Webcam(Percorsi p, Argomenti scelta)
    {
        if (!NomiWebcam.WindowsSupportato(Environment.OSVersion.Version.Build)) return null;
        var giàInstallata = WebcamRegistrata();
        if (!giàInstallata)
        {
            var vuole = scelta.Silenzioso
                ? scelta.Webcam
                : FunzioniWindows.Chiedi("Installo anche la webcam «WebcamLR» per Zoom, Teams, Meet, OBS e le altre app?\n\n"
                                         + "Puoi farlo anche dopo da WebcamLR, nella scheda «Webcam per le altre app».");
            if (!vuole) return null;
        }
        var codice = Program.Esegui(p.InstallatoreWebcam, "installa");
        return codice == CodiciInstallazione.Riuscita
            ? (giàInstallata ? null : "installata. Chiudi e riapri le app di chiamata già aperte.")
            : CodiciInstallazione.Descrivi(codice);
    }

    public static bool WebcamRegistrata()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var server = radice.OpenSubKey($@"SOFTWARE\Classes\CLSID\{NomiWebcam.ClsidTraGraffe}\InprocServer32");
            return server is not null;
        }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// Apre WebcamLR come utente normale, non come amministratore (l'installatore lo è): passando da Esplora risorse,
    /// che gira sempre senza privilegi.
    /// </summary>
    private static void ApriDaUtente(string eseguibile)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", ValoriDisinstallazione.Tra(eseguibile)) { UseShellExecute = false }); }
        catch (Exception errore) { Registro.Scrivi($"Non apro WebcamLR: {errore.Message}"); }
    }
}
