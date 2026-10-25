using System.Net.Sockets;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>Numeri mostrati sotto l'anteprima, aggiornati ogni secondo.</summary>
public sealed record Statistiche(int Larghezza, int Altezza, int Fps, double MegabitAlSecondo, int? LatenzaMs, Codec Codec = Codec.H264);

/// <summary>
/// La connessione con un telefono, lato computer: la stessa logica di Mac/Sorgenti/SessioneComputer.swift.
/// Gli eventi arrivano su thread di sistema: l'interfaccia li riporta sul proprio thread.
/// Protocollo 2: stretta di mano, poi tutto cifrato; il telefono passa solo se fidato, con il gettone
/// del QR code o confermato dall'utente (Documenti/Protocollo.md, «Collegamento sicuro»).
/// </summary>
public sealed class SessioneComputer : IAsyncDisposable
{
    public event Action<Ciao>? Salutato;
    public event Action<FormatoVideo>? FormatoRicevuto;
    public event Action<StatoTelefono>? StatoRicevuto;
    /// <summary>Cosa si può comandare sul telefono (obiettivi, zoom, torcia).</summary>
    public event Action<Capacita>? CapacitaRicevute;
    public event Action<Statistiche>? StatisticheAggiornate;
    public event Action<FotogrammaVideo>? FotogrammaRicevuto;
    /// <summary>Nessun dato da 3 secondi.</summary>
    public event Action? Silenzio;
    public event Action? Ripresa;
    public event Action? Chiusa;
    /// <summary>Il telefono non è fidato: il computer sta chiedendo all'utente (nome del telefono, codice).</summary>
    public event Action<string, string>? ConfermaInCorso;
    /// <summary>Il telefono non è stato ammesso (<see cref="Ammetti"/>): la sessione si chiude con «arrivederci».</summary>
    public event Action<Ciao>? NonAmmesso;

    /// <summary>Tempo per la stretta di mano e la prova; per la conferma dell'utente vale <see cref="AttesaConferma"/>.</summary>
    public static readonly TimeSpan AttesaStretta = TimeSpan.FromSeconds(10);
    public static readonly TimeSpan AttesaConferma = TimeSpan.FromSeconds(60);

    private readonly Socket presa;
    private readonly NetworkStream flusso;
    private readonly string nomeComputer;
    private readonly TimeSpan intervallo;
    private readonly CancellationTokenSource annulla = new();
    private readonly SemaphoreSlim scrittura = new(1, 1);
    private readonly MisuraLatenza latenza = new();
    private readonly object blocco = new();
    private readonly Abbinamento abbinamento;
    private readonly ulong inizio = Orologio.Adesso();

    private SessioneSicura? sicura;
    private bool provato;
    private string? gettoneProva;
    private int accettato;
    private int confermaInCorso;
    /// <summary>Il primo «ciao» avvia l'accettazione; un secondo, mentre si aspetta, non apre un'altra domanda.</summary>
    private bool inAccettazione;

    private FormatoVideo? formato;
    private int fotogrammiUltimoSecondo;
    private long byteUltimoSecondo;
    private ulong ultimoPacchetto = Orologio.Adesso();
    private bool inSilenzio;
    private int chiusa;
    private Task? lavoro;
    /// <summary>Solo sul thread di lettura: il primo fotogramma è già stato segnato nella misura dell'avvio.</summary>
    private bool videoArrivato;

    // Pausa intelligente: l'«anteprima» parte dopo il benvenuto e poi a ogni cambiamento, una alla volta e senza ripetere.
    private int anteprimaVisibile = 1;
    private int benvenutoInviato;
    private bool? anteprimaInviata;
    private readonly SemaphoreSlim inviiAnteprima = new(1, 1);

    /// <param name="intervallo">Ogni quanto mandare ping e statistiche: 1 secondo, più breve solo nei test.</param>
    /// <param name="arrivo">Quando la connessione è stata accettata (Orologio, µs), per misurare l'avvio (1.11).</param>
    public SessioneComputer(Socket presa, string nomeComputer, Abbinamento abbinamento, TimeSpan? intervallo = null,
        ulong? arrivo = null)
    {
        Avvio = new MisuraAvvio(arrivo);
        this.presa = presa;
        this.abbinamento = abbinamento;
        presa.NoDelay = true;
        flusso = new NetworkStream(presa, ownsSocket: true);
        this.nomeComputer = nomeComputer;
        this.intervallo = intervallo ?? TimeSpan.FromSeconds(1);
    }

    /// <summary>Dall'accettazione al primo fotogramma a schermo (1.11): l'ultima tappa la segna chi mostra il video.</summary>
    public MisuraAvvio Avvio { get; }

    /// <summary>L'impronta del telefono, dopo la stretta di mano.</summary>
    public string? ImprontaTelefono => sicura?.ImprontaAltro;

