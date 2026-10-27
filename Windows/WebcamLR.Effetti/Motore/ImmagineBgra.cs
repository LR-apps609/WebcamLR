namespace WebcamLR.Effetti;

/// <summary>
/// Un'immagine BGRA a 8 bit per canale, righe dall'alto, senza spazi tra le righe (passo = larghezza × 4). È il formato
/// in cui Windows dà i fotogrammi decodificati (B8G8R8A8) e quello che il motore restituisce a tutte le uscite.
/// </summary>
public sealed class ImmagineBgra
{
    public ImmagineBgra(int larghezza, int altezza, byte[]? dati = null)
    {
        if (larghezza <= 0 || altezza <= 0) throw new ArgumentException("Misura dell'immagine non valida");
        Larghezza = larghezza;
        Altezza = altezza;
        Dati = dati ?? new byte[larghezza * altezza * 4];
        if (Dati.Length < larghezza * altezza * 4) throw new ArgumentException("Dati più corti dell'immagine", nameof(dati));
    }

    public byte[] Dati { get; }
    public int Larghezza { get; }
    public int Altezza { get; }
    public int Passo => Larghezza * 4;

    /// <summary>Il timestamp del telefono (µs) del fotogramma da cui viene, per il ritardo da vetro a uscita.</summary>
    public ulong? Timestamp { get; set; }

    public Span<byte> Riga(int y) => Dati.AsSpan(y * Passo, Passo);

    public ImmagineBgra Copia()
    {
        var copia = new ImmagineBgra(Larghezza, Altezza);
        Dati.AsSpan(0, Larghezza * Altezza * 4).CopyTo(copia.Dati);
        copia.Timestamp = Timestamp;
        return copia;
    }

    /// <summary>Copia dentro un'immagine data con un passo qualsiasi (una superficie della scheda video, una bitmap).</summary>
    public static void CopiaRighe(ReadOnlySpan<byte> sorgente, int passoSorgente, Span<byte> destinazione, int passoDestinazione,
        int larghezza, int altezza)
    {
        var byteRiga = larghezza * 4;
        for (var y = 0; y < altezza; y++)
            sorgente.Slice(y * passoSorgente, byteRiga).CopyTo(destinazione.Slice(y * passoDestinazione, byteRiga));
    }
}

/// <summary>
/// Le immagini di una misura, riusate: a 1080p ognuna è 8 MB e a 30 fps allocarle ogni volta stancherebbe il
/// garbage collector. Restituire un'immagine di un'altra misura la butta. Da qualsiasi thread.
/// </summary>
public sealed class RiservaImmagini
{
    private readonly object blocco = new();
    private readonly Stack<ImmagineBgra> libere = new();
    private readonly int massimo;

    public RiservaImmagini(int massimo = 6) => this.massimo = massimo;

    public ImmagineBgra Prendi(int larghezza, int altezza)
    {
        lock (blocco)
        {
            while (libere.TryPop(out var immagine))
            {
                if (immagine.Larghezza == larghezza && immagine.Altezza == altezza)
                {
                    immagine.Timestamp = null;
                    return immagine;
                }
            }
        }
        return new ImmagineBgra(larghezza, altezza);
    }

    public void Restituisci(ImmagineBgra? immagine)
    {
        if (immagine is null) return;
        lock (blocco)
        {
            if (libere.Count < massimo && !libere.Contains(immagine)) libere.Push(immagine);
        }
    }
}

/// <summary>Un rettangolo in coordinate normalizzate del fotogramma (0..1), origine in alto a sinistra.</summary>
public readonly record struct Rettangolo(double X, double Y, double Larghezza, double Altezza)
{
    public double CentroX => X + Larghezza / 2;
    public double CentroY => Y + Altezza / 2;
    public double Destra => X + Larghezza;
    public double Basso => Y + Altezza;

    public Rettangolo Unione(Rettangolo altro)
    {
        var x = Math.Min(X, altro.X);
        var y = Math.Min(Y, altro.Y);
        return new(x, y, Math.Max(Destra, altro.Destra) - x, Math.Max(Basso, altro.Basso) - y);
    }

    /// <summary>In pixel di un'immagine larga <paramref name="larghezza"/> e alta <paramref name="altezza"/>.</summary>
    public Rettangolo InPixel(int larghezza, int altezza) => new(X * larghezza, Y * altezza, Larghezza * larghezza, Altezza * altezza);
}
