using System.Diagnostics;
using System.Runtime.InteropServices;
using static WebcamLR.Webcam.DirectShow.ComNativo;

namespace WebcamLR.Webcam.DirectShow;

/// <summary>
/// Il pin d'uscita «Cattura» del filtro. Si collega al pin d'ingresso dell'app (Connect, con il formato scelto con
/// IAMStreamConfig::SetFormat o il primo adatto), negozia l'allocatore (quello dell'app, oppure uno nostro) e, mentre
/// il grafo è in Run, un thread consegna i fotogrammi con IMemInputPin::Receive al ritmo del formato.
/// Si dichiara PIN_CATEGORY_CAPTURE con IKsPropertySet: Chrome e le altre app cercano il pin di cattura così.
/// </summary>
[ClassInterface(ClassInterfaceType.None)]
public sealed unsafe class PinWebcam : IPin, IAMStreamConfig, IKsPropertySet, IQualityControl
{
    internal const string Id = "Cattura";

    private readonly FiltroWebcam filtro;
    private object Blocco => filtro.Blocco;

    // Con il blocco del filtro.
    private nint collegato;
    private nint ingresso;
    private nint allocatore;
    private FormatoDirectShow? formatoCollegato;
    private int passo;
    private FormatoDirectShow? preferito;
    private Thread? consegna;
    private ManualResetEvent? fineConsegna;
    private bool consegneSospese;
    private readonly AutoResetEvent segnaleStato = new(false);

    internal PinWebcam(FiltroWebcam filtro) => this.filtro = filtro;

    internal string Descrizione
    {
        get { lock (Blocco) return formatoCollegato?.ToString() ?? "non collegato"; }
    }

    private FormatoDirectShow[] FormatiInOrdine()
    {
        var scelto = preferito;
        return scelto is { } p ? [p, .. FormatiDirectShow.Tutti.Where(f => f != p)] : [.. FormatiDirectShow.Tutti];
    }

    // ── Stati del filtro ───────────────────────────────────────────

    /// <summary>Da fermo a pausa: allocatore pronto e thread di consegna avviato (consegna solo in Run).</summary>
    internal int Attiva()
    {
        nint a;
        lock (Blocco)
        {
            if (collegato == 0 || allocatore == 0 || consegna is not null) return S_OK;
            a = allocatore;
            Marshal.AddRef(a);
        }
        try
        {
            var hr = AllocCommit(a);
            if (hr < 0)
            {
                RegistroDirectShow.Scrivi($"Commit dell'allocatore non riuscito: 0x{hr:X8}");
                return hr;
            }
        }
        finally { Marshal.Release(a); }
        lock (Blocco)
        {
            consegneSospese = false;
            var fine = new ManualResetEvent(false);
            fineConsegna = fine;
            consegna = new Thread(() => CicloConsegna(fine)) { IsBackground = true, Name = "WebcamLR DirectShow" };
            consegna.SetApartmentState(ApartmentState.MTA);
            consegna.Start();
        }
        return S_OK;
    }

    /// <summary>Stop: ferma il thread e libera i buffer (Decommit sveglia un GetBuffer in attesa).</summary>
    internal void Disattiva()
    {
        Thread? thread;
        ManualResetEvent? fine;
        nint a;
        lock (Blocco)
        {
            thread = consegna;
            fine = fineConsegna;
            consegna = null;
            fineConsegna = null;
            a = allocatore;
            if (a != 0) Marshal.AddRef(a);
        }
        fine?.Set();
        segnaleStato.Set();
        if (a != 0)
        {
            AllocDecommit(a);
            Marshal.Release(a);
        }
        if (thread is not null && thread != Thread.CurrentThread && !thread.Join(TimeSpan.FromSeconds(2)))
            RegistroDirectShow.Scrivi("Il thread di consegna non si è fermato in 2 s");
    }

    internal void StatoCambiato()
    {
        lock (Blocco) consegneSospese = false;
        segnaleStato.Set();
    }

    // ── IPin ───────────────────────────────────────────────────────

