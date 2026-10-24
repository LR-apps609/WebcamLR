using System.Runtime.InteropServices;
using static WebcamLR.Webcam.FunzioniMF;

namespace WebcamLR.Webcam;

/// <summary>
/// La classe COM registrata con il CLSID di <see cref="NomiWebcam.Clsid"/>: Frame Server (e FrameServerMonitor) la creano
/// con CoCreateInstance e chiamano ActivateObject per avere la sorgente. Come gli esempi di Microsoft (Windows-Camera,
/// VirtualCamera) è un IMFActivate; gli attributi che Frame Server ci mette passano alla sorgente.
/// </summary>
[ComVisible(true)]
[Guid(NomiWebcam.Clsid)]
[ClassInterface(ClassInterfaceType.None)]
public sealed class AttivatoreWebcam : IMFActivate, IMFAttributes
{
    private readonly IMFAttributes attributi;
    private readonly object blocco = new();
    private SorgenteWebcam? sorgente;

    public AttivatoreWebcam()
    {
        Verifica(MFCreateAttributes(out attributi, 4), "MFCreateAttributes");
    }

    public int ActivateObject(ref Guid riid, out nint ppv)
    {
        ppv = 0;
        try
        {
            SorgenteWebcam nuova;
            lock (blocco)
            {
                sorgente ??= new SorgenteWebcam(attributi);
                nuova = sorgente;
            }
            var sconosciuto = Marshal.GetIUnknownForObject(nuova);
            try { return Marshal.QueryInterface(sconosciuto, ref riid, out ppv); }
            finally { Marshal.Release(sconosciuto); }
        }
        catch (Exception errore)
        {
            RegistroWebcam.Scrivi($"ActivateObject non riuscito: {errore}");
            return errore.HResult < 0 ? errore.HResult : E_FAIL;
        }
    }

    public int ShutdownObject()
    {
        SorgenteWebcam? vecchia;
        lock (blocco)
        {
            vecchia = sorgente;
            sorgente = null;
        }
        vecchia?.Shutdown();
        return S_OK;
    }

    public int DetachObject()
    {
        lock (blocco) sorgente = null;
        return S_OK;
    }

    // IMFAttributes: tutto passa all'archivio creato da Media Foundation.
    public int GetItem(ref Guid guidKey, nint pValue) => attributi.GetItem(ref guidKey, pValue);
    public int GetItemType(ref Guid guidKey, out int pType) => attributi.GetItemType(ref guidKey, out pType);
    public int CompareItem(ref Guid guidKey, nint value, out int pbResult) => attributi.CompareItem(ref guidKey, value, out pbResult);
    public int Compare(nint pTheirs, int matchType, out int pbResult) => attributi.Compare(pTheirs, matchType, out pbResult);
    public int GetUINT32(ref Guid guidKey, out uint punValue) => attributi.GetUINT32(ref guidKey, out punValue);
    public int GetUINT64(ref Guid guidKey, out ulong punValue) => attributi.GetUINT64(ref guidKey, out punValue);
    public int GetDouble(ref Guid guidKey, out double pfValue) => attributi.GetDouble(ref guidKey, out pfValue);
    public int GetGUID(ref Guid guidKey, out Guid pguidValue) => attributi.GetGUID(ref guidKey, out pguidValue);
    public int GetStringLength(ref Guid guidKey, out uint pcchLength) => attributi.GetStringLength(ref guidKey, out pcchLength);
    public int GetString(ref Guid guidKey, nint pwszValue, uint cchBufSize, nint pcchLength) => attributi.GetString(ref guidKey, pwszValue, cchBufSize, pcchLength);
    public int GetAllocatedString(ref Guid guidKey, out nint ppwszValue, out uint pcchLength) => attributi.GetAllocatedString(ref guidKey, out ppwszValue, out pcchLength);
    public int GetBlobSize(ref Guid guidKey, out uint pcbBlobSize) => attributi.GetBlobSize(ref guidKey, out pcbBlobSize);
    public int GetBlob(ref Guid guidKey, nint pBuf, uint cbBufSize, nint pcbBlobSize) => attributi.GetBlob(ref guidKey, pBuf, cbBufSize, pcbBlobSize);
    public int GetAllocatedBlob(ref Guid guidKey, out nint ppBuf, out uint pcbSize) => attributi.GetAllocatedBlob(ref guidKey, out ppBuf, out pcbSize);
    public int GetUnknown(ref Guid guidKey, ref Guid riid, out nint ppv) => attributi.GetUnknown(ref guidKey, ref riid, out ppv);
    public int SetItem(ref Guid guidKey, nint value) => attributi.SetItem(ref guidKey, value);
    public int DeleteItem(ref Guid guidKey) => attributi.DeleteItem(ref guidKey);
    public int DeleteAllItems() => attributi.DeleteAllItems();
    public int SetUINT32(ref Guid guidKey, uint unValue) => attributi.SetUINT32(ref guidKey, unValue);
    public int SetUINT64(ref Guid guidKey, ulong unValue) => attributi.SetUINT64(ref guidKey, unValue);
    public int SetDouble(ref Guid guidKey, double fValue) => attributi.SetDouble(ref guidKey, fValue);
    public int SetGUID(ref Guid guidKey, ref Guid guidValue) => attributi.SetGUID(ref guidKey, ref guidValue);
    public int SetString(ref Guid guidKey, nint wszValue) => attributi.SetString(ref guidKey, wszValue);
    public int SetBlob(ref Guid guidKey, nint pBuf, uint cbBufSize) => attributi.SetBlob(ref guidKey, pBuf, cbBufSize);
    public int SetUnknown(ref Guid guidKey, nint pUnknown) => attributi.SetUnknown(ref guidKey, pUnknown);
    public int LockStore() => attributi.LockStore();
    public int UnlockStore() => attributi.UnlockStore();
    public int GetCount(out uint pcItems) => attributi.GetCount(out pcItems);
    public int GetItemByIndex(uint unIndex, out Guid pguidKey, nint pValue) => attributi.GetItemByIndex(unIndex, out pguidKey, pValue);
    public int CopyAllItems(nint pDest) => attributi.CopyAllItems(pDest);
}
