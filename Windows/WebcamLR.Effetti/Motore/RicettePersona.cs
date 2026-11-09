namespace WebcamLR.Effetti;

/// <summary>
/// Qualità 11: i numeri del ritocco della pelle e della luce sul volto, gli stessi del Mac (RicetteEffetti.pelle e
/// luceVolto in Mac/Sorgenti/RicetteEffetti.swift). Tecnica e misure del banco: Documenti/Ritocco pelle - banco.md.
/// </summary>
public static class RegolePelle
{
    /// <summary>Raggio delle medie del filtro guidato, in parte dell'altezza del volto: 2%, 8 px per un volto di 400 px.</summary>
    public const double RaggioVolto = 0.02;

    /// <summary>
    /// ε del filtro guidato sulla luma (sRGB, 0..1): (0,015 + 0,025 · forza)². Dove la luma varia meno di √ε attorno
    /// al punto (pori, macchie, brufoli: da 0,02 a 0,04) si leviga; dove varia di più (occhi, sopracciglia, capelli,
    /// labbra, contorno del viso: 0,1 e oltre) il filtro restituisce l'immagine com'è.
    /// </summary>
    public static float Epsilon(double forza)
    {
        var s = 0.015 + 0.025 * Math.Clamp(forza, 0, 1);
        return (float)(s * s);
    }

    /// <summary>
    /// Vicino a un bordo vero il ritocco si ferma del tutto: con la deviazione locale della luma da 0,04 a 0,08 (varianza
    /// da 0,0016 a 0,0064) il peso scende da 1 a 0 (smoothstep). Il filtro guidato da solo lascia un velo sui bordi
    /// medi (labbra, contorno del viso su un fondo color legno, frangia): qui si fermano, come con la maschera dei
    /// dettagli del Mac di prima. Pori e macchie (deviazione 0,02–0,035) restano sotto.
    /// </summary>
    public static float PesoBordo(float varianza) => 1 - Morbido((varianza - 0.0016f) / 0.0048f);

    /// <summary>
    /// Quanto il colore di ogni punto della pelle va verso quello medio della pelle attorno (rossori, macchie colorate),
    /// a luma ferma. La media è pesata con <see cref="PesoColore"/>: labbra, occhi e sfondo non la sporcano.
    /// </summary>
    public const float UniformaColore = 0.5f;

    /// <summary>Ai livelli leggeri (senza grana fine) il ritocco è più delicato: tre quarti della forza.</summary>
    public const float ForzaLeggero = 0.75f;

    /// <summary>Quanta grana fine (pixel meno la sua binomiale 3×3) torna sulla pelle levigata: senza, sembra plastica.</summary>
    public const float RitornoGrana = 0.35f;

    /// <summary>
    /// L'ellisse attorno a ogni volto, in parti dei semiassi del rettangolo (centro 4% più in basso): piena fino a 1,
    /// niente oltre 1,4. Prima era un disco largo quanto il lato più lungo: arrivava allo sfondo accanto alle guance.
    /// </summary>
    public const double EllisseInterna = 1.0, EllisseEsterna = 1.4;

    /// <summary>
    /// u e v: la crominanza (Cb, Cr di BT.601 in byte) ruotata verso la tinta della pelle, 130° nel piano Cb, Cr. Tutte
    /// le pelli, dalla più chiara alla più scura, stanno lì (cambia la quantità di colore, non la tinta); labbra a 106°,
    /// bianco degli occhi, capelli neri e grigi senza colore. Pesi su rosso, verde e blu in byte.
    /// </summary>
    public static readonly (float R, float G, float B) PesiU = (0.49148f, -0.10780f, -0.38368f);
    public static readonly (float R, float G, float B) PesiV = (-0.19213f, 0.52289f, -0.33076f);

