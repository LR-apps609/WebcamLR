using System.Net;
using System.Net.Sockets;

namespace WebcamLR.Ricevitore;

/// <summary>A che punto è il cavo USB, per la finestra e la diagnosi.</summary>
public enum StatoCavo
{
    /// <summary>
    /// Il servizio del cavo non risponde: per l'iPhone l'app «Dispositivi Apple» (porta 27015), per Android il server
    /// di adb (porta 5037), che non c'è o non è partito.
    /// </summary>
    ServizioAssente,
    /// <summary>Il servizio c'è e avvisa quando si collega un telefono; nessun telefono parla con noi sul cavo.</summary>
    InAscolto,
    /// <summary>Un telefono è collegato con il cavo e la connessione verso WebcamLR sul telefono è aperta.</summary>
    Collegato,
}

/// <summary>Le frasi del registro che ogni cavo dice a modo suo («iPhone collegato…», «Android collegato…»).</summary>
public enum EventoCavo
{
    ServizioTrovato,
    ServizioFermo,
    TelefonoCollegato,
    TelefonoStaccato,
    /// <summary>Il telefono ha chiuso il cavo prima di accettare: con l'attesa prima del prossimo tentativo.</summary>
    Rifiutato,
    /// <summary>Il canale verso WebcamLR sul telefono è aperto.</summary>
    CanaleAperto,
}

/// <summary>
/// La parte comune dei cavi USB (Qualità 17): usbmux per l'iPhone (<see cref="ClienteUsbmux"/>) e adb per Android
/// (<see cref="ClienteAdb"/>). Ogni cavo sa raggiungere il suo servizio e aprire un canale verso la porta 52741 del
/// telefono; qui c'è tutto il resto, uguale per i due: un compito per telefono collegato che riprova ogni secondo
/// finché l'app risponde, l'attesa che raddoppia (2, 4, 8 … fino a 30 secondi) quando il telefono chiude il canale prima
/// di accettare, la sospensione dopo «Scollega», la pausa per la strada scelta (resta il Wi-Fi) con
/// <see cref="RiprendiScelti"/>, e <see cref="Riprendi"/> dopo il risveglio o un cambio di rete.
/// La connessione che arriva con <see cref="TelefonoViaCavo"/> si usa come una connessione Wi-Fi (il telefono manda
/// per primo la «stretta»). Gli eventi arrivano su thread di sistema.
/// </summary>
/// <typeparam name="TChiave">Come il servizio chiama il telefono: il DeviceID di usbmux, il numero di serie di adb.</typeparam>
public abstract class ClienteCavo<TChiave> : IAsyncDisposable where TChiave : notnull
{
    /// <summary>La porta su cui WebcamLR sul telefono ascolta, solo su 127.0.0.1 (raggiungibile solo dal cavo).</summary>
    public const ushort PortaTelefono = 52741;

    /// <summary>
    /// Qualità 19 («avvio zero passi»): con il telefono già sul cavo, aprendo l'app si aspetta al massimo un secondo (erano
    /// 2) prima che il PC la raggiunga. Un tentativo verso il servizio è locale e costa pochissimo.
    /// </summary>
    public static readonly TimeSpan IntervalloConnectPredefinito = TimeSpan.FromSeconds(1);

    /// <summary>Una connessione verso WebcamLR sul telefono, attraverso il cavo: da dare a una SessioneComputer.</summary>
    public event Action<Socket>? TelefonoViaCavo;
    public event Action<StatoCavo>? StatoCambiato;
    /// <summary>Per il registro del collegamento: frasi brevi su ciò che succede sul cavo.</summary>
    public event Action<string>? Evento;

    private readonly TimeSpan intervalloRiprova;
    private readonly TimeSpan intervalloConnect;
    private readonly TimeSpan attesaMassima;
    private readonly TimeSpan attesaServizio;
    private readonly CancellationTokenSource annulla = new();
    private readonly object blocco = new();
    private readonly Dictionary<TChiave, Dispositivo> dispositivi = new();
    private StatoCavo stato = StatoCavo.ServizioAssente;
    /// <summary>Falso fino al primo tentativo di raggiungere il servizio: prima lo stato non dice ancora nulla.</summary>
    private bool statoNoto;
    private bool servizioRaggiunto;
    private Task? lavoro;
    /// <summary>Completata da <see cref="Riprendi"/>: interrompe le attese in corso (servizio, Connect, rifiuti).</summary>
    private TaskCompletionSource sveglia = NuovaSveglia();

