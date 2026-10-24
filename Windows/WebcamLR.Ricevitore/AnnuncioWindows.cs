using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Pubblica `_webcamlr._tcp` in rete locale con il servizio mDNS di Windows (DnsServiceRegister,
/// Windows 10 versione 1903 o successiva), così l'iPhone trova il PC da solo (funzione 1).
/// Su sistemi più vecchi non fa nulla: resta il QR code.
/// Dopo un cambio di rete o il risveglio dallo stop l'app lo rinnova (1.12): <see cref="ChiudiAsync"/> e uno nuovo,
/// così un telefono che sta già cercando trova subito il PC sulla rete nuova.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class AnnuncioWindows : IDisposable
{
    private const uint VersioneRichiesta = 1;      // DNS_QUERY_REQUEST_VERSION1
    private const uint RichiestaInCorso = 9506;    // DNS_REQUEST_PENDING

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void Completato(uint stato, IntPtr contesto, IntPtr istanza);

    [StructLayout(LayoutKind.Sequential)]
    private struct RichiestaRegistrazione
    {
        public uint Version;
        public uint InterfaceIndex;
        public IntPtr pServiceInstance;
        public IntPtr pRegisterCompletionCallback;
        public IntPtr pQueryContext;
        public IntPtr hCredentials;
        public int unicastEnabled;
    }

    [DllImport("dnsapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern IntPtr DnsServiceConstructInstance(string pServiceName, string pHostName, IntPtr pIp4, IntPtr pIp6,
        ushort wPort, ushort wPriority, ushort wWeight, uint dwPropertiesCount,
        [MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPWStr)] string[] keys,
        [MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPWStr)] string[] values);

    [DllImport("dnsapi.dll", ExactSpelling = true)]
    private static extern void DnsServiceFreeInstance(IntPtr pInstance);

    [DllImport("dnsapi.dll", ExactSpelling = true)]
    private static extern uint DnsServiceRegister(IntPtr pRequest, IntPtr pCancel);

    [DllImport("dnsapi.dll", ExactSpelling = true)]
    private static extern uint DnsServiceDeRegister(IntPtr pRequest, IntPtr pCancel);

    private readonly Completato completato;   // tenuto vivo: Windows lo chiama più tardi
    private IntPtr istanza;
    private IntPtr richiesta;
    /// <summary>Completata quando Windows conferma la cancellazione: solo dopo si libera la richiesta.</summary>
    private TaskCompletionSource? cancellato;
    private Task? chiusura;
    /// <summary>Diventa 1 al primo richiamo: quello è sempre l'esito della registrazione, anche a cancellazione già chiesta.</summary>
    private int registrazioneConclusa;

    /// <summary>
    /// Annunci tolti senza la conferma di Windows (scaduti i 2 secondi, o l'app che si chiude): restano qui, con la
    /// richiesta in memoria, finché Windows non chiama il richiamo. Se il GC raccogliesse il delegato, o la richiesta
    /// fosse già liberata, un richiamo in ritardo farebbe cadere l'app. Pochi byte, e solo in casi rari.
    /// </summary>
    private static readonly HashSet<AnnuncioWindows> inSospeso = [];

    /// <summary>Esito della registrazione: 0 = riuscita; arriva su un thread di sistema.</summary>
    public event Action<uint>? Registrato;

    public bool Attivo => richiesta != IntPtr.Zero;

    public AnnuncioWindows(ushort porta, string? nome = null)
    {
        completato = (stato, _, istanzaRestituita) =>
        {
            if (istanzaRestituita != IntPtr.Zero) DnsServiceFreeInstance(istanzaRestituita);
            // Il primo richiamo è l'esito della registrazione (la verifica del nome in rete dura quasi un secondo:
            // un rinnovo subito dopo il risveglio può chiedere la cancellazione prima). Dopo DnsServiceDeRegister
            // la stessa funzione dice che la cancellazione è finita.
            var registrazione = Interlocked.Exchange(ref registrazioneConclusa, 1) == 0;
            var attesa = Volatile.Read(ref cancellato);
            if (attesa is null)
            {
                Registrato?.Invoke(stato);
            }
            else if (!registrazione)
            {
                attesa.TrySetResult();
                // Arrivato dopo la scadenza: Windows non lo chiamerà più, l'annuncio può andarsene.
                lock (inSospeso) inSospeso.Remove(this);
            }
        };
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 18362)) return;

        var computer = Environment.MachineName;
        nome ??= computer;
        istanza = DnsServiceConstructInstance($"{nome}.{Servizio.TipoBonjour}.local", $"{computer}.local",
            IntPtr.Zero, IntPtr.Zero, porta, 0, 0, 2,
            ["v", "p"], [Servizio.VersioneProtocollo.ToString(), "windows"]);
        if (istanza == IntPtr.Zero) return;

        var dati = new RichiestaRegistrazione
        {
            Version = VersioneRichiesta,
            pServiceInstance = istanza,
            pRegisterCompletionCallback = Marshal.GetFunctionPointerForDelegate(completato),
        };
        richiesta = Marshal.AllocHGlobal(Marshal.SizeOf<RichiestaRegistrazione>());
        Marshal.StructureToPtr(dati, richiesta, false);
        if (DnsServiceRegister(richiesta, IntPtr.Zero) != RichiestaInCorso)
        {
            Libera();
        }
    }

    /// <summary>
    /// Toglie l'annuncio e aspetta che Windows lo confermi (al massimo 2 secondi): così uno nuovo con lo stesso
    /// nome non si scontra con quello vecchio, e la richiesta non si libera mentre Windows la usa ancora.
    /// </summary>
    public Task ChiudiAsync() => chiusura ??= ChiudiInternoAsync();

    private async Task ChiudiInternoAsync()
    {
        if (richiesta == IntPtr.Zero)
        {
            Libera();
            return;
        }
        var attesa = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Volatile.Write(ref cancellato, attesa);
        lock (inSospeso) inSospeso.Add(this);
        if (DnsServiceDeRegister(richiesta, IntPtr.Zero) != RichiestaInCorso)
        {
            lock (inSospeso) inSospeso.Remove(this);
            Libera();
            return;
        }
        if (await Task.WhenAny(attesa.Task, Task.Delay(2000)) != attesa.Task)
        {
            // Nessuna conferma: Windows può ancora usare la richiesta e chiamare il richiamo. Resta tutto vivo
            // (in inSospeso) e non si libera nulla: meglio pochi byte persi che un'app che cade.
            return;
        }
        lock (inSospeso) inSospeso.Remove(this);
        Libera();
    }

    public void Dispose()
    {
        if (chiusura is not null) return;
        if (richiesta != IntPtr.Zero)
        {
            // L'app si chiude: si toglie l'annuncio senza aspettare, ma senza liberare ciò che Windows può ancora usare.
            Volatile.Write(ref cancellato, new TaskCompletionSource());
            lock (inSospeso) inSospeso.Add(this);
            if (DnsServiceDeRegister(richiesta, IntPtr.Zero) == RichiestaInCorso) return;
            lock (inSospeso) inSospeso.Remove(this);
        }
        Libera();
    }

    private void Libera()
    {
        if (richiesta != IntPtr.Zero) { Marshal.FreeHGlobal(richiesta); richiesta = IntPtr.Zero; }
        if (istanza != IntPtr.Zero) { DnsServiceFreeInstance(istanza); istanza = IntPtr.Zero; }
    }
}
