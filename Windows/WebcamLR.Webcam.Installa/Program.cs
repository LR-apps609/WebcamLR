using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32;

namespace WebcamLR.Webcam.Installa;

/// <summary>
/// «WebcamLR.Webcam.Installa.exe installa» e «… rimuovi», lanciati da WebcamLR come amministratore.
/// Installa, su Windows 11: copia la sorgente in «C:\Program Files\WebcamLR\Webcam» (Frame Server non legge la cartella
/// dell'utente), la registra in HKLM (Frame Server gira come LocalService e non vede HKCU) e crea la webcam per tutti
/// gli utenti. Su Windows 10 (P23): copia e registra il filtro DirectShow, a 64 e, se c'è il runtime x86, a 32 bit.
/// «… directshow» registra il filtro anche su Windows 11 (solo a mano, per app che vedono soltanto DirectShow:
/// attenzione, Chrome mostrerebbe due «WebcamLR»).
/// Rimuovi: toglie la webcam, il filtro, le registrazioni e i file, senza riavvio (i file ancora aperti si cancellano al riavvio).
/// Per l'installatore di WebcamLR, che gira senza amministratore e chiede il permesso una volta sola:
/// «configura &lt;WebcamLR.exe&gt; [webcam]» (regola del firewall, più la webcam se chiesta o se c'era già),
/// «disinstalla &lt;WebcamLR.exe&gt;» (webcam e regola), e a parte «firewall» e «rimuovi-firewall» &lt;WebcamLR.exe&gt;.
/// Il codice d'uscita è uno di <see cref="CodiciInstallazione"/>, o l'HRESULT di Windows se negativo.
/// </summary>
internal static class Program
{
    private static readonly string CartellaRegistro = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), NomiWebcam.SottocartellaRegistro);
    private static readonly string FileRegistro = Path.Combine(CartellaRegistro, "Installazione webcam.txt");

    private static string Destinazione => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), NomiWebcam.SottocartellaProgrammi);

    private static string ChiaveClsid => $@"SOFTWARE\Classes\CLSID\{NomiWebcam.ClsidTraGraffe}";

    private static int Main(string[] argomenti)
    {
        PreparaCartellaRegistro();
        Scrivi($"— WebcamLR.Webcam.Installa {string.Join(' ', argomenti)} (Windows {Environment.OSVersion.Version})");
        try
        {
            var codice = argomenti.FirstOrDefault()?.ToLowerInvariant() switch
            {
                "installa" => NomiWebcam.TipoPer(Environment.OSVersion.Version.Build) == TipoWebcam.MediaFoundation
                    ? Installa()
                    : InstallaDirectShow(),
                "directshow" => InstallaDirectShow(),
                "rimuovi" => Rimuovi(),
                "firewall" when argomenti.Length >= 2 => Firewall.Aggiungi(argomenti[1], Scrivi),
                "rimuovi-firewall" when argomenti.Length >= 2 => Firewall.Togli(argomenti[1], Scrivi),
                "configura" when argomenti.Length >= 2 => Configura(argomenti[1], argomenti.Skip(2).Contains("webcam", StringComparer.OrdinalIgnoreCase)),
                "disinstalla" when argomenti.Length >= 2 => Disinstalla(argomenti[1]),
                _ => CodiciInstallazione.ArgomentiErrati,
            };
            Scrivi($"Esito: {codice} · {CodiciInstallazione.Descrivi(codice)}");
            return codice;
        }
        catch (Exception errore)
        {
            Scrivi($"Errore: {errore}");
            return errore.HResult < 0 ? errore.HResult : CodiciInstallazione.RegistroFallito;
        }
    }

    /// <summary>
    /// Dall'installatore di WebcamLR (WebcamLR-Setup.exe), con una sola richiesta di permesso: la regola del firewall
    /// per <paramref name="programma"/> e la webcam, se chiesta («webcam») o se c'era già (va aggiornata insieme all'app:
    /// la memoria condivisa cambia versione).
    /// </summary>
    private static int Configura(string programma, bool webcam)
    {
        var firewall = Firewall.Aggiungi(programma, Scrivi);
        var codice = CodiciInstallazione.Riuscita;
        if (webcam || WebcamRegistrata())
        {
            codice = NomiWebcam.TipoPer(Environment.OSVersion.Version.Build) == TipoWebcam.MediaFoundation ? Installa() : InstallaDirectShow();
        }
        if (!CodiciInstallazione.ÈRiuscita(codice)) return codice;
        return firewall == CodiciInstallazione.Riuscita ? codice : firewall;
    }

    /// <summary>Dal disinstallatore di WebcamLR: toglie la webcam (se c'è) e la regola del firewall.</summary>
    private static int Disinstalla(string programma)
    {
        var firewall = Firewall.Togli(programma, Scrivi);
        var codice = Rimuovi();
        return codice != CodiciInstallazione.Riuscita ? codice : firewall;
    }

    /// <summary>Vero se la sorgente di Windows 11 o il filtro DirectShow sono registrati.</summary>
    private static bool WebcamRegistrata()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var sorgente = radice.OpenSubKey(ChiaveClsid + @"\InprocServer32");
            using var filtro = radice.OpenSubKey(NomiWebcam.ChiaveClsidDirectShow + @"\InprocServer32");
            return sorgente is not null || filtro is not null;
        }
        catch (Exception) { return false; }
    }

    private static int Installa()
    {
        if (!NomiWebcam.WindowsSupportato(Environment.OSVersion.Version.Build)) return CodiciInstallazione.WindowsNonSupportato;
        var origine = AppContext.BaseDirectory;
        if (!File.Exists(Path.Combine(origine, NomiWebcam.FileComHost)) || !File.Exists(Path.Combine(origine, NomiWebcam.FileSorgente)))
            return CodiciInstallazione.FileMancanti;

        // 1. I file in Programmi.
        if (!CopiaFile(origine)) return CodiciInstallazione.CopiaFallita;

        // 2. La registrazione COM, nel registro a 64 bit come Frame Server.
        var comHost = Path.Combine(Destinazione, NomiWebcam.FileComHost);
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Default);
            using var classe = radice.CreateSubKey(ChiaveClsid, writable: true);
            classe.SetValue("", "WebcamLR · webcam virtuale");
            using var server = classe.CreateSubKey("InprocServer32", writable: true);
            server.SetValue("", comHost);
            server.SetValue("ThreadingModel", "Both");
            Scrivi($"Registrato {ChiaveClsid} → {comHost}");
        }
        catch (Exception errore)
        {
            Scrivi($"Registro non riuscito: {errore.Message}");
            return CodiciInstallazione.RegistroFallito;
        }

        // 3. La webcam, per tutti gli utenti e anche dopo il riavvio.
        return FotocameraVirtuale.Crea(Scrivi);
    }

    /// <summary>Windows 10 (P23): il filtro DirectShow, che ogni app carica nel suo processo. Niente Frame Server.</summary>
    private static int InstallaDirectShow()
    {
        if (Environment.OSVersion.Version.Build < 17763) return CodiciInstallazione.WindowsNonSupportato;
        var origine = AppContext.BaseDirectory;
        if (!File.Exists(Path.Combine(origine, NomiWebcam.FileComHostFiltro)) || !File.Exists(Path.Combine(origine, NomiWebcam.FileFiltro)))
            return CodiciInstallazione.FileMancanti;
        if (!File.Exists(Path.Combine(origine, NomiWebcam.SottocartellaX86, NomiWebcam.FileComHostFiltro)))
            Scrivi("Manca la copia x86 del filtro accanto all'app: niente webcam per le app a 32 bit");
        if (!CopiaFile(origine)) return CodiciInstallazione.CopiaFallita;
        return FiltroDirectShow.Registra(Destinazione, Scrivi);
    }

    /// <summary>
    /// Copia DLL, JSON ed EXE della cartella «Webcam» (e della sua «x86») in Programmi. Se un'app ha la versione vecchia
    /// aperta (Frame Server, oppure Zoom o Chrome con il filtro DirectShow), la si sposta (un file aperto si può
    /// rinominare) e si cancella al riavvio.
    /// </summary>
    private static bool CopiaFile(string origine)
    {
        try
        {
            if (!StessaCartella(origine, Destinazione))
            {
                CopiaCartella(origine, Destinazione);
                var origineX86 = Path.Combine(origine, NomiWebcam.SottocartellaX86);
                if (Directory.Exists(origineX86)) CopiaCartella(origineX86, Path.Combine(Destinazione, NomiWebcam.SottocartellaX86));
            }
            CancellaVecchi(Destinazione);
            CancellaVecchi(Path.Combine(Destinazione, NomiWebcam.SottocartellaX86));
            return true;
        }
        catch (Exception errore)
        {
            Scrivi($"Copia non riuscita: {errore.Message}");
            return false;
        }
    }

    private static void CopiaCartella(string da, string a)
    {
        Directory.CreateDirectory(a);
        foreach (var file in Directory.GetFiles(da))
        {
            var nome = Path.GetFileName(file);
            if (!(nome.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) || nome.EndsWith(".json", StringComparison.OrdinalIgnoreCase)
                  || nome.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))) continue;
            Copia(file, Path.Combine(a, nome));
        }
    }

    private static int Rimuovi()
    {
        // Prima la webcam (sparisce dalle app), poi la registrazione, poi i file: mai il contrario,
        // altrimenti Windows resterebbe con una webcam che non sa più caricare.
        var hr = NomiWebcam.WindowsSupportato(Environment.OSVersion.Version.Build) ? FotocameraVirtuale.Rimuovi(Scrivi) : 0;
        if (hr < 0) Scrivi($"La webcam non si è tolta (0x{hr:X8}): continuo con il resto");

        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Default);
            radice.DeleteSubKeyTree(ChiaveClsid, throwOnMissingSubKey: false);
            Scrivi($"Tolto {ChiaveClsid}");
        }
        catch (Exception errore)
        {
            Scrivi($"Registro: {errore.Message}");
            return CodiciInstallazione.RegistroFallito;
        }
        // Il filtro DirectShow (Windows 10, o registrato a mano su Windows 11): sempre, anche se non c'era.
        if (FiltroDirectShow.Rimuovi(Scrivi) != CodiciInstallazione.Riuscita) return CodiciInstallazione.RegistroFallito;

        CancellaCartella(Path.Combine(Destinazione, NomiWebcam.SottocartellaX86));
        CancellaCartella(Destinazione);
        var genitore = Path.GetDirectoryName(Destinazione)!;
        try { if (Directory.Exists(genitore) && !Directory.EnumerateFileSystemEntries(genitore).Any()) Directory.Delete(genitore); } catch (Exception) { }
        return CodiciInstallazione.Riuscita;
    }

    private static void CancellaCartella(string cartella)
    {
        if (!Directory.Exists(cartella)) return;
        foreach (var file in Directory.GetFiles(cartella))
        {
            try { File.Delete(file); }
            catch (Exception)
            {
                // Ancora aperto (Frame Server, un'app con il filtro DirectShow, questo installatore): si cancella al riavvio.
                MoveFileExW(file, null, MOVEFILE_DELAY_UNTIL_REBOOT);
                Scrivi($"Si cancellerà al riavvio: {Path.GetFileName(file)}");
            }
        }
        try { Directory.Delete(cartella); } catch (Exception) { MoveFileExW(cartella, null, MOVEFILE_DELAY_UNTIL_REBOOT); }
    }

    private static void Copia(string da, string a)
    {
        try
        {
            File.Copy(da, a, overwrite: true);
        }
        catch (IOException)
        {
            var spostato = $"{a}.vecchio-{DateTime.Now:yyyyMMddHHmmss}";
            File.Move(a, spostato);
            MoveFileExW(spostato, null, MOVEFILE_DELAY_UNTIL_REBOOT);
            File.Copy(da, a, overwrite: true);
            Scrivi($"{Path.GetFileName(a)} era in uso: la versione vecchia si cancella al riavvio");
        }
        // Il «Mark of the Web» (file scaricato da Internet) farebbe rifiutare la DLL: lo si toglie.
        DeleteFileW(a + ":Zone.Identifier");
        Scrivi($"Copiato {Path.GetFileName(a)}");
    }

    private static void CancellaVecchi(string cartella)
    {
        if (!Directory.Exists(cartella)) return;
        foreach (var vecchio in Directory.GetFiles(cartella, "*.vecchio-*"))
        {
            try { File.Delete(vecchio); } catch (Exception) { }
        }
    }

    private static bool StessaCartella(string a, string b) =>
        string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// «C:\ProgramData\WebcamLR», dove scrive anche la sorgente: creata qui da amministratore, va data in modifica
    /// a LocalService (Frame Server), altrimenti il registro della webcam resterebbe vuoto.
    /// </summary>
    private static void PreparaCartellaRegistro()
    {
        try
        {
            var cartella = Directory.CreateDirectory(CartellaRegistro);
            var sicurezza = cartella.GetAccessControl();
            var servizioLocale = new SecurityIdentifier(WellKnownSidType.LocalServiceSid, null);
            sicurezza.AddAccessRule(new FileSystemAccessRule(servizioLocale, FileSystemRights.Modify,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
            cartella.SetAccessControl(sicurezza);
        }
        catch (Exception) { }
    }

    private static void Scrivi(string testo)
    {
        try { File.AppendAllText(FileRegistro, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {testo}{Environment.NewLine}"); }
        catch (Exception) { }
    }

    private const uint MOVEFILE_DELAY_UNTIL_REBOOT = 0x4;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileExW(string esistente, string? nuovo, uint flag);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool DeleteFileW(string nome);
}