    public int Connect(nint pReceivePin, nint pmt)
    {
        if (pReceivePin == 0) return E_POINTER;
        try
        {
            FormatoDirectShow[] candidati;
            lock (Blocco)
            {
                if (collegato != 0) return VFW_E_ALREADY_CONNECTED;
                if (filtro.Stato != State_Stopped) return VFW_E_NOT_STOPPED;
                var ordine = FormatiInOrdine();
                if (pmt != 0)
                {
                    // Tipo dato dall'app (anche incompleto): i nostri compatibili, quello scelto con SetFormat per primo.
                    var compatibili = TipoMedia.Compatibili((AM_MEDIA_TYPE*)pmt).ToHashSet();
                    candidati = ordine.Where(compatibili.Contains).ToArray();
                }
                else
                {
                    candidati = preferito is { } p ? [p] : ordine;
                }
            }
            foreach (var formato in candidati)
            {
                if (ProvaCollegamento(pReceivePin, formato) >= 0)
                {
                    RegistroDirectShow.Scrivi($"Collegato: {formato}");
                    return S_OK;
                }
            }
            RegistroDirectShow.Scrivi($"Nessun formato accettato ({candidati.Length} provati)");
            return VFW_E_NO_ACCEPTABLE_TYPES;
        }
        catch (Exception errore) { return FiltroWebcam.Codice(errore); }
    }

    private int ProvaCollegamento(nint ricevente, FormatoDirectShow formato)
    {
        AM_MEDIA_TYPE tipo;
        TipoMedia.Riempi(&tipo, formato);
        var io = Marshal.GetComInterfaceForObject(this, typeof(IPin));
        try
        {
            // Come CBasePin::AttemptConnection: collegati già prima di ReceiveConnection, perché l'app che riceve può
            // chiederci ConnectedTo o ConnectionMediaType mentre decide. Se rifiuta, si torna indietro.
            Marshal.AddRef(ricevente);
            lock (Blocco)
            {
                collegato = ricevente;
                formatoCollegato = formato;
                passo = formato.BytePerRiga;
            }
            var hr = PinReceiveConnection(ricevente, io, &tipo);
            if (hr < 0)
            {
                Scollega();
                return hr;
            }
            hr = ScegliAllocatore(ricevente, formato);
            if (hr < 0)
            {
                RegistroDirectShow.Scrivi($"Allocatore non concordato per {formato}: 0x{hr:X8}");
                PinDisconnect(ricevente);
                Scollega();
            }
            return hr;
        }
        finally
        {
            Marshal.Release(io);
            TipoMedia.LiberaContenuto(&tipo);
        }
    }

    /// <summary>
    /// Come CBaseOutputPin::DecideAllocator: prima l'allocatore dell'app, altrimenti uno nostro (CLSID_MemoryAllocator),
    /// con buffer grandi almeno un fotogramma.
    /// </summary>
    private int ScegliAllocatore(nint ricevente, FormatoDirectShow formato)
    {
        var mem = QueryInterface(ricevente, IID_IMemInputPin);
        if (mem == 0) return E_NOINTERFACE;
        ALLOCATOR_PROPERTIES richiesta = default;
        MemGetAllocatorRequirements(mem, &richiesta);

        var hr = MemGetAllocator(mem, out var a);
        if (hr >= 0 && a != 0)
        {
            if (Configura(a, richiesta, formato) && MemNotifyAllocator(mem, a, false) >= 0) return Tieni(mem, a);
            Libera(ref a);
        }
        a = CreaAllocatore();
        if (a == 0)
        {
            Libera(ref mem);
            return VFW_E_NO_ALLOCATOR;
        }
        if (Configura(a, richiesta, formato) && (hr = MemNotifyAllocator(mem, a, false)) >= 0) return Tieni(mem, a);
        Libera(ref a);
        Libera(ref mem);
        return hr < 0 ? hr : VFW_E_NO_ALLOCATOR;
    }

    private int Tieni(nint mem, nint a)
    {
        lock (Blocco)
        {
            ingresso = mem;
            allocatore = a;
        }
        return S_OK;
    }

