using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32;

namespace WebcamLR.Webcam.Installa;

/// <summary>
/// «WebcamLR.Webcam.Installa.exe installa» e «… rimuovi», lanciati da WebcamLR come amministratore.
/// Installa: copia la sorgente in «C:\Program Files\WebcamLR\Webcam» (Frame Server non legge la cartella dell'utente),
/// la registra in HKLM (Frame Server gira come LocalService e non vede HKCU) e crea la webcam per tutti gli utenti.
/// Rimuovi: toglie la webcam, la registrazione e i file, senza riavvio (i file ancora aperti si cancellano al riavvio).
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
                "installa" => Installa(),
                "rimuovi" => Rimuovi(),
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

    private static int Installa()
    {
        if (!NomiWebcam.WindowsSupportato(Environment.OSVersion.Version.Build)) return CodiciInstallazione.WindowsNonSupportato;
        var origine = AppContext.BaseDirectory;
        if (!File.Exists(Path.Combine(origine, NomiWebcam.FileComHost)) || !File.Exists(Path.Combine(origine, NomiWebcam.FileSorgente)))
            return CodiciInstallazione.FileMancanti;

        // 1. I file in Programmi. Se Frame Server ha la versione vecchia aperta, la si sposta (un file aperto si può
        //    rinominare) e si cancella al riavvio.
        try
        {
            Directory.CreateDirectory(Destinazione);
            if (!StessaCartella(origine, Destinazione))
            {
                foreach (var file in Directory.GetFiles(origine))
                {
                    var nome = Path.GetFileName(file);
                    if (!(nome.EndsWith(".dll", StringComparison.OrdinalIgnoreCase) || nome.EndsWith(".json", StringComparison.OrdinalIgnoreCase)
                          || nome.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))) continue;
                    Copia(file, Path.Combine(Destinazione, nome));
                }
            }
            CancellaVecchi();
        }
        catch (Exception errore)
        {
            Scrivi($"Copia non riuscita: {errore.Message}");
            return CodiciInstallazione.CopiaFallita;
        }

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

        if (Directory.Exists(Destinazione))
        {
            foreach (var file in Directory.GetFiles(Destinazione))
            {
                try { File.Delete(file); }
                catch (Exception)
                {
                    // Ancora aperto da Frame Server o da questo stesso installatore: si cancella al riavvio.
                    MoveFileExW(file, null, MOVEFILE_DELAY_UNTIL_REBOOT);
                    Scrivi($"Si cancellerà al riavvio: {Path.GetFileName(file)}");
                }
            }
            try { Directory.Delete(Destinazione); } catch (Exception) { MoveFileExW(Destinazione, null, MOVEFILE_DELAY_UNTIL_REBOOT); }
            var genitore = Path.GetDirectoryName(Destinazione)!;
            try { if (!Directory.EnumerateFileSystemEntries(genitore).Any()) Directory.Delete(genitore); } catch (Exception) { }
        }
        return CodiciInstallazione.Riuscita;
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

    private static void CancellaVecchi()
    {
        foreach (var vecchio in Directory.GetFiles(Destinazione, "*.vecchio-*"))
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
