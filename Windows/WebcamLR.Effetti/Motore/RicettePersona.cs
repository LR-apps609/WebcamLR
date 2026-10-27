namespace WebcamLR.Effetti;

/// <summary>
/// Ritocco della pelle (EffettoPelle.swift), luce sul volto (EffettoLuceVolto.swift, la parte «schiarisci il viso») e
/// nitidezza delle regolazioni, sul posto, in pixel BGRA sRGB. Pelle e luce lavorano solo attorno ai volti.
/// </summary>
public static class RicettePersona
{
    /// <summary>Oltre circa 1/12 di differenza dalla versione sfocata è un bordo, non pelle (come sul Mac).</summary>
    private const float SensibilitaBordi = 12f;

    /// <param name="volti">I rettangoli dei volti in pixel (origine in alto).</param>
    /// <param name="leggero">Senza la maschera dei bordi, a forza dimezzata (livelli più bassi).</param>
    public static void Pelle(ImmagineBgra immagine, double valore, IReadOnlyList<Rettangolo> volti, bool leggero)
    {
        var forza = (float)Math.Clamp(valore, 0, 1);
        int l = immagine.Larghezza, a = immagine.Altezza;
        var rettangoli = volti.Where(v => v.Altezza > 8 && v.Destra > 0 && v.Basso > 0 && v.X < l && v.Y < a).ToList();
        if (forza <= 0.001 || rettangoli.Count == 0) return;
        var altezzaMassima = rettangoli.Max(v => v.Altezza);
        var zona = rettangoli.Select(v => new Rettangolo(v.X - v.Larghezza * 0.4, v.Y - v.Altezza * 0.45, v.Larghezza * 1.8, v.Altezza * 1.9))
            .Aggregate((x, y) => x.Unione(y));
        int zx0 = Math.Clamp((int)zona.X, 0, l), zy0 = Math.Clamp((int)zona.Y, 0, a);
        int zx1 = Math.Clamp((int)Math.Ceiling(zona.Destra), 0, l), zy1 = Math.Clamp((int)Math.Ceiling(zona.Basso), 0, a);
        if (zx1 - zx0 < 4 || zy1 - zy0 < 4) return;

        // La versione sfocata della zona, a metà risoluzione (come sul Mac): due medie quadrate ≈ una gaussiana.
        var sigma = Math.Max(1.5, altezzaMassima * (0.008 + 0.01 * forza));
        int lm = (zx1 - zx0) / 2, am = (zy1 - zy0) / 2;
        if (lm < 2 || am < 2) return;
        var piani = new float[3][];
        var appoggio = new float[lm * am];
        var uscita = new float[lm * am];
        var sigmaMeta = sigma / 2;
        var raggio = Math.Max(1, (int)Math.Round((Math.Sqrt(6 * sigmaMeta * sigmaMeta + 1) - 1) / 2));
        for (var c = 0; c < 3; c++)
        {
            var piano = new float[lm * am];
            for (var y = 0; y < am; y++)
            {
                var r0 = (zy0 + 2 * y) * immagine.Passo;
                var r1 = r0 + immagine.Passo;
                for (var x = 0; x < lm; x++)
                {
                    var o = (zx0 + 2 * x) * 4 + c;
                    piano[y * lm + x] = (immagine.Dati[r0 + o] + immagine.Dati[r0 + o + 4] + immagine.Dati[r1 + o] + immagine.Dati[r1 + o + 4]) * 0.25f;
                }
            }
            Elaborazione.MediaQuadrata(piano, uscita, lm, am, raggio, appoggio);
            Elaborazione.MediaQuadrata(uscita, piano, lm, am, raggio, appoggio);
            piani[c] = piano;
        }
        var scala = (leggero ? 0.375f : 0.75f) * forza;
        var dischi = rettangoli.Select(v =>
        {
            var lato = Math.Max(v.Larghezza, v.Altezza);
            return (Cx: v.CentroX, Cy: v.CentroY + v.Altezza * 0.04, R0: lato * 0.38, R1: lato * 0.72);
        }).ToList();
        Elaborazione.PerRighe(zy1 - zy0, (inizio, fine) =>
        {
            Span<float> sfocato = stackalloc float[3];
            for (var yy = inizio; yy < fine; yy++)
            {
                var y = zy0 + yy;
                var py = Math.Clamp((yy + 0.5f) / 2 - 0.5f, 0, am - 1);
                int y0 = (int)py, y1 = Math.Min(y0 + 1, am - 1);
                var wy = py - y0;
                var riga = y * immagine.Passo;
                for (var x = zx0; x < zx1; x++)
                {
                    // Il disco più forte tra quelli dei volti.
                    float disco = 0;
                    foreach (var d in dischi)
                    {
                        var dist = Math.Sqrt((x + 0.5 - d.Cx) * (x + 0.5 - d.Cx) + (y + 0.5 - d.Cy) * (y + 0.5 - d.Cy));
                        var v = dist <= d.R0 ? 1f : dist >= d.R1 ? 0f : (float)((d.R1 - dist) / (d.R1 - d.R0));
                        if (v > disco) disco = v;
                    }
                    if (disco <= 0) continue;
                    var px = Math.Clamp((x - zx0 + 0.5f) / 2 - 0.5f, 0, lm - 1);
                    int x0 = (int)px, x1 = Math.Min(x0 + 1, lm - 1);
                    var wx = px - x0;
                    var o = riga + x * 4;
                    float differenza = 0;
                    for (var c = 0; c < 3; c++)
                    {
                        var p = piani[c];
                        var sopra = p[y0 * lm + x0] + (p[y0 * lm + x1] - p[y0 * lm + x0]) * wx;
                        var sotto = p[y1 * lm + x0] + (p[y1 * lm + x1] - p[y1 * lm + x0]) * wx;
                        sfocato[c] = sopra + (sotto - sopra) * wy;
                        differenza += Math.Abs(immagine.Dati[o + c] - sfocato[c]) / 255f;
                    }
                    var m = disco * scala;
                    if (!leggero) m *= Math.Clamp(1 - SensibilitaBordi / 3 * differenza, 0, 1);
                    if (m <= 0.002f) continue;
                    for (var c = 0; c < 3; c++)
                        immagine.Dati[o + c] = (byte)(immagine.Dati[o + c] + (sfocato[c] - immagine.Dati[o + c]) * m + 0.5f);
                }
            }
        });
    }

