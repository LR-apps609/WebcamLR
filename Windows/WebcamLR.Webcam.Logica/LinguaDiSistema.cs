using System.Globalization;
using System.Runtime.InteropServices;

namespace WebcamLR.Webcam;

/// <summary>
/// La lingua dell'interfaccia di Windows per chi consegna i fotogrammi, quando l'app non ha scritto la sua.
/// Dentro Frame Server (LocalService) è quella del sistema, scelta all'installazione di Windows; dentro un'app
/// (filtro DirectShow) quella dell'utente. Mai un'eccezione: nel dubbio, la cultura di .NET.
/// </summary>
public static class LinguaDiSistema
{
    public static LinguaAttesa Leggi()
    {
        try
        {
            if (OperatingSystem.IsWindows()) return Lingue.DaLangId(GetUserDefaultUILanguage());
        }
        catch (Exception) { }
        try { return Lingue.DaCultura(CultureInfo.CurrentUICulture); }
        catch (Exception) { return LinguaAttesa.Inglese; }
    }

    [DllImport("kernel32.dll")]
    private static extern ushort GetUserDefaultUILanguage();
}
