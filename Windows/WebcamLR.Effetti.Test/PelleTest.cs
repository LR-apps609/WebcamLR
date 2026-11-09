using Xunit;
using Xunit.Abstractions;

namespace WebcamLR.Effetti.Test;

/// <summary>
/// Qualità 11: il ritocco della pelle (filtro guidato sulla luma, peso del colore, grana fine, colore uniformato) e la
/// luce sul volto (guadagno sulla luma, senza bruciare né cambiare colore). Il banco con i volti sintetici è in
/// Strumenti/banco_pelle; qui le proprietà che non devono tornare indietro.
/// </summary>
public class PelleTest(ITestOutputHelper uscita)
{
    private const int L = 480, A = 360;
    private static readonly Rettangolo Volto = new(160, 80, 160, 200);

    /// <summary>
    /// Una pelle media con pori (rumore sfocato, circa ±3%) e grana fine (±3% pixel per pixel), dentro il rettangolo del
    /// volto; fuori una parete grigia con la stessa trama. Con <paramref name="riga"/> un tratto scuro orizzontale spesso 3 px (un «occhio») a quella y.
    /// </summary>
    private static ImmagineBgra Pelle(int seme, (byte R, byte G, byte B)? colore = null, int? riga = null)
    {
        var (r0, g0, b0) = colore ?? ((byte)199, (byte)140, (byte)110);
        var caso = new Random(seme);
        var rumore = new float[L * A];
        var grana = new float[L * A];
        for (var i = 0; i < rumore.Length; i++)
        {
            rumore[i] = (float)(caso.NextDouble() * 2 - 1);
            grana[i] = (float)(caso.NextDouble() * 2 - 1);
        }
        Elaborazione.Gaussiana(rumore, L, A, 1, 1.5, new float[L * A]);
        var im = new ImmagineBgra(L, A);
        for (var y = 0; y < A; y++)
            for (var x = 0; x < L; x++)
            {
                var i = y * L + x;
                var t = 1 + 0.25f * rumore[i] + 0.03f * grana[i];
                var dentro = x >= Volto.X && x < Volto.Destra && y >= Volto.Y && y < Volto.Basso;
                var (r, g, b) = dentro ? (r0 * t, g0 * t, b0 * t) : (120 * t, 124 * t, 130 * t);
                if (riga is int ry && dentro && Math.Abs(y - ry) <= 1 && x > Volto.X + 30 && x < Volto.Destra - 30) (r, g, b) = (40, 30, 28);
                im.Dati[i * 4] = (byte)Math.Clamp(b, 0, 255);
                im.Dati[i * 4 + 1] = (byte)Math.Clamp(g, 0, 255);
                im.Dati[i * 4 + 2] = (byte)Math.Clamp(r, 0, 255);
                im.Dati[i * 4 + 3] = 255;
            }
        return im;
    }

    private static float Luma(ImmagineBgra im, int x, int y)
    {
        var o = (y * L + x) * 4;
        return 0.2126f * im.Dati[o + 2] + 0.7152f * im.Dati[o + 1] + 0.0722f * im.Dati[o];
    }

    /// <summary>Deviazione standard della luma nel centro del volto, lontano dalla riga (se c'è).</summary>
    private static double Deviazione(ImmagineBgra im, Func<int, int, float>? f = null)
    {
        f ??= (x, y) => Luma(im, x, y);
        double s = 0, s2 = 0; var n = 0;
        for (var y = 140; y < 200; y++)
            for (var x = 200; x < 280; x++)
            {
                var v = f(x, y);
                s += v; s2 += v * v; n++;
            }
        var m = s / n;
        return Math.Sqrt(s2 / n - m * m);
    }

    /// <summary>La parte più fine: la luma meno la sua binomiale 3×3.</summary>
    private static float Fine(ImmagineBgra im, int x, int y) =>
        Luma(im, x, y) - (4 * Luma(im, x, y) + 2 * (Luma(im, x - 1, y) + Luma(im, x + 1, y) + Luma(im, x, y - 1) + Luma(im, x, y + 1))
            + Luma(im, x - 1, y - 1) + Luma(im, x + 1, y - 1) + Luma(im, x - 1, y + 1) + Luma(im, x + 1, y + 1)) / 16;

    [Theory]
    [InlineData(255, 224, 196)]   // molto chiara
    [InlineData(234, 192, 160)]   // chiara
    [InlineData(198, 140, 110)]   // media
    [InlineData(180, 130, 90)]    // olivastra
    [InlineData(141, 85, 60)]     // bruna
    [InlineData(92, 56, 40)]      // scura
    [InlineData(60, 40, 30)]      // molto scura
    public void TutteLePelliSonoPelle(int r, int g, int b) => Assert.True(RegolePelle.PesoColore(r, g, b) > 0.9f);

    [Theory]
    [InlineData(190, 90, 95, 0.15)]   // labbra
    [InlineData(235, 230, 225, 0)]    // bianco degli occhi
    [InlineData(30, 25, 22, 0)]       // capelli neri
    [InlineData(128, 128, 128, 0)]    // grigio
    [InlineData(60, 90, 160, 0)]      // blu
    [InlineData(60, 140, 70, 0)]      // verde
    public void LabbraOcchiECapelliNo(int r, int g, int b, double massimo) =>
        Assert.True(RegolePelle.PesoColore(r, g, b) <= massimo + 1e-6);

