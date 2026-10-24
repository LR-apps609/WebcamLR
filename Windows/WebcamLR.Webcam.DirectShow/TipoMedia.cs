using System.Runtime.InteropServices;

namespace WebcamLR.Webcam.DirectShow;

/// <summary>
/// AM_MEDIA_TYPE dei nostri formati: creati, copiati, letti e liberati come fanno CreateMediaType/FreeMediaType delle
/// classi base di DirectShow (struttura e blocco del formato con CoTaskMemAlloc: l'app li libera con CoTaskMemFree).
/// </summary>
internal static unsafe class TipoMedia
{
    /// <summary>Riempie una struttura dell'app (ConnectionMediaType, IEnumMediaTypes) con un formato nostro.</summary>
    public static void Riempi(AM_MEDIA_TYPE* tipo, FormatoDirectShow formato)
    {
        var blocco = (byte*)Marshal.AllocCoTaskMem(StruttureDirectShow.DimensioneVideoInfoHeader);
        StruttureDirectShow.ScriviVideoInfoHeader(new Span<byte>(blocco, StruttureDirectShow.DimensioneVideoInfoHeader), formato);
        *tipo = new AM_MEDIA_TYPE
        {
            majortype = GuidDirectShow.MEDIATYPE_Video,
            subtype = formato.Sottotipo,
            bFixedSizeSamples = 1,
            bTemporalCompression = 0,
            lSampleSize = (uint)formato.ByteImmagine,
            formattype = GuidDirectShow.FORMAT_VideoInfo,
            pUnk = 0,
            cbFormat = StruttureDirectShow.DimensioneVideoInfoHeader,
            pbFormat = (nint)blocco,
        };
    }

    /// <summary>Un AM_MEDIA_TYPE nuovo (GetFormat, GetStreamCaps, IEnumMediaTypes::Next): l'app lo libera con DeleteMediaType.</summary>
    public static AM_MEDIA_TYPE* Crea(FormatoDirectShow formato)
    {
        var tipo = (AM_MEDIA_TYPE*)Marshal.AllocCoTaskMem(sizeof(AM_MEDIA_TYPE));
        Riempi(tipo, formato);
        return tipo;
    }

    /// <summary>FreeMediaType: il blocco del formato e l'eventuale pUnk; la struttura resta all'app.</summary>
    public static void LiberaContenuto(AM_MEDIA_TYPE* tipo)
    {
        if (tipo == null) return;
        if (tipo->pbFormat != 0) Marshal.FreeCoTaskMem(tipo->pbFormat);
        tipo->pbFormat = 0;
        tipo->cbFormat = 0;
        if (tipo->pUnk != 0) Marshal.Release(tipo->pUnk);
        tipo->pUnk = 0;
    }

    /// <summary>DeleteMediaType: contenuto e struttura (per i tipi dati da un'app, come IMediaSample::GetMediaType).</summary>
    public static void Elimina(AM_MEDIA_TYPE* tipo)
    {
        if (tipo == null) return;
        LiberaContenuto(tipo);
        Marshal.FreeCoTaskMem((nint)tipo);
    }

    /// <summary>
    /// Cosa chiede un'app con un AM_MEDIA_TYPE, anche incompleto: tipo principale, sottotipo e formato possono essere
    /// GUID_NULL («qualsiasi»). Restituisce il sottotipo (Guid.Empty se qualsiasi) e, se c'è un blocco VIDEOINFOHEADER o
    /// VIDEOINFOHEADER2, le misure. Falso se non è video o se il blocco non si capisce.
    /// </summary>
    public static bool Leggi(AM_MEDIA_TYPE* tipo, out Guid sottotipo, out InfoVideo? info)
    {
        sottotipo = Guid.Empty;
        info = null;
        if (tipo == null) return true;
        if (tipo->majortype != Guid.Empty && tipo->majortype != GuidDirectShow.MEDIATYPE_Video) return false;
        sottotipo = tipo->subtype;
        if (tipo->formattype == Guid.Empty || tipo->pbFormat == 0 || tipo->cbFormat == 0) return true;
        var versione2 = tipo->formattype == GuidDirectShow.FORMAT_VideoInfo2;
        if (!versione2 && tipo->formattype != GuidDirectShow.FORMAT_VideoInfo) return false;
        info = StruttureDirectShow.LeggiInfoVideo(new ReadOnlySpan<byte>((byte*)tipo->pbFormat, (int)Math.Min(tipo->cbFormat, 4096)), versione2);
        return info is not null;
    }

    /// <summary>I nostri formati compatibili con quello chiesto (anche incompleto), nell'ordine di FormatiDirectShow.</summary>
    public static IEnumerable<FormatoDirectShow> Compatibili(AM_MEDIA_TYPE* tipo)
    {
        if (!Leggi(tipo, out var sottotipo, out var info)) return [];
        return FormatiDirectShow.Tutti.Where(f =>
            (sottotipo == Guid.Empty || f.Sottotipo == sottotipo)
            && (info is not { } i || (i.Larghezza == f.Larghezza && Math.Abs(i.Altezza) == f.Altezza
                && (i.Durata100ns <= 0 || FormatiDirectShow.Trova(f.Sottotipo, f.Larghezza, f.Altezza, i.Durata100ns) == f))));
    }

    /// <summary>
    /// Il passo (byte per riga) di un tipo proposto da un renderer per lo stesso formato, con righe più larghe;
    /// 0 se il tipo non è quello. Serve quando l'app collega la webcam direttamente al renderer video (AMCap, GraphEdit).
    /// </summary>
    public static int PassoProposto(AM_MEDIA_TYPE* tipo, FormatoDirectShow formato)
    {
        if (!Leggi(tipo, out var sottotipo, out var info) || info is not { } i) return 0;
        if (sottotipo != formato.Sottotipo || Math.Abs(i.Altezza) != formato.Altezza || i.Larghezza < formato.Larghezza) return 0;
        if (formato.Codifica == CodificaDirectShow.Rgb24 && i.Altezza < 0) return 0; // dall'alto: non lo scriviamo così
        return FormatoDirectShow.PassoPer(formato.Codifica, i.Larghezza);
    }
}
