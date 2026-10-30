using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class PosizioneFinestraTest
{
    private static readonly Rettangolo Principale = new(0, 0, 1920, 1040);
    private static readonly Rettangolo Secondo = new(1920, 0, 2560, 1400);

    [Fact]
    public void TestoAvantiEIndietro()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(-1800, 40, 1280, 800), true);
        Assert.Equal("dip;-1800;40;1280;800;1", posizione.Testo());
        Assert.Equal(posizione, PosizioneFinestra.DaTesto(posizione.Testo()));
    }

    [Fact]
    public void IlFormatoDiPrimaEraInPixel()
    {
        var vecchia = PosizioneFinestra.DaTesto("100;40;1600;960;0");
        Assert.NotNull(vecchia);
        Assert.False(vecchia!.MisuraInDip);
        // In pixel così com'era: a 150 % non si ingrandisce una seconda volta.
        Assert.Equal(new Rettangolo(100, 40, 1600, 960), vecchia.Su([Principale], 1.5));
        Assert.Equal("100;40;1600;960;0", vecchia.Testo());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("1;2;3")]
    [InlineData("a;0;100;100;0")]
    [InlineData("0;0;0;100;0")]
    [InlineData("px;0;0;100;100;0")]
    [InlineData("dip;0;0;100;0")]
    public void TestoNonValido(string? testo)
    {
        Assert.Null(PosizioneFinestra.DaTesto(testo));
    }

    [Fact]
    public void MisuraInDipConLaScala()
    {
        // 1360×840 DIP a 150 %: 2040×1260 pixel, non 907×560 DIP come quando la misura era in pixel.
        var posizione = PosizioneFinestra.DaPixel(new Rettangolo(2000, 50, 2040, 1260), 1.5, massimizzata: false);
        Assert.Equal(new Rettangolo(2000, 50, 1360, 840), posizione.Rettangolo);
        Assert.Equal(new Rettangolo(2000, 50, 2040, 1260), posizione.Su([Principale, Secondo], 1.5));
        // Sullo stesso schermo portato al 100 %: la stessa misura in DIP, meno pixel.
        Assert.Equal(new Rettangolo(2000, 50, 1360, 840), posizione.Su([Principale, Secondo], 1));
    }

    [Fact]
    public void ScalaSenzaSensoValeUno()
    {
        Assert.Equal(1, PosizioneFinestra.ScalaValida(0));
        Assert.Equal(1, PosizioneFinestra.ScalaValida(double.NaN));
        Assert.Equal(1.25, PosizioneFinestra.ScalaValida(1.25));
        Assert.Equal(960, PosizioneFinestra.InPixel(960, -2));
    }

    [Fact]
    public void PrimaAperturaAlCentroInDip()
    {
        // 100 %: 1360×840 al centro dell'area di lavoro.
        Assert.Equal(new Rettangolo(280, 100, 1360, 840), PosizioneFinestra.Iniziale(Principale, 1));
        // 150 % su uno schermo 2560×1400: 2040×1260 pixel, cioè 1360×840 DIP.
        Assert.Equal(new Rettangolo(1920 + 260, 70, 2040, 1260), PosizioneFinestra.Iniziale(Secondo, 1.5));
        // 150 % su un portatile 1920×1040: lo schermo non basta, la finestra lo riempie.
        Assert.Equal(new Rettangolo(0, 0, 1920, 1040), PosizioneFinestra.Iniziale(Principale, 1.5));
    }

    [Fact]
    public void SulloSchermoResta()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(2100, 100, 1280, 800), false);
        Assert.Equal(posizione.Rettangolo, posizione.Su([Principale, Secondo], 1));
    }

    [Fact]
    public void SchermoStaccatoNonVale()
    {
        // Era sul secondo schermo, che adesso non c'è più.
        var posizione = new PosizioneFinestra(new Rettangolo(2100, 100, 1280, 800), false);
        Assert.Null(posizione.Su([Principale], 1));
    }

    [Fact]
    public void BarraDelTitoloFuoriNonVale()
    {
        // Solo 50 pixel della barra sono sullo schermo: non si riuscirebbe a trascinarla.
        var posizione = new PosizioneFinestra(new Rettangolo(1870, 100, 1280, 800), false);
        Assert.Null(posizione.Su([Principale], 1));
        // Barra sopra il bordo alto.
        Assert.Null(new PosizioneFinestra(new Rettangolo(100, -500, 1280, 800), false).Su([Principale], 1));
    }

    [Fact]
    public void TroppoGrandeSiStringeESiSpostaDentro()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(1000, 300, 2560, 1400), false);
        Assert.Equal(new Rettangolo(0, 0, 1920, 1040), posizione.Su([Principale], 1));
    }

    [Fact]
    public void TroppoPiccolaSiAllargaAllaMisuraMinima()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(100, 100, 200, 100), false);
        // 960×600 DIP: a 100 % in pixel uguali, a 125 % 1200×750.
        Assert.Equal(new Rettangolo(100, 100, 960, 600), posizione.Su([Principale], 1));
        Assert.Equal(new Rettangolo(100, 100, 1200, 750), posizione.Su([Principale], 1.25));
    }

    [Fact]
    public void ACavalloDiDueSchermiRestaDovEra()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(1700, 100, 1280, 800), true);
        Assert.Equal(posizione.Rettangolo, posizione.Su([Principale, Secondo], 1));
    }

    [Fact]
    public void TroppoGrandeACavalloEntraNelloSchermoConPiuBarra()
    {
        // Più alta del primo schermo: va stretta e portata nel secondo, dove sta la parte maggiore della barra.
        var posizione = new PosizioneFinestra(new Rettangolo(1700, 100, 1280, 1500), false);
        Assert.Equal(new Rettangolo(1700, 0, 1280, 1400), posizione.Su([Principale, Secondo], 1));
    }
}
