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
    /// <summary>La regola del firewall per WebcamLR (<see cref="RegolaFirewall"/>) non si è aggiunta o tolta.</summary>
    public const int FirewallFallito = 8;
    /// <summary>E_ACCESSDENIED: di solito la privacy della fotocamera spenta per le app desktop.</summary>
    public const int AccessoNegato = unchecked((int)0x80070005);
    /// <summary>E_NOTIMPL: MFCreateVirtualCamera assente (Windows 10).</summary>
    public const int NonImplementato = unchecked((int)0x80004001);

    public static bool ÈRiuscita(int codice) => codice is Riuscita or RiuscitaSenza32Bit;

    /// <summary>
    /// Cosa è successo, in italiano o in inglese (W2: la stessa regola dell'app). <see cref="LinguaAttesa.Automatica"/>
    /// vale la lingua dell'interfaccia di Windows (<see cref="LinguaDiSistema"/>): così parlano anche l'installatore e il
    /// disinstallatore, che non hanno i file dei testi dell'app.
    /// </summary>
    public static string Descrivi(int codice, LinguaAttesa lingua = LinguaAttesa.Automatica)
    {
        var it = Italiano(lingua);
        string S(string italiano, string inglese) => it ? italiano : inglese;
        return codice switch
        {
            Riuscita => S("Fatto.", "Done."),
            RiuscitaSenza32Bit => S("Fatto per le app a 64 bit (Zoom, Chrome, Edge, Firefox, OBS, Discord). Le app a 32 bit non la vedono: "
                + "per loro installa «.NET Desktop Runtime 8» x86 da https://dotnet.microsoft.com/download/dotnet/8.0 e premi «Ripara la webcam».",
                "Done for 64-bit apps (Zoom, Chrome, Edge, Firefox, OBS, Discord). 32-bit apps don’t see it: "
                + "for them, install “.NET Desktop Runtime 8” x86 from https://dotnet.microsoft.com/download/dotnet/8.0 and press “Repair the webcam”."),
            ArgomentiErrati => S("Installatore chiamato in modo sbagliato: riprova da WebcamLR.",
                "The installer was started the wrong way: try again from WebcamLR."),
            FirewallFallito => S("Non riesco a dire al firewall di Windows di lasciar passare il telefono. Alla prima apertura Windows "
                + "chiederà se consentire WebcamLR: scegli «Reti private» e premi «Consenti».",
                "I can’t tell Windows Firewall to let the phone through. The first time you open WebcamLR, Windows "
                + "will ask whether to allow it: choose “Private networks” and press “Allow”."),
            WindowsNonSupportato => S("Questa versione di Windows è troppo vecchia per la webcam: serve Windows 10 (1809 o successivo) o Windows 11.",
                "This version of Windows is too old for the webcam: you need Windows 10 (1809 or later) or Windows 11."),
            FileMancanti => S("Mancano i file della webcam accanto a WebcamLR: ricompila WebcamLR.",
                "The webcam files next to WebcamLR are missing: rebuild WebcamLR."),
            CopiaFallita => S("Non riesco a copiare la webcam in «Programmi». Chiudi le app che usano la webcam e riprova.",
                "I can’t copy the webcam to “Program Files”. Close the apps using the webcam and try again."),
            RegistroFallito => S("Non riesco a registrare la webcam in Windows.", "I can’t register the webcam in Windows."),
            Annullata => S("Annullato: Windows chiede il permesso dell'amministratore per installare la webcam.",
                "Cancelled: Windows needs administrator permission to install the webcam."),
            InstallatoreMancante => S("Non trovo l'installatore della webcam accanto a WebcamLR: ricompila WebcamLR.",
                "I can’t find the webcam installer next to WebcamLR: rebuild WebcamLR."),
            AccessoNegato => S("Windows ha negato l'accesso alla fotocamera: in Impostazioni → Privacy e sicurezza → Fotocamera "
                + "accendi «Accesso alla fotocamera» e «Consenti alle app desktop di accedere alla fotocamera», poi riprova (codice 0x80070005).",
                "Windows denied access to the camera: in Settings → Privacy & security → Camera "
                + "turn on “Camera access” and “Let desktop apps access your camera”, then try again (code 0x80070005)."),
            NonImplementato => S("Questo Windows non sa creare webcam Media Foundation: su Windows 10 WebcamLR installa il filtro DirectShow.",
                "This Windows can’t create Media Foundation webcams: on Windows 10 WebcamLR installs the DirectShow filter."),
            _ when codice < 0 => S($"Windows ha rifiutato la webcam (codice 0x{codice:X8}).", $"Windows refused the webcam (code 0x{codice:X8})."),
            _ => S($"Qualcosa non ha funzionato (codice {codice}): riprova, e se succede ancora scrivici da «Segnala un bug».",
                $"Something went wrong (code {codice}): try again, and if it happens again write to us with “Report a bug”."),
        };
    }

    /// <summary>Riga da mostrare sotto il titolo della scheda «Webcam per le altre app», nella lingua chiesta.</summary>
    public static string Descrivi(StatoWebcam stato, TipoWebcam tipo = TipoWebcam.MediaFoundation, LinguaAttesa lingua = LinguaAttesa.Automatica)
    {
        var it = Italiano(lingua);
        string S(string italiano, string inglese) => it ? italiano : inglese;
        return (stato, tipo) switch
        {
            (StatoWebcam.NonInstallata, TipoWebcam.DirectShow) => S("Installa la webcam «WebcamLR» per usare il telefono in Zoom, Meet e nei siti "
                + "(Chrome, Edge, Firefox), in OBS e Discord. Su Windows 10 non compare nell'app Fotocamera di Windows e il nuovo Teams può "
                + "non vederla: lì usa Teams nel browser. Serve una volta sola, con il permesso dell'amministratore.",
                "Install the “WebcamLR” webcam to use the phone in Zoom, Meet and on websites "
                + "(Chrome, Edge, Firefox), in OBS and Discord. On Windows 10 it doesn’t appear in the Windows Camera app and the new Teams may "
                + "not see it: there, use Teams in the browser. You only need to do this once, with administrator permission."),
            (StatoWebcam.NonInstallata, _) => S("Installa la webcam «WebcamLR» per usare il telefono in Zoom, Teams, Meet, WhatsApp, OBS e nei siti. "
                + "Serve una volta sola, con il permesso dell'amministratore.",
                "Install the “WebcamLR” webcam to use the phone in Zoom, Teams, Meet, WhatsApp, OBS and on websites. "
                + "You only need to do this once, with administrator permission."),
            (StatoWebcam.DaRiparare, _) => S("La webcam è installata solo in parte: ripara l'installazione.",
                "The webcam is only partly installed: repair the installation."),
            (StatoWebcam.Installata, TipoWebcam.DirectShow) => S("«WebcamLR» è nell'elenco delle videocamere di Zoom, dei browser, di OBS e delle "
                + "altre app. Senza telefono mostra un'immagine di attesa. Un'app già aperta va chiusa e riaperta per vederla.",
                "“WebcamLR” is in the camera list of Zoom, browsers, OBS and other "
                + "apps. Without a phone it shows a waiting image. An app that’s already open must be closed and reopened to see it."),
            (StatoWebcam.Installata, _) => S("«WebcamLR» è nell'elenco delle videocamere di tutte le app. Senza telefono mostra un'immagine di attesa.",
                "“WebcamLR” is in the camera list of every app. Without a phone it shows a waiting image."),
            (StatoWebcam.InUso, _) => S("Un'app sta usando la webcam «WebcamLR» adesso.", "An app is using the “WebcamLR” webcam right now."),
            _ => "",
        };
    }

    private static bool Italiano(LinguaAttesa lingua) =>
        Lingue.Risolvi(lingua, lingua == LinguaAttesa.Automatica ? LinguaDiSistema.Leggi() : LinguaAttesa.Inglese) == LinguaAttesa.Italiano;
}
