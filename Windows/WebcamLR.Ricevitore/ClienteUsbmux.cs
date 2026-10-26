using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;

namespace WebcamLR.Ricevitore;

/// <summary>A che punto è il cavo USB, per la finestra e la diagnosi.</summary>
public enum StatoCavo
{
    /// <summary>Il servizio di Apple (app «Dispositivi Apple») non risponde sulla porta 27015.</summary>
    ServizioAssente,
    /// <summary>Il servizio c'è e avvisa quando si collega un iPhone; nessun telefono parla con noi sul cavo.</summary>
    InAscolto,
    /// <summary>Un iPhone è collegato con il cavo e la connessione verso WebcamLR sull'iPhone è aperta.</summary>
    Collegato,
}

/// <summary>Un messaggio usbmux: l'etichetta dell'intestazione e il plist.</summary>
public sealed record MessaggioUsbmux(uint Etichetta, Dictionary<string, object> Contenuto)
{
    public const int LunghezzaIntestazione = 16;
    public const uint Versione = 1;
    public const uint TipoPlist = 8;
    /// <summary>Un messaggio più lungo di così non è usbmux: la connessione si chiude.</summary>
    public const int LunghezzaMassima = 1 << 20;

    public string? Tipo => Contenuto.GetValueOrDefault("MessageType") as string;

    /// <summary>Intestazione di 16 byte little-endian (lunghezza totale, versione 1, tipo 8, etichetta) e plist XML.</summary>
    public static byte[] Codifica(uint etichetta, IReadOnlyDictionary<string, object> contenuto)
    {
        var plist = Plist.Scrivi(contenuto);
        var messaggio = new byte[LunghezzaIntestazione + plist.Length];
        var intestazione = messaggio.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[0..], (uint)messaggio.Length);
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[4..], Versione);
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[8..], TipoPlist);
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[12..], etichetta);
        plist.CopyTo(messaggio, LunghezzaIntestazione);
        return messaggio;
    }

    /// <summary>
    /// Legge esattamente un messaggio, senza un byte di più: dopo un Connect riuscito ciò che segue
    /// è già la nostra connessione con l'iPhone. Null se la connessione si chiude prima di un messaggio intero.
    /// </summary>
    public static async Task<MessaggioUsbmux?> LeggiAsync(Stream flusso, CancellationToken annullato)
    {
        var intestazione = new byte[LunghezzaIntestazione];
        if (!await LeggiTuttoAsync(flusso, intestazione, annullato)) return null;
        var lunghezza = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(0));
        var versione = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(4));
        var tipo = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(8));
        var etichetta = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(12));
        if (lunghezza < LunghezzaIntestazione || lunghezza > LunghezzaMassima)
            throw new FormatException($"Lunghezza usbmux non valida: {lunghezza}");
        if (versione != Versione || tipo != TipoPlist)
            throw new FormatException($"Messaggio usbmux non previsto (versione {versione}, tipo {tipo})");
        var contenuto = new byte[lunghezza - LunghezzaIntestazione];
        if (!await LeggiTuttoAsync(flusso, contenuto, annullato)) return null;
        return new MessaggioUsbmux(etichetta, Plist.Leggi(contenuto));
    }

    private static async Task<bool> LeggiTuttoAsync(Stream flusso, byte[] buffer, CancellationToken annullato)
    {
        var letti = 0;
        while (letti < buffer.Length)
        {
            var n = await flusso.ReadAsync(buffer.AsMemory(letti), annullato);
            if (n == 0) return false;
            letti += n;
        }
        return true;
    }

    /// <summary>Un numero del plist, qualunque sia il tipo con cui è stato letto.</summary>
    public long? Numero(string chiave) => Contenuto.GetValueOrDefault(chiave) switch
    {
        long numero => numero,
        double reale => (long)reale,
        string testo when long.TryParse(testo, out var numero) => numero,
        _ => null,
    };
}

