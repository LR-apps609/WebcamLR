using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class DomandeFrequentiTest
{
    [Fact]
    public void QuindiciDomandeConIdUnici()
    {
        Assert.Equal(15, DomandeFrequenti.Tutte.Count);
        Assert.Equal(DomandeFrequenti.Tutte.Count, DomandeFrequenti.Tutte.Select(d => d.Id).Distinct().Count());
    }

    [Theory]
    [InlineData("usb", "cavo")]
    [InlineData("LATENZA", "ritardo")]
    [InlineData("qualita", "qualita")]      // senza accento trova «qualità»
    [InlineData("università", "rete-ospiti")]
    [InlineData("firewall windows", "firewall")]
    public void RicercaTrovaLaRispostaGiusta(string ricerca, string attesa)
    {
        Assert.Contains(DomandeFrequenti.Cerca(ricerca), d => d.Id == attesa);
    }

    [Fact]
    public void RicercaVuotaMostraTutto()
    {
        Assert.Equal(15, DomandeFrequenti.Cerca("  ").Count());
        Assert.Empty(DomandeFrequenti.Cerca("parola-che-non-esiste"));
    }
}
