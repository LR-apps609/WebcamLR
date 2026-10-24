using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace WebcamLR.Webcam.Installa;

/// <summary>
/// Registrazione del filtro DirectShow «WebcamLR» (Windows 10, P23), come fa il DllRegisterServer dei filtri di cattura:
/// <list type="number">
/// <item>la classe COM in HKLM: nel registro a 64 bit la DLL x64 (o ARM64), nel registro a 32 bit (WOW6432Node) quella x86;</item>
/// <item>il filtro nella categoria CLSID_VideoInputDeviceCategory con IFilterMapper2::RegisterFilter, che scrive
/// CLSID, FriendlyName e FilterData (i pin e i tipi, nel formato binario che sa solo Windows) sotto
/// «CLSID\{860BB310-…}\Instance\{nostro CLSID}». Poi gli stessi valori vanno anche nel registro a 32 bit, per le app
/// a 32 bit: il blocco FilterData non contiene puntatori ed è uguale per le due architetture.</item>
/// </list>
/// IFilterMapper2 (strmif.h): IUnknown 0–2, CreateCategory 3, UnregisterFilter 4, RegisterFilter 5. IID
/// {b79bb0b0-33c1-11d1-abe1-00a0c905f375}, REGFILTER2/REGFILTERPINS2/REGPINTYPES come in strmif.h.
/// </summary>
internal static unsafe class FiltroDirectShow
{
    private const uint MERIT_DO_NOT_USE = 0x200000;
    private const uint REG_PINFLAG_B_OUTPUT = 0x8;
    private const uint CLSCTX_INPROC_SERVER = 0x1;
    private static readonly Guid IID_IFilterMapper2 = new("b79bb0b0-33c1-11d1-abe1-00a0c905f375");

    [StructLayout(LayoutKind.Sequential)]
    private struct REGPINTYPES { public Guid* clsMajorType; public Guid* clsMinorType; }

    [StructLayout(LayoutKind.Sequential)]
    private struct REGFILTERPINS2
    {
        public uint dwFlags;
        public uint cInstances;
        public uint nMediaTypes;
        public REGPINTYPES* lpMediaType;
        public uint nMediums;
        public nint lpMedium;
        public Guid* clsPinCategory;
    }

    /// <summary>dwVersion 2: l'unione vale { ULONG cPins2; const REGFILTERPINS2 *rgPins2; }.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct REGFILTER2
    {
        public uint dwVersion;
        public uint dwMerit;
        public uint cPins2;
        public REGFILTERPINS2* rgPins2;
    }

    /// <summary>Registra il filtro. Restituisce Riuscita, RiuscitaSenza32Bit o RegistroFallito.</summary>
    public static int Registra(string destinazione, Action<string> registro)
    {
        var comHost = Path.Combine(destinazione, NomiWebcam.FileComHostFiltro);
        var comHostX86 = Path.Combine(destinazione, NomiWebcam.SottocartellaX86, NomiWebcam.FileComHostFiltro);
        var conX86 = Environment.Is64BitOperatingSystem && File.Exists(comHostX86) && RuntimeX86Presente(registro);
        try
        {
            RegistraClasse(RegistryView.Registry64, comHost, registro);
            if (conX86) RegistraClasse(RegistryView.Registry32, comHostX86, registro);
            else TogliVista(RegistryView.Registry32, registro);
        }
        catch (Exception errore)
        {
            registro($"Classe COM non registrata: {errore.Message}");
            return CodiciInstallazione.RegistroFallito;
        }

        // La categoria: prima con IFilterMapper2 (anche FilterData), poi i valori copiati in tutte e due le viste.
        var valori = new Dictionary<string, object>
        {
            ["CLSID"] = NomiWebcam.ClsidDirectShowTraGraffe,
            ["FriendlyName"] = NomiWebcam.NomeDirectShow,
        };
        var hr = RegistraConFilterMapper(registro);
        registro($"IFilterMapper2::RegisterFilter: 0x{hr:X8}");
        if (hr >= 0 && LeggiFilterData() is { } filterData) valori["FilterData"] = filterData;
        else registro("FilterData non disponibile: il filtro si registra senza (le app lo elencano comunque)");
        try
        {
            ScriviIstanza(RegistryView.Registry64, valori);
            if (conX86) ScriviIstanza(RegistryView.Registry32, valori);
            registro($"Categoria video: {NomiWebcam.ChiaveIstanzaDirectShow}{(conX86 ? " (64 e 32 bit)" : " (64 bit)")}");
        }
        catch (Exception errore)
        {
            registro($"Categoria non scritta: {errore.Message}");
            return CodiciInstallazione.RegistroFallito;
        }
        return conX86 ? CodiciInstallazione.Riuscita : CodiciInstallazione.RiuscitaSenza32Bit;
    }

