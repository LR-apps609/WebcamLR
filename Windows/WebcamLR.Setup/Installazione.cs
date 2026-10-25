using System.Diagnostics;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// Installa o aggiorna WebcamLR per l'utente: .NET se manca, i file in «%LOCALAPPDATA%\Programs\WebcamLR», il
/// collegamento nel menu Start, la voce in «App installate» (HKCU), poi con un solo permesso dell'amministratore la
/// regola del firewall per le reti private e, a richiesta, la webcam per le altre app (Windows 11: Media Foundation;
/// Windows 10: filtro DirectShow).
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
                null => $"Installo WebcamLR {v} per il tuo utente in:\n{p.CartellaApp}\n\nContinuare?",
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

        // 5. Firewall e webcam per le altre app, con un solo permesso dell'amministratore.
        var avviso = ConfiguraPC(p, scelta);

        if (scelta.Silenzioso) return Program.Fatto;
        var fine = "WebcamLR è installata: la trovi nel menu Start."
                   + (avviso is null ? "" : $"\n\n{avviso}")
                   + "\n\nAprirla adesso?";
        if (FunzioniWindows.Chiedi(fine)) ApriDaUtente(p.Eseguibile);
        return Program.Fatto;
    }

    private static string? VersioneInstallata()
    {
        try
        {
            using var chiave = Registry.CurrentUser.OpenSubKey(DatiProdotto.ChiaveDisinstallazione);
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
                + "Lo scarico da Microsoft e lo installo adesso? Windows chiederà il permesso dell'amministratore."))
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
                // .NET si installa per tutto il PC (C:\Program Files\dotnet): serve l'amministratore.
                var codice = Program.EseguiDaAmministratore(file, scelta.Silenzioso ? "/install /quiet /norestart" : "/install /passive /norestart");
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
        // Resti di un aggiornamento con file aperti: adesso si possono cancellare.
        foreach (var resto in Directory.EnumerateFiles(cartella, "*.vecchio-*", SearchOption.AllDirectories))
        {
            try { File.Delete(resto); } catch (Exception) { }
        }
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
                // Aperto da qualcuno: lo si rinomina (si può anche se è aperto); il resto lo cancella il prossimo aggiornamento.
                var spostato = $"{destinazione}.vecchio-{DateTime.Now:yyyyMMddHHmmss}";
                File.Move(destinazione, spostato);
                voce.ExtractToFile(destinazione, overwrite: true);
            }
            // Il «Mark of the Web» (installatore scaricato da Internet) farebbe chiedere conferma a ogni avvio.
            FunzioniWindows.DeleteFileW(destinazione + ":Zone.Identifier");
            totale += voce.Length;
        }

        if (vecchia is not null) CancellaCartella(vecchia);
        return totale;
    }

    /// <summary>Cancella una cartella; quello che è ancora aperto resta e si cancella alla prossima occasione.</summary>
    public static void CancellaCartella(string cartella)
    {
        try { Directory.Delete(cartella, recursive: true); return; }
        catch (Exception) { }
        foreach (var file in Directory.EnumerateFiles(cartella, "*", SearchOption.AllDirectories))
        {
            try { File.Delete(file); } catch (Exception) { }
        }
        foreach (var sotto in Directory.EnumerateDirectories(cartella, "*", SearchOption.AllDirectories).OrderByDescending(d => d.Length).Append(cartella))
        {
            try { Directory.Delete(sotto); } catch (Exception) { }
        }
    }

    private static void ScriviDisinstallazione(Percorsi p, long dimensione)
    {
        using var chiave = Registry.CurrentUser.CreateSubKey(DatiProdotto.ChiaveDisinstallazione, writable: true);
        foreach (var valore in ValoriDisinstallazione.Crea(p, Program.Versione, dimensione, DateTime.Now))
            chiave.SetValue(valore.Nome, valore.Valore, valore.ÈNumero ? RegistryValueKind.DWord : RegistryValueKind.String);
        Registro.Scrivi($"Scritto HKCU\\{DatiProdotto.ChiaveDisinstallazione}");
    }

    // ——— Firewall e webcam ———

    /// <summary>
    /// Una sola richiesta di permesso per WebcamLR.Webcam.Installa.exe «configura»: la regola del firewall (reti private)
    /// e la webcam. Se la webcam c'era già si aggiorna da sola (la sorgente nuova deve combaciare con l'app nuova);
    /// altrimenti si chiede. Restituisce un avviso da mostrare alla fine, o null se è andato tutto bene.
    /// </summary>
    private static string? ConfiguraPC(Percorsi p, Argomenti scelta)
    {
        var build = Environment.OSVersion.Version.Build;
        var webcamPossibile = build >= 17763;
        var giàInstallata = WebcamRegistrata();
        var webcam = giàInstallata;
        if (!giàInstallata && webcamPossibile)
        {
            var dove = NomiWebcam.TipoPer(build) == TipoWebcam.MediaFoundation
                ? "Zoom, Teams, Meet, WhatsApp, OBS e i siti"
                : "Zoom, Meet, OBS e i siti in Chrome, Edge e Firefox";
            webcam = scelta.Silenzioso
                ? scelta.Webcam
                : FunzioniWindows.Chiedi($"Installo anche la webcam «WebcamLR» per {dove}?\n\n"
                                         + "Puoi farlo anche dopo da WebcamLR, nella scheda «Webcam per le altre app».");
        }
        if (!scelta.Silenzioso)
        {
            FunzioniWindows.Informa("Adesso Windows chiede il permesso dell'amministratore (una volta sola) per "
                                    + (webcam ? "installare la webcam e " : "")
                                    + "lasciar passare il telefono nel firewall sulle reti private.\n\n"
                                    + "La finestra dice «Autore: Sconosciuto» perché WebcamLR non è ancora firmata: rispondi «Sì».");
        }
        var argomenti = $"configura {ValoriDisinstallazione.Tra(p.Eseguibile)}" + (webcam ? " webcam" : "");
        var codice = Program.EseguiDaAmministratore(p.InstallatoreWebcam, argomenti);
        Registro.Scrivi($"Configurazione del PC: {codice} · {CodiciInstallazione.Descrivi(codice)}");
        if (codice == CodiciInstallazione.Annullata)
            return "Senza il permesso dell'amministratore la webcam non è installata e il firewall non è configurato: "
                   + "alla prima apertura Windows chiederà di consentire WebcamLR (scegli «Reti private»). "
                   + "La webcam si installa da WebcamLR, scheda «Webcam per le altre app».";
        if (codice == CodiciInstallazione.Riuscita)
            return webcam && !giàInstallata ? "Webcam per le altre app: installata. Chiudi e riapri le app di chiamata già aperte." : null;
        return (webcam ? "Webcam per le altre app: " : "") + CodiciInstallazione.Descrivi(codice);
    }

    /// <summary>La sorgente di Windows 11 o il filtro DirectShow registrati (si legge HKLM anche senza amministratore).</summary>
    public static bool WebcamRegistrata()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var sorgente = radice.OpenSubKey($@"SOFTWARE\Classes\CLSID\{NomiWebcam.ClsidTraGraffe}\InprocServer32");
            using var filtro = radice.OpenSubKey(NomiWebcam.ChiaveClsidDirectShow + @"\InprocServer32");
            return sorgente is not null || filtro is not null;
        }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// Apre WebcamLR come utente normale anche se l'installatore è stato avviato da amministratore (installazioni
    /// aziendali): passando da Esplora risorse, che gira sempre senza privilegi.
    /// </summary>
    private static void ApriDaUtente(string eseguibile)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", ValoriDisinstallazione.Tra(eseguibile)) { UseShellExecute = false }); }
        catch (Exception errore) { Registro.Scrivi($"Non apro WebcamLR: {errore.Message}"); }
    }
}