    private static bool Configura(nint a, ALLOCATOR_PROPERTIES richiesta, FormatoDirectShow formato)
    {
        var voluta = new ALLOCATOR_PROPERTIES
        {
            cBuffers = Math.Max(richiesta.cBuffers, 2),
            cbBuffer = Math.Max(richiesta.cbBuffer, formato.ByteImmagine),
            cbAlign = Math.Max(richiesta.cbAlign, 1),
            cbPrefix = richiesta.cbPrefix,
        };
        ALLOCATOR_PROPERTIES ottenuta = default;
        return AllocSetProperties(a, &voluta, &ottenuta) >= 0 && ottenuta.cBuffers >= 1 && ottenuta.cbBuffer >= formato.ByteImmagine;
    }

    private void Scollega()
    {
        lock (Blocco)
        {
            Libera(ref allocatore);
            Libera(ref ingresso);
            Libera(ref collegato);
            formatoCollegato = null;
            passo = 0;
        }
    }

    public int ReceiveConnection(nint pConnector, nint pmt) => E_UNEXPECTED; // pin d'uscita

    public int Disconnect()
    {
        lock (Blocco)
        {
            if (collegato == 0) return S_FALSE;
            if (filtro.Stato != State_Stopped) return VFW_E_NOT_STOPPED;
        }
        Scollega();
        RegistroDirectShow.Scrivi("Scollegato");
        return S_OK;
    }

    public int ConnectedTo(nint pPin)
    {
        if (pPin == 0) return E_POINTER;
        lock (Blocco)
        {
            *(nint*)pPin = collegato;
            if (collegato == 0) return VFW_E_NOT_CONNECTED;
            Marshal.AddRef(collegato);
            return S_OK;
        }
    }

    public int ConnectionMediaType(nint pmt)
    {
        if (pmt == 0) return E_POINTER;
        lock (Blocco)
        {
            if (formatoCollegato is not { } f)
            {
                *(AM_MEDIA_TYPE*)pmt = default;
                return VFW_E_NOT_CONNECTED;
            }
            try
            {
                TipoMedia.Riempi((AM_MEDIA_TYPE*)pmt, f);
                return S_OK;
            }
            catch (Exception) { return E_OUTOFMEMORY; }
        }
    }

    /// <summary>PIN_INFO: IBaseFilter* (con AddRef), PIN_DIRECTION, WCHAR achName[128].</summary>
    public int QueryPinInfo(nint pInfo)
    {
        if (pInfo == 0) return E_POINTER;
        try
        {
            *(nint*)pInfo = Marshal.GetComInterfaceForObject(filtro, typeof(IBaseFilter));
            *(int*)((byte*)pInfo + IntPtr.Size) = PINDIR_OUTPUT;
            FiltroWebcam.ScriviNome((char*)((byte*)pInfo + IntPtr.Size + 4), Id);
            return S_OK;
        }
        catch (Exception errore) { return FiltroWebcam.Codice(errore); }
    }

    public int QueryDirection(nint pPinDir)
    {
        if (pPinDir == 0) return E_POINTER;
        *(int*)pPinDir = PINDIR_OUTPUT;
        return S_OK;
    }

    public int QueryId(nint Id)
    {
        if (Id == 0) return E_POINTER;
        *(nint*)Id = Marshal.StringToCoTaskMemUni(PinWebcam.Id);
        return S_OK;
    }

    /// <summary>S_OK solo per un tipo completo che è uno dei nostri.</summary>
    public int QueryAccept(nint pmt)
    {
        if (pmt == 0) return E_POINTER;
        try
        {
            var tipo = (AM_MEDIA_TYPE*)pmt;
            if (!TipoMedia.Leggi(tipo, out var sottotipo, out var info) || sottotipo == Guid.Empty || info is null) return S_FALSE;
            return TipoMedia.Compatibili(tipo).Any() ? S_OK : S_FALSE;
        }
        catch (Exception) { return S_FALSE; }
    }

