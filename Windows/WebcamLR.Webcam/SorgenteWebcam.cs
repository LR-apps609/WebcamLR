using System.Runtime.InteropServices;
using static WebcamLR.Webcam.FunzioniMF;

namespace WebcamLR.Webcam;

/// <summary>
/// La sorgente Media Foundation della webcam «WebcamLR», con un solo flusso video. Gira dentro Frame Server, che la
/// condivide tra tutte le app che aprono la webcam. Il codice qui deve restare piccolo e non lanciare mai eccezioni
/// verso Windows: un errore che fa cadere Frame Server spegne tutte le webcam del PC. Per questo ogni metodo COM
/// cattura tutto e restituisce un HRESULT.
/// </summary>
[ClassInterface(ClassInterfaceType.None)]
public sealed class SorgenteWebcam : IMFMediaSource2, IMFMediaSourceEx, IMFMediaSource, IMFMediaEventGenerator, IMFGetService, IKsControl
{
    private readonly object blocco = new();
    private readonly IMFAttributes attributi;
    private readonly IMFMediaEventQueue coda;
    private readonly IMFPresentationDescriptor descrittore;
    private readonly FlussoWebcam flusso;
    private bool chiusa;
    private bool flussoAnnunciato;
    private readonly bool avviataMF;

    public bool Chiusa { get { lock (blocco) return chiusa; } }

    internal SorgenteWebcam(IMFAttributes attributiAttivatore)
    {
        avviataMF = MFStartup(MF_VERSION, MFSTARTUP_LITE) >= 0;
        Verifica(MFCreateAttributes(out attributi, 10), "MFCreateAttributes");
        // Quello che Frame Server ha messo sull'attivatore vale anche per la sorgente.
        var destinazione = Puntatore<IMFAttributes>(attributi);
        try { attributiAttivatore.CopyAllItems(destinazione); }
        finally { Marshal.Release(destinazione); }

        Verifica(MFCreateEventQueue(out coda), "MFCreateEventQueue");
        flusso = new FlussoWebcam(this, 0);
        var descrittoreFlusso = Puntatore<IMFStreamDescriptor>(flusso.Descrittore);
        try { Verifica(MFCreatePresentationDescriptor(1, [descrittoreFlusso], out descrittore), "MFCreatePresentationDescriptor"); }
        finally { Marshal.Release(descrittoreFlusso); }
        Verifica(descrittore.SelectStream(0), "SelectStream");
        RegistroWebcam.Scrivi($"Sorgente creata (processo {Environment.ProcessPath}, .NET {Environment.Version})");
    }

    // ── IMFMediaEventGenerator ─────────────────────────────────────

    public int GetEvent(uint dwFlags, out nint ppEvent)
    {
        ppEvent = 0;
        IMFMediaEventQueue q;
        lock (blocco) { if (chiusa) return MF_E_SHUTDOWN; q = coda; }
        // Fuori dal blocco: GetEvent può aspettare a lungo.
        return Protetto(() => q.GetEvent(dwFlags, out var evento) is var hr && hr >= 0 ? (hr, evento) : (hr, 0), out ppEvent);
    }

