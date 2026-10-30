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
        // Frammentato: un solo frammento da 2 secondi, chiuso alla fine.
        var frammento = Assert.Single(LettoreFmp4.Frammenti(await File.ReadAllBytesAsync(file)));
        Assert.Equal(60, frammento.Campioni.Count);
        // Fermare di nuovo non cambia nulla.
        Assert.Equal(fine, await registrazione.FermaAsync());
    }

    /// <summary>I fotogrammi poco alla volta, perché la coda non salti nulla (il disco qui è memoria, velocissimo).</summary>
    private static async Task AccodaPianoAsync(Registrazione registrazione, int quanti)
    {
        for (var i = 0; i < quanti; i++)
        {
            registrazione.Accoda(Fotogramma(i));
            if (i % 20 == 19) await Task.Delay(5);
        }
    }

    [Fact]
    public async Task DiscoPienoTieneIlFileFinoAllUltimoFrammento()
    {
        // Il disco si riempie durante il secondo frammento: il primo (2 s) resta, il pezzo a metà si toglie.
        var primo = LettoreFmp4.Frammenti(ScrittoreDiProva(150))[0];
        var disco = new FlussoCheSiRiempie(primo.FineMdat + 100);
        var file = Path.Combine(cartella, "disco-pieno.mp4");
        var registrazione = Registrazione.Avvia(disco, file, Codec.H264, 1280, 720, DateTime.Now);
        var avvisata = new TaskCompletionSource<FineRegistrazione>();
        registrazione.FinitaDaSola += fine => avvisata.TrySetResult(fine);
        await AccodaPianoAsync(registrazione, 150);
        var fine = await avvisata.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(EsitoRegistrazione.DiscoPieno, fine.Esito);
        Assert.True(fine.FileSalvato);
        Assert.InRange(fine.Durata.TotalSeconds, 1.99, 2.01);
        var salvato = disco.ToArray();
        Assert.Equal(primo.FineMdat, salvato.Length);
        Assert.Equal(salvato.Length, fine.Byte);
        Assert.Equal(60, Assert.Single(LettoreFmp4.Frammenti(salvato)).Campioni.Count);
        Assert.Equal("Disco pieno: registrazione fermata. Ho salvato i primi 00:02 in Video › WebcamLR.", Riprese.Testo(fine));
        Assert.Equal(fine, await registrazione.FermaAsync());
    }

    [Fact]
    public async Task AltroErroreDiScritturaTieneIlFile()
    {
        var disco = new FlussoCheSiRiempie(LettoreFmp4.Frammenti(ScrittoreDiProva(150))[0].FineMdat + 10, unchecked((int)0x80070015));
        var registrazione = Registrazione.Avvia(disco, Path.Combine(cartella, "staccato.mp4"), Codec.H264, 1280, 720, DateTime.Now);
        await AccodaPianoAsync(registrazione, 150);
        var fine = await registrazione.FermaAsync();
        Assert.Equal(EsitoRegistrazione.ErroreDiScrittura, fine.Esito);
        Assert.True(fine.SalvataInParte);
        Assert.InRange(fine.Durata.TotalSeconds, 1.99, 2.01);
    }

    [Fact]
    public async Task ErroreSubitoNonLasciaNiente()
    {
        // Il disco è pieno già all'inizio: nemmeno un frammento, il file non resta.
        var file = Path.Combine(cartella, "subito.mp4");
        await File.WriteAllBytesAsync(file, []);
        var registrazione = Registrazione.Avvia(new FlussoCheSiRiempie(100), file, Codec.H264, 1280, 720, DateTime.Now);
        await AccodaPianoAsync(registrazione, 90);
        var fine = await registrazione.FermaAsync();
        Assert.Equal(EsitoRegistrazione.Interrotta, fine.Esito);
        Assert.False(fine.FileSalvato);
        Assert.False(File.Exists(file));
    }

    private static byte[] ScrittoreDiProva(int quanti)
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 1280, 720, DateTime.Now);
        for (var i = 0; i < quanti; i++)
        {
            var fotogramma = Fotogramma(i);
            scrittore.Aggiungi(fotogramma.Dati, fotogramma.Chiave, fotogramma.Timestamp);
        }
        return flusso.ToArray();
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
