using System.Runtime.InteropServices;

namespace WebcamLR.Webcam;

/// <summary>Funzioni di mfplat.dll, GUID e costanti dagli header di Media Foundation.</summary>
internal static class FunzioniMF
{
    public const int S_OK = 0;
    public const int E_NOTIMPL = unchecked((int)0x80004001);
    public const int E_NOINTERFACE = unchecked((int)0x80004002);
    public const int E_POINTER = unchecked((int)0x80004003);
    public const int E_FAIL = unchecked((int)0x80004005);
    public const int E_INVALIDARG = unchecked((int)0x80070057);
    public const int MF_E_INVALIDREQUEST = unchecked((int)0xC00D36B2);
    public const int MF_E_INVALIDSTREAMNUMBER = unchecked((int)0xC00D36B3);
    public const int MF_E_INVALIDMEDIATYPE = unchecked((int)0xC00D36B4);
    public const int MF_E_UNSUPPORTED_SERVICE = unchecked((int)0xC00D36BA);
    public const int MF_E_UNSUPPORTED_TIME_FORMAT = unchecked((int)0xC00D36C5);
    public const int MF_E_INVALID_STATE_TRANSITION = unchecked((int)0xC00D3E82);
    public const int MF_E_SHUTDOWN = unchecked((int)0xC00D3E85);
    /// <summary>HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND): la risposta di IKsControl per «nessuna proprietà».</summary>
    public const int HRESULT_ERROR_SET_NOT_FOUND = unchecked((int)0x80070492);

    public const uint MF_VERSION = 0x00020070;
    public const uint MFSTARTUP_LITE = 1;
    public const uint MFMEDIASOURCE_IS_LIVE = 0x1;

    // MediaEventType (mfobjects.h)
    public const uint MESourceStarted = 201;
    public const uint MEStreamStarted = 202;
    public const uint MENewStream = 205;
    public const uint MEUpdatedStream = 206;
    public const uint MESourceStopped = 207;
    public const uint MEStreamStopped = 208;
    public const uint MESourcePaused = 209;
    public const uint MEStreamPaused = 210;
    public const uint MEMediaSample = 213;

    // MF_STREAM_STATE (mfidl.h)
    public const int MF_STREAM_STATE_STOPPED = 0;
    public const int MF_STREAM_STATE_PAUSED = 1;
    public const int MF_STREAM_STATE_RUNNING = 2;

    public const uint MFVideoInterlace_Progressive = 2;
    public const uint MFVideoTransferMatrix_BT709 = 1;
    public const uint MFNominalRange_16_235 = 2;
    public const uint MFVideoPrimaries_BT709 = 2;
    public const uint MFVideoTransFunc_709 = 5;
    public const uint MFFrameSourceTypes_Color = 0x0001;

    public static Guid GUID_NULL = Guid.Empty;
    public static Guid MFMediaType_Video = new("73646976-0000-0010-8000-00AA00389B71");
    public static Guid MFVideoFormat_NV12 = new("3231564E-0000-0010-8000-00AA00389B71");

