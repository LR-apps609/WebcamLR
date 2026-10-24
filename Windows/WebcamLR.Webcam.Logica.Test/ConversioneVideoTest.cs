using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

public class InquadratureTest
{
    [Fact]
    public void StesseProporzioniUsaTutto()
    {
        var (sorgente, destinazione) = Inquadrature.Calcola(1280, 720, 1920, 1080, Inquadratura.Adatta);
        Assert.Equal(Riquadro.Intero(1280, 720), sorgente);
        Assert.Equal(Riquadro.Intero(1920, 1080), destinazione);
        (sorgente, destinazione) = Inquadrature.Calcola(3840, 2160, 1280, 720, Inquadratura.Riempi);
        Assert.Equal(Riquadro.Intero(3840, 2160), sorgente);
        Assert.Equal(Riquadro.Intero(1280, 720), destinazione);
    }

    [Fact]
    public void VerticaleAdattaHaLeBandeNereAiLati()
    {
        var (sorgente, destinazione) = Inquadrature.Calcola(1080, 1920, 1920, 1080, Inquadratura.Adatta);
        Assert.Equal(Riquadro.Intero(1080, 1920), sorgente);
        // 1080 × 1080/1920 = 607,5 → 608 (pari), al centro.
        Assert.Equal(new Riquadro(656, 0, 608, 1080), destinazione);
    }

    [Fact]
    public void VerticaleRiempiTieneLaFasciaCentrale()
    {
        var (sorgente, destinazione) = Inquadrature.Calcola(1080, 1920, 1920, 1080, Inquadratura.Riempi);
        Assert.Equal(Riquadro.Intero(1920, 1080), destinazione);
        Assert.Equal(new Riquadro(0, 656, 1080, 608), sorgente);
    }

    [Fact]
    public void QuattroTerziAdattaHaLeBandeAiLati()
    {
        var (_, destinazione) = Inquadrature.Calcola(1440, 1080, 1280, 720, Inquadratura.Adatta);
        Assert.Equal(new Riquadro(160, 0, 960, 720), destinazione);
    }

    [Fact]
    public void RiquadriSemprePariPerNv12()
    {
        foreach (var (l, a) in new[] { (1080, 1920), (1920, 1440), (1366, 768), (720, 1280), (1170, 2532), (3024, 4032) })
        {
            foreach (var formato in FormatiWebcam.Tutti)
            {
                var (_, d) = Inquadrature.Calcola(l, a, formato.Larghezza, formato.Altezza, Inquadratura.Adatta);
                Assert.Equal(0, (d.X | d.Y | d.Larghezza | d.Altezza) & 1);
                Assert.True(d.X + d.Larghezza <= formato.Larghezza && d.Y + d.Altezza <= formato.Altezza);
            }
        }
    }

    [Fact]
    public void IntermediaAdattaEsattamenteLaParteVisibile()
    {
        Assert.Equal((1920, 1080), Inquadrature.DimensioneIntermedia(3840, 2160, 1920, 1080, Inquadratura.Adatta));
        Assert.Equal((608, 1080), Inquadrature.DimensioneIntermedia(1080, 1920, 1920, 1080, Inquadratura.Adatta));
        Assert.Equal((1280, 720), Inquadrature.DimensioneIntermedia(1920, 1080, 1280, 720, Inquadratura.Adatta));
    }

    [Fact]
    public void IntermediaRiempiPoiPassaPixelPerPixel()
    {
        var (l, a) = Inquadrature.DimensioneIntermedia(1440, 1080, 1280, 720, Inquadratura.Riempi);
        Assert.Equal((1280, 960), (l, a));
        var (sorgente, destinazione) = Inquadrature.Calcola(l, a, 1280, 720, Inquadratura.Riempi);
        Assert.Equal(destinazione.Larghezza, sorgente.Larghezza);
        Assert.Equal(destinazione.Altezza, sorgente.Altezza);
    }

    [Fact]
    public void IntermediaRiempiVerticaleNonDiventaEnorme()
    {
        var (l, a) = Inquadrature.DimensioneIntermedia(2160, 3840, 1920, 1080, Inquadratura.Riempi);
        Assert.True((long)l * a <= 2L * 1920 * 1080 + 4 * 3840);
        Assert.Equal(0, (l | a) & 1);
    }
}

