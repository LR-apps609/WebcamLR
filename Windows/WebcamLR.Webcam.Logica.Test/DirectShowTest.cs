using System.Buffers.Binary;
using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

/// <summary>La parte del filtro DirectShow (Windows 10, P23) che si prova anche su Linux.</summary>
public class FormatiDirectShowTest
{
    [Fact]
    public void PrimoFormato720pYuy2A30()
    {
        Assert.Equal(new FormatoDirectShow(1280, 720, 30, CodificaDirectShow.Yuy2), FormatiDirectShow.Predefinito);
    }

    [Fact]
    public void OgniMisuraHaLeTreCodificheEdÈAncheNellAnello()
    {
        foreach (var gruppo in FormatiDirectShow.Tutti.GroupBy(f => (f.Larghezza, f.Altezza, f.Fps)))
        {
            Assert.Equal(new[] { CodificaDirectShow.Yuy2, CodificaDirectShow.Nv12, CodificaDirectShow.Rgb24 }, gruppo.Select(f => f.Codifica));
            // L'app converte già alla misura chiesta solo se la conosce (FormatiWebcam.Cerca).
            Assert.Contains(gruppo.First().Anello, FormatiWebcam.Tutti);
        }
        Assert.Contains(FormatiDirectShow.Tutti, f => f is { Larghezza: 1920, Altezza: 1080, Fps: 30 });
        Assert.Contains(FormatiDirectShow.Tutti, f => f is { Larghezza: 1280, Altezza: 720, Fps: 60 });
        Assert.Equal(FormatiDirectShow.Tutti.Count, FormatiDirectShow.Tutti.Distinct().Count());
    }

    [Theory]
    [InlineData(CodificaDirectShow.Yuy2, 1280, 720, 2560, 1843200, 16)]
    [InlineData(CodificaDirectShow.Nv12, 1280, 720, 1280, 1382400, 12)]
    [InlineData(CodificaDirectShow.Rgb24, 1920, 1080, 5760, 6220800, 24)]
    public void ByteERighe(CodificaDirectShow codifica, int l, int a, int passo, int byteImmagine, int bit)
    {
        var f = new FormatoDirectShow(l, a, 30, codifica);
        Assert.Equal(passo, f.BytePerRiga);
        Assert.Equal(byteImmagine, f.ByteImmagine);
        Assert.Equal(bit, f.BitPerPixel);
        Assert.Equal(333_333, f.Durata100ns);
    }

    [Theory]
    [InlineData(1000, 3000)]
    [InlineData(6, 20)]   // 18 byte arrotondati a 20, come le righe di una bitmap
    [InlineData(2, 8)]
    public void Rgb24HaRigheMultipleDiQuattro(int larghezza, int passo) =>
        Assert.Equal(passo, FormatoDirectShow.PassoPer(CodificaDirectShow.Rgb24, larghezza));

    [Fact]
    public void FourCCComeNelleBitmap()
    {
        Assert.Equal("YUY2", FourCC(new FormatoDirectShow(640, 360, 30, CodificaDirectShow.Yuy2).FourCC));
        Assert.Equal("NV12", FourCC(new FormatoDirectShow(640, 360, 30, CodificaDirectShow.Nv12).FourCC));
        Assert.Equal(0u, new FormatoDirectShow(640, 360, 30, CodificaDirectShow.Rgb24).FourCC);
        // I sottotipi YUV sono il FOURCC più il GUID base dei media.
        Assert.StartsWith(new FormatoDirectShow(640, 360, 30, CodificaDirectShow.Yuy2).FourCC.ToString("x8"),
            GuidDirectShow.MEDIASUBTYPE_YUY2.ToString());
        Assert.StartsWith(new FormatoDirectShow(640, 360, 30, CodificaDirectShow.Nv12).FourCC.ToString("x8"),
            GuidDirectShow.MEDIASUBTYPE_NV12.ToString());
    }

    private static string FourCC(uint valore) => new(BitConverter.GetBytes(valore).Select(b => (char)b).ToArray());

