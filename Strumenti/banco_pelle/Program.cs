// Qualità 11 · Il banco del ritocco della pelle e della luce sul volto. Numeri commentati: Documenti/Ritocco pelle - banco.md.
//
//   dotnet run -c Release --project Strumenti/banco_pelle                 (la libreria di questa copia)
//   dotnet run -c Release --project Strumenti/banco_pelle -p:Effetti=<altra copia>/Windows/WebcamLR.Effetti -p:Prima=true
//                                                       (una libreria di prima della Qualità 11)
//   ... -- --immagini <cartella>    (anche i ritagli del volto medio, prima e dopo, in PPM)
//
// Tre volti sintetici (Volto.cs: pelle chiara, media e scura), le ricette vere di WebcamLR.Effetti (RicettePersona.Pelle e,
// per la luce, il Compositore con la sua dissolvenza) e un modello in C# della ricetta del Mac di prima (Core Image qui non
// c'è). Misure sulla luma (Rec. 709, 0–255):
// - rugosità: scarto quadratico medio della luma dalla pelle pulita (senza macchie, pori e brufoli) nel nucleo della pelle;
// - rossori: lo stesso per Cr (BT.601, 0–255): i brufoli e le macchie rosse;
// - grana: deviazione della parte più fine (pixel − binomiale 3×3) nel nucleo, uscita / ingresso (0 = plastica);
// - bordi: gradiente medio (Sobel) uscita / ingresso sui bordi veri (dove il volto pulito ha un gradiente forte) di
//   occhi e sopracciglia, bocca, capelli e contorno del viso;
// - alone: differenza media (0–255, per canale) uscita − ingresso sullo sfondo da 6 a 30 px fuori dal viso;
// - colore: spostamento medio di Cb e Cr nel nucleo;
// - sfarfallio: differenza media tra fotogrammi successivi (30 fotogrammi) nel nucleo e sui bordi, con il rettangolo del
//   volto che trema (1,5% in posizione, 2% in misura, come la stima dalla maschera) e senza rumore: tutto quello che
//   cambia lo fa il ritocco; e con il rumore del sensore, accanto a quello dell'ingresso;
// - tempo: mediana di 30 chiamate a 1080p con un volto alto 405 px.

using System.Diagnostics;
using BancoPelle;
using WebcamLR.Effetti;

var volti = new[]
{
    new Volto("chiara", (0.92, 0.75, 0.63), 11),
    new Volto("media", (0.78, 0.55, 0.43), 12),
    new Volto("scura", (0.38, 0.24, 0.17), 13),
};
Console.WriteLine($"Banco pelle · {Volto.L}×{Volto.A}, volto {volti[0].Rettangolo.Larghezza:0}×{volti[0].Rettangolo.Altezza:0} px · processori {Environment.ProcessorCount}");
Console.WriteLine();

var varianti = new (string Nome, Action<ImmagineBgra, double, Rettangolo, Volto> Applica)[]
{
    ("Windows, pieno", (im, f, r, v) => RicettePersona.Pelle(im, f, [r], false)),
    ("Windows, leggero", (im, f, r, v) => RicettePersona.Pelle(im, f, [r], true)),
    ("Mac di prima (modello)", (im, f, r, v) => MacPrima.Pelle(im, f, r)),
#if PROTEZIONE
    ("Windows pieno + occhi e bocca protetti (come il Mac)", (im, f, r, v) => RicettePersona.Pelle(im, f, [r], false,
        v.Lineamenti.Select(z => new Rettangolo(z.Cx - z.Ax, z.Cy - z.Ay, 2 * z.Ax, 2 * z.Ay)).ToList())),
#endif
};

