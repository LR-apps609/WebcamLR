using System.Globalization;
using System.Resources;

[assembly: NeutralResourcesLanguage("it")]

namespace WebcamLR.Ricevitore;

/// <summary>
/// La lingua dei testi di WebcamLR per Windows (W2), con la stessa regola di iPhone, Mac e Android: italiano se la
/// lingua dell'interfaccia di Windows è l'italiano (it-IT, it-CH…), inglese per tutte le altre.
/// L'app la sceglie all'avvio con <see cref="Imposta"/>; di serie vale la cultura dell'interfaccia di .NET.
/// </summary>
public static class Lingua
{
    public static CultureInfo Italiano { get; } = CultureInfo.GetCultureInfo("it-IT");
    public static CultureInfo Inglese { get; } = CultureInfo.GetCultureInfo("en-US");

    private static CultureInfo scelta = Scegli(CultureInfo.CurrentUICulture);
    private static readonly AsyncLocal<CultureInfo?> provvisoria = new();

    /// <summary>Vero per ogni cultura italiana, anche quelle senza regione («it»).</summary>
    public static bool ÈItaliana(CultureInfo cultura) =>
        cultura.Name.Equals("it", StringComparison.OrdinalIgnoreCase) || cultura.Name.StartsWith("it-", StringComparison.OrdinalIgnoreCase);

    /// <summary>La lingua dei testi per una lingua di sistema: <see cref="Italiano"/> o <see cref="Inglese"/>.</summary>
    public static CultureInfo Scegli(CultureInfo sistema) => ÈItaliana(sistema) ? Italiano : Inglese;

    /// <summary>La lingua in cui escono i testi adesso (anche per i numeri: virgola o punto decimale).</summary>
    public static CultureInfo Attuale => provvisoria.Value ?? Volatile.Read(ref scelta);

    public static bool InItaliano => ReferenceEquals(Attuale, Italiano);

    /// <summary>Sceglie la lingua per tutta l'app, dalla lingua di Windows: da chiamare una volta, all'avvio.</summary>
    public static void Imposta(CultureInfo sistema) => Volatile.Write(ref scelta, Scegli(sistema));

    /// <summary>
    /// Per i test: i testi in un'altra lingua solo in questo flusso di esecuzione (anche dopo un await), senza cambiare
    /// quella degli altri test che girano in parallelo. Si torna alla lingua di prima chiudendo l'oggetto restituito.
    /// </summary>
    public static IDisposable Provvisoria(CultureInfo cultura)
    {
        var prima = provvisoria.Value;
        provvisoria.Value = Scegli(cultura);
        return new Ripristino(() => provvisoria.Value = prima);
    }

    /// <summary>
    /// Un numero con il separatore decimale della lingua: «0,9» in italiano, «0.9» in inglese. La virgola a mano, come
    /// prima: non dipende dai dati delle culture installati. Solo per formati senza separatore delle migliaia.
    /// </summary>
    public static string Decimale(double valore, string formato)
    {
        var testo = valore.ToString(formato, CultureInfo.InvariantCulture);
        return InItaliano ? testo.Replace('.', ',') : testo;
    }

    /// <summary>Un intero con il separatore delle migliaia della lingua: «20.000» in italiano, «20,000» in inglese.</summary>
    public static string Migliaia(long numero)
    {
        var testo = numero.ToString("#,0", CultureInfo.InvariantCulture);
        return InItaliano ? testo.Replace(',', '.') : testo;
    }

    private sealed class Ripristino(Action azione) : IDisposable
    {
        private Action? azione = azione;

        public void Dispose()
        {
            azione?.Invoke();
            azione = null;
        }
    }
}

/// <summary>
/// I testi del ricevitore che l'utente vede (stato, diagnosi, domande frequenti, guida, avvisi, righe del registro):
/// Risorse/Testi.resx (italiano, la lingua di partenza) e Risorse/Testi.en.resx (inglese, assembly satellite «en»).
/// Le chiavi sono le stesse nei due file; i valori usano {0}, {1}… come string.Format. Senza WinUI: va anche su Linux.
/// Come aggiungere un testo: Documenti/Windows - installazione e prova.md, «Testi in italiano e inglese».
/// </summary>
public static class TestiRicevitore
{
    private static readonly ResourceManager Risorse = new("WebcamLR.Ricevitore.Risorse.Testi", typeof(TestiRicevitore).Assembly);

    /// <summary>Il testo nella lingua attuale; la chiave stessa se manca (non succede: lo controlla un test).</summary>
    public static string T(string chiave) => Risorse.GetString(chiave, Lingua.Attuale) ?? chiave;

    /// <summary>Il testo con i valori al posto di {0}, {1}…, formattati nella lingua attuale.</summary>
    public static string T(string chiave, params object?[] valori) => string.Format(Lingua.Attuale, T(chiave), valori);

    /// <summary>Tutte le voci di una lingua, senza ripiego sull'altra: per i test.</summary>
    public static IReadOnlyDictionary<string, string> Voci(CultureInfo cultura)
    {
        // L'italiano è nell'assembly principale (lingua neutra), l'inglese nel satellite «en».
        var insieme = Risorse.GetResourceSet(
            Lingua.ÈItaliana(cultura) ? CultureInfo.InvariantCulture : CultureInfo.GetCultureInfo(cultura.TwoLetterISOLanguageName), true, false);
        var voci = new Dictionary<string, string>();
        if (insieme is null) return voci;
        foreach (System.Collections.DictionaryEntry voce in insieme)
        {
            if (voce.Key is string chiave && voce.Value is string valore) voci[chiave] = valore;
        }
        return voci;
    }
}