    [Fact]
    public void TrovaComeLoChiedonoLeApp()
    {
        Assert.Equal(new FormatoDirectShow(1920, 1080, 60, CodificaDirectShow.Nv12),
            FormatiDirectShow.Trova(GuidDirectShow.MEDIASUBTYPE_NV12, 1920, 1080, 166_666));
        // Sottotipo e durata vuoti: il primo con quella misura (YUY2 a 30 fps).
        Assert.Equal(new FormatoDirectShow(640, 360, 30, CodificaDirectShow.Yuy2), FormatiDirectShow.Trova(Guid.Empty, 640, 360, 0));
        // RGB dall'alto in basso (altezza negativa): conta la misura.
        Assert.Equal(CodificaDirectShow.Rgb24, FormatiDirectShow.Trova(GuidDirectShow.MEDIASUBTYPE_RGB24, 1280, -720, 333_333)?.Codifica);
        // 29,97 fps arrotonda a 30.
        Assert.NotNull(FormatiDirectShow.Trova(GuidDirectShow.MEDIASUBTYPE_YUY2, 1280, 720, 333_667));
        Assert.Null(FormatiDirectShow.Trova(GuidDirectShow.MEDIASUBTYPE_YUY2, 640, 480, 0));
        Assert.Null(FormatiDirectShow.Trova(GuidDirectShow.MEDIASUBTYPE_YUY2, 960, 540, 166_666));
        Assert.Null(FormatiDirectShow.Trova(Guid.NewGuid(), 1280, 720, 0));
    }

    [Fact]
    public void GuidComeNegliHeader()
    {
        // uuids.h: OUR_GUID_ENTRY(MEDIATYPE_Video,0x73646976,0x0000,0x0010,0x80,0x00,0x00,0xaa,0x00,0x38,0x9b,0x71)
        Assert.Equal(new Guid(0x73646976, 0x0000, 0x0010, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71), GuidDirectShow.MEDIATYPE_Video);
        Assert.Equal(new Guid(0x05589f80, 0xc356, 0x11ce, 0xbf, 0x01, 0x00, 0xaa, 0x00, 0x55, 0x59, 0x5a), GuidDirectShow.FORMAT_VideoInfo);
        Assert.Equal(new Guid(0x860BB310, 0x5D01, 0x11d0, 0xBD, 0x3B, 0x00, 0xA0, 0xC9, 0x11, 0xCE, 0x86), GuidDirectShow.CLSID_VideoInputDeviceCategory);
        Assert.Equal(new Guid(0xfb6c4281, 0x0353, 0x11d1, 0x90, 0x5f, 0x00, 0x00, 0xc0, 0xcc, 0x16, 0xba), GuidDirectShow.PIN_CATEGORY_CAPTURE);
        Assert.Equal(new Guid(0x9b00f101, 0x1567, 0x11d1, 0xb3, 0xf1, 0x0, 0xaa, 0x0, 0x37, 0x61, 0xc5), GuidDirectShow.AMPROPSETID_Pin);
        Assert.Equal(new Guid(0xe436eb7d, 0x524f, 0x11ce, 0x9f, 0x53, 0x00, 0x20, 0xaf, 0x0b, 0xa7, 0x70), GuidDirectShow.MEDIASUBTYPE_RGB24);
        Assert.Equal(new Guid(0xcda42200, 0xbd88, 0x11d0, 0xbd, 0x4e, 0x0, 0xa0, 0xc9, 0x11, 0xce, 0x86), GuidDirectShow.CLSID_FilterMapper2);
        Assert.Equal(new Guid(0x1e651cc0, 0xb199, 0x11d0, 0x82, 0x12, 0x00, 0xc0, 0x4f, 0xc3, 0x2c, 0x45), GuidDirectShow.CLSID_MemoryAllocator);
        Assert.Equal(new Guid(0xf72a76A0, 0xeb0a, 0x11d0, 0xac, 0xe4, 0x00, 0x00, 0xc0, 0xcc, 0x16, 0xba), GuidDirectShow.FORMAT_VideoInfo2);
        Assert.Equal(CodificaDirectShow.Nv12, FormatiDirectShow.CodificaDi(GuidDirectShow.MEDIASUBTYPE_NV12));
        Assert.Null(FormatiDirectShow.CodificaDi(GuidDirectShow.MEDIATYPE_Video));
    }
}