    public int EnumMediaTypes(nint ppEnum)
    {
        if (ppEnum == 0) return E_POINTER;
        try
        {
            FormatoDirectShow[] formati;
            lock (Blocco) formati = FormatiInOrdine();
            *(nint*)ppEnum = Marshal.GetComInterfaceForObject(new EnumeratoreTipi(formati), typeof(IEnumMediaTypes));
            return S_OK;
        }
        catch (Exception errore) { return FiltroWebcam.Codice(errore); }
    }

    public int QueryInternalConnections(nint apPin, nint nPin) => E_NOTIMPL;
    public int EndOfStream() => E_UNEXPECTED;
    public int BeginFlush() => E_UNEXPECTED;
    public int EndFlush() => E_UNEXPECTED;
    public int NewSegment(long tStart, long tStop, double dRate) => S_OK;

    // ── IAMStreamConfig ────────────────────────────────────────────

    /// <summary>
    /// L'app sceglie il formato (Chrome lo fa prima di collegare, OBS anche dopo). Già collegati: se l'app che riceve
    /// lo accetta, si chiede al grafo di ricollegare il pin, e Connect userà il formato scelto.
    /// </summary>
    public int SetFormat(nint pmt)
    {
        try
        {
            if (pmt == 0)
            {
                lock (Blocco) preferito = null;
                return S_OK;
            }
            var scelto = TipoMedia.Compatibili((AM_MEDIA_TYPE*)pmt).Cast<FormatoDirectShow?>().FirstOrDefault();
            if (scelto is not { } f) return VFW_E_INVALIDMEDIATYPE;
            nint ricevente, grafo;
            lock (Blocco)
            {
                preferito = f;
                if (collegato == 0 || formatoCollegato == f) return S_OK;
                if (filtro.Stato != State_Stopped) return VFW_E_NOT_STOPPED;
                ricevente = collegato;
                Marshal.AddRef(ricevente);
                grafo = filtro.Grafo;
            }
            try
            {
                AM_MEDIA_TYPE tipo;
                TipoMedia.Riempi(&tipo, f);
                try
                {
                    if (PinQueryAccept(ricevente, &tipo) != S_OK) return VFW_E_INVALIDMEDIATYPE;
                }
                finally { TipoMedia.LiberaContenuto(&tipo); }
                if (grafo == 0) return S_OK;
                var io = Marshal.GetComInterfaceForObject(this, typeof(IPin));
                try { return GraphReconnect(grafo, io); }
                finally { Marshal.Release(io); }
            }
            finally { Marshal.Release(ricevente); }
        }
        catch (Exception errore) { return FiltroWebcam.Codice(errore); }
    }

    public int GetFormat(nint ppmt)
    {
        if (ppmt == 0) return E_POINTER;
        try
        {
            FormatoDirectShow f;
            lock (Blocco) f = formatoCollegato ?? preferito ?? FormatiDirectShow.Predefinito;
            *(AM_MEDIA_TYPE**)ppmt = TipoMedia.Crea(f);
            return S_OK;
        }
        catch (Exception) { return E_OUTOFMEMORY; }
    }

    public int GetNumberOfCapabilities(nint piCount, nint piSize)
    {
        if (piCount == 0 || piSize == 0) return E_POINTER;
        *(int*)piCount = FormatiDirectShow.Tutti.Count;
        *(int*)piSize = StruttureDirectShow.DimensioneCapacita;
        return S_OK;
    }

    public int GetStreamCaps(int iIndex, nint ppmt, nint pSCC)
    {
        if (ppmt == 0 || pSCC == 0) return E_POINTER;
        if (iIndex < 0) return E_INVALIDARG;
        if (iIndex >= FormatiDirectShow.Tutti.Count) return S_FALSE;
        try
        {
            var f = FormatiDirectShow.Tutti[iIndex];
            StruttureDirectShow.ScriviCapacita(new Span<byte>((void*)pSCC, StruttureDirectShow.DimensioneCapacita), f);
            *(AM_MEDIA_TYPE**)ppmt = TipoMedia.Crea(f);
            return S_OK;
        }
        catch (Exception) { return E_OUTOFMEMORY; }
    }