    [Fact]
    public void LevigaLaPelleSenzaCambiareIlColore()
    {
        var prima = Pelle(1);
        var dopo = prima.Copia();
        RicettePersona.Pelle(dopo, 1, [Volto], false);
        Assert.True(Deviazione(dopo) < 0.75 * Deviazione(prima), $"{Deviazione(prima):0.00} → {Deviazione(dopo):0.00}");
        // Il colore medio della pelle resta quello (al più un livello).
        for (var c = 0; c < 3; c++)
        {
            double sp = 0, sd = 0;
            for (var y = 140; y < 200; y++)
                for (var x = 200; x < 280; x++)
                {
                    sp += prima.Dati[(y * L + x) * 4 + c];
                    sd += dopo.Dati[(y * L + x) * 4 + c];
                }
            Assert.InRange((sd - sp) / (60 * 80), -1, 1);
        }
    }

    [Fact]
    public void NonEPlastica()
    {
        // Anche a forza piena la grana più fine resta per almeno un terzo (il ritorno della grana): niente pelle di plastica.
        var prima = Pelle(2);
        var dopo = prima.Copia();
        RicettePersona.Pelle(dopo, 1, [Volto], false);
        var rapporto = Deviazione(dopo, (x, y) => Fine(dopo, x, y)) / Deviazione(prima, (x, y) => Fine(prima, x, y));
        uscita.WriteLine($"grana: {rapporto:0.000}, deviazione {Deviazione(prima):0.00} → {Deviazione(dopo):0.00}");
        Assert.InRange(rapporto, 0.33, 0.95);
    }

    [Fact]
    public void IlBordoDiUnOcchioResta()
    {
        // Il tratto scuro: il salto di luma sopra e sotto resta (non si impasta).
        var prima = Pelle(3, riga: 170);
        var dopo = prima.Copia();
        RicettePersona.Pelle(dopo, 1, [Volto], false);
        double salto(ImmagineBgra im) => Enumerable.Range(200, 80).Average(x => Luma(im, x, 165) - Luma(im, x, 170));
        uscita.WriteLine($"salto: {salto(prima):0.0} → {salto(dopo):0.0}");
        Assert.True(salto(dopo) > 0.98 * salto(prima), $"{salto(prima):0.0} → {salto(dopo):0.0}");
        // Ai livelli leggeri anche.
        var leggero = prima.Copia();
        RicettePersona.Pelle(leggero, 1, [Volto], true);
        Assert.True(salto(leggero) > 0.93 * salto(prima), $"leggero {salto(prima):0.0} → {salto(leggero):0.0}");
    }

    [Fact]
    public void FuoriDallaPelleNienteCambia()
    {
        // Un volto blu (non è pelle): nessun punto cambia. E fuori dall'ellisse esterna, con la pelle vera, nemmeno.
        var blu = Pelle(4, ((byte)60, (byte)90, (byte)160));
        var copia = blu.Copia();
        RicettePersona.Pelle(copia, 1, [Volto], false);
        Assert.Equal(blu.Dati, copia.Dati);

        var pelle = Pelle(5);
        var dopo = pelle.Copia();
        RicettePersona.Pelle(dopo, 1, [Volto], false);
        double sx = Volto.Larghezza / 2 * RegolePelle.EllisseEsterna, sy = Volto.Altezza / 2 * RegolePelle.EllisseEsterna;
        double cx = Volto.CentroX, cy = Volto.CentroY + Volto.Altezza * 0.04;
        for (var y = 0; y < A; y++)
            for (var x = 0; x < L; x++)
            {
                var dx = (x + 0.5 - cx) / sx;
                var dy = (y + 0.5 - cy) / sy;
                if (dx * dx + dy * dy < 1.0) continue;
                for (var c = 0; c < 4; c++) Assert.Equal(pelle.Dati[(y * L + x) * 4 + c], dopo.Dati[(y * L + x) * 4 + c]);
            }
    }

    [Fact]
    public void LeZoneProtetteRestanoComeSono()
    {
        var prima = Pelle(6);
        var dopo = prima.Copia();
        var occhio = new Rettangolo(200, 130, 80, 40);
        RicettePersona.Pelle(dopo, 1, [Volto], false, [occhio]);
        // Dentro il 75% dell'ellisse: identico.
        for (var y = 130; y < 170; y++)
            for (var x = 200; x < 280; x++)
            {
                var dx = (x + 0.5 - occhio.CentroX) / 40;
                var dy = (y + 0.5 - occhio.CentroY) / 20;
                if (dx * dx + dy * dy > 0.7 * 0.7) continue;
                for (var c = 0; c < 3; c++) Assert.Equal(prima.Dati[(y * L + x) * 4 + c], dopo.Dati[(y * L + x) * 4 + c]);
            }
        // Altrove la pelle è levigata come senza zone.
        var senza = prima.Copia();
        RicettePersona.Pelle(senza, 1, [Volto], false);
        Assert.Equal(senza.Riga(220).ToArray(), dopo.Riga(220).ToArray());
    }

