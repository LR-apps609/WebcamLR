using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Il cavo USB di Android (Qualità 17), scritto da zero come quello dell'iPhone: parla con il server di adb su
/// 127.0.0.1:5037 (Documenti/Protocollo.md, «Cavo USB con Android: adb»; la scelta in Documenti/Cavo USB Android.md).
/// Chiede «host:track-devices», che manda l'elenco dei telefoni a ogni cambiamento; per ogni telefono sul cavo con il
/// debug USB consentito («device») apre un'altra connessione, sceglie il telefono («host:transport:seriale») e la sua
/// porta 52741 («tcp:52741»). Con due «OKAY» la connessione è un canale TCP verso WebcamLR sul telefono, come il
/// Connect di usbmux: niente regole «adb forward» o «adb reverse» da creare e togliere, nessuna porta occupata sul PC.
/// Se l'app sul telefono non ascolta, adb risponde «FAIL»: si riprova ogni secondo. Tutto il resto (rifiuti,
/// sospensione, pausa per scelta) è di <see cref="ClienteCavo{TChiave}"/>.
///
/// adb non è nostro: se il suo server non risponde, si prova ad avviarlo con <see cref="AvviaServer"/> (adb trovato
/// sul PC, vedi <see cref="TrovaAdb"/>), al massimo una volta al minuto. Un server già acceso (Android Studio, scrcpy)
/// si usa così com'è: mai «adb kill-server», mai un adb di un'altra versione contro un server acceso.
/// </summary>
public sealed class ClienteAdb : ClienteCavo<string>
{
    private readonly IPEndPoint servizio;
    private readonly TimeSpan attesaRisposta = TimeSpan.FromSeconds(5);
    private readonly TimeSpan pausaAvvio;
    private readonly object blocco = new();
    private IReadOnlyList<DispositivoAdb> elenco = [];
    private DateTime? ultimoAvvio;
    private bool avvioTentato;

    /// <summary>
    /// Avvia il server di adb quando non risponde; vero se ci ha provato (adb trovato). Null: non si avvia nulla
    /// (si aspetta che lo avvii qualcun altro). Di serie <see cref="AvviaServerDelSistemaAsync"/>.
    /// </summary>
    public Func<CancellationToken, Task<bool>>? AvviaServer { get; init; } = AvviaServerDelSistemaAsync;

    /// <summary>L'elenco dei telefoni di adb è cambiato (per la diagnosi: un telefono da autorizzare).</summary>
    public event Action? ElencoCambiato;

    /// <param name="servizio">Dove risponde il server di adb: 127.0.0.1:5037, un'altra porta solo nei test.</param>
    /// <param name="pausaAvvio">Quanto aspettare tra due tentativi di avviare il server: 1 minuto.</param>
    public ClienteAdb(IPEndPoint? servizio = null, TimeSpan? intervalloRiprova = null, TimeSpan? attesaServizio = null,
        TimeSpan? attesaMassima = null, TimeSpan? intervalloConnect = null, TimeSpan? pausaAvvio = null)
        : base(intervalloRiprova, attesaServizio, attesaMassima, intervalloConnect)
    {
        this.servizio = servizio ?? new IPEndPoint(IPAddress.Loopback, ProtocolloAdb.PortaServer);
        this.pausaAvvio = pausaAvvio ?? TimeSpan.FromMinutes(1);
    }

    /// <summary>L'ultimo elenco di adb, solo i telefoni sul cavo USB (niente debug wireless né emulatori).</summary>
    public IReadOnlyList<DispositivoAdb> Elenco
    {
        get { lock (blocco) return elenco; }
    }

    /// <summary>Telefoni sul cavo che aspettano «Consenti» alla domanda del debug USB.</summary>
    public int DaAutorizzare => Elenco.Count(d => d.Stato == StatoDispositivoAdb.NonAutorizzato);

    /// <summary>
    /// Vero se si è provato ad avviare il server e adb non c'era: sul PC mancano gli strumenti di Android
    /// (la guida dice come averli). Falso finché non si sa, o se adb c'è.
    /// </summary>
    public bool AdbMancante { get; private set; }

    protected override string Testo(EventoCavo evento, string? attesa = null) => evento switch
    {
        EventoCavo.ServizioTrovato => TestiRicevitore.T("CavoAndroid_ServizioTrovato"),
        EventoCavo.ServizioFermo => TestiRicevitore.T("CavoAndroid_ServizioFermo"),
        EventoCavo.TelefonoCollegato => TestiRicevitore.T("CavoAndroid_Collegato"),
        EventoCavo.TelefonoStaccato => TestiRicevitore.T("CavoAndroid_Staccato"),
        EventoCavo.Rifiutato => TestiRicevitore.T("CavoAndroid_Rifiutato", attesa ?? ""),
        _ => TestiRicevitore.T("CavoAndroid_CanaleAperto"),
    };

