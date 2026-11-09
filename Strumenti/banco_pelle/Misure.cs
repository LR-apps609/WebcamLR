using WebcamLR.Effetti;

namespace BancoPelle;

/// <summary>Le misure di un fotogramma (vedi Program.cs) e la loro media.</summary>
public sealed class Misure
{
    public double RugIn, RugOut, Grana, Occhi, Bocca, Capelli, Contorno, Alone, Cb, Cr;

    public void Somma(Misure m)
    {
        RugIn += m.RugIn; RugOut += m.RugOut; Grana += m.Grana; Occhi += m.Occhi; Bocca += m.Bocca; Capelli += m.Capelli;
        Contorno += m.Contorno; Alone += m.Alone; Cb += m.Cb; Cr += m.Cr;
    }

    public void Media(int n)
    {
        RugIn /= n; RugOut /= n; Grana /= n; Occhi /= n; Bocca /= n; Capelli /= n; Contorno /= n; Alone /= n; Cb /= n; Cr /= n;
    }

    public static float[] Luma(ImmagineBgra im)
    {
        var y = new float[im.Larghezza * im.Altezza];
        for (var i = 0; i < y.Length; i++) y[i] = 0.2126f * im.Dati[i * 4 + 2] + 0.7152f * im.Dati[i * 4 + 1] + 0.0722f * im.Dati[i * 4];
        return y;
    }

    private static (float Cb, float Cr) CbCr(byte[] d, int i)
    {
        float r = d[i * 4 + 2], g = d[i * 4 + 1], b = d[i * 4];
        return (-0.168736f * r - 0.331264f * g + 0.5f * b, 0.5f * r - 0.418688f * g - 0.081312f * b);
    }

    public static Misure Una(Volto v, ImmagineBgra ingresso, ImmagineBgra uscita)
    {
        int l = Volto.L, a = Volto.A;
        var yi = Luma(ingresso);
        var yo = Luma(uscita);
        double ri = 0, ro = 0, hi = 0, ho = 0, cb = 0, cr = 0; var n = 0;
        for (var y = 1; y < a - 1; y++)
            for (var x = 1; x < l - 1; x++)
            {
                var i = y * l + x;
                if (!v.Nucleo[i]) continue;
                ri += Q(yi[i] - v.Pulita[i]);
                ro += Q(yo[i] - v.Pulita[i]);
                hi += Q(Fine(yi, i, l));
                ho += Q(Fine(yo, i, l));
                var (cbi, cri) = CbCr(ingresso.Dati, i);
                var (cbo, cro) = CbCr(uscita.Dati, i);
                cb += cbo - cbi; cr += cro - cri;
                n++;
            }
        double alone = 0; var na = 0;
        for (var i = 0; i < l * a; i++)
        {
            if (!v.Anello[i]) continue;
            for (var c = 0; c < 3; c++) alone += Math.Abs(uscita.Dati[i * 4 + c] - ingresso.Dati[i * 4 + c]);
            na += 3;
        }
        return new Misure
        {
            RugIn = Math.Sqrt(ri / n), RugOut = Math.Sqrt(ro / n), Grana = Math.Sqrt(ho / hi), Cb = cb / n, Cr = cr / n,
            Occhi = Gradiente(yi, yo, v.Occhi), Bocca = Gradiente(yi, yo, v.Bocca), Capelli = Gradiente(yi, yo, v.Capelli),
            Contorno = Gradiente(yi, yo, v.Contorno), Alone = alone / na,
        };
    }

    /// <summary>Il pixel meno la sua binomiale 3×3: la grana più fine.</summary>
    private static float Fine(float[] y, int i, int l) =>
        y[i] - (4 * y[i] + 2 * (y[i - 1] + y[i + 1] + y[i - l] + y[i + l]) + y[i - l - 1] + y[i - l + 1] + y[i + l - 1] + y[i + l + 1]) / 16;

    private static double Sobel(float[] y, int i, int l)
    {
        var gx = y[i - l + 1] + 2 * y[i + 1] + y[i + l + 1] - y[i - l - 1] - 2 * y[i - 1] - y[i + l - 1];
        var gy = y[i + l - 1] + 2 * y[i + l] + y[i + l + 1] - y[i - l - 1] - 2 * y[i - l] - y[i - l + 1];
        return Math.Sqrt(gx * gx + gy * gy);
    }

    /// <summary>Gradiente medio dell'uscita diviso quello dell'ingresso nella zona (1 = bordi intatti).</summary>
    private static double Gradiente(float[] yi, float[] yo, bool[] zona)
    {
        int l = Volto.L, a = Volto.A;
        double gi = 0, go = 0;
        for (var y = 1; y < a - 1; y++)
            for (var x = 1; x < l - 1; x++)
            {
                var i = y * l + x;
                if (!zona[i]) continue;
                gi += Sobel(yi, i, l);
                go += Sobel(yo, i, l);
            }
        return go / gi;
    }

    private static double Q(double v) => v * v;

    public readonly record struct MisureLuce(double DeltaY, double Saturazione, double Tinta, double Riflessi, double Bruciati, double Sfondo);

