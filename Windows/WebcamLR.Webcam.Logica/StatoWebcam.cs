namespace WebcamLR.Webcam;

/// <summary>Lo stato della webcam WebcamLR su questo PC, come lo mostra l'app.</summary>
public enum StatoWebcam
{
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
    /// <summary>
    /// Windows 10: filtro DirectShow installato per le app a 64 bit ma non per quelle a 32 bit, perché manca il
    /// runtime .NET 8 x86 (o la copia a 32 bit del filtro). È comunque una riuscita.
    /// </summary>
    public const int RiuscitaSenza32Bit = 7;
    /// <summary>E_ACCESSDENIED: di solito la privacy della fotocamera spenta per le app desktop.</summary>
    public const int AccessoNegato = unchecked((int)0x80070005);
    /// <summary>E_NOTIMPL: MFCreateVirtualCamera assente (Windows 10).</summary>
    public const int NonImplementato = unchecked((int)0x80004001);

    public static bool ÈRiuscita(int codice) => codice is Riuscita or RiuscitaSenza32Bit;

    public static string Descrivi(int codice) => codice switch
    {
        Riuscita => "Fatto.",
        RiuscitaSenza32Bit => "Fatto per le app a 64 bit (Zoom, Chrome, Edge, Firefox, OBS, Discord). Le app a 32 bit non la vedono: "
            + "per loro installa «.NET Desktop Runtime 8» x86 da https://dotnet.microsoft.com/download/dotnet/8.0 e premi «Ripara la webcam».",
        ArgomentiErrati => "Installatore chiamato in modo sbagliato: riprova da WebcamLR.",
        WindowsNonSupportato => "Questa versione di Windows è troppo vecchia per la webcam: serve Windows 10 (1809 o successivo) o Windows 11.",
        FileMancanti => "Mancano i file della webcam accanto a WebcamLR: ricompila WebcamLR.",
        CopiaFallita => "Non riesco a copiare la webcam in «Programmi». Chiudi le app che usano la webcam e riprova.",
        RegistroFallito => "Non riesco a registrare la webcam in Windows.",
        Annullata => "Annullato: Windows chiede il permesso dell'amministratore per installare la webcam.",
        InstallatoreMancante => "Non trovo l'installatore della webcam accanto a WebcamLR: ricompila WebcamLR.",
        AccessoNegato => "Windows ha negato l'accesso alla fotocamera: in Impostazioni → Privacy e sicurezza → Fotocamera "
            + "accendi «Accesso alla fotocamera» e «Consenti alle app desktop di accedere alla fotocamera», poi riprova (codice 0x80070005).",
        NonImplementato => "Questo Windows non sa creare webcam Media Foundation: su Windows 10 WebcamLR installa il filtro DirectShow.",
        _ when codice < 0 => $"Windows ha rifiutato la webcam (codice 0x{codice:X8}).",
        _ => $"Qualcosa non ha funzionato (codice {codice}): riprova, e se succede ancora scrivici da «Segnala un bug».",
    };

    /// <summary>Riga da mostrare sotto il titolo della scheda «Webcam per le altre app».</summary>
    public static string Descrivi(StatoWebcam stato, TipoWebcam tipo = TipoWebcam.MediaFoundation) => (stato, tipo) switch
    {
        (StatoWebcam.NonInstallata, TipoWebcam.DirectShow) => "Installa la webcam «WebcamLR» per usare il telefono in Zoom, Meet e nei siti "
            + "(Chrome, Edge, Firefox), in OBS e Discord. Su Windows 10 non compare nell'app Fotocamera di Windows e il nuovo Teams può "
            + "non vederla: lì usa Teams nel browser. Serve una volta sola, con il permesso dell'amministratore.",
        (StatoWebcam.NonInstallata, _) => "Installa la webcam «WebcamLR» per usare il telefono in Zoom, Teams, Meet, WhatsApp, OBS e nei siti. "
            + "Serve una volta sola, con il permesso dell'amministratore.",
        (StatoWebcam.DaRiparare, _) => "La webcam è installata solo in parte: ripara l'installazione.",
        (StatoWebcam.Installata, TipoWebcam.DirectShow) => "«WebcamLR» è nell'elenco delle videocamere di Zoom, dei browser, di OBS e delle "
            + "altre app. Senza telefono mostra un'immagine di attesa. Un'app già aperta va chiusa e riaperta per vederla.",
        (StatoWebcam.Installata, _) => "«WebcamLR» è nell'elenco delle videocamere di tutte le app. Senza telefono mostra un'immagine di attesa.",
        (StatoWebcam.InUso, _) => "Un'app sta usando la webcam «WebcamLR» adesso.",
        _ => "",
    };
}
