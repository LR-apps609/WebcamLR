using System.Diagnostics;
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
        // Più l'immagine personale della schermata di attesa: 1920 × 1080 × 3/2, arrotondati a 4 KB.
        Assert.Equal(3112960, AnelloFotogrammi.ByteImmagine);
        Assert.Equal(4096 + 3L * 12443648 + 3112960, AnelloFotogrammi.DimensioneTotale);
        Assert.True(AnelloFotogrammi.DimensioneTotale < 40L * 1024 * 1024);
        anello.Prepara();
        Assert.Equal(0x56524C57u, *(uint*)memoria);
        Assert.Equal((byte)'W', memoria[0]);
        Assert.Equal((byte)'V', memoria[3]);
        Assert.Equal(3u, *(uint*)(memoria + 4));
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
        anello.Scrivi(Fotogramma(1280, 720, 1), 1280, 720, 5000, istanteTick: 111);
        anello.Scrivi(Fotogramma(1280, 720, 2), 1280, 720, 5033, istanteTick: 222);
        var letto = new byte[FormatiWebcam.Massimo.Byte];
        Assert.True(anello.Leggi(letto, out var info));
        Assert.Equal(new InfoFotogramma(2, 1280, 720, 5033, 222), info);
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
    public void LaVersione2NonSiUsa()
    {
        // Una sorgente di prima della schermata di attesa nuova: stessa misura dei posti, versione 2.
        anello.Prepara();
        *(uint*)(memoria + 4) = 2;
        Assert.False(anello.Valido);
    }

    [Fact]
    public void StatoDellAttesaScrittoELetto()
    {
        anello.Prepara();
        // Appena creata: nessuno stato, battito 0 (WebcamLR chiusa).
        Assert.Equal((StatoAttesa.Nessuna, StileAttesa.WebcamLR, LinguaAttesa.Automatica, 0L), anello.LeggiAttesa());
        anello.ImpostaAttesa(StatoAttesa.Pausa, StileAttesa.Sfocata, LinguaAttesa.Italiano, 12_345);
        Assert.Equal((StatoAttesa.Pausa, StileAttesa.Sfocata, LinguaAttesa.Italiano, 12_345L), anello.LeggiAttesa());
        // Posizioni come nel commento di AnelloFotogrammi.
        Assert.Equal(3u, *(uint*)(memoria + 256));
        Assert.Equal(3u, *(uint*)(memoria + 260));
        Assert.Equal(12_345L, *(long*)(memoria + 264));
        Assert.Equal(1u, *(uint*)(memoria + 272));
        Assert.True(AnelloFotogrammi.AppViva(12_345, 12_345 + NomiWebcam.StatoAppMs - 1));
        Assert.False(AnelloFotogrammi.AppViva(12_345, 12_345 + NomiWebcam.StatoAppMs));
        Assert.False(AnelloFotogrammi.AppViva(0, 5));

        anello.SegnalaChiusura();
        var dopo = anello.LeggiAttesa();
        Assert.Equal(StatoAttesa.NonCollegata, dopo.Stato);
        Assert.Equal(0L, dopo.BattitoMs);
    }

    [Fact]
    public void ValoriSconosciutiDiventanoQuelliPredefiniti()
    {
        anello.Prepara();
        *(uint*)(memoria + 256) = 99;
        *(uint*)(memoria + 260) = 99;
        *(uint*)(memoria + 272) = 99;
        var letto = anello.LeggiAttesa();
        Assert.Equal((StatoAttesa.NonCollegata, StileAttesa.WebcamLR, LinguaAttesa.Automatica), (letto.Stato, letto.Stile, letto.Lingua));
    }

    [Fact]
    public void ImmaginePersonaleScrittaELetta()
    {
        anello.Prepara();
        Assert.Null(anello.LeggiImmaginePersonale());
        Assert.Equal(0, anello.VersioneImmagine);
        var dati = Fotogramma(1920, 1080, 77);
        anello.ScriviImmaginePersonale(dati, 1920, 1080);
        var letta = anello.LeggiImmaginePersonale();
        Assert.NotNull(letta);
        Assert.Equal(1, letta!.Value.Versione);
        Assert.Equal((1920, 1080), (letta.Value.Immagine.Larghezza, letta.Value.Immagine.Altezza));
        Assert.Equal(dati, letta.Value.Immagine.Dati);
        // Non tocca i posti dei fotogrammi.
        Assert.False(anello.Leggi(new byte[FormatiWebcam.Massimo.Byte], out _));

        anello.ScriviImmaginePersonale(Fotogramma(640, 480, 5), 640, 480);
        Assert.Equal(2, anello.VersioneImmagine);
        anello.TogliImmaginePersonale();
        Assert.Null(anello.LeggiImmaginePersonale());

        Assert.Throws<ArgumentException>(() => anello.ScriviImmaginePersonale(new byte[3840 * 2160 * 3 / 2], 3840, 2160));
        Assert.Throws<ArgumentException>(() => anello.ScriviImmaginePersonale(new byte[1000], 101, 10));
    }

    [Fact]
    public void ImmaginePersonaleDaBgraRimpicciolitaConLeProporzioni()
    {
        anello.Prepara();
        // Una foto verticale 3000×4000 bianca: entra in 1920×1080 come 810×1080.
        var bgra = new byte[3000 * 4000 * 4];
        Array.Fill(bgra, (byte)255);
        anello.ScriviImmaginePersonaleBgra(bgra, 3000, 4000, 3000 * 4);
        var letta = anello.LeggiImmaginePersonale()!.Value.Immagine;
        Assert.Equal((810, 1080), (letta.Larghezza, letta.Altezza));
        Assert.Equal(235, letta.Dati[0]);
    }

    [Fact]
    public void ImmagineInScritturaNonSiLegge()
    {
        anello.Prepara();
        anello.ScriviImmaginePersonale(Fotogramma(640, 360, 1), 640, 360);
        *(long*)(memoria + 280) = -1;
        Assert.Null(anello.LeggiImmaginePersonale());
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
        Assert.Equal(new InfoFotogramma(4, 3840, 2160, 4), info with { IstanteTick = 0 });
        // Senza istante dato vale «adesso»: mai zero.
        Assert.NotEqual(0, info.IstanteTick);
        Assert.Equal(dati, letto);
    }

    /// <summary>La sorgente consegna sempre l'ultimo fotogramma completo: quelli scritti prima si saltano.</summary>
    [Fact]
    public void SiConsegnaLUltimoSaltandoIVecchi()
    {
        anello.Prepara();
        // L'app scrive tre fotogrammi mentre la sorgente aspetta (un'app di chiamata lenta, un ritardo di rete recuperato).
        for (var i = 1; i <= 3; i++) anello.Scrivi(Fotogramma(640, 360, (byte)(10 * i)), 640, 360, i, istanteTick: 1000 * i);
        var letto = new byte[640 * 360 * 3 / 2];
        Assert.True(anello.Leggi(letto, out var info));
        Assert.Equal((3, 3000L), (info.Numero, info.IstanteTick));
        Assert.Equal(30, letto[0]);
    }

    [Fact]
    public void AttesaDellaSorgenteScrittaELetta()
    {
        anello.Prepara();
        const long frequenza = 10_000_000;
        // Una sorgente di prima non la scrive: «non si sa».
        Assert.Null(anello.AttesaSorgente(5 * frequenza, frequenza));
        anello.ScriviAttesaSorgente(12_500, 5 * frequenza);
        Assert.Equal(12_500, anello.AttesaSorgente(6 * frequenza, frequenza));
        // Più vecchia di 2 secondi (nessuna app usa più la webcam): non vale.
        Assert.Null(anello.AttesaSorgente(7 * frequenza + 1, frequenza));
        // I campi nuovi stanno dopo l'immagine personale e prima dei dati, nei byte che le versioni di prima lasciano a zero.
        Assert.Equal(12_500, *(long*)(memoria + 296));
        Assert.Equal(5 * frequenza, *(long*)(memoria + 304));
    }

    [Fact]
    public void FrescoPerUnSecondo()
    {
        var info = new InfoFotogramma(5, 1920, 1080, 1_000);
        Assert.True(AnelloFotogrammi.Fresco(info, 1_999));
        Assert.False(AnelloFotogrammi.Fresco(info, 2_000));
        Assert.False(AnelloFotogrammi.Fresco(default, 0));
    }

    /// <remarks>
    /// Niente scadenza a orologio: con la macchina carica lo scrittore poteva partire tardi o prendere sempre il posto
    /// che si stava leggendo, e il test finiva con zero letture riuscite. Lo scrittore va avanti finché il lettore non
    /// ha fatto abbastanza letture complete e lui abbastanza fotogrammi; i 30 secondi sono solo un paracadute.
    /// </remarks>
    [Fact]
    public void LetturaEScritturaInsiemeNonDannoFotogrammiMisti()
    {
        anello.Prepara();
        const int l = 640, a = 360, lettureVolute = 100, fotogrammiVoluti = 1000;
        var letture = 0;
        var basta = false;
        var paracadute = Stopwatch.StartNew();
        byte valore = 0;
        Exception? errore = null;
        // Un thread suo, non il pool: con il pool pieno (gli altri test) il Task poteva partire tardi.
        var scrittore = new Thread(() =>
        {
            try
            {
                var scritti = 0;
                var altro = new AnelloFotogrammi(memoria, AnelloFotogrammi.DimensioneTotale);
                while (!Volatile.Read(ref basta) && paracadute.Elapsed < TimeSpan.FromSeconds(30)
                       && (Volatile.Read(ref letture) < lettureVolute || scritti < fotogrammiVoluti))
                {
                    valore++;
                    var spazio = altro.IniziaScrittura(l, a);
                    spazio.Fill(valore);
                    altro.ConcludiScrittura(Environment.TickCount64);
                    scritti++;
                }
            }
            catch (Exception e) { errore = e; }
        }) { IsBackground = true };
        scrittore.Start();
        var letto = new byte[l * a * 3 / 2];
        try
        {
            while (scrittore.IsAlive)
            {
                if (!anello.Leggi(letto, out _)) continue;
                Interlocked.Increment(ref letture);
                // Tutto il fotogramma ha lo stesso valore: nessuna lettura a metà tra due fotogrammi.
                Assert.True(letto.AsSpan().IndexOfAnyExcept(letto[0]) < 0);
            }
        }
        finally
        {
            // Lo scrittore non deve toccare la memoria dopo che Dispose l'ha liberata.
            Volatile.Write(ref basta, true);
            scrittore.Join();
        }
        Assert.Null(errore);
        Assert.True(letture >= lettureVolute, $"Solo {letture} letture complete in {paracadute.Elapsed}");
        // A scrittore fermo si legge l'ultimo fotogramma, intero.
        Assert.True(anello.Leggi(letto, out _));
        Assert.True(letto.AsSpan().IndexOfAnyExcept(valore) < 0);
    }

    private static byte[] Fotogramma(int larghezza, int altezza, byte valore)
    {
        var dati = new byte[larghezza * altezza * 3 / 2];
        Array.Fill(dati, valore);
        return dati;
    }
}
