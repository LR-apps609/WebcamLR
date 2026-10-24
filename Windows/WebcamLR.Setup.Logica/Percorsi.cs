using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>Nomi fissi dell'installazione. Cambiarli vuol dire lasciare indietro le installazioni vecchie.</summary>
public static class DatiProdotto
{
    public const string Nome = "WebcamLR";
    public const string Editore = "LR Apps";
    public const string Sito = "https://lr-apps609.github.io/WebcamLR/";
    public const string Eseguibile = "WebcamLR.exe";
    public const string Disinstallatore = "Disinstalla WebcamLR.exe";
    public const string Collegamento = "WebcamLR.lnk";

    /// <summary>
    /// L'app sta in «C:\Program Files\WebcamLR\App», non direttamente in «…\WebcamLR»: lì accanto, in «…\WebcamLR\Webcam»,
    /// l'installatore della webcam copia la sorgente per Frame Server (<see cref="NomiWebcam.SottocartellaProgrammi"/>)
    /// e la toglie con «rimuovi». Se fossero la stessa cartella, togliere la webcam cancellerebbe i file da cui l'app
    /// la reinstalla.
    /// </summary>
    public const string SottocartellaApp = @"WebcamLR\App";

    /// <summary>La chiave di «App installate» (Impostazioni → App) e del vecchio «Programmi e funzionalità», in HKLM a 64 bit.</summary>
    public const string ChiaveDisinstallazione = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WebcamLR";

    /// <summary>Il nome della risorsa con l'app compressa, dentro l'installatore.</summary>
    public const string RisorsaPacchetto = "Pacchetto.zip";
}

/// <summary>
/// Dove va ogni cosa, a partire dalle cartelle di Windows (passate da fuori: così si prova anche su Linux).
/// </summary>
/// <param name="ProgrammiWindows">«C:\Program Files» (Environment.SpecialFolder.ProgramFiles, a 64 bit).</param>
/// <param name="MenuStartComune">«C:\ProgramData\Microsoft\Windows\Start Menu\Programs» (CommonPrograms): per tutti gli utenti.</param>
public sealed record Percorsi(string ProgrammiWindows, string MenuStartComune)
{
    private static string Unisci(params string[] parti) => string.Join('\\', parti.Select(p => p.Trim('\\')));

    /// <summary>«C:\Program Files\WebcamLR\App».</summary>
    public string CartellaApp => Unisci(ProgrammiWindows, DatiProdotto.SottocartellaApp);

    /// <summary>«C:\Program Files\WebcamLR»: si cancella alla fine della disinstallazione, se resta vuota.</summary>
    public string CartellaProdotto => Unisci(ProgrammiWindows, DatiProdotto.Nome);

    public string Eseguibile => Unisci(CartellaApp, DatiProdotto.Eseguibile);
    public string Disinstallatore => Unisci(CartellaApp, DatiProdotto.Disinstallatore);
    public string Collegamento => Unisci(MenuStartComune, DatiProdotto.Collegamento);

    /// <summary>L'installatore della webcam nella cartella «Webcam» accanto a WebcamLR.exe, come nella build di sviluppo.</summary>
    public string InstallatoreWebcam => Unisci(CartellaApp, NomiWebcam.CartellaAccantoAllApp, NomiWebcam.FileInstallatore);

    /// <summary>Dove l'installatore della webcam copia la sorgente: deve restare diversa da <see cref="CartellaApp"/>.</summary>
    public string CartellaWebcamInstallata => Unisci(ProgrammiWindows, NomiWebcam.SottocartellaProgrammi);
}
