namespace WebcamLR.Webcam;

/// <summary>Lo stato della webcam WebcamLR su questo PC, come lo mostra l'app.</summary>
public enum StatoWebcam
{
    /// <summary>Windows 10: MFCreateVirtualCamera non c'è (il filtro DirectShow arriverà con la 1.25).</summary>
    NonSupportata,
    NonInstallata,
    /// <summary>Registrata a metà: il componente COM c'è ma Windows non elenca la webcam (o il contrario).</summary>
    DaRiparare,
    Installata,
    /// <summary>Installata e un'app la sta usando adesso.</summary>
    InUso,
}

/// <summary>Codici d'uscita di WebcamLR.Webcam.Installa.exe. I codici negativi sono HRESULT di Windows.</summary>
public static class CodiciInstallazione
{
    public const int Riuscita = 0;
    public const int ArgomentiErrati = 1;
    public const int WindowsNonSupportato = 2;
    public const int FileMancanti = 3;
    public const int CopiaFallita = 4;
    public const int RegistroFallito = 5;
    /// <summary>L'utente ha detto no alla richiesta di Windows (Controllo account utente). Lo usa l'app, non l'installatore.</summary>
    public const int Annullata = 1223;
    public const int InstallatoreMancante = 6;
    /// <summary>E_ACCESSDENIED: di solito la privacy della fotocamera spenta per le app desktop.</summary>
    public const int AccessoNegato = unchecked((int)0x80070005);
    /// <summary>E_NOTIMPL: MFCreateVirtualCamera assente (Windows 10).</summary>
    public const int NonImplementato = unchecked((int)0x80004001);

    public static string Descrivi(int codice) => codice switch
    {
        Riuscita => "Fatto.",
        ArgomentiErrati => "Installatore chiamato in modo sbagliato: riprova da WebcamLR.",
        WindowsNonSupportato => "Serve Windows 11: su Windows 10 la webcam arriverà con un aggiornamento.",
        FileMancanti => "Mancano i file della webcam accanto a WebcamLR: ricompila WebcamLR.",
        CopiaFallita => "Non riesco a copiare la webcam in «Programmi». Chiudi le app che usano la webcam e riprova.",
        RegistroFallito => "Non riesco a registrare la webcam in Windows.",
        Annullata => "Annullato: Windows chiede il permesso dell'amministratore per installare la webcam.",
        InstallatoreMancante => "Non trovo l'installatore della webcam accanto a WebcamLR: ricompila WebcamLR.",
        AccessoNegato => "Windows ha negato l'accesso alla fotocamera: in Impostazioni → Privacy e sicurezza → Fotocamera "
            + "accendi «Accesso alla fotocamera» e «Consenti alle app desktop di accedere alla fotocamera», poi riprova (codice 0x80070005).",
        NonImplementato => "Questo Windows non sa creare webcam virtuali: serve Windows 11.",
        _ when codice < 0 => $"Windows ha rifiutato la webcam (codice 0x{codice:X8}).",
        _ => $"Errore sconosciuto ({codice}).",
    };

    /// <summary>Riga da mostrare sotto il titolo della scheda «Webcam per le altre app».</summary>
    public static string Descrivi(StatoWebcam stato) => stato switch
    {
        StatoWebcam.NonSupportata => "Su Windows 10 la webcam per Zoom, Teams e gli altri non c'è ancora: arriverà con un aggiornamento (1.25). Il video si vede comunque qui.",
        StatoWebcam.NonInstallata => "Installa la webcam «WebcamLR» per usare il telefono in Zoom, Teams, Meet, WhatsApp, OBS e nei siti. Serve una volta sola, con il permesso dell'amministratore.",
        StatoWebcam.DaRiparare => "La webcam è installata solo in parte: ripara l'installazione.",
        StatoWebcam.Installata => "«WebcamLR» è nell'elenco delle fotocamere di tutte le app. Senza telefono mostra un'immagine di attesa.",
        StatoWebcam.InUso => "Un'app sta usando la webcam «WebcamLR» adesso.",
        _ => "",
    };
}
