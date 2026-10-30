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
/// Passo 7 (windows.md 2.2): la misura è in DIP, i pixel indipendenti dalla scala di Windows, così a 150 % la finestra
/// resta grande come a 100 % invece di rimpicciolirsi. La posizione resta in pixel dello schermo: tra schermi con scale
/// diverse Windows non ha coordinate in DIP. Si salva come testo «dip;x;y;larghezza;altezza;massimizzata»; il formato di
/// prima («x;y;larghezza;altezza;massimizzata», senza «dip») era tutto in pixel e si legge ancora.
/// </summary>
/// <param name="MisuraInDip">Falso solo per una posizione salvata nel formato di prima.</param>
public sealed record PosizioneFinestra(Rettangolo Rettangolo, bool Massimizzata, bool MisuraInDip = true)
{
    /// <summary>La misura della prima apertura, in DIP.</summary>
    public const int LarghezzaIniziale = 1360;
    public const int AltezzaIniziale = 840;
    /// <summary>
    /// Sotto questa misura (in DIP) la finestra non si stringe: è la più piccola in cui le colonne e il video stanno
    /// (Mac: 960×600 punti).
    /// </summary>
    public const int LarghezzaMinima = 960;
    public const int AltezzaMinima = 600;
    /// <summary>Quanto della barra del titolo deve stare su uno schermo per poterla trascinare (in pixel).</summary>
    public const int BarraVisibileLarghezza = 120;
    public const int BarraVisibileAltezza = 32;

    private const string SegnoDip = "dip";

    public string Testo()
    {
        var valori = string.Join(';', Rettangolo.X, Rettangolo.Y, Rettangolo.Larghezza, Rettangolo.Altezza, Massimizzata ? 1 : 0);
        return MisuraInDip ? $"{SegnoDip};{valori}" : valori;
    }

    public static PosizioneFinestra? DaTesto(string? testo)
    {
        var parti = testo?.Split(';');
        if (parti is null) return null;
        var inDip = parti.Length == 6 && parti[0] == SegnoDip;
        if (inDip) parti = parti[1..];
        if (parti.Length != 5) return null;
        var numeri = new int[5];
        for (var i = 0; i < 5; i++)
        {
            if (!int.TryParse(parti[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out numeri[i])) return null;
        }
        if (numeri[2] <= 0 || numeri[3] <= 0) return null;
        return new(new Rettangolo(numeri[0], numeri[1], numeri[2], numeri[3]), numeri[4] == 1, inDip);
    }

    /// <summary>La scala di Windows (1 = 100 %, 1,5 = 150 %); un valore senza senso vale 1.</summary>
    public static double ScalaValida(double scala) => double.IsFinite(scala) && scala >= 0.5 && scala <= 8 ? scala : 1;

    /// <summary>Da DIP a pixel con la scala di Windows.</summary>
    public static int InPixel(double dip, double scala) => (int)Math.Round(dip * ScalaValida(scala));

    /// <summary>La finestra com'è adesso (in pixel, come la dà AppWindow), da salvare con la misura in DIP.</summary>
    public static PosizioneFinestra DaPixel(Rettangolo pixel, double scala, bool massimizzata)
    {
        var s = ScalaValida(scala);
        return new(new Rettangolo(pixel.X, pixel.Y, (int)Math.Round(pixel.Larghezza / s), (int)Math.Round(pixel.Altezza / s)),
            massimizzata);
    }

    /// <summary>
    /// La prima apertura: 1360×840 DIP con la scala dello schermo, al centro della sua area di lavoro; più piccola se lo
    /// schermo non basta (mai sotto la misura minima, se lo schermo la contiene). In pixel.
    /// </summary>
    public static Rettangolo Iniziale(Rettangolo area, double scala)
    {
        var larghezza = Math.Min(InPixel(LarghezzaIniziale, scala), area.Larghezza);
        var altezza = Math.Min(InPixel(AltezzaIniziale, scala), area.Altezza);
        return new Rettangolo(area.X + (area.Larghezza - larghezza) / 2, area.Y + (area.Altezza - altezza) / 2, larghezza, altezza);
    }

    /// <summary>
    /// Il rettangolo in pixel da usare sugli schermi di adesso (le loro aree di lavoro, senza barra delle applicazioni),
    /// con la scala dello schermo su cui torna, o null se la barra del titolo non si vedrebbe abbastanza: per esempio uno
    /// schermo staccato. Se la finestra è più grande dello schermo in cui cade, la si stringe e la si sposta dentro;
    /// se è sotto la misura minima, la si allarga.
    /// </summary>
    public Rettangolo? Su(IReadOnlyList<Rettangolo> schermi, double scala)
    {
        var r = MisuraInDip
            ? Rettangolo with { Larghezza = InPixel(Rettangolo.Larghezza, scala), Altezza = InPixel(Rettangolo.Altezza, scala) }
            : Rettangolo;
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

        var larghezza = Math.Min(Math.Max(r.Larghezza, InPixel(LarghezzaMinima, scala)), s.Larghezza);
        var altezza = Math.Min(Math.Max(r.Altezza, InPixel(AltezzaMinima, scala)), s.Altezza);
        // Una finestra a cavallo di due schermi resta dov'era; solo se è stata stretta la si porta dentro.
        var x = larghezza < r.Larghezza ? Math.Clamp(r.X, s.X, s.X + s.Larghezza - larghezza) : r.X;
        var y = altezza < r.Altezza ? Math.Clamp(r.Y, s.Y, s.Y + s.Altezza - altezza) : r.Y;
        return new Rettangolo(x, y, larghezza, altezza);
    }
}