    private sealed class Dispositivo(TChiave id)
    {
        public TChiave Id { get; } = id;
        public CancellationTokenSource Fine { get; } = new();
        public Socket? Presa;
        /// <summary>Chiuso dal computer (Scollega, rifiuto, altro telefono): non si ricollega finché il cavo non si stacca.</summary>
        public bool Sospeso;
        /// <summary>
        /// Lasciato per la strada scelta (resta il Wi-Fi: scelto a mano, o pausa dopo un cambio): non si ricollega da
        /// solo, ma torna con <see cref="RiprendiScelti"/> (scelta cambiata, Wi-Fi perso) o staccando e riattaccando il cavo.
        /// </summary>
        public bool InPausaPerScelta;
        /// <summary>La sessione su <see cref="Presa"/> è stata accettata (il telefono ha mandato il suo «ciao»).</summary>
        public bool Accettata;
        /// <summary>Connessioni di fila chiuse dal telefono prima di essere accettate: decidono l'attesa.</summary>
        public int Rifiuti;
    }

    /// <param name="intervalloRiprova">La base dell'attesa dopo un rifiuto (<see cref="AttesaDopoRifiuti"/>): 2 secondi.</param>
    /// <param name="attesaServizio">Ogni quanto riprovare a raggiungere il servizio se manca: 5 secondi.</param>
    /// <param name="attesaMassima">Il limite dell'attesa che raddoppia quando il telefono rifiuta il cavo: 30 secondi.</param>
    /// <param name="intervalloConnect">
    /// Ogni quanto riprovare mentre il telefono è collegato ma l'app non risponde, e ogni quanto guardare se la
    /// connessione è ancora aperta: di serie 1 secondo (<see cref="IntervalloConnectPredefinito"/>); con un
    /// <paramref name="intervalloRiprova"/> scelto (nei test) lo stesso valore.
    /// </param>
    protected ClienteCavo(TimeSpan? intervalloRiprova, TimeSpan? attesaServizio, TimeSpan? attesaMassima, TimeSpan? intervalloConnect)
    {
        this.intervalloRiprova = intervalloRiprova ?? TimeSpan.FromSeconds(2);
        this.intervalloConnect = intervalloConnect ?? intervalloRiprova ?? IntervalloConnectPredefinito;
        this.attesaMassima = attesaMassima ?? TimeSpan.FromSeconds(30);
        this.attesaServizio = attesaServizio ?? TimeSpan.FromSeconds(5);
    }

    /// <summary>
    /// Apre la connessione con il servizio e chiede di essere avvisato dei telefoni collegati. Chiama
    /// <paramref name="raggiunto"/> appena il servizio risponde, <see cref="ServizioInAscolto"/> quando ha accettato,
    /// <see cref="Collega"/> e <see cref="Stacca"/> per i telefoni. Ritorna quando il servizio chiude la connessione;
    /// lancia un'eccezione se non si raggiunge.
    /// </summary>
    protected abstract Task AscoltaServizioAsync(Action raggiunto, CancellationToken annullato);

    /// <summary>Un canale nuovo verso la porta 52741 del telefono; null se l'app sul telefono non risponde.</summary>
    protected abstract Task<Socket?> ConnettiAsync(TChiave id, CancellationToken annullato);

    /// <summary>La frase del registro per questo cavo; <paramref name="attesa"/> solo per <see cref="EventoCavo.Rifiutato"/>.</summary>
    protected abstract string Testo(EventoCavo evento, string? attesa = null);

    public StatoCavo Stato
    {
        get { lock (blocco) return stato; }
    }

    /// <summary>
    /// Vero se almeno un telefono è collegato con il cavo e si sta cercando di parlargli, anche se WebcamLR
    /// sul telefono non risponde. Un telefono sospeso (Scollega, rifiutato) non conta: non si ricollega da solo,
    /// e la diagnosi non deve dire «il collegamento parte da solo».
    /// </summary>
    public bool TelefonoAlCavo
    {
        get { lock (blocco) return dispositivi.Values.Any(d => !d.Sospeso && !d.InPausaPerScelta); }
    }