Console.WriteLine("| Variante | Forza | Rugosità (in → out) | Riduzione | Rossori (in → out) | Grana | Occhi | Bocca | Capelli | Contorno | Alone | ΔCb/ΔCr |");
Console.WriteLine("|---|---|---|---|---|---|---|---|---|---|---|---|");
var ingressi = volti.Select(v => v.ConRumore(1)).ToArray();
var cartellaImmagini = args.SkipWhile(a => a != "--immagini").Skip(1).FirstOrDefault();
if (cartellaImmagini is not null)
{
    Directory.CreateDirectory(cartellaImmagini);
    for (var k = 0; k < volti.Length; k++) Ppm(ingressi[k], volti[k], Path.Combine(cartellaImmagini, $"{volti[k].Nome}-ingresso.ppm"));
}
foreach (var forza in new[] { 0.5, 1.0 })
{
    foreach (var (nome, applica) in varianti)
    {
        var m = new Misure();
        var perTono = new List<string>();
        for (var k = 0; k < volti.Length; k++)
        {
            var v = volti[k];
            var uscita = ingressi[k].Copia();
            applica(uscita, forza, v.Rettangolo, v);
            if (cartellaImmagini is not null)
                Ppm(uscita, v, Path.Combine(cartellaImmagini, $"{v.Nome}-{string.Concat(nome.Where(char.IsLetterOrDigit))}-{forza * 10:0}.ppm"));
            var r = Misure.Una(v, ingressi[k], uscita);
            m.Somma(r);
            perTono.Add($"{v.Nome} {r.RugIn:0.00}→{r.RugOut:0.00}");
        }
        m.Media(volti.Length);
        Console.WriteLine($"| {nome} | {forza:0.0} | {m.RugIn:0.00} → {m.RugOut:0.00} | {100 * (1 - m.RugOut / m.RugIn):0}% | {m.RosIn:0.00} → {m.RosOut:0.00} | {m.Grana:0.00} | {m.Occhi:0.00} | {m.Bocca:0.00} | {m.Capelli:0.00} | {m.Contorno:0.00} | {m.Alone:0.00} | {m.Cb:+0.00;-0.00;0.00}/{m.Cr:+0.00;-0.00;0.00} |");
        Console.Error.WriteLine($"   {nome} {forza}: {string.Join(", ", perTono)}");
    }
}

Console.WriteLine();
Console.WriteLine("Sfarfallio (forza 0,5, volto medio, 30 fotogrammi): differenza media tra fotogrammi successivi, 0–255");
Console.WriteLine();
Console.WriteLine("| Variante | Solo il rettangolo che trema: pelle | bordi | Con il rumore: pelle (ingresso) | bordi (ingresso) |");
Console.WriteLine("|---|---|---|---|---|");
{
    var v = volti[1];
    foreach (var (nome, applica) in varianti)
    {
        var (fermaPelle, fermaBordi) = Sfarfallio(v, applica, false);
        var (pelle, bordi) = Sfarfallio(v, applica, true);
        var (pelleIn, bordiIn) = Sfarfallio(v, null, true);
        Console.WriteLine($"| {nome} | {fermaPelle:0.000} | {fermaBordi:0.000} | {pelle:0.00} ({pelleIn:0.00}) | {bordi:0.00} ({bordiIn:0.00}) |");
    }
}

Console.WriteLine();
Console.WriteLine("Luce sul volto (Compositore, 20 fotogrammi, presenza piena)");
Console.WriteLine();
Console.WriteLine("| Volto | ΔY pelle | Saturazione out/in | Tinta (°) | Riflessi: ΔY | Bruciati in più | Sfondo vicino ΔY |");
Console.WriteLine("|---|---|---|---|---|---|---|");
foreach (var v in volti)
{
    using var compositore = new Compositore();
    var uscita = new ImmagineBgra(Volto.L, Volto.A);
    var rett = v.Rettangolo;
    var norm = new Rettangolo(rett.X / Volto.L, rett.Y / Volto.A, rett.Larghezza / Volto.L, rett.Altezza / Volto.A);
    var imp = new ImpostazioniMotore { LuceVolto = true };
    var ist = new StatoEffettiComputer.Istantanea(imp, null, null, null);
    var ingresso = ingressi[Array.IndexOf(volti, v)];
    for (var i = 0; i < 20; i++)
        compositore.Rendi(new IngressoResa(ingresso, null, null, null, [norm], (ulong)i * 33_000, 1 / 30.0), ist, LivelloResa.Pieno, uscita);
    var l = Misure.Luce(v, ingresso, uscita);
    Console.WriteLine($"| {v.Nome} | {l.DeltaY:+0.0;-0.0} | {l.Saturazione:0.000} | {l.Tinta:+0.0;-0.0;0.0} | {l.Riflessi:+0.0;-0.0} | {l.Bruciati:0.00}% | {l.Sfondo:+0.0;-0.0} |");
}

