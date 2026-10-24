using System.Runtime.InteropServices;

namespace WebcamLR.Webcam;

// Le interfacce COM di Media Foundation che servono alla sorgente, scritte a mano dagli header dell'SDK di Windows
// (mfobjects.h, mfidl.h, ks.h). L'interoperabilità COM classica di .NET non conosce l'ereditarietà delle interfacce:
// ogni interfaccia ripete, nello stesso ordine, i metodi di quelle da cui deriva (l'ordine è la tabella dei metodi).
// Tutti i metodi restituiscono l'HRESULT ([PreserveSig]); i puntatori a interfaccia che passano soltanto sono nint,
// così .NET non crea oggetti intermedi e i conteggi dei riferimenti restano quelli di COM.

[ComImport, Guid("2cd2d921-c447-44a7-a13c-4adabfc247e3"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFAttributes
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
}

[ComImport, Guid("7FEE9E9A-4A89-47a6-899C-B6A53A70FB67"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFActivate
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
    // IMFActivate
    [PreserveSig] int ActivateObject([In] ref Guid riid, out nint ppv);
    [PreserveSig] int ShutdownObject();
    [PreserveSig] int DetachObject();
}

[ComImport, Guid("2CD0BD52-BCD5-4B89-B62C-EADC0C031E7D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaEventGenerator
{
    // IMFMediaEventGenerator
    [PreserveSig] int GetEvent(uint dwFlags, out nint ppEvent);
    [PreserveSig] int BeginGetEvent(nint pCallback, nint punkState);
    [PreserveSig] int EndGetEvent(nint pResult, out nint ppEvent);
    [PreserveSig] int QueueEvent(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pvValue);
}

[ComImport, Guid("279a808d-aec7-40c8-9c6b-a6b492c78a66"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaSource
{
    // IMFMediaEventGenerator
    [PreserveSig] int GetEvent(uint dwFlags, out nint ppEvent);
    [PreserveSig] int BeginGetEvent(nint pCallback, nint punkState);
    [PreserveSig] int EndGetEvent(nint pResult, out nint ppEvent);
    [PreserveSig] int QueueEvent(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pvValue);
    // IMFMediaSource
    [PreserveSig] int GetCharacteristics(out uint pdwCharacteristics);
    [PreserveSig] int CreatePresentationDescriptor(out nint ppPresentationDescriptor);
    [PreserveSig] int Start(nint pPresentationDescriptor, nint pguidTimeFormat, nint pvarStartPosition);
    [PreserveSig] int Stop();
    [PreserveSig] int Pause();
    [PreserveSig] int Shutdown();
}

[ComImport, Guid("3C9B2EB9-86D5-4514-A394-F56664F9F0D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaSourceEx
{
    // IMFMediaEventGenerator
    [PreserveSig] int GetEvent(uint dwFlags, out nint ppEvent);
    [PreserveSig] int BeginGetEvent(nint pCallback, nint punkState);
    [PreserveSig] int EndGetEvent(nint pResult, out nint ppEvent);
    [PreserveSig] int QueueEvent(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pvValue);
    // IMFMediaSource
    [PreserveSig] int GetCharacteristics(out uint pdwCharacteristics);
    [PreserveSig] int CreatePresentationDescriptor(out nint ppPresentationDescriptor);
    [PreserveSig] int Start(nint pPresentationDescriptor, nint pguidTimeFormat, nint pvarStartPosition);
    [PreserveSig] int Stop();
    [PreserveSig] int Pause();
    [PreserveSig] int Shutdown();
    // IMFMediaSourceEx
    [PreserveSig] int GetSourceAttributes(out nint ppAttributes);
    [PreserveSig] int GetStreamAttributes(uint dwStreamIdentifier, out nint ppAttributes);
    [PreserveSig] int SetD3DManager(nint pManager);
}

[ComImport, Guid("FBB03414-D13B-4786-8319-5AC51FC0A136"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaSource2
{
    // IMFMediaEventGenerator
    [PreserveSig] int GetEvent(uint dwFlags, out nint ppEvent);
    [PreserveSig] int BeginGetEvent(nint pCallback, nint punkState);
    [PreserveSig] int EndGetEvent(nint pResult, out nint ppEvent);
    [PreserveSig] int QueueEvent(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pvValue);
    // IMFMediaSource
    [PreserveSig] int GetCharacteristics(out uint pdwCharacteristics);
    [PreserveSig] int CreatePresentationDescriptor(out nint ppPresentationDescriptor);
    [PreserveSig] int Start(nint pPresentationDescriptor, nint pguidTimeFormat, nint pvarStartPosition);
    [PreserveSig] int Stop();
    [PreserveSig] int Pause();
    [PreserveSig] int Shutdown();
    // IMFMediaSourceEx
    [PreserveSig] int GetSourceAttributes(out nint ppAttributes);
    [PreserveSig] int GetStreamAttributes(uint dwStreamIdentifier, out nint ppAttributes);
    [PreserveSig] int SetD3DManager(nint pManager);
    // IMFMediaSource2
    [PreserveSig] int SetMediaType(uint dwStreamID, nint pMediaType);
}

[ComImport, Guid("D182108F-4EC6-443f-AA42-A71106EC825F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaStream
{
    // IMFMediaEventGenerator
    [PreserveSig] int GetEvent(uint dwFlags, out nint ppEvent);
    [PreserveSig] int BeginGetEvent(nint pCallback, nint punkState);
    [PreserveSig] int EndGetEvent(nint pResult, out nint ppEvent);
    [PreserveSig] int QueueEvent(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pvValue);
    // IMFMediaStream
    [PreserveSig] int GetMediaSource(out nint ppMediaSource);
    [PreserveSig] int GetStreamDescriptor(out nint ppStreamDescriptor);
    [PreserveSig] int RequestSample(nint pToken);
}

[ComImport, Guid("C5BC37D6-75C7-46A1-A132-81B5F723C20F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaStream2
{
    // IMFMediaEventGenerator
    [PreserveSig] int GetEvent(uint dwFlags, out nint ppEvent);
    [PreserveSig] int BeginGetEvent(nint pCallback, nint punkState);
    [PreserveSig] int EndGetEvent(nint pResult, out nint ppEvent);
    [PreserveSig] int QueueEvent(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pvValue);
    // IMFMediaStream
    [PreserveSig] int GetMediaSource(out nint ppMediaSource);
    [PreserveSig] int GetStreamDescriptor(out nint ppStreamDescriptor);
    [PreserveSig] int RequestSample(nint pToken);
    // IMFMediaStream2
    [PreserveSig] int SetStreamState(int value);
    [PreserveSig] int GetStreamState(out int value);
}

/// <summary>Le proprietà KS del driver: la webcam non ne ha, ma Frame Server chiede l'interfaccia.</summary>
[ComImport, Guid("28F54685-06FD-11D2-B27A-00A0C9223196"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKsControl
{
    [PreserveSig] int KsProperty(nint property, uint propertyLength, nint propertyData, uint dataLength, out uint bytesReturned);
    [PreserveSig] int KsMethod(nint method, uint methodLength, nint methodData, uint dataLength, out uint bytesReturned);
    [PreserveSig] int KsEvent(nint ksEvent, uint eventLength, nint eventData, uint dataLength, out uint bytesReturned);
}

[ComImport, Guid("fa993888-4383-415a-a930-dd472a8cf6f7"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFGetService
{
    [PreserveSig] int GetService([In] ref Guid guidService, [In] ref Guid riid, out nint ppvObject);
}

// ── Oggetti di Media Foundation che la sorgente usa ─────────────────

[ComImport, Guid("36f846fc-2256-48b6-b58e-e2b638316581"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaEventQueue
{
    [PreserveSig] int GetEvent(uint dwFlags, out nint ppEvent);
    [PreserveSig] int BeginGetEvent(nint pCallback, nint punkState);
    [PreserveSig] int EndGetEvent(nint pResult, out nint ppEvent);
    [PreserveSig] int QueueEvent(nint pEvent);
    [PreserveSig] int QueueEventParamVar(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pvValue);
    [PreserveSig] int QueueEventParamUnk(uint met, [In] ref Guid guidExtendedType, int hrStatus, nint pUnk);
    [PreserveSig] int Shutdown();
}

[ComImport, Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaType
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

[ComImport, Guid("e93dcf6c-4b07-4e1e-8123-aa16ed6eadf5"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFMediaTypeHandler
{
    [PreserveSig] int IsMediaTypeSupported(nint pMediaType, nint ppMediaType);
    [PreserveSig] int GetMediaTypeCount(out uint pdwTypeCount);
    [PreserveSig] int GetMediaTypeByIndex(uint dwIndex, out IMFMediaType ppType);
    [PreserveSig] int SetCurrentMediaType(IMFMediaType pMediaType);
    [PreserveSig] int GetCurrentMediaType(out IMFMediaType ppMediaType);
    [PreserveSig] int GetMajorType(out Guid pguidMajorType);
}

[ComImport, Guid("56c03d9c-9dbb-45f5-ab4b-d80f47c05938"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFStreamDescriptor
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
    // IMFStreamDescriptor
    [PreserveSig] int GetStreamIdentifier(out uint pdwStreamIdentifier);
    [PreserveSig] int GetMediaTypeHandler(out IMFMediaTypeHandler ppMediaTypeHandler);
}

[ComImport, Guid("03cb2711-24d7-4db6-a17f-f3a7a479a536"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFPresentationDescriptor
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
    // IMFPresentationDescriptor
    [PreserveSig] int GetStreamDescriptorCount(out uint pdwDescriptorCount);
    [PreserveSig] int GetStreamDescriptorByIndex(uint dwIndex, out int pfSelected, out IMFStreamDescriptor ppDescriptor);
    [PreserveSig] int SelectStream(uint dwDescriptorIndex);
    [PreserveSig] int DeselectStream(uint dwDescriptorIndex);
    [PreserveSig] int Clone(out nint ppPresentationDescriptor);
}

[ComImport, Guid("c40a00f2-b93a-4d80-ae8c-5a1c634f58e4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMFSample
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
public interface IMFMediaBuffer
{
    [PreserveSig] int Lock(out nint ppbBuffer, out uint pcbMaxLength, out uint pcbCurrentLength);
    [PreserveSig] int Unlock();
    [PreserveSig] int GetCurrentLength(out uint pcbCurrentLength);
    [PreserveSig] int SetCurrentLength(uint cbCurrentLength);
    [PreserveSig] int GetMaxLength(out uint pcbMaxLength);
}
