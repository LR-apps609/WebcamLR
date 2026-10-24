using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class RegistroCollegamentoTest
{
    [Fact]
    public void TieneSoloGliUltimiCinquanta()
    {
        var registro = new RegistroCollegamento();
        for (var i = 1; i <= 60; i++) registro.Aggiungi($"evento {i}");
        var voci = registro.Voci;
        Assert.Equal(RegistroCollegamento.CapienzaPredefinita, voci.Count);
        Assert.Equal("evento 11", voci[0].Testo);
        Assert.Equal("evento 60", voci[^1].Testo);
    }

    [Fact]
    public void RigheConLOraEInOrdine()
    {
        var ora = new DateTime(2026, 10, 24, 9, 5, 7);
        var registro = new RegistroCollegamento(orologio: () => ora = ora.AddSeconds(1));
        registro.Aggiungi("Nuova connessione dal cavo USB");
        registro.Aggiungi("  «iPhone» accettato  ");
        registro.Aggiungi("   ");
        Assert.Equal("09:05:08  Nuova connessione dal cavo USB\n09:05:09  «iPhone» accettato", registro.Testo());
        Assert.Equal("09:05:09  «iPhone» accettato\n09:05:08  Nuova connessione dal cavo USB", registro.Testo(recentiPrima: true));
    }

    [Fact]
    public void AvvisaAOgniEvento()
    {
        var registro = new RegistroCollegamento(capienza: 3);
        var avvisi = 0;
        registro.Cambiato += () => avvisi++;
        registro.Aggiungi("a");
        registro.Aggiungi("b");
        Assert.Equal(2, avvisi);
    }

    [Fact]
    public async Task SiScriveDaPiuThreadInsieme()
    {
        var registro = new RegistroCollegamento(capienza: 50);
        await Task.WhenAll(Enumerable.Range(0, 8).Select(t => Task.Run(() =>
        {
            for (var i = 0; i < 500; i++) registro.Aggiungi($"{t}-{i}");
        })));
        Assert.Equal(50, registro.Voci.Count);
    }
}