    /// <summary>Vero dopo il primo tentativo di raggiungere il servizio: prima lo stato non dice ancora nulla.</summary>
    public bool Verificato
    {
        get { lock (blocco) return statoNoto; }
    }

    /// <summary>Vero se questa presa è un canale aperto da questo cavo (per sapere a quale cavo restituirla).</summary>
    public bool EMia(Socket presa)
    {
        lock (blocco) return dispositivi.Values.Any(d => ReferenceEquals(d.Presa, presa));
    }

    public void Avvia() => lavoro ??= Task.Run(() => ServizioAsync(annulla.Token));

    /// <summary>
    /// La connessione è stata chiusa dal computer (Scollega, telefono rifiutato o sostituito): quel telefono
    /// non si ricollega da solo finché il cavo non viene staccato e ricollegato. Senza, due telefoni si
    /// caccerebbero a vicenda e un telefono rifiutato chiederebbe di nuovo ogni 2 secondi.
    /// Una presa che non è di questo cavo si ignora.
    /// </summary>
    /// <param name="perScelta">
    /// Chiusa per la strada scelta (<see cref="SessioneComputer.LasciataPerScelta"/>), non per «Scollega»: il cavo resta
    /// fermo ma torna con <see cref="RiprendiScelti"/>. Una pausa per scelta non diventa sospensione quando la sessione,
    /// chiusa, chiama di nuovo questo metodo senza il parametro.
    /// </param>
    public void Sospendi(Socket presa, bool perScelta = false)
    {
        lock (blocco)
        {
            foreach (var dispositivo in dispositivi.Values)
            {
                if (!ReferenceEquals(dispositivo.Presa, presa)) continue;
                if (perScelta) dispositivo.InPausaPerScelta = true;
                else if (!dispositivo.InPausaPerScelta) dispositivo.Sospeso = true;
            }
        }
    }

    /// <summary>
    /// I cavi lasciati per la strada scelta tornano a collegarsi (subito): la scelta è cambiata, o il Wi-Fi in uso si è
    /// staccato e il cavo serve a non perdere il video. I telefoni sospesi da «Scollega» restano sospesi.
    /// </summary>
    public void RiprendiScelti()
    {
        var ripresi = false;
        lock (blocco)
        {
            foreach (var dispositivo in dispositivi.Values)
            {
                if (!dispositivo.InPausaPerScelta) continue;
                dispositivo.InPausaPerScelta = false;
                ripresi = true;
            }
        }
        if (ripresi) Riprendi();
    }

    /// <summary>
    /// La sessione su quella connessione è stata accettata (il telefono ha mandato il suo «ciao»): il cavo
    /// funziona, e se più avanti la connessione si chiude si riprova di nuovo ogni secondo.
    /// </summary>
    public void StrettaRiuscita(Socket presa)
    {
        lock (blocco)
        {
            foreach (var dispositivo in dispositivi.Values)
            {
                if (!ReferenceEquals(dispositivo.Presa, presa)) continue;
                dispositivo.Accettata = true;
                dispositivo.Rifiuti = 0;
            }
        }
    }

    /// <summary>
    /// Dopo il risveglio dallo stop o un cambio di rete (1.12): si riprova subito, senza aspettare la fine delle
    /// attese in corso (fino a 30 secondi dopo dei rifiuti, 5 secondi per il servizio), e l'attesa crescente
    /// riparte da capo. Un telefono sospeso (Scollega, rifiutato) resta sospeso: lo ha deciso l'utente.
    /// </summary>
    public void Riprendi()
    {
        TaskCompletionSource vecchia;
        lock (blocco)
        {
            foreach (var dispositivo in dispositivi.Values) dispositivo.Rifiuti = 0;
            vecchia = sveglia;
            sveglia = NuovaSveglia();
        }
        vecchia.TrySetResult();
    }

