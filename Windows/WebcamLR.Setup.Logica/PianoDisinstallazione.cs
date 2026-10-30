using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>Com'è andata la parte con il permesso dell'amministratore (webcam e firewall): il testo della finestra finale.</summary>
public enum EsitoDisinstallazione
{
    /// <summary>Tolto tutto (o non c'era niente da togliere con il permesso).</summary>
    Riuscita,
    /// <summary>L'utente ha detto no al Controllo account utente e la webcam c'è ancora: lo si dice nel piede.</summary>
    WebcamRimasta,
    /// <summary>Un altro problema: finisce nel registro, come prima (la finestra finale non lo dice).</summary>
    Problema,
}

/// <summary>
/// Le decisioni del disinstallatore (1.0 beta 4, come PianoInstallazione): al posto di due MessageBox («OK/Annulla» e il
/// messaggio finale) le stesse Task Dialog dell'installatore (FinestraDomanda). La prima chiede, con «Annulla»
/// predefinito (togliere non è mai la scelta più comoda) e lo scudo su «Disinstalla» se Windows chiederà il permesso
/// dell'amministratore; la seconda dice com'è andata, con «Chiudi» soltanto. Qui le regole, senza Windows: si provano con
/// dotnet test.
/// </summary>
public static class PianoDisinstallazione
{
    /// <summary>
    /// Il permesso dell'amministratore serve solo se c'è l'installatore della webcam nella cartella dell'app: è lui che
    /// toglie la webcam e la regola del firewall. Senza, «Disinstalla» non ha lo scudo.
    /// </summary>
    public static bool ServeAmministratore(bool installatoreWebcamPresente) => installatoreWebcamPresente;

    /// <summary>
    /// Il pulsante predefinito della prima finestra è «Annulla» (il secondo): Invio non disinstalla per sbaglio. Esc e
    /// la X valgono «Annulla» comunque.
    /// </summary>
    public const bool PredefinitoAnnulla = true;

    /// <summary>
    /// Com'è andata, dal codice di WebcamLR.Webcam.Installa.exe «disinstalla» (null se non è partito perché manca) e da
    /// se la webcam è ancora registrata dopo. Le stesse regole di prima: il «no» al permesso si dice solo se la webcam è
    /// rimasta; gli altri problemi vanno nel registro.
    /// </summary>
    public static EsitoDisinstallazione Esito(int? codice, bool webcamAncoraRegistrata) => codice switch
    {
        null or CodiciInstallazione.Riuscita => EsitoDisinstallazione.Riuscita,
        CodiciInstallazione.Annullata => webcamAncoraRegistrata ? EsitoDisinstallazione.WebcamRimasta : EsitoDisinstallazione.Riuscita,
        _ => EsitoDisinstallazione.Problema,
    };
}
