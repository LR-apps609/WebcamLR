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
        Assert.Equal("-1800;40;1280;800;1", posizione.Testo());
        Assert.Equal(posizione, PosizioneFinestra.DaTesto(posizione.Testo()));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("1;2;3")]
    [InlineData("a;0;100;100;0")]
    [InlineData("0;0;0;100;0")]
    public void TestoNonValido(string? testo)
    {
        Assert.Null(PosizioneFinestra.DaTesto(testo));
    }

    [Fact]
    public void SulloSchermoResta()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(2100, 100, 1280, 800), false);
        Assert.Equal(posizione, posizione.Su([Principale, Secondo]));
    }

    [Fact]
    public void SchermoStaccatoNonVale()
    {
        // Era sul secondo schermo, che adesso non c'è più.
        var posizione = new PosizioneFinestra(new Rettangolo(2100, 100, 1280, 800), false);
        Assert.Null(posizione.Su([Principale]));
    }

    [Fact]
    public void BarraDelTitoloFuoriNonVale()
    {
        // Solo 50 pixel della barra sono sullo schermo: non si riuscirebbe a trascinarla.
        var posizione = new PosizioneFinestra(new Rettangolo(1870, 100, 1280, 800), false);
        Assert.Null(posizione.Su([Principale]));
        // Barra sopra il bordo alto.
        Assert.Null(new PosizioneFinestra(new Rettangolo(100, -500, 1280, 800), false).Su([Principale]));
    }

    [Fact]
    public void TroppoGrandeSiStringeESiSpostaDentro()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(1000, 300, 2560, 1400), false);
        var adattata = posizione.Su([Principale]);
        Assert.Equal(new Rettangolo(0, 0, 1920, 1040), adattata?.Rettangolo);
    }

    [Fact]
    public void TroppoPiccolaSiAllarga()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(100, 100, 200, 100), false);
        Assert.Equal(new Rettangolo(100, 100, 640, 400), posizione.Su([Principale])?.Rettangolo);
    }

    [Fact]
    public void ACavalloDiDueSchermiRestaDovEra()
    {
        var posizione = new PosizioneFinestra(new Rettangolo(1700, 100, 1280, 800), true);
        var adattata = posizione.Su([Principale, Secondo]);
        Assert.Equal(posizione.Rettangolo, adattata?.Rettangolo);
        Assert.True(adattata?.Massimizzata);
    }

    [Fact]
    public void TroppoGrandeACavalloEntraNelloSchermoConPiuBarra()
    {
        // Più alta del primo schermo: va stretta e portata nel secondo, dove sta la parte maggiore della barra.
        var posizione = new PosizioneFinestra(new Rettangolo(1700, 100, 1280, 1500), false);
        Assert.Equal(new Rettangolo(1700, 0, 1280, 1400), posizione.Su([Principale, Secondo])?.Rettangolo);
    }
}
