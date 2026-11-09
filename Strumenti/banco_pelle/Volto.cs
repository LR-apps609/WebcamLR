using WebcamLR.Effetti;

namespace BancoPelle;

/// <summary>
/// Un volto sintetico 1920×1080, disegnato qui (nessuna foto di persone): pelle con ombreggiatura, macchie (σ 5 px, 4%),
/// pori (σ 1,2 px, 3%), grana fine (σ 0,6 px, 2%), qualche brufolo rosso e due riflessi; occhi con palpebre e ciglia,
/// sopracciglia a peli, labbra, narici, capelli a ciocche con la frangia sulla fronte, collo, maglia; dietro un pannello
/// di legno (colore simile alla pelle) e una parete grigia. Tutto in sRGB 0..1, poi in byte con il rumore del sensore.
/// «Pulita» è lo stesso volto senza macchie, pori e brufoli (con la grana fine e i riflessi): il risultato ideale.
/// </summary>
public sealed class Volto
{
    public const int L = 1920, A = 1080;

    public readonly double Cx = 960, Cy = 540, Ax = 170, Ay = 225;
    public ImmagineBgra Senza { get; }            // senza rumore del sensore
    public float[] Pulita { get; }                // luma (0..255) del volto ideale, senza rumore
    public float[] PulitaCr { get; }              // Cr (BT.601, attorno a 0) del volto ideale
    public bool[] Nucleo { get; }                 // pelle lontana dai lineamenti
    public bool[] Occhi { get; }                  // occhi e sopracciglia
    public bool[] Bocca { get; }
    public bool[] Capelli { get; }                // frangia e capelli attorno alla fronte
    public bool[] Contorno { get; }               // ±6 px dal contorno del viso (senza capelli)
    public bool[] Anello { get; }                 // sfondo da 6 a 30 px fuori dal viso
    public bool[] Ellisse { get; }                // l'ellisse della luce sul volto (per le bruciature)
    public string Nome { get; }

    /// <summary>Il rettangolo del volto come lo stima il motore (la pelle del viso), in pixel.</summary>
    public Rettangolo Rettangolo => new(Cx - Ax, Cy - Ay * 0.8, 2 * Ax, Ay * 1.8);

    /// <summary>Le zone da proteggere (occhi con sopracciglia, bocca), come le darebbero i punti del volto di Vision.</summary>
    public IReadOnlyList<(double Cx, double Cy, double Ax, double Ay)> Lineamenti { get; }

    private readonly Random caso;

