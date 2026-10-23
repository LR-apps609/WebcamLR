namespace WebcamLR.Ricevitore;

/// <summary>
/// Latenza tra la cattura sul telefono e l'arrivo sul computer.
/// La differenza tra i due orologi viene dal pong con l'andata e ritorno più breve tra gli ultimi 10.
/// </summary>
public sealed class MisuraLatenza
{
    private const int MisureTenute = 10;
    private readonly Queue<(ulong AndataRitorno, long Scarto)> misure = new();
    private readonly List<int> latenzeRecenti = new();

    public int? UltimaLatenzaMs { get; private set; }

    /// <param name="t">Il valore spedito nel ping (orologio del computer).</param>
    /// <param name="telefono">L'orologio del telefono al momento del pong.</param>
    /// <param name="adesso">L'orologio del computer all'arrivo del pong.</param>
    public void AggiungiPong(ulong t, ulong telefono, ulong adesso)
    {
        if (adesso < t) return;
        var andataRitorno = adesso - t;
        var scarto = (long)telefono - (long)(t + andataRitorno / 2);
        misure.Enqueue((andataRitorno, scarto));
        if (misure.Count > MisureTenute) misure.Dequeue();
    }

    public long? MiglioreScarto =>
        misure.Count == 0 ? null : misure.MinBy(m => m.AndataRitorno).Scarto;

    /// <summary>Registra un fotogramma arrivato; restituisce la sua latenza in millisecondi, se calcolabile.</summary>
    public int? Fotogramma(ulong timestampTelefono, ulong adesso)
    {
        if (MiglioreScarto is not long scarto) return null;
        var cattura = (long)timestampTelefono - scarto;
        var latenza = (int)(((long)adesso - cattura) / 1000);
        if (latenza is < 0 or >= 10_000) return null;
        latenzeRecenti.Add(latenza);
        return latenza;
    }

    /// <summary>Chiude il secondo: la latenza mostrata è la mediana dei fotogrammi arrivati.</summary>
    public int? ChiudiSecondo()
    {
        if (latenzeRecenti.Count > 0)
        {
            latenzeRecenti.Sort();
            UltimaLatenzaMs = latenzeRecenti[latenzeRecenti.Count / 2];
            latenzeRecenti.Clear();
        }
        return UltimaLatenzaMs;
    }
}
