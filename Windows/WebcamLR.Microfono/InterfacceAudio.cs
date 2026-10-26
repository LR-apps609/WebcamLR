using System.Runtime.InteropServices;

namespace WebcamLR.Microfono;

// Le interfacce COM che servono al microfono, scritte a mano dagli header dell'SDK di Windows, come in
// WebcamLR.Webcam/InterfacceMF.cs (stesse regole: ogni interfaccia ripete nell'ordine i metodi di quelle da cui deriva,
// tutti i metodi restituiscono l'HRESULT). IMFMediaType, IMFSample e IMFMediaBuffer sono copiate da lì; IMFTransform
// (mftransform.h), IMMDeviceEnumerator, IMMDeviceCollection, IMMDevice (mmdeviceapi.h), IAudioClient, IAudioRenderClient
// (audioclient.h), IPropertyStore (propsys.h) e WAVEFORMATEX (mmreg.h) sono verificate una per una (IID, ordine dei
// metodi, parametri) con gli header mingw-w64.

[ComImport, Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFMediaType
{
    // IMFAttributes (30 metodi, nell'ordine di mfobjects.h)
    [PreserveSig] int GetItem([In] ref Guid guidKey, nint pValue);
    [PreserveSig] int GetItemType([In] ref Guid guidKey, out int pType);
    [PreserveSig] int CompareItem([In] ref Guid guidKey, nint value, out int pbResult);
    [PreserveSig] int Compare(nint pTheirs, int matchType, out int pbResult);
    [PreserveSig] int GetUINT32([In] ref Guid guidKey, out uint punValue);
    [PreserveSig] int GetUINT64([In] ref Guid guidKey, out ulong punValue);
    [PreserveSig] int GetDouble([In] ref Guid guidKey, out double pfValue);
    [PreserveSig] int GetGUID([In] ref Guid guidKey, out Guid pguidValue);
    [PreserveSig] int GetStringLength([In] ref Guid guidKey, out uint pcchLength);
    [PreserveSig] int GetString([In] ref Guid guidKey, nint pwszValue, uint cchBufSize, nint pcchLength);
    [PreserveSig] int GetAllocatedString([In] ref Guid guidKey, out nint ppwszValue, out uint pcchLength);
    [PreserveSig] int GetBlobSize([In] ref Guid guidKey, out uint pcbBlobSize);
    [PreserveSig] int GetBlob([In] ref Guid guidKey, nint pBuf, uint cbBufSize, nint pcbBlobSize);
    [PreserveSig] int GetAllocatedBlob([In] ref Guid guidKey, out nint ppBuf, out uint pcbSize);
    [PreserveSig] int GetUnknown([In] ref Guid guidKey, [In] ref Guid riid, out nint ppv);
    [PreserveSig] int SetItem([In] ref Guid guidKey, nint value);
    [PreserveSig] int DeleteItem([In] ref Guid guidKey);
    [PreserveSig] int DeleteAllItems();
    [PreserveSig] int SetUINT32([In] ref Guid guidKey, uint unValue);
    [PreserveSig] int SetUINT64([In] ref Guid guidKey, ulong unValue);
    [PreserveSig] int SetDouble([In] ref Guid guidKey, double fValue);
    [PreserveSig] int SetGUID([In] ref Guid guidKey, [In] ref Guid guidValue);
    [PreserveSig] int SetString([In] ref Guid guidKey, nint wszValue);
    [PreserveSig] int SetBlob([In] ref Guid guidKey, nint pBuf, uint cbBufSize);
    [PreserveSig] int SetUnknown([In] ref Guid guidKey, nint pUnknown);
    [PreserveSig] int LockStore();
    [PreserveSig] int UnlockStore();
    [PreserveSig] int GetCount(out uint pcItems);
    [PreserveSig] int GetItemByIndex(uint unIndex, out Guid pguidKey, nint pValue);
    [PreserveSig] int CopyAllItems(nint pDest);
    // IMFMediaType
    [PreserveSig] int GetMajorType(out Guid pguidMajorType);
    [PreserveSig] int IsCompressedFormat(out int pfCompressed);
    [PreserveSig] int IsEqual(nint pIMediaType, out uint pdwFlags);
    [PreserveSig] int GetRepresentation(Guid guidRepresentation, out nint ppvRepresentation);
    [PreserveSig] int FreeRepresentation(Guid guidRepresentation, nint pvRepresentation);
}

[ComImport, Guid("c40a00f2-b93a-4d80-ae8c-5a1c634f58e4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFSample
{
    // IMFAttributes (30 metodi, nell'ordine di mfobjects.h)
    [PreserveSig] int GetItem([In] ref Guid guidKey, nint pValue);
    [PreserveSig] int GetItemType([In] ref Guid guidKey, out int pType);
    [PreserveSig] int CompareItem([In] ref Guid guidKey, nint value, out int pbResult);
    [PreserveSig] int Compare(nint pTheirs, int matchType, out int pbResult);
    [PreserveSig] int GetUINT32([In] ref Guid guidKey, out uint punValue);
    [PreserveSig] int GetUINT64([In] ref Guid guidKey, out ulong punValue);
    [PreserveSig] int GetDouble([In] ref Guid guidKey, out double pfValue);
    [PreserveSig] int GetGUID([In] ref Guid guidKey, out Guid pguidValue);
    [PreserveSig] int GetStringLength([In] ref Guid guidKey, out uint pcchLength);
    [PreserveSig] int GetString([In] ref Guid guidKey, nint pwszValue, uint cchBufSize, nint pcchLength);
    [PreserveSig] int GetAllocatedString([In] ref Guid guidKey, out nint ppwszValue, out uint pcchLength);
    [PreserveSig] int GetBlobSize([In] ref Guid guidKey, out uint pcbBlobSize);
    [PreserveSig] int GetBlob([In] ref Guid guidKey, nint pBuf, uint cbBufSize, nint pcbBlobSize);
    [PreserveSig] int GetAllocatedBlob([In] ref Guid guidKey, out nint ppBuf, out uint pcbSize);
    [PreserveSig] int GetUnknown([In] ref Guid guidKey, [In] ref Guid riid, out nint ppv);
    [PreserveSig] int SetItem([In] ref Guid guidKey, nint value);
    [PreserveSig] int DeleteItem([In] ref Guid guidKey);
    [PreserveSig] int DeleteAllItems();
    [PreserveSig] int SetUINT32([In] ref Guid guidKey, uint unValue);
    [PreserveSig] int SetUINT64([In] ref Guid guidKey, ulong unValue);
    [PreserveSig] int SetDouble([In] ref Guid guidKey, double fValue);
    [PreserveSig] int SetGUID([In] ref Guid guidKey, [In] ref Guid guidValue);
    [PreserveSig] int SetString([In] ref Guid guidKey, nint wszValue);
    [PreserveSig] int SetBlob([In] ref Guid guidKey, nint pBuf, uint cbBufSize);
    [PreserveSig] int SetUnknown([In] ref Guid guidKey, nint pUnknown);
    [PreserveSig] int LockStore();
    [PreserveSig] int UnlockStore();
    [PreserveSig] int GetCount(out uint pcItems);
    [PreserveSig] int GetItemByIndex(uint unIndex, out Guid pguidKey, nint pValue);
    [PreserveSig] int CopyAllItems(nint pDest);
    // IMFSample
    [PreserveSig] int GetSampleFlags(out uint pdwSampleFlags);
    [PreserveSig] int SetSampleFlags(uint dwSampleFlags);
    [PreserveSig] int GetSampleTime(out long phnsSampleTime);
    [PreserveSig] int SetSampleTime(long hnsSampleTime);
    [PreserveSig] int GetSampleDuration(out long phnsSampleDuration);
    [PreserveSig] int SetSampleDuration(long hnsSampleDuration);
    [PreserveSig] int GetBufferCount(out uint pdwBufferCount);
    [PreserveSig] int GetBufferByIndex(uint dwIndex, out nint ppBuffer);
    [PreserveSig] int ConvertToContiguousBuffer(out nint ppBuffer);
    [PreserveSig] int AddBuffer(IMFMediaBuffer pBuffer);
    [PreserveSig] int RemoveBufferByIndex(uint dwIndex);
    [PreserveSig] int RemoveAllBuffers();
    [PreserveSig] int GetTotalLength(out uint pcbTotalLength);
    [PreserveSig] int CopyToBuffer(nint pBuffer);
}

[ComImport, Guid("045FA593-8799-42b8-BC8D-8968C6453507"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFMediaBuffer
{
    [PreserveSig] int Lock(out nint ppbBuffer, out uint pcbMaxLength, out uint pcbCurrentLength);
    [PreserveSig] int Unlock();
    [PreserveSig] int GetCurrentLength(out uint pcbCurrentLength);
    [PreserveSig] int SetCurrentLength(uint cbCurrentLength);
    [PreserveSig] int GetMaxLength(out uint pcbMaxLength);
}

/// <summary>MFT_INPUT_STREAM_INFO (mftransform.h).</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct InfoIngressoMft
{
    public long hnsMaxLatency;
    public uint dwFlags;
    public uint cbSize;
    public uint cbMaxLookahead;
    public uint cbAlignment;
}

/// <summary>MFT_OUTPUT_STREAM_INFO (mftransform.h).</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct InfoUscitaMft
{
    public uint dwFlags;
    public uint cbSize;
    public uint cbAlignment;
}

/// <summary>MFT_OUTPUT_DATA_BUFFER (mftransform.h): i puntatori restano nint, i riferimenti li gestisce chi chiama.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct DatiUscitaMft
{
    public uint dwStreamID;
    public nint pSample;
    public uint dwStatus;
    public nint pEvents;
}

[ComImport, Guid("bf94c121-5b05-4e6f-8000-ba598961414d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFTransform
{
    [PreserveSig] int GetStreamLimits(out uint inputMinimum, out uint inputMaximum, out uint outputMinimum, out uint outputMaximum);
    [PreserveSig] int GetStreamCount(out uint inputs, out uint outputs);
    [PreserveSig] int GetStreamIDs(uint inputSize, nint inputs, uint outputSize, nint outputs);
    [PreserveSig] int GetInputStreamInfo(uint id, out InfoIngressoMft info);
    [PreserveSig] int GetOutputStreamInfo(uint id, out InfoUscitaMft info);
    [PreserveSig] int GetAttributes(out nint attributes);
    [PreserveSig] int GetInputStreamAttributes(uint id, out nint attributes);
    [PreserveSig] int GetOutputStreamAttributes(uint id, out nint attributes);
    [PreserveSig] int DeleteInputStream(uint id);
    [PreserveSig] int AddInputStreams(uint streams, nint ids);
    [PreserveSig] int GetInputAvailableType(uint id, uint index, out IMFMediaType type);
    [PreserveSig] int GetOutputAvailableType(uint id, uint index, out IMFMediaType type);
    [PreserveSig] int SetInputType(uint id, IMFMediaType? type, uint flags);
    [PreserveSig] int SetOutputType(uint id, IMFMediaType? type, uint flags);
    [PreserveSig] int GetInputCurrentType(uint id, out IMFMediaType type);
    [PreserveSig] int GetOutputCurrentType(uint id, out IMFMediaType type);
    [PreserveSig] int GetInputStatus(uint id, out uint flags);
    [PreserveSig] int GetOutputStatus(out uint flags);
    [PreserveSig] int SetOutputBounds(long lower, long upper);
    [PreserveSig] int ProcessEvent(uint id, nint mediaEvent);
    [PreserveSig] int ProcessMessage(uint message, nint param);
    [PreserveSig] int ProcessInput(uint id, IMFSample sample, uint flags);
    [PreserveSig] int ProcessOutput(uint flags, uint count, ref DatiUscitaMft samples, out uint status);
}

[ComImport, Guid("a95664d2-9614-4f35-a746-de8db63617e6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceEnumerator
{
    [PreserveSig] int EnumAudioEndpoints(int dataFlow, uint stateMask, out IMMDeviceCollection devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    [PreserveSig] int RegisterEndpointNotificationCallback(nint client);
    [PreserveSig] int UnregisterEndpointNotificationCallback(nint client);
}

[ComImport, Guid("0bd7a1be-7a1a-44db-8397-cc5392387b5e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDeviceCollection
{
    [PreserveSig] int GetCount(out uint count);
    [PreserveSig] int Item(uint index, out IMMDevice device);
}

[ComImport, Guid("d666063f-1587-4e43-81f1-b948e807363f"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMMDevice
{
    [PreserveSig] int Activate([In] ref Guid iid, uint clsCtx, nint activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
    [PreserveSig] int OpenPropertyStore(uint access, out IPropertyStore properties);
    /// <summary>L'ID è una stringa allocata con CoTaskMemAlloc: la libera chi chiama.</summary>
    [PreserveSig] int GetId(out nint id);
    [PreserveSig] int GetState(out uint state);
}

[ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IPropertyStore
{
    [PreserveSig] int GetCount(out uint count);
    [PreserveSig] int GetAt(uint index, out ChiaveProprieta key);
    [PreserveSig] int GetValue([In] ref ChiaveProprieta key, out ValoreProprieta value);
    [PreserveSig] int SetValue([In] ref ChiaveProprieta key, [In] ref ValoreProprieta value);
    [PreserveSig] int Commit();
}

/// <summary>PROPERTYKEY.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct ChiaveProprieta
{
    public Guid fmtid;
    public uint pid;
}

/// <summary>PROPVARIANT, solo quanto serve per leggere una stringa (VT_LPWSTR); si libera con PropVariantClear.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct ValoreProprieta
{
    public ushort vt;
    public ushort riservato1;
    public ushort riservato2;
    public ushort riservato3;
    public nint valore;
    public nint valore2;
}

[ComImport, Guid("1cb9ad4c-dbfa-4c32-b178-c2f568a703b2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioClient
{
    [PreserveSig] int Initialize(int shareMode, uint streamFlags, long bufferDuration, long periodicity, [In] ref FormatoOnda format, nint audioSessionGuid);
    [PreserveSig] int GetBufferSize(out uint bufferFrames);
    [PreserveSig] int GetStreamLatency(out long latency);
    [PreserveSig] int GetCurrentPadding(out uint paddingFrames);
    [PreserveSig] int IsFormatSupported(int shareMode, [In] ref FormatoOnda format, out nint closestMatch);
    [PreserveSig] int GetMixFormat(out nint deviceFormat);
    [PreserveSig] int GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);
    [PreserveSig] int Start();
    [PreserveSig] int Stop();
    [PreserveSig] int Reset();
    [PreserveSig] int SetEventHandle(nint eventHandle);
    [PreserveSig] int GetService([In] ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
}

[ComImport, Guid("f294acfc-3146-4483-a7bf-addca7c260e2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IAudioRenderClient
{
    [PreserveSig] int GetBuffer(uint framesRequested, out nint data);
    [PreserveSig] int ReleaseBuffer(uint framesWritten, uint flags);
}

/// <summary>WAVEFORMATEX (mmreg.h): 18 byte, impacchettato a 1 come nell'header.</summary>
[StructLayout(LayoutKind.Sequential, Pack = 1)]
internal struct FormatoOnda
{
    public ushort wFormatTag;
    public ushort nChannels;
    public uint nSamplesPerSec;
    public uint nAvgBytesPerSec;
    public ushort nBlockAlign;
    public ushort wBitsPerSample;
    public ushort cbSize;
}