    protected override async Task AscoltaServizioAsync(Action raggiunto, CancellationToken annullato)
    {
        Socket presa;
        try { presa = await ApriAsync(servizio, annullato); }
        catch (SocketException)
        {
            await ProvaAdAvviareAsync(annullato);
            throw;
        }
        using (presa)
        {
            await using var flusso = new NetworkStream(presa, ownsSocket: false);
            raggiunto();
            try
            {
                await flusso.WriteAsync(ProtocolloAdb.Richiesta("host:track-devices"), annullato);
                if (!await ProtocolloAdb.LeggiEsitoAsync(flusso, annullato)) return;
                ServizioInAscolto();
                while (await ProtocolloAdb.LeggiBloccoAsync(flusso, annullato) is { } testo)
                    Aggiorna(ProtocolloAdb.LeggiElenco(testo));
            }
            catch (RifiutoAdb) { }
            finally { Aggiorna([]); }
        }
    }

    /// <summary>Un elenco nuovo: i telefoni pronti si collegano, gli altri (staccati, non più autorizzati) si staccano.</summary>
    private void Aggiorna(IReadOnlyList<DispositivoAdb> tutti)
    {
        var sulCavo = tutti.Where(d => d.ViaUsb).ToList();
        bool cambiato;
        lock (blocco)
        {
            cambiato = !sulCavo.SequenceEqual(elenco);
            elenco = sulCavo;
        }
        var pronti = sulCavo.Where(d => d.Stato == StatoDispositivoAdb.Pronto).Select(d => d.Seriale).ToHashSet(StringComparer.Ordinal);
        foreach (var noto in Collegati())
            if (!pronti.Contains(noto)) Stacca(noto);
        foreach (var seriale in pronti) Collega(seriale);
        if (cambiato) ElencoCambiato?.Invoke();
    }

    /// <summary>Al massimo una volta ogni <see cref="pausaAvvio"/>: il server di adb non risponde, si prova ad avviarlo.</summary>
    private async Task ProvaAdAvviareAsync(CancellationToken annullato)
    {
        if (AvviaServer is not { } avvia) return;
        lock (blocco)
        {
            var adesso = DateTime.UtcNow;
            if (ultimoAvvio is { } ultimo && adesso - ultimo < pausaAvvio) return;
            ultimoAvvio = adesso;
        }
        bool trovato;
        try { trovato = await avvia(annullato); }
        catch (OperationCanceledException) { throw; }
        catch (Exception) { trovato = true; }
        var primaVolta = !avvioTentato;
        avvioTentato = true;
        var cambiato = AdbMancante != !trovato || primaVolta;
        AdbMancante = !trovato;
        if (cambiato) ElencoCambiato?.Invoke();
    }

    /// <summary>
    /// «host:transport:seriale» e «tcp:52741» su una connessione nuova al server: con due «OKAY» è il canale verso
    /// WebcamLR sul telefono. «FAIL» (app chiusa, telefono non autorizzato o staccato) o nessuna risposta: null.
    /// </summary>
    protected override async Task<Socket?> ConnettiAsync(string seriale, CancellationToken annullato)
    {
        Socket? presa = null;
        try
        {
            presa = await ApriAsync(servizio, annullato);
            using var tempo = CancellationTokenSource.CreateLinkedTokenSource(annullato);
            tempo.CancelAfter(attesaRisposta);
            // Senza possedere la presa: chiudere il flusso non deve chiudere il canale verso il telefono.
            using var flusso = new NetworkStream(presa, ownsSocket: false);
            await flusso.WriteAsync(ProtocolloAdb.Richiesta(ProtocolloAdb.RichiestaTelefono(seriale)), tempo.Token);
            if (!await ProtocolloAdb.LeggiEsitoAsync(flusso, tempo.Token)) return null;
            await flusso.WriteAsync(ProtocolloAdb.Richiesta(ProtocolloAdb.RichiestaPorta(PortaTelefono)), tempo.Token);
            if (!await ProtocolloAdb.LeggiEsitoAsync(flusso, tempo.Token)) return null;
            var pronta = presa;
            presa = null;
            return pronta;
        }
        catch (OperationCanceledException) when (annullato.IsCancellationRequested) { throw; }
        catch (Exception) { return null; }
        finally { presa?.Dispose(); }
    }

    /// <summary>
    /// Cerca adb (<see cref="TrovaAdb"/>) e lancia «adb start-server», senza finestra; il server resta acceso da solo.
    /// Falso se adb non c'è sul PC.
    /// </summary>
    public static async Task<bool> AvviaServerDelSistemaAsync(CancellationToken annullato)
    {
        var dati = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var cartellaApp = string.IsNullOrEmpty(dati) ? null : Path.Combine(dati, "WebcamLR");
        var nome = OperatingSystem.IsWindows() ? "adb.exe" : "adb";
        var candidati = TrovaAdb.Candidati(Environment.GetEnvironmentVariable, cartellaApp, nome, Path.PathSeparator);
        if (TrovaAdb.Primo(candidati, File.Exists) is not { } adb) return false;
        using var processo = Process.Start(new ProcessStartInfo(adb, "start-server")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            WindowStyle = ProcessWindowStyle.Hidden,
        });
        if (processo is null) return true;
        using var tempo = CancellationTokenSource.CreateLinkedTokenSource(annullato);
        tempo.CancelAfter(TimeSpan.FromSeconds(10));
        try { await processo.WaitForExitAsync(tempo.Token); }
        catch (OperationCanceledException) when (!annullato.IsCancellationRequested) { }
        return true;
    }
}
