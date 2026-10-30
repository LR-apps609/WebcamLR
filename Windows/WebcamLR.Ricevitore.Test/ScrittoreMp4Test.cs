using System.Buffers.Binary;
using System.Text;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Il file MP4 della registrazione (P18) scatola per scatola, frammentato (1.0 beta 2, windows.md 1.3 e 1.4). I parametri
/// del codec sono quelli veri di due video di prova (H.264 High 720p e HEVC Main 1080p): i record avcC e hvcC attesi
/// sono quelli che scrive ffmpeg con gli stessi parametri. Con ffmpeg sul computer, anche un video vero letto da ffprobe.
/// </summary>
public class ScrittoreMp4Test
{
    internal static readonly byte[] SpsH264 = Convert.FromHexString("6764001facb200a00b760220000003002000000781e30649");
    internal static readonly byte[] PpsH264 = Convert.FromHexString("68ebc3cb22c0");
    private const string AvcCAtteso = "0164001fffe100186764001facb200a00b760220000003002000000781e3064901000668ebc3cb22c0fdf8f800";

    private static readonly byte[] VpsHevc = Convert.FromHexString("40010c01ffff016000000300900000030000030078928090");
    private static readonly byte[] SpsHevc = Convert.FromHexString("420101016000000300900000030000030078a003c08010e5964a924caf016808000003000800000300f040");
    private static readonly byte[] PpsHevc = Convert.FromHexString("4401c172b46240");
    private const string HvcCAtteso = "01016000000090000000000078f000fcfdf8f800000f03a00001001840010c01ffff016000000300900000030000030078928090a10001002b420101016000000300900000030000030078a003c08010e5964a924caf016808000003000800000300f040a2000100074401c172b46240";

    // ── Annex B e parametri ────────────────────────────────────────

    [Fact]
    public void UnitaConCodiciDiInizioDaTreEQuattroByte()
    {
        byte[] dati = [0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3, 0, 0, 0, 1, 0x65, 4, 5, 6];
        var unita = AnnexB.Unita(dati);
        Assert.Equal([(4, 3), (10, 2), (16, 4)], unita);
        Assert.Empty(AnnexB.Unita([1, 2, 3]));
    }

    [Fact]
    public void TipiDelleUnita()
    {
        Assert.Equal(7, AnnexB.Tipo(Codec.H264, 0x67));
        Assert.Equal(5, AnnexB.Tipo(Codec.H264, 0x65));
        Assert.Equal(32, AnnexB.Tipo(Codec.Hevc, 0x40));
        Assert.Equal(33, AnnexB.Tipo(Codec.Hevc, 0x42));
        Assert.Equal(19, AnnexB.Tipo(Codec.Hevc, 0x26));
    }

    [Fact]
    public void ByteDiPrevenzioneTolti()
    {
        Assert.Equal(new byte[] { 1, 0, 0, 0, 0, 1, 0, 0, 3 }, AnnexB.SenzaPrevenzione([1, 0, 0, 3, 0, 0, 3, 1, 0, 0, 3, 3]));
    }

    [Fact]
    public void GolombSenzaSegno()
    {
        // 1 → 0, 010 → 1, 011 → 2, 00100 → 3, 00111 → 6
        var bit = new LettoreBit([0b1010_0110, 0b0100_0011, 0b1000_0000]);
        Assert.Equal(0u, bit.Ue());
        Assert.Equal(1u, bit.Ue());
        Assert.Equal(2u, bit.Ue());
        Assert.Equal(3u, bit.Ue());
        Assert.Equal(6u, bit.Ue());
    }

    [Fact]
    public void AvcCComeFfmpeg()
    {
        var dati = AnnexBDi(SpsH264, PpsH264, [0x65, 0x88, 0x84]);
        var parametri = ParametriVideo.Da(Codec.H264, dati, AnnexB.Unita(dati))!;
        Assert.Equal((1, 0, 0), ParametriVideo.InfoH264(SpsH264));
        Assert.Equal(AvcCAtteso, Convert.ToHexString(parametri.RecordConfigurazione()).ToLowerInvariant());
    }

    [Fact]
    public void HvcCComeFfmpeg()
    {
        var dati = AnnexBDi(VpsHevc, SpsHevc, PpsHevc, [0x26, 0x01, 0xAF]);
        var parametri = ParametriVideo.Da(Codec.Hevc, dati, AnnexB.Unita(dati))!;
        var info = ParametriVideo.InfoHevc(SpsHevc);
        Assert.Equal((1920, 1080, 1, 0, 0, 0), (info.Larghezza, info.Altezza, info.Croma, info.ProfonditaLuma, info.ProfonditaCroma, info.SottostratiMeno1));
        Assert.Equal(HvcCAtteso, Convert.ToHexString(parametri.RecordConfigurazione()).ToLowerInvariant());
    }

