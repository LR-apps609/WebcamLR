using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class ScorciatoieTest
{
    [Theory]
    [InlineData(1, 3, 0)]
    [InlineData(3, 3, 2)]
    [InlineData(4, 3, null)]
    [InlineData(4, 5, 3)]
    [InlineData(5, 5, null)]
    [InlineData(0, 3, null)]
    public void TastiDegliObiettivi(int numero, int disponibili, int? atteso)
    {
        Assert.Equal(atteso, Scorciatoie.Obiettivo(numero, disponibili));
    }

    [Theory]
    [InlineData(1.0, 10, 1, 1.5)]
    [InlineData(1.3, 10, 1, 1.5)]
    [InlineData(1.5, 10, 1, 2.0)]
    [InlineData(1.3, 10, -1, 1.0)]
    [InlineData(2.0, 10, -1, 1.5)]
    [InlineData(1.0, 10, -1, 1.0)]
    [InlineData(9.8, 10, 1, 10.0)]
    [InlineData(10.0, 10, 1, 10.0)]
    [InlineData(1.0, 1, 1, 1.0)]
    public void PassiDelloZoom(double attuale, double massimo, int verso, double atteso)
    {
        Assert.Equal(atteso, Scorciatoie.Zoom(attuale, massimo, verso), 6);
    }
}