    [Fact]
    public void LeggeroLevigaMenoMaLeviga()
    {
        var prima = Pelle(7);
        var pieno = prima.Copia();
        var leggero = prima.Copia();
        RicettePersona.Pelle(pieno, 0.6, [Volto], false);
        RicettePersona.Pelle(leggero, 0.6, [Volto], true);
        var d0 = Deviazione(prima);
        Assert.True(Deviazione(leggero) < 0.92 * d0, $"{d0:0.00} → {Deviazione(leggero):0.00}");
        Assert.True(Deviazione(pieno) <= Deviazione(leggero) + 0.05);
    }

    [Fact]
    public void ForzaZeroNonTocca()
    {
        var prima = Pelle(8);
        var dopo = prima.Copia();
        RicettePersona.Pelle(dopo, 0, [Volto], false);
        RicettePersona.Pelle(dopo, double.NaN, [Volto], false);
        RicettePersona.Pelle(dopo, 1, [], false);
        Assert.Equal(prima.Dati, dopo.Dati);
    }

    [Fact]
    public void IlRossoreSiAttenua()
    {
        // Un brufolo rosso (raggio 5 px) sulla pelle liscia: il suo rosso relativo scende almeno di un terzo.
        var im = new ImmagineBgra(L, A);
        for (var i = 0; i < L * A; i++)
        {
            int x = i % L, y = i / L;
            var d = Math.Sqrt((x - 240) * (x - 240) + (y - 180) * (y - 180));
            var macchia = d < 5 ? 1.0 : 0;
            im.Dati[i * 4] = (byte)(110 * (1 - 0.15 * macchia));
            im.Dati[i * 4 + 1] = (byte)(140 * (1 - 0.13 * macchia));
            im.Dati[i * 4 + 2] = 199;
            im.Dati[i * 4 + 3] = 255;
        }
        var dopo = im.Copia();
        RicettePersona.Pelle(dopo, 1, [Volto], false);
        double rosso(ImmagineBgra x) => x.Dati[(180 * L + 240) * 4 + 2] - Luma(x, 240, 180);
        double fondo(ImmagineBgra x) => x.Dati[(150 * L + 240) * 4 + 2] - Luma(x, 240, 150);
        Assert.True(rosso(dopo) - fondo(dopo) < 0.67 * (rosso(im) - fondo(im)), $"{rosso(im) - fondo(im):0.0} → {rosso(dopo) - fondo(dopo):0.0}");
    }

    [Fact]
    public void LuceSchiarisceSenzaCambiareColoreNeBruciare()
    {
        var im = new ImmagineBgra(L, A);
        // A sinistra del centro una pelle media, a destra una pelle chiarissima quasi bianca (riflesso).
        for (var i = 0; i < L * A; i++)
        {
            var chiara = i % L >= 240;
            im.Dati[i * 4] = (byte)(chiara ? 236 : 110);
            im.Dati[i * 4 + 1] = (byte)(chiara ? 244 : 140);
            im.Dati[i * 4 + 2] = (byte)(chiara ? 252 : 199);
            im.Dati[i * 4 + 3] = 255;
        }
        var dopo = im.Copia();
        RicettePersona.LuceVolto(dopo, Volto, 1);
        var o = (180 * L + 236) * 4;
        Assert.True(dopo.Dati[o + 2] > 210, $"rosso {dopo.Dati[o + 2]}");
        // Stessi rapporti tra i canali (la tinta e la saturazione restano), entro l'arrotondamento.
        Assert.InRange(dopo.Dati[o + 2] / (double)dopo.Dati[o + 1], 199 / 140.0 - 0.015, 199 / 140.0 + 0.015);
        Assert.InRange(dopo.Dati[o + 1] / (double)dopo.Dati[o], 140 / 110.0 - 0.015, 140 / 110.0 + 0.015);
        // Il chiaro non arriva al bianco pieno.
        var c = (180 * L + 250) * 4;
        Assert.InRange(dopo.Dati[c + 2], 252, 253);
        Assert.True(dopo.Dati[c] > 236 && dopo.Dati[c + 1] > 244);
        // Fuori dall'ellisse (a sinistra, oltre 0,8 della larghezza del volto dal centro) niente.
        Assert.Equal(im.Riga(180)[..(100 * 4)].ToArray(), dopo.Riga(180)[..(100 * 4)].ToArray());
    }

    [Fact]
    public void TettoDellaLuce()
    {
        Assert.Equal(1f, RegolePelle.TettoLuce(254));
        Assert.Equal(1f, RegolePelle.TettoLuce(255));
        Assert.Equal(252f, 250 * RegolePelle.TettoLuce(250), 3);
        Assert.Equal(177f, 100 * RegolePelle.TettoLuce(100), 3);
        Assert.True(RegolePelle.GuadagniLuce[64] > 1.1f && RegolePelle.GuadagniLuce[250] < 1.01f);
    }
}
