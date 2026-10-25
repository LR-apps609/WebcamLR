namespace WebcamLR.Ricevitore;

/// <summary>
/// «App che usano la webcam» (come «App che usano WebcamLR» sul Mac): Windows segna nelle impostazioni della privacy
/// (CapabilityAccessManager\ConsentStore\webcam) quando ogni app ha iniziato e finito di usare una fotocamera; finché la
/// fine è 0 l'app la sta usando. Windows non dice quale fotocamera: il PC mostra l'elenco solo mentre «WebcamLR» è in
/// onda, quindi sono le app che stanno usando (quasi certamente) WebcamLR. Qui i nomi leggibili, senza registro.
/// </summary>
public static class AppWebcam
{
    /// <summary>Al massimo tante app nell'elenco.</summary>
    public const int Massimo = 6;

    private static readonly Dictionary<string, string> NomiNoti = new(StringComparer.OrdinalIgnoreCase)
    {
        ["zoom"] = "Zoom",
        ["ms-teams"] = "Teams",
        ["teams"] = "Teams",
        ["msteams"] = "Teams",
        ["chrome"] = "Chrome",
        ["msedge"] = "Edge",
        ["msedgewebview2"] = "Edge",
        ["firefox"] = "Firefox",
        ["opera"] = "Opera",
        ["brave"] = "Brave",
        ["obs64"] = "OBS",
        ["obs32"] = "OBS",
        ["obs"] = "OBS",
        ["discord"] = "Discord",
        ["whatsapp"] = "WhatsApp",
        ["whatsappdesktop"] = "WhatsApp",
        ["slack"] = "Slack",
        ["skype"] = "Skype",
        ["webex"] = "Webex",
        ["ciscocollabhost"] = "Webex",
        ["atmgr"] = "Webex",
        ["windowscamera"] = "Fotocamera",
        ["telegram"] = "Telegram",
        ["signal"] = "Signal",
    };

    /// <summary>
    /// Il nome da mostrare per una chiave del registro: un percorso con «#» al posto di «\» per le app classiche
    /// («C:#Program Files#Zoom#bin#Zoom.exe» → «Zoom»), il nome del pacchetto per quelle dello Store
    /// («Microsoft.WindowsCamera_8wekyb3d8bbwe» → «Fotocamera»). Null per WebcamLR stessa e per chiavi vuote.
    /// </summary>
    public static string? Nome(string? chiave)
    {
        if (string.IsNullOrWhiteSpace(chiave)) return null;
        string base_;
        if (chiave.Contains('#') || chiave.Contains('\\'))
        {
            var percorso = chiave.Replace('#', '\\');
            base_ = Path.GetFileNameWithoutExtension(percorso.Split('\\').Last());
        }
        else
        {
            // Pacchetto: «Editore.NomeApp_firma» → «NomeApp».
            var nome = chiave.Split('_')[0];
            base_ = nome.Split('.').Last();
        }
        if (string.IsNullOrWhiteSpace(base_) || base_.Equals("WebcamLR", StringComparison.OrdinalIgnoreCase)) return null;
        if (NomiNoti.TryGetValue(base_, out var noto)) return noto;
        var leggibile = ValoriSicuri.Testo(base_, 30);
        return leggibile.Length == 0 ? null : char.ToUpperInvariant(leggibile[0]) + leggibile[1..];
    }

    /// <summary>In uso adesso: ha iniziato e non ha ancora finito (i due valori sono FILETIME, 0 = mai o in corso).</summary>
    public static bool InUso(long inizio, long fine) => inizio > 0 && fine == 0;

    /// <summary>I nomi delle app in uso, senza doppioni (Teams può comparire due volte), in ordine, al massimo <see cref="Massimo"/>.</summary>
    public static IReadOnlyList<string> Elenco(IEnumerable<(string Chiave, long Inizio, long Fine)> voci) =>
        voci.Where(v => InUso(v.Inizio, v.Fine)).Select(v => Nome(v.Chiave)).OfType<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase).Order(StringComparer.CurrentCultureIgnoreCase).Take(Massimo).ToList();
}
