namespace WebcamLR.Ricevitore;

/// <summary>
/// La latenza degli ultimi 60 secondi, una misura al secondo, per il grafico sotto l'anteprima (round 2, funzione 48).
/// I secondi senza misura restano vuoti: la linea li salta invece di inventarli.
/// </summary>
public sealed class StoriaLatenza
{
    public const int Secondi = 60;

    /// <summary>Il grafico arriva almeno a 150 ms (la soglia di «Debole»), così una linea bassa resta bassa.</summary>
    public const int ScalaMinimaMs = 150;

    private readonly Queue<int?> misure = new();

    public int Conteggio => misure.Count;

    /// <summary>Da chiamare a ogni aggiornamento delle statistiche, cioè ogni secondo.</summary>
    public void Aggiungi(int? latenzaMs)
    {
        misure.Enqueue(latenzaMs);
        while (misure.Count > Secondi) misure.Dequeue();
    }

    public void Azzera() => misure.Clear();

    public int? Media => Valide().Any() ? (int)Math.Round(Valide().Average()) : null;

    public int? Massima => Valide().Any() ? Valide().Max() : null;

    /// <summary>Il valore più alto dell'asse verticale, in millisecondi.</summary>
    public int Scala => Math.Max(ScalaMinimaMs, Massima ?? 0);

    /// <summary>
    /// I punti della linea in un riquadro largo <paramref name="larghezza"/> e alto <paramref name="altezza"/>:
    /// il secondo più recente sta sul bordo destro, lo zero in basso.
    /// </summary>
    public IReadOnlyList<(double X, double Y)> Punti(double larghezza, double altezza)
    {
        var punti = new List<(double, double)>();
        var scala = (double)Scala;
        var passo = larghezza / (Secondi - 1);
        var inizio = Secondi - misure.Count;
        var indice = 0;
        foreach (var misura in misure)
        {
            if (misura is int ms)
            {
                var x = (inizio + indice) * passo;
                var y = altezza - Math.Clamp(ms / scala, 0, 1) * altezza;
                punti.Add((Math.Round(x, 2), Math.Round(y, 2)));
            }
            indice++;
        }
        return punti;
    }

    /// <summary>L'altezza della linea guida dei 100 ms, l'obiettivo del round 1.</summary>
    public double AltezzaDi(int latenzaMs, double altezza) =>
        Math.Round(altezza - Math.Clamp(latenzaMs / (double)Scala, 0, 1) * altezza, 2);

    private IEnumerable<int> Valide() => misure.OfType<int>();
}
