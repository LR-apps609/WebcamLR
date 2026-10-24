using System.Runtime.InteropServices;
using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

/// <summary>L'anello su memoria normale, come sarà sulla memoria condivisa tra app e Frame Server.</summary>
public sealed unsafe class AnelloFotogrammiTest : IDisposable
{
    private readonly byte* memoria;
    private readonly AnelloFotogrammi anello;

    public AnelloFotogrammiTest()
    {
        memoria = (byte*)NativeMemory.AllocZeroed((nuint)AnelloFotogrammi.DimensioneTotale);
        anello = new AnelloFotogrammi(memoria, AnelloFotogrammi.DimensioneTotale);
    }

    public void Dispose() => NativeMemory.Free(memoria);

    [Fact]
    public void DisposizioneComeNelCommento()
    {
        Assert.Equal(4096, AnelloFotogrammi.DimensioneIntestazione);
        // Posti da 4K (P12): 3840 × 2160 × 3/2 = 12 441 600 byte, arrotondati a 4 KB.
        Assert.Equal(12443648, AnelloFotogrammi.BytePerPosto);
        Assert.Equal(4096 + 3L * 12443648, AnelloFotogrammi.DimensioneTotale);
        Assert.True(AnelloFotogrammi.DimensioneTotale < 40L * 1024 * 1024);
        anello.Prepara();
        Assert.Equal(0x56524C57u, *(uint*)memoria);
        Assert.Equal((byte)'W', memoria[0]);
        Assert.Equal((byte)'V', memoria[3]);
        Assert.Equal(2u, *(uint*)(memoria + 4));
        Assert.Equal(3u, *(uint*)(memoria + 8));
        Assert.Equal(12443648u, *(uint*)(memoria + 12));
    }

    [Fact]
    public void SenzaPreparazioneNonSiLegge()
    {
        Assert.False(anello.Valido);
        Assert.False(anello.Leggi(new byte[FormatiWebcam.Massimo.Byte], out _));
    }

    [Fact]
    public void PreparareDiNuovoNonCancella()
    {
        anello.Prepara();
        anello.Scrivi(Fotogramma(640, 360, 7), 640, 360, 1000);
        new AnelloFotogrammi(memoria, AnelloFotogrammi.DimensioneTotale).Prepara();
        Assert.Equal(1, anello.UltimoNumero);
    }

    [Fact]
    public void ScriveELeggeLUltimo()
    {
        anello.Prepara();
        Assert.False(anello.Leggi(new byte[100], out _));
        anello.Scrivi(Fotogramma(1280, 720, 1), 1280, 720, 5000);
        anello.Scrivi(Fotogramma(1280, 720, 2), 1280, 720, 5033);
        var letto = new byte[FormatiWebcam.Massimo.Byte];
        Assert.True(anello.Leggi(letto, out var info));
        Assert.Equal(new InfoFotogramma(2, 1280, 720, 5033), info);
        Assert.Equal(Fotogramma(1280, 720, 2), letto[..(1280 * 720 * 3 / 2)]);
    }

    [Fact]
    public void GiraSuTrePosti()
    {
        anello.Prepara();
        for (var i = 1; i <= 10; i++)
        {
            anello.Scrivi(Fotogramma(640, 360, (byte)i), 640, 360, i);
            var letto = new byte[640 * 360 * 3 / 2];
            Assert.True(anello.Leggi(letto, out var info));
            Assert.Equal(i, info.Numero);
            Assert.Equal((byte)i, letto[0]);
            Assert.Equal((byte)i, letto[^1]);
        }
    }

    [Fact]
    public void UnaScritturaANumeroNuovoNonSiLeggeAMeta()
    {
        anello.Prepara();
        anello.Scrivi(Fotogramma(640, 360, 1), 640, 360, 1);
        // L'app ha preso il posto del fotogramma 2 ma non ha finito: si legge ancora l'1.
        var spazio = anello.IniziaScrittura(640, 360);
        spazio.Fill(99);
        var letto = new byte[640 * 360 * 3 / 2];
        Assert.True(anello.Leggi(letto, out var info));
        Assert.Equal(1, info.Numero);
        Assert.Equal(1, letto[0]);
        anello.ConcludiScrittura(2);
        Assert.True(anello.Leggi(letto, out info));
        Assert.Equal(2, info.Numero);
        Assert.Equal(99, letto[0]);
    }

    [Fact]
    public void UnPostoInRiscritturaNonSiLegge()
    {
        anello.Prepara();
        // Fotogrammi 1, 2, 3: il prossimo (4) riscrive il posto dell'1, non quello del 3.
        for (var i = 1; i <= 3; i++) anello.Scrivi(Fotogramma(640, 360, (byte)i), 640, 360, i);
        // Un'app che ripartisse con un numero vecchio non deve rovinare il 3: il numero riparte da quello in memoria.
        var altroScrittore = new AnelloFotogrammi(memoria, AnelloFotogrammi.DimensioneTotale);
        altroScrittore.Scrivi(Fotogramma(640, 360, 4), 640, 360, 4);
        var letto = new byte[640 * 360 * 3 / 2];
        Assert.True(anello.Leggi(letto, out var info));
        Assert.Equal(4, info.Numero);
        Assert.Equal(4, letto[0]);
    }