/// <summary>
/// Il cavo USB su Windows (aggiornamento 1.7), scritto da zero: parla con usbmux, il servizio di Apple
/// installato con l'app «Dispositivi Apple», su 127.0.0.1:27015 (Documenti/Protocollo.md, «Collegamento via cavo USB»).
/// Manda «Listen»; a ogni iPhone collegato con il cavo («Attached», ConnectionType USB) apre un'altra connessione
/// e chiede «Connect» verso la porta 52741 dell'iPhone. Con Result 0 quella connessione è un canale TCP verso
/// WebcamLR sull'iPhone: arriva con <see cref="TelefonoViaCavo"/> e si usa come una connessione Wi-Fi
/// (il telefono manda per primo la «stretta»). Finché l'iPhone resta collegato, se l'app non risponde
/// si riprova ogni 2 secondi; quando la connessione si chiude, anche. Se invece il telefono accetta la
/// connessione ma la chiude prima di essere accettato (rifiuta il cavo: altro computer, conferma in sospeso,
/// cavo escluso per questa sessione), l'attesa raddoppia a ogni volta: 2, 4, 8 … fino a 30 secondi.
/// Si torna a 2 secondi con un collegamento accettato (<see cref="StrettaRiuscita"/>) o ricollegando il cavo.
/// Gli eventi arrivano su thread di sistema.
/// </summary>
public sealed class ClienteUsbmux : IAsyncDisposable
{
    public const int PortaServizio = 27015;
    /// <summary>La porta su cui WebcamLR sull'iPhone ascolta, solo su 127.0.0.1 (raggiungibile solo dal cavo).</summary>
    public const ushort PortaTelefono = 52741;
    public const string NomeProgramma = "WebcamLR";

    /// <summary>Una connessione verso WebcamLR sull'iPhone, attraverso il cavo: da dare a una SessioneComputer.</summary>
    public event Action<Socket>? TelefonoViaCavo;
    public event Action<StatoCavo>? StatoCambiato;
    /// <summary>Per il registro del collegamento: frasi brevi su ciò che succede sul cavo.</summary>
    public event Action<string>? Evento;

    private readonly IPEndPoint servizio;
    private readonly TimeSpan intervalloRiprova;
    private readonly TimeSpan attesaMassima;
    private readonly TimeSpan attesaServizio;
    private readonly TimeSpan attesaRisposta;
    private readonly CancellationTokenSource annulla = new();
    private readonly object blocco = new();
    private readonly Dictionary<long, Dispositivo> dispositivi = new();
    private StatoCavo stato = StatoCavo.ServizioAssente;
    /// <summary>Falso fino al primo tentativo di raggiungere il servizio: prima lo stato non dice ancora nulla.</summary>
    private bool statoNoto;
    private bool servizioRaggiunto;
    private uint etichetta;
    private Task? lavoro;
    /// <summary>Completata da <see cref="Riprendi"/>: interrompe le attese in corso (servizio, Connect, rifiuti).</summary>
    private TaskCompletionSource sveglia = NuovaSveglia();

    private sealed class Dispositivo(long id)
    {
        public long Id { get; } = id;
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

    /// <param name="servizio">Dove risponde usbmux: 127.0.0.1:27015, un'altra porta solo nei test.</param>
    /// <param name="intervalloRiprova">Ogni quanto riprovare il Connect mentre l'iPhone è collegato: 2 secondi.</param>
    /// <param name="attesaServizio">Ogni quanto riprovare a raggiungere il servizio se manca: 5 secondi.</param>
    /// <param name="attesaMassima">Il limite dell'attesa che raddoppia quando il telefono rifiuta il cavo: 30 secondi.</param>
    public ClienteUsbmux(IPEndPoint? servizio = null, TimeSpan? intervalloRiprova = null, TimeSpan? attesaServizio = null,
        TimeSpan? attesaMassima = null)
    {
        this.servizio = servizio ?? new IPEndPoint(IPAddress.Loopback, PortaServizio);
        this.intervalloRiprova = intervalloRiprova ?? TimeSpan.FromSeconds(2);
        this.attesaMassima = attesaMassima ?? TimeSpan.FromSeconds(30);
        this.attesaServizio = attesaServizio ?? TimeSpan.FromSeconds(5);
        attesaRisposta = TimeSpan.FromSeconds(5);
    }

