using System.Runtime.Intrinsics;
using System.Runtime.Intrinsics.X86;
using WebcamLR.Protocollo;

namespace WebcamLR.Effetti;

// Le ricette di colore dell'iPhone (EffettoFiltro.swift, le regolazioni di PipelineEffetti.swift, EffettoCalore.swift),
// portate come sul Mac (Mac/Sorgenti/RicetteEffetti.swift) ma per il processore: ogni ricetta è una catena di «stadi»,
// ognuno fatto di una tabella per canale all'ingresso (8 bit → 12 bit, nello spazio di lavoro dello stadio: lineare o
// sRGB), una matrice 3×3 con scostamento (saturazione, bianco e nero, seppia) e una tabella per canale all'uscita
// (12 bit → 8 bit sRGB). Gli stadi senza matrice si fondono in una tabella sola per canale: il calore da solo, una curva.
// Differenze dal Mac, volute per il tempo di calcolo: la vibranza di «Vivido» è una saturazione, la mescolanza ombre/luci
// di «Cinema» usa il valore del canale invece della luminanza, la riduzione del rumore di «Notte» non c'è.

/// <summary>Le funzioni di base: curve sRGB, curve di tono, matrici.</summary>
public static class Colore
{
    public static double InLineare(double s) => s <= 0.04045 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);

    public static double InSrgb(double l)
    {
        l = Math.Clamp(l, 0, 1);
        return l <= 0.0031308 ? l * 12.92 : 1.055 * Math.Pow(l, 1 / 2.4) - 0.055;
    }

    /// <summary>Pesi della luminanza di CIColorControls (Rec. 709).</summary>
    public static readonly double[] PesiLuminanza = [0.2126, 0.7152, 0.0722];

    /// <summary>
    /// Curva di tono a cinque punti (come CIToneCurve), interpolata con una cubica monotona (Fritsch–Carlson): passa per
    /// i punti senza oscillare. Fuori dai punti resta costante.
    /// </summary>
    public static Func<double, double> Curva((double X, double Y)[] punti)
    {
        var n = punti.Length;
        var d = new double[n - 1];
        for (var i = 0; i < n - 1; i++) d[i] = (punti[i + 1].Y - punti[i].Y) / (punti[i + 1].X - punti[i].X);
        var m = new double[n];
        m[0] = d[0];
        m[n - 1] = d[n - 2];
        for (var i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
        for (var i = 0; i < n - 1; i++)
        {
            if (d[i] == 0)
            {
                m[i] = m[i + 1] = 0;
                continue;
            }
            var a = m[i] / d[i];
            var b = m[i + 1] / d[i];
            var s = a * a + b * b;
            if (s > 9)
            {
                var t = 3 / Math.Sqrt(s);
                m[i] = t * a * d[i];
                m[i + 1] = t * b * d[i];
            }
        }
        return x =>
        {
            if (x <= punti[0].X) return punti[0].Y;
            if (x >= punti[n - 1].X) return punti[n - 1].Y;
            var i = 0;
            while (i < n - 2 && x > punti[i + 1].X) i++;
            var h = punti[i + 1].X - punti[i].X;
            var t = (x - punti[i].X) / h;
            var t2 = t * t;
            var t3 = t2 * t;
            return (2 * t3 - 3 * t2 + 1) * punti[i].Y + (t3 - 2 * t2 + t) * h * m[i]
                + (-2 * t3 + 3 * t2) * punti[i + 1].Y + (t3 - t2) * h * m[i + 1];
        };
    }

    /// <summary>La matrice della saturazione di CIColorControls: s × identità + (1 − s) × luminanza.</summary>
    public static double[] Saturazione(double s)
    {
        var m = new double[9];
        for (var r = 0; r < 3; r++)
            for (var c = 0; c < 3; c++)
                m[r * 3 + c] = (r == c ? s : 0) + (1 - s) * PesiLuminanza[c];
        return m;
    }

    public static double[] Diagonale(double r, double g, double b) => [r, 0, 0, 0, g, 0, 0, 0, b];

    public static double[] Per(double[] a, double[] b)
    {
        var m = new double[9];
        for (var r = 0; r < 3; r++)
            for (var c = 0; c < 3; c++)
                m[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
        return m;
    }

    public static readonly double[] Identita = Diagonale(1, 1, 1);
}

/// <summary>Uno stadio prima di essere compilato: funzioni per canale (0..1 → 0..1) e la matrice in mezzo.</summary>
public sealed record StadioColore(Func<int, double, double> Ingresso, double[] Matrice, double[] Scostamento,
    Func<int, double, double> Uscita)
{
    public bool SenzaMatrice => Matrice.SequenceEqual(Colore.Identita) && Scostamento.All(v => v == 0);

    /// <summary>Solo tabelle per canale: <paramref name="f"/>(canale, valore sRGB) → sRGB.</summary>
    public static StadioColore PerCanale(Func<int, double, double> f) => new(f, Colore.Identita, [0, 0, 0], (_, v) => v);

    /// <summary>Lavoro in lineare: ingresso sRGB → lineare, la matrice, poi <paramref name="uscita"/> (lineare → sRGB).</summary>
    public static StadioColore Lineare(double[] matrice, Func<double, double>? uscita = null, Func<double, double>? ingresso = null) =>
        new((_, v) => (ingresso ?? (x => x))(Colore.InLineare(v)), matrice, [0, 0, 0],
            (_, v) => (uscita ?? Colore.InSrgb)(v));
}

/// <summary>
/// Una catena di stadi compilata in tabelle intere, pronta per i pixel BGRA. Senza matrici diventa una tabella per
/// canale (8 → 8 bit). Si può usare da più thread insieme (solo lettura).
/// </summary>
public sealed class CatenaColore
{
    private const int Bit = 12;
    private const int Massimo = (1 << Bit) - 1;
    private const int Uno = 1 << Bit;

    private readonly byte[][]? perCanale;
    private readonly Compilato[] stadi;

    private sealed record Compilato(ushort[][] Ingresso, int[] Matrice, int[] Scostamento, byte[][] Uscita)
    {
        // Le stesse tabelle in interi a 32 bit, per le letture a gruppi di 8 (AVX2).
        public readonly int[][] IngressoInt = Ingresso.Select(t => t.Select(v => (int)v).ToArray()).ToArray();
        public readonly int[][] UscitaInt = Uscita.Select(t => t.Select(v => (int)v).ToArray()).ToArray();
    }

    public static CatenaColore? Da(IReadOnlyList<StadioColore> stadi) => stadi.Count == 0 ? null : new CatenaColore(stadi);

    private CatenaColore(IReadOnlyList<StadioColore> sorgente)
    {
        // Gli stadi senza matrice si fondono in quello dopo (all'ingresso) o, in fondo, in quello prima (all'uscita).
        var gruppi = new List<(List<StadioColore> Prima, StadioColore? ConMatrice)>();
        var attesa = new List<StadioColore>();
        foreach (var stadio in sorgente)
        {
            if (stadio.SenzaMatrice) attesa.Add(stadio);
            else
            {
                gruppi.Add((attesa, stadio));
                attesa = [];
            }
        }
        if (gruppi.Count == 0)
        {
            perCanale = new byte[3][];
            for (var c = 0; c < 3; c++)
            {
                perCanale[c] = new byte[256];
                for (var v = 0; v < 256; v++) perCanale[c][v] = InByte(Applica1D(attesa, c, v / 255.0));
            }
            stadi = [];
            return;
        }
        var finali = attesa;
        stadi = new Compilato[gruppi.Count];
        for (var g = 0; g < gruppi.Count; g++)
        {
            var (prima, stadio) = gruppi[g];
            var ultimo = g == gruppi.Count - 1;
            var ingresso = new ushort[3][];
            var uscita = new byte[3][];
            for (var c = 0; c < 3; c++)
            {
                ingresso[c] = new ushort[256];
                for (var v = 0; v < 256; v++)
                    ingresso[c][v] = (ushort)Math.Clamp((int)Math.Round(stadio!.Ingresso(c, Applica1D(prima, c, v / 255.0)) * Massimo), 0, Massimo);
                uscita[c] = new byte[Uno];
                for (var v = 0; v < Uno; v++)
                {
                    var valore = stadio!.Uscita(c, v / (double)Massimo);
                    if (ultimo) valore = Applica1D(finali, c, valore);
                    uscita[c][v] = InByte(valore);
                }
            }
            stadi[g] = new Compilato(ingresso, stadio!.Matrice.Select(m => (int)Math.Round(m * Uno)).ToArray(),
                stadio.Scostamento.Select(s => (int)Math.Round(s * Massimo)).ToArray(), uscita);
        }
    }

    private static double Applica1D(List<StadioColore> stadi, int canale, double valore)
    {
        foreach (var s in stadi) valore = Math.Clamp(s.Uscita(canale, s.Ingresso(canale, Math.Clamp(valore, 0, 1))), 0, 1);
        return valore;
    }

    private static byte InByte(double v) => (byte)Math.Clamp((int)Math.Round(v * 255), 0, 255);

    /// <summary>Vero se è una sola tabella per canale (costa pochissimo).</summary>
    public bool SoloPerCanale => perCanale is not null;

    /// <summary>Le tabelle per canale (B, G, R come i byte del pixel: indice 2 = rosso), se la catena è solo per canale.</summary>
    internal byte[][]? TabellePerCanale => perCanale;

    /// <summary>Applica la catena a una riga di pixel BGRA, sul posto. L'alfa non cambia.</summary>
    public unsafe void Applica(Span<byte> bgra)
    {
        var pixel = bgra.Length / 4;
        fixed (byte* inizio = bgra)
        {
            if (perCanale is { } t)
            {
                fixed (byte* tr = t[0], tg = t[1], tb = t[2])
                {
                    var p = inizio;
                    for (var i = 0; i < pixel; i++, p += 4)
                    {
                        p[0] = tb[p[0]];
                        p[1] = tg[p[1]];
                        p[2] = tr[p[2]];
                    }
                }
                return;
            }
            foreach (var s in stadi)
            {
                var m = s.Matrice;
                int m0 = m[0], m1 = m[1], m2 = m[2], m3 = m[3], m4 = m[4], m5 = m[5], m6 = m[6], m7 = m[7], m8 = m[8];
                int s0 = (s.Scostamento[0] << Bit) + Uno / 2, s1 = (s.Scostamento[1] << Bit) + Uno / 2, s2 = (s.Scostamento[2] << Bit) + Uno / 2;
                var i = 0;
                if (Avx2.IsSupported) i = StadioAvx2(s, inizio, pixel);
                fixed (ushort* ir = s.Ingresso[0], ig = s.Ingresso[1], ib = s.Ingresso[2])
                fixed (byte* ur = s.Uscita[0], ug = s.Uscita[1], ub = s.Uscita[2])
                {
                    var p = inizio + i * 4;
                    for (; i < pixel; i++, p += 4)
                    {
                        int r = ir[p[2]], g = ig[p[1]], b = ib[p[0]];
                        var nr = Math.Clamp((m0 * r + m1 * g + m2 * b + s0) >> Bit, 0, Massimo);
                        var ng = Math.Clamp((m3 * r + m4 * g + m5 * b + s1) >> Bit, 0, Massimo);
                        var nb = Math.Clamp((m6 * r + m7 * g + m8 * b + s2) >> Bit, 0, Massimo);
                        p[2] = ur[nr];
                        p[1] = ug[ng];
                        p[0] = ub[nb];
                    }
                }
            }
        }
    }

    /// <summary>
    /// Uno stadio con la matrice, 8 pixel alla volta con AVX2 (letture delle tabelle a gruppi): restituisce quanti pixel ha
    /// fatto; il resto lo fa il ciclo normale.
    /// </summary>
    private static unsafe int StadioAvx2(Compilato s, byte* inizio, int pixel)
    {
        var m = s.Matrice;
        var mezzo = Uno / 2;
        var v0 = Vector256.Create(m[0]); var v1 = Vector256.Create(m[1]); var v2 = Vector256.Create(m[2]);
        var v3 = Vector256.Create(m[3]); var v4 = Vector256.Create(m[4]); var v5 = Vector256.Create(m[5]);
        var v6 = Vector256.Create(m[6]); var v7 = Vector256.Create(m[7]); var v8 = Vector256.Create(m[8]);
        var b0 = Vector256.Create((s.Scostamento[0] << Bit) + mezzo);
        var b1 = Vector256.Create((s.Scostamento[1] << Bit) + mezzo);
        var b2 = Vector256.Create((s.Scostamento[2] << Bit) + mezzo);
        var ff = Vector256.Create(0xFF);
        var alfa = Vector256.Create(unchecked((int)0xFF000000));
        var zero = Vector256<int>.Zero;
        var massimo = Vector256.Create(Massimo);
        var i = 0;
        fixed (int* ir = s.IngressoInt[0], ig = s.IngressoInt[1], ib = s.IngressoInt[2])
        fixed (int* ur = s.UscitaInt[0], ug = s.UscitaInt[1], ub = s.UscitaInt[2])
        {
            for (; i + 8 <= pixel; i += 8)
            {
                var p = (int*)(inizio + i * 4);
                var px = Avx.LoadVector256(p);
                var b = Avx2.GatherVector256(ib, Avx2.And(px, ff), 4);
                var g = Avx2.GatherVector256(ig, Avx2.And(Avx2.ShiftRightLogical(px, 8), ff), 4);
                var r = Avx2.GatherVector256(ir, Avx2.And(Avx2.ShiftRightLogical(px, 16), ff), 4);
                var nr = Avx2.ShiftRightArithmetic(Avx2.Add(Avx2.Add(Avx2.MultiplyLow(v0, r), Avx2.MultiplyLow(v1, g)), Avx2.Add(Avx2.MultiplyLow(v2, b), b0)), Bit);
                var ng = Avx2.ShiftRightArithmetic(Avx2.Add(Avx2.Add(Avx2.MultiplyLow(v3, r), Avx2.MultiplyLow(v4, g)), Avx2.Add(Avx2.MultiplyLow(v5, b), b1)), Bit);
                var nb = Avx2.ShiftRightArithmetic(Avx2.Add(Avx2.Add(Avx2.MultiplyLow(v6, r), Avx2.MultiplyLow(v7, g)), Avx2.Add(Avx2.MultiplyLow(v8, b), b2)), Bit);
                nr = Avx2.Min(Avx2.Max(nr, zero), massimo);
                ng = Avx2.Min(Avx2.Max(ng, zero), massimo);
                nb = Avx2.Min(Avx2.Max(nb, zero), massimo);
                var or = Avx2.GatherVector256(ur, nr, 4);
                var og = Avx2.GatherVector256(ug, ng, 4);
                var ob = Avx2.GatherVector256(ub, nb, 4);
                var risultato = Avx2.Or(Avx2.Or(Avx2.And(px, alfa), Avx2.ShiftLeftLogical(or, 16)), Avx2.Or(Avx2.ShiftLeftLogical(og, 8), ob));
                Avx.Store(p, risultato);
            }
        }
        return i;
    }
}

/// <summary>Le ricette: filtri, regolazioni, calore, luce sul volto. Valori dell'iPhone e del Mac.</summary>
public static class RicetteColore
{
    /// <summary>
    /// I guadagni di rosso, verde e blu del calore a forza 1 (500 K più caldo, luminanza del bianco invariata): la stessa
    /// matrice diagonale dell'iPhone (EffettoCalore.swift), in sRGB lineare.
    /// </summary>
    public static readonly (double R, double G, double B) GuadagniCalore = (1.0467, 0.9946, 0.9158);

    /// <summary>Il calore come stadio (diagonale in lineare = una tabella per canale). Null a forza 0.</summary>
    public static StadioColore? Calore(double valore)
    {
        var forza = Math.Clamp(double.IsFinite(valore) ? valore : 0, 0, 1);
        if (forza <= 0.001) return null;
        double[] guadagni = [1 + (GuadagniCalore.R - 1) * forza, 1 + (GuadagniCalore.G - 1) * forza, 1 + (GuadagniCalore.B - 1) * forza];
        return StadioColore.PerCanale((c, v) => Colore.InSrgb(Colore.InLineare(v) * guadagni[c]));
    }

    /// <summary>Gli stadi di un filtro del protocollo; nessuno per «naturale» o uno sconosciuto.</summary>
    public static IReadOnlyList<StadioColore> Filtro(string filtro)
    {
        switch (filtro)
        {
            case Filtri.Caldo:
                return [StadioColore.Lineare(Colore.Per(Colore.Saturazione(1.05), Colore.Diagonale(1.07, 1.0, 0.88)))];
            case Filtri.Freddo:
            {
                var curva = Colore.Curva([(0, 0), (0.25, 0.25), (0.5, 0.51), (0.75, 0.77), (1, 1)]);
                return [StadioColore.Lineare(Colore.Per(Colore.Saturazione(0.97), Colore.Diagonale(0.92, 0.98, 1.08)),
                    v => curva(Colore.InSrgb(v)))];
            }
            case Filtri.Luminoso:
            {
                var curva = Colore.Curva([(0, 0.04), (0.25, 0.33), (0.5, 0.59), (0.75, 0.81), (1, 1)]);
                return [StadioColore.PerCanale((_, v) => curva(v))];
            }
            case Filtri.Cinema:
            {
                // In sRGB: ombre verso il blu, luci verso il rosso (pesate con il valore del canale), contrasto a S,
                // saturazione 0,92. La vignettatura la fa la resa (Compositore), con la sua mappa.
                double[] ombre = [0.90, 1.0, 1.06], luci = [1.07, 1.0, 0.90], bias = [0, 0.004, 0.012];
                var curva = Colore.Curva([(0, 0.02), (0.25, 0.20), (0.5, 0.5), (0.75, 0.80), (1, 0.98)]);
                return [new StadioColore((c, v) => curva(Math.Clamp(v * (ombre[c] + (luci[c] - ombre[c]) * v) + bias[c] * (1 - v), 0, 1)),
                    Colore.Saturazione(0.92), [0, 0, 0], (_, v) => v)];
            }
            case Filtri.Vivido:
                // Vibranza 0,5 (circa una saturazione di 1,2 sui colori spenti) per la saturazione 1,12, contrasto 1,04.
                return [StadioColore.Lineare(Colore.Saturazione(1.12 * 1.2), v => Colore.InSrgb((v - 0.5) * 1.04 + 0.5))];
            case Filtri.Tenue:
            {
                var curva = Colore.Curva([(0, 0.06), (0.25, 0.29), (0.5, 0.52), (0.75, 0.75), (1, 0.96)]);
                return [StadioColore.Lineare(Colore.Saturazione(0.72), v => curva(Colore.InSrgb(v)))];
            }
            case Filtri.BiancoNero:
            {
                var curva = Colore.Curva([(0, 0), (0.25, 0.23), (0.5, 0.5), (0.75, 0.78), (1, 1)]);
                return [StadioColore.Lineare(Colore.Saturazione(0), v => curva(Colore.InSrgb(v)))];
            }
            case Filtri.Seppia:
            {
                // CISepiaTone a 0,75: la matrice seppia classica mescolata con l'identità.
                double[] seppia = [0.393, 0.769, 0.189, 0.349, 0.686, 0.168, 0.272, 0.534, 0.131];
                var matrice = new double[9];
                for (var i = 0; i < 9; i++) matrice[i] = 0.75 * seppia[i] + 0.25 * Colore.Identita[i];
                var curva = Colore.Curva([(0, 0.04), (0.25, 0.27), (0.5, 0.51), (0.75, 0.75), (1, 0.97)]);
                return [StadioColore.Lineare(matrice, v => curva(Colore.InSrgb(v)))];
            }
            case Filtri.Notte:
            {
                // +0,5 EV in lineare, la curva in sRGB, poi saturazione 0,95.
                var guadagno = Math.Pow(2, 0.5);
                var curva = Colore.Curva([(0, 0.03), (0.25, 0.34), (0.5, 0.60), (0.75, 0.82), (1, 1)]);
                return
                [
                    StadioColore.PerCanale((_, v) => curva(Colore.InSrgb(Colore.InLineare(v) * guadagno))),
                    StadioColore.Lineare(Colore.Saturazione(0.95)),
                ];
            }
            default:
                return [];
        }
    }

    /// <summary>
    /// Luminosità, contrasto e saturazione dell'utente (come CIColorControls nelle regolazioni dell'iPhone: un quarto
    /// della luminosità, contrasto 1 + c/2, saturazione 1 + s). La nitidezza la fa la resa, con un vicinato.
    /// </summary>
    public static StadioColore? Regolazioni(double luminosita, double contrasto, double saturazione)
    {
        static double Limita(double v) => double.IsFinite(v) ? Math.Clamp(v, -1, 1) : 0;
        var luce = Limita(luminosita) * 0.25;
        var k = 1 + Limita(contrasto) * 0.5;
        var s = 1 + Limita(saturazione);
        if (luce == 0 && k == 1 && s == 1) return null;
        return StadioColore.Lineare(Colore.Saturazione(s), v => Colore.InSrgb((v + luce - 0.5) * k + 0.5));
    }

    /// <summary>Filtro e regolazioni in una catena; null se non c'è niente da fare.</summary>
    public static CatenaColore? Catena(string filtro, double luminosita, double contrasto, double saturazione)
    {
        var stadi = new List<StadioColore>(Filtro(filtro));
        if (Regolazioni(luminosita, contrasto, saturazione) is { } r) stadi.Add(r);
        return CatenaColore.Da(stadi);
    }

    /// <summary>La curva della luce sul volto (circa +0,4 EV su ombre e mezzitoni, il bianco al suo posto), in sRGB.</summary>
    public static byte[] TabellaLuceVolto()
    {
        var curva = Colore.Curva([(0, 0), (0.25, 0.29), (0.5, 0.565), (0.75, 0.81), (1, 1)]);
        var tabella = new byte[256];
        for (var v = 0; v < 256; v++) tabella[v] = (byte)Math.Clamp((int)Math.Round(curva(v / 255.0) * 255), 0, 255);
        return tabella;
    }
}