    /// <summary>
    /// Quanto un colore (sRGB, byte) è pelle, 0…1: la tinta entro circa ±12° da quella della pelle (fino a ±24°,
    /// 0,45 · u − |v| in 4 byte) e almeno un po' di colore (u da 5 a 9 byte: il bianco degli occhi, i capelli neri e i
    /// grigi restano fuori).
    /// </summary>
    public static float PesoColore(float r, float g, float b)
    {
        var u = PesiU.R * r + PesiU.G * g + PesiU.B * b;
        var v = PesiV.R * r + PesiV.G * g + PesiV.B * b;
        return Math.Clamp((0.45f * u - Math.Abs(v)) / 4f, 0, 1) * Math.Clamp((u - 5f) / 4f, 0, 1);
    }

    /// <summary>
    /// Fuori dalle zone protette (occhi con le sopracciglia, bocca: ellissi inscritte nei rettangoli, dai punti del volto
    /// sul Mac) 1; dentro, fino a 0,75 del raggio, 0; in mezzo una rampa.
    /// </summary>
    public static float Protezione(double x, double y, IReadOnlyList<Rettangolo>? zone)
    {
        if (zone is null) return 1;
        var peso = 1.0;
        foreach (var z in zone)
        {
            if (z.Larghezza <= 0 || z.Altezza <= 0) continue;
            var dx = (x - z.CentroX) / (z.Larghezza / 2);
            var dy = (y - z.CentroY) / (z.Altezza / 2);
            var d = Math.Sqrt(dx * dx + dy * dy);
            peso = Math.Min(peso, Math.Clamp((d - 0.75) / 0.35, 0, 1));
        }
        return (float)peso;
    }

    /// <summary>
    /// La luce sul volto: il guadagno per la luma (sRGB, byte) che la porta sulla curva della luce (circa +0,4 EV su ombre
    /// e mezzitoni, il bianco al suo posto). Lo stesso guadagno su rosso, verde e blu: la tinta e la saturazione non
    /// cambiano (prima la curva andava canale per canale e spegneva le pelli chiare).
    /// </summary>
    public static readonly float[] GuadagniLuce = CalcolaGuadagniLuce();

    private static float[] CalcolaGuadagniLuce()
    {
        var curva = Colore.Curva([(0, 0), (0.25, 0.29), (0.5, 0.565), (0.75, 0.81), (1, 1)]);
        var guadagni = new float[256];
        for (var y = 0; y < 256; y++) guadagni[y] = y == 0 ? 1 : (float)(curva(y / 255.0) * 255 / y);
        return guadagni;
    }

    /// <summary>L'ellisse della luce: centro un po' sotto quello del volto, semiassi in parti del rettangolo del volto.</summary>
    public const double LuceCentro = 0.06, LuceLarghezza = 0.8, LuceAltezza = 1.0;

    /// <summary>
    /// Il guadagno più alto per un pixel con il canale più alto a <paramref name="massimo"/>: quel canale arriva al più
    /// a metà strada da 254 (250 → 252), quindi resta sotto il bianco pieno e il colore non cambia.
    /// </summary>
    public static float TettoLuce(int massimo) => massimo <= 0 || massimo >= 254 ? 1 : (massimo + (254 - massimo) * 0.5f) / massimo;

    /// <summary>Smoothstep 3t² − 2t³ di t limitato a 0…1.</summary>
    public static float Morbido(double t)
    {
        var s = (float)Math.Clamp(t, 0, 1);
        return s * s * (3 - 2 * s);
    }
}

/// <summary>
/// Ritocco della pelle, luce sul volto e nitidezza delle regolazioni, sul posto, in pixel BGRA sRGB. Pelle e luce
/// lavorano solo attorno ai volti.
/// </summary>
public static class RicettePersona
{
    /// <summary>I buffer del ritocco, riusati (uno per thread: la resa è uno solo).</summary>
    private sealed class LavagnaPelle
    {
        private readonly float[][] buffer = new float[15][];

        public float[] Prendi(int indice, int n) =>
            buffer[indice] is { } b && b.Length >= n ? b : buffer[indice] = new float[n];
    }