public class ConversioneVideoTest
{
    [Theory]
    [InlineData(0, 0, 0, 16, 128, 128)]
    [InlineData(255, 255, 255, 235, 128, 128)]
    [InlineData(128, 128, 128, 126, 128, 128)]
    public void ColoriNeutri(int r, int g, int b, int y, int cb, int cr)
    {
        Assert.Equal(y, ConversioneVideo.Luminanza(r, g, b));
        Assert.Equal(cb, ConversioneVideo.Cb(r, g, b));
        Assert.Equal(cr, ConversioneVideo.Cr(r, g, b));
    }

    [Fact]
    public void RossoPuroBT709()
    {
        // BT.709 a gamma ridotta: Y = 16 + 0,1826·255 ≈ 63, Cr = 128 + 0,4392·255 ≈ 240.
        Assert.InRange(ConversioneVideo.Luminanza(255, 0, 0), 62, 64);
        Assert.InRange(ConversioneVideo.Cr(255, 0, 0), 239, 241);
        Assert.InRange(ConversioneVideo.Cb(255, 0, 0), 101, 103);
    }

    [Fact]
    public void PixelPerPixelConVerde()
    {
        const int l = 8, a = 4;
        var bgra = Tinta(l, a, 0, 255, 0);
        var nv12 = new byte[l * a * 3 / 2];
        ConversioneVideo.BgraInNv12(bgra, l, a, l * 4, Riquadro.Intero(l, a), nv12, l, a, Riquadro.Intero(l, a), false);
        var y = ConversioneVideo.Luminanza(0, 255, 0);
        Assert.All(nv12[..(l * a)], v => Assert.Equal(y, v));
        for (var i = l * a; i < nv12.Length; i += 2)
        {
            Assert.Equal(ConversioneVideo.Cb(0, 255, 0), nv12[i]);
            Assert.Equal(ConversioneVideo.Cr(0, 255, 0), nv12[i + 1]);
        }
    }

    [Fact]
    public void BandeNereFuoriDallaDestinazione()
    {
        const int l = 16, a = 8;
        var bgra = Tinta(4, 8, 255, 255, 255);
        var nv12 = new byte[l * a * 3 / 2];
        var destinazione = new Riquadro(6, 0, 4, 8);
        ConversioneVideo.BgraInNv12(bgra, 4, 8, 16, Riquadro.Intero(4, 8), nv12, l, a, destinazione, false);
        for (var riga = 0; riga < a; riga++)
        {
            for (var colonna = 0; colonna < l; colonna++)
            {
                var dentro = colonna >= 6 && colonna < 10;
                Assert.Equal(dentro ? 235 : 16, nv12[riga * l + colonna]);
            }
        }
        Assert.All(nv12[(l * a)..], v => Assert.Equal(128, v));
    }

    [Fact]
    public void SpecchiaRovesciaLeColonne()
    {
        const int l = 4, a = 2;
        // Colonna 0 bianca, le altre nere.
        var bgra = Tinta(l, a, 0, 0, 0);
        for (var riga = 0; riga < a; riga++) bgra[riga * l * 4] = bgra[riga * l * 4 + 1] = bgra[riga * l * 4 + 2] = 255;
        var dritto = new byte[l * a * 3 / 2];
        var specchiato = new byte[l * a * 3 / 2];
        ConversioneVideo.BgraInNv12(bgra, l, a, l * 4, Riquadro.Intero(l, a), dritto, l, a, Riquadro.Intero(l, a), false);
        ConversioneVideo.BgraInNv12(bgra, l, a, l * 4, Riquadro.Intero(l, a), specchiato, l, a, Riquadro.Intero(l, a), true);
        Assert.Equal(235, dritto[0]);
        Assert.Equal(16, dritto[3]);
        Assert.Equal(16, specchiato[0]);
        Assert.Equal(235, specchiato[3]);
    }

    [Fact]
    public void RispettaIlPassoDelleRighe()
    {
        const int l = 4, a = 2, passo = 32;
        var bgra = new byte[passo * a];
        Array.Fill(bgra, (byte)200); // il margine a destra di ogni riga non si deve vedere
        for (var riga = 0; riga < a; riga++) Array.Clear(bgra, riga * passo, l * 4);
        var nv12 = new byte[l * a * 3 / 2];
        ConversioneVideo.BgraInNv12(bgra, l, a, passo, Riquadro.Intero(l, a), nv12, l, a, Riquadro.Intero(l, a), false);
        Assert.All(nv12[..(l * a)], v => Assert.Equal(16, v));
    }

