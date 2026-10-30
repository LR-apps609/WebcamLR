using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>Che cosa fa l'installatore rispetto a ciò che c'è già sul PC: decide il titolo e il pulsante della prima finestra.</summary>
public enum CasoInstallazione
{
    /// <summary>WebcamLR non c'è: «Installa».</summary>
    Nuova,
    /// <summary>C'è una versione più vecchia: «Aggiorna».</summary>
    Aggiornamento,
    /// <summary>C'è la stessa versione: «Installa di nuovo» (ripara i file).</summary>
    StessaVersione,
    /// <summary>C'è una versione più recente: «Installa comunque».</summary>
    PiuRecenteInstallata,
}

/// <summary>Come è andata la configurazione del PC (firewall e webcam, con il permesso dell'amministratore): il testo della finestra finale.</summary>
public enum EsitoConfigurazione
{
    /// <summary>Tutto a posto, niente da aggiungere.</summary>
    Riuscita,
    /// <summary>Tutto a posto e la webcam è nuova: le app di chiamata già aperte vanno riaperte.</summary>
    WebcamInstallata,
    /// <summary>L'utente ha detto no al Controllo account utente: niente firewall né webcam (si fanno dopo).</summary>
    SenzaPermesso,
    /// <summary>Un altro problema: la finestra finale dice quale (CodiciInstallazione.Descrivi).</summary>
    Problema,
}

/// <summary>
/// Le decisioni dell'installatore (windows.md N6, 1.0 beta 4). Prima erano cinque MessageBox in fila (cosa faccio, .NET,
/// la webcam, l'avviso del permesso, la fine), con icone e pulsanti diversi. Adesso due Task Dialog di sistema e il
/// Controllo account utente: la prima dice cosa succede (anche .NET da scaricare e WebcamLR aperta), ha la casella
/// «Installa anche la webcam per Zoom, Teams…» e l'avviso del permesso nel piede; la seconda dice com'è andata e offre
/// «Apri WebcamLR». Qui le regole, senza Windows: si provano con dotnet test.
/// </summary>
public static class PianoInstallazione
{
    /// <summary>
    /// La webcam per le altre app si installa da Windows 10 1809 (build 17763: filtro DirectShow; da Windows 11 Media
    /// Foundation). Prima la casella non c'è.
    /// </summary>
    public const int BuildMinimaWebcam = 17763;

    public static CasoInstallazione Caso(string? installata, string nuova)
    {
        if (string.IsNullOrWhiteSpace(installata)) return CasoInstallazione.Nuova;
        var confronto = Versioni.Confronta(installata, nuova);
        return confronto < 0 ? CasoInstallazione.Aggiornamento
            : confronto == 0 ? CasoInstallazione.StessaVersione
            : CasoInstallazione.PiuRecenteInstallata;
    }

    /// <summary>
    /// La casella «Installa anche la webcam…» si mostra solo se la webcam non c'è ancora e questo Windows la può avere.
    /// Se c'è già si aggiorna da sola insieme all'app (la sorgente nuova deve combaciare con l'app nuova): niente domanda.
    /// </summary>
    public static bool MostraCasellaWebcam(bool webcamGiaInstallata, int buildWindows) =>
        !webcamGiaInstallata && buildWindows >= BuildMinimaWebcam;

    /// <summary>
    /// Se configurare anche la webcam: già installata sì (si aggiorna); altrimenti la casella spuntata (spuntata di
    /// serie) o, senza domande («/silenzioso»), l'argomento «/webcam». Mai dove Windows non la può avere.
    /// </summary>
    public static bool WebcamDaConfigurare(bool webcamGiaInstallata, int buildWindows, bool silenzioso, bool argomentoWebcam, bool casellaSpuntata)
    {
        if (webcamGiaInstallata) return true;
        if (buildWindows < BuildMinimaWebcam) return false;
        return silenzioso ? argomentoWebcam : casellaSpuntata;
    }

    /// <summary>Il permesso dell'amministratore serve sempre (la regola del firewall per le reti private): «Installa» ha lo scudo.</summary>
    public static bool ServeAmministratore => true;

    /// <summary>Com'è andata la configurazione, dal codice di WebcamLR.Webcam.Installa.exe «configura».</summary>
    public static EsitoConfigurazione Esito(int codice, bool webcamConfigurata, bool webcamGiaInstallata) => codice switch
    {
        CodiciInstallazione.Annullata => EsitoConfigurazione.SenzaPermesso,
        CodiciInstallazione.Riuscita => webcamConfigurata && !webcamGiaInstallata
            ? EsitoConfigurazione.WebcamInstallata : EsitoConfigurazione.Riuscita,
        _ => EsitoConfigurazione.Problema,
    };
}
