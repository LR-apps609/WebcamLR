using System.Runtime.InteropServices;
using static WebcamLR.Webcam.DirectShow.ComNativo;

namespace WebcamLR.Webcam.DirectShow;

/// <summary>
/// Il filtro DirectShow «WebcamLR» (Windows 10, P23): una sorgente di cattura video con un pin solo. Le app lo trovano
/// nella categoria CLSID_VideoInputDeviceCategory, lo creano con CoCreateInstance dentro il loro processo e lo mettono
/// nel loro grafo. Gira dentro Zoom, Chrome, OBS…: ogni metodo cattura tutto e restituisce un HRESULT, perché
/// un'eccezione che esce da qui farebbe cadere l'app dell'utente.
/// </summary>
[ComVisible(true)]
[Guid(NomiWebcam.ClsidDirectShow)]
[ClassInterface(ClassInterfaceType.None)]
public sealed unsafe class FiltroWebcam : IBaseFilter, IMediaFilter, IPersist, IAMFilterMiscFlags
{
    internal readonly object Blocco = new();
    private readonly PinWebcam pin;
    private int stato = State_Stopped;
    private long inizioFlusso;
    private nint orologio;
    /// <summary>Il grafo che contiene il filtro: senza AddRef, come vuole DirectShow (il grafo tiene il filtro, non il contrario).</summary>
    private nint grafo;
    private string nome = NomiWebcam.NomeDirectShow;

    public FiltroWebcam()
    {
        pin = new PinWebcam(this);
        RegistroDirectShow.Scrivi($"Filtro creato (.NET {Environment.Version})");
    }

    internal int Stato { get { lock (Blocco) return stato; } }
    internal nint Grafo { get { lock (Blocco) return grafo; } }

    /// <summary>
    /// Il tempo di flusso adesso (in unità da 100 ns, dall'inizio di Run), se il grafo ha un orologio. I campioni di
    /// una sorgente dal vivo hanno questo come inizio: il renderer li mostra subito, senza aspettare.
    /// </summary>
    internal bool TempoFlusso(out long tempo)
    {
        tempo = 0;
        nint o;
        long inizio;
        lock (Blocco)
        {
            if (orologio == 0 || stato != State_Running) return false;
            o = orologio;
            Marshal.AddRef(o);
            inizio = inizioFlusso;
        }
        try
        {
            if (ClockGetTime(o, out var adesso) < 0) return false;
            tempo = Math.Max(0, adesso - inizio);
            return true;
        }
        finally { Marshal.Release(o); }
    }

    // ── IPersist ───────────────────────────────────────────────────

    public int GetClassID(nint pClassID)
    {
        if (pClassID == 0) return E_POINTER;
        *(Guid*)pClassID = typeof(FiltroWebcam).GUID;
        return S_OK;
    }

    // ── IMediaFilter ───────────────────────────────────────────────

    public int Stop()
    {
        try
        {
            lock (Blocco)
            {
                if (stato == State_Stopped) return S_OK;
                stato = State_Stopped;
            }
            pin.Disattiva();
            RegistroDirectShow.Scrivi("Stop");
            return S_OK;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    public int Pause()
    {
        try
        {
            bool eraFermo;
            lock (Blocco)
            {
                eraFermo = stato == State_Stopped;
                stato = State_Paused;
            }
            if (eraFermo)
            {
                var hr = pin.Attiva();
                if (hr < 0)
                {
                    lock (Blocco) stato = State_Stopped;
                    return hr;
                }
            }
            pin.StatoCambiato();
            // Una sorgente dal vivo non prepara nulla in pausa.
            return VFW_S_CANT_CUE;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    public int Run(long tStart)
    {
        try
        {
            if (Stato == State_Stopped)
            {
                var hr = Pause();
                if (hr < 0) return hr;
            }
            lock (Blocco)
            {
                inizioFlusso = tStart;
                stato = State_Running;
            }
            pin.StatoCambiato();
            RegistroDirectShow.Scrivi($"Run ({pin.Descrizione})");
            return S_OK;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    public int GetState(uint dwMilliSecsTimeout, nint State)
    {
        if (State == 0) return E_POINTER;
        lock (Blocco)
        {
            *(int*)State = stato;
            return stato == State_Paused ? VFW_S_CANT_CUE : S_OK;
        }
    }

    public int SetSyncSource(nint pClock)
    {
        lock (Blocco)
        {
            if (pClock != 0) Marshal.AddRef(pClock);
            Libera(ref orologio);
            orologio = pClock;
        }
        return S_OK;
    }

    public int GetSyncSource(nint pClock)
    {
        if (pClock == 0) return E_POINTER;
        lock (Blocco)
        {
            if (orologio != 0) Marshal.AddRef(orologio);
            *(nint*)pClock = orologio;
        }
        return S_OK;
    }

    // ── IBaseFilter ────────────────────────────────────────────────

    public int EnumPins(nint ppEnum)
    {
        if (ppEnum == 0) return E_POINTER;
        try
        {
            *(nint*)ppEnum = Marshal.GetComInterfaceForObject(new EnumeratorePin(pin), typeof(IEnumPins));
            return S_OK;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    public int FindPin(nint Id, nint ppPin)
    {
        if (ppPin == 0) return E_POINTER;
        *(nint*)ppPin = 0;
        if (Id == 0) return E_POINTER;
        try
        {
            if (Marshal.PtrToStringUni(Id) != PinWebcam.Id) return VFW_E_NOT_FOUND;
            *(nint*)ppPin = Marshal.GetComInterfaceForObject(pin, typeof(IPin));
            return S_OK;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    /// <summary>FILTER_INFO: WCHAR achName[128], poi IFilterGraph* (con AddRef).</summary>
    public int QueryFilterInfo(nint pInfo)
    {
        if (pInfo == 0) return E_POINTER;
        lock (Blocco)
        {
            ScriviNome((char*)pInfo, nome);
            if (grafo != 0) Marshal.AddRef(grafo);
            *(nint*)((byte*)pInfo + 256) = grafo;
        }
        return S_OK;
    }

    public int JoinFilterGraph(nint pGraph, nint pName)
    {
        try
        {
            lock (Blocco)
            {
                grafo = pGraph;
                nome = pName != 0 ? Marshal.PtrToStringUni(pName) ?? NomiWebcam.NomeDirectShow : NomiWebcam.NomeDirectShow;
            }
            if (pGraph == 0)
            {
                // Tolto dal grafo: niente più consegne, e l'orologio del grafo non va tenuto (nessun finalizzatore
                // rilascia puntatori COM: alla chiusura dell'app potrebbero già non valere più).
                pin.Disattiva();
                lock (Blocco) Libera(ref orologio);
            }
            return S_OK;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    public int QueryVendorInfo(nint pVendorInfo) => E_NOTIMPL;

    // ── IAMFilterMiscFlags ─────────────────────────────────────────

    public uint GetMiscFlags() => AM_FILTER_MISC_FLAGS_IS_SOURCE;

    /// <summary>Copia un nome in un campo WCHAR[128], troncato e chiuso da zero.</summary>
    internal static void ScriviNome(char* destinazione, string testo)
    {
        var n = Math.Min(testo.Length, 127);
        for (var i = 0; i < n; i++) destinazione[i] = testo[i];
        destinazione[n] = '\0';
    }

    internal static int Codice(Exception errore)
    {
        RegistroDirectShow.Scrivi($"Errore: {errore}");
        return errore.HResult < 0 ? errore.HResult : E_FAIL;
    }
}
