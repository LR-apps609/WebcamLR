using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class MisuraLatenzaTest
{
    /// <summary>Orologio del telefono avanti di 5 secondi; fotogramma catturato 30 ms prima dell'arrivo.</summary>
    [Fact]
    public void LatenzaConOrologiDiversi()
    {
        var misura = new MisuraLatenza();
        const long avanti = 5_000_000;
        // Ping partito a 1000 µs, pong arrivato a 1200: il telefono ha risposto a metà strada (1100).
        misura.AggiungiPong(t: 1000, telefono: 1100 + avanti, adesso: 1200);
        Assert.Equal(avanti, misura.MiglioreScarto);

        var arrivo = 100_000UL;
        var catturaTelefono = (ulong)((long)arrivo - 30_000 + avanti);
        Assert.Equal(30, misura.Fotogramma(catturaTelefono, arrivo));
    }

    [Fact]
    public void SiUsaIlPongPiuRapido()
    {
        var misura = new MisuraLatenza();
        misura.AggiungiPong(t: 0, telefono: 900, adesso: 2000);   // lento: scarto stimato -100
        misura.AggiungiPong(t: 5000, telefono: 5050, adesso: 5100); // rapido: scarto 0
        Assert.Equal(0, misura.MiglioreScarto);
    }

    [Fact]
    public void LaLatenzaMostrataELaMediana()
    {
        var misura = new MisuraLatenza();
        misura.AggiungiPong(0, 50, 100);
        foreach (var ms in new[] { 30, 31, 90, 29, 32 })
        {
            misura.Fotogramma(1_000_000, 1_000_000 + (ulong)ms * 1000);
        }
        Assert.Equal(31, misura.ChiudiSecondo());
        Assert.Equal(31, misura.ChiudiSecondo()); // nessun fotogramma nuovo: resta l'ultima
    }

    [Fact]
    public void SenzaPongNonSiCalcola()
    {
        Assert.Null(new MisuraLatenza().Fotogramma(1, 2));
    }
}