public class StruttureDirectShowTest
{
    [Fact]
    public void VideoInfoHeaderAlPostoGiusto()
    {
        var f = new FormatoDirectShow(1280, 720, 30, CodificaDirectShow.Yuy2);
        var byteVih = new byte[StruttureDirectShow.DimensioneVideoInfoHeader];
        StruttureDirectShow.ScriviVideoInfoHeader(byteVih, f);
        Assert.All(byteVih[..32], b => Assert.Equal(0, b)); // rcSource e rcTarget vuoti
        Assert.Equal((uint)(1280 * 720 * 2 * 8 * 30), BinaryPrimitives.ReadUInt32LittleEndian(byteVih.AsSpan(32)));
        Assert.Equal(333_333, BinaryPrimitives.ReadInt64LittleEndian(byteVih.AsSpan(40)));
        Assert.Equal(40u, BinaryPrimitives.ReadUInt32LittleEndian(byteVih.AsSpan(48)));  // biSize
        Assert.Equal(1280, BinaryPrimitives.ReadInt32LittleEndian(byteVih.AsSpan(52)));  // biWidth
        Assert.Equal(720, BinaryPrimitives.ReadInt32LittleEndian(byteVih.AsSpan(56)));   // biHeight
        Assert.Equal(1, BinaryPrimitives.ReadUInt16LittleEndian(byteVih.AsSpan(60)));    // biPlanes
        Assert.Equal(16, BinaryPrimitives.ReadUInt16LittleEndian(byteVih.AsSpan(62)));   // biBitCount
        Assert.Equal(0x32595559u, BinaryPrimitives.ReadUInt32LittleEndian(byteVih.AsSpan(64))); // biCompression
        Assert.Equal((uint)f.ByteImmagine, BinaryPrimitives.ReadUInt32LittleEndian(byteVih.AsSpan(68))); // biSizeImage

        var letto = StruttureDirectShow.LeggiInfoVideo(byteVih, versione2: false);
        Assert.Equal(new InfoVideo(1280, 720, 16, 0x32595559, 333_333, (uint)f.ByteImmagine), letto);
        Assert.Null(StruttureDirectShow.LeggiInfoVideo(byteVih.AsSpan(0, 60), versione2: false));
    }

    [Fact]
    public void VideoInfoHeader2HaLaBitmapA72()
    {
        var byteVih2 = new byte[112];
        BinaryPrimitives.WriteInt64LittleEndian(byteVih2.AsSpan(40), 166_666);
        BinaryPrimitives.WriteInt32LittleEndian(byteVih2.AsSpan(72 + 4), 1920);
        BinaryPrimitives.WriteInt32LittleEndian(byteVih2.AsSpan(72 + 8), 1080);
        var letto = StruttureDirectShow.LeggiInfoVideo(byteVih2, versione2: true);
        Assert.Equal(1920, letto?.Larghezza);
        Assert.Equal(1080, letto?.Altezza);
        Assert.Equal(166_666, letto?.Durata100ns);
    }

    [Fact]
    public void CapacitaAMisuraFissa()
    {
        var f = new FormatoDirectShow(1920, 1080, 60, CodificaDirectShow.Rgb24);
        var caps = new byte[StruttureDirectShow.DimensioneCapacita];
        StruttureDirectShow.ScriviCapacita(caps, f);
        Assert.Equal(GuidDirectShow.FORMAT_VideoInfo, new Guid(caps.AsSpan(0, 16)));
        foreach (var posizione in new[] { 20, 28, 36, 60, 68 }) // InputSize, cropping, MinOutputSize, MaxOutputSize
        {
            Assert.Equal(1920, BinaryPrimitives.ReadInt32LittleEndian(caps.AsSpan(posizione)));
            Assert.Equal(1080, BinaryPrimitives.ReadInt32LittleEndian(caps.AsSpan(posizione + 4)));
        }
        Assert.Equal(1, BinaryPrimitives.ReadInt32LittleEndian(caps.AsSpan(76))); // OutputGranularityX: mai 0
        Assert.Equal(1, BinaryPrimitives.ReadInt32LittleEndian(caps.AsSpan(80)));
        Assert.Equal(166_666, BinaryPrimitives.ReadInt64LittleEndian(caps.AsSpan(104))); // MinFrameInterval
        Assert.Equal(166_666, BinaryPrimitives.ReadInt64LittleEndian(caps.AsSpan(112))); // MaxFrameInterval
        // 1080p RGB24 a 60 fps fa quasi 3 Gbit/s: non sta in un LONG, si ferma al massimo invece di diventare negativo.
        Assert.Equal(int.MaxValue, BinaryPrimitives.ReadInt32LittleEndian(caps.AsSpan(120)));
        Assert.Equal(int.MaxValue, BinaryPrimitives.ReadInt32LittleEndian(caps.AsSpan(124)));
    }
}