    [Fact]
    public void DimensioniSbagliateRifiutate()
    {
        anello.Prepara();
        Assert.Throws<ArgumentException>(() => anello.IniziaScrittura(641, 360));
        Assert.Throws<ArgumentException>(() => anello.IniziaScrittura(3842, 2160));
        Assert.Throws<ArgumentException>(() => anello.IniziaScrittura(7680, 4320));
        Assert.Throws<ArgumentException>(() => anello.IniziaScrittura(0, 0));
    }

    [Fact]
    public void RichiestaEInUso()
    {
        anello.Prepara();
        Assert.False(anello.InUso(10_000));
        anello.SegnalaRichiesta(1280, 720, 10_000);
        Assert.Equal((1280, 720, 10_000L), anello.Richiesta());
        Assert.True(anello.InUso(11_999));
        Assert.False(anello.InUso(12_000));
        Assert.Equal(1, anello.FotogrammiDati);
        Assert.Equal(30, anello.FpsChiesti);
        anello.SegnalaRichiesta(1920, 1080, 10_033, 60);
        Assert.Equal(60, anello.FpsChiesti);
        Assert.Equal(60u, *(uint*)(memoria + 56));
        Assert.Equal(1920u, *(uint*)(memoria + 32));
    }

    [Fact]
    public void UnaVersioneVecchiaNonSiUsa()
    {
        anello.Prepara();
        // Una sorgente della versione 1 (posti da 1080p): l'app non scrive e non legge.
        *(uint*)(memoria + 4) = 1;
        *(uint*)(memoria + 12) = 3112960;
        Assert.False(anello.Valido);
        Assert.False(anello.Leggi(new byte[100], out _));
    }

    [Fact]
    public void TuttiIFormatiPassanoNellAnello()
    {
        anello.Prepara();
        long tempo = 0;
        foreach (var formato in FormatiWebcam.Tutti)
        {
            tempo++;
            anello.Scrivi(Fotogramma(formato.Larghezza, formato.Altezza, (byte)tempo), formato.Larghezza, formato.Altezza, tempo);
            var letto = new byte[FormatiWebcam.Massimo.Byte];
            Assert.True(anello.Leggi(letto, out var info));
            Assert.Equal((formato.Larghezza, formato.Altezza), (info.Larghezza, info.Altezza));
            Assert.Equal((byte)tempo, letto[formato.Byte - 1]);
        }
    }

    [Fact]
    public void QuattroKScrittoELettoPerIntero()
    {
        anello.Prepara();
        var dati = new byte[3840 * 2160 * 3 / 2];
        for (var i = 0; i < dati.Length; i++) dati[i] = (byte)(i * 7);
        for (var n = 1; n <= 4; n++) anello.Scrivi(dati, 3840, 2160, n);
        var letto = new byte[FormatiWebcam.Massimo.Byte];
        Assert.True(anello.Leggi(letto, out var info));
        Assert.Equal(new InfoFotogramma(4, 3840, 2160, 4), info);
        Assert.Equal(dati, letto);
    }

    [Fact]
    public void FrescoPerUnSecondo()
    {
        var info = new InfoFotogramma(5, 1920, 1080, 1_000);
        Assert.True(AnelloFotogrammi.Fresco(info, 1_999));
        Assert.False(AnelloFotogrammi.Fresco(info, 2_000));
        Assert.False(AnelloFotogrammi.Fresco(default, 0));
    }

    [Fact]
    public void LetturaEScritturaInsiemeNonDannoFotogrammiMisti()
    {
        anello.Prepara();
        const int l = 640, a = 360;
        var fine = DateTime.UtcNow.AddMilliseconds(400);
        var scrittore = Task.Run(() =>
        {
            byte valore = 0;
            var altro = new AnelloFotogrammi(memoria, AnelloFotogrammi.DimensioneTotale);
            while (DateTime.UtcNow < fine)
            {
                valore++;
                var spazio = altro.IniziaScrittura(l, a);
                spazio.Fill(valore);
                altro.ConcludiScrittura(Environment.TickCount64);
            }
        });
        var letto = new byte[l * a * 3 / 2];
        var letture = 0;
        while (!scrittore.IsCompleted)
        {
            if (!anello.Leggi(letto, out _)) continue;
            letture++;
            // Tutto il fotogramma ha lo stesso valore: nessuna lettura a metà tra due fotogrammi.
            Assert.True(letto.AsSpan().IndexOfAnyExcept(letto[0]) < 0);
        }
        Assert.Null(scrittore.Exception);
        Assert.True(letture > 0);
    }

    private static byte[] Fotogramma(int larghezza, int altezza, byte valore)
    {
        var dati = new byte[larghezza * altezza * 3 / 2];
        Array.Fill(dati, valore);
        return dati;
    }
}
