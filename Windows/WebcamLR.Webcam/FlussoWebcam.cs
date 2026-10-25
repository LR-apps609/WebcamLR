using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using static WebcamLR.Webcam.FunzioniMF;

namespace WebcamLR.Webcam;

/// <summary>
/// L'unico flusso della webcam: NV12 nei formati di <see cref="FormatiWebcam"/>, a 30 o 60 fotogrammi al secondo.
/// Frame Server chiede i fotogrammi uno alla volta (RequestSample); un thread li consegna al ritmo del formato scelto
/// (<see cref="RitmoWebcam"/>), prendendo l'ultimo fotogramma scritto dall'app nella memoria condivisa, oppure
/// la schermata di attesa con le sue dissolvenze (<see cref="CompositoreWebcam"/>, uguale nel filtro DirectShow). A 60 fps con il telefono a 30 ogni fotogramma del telefono esce due volte: l'app riceve
/// comunque 60 fotogrammi al secondo, regolari.
/// </summary>
[ClassInterface(ClassInterfaceType.None)]
public sealed class FlussoWebcam : IMFMediaStream2, IMFMediaStream, IMFMediaEventGenerator, IKsControl
{
    private readonly SorgenteWebcam sorgente;
    private readonly uint id;
    private readonly object blocco = new();
    private readonly IMFMediaEventQueue coda;
    private readonly ConcurrentQueue<nint> richieste = new();
    private readonly AutoResetEvent nuovaRichiesta = new(false);
    private readonly ManualResetEvent fine = new(false);
    private Thread? consegna;
    private int stato = MF_STREAM_STATE_STOPPED;
    private bool chiuso;
    private FormatoWebcam formato = FormatiWebcam.Predefinito;

    // Solo il thread di consegna usa questi.
    private MemoriaCondivisa? memoria;
    private long prossimoTentativoMemoria;
    /// <summary>Video o schermata di attesa: creato dal thread di consegna, nella lingua del sistema (Frame Server non ha un utente).</summary>
    private CompositoreWebcam? compositore;

    internal IMFAttributes Attributi { get; }
    internal IMFStreamDescriptor Descrittore { get; }
    internal long FotogrammiConsegnati { get; private set; }

    internal FormatoWebcam Formato { get { lock (blocco) return formato; } }

    internal FlussoWebcam(SorgenteWebcam sorgente, uint id)
    {
        this.sorgente = sorgente;
        this.id = id;
        Verifica(MFCreateAttributes(out var attributi, 10), "MFCreateAttributes");
        Attributi = attributi;
        ImpostaAttributiFlusso(Attributi);
        Verifica(MFCreateEventQueue(out coda), "MFCreateEventQueue");

        var tipi = FormatiWebcam.Tutti.Select(CreaTipo).ToArray();
        var puntatori = tipi.Select(Puntatore<IMFMediaType>).ToArray();
        try
        {
            Verifica(MFCreateStreamDescriptor(id, (uint)tipi.Length, puntatori, out var descrittore), "MFCreateStreamDescriptor");
            Descrittore = descrittore;
        }
        finally
        {
            foreach (var p in puntatori) Marshal.Release(p);
        }
        Verifica(Descrittore.GetMediaTypeHandler(out var gestore), "GetMediaTypeHandler");
        try { Verifica(gestore.SetCurrentMediaType(tipi[0]), "SetCurrentMediaType"); }
        finally { Libera(gestore); }
        foreach (var tipo in tipi) Libera(tipo);

        // Gli stessi attributi anche sul descrittore: Frame Server li legge da lì.
        Verifica(Descrittore.SetGUID(ref MF_DEVICESTREAM_STREAM_CATEGORY, ref PINNAME_VIDEO_CAPTURE), "categoria");
        Verifica(Descrittore.SetUINT32(ref MF_DEVICESTREAM_STREAM_ID, id), "id");
        Verifica(Descrittore.SetUINT32(ref MF_DEVICESTREAM_FRAMESERVER_SHARED, 1), "condiviso");
        Verifica(Descrittore.SetUINT32(ref MF_DEVICESTREAM_ATTRIBUTE_FRAMESOURCE_TYPES, MFFrameSourceTypes_Color), "colore");
    }

