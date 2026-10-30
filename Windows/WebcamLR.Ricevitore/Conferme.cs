namespace WebcamLR.Ricevitore;

/// <summary>
/// Una domanda prima di un gesto distruttivo: titolo (la domanda), testo (cosa succede, può essere vuoto) e i due
/// pulsanti. Nell'app il pulsante predefinito è sempre <see cref="Annulla"/>: Invio ed Esc non distruggono nulla.
/// </summary>
public sealed record Domanda(string Titolo, string Testo, string Conferma, string Annulla);

/// <summary>
/// Niente gesti distruttivi a sorpresa (1.0 beta 2, passo 4; windows.md 1.8, 2.10, 2.11): le domande prima di
/// scollegare un telefono in onda o registrando, eliminare o sostituire un profilo, togliere un telefono fidato, e la
/// frase in più quando si rimuove la webcam che un'app sta usando. Qui si decide se chiedere e con quali parole;
/// l'app mostra la ContentDialog.
/// </summary>
public static class Conferme
{
    /// <summary>
    /// Prima di scollegare <paramref name="telefono"/>: la domanda, o null se si scollega subito. Si chiede solo se il
    /// telefono è quello nella webcam (<paramref name="nellaWebcam"/>) e un'app usa il video (<paramref name="inOnda"/>,
    /// con i nomi letti da Windows in <paramref name="appInUso"/>, anche vuoti) o si registra. Se c'è un altro telefono
    /// (<paramref name="passaA"/>) il video passa a lui invece di fermarsi.
    /// </summary>
    public static Domanda? Scollega(string telefono, bool nellaWebcam, bool inOnda, IReadOnlyList<string> appInUso,
        bool registrando, string? passaA = null)
    {
        if (!nellaWebcam || (!inOnda && !registrando)) return null;
        var frasi = new List<string>();
        if (inOnda)
        {
            var nomi = Nomi(appInUso);
            var altro = string.IsNullOrWhiteSpace(passaA) ? null : passaA.Trim();
            frasi.Add((nomi.Count, altro) switch
            {
                (0, null) => TestiRicevitore.T("Scollega_UnAppSiFerma"),
                (1, null) => TestiRicevitore.T("Scollega_AppSiFerma", nomi[0]),
                (_, null) => TestiRicevitore.T("Scollega_AppSiFermano", DomandaUscita.Elenco(nomi)),
                (0, _) => TestiRicevitore.T("Scollega_UnAppPassaA", altro),
                (1, _) => TestiRicevitore.T("Scollega_AppPassaA", nomi[0], altro),
                _ => TestiRicevitore.T("Scollega_AppPassanoA", DomandaUscita.Elenco(nomi), altro),
            });
        }
        if (registrando) frasi.Add(TestiRicevitore.T("Uscita_Registrazione"));
        return new Domanda(TestiRicevitore.T("Scollega_Titolo", Nome(telefono)), string.Join(" ", frasi),
            TestiRicevitore.T("Scollega_Scollega"), TestiRicevitore.T("Uscita_Annulla"));
    }

    /// <summary>«Eliminare il profilo «Riunione»?» · «Elimina» · «Annulla».</summary>
    public static Domanda EliminaProfilo(string nome) =>
        new(TestiRicevitore.T("Conferma_EliminaProfilo", Nome(nome)), "", TestiRicevitore.T("Conferma_Elimina"), TestiRicevitore.T("Uscita_Annulla"));

    /// <summary>Salvando con un nome già usato: «C'è già un profilo «Riunione»: sostituirlo?» · «Sostituisci» · «Annulla».</summary>
    public static Domanda SostituisciProfilo(string nome) =>
        new(TestiRicevitore.T("Conferma_SostituisciProfilo", Nome(nome)), "", TestiRicevitore.T("Conferma_Sostituisci"), TestiRicevitore.T("Uscita_Annulla"));

    /// <summary>
    /// Il nome già usato, se c'è, scritto come era salvato: «riunione» trova «Riunione» (maiuscole e spazi non contano),
    /// così sostituendo non restano due profili quasi uguali.
    /// </summary>
    public static string? NomeGiaUsato(string nome, IEnumerable<string> esistenti)
    {
        var cercato = nome.Trim();
        return esistenti.FirstOrDefault(e => string.Equals(e.Trim(), cercato, StringComparison.CurrentCultureIgnoreCase));
    }

