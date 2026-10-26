using System.Runtime.InteropServices;
using WebcamLR.Ricevitore;

namespace WebcamLR.Microfono;

/// <summary>Chi dà i campioni da suonare (mono, float, 48 kHz): di solito MicrofonoTelefono.Leggi.</summary>
public delegate int LetturaAudio(Span<float> uscita);

/// <summary>
/// Il microfono del telefono verso un'uscita audio di Windows (W2), con WASAPI in modalità condivisa: altoparlanti,
/// cuffie o un cavo audio virtuale che l'utente ha installato da sé (VB-CABLE, Voicemeeter…). Così le app di chiamata e
/// OBS lo ricevono anche senza un microfono virtuale di WebcamLR, che su Windows richiede un driver firmato
/// (Documenti/Microfono Windows.md). Diamo sempre 48 kHz mono float: Windows converte per la scheda
/// (AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM). Un thread suo, svegliato dalla scheda a ogni periodo (circa 10 ms).
/// </summary>
public sealed class UscitaAudio : IDisposable
{
    private static readonly Guid ClsidEnumeratore = new("bcde0395-e52f-467c-8e3d-c4579291692e");
    private static readonly Guid IidClienteAudio = new("1cb9ad4c-dbfa-4c32-b178-c2f568a703b2");
    private static readonly Guid IidClienteRiproduzione = new("f294acfc-3146-4483-a7bf-addca7c260e2");
    private static readonly ChiaveProprieta NomeDispositivo = new() { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };

    private const int eRender = 0;
    private const uint DEVICE_STATE_ACTIVE = 1;
    private const uint STGM_READ = 0;
    private const ushort VT_LPWSTR = 31;
    private const uint CLSCTX_ALL = 0x17;
    private const int AUDCLNT_SHAREMODE_SHARED = 0;
    private const uint AUDCLNT_STREAMFLAGS_EVENTCALLBACK = 0x00040000;
    private const uint AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = 0x08000000;
    private const uint AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = 0x80000000;
    private const uint AUDCLNT_BUFFERFLAGS_SILENT = 2;
    private const ushort WAVE_FORMAT_IEEE_FLOAT = 3;
    /// <summary>Buffer chiesto alla scheda: 20 ms in unità da 100 ns. Abbastanza per non saltare, poco per non ritardare.</summary>
    private const long DurataBuffer = 200_000;

    private readonly LetturaAudio leggi;
    private readonly Thread filo;
    private readonly AutoResetEvent sveglia = new(false);
    private readonly TaskCompletionSource<string?> avvio = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private volatile bool fermare;

    private UscitaAudio(DispositivoAudio dispositivo, LetturaAudio leggi)
    {
        Dispositivo = dispositivo;
        this.leggi = leggi;
        filo = new Thread(Suona) { IsBackground = true, Name = "WebcamLR · uscita del microfono", Priority = ThreadPriority.Highest };
        filo.SetApartmentState(ApartmentState.MTA);
    }

    public DispositivoAudio Dispositivo { get; }

    /// <summary>L'uscita si è fermata da sola (scheda staccata, Windows ha cambiato formato): il motivo, per il registro.</summary>
    public event Action<string>? Interrotta;

    /// <summary>
    /// Apre l'uscita e comincia a suonare. Restituisce l'uscita, oppure il motivo per cui Windows non l'ha aperta.
    /// </summary>
    public static async Task<(UscitaAudio? Uscita, string? Errore)> ApriAsync(DispositivoAudio dispositivo, LetturaAudio leggi)
    {
        var uscita = new UscitaAudio(dispositivo, leggi);
        uscita.filo.Start();
        var errore = await uscita.avvio.Task.ConfigureAwait(false);
        if (errore is null) return (uscita, null);
        uscita.Dispose();
        return (null, errore);
    }