    private static void ImpostaAttributiFlusso(IMFAttributes attributi)
    {
        Verifica(attributi.SetGUID(ref MF_DEVICESTREAM_STREAM_CATEGORY, ref PINNAME_VIDEO_CAPTURE), "categoria");
        Verifica(attributi.SetUINT32(ref MF_DEVICESTREAM_STREAM_ID, 0), "id");
        Verifica(attributi.SetUINT32(ref MF_DEVICESTREAM_FRAMESERVER_SHARED, 1), "condiviso");
        Verifica(attributi.SetUINT32(ref MF_DEVICESTREAM_ATTRIBUTE_FRAMESOURCE_TYPES, MFFrameSourceTypes_Color), "colore");
    }

    /// <summary>
    /// Un formato NV12 descritto per intero: le app di chiamata (il nuovo Teams per primo) sono pignole, e un attributo
    /// mancante (frequenza, interlacciamento, passo) è la causa più probabile di «l'anteprima va, l'altro non vede».
    /// </summary>
    private static IMFMediaType CreaTipo(FormatoWebcam f)
    {
        Verifica(MFCreateMediaType(out var tipo), "MFCreateMediaType");
        Verifica(tipo.SetGUID(ref MF_MT_MAJOR_TYPE, ref MFMediaType_Video), "major");
        Verifica(tipo.SetGUID(ref MF_MT_SUBTYPE, ref MFVideoFormat_NV12), "subtype");
        Verifica(tipo.SetUINT64(ref MF_MT_FRAME_SIZE, Coppia((uint)f.Larghezza, (uint)f.Altezza)), "misura");
        Verifica(tipo.SetUINT64(ref MF_MT_FRAME_RATE, Coppia((uint)f.Fps, 1)), "fps");
        Verifica(tipo.SetUINT64(ref MF_MT_FRAME_RATE_RANGE_MAX, Coppia((uint)f.Fps, 1)), "fps max");
        Verifica(tipo.SetUINT64(ref MF_MT_FRAME_RATE_RANGE_MIN, Coppia((uint)f.Fps, 1)), "fps min");
        Verifica(tipo.SetUINT64(ref MF_MT_PIXEL_ASPECT_RATIO, Coppia(1, 1)), "pixel quadrati");
        Verifica(tipo.SetUINT32(ref MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive), "progressivo");
        Verifica(tipo.SetUINT32(ref MF_MT_ALL_SAMPLES_INDEPENDENT, 1), "indipendenti");
        Verifica(tipo.SetUINT32(ref MF_MT_FIXED_SIZE_SAMPLES, 1), "misura fissa");
        Verifica(tipo.SetUINT32(ref MF_MT_SAMPLE_SIZE, (uint)f.Byte), "byte");
        Verifica(tipo.SetUINT32(ref MF_MT_DEFAULT_STRIDE, (uint)f.Larghezza), "passo");
        Verifica(tipo.SetUINT32(ref MF_MT_AVG_BITRATE, (uint)Math.Min(uint.MaxValue, (long)f.Byte * 8 * f.Fps)), "bitrate");
        Verifica(tipo.SetUINT32(ref MF_MT_YUV_MATRIX, MFVideoTransferMatrix_BT709), "matrice");
        Verifica(tipo.SetUINT32(ref MF_MT_VIDEO_NOMINAL_RANGE, MFNominalRange_16_235), "gamma");
        Verifica(tipo.SetUINT32(ref MF_MT_VIDEO_PRIMARIES, MFVideoPrimaries_BT709), "primari");
        Verifica(tipo.SetUINT32(ref MF_MT_TRANSFER_FUNCTION, MFVideoTransFunc_709), "trasferimento");
        return tipo;
    }