    /// <summary>
    /// Un'ellisse morbida attorno al volto (già levigato), schiarita con la curva della luce; <paramref name="presenza"/>
    /// 0…1 per la dissolvenza.
    /// </summary>
    public static void LuceVolto(ImmagineBgra immagine, Rettangolo volto, double presenza, byte[] curva)
    {
        if (presenza <= 0.01) return;
        int l = immagine.Larghezza, a = immagine.Altezza;
        var cx = volto.CentroX;
        var cy = volto.CentroY + volto.Altezza * 0.08;
        var sx = volto.Larghezza * 1.0;
        var sy = volto.Altezza * 1.25;
        if (sx <= 0 || sy <= 0) return;
        int x0 = Math.Clamp((int)(cx - sx), 0, l), x1 = Math.Clamp((int)Math.Ceiling(cx + sx), 0, l);
        int y0 = Math.Clamp((int)(cy - sy), 0, a), y1 = Math.Clamp((int)Math.Ceiling(cy + sy), 0, a);
        if (x1 <= x0 || y1 <= y0) return;
        Elaborazione.PerRighe(y1 - y0, (inizio, fine) =>
        {
            for (var yy = inizio; yy < fine; yy++)
            {
                var y = y0 + yy;
                var dy = (y + 0.5 - cy) / sy;
                var o = y * immagine.Passo;
                for (var x = x0; x < x1; x++)
                {
                    var dx = (x + 0.5 - cx) / sx;
                    var d = Math.Sqrt(dx * dx + dy * dy);
                    if (d >= 1) continue;
                    var m = (float)((d <= 0.35 ? 1 : (1 - d) / 0.65) * presenza);
                    var p = o + x * 4;
                    for (var c = 0; c < 3; c++)
                    {
                        var v = immagine.Dati[p + c];
                        immagine.Dati[p + c] = (byte)(v + (curva[v] - v) * m + 0.5f);
                    }
                }
            }
        });
    }

