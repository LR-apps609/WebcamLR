using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// A che punto è il collegamento, per il menu e l'icona accanto all'orologio. Si chiamava «StatoCollegamento»: il nome
/// ora è del messaggio del protocollo (<c>stato.collegamento</c>); FaseCollegamento come in Stile.
/// </summary>
public enum FaseCollegamento
{
    NessunTelefono,
    Collegato,
    Riconnessione,
}

/// <summary>
/// Quale icona accanto all'orologio (1.0 beta 2, windows.md 2.10 e N3): il logo normale, con il punto corallo (in onda o
/// registrando) o con il punto ambra (riconnessione).
/// </summary>
public enum IconaNotifica
{
    Normale,
    InOnda,
    Riconnessione,
}

/// <summary>
/// Tutto quello che l'icona accanto all'orologio racconta a finestra chiusa: il collegamento, se un'app usa il video
/// (con i nomi, quando Windows li dice) e da quanto si registra.
/// </summary>
public sealed record StatoNotifica(
    FaseCollegamento Fase,
    string? NomeTelefono = null,
    int? LatenzaMs = null,
    bool InOnda = false,
    IReadOnlyList<string>? AppInUso = null,
    TimeSpan? Registrazione = null);

/// <summary>Lo stato in una riga di parole (round 2, funzioni 44 e 45), senza millisecondi.</summary>
public static class DescrizioneStato
{
    /// <summary>Windows taglia il testo dell'icona accanto all'orologio a 127 caratteri.</summary>
    public const int LunghezzaMassimaSuggerimento = 127;

    /// <summary>Per esempio «Collegato a iPhone di Ledion · Ottimo».</summary>
    public static string Riga(FaseCollegamento stato, string? nomeTelefono, int? latenzaMs = null)
    {
        var nome = string.IsNullOrWhiteSpace(nomeTelefono) ? TestiRicevitore.T("Stato_UnTelefono") : nomeTelefono.Trim();
        return stato switch
        {
            FaseCollegamento.Collegato when latenzaMs is int ms => TestiRicevitore.T("Stato_CollegatoAQualita", nome, Qualita.Da(ms).Testo()),
            FaseCollegamento.Collegato => TestiRicevitore.T("Stato_CollegatoA", nome),
            FaseCollegamento.Riconnessione => TestiRicevitore.T("Stato_RiconnessioneA", nome),
            _ => TestiRicevitore.T("Stato_NessunTelefono"),
        };
    }

    /// <summary>Nella modalità semplice: «Video in arrivo da Pixel 8», o «dal telefono» se il nome manca.</summary>
    public static string VideoInArrivo(string? nomeTelefono) =>
        string.IsNullOrWhiteSpace(nomeTelefono) ? TestiRicevitore.T("Stato_VideoDalTelefono") : TestiRicevitore.T("Stato_VideoDa", nomeTelefono.Trim());

    /// <summary>Il nome della piattaforma da mostrare («iPhone», «Android»), dal campo «piattaforma» di «ciao».</summary>
    public static string NomePiattaforma(Piattaforma piattaforma) => piattaforma switch
    {
        Piattaforma.Iphone => "iPhone",
        Piattaforma.Android => "Android",
        Piattaforma.Mac => "Mac",
        Piattaforma.Windows => "Windows",
        _ => TestiRicevitore.T("Piattaforma_Altro"),
    };

    /// <summary>Il testo al passaggio del mouse sull'icona: «WebcamLR · » e la riga, tagliato se serve.</summary>
    public static string Suggerimento(FaseCollegamento stato, string? nomeTelefono, int? latenzaMs = null) =>
        Taglia($"WebcamLR · {Riga(stato, nomeTelefono, latenzaMs)}");