    internal void ImpostaFormato(FormatoWebcam nuovo)
    {
        lock (blocco) formato = nuovo;
    }

    /// <summary>Chiamata dalla sorgente in Start, con il suo blocco preso. <paramref name="tempo"/>: MFGetSystemTime dell'avvio.</summary>
    internal void Avvia(long tempo)
    {
        lock (blocco)
        {
            if (chiuso) return;
            stato = MF_STREAM_STATE_RUNNING;
            AvviaConsegnaSeServe();
        }
        Verifica(AccodaConTempo(coda, MEStreamStarted, tempo), "MEStreamStarted");
    }

    /// <summary>
    /// Il thread di consegna, una volta sola. Serve anche quando Frame Server rimette il flusso in RUNNING con
    /// SetStreamState senza passare da Start: senza thread le richieste resterebbero in fila per sempre.
    /// </summary>
    private void AvviaConsegnaSeServe()
    {
        if (consegna is not null) return;
        consegna = new Thread(CicloConsegna) { IsBackground = true, Name = "WebcamLR consegna" };
        consegna.Start();
    }

    internal void Ferma(bool annuncia)
    {
        bool eraAvviato;
        lock (blocco)
        {
            if (chiuso) return;
            eraAvviato = stato != MF_STREAM_STATE_STOPPED;
            stato = MF_STREAM_STATE_STOPPED;
        }
        SvuotaRichieste();
        if (annuncia && eraAvviato)
        {
            var tipo = GUID_NULL;
            coda.QueueEventParamVar(MEStreamStopped, ref tipo, S_OK, 0);
        }
    }

    internal void Chiudi()
    {
        Thread? thread;
        lock (blocco)
        {
            if (chiuso) return;
            chiuso = true;
            stato = MF_STREAM_STATE_STOPPED;
            thread = consegna;
        }
        fine.Set();
        thread?.Join(TimeSpan.FromSeconds(2));
        SvuotaRichieste();
        try { coda.Shutdown(); } catch (Exception) { }
        // La memoria condivisa la chiude il thread di consegna quando esce (è l'unico che la usa): chiuderla da qui,
        // con il thread ancora dentro una copia dopo un Join scaduto, toglierebbe la vista sotto i suoi piedi e un
        // accesso a memoria non valida farebbe cadere tutto Frame Server.
    }

    private void SvuotaRichieste()
    {
        while (richieste.TryDequeue(out var gettone))
        {
            if (gettone != 0) Marshal.Release(gettone);
        }
    }

    // ── IMFMediaEventGenerator ─────────────────────────────────────

    public int GetEvent(uint dwFlags, out nint ppEvent)
    {
        ppEvent = 0;
        lock (blocco) { if (chiuso) return MF_E_SHUTDOWN; }
        try { return coda.GetEvent(dwFlags, out ppEvent); }
        catch (Exception errore) { return Codice(errore); }
    }

    public int BeginGetEvent(nint pCallback, nint punkState)
    {
        lock (blocco) { if (chiuso) return MF_E_SHUTDOWN; }
        try { return coda.BeginGetEvent(pCallback, punkState); }
        catch (Exception errore) { return Codice(errore); }
    }

    public int EndGetEvent(nint pResult, out nint ppEvent)
    {
        ppEvent = 0;
        try { return coda.EndGetEvent(pResult, out ppEvent); }
        catch (Exception errore) { return Codice(errore); }
    }

    public int QueueEvent(uint met, ref Guid guidExtendedType, int hrStatus, nint pvValue)
    {
        lock (blocco) { if (chiuso) return MF_E_SHUTDOWN; }
        try { return coda.QueueEventParamVar(met, ref guidExtendedType, hrStatus, pvValue); }
        catch (Exception errore) { return Codice(errore); }
    }

    // ── IMFMediaStream ─────────────────────────────────────────────