    public int BeginGetEvent(nint pCallback, nint punkState)
    {
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            return Protetto(() => coda.BeginGetEvent(pCallback, punkState));
        }
    }

    public int EndGetEvent(nint pResult, out nint ppEvent)
    {
        ppEvent = 0;
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            return Protetto(() => coda.EndGetEvent(pResult, out var evento) is var hr && hr >= 0 ? (hr, evento) : (hr, 0), out ppEvent);
        }
    }

    public int QueueEvent(uint met, ref Guid guidExtendedType, int hrStatus, nint pvValue)
    {
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            var tipo = guidExtendedType;
            return Protetto(() => coda.QueueEventParamVar(met, ref tipo, hrStatus, pvValue));
        }
    }

    // ── IMFMediaSource ─────────────────────────────────────────────

    public int GetCharacteristics(out uint pdwCharacteristics)
    {
        pdwCharacteristics = MFMEDIASOURCE_IS_LIVE;
        lock (blocco) return chiusa ? MF_E_SHUTDOWN : S_OK;
    }

    public int CreatePresentationDescriptor(out nint ppPresentationDescriptor)
    {
        ppPresentationDescriptor = 0;
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            return Protetto(() => descrittore.Clone(out var copia) is var hr && hr >= 0 ? (hr, copia) : (hr, 0), out ppPresentationDescriptor);
        }
    }

    public int Start(nint pPresentationDescriptor, nint pguidTimeFormat, nint pvarStartPosition)
    {
        if (pPresentationDescriptor == 0 || pvarStartPosition == 0) return E_INVALIDARG;
        // Solo il formato del tempo predefinito (100 ns), come gli esempi di Microsoft.
        if (pguidTimeFormat != 0 && Marshal.PtrToStructure<Guid>(pguidTimeFormat) != Guid.Empty) return MF_E_UNSUPPORTED_TIME_FORMAT;
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            try
            {
                var scelto = (IMFPresentationDescriptor)Marshal.GetObjectForIUnknown(pPresentationDescriptor);
                var selezionato = false;
                try
                {
                    Verifica(scelto.GetStreamDescriptorCount(out var quanti), "GetStreamDescriptorCount");
                    for (uint i = 0; i < quanti; i++)
                    {
                        Verifica(scelto.GetStreamDescriptorByIndex(i, out var attivo, out var descrittoreFlusso), "GetStreamDescriptorByIndex");
                        try
                        {
                            Verifica(descrittoreFlusso.GetStreamIdentifier(out var id), "GetStreamIdentifier");
                            if (id != 0 || attivo == 0) continue;
                            selezionato = true;
                            var formato = FormatoCorrente(descrittoreFlusso);
                            if (formato is { } f) flusso.ImpostaFormato(f);
                        }
                        finally { Libera(descrittoreFlusso); }
                    }
                }
                finally { Libera(scelto); }

                // Il momento dell'avvio (orologio di sistema, VT_I8) negli eventi, come gli esempi di Microsoft:
                // con una webcam dal vivo la posizione chiesta è sempre VT_EMPTY e non direbbe nulla.
                var adesso = MFGetSystemTime();
                if (selezionato)
                {
                    // Prima il flusso nuovo (o aggiornato), poi «sorgente avviata», poi «flusso avviato».
                    // MEUpdatedStream solo se il flusso era già avviato: dopo Stop è di nuovo «nuovo» (MENewStream).
                    var tipo = GUID_NULL;
                    var sconosciuto = Marshal.GetIUnknownForObject(flusso);
                    try { Verifica(coda.QueueEventParamUnk(flussoAnnunciato ? MEUpdatedStream : MENewStream, ref tipo, S_OK, sconosciuto), "MENewStream"); }
                    finally { Marshal.Release(sconosciuto); }
                    flussoAnnunciato = true;
                    Verifica(AccodaConTempo(coda, MESourceStarted, adesso), "MESourceStarted");
                    flusso.Avvia(adesso);
                }
                else
                {
                    flusso.Ferma(annuncia: true);
                    flussoAnnunciato = false;
                    Verifica(AccodaConTempo(coda, MESourceStarted, adesso), "MESourceStarted");
                }
                RegistroWebcam.Scrivi($"Avviata: {flusso.Formato}");
                return S_OK;
            }
            catch (Exception errore)
            {
                RegistroWebcam.Scrivi($"Start non riuscito: {errore}");
                return Codice(errore);
            }
        }
    }

    public int Stop()
    {
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            try
            {
                flusso.Ferma(annuncia: true);
                flussoAnnunciato = false;
                Verifica(AccodaConTempo(coda, MESourceStopped, MFGetSystemTime()), "MESourceStopped");
                RegistroWebcam.Scrivi("Fermata");
                return S_OK;
            }
            catch (Exception errore) { return Codice(errore); }
        }
    }

    /// <summary>Una webcam dal vivo non va in pausa: come gli esempi di Microsoft (MF_E_INVALID_STATE_TRANSITION).</summary>
    public int Pause()
    {
        lock (blocco) return chiusa ? MF_E_SHUTDOWN : MF_E_INVALID_STATE_TRANSITION;
    }

    public int Shutdown()
    {
        lock (blocco)
        {
            if (chiusa) return S_OK;
            chiusa = true;
        }
        try
        {
            flusso.Chiudi();
            coda.Shutdown();
            RegistroWebcam.Scrivi($"Sorgente chiusa: {flusso.FotogrammiConsegnati} fotogrammi consegnati");
        }
        catch (Exception errore) { RegistroWebcam.Scrivi($"Shutdown: {errore.Message}"); }
        finally
        {
            // La coda non si rilascia qui: un GetEvent di Frame Server può essere ancora dentro (torna con MF_E_SHUTDOWN);
            // la rilascia il garbage collector quando nessuno la usa più.
            Libera(descrittore);
            Libera(attributi);
            if (avviataMF) MFShutdown();
        }
        return S_OK;
    }

    // ── IMFMediaSourceEx e IMFMediaSource2 ─────────────────────────

    public int GetSourceAttributes(out nint ppAttributes)
    {
        ppAttributes = 0;
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            return Protetto(() => (S_OK, Puntatore<IMFAttributes>(attributi)), out ppAttributes);
        }
    }

    public int GetStreamAttributes(uint dwStreamIdentifier, out nint ppAttributes)
    {
        ppAttributes = 0;
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            if (dwStreamIdentifier != 0) return MF_E_INVALIDSTREAMNUMBER;
            return Protetto(() => (S_OK, Puntatore<IMFAttributes>(flusso.Attributi)), out ppAttributes);
        }
    }

    /// <summary>I fotogrammi sono in memoria normale: la scheda video di Frame Server non serve.</summary>
    public int SetD3DManager(nint pManager)
    {
        lock (blocco) return chiusa ? MF_E_SHUTDOWN : S_OK;
    }

    public int SetMediaType(uint dwStreamID, nint pMediaType)
    {
        if (pMediaType == 0) return E_POINTER;
        lock (blocco)
        {
            if (chiusa) return MF_E_SHUTDOWN;
            if (dwStreamID != 0) return MF_E_INVALIDSTREAMNUMBER;
            try
            {
                var tipo = (IMFMediaType)Marshal.GetObjectForIUnknown(pMediaType);
                try
                {
                    var formato = Formato(tipo);
                    if (formato is null) return MF_E_INVALIDMEDIATYPE;
                    flusso.ImpostaFormato(formato.Value);
                    RegistroWebcam.Scrivi($"Formato scelto: {formato}");
                    return S_OK;
                }
                finally { Libera(tipo); }
            }
            catch (Exception errore) { return Codice(errore); }
        }
    }

    // ── IMFGetService e IKsControl: niente da offrire ───────────────

    public int GetService(ref Guid guidService, ref Guid riid, out nint ppvObject)
    {
        ppvObject = 0;
        return MF_E_UNSUPPORTED_SERVICE;
    }

    public int KsProperty(nint property, uint propertyLength, nint propertyData, uint dataLength, nint bytesReturned)
    {
        AzzeraSeValido(bytesReturned);
        return HRESULT_ERROR_SET_NOT_FOUND;
    }

    public int KsMethod(nint method, uint methodLength, nint methodData, uint dataLength, nint bytesReturned)
    {
        AzzeraSeValido(bytesReturned);
        return HRESULT_ERROR_SET_NOT_FOUND;
    }

    public int KsEvent(nint ksEvent, uint eventLength, nint eventData, uint dataLength, nint bytesReturned)
    {
        AzzeraSeValido(bytesReturned);
        return HRESULT_ERROR_SET_NOT_FOUND;
    }

    // ── Aiuti ──────────────────────────────────────────────────────

    /// <summary>Il formato corrente del descrittore di flusso scelto dall'app, se è uno dei nostri.</summary>
    private static FormatoWebcam? FormatoCorrente(IMFStreamDescriptor descrittoreFlusso)
    {
        if (descrittoreFlusso.GetMediaTypeHandler(out var gestore) < 0) return null;
        try
        {
            if (gestore.GetCurrentMediaType(out var tipo) < 0) return null;
            try { return Formato(tipo); }
            finally { Libera(tipo); }
        }
        finally { Libera(gestore); }
    }

    internal static FormatoWebcam? Formato(IMFMediaType tipo)
    {
        if (tipo.GetUINT64(ref MF_MT_FRAME_SIZE, out var misura) < 0) return null;
        var larghezza = (int)(misura >> 32);
        var altezza = (int)(misura & 0xFFFFFFFF);
        foreach (var formato in FormatiWebcam.Tutti)
        {
            if (formato.Larghezza == larghezza && formato.Altezza == altezza) return formato;
        }
        return null;
    }

    private static int Codice(Exception errore) => errore.HResult < 0 ? errore.HResult : E_FAIL;

    private static int Protetto(Func<int> azione)
    {
        try { return azione(); }
        catch (Exception errore) { return Codice(errore); }
    }

    private static int Protetto(Func<(int Hr, nint Puntatore)> azione, out nint risultato)
    {
        try
        {
            var (hr, puntatore) = azione();
            risultato = puntatore;
            return hr;
        }
        catch (Exception errore)
        {
            risultato = 0;
            return Codice(errore);
        }
    }
}
