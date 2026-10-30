namespace WebcamLR.Ricevitore;

/// <summary>
/// «WebcamLR.exe --esci» (windows.md 1.7): l'installatore chiede alla copia aperta di uscire bene. La copia nuova
/// passa la richiesta a quella aperta con l'istanza unica (App.xaml.cs); se non c'è nessuna copia aperta, esce senza
/// aprire niente. Lo stesso argomento è in ChiusuraApp (WebcamLR.Setup.Logica).
/// </summary>
public static class UscitaRichiesta
{
    public const string Argomento = "--esci";

    /// <summary>Dagli argomenti del processo (Environment.GetCommandLineArgs).</summary>
    public static bool Chiesta(IEnumerable<string> argomenti) =>
        argomenti.Any(a => a.Trim().Equals(Argomento, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Dalla riga di comando passata con l'attivazione (in un'app non pacchettizzata c'è anche il percorso dell'exe,
    /// tra virgolette se ha spazi): conta solo l'argomento intero, non un pezzo di percorso.
    /// </summary>
    public static bool Chiesta(string? rigaDiComando)
    {
        if (string.IsNullOrWhiteSpace(rigaDiComando)) return false;
        var parti = new List<string>();
        var attuale = new System.Text.StringBuilder();
        var traVirgolette = false;
        foreach (var c in rigaDiComando)
        {
            if (c == '"') { traVirgolette = !traVirgolette; continue; }
            if (char.IsWhiteSpace(c) && !traVirgolette)
            {
                if (attuale.Length > 0) parti.Add(attuale.ToString());
                attuale.Clear();
                continue;
            }
            attuale.Append(c);
        }
        if (attuale.Length > 0) parti.Add(attuale.ToString());
        return Chiesta(parti);
    }
}

/// <summary>La domanda prima di uscire (windows.md 1.1 e 1.10): titolo, testo e pulsanti.</summary>
public sealed record DomandaUscita(string Titolo, string Testo, string Esci, string Annulla)
{
    /// <summary>
    /// La domanda, o null se non c'è nulla in corso (si esce subito). Si chiede se un'app usa il video
    /// (<paramref name="inOnda"/>, con i nomi letti da Windows in <paramref name="appInUso"/>, anche vuoti), se si
    /// registra o se un telefono è collegato. Il telefono si nomina solo se nessuna app usa il video: altrimenti conta
    /// la chiamata.
    /// </summary>
    public static DomandaUscita? Crea(bool inOnda, IReadOnlyList<string> appInUso, bool registrando, IReadOnlyList<string> telefoni)
    {
        if (!inOnda && !registrando && telefoni.Count == 0) return null;
        var frasi = new List<string>();
        if (inOnda)
        {
            var nomi = appInUso.Where(n => !string.IsNullOrWhiteSpace(n)).Select(n => n.Trim()).Distinct().ToList();
            frasi.Add(nomi.Count switch
            {
                0 => TestiRicevitore.T("Uscita_UnAppUsaIlVideo"),
                1 => TestiRicevitore.T("Uscita_AppUsaIlVideo", nomi[0]),
                _ => TestiRicevitore.T("Uscita_AppUsanoIlVideo", Elenco(nomi)),
            });
        }
        if (registrando) frasi.Add(TestiRicevitore.T("Uscita_Registrazione"));
        if (!inOnda && telefoni.Count > 0)
        {
            frasi.Add(telefoni.Count == 1 && !string.IsNullOrWhiteSpace(telefoni[0])
                ? TestiRicevitore.T("Uscita_TelefonoSiScollega", telefoni[0].Trim())
                : TestiRicevitore.T("Uscita_TelefoniSiScollegano"));
        }
        return new DomandaUscita(TestiRicevitore.T("Uscita_Titolo"), string.Join(" ", frasi),
            TestiRicevitore.T("Uscita_Esci"), TestiRicevitore.T("Uscita_Annulla"));
    }

    /// <summary>«Zoom», «Zoom e Teams», «Zoom, Teams e OBS».</summary>
    internal static string Elenco(IReadOnlyList<string> nomi) =>
        nomi.Count == 1 ? nomi[0]
        : string.Join(", ", nomi.Take(nomi.Count - 1)) + TestiRicevitore.T("Uscita_E") + nomi[^1];
}

/// <summary>
/// X e Alt+F4 nascondono la finestra accanto all'orologio (windows.md 1.2): la prima volta in ogni sessione, e sempre
/// se si registra o si è in onda, una notifica lo dice.
/// </summary>
public sealed class AvvisoFinestraNascosta
{
    private bool detto;

    /// <summary>Vero se questa volta serve la notifica; la prima volta si ricorda.</summary>
    public bool Serve(bool registrando, bool inOnda)
    {
        var serve = !detto || registrando || inOnda;
        detto = true;
        return serve;
    }

    /// <summary>Titolo e testo della notifica.</summary>
    public static (string Titolo, string Testo) Notifica(bool registrando) =>
        (TestiRicevitore.T("Nascosta_Titolo"),
         registrando ? TestiRicevitore.T("Nascosta_TestoRegistrazione") : TestiRicevitore.T("Nascosta_Testo"));
}
