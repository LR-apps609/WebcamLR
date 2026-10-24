using System.ComponentModel;
using System.Diagnostics;
using Microsoft.Win32;
using Windows.Devices.Enumeration;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// Installazione, riparazione e rimozione della webcam «WebcamLR» (1.24–1.26; Windows 10 con il filtro DirectShow, P23),
/// e lo stato da mostrare.
/// Il lavoro vero lo fa WebcamLR.Webcam.Installa.exe, nella cartella «Webcam» accanto all'app, lanciato con il
/// permesso dell'amministratore (Windows lo chiede con la sua finestra): l'app resta un'app normale.
/// </summary>
public static class InstallazioneWebcam
{
    /// <summary>Media Foundation su Windows 11, filtro DirectShow su Windows 10 (P23): l'installatore sceglie allo stesso modo.</summary>
    public static TipoWebcam Tipo => NomiWebcam.TipoPer(Environment.OSVersion.Version.Build);

    private static string Installatore =>
        Path.Combine(AppContext.BaseDirectory, NomiWebcam.CartellaAccantoAllApp, NomiWebcam.FileInstallatore);

    /// <summary>Lo stato attuale. Lento (elenca le fotocamere): mai sul thread dell'interfaccia senza await.</summary>
    public static async Task<StatoWebcam> StatoAsync(bool inUso)
    {
        bool registrata, elencata;
        if (Tipo == TipoWebcam.MediaFoundation)
        {
            registrata = Registrata();
            elencata = await ElencataAsync();
        }
        else
        {
            // Il filtro DirectShow non compare tra le fotocamere di Windows (DeviceInformation): conta la categoria video.
            registrata = FiltroRegistrato();
            elencata = FiltroNellaCategoria();
        }
        if (registrata && elencata) return inUso ? StatoWebcam.InUso : StatoWebcam.Installata;
        return registrata || elencata ? StatoWebcam.DaRiparare : StatoWebcam.NonInstallata;
    }

    /// <summary>Windows 10: la classe COM del filtro in HKLM (64 bit) punta a un file che esiste.</summary>
    public static bool FiltroRegistrato()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var server = radice.OpenSubKey(NomiWebcam.ChiaveClsidDirectShow + @"\InprocServer32");
            return server?.GetValue("") is string percorso && File.Exists(percorso);
        }
        catch (Exception) { return false; }
    }

    /// <summary>Windows 10: il filtro è nella categoria «dispositivi di cattura video», dove le app lo cercano.</summary>
    public static bool FiltroNellaCategoria()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var istanza = radice.OpenSubKey(NomiWebcam.ChiaveIstanzaDirectShow);
            return istanza?.GetValue("FriendlyName") is string;
        }
        catch (Exception) { return false; }
    }

    /// <summary>Il componente COM in HKLM punta a un file che esiste.</summary>
    public static bool Registrata()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var server = radice.OpenSubKey($@"SOFTWARE\Classes\CLSID\{NomiWebcam.ClsidTraGraffe}\InprocServer32");
            return server?.GetValue("") is string percorso && File.Exists(percorso);
        }
        catch (Exception) { return false; }
    }

    /// <summary>Windows elenca una fotocamera chiamata «WebcamLR» (come la vedono le app).</summary>
    public static async Task<bool> ElencataAsync()
    {
        try
        {
            var fotocamere = await DeviceInformation.FindAllAsync(DeviceClass.VideoCapture);
            return fotocamere.Any(f => NomiWebcam.ÈLaWebcam(f.Name));
        }
        catch (Exception) { return false; }
    }

    /// <summary>
    /// La privacy di Windows nega la fotocamera alle app desktop: allora Zoom, Teams e Chrome non vedono nessuna webcam,
    /// nemmeno «WebcamLR» (Impostazioni → Privacy e sicurezza → Fotocamera).
    /// </summary>
    public static bool FotocameraNegataDallaPrivacy()
    {
        const string chiave = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam";
        static bool Negata(RegistryKey radice, string percorso)
        {
            using var k = radice.OpenSubKey(percorso);
            return string.Equals(k?.GetValue("Value") as string, "Deny", StringComparison.OrdinalIgnoreCase);
        }
        try
        {
            return Negata(Registry.LocalMachine, chiave) || Negata(Registry.CurrentUser, chiave)
                || Negata(Registry.CurrentUser, chiave + @"\NonPackaged");
        }
        catch (Exception) { return false; }
    }

    public static Task<int> InstallaAsync() => EseguiAsync("installa");

    public static Task<int> RimuoviAsync() => EseguiAsync("rimuovi");

    private static async Task<int> EseguiAsync(string azione)
    {
        if (!File.Exists(Installatore)) return CodiciInstallazione.InstallatoreMancante;
        try
        {
            using var processo = Process.Start(new ProcessStartInfo(Installatore, azione)
            {
                UseShellExecute = true,
                Verb = "runas",
                WorkingDirectory = Path.GetDirectoryName(Installatore)!,
            });
            if (processo is null) return CodiciInstallazione.InstallatoreMancante;
            await processo.WaitForExitAsync();
            return processo.ExitCode;
        }
        catch (Win32Exception errore) when (errore.NativeErrorCode == CodiciInstallazione.Annullata)
        {
            return CodiciInstallazione.Annullata;
        }
    }

    /// <summary>Apre la pagina della privacy della fotocamera nelle Impostazioni.</summary>
    public static void ApriPrivacy()
    {
        try { Process.Start(new ProcessStartInfo("ms-settings:privacy-webcam") { UseShellExecute = true }); }
        catch (Exception) { }
    }
}
