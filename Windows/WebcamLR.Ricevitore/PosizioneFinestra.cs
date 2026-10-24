using System.Globalization;

namespace WebcamLR.Ricevitore;

/// <summary>Un rettangolo in pixel dello schermo, come quelli di AppWindow e DisplayArea.</summary>
public readonly record struct Rettangolo(int X, int Y, int Larghezza, int Altezza)
{
    public Rettangolo Intersezione(Rettangolo altro)
    {
        var sinistra = Math.Max(X, altro.X);
        var sopra = Math.Max(Y, altro.Y);
        var destra = Math.Min(X + Larghezza, altro.X + altro.Larghezza);
        var sotto = Math.Min(Y + Altezza, altro.Y + altro.Altezza);
        return destra <= sinistra || sotto <= sopra ? default : new(sinistra, sopra, destra - sinistra, sotto - sopra);
    }
}

/// <summary>
/// Dimensione e posizione della finestra tra un'apertura e l'altra (round 2, funzione 47).
/// Si salva come testo «x;y;larghezza;altezza;massimizzata» nelle preferenze.
/// </summary>
public sealed record PosizioneFinestra(Rettangolo Rettangolo, bool Massimizzata)
{
    public const int LarghezzaMinima = 640;
    public const int AltezzaMinima = 400;
    /// <summary>Quanto della barra del titolo deve stare su uno schermo per poterla trascinare.</summary>
    public const int BarraVisibileLarghezza = 120;
    public const int BarraVisibileAltezza = 32;

    public string Testo() => string.Join(';',
        Rettangolo.X, Rettangolo.Y, Rettangolo.Larghezza, Rettangolo.Altezza, Massimizzata ? 1 : 0);

    public static PosizioneFinestra? DaTesto(string? testo)
    {
        var parti = testo?.Split(';');
        if (parti is not { Length: 5 }) return null;
        var numeri = new int[5];
        for (var i = 0; i < 5; i++)
        {
            if (!int.TryParse(parti[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out numeri[i])) return null;
        }
        if (numeri[2] <= 0 || numeri[3] <= 0) return null;
        return new(new Rettangolo(numeri[0], numeri[1], numeri[2], numeri[3]), numeri[4] == 1);
    }

    /// <summary>
    /// La posizione da usare sugli schermi di adesso (le loro aree di lavoro, senza barra delle applicazioni),
    /// o null se la barra del titolo non si vedrebbe abbastanza: per esempio uno schermo staccato.
    /// Se la finestra è più grande dello schermo in cui cade, la si stringe e la si sposta dentro;
    /// se è sotto la misura minima, la si allarga.
    /// </summary>
    public PosizioneFinestra? Su(IReadOnlyList<Rettangolo> schermi)
    {
        var r = Rettangolo;
        var barra = new Rettangolo(r.X, r.Y, r.Larghezza, BarraVisibileAltezza);
        Rettangolo? schermo = null;
        var migliore = 0;
        foreach (var area in schermi)
        {
            var visibile = barra.Intersezione(area);
            if (visibile.Larghezza < BarraVisibileLarghezza || visibile.Altezza < BarraVisibileAltezza) continue;
            var superficie = visibile.Larghezza * visibile.Altezza;
            if (superficie > migliore) { migliore = superficie; schermo = area; }
        }
        if (schermo is not { } s) return null;

        var larghezza = Math.Min(Math.Max(r.Larghezza, LarghezzaMinima), s.Larghezza);
        var altezza = Math.Min(Math.Max(r.Altezza, AltezzaMinima), s.Altezza);
        // Una finestra a cavallo di due schermi resta dov'era; solo se è stata stretta la si porta dentro.
        var x = larghezza < r.Larghezza ? Math.Clamp(r.X, s.X, s.X + s.Larghezza - larghezza) : r.X;
        var y = altezza < r.Altezza ? Math.Clamp(r.Y, s.Y, s.Y + s.Altezza - altezza) : r.Y;
        return this with { Rettangolo = new Rettangolo(x, y, larghezza, altezza) };
    }
}