    /// <summary>
    /// La luce sul volto: ΔY e saturazione (croma out / in) nel nucleo della pelle, tinta (angolo di Cb, Cr) in gradi, ΔY
    /// sui riflessi (luma ≥ 215), punti con un canale a 255 che prima non c'erano (% dell'ellisse della luce), ΔY medio
    /// sullo sfondo accanto al viso.
    /// </summary>
    public static MisureLuce Luce(Volto v, ImmagineBgra ingresso, ImmagineBgra uscita)
    {
        var yi = Luma(ingresso);
        var yo = Luma(uscita);
        double dy = 0, ci = 0, co = 0, tinta = 0, rif = 0, sf = 0; int n = 0, nr = 0, ns = 0, ne = 0, bruciati = 0;
        for (var i = 0; i < yi.Length; i++)
        {
            if (v.Ellisse[i])
            {
                ne++;
                var maxI = Math.Max(ingresso.Dati[i * 4], Math.Max(ingresso.Dati[i * 4 + 1], ingresso.Dati[i * 4 + 2]));
                var maxO = Math.Max(uscita.Dati[i * 4], Math.Max(uscita.Dati[i * 4 + 1], uscita.Dati[i * 4 + 2]));
                if (maxO == 255 && maxI < 255) bruciati++;
                if (yi[i] >= 215 && !v.Occhi[i]) { rif += yo[i] - yi[i]; nr++; }
            }
            if (v.Anello[i]) { sf += yo[i] - yi[i]; ns++; }
            if (!v.Nucleo[i]) continue;
            dy += yo[i] - yi[i];
            var (cbi, cri) = CbCr(ingresso.Dati, i);
            var (cbo, cro) = CbCr(uscita.Dati, i);
            ci += Math.Sqrt(cbi * cbi + cri * cri);
            co += Math.Sqrt(cbo * cbo + cro * cro);
            var d = Math.Atan2(cro, cbo) - Math.Atan2(cri, cbi);
            tinta += d * 180 / Math.PI;
            n++;
        }
        return new MisureLuce(dy / n, co / ci, tinta / n, nr > 0 ? rif / nr : 0, 100.0 * bruciati / ne, sf / Math.Max(1, ns));
    }
}

/// <summary>
/// Un modello in C# del ritocco della pelle del Mac di prima (RicetteEffetti.pelle al commit 7e5dd09): gaussiana piccola
/// (σ dallo 0,25% allo 0,55% dell'altezza del volto, al massimo 3 px), maschera dei dettagli 1 − 25/3 · Σ|originale −
/// sfocata| in sRGB allargata con un minimo locale di raggio σ, disco morbido (0,38–0,72 del lato), forza massima 0,5. Il
/// Mac lavora in lineare e sfoca in lineare: qui tutto in sRGB, quindi è un'approssimazione.
/// </summary>
public static class MacPrima
{
    public static void Pelle(ImmagineBgra im, double valore, Rettangolo volto)
    {
        var forza = Math.Clamp(valore, 0, 1);
        int l = im.Larghezza, a = im.Altezza, n = l * a;
        var sigma = Math.Min(Math.Max(1, volto.Altezza * (0.0025 + 0.003 * forza)), 3);
        var lato = Math.Max(volto.Larghezza, volto.Altezza);
        double cx = volto.CentroX, cy = volto.CentroY + volto.Altezza * 0.04;
        int x0 = Math.Max(0, (int)(cx - lato * 0.75)), x1 = Math.Min(l, (int)(cx + lato * 0.75));
        int y0 = Math.Max(0, (int)(cy - lato * 0.75)), y1 = Math.Min(a, (int)(cy + lato * 0.75));
        var piani = new float[3][];
        for (var c = 0; c < 3; c++)
        {
            var p = new float[n];
            for (var i = 0; i < n; i++) p[i] = im.Dati[i * 4 + c];
            Elaborazione.Gaussiana(p, l, a, 1, sigma, new float[n]);
            piani[c] = p;
        }
        var dettagli = new float[n];
        for (var i = 0; i < n; i++)
        {
            float s = 0;
            for (var c = 0; c < 3; c++) s += Math.Abs(im.Dati[i * 4 + c] - piani[c][i]) / 255f;
            dettagli[i] = Math.Clamp(1 - 25f / 3 * s, 0, 1);
        }
        var raggio = (int)Math.Max(1, Math.Round(sigma));
        var minimo = new float[n];
        for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++)
            {
                var m = 1f;
                for (var dy = -raggio; dy <= raggio; dy++)
                    for (var dx = -raggio; dx <= raggio; dx++)
                    {
                        if (dx * dx + dy * dy > raggio * raggio) continue;
                        int xx = Math.Clamp(x + dx, 0, l - 1), yy = Math.Clamp(y + dy, 0, a - 1);
                        m = Math.Min(m, dettagli[yy * l + xx]);
                    }
                minimo[y * l + x] = m;
            }
        for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++)
            {
                var d = Math.Sqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy));
                var disco = d <= lato * 0.38 ? 1 : d >= lato * 0.72 ? 0 : (lato * 0.72 - d) / (lato * 0.34);
                var i = y * l + x;
                var peso = (float)(disco * minimo[i] * 0.5 * forza);
                for (var c = 0; c < 3; c++)
                    im.Dati[i * 4 + c] = (byte)Math.Clamp(Math.Round(im.Dati[i * 4 + c] + (piani[c][i] - im.Dati[i * 4 + c]) * peso), 0, 255);
            }
    }
}
