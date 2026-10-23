using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class StoriaLatenzaTest
{
    [Fact]
    public void TieneSoloGliUltimi60Secondi()
    {
        var storia = new StoriaLatenza();
        for (var i = 0; i < 75; i++) storia.Aggiungi(i);
        Assert.Equal(60, storia.Conteggio);
        Assert.Equal(74, storia.Massima);
        // Restano 15…74: media 44,5, arrotondata.
        Assert.Equal(44, storia.Media);
    }

    [Fact]
    public void UltimoPuntoSulBordoDestro()
    {
        var storia = new StoriaLatenza();
        storia.Aggiungi(0);
        storia.Aggiungi(75);
        var punti = storia.Punti(118, 24);
        Assert.Equal(2, punti.Count);
        Assert.Equal((116.0, 24.0), punti[0]);
        // 75 ms su una scala di 150: a metà altezza.
        Assert.Equal((118.0, 12.0), punti[1]);
    }

    [Fact]
    public void ISecondiSenzaMisuraSiSaltano()
    {
        var storia = new StoriaLatenza();
        storia.Aggiungi(40);
        storia.Aggiungi(null);
        storia.Aggiungi(40);
        Assert.Equal(2, storia.Punti(59, 10).Count);
        Assert.Equal(40, storia.Media);
    }

    [Fact]
    public void LaScalaCresceConIPicchi()
    {
        var storia = new StoriaLatenza();
        storia.Aggiungi(50);
        Assert.Equal(150, storia.Scala);
        storia.Aggiungi(300);
        Assert.Equal(300, storia.Scala);
        Assert.Equal(0, storia.Punti(59, 30)[1].Y);
        Assert.Equal(20, storia.AltezzaDi(100, 30));
    }

    [Fact]
    public void VuotaSenzaMisure()
    {
        var storia = new StoriaLatenza();
        Assert.Null(storia.Media);
        Assert.Empty(storia.Punti(100, 20));
        storia.Aggiungi(30);
        storia.Azzera();
        Assert.Equal(0, storia.Conteggio);
    }
}