public class ConversioneDirectShowTest
{
    /// <summary>Un NV12 4×2 con valori riconoscibili: Y 10..17, U/V 100..103.</summary>
    private static byte[] Piccolo()
    {
        var nv12 = new byte[4 * 2 * 3 / 2];
        for (var i = 0; i < 8; i++) nv12[i] = (byte)(10 + i);
        nv12[8] = 100; nv12[9] = 101; nv12[10] = 102; nv12[11] = 103;
        return nv12;
    }

    [Fact]
    public void Yuy2AlternaLuminanzaECrominanza()
    {
        var f = new FormatoDirectShow(4, 2, 30, CodificaDirectShow.Yuy2);
        var uscita = new byte[f.ByteImmagine];
        Assert.Equal(16, ConversioneDirectShow.Converti(Piccolo(), f, uscita, f.BytePerRiga));
        // Riga 0: Y0 U0 Y1 V0 Y2 U1 Y3 V1; riga 1 uguale con la sua luminanza e la stessa crominanza.
        Assert.Equal(new byte[] { 10, 100, 11, 101, 12, 102, 13, 103, 14, 100, 15, 101, 16, 102, 17, 103 }, uscita);
    }

    [Fact]
    public void Nv12ConPassoPiùLargo()
    {
        var f = new FormatoDirectShow(4, 2, 30, CodificaDirectShow.Nv12);
        var uscita = new byte[8 * 3];
        Assert.Equal(24, ConversioneDirectShow.Converti(Piccolo(), f, uscita, passo: 8));
        Assert.Equal(new byte[] { 10, 11, 12, 13, 0, 0, 0, 0, 14, 15, 16, 17, 0, 0, 0, 0, 100, 101, 102, 103, 0, 0, 0, 0 }, uscita);
        var stretto = new byte[12];
        ConversioneDirectShow.Converti(Piccolo(), f, stretto, passo: 4);
        Assert.Equal(Piccolo(), stretto);
    }

    [Theory]
    [InlineData(255, 255, 255)]
    [InlineData(0, 0, 0)]
    [InlineData(255, 0, 0)]
    [InlineData(0, 255, 0)]
    [InlineData(0, 0, 255)]
    [InlineData(0x0E, 0x1A, 0x22)] // il fondo dell'immagine di attesa
    [InlineData(0x2C, 0xC5, 0xD8)] // il ciano dello stile
    public void Rgb24TornaAiColoriDiPartenza(int r, int g, int b)
    {
        // RGB → NV12 con la conversione dell'app, poi NV12 → RGB24 con quella del filtro: al massimo 3 di differenza.
        const int l = 4, a = 2;
        var nv12 = new byte[l * a * 3 / 2];
        Array.Fill(nv12, ConversioneVideo.Luminanza(r, g, b), 0, l * a);
        for (var i = l * a; i < nv12.Length; i += 2)
        {
            nv12[i] = ConversioneVideo.Cb(r, g, b);
            nv12[i + 1] = ConversioneVideo.Cr(r, g, b);
        }
        var f = new FormatoDirectShow(l, a, 30, CodificaDirectShow.Rgb24);
        var uscita = new byte[f.ByteImmagine];
        ConversioneDirectShow.Converti(nv12, f, uscita, f.BytePerRiga);
        for (var pixel = 0; pixel < l; pixel++)
        {
            Assert.InRange(uscita[pixel * 3 + 0], b - 3, b + 3);
            Assert.InRange(uscita[pixel * 3 + 1], g - 3, g + 3);
            Assert.InRange(uscita[pixel * 3 + 2], r - 3, r + 3);
        }
    }