    public Volto(string nome, (double R, double G, double B) pelle, int seme)
    {
        Nome = nome;
        caso = new Random(seme);
        int n = L * A;
        var r = new float[n]; var g = new float[n]; var b = new float[n];
        var pr = new float[n]; var pg = new float[n]; var pb = new float[n];

        // Sfondo: legno a sinistra (venature verticali), parete grigio-blu a destra, una libreria in fondo a destra.
        var venature = RumoreStirato(1.5, 30);
        var parete = Rumore(8, 1);
        for (var y = 0; y < A; y++)
            for (var x = 0; x < L; x++)
            {
                var i = y * L + x;
                (double, double, double) c;
                if (x < 820) { var v = 1 + 0.12 * venature[i]; c = (0.59 * v, 0.39 * v, 0.24 * v); }
                else if (x > 1620 && y > 200 && y < 900) { var k = ((x - 1620) / 40 + (y - 200) / 120) % 4; c = k switch { 0 => (0.55, 0.15, 0.12), 1 => (0.15, 0.30, 0.55), 2 => (0.80, 0.75, 0.55), _ => (0.20, 0.45, 0.25) }; }
                else { var v = 1 + 0.03 * parete[i]; c = (0.43 * v, 0.47 * v, 0.51 * v); }
                Metti(r, g, b, i, c, 1);
            }

        // Capelli dietro e attorno alla fronte (fino alle orecchie): ciocche verticali (rumore stirato), castano scuro.
        var ciocche = RumoreStirato(0.7, 7);
        double hx = Cx, hy = Cy - 40, hax = Ax + 45, hay = Ay + 55;
        Disegna(r, g, b, hx - hax, hy - hay, hx + hax, Cy - Ay * 0.15, (x, y) =>
        {
            var d = D(x, y, hx, hy, hax, hay);
            return (Copertura(d, Math.Min(hax, hay)), Capello(ciocche[y * L + x]));
        });
        // Collo e maglia.
        Disegna(r, g, b, Cx - Ax * 0.55, Cy + Ay * 0.6, Cx + Ax * 0.55, A, (x, y) => (1, (pelle.R * 0.8, pelle.G * 0.8, pelle.B * 0.8)));
        Disegna(r, g, b, Cx - 420, Cy + Ay + 110, Cx + 420, A, (x, y) => (1, (0.10, 0.14, 0.26)));

        // La pelle del viso: ombreggiatura di una sfera illuminata da sinistra in alto, macchie, pori, grana, brufoli.
        var macchie = Rumore(5, 0.04);
        var pori = Rumore(1.2, 0.03);
        var grana = Rumore(0.6, 0.02);
        var brufoli = new List<(double X, double Y, double R)>();
        for (var k = 0; k < 14; k++)
        {
            var ang = caso.NextDouble() * Math.PI * 2;
            var rr = Math.Sqrt(caso.NextDouble()) * 0.75;
            brufoli.Add((Cx + Math.Cos(ang) * rr * Ax, Cy + 30 + Math.Sin(ang) * rr * Ay * 0.7, 3 + caso.NextDouble() * 4));
        }
        Array.Copy(r, pr, n); Array.Copy(g, pg, n); Array.Copy(b, pb, n);
        for (var y = (int)(Cy - Ay - 2); y <= (int)(Cy + Ay + 2); y++)
            for (var x = (int)(Cx - Ax - 2); x <= (int)(Cx + Ax + 2); x++)
            {
                var d = D(x, y, Cx, Cy, Ax, Ay);
                var cop = Copertura(d, Ax);
                if (cop <= 0) continue;
                var i = y * L + x;
                double nx = (x - Cx) / Ax, ny = (y - Cy) / Ay;
                var nz = Math.Sqrt(Math.Max(0, 1 - nx * nx - ny * ny));
                var luce = 0.72 + 0.30 * nz + 0.08 * (-nx - ny) / 2;
                // Riflessi sulla fronte e sulla punta del naso.
                var riflesso = 0.16 * Math.Exp(-(Q(x - Cx + 20) + Q(y - Cy + 120)) / (2 * 22 * 22)) + 0.12 * Math.Exp(-(Q(x - Cx) + Q(y - Cy - 45)) / (2 * 9 * 9));
                var pulito = (pelle.R * luce * (1 + grana[i]) + riflesso, pelle.G * luce * (1 + grana[i]) + riflesso, pelle.B * luce * (1 + grana[i]) + riflesso);
                var t = 1 + macchie[i] + pori[i] + grana[i];
                var rosso = 0.0;
                foreach (var (bx, by, br) in brufoli) rosso = Math.Max(rosso, Math.Exp(-(Q(x - bx) + Q(y - by)) / (2 * br * br)));
                var sporco = (pelle.R * luce * t + riflesso, pelle.G * luce * t * (1 - 0.12 * rosso) + riflesso, pelle.B * luce * t * (1 - 0.14 * rosso) + riflesso);
                Metti(r, g, b, i, sporco, cop);
                Metti(pr, pg, pb, i, pulito, cop);
            }

        // I lineamenti, uguali nei due: occhi, sopracciglia, narici, labbra, frangia.
        var lineamenti = new List<(double, double, double, double)>();
        var peli = new List<(double X0, double Y0, double X1, double Y1)>();
        foreach (var lato in new[] { -1, 1 })
        {
            double ex = Cx + lato * 72, ey = Cy - 38;
            lineamenti.Add((ex, ey - 22, 58, 42));
            // Sopracciglio: 70 peli inclinati lungo un arco.
            for (var k = 0; k < 70; k++)
            {
                var t = caso.NextDouble();
                var px = ex - 46 + 92 * t;
                var py = ey - 48 - 10 * Math.Sin(t * Math.PI) + caso.NextDouble() * 8;
                var ang = (lato > 0 ? 0.25 : Math.PI - 0.25) + (caso.NextDouble() - 0.5) * 0.4;
                peli.Add((px, py, px + Math.Cos(ang) * 14 * (lato > 0 ? 1 : 1), py - Math.Abs(Math.Sin(ang)) * 6));
            }
        }
        foreach (var sr in new[] { (r, g, b), (pr, pg, pb) })
        {
            foreach (var lato in new[] { -1, 1 })
            {
                double ex = Cx + lato * 72, ey = Cy - 38;
                Disegna(sr.Item1, sr.Item2, sr.Item3, ex - 40, ey - 20, ex + 40, ey + 20, (x, y) => (Copertura(D(x, y, ex, ey, 34, 13), 13), (0.90, 0.88, 0.86)));
                Disegna(sr.Item1, sr.Item2, sr.Item3, ex - 16, ey - 16, ex + 16, ey + 16, (x, y) => (Copertura(Math.Sqrt(Q(x - ex) + Q(y - ey)) / 12, 12) * (y > ey - 13 ? 1 : 0), (0.30, 0.20, 0.12)));
                Disegna(sr.Item1, sr.Item2, sr.Item3, ex - 7, ey - 7, ex + 7, ey + 7, (x, y) => (Copertura(Math.Sqrt(Q(x - ex) + Q(y - ey)) / 5, 5), (0.03, 0.03, 0.03)));
                // Palpebra: un arco scuro spesso 3 px sopra l'occhio, e le ciglia.
                Disegna(sr.Item1, sr.Item2, sr.Item3, ex - 40, ey - 20, ex + 40, ey, (x, y) =>
                {
                    var d = D(x, y, ex, ey + 2, 36, 15);
                    return (y < ey ? Math.Clamp(1.6 - Math.Abs(d - 1) * 15 / 1.6, 0, 1) : 0, (0.12, 0.08, 0.07));
                });
            }
            foreach (var (x0, y0, x1, y1) in peli)
                Disegna(sr.Item1, sr.Item2, sr.Item3, Math.Min(x0, x1) - 2, Math.Min(y0, y1) - 2, Math.Max(x0, x1) + 2, Math.Max(y0, y1) + 2,
                    (x, y) => (Math.Clamp(1.2 - Segmento(x, y, x0, y0, x1, y1), 0, 1) * 0.85, (0.16, 0.10, 0.07)));
            foreach (var lato in new[] { -1, 1 })
            {
                double nx = Cx + lato * 16, ny = Cy + 62;
                Disegna(sr.Item1, sr.Item2, sr.Item3, nx - 10, ny - 8, nx + 10, ny + 8, (x, y) => (Copertura(D(x, y, nx, ny, 8, 5), 5) * 0.7, (0.25, 0.13, 0.10)));
            }
            double mx = Cx, my = Cy + 115;
            Disegna(sr.Item1, sr.Item2, sr.Item3, mx - 64, my - 22, mx + 64, my + 22, (x, y) =>
            {
                var d = D(x, y, mx, my, 58, 18);
                var c = (0.68 * pelle.R / 0.78 + 0.05, 0.36 * pelle.G / 0.60, 0.38 * pelle.B / 0.50);
                if (Math.Abs(y - my) < 1.5) c = (c.Item1 * 0.4, c.Item2 * 0.4, c.Item3 * 0.4);
                return (Copertura(d, 18), c);
            });
            // Frangia: ciocche che scendono sulla fronte, con il bordo frastagliato.
            var cima = Cy - Ay * 0.72;
            Disegna(sr.Item1, sr.Item2, sr.Item3, Cx - Ax, Cy - Ay - 10, Cx + Ax, cima + 60, (x, y) =>
            {
                var n0 = ciocche[y * L + x];
                var limite = cima + 25 + 30 * Math.Sin((x - Cx) / 37.0) + 35 * n0;
                return (Math.Clamp((limite - y) / 2.0, 0, 1) * (D(x, y, hx, hy, hax, hay) < 1 ? 1 : 0), Capello(n0));
            });
        }
        lineamenti.Add((Cx, Cy + 115, 76, 32));
        Lineamenti = lineamenti;

        // In byte (senza rumore) e la luma pulita.
        Senza = new ImmagineBgra(L, A);
        Pulita = new float[n];
        PulitaCr = new float[n];
        for (var i = 0; i < n; i++)
        {
            Senza.Dati[i * 4 + 2] = B8(r[i]); Senza.Dati[i * 4 + 1] = B8(g[i]); Senza.Dati[i * 4] = B8(b[i]); Senza.Dati[i * 4 + 3] = 255;
            Pulita[i] = (float)(0.2126 * B8(pr[i]) + 0.7152 * B8(pg[i]) + 0.0722 * B8(pb[i]));
            PulitaCr[i] = (float)(0.5 * B8(pr[i]) - 0.418688 * B8(pg[i]) - 0.081312 * B8(pb[i]));
        }

        // Le zone delle misure.
        Nucleo = new bool[n]; Occhi = new bool[n]; Bocca = new bool[n]; Capelli = new bool[n]; Contorno = new bool[n]; Anello = new bool[n]; Ellisse = new bool[n];
        for (var y = 0; y < A; y++)
            for (var x = 0; x < L; x++)
            {
                var i = y * L + x;
                var d = D(x, y, Cx, Cy, Ax, Ay);
                var vicinoLineamento = false;
                foreach (var (lx, ly, lax, lay) in lineamenti)
                {
                    var dl = D(x, y, lx, ly, lax, lay);
                    if (dl < 1) { if (ly < Cy + 50) Occhi[i] = true; else Bocca[i] = true; }
                    if (dl < 1.25) vicinoLineamento = true;
                }
                foreach (var lato in new[] { -1, 1 }) if (D(x, y, Cx + lato * 16, Cy + 62, 20, 16) < 1) vicinoLineamento = true;
                var cima = Cy - Ay * 0.72;
                Capelli[i] = d < 1.0 && y < cima + 100 && y > Cy - Ay - 5;
                Nucleo[i] = d < 0.85 && !vicinoLineamento && y > cima + 110;
                Contorno[i] = Math.Abs(d - 1) * Ax < 6 && y > Cy - Ay * 0.1 && y < Cy + Ay * 0.6;
                Anello[i] = d > 1 && (d - 1) * Ax > 6 && (d - 1) * Ax < 30 && y > Cy - Ay * 0.1 && y < Cy + Ay * 0.55
                    && Math.Abs(x - Cx) > Ax * 0.55 + 4;
                Ellisse[i] = D(x, y, Cx, Cy + Ay * (0.1 + 1.8 * 0.08), Ax * 2, Ay * 1.8 * 1.25) < 0.9;
            }
    }

