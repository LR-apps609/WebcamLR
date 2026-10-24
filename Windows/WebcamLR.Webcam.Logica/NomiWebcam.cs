namespace WebcamLR.Webcam;

/// <summary>
/// I nomi che l'app, la sorgente della webcam (dentro il servizio Frame Server di Windows) e l'installatore
/// devono avere uguali. Cambiarli vuol dire reinstallare la webcam.
/// </summary>
public static class NomiWebcam
{
    /// <summary>Il nome dato a MFCreateVirtualCamera.</summary>
    public const string Nome = "WebcamLR";

    /// <summary>
    /// Vero se il nome di una fotocamera elencata da Windows è la nostra. Windows aggiunge da sé un'indicazione al nome
    /// passato a MFCreateVirtualCamera (documentazione: «The pipeline will automatically append "Windows Virtual Camera"»):
    /// le app vedono «WebcamLR (Windows Virtual Camera)», o «… (Windows Test Virtual Camera)» su alcune build.
    /// Chi controlla se la webcam è installata deve usare questo, non l'uguaglianza con <see cref="Nome"/>.
    /// </summary>
    public static bool ÈLaWebcam(string? nomeElencato)
    {
        if (string.IsNullOrWhiteSpace(nomeElencato)) return false;
        var nome = nomeElencato.Trim();
        if (string.Equals(nome, Nome, StringComparison.OrdinalIgnoreCase)) return true;
        return nome.StartsWith(Nome + " (", StringComparison.OrdinalIgnoreCase) && nome.EndsWith(')')
            && nome.Contains("Virtual Camera", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>CLSID della classe COM che Frame Server crea (AttivatoreWebcam, un IMFActivate).</summary>
    public const string Clsid = "db0f4591-f583-4051-8a52-367e59ee3984";

    /// <summary>Come lo vuole MFCreateVirtualCamera: tra graffe.</summary>
    public static string ClsidTraGraffe => "{" + Clsid + "}";

    /// <summary>
    /// Memoria condivisa con i fotogrammi. Frame Server gira come LocalService nella sessione 0, l'app nella
    /// sessione dell'utente: serve lo spazio dei nomi «Global\». Un processo normale non può creare oggetti in
    /// «Global\» (manca SeCreateGlobalPrivilege) ma può aprirli: per questo li crea la sorgente, l'app li apre.
    /// </summary>
    public const string NomeMemoria = @"Global\WebcamLR.Video";

    /// <summary>Evento (a reset automatico) che l'app segnala dopo ogni fotogramma scritto.</summary>
    public const string NomeEvento = @"Global\WebcamLR.Video.Nuovo";

    /// <summary>
    /// Chi può aprire la memoria condivisa: sistema e LocalService (Frame Server) tutto, amministratori tutto,
    /// utenti collegati al PC (anche da Desktop remoto: SID «IU», INTERACTIVE) lettura e scrittura.
    /// Gli oggetti senza etichetta d'integrità valgono «media», quindi l'app normale (media) può scrivere.
    /// </summary>
    public const string SddlMemoria = "D:P(A;;GA;;;SY)(A;;GA;;;LS)(A;;GA;;;BA)(A;;GRGW;;;IU)";

    /// <summary>Per l'evento basta lo stesso elenco; GA perché l'app deve poterlo segnalare (EVENT_MODIFY_STATE).</summary>
    public const string SddlEvento = "D:P(A;;GA;;;SY)(A;;GA;;;LS)(A;;GA;;;BA)(A;;GA;;;IU)";

    /// <summary>
    /// Dove l'installatore copia la sorgente, sotto «C:\Program Files»: Frame Server (LocalService) non può leggere
    /// la cartella dell'utente, dove l'app viene compilata.
    /// </summary>
    public const string SottocartellaProgrammi = @"WebcamLR\Webcam";

    /// <summary>Registro della sorgente, in «C:\ProgramData»: lo scrive LocalService, l'utente lo può leggere.</summary>
    public const string SottocartellaRegistro = "WebcamLR";
    public const string FileRegistro = "Registro webcam.txt";

    public const string FileSorgente = "WebcamLR.Webcam.dll";
    public const string FileComHost = "WebcamLR.Webcam.comhost.dll";
    public const string FileInstallatore = "WebcamLR.Webcam.Installa.exe";
    /// <summary>La cartella accanto a WebcamLR.exe dove la build mette sorgente e installatore.</summary>
    public const string CartellaAccantoAllApp = "Webcam";

    /// <summary>MFCreateVirtualCamera c'è da Windows 11 (build 22000).</summary>
    public const int BuildMinima = 22000;

    /// <summary>Vero se questo Windows sa creare la webcam Media Foundation (Windows 11). Su Windows 10 c'è il filtro DirectShow.</summary>
    public static bool WindowsSupportato(int build) => build >= BuildMinima;

    /// <summary>
    /// Quale webcam si installa: Media Foundation su Windows 11 (la vedono tutte le app, anche Fotocamera), il filtro
    /// DirectShow su Windows 10. Su Windows 11 il filtro non si registra: Chrome vedrebbe due «WebcamLR».
    /// </summary>
    public static TipoWebcam TipoPer(int build) => WindowsSupportato(build) ? TipoWebcam.MediaFoundation : TipoWebcam.DirectShow;

    // ── Filtro DirectShow (Windows 10, P23) ────────────────────────

    /// <summary>
    /// CLSID del filtro DirectShow (FiltroWebcam), diverso da quello della sorgente Media Foundation: sono due classi
    /// COM in due DLL. Lo stesso CLSID vale per la DLL a 64 bit e per quella a 32 bit (registro WOW6432Node).
    /// </summary>
    public const string ClsidDirectShow = "70917e66-b31c-4a4d-b96d-cf8768d7f45b";

    public static string ClsidDirectShowTraGraffe => "{" + ClsidDirectShow + "}";

    /// <summary>Il nome nell'elenco delle videocamere delle app (FriendlyName): senza aggiunte, a differenza di Windows 11.</summary>
    public const string NomeDirectShow = Nome;

    /// <summary>La chiave della categoria «dispositivi di cattura video» (CLSID_VideoInputDeviceCategory) sotto HKLM.</summary>
    public const string ChiaveCategoriaVideo = @"SOFTWARE\Classes\CLSID\{860bb310-5d01-11d0-bd3b-00a0c911ce86}\Instance";

    /// <summary>Dove IFilterMapper2 scrive il filtro nella categoria: le app lo trovano lì.</summary>
    public static string ChiaveIstanzaDirectShow => ChiaveCategoriaVideo + "\\" + ClsidDirectShowTraGraffe;

    public static string ChiaveClsidDirectShow => @"SOFTWARE\Classes\CLSID\" + ClsidDirectShowTraGraffe;

    public const string FileFiltro = "WebcamLR.Webcam.DirectShow.dll";
    public const string FileComHostFiltro = "WebcamLR.Webcam.DirectShow.comhost.dll";

    /// <summary>
    /// La copia a 32 bit del filtro, per le app a 32 bit: sottocartella di «Webcam» accanto all'app e di quella in
    /// Programmi. Serve anche il runtime .NET 8 a 32 bit (x86), che l'SDK a 64 bit non installa.
    /// </summary>
    public const string SottocartellaX86 = "x86";

    /// <summary>Registro del filtro, nella cartella dell'utente: gira dentro Zoom, Chrome, OBS…, come l'utente.</summary>
    public const string FileRegistroDirectShow = "Registro webcam DirectShow.txt";

    /// <summary>
    /// Memoria condivisa per il filtro DirectShow: lo spazio «Local\» della sessione dell'utente. Senza Frame Server
    /// il filtro gira dentro ogni app, nella stessa sessione di WebcamLR: non serve «Global\», che un processo normale
    /// non può creare. La crea chi arriva prima (l'app o il filtro), gli altri la aprono.
    /// </summary>
    public const string NomeMemoriaLocale = @"Local\WebcamLR.Video";

    public const string NomeEventoLocale = @"Local\WebcamLR.Video.Nuovo";

    /// <summary>
    /// Sistema, amministratori e utenti collegati tutto (un'app avviata come amministratore e Zoom normale si vedono),
    /// più l'etichetta d'integrità bassa (ML…LW): anche un'app che cattura da un processo a integrità bassa può segnare
    /// il suo battito. Senza etichetta l'oggetto varrebbe «media» e un processo basso lo potrebbe solo leggere.
    /// </summary>
    public const string SddlLocale = "D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;IU)S:(ML;;NW;;;LW)";

    /// <summary>Senza fotogrammi nuovi da più di così, la webcam mostra l'immagine di attesa.</summary>
    public const int FrescoMs = 1000;

    /// <summary>La sorgente aggiorna il suo battito a ogni fotogramma: più vecchio di così, nessuna app usa la webcam.</summary>
    public const int InUsoMs = 2000;
}

/// <summary>Le due webcam di WebcamLR: una sola per PC, secondo la versione di Windows.</summary>
public enum TipoWebcam
{
    /// <summary>Windows 11: MFCreateVirtualCamera e la sorgente dentro Frame Server.</summary>
    MediaFoundation,
    /// <summary>Windows 10: il filtro DirectShow dentro ogni app che apre la webcam.</summary>
    DirectShow,
}

/// <summary>I nomi e i permessi di un anello di fotogrammi: quello globale di Windows 11 o quello locale di Windows 10.</summary>
public sealed record NomiAnello(string Memoria, string Evento, string SddlMemoria, string SddlEvento)
{
    /// <summary>Windows 11: la sorgente in Frame Server (sessione 0) lo crea, l'app lo apre.</summary>
    public static NomiAnello Globale { get; } = new(NomiWebcam.NomeMemoria, NomiWebcam.NomeEvento, NomiWebcam.SddlMemoria, NomiWebcam.SddlEvento);

    /// <summary>Windows 10: l'app e il filtro DirectShow, nella stessa sessione; lo crea chi arriva prima.</summary>
    public static NomiAnello Locale { get; } = new(NomiWebcam.NomeMemoriaLocale, NomiWebcam.NomeEventoLocale, NomiWebcam.SddlLocale, NomiWebcam.SddlLocale);
}
