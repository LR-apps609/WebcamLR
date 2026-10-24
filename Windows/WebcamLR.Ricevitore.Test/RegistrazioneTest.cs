using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;
using static WebcamLR.Ricevitore.Test.ScrittoreMp4Test;

namespace WebcamLR.Ricevitore.Test;

/// <summary>La registrazione su disco (P18): file salvato, troppo breve, video cambiato, rete che non aspetta.</summary>
public sealed class RegistrazioneTest : IDisposable
{
    private readonly string cartella = Directory.CreateTempSubdirectory("webcamlr-registrazione").FullName;

    public void Dispose()
    {
        try { Directory.Delete(cartella, recursive: true); } catch (IOException) { }
    }

    private string NuovoFile() => Riprese.FileLibero(cartella, "mp4", DateTime.Now);

    private static FotogrammaVideo Fotogramma(int i, ulong inizio = 1_000_000, byte[]? sps = null)
    {
        var chiave = i % 30 == 0;
        var dati = chiave ? AnnexBDi(sps ?? SpsH264, PpsH264, [0x65, (byte)i]) : AnnexBDi([0x41, (byte)i]);
        return new FotogrammaVideo(inizio + (ulong)i * 33_333, chiave, chiave, dati);
    }

    [Fact]
    public async Task DueSecondiSalvati()
    {
        var file = NuovoFile();
        var registrazione = Registrazione.Avvia(file, Codec.H264, 1280, 720, DateTime.Now);
        for (var i = 0; i < 60; i++) registrazione.Accoda(Fotogramma(i));
        var fine = await registrazione.FermaAsync();
        Assert.Equal(EsitoRegistrazione.Salvata, fine.Esito);
        Assert.True(fine.FileSalvato);
        Assert.Equal(file, fine.File);
        Assert.InRange(fine.Durata.TotalSeconds, 1.99, 2.01);
        Assert.True(File.Exists(file));
        Assert.Equal(new FileInfo(file).Length, fine.Byte);
        Assert.Equal(fine.Byte, registrazione.Byte);
        // Fermare di nuovo non cambia nulla.
        Assert.Equal(fine, await registrazione.FermaAsync());
    }

    [Fact]
    public async Task MenoDiUnSecondoNonResta()
    {
        var file = NuovoFile();
        var registrazione = Registrazione.Avvia(file, Codec.H264, 1280, 720, DateTime.Now);
        for (var i = 0; i < 20; i++) registrazione.Accoda(Fotogramma(i));
        var fine = await registrazione.FermaAsync();
        Assert.Equal(EsitoRegistrazione.TroppoBreve, fine.Esito);
        Assert.False(fine.FileSalvato);
        Assert.False(File.Exists(file));
    }

    [Fact]
    public async Task SenzaFotogrammaChiaveTroppoBreve()
    {
        var file = NuovoFile();
        var registrazione = Registrazione.Avvia(file, Codec.H264, 1280, 720, DateTime.Now);
        for (var i = 1; i < 29; i++) registrazione.Accoda(Fotogramma(i));
        Assert.Equal(EsitoRegistrazione.TroppoBreve, (await registrazione.FermaAsync()).Esito);
        Assert.False(File.Exists(file));
    }

    [Fact]
    public async Task VideoCambiatoChiudeESalva()
    {
        var file = NuovoFile();
        var registrazione = Registrazione.Avvia(file, Codec.H264, 1280, 720, DateTime.Now);
        var avvisata = new TaskCompletionSource<FineRegistrazione>();
        registrazione.FinitaDaSola += fine => avvisata.TrySetResult(fine);
        for (var i = 0; i < 60; i++) registrazione.Accoda(Fotogramma(i));
        var altroSps = (byte[])SpsH264.Clone();
        altroSps[3] = 0x28;
        for (var i = 60; i < 90; i++) registrazione.Accoda(Fotogramma(i, sps: altroSps));
        var fine = await avvisata.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(EsitoRegistrazione.VideoCambiato, fine.Esito);
        Assert.True(File.Exists(file));
        Assert.InRange(fine.Durata.TotalSeconds, 1.99, 2.01);
        Assert.Equal(fine, await registrazione.FermaAsync());
    }

    [Fact]
    public async Task FileGiaPresenteNonSiTocca()
    {
        var file = NuovoFile();
        await File.WriteAllBytesAsync(file, [42]);
        Assert.Throws<IOException>(() => Registrazione.Avvia(file, Codec.H264, 1280, 720, DateTime.Now));
        Assert.Equal([42], await File.ReadAllBytesAsync(file));
    }

    [Fact]
    public async Task LaReteNonAspettaIlDisco()
    {
        var file = NuovoFile();
        var registrazione = Registrazione.Avvia(file, Codec.H264, 1280, 720, DateTime.Now);
        // Molti fotogrammi di fila: Accoda non blocca mai, quelli in eccesso si saltano fino a un fotogramma chiave.
        var orologio = System.Diagnostics.Stopwatch.StartNew();
        for (var i = 0; i < 3000; i++) registrazione.Accoda(Fotogramma(i));
        Assert.True(orologio.ElapsedMilliseconds < 2000);
        var fine = await registrazione.FermaAsync();
        Assert.Equal(EsitoRegistrazione.Salvata, fine.Esito);
    }
}
