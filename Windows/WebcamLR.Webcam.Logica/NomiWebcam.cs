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

    public static bool WindowsSupportato(int build) => build >= BuildMinima;

    /// <summary>Senza fotogrammi nuovi da più di così, la webcam mostra l'immagine di attesa.</summary>
    public const int FrescoMs = 1000;

    /// <summary>La sorgente aggiorna il suo battito a ogni fotogramma: più vecchio di così, nessuna app usa la webcam.</summary>
    public const int InUsoMs = 2000;
}