    /// <summary>Toglie filtro e classe da tutte e due le viste del registro. Nessun errore se non c'erano.</summary>
    public static int Rimuovi(Action<string> registro)
    {
        try
        {
            TogliVista(RegistryView.Registry64, registro);
            if (Environment.Is64BitOperatingSystem) TogliVista(RegistryView.Registry32, registro);
            return CodiciInstallazione.Riuscita;
        }
        catch (Exception errore)
        {
            registro($"Filtro DirectShow non tolto: {errore.Message}");
            return CodiciInstallazione.RegistroFallito;
        }
    }

    /// <summary>Vero se il filtro è registrato nel registro a 64 bit (classe con file esistente e istanza nella categoria).</summary>
    public static bool Registrato()
    {
        using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
        using var server = radice.OpenSubKey(NomiWebcam.ChiaveClsidDirectShow + @"\InprocServer32");
        using var istanza = radice.OpenSubKey(NomiWebcam.ChiaveIstanzaDirectShow);
        return server?.GetValue("") is string percorso && File.Exists(percorso) && istanza is not null;
    }

    private static void RegistraClasse(RegistryView vista, string comHost, Action<string> registro)
    {
        using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, vista);
        using var classe = radice.CreateSubKey(NomiWebcam.ChiaveClsidDirectShow, writable: true);
        classe.SetValue("", NomiWebcam.NomeDirectShow);
        using var server = classe.CreateSubKey("InprocServer32", writable: true);
        server.SetValue("", comHost);
        // Both: le app DirectShow chiamano i filtri da qualsiasi thread; gli oggetti .NET esposti a COM sono agili.
        server.SetValue("ThreadingModel", "Both");
        registro($"Registrato {NomiWebcam.ChiaveClsidDirectShow} ({vista}) → {comHost}");
    }

    private static void ScriviIstanza(RegistryView vista, Dictionary<string, object> valori)
    {
        using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, vista);
        using var istanza = radice.CreateSubKey(NomiWebcam.ChiaveIstanzaDirectShow, writable: true);
        foreach (var (nome, valore) in valori)
            istanza.SetValue(nome, valore, valore is byte[] ? RegistryValueKind.Binary : RegistryValueKind.String);
    }

    private static void TogliVista(RegistryView vista, Action<string> registro)
    {
        using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, vista);
        radice.DeleteSubKeyTree(NomiWebcam.ChiaveIstanzaDirectShow, throwOnMissingSubKey: false);
        radice.DeleteSubKeyTree(NomiWebcam.ChiaveClsidDirectShow, throwOnMissingSubKey: false);
        registro($"Tolto il filtro DirectShow dal registro ({vista})");
    }

    /// <summary>
    /// FilterData scritto da IFilterMapper2: lo si legge dalla vista unita HKCR (Windows può averlo messo in HKLM o,
    /// di rado, in HKCU\Software\Classes), poi lo si scrive esplicitamente in HKLM.
    /// </summary>
    private static byte[]? LeggiFilterData()
    {
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.ClassesRoot, RegistryView.Registry64);
            var percorso = NomiWebcam.ChiaveIstanzaDirectShow["SOFTWARE\\Classes\\".Length..];
            using var istanza = radice.OpenSubKey(percorso);
            return istanza?.GetValue("FilterData") as byte[];
        }
        catch (Exception) { return null; }
    }

    private static int RegistraConFilterMapper(Action<string> registro)
    {
        var inizializzato = CoInitializeEx(0, COINIT_MULTITHREADED);
        try
        {
            var clsid = GuidDirectShow.CLSID_FilterMapper2;
            var iid = IID_IFilterMapper2;
            var hr = CoCreateInstance(ref clsid, 0, CLSCTX_INPROC_SERVER, ref iid, out var mapper);
            if (hr < 0) return hr;
            try
            {
                // Un pin d'uscita di cattura con i tre sottotipi video. Merito «da non usare»: nessun grafo lo inserisce
                // da solo; le app lo scelgono dall'elenco delle videocamere, come OBS Virtual Camera.
                var video = GuidDirectShow.MEDIATYPE_Video;
                var sottotipi = stackalloc Guid[3];
                sottotipi[0] = GuidDirectShow.MEDIASUBTYPE_YUY2;
                sottotipi[1] = GuidDirectShow.MEDIASUBTYPE_NV12;
                sottotipi[2] = GuidDirectShow.MEDIASUBTYPE_RGB24;
                var tipi = stackalloc REGPINTYPES[3];
                for (var i = 0; i < 3; i++) tipi[i] = new REGPINTYPES { clsMajorType = &video, clsMinorType = &sottotipi[i] };
                var categoriaPin = GuidDirectShow.PIN_CATEGORY_CAPTURE;
                var pin = new REGFILTERPINS2
                {
                    dwFlags = REG_PINFLAG_B_OUTPUT,
                    cInstances = 1,
                    nMediaTypes = 3,
                    lpMediaType = tipi,
                    nMediums = 0,
                    lpMedium = 0,
                    clsPinCategory = &categoriaPin,
                };
                var filtro = new REGFILTER2 { dwVersion = 2, dwMerit = MERIT_DO_NOT_USE, cPins2 = 1, rgPins2 = &pin };
                var clsidFiltro = Guid.Parse(NomiWebcam.ClsidDirectShow);
                var categoria = GuidDirectShow.CLSID_VideoInputDeviceCategory;
                fixed (char* nome = NomiWebcam.NomeDirectShow)
                fixed (char* istanza = NomiWebcam.ClsidDirectShowTraGraffe)
                {
                    var tabella = *(nint**)mapper;
                    var registerFilter = (delegate* unmanaged[Stdcall]<nint, Guid*, char*, nint, Guid*, char*, REGFILTER2*, int>)tabella[5];
                    return registerFilter(mapper, &clsidFiltro, nome, 0, &categoria, istanza, &filtro);
                }
            }
            finally { Marshal.Release(mapper); }
        }
        catch (Exception errore)
        {
            registro($"IFilterMapper2 non disponibile: {errore.Message}");
            return errore.HResult < 0 ? errore.HResult : unchecked((int)0x80004005);
        }
        finally
        {
            if (inizializzato >= 0) CoUninitialize();
        }
    }

    /// <summary>
    /// Il runtime .NET 8 (o più nuovo) a 32 bit: senza, la DLL x86 non parte e le app a 32 bit vedrebbero una
    /// videocamera che non si apre. Meglio non elencarla affatto.
    /// </summary>
    private static bool RuntimeX86Presente(Action<string> registro)
    {
        var cartelle = new List<string> { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "dotnet") };
        try
        {
            using var radice = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32);
            using var chiave = radice.OpenSubKey(@"SOFTWARE\dotnet\Setup\InstalledVersions\x86");
            if (chiave?.GetValue("InstallLocation") is string posizione) cartelle.Insert(0, posizione);
        }
        catch (Exception) { }
        foreach (var cartella in cartelle)
        {
            var condivisa = Path.Combine(cartella, "shared", "Microsoft.NETCore.App");
            if (!Directory.Exists(condivisa)) continue;
            foreach (var versione in Directory.GetDirectories(condivisa))
            {
                if (Version.TryParse(Path.GetFileName(versione).Split('-')[0], out var v) && v.Major >= 8)
                {
                    registro($"Runtime .NET x86 trovato: {versione}");
                    return true;
                }
            }
        }
        registro("Runtime .NET 8 x86 assente: il filtro si registra solo per le app a 64 bit");
        return false;
    }

    private const uint COINIT_MULTITHREADED = 0x0;

    [DllImport("ole32.dll")] private static extern int CoInitializeEx(nint riservato, uint modo);
    [DllImport("ole32.dll")] private static extern void CoUninitialize();
    [DllImport("ole32.dll")] private static extern int CoCreateInstance(ref Guid clsid, nint esterno, uint contesto, ref Guid iid, out nint oggetto);
}