    /// <summary>
    /// Nitidezza: positiva = maschera di contrasto sulla sola luminosità (niente aloni colorati); negativa = un velo
    /// morbido (sfocatura binomiale 3×3, circa un pixel). Valore −1…1. <paramref name="copia"/>: un buffer riusato.
    /// </summary>
    public static unsafe void Nitidezza(ImmagineBgra immagine, double valore, ref byte[] copia)
    {
        var v = (float)Math.Clamp(valore, -1, 1);
        if (Math.Abs(v) <= 0.005f) return;
        int l = immagine.Larghezza, a = immagine.Altezza;
        var passo = immagine.Passo;
        var n = l * a;
        if (v > 0)
        {
            // La luminosità in un piano a sé (riusa la copia), poi la differenza dalla sua versione sfocata.
            if (copia.Length < n) copia = new byte[n];
            var luma = copia;
            Elaborazione.PerRighe(a, (inizio, fine) =>
            {
                fixed (byte* s = immagine.Dati, y0 = luma)
                {
                    for (var y = inizio; y < fine; y++)
                    {
                        var p = s + y * passo;
                        var q = y0 + y * l;
                        for (var x = 0; x < l; x++, p += 4) q[x] = (byte)((19 * p[0] + 183 * p[1] + 54 * p[2] + 128) >> 8);
                    }
                }
            });
            var guadagno = (int)(v * 1.6f * 256);
            Elaborazione.PerRighe(a, (inizio, fine) =>
            {
                fixed (byte* s = immagine.Dati, y0 = luma)
                {
                    for (var y = inizio; y < fine; y++)
                    {
                        var su = y0 + Math.Max(y - 1, 0) * l;
                        var qui = y0 + y * l;
                        var giu = y0 + Math.Min(y + 1, a - 1) * l;
                        var p = s + y * passo;
                        for (var x = 0; x < l; x++, p += 4)
                        {
                            int xs = Math.Max(x - 1, 0), xd = Math.Min(x + 1, l - 1);
                            var sfocata = su[xs] + 2 * su[x] + su[xd] + 2 * qui[xs] + 4 * qui[x] + 2 * qui[xd] + giu[xs] + 2 * giu[x] + giu[xd];
                            var aggiunta = ((qui[x] << 4) - sfocata) * guadagno >> 12;
                            if (aggiunta == 0) continue;
                            p[0] = (byte)Math.Clamp(p[0] + aggiunta, 0, 255);
                            p[1] = (byte)Math.Clamp(p[1] + aggiunta, 0, 255);
                            p[2] = (byte)Math.Clamp(p[2] + aggiunta, 0, 255);
                        }
                    }
                }
            });
            return;
        }
        if (copia.Length < n * 4) copia = new byte[n * 4];
        var originale = copia;
        immagine.Dati.AsSpan(0, n * 4).CopyTo(originale);
        var peso = (int)(-v * 256);
        Elaborazione.PerRighe(a, (inizio, fine) =>
        {
            fixed (byte* d = immagine.Dati, o0 = originale)
            {
                for (var y = inizio; y < fine; y++)
                {
                    var su = o0 + Math.Max(y - 1, 0) * passo;
                    var qui = o0 + y * passo;
                    var giu = o0 + Math.Min(y + 1, a - 1) * passo;
                    var p = d + y * passo;
                    for (var x = 0; x < l; x++)
                    {
                        int xs = Math.Max(x - 1, 0) * 4, xc = x * 4, xd = Math.Min(x + 1, l - 1) * 4;
                        for (var c = 0; c < 3; c++)
                        {
                            var sfocata = (su[xs + c] + 2 * su[xc + c] + su[xd + c] + 2 * qui[xs + c] + 4 * qui[xc + c]
                                + 2 * qui[xd + c] + giu[xs + c] + 2 * giu[xc + c] + giu[xd + c] + 8) >> 4;
                            int o = qui[xc + c];
                            p[xc + c] = (byte)(o + (((sfocata - o) * peso + 128) >> 8));
                        }
                    }
                }
            }
        });
    }
}