    /// <summary>Il fotogramma con il rumore del sensore (σ = 2/255 per canale), diverso a ogni seme.</summary>
    public ImmagineBgra ConRumore(int seme, double sigma = 2)
    {
        var c = new Random(seme);
        var u = Senza.Copia();
        for (var i = 0; i < u.Dati.Length; i++)
        {
            if ((i & 3) == 3) continue;
            u.Dati[i] = (byte)Math.Clamp(Math.Round(u.Dati[i] + Gauss(c) * sigma), 0, 255);
        }
        return u;
    }

    private static (double, double, double) Capello(double n) => (0.22 + 0.10 * n, 0.14 + 0.07 * n, 0.09 + 0.05 * n);

    private static double Q(double v) => v * v;
    private static double D(double x, double y, double cx, double cy, double ax, double ay) => Math.Sqrt(Q((x + 0.5 - cx) / ax) + Q((y + 0.5 - cy) / ay));
    private static double Copertura(double d, double raggio) => Math.Clamp((1 - d) * raggio + 0.5, 0, 1);
    private static byte B8(double v) => (byte)Math.Clamp(Math.Round(v * 255), 0, 255);

    private static double Segmento(double x, double y, double x0, double y0, double x1, double y1)
    {
        double px = x + 0.5 - x0, py = y + 0.5 - y0, dx = x1 - x0, dy = y1 - y0;
        var t = Math.Clamp((px * dx + py * dy) / (dx * dx + dy * dy), 0, 1);
        return Math.Sqrt(Q(px - t * dx) + Q(py - t * dy));
    }