    [Fact]
    public void ScalaConMezzaImmagineBianca()
    {
        // Metà sinistra bianca, metà destra nera, raddoppiata: la metà resta al suo posto.
        const int l = 8, a = 4;
        var bgra = Tinta(l, a, 0, 0, 0);
        for (var riga = 0; riga < a; riga++)
            for (var colonna = 0; colonna < l / 2; colonna++)
                bgra[(riga * l + colonna) * 4] = bgra[(riga * l + colonna) * 4 + 1] = bgra[(riga * l + colonna) * 4 + 2] = 255;
        var nv12 = new byte[16 * 8 * 3 / 2];
        ConversioneVideo.BgraInNv12(bgra, l, a, l * 4, Riquadro.Intero(l, a), nv12, 16, 8, Riquadro.Intero(16, 8), false);
        Assert.Equal(235, nv12[0]);
        Assert.Equal(235, nv12[5]);
        Assert.Equal(16, nv12[10]);
        Assert.Equal(16, nv12[15]);
    }

    [Fact]
    public void ConversioneGrandeInParallelo()
    {
        const int l = 1920, a = 1080;
        var bgra = Tinta(l, a, 108, 188, 196); // il ciano di WebcamLR
        var nv12 = new byte[FormatoWebcam.DimensioneNv12(l, a)];
        ConversioneVideo.BgraInNv12(bgra, l, a, l * 4, Riquadro.Intero(l, a), nv12, l, a, Riquadro.Intero(l, a), false);
        var y = ConversioneVideo.Luminanza(108, 188, 196);
        Assert.True(nv12.AsSpan(0, l * a).IndexOfAnyExcept(y) < 0);
    }

    [Fact]
    public void RiquadroDispariRifiutato()
    {
        var bgra = new byte[16 * 4];
        var nv12 = new byte[8 * 4 * 3 / 2];
        Assert.Throws<ArgumentException>(() =>
            ConversioneVideo.BgraInNv12(bgra, 4, 4, 16, Riquadro.Intero(4, 4), nv12, 8, 4, new Riquadro(1, 0, 4, 4), false));
    }

    [Fact]
    public void ScalaNv12UgualeCopia()
    {
        var sorgente = new byte[FormatoWebcam.DimensioneNv12(64, 36)];
        new Random(3).NextBytes(sorgente);
        var destinazione = new byte[sorgente.Length];
        ConversioneVideo.ScalaNv12(sorgente, 64, 36, destinazione, 64, 36);
        Assert.Equal(sorgente, destinazione);
    }

    [Fact]
    public void ScalaNv12TinteUnite()
    {
        var sorgente = new byte[FormatoWebcam.DimensioneNv12(1920, 1080)];
        sorgente.AsSpan(0, 1920 * 1080).Fill(200);
        for (var i = 1920 * 1080; i < sorgente.Length; i += 2) { sorgente[i] = 90; sorgente[i + 1] = 170; }
        var destinazione = new byte[FormatoWebcam.DimensioneNv12(1280, 720)];
        ConversioneVideo.ScalaNv12(sorgente, 1920, 1080, destinazione, 1280, 720);
        Assert.True(destinazione.AsSpan(0, 1280 * 720).IndexOfAnyExcept((byte)200) < 0);
        for (var i = 1280 * 720; i < destinazione.Length; i += 2)
        {
            Assert.Equal(90, destinazione[i]);
            Assert.Equal(170, destinazione[i + 1]);
        }
    }

    [Fact]
    public void ScalaNv12QuattroTerziConBande()
    {
        var sorgente = new byte[FormatoWebcam.DimensioneNv12(640, 480)];
        sorgente.AsSpan(0, 640 * 480).Fill(235);
        sorgente.AsSpan(640 * 480).Fill(128);
        var destinazione = new byte[FormatoWebcam.DimensioneNv12(1280, 720)];
        ConversioneVideo.ScalaNv12(sorgente, 640, 480, destinazione, 1280, 720);
        Assert.Equal(16, destinazione[0]);            // banda a sinistra
        Assert.Equal(235, destinazione[640]);         // centro
        Assert.Equal(16, destinazione[1279]);         // banda a destra
    }

    [Fact]
    public void RiempiNero()
    {
        var nv12 = new byte[FormatoWebcam.DimensioneNv12(4, 2)];
        ConversioneVideo.RiempiNero(nv12, 4, 2);
        Assert.Equal(new byte[] { 16, 16, 16, 16, 16, 16, 16, 16, 128, 128, 128, 128 }, nv12);
    }

    internal static byte[] Tinta(int l, int a, byte r, byte g, byte b)
    {
        var bgra = new byte[l * a * 4];
        for (var i = 0; i < bgra.Length; i += 4) { bgra[i] = b; bgra[i + 1] = g; bgra[i + 2] = r; bgra[i + 3] = 255; }
        return bgra;
    }
}
