namespace WebcamLR.Effetti;

/// <summary>
/// Decide se il modello pieno è troppo lento su questo PC (come su Android): le prime maschere non contano (la scheda
/// video prepara gli shader), poi una media mobile; se dopo la prova supera il limite si passa al modello leggero per
/// il resto della sessione.
/// </summary>
public sealed class MisuraVelocita
{
    /// <summary>Maschere di riscaldamento, non contate.</summary>
    public const int Riscaldamento = 5;

    /// <summary>Maschere contate prima di decidere.</summary>
    public const int Prova = 20;

    /// <summary>
    /// Oltre questa media (ms per maschera) il modello pieno è lasciato. A 30 fps un fotogramma dura 33 ms; la maschera si
    /// calcola accanto al video, e sopra i 25 ms resterebbe indietro e la persona lascerebbe una scia.
    /// </summary>
    public const double LimiteMs = 25;

    private int conteggio;

    /// <summary>Media mobile in ms (dopo il riscaldamento), 0 prima.</summary>
    public double MediaMs { get; private set; }

    /// <summary>Aggiunge la durata di una maschera; vero se il modello va lasciato (una volta decisa, resta vera).</summary>
    public bool Aggiungi(double ms)
    {
        conteggio++;
        if (conteggio <= Riscaldamento) return false;
        MediaMs = conteggio == Riscaldamento + 1 ? ms : MediaMs * 0.9 + ms * 0.1;
        return TroppoLento;
    }

    public bool TroppoLento => conteggio >= Riscaldamento + Prova && MediaMs > LimiteMs;
}