    private bool Accettato => Volatile.Read(ref accettato) == 1;

    /// <summary>
    /// Vero se l'ha chiusa il computer con «arrivederci» (Scollega, telefono rifiutato o sostituito):
    /// sul cavo USB quel telefono non va ricollegato da solo.
    /// </summary>
    public bool ChiusaDalComputer => Volatile.Read(ref chiusaDalComputer) == 1;
    private int chiusaDalComputer;

    /// <summary>Come è arrivato il telefono (1.2): Wi-Fi, cavo USB, cavo di rete, hotspot; null se non si sa.</summary>
    public TipoCollegamento? Collegamento { get; init; }

    /// <summary>
    /// Arrivata dal cavo USB (usbmux dell'iPhone, o rete del Tethering USB di Android) invece che dal Wi-Fi:
    /// per la precedenza del cavo sul Wi-Fi.
    /// </summary>
    public bool ViaCavo => Collegamento == TipoCollegamento.CavoUsb;

    /// <summary>
    /// Decide, dal codice di sicurezza del telefono, se può entrare, prima della fiducia e della domanda all'utente
    /// (P21: un terzo telefono non entra). Null = tutti. Si chiama dal thread di rete.
    /// </summary>
    public Func<string, bool>? Ammetti { get; init; }

    /// <summary>Vero dopo la chiusura, per qualsiasi motivo.</summary>
    public bool Terminata => Volatile.Read(ref chiusa) == 1;

    public void Avvia() => lavoro = Task.WhenAll(LeggiAsync(annulla.Token), OgniSecondoAsync(annulla.Token));

    /// <summary>Chiusura voluta: manda «arrivederci», così il telefono non si ricollega da solo.</summary>
    public async Task ChiudiAsync()
    {
        Volatile.Write(ref chiusaDalComputer, 1);
        try { await InviaAsync(new Arrivederci()); } catch { }
        Termina();
    }

    /// <summary>Comandi della fotocamera e degli effetti verso il telefono: solo i campi presenti.</summary>
    public Task ComandaAsync(Comando comando) => InviaAsync(comando);

    /// <summary>Il gobbo sul telefono: solo i campi presenti.</summary>
    public Task GobboAsync(Gobbo gobbo) => InviaAsync(gobbo);

    /// <summary>Chiede al telefono un formato (per esempio 60 fps per la webcam); il telefono risponde con quello vero.</summary>
    public Task ChiediFormatoAsync(FormatoVideo formato) => InviaAsync(formato);

    /// <summary>
    /// La finestra del computer mostra il video (pausa intelligente). Si può impostare prima di <see cref="Avvia"/>:
    /// il valore parte subito dopo il benvenuto.
    /// </summary>
    public bool AnteprimaVisibile
    {
        get => Volatile.Read(ref anteprimaVisibile) == 1;
        set => Volatile.Write(ref anteprimaVisibile, value ? 1 : 0);
    }

    /// <summary>Cambia <see cref="AnteprimaVisibile"/> e lo dice al telefono, se è accettato e se il valore è nuovo.</summary>
    public Task SegnalaAnteprimaAsync(bool visibile)
    {
        AnteprimaVisibile = visibile;
        return InviaAnteprimaAsync();
    }

    /// <summary>Uno alla volta: il valore si legge dentro il semaforo, così l'ultimo arrivato al telefono è quello giusto.</summary>
    private async Task InviaAnteprimaAsync()
    {
        await inviiAnteprima.WaitAsync();
        try
        {
            if (Volatile.Read(ref benvenutoInviato) == 0 || Terminata) return;
            var visibile = AnteprimaVisibile;
            if (anteprimaInviata == visibile) return;
            anteprimaInviata = visibile;
            await InviaAsync(new Anteprima(visibile));
        }
        finally { inviiAnteprima.Release(); }
    }

    /// <summary>Dice al telefono se un'app sta usando la webcam «WebcamLR»: lì compare il rosso «IN ONDA».</summary>
    public Task SegnalaAsync(InOnda inOnda) => InviaAsync(inOnda);

    public async ValueTask DisposeAsync()
    {
        Termina();
        if (lavoro is not null)
        {
            try { await lavoro; } catch { }
        }
    }

    private async Task LeggiAsync(CancellationToken annullato)
    {
        var lettore = new LettorePacchetti();
        var buffer = new byte[256 * 1024];
        try
        {
            while (!annullato.IsCancellationRequested)
            {
                var letti = await flusso.ReadAsync(buffer, annullato);
                if (letti == 0) break;
                lettore.Aggiungi(buffer.AsSpan(0, letti));
                while (lettore.Prossimo() is { } pacchetto)
                {
                    await GestisciAsync(pacchetto);
                }
            }
        }
        // Qualsiasi errore (rete, protocollo, stretta di mano o prova non valide) chiude subito: altrimenti la lettura
        // si fermerebbe e la sessione resterebbe in piedi fino al silenzio. I messaggi illeggibili dopo la prova
        // non arrivano qui: si saltano in GestisciAsync.
        catch (Exception) { }
        Termina();
    }

