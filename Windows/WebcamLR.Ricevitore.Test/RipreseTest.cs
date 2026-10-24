using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Foto e registrazioni su Windows (P18): nomi, tempi, byte e frasi, come sul Mac.</summary>
public class RipreseTest
{
    private static readonly DateTime Quando = new(2026, 10, 24, 14, 5, 33);

    [Fact]
    public void NomeConLaDataComeSulMac()
    {
        Assert.Equal("2026-10-24 alle 14.05.33", Riprese.NomeData(Quando));
        var file = Riprese.FileLibero(Path.Combine("C:", "Immagini", "WebcamLR"), "png", Quando, _ => false);
        Assert.Equal("WebcamLR 2026-10-24 alle 14.05.33.png", Path.GetFileName(file));
    }

    [Fact]
    public void FileGiaPresenteNonSiSovrascrive()
    {
        var esistenti = new HashSet<string>
        {
            Path.Combine("v", "WebcamLR 2026-10-24 alle 14.05.33.mp4"),
            Path.Combine("v", "WebcamLR 2026-10-24 alle 14.05.33 (2).mp4"),
        };
        var file = Riprese.FileLibero("v", "mp4", Quando, esistenti.Contains);
        Assert.Equal(Path.Combine("v", "WebcamLR 2026-10-24 alle 14.05.33 (3).mp4"), file);
    }

    [Fact]
    public void FileLiberoSulDiscoVero()
    {
        var cartella = Directory.CreateTempSubdirectory("webcamlr-riprese").FullName;
        try
        {
            var primo = Riprese.FileLibero(cartella, "png", Quando);
            File.WriteAllBytes(primo, [1]);
            var secondo = Riprese.FileLibero(cartella, "png", Quando);
            Assert.NotEqual(primo, secondo);
            Assert.EndsWith(" (2).png", secondo);
        }
        finally
        {
            Directory.Delete(cartella, recursive: true);
        }
    }

    [Theory]
    [InlineData(0, "00:00")]
    [InlineData(12.9, "00:12")]
    [InlineData(754, "12:34")]
    [InlineData(3599, "59:59")]
    [InlineData(3723, "1:02:03")]
    [InlineData(-5, "00:00")]
    public void DurataInMinutiESecondi(double secondi, string atteso) =>
        Assert.Equal(atteso, Riprese.Durata(TimeSpan.FromSeconds(secondi)));

    [Theory]
    [InlineData(0, "0 byte")]
    [InlineData(999, "999 byte")]
    [InlineData(512_000, "512 KB")]
    [InlineData(8_400_000, "8,4 MB")]
    [InlineData(250_000_000, "250 MB")]
    [InlineData(1_234_000_000, "1,23 GB")]
    public void ByteAllItaliana(long byteTotali, string atteso) => Assert.Equal(atteso, Riprese.Byte(byteTotali));

    [Fact]
    public void PulsanteMentreRegistra()
    {
        Assert.Equal("Ferma · 00:12 · 8,4 MB", Riprese.TestoRegistrazione(TimeSpan.FromSeconds(12), 8_400_000));
        Assert.Equal("00:12", Riprese.TestoRegistrazione(TimeSpan.FromSeconds(12), 8_400_000, compatto: true));
    }

    [Fact]
    public void SpazioScarsoSottoIDueGiga()
    {
        Assert.Null(Riprese.SpazioScarso(2_000_000_000));
        Assert.Equal(1_800_000_000, Riprese.SpazioScarso(1_800_000_000));
        Assert.Equal("Solo 1,80 GB liberi", Riprese.AvvisoSpazio(1_800_000_000));
        Assert.Contains("Ferma la registrazione o libera spazio", Riprese.SpiegazioneSpazio(500_000_000));
    }

    [Fact]
    public void FrasiDiFine()
    {
        Assert.Equal("Registrazione salvata in Video › WebcamLR", Riprese.Testo(EsitoRegistrazione.Salvata));
        Assert.StartsWith("Registrazione troppo breve", Riprese.Testo(EsitoRegistrazione.TroppoBreve));
        Assert.StartsWith("Il video è cambiato", Riprese.Testo(EsitoRegistrazione.VideoCambiato));
        Assert.Contains("spazio sul disco", Riprese.Testo(EsitoRegistrazione.Interrotta));
        // Glossario: «fotogramma», mai «frame»; ogni errore dice cosa fare.
        foreach (var frase in new[] { Riprese.CopiaNonRiuscita, Riprese.NessunVideo, Riprese.FotoNonSalvata, Riprese.RegistrazioneNonCreata, Riprese.RegistrazioneInterrotta })
        {
            Assert.DoesNotContain("frame", frase, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("riprova", frase);
        }
    }
}