    /// <summary>Le uscite audio attive di Windows, con il nome che si vede nelle Impostazioni audio. Vuoto se non si può.</summary>
    public static IReadOnlyList<DispositivoAudio> Dispositivi()
    {
        var elenco = new List<DispositivoAudio>();
        IMMDeviceEnumerator? enumeratore = null;
        IMMDeviceCollection? raccolta = null;
        try
        {
            enumeratore = CreaEnumeratore();
            if (enumeratore.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, out raccolta) < 0) return elenco;
            raccolta.GetCount(out var quanti);
            for (uint i = 0; i < quanti; i++)
            {
                if (raccolta.Item(i, out var dispositivo) < 0) continue;
                try
                {
                    if (Id(dispositivo) is { } id) elenco.Add(new DispositivoAudio(id, Nome(dispositivo) ?? id));
                }
                finally { Marshal.ReleaseComObject(dispositivo); }
            }
        }
        catch (Exception errore) when (errore is COMException or InvalidCastException) { }
        finally
        {
            if (raccolta is not null) Marshal.ReleaseComObject(raccolta);
            if (enumeratore is not null) Marshal.ReleaseComObject(enumeratore);
        }
        return elenco.OrderBy(d => d.Nome, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    public void Dispose()
    {
        fermare = true;
        sveglia.Set();
        if (filo.IsAlive && Thread.CurrentThread != filo) filo.Join(2_000);
        sveglia.Dispose();
    }

    // MARK: il thread dell'audio

    private unsafe void Suona()
    {
        IMMDeviceEnumerator? enumeratore = null;
        IMMDevice? dispositivo = null;
        IAudioClient? cliente = null;
        IAudioRenderClient? riproduzione = null;
        string? motivo = null;
        var avviato = false;
        try
        {
            enumeratore = CreaEnumeratore();
            if (enumeratore.GetDevice(Dispositivo.Id, out dispositivo) < 0)
                throw new InvalidOperationException("Uscita audio non trovata");
            var iid = IidClienteAudio;
            Controlla(dispositivo.Activate(ref iid, CLSCTX_ALL, 0, out var oggetto), "Attivazione");
            cliente = (IAudioClient)oggetto;
            var formato = new FormatoOnda
            {
                wFormatTag = WAVE_FORMAT_IEEE_FLOAT,
                nChannels = 1,
                nSamplesPerSec = LineaAudio.Frequenza,
                nAvgBytesPerSec = LineaAudio.Frequenza * 4,
                nBlockAlign = 4,
                wBitsPerSample = 32,
                cbSize = 0,
            };
            Controlla(cliente.Initialize(AUDCLNT_SHAREMODE_SHARED,
                AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                DurataBuffer, 0, ref formato, 0), "Inizializzazione");
            Controlla(cliente.SetEventHandle(sveglia.SafeWaitHandle.DangerousGetHandle()), "Evento");
            Controlla(cliente.GetBufferSize(out var capienza), "Buffer");
            var iidRiproduzione = IidClienteRiproduzione;
            Controlla(cliente.GetService(ref iidRiproduzione, out var servizio), "Servizio");
            riproduzione = (IAudioRenderClient)servizio;

            // Si parte con il buffer pieno di silenzio: niente scoppio all'avvio.
            if (riproduzione.GetBuffer(capienza, out _) >= 0) riproduzione.ReleaseBuffer(capienza, AUDCLNT_BUFFERFLAGS_SILENT);
            Controlla(cliente.Start(), "Avvio");
            avviato = true;
            avvio.TrySetResult(null);

            while (!fermare)
            {
                sveglia.WaitOne(500);
                if (fermare) break;
                var esito = cliente.GetCurrentPadding(out var occupati);
                if (esito < 0)
                {
                    motivo = Descrivi(esito);
                    break;
                }
                var liberi = capienza - Math.Min(occupati, capienza);
                if (liberi == 0) continue;
                if (riproduzione.GetBuffer(liberi, out var dati) < 0) continue;
                try { leggi(new Span<float>((void*)dati, (int)liberi)); }
                catch (Exception) { new Span<float>((void*)dati, (int)liberi).Clear(); }
                riproduzione.ReleaseBuffer(liberi, 0);
            }
        }
        catch (Exception errore)
        {
            motivo = errore is COMException com ? Descrivi(com.HResult, errore.Message) : errore.Message;
        }
        finally
        {
            try { cliente?.Stop(); } catch (Exception) { }
            foreach (var oggetto in new object?[] { riproduzione, cliente, dispositivo, enumeratore })
            {
                if (oggetto is not null && Marshal.IsComObject(oggetto))
                {
                    try { Marshal.ReleaseComObject(oggetto); } catch (Exception) { }
                }
            }
        }
        if (!avviato) avvio.TrySetResult(motivo ?? "Uscita audio non disponibile");
        else if (!fermare && motivo is not null) Interrotta?.Invoke(motivo);
    }

    // MARK: aiuti

    private static IMMDeviceEnumerator CreaEnumeratore()
    {
        var tipo = Type.GetTypeFromCLSID(ClsidEnumeratore, throwOnError: true)!;
        return (IMMDeviceEnumerator)Activator.CreateInstance(tipo)!;
    }

    private static string? Id(IMMDevice dispositivo)
    {
        if (dispositivo.GetId(out var puntatore) < 0 || puntatore == 0) return null;
        try { return Marshal.PtrToStringUni(puntatore); }
        finally { Marshal.FreeCoTaskMem(puntatore); }
    }

    private static string? Nome(IMMDevice dispositivo)
    {
        if (dispositivo.OpenPropertyStore(STGM_READ, out var proprieta) < 0) return null;
        try
        {
            var chiave = NomeDispositivo;
            if (proprieta.GetValue(ref chiave, out var valore) < 0) return null;
            try { return valore.vt == VT_LPWSTR && valore.valore != 0 ? Marshal.PtrToStringUni(valore.valore) : null; }
            finally { PropVariantClear(ref valore); }
        }
        finally { Marshal.ReleaseComObject(proprieta); }
    }

    private static void Controlla(int esito, string passo)
    {
        if (esito < 0) throw new COMException($"{passo}: {Descrivi(esito)}", esito);
    }

    /// <summary>I codici di WASAPI che capitano davvero, in parole; gli altri in esadecimale.</summary>
    private static string Descrivi(int esito, string? messaggio = null) => unchecked((uint)esito) switch
    {
        0x88890004 => "la scheda audio è stata staccata o disattivata",
        0x88890008 => "Windows non accetta il formato audio",
        0x8889000A => "la scheda audio è usata in modo esclusivo da un'altra app",
        0x88890010 => "il servizio Audio di Windows non è attivo",
        _ => messaggio ?? $"errore 0x{esito:X8}",
    };

    [DllImport("ole32.dll")] private static extern int PropVariantClear(ref ValoreProprieta valore);
}