Console.WriteLine();
Console.WriteLine("Tempo del ritocco (forza 0,6), mediana di 30 chiamate");
Console.WriteLine();
foreach (var (nome, applica) in varianti.Take(2))
{
    var v = volti[1];
    var lavoro = ingressi[1].Copia();
    var tempi = new List<double>();
    for (var i = 0; i < 40; i++)
    {
        ingressi[1].Dati.CopyTo(lavoro.Dati, 0);
        var o = Stopwatch.StartNew();
        applica(lavoro, 0.6, v.Rettangolo, v);
        if (i >= 10) tempi.Add(o.Elapsed.TotalMilliseconds);
    }
    tempi.Sort();
    Console.WriteLine($"- {nome}: {tempi[tempi.Count / 2]:0.00} ms");
}

static (double Pelle, double Bordi) Sfarfallio(Volto v, Action<ImmagineBgra, double, Rettangolo, Volto>? applica, bool rumore)
{
    var caso = new Random(7);
    float[]? prima = null;
    double sp = 0, sb = 0;
    var conti = 0;
    var rett = v.Rettangolo;
    for (var t = 0; t < 30; t++)
    {
        var im = rumore ? v.ConRumore(100 + t) : v.Senza.Copia();
        if (applica is not null)
        {
            var s = 1 + (caso.NextDouble() - 0.5) * 2 * 0.02 * 1.7;
            var dx = (caso.NextDouble() - 0.5) * 2 * 0.015 * 1.7 * rett.Larghezza;
            var dy = (caso.NextDouble() - 0.5) * 2 * 0.015 * 1.7 * rett.Altezza;
            var r = new Rettangolo(rett.CentroX + dx - rett.Larghezza * s / 2, rett.CentroY + dy - rett.Altezza * s / 2, rett.Larghezza * s, rett.Altezza * s);
            applica(im, 0.5, r, v);
        }
        var y = Misure.Luma(im);
        if (prima is not null)
        {
            double p = 0, b = 0; int np = 0, nb = 0;
            for (var i = 0; i < y.Length; i++)
            {
                var d = Math.Abs(y[i] - prima[i]);
                if (v.Nucleo[i]) { p += d; np++; }
                else if (v.Occhi[i] || v.Bocca[i] || v.Capelli[i] || v.Contorno[i]) { b += d; nb++; }
            }
            sp += p / np; sb += b / nb; conti++;
        }
        prima = y;
    }
    return (sp / conti, sb / conti);
}

/// <summary>Il ritaglio attorno al volto in PPM (si apre con quasi tutti i programmi di immagini).</summary>
static void Ppm(ImmagineBgra im, Volto v, string percorso)
{
    int x0 = (int)(v.Cx - 300), y0 = (int)(v.Cy - 320), l = 600, a = 640;
    using var f = File.Create(percorso);
    var testa = System.Text.Encoding.ASCII.GetBytes($"P6\n{l} {a}\n255\n");
    f.Write(testa);
    var riga = new byte[l * 3];
    for (var y = 0; y < a; y++)
    {
        for (var x = 0; x < l; x++)
        {
            var o = ((y0 + y) * im.Larghezza + x0 + x) * 4;
            riga[x * 3] = im.Dati[o + 2]; riga[x * 3 + 1] = im.Dati[o + 1]; riga[x * 3 + 2] = im.Dati[o];
        }
        f.Write(riga);
    }
}