    private async Task GestisciAsync(Pacchetto ricevuto)
    {
        if (sicura is null)
        {
            // Prima di tutto la stretta di mano, in chiaro; qualsiasi altra cosa (anche un telefono
            // con il protocollo 1) chiude la connessione.
            if (ricevuto.Tipo != TipoPacchetto.Controllo || CodificaMessaggi.DaPacchetto(ricevuto) is not Stretta apertura)
                throw new ErroreProtocollo("Manca la stretta di mano");
            using var stretta = new StrettaComputer(abbinamento.Identita);
            var (risposta, sessione) = stretta.Rispondi(apertura);
            await InviaAsync(risposta, inChiaro: true);
            Avvio.Stretta();
            sicura = sessione;
            return;
        }
        var pacchetto = sicura.Canale.Decifra(ricevuto);
        if (!Accettato)
        {
            if (pacchetto.Tipo != TipoPacchetto.Controllo) return;
            // Fino alla prova ogni errore chiude; dopo, un messaggio illeggibile si salta (Protocollo.md, «Valori sconosciuti»).
            if (!provato) PrimaDiEssereAccettato(CodificaMessaggi.DaPacchetto(pacchetto));
            else if (CodificaMessaggi.DaPacchettoSeLeggibile(pacchetto) is { } messaggio) PrimaDiEssereAccettato(messaggio);
            return;
        }

        var adesso = Orologio.Adesso();
        bool riprende;
        lock (blocco)
        {
            ultimoPacchetto = adesso;
            riprende = inSilenzio;
            inSilenzio = false;
        }
        if (riprende) Ripresa?.Invoke();

        switch (pacchetto.Tipo)
        {
            case TipoPacchetto.Controllo:
                // Un messaggio illeggibile (telefono più nuovo, campo del tipo sbagliato) si salta: la sessione resta.
                if (CodificaMessaggi.DaPacchettoSeLeggibile(pacchetto) is { } messaggio) await GestisciAsync(messaggio, adesso);
                break;
            case TipoPacchetto.Video:
                var fotogramma = FotogrammaVideo.DaPacchetto(pacchetto);
                if (!videoArrivato)
                {
                    videoArrivato = true;
                    Avvio.PrimoFotogramma();
                }
                lock (blocco)
                {
                    fotogrammiUltimoSecondo++;
                    byteUltimoSecondo += pacchetto.Contenuto.Length;
                    latenza.Fotogramma(fotogramma.Timestamp, adesso);
                }
                FotogrammaRicevuto?.Invoke(fotogramma);
                break;
        }
    }

    private async Task GestisciAsync(Messaggio messaggio, ulong adesso)
    {
        switch (messaggio)
        {
            case Ciao:
                // Già accettato: un secondo «ciao» non cambia nulla.
                break;
            case Pong pong:
                lock (blocco) latenza.AggiungiPong(pong.T, pong.Telefono, adesso);
                break;
            // Dalla rete: nei limiti prima di arrivare alla finestra (ValoriSicuri). Un formato non credibile si ignora.
            case FormatoVideo arrivato when ValoriSicuri.Sanifica(arrivato) is { } nuovo:
                lock (blocco) formato = nuovo;
                FormatoRicevuto?.Invoke(nuovo);
                break;
            case StatoTelefono stato:
                StatoRicevuto?.Invoke(ValoriSicuri.Sanifica(stato));
                break;
            case Capacita capacita:
                CapacitaRicevute?.Invoke(ValoriSicuri.Sanifica(capacita));
                break;
            case Arrivederci:
                Termina();
                break;
        }
    }

    /// <summary>Prima del «benvenuto» contano solo la prova e il «ciao»; il video non arriva ancora.</summary>
    private void PrimaDiEssereAccettato(Messaggio messaggio)
    {
        switch (messaggio)
        {
            case Prova prova when !provato:
                if (!StrettaComputer.ProvaValida(prova, sicura!)) throw new ErroreProtocollo("Prova del telefono non valida");
                provato = true;
                gettoneProva = prova.Gettone;
                break;
            case Ciao ciao when provato && !inAccettazione:
                inAccettazione = true;
                _ = AccettaAsync(ValoriSicuri.Sanifica(ciao));
                break;
            case Arrivederci:
                Termina();
                break;
            case not Prova when !provato:
                throw new ErroreProtocollo("Messaggio prima della prova");
            default:
                // In attesa della conferma: il resto (per esempio un «formato» in anticipo) si ignora.
                break;
        }
    }