    [ThreadStatic] private static LavagnaPelle? lavagna;

    /// <summary>
    /// Qualità 11. Il ritocco della pelle, come il «beauty» delle app di webcam ma senza effetto plastica:
    /// <list type="number">
    /// <item>Un filtro guidato (He, Sun e Tang) della luma con sé stessa, che conserva i bordi: a = var / (var + ε),
    /// b = (1 − a) · media, poi media(a) · Y + media(b). Le medie su una griglia a metà (pieno) o a un quarto (leggero)
    /// della zona dei volti, con un raggio del 2% dell'altezza del volto; l'applicazione alla luma piena.</item>
    /// <item>Un ritorno della grana fine (<see cref="RegolePelle.RitornoGrana"/>) dove il filtro ha levigato.</item>
    /// <item>Solo sulla pelle: un peso dal colore (<see cref="RegolePelle.PesoColore"/>) che si spegne vicino ai bordi
    /// veri (<see cref="RegolePelle.PesoBordo"/>), un'ellisse attorno a ogni volto e, se ci sono, le zone protette (occhi e
    /// bocca dai punti del volto).</item>
    /// <item>La luma cambia con la stessa differenza su rosso, verde e blu; il colore va solo verso quello medio della
    /// pelle attorno (<see cref="RegolePelle.UniformaColore"/>: i rossori si attenuano, la tinta della pelle resta).</item>
    /// </list>
    /// </summary>
    /// <param name="volti">I rettangoli dei volti in pixel (origine in alto).</param>
    /// <param name="leggero">
    /// Livelli più bassi: la griglia a un quarto, niente ritorno della grana e tre quarti della forza (circa metà del tempo).
    /// </param>
    /// <param name="protette">Zone da non toccare (occhi, bocca), in pixel; null = nessuna.</param>
    public static void Pelle(ImmagineBgra immagine, double valore, IReadOnlyList<Rettangolo> volti, bool leggero,
        IReadOnlyList<Rettangolo>? protette = null)
    {
        var forza = (float)Math.Clamp(double.IsFinite(valore) ? valore : 0, 0, 1);
        int l = immagine.Larghezza, a = immagine.Altezza;
        var rettangoli = volti.Where(v => v.Altezza > 8 && v.Destra > 0 && v.Basso > 0 && v.X < l && v.Y < a).ToList();
        if (forza <= 0.001 || rettangoli.Count == 0) return;
        var eps = RegolePelle.Epsilon(forza);
        if (leggero) forza *= RegolePelle.ForzaLeggero;
        var altezzaMassima = rettangoli.Max(v => v.Altezza);
        var ellissi = rettangoli.Select(v => (Cx: v.CentroX, Cy: v.CentroY + v.Altezza * 0.04,
            Sx: v.Larghezza / 2 * RegolePelle.EllisseEsterna, Sy: v.Altezza / 2 * RegolePelle.EllisseEsterna)).ToArray();
        const double interna = RegolePelle.EllisseInterna / RegolePelle.EllisseEsterna;
        int zx0 = Math.Clamp((int)Math.Floor(ellissi.Min(e => e.Cx - e.Sx)), 0, l);
        int zx1 = Math.Clamp((int)Math.Ceiling(ellissi.Max(e => e.Cx + e.Sx)), 0, l);
        int zy0 = Math.Clamp((int)Math.Floor(ellissi.Min(e => e.Cy - e.Sy)), 0, a);
        int zy1 = Math.Clamp((int)Math.Ceiling(ellissi.Max(e => e.Cy + e.Sy)), 0, a);
        var f = leggero ? 4 : 2;
        int lm = (zx1 - zx0) / f, am = (zy1 - zy0) / f;
        if (lm < 4 || am < 4) return;
        var n = lm * am;
        var lav = lavagna ??= new LavagnaPelle();
        float[] luma = lav.Prendi(0, n), quadrati = lav.Prendi(1, n), colore = lav.Prendi(2, n), media = lav.Prendi(3, n),
            mediaQuadrati = lav.Prendi(4, n), coefA = lav.Prendi(5, n), coefB = lav.Prendi(6, n), appoggio = lav.Prendi(7, n),
            pesoPuro = lav.Prendi(9, n), rossoPesato = lav.Prendi(10, n), bluPesato = lav.Prendi(11, n),
            mediaPeso = lav.Prendi(12, n), mediaRosso = lav.Prendi(13, n), mediaBlu = lav.Prendi(14, n);
        var dati = immagine.Dati;
        var passo = immagine.Passo;

        // 1. La griglia: media di f×f pixel, la sua luma (0..1), il quadrato, il peso del colore e la crominanza (rosso e blu
        // meno la luma) pesata con il colore.
        Elaborazione.PerRighe(am, (inizio, fine) =>
        {
            var inverso = 1f / (f * f);
            for (var y = inizio; y < fine; y++)
            {
                for (var x = 0; x < lm; x++)
                {
                    float r = 0, g = 0, b = 0;
                    for (var dy = 0; dy < f; dy++)
                    {
                        var o = (zy0 + y * f + dy) * passo + (zx0 + x * f) * 4;
                        for (var dx = 0; dx < f; dx++, o += 4)
                        {
                            b += dati[o];
                            g += dati[o + 1];
                            r += dati[o + 2];
                        }
                    }
                    r *= inverso; g *= inverso; b *= inverso;
                    var i = y * lm + x;
                    var yy = (0.2126f * r + 0.7152f * g + 0.0722f * b) / 255f;
                    luma[i] = yy;
                    quadrati[i] = yy * yy;
                    var peso = RegolePelle.PesoColore(r, g, b);
                    colore[i] = pesoPuro[i] = peso;
                    rossoPesato[i] = peso * (r / 255f - yy);
                    bluPesato[i] = peso * (b / 255f - yy);
                }
            }
        });

        // 2. Il filtro guidato della luma con sé stessa; il peso della pelle (colore, lontano dai bordi) appena
        // ammorbidito (niente puntini).
        var raggio = Math.Max(1, (int)Math.Round(altezzaMassima * RegolePelle.RaggioVolto / f));
        Elaborazione.MediaQuadrata(luma, media, lm, am, raggio, appoggio);
        Elaborazione.MediaQuadrata(quadrati, mediaQuadrati, lm, am, raggio, appoggio);
        for (var i = 0; i < n; i++)
        {
            var varianza = Math.Max(mediaQuadrati[i] - media[i] * media[i], 0);
            var ai = varianza / (varianza + eps);
            coefA[i] = ai;
            coefB[i] = (1 - ai) * media[i];
            colore[i] *= RegolePelle.PesoBordo(varianza);
        }
        float[] mediaA = media, mediaB = mediaQuadrati, pelle = quadrati;
        Elaborazione.MediaQuadrata(coefA, mediaA, lm, am, raggio, appoggio);
        Elaborazione.MediaQuadrata(coefB, mediaB, lm, am, raggio, appoggio);
        Elaborazione.MediaQuadrata(colore, pelle, lm, am, 1, appoggio);
        // Il colore medio della sola pelle attorno (media pesata: labbra, occhi e sfondo non entrano), su un raggio doppio.
        Elaborazione.MediaQuadrata(pesoPuro, mediaPeso, lm, am, 2 * raggio, appoggio);
        Elaborazione.MediaQuadrata(rossoPesato, mediaRosso, lm, am, 2 * raggio, appoggio);
        Elaborazione.MediaQuadrata(bluPesato, mediaBlu, lm, am, 2 * raggio, appoggio);
        for (var i = 0; i < n; i++)
        {
            var inverso = 1 / Math.Max(mediaPeso[i], 0.05f);
            mediaRosso[i] *= inverso;
            mediaBlu[i] *= inverso;
        }

        // 3. La luma piena della zona (per la grana fine), poi il ritocco pixel per pixel.
        int zl = zx1 - zx0, za = zy1 - zy0;
        var lumaPiena = leggero ? null : lav.Prendi(8, zl * za);
        if (lumaPiena is not null)
        {
            Elaborazione.PerRighe(za, (inizio, fine) =>
            {
                for (var yy = inizio; yy < fine; yy++)
                {
                    var o = (zy0 + yy) * passo + zx0 * 4;
                    var q = yy * zl;
                    for (var xx = 0; xx < zl; xx++, o += 4)
                        lumaPiena[q + xx] = (0.2126f * dati[o + 2] + 0.7152f * dati[o + 1] + 0.0722f * dati[o]) / 255f;
                }
            });
        }
        Elaborazione.PerRighe(za, (inizio, fine) =>
        {
            for (var yy = inizio; yy < fine; yy++)
            {
                var y = zy0 + yy;
                var py = Math.Clamp((yy + 0.5f) / f - 0.5f, 0, am - 1);
                int y0 = (int)py, y1 = Math.Min(y0 + 1, am - 1);
                var wy = py - y0;
                var riga = y * passo;
                for (var xx = 0; xx < zl; xx++)
                {
                    var x = zx0 + xx;
                    // L'ellisse più forte tra quelle dei volti (distanza normalizzata a quella esterna).
                    float disco = 0;
                    foreach (var e in ellissi)
                    {
                        var dx = (x + 0.5 - e.Cx) / e.Sx;
                        var dy = (y + 0.5 - e.Cy) / e.Sy;
                        var dist = Math.Sqrt(dx * dx + dy * dy);
                        var v = dist <= interna ? 1f : dist >= 1 ? 0f : (float)((1 - dist) / (1 - interna));
                        if (v > disco) disco = v;
                    }
                    if (disco <= 0) continue;
                    var px = Math.Clamp((xx + 0.5f) / f - 0.5f, 0, lm - 1);
                    int x0 = (int)px, x1 = Math.Min(x0 + 1, lm - 1);
                    var wx = px - x0;
                    var peso = forza * disco * Bilineare(pelle, lm, x0, x1, y0, y1, wx, wy);
                    if (peso <= 0.002f) continue;
                    if (protette is not null) peso *= RegolePelle.Protezione(x + 0.5, y + 0.5, protette);
                    if (peso <= 0.002f) continue;
                    var o = riga + x * 4;
                    var ma = Bilineare(mediaA, lm, x0, x1, y0, y1, wx, wy);
                    var mb = Bilineare(mediaB, lm, x0, x1, y0, y1, wx, wy);
                    float lumaQui, differenza;
                    if (lumaPiena is not null)
                    {
                        var q = yy * zl + xx;
                        lumaQui = lumaPiena[q];
                        differenza = ma * lumaQui + mb - lumaQui;
                        if (xx > 0 && xx < zl - 1 && yy > 0 && yy < za - 1)
                        {
                            var binomiale = (4 * lumaQui + 2 * (lumaPiena[q - 1] + lumaPiena[q + 1] + lumaPiena[q - zl] + lumaPiena[q + zl])
                                + lumaPiena[q - zl - 1] + lumaPiena[q - zl + 1] + lumaPiena[q + zl - 1] + lumaPiena[q + zl + 1]) / 16;
                            differenza += RegolePelle.RitornoGrana * (1 - ma) * (lumaQui - binomiale);
                        }
                    }
                    else
                    {
                        lumaQui = (0.2126f * dati[o + 2] + 0.7152f * dati[o + 1] + 0.0722f * dati[o]) / 255f;
                        differenza = ma * lumaQui + mb - lumaQui;
                    }
                    var aggiunta = differenza * peso * 255f;
                    // Il colore verso quello medio della pelle attorno (rossori), a luma ferma.
                    int bq = dati[o], gq = dati[o + 1], rq = dati[o + 2];
                    var luma255 = 0.2126f * rq + 0.7152f * gq + 0.0722f * bq;
                    var uniforma = RegolePelle.UniformaColore * peso;
                    var dr = (Bilineare(mediaRosso, lm, x0, x1, y0, y1, wx, wy) * 255f - (rq - luma255)) * uniforma;
                    var db = (Bilineare(mediaBlu, lm, x0, x1, y0, y1, wx, wy) * 255f - (bq - luma255)) * uniforma;
                    var dg = -(0.2126f * dr + 0.0722f * db) / 0.7152f;
                    dati[o] = (byte)Math.Clamp((int)MathF.Round(bq + aggiunta + db), 0, 255);
                    dati[o + 1] = (byte)Math.Clamp((int)MathF.Round(gq + aggiunta + dg), 0, 255);
                    dati[o + 2] = (byte)Math.Clamp((int)MathF.Round(rq + aggiunta + dr), 0, 255);
                }
            }
        });
    }

