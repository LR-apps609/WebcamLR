using System.Globalization;
using Microsoft.Windows.ApplicationModel.Resources;
using WebcamLR.Ricevitore;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// I testi dell'app in italiano o in inglese (W2), come su iPhone, Mac e Android: italiano se la lingua
/// dell'interfaccia di Windows è l'italiano, altrimenti inglese.
///
/// - XAML: <c>x:Uid="Nome"</c> sull'elemento, e nei file Strings\it-IT\Resources.resw e Strings\en-US\Resources.resw
///   le voci «Nome.Text», «Nome.Content», «Nome.[using:Microsoft.UI.Xaml.Controls]ToolTipService.ToolTip»…
/// - C#: <c>Testi.T("Chiave")</c>, oppure <c>Testi.T("Chiave", valori…)</c> con {0}, {1}… nel testo.
/// - I testi della logica comune (stato, diagnosi, domande frequenti…) stanno in WebcamLR.Ricevitore
///   (<see cref="TestiRicevitore"/>), che segue la stessa lingua.
///
/// App non pacchettizzata: i .resw finiscono in WebcamLR.pri accanto all'exe e li legge MRT Core
/// (Microsoft.Windows.ApplicationModel.Resources), non il ResourceLoader di UWP, che senza pacchetto non funziona.
/// La lingua si sceglie in <see cref="Imposta"/>, chiamata dal costruttore di App prima di caricare qualsiasi XAML:
/// Microsoft.Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride (Windows App SDK 1.5 e seguenti, valido
/// anche senza pacchetto, ma non salvato: va impostato a ogni avvio) per gli x:Uid, e un contesto con la lingua scritta
/// esplicitamente per <see cref="T(string)"/>, così il codice non dipende dall'override.
/// </summary>
public static class Testi
{
    private static ResourceManager? gestore;
    private static ResourceMap? mappa;
    private static ResourceContext? contesto;

    /// <summary>Vero se l'app parla italiano.</summary>
    public static bool Italiano => Lingua.InItaliano;

    /// <summary>La cultura dei testi: anche per i numeri (virgola o punto decimale) nei valori di <see cref="T(string, object?[])"/>.</summary>
    public static CultureInfo Cultura => Lingua.Attuale;

    /// <summary>La lingua da passare alla webcam e ai testi di WebcamLR.Webcam.Logica.</summary>
    public static LinguaAttesa LinguaWebcam => Italiano ? LinguaAttesa.Italiano : LinguaAttesa.Inglese;

    /// <summary>Il nome della lingua per MRT e per l'override: «it-IT» o «en-US», come le cartelle in Strings.</summary>
    public static string NomeLingua => Italiano ? "it-IT" : "en-US";

    /// <summary>
    /// Sceglie la lingua dalla lingua dell'interfaccia di Windows (CultureInfo.CurrentUICulture, che per un'app desktop
    /// è quella dell'utente) e la comunica a XAML e al ricevitore. Mai un'eccezione: nel peggiore dei casi gli x:Uid
    /// seguono l'elenco delle lingue di Windows, che dà lo stesso risultato quasi sempre.
    /// </summary>
    public static void Imposta()
    {
        Lingua.Imposta(CultureInfo.CurrentUICulture);
        try { Microsoft.Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride = NomeLingua; }
        catch (Exception errore) { App.ScriviErrore(errore); }
        try
        {
            gestore = new ResourceManager();
            mappa = gestore.MainResourceMap.GetSubtree("Resources");
            contesto = gestore.CreateResourceContext();
            contesto.QualifierValues[KnownResourceQualifierName.Language] = NomeLingua;
        }
        catch (Exception errore)
        {
            App.ScriviErrore(errore);
            gestore = null;
            mappa = null;
            contesto = null;
        }
    }

    /// <summary>Il testo nella lingua dell'app; la chiave stessa se manca (lo controlla Strumenti/controlla_testi_windows.py).</summary>
    public static string T(string chiave)
    {
        if (mappa is null || contesto is null) return chiave;
        try { return mappa.TryGetValue(chiave, contesto)?.ValueAsString ?? chiave; }
        catch (Exception) { return chiave; }
    }

    /// <summary>Il testo con i valori al posto di {0}, {1}…, formattati nella lingua dell'app.</summary>
    public static string T(string chiave, params object?[] valori)
    {
        var modello = T(chiave);
        try { return string.Format(Cultura, modello, valori); }
        catch (FormatException) { return modello; }
    }
}
