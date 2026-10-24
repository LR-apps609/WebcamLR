using System.Buffers.Binary;

namespace WebcamLR.Webcam;

/// <summary>Come sono fatti i pixel di un formato del filtro DirectShow (Windows 10).</summary>
public enum CodificaDirectShow
{
    /// <summary>4:2:2 a pacchetti (Y0 U Y1 V): il formato che quasi tutte le app DirectShow accettano.</summary>
    Yuy2,
    /// <summary>Lo stesso formato della memoria condivisa: si copia e basta.</summary>
    Nv12,
    /// <summary>B, G, R per pixel, righe dal basso verso l'alto come una bitmap di Windows: per le app vecchie.</summary>
    Rgb24,
}

/// <summary>Un formato offerto dal filtro DirectShow: misura, frequenza e codifica.</summary>
public readonly record struct FormatoDirectShow(int Larghezza, int Altezza, int Fps, CodificaDirectShow Codifica)
{
    public int BitPerPixel => Codifica switch { CodificaDirectShow.Yuy2 => 16, CodificaDirectShow.Nv12 => 12, _ => 24 };

    /// <summary>Byte per riga senza margini aggiunti dall'app che riceve. RGB24 come le bitmap: multiplo di 4.</summary>
    public int BytePerRiga => PassoPer(Codifica, Larghezza);

    public int ByteImmagine => Codifica == CodificaDirectShow.Nv12 ? Larghezza * Altezza * 3 / 2 : BytePerRiga * Altezza;

    /// <summary>biCompression della BITMAPINFOHEADER: il FOURCC per YUY2 e NV12, BI_RGB (0) per RGB24.</summary>
    public uint FourCC => Codifica switch
    {
        CodificaDirectShow.Yuy2 => 0x32595559, // «YUY2»
        CodificaDirectShow.Nv12 => 0x3231564E, // «NV12»
        _ => 0,
    };

    public Guid Sottotipo => Codifica switch
    {
        CodificaDirectShow.Yuy2 => GuidDirectShow.MEDIASUBTYPE_YUY2,
        CodificaDirectShow.Nv12 => GuidDirectShow.MEDIASUBTYPE_NV12,
        _ => GuidDirectShow.MEDIASUBTYPE_RGB24,
    };

    /// <summary>AvgTimePerFrame: la durata di un fotogramma in unità da 100 ns.</summary>
    public long Durata100ns => 10_000_000L / Fps;

    public long BitAlSecondo => (long)ByteImmagine * 8 * Fps;

    /// <summary>Il formato della memoria condivisa da chiedere all'app: stessa misura e frequenza, sempre NV12.</summary>
    public FormatoWebcam Anello => new(Larghezza, Altezza, Fps);

    /// <summary>Byte per riga di una codifica per una larghezza data (anche quella, più grande, chiesta da un renderer).</summary>
    public static int PassoPer(CodificaDirectShow codifica, int larghezza) => codifica switch
    {
        CodificaDirectShow.Yuy2 => larghezza * 2,
        CodificaDirectShow.Nv12 => larghezza,
        _ => (larghezza * 3 + 3) & ~3,
    };

    public override string ToString() => $"{Larghezza}×{Altezza} a {Fps} fps {Codifica.ToString().ToUpperInvariant()}";
}

/// <summary>
/// I formati del filtro DirectShow, nell'ordine in cui li vedono le app. Il primo è quello predefinito: 1280×720 a
/// 30 fps, leggero da convertire anche su un PC vecchio (Windows 10); Zoom, Meet e OBS scelgono comunque da sé.
/// Per ogni misura prima YUY2 (lo accettano tutte le app DirectShow), poi NV12 (nessuna conversione), poi RGB24.
/// Tutte le misure sono anche in <see cref="FormatiWebcam.Tutti"/>, così l'app scrive già la misura giusta.
/// Niente 4K: le app DirectShow non lo chiedono e ogni app che usa la webcam converte per conto suo.
/// </summary>
public static class FormatiDirectShow
{
    private static readonly (int Larghezza, int Altezza, int Fps)[] Misure =
    [
        (1280, 720, 30),
        (1920, 1080, 30),
        (960, 540, 30),
        (640, 360, 30),
        (1280, 720, 60),
        (1920, 1080, 60),
    ];

    private static readonly CodificaDirectShow[] Codifiche = [CodificaDirectShow.Yuy2, CodificaDirectShow.Nv12, CodificaDirectShow.Rgb24];

    public static readonly IReadOnlyList<FormatoDirectShow> Tutti =
        Misure.SelectMany(m => Codifiche.Select(c => new FormatoDirectShow(m.Larghezza, m.Altezza, m.Fps, c))).ToArray();

    public static FormatoDirectShow Predefinito => Tutti[0];

    /// <summary>Il più grande, per preparare una volta sola lo spazio di conversione.</summary>
    public static int ByteMassimi { get; } = Tutti.Max(f => f.ByteImmagine);

