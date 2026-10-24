using System.Runtime.InteropServices;

namespace WebcamLR.Webcam.DirectShow;

// Le interfacce DirectShow che il filtro offre alle app, scritte a mano da strmif.h. Come per la sorgente di Windows 11
// l'interoperabilità COM classica non conosce l'ereditarietà: ogni interfaccia ripete, nello stesso ordine, i metodi di
// quelle da cui deriva (IPersist → IMediaFilter → IBaseFilter). Tutti i metodi restituiscono l'HRESULT
// ([PreserveSig]) e tutti i puntatori sono nint: niente conversioni automatiche di .NET, i conteggi dei riferimenti
// restano quelli di COM e un puntatore nullo passato da un'app si controlla invece di far cadere l'app.
// Verificate con strmif.h di mingw-w64 (IID, ordine dei metodi nelle tabelle …Vtbl, parametri): vedi LEGGIMI.

[ComImport, Guid("0000010c-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPersist
{
    [PreserveSig] int GetClassID(nint pClassID);
}

[ComImport, Guid("56a86899-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMediaFilter
{
    // IPersist
    [PreserveSig] int GetClassID(nint pClassID);
    // IMediaFilter
    [PreserveSig] int Stop();
    [PreserveSig] int Pause();
    [PreserveSig] int Run(long tStart);
    [PreserveSig] int GetState(uint dwMilliSecsTimeout, nint State);
    [PreserveSig] int SetSyncSource(nint pClock);
    [PreserveSig] int GetSyncSource(nint pClock);
}

[ComImport, Guid("56a86895-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IBaseFilter
{
    // IPersist
    [PreserveSig] int GetClassID(nint pClassID);
    // IMediaFilter
    [PreserveSig] int Stop();
    [PreserveSig] int Pause();
    [PreserveSig] int Run(long tStart);
    [PreserveSig] int GetState(uint dwMilliSecsTimeout, nint State);
    [PreserveSig] int SetSyncSource(nint pClock);
    [PreserveSig] int GetSyncSource(nint pClock);
    // IBaseFilter
    [PreserveSig] int EnumPins(nint ppEnum);
    [PreserveSig] int FindPin(nint Id, nint ppPin);
    [PreserveSig] int QueryFilterInfo(nint pInfo);
    [PreserveSig] int JoinFilterGraph(nint pGraph, nint pName);
    [PreserveSig] int QueryVendorInfo(nint pVendorInfo);
}

[ComImport, Guid("2dd74950-a890-11d1-abe8-00a0c905f375"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAMFilterMiscFlags
{
    /// <summary>Restituisce ULONG, non un HRESULT.</summary>
    [PreserveSig] uint GetMiscFlags();
}

[ComImport, Guid("56a86891-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPin
{
    [PreserveSig] int Connect(nint pReceivePin, nint pmt);
    [PreserveSig] int ReceiveConnection(nint pConnector, nint pmt);
    [PreserveSig] int Disconnect();
    [PreserveSig] int ConnectedTo(nint pPin);
    [PreserveSig] int ConnectionMediaType(nint pmt);
    [PreserveSig] int QueryPinInfo(nint pInfo);
    [PreserveSig] int QueryDirection(nint pPinDir);
    [PreserveSig] int QueryId(nint Id);
    [PreserveSig] int QueryAccept(nint pmt);
    [PreserveSig] int EnumMediaTypes(nint ppEnum);
    [PreserveSig] int QueryInternalConnections(nint apPin, nint nPin);
    [PreserveSig] int EndOfStream();
    [PreserveSig] int BeginFlush();
    [PreserveSig] int EndFlush();
    [PreserveSig] int NewSegment(long tStart, long tStop, double dRate);
}

[ComImport, Guid("c6e13340-30ac-11d0-a18c-00a0c9118956"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAMStreamConfig
{
    [PreserveSig] int SetFormat(nint pmt);
    [PreserveSig] int GetFormat(nint ppmt);
    [PreserveSig] int GetNumberOfCapabilities(nint piCount, nint piSize);
    [PreserveSig] int GetStreamCaps(int iIndex, nint ppmt, nint pSCC);
}

[ComImport, Guid("31efac30-515c-11d0-a9aa-00aa0061be93"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IKsPropertySet
{
    [PreserveSig] int Set(ref Guid guidPropSet, uint dwPropID, nint pInstanceData, uint cbInstanceData, nint pPropData, uint cbPropData);
    [PreserveSig] int Get(ref Guid guidPropSet, uint dwPropID, nint pInstanceData, uint cbInstanceData, nint pPropData, uint cbPropData, nint pcbReturned);
    [PreserveSig] int QuerySupported(ref Guid guidPropSet, uint dwPropID, nint pTypeSupport);
}

/// <summary>tagQuality di strmif.h: passata per valore a IQualityControl::Notify.</summary>
[StructLayout(LayoutKind.Sequential)]
public struct Quality
{
    public int Type;
    public int Proportion;
    public long Late;
    public long TimeStamp;
}

[ComImport, Guid("56a868a5-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IQualityControl
{
    [PreserveSig] int Notify(nint pSelf, Quality q);
    [PreserveSig] int SetSink(nint piqc);
}

[ComImport, Guid("56a86892-0ad4-11ce-b03a-0020af0ba770"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IEnumPins
{
    [PreserveSig] int Next(uint cPins, nint ppPins, nint pcFetched);
    [PreserveSig] int Skip(uint cPins);
    [PreserveSig] int Reset();
    [PreserveSig] int Clone(nint ppEnum);
}

[ComImport, Guid("89c31040-846b-11ce-97d3-00aa0055595a"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IEnumMediaTypes
{
    [PreserveSig] int Next(uint cMediaTypes, nint ppMediaTypes, nint pcFetched);
    [PreserveSig] int Skip(uint cMediaTypes);
    [PreserveSig] int Reset();
    [PreserveSig] int Clone(nint ppEnum);
}