    private async Task AccettaAsync(Ciao ciao)
    {
        try
        {
            var impronta = sicura!.ImprontaAltro;
            if (Ammetti is { } ammetti && !ammetti(impronta))
            {
                NonAmmesso?.Invoke(ciao);
                await ChiudiAsync();
                return;
            }
            var consentito = abbinamento.Fidato(impronta) || abbinamento.UsaGettone(gettoneProva);
            if (!consentito && abbinamento.ChiediConferma is { } chiedi)
            {
                Volatile.Write(ref confermaInCorso, 1);
                Avvio.Conferma();
                await InviaAsync(new Approvazione(sicura.Codice));
                ConfermaInCorso?.Invoke(ciao.Nome, sicura.Codice);
                using var tempo = CancellationTokenSource.CreateLinkedTokenSource(annulla.Token);
                tempo.CancelAfter(AttesaConferma);
                try { consentito = await chiedi(ciao.Nome, sicura.Codice, tempo.Token); }
                catch (OperationCanceledException) { consentito = false; }
            }
            if (!consentito)
            {
                await ChiudiAsync();
                return;
            }
            abbinamento.Fida(impronta, ciao.Nome);
            lock (blocco) ultimoPacchetto = Orologio.Adesso();
            // Accettato e annunciato prima del benvenuto: ciò che il telefono manda subito dopo
            // (formato, video) trova già la sessione al suo posto e non va perso.
            Volatile.Write(ref accettato, 1);
            Salutato?.Invoke(ciao);
            await InviaAsync(new Benvenuto(Servizio.VersioneProtocollo, nomeComputer, Piattaforma.Windows));
            Avvio.Benvenuto();
            // Subito dopo il benvenuto: se la finestra mostra il video (pausa intelligente).
            Volatile.Write(ref benvenutoInviato, 1);
            await InviaAnteprimaAsync();
        }
        catch (Exception)
        {
            Termina();
        }
    }

    private async Task OgniSecondoAsync(CancellationToken annullato)
    {
        using var timer = new PeriodicTimer(intervallo);
        try
        {
            do
            {
                var adesso = Orologio.Adesso();
                if (!Accettato)
                {
                    // Non accettato in tempo (stretta di mano, prova e «ciao») si chiude; durante la conferma dell'utente si aspetta.
                    if (Volatile.Read(ref confermaInCorso) == 0 && adesso - inizio > (ulong)AttesaStretta.TotalMicroseconds)
                    {
                        Termina();
                        return;
                    }
                    continue;
                }
                await InviaAsync(new Ping(adesso));

                Statistiche statistiche;
                int? ultima;
                ulong silenzio;
                bool entraInSilenzio = false;
                lock (blocco)
                {
                    ultima = latenza.ChiudiSecondo();
                    var secondi = intervallo.TotalSeconds;
                    statistiche = new Statistiche(formato?.Larghezza ?? 0, formato?.Altezza ?? 0,
                        (int)Math.Round(fotogrammiUltimoSecondo / secondi),
                        byteUltimoSecondo * 8 / 1_000_000.0 / secondi, ultima, formato?.Codec ?? Codec.H264);
                    fotogrammiUltimoSecondo = 0;
                    byteUltimoSecondo = 0;
                    silenzio = adesso - Math.Min(ultimoPacchetto, adesso);
                    if (silenzio > 3_000_000 && !inSilenzio)
                    {
                        inSilenzio = true;
                        entraInSilenzio = true;
                    }
                }
                if (ultima is int ms) await InviaAsync(new Latenza(ms));
                StatisticheAggiornate?.Invoke(statistiche);
                if (silenzio > 10_000_000) { Termina(); return; }
                if (entraInSilenzio) Silenzio?.Invoke();
            }
            while (await timer.WaitForNextTickAsync(annullato));
        }
        catch (OperationCanceledException) { }
        catch (IOException) { Termina(); }
        catch (ObjectDisposedException) { }
    }

    private async Task InviaAsync(Messaggio messaggio, bool inChiaro = false)
    {
        var pacchetto = CodificaMessaggi.ComePacchetto(messaggio);
        await scrittura.WaitAsync();
        try
        {
            // Si cifra dentro il semaforo: l'ordine dei contatori è quello di scrittura.
            if (!inChiaro)
            {
                if (sicura is null) return;
                pacchetto = sicura.Canale.Cifra(pacchetto);
            }
            await flusso.WriteAsync(pacchetto.Codificato());
        }
        finally { scrittura.Release(); }
    }

    private void Termina()
    {
        if (Interlocked.Exchange(ref chiusa, 1) == 1) return;
        annulla.Cancel();
        try { presa.Shutdown(SocketShutdown.Both); } catch { }
        flusso.Dispose();
        Chiusa?.Invoke();
    }
}