    /// <summary>«Rimuovere «Pixel 8» dai telefoni fidati?» e cosa succede la prossima volta.</summary>
    public static Domanda RimuoviFidato(string nome) =>
        new(TestiRicevitore.T("Conferma_RimuoviFidato", Nome(nome)), TestiRicevitore.T("Conferma_RimuoviFidatoTesto"),
            TestiRicevitore.T("Conferma_Rimuovi"), TestiRicevitore.T("Uscita_Annulla"));

    /// <summary>
    /// La frase in più nella domanda «Rimuovere la webcam WebcamLR?» quando un'app la sta usando
    /// («Zoom la sta usando adesso: chi ti guarda perderà il video.»); null se nessuna app la usa.
    /// </summary>
    public static string? WebcamInUso(bool inOnda, IReadOnlyList<string> appInUso)
    {
        if (!inOnda) return null;
        var nomi = Nomi(appInUso);
        return nomi.Count switch
        {
            0 => TestiRicevitore.T("Conferma_WebcamUnApp"),
            1 => TestiRicevitore.T("Conferma_WebcamApp", nomi[0]),
            _ => TestiRicevitore.T("Conferma_WebcamApps", DomandaUscita.Elenco(nomi)),
        };
    }

    /// <summary>
    /// Il codice di conferma è scaduto (windows.md 2.16)? La domanda si chiude anche se il telefono se ne va prima: conta
    /// come scaduta solo se è rimasta aperta quasi tutto il tempo (<see cref="SessioneComputer.AttesaConferma"/>, meno
    /// un secondo di margine).
    /// </summary>
    public static bool TempoScaduto(TimeSpan aperta) => aperta >= SessioneComputer.AttesaConferma - TimeSpan.FromSeconds(1);

    /// <summary>«Tempo scaduto: «Pixel 8» non è stato collegato. Riprova dal telefono.»</summary>
    public static string CodiceScaduto(string nome) => TestiRicevitore.T("Conferma_TempoScaduto", Nome(nome));

    private static List<string> Nomi(IReadOnlyList<string> appInUso) =>
        appInUso.Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => n.Trim()).Distinct().ToList();

    private static string Nome(string nome) => string.IsNullOrWhiteSpace(nome) ? TestiRicevitore.T("Conferma_IlTelefono") : nome.Trim();
}

/// <summary>
/// «Annulla» per poco tempo dopo un gesto (windows.md 1.8, «Azzera» delle regolazioni): i valori di prima si ricordano
/// per <see cref="Durata"/>; finché non scadono «Annulla» nell'InfoBar o Ctrl+Z li rimettono, una volta sola.
/// L'orologio è passato da fuori (millisecondi), così i test non aspettano.
/// </summary>
public sealed class AnnullaPerPoco<T> where T : class
{
    /// <summary>Quanto resta disponibile «Annulla».</summary>
    public static readonly TimeSpan Durata = TimeSpan.FromSeconds(8);

    private T? prima;
    private long scadenzaMs;

    /// <summary>Dopo il gesto: i valori di prima, da rimettere se si annulla. Un gesto nuovo prende il posto del vecchio.</summary>
    public void Ricorda(T valoriDiPrima, long adessoMs)
    {
        prima = valoriDiPrima;
        scadenzaMs = adessoMs + (long)Durata.TotalMilliseconds;
    }

    /// <summary>Vero finché si può annullare.</summary>
    public bool Disponibile(long adessoMs) => prima is not null && adessoMs < scadenzaMs;

    /// <summary>I valori da rimettere, se si è ancora in tempo; dopo, niente più da annullare.</summary>
    public T? Annulla(long adessoMs)
    {
        var valori = Disponibile(adessoMs) ? prima : null;
        Dimentica();
        return valori;
    }

    /// <summary>Scaduto, chiuso a mano o cambiato telefono: non si annulla più.</summary>
    public void Dimentica() => prima = null;
}