    /// <summary>
    /// Il formato chiesto da un'app (sottotipo, misura e AvgTimePerFrame di un AM_MEDIA_TYPE). Sottotipo vuoto
    /// (Guid.Empty) o durata 0 vogliono dire «qualsiasi». L'altezza può essere negativa (RGB dall'alto in basso):
    /// conta la misura. Null se non è uno dei nostri.
    /// </summary>
    public static FormatoDirectShow? Trova(Guid sottotipo, int larghezza, int altezza, long durata100ns)
    {
        altezza = Math.Abs(altezza);
        var fps = durata100ns > 0 ? (int)Math.Round(10_000_000.0 / durata100ns) : 0;
        foreach (var formato in Tutti)
        {
            if (sottotipo != Guid.Empty && formato.Sottotipo != sottotipo) continue;
            if (formato.Larghezza != larghezza || formato.Altezza != altezza) continue;
            if (fps != 0 && formato.Fps != fps) continue;
            return formato;
        }
        return null;
    }

    public static CodificaDirectShow? CodificaDi(Guid sottotipo) =>
        sottotipo == GuidDirectShow.MEDIASUBTYPE_YUY2 ? CodificaDirectShow.Yuy2
        : sottotipo == GuidDirectShow.MEDIASUBTYPE_NV12 ? CodificaDirectShow.Nv12
        : sottotipo == GuidDirectShow.MEDIASUBTYPE_RGB24 ? CodificaDirectShow.Rgb24
        : null;
}

/// <summary>I GUID di DirectShow che servono (uuids.h dell'SDK di Windows; verificati con quelli di mingw-w64).</summary>
public static class GuidDirectShow
{
    public static readonly Guid MEDIATYPE_Video = new("73646976-0000-0010-8000-00aa00389b71");
    public static readonly Guid MEDIASUBTYPE_YUY2 = new("32595559-0000-0010-8000-00aa00389b71");
    public static readonly Guid MEDIASUBTYPE_NV12 = new("3231564e-0000-0010-8000-00aa00389b71");
    public static readonly Guid MEDIASUBTYPE_RGB24 = new("e436eb7d-524f-11ce-9f53-0020af0ba770");
    public static readonly Guid FORMAT_VideoInfo = new("05589f80-c356-11ce-bf01-00aa0055595a");
    public static readonly Guid FORMAT_VideoInfo2 = new("f72a76a0-eb0a-11d0-ace4-0000c0cc16ba");
    public static readonly Guid CLSID_VideoInputDeviceCategory = new("860bb310-5d01-11d0-bd3b-00a0c911ce86");
    public static readonly Guid CLSID_FilterMapper2 = new("cda42200-bd88-11d0-bd4e-00a0c911ce86");
    public static readonly Guid CLSID_MemoryAllocator = new("1e651cc0-b199-11d0-8212-00c04fc32c45");
    public static readonly Guid AMPROPSETID_Pin = new("9b00f101-1567-11d1-b3f1-00aa003761c5");
    public static readonly Guid PIN_CATEGORY_CAPTURE = new("fb6c4281-0353-11d1-905f-0000c0cc16ba");
}

/// <summary>Le misure lette dal blocco di formato di un tipo (VIDEOINFOHEADER o VIDEOINFOHEADER2).</summary>
public readonly record struct InfoVideo(int Larghezza, int Altezza, short BitPerPixel, uint Compressione, long Durata100ns, uint ByteImmagine);

/// <summary>
/// Le strutture di DirectShow che passano come byte, scritte e lette qui per poterle provare anche su Linux.
/// <code>
/// VIDEOINFOHEADER (88 byte, amvideo.h):  0 RECT rcSource · 16 RECT rcTarget · 32 dwBitRate · 36 dwBitErrorRate
///                                        40 AvgTimePerFrame (i64) · 48 BITMAPINFOHEADER (40 byte)
/// VIDEOINFOHEADER2: bmiHeader a 72 (dopo dwInterlaceFlags, dwCopyProtectFlags, rapporto X e Y, dwControlFlags, dwReserved2)
/// BITMAPINFOHEADER: 0 biSize · 4 biWidth · 8 biHeight · 12 biPlanes (u16) · 14 biBitCount (u16) · 16 biCompression
///                   20 biSizeImage · 24/28 pixel per metro · 32 biClrUsed · 36 biClrImportant
/// VIDEO_STREAM_CONFIG_CAPS (128 byte, strmif.h): 0 guid · 16 VideoStandard · 20 InputSize · 28 MinCroppingSize
///   36 MaxCroppingSize · 44 CropGranularityX/Y · 52 CropAlignX/Y · 60 MinOutputSize · 68 MaxOutputSize
///   76 OutputGranularityX/Y · 84 StretchTapsX/Y · 92 ShrinkTapsX/Y · 104 MinFrameInterval (i64, allineato a 8)
///   112 MaxFrameInterval · 120 MinBitsPerSecond · 124 MaxBitsPerSecond
/// </code>
/// </summary>
public static class StruttureDirectShow
{
    public const int DimensioneVideoInfoHeader = 88;
    public const int DimensioneCapacita = 128;
    private const int PosizioneBitmap = 48;
    private const int PosizioneBitmap2 = 72;
    private const int DimensioneBitmap = 40;