    private static void Metti(float[] r, float[] g, float[] b, int i, (double R, double G, double B) c, double peso)
    {
        r[i] = (float)(r[i] + (c.R - r[i]) * peso);
        g[i] = (float)(g[i] + (c.G - g[i]) * peso);
        b[i] = (float)(b[i] + (c.B - b[i]) * peso);
    }

    private static void Disegna(float[] r, float[] g, float[] b, double x0, double y0, double x1, double y1,
        Func<int, int, (double Peso, (double, double, double) Colore)> f)
    {
        for (var y = Math.Max(0, (int)y0); y < Math.Min(A, (int)Math.Ceiling(y1)); y++)
            for (var x = Math.Max(0, (int)x0); x < Math.Min(L, (int)Math.Ceiling(x1)); x++)
            {
                var (p, c) = f(x, y);
                if (p > 0) Metti(r, g, b, y * L + x, c, p);
            }
    }

    private static double Gauss(Random c) => Math.Sqrt(-2 * Math.Log(1 - c.NextDouble())) * Math.Cos(2 * Math.PI * c.NextDouble());

    /// <summary>Rumore gaussiano sfocato con σ, riportato a deviazione standard <paramref name="ampiezza"/>.</summary>
    private float[] Rumore(double sigma, double ampiezza)
    {
        var n = L * A;
        var v = new float[n];
        for (var i = 0; i < n; i++) v[i] = (float)Gauss(caso);
        Elaborazione.Gaussiana(v, L, A, 1, sigma, new float[n]);
        Normalizza(v, ampiezza);
        return v;
    }