    private static TaskCompletionSource NuovaSveglia() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// <summary>
    /// Aspetta <paramref name="attesa"/>, o meno se arriva <see cref="Riprendi"/>; vero se svegliata prima.
    /// Lancia OperationCanceledException se annullata, come Task.Delay.
    /// </summary>
    protected async Task<bool> AttendiAsync(TimeSpan attesa, CancellationToken annullato)
    {
        Task svegliata;
        lock (blocco) svegliata = sveglia.Task;
        using var fine = CancellationTokenSource.CreateLinkedTokenSource(annullato);
        var vinta = await Task.WhenAny(Task.Delay(attesa, fine.Token), svegliata);
        fine.Cancel();
        annullato.ThrowIfCancellationRequested();
        return vinta == svegliata;
    }

    /// <summary>
    /// Quanto aspettare prima del prossimo tentativo dopo <paramref name="rifiuti"/> connessioni di fila chiuse
    /// dal telefono prima di essere accettate: 2, 4, 8, 16 secondi, poi sempre il massimo (30).
    /// </summary>
    public TimeSpan AttesaDopoRifiuti(int rifiuti)
    {
        if (rifiuti <= 1) return intervalloRiprova;
        var attesa = intervalloRiprova;
        for (var i = 1; i < rifiuti && attesa < attesaMassima; i++) attesa *= 2;
        return attesa < attesaMassima ? attesa : attesaMassima;
    }

    private async Task ServizioAsync(CancellationToken annullato)
    {
        while (!annullato.IsCancellationRequested)
        {
            var raggiunto = false;
            try
            {
                await AscoltaServizioAsync(() =>
                {
                    lock (blocco) servizioRaggiunto = true;
                    raggiunto = true;
                    Evento?.Invoke(Testo(EventoCavo.ServizioTrovato));
                }, annullato);
                if (raggiunto) Evento?.Invoke(Testo(EventoCavo.ServizioFermo));
            }
            catch (OperationCanceledException) when (annullato.IsCancellationRequested) { return; }
            catch (Exception) { }
            lock (blocco) servizioRaggiunto = false;
            DimenticaTutti();
            Imposta(StatoCavo.ServizioAssente);
            try { await AttendiAsync(attesaServizio, annullato); }
            catch (OperationCanceledException) { return; }
        }
    }

    /// <summary>Il servizio ha accettato la richiesta di avvisi: si aspettano i telefoni.</summary>
    protected void ServizioInAscolto() => Imposta(StatoCavo.InAscolto);

    /// <summary>I telefoni che il servizio ha segnalato e che non si sono ancora staccati.</summary>
    protected IReadOnlyList<TChiave> Collegati()
    {
        lock (blocco) return dispositivi.Keys.ToList();
    }

    /// <summary>Un telefono collegato con il cavo: da ora si prova ad aprire il canale. Uno già noto si ignora.</summary>
    protected void Collega(TChiave id)
    {
        Dispositivo nuovo;
        lock (blocco)
        {
            if (dispositivi.ContainsKey(id)) return;
            nuovo = new Dispositivo(id);
            dispositivi[id] = nuovo;
        }
        Evento?.Invoke(Testo(EventoCavo.TelefonoCollegato));
        _ = Task.Run(() => DispositivoAsync(nuovo));
    }

    /// <summary>Un telefono staccato: i tentativi si fermano (la sessione aperta si chiude da sola, con il canale).</summary>
    protected void Stacca(TChiave id)
    {
        Dispositivo? staccato;
        lock (blocco)
        {
            if (!dispositivi.Remove(id, out staccato)) return;
        }
        staccato.Fine.Cancel();
        Evento?.Invoke(Testo(EventoCavo.TelefonoStaccato));
        AggiornaStato();
    }

    private void DimenticaTutti()
    {
        List<Dispositivo> tutti;
        lock (blocco)
        {
            tutti = dispositivi.Values.ToList();
            dispositivi.Clear();
        }
        foreach (var dispositivo in tutti) dispositivo.Fine.Cancel();
    }