    [Fact]
    public void SenzaParametriNiente()
    {
        var soloFetta = AnnexBDi([0x65, 1, 2]);
        Assert.Null(ParametriVideo.Da(Codec.H264, soloFetta, AnnexB.Unita(soloFetta)));
        // HEVC senza VPS non basta.
        var senzaVps = AnnexBDi(SpsHevc, PpsHevc);
        Assert.Null(ParametriVideo.Da(Codec.Hevc, senzaVps, AnnexB.Unita(senzaVps)));
    }

    // ── Il file frammentato ────────────────────────────────────────

    private static readonly DateTime Creazione = new(2026, 10, 24, 12, 0, 0, DateTimeKind.Utc);

    /// <summary>
    /// Fotogrammi H.264 finti: chiave ogni <paramref name="chiaveOgni"/> con delimitatore e parametri (che nel file non
    /// devono finire nei campioni), gli altri con una fetta sola. Il secondo byte della fetta è il numero del fotogramma.
    /// </summary>
    private static List<(byte[] Dati, bool Chiave, ulong Tempo)> FotogrammiH264(int quanti, int chiaveOgni = 30, ulong passo = 33_333)
    {
        var fotogrammi = new List<(byte[], bool, ulong)>();
        for (var i = 0; i < quanti; i++)
        {
            var chiave = i % chiaveOgni == 0;
            var dati = chiave
                ? AnnexBDi([0x09, 0xF0], SpsH264, PpsH264, [0x65, (byte)i, 0, 0, 3, 1])
                : AnnexBDi([0x09, 0xF0], [0x41, (byte)i, 7]);
            fotogrammi.Add((dati, chiave, 5_000_000 + (ulong)i * passo));
        }
        return fotogrammi;
    }

