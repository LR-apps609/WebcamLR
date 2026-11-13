using System.Globalization;

/// <summary>
/// .NET chiama StartupHook.Initialize prima di Main, sullo stesso thread, quando DOTNET_STARTUP_HOOKS punta a questa DLL.
/// WebcamLR sceglie la lingua da CultureInfo.CurrentUICulture (Testi.Imposta, Lingua.Imposta): qui la si imposta dalla
/// variabile WEBCAMLR_COLLAUDO_LINGUA («it-IT», «en-US»…). Senza variabile non cambia nulla. Il nome della classe (senza
/// spazio dei nomi) e del metodo li fissa .NET.
/// </summary>
internal class StartupHook
{
    public static void Initialize()
    {
        var lingua = Environment.GetEnvironmentVariable("WEBCAMLR_COLLAUDO_LINGUA");
        if (string.IsNullOrWhiteSpace(lingua)) return;
        try
        {
            var cultura = CultureInfo.GetCultureInfo(lingua.Trim());
            CultureInfo.DefaultThreadCurrentUICulture = cultura;
            CultureInfo.DefaultThreadCurrentCulture = cultura;
            CultureInfo.CurrentUICulture = cultura;
            CultureInfo.CurrentCulture = cultura;
        }
        catch (CultureNotFoundException) { }
    }
}