    /// <summary>Finché il telefono resta collegato: un canale, e se non riesce (o la connessione si chiude) si riprova.</summary>
    private async Task DispositivoAsync(Dispositivo dispositivo)
    {
        using var fine = CancellationTokenSource.CreateLinkedTokenSource(annulla.Token, dispositivo.Fine.Token);
        var annullato = fine.Token;
        try
        {
            while (!annullato.IsCancellationRequested)
            {
                bool daCollegare;
                var rifiuti = 0;
                lock (blocco)
                {
                    daCollegare = !dispositivo.Sospeso && !dispositivo.InPausaPerScelta && !Aperta(dispositivo.Presa);
                    if (daCollegare && dispositivo.Presa is not null)
                    {
                        // La connessione data alla sessione è finita: chiusa dal telefono prima di essere accettata?
                        if (dispositivo.Accettata) dispositivo.Rifiuti = 0;
                        else rifiuti = ++dispositivo.Rifiuti;
                        dispositivo.Accettata = false;
                        dispositivo.Presa = null;
                    }
                }
                if (rifiuti > 0)
                {
                    AggiornaStato();
                    var attesa = AttesaDopoRifiuti(rifiuti);
                    // Una riga per gradino, non una a ogni tentativo.
                    if (rifiuti == 1 || attesa != AttesaDopoRifiuti(rifiuti - 1))
                        Evento?.Invoke(Testo(EventoCavo.Rifiutato, Secondi(attesa)));
                    // Il controllo che ha visto la chiusura vale già un intervallo: si aspetta solo il resto.
                    var resto = attesa - intervalloConnect;
                    if (resto > TimeSpan.Zero)
                    {
                        await AttendiAsync(resto, annullato);
                        // Nel frattempo può essere stato sospeso: si ricontrolla da capo, senza un altro intervallo.
                        continue;
                    }
                }
                if (daCollegare)
                {
                    AggiornaStato();
                    if (await ConnettiAsync(dispositivo.Id, annullato) is { } presa)
                    {
                        lock (blocco) dispositivo.Presa = presa;
                        AggiornaStato();
                        Evento?.Invoke(Testo(EventoCavo.CanaleAperto));
                        // Chi riceve lavora su questo thread (1.11): un suo errore non deve fermare il ciclo, altrimenti
                        // il telefono non si ricollegherebbe più fino a quando non viene staccato. La presa chiusa
                        // vale come un rifiuto e si riprova.
                        try { TelefonoViaCavo?.Invoke(presa); }
                        catch (Exception) { presa.Dispose(); }
                    }
                }
                await AttendiAsync(intervalloConnect, annullato);
            }
        }
        catch (OperationCanceledException) { }
        AggiornaStato();
    }

    private static string Secondi(TimeSpan attesa)
    {
        var secondi = Math.Max(1, (int)Math.Round(attesa.TotalSeconds));
        return secondi == 1 ? TestiRicevitore.T("Cavo_UnSecondo") : TestiRicevitore.T("Cavo_Secondi", secondi);
    }

    /// <summary>Una connessione TCP nuova verso il servizio (su loopback), con TCP_NODELAY come le altre.</summary>
    protected static async Task<Socket> ApriAsync(IPEndPoint servizio, CancellationToken annullato)
    {
        var presa = new Socket(servizio.AddressFamily, SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
        try
        {
            await presa.ConnectAsync(servizio, annullato);
            return presa;
        }
        catch
        {
            presa.Dispose();
            throw;
        }
    }

    /// <summary>Una presa passata alla sessione è aperta finché la sessione non la chiude.</summary>
    private static bool Aperta(Socket? presa)
    {
        if (presa is null) return false;
        try { return !presa.SafeHandle.IsClosed && presa.Connected; }
        catch (ObjectDisposedException) { return false; }
    }

    private void AggiornaStato()
    {
        StatoCavo nuovo;
        lock (blocco)
        {
            if (!servizioRaggiunto) return;
            nuovo = dispositivi.Values.Any(d => Aperta(d.Presa)) ? StatoCavo.Collegato : StatoCavo.InAscolto;
        }
        Imposta(nuovo);
    }

    private void Imposta(StatoCavo nuovo)
    {
        lock (blocco)
        {
            if (statoNoto && stato == nuovo) return;
            statoNoto = true;
            stato = nuovo;
        }
        StatoCambiato?.Invoke(nuovo);
    }

    public async ValueTask DisposeAsync()
    {
        annulla.Cancel();
        DimenticaTutti();
        if (lavoro is not null)
        {
            try { await lavoro; } catch { }
        }
        GC.SuppressFinalize(this);
    }
}
