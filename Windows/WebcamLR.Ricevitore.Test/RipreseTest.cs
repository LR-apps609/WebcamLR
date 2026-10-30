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
    public void MinutiRimastiAlRitmoDellaRegistrazione()
    {
        // 1 MB al secondo (8 Mbit/s): 600 MB liberi sono 10 minuti, 599 MB 9 minuti e 59 secondi.
        var durata = TimeSpan.FromSeconds(60);
        const long scritti = 60_000_000;
        Assert.Equal(10, Riprese.MinutiRimasti(600_000_000, scritti, durata));
        Assert.Equal(9, Riprese.MinutiRimasti(599_000_000, scritti, durata));
        Assert.Equal(0, Riprese.MinutiRimasti(30_000_000, scritti, durata));
        Assert.Equal(0, Riprese.MinutiRimasti(-1, scritti, durata));
        // Nei primi secondi, o senza byte, il ritmo non si sa: nessuna stima.
        Assert.Null(Riprese.MinutiRimasti(1_000, 4_000_000, TimeSpan.FromSeconds(4)));
        Assert.Null(Riprese.MinutiRimasti(1_000, 0, durata));
        // In 4K a 50 Mbit/s 2 GB sono pochi minuti; in 720p a 4 Mbit/s più di un'ora.
        Assert.Equal(5, Riprese.MinutiRimasti(2_000_000_000, 6_250_000L * 60, durata));
        Assert.Equal(66, Riprese.MinutiRimasti(2_000_000_000, 500_000L * 60, durata));
    }

    [Fact]
    public void SpazioQuasiFinitoSottoDieciMinuti()
    {
        var durata = TimeSpan.FromSeconds(60);
        const long scritti = 60_000_000; // 1 MB al secondo
        Assert.Null(Riprese.SpazioScarso(600_000_000, scritti, durata));
        Assert.Equal(9, Riprese.SpazioScarso(599_000_000, scritti, durata));
        Assert.Null(Riprese.SpazioScarso(1_000, scritti, TimeSpan.FromSeconds(2)));
        Assert.Equal("Spazio quasi finito: restano circa 9 minuti", Riprese.AvvisoSpazio(9));
        Assert.Equal("Spazio quasi finito: resta circa un minuto", Riprese.AvvisoSpazio(1));
        Assert.Equal("Spazio quasi finito: resta circa un minuto", Riprese.AvvisoSpazio(0));
        Assert.Contains("Ferma la registrazione o libera spazio", Riprese.SpiegazioneSpazio(500_000_000));
    }

    [Fact]
    public void DiscoPienoDiceQuantoESalvato()
    {
        var fine = new FineRegistrazione(EsitoRegistrazione.DiscoPieno, "x.mp4", TimeSpan.FromSeconds(751.4), 1);
        Assert.True(fine.FileSalvato);
        Assert.True(fine.SalvataInParte);
        Assert.Equal("Disco pieno: registrazione fermata. Ho salvato i primi 12:31 in Video › WebcamLR.", Riprese.Testo(fine));
        var altro = fine with { Esito = EsitoRegistrazione.ErroreDiScrittura };
        Assert.True(altro.FileSalvato);
        Assert.Equal("Non riesco più a scrivere sul disco: registrazione fermata. Ho salvato i primi 12:31 in Video › WebcamLR.", Riprese.Testo(altro));
        // Gli altri esiti come prima.
        Assert.Equal(Riprese.RegistrazioneSalvata, Riprese.Testo(fine with { Esito = EsitoRegistrazione.Salvata }));
        Assert.False((fine with { Esito = EsitoRegistrazione.Interrotta }).FileSalvato);
        Assert.False((fine with { Esito = EsitoRegistrazione.Salvata }).SalvataInParte);
    }

    [Fact]
    public void ErroreDiscoPienoRiconosciuto()
    {
        // ERROR_DISK_FULL e ERROR_HANDLE_DISK_FULL come HRESULT, cioè come li dà FileStream su Windows.
        Assert.True(Riprese.EDiscoPieno(new IOException("", unchecked((int)0x80070070)), null));
        Assert.True(Riprese.EDiscoPieno(new IOException("", unchecked((int)0x80070027)), null));
        // Un altro errore (disco staccato, permessi) con tanto spazio: no; con lo spazio quasi a zero: sì.
        Assert.False(Riprese.EDiscoPieno(new IOException("", unchecked((int)0x80070015)), 50_000_000_000));
        Assert.False(Riprese.EDiscoPieno(new UnauthorizedAccessException(), null));
        Assert.True(Riprese.EDiscoPieno(new IOException("", unchecked((int)0x80070015)), 1_000_000));
    }

    [Fact]
    public void ErroreDiscoPienoVeroSuLinux()
    {
        // /dev/full risponde ENOSPC a ogni scrittura: l'eccezione vera di .NET va riconosciuta.
        if (!OperatingSystem.IsLinux() || !File.Exists("/dev/full")) return;
        using var pieno = new FileStream("/dev/full", FileMode.Open, FileAccess.Write, FileShare.ReadWrite, bufferSize: 0);
        var errore = Assert.Throws<IOException>(() => pieno.Write(new byte[16]));
        Assert.True(Riprese.EDiscoPieno(errore, null));
    }

    [Fact]
    public void DomandaPrimaDiFermareLaRegistrazione()
    {
        Assert.Equal("Stai registrando: la registrazione si chiude e si salva. Continuare?", Riprese.DomandaRegistrando);
        Assert.Equal("Continua", Riprese.Continua);
        Assert.Equal("Annulla", Riprese.Annulla);
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