    /// <summary>Rumore stirato in verticale (ciocche): σ <paramref name="sx"/> in orizzontale, <paramref name="sy"/> in verticale.</summary>
    private float[] RumoreStirato(double sx, double sy)
    {
        var n = L * A;
        var v = new float[n];
        for (var i = 0; i < n; i++) v[i] = (float)Gauss(caso);
        // Prima tutto con sx, poi solo in verticale con una media lungo le colonne (≈ gaussiana sy).
        Elaborazione.Gaussiana(v, L, A, 1, sx, new float[n]);
        var raggio = (int)(sy * 1.7);
        var col = new float[A];
        for (var x = 0; x < L; x++)
        {
            for (var y = 0; y < A; y++) col[y] = v[y * L + x];
            for (var y = 0; y < A; y++)
            {
                float s = 0; var c = 0;
                for (var k = Math.Max(0, y - raggio); k <= Math.Min(A - 1, y + raggio); k++) { s += col[k]; c++; }
                v[y * L + x] = s / c;
            }
        }
        Normalizza(v, 1);
        return v;
    }

    private static void Normalizza(float[] v, double ampiezza)
    {
        double s = 0, s2 = 0;
        foreach (var x in v) { s += x; s2 += x * x; }
        var m = s / v.Length;
        var dev = Math.Sqrt(Math.Max(1e-12, s2 / v.Length - m * m));
        for (var i = 0; i < v.Length; i++) v[i] = (float)((v[i] - m) / dev * ampiezza);
    }
}
