using System.Buffers.Binary;
using System.Text;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Il file MP4 della registrazione (P18) scatola per scatola. I parametri del codec sono quelli veri di due video
/// di prova (H.264 High 720p e HEVC Main 1080p): i record avcC e hvcC attesi sono quelli che scrive ffmpeg con gli
/// stessi parametri (provato a mano con ffprobe e ffmpeg: file leggibile, durata giusta, ricerca a metà).
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

    // ── Il file ────────────────────────────────────────────────────

    [Fact]
    public void FileH264ScatolaPerScatola()
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.H264, 1280, 720, new DateTime(2026, 10, 24, 12, 0, 0, DateTimeKind.Utc));
        // Prima del primo fotogramma chiave non si scrive nulla.
        Assert.Equal(EsitoCampione.InAttesaDiChiave, scrittore.Aggiungi(AnnexBDi([0x41, 9, 9]), false, 1_000));
        Assert.Equal(0, flusso.Length);

        var fotogrammi = new List<(byte[] Dati, bool Chiave, ulong Tempo)>();
        for (var i = 0; i < 90; i++)
        {
            var chiave = i % 30 == 0;
            // Delimitatore e parametri nei fotogrammi chiave: nel file non devono finire nei campioni.
            var dati = chiave
                ? AnnexBDi([0x09, 0xF0], SpsH264, PpsH264, [0x65, (byte)i, 0, 0, 3, 1])
                : AnnexBDi([0x09, 0xF0], [0x41, (byte)i, 7]);
            fotogrammi.Add((dati, chiave, 5_000_000 + (ulong)i * 33_333));
        }
        foreach (var (dati, chiave, tempo) in fotogrammi) Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(dati, chiave, tempo));
        scrittore.Concludi();

        var file = flusso.ToArray();
        Assert.Equal(file.Length, scrittore.Byte);
        var radice = Scatola.Leggi(file, 0, file.Length);
        Assert.Equal(["ftyp", "mdat", "moov"], radice.Select(s => s.Tipo));
        Assert.Equal("isom", Encoding.ASCII.GetString(file, 8, 4));

        // mdat con dimensione a 64 bit sistemata alla fine.
        var mdat = radice[1];
        Assert.Equal(1u, BinaryPrimitives.ReadUInt32BigEndian(file.AsSpan(mdat.Inizio)));
        Assert.Equal(mdat.Fine - mdat.Inizio, (long)BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(mdat.Inizio + 8)));

        var stbl = Trova(file, radice[2], "trak", "mdia", "minf", "stbl");
        var stsd = Figlio(file, stbl, "stsd");
        var avc1 = Scatola.Leggi(file, stsd.Contenuto + 8, stsd.Fine).Single();
        Assert.Equal("avc1", avc1.Tipo);
        Assert.Equal((1280, 720), (BinaryPrimitives.ReadUInt16BigEndian(file.AsSpan(avc1.Contenuto + 24)), BinaryPrimitives.ReadUInt16BigEndian(file.AsSpan(avc1.Contenuto + 26))));
        var avcC = Scatola.Leggi(file, avc1.Contenuto + 78, avc1.Fine).First();
        Assert.Equal("avcC", avcC.Tipo);
        Assert.Equal(AvcCAtteso, Convert.ToHexString(file, avcC.Contenuto, avcC.Fine - avcC.Contenuto).ToLowerInvariant());

        // 90 campioni da 3000 (33,333 ms a 90 kHz): un'unica corsa, a parte gli arrotondamenti.
        var stts = Figlio(file, stbl, "stts");
        var corse = Interi(file, stts.Contenuto + 4);
        var totale = 0u;
        for (var i = 0; i < corse; i++) totale += U32(file, stts.Contenuto + 8 + i * 8);
        Assert.Equal(90u, totale);
        Assert.InRange(scrittore.Durata.TotalSeconds, 2.99, 3.01);

        // Chiave ogni 30: campioni 1, 31, 61.
        var stss = Figlio(file, stbl, "stss");
        Assert.Equal(3u, U32(file, stss.Contenuto + 4));
        Assert.Equal([1u, 31u, 61u], Enumerable.Range(0, 3).Select(i => U32(file, stss.Contenuto + 8 + i * 4)));

        // Ogni campione al suo posto: lunghezza su 4 byte e poi la fetta, senza delimitatore né parametri.
        var stsz = Figlio(file, stbl, "stsz");
        var stco = Figlio(file, stbl, "stco");
        Assert.Equal(90u, U32(file, stsz.Contenuto + 8));
        Assert.Equal(90u, U32(file, stco.Contenuto + 4));
        for (var i = 0; i < 90; i++)
        {
            var dimensione = U32(file, stsz.Contenuto + 12 + i * 4);
            var posizione = (int)U32(file, stco.Contenuto + 8 + i * 4);
            var chiave = i % 30 == 0;
            Assert.Equal(chiave ? 10u : 7u, dimensione);
            Assert.Equal(dimensione - 4, U32(file, posizione));
            Assert.Equal(chiave ? 0x65 : 0x41, file[posizione + 4]);
            Assert.Equal((byte)i, file[posizione + 5]);
            Assert.True(posizione >= mdat.Inizio + 16 && posizione + dimensione <= mdat.Fine);
        }

        // Una sola traccia video, 3 secondi nel filmato (scala 1000).
        var mvhd = Figlio(file, radice[2], "mvhd");
        Assert.Equal(1, file[mvhd.Contenuto]);
        Assert.Equal(1000u, U32(file, mvhd.Contenuto + 20));
        Assert.InRange(BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(mvhd.Contenuto + 24)), 2990ul, 3010ul);
        var hdlr = Trova(file, radice[2], "trak", "mdia", "hdlr");
        Assert.Equal("vide", Encoding.ASCII.GetString(file, hdlr.Contenuto + 8, 4));
    }

    [Fact]
    public void FileHevcConHvcC()
    {
        var flusso = new MemoryStream();
        var scrittore = new ScrittoreMp4(flusso, Codec.Hevc, 1920, 1080, DateTime.UtcNow);
        Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(AnnexBDi([0x46, 0x01, 0x50], VpsHevc, SpsHevc, PpsHevc, [0x26, 0x01, 0xAF]), true, 0));
        Assert.Equal(EsitoCampione.Scritto, scrittore.Aggiungi(AnnexBDi([0x02, 0x01, 0xD0]), false, 33_333));
        scrittore.Concludi();
        var file = flusso.ToArray();
        var radice = Scatola.Leggi(file, 0, file.Length);
        var stsd = Trova(file, radice[2], "trak", "mdia", "minf", "stbl", "stsd");
        var hvc1 = Scatola.Leggi(file, stsd.Contenuto + 8, stsd.Fine).Single();
        Assert.Equal("hvc1", hvc1.Tipo);
        var hvcC = Scatola.Leggi(file, hvc1.Contenuto + 78, hvc1.Fine).First();
        Assert.Equal("hvcC", hvcC.Tipo);
        Assert.Equal(HvcCAtteso, Convert.ToHexString(file, hvcC.Contenuto, hvcC.Fine - hvcC.Contenuto).ToLowerInvariant());
        var stsz = Trova(file, radice[2], "trak", "mdia", "minf", "stbl", "stsz");
        // Il delimitatore HEVC (tipo 35) e i parametri non sono nel campione: solo la fetta, 4 + 3 byte.
        Assert.Equal(7u, U32(file, stsz.Contenuto + 12));
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
        var file = flusso.ToArray();
        var stts = Trova(file, Scatola.Leggi(file, 0, file.Length)[2], "trak", "mdia", "minf", "stbl", "stts");
        var durate = new List<uint>();
        var corse = Interi(file, stts.Contenuto + 4);
        for (var i = 0; i < corse; i++)
            durate.AddRange(Enumerable.Repeat(U32(file, stts.Contenuto + 12 + i * 8), (int)U32(file, stts.Contenuto + 8 + i * 8)));
        Assert.Equal([1500u, 1u, 1u, 1u], durate);
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

    private static int Interi(byte[] file, int posizione) => (int)U32(file, posizione);

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

    private sealed record Scatola(string Tipo, int Inizio, int Contenuto, int Fine)
    {
        public static List<Scatola> Leggi(byte[] file, int da, int a)
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
                    dimensione = (long)BinaryPrimitives.ReadUInt64BigEndian(file.AsSpan(p + 8));
                    intestazione = 16;
                }
                Assert.True(dimensione >= intestazione && p + dimensione <= a, $"Scatola «{tipo}» fuori misura");
                scatole.Add(new Scatola(tipo, p, p + intestazione, (int)(p + dimensione)));
                p += (int)dimensione;
            }
            Assert.Equal(a, p);
            return scatole;
        }
    }
}