    public static Guid MF_MT_MAJOR_TYPE = new("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    public static Guid MF_MT_SUBTYPE = new("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    public static Guid MF_MT_FRAME_SIZE = new("1652c33d-d6b2-4012-b834-72030849a37d");
    public static Guid MF_MT_FRAME_RATE = new("c459a2e8-3d2c-4e44-b132-fee5156c7bb0");
    public static Guid MF_MT_FRAME_RATE_RANGE_MAX = new("e3371d41-b4cf-4a05-bd4e-20b88bb2c4d6");
    public static Guid MF_MT_FRAME_RATE_RANGE_MIN = new("d2e7558c-dc1f-403f-9a72-d28bb1eb3b5e");
    public static Guid MF_MT_PIXEL_ASPECT_RATIO = new("c6376a1e-8d0a-4027-be45-6d9a0ad39bb6");
    public static Guid MF_MT_INTERLACE_MODE = new("e2724bb8-e676-4806-b4b2-a8d6efb44ccd");
    public static Guid MF_MT_ALL_SAMPLES_INDEPENDENT = new("c9173739-5e56-461c-b713-46fb995cb95f");
    public static Guid MF_MT_FIXED_SIZE_SAMPLES = new("b8ebefaf-b718-4e04-b0a9-116775e3321b");
    public static Guid MF_MT_SAMPLE_SIZE = new("dad3ab78-1990-408b-bce2-eba673dacc10");
    public static Guid MF_MT_DEFAULT_STRIDE = new("644b4e48-1e02-4516-b0eb-c01ca9d49ac6");
    public static Guid MF_MT_AVG_BITRATE = new("20332624-fb0d-4d9e-bd0d-cbf6786c102e");
    public static Guid MF_MT_YUV_MATRIX = new("3e23d450-2c75-4d25-a00e-b91670d12327");
    public static Guid MF_MT_VIDEO_NOMINAL_RANGE = new("c21b8ee5-b956-4071-8daf-325edf5cab11");
    public static Guid MF_MT_VIDEO_PRIMARIES = new("dbfbe4d7-0740-4ee0-8192-850ab0e21935");
    public static Guid MF_MT_TRANSFER_FUNCTION = new("5fb0fce9-be5c-4935-a811-ec838f8eed93");

    public static Guid MF_DEVICESTREAM_STREAM_CATEGORY = new("2939e7b8-a62e-4579-b674-d4073dfabbba");
    public static Guid MF_DEVICESTREAM_STREAM_ID = new("11bd5120-d124-446b-88e6-17060257fff9");
    public static Guid MF_DEVICESTREAM_FRAMESERVER_SHARED = new("1cb378e9-b279-41d4-af97-34a243e68320");
    public static Guid MF_DEVICESTREAM_ATTRIBUTE_FRAMESOURCE_TYPES = new("17145fd1-1b2b-423c-8001-2b6833ed3588");
    /// <summary>KSCATEGORY/PINNAME_VIDEO_CAPTURE (ks.h): il flusso è quello della cattura video.</summary>
    public static Guid PINNAME_VIDEO_CAPTURE = new("fb6c4281-0353-11d1-905f-0000c0cc16ba");

    public static Guid MFSampleExtension_Token = new("8294da66-f328-4805-b551-00deb4c57a61");
    public static Guid MFSampleExtension_CleanPoint = new("9cdf01d8-a0f0-43ba-b077-eaa06cbd728a");

    public static ulong Coppia(uint alto, uint basso) => ((ulong)alto << 32) | basso;

    [DllImport("mfplat.dll")] public static extern int MFStartup(uint version, uint flags);
    [DllImport("mfplat.dll")] public static extern int MFShutdown();
    [DllImport("mfplat.dll")] public static extern int MFCreateAttributes(out IMFAttributes ppMFAttributes, uint cInitialSize);
    [DllImport("mfplat.dll")] public static extern int MFCreateEventQueue(out IMFMediaEventQueue ppMediaEventQueue);
    [DllImport("mfplat.dll")] public static extern int MFCreateMediaType(out IMFMediaType ppMFType);
    [DllImport("mfplat.dll")]
    public static extern int MFCreateStreamDescriptor(uint dwStreamIdentifier, uint cMediaTypes, nint[] apMediaTypes, out IMFStreamDescriptor ppDescriptor);
    [DllImport("mfplat.dll")]
    public static extern int MFCreatePresentationDescriptor(uint cStreamDescriptors, nint[] apStreamDescriptors, out IMFPresentationDescriptor ppPresentationDescriptor);
    [DllImport("mfplat.dll")] public static extern int MFCreateMemoryBuffer(uint cbMaxLength, out IMFMediaBuffer ppBuffer);
    [DllImport("mfplat.dll")] public static extern int MFCreateSample(out IMFSample ppIMFSample);
    /// <summary>Orologio di sistema in unità da 100 ns (basato su QueryPerformanceCounter), quello che Frame Server si aspetta.</summary>
    [DllImport("mfplat.dll")] public static extern long MFGetSystemTime();

    /// <summary>
    /// Un PROPVARIANT di tipo VT_I8 (8 byte di testa, poi il valore; 24 byte in tutto su x64 e ARM64).
    /// Con questo la sorgente dice in MESourceStarted, MEStreamStarted e MESourceStopped il momento (orologio di
    /// sistema), come i due esempi di riferimento (Windows-Camera VirtualCamera e VCamSample).
    /// </summary>
    [StructLayout(LayoutKind.Explicit, Size = 24)]
    private struct VarianteI8
    {
        [FieldOffset(0)] public ushort Tipo;
        [FieldOffset(8)] public long Valore;
    }

    private const ushort VT_I8 = 20;

    /// <summary>Mette in coda un evento con il valore VT_I8 dato (la coda copia il PROPVARIANT).</summary>
    public static unsafe int AccodaConTempo(IMFMediaEventQueue coda, uint evento, long tempo)
    {
        var valore = new VarianteI8 { Tipo = VT_I8, Valore = tempo };
        var tipo = GUID_NULL;
        return coda.QueueEventParamVar(evento, ref tipo, S_OK, (nint)(&valore));
    }

    /// <summary>Scrive lo zero in un ULONG* di IKsControl, se il chiamante ne ha passato uno.</summary>
    public static unsafe void AzzeraSeValido(nint puntatore)
    {
        if (puntatore != 0) *(uint*)puntatore = 0;
    }

    /// <summary>Lancia un'eccezione con l'HRESULT se la chiamata è fallita.</summary>
    public static void Verifica(int hr, string cosa)
    {
        if (hr < 0) throw new COMException($"{cosa}: 0x{hr:X8}", hr);
    }

    /// <summary>Rilascia subito un oggetto COM tenuto da .NET, senza aspettare il garbage collector.</summary>
    public static void Libera(object? oggetto)
    {
        if (oggetto is not null && Marshal.IsComObject(oggetto)) Marshal.ReleaseComObject(oggetto);
    }

    /// <summary>Puntatore COM (con un riferimento in più) all'interfaccia T dell'oggetto, .NET o nativo.</summary>
    public static nint Puntatore<T>(object oggetto) => Marshal.GetComInterfaceForObject(oggetto, typeof(T));
}