    public static void ScriviVideoInfoHeader(Span<byte> destinazione, FormatoDirectShow f)
    {
        if (destinazione.Length < DimensioneVideoInfoHeader) throw new ArgumentException("Servono 88 byte", nameof(destinazione));
        var d = destinazione[..DimensioneVideoInfoHeader];
        d.Clear();
        // rcSource e rcTarget vuoti: «tutta l'immagine», come le webcam vere.
        BinaryPrimitives.WriteUInt32LittleEndian(d[32..], (uint)Math.Min(uint.MaxValue, f.BitAlSecondo));
        BinaryPrimitives.WriteInt64LittleEndian(d[40..], f.Durata100ns);
        var b = d[PosizioneBitmap..];
        BinaryPrimitives.WriteUInt32LittleEndian(b, DimensioneBitmap);
        BinaryPrimitives.WriteInt32LittleEndian(b[4..], f.Larghezza);
        // Altezza positiva: per YUY2 e NV12 vuol dire dall'alto, per RGB24 dal basso (come lo scrive la conversione).
        BinaryPrimitives.WriteInt32LittleEndian(b[8..], f.Altezza);
        BinaryPrimitives.WriteUInt16LittleEndian(b[12..], 1);
        BinaryPrimitives.WriteUInt16LittleEndian(b[14..], (ushort)f.BitPerPixel);
        BinaryPrimitives.WriteUInt32LittleEndian(b[16..], f.FourCC);
        BinaryPrimitives.WriteUInt32LittleEndian(b[20..], (uint)f.ByteImmagine);
    }

    /// <summary>Legge un VIDEOINFOHEADER (o un VIDEOINFOHEADER2). Null se i byte sono troppo pochi.</summary>
    public static InfoVideo? LeggiInfoVideo(ReadOnlySpan<byte> formato, bool versione2)
    {
        var posizione = versione2 ? PosizioneBitmap2 : PosizioneBitmap;
        if (formato.Length < posizione + DimensioneBitmap) return null;
        var b = formato[posizione..];
        return new InfoVideo(
            BinaryPrimitives.ReadInt32LittleEndian(b[4..]),
            BinaryPrimitives.ReadInt32LittleEndian(b[8..]),
            BinaryPrimitives.ReadInt16LittleEndian(b[14..]),
            BinaryPrimitives.ReadUInt32LittleEndian(b[16..]),
            BinaryPrimitives.ReadInt64LittleEndian(formato[40..]),
            BinaryPrimitives.ReadUInt32LittleEndian(b[20..]));
    }

    /// <summary>
    /// VIDEO_STREAM_CONFIG_CAPS di un formato a misura fissa: misure minime e massime uguali, passi di 1 pixel
    /// (OBS conta le misure possibili camminando da minima a massima: un passo 0 non finirebbe mai).
    /// </summary>
    public static void ScriviCapacita(Span<byte> destinazione, FormatoDirectShow f)
    {
        if (destinazione.Length < DimensioneCapacita) throw new ArgumentException("Servono 128 byte", nameof(destinazione));
        var d = destinazione[..DimensioneCapacita];
        d.Clear();
        GuidDirectShow.FORMAT_VideoInfo.TryWriteBytes(d);
        static void Misura(Span<byte> d, int posizione, FormatoDirectShow f)
        {
            BinaryPrimitives.WriteInt32LittleEndian(d[posizione..], f.Larghezza);
            BinaryPrimitives.WriteInt32LittleEndian(d[(posizione + 4)..], f.Altezza);
        }
        Misura(d, 20, f); Misura(d, 28, f); Misura(d, 36, f);
        BinaryPrimitives.WriteInt32LittleEndian(d[44..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(d[48..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(d[52..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(d[56..], 1);
        Misura(d, 60, f); Misura(d, 68, f);
        BinaryPrimitives.WriteInt32LittleEndian(d[76..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(d[80..], 1);
        BinaryPrimitives.WriteInt64LittleEndian(d[104..], f.Durata100ns);
        BinaryPrimitives.WriteInt64LittleEndian(d[112..], f.Durata100ns);
        var bit = (int)Math.Min(int.MaxValue, f.BitAlSecondo);
        BinaryPrimitives.WriteInt32LittleEndian(d[120..], bit);
        BinaryPrimitives.WriteInt32LittleEndian(d[124..], bit);
    }
}