    private static float Bilineare(float[] p, int larghezza, int x0, int x1, int y0, int y1, float wx, float wy)
    {
        var sopra = p[y0 * larghezza + x0] + (p[y0 * larghezza + x1] - p[y0 * larghezza + x0]) * wx;
        var sotto = p[y1 * larghezza + x0] + (p[y1 * larghezza + x1] - p[y1 * larghezza + x0]) * wx;
        return sopra + (sotto - sopra) * wy;
    }

    /// <summary>
    /// Qualità 11: un'ellisse morbida attorno al volto (smoothstep dal 30% del raggio al bordo) schiarita con la curva
    /// della luce applicata alla luma (<see cref="RegolePelle.GuadagniLuce"/>): lo stesso guadagno sui tre canali, con
    /// il canale più alto che si prende al massimo metà dello spazio rimasto fino a 254 (<see cref="RegolePelle.TettoLuce"/>:
    /// niente chiari bruciati, niente colore cambiato).
    /// <paramref name="presenza"/> 0…1 per la dissolvenza.
    /// </summary>
    public static void LuceVolto(ImmagineBgra immagine, Rettangolo volto, double presenza)
    {
        if (presenza <= 0.01) return;
        int l = immagine.Larghezza, a = immagine.Altezza;
        var cx = volto.CentroX;
        var cy = volto.CentroY + volto.Altezza * RegolePelle.LuceCentro;
        var sx = volto.Larghezza * RegolePelle.LuceLarghezza;
        var sy = volto.Altezza * RegolePelle.LuceAltezza;
        if (sx <= 0 || sy <= 0) return;
        int x0 = Math.Clamp((int)(cx - sx), 0, l), x1 = Math.Clamp((int)Math.Ceiling(cx + sx), 0, l);
        int y0 = Math.Clamp((int)(cy - sy), 0, a), y1 = Math.Clamp((int)Math.Ceiling(cy + sy), 0, a);
        if (x1 <= x0 || y1 <= y0) return;
        var guadagni = RegolePelle.GuadagniLuce;
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
                    var m = RegolePelle.Morbido((1 - d) / 0.7) * (float)presenza;
                    var p = o + x * 4;
                    int b = immagine.Dati[p], g = immagine.Dati[p + 1], r = immagine.Dati[p + 2];
                    var massimo = Math.Max(r, Math.Max(g, b));
                    if (massimo == 0) continue;
                    var y8 = (54 * r + 183 * g + 19 * b + 128) >> 8;
                    var guadagno = Math.Min(guadagni[y8], RegolePelle.TettoLuce(massimo));
                    var fattore = 1 + (guadagno - 1) * m;
                    immagine.Dati[p] = (byte)Math.Min(255, (int)(b * fattore + 0.5f));
                    immagine.Dati[p + 1] = (byte)Math.Min(255, (int)(g * fattore + 0.5f));
                    immagine.Dati[p + 2] = (byte)Math.Min(255, (int)(r * fattore + 0.5f));
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
