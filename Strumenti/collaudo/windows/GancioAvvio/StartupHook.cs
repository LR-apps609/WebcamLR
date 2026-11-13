using System.Globalization;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Runtime.Loader;

/// <summary>
/// .NET chiama StartupHook.Initialize prima di Main, sullo stesso thread, quando DOTNET_STARTUP_HOOKS punta a questa DLL
/// (il nome della classe, senza spazio dei nomi, e del metodo li fissa .NET). Due cose, ognuna solo se chiesta:
/// <list type="bullet">
/// <item>WEBCAMLR_COLLAUDO_LINGUA («it-IT», «en-US»): la lingua dell'interfaccia. WebcamLR la sceglie da
/// CultureInfo.CurrentUICulture (Testi.Imposta), che sul runner è l'inglese di Windows.</item>
/// <item>WEBCAMLR_COLLAUDO_CONTRASTO=1: sulle macchine Windows Server di GitHub la sottoscrizione a
/// AccessibilitySettings.HighContrastChanged fallisce con 0x80070490 (elemento non trovato) e WebcamLR non parte
/// (MainWindow.PreparaFinestra). Qui l'errore si ignora: l'app parte, solo senza l'avviso di cambio del contrasto elevato,
/// che sul runner non cambia mai. Su un PC vero la sottoscrizione riesce e questo non serve.</item>
/// </list>
/// Ogni azione scrive una riga nel file WEBCAMLR_COLLAUDO_REGISTRO, se c'è.
/// </summary>
internal class StartupHook
{
    public static void Initialize()
    {
        var lingua = Environment.GetEnvironmentVariable("WEBCAMLR_COLLAUDO_LINGUA");
        if (!string.IsNullOrWhiteSpace(lingua))
        {
            try
            {
                var cultura = CultureInfo.GetCultureInfo(lingua.Trim());
                CultureInfo.DefaultThreadCurrentUICulture = cultura;
                CultureInfo.DefaultThreadCurrentCulture = cultura;
                CultureInfo.CurrentUICulture = cultura;
                CultureInfo.CurrentCulture = cultura;
                Scrivi($"lingua {cultura.Name}");
            }
            catch (CultureNotFoundException) { Scrivi($"lingua sconosciuta: {lingua}"); }
        }
        if (Environment.GetEnvironmentVariable("WEBCAMLR_COLLAUDO_CONTRASTO") == "1")
        {
            // 0Harmony.dll sta accanto a questa DLL, non accanto all'app: si carica da qui.
            var cartella = Path.GetDirectoryName(typeof(StartupHook).Assembly.Location)!;
            AssemblyLoadContext.Default.Resolving += (contesto, nome) =>
            {
                var file = Path.Combine(cartella, nome.Name + ".dll");
                return File.Exists(file) ? contesto.LoadFromAssemblyPath(file) : null;
            };
            try { Contrasto.Prepara(); }
            catch (Exception errore) { Scrivi($"contrasto: non preparato ({errore.GetType().Name}: {errore.Message})"); }
        }
    }

    internal static void Scrivi(string riga)
    {
        var file = Environment.GetEnvironmentVariable("WEBCAMLR_COLLAUDO_REGISTRO");
        if (string.IsNullOrEmpty(file)) return;
        try { File.AppendAllText(file, $"{DateTime.Now:HH:mm:ss.fff} gancio: {riga}{Environment.NewLine}"); }
        catch (IOException) { }
    }
}

internal static class Contrasto
{
    private const int ElementoNonTrovato = unchecked((int)0x80070490);

    /// <summary>La proiezione di Windows si carica solo dopo: si aspetta che arrivi, poi si mette il «finalizzatore».</summary>
    [MethodImpl(MethodImplOptions.NoInlining)]
    public static void Prepara()
    {
        foreach (var gia in AppDomain.CurrentDomain.GetAssemblies()) Prova(gia);
        AppDomain.CurrentDomain.AssemblyLoad += (_, evento) => Prova(evento.LoadedAssembly);
        StartupHook.Scrivi("contrasto: in attesa della proiezione di Windows");
    }

    private static int fatto;

    private static void Prova(Assembly assembly)
    {
        if (assembly.GetName().Name != "Microsoft.Windows.SDK.NET") return;
        if (Interlocked.Exchange(ref fatto, 1) == 1) return;
        try
        {
            var tipo = assembly.GetType("Windows.UI.ViewManagement.AccessibilitySettings", throwOnError: true)!;
            var metodo = tipo.GetMethod("add_HighContrastChanged")!;
            var harmony = new HarmonyLib.Harmony("webcamlr.collaudo.contrasto");
            harmony.Patch(metodo, finalizer: new HarmonyLib.HarmonyMethod(typeof(Contrasto).GetMethod(nameof(Finalizzatore),
                BindingFlags.Static | BindingFlags.NonPublic)));
            StartupHook.Scrivi("contrasto: errore 0x80070490 di HighContrastChanged ignorato da qui in poi");
        }
        catch (Exception errore) { StartupHook.Scrivi($"contrasto: non riuscito ({errore.GetType().Name}: {errore.Message})"); }
    }

    private static Exception? Finalizzatore(Exception? __exception)
    {
        if (__exception is COMException { HResult: ElementoNonTrovato })
        {
            StartupHook.Scrivi("contrasto: HighContrastChanged ha dato 0x80070490, ignorato");
            return null;
        }
        return __exception;
    }
}
