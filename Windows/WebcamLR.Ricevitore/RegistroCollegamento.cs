namespace WebcamLR.Ricevitore;

/// <summary>Un evento del registro: l'ora e una frase breve.</summary>
public sealed record VoceRegistro(DateTime Ora, string Testo)
{
    public string Riga => $"{Ora:HH:mm:ss}  {Testo}";
}

/// <summary>
/// Registro del collegamento (modalità avanzata, 1.5): gli ultimi eventi, solo in memoria.
/// Si può scrivere da qualsiasi thread; <see cref="Cambiato"/> arriva sul thread di chi scrive.
/// </summary>
public sealed class RegistroCollegamento
{
    public const int CapienzaPredefinita = 50;

    public event Action? Cambiato;

    private readonly object blocco = new();
    private readonly Queue<VoceRegistro> voci = new();
    private readonly int capienza;
    private readonly Func<DateTime> orologio;

    public RegistroCollegamento(int capienza = CapienzaPredefinita, Func<DateTime>? orologio = null)
    {
        this.capienza = Math.Max(1, capienza);
        this.orologio = orologio ?? (() => DateTime.Now);
    }

    public void Aggiungi(string testo)
    {
        if (string.IsNullOrWhiteSpace(testo)) return;
        lock (blocco)
        {
            voci.Enqueue(new VoceRegistro(orologio(), testo.Trim()));
            while (voci.Count > capienza) voci.Dequeue();
        }
        Cambiato?.Invoke();
    }

    /// <summary>Dal più vecchio al più recente.</summary>
    public IReadOnlyList<VoceRegistro> Voci
    {
        get { lock (blocco) return voci.ToList(); }
    }

    /// <summary>Una riga per evento; per la finestra i più recenti in cima, per copiarlo in ordine di tempo.</summary>
    public string Testo(bool recentiPrima = false)
    {
        IEnumerable<VoceRegistro> elenco = Voci;
        if (recentiPrima) elenco = elenco.Reverse();
        return string.Join("\n", elenco.Select(voce => voce.Riga));
    }
}