    [Fact]
    public void Rgb24DalBassoVersoLAlto()
    {
        // Riga di sopra bianca, riga di sotto nera: in memoria la prima riga è quella nera.
        const int l = 2, a = 2;
        var nv12 = new byte[] { 235, 235, 16, 16, 128, 128 };
        var f = new FormatoDirectShow(l, a, 30, CodificaDirectShow.Rgb24);
        var uscita = new byte[f.ByteImmagine];
        ConversioneDirectShow.Converti(nv12, f, uscita, f.BytePerRiga);
        Assert.Equal(8, f.BytePerRiga); // 6 byte arrotondati a 8
        Assert.All(uscita[..6], v => Assert.Equal(0, v));
        Assert.All(uscita[8..14], v => Assert.Equal(255, v));
        Assert.Equal(0, uscita[6]); // il margine della riga resta com'era
    }

    [Fact]
    public void FotogrammaGrandeInParalleloComeInSerie()
    {
        // 1280×720 passa da Parallel.For: deve dare gli stessi byte, riga per riga, di un calcolo a mano.
        const int l = 1280, a = 720;
        var nv12 = new byte[l * a * 3 / 2];
        new Random(7).NextBytes(nv12);
        var f = new FormatoDirectShow(l, a, 30, CodificaDirectShow.Yuy2);
        var uscita = new byte[f.ByteImmagine];
        ConversioneDirectShow.Converti(nv12, f, uscita, f.BytePerRiga);
        foreach (var y in new[] { 0, 1, 359, 718, 719 })
        {
            for (var x = 0; x < l; x += 2)
            {
                var o = y * l * 2 + x * 2;
                Assert.Equal(nv12[y * l + x], uscita[o]);
                Assert.Equal(nv12[l * a + (y / 2) * l + x], uscita[o + 1]);
                Assert.Equal(nv12[y * l + x + 1], uscita[o + 2]);
                Assert.Equal(nv12[l * a + (y / 2) * l + x + 1], uscita[o + 3]);
            }
        }
    }

    [Fact]
    public void RifiutaSpaziTroppoPiccoli()
    {
        var f = new FormatoDirectShow(4, 2, 30, CodificaDirectShow.Yuy2);
        Assert.Throws<ArgumentException>(() => ConversioneDirectShow.Converti(Piccolo(), f, new byte[15], 8));
        Assert.Throws<ArgumentException>(() => ConversioneDirectShow.Converti(Piccolo(), f, new byte[16], 7));
        Assert.Throws<ArgumentException>(() => ConversioneDirectShow.Converti(new byte[11], f, new byte[16], 8));
    }
}

public class NomiDirectShowTest
{
    [Fact]
    public void ClsidDiversoDaQuelloDellaSorgente()
    {
        Assert.True(Guid.TryParseExact(NomiWebcam.ClsidDirectShowTraGraffe, "B", out var filtro));
        Assert.NotEqual(Guid.Parse(NomiWebcam.Clsid), filtro);
        Assert.EndsWith(NomiWebcam.ClsidDirectShowTraGraffe, NomiWebcam.ChiaveIstanzaDirectShow);
        Assert.Contains(GuidDirectShow.CLSID_VideoInputDeviceCategory.ToString("B"), NomiWebcam.ChiaveIstanzaDirectShow);
        Assert.StartsWith(@"SOFTWARE\Classes\CLSID\{", NomiWebcam.ChiaveClsidDirectShow);
    }

    [Fact]
    public void AnelloLocaleNellaSessioneDellUtente()
    {
        Assert.StartsWith(@"Local\", NomiAnello.Locale.Memoria);
        Assert.StartsWith(@"Local\", NomiAnello.Locale.Evento);
        // Stesso nome dopo lo spazio: la disposizione è la stessa, cambia solo chi la crea.
        Assert.Equal(NomiAnello.Globale.Memoria[@"Global\".Length..], NomiAnello.Locale.Memoria[@"Local\".Length..]);
        Assert.Equal(NomiWebcam.NomeMemoria, NomiAnello.Globale.Memoria);
        Assert.Equal(NomiWebcam.SddlMemoria, NomiAnello.Globale.SddlMemoria);
        Assert.DoesNotContain(";LS)", NomiAnello.Locale.SddlMemoria); // niente Frame Server su Windows 10
        Assert.Contains("(A;;GA;;;IU)", NomiAnello.Locale.SddlMemoria);
        Assert.EndsWith("S:(ML;;NW;;;LW)", NomiAnello.Locale.SddlMemoria);
    }
}