    // ── IKsPropertySet: solo la categoria del pin ──────────────────

    public int Set(ref Guid guidPropSet, uint dwPropID, nint pInstanceData, uint cbInstanceData, nint pPropData, uint cbPropData) => E_NOTIMPL;

    public int Get(ref Guid guidPropSet, uint dwPropID, nint pInstanceData, uint cbInstanceData, nint pPropData, uint cbPropData, nint pcbReturned)
    {
        if (guidPropSet != GuidDirectShow.AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
        if (dwPropID != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
        if (pPropData == 0 && pcbReturned == 0) return E_POINTER;
        if (pcbReturned != 0) *(uint*)pcbReturned = (uint)sizeof(Guid);
        if (pPropData == 0) return S_OK;
        if (cbPropData < sizeof(Guid)) return E_UNEXPECTED;
        *(Guid*)pPropData = GuidDirectShow.PIN_CATEGORY_CAPTURE;
        return S_OK;
    }

    public int QuerySupported(ref Guid guidPropSet, uint dwPropID, nint pTypeSupport)
    {
        if (guidPropSet != GuidDirectShow.AMPROPSETID_Pin) return E_PROP_SET_UNSUPPORTED;
        if (dwPropID != AMPROPERTY_PIN_CATEGORY) return E_PROP_ID_UNSUPPORTED;
        if (pTypeSupport != 0) *(uint*)pTypeSupport = KSPROPERTY_SUPPORT_GET;
        return S_OK;
    }

    // ── IQualityControl: una webcam dal vivo non rallenta su richiesta ──

    public int Notify(nint pSelf, Quality q) => E_NOTIMPL;
    public int SetSink(nint piqc) => S_OK;

    // ── Consegna dei fotogrammi ────────────────────────────────────

    /// <summary>Protetto: un'eccezione non gestita in un thread .NET chiuderebbe l'app dell'utente.</summary>
    private void CicloConsegna(ManualResetEvent fine)
    {
        var fonte = new FonteFotogrammi();
        try { CicloConsegnaInterno(fine, fonte); }
        catch (Exception errore) { RegistroDirectShow.Scrivi($"Thread di consegna fermato: {errore}"); }
        finally
        {
            try { fonte.Dispose(); } catch (Exception) { }
            // L'evento di fine non si chiude qui: Disattiva lo può ancora segnalare. Se il thread esce per un errore,
            // il prossimo Pause ne avvia uno nuovo.
            lock (Blocco)
            {
                if (consegna == Thread.CurrentThread)
                {
                    consegna = null;
                    fineConsegna = null;
                }
            }
        }
    }

    private void CicloConsegnaInterno(ManualResetEvent fine, FonteFotogrammi fonte)
    {
        using var orologio = new OrologioPreciso();
        var attese = new WaitHandle[] { fine, segnaleStato };
        long ultimaConsegna = 0;
        var primo = true;
        var errori = 0;
        var spazioPiccolo = false;
        long consegnati = 0;

        while (!fine.WaitOne(0))
        {
            nint mem, a;
            FormatoDirectShow formato;
            int passoAdesso;
            lock (Blocco)
            {
                var pronto = filtro.Stato == State_Running && !consegneSospese && ingresso != 0 && allocatore != 0 && formatoCollegato is not null;
                if (!pronto)
                {
                    mem = a = 0;
                    formato = default;
                    passoAdesso = 0;
                }
                else
                {
                    mem = ingresso;
                    a = allocatore;
                    Marshal.AddRef(mem);
                    Marshal.AddRef(a);
                    formato = formatoCollegato!.Value;
                    passoAdesso = passo;
                }
            }
            if (mem == 0)
            {
                primo = true;
                WaitHandle.WaitAny(attese, 200);
                continue;
            }

            nint campione = 0;
            var hr = S_OK;
            try
            {
                // Il ritmo del formato (30 o 60 fps); con l'app che manda video si va con i suoi fotogrammi.
                var ritmo = new RitmoWebcam(formato.Fps, Stopwatch.Frequency);
                if (primo) ultimaConsegna = Stopwatch.GetTimestamp() - ritmo.IntervalloTick;
                var conApp = fonte.AppAttiva;
                if (conApp)
                {
                    orologio.AspettaFino(ultimaConsegna + ritmo.MinimoTick);
                    var restante = ultimaConsegna + ritmo.MassimoTick - Stopwatch.GetTimestamp();
                    if (restante > 0) fonte.Aspetta((int)(restante * 1000 / Stopwatch.Frequency));
                }
                else
                {
                    orologio.AspettaFino(ultimaConsegna + ritmo.IntervalloTick);
                }
                var adesso = Stopwatch.GetTimestamp();
                ultimaConsegna = conApp || adesso - ultimaConsegna > ritmo.IntervalloTick * 3 ? adesso : ultimaConsegna + ritmo.IntervalloTick;
                if (fine.WaitOne(0)) break;

                // Aspetta un buffer libero; dopo Stop (Decommit) fallisce subito.
                hr = AllocGetBuffer(a, out campione);
                if (hr < 0 || campione == 0)
                {
                    hr = S_OK;
                    fine.WaitOne(10);
                    continue;
                }

                // Un renderer può chiedere righe più larghe con il primo buffer (cambio di formato dinamico).
                if (SampleGetMediaType(campione, out var tipoNuovo) == S_OK && tipoNuovo != null)
                {
                    var proposto = TipoMedia.PassoProposto(tipoNuovo, formato);
                    TipoMedia.Elimina(tipoNuovo);
                    if (proposto > 0 && proposto != passoAdesso)
                    {
                        passoAdesso = proposto;
                        lock (Blocco) passo = proposto;
                        RegistroDirectShow.Scrivi($"L'app chiede righe di {proposto} byte");
                    }
                }

                if (SampleGetPointer(campione, out var dati) < 0 || dati == null) continue;
                var dimensione = SampleGetSize(campione);
                var servono = formato.Codifica == CodificaDirectShow.Nv12 ? passoAdesso * formato.Altezza * 3 / 2 : passoAdesso * formato.Altezza;
                if (dimensione < servono)
                {
                    if (!spazioPiccolo) RegistroDirectShow.Scrivi($"Buffer troppo piccolo: {dimensione} byte, ne servono {servono}");
                    spazioPiccolo = true;
                    continue;
                }

                var nv12 = fonte.Fotogramma(formato.Anello);
                var usati = ConversioneDirectShow.Converti(nv12, formato, new Span<byte>(dati, dimensione), passoAdesso);
                SampleSetActualDataLength(campione, usati);
                if (filtro.TempoFlusso(out var inizio))
                {
                    var fineCampione = inizio + formato.Durata100ns;
                    SampleSetTime(campione, &inizio, &fineCampione);
                }
                else
                {
                    SampleSetTime(campione, null, null);
                }
                SampleSetSyncPoint(campione, true);
                SampleSetDiscontinuity(campione, primo);
                primo = false;

                hr = MemReceive(mem, campione);
                if (hr >= 0 && ++consegnati == 1) RegistroDirectShow.Scrivi($"Primo fotogramma consegnato ({formato})");
            }
            finally
            {
                Libera(ref campione);
                Marshal.Release(a);
                Marshal.Release(mem);
            }

            if (hr == S_FALSE)
            {
                // L'app non vuole altri campioni (come per CSourceStream): si riprende al prossimo Pause/Run.
                lock (Blocco) consegneSospese = true;
                RegistroDirectShow.Scrivi("L'app ha chiesto di smettere (Receive: S_FALSE)");
            }
            else if (hr < 0)
            {
                if (errori++ == 0) RegistroDirectShow.Scrivi($"Receive non riuscito: 0x{hr:X8}");
                if (errori >= 30)
                {
                    lock (Blocco) consegneSospese = true;
                    RegistroDirectShow.Scrivi("Troppi errori di Receive: consegne sospese fino al prossimo Run");
                    errori = 0;
                }
            }
            else
            {
                errori = 0;
            }
        }
    }
}