    /// <summary>
    /// L'icona da mostrare. La riconnessione vince: è un problema da guardare, anche in onda (il suggerimento dice il
    /// resto); poi il punto corallo se un'app usa il video o se si registra, come la pillola e il tasto «Registra».
    /// </summary>
    public static IconaNotifica Icona(StatoNotifica stato) =>
        stato.Fase == FaseCollegamento.Riconnessione ? IconaNotifica.Riconnessione
        : stato.InOnda || stato.Registrazione is not null ? IconaNotifica.InOnda
        : IconaNotifica.Normale;

    /// <summary>
    /// La riga di stato del menu, con «in onda» e la registrazione: «In onda su Zoom · Registrazione 12:31». In onda con
    /// il telefono collegato basta «In onda su Zoom» (il collegamento va bene, altrimenti non si sarebbe in onda); in
    /// riconnessione o senza telefono si dicono tutte e due le cose.
    /// </summary>
    public static string Riga(StatoNotifica stato)
    {
        var parti = new List<string>();
        if (!(stato.InOnda && stato.Fase == FaseCollegamento.Collegato)) parti.Add(Riga(stato.Fase, stato.NomeTelefono, stato.LatenzaMs));
        if (stato.InOnda) parti.Add(InOnda(stato.AppInUso));
        if (stato.Registrazione is { } durata) parti.Add(TestiRicevitore.T("Stato_Registrazione", Riprese.Durata(durata)));
        return string.Join(" · ", parti);
    }

    /// <summary>Al passaggio del mouse: «WebcamLR · In onda su Zoom · Registrazione 12:31», al massimo 127 caratteri.</summary>
    public static string Suggerimento(StatoNotifica stato) => Taglia($"WebcamLR · {Riga(stato)}");

    /// <summary>«In onda su Zoom», «In onda su Zoom e Teams»; «In onda» se Windows non dice quale app.</summary>
    public static string InOnda(IReadOnlyList<string>? app)
    {
        var nomi = (app ?? []).Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => n.Trim()).Distinct().ToList();
        return nomi.Count == 0 ? TestiRicevitore.T("Stato_InOnda") : TestiRicevitore.T("Stato_InOndaSu", DomandaUscita.Elenco(nomi));
    }

    /// <summary>
    /// Per l'Assistente vocale, su un comando spento (windows.md 2.13): «Specchia, non disponibile: solo con la fotocamera
    /// frontale». Il motivo perde la maiuscola iniziale e il punto finale; senza nome resta solo il motivo.
    /// </summary>
    public static string NonDisponibile(string? nome, string motivo)
    {
        var frase = motivo.Trim().TrimEnd('.');
        if (string.IsNullOrWhiteSpace(nome)) return frase;
        if (frase.Length > 1 && char.IsUpper(frase[0]) && !char.IsUpper(frase[1])) frase = char.ToLowerInvariant(frase[0]) + frase[1..];
        return TestiRicevitore.T("Accessibilita_NonDisponibile", nome.Trim(), frase);
    }

    private static string Taglia(string testo) =>
        testo.Length <= LunghezzaMassimaSuggerimento ? testo : testo[..(LunghezzaMassimaSuggerimento - 1)] + "…";
}

/// <summary>
/// Le righe del registro per «in onda» (windows.md N4): «In onda su Zoom» all'inizio (o quando l'elenco delle app cambia),
/// «Fuori onda» alla fine. Windows dice le app solo ogni tanto e a volte un elenco vuoto: un elenco vuoto dopo una riga
/// già scritta non ne scrive un'altra, così il registro non balla.
/// </summary>
public sealed class RegistroInOnda
{
    private string? ultima;

    /// <summary>La riga da scrivere, o null se non è cambiato nulla.</summary>
    public string? Cambio(bool inOnda, IReadOnlyList<string>? app)
    {
        if (!inOnda)
        {
            if (ultima is null) return null;
            ultima = null;
            return TestiRicevitore.T("Stato_FuoriOnda");
        }
        var conNomi = (app ?? []).Any(n => !string.IsNullOrWhiteSpace(n));
        if (ultima is not null && !conNomi) return null;
        var riga = DescrizioneStato.InOnda(app);
        if (riga == ultima) return null;
        ultima = riga;
        return riga;
    }
}