    public StatoCavo Stato
    {
        get { lock (blocco) return stato; }
    }

    /// <summary>
    /// Vero se almeno un iPhone è collegato con il cavo e si sta cercando di parlargli, anche se WebcamLR
    /// sull'iPhone non risponde. Un iPhone sospeso (Scollega, rifiutato) non conta: non si ricollega da solo,
    /// e la diagnosi non deve dire «il collegamento parte da solo».
    /// </summary>
    public bool IPhoneAlCavo
    {
        get { lock (blocco) return dispositivi.Values.Any(d => !d.Sospeso && !d.InPausaPerScelta); }
    }

    /// <summary>Vero dopo il primo tentativo di raggiungere il servizio: prima lo stato non dice ancora nulla.</summary>
    public bool Verificato
    {
        get { lock (blocco) return statoNoto; }
    }

    /// <summary>Il byte order di rete per PortNumber: 52741 (0xCE05) diventa 0x05CE = 1486.</summary>
    public static ushort InOrdineDiRete(ushort porta) => (ushort)((porta >> 8) | (porta << 8));

    public void Avvia() => lavoro ??= Task.Run(() => ServizioAsync(annulla.Token));

    /// <summary>
    /// La connessione è stata chiusa dal computer (Scollega, telefono rifiutato o sostituito): quell'iPhone
    /// non si ricollega da solo finché il cavo non viene staccato e ricollegato. Senza, due telefoni si
    /// caccerebbero a vicenda e un telefono rifiutato chiederebbe di nuovo ogni 2 secondi.
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
    /// staccato e il cavo serve a non perdere il video. Gli iPhone sospesi da «Scollega» restano sospesi.
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
    /// funziona, e se più avanti la connessione si chiude si riprova di nuovo ogni 2 secondi.
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
    /// riparte da capo. Un iPhone sospeso (Scollega, rifiutato) resta sospeso: lo ha deciso l'utente.
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
    private async Task<bool> AttendiAsync(TimeSpan attesa, CancellationToken annullato)
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
    /// Quanto aspettare prima del prossimo Connect dopo <paramref name="rifiuti"/> connessioni di fila chiuse
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
            try
            {
                using var presa = await ApriAsync(annullato);
                await using var flusso = new NetworkStream(presa, ownsSocket: false);
                var richiesta = ProssimaEtichetta();
                await flusso.WriteAsync(MessaggioUsbmux.Codifica(richiesta, Richiesta("Listen")), annullato);
                lock (blocco) servizioRaggiunto = true;
                Evento?.Invoke(TestiRicevitore.T("Cavo_ServizioTrovato"));
                await AscoltaAsync(flusso, richiesta, annullato);
                Evento?.Invoke(TestiRicevitore.T("Cavo_ServizioFermo"));
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

    /// <summary>Legge gli avvisi del servizio finché la connessione resta aperta.</summary>
    private async Task AscoltaAsync(NetworkStream flusso, uint richiesta, CancellationToken annullato)
    {
        while (await MessaggioUsbmux.LeggiAsync(flusso, annullato) is { } messaggio)
        {
            switch (messaggio.Tipo)
            {
                case "Result" when messaggio.Etichetta == richiesta:
                    // Listen rifiutato: il servizio non è utilizzabile, si riprova più tardi.
                    if (messaggio.Numero("Number") != 0) return;
                    Imposta(StatoCavo.InAscolto);
                    break;
                case "Attached":
                    var proprieta = messaggio.Contenuto.GetValueOrDefault("Properties") as Dictionary<string, object>;
                    // Gli iPhone sincronizzati in Wi-Fi compaiono come «Network»: per noi conta solo il cavo.
                    if (proprieta?.GetValueOrDefault("ConnectionType") as string != "USB") break;
                    if (messaggio.Numero("DeviceID") is long collegato) Collega(collegato);
                    break;
                case "Detached":
                    if (messaggio.Numero("DeviceID") is long staccato) Stacca(staccato);
                    break;
            }
        }
    }

    private void Collega(long id)
    {
        Dispositivo nuovo;
        lock (blocco)
        {
            if (dispositivi.ContainsKey(id)) return;
            nuovo = new Dispositivo(id);
            dispositivi[id] = nuovo;
        }
        Evento?.Invoke(TestiRicevitore.T("Cavo_IPhoneCollegato"));
        _ = Task.Run(() => DispositivoAsync(nuovo));
    }

    private void Stacca(long id)
    {
        Dispositivo? staccato;
        lock (blocco)
        {
            if (!dispositivi.Remove(id, out staccato)) return;
        }
        staccato.Fine.Cancel();
        Evento?.Invoke(TestiRicevitore.T("Cavo_IPhoneStaccato"));
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

    /// <summary>Finché l'iPhone resta collegato: Connect, e se non riesce (o la connessione si chiude) si riprova.</summary>
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
                        Evento?.Invoke(TestiRicevitore.T("Cavo_Rifiutato", Secondi(attesa)));
                    // Il controllo che ha visto la chiusura vale già un intervallo: si aspetta solo il resto.
                    var resto = attesa - intervalloRiprova;
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
                        Evento?.Invoke(TestiRicevitore.T("Cavo_Collegato"));
                        // Chi riceve lavora su questo thread (1.11): un suo errore non deve fermare il ciclo, altrimenti
                        // l'iPhone non si ricollegherebbe più fino a quando non viene staccato. La presa chiusa
                        // vale come un rifiuto e si riprova.
                        try { TelefonoViaCavo?.Invoke(presa); }
                        catch (Exception) { presa.Dispose(); }
                    }
                }
                await AttendiAsync(intervalloRiprova, annullato);
            }
        }
        catch (OperationCanceledException) { }
        AggiornaStato();
    }

    /// <summary>Una connessione nuova al servizio e «Connect»: con Result 0 diventa il canale verso l'iPhone.</summary>
    private async Task<Socket?> ConnettiAsync(long id, CancellationToken annullato)
    {
        Socket? presa = null;
        try
        {
            presa = await ApriAsync(annullato);
            using var tempo = CancellationTokenSource.CreateLinkedTokenSource(annullato);
            tempo.CancelAfter(attesaRisposta);
            var richiesta = ProssimaEtichetta();
            var contenuto = Richiesta("Connect");
            contenuto["DeviceID"] = id;
            contenuto["PortNumber"] = (int)InOrdineDiRete(PortaTelefono);
            // Senza possedere la presa: chiudere il flusso non deve chiudere il canale verso l'iPhone.
            using var flusso = new NetworkStream(presa, ownsSocket: false);
            await flusso.WriteAsync(MessaggioUsbmux.Codifica(richiesta, contenuto), tempo.Token);
            var risposta = await MessaggioUsbmux.LeggiAsync(flusso, tempo.Token);
            if (risposta is { Tipo: "Result" } && risposta.Etichetta == richiesta && risposta.Numero("Number") == 0)
            {
                var pronta = presa;
                presa = null;
                return pronta;
            }
            return null;
        }
        catch (OperationCanceledException) when (annullato.IsCancellationRequested) { throw; }
        catch (Exception) { return null; }
        finally { presa?.Dispose(); }
    }

    private static string Secondi(TimeSpan attesa)
    {
        var secondi = Math.Max(1, (int)Math.Round(attesa.TotalSeconds));
        return secondi == 1 ? TestiRicevitore.T("Cavo_UnSecondo") : TestiRicevitore.T("Cavo_Secondi", secondi);
    }

    private async Task<Socket> ApriAsync(CancellationToken annullato)
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

    private static Dictionary<string, object> Richiesta(string tipo) => new()
    {
        ["MessageType"] = tipo,
        ["ClientVersionString"] = NomeProgramma,
        ["ProgName"] = NomeProgramma,
        ["kLibUSBMuxVersion"] = 3,
    };

    private uint ProssimaEtichetta() => Interlocked.Increment(ref etichetta);

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
    }
}
