using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

/// <summary>Qualità 16: webcam oltre 1080p30, con il video del telefono scalato una volta sola.</summary>
public class ScalaUnaVoltaTest
{
    private static readonly FormatoWebcam QuattroK = new(3840, 2160, 30);
    private static readonly FormatoWebcam FullHd60 = new(1920, 1080, 60);
    private static readonly FormatoWebcam Hd = new(1280, 720, 30);

    [Fact]
    public void LaWebcamOffre1080p60E4K30ancheSuWindows10()
    {
        Assert.Contains(FullHd60, FormatiWebcam.Tutti);
        Assert.Contains(QuattroK, FormatiWebcam.Tutti);
        Assert.Contains(new FormatoWebcam(1280, 720, 60), FormatiWebcam.Tutti);
        Assert.Contains(FormatiDirectShow.Tutti, f => f is { Larghezza: 1920, Altezza: 1080, Fps: 60 });
        Assert.Contains(FormatiDirectShow.Tutti, f => f is { Larghezza: 3840, Altezza: 2160, Fps: 30 });
        // I primi restano quelli di sempre: le app che prendono il primo formato adatto non cambiano scelta.
        Assert.Equal(new FormatoWebcam(1920, 1080, 30), FormatiWebcam.Predefinito);
        Assert.Equal(new FormatoDirectShow(1280, 720, 30, CodificaDirectShow.Yuy2), FormatiDirectShow.Predefinito);
        Assert.Equal(QuattroK, FormatiWebcam.Tutti[^1]);
    }

    [Fact]
    public void SenzaWebcamComePrima()
    {
        // Fino al 1080p la misura del video, oltre ridotta: anteprima, foto e registrazione non cambiano.
        Assert.Equal((1920, 1080), ScalaUnaVolta.MisuraLavoro(1920, 1080, null, Inquadratura.Adatta));
        Assert.Equal((1920, 1080), ScalaUnaVolta.MisuraLavoro(3840, 2160, null, Inquadratura.Adatta));
        Assert.Equal((1080, 1920), ScalaUnaVolta.MisuraLavoro(2160, 3840, null, Inquadratura.Adatta));
        Assert.Equal((1280, 720), ScalaUnaVolta.MisuraLavoro(1280, 720, null, Inquadratura.Adatta));
    }

    [Fact]
    public void QuattroKdelTelefonoArrivaInteroAunAppIn4K()
    {
        // Prima il motore lo portava a 1080p e la webcam lo ingrandiva di nuovo: due scalature e niente 4K vero.
        var lavoro = ScalaUnaVolta.MisuraLavoro(3840, 2160, QuattroK, Inquadratura.Adatta);
        Assert.Equal((3840, 2160), lavoro);
        Assert.Equal(0, ScalaUnaVolta.Scalature(3840, 2160, lavoro, QuattroK, Inquadratura.Adatta));
        Assert.Equal(2, ScalaUnaVolta.Scalature(3840, 2160, ScalaUnaVolta.SenzaWebcam(3840, 2160), QuattroK, Inquadratura.Adatta));
    }

    [Theory]
    // Il telefono manda di più: si riduce una volta, nella copia dalla scheda video, e la conversione passa pixel per pixel.
    [InlineData(3840, 2160, 1280, 720, 1280, 720)]
    [InlineData(3840, 2160, 1920, 1080, 1920, 1080)]
    [InlineData(1920, 1080, 1280, 720, 1280, 720)]
    [InlineData(1920, 1080, 640, 360, 640, 360)]
    // Verticale in una webcam 16:9 (Adatta): la fascia alta quanto la webcam, con le bande.
    [InlineData(1080, 1920, 1280, 720, 404, 720)]
    [InlineData(2160, 3840, 3840, 2160, 1214, 2160)]
    public void DiPiuSiRiduceUnaVolta(int l, int a, int lw, int aw, int attesaL, int attesaA)
    {
        var webcam = new FormatoWebcam(lw, aw, 30);
        var lavoro = ScalaUnaVolta.MisuraLavoro(l, a, webcam, Inquadratura.Adatta);
        Assert.Equal((attesaL, attesaA), lavoro);
        Assert.Equal(1, ScalaUnaVolta.Scalature(l, a, lavoro, webcam, Inquadratura.Adatta));
    }

    [Theory]
    // Il telefono manda di meno: il motore lavora alla sua misura e si ingrandisce una volta, nella conversione alla fine.
    [InlineData(1920, 1080, 3840, 2160)]
    [InlineData(1280, 720, 1920, 1080)]
    [InlineData(1280, 720, 3840, 2160)]
    [InlineData(1080, 1920, 3840, 2160)]
    [InlineData(720, 1280, 3840, 2160)]
    public void DiMenoSiIngrandisceUnaVolta(int l, int a, int lw, int aw)
    {
        var webcam = new FormatoWebcam(lw, aw, 30);
        var lavoro = ScalaUnaVolta.MisuraLavoro(l, a, webcam, Inquadratura.Adatta);
        Assert.Equal((l, a), lavoro);
        Assert.Equal(1, ScalaUnaVolta.Scalature(l, a, lavoro, webcam, Inquadratura.Adatta));
    }

