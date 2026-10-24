using System.Runtime.InteropServices;

namespace WebcamLR.Webcam.DirectShow;

/// <summary>AM_MEDIA_TYPE di strmif.h. Sequenziale con nint: la disposizione giusta sia a 64 sia a 32 bit (88 e 72 byte).</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct AM_MEDIA_TYPE
{
    public Guid majortype;
    public Guid subtype;
    public int bFixedSizeSamples;
    public int bTemporalCompression;
    public uint lSampleSize;
    public Guid formattype;
    public nint pUnk;
    public uint cbFormat;
    public nint pbFormat;
}

/// <summary>ALLOCATOR_PROPERTIES di strmif.h.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct ALLOCATOR_PROPERTIES
{
    public int cBuffers;
    public int cbBuffer;
    public int cbAlign;
    public int cbPrefix;
}

/// <summary>
/// Le chiamate agli oggetti delle app (il pin che riceve, il suo allocatore, i campioni, l'orologio del grafo):
/// direttamente dalla tabella dei metodi, con il numero preso da strmif.h (3 di IUnknown, poi i metodi nell'ordine).
/// Niente oggetti .NET intermedi: un campione restituito tardi dal finalizzatore bloccherebbe l'allocatore dell'app.
/// </summary>
internal static unsafe class ComNativo
{
    public const int S_OK = 0;
    public const int S_FALSE = 1;
    public const int E_NOTIMPL = unchecked((int)0x80004001);
    public const int E_NOINTERFACE = unchecked((int)0x80004002);
    public const int E_POINTER = unchecked((int)0x80004003);
    public const int E_FAIL = unchecked((int)0x80004005);
    public const int E_UNEXPECTED = unchecked((int)0x8000FFFF);
    public const int E_INVALIDARG = unchecked((int)0x80070057);
    public const int E_OUTOFMEMORY = unchecked((int)0x8007000E);
    public const int VFW_S_CANT_CUE = 0x00040268;
    public const int VFW_E_INVALIDMEDIATYPE = unchecked((int)0x80040200);
    public const int VFW_E_ALREADY_CONNECTED = unchecked((int)0x80040204);
    public const int VFW_E_NO_ACCEPTABLE_TYPES = unchecked((int)0x80040207);
    public const int VFW_E_NOT_CONNECTED = unchecked((int)0x80040209);
    public const int VFW_E_NO_ALLOCATOR = unchecked((int)0x8004020A);
    public const int VFW_E_NOT_FOUND = unchecked((int)0x80040216);
    public const int VFW_E_NOT_STOPPED = unchecked((int)0x80040224);
    public const int E_PROP_ID_UNSUPPORTED = unchecked((int)0x80070490);
    public const int E_PROP_SET_UNSUPPORTED = unchecked((int)0x80070492);

    public const int State_Stopped = 0, State_Paused = 1, State_Running = 2;
    public const int PINDIR_OUTPUT = 1;
    public const uint AM_FILTER_MISC_FLAGS_IS_SOURCE = 0x2;
    public const uint KSPROPERTY_SUPPORT_GET = 1;
    public const uint AMPROPERTY_PIN_CATEGORY = 0;

    public static readonly Guid IID_IPin = new("56a86891-0ad4-11ce-b03a-0020af0ba770");
    public static readonly Guid IID_IMemInputPin = new("56a8689d-0ad4-11ce-b03a-0020af0ba770");
    public static readonly Guid IID_IMemAllocator = new("56a8689c-0ad4-11ce-b03a-0020af0ba770");

    private static nint Metodo(nint oggetto, int indice) => (*(nint**)oggetto)[indice];

