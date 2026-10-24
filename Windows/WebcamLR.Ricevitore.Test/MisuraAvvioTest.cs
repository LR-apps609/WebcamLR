using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class MisuraAvvioTest
{
    /// <summary>Un orologio finto in µs che va avanti solo quando lo dice il test.</summary>
    private sealed class OrologioFinto
    {
        public ulong Adesso;
        public ulong Leggi() => Adesso;
    }

    [Fact]
    public void TappeETotaleDallArrivo()
    {
        var orologio = new OrologioFinto { Adesso = 1_000_000 };
        var misura = new MisuraAvvio(orologio: orologio.Leggi);
        Assert.Null(misura.Testo);
        Assert.Null(misura.Riga);

        orologio.Adesso += 12_000; misura.Stretta();
        orologio.Adesso += 30_000; misura.Benvenuto();
        orologio.Adesso += 600_000; misura.PrimoFotogramma();
        orologio.Adesso += 250_000;
        Assert.True(misura.Mostrato());

        Assert.Equal(TimeSpan.FromMilliseconds(892), misura.Totale);
        Assert.Equal("Avvio: 0,9 s", misura.Testo);
        Assert.Equal("Avvio: 0,9 s (stretta di mano 12 ms · benvenuto 42 ms · primo fotogramma 642 ms · a schermo 892 ms)", misura.Riga);
    }

    [Fact]
    public void OgniTappaContaLaPrimaVolta()
    {
        var orologio = new OrologioFinto { Adesso = 5_000 };
        var misura = new MisuraAvvio(orologio: orologio.Leggi);
        orologio.Adesso += 100_000;
        misura.PrimoFotogramma();
        Assert.True(misura.Mostrato());
        orologio.Adesso += 5_000_000;
        misura.PrimoFotogramma();
        // Il secondo fotogramma a schermo (altro formato, altro obiettivo) non cambia nulla né riscrive il registro.
        Assert.False(misura.Mostrato());
        Assert.Equal("Avvio: 0,1 s (primo fotogramma 100 ms · a schermo 100 ms)", misura.Riga);
    }

    [Theory]
    [InlineData(20, "Avvio: 0,1 s")]
    [InlineData(949, "Avvio: 0,9 s")]
    [InlineData(950, "Avvio: 1,0 s")]
    [InlineData(1_840, "Avvio: 1,8 s")]
    [InlineData(12_345, "Avvio: 12,3 s")]
    public void TestoConLaVirgola(int millisecondi, string atteso) =>
        Assert.Equal(atteso, MisuraAvvio.TestoDi(TimeSpan.FromMilliseconds(millisecondi)));

    [Fact]
    public void ConLaConfermaDellUtenteSiDice()
    {
        var orologio = new OrologioFinto { Adesso = 0 };
        var misura = new MisuraAvvio(arrivo: 0, orologio: orologio.Leggi);
        misura.Conferma();
        orologio.Adesso = 8_000_000;
        misura.Mostrato();
        Assert.EndsWith(", con la conferma dell'utente", misura.Riga);
    }

    [Fact]
    public void ArrivoDatoDaChiAccetta()
    {
        var arrivo = Orologio.Adesso();
        var misura = new MisuraAvvio(arrivo);
        Assert.Equal(arrivo, misura.Arrivo);
        misura.Mostrato();
        Assert.True(misura.Totale >= TimeSpan.Zero);
    }

    [Fact]
    public void TelefonoGiaFidatoNonRiscriveIlFile()
    {
        using var identita = IdentitaDispositivo.Nuova();
        var salvataggi = 0;
        var abbinamento = new Abbinamento(identita, new Dictionary<string, string> { ["abc"] = "iPhone" }, _ => salvataggi++);
        abbinamento.Fida("abc", "iPhone");
        Assert.Equal(0, salvataggi);
        abbinamento.Fida("abc", "iPhone di Ledion");
        abbinamento.Fida("def", "iPad");
        Assert.Equal(2, salvataggi);
    }
}