    public int GetMediaSource(out nint ppMediaSource)
    {
        ppMediaSource = 0;
        lock (blocco) { if (chiuso) return MF_E_SHUTDOWN; }
        try
        {
            ppMediaSource = Puntatore<IMFMediaSource>(sorgente);
            return S_OK;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    public int GetStreamDescriptor(out nint ppStreamDescriptor)
    {
        ppStreamDescriptor = 0;
        lock (blocco) { if (chiuso) return MF_E_SHUTDOWN; }
        try
        {
            ppStreamDescriptor = Puntatore<IMFStreamDescriptor>(Descrittore);
            return S_OK;
        }
        catch (Exception errore) { return Codice(errore); }
    }

    /// <summary>Frame Server chiede un fotogramma: lo si mette in fila e lo consegna il thread, al ritmo del formato.</summary>
    public int RequestSample(nint pToken)
    {
        lock (blocco)
        {
            if (chiuso) return MF_E_SHUTDOWN;
            if (stato != MF_STREAM_STATE_RUNNING) return MF_E_INVALIDREQUEST;
            if (pToken != 0) Marshal.AddRef(pToken);
            richieste.Enqueue(pToken);
        }
        nuovaRichiesta.Set();
        return S_OK;
    }

    // ── IMFMediaStream2 ────────────────────────────────────────────

    public int SetStreamState(int value)
    {
        if (value is not (MF_STREAM_STATE_STOPPED or MF_STREAM_STATE_PAUSED or MF_STREAM_STATE_RUNNING)) return E_INVALIDARG;
        lock (blocco)
        {
            if (chiuso) return MF_E_SHUTDOWN;
            stato = value;
            if (value == MF_STREAM_STATE_RUNNING) AvviaConsegnaSeServe();
        }
        if (value != MF_STREAM_STATE_RUNNING) SvuotaRichieste();
        return S_OK;
    }

    public int GetStreamState(out int value)
    {
        lock (blocco)
        {
            value = stato;
            return chiuso ? MF_E_SHUTDOWN : S_OK;
        }
    }

    // ── IKsControl ─────────────────────────────────────────────────

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

    // ── Consegna dei fotogrammi ────────────────────────────────────

    /// <summary>
    /// Il corpo del thread, protetto: un'eccezione non gestita in un thread .NET chiude l'intero processo, cioè
    /// Frame Server con tutte le webcam del PC. Qui si chiude anche la memoria condivisa, quando il thread esce.
    /// </summary>
    private void CicloConsegna()
    {
        try { CicloConsegnaInterno(); }
        catch (Exception errore) { RegistroWebcam.Scrivi($"Thread di consegna fermato: {errore}"); }
        finally
        {
            try { memoria?.Dispose(); } catch (Exception) { }
            memoria = null;
            // Il prossimo Start (o SetStreamState RUNNING) ne crea uno nuovo.
            lock (blocco) consegna = null;
        }
    }

    private void CicloConsegnaInterno()
    {
        using var orologio = new OrologioPreciso();
        var ultimaConsegna = Stopwatch.GetTimestamp() - Ritmo().IntervalloTick;
        var attese = new WaitHandle[] { fine, nuovaRichiesta };
        while (true)
        {
            if (richieste.IsEmpty)
            {
                if (WaitHandle.WaitAny(attese, 500) == 0) return;
                continue;
            }
            if (fine.WaitOne(0)) return;

            // Il ritmo del formato scelto adesso (30 o 60 fps): un cambio di formato vale dal fotogramma dopo.
            // Con l'app che manda video si va con i suoi fotogrammi (meno ritardo), altrimenti a ritmo fisso.
            var ritmo = Ritmo();
            var conApp = memoria is not null && AppAttiva();
            if (conApp)
            {
                orologio.AspettaFino(ultimaConsegna + ritmo.MinimoTick);
                var restante = ultimaConsegna + ritmo.MassimoTick - Stopwatch.GetTimestamp();
                if (restante > 0) memoria!.Aspetta((int)(restante * 1000 / Stopwatch.Frequency));
            }
            else
            {
                orologio.AspettaFino(ultimaConsegna + ritmo.IntervalloTick);
            }
            var adesso = Stopwatch.GetTimestamp();
            // A ritmo fisso si somma l'intervallo (niente deriva); dopo una pausa lunga non si recupera di corsa.
            ultimaConsegna = conApp || adesso - ultimaConsegna > ritmo.IntervalloTick * 3 ? adesso : ultimaConsegna + ritmo.IntervalloTick;

            if (!richieste.TryDequeue(out var gettone)) continue;
            try { Consegna(gettone); }
            catch (Exception errore) { RegistroWebcam.Scrivi($"Consegna non riuscita: {errore.Message}"); }
            finally { if (gettone != 0) Marshal.Release(gettone); }
        }
    }

    private bool AppAttiva() => compositore?.AppAttiva(Environment.TickCount64) == true;

    private RitmoWebcam Ritmo() => new(Formato.Fps, Stopwatch.Frequency);

    private void Consegna(nint gettone)
    {
        FormatoWebcam f;
        lock (blocco)
        {
            if (stato != MF_STREAM_STATE_RUNNING || chiuso) return;
            f = formato;
        }
        var dati = Fotogramma(f);

        Verifica(MFCreateMemoryBuffer((uint)f.Byte, out var buffer), "MFCreateMemoryBuffer");
        IMFSample? campione = null;
        try
        {
            Verifica(buffer.Lock(out var puntatore, out var massimo, out _), "Lock");
            try
            {
                if (massimo < f.Byte) throw new InvalidOperationException("Buffer troppo piccolo");
                Marshal.Copy(dati, 0, puntatore, f.Byte);
            }
            finally { buffer.Unlock(); }
            Verifica(buffer.SetCurrentLength((uint)f.Byte), "SetCurrentLength");

            Verifica(MFCreateSample(out campione), "MFCreateSample");
            Verifica(campione.AddBuffer(buffer), "AddBuffer");
            // Orologio di sistema, sempre crescente: Frame Server e le app ordinano i fotogrammi con questo.
            Verifica(campione.SetSampleTime(MFGetSystemTime()), "SetSampleTime");
            Verifica(campione.SetSampleDuration(new RitmoWebcam(f.Fps, Stopwatch.Frequency).Durata100ns), "SetSampleDuration");
            Verifica(campione.SetUINT32(ref MFSampleExtension_CleanPoint, 1), "CleanPoint");
            if (gettone != 0) Verifica(campione.SetUnknown(ref MFSampleExtension_Token, gettone), "Token");

            var puntatoreCampione = Puntatore<IMFSample>(campione);
            try
            {
                var tipo = GUID_NULL;
                Verifica(coda.QueueEventParamUnk(MEMediaSample, ref tipo, S_OK, puntatoreCampione), "MEMediaSample");
            }
            finally { Marshal.Release(puntatoreCampione); }
            FotogrammiConsegnati++;
        }
        finally
        {
            Libera(campione);
            Libera(buffer);
        }
    }

    /// <summary>L'ultimo fotogramma dell'app nel formato chiesto, oppure la schermata di attesa.</summary>
    private byte[] Fotogramma(FormatoWebcam f)
    {
        var adesso = Environment.TickCount64;
        if (memoria is null && adesso >= prossimoTentativoMemoria)
        {
            try
            {
                memoria = MemoriaCondivisa.Crea();
                RegistroWebcam.Scrivi("Memoria condivisa pronta");
            }
            catch (Exception errore)
            {
                prossimoTentativoMemoria = adesso + 5000;
                RegistroWebcam.Scrivi($"Memoria condivisa non disponibile: {errore.Message}");
            }
        }
        compositore ??= new CompositoreWebcam(LinguaDiSistema.Leggi(), RegistroWebcam.Scrivi);
        return compositore.Fotogramma(memoria?.Anello, f, adesso);
    }

    private static int Codice(Exception errore) => errore.HResult < 0 ? errore.HResult : E_FAIL;
}