    // ── IPin (strmif.h: Connect 3, ReceiveConnection 4, Disconnect 5, …, QueryAccept 11) ──
    public static int PinReceiveConnection(nint pin, nint connettore, AM_MEDIA_TYPE* tipo) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, AM_MEDIA_TYPE*, int>)Metodo(pin, 4))(pin, connettore, tipo);
    public static int PinDisconnect(nint pin) => ((delegate* unmanaged[Stdcall]<nint, int>)Metodo(pin, 5))(pin);
    public static int PinQueryAccept(nint pin, AM_MEDIA_TYPE* tipo) =>
        ((delegate* unmanaged[Stdcall]<nint, AM_MEDIA_TYPE*, int>)Metodo(pin, 11))(pin, tipo);

    // ── IMemInputPin (GetAllocator 3, NotifyAllocator 4, GetAllocatorRequirements 5, Receive 6) ──
    public static int MemGetAllocator(nint pin, out nint allocatore)
    {
        nint a = 0;
        var hr = ((delegate* unmanaged[Stdcall]<nint, nint*, int>)Metodo(pin, 3))(pin, &a);
        allocatore = hr >= 0 ? a : 0;
        return hr;
    }
    public static int MemNotifyAllocator(nint pin, nint allocatore, bool soloLettura) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, int, int>)Metodo(pin, 4))(pin, allocatore, soloLettura ? 1 : 0);
    public static int MemGetAllocatorRequirements(nint pin, ALLOCATOR_PROPERTIES* proprieta) =>
        ((delegate* unmanaged[Stdcall]<nint, ALLOCATOR_PROPERTIES*, int>)Metodo(pin, 5))(pin, proprieta);
    public static int MemReceive(nint pin, nint campione) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, int>)Metodo(pin, 6))(pin, campione);

    // ── IMemAllocator (SetProperties 3, GetProperties 4, Commit 5, Decommit 6, GetBuffer 7) ──
    public static int AllocSetProperties(nint allocatore, ALLOCATOR_PROPERTIES* richiesta, ALLOCATOR_PROPERTIES* ottenuta) =>
        ((delegate* unmanaged[Stdcall]<nint, ALLOCATOR_PROPERTIES*, ALLOCATOR_PROPERTIES*, int>)Metodo(allocatore, 3))(allocatore, richiesta, ottenuta);
    public static int AllocCommit(nint allocatore) => ((delegate* unmanaged[Stdcall]<nint, int>)Metodo(allocatore, 5))(allocatore);
    public static int AllocDecommit(nint allocatore) => ((delegate* unmanaged[Stdcall]<nint, int>)Metodo(allocatore, 6))(allocatore);
    public static int AllocGetBuffer(nint allocatore, out nint campione)
    {
        nint c = 0;
        var hr = ((delegate* unmanaged[Stdcall]<nint, nint*, long*, long*, uint, int>)Metodo(allocatore, 7))(allocatore, &c, null, null, 0);
        campione = hr >= 0 ? c : 0;
        return hr;
    }

    // ── IMediaSample (GetPointer 3, GetSize 4, SetTime 6, SetSyncPoint 8, SetActualDataLength 12,
    //    GetMediaType 13, SetDiscontinuity 16) ──
    public static int SampleGetPointer(nint campione, out byte* dati)
    {
        byte* p = null;
        var hr = ((delegate* unmanaged[Stdcall]<nint, byte**, int>)Metodo(campione, 3))(campione, &p);
        dati = p;
        return hr;
    }
    /// <summary>Restituisce un LONG (i byte del buffer), non un HRESULT.</summary>
    public static int SampleGetSize(nint campione) => ((delegate* unmanaged[Stdcall]<nint, int>)Metodo(campione, 4))(campione);
    public static int SampleSetTime(nint campione, long* inizio, long* fine) =>
        ((delegate* unmanaged[Stdcall]<nint, long*, long*, int>)Metodo(campione, 6))(campione, inizio, fine);
    public static int SampleSetSyncPoint(nint campione, bool vero) =>
        ((delegate* unmanaged[Stdcall]<nint, int, int>)Metodo(campione, 8))(campione, vero ? 1 : 0);
    public static int SampleSetActualDataLength(nint campione, int lunghezza) =>
        ((delegate* unmanaged[Stdcall]<nint, int, int>)Metodo(campione, 12))(campione, lunghezza);
    public static int SampleGetMediaType(nint campione, out AM_MEDIA_TYPE* tipo)
    {
        AM_MEDIA_TYPE* t = null;
        var hr = ((delegate* unmanaged[Stdcall]<nint, AM_MEDIA_TYPE**, int>)Metodo(campione, 13))(campione, &t);
        tipo = hr == S_OK ? t : null;
        return hr;
    }
    public static int SampleSetDiscontinuity(nint campione, bool vero) =>
        ((delegate* unmanaged[Stdcall]<nint, int, int>)Metodo(campione, 16))(campione, vero ? 1 : 0);

    // ── IReferenceClock (GetTime 3) ──
    public static int ClockGetTime(nint orologio, out long tempo)
    {
        long t = 0;
        var hr = ((delegate* unmanaged[Stdcall]<nint, long*, int>)Metodo(orologio, 3))(orologio, &t);
        tempo = t;
        return hr;
    }

    // ── IFilterGraph (Reconnect 8) ──
    public static int GraphReconnect(nint grafo, nint pin) => ((delegate* unmanaged[Stdcall]<nint, nint, int>)Metodo(grafo, 8))(grafo, pin);

    public static nint QueryInterface(nint oggetto, Guid iid)
    {
        return Marshal.QueryInterface(oggetto, ref iid, out var risultato) >= 0 ? risultato : 0;
    }

    public static void Libera(ref nint oggetto)
    {
        var vecchio = oggetto;
        oggetto = 0;
        if (vecchio != 0) Marshal.Release(vecchio);
    }

    public static nint CreaAllocatore()
    {
        var clsid = GuidDirectShow.CLSID_MemoryAllocator;
        var iid = IID_IMemAllocator;
        return CoCreateInstance(ref clsid, 0, CLSCTX_INPROC_SERVER, ref iid, out var allocatore) >= 0 ? allocatore : 0;
    }

    private const uint CLSCTX_INPROC_SERVER = 0x1;

    [DllImport("ole32.dll")]
    private static extern int CoCreateInstance(ref Guid clsid, nint esterno, uint contesto, ref Guid iid, out nint oggetto);
}