    private static (byte[] File, ScrittoreMp4 Scrittore) ScriviH264(int quanti, bool concludi = true)
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 1280, 720, Creazione);
        foreach (var (dati, chiave, tempo) in FotogrammiH264(quanti)) Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(dati, chiave, tempo));
        if (concludi) scrittore.Concludi();
        return (flusso.ToArray(), scrittore);
    }

    [Fact]
    public void FileH264FrammentatoScatolaPerScatola()
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 1280, 720, Creazione);
        // Prima del primo fotogramma chiave non si scrive nulla.
        Assert.Equal(EsitoCampione.InAttesaDiChiave, scrittore.Aggiungi(AnnexBDi([0x41, 9, 9]), false, 1_000));
        Assert.Equal(0, flusso.Length);
        // 10 secondi a 30 fps, chiave ogni secondo: frammenti da 2 secondi (60 fotogrammi), l'ultimo alla chiusura.
        foreach (var (dati, chiave, tempo) in FotogrammiH264(300)) Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(dati, chiave, tempo));
        scrittore.Concludi();
        var file = flusso.ToArray();
        Assert.Equal(file.Length, scrittore.Byte);
        Assert.Equal(file.Length, scrittore.ByteSalvati);
        Assert.Equal(5, scrittore.Frammenti);
        Assert.InRange(scrittore.Durata.TotalSeconds, 9.99, 10.01);
        Assert.Equal(scrittore.Durata, scrittore.DurataSalvata);

        // In cima: ftyp, moov, cinque coppie moof+mdat, mfra. Come ffmpeg con frag_keyframe+empty_moov+default_base_moof.
        var radice = Scatola.Leggi(file, 0, file.Length);
        Assert.Equal(["ftyp", "moov", "moof", "mdat", "moof", "mdat", "moof", "mdat", "moof", "mdat", "moof", "mdat", "mfra"], radice.Select(s => s.Tipo));
        Assert.Equal("iso5", Encoding.ASCII.GetString(file, 8, 4));
        Assert.Equal(["iso5", "iso6", "mp41"], Enumerable.Range(0, 3).Select(i => Encoding.ASCII.GetString(file, 16 + i * 4, 4)));

        // moov: la traccia con avcC, tabelle dei campioni vuote, mvex/trex e durata zero (la dicono i frammenti).
        var moov = radice[1];
        var stbl = Trova(file, moov, "trak", "mdia", "minf", "stbl");
        var stsd = Figlio(file, stbl, "stsd");
        var avc1 = Scatola.Leggi(file, stsd.Contenuto + 8, stsd.Fine).Single();
        Assert.Equal("avc1", avc1.Tipo);
        Assert.Equal((1280, 720), (BinaryPrimitives.ReadUInt16BigEndian(file.AsSpan(avc1.Contenuto + 24)), BinaryPrimitives.ReadUInt16BigEndian(file.AsSpan(avc1.Contenuto + 26))));
        var avcC = Scatola.Leggi(file, avc1.Contenuto + 78, avc1.Fine).First();
        Assert.Equal("avcC", avcC.Tipo);
        Assert.Equal(AvcCAtteso, Convert.ToHexString(file, avcC.Contenuto, avcC.Fine - avcC.Contenuto).ToLowerInvariant());
        Assert.Equal(0u, U32(file, Figlio(file, stbl, "stts").Contenuto + 4));
        Assert.Equal(0u, U32(file, Figlio(file, stbl, "stsc").Contenuto + 4));
        Assert.Equal(0u, U32(file, Figlio(file, stbl, "stsz").Contenuto + 8));
        Assert.Equal(0u, U32(file, Figlio(file, stbl, "stco").Contenuto + 4));
        var trex = Trova(file, moov, "mvex", "trex");
        Assert.Equal([0u, 1u, 1u, 0u, 0u, 0u], Enumerable.Range(0, 6).Select(i => U32(file, trex.Contenuto + i * 4)));
        var mvhd = Figlio(file, moov, "mvhd");
        Assert.Equal(1000u, U32(file, mvhd.Contenuto + 20));
        Assert.Equal(0ul, BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(mvhd.Contenuto + 24)));
        Assert.Equal("vide", Encoding.ASCII.GetString(file, Trova(file, moov, "trak", "mdia", "hdlr").Contenuto + 8, 4));
        var mdhd = Trova(file, moov, "trak", "mdia", "mdhd");
        Assert.Equal((uint)ScrittoreMp4.ScalaTempi, U32(file, mdhd.Contenuto + 20));

        // I frammenti, letti come un lettore qualsiasi.
        var frammenti = LettoreFmp4.Frammenti(file);
        Assert.Equal(5, frammenti.Count);
        Assert.Equal([1u, 2u, 3u, 4u, 5u], frammenti.Select(f => f.Sequenza));
        ulong atteso = 0;
        var numero = 0;
        foreach (var frammento in frammenti)
        {
            Assert.Equal(0x020000u, frammento.FlagTfhd);   // default-base-is-moof
            Assert.Equal(0x000701u, frammento.FlagTrun);   // data-offset, durata, dimensione, flag
            // base_media_decode_time: la somma delle durate dei frammenti prima, e il tempo del suo primo fotogramma.
            Assert.Equal(atteso, frammento.Base);
            Assert.Equal(numero * 33_333L * ScrittoreMp4.ScalaTempi / 1_000_000, (long)frammento.Base);
            Assert.Equal(60, frammento.Campioni.Count);
            // Comincia da un fotogramma chiave; chiave ogni 30.
            for (var i = 0; i < frammento.Campioni.Count; i++)
            {
                var campione = frammento.Campioni[i];
                var chiave = (numero + i) % 30 == 0;
                Assert.Equal(chiave ? ScrittoreMp4.FlagChiave : ScrittoreMp4.FlagNonChiave, campione.Flag);
                Assert.InRange(campione.Durata, 2999u, 3000u);
                Assert.Equal(chiave ? 10u : 7u, campione.Dimensione);
                // Lunghezza su 4 byte e poi la fetta, senza delimitatore né parametri.
                Assert.Equal(campione.Dimensione - 4, U32(file, campione.Posizione));
                Assert.Equal(chiave ? 0x65 : 0x41, file[campione.Posizione + 4]);
                Assert.Equal((byte)(numero + i), file[campione.Posizione + 5]);
            }
            Assert.True(frammento.Campioni[0].Flag == ScrittoreMp4.FlagChiave);
            atteso += (ulong)frammento.Campioni.Sum(c => c.Durata);
            numero += frammento.Campioni.Count;
        }
        Assert.InRange((long)atteso, 899_990L, 900_010L);

        // mfra: un punto di partenza per frammento, con la posizione del suo moof; mfro con la dimensione di mfra.
        var mfra = radice[^1];
        var tfra = Figlio(file, mfra, "tfra");
        Assert.Equal(1, file[tfra.Contenuto]);
        Assert.Equal(1u, U32(file, tfra.Contenuto + 4));
        Assert.Equal(5u, U32(file, tfra.Contenuto + 12));
        for (var i = 0; i < 5; i++)
        {
            var voce = tfra.Contenuto + 16 + i * 19;
            Assert.Equal(frammenti[i].Base, BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(voce)));
            Assert.Equal((ulong)frammenti[i].InizioMoof, BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(voce + 8)));
            Assert.Equal([1, 1, 1], file.AsSpan(voce + 16, 3).ToArray());
        }
        var mfro = Figlio(file, mfra, "mfro");
        Assert.Equal((uint)(mfra.Fine - mfra.Inizio), U32(file, mfro.Contenuto + 4));
    }

    [Fact]
    public void FrammentoScrittoSoloAlFotogrammaChiaveDopoDueSecondi()
    {
        // Chiave ogni 45 fotogrammi (1,5 s): il primo frammento si chiude alla seconda chiave dopo l'inizio (3 s).
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 640, 360, Creazione);
        foreach (var (dati, chiave, tempo) in FotogrammiH264(100, chiaveOgni: 45)) scrittore.Aggiungi(dati, chiave, tempo);
        // Fotogrammi 0-89 nel primo frammento (scritto all'arrivo del 90), 90-99 ancora in memoria.
        var frammenti = LettoreFmp4.Frammenti(flusso.ToArray());
        Assert.Equal(90, Assert.Single(frammenti).Campioni.Count);
        Assert.Equal(flusso.Length, scrittore.ByteSalvati);
        Assert.True(scrittore.Byte > scrittore.ByteSalvati);
        Assert.InRange(scrittore.DurataSalvata.TotalSeconds, 2.99, 3.01);
        Assert.InRange(scrittore.Durata.TotalSeconds, 3.32, 3.34);
        Assert.Equal(100, scrittore.Campioni);
    }

    [Fact]
    public void FileTroncatoInQualsiasiPuntoSiLeggeFinoAllUltimoFrammentoCompleto()
    {
        var (completo, _) = ScriviH264(300);
        var frammenti = LettoreFmp4.Frammenti(completo);
        Assert.Equal(5, frammenti.Count);
        var fineMoov = Scatola.Leggi(completo, 0, completo.Length)[1].Fine;
        // Ogni taglio possibile, anche a metà di un'intestazione, di moof o di mdat.
        for (var taglio = 0; taglio <= completo.Length; taglio++)
        {
            var troncato = completo.AsSpan(0, taglio).ToArray();
            var attesi = frammenti.Where(f => f.FineMdat <= taglio).ToList();
            var letti = LettoreFmp4.Frammenti(troncato);
            Assert.Equal(attesi.Count, letti.Count);
            for (var i = 0; i < letti.Count; i++)
            {
                Assert.Equal(attesi[i].Sequenza, letti[i].Sequenza);
                Assert.Equal(attesi[i].Base, letti[i].Base);
                Assert.Equal(attesi[i].Campioni, letti[i].Campioni);
            }
            // Lo stesso con il lettore dell'app (registrazione con gli effetti dopo un errore del disco).
            var parte = FrammentiMp4.Leggi(new MemoryStream(troncato));
            Assert.Equal(attesi.Count, parte.Frammenti);
            Assert.Equal(attesi.Count > 0 ? attesi[^1].FineMdat : taglio >= fineMoov ? fineMoov : 0, parte.Fine);
            var durata = attesi.Count == 0 ? 0 : (long)attesi[^1].Base + attesi[^1].Campioni.Sum(c => c.Durata);
            Assert.Equal(durata / (double)ScrittoreMp4.ScalaTempi, parte.Durata.TotalSeconds, 6);
        }
    }

    [Fact]
    public void InterrottoSenzaChiusuraRestaLeggibile()
    {
        // Crash o spegnimento: Concludi non arriva mai. Quello che è nel flusso si legge fino all'ultimo frammento.
        var (file, scrittore) = ScriviH264(250, concludi: false);
        var frammenti = LettoreFmp4.Frammenti(file);
        Assert.Equal(4, frammenti.Count); // 0-239; 240-249 erano ancora in memoria
        Assert.Equal(240, frammenti.Sum(f => f.Campioni.Count));
        Assert.Equal(file.Length, frammenti[^1].FineMdat);
        Assert.Equal(file.Length, scrittore.ByteSalvati);
        Assert.InRange(scrittore.DurataSalvata.TotalSeconds, 7.99, 8.01);
    }

    [Fact]
    public void DiscoPienoTieneIFrammentiCompleti()
    {
        // Il «disco» si riempie a metà del terzo frammento: ChiudiDopoErrore toglie il pezzo a metà.
        var (completo, _) = ScriviH264(300);
        var frammenti = LettoreFmp4.Frammenti(completo);
        var limite = frammenti[2].InizioMoof + 300;
        var flusso = new FlussoCheSiRiempie(limite);
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 1280, 720, Creazione);
        IOException? errore = null;
        foreach (var (dati, chiave, tempo) in FotogrammiH264(300))
        {
            try { scrittore.Aggiungi(dati, chiave, tempo); }
            catch (IOException e) { errore = e; break; }
        }
        Assert.NotNull(errore);
        Assert.Equal(limite, flusso.Length);
        var salvata = scrittore.ChiudiDopoErrore();
        Assert.Equal(frammenti[1].FineMdat, flusso.Length);
        Assert.Equal(flusso.Length, scrittore.ByteSalvati);
        Assert.InRange(salvata.TotalSeconds, 3.99, 4.01);
        var letti = LettoreFmp4.Frammenti(flusso.ToArray());
        Assert.Equal(2, letti.Count);
        Assert.Equal(["ftyp", "moov", "moof", "mdat", "moof", "mdat"], Scatola.Leggi(flusso.ToArray(), 0, (int)flusso.Length).Select(s => s.Tipo));
        // Dopo l'errore non si scrive più.
        Assert.Throws<InvalidOperationException>(() => scrittore.Aggiungi(AnnexBDi([0x41, 1]), false, 99_000_000));
    }

    [Fact]
    public void FileHevcFrammentatoConHvcC()
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.Hevc, 1920, 1080, DateTime.UtcNow);
        for (var i = 0; i < 150; i++)
        {
            var chiave = i % 60 == 0; // ogni 2 secondi
            // Delimitatore (tipo 35) e parametri non vanno nel campione; IDR (19) chiave, TRAIL_R (1) gli altri.
            var dati = chiave
                ? AnnexBDi([0x46, 0x01, 0x50], VpsHevc, SpsHevc, PpsHevc, [0x26, 0x01, (byte)(i + 1)])
                : AnnexBDi([0x46, 0x01, 0x50], [0x02, 0x01, (byte)i, 0xD0]);
            Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(dati, chiave, (ulong)i * 33_333));
        }
        scrittore.Concludi();
        var file = flusso.ToArray();
        var radice = Scatola.Leggi(file, 0, file.Length);
        Assert.Equal(["ftyp", "moov", "moof", "mdat", "moof", "mdat", "moof", "mdat", "mfra"], radice.Select(s => s.Tipo));
        var stsd = Trova(file, radice[1], "trak", "mdia", "minf", "stbl", "stsd");
        var hvc1 = Scatola.Leggi(file, stsd.Contenuto + 8, stsd.Fine).Single();
        Assert.Equal("hvc1", hvc1.Tipo);
        var hvcC = Scatola.Leggi(file, hvc1.Contenuto + 78, hvc1.Fine).First();
        Assert.Equal("hvcC", hvcC.Tipo);
        Assert.Equal(HvcCAtteso, Convert.ToHexString(file, hvcC.Contenuto, hvcC.Fine - hvcC.Contenuto).ToLowerInvariant());

        var frammenti = LettoreFmp4.Frammenti(file);
        Assert.Equal([60, 60, 30], frammenti.Select(f => f.Campioni.Count));
        Assert.Equal([1u, 2u, 3u], frammenti.Select(f => f.Sequenza));
        ulong atteso = 0;
        foreach (var frammento in frammenti)
        {
            Assert.Equal(atteso, frammento.Base);
            Assert.Equal(ScrittoreMp4.FlagChiave, frammento.Campioni[0].Flag);
            Assert.All(frammento.Campioni.Skip(1), c => Assert.Equal(ScrittoreMp4.FlagNonChiave, c.Flag));
            // Solo la fetta: 4 + 3 byte la chiave, 4 + 4 gli altri.
            Assert.Equal(7u, frammento.Campioni[0].Dimensione);
            Assert.All(frammento.Campioni.Skip(1), c => Assert.Equal(8u, c.Dimensione));
            Assert.Equal(0x26, file[frammento.Campioni[0].Posizione + 4]);
            atteso += (ulong)frammento.Campioni.Sum(c => c.Durata);
        }
        Assert.InRange(scrittore.Durata.TotalSeconds, 4.99, 5.01);
    }

    [Fact]
    public void ParametriDiversiChiudonoIlFile()
    {
        var scrittore = new ScrittoreMp4(new MemoryStream(), Codec.H264, 1280, 720, DateTime.UtcNow);
        Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(AnnexBDi(SpsH264, PpsH264, [0x65, 1]), true, 0));
        // Lo stesso SPS in un fotogramma chiave dopo: si continua.
        Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(AnnexBDi(SpsH264, PpsH264, [0x65, 2]), true, 2_000_000));
        var altroSps = (byte[])SpsH264.Clone();
        altroSps[3] = 0x28; // un altro livello: un altro video
        Assert.Equal(EsitoCampione.FormatoCambiato, scrittore.Aggiungi(AnnexBDi(altroSps, PpsH264, [0x65, 3]), true, 4_000_000));
        Assert.Equal(2, scrittore.Campioni);
    }

    [Fact]
    public void TempiSempreCrescentiEUltimoComeIlPrecedente()
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 640, 360, DateTime.UtcNow);
        scrittore.Aggiungi(AnnexBDi(SpsH264, PpsH264, [0x65, 1]), true, 1_000_000);
        scrittore.Aggiungi(AnnexBDi([0x41, 2]), false, 1_016_667); // 60 fps
        scrittore.Aggiungi(AnnexBDi([0x41, 3]), false, 1_016_667); // stesso timestamp: un tick dopo
        scrittore.Aggiungi(AnnexBDi([0x41, 4]), false, 900_000);   // all'indietro: un tick dopo
        scrittore.Concludi();
        var frammento = Assert.Single(LettoreFmp4.Frammenti(flusso.ToArray()));
        Assert.Equal([1500u, 1u, 1u, 1u], frammento.Campioni.Select(c => c.Durata));
    }

    [Fact]
    public void SenzaFotogrammiFileVuoto()
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 640, 360, DateTime.UtcNow);
        scrittore.Concludi();
        Assert.Equal(0, flusso.Length);
        Assert.Equal(TimeSpan.Zero, scrittore.Durata);
    }

    // ── Con fotogrammi veri, provati con ffprobe ───────────────────

    /// <summary>
    /// Un video vero codificato da ffmpeg (H.264 e HEVC, come il telefono: niente fotogrammi B, delimitatori e parametri
    /// a ogni fotogramma chiave), dato allo scrittore fotogramma per fotogramma; ffprobe e ffmpeg devono leggerlo tutto,
    /// e il file troncato fino all'ultimo frammento. Senza ffmpeg sul computer la prova non fa nulla.
    /// </summary>
    [Theory]
    [InlineData(Codec.H264)]
    [InlineData(Codec.Hevc)]
    public void FfprobeLeggeIlFileConFotogrammiVeri(Codec codec)
    {
        if (Programma("ffmpeg") is not { } ffmpeg || Programma("ffprobe") is not { } ffprobe) return;
        var cartella = Directory.CreateTempSubdirectory("webcamlr-fmp4").FullName;
        try
        {
            var grezzo = Path.Combine(cartella, codec == Codec.Hevc ? "prova.hevc" : "prova.h264");
            var codifica = codec == Codec.Hevc
                ? "-c:v libx265 -x265-params keyint=30:min-keyint=30:scenecut=0:bframes=0:open-gop=0:aud=1:repeat-headers=1:log-level=error -f hevc"
                : "-c:v libx264 -bf 0 -x264-params keyint=30:min-keyint=30:scenecut=0:aud=1:repeat-headers=1 -f h264";
            var (esito, _, errori) = Esegui(ffmpeg, $"-v error -y -f lavfi -i testsrc2=size=640x360:rate=30 -t 7 -pix_fmt yuv420p {codifica} \"{grezzo}\"");
            Assert.True(esito == 0, errori);

            var fotogrammi = UnitaDiAccesso(File.ReadAllBytes(grezzo), codec);
            Assert.Equal(210, fotogrammi.Count);
            var file = Path.Combine(cartella, "registrazione.mp4");
            using (var flusso = new FileStream(file, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read, 0))
            {
                var scrittore = new ScrittoreMp4(flusso, codec, 640, 360, DateTime.UtcNow);
                for (var i = 0; i < fotogrammi.Count; i++)
                    Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(fotogrammi[i].Dati, fotogrammi[i].Chiave, 1_000_000 + (ulong)i * 33_333));
                scrittore.Concludi();
                Assert.Equal(4, scrittore.Frammenti); // da 2 s: 0-2, 2-4, 4-6, 6-7
            }

            var (_, uscita, erroriProbe) = Esegui(ffprobe,
                $"-v error -count_frames -select_streams v:0 -show_entries stream=codec_name,width,height,nb_read_frames -show_entries format=duration -of default=nw=1 \"{file}\"");
            Assert.True(erroriProbe.Trim().Length == 0, erroriProbe);
            Assert.Contains($"codec_name={(codec == Codec.Hevc ? "hevc" : "h264")}", uscita);
            Assert.Contains("width=640", uscita);
            Assert.Contains("height=360", uscita);
            Assert.Contains("nb_read_frames=210", uscita);
            var durata = double.Parse(uscita.Split('\n').First(r => r.StartsWith("duration=")).Split('=')[1].Trim(), System.Globalization.CultureInfo.InvariantCulture);
            Assert.InRange(durata, 6.95, 7.05);
            // Decodifica completa senza errori.
            var (esitoDecodifica, _, erroriDecodifica) = Esegui(ffmpeg, $"-v error -i \"{file}\" -f null -");
            Assert.True(esitoDecodifica == 0 && erroriDecodifica.Trim().Length == 0, erroriDecodifica);

            // Troncato a metà del terzo frammento: si leggono almeno i primi due (120 fotogrammi) e nient'altro si rompe.
            var completo = File.ReadAllBytes(file);
            var frammenti = LettoreFmp4.Frammenti(completo);
            var troncato = Path.Combine(cartella, "troncato.mp4");
            File.WriteAllBytes(troncato, completo.AsSpan(0, frammenti[2].InizioMoof + (frammenti[2].FineMdat - frammenti[2].InizioMoof) / 2).ToArray());
            var (esitoTroncato, uscitaTroncato, _) = Esegui(ffprobe,
                $"-v quiet -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of default=nw=1:nk=1 \"{troncato}\"");
            Assert.Equal(0, esitoTroncato);
            Assert.InRange(int.Parse(uscitaTroncato.Trim()), 120, 180);

            // Il lettore dell'app su un fMP4 fatto da ffmpeg (durate predefinite in tfhd, non in trun).
            var diFfmpeg = Path.Combine(cartella, "ffmpeg.mp4");
            Assert.Equal(0, Esegui(ffmpeg, $"-v error -y -r 30 -i \"{grezzo}\" -c copy -movflags frag_keyframe+empty_moov+default_base_moof \"{diFfmpeg}\"").Esito);
            using var letto = File.OpenRead(diFfmpeg);
            var parte = FrammentiMp4.Leggi(letto);
            Assert.Equal(7, parte.Frammenti);
            Assert.Equal(letto.Length - MfraDi(File.ReadAllBytes(diFfmpeg)), parte.Fine);
            Assert.InRange(parte.Durata.TotalSeconds, 6.95, 7.05);
        }
        finally
        {
            try { Directory.Delete(cartella, recursive: true); } catch (IOException) { }
        }
    }

    /// <summary>La dimensione di mfra in fondo (0 se non c'è).</summary>
    private static long MfraDi(byte[] file)
    {
        var radice = Scatola.Leggi(file, 0, file.Length);
        return radice[^1].Tipo == "mfra" ? radice[^1].Fine - radice[^1].Inizio : 0;
    }

    /// <summary>Le unità di accesso di un flusso Annex B, divise ai delimitatori; chiave se c'è una IDR (o IRAP in HEVC).</summary>
    private static List<(byte[] Dati, bool Chiave)> UnitaDiAccesso(byte[] flusso, Codec codec)
    {
        var unita = AnnexB.Unita(flusso);
        var risultato = new List<(byte[], bool)>();
        var delimitatore = codec == Codec.Hevc ? 35 : 9;
        var inizio = -1;
        var chiave = false;
        foreach (var (posizione, _) in unita)
        {
            var tipo = AnnexB.Tipo(codec, flusso[posizione]);
            if (tipo == delimitatore)
            {
                // Il codice di inizio (3 o 4 byte) prima del delimitatore apre il fotogramma.
                var apertura = posizione - (posizione >= 4 && flusso[posizione - 4] == 0 ? 4 : 3);
                if (inizio >= 0) risultato.Add((flusso[inizio..apertura], chiave));
                inizio = apertura;
                chiave = false;
            }
            chiave |= codec == Codec.Hevc ? tipo is >= 16 and <= 21 : tipo == 5;
        }
        if (inizio >= 0) risultato.Add((flusso[inizio..], chiave));
        return risultato;
    }

    private static string? Programma(string nome)
    {
        foreach (var cartella in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            foreach (var file in new[] { Path.Combine(cartella, nome), Path.Combine(cartella, nome + ".exe") })
                if (File.Exists(file)) return file;
        }
        return null;
    }

    private static (int Esito, string Uscita, string Errori) Esegui(string programma, string argomenti)
    {
        using var processo = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(programma, argomenti)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        })!;
        var uscita = processo.StandardOutput.ReadToEndAsync();
        var errori = processo.StandardError.ReadToEndAsync();
        processo.WaitForExit();
        return (processo.ExitCode, uscita.Result, errori.Result);
    }

    // ── Aiuti ──────────────────────────────────────────────────────

    internal static byte[] AnnexBDi(params byte[][] unita)
    {
        var uscita = new List<byte>();
        foreach (var u in unita)
        {
            uscita.AddRange([0, 0, 0, 1]);
            uscita.AddRange(u);
        }
        return [.. uscita];
    }

    private static uint U32(byte[] file, int posizione) => BinaryPrimitives.ReadUInt32BigEndian(file.AsSpan(posizione));

    private static Scatola Figlio(byte[] file, Scatola genitore, string tipo)
    {
        // Le scatole «piene» con tabelle (stsd, dref) hanno versione e numero di voci prima dei figli: qui si cercano
        // solo i figli diretti di scatole contenitore.
        return Scatola.Leggi(file, genitore.Contenuto, genitore.Fine).Single(s => s.Tipo == tipo);
    }

    private static Scatola Trova(byte[] file, Scatola da, params string[] percorso)
    {
        var attuale = da;
        foreach (var tipo in percorso) attuale = Figlio(file, attuale, tipo);
        return attuale;
    }

    internal sealed record Scatola(string Tipo, int Inizio, int Contenuto, int Fine)
    {
        /// <summary>Tutte le scatole in [da, a), che devono riempirlo esattamente.</summary>
        public static List<Scatola> Leggi(byte[] file, int da, int a)
        {
            var scatole = LeggiFinoAlTaglio(file, da, a, out var fine);
            Assert.Equal(a, fine);
            return scatole;
        }

        /// <summary>Le scatole intere in [da, a): si ferma alla prima tagliata (un file interrotto).</summary>
        public static List<Scatola> LeggiFinoAlTaglio(byte[] file, int da, int a, out int fine)
        {
            var scatole = new List<Scatola>();
            var p = da;
            while (p + 8 <= a)
            {
                long dimensione = BinaryPrimitives.ReadUInt32BigEndian(file.AsSpan(p));
                var tipo = Encoding.ASCII.GetString(file, p + 4, 4);
                var intestazione = 8;
                if (dimensione == 1)
                {
                    if (p + 16 > a) break;
                    dimensione = (long)BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(p + 8));
                    intestazione = 16;
                }
                Assert.True(dimensione >= intestazione, $"Scatola «{tipo}» con dimensione {dimensione}");
                if (p + dimensione > a) break;
                scatole.Add(new Scatola(tipo, p, p + intestazione, (int)(p + dimensione)));
                p += (int)dimensione;
            }
            fine = p;
            return scatole;
        }
    }

    internal sealed record CampioneLetto(uint Durata, uint Dimensione, uint Flag, int Posizione);

    internal sealed record FrammentoLetto(uint Sequenza, ulong Base, uint FlagTfhd, uint FlagTrun, List<CampioneLetto> Campioni, int InizioMoof, int FineMdat);

    /// <summary>
    /// Un lettore di MP4 frammentati semplice, scritto qui apposta e indipendente dallo scrittore: le scatole in cima
    /// fino alla prima tagliata, e di ogni moof seguito da un mdat intero sequenza, tempo di partenza e campioni.
    /// </summary>
    internal static class LettoreFmp4
    {
        public static List<FrammentoLetto> Frammenti(byte[] file)
        {
            var cima = Scatola.LeggiFinoAlTaglio(file, 0, file.Length, out _);
            var frammenti = new List<FrammentoLetto>();
            for (var i = 0; i < cima.Count; i++)
            {
                if (cima[i].Tipo != "moof") continue;
                if (i + 1 >= cima.Count || cima[i + 1].Tipo != "mdat") break;
                var moof = cima[i];
                var mdat = cima[i + 1];
                var mfhd = Scatola.Leggi(file, moof.Contenuto, moof.Fine).Single(s => s.Tipo == "mfhd");
                var traf = Scatola.Leggi(file, moof.Contenuto, moof.Fine).Single(s => s.Tipo == "traf");
                var figli = Scatola.Leggi(file, traf.Contenuto, traf.Fine);
                Assert.Equal(["tfhd", "tfdt", "trun"], figli.Select(s => s.Tipo));
                var tfhd = figli[0];
                var tfdt = figli[1];
                var trun = figli[2];
                Assert.Equal(1u, U32(file, tfhd.Contenuto + 4)); // track_ID
                Assert.Equal(1, file[tfdt.Contenuto]);           // versione 1, 64 bit
                var flagTrun = U32(file, trun.Contenuto) & 0xFFFFFF;
                var quanti = (int)U32(file, trun.Contenuto + 4);
                var scostamento = (int)U32(file, trun.Contenuto + 8);
                // default-base-is-moof: i dati partono da moof + scostamento, subito dentro mdat.
                var posizione = moof.Inizio + scostamento;
                Assert.Equal(mdat.Contenuto, posizione);
                var campioni = new List<CampioneLetto>();
                var p = trun.Contenuto + 12;
                for (var c = 0; c < quanti; c++)
                {
                    var campione = new CampioneLetto(U32(file, p), U32(file, p + 4), U32(file, p + 8), posizione);
                    campioni.Add(campione);
                    posizione += (int)campione.Dimensione;
                    p += 12;
                }
                Assert.Equal(trun.Fine, p);
                // I campioni riempiono mdat esattamente.
                Assert.Equal(mdat.Fine, posizione);
                frammenti.Add(new FrammentoLetto(U32(file, mfhd.Contenuto + 4), BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(tfdt.Contenuto + 4)),
                    U32(file, tfhd.Contenuto) & 0xFFFFFF, flagTrun, campioni, moof.Inizio, mdat.Fine));
            }
            return frammenti;
        }
    }

    /// <summary>Un «disco» che si riempie dopo <c>limite</c> byte: scrive quello che ci sta, poi IOException (come Windows).</summary>
    internal sealed class FlussoCheSiRiempie(long limite, int codiceErrore = unchecked((int)0x80070070)) : MemoryStream
    {
        public override void Write(byte[] buffer, int offset, int count)
        {
            var spazio = (int)Math.Max(0, limite - Position);
            base.Write(buffer, offset, Math.Min(spazio, count));
            if (count > spazio) throw new IOException("Spazio insufficiente sul disco.", codiceErrore);
        }

        public override void Write(ReadOnlySpan<byte> buffer) => Write(buffer.ToArray(), 0, buffer.Length);
    }
}