    [Fact]
    public void StessaMisuraNessunaScalatura()
    {
        foreach (var formato in new[] { Hd, FullHd60, QuattroK })
        {
            var lavoro = ScalaUnaVolta.MisuraLavoro(formato.Larghezza, formato.Altezza, formato, Inquadratura.Adatta);
            Assert.Equal((formato.Larghezza, formato.Altezza), lavoro);
            Assert.Equal(0, ScalaUnaVolta.Scalature(formato.Larghezza, formato.Altezza, lavoro, formato, Inquadratura.Adatta));
        }
    }

    [Fact]
    public void RiempiOrizzontaleUnaVolta()
    {
        // 4:3 in una webcam 16:9 con «Riempi»: si taglia sopra e sotto e si riduce una volta.
        var lavoro = ScalaUnaVolta.MisuraLavoro(1440, 1080, Hd, Inquadratura.Riempi);
        Assert.True(lavoro.Larghezza < 1440 && lavoro.Altezza < 1080);
        Assert.Equal(1, ScalaUnaVolta.Scalature(1440, 1080, lavoro, Hd, Inquadratura.Riempi));
    }

    [Fact]
    public void DuranteLaRegistrazioneLaMisuraResta()
    {
        // Il file è a 1080p: un'app che apre la webcam in 4K o a 720p non lo chiude; la webcam scala una volta da qui.
        var registrazione = ScalaUnaVolta.SenzaWebcam(3840, 2160);
        Assert.Equal(registrazione, ScalaUnaVolta.MisuraLavoro(3840, 2160, QuattroK, Inquadratura.Adatta, registrazione));
        Assert.Equal(registrazione, ScalaUnaVolta.MisuraLavoro(3840, 2160, Hd, Inquadratura.Adatta, registrazione));
        // L'unica eccezione nota: mentre si registra, un 4K verso una webcam a 720p si riduce due volte.
        Assert.Equal(2, ScalaUnaVolta.Scalature(3840, 2160, registrazione, Hd, Inquadratura.Adatta));
        // Il telefono cambia misura (girato, altro obiettivo): vale la regola normale e la registrazione si chiude come prima.
        Assert.Equal((1280, 720), ScalaUnaVolta.MisuraLavoro(1280, 720, null, Inquadratura.Adatta, registrazione));
    }

    [Fact]
    public void MisurePariEValoriStrani()
    {
        Assert.Equal((0, 0), ScalaUnaVolta.MisuraLavoro(0, 0, QuattroK, Inquadratura.Adatta));
        var dispari = ScalaUnaVolta.MisuraLavoro(1279, 719, QuattroK, Inquadratura.Adatta);
        Assert.Equal((1278, 718), dispari);
        foreach (var formato in FormatiWebcam.Tutti)
        foreach (var (l, a) in new[] { (3840, 2160), (2160, 3840), (1920, 1080), (1080, 1920), (1280, 720), (1440, 1080), (640, 480) })
        foreach (var modo in new[] { Inquadratura.Adatta, Inquadratura.Riempi })
        {
            var (ll, al) = ScalaUnaVolta.MisuraLavoro(l, a, formato, modo);
            Assert.True(ll >= 2 && al >= 2 && ll % 2 == 0 && al % 2 == 0, $"{l}×{a} → {formato}: {ll}×{al}");
            // Mai più grande del video: non si ingrandisce prima degli effetti.
            Assert.True(ll <= l && al <= a, $"{l}×{a} → {formato}: {ll}×{al}");
        }
    }

    [Fact]
    public void LaMemoriaCondivisaTieneIl4K()
    {
        // Ogni posto dell'anello tiene il formato più grande; tre posti, presi una volta sola.
        foreach (var formato in FormatiWebcam.Tutti) Assert.True(formato.Byte <= AnelloFotogrammi.BytePerPosto);
        Assert.Equal(12_441_600, QuattroK.Byte);
        Assert.Equal(373_248_000, ScalaUnaVolta.ByteAlSecondo(QuattroK));
        Assert.Equal(186_624_000, ScalaUnaVolta.ByteAlSecondo(FullHd60));
        // Un 4K a 30 fps sposta il doppio di un 1080p a 60 fps, non di più.
        Assert.Equal(2, ScalaUnaVolta.ByteAlSecondo(QuattroK) / ScalaUnaVolta.ByteAlSecondo(FullHd60));
    }
}
