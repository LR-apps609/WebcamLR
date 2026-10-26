using WebcamLR.Webcam;

namespace WebcamLR.Setup;

/// <summary>
/// Le finestre dell'installatore e del disinstallatore in italiano o in inglese (W2), con la regola dell'app: italiano
/// se la lingua dell'interfaccia di Windows è l'italiano, altrimenti inglese. Qui niente file di risorse: l'exe è
/// autonomo e ridotto con il trimming, e i testi sono pochi, quindi stanno accanto, a coppie. Il registro
/// («Installazione.txt») resta in italiano: è per chi aiuta.
/// </summary>
internal static class Testi
{
    /// <summary>Dalla lingua dell'utente di Windows (GetUserDefaultUILanguage): funziona anche con InvariantGlobalization.</summary>
    public static bool Italiano { get; } = LinguaDiSistema.Leggi() == LinguaAttesa.Italiano;

    public static LinguaAttesa Lingua => Italiano ? LinguaAttesa.Italiano : LinguaAttesa.Inglese;

    /// <summary>Il testo nella lingua dell'utente: prima l'italiano, poi l'inglese.</summary>
    public static string S(string italiano, string inglese) => Italiano ? italiano : inglese;
}
