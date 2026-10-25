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
    /// L'app si installa per l'utente, senza amministratore, dove Windows mette le app di un utente solo
    /// («%LOCALAPPDATA%\Programs», come Visual Studio Code): così si aggiorna senza chiedere permessi.
    /// La webcam no: Frame Server (LocalService) non legge la cartella dell'utente, quindi WebcamLR.Webcam.Installa.exe,
    /// con il permesso dell'amministratore, la copia in «C:\Program Files\WebcamLR\Webcam» (<see cref="NomiWebcam.SottocartellaProgrammi"/>).
    /// </summary>
    public const string SottocartellaApp = @"Programs\WebcamLR";

    /// <summary>La chiave di «App installate» (Impostazioni → App), in HKCU: l'installazione è dell'utente.</summary>
    public const string ChiaveDisinstallazione = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\WebcamLR";

    /// <summary>Il nome della risorsa con l'app compressa, dentro l'installatore.</summary>
    public const string RisorsaPacchetto = "Pacchetto.zip";

    /// <summary>Il registro dell'installazione, in «%LOCALAPPDATA%\WebcamLR», accanto al registro del filtro DirectShow.</summary>
    public const string FileRegistro = "Installazione.txt";
}

/// <summary>
/// Dove va ogni cosa, a partire dalle cartelle di Windows (passate da fuori: così si prova anche su Linux).
/// </summary>
/// <param name="DatiLocali">«C:\Users\nome\AppData\Local» (Environment.SpecialFolder.LocalApplicationData).</param>
/// <param name="MenuStart">«…\AppData\Roaming\Microsoft\Windows\Start Menu\Programs» (Environment.SpecialFolder.Programs): dell'utente.</param>
/// <param name="ProgrammiWindows">«C:\Program Files» (a 64 bit): solo per la webcam.</param>
public sealed record Percorsi(string DatiLocali, string MenuStart, string ProgrammiWindows)
{
    private static string Unisci(params string[] parti) => string.Join('\\', parti.Select(p => p.Trim('\\')));

    /// <summary>«%LOCALAPPDATA%\Programs\WebcamLR».</summary>
    public string CartellaApp => Unisci(DatiLocali, DatiProdotto.SottocartellaApp);

    public string Eseguibile => Unisci(CartellaApp, DatiProdotto.Eseguibile);
    public string Disinstallatore => Unisci(CartellaApp, DatiProdotto.Disinstallatore);
    public string Collegamento => Unisci(MenuStart, DatiProdotto.Collegamento);

    /// <summary>L'installatore della webcam nella cartella «Webcam» accanto a WebcamLR.exe, come nella build di sviluppo.</summary>
    public string InstallatoreWebcam => Unisci(CartellaApp, NomiWebcam.CartellaAccantoAllApp, NomiWebcam.FileInstallatore);

    /// <summary>Dove l'installatore della webcam copia la sorgente: sempre diversa da <see cref="CartellaApp"/>.</summary>
    public string CartellaWebcamInstallata => Unisci(ProgrammiWindows, NomiWebcam.SottocartellaProgrammi);

    /// <summary>«%LOCALAPPDATA%\WebcamLR\Installazione.txt».</summary>
    public string Registro => Unisci(DatiLocali, DatiProdotto.Nome, DatiProdotto.FileRegistro);
}
