using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;
using WebcamLR.Protocollo;

namespace WebcamLR.Collaudo;

/// <summary>Come finisce una sessione del telefono finto (anche il codice di uscita del programma).</summary>
public enum Esito
{
    Finita = 0,
    /// <summary>Il computer non ha accettato (arrivederci o connessione chiusa prima del benvenuto, o tempo scaduto).</summary>
    Rifiutato = 2,
    /// <summary>Connessione non riuscita o caduta per un errore.</summary>
    ErroreRete = 3,
    /// <summary>Il computer ha chiuso la sessione dopo il benvenuto (arrivederci o connessione chiusa).</summary>
    ChiusaDalComputer = 4,
    /// <summary>Interruzione simulata (--interrompi-dopo senza --riconnetti-dopo).</summary>
    Interrotta = 5,
}

/// <summary>
/// Un telefono finto che parla il protocollo 2 come l'app dell'iPhone (stretta di mano, prova, tutto cifrato), nato dal
/// TelefonoFinto dei test di WebcamLR.Ricevitore.Test e allargato per il collaudo: video sintetico vero (H.264 I_PCM),
/// capacità, stato ogni 5 secondi, comandi applicati e confermati, pausa automatica, interruzione della rete simulata.
/// </summary>
public sealed class Telefono
{
    private readonly Opzioni opzioni;
    private readonly IdentitaDispositivo identita;
    private readonly Action<string> scrivi;
    private readonly Stopwatch vita = Stopwatch.StartNew();
    private readonly SemaphoreSlim scrittura = new(1, 1);

    private TcpClient? cliente;
    private NetworkStream? flusso;
    private SessioneSicura? sicura;
    private readonly Channel<Messaggio> ricevuti = Channel.CreateUnbounded<Messaggio>();
    private volatile bool muto;
    private volatile bool inPausa;
    private volatile bool chiusoDalComputer;
    private (int Larghezza, int Altezza, int Fps) formato;
    private readonly object blocco = new();

    // Lo stato della «fotocamera», cambiato dai comandi del computer e rimandato in «stato».
    private string obiettivo = "principale";
    private double zoom = 1;
    private bool torcia;
    private double esposizione;
    private bool specchia;
    private string filtro = Filtri.Naturale;
    private string sfondo = ModiSfondo.Nessuno;
    private string qualita = LivelliQualita.Auto;
    private string? ultimoComando;
    private int? ultimaLatenza;
    private bool? inOnda;
    /// <summary>Il microfono manda l'audio (dopo «comando audio» vero, se --audio).</summary>
    private volatile bool audioAcceso;
    private int generazioneAudio;
    public long PacchettiAudioInviati { get; private set; }

    public long FotogrammiInviati { get; private set; }

    public Telefono(Opzioni opzioni, IdentitaDispositivo identita, Action<string> scrivi)
    {
        this.opzioni = opzioni;
        this.identita = identita;
        this.scrivi = scrivi;
        formato = (opzioni.Larghezza, opzioni.Altezza, opzioni.Fps);
    }

    /// <summary>Una sessione intera: collegamento, abbinamento, video fino alla fine o all'interruzione.</summary>
    public async Task<Esito> SessioneAsync(TimeSpan durata, TimeSpan? interrompiDopo, CancellationToken annulla)
    {
        using var fine = CancellationTokenSource.CreateLinkedTokenSource(annulla);
        fine.CancelAfter(durata);
        try
        {
            cliente = new TcpClient { NoDelay = true };
            scrivi($"Collegamento a {opzioni.Indirizzo}:{opzioni.Porta} come «{opzioni.Nome}» (impronta {identita.Impronta})");
            await cliente.ConnectAsync(IPAddress.Parse(opzioni.Indirizzo), opzioni.Porta, fine.Token);
            flusso = cliente.GetStream();

            using var stretta = new StrettaTelefono(identita);
            await ScriviAsync(CodificaMessaggi.ComePacchetto(stretta.Apertura), fine.Token);
            var lettore = new LettorePacchetti();
            var risposta = await LeggiUnoAsync(lettore, fine.Token);
            var (sessione, prova) = stretta.Completa((Stretta)CodificaMessaggi.DaPacchetto(risposta), opzioni.Gettone);
            sicura = sessione;
            scrivi($"Stretta di mano riuscita: computer {sessione.ImprontaAltro}, codice di controllo {sessione.Codice}");
            if (opzioni.ImprontaAttesa is { } attesa && attesa != sessione.ImprontaAltro)
            {
                scrivi($"RIFIUTATO dal telefono: l'impronta del computer non è quella del QR ({attesa})");
                return Esito.Rifiutato;
            }
            var lettura = LeggiAsync(lettore, fine.Token);
            await InviaAsync(prova, fine.Token);
            scrivi(opzioni.Gettone is null ? "Prova mandata senza gettone" : $"Prova mandata con il gettone {opzioni.Gettone}");
            await InviaAsync(new Ciao(Servizio.VersioneProtocollo, opzioni.Nome, opzioni.Piattaforma, "collaudo"), fine.Token);

            // Il benvenuto: subito se fidato o con il gettone giusto, altrimenti dopo la conferma sul computer (60 s).
            var benvenuto = await AttendiBenvenutoAsync(fine.Token);
            if (benvenuto is null)
            {
                scrivi("RIFIUTATO: il computer non ha accettato il telefono");
                return Esito.Rifiutato;
            }
            scrivi($"ACCETTATO dal computer «{benvenuto.Nome}» ({benvenuto.Piattaforma})");

            await InviaAsync(Capacita(), fine.Token);
            await InviaAsync(Stato(), fine.Token);
            var stato = StatoPeriodicoAsync(fine.Token);
            var video = opzioni.SenzaVideo ? Task.CompletedTask : VideoAsync(fine.Token);

            Task attesaInterruzione = interrompiDopo is { } dopo ? Task.Delay(dopo, fine.Token) : Task.Delay(Timeout.Infinite, fine.Token);
            var finita = await Task.WhenAny(lettura, attesaInterruzione, Task.Delay(Timeout.Infinite, fine.Token));
            if (finita == attesaInterruzione && attesaInterruzione.IsCompletedSuccessfully)
            {
                await InterrompiAsync(fine.Token);
                return Esito.Interrotta;
            }
            if (finita == lettura)
            {
                scrivi(chiusoDalComputer ? "Il computer ha chiuso la sessione (arrivederci)" : "Connessione chiusa dal computer");
                return Esito.ChiusaDalComputer;
            }
            // Durata finita: chiusura volontaria come il telefono vero.
            try { await InviaAsync(new Arrivederci(), CancellationToken.None); } catch (Exception) { }
            scrivi($"Fine della durata: arrivederci mandato ({FotogrammiInviati} fotogrammi inviati)");
            return Esito.Finita;
        }
        catch (OperationCanceledException) when (annulla.IsCancellationRequested)
        {
            try { await InviaAsync(new Arrivederci(), CancellationToken.None); } catch (Exception) { }
            scrivi("Interrotto dall'utente: arrivederci mandato");
            return Esito.Finita;
        }
        catch (OperationCanceledException)
        {
            scrivi("Tempo scaduto");
            return sicura is null ? Esito.ErroreRete : Esito.Finita;
        }
        catch (Exception errore) when (errore is SocketException or IOException or ErroreProtocollo or InvalidCastException)
        {
            scrivi($"ERRORE di rete: {errore.Message}");
            return Esito.ErroreRete;
        }
        finally
        {
            fine.Cancel();
            cliente?.Dispose();
        }
    }

    /// <summary>
    /// La rete che cade: «silenzio» (il Wi-Fi sparisce: niente più pong, video né stato, la connessione resta aperta
    /// finché il computer non la chiude) oppure «chiusura» (la connessione si chiude di colpo, senza arrivederci).
    /// </summary>
    private async Task InterrompiAsync(CancellationToken annulla)
    {
        if (opzioni.ModoInterruzione == "chiusura")
        {
            scrivi("INTERRUZIONE simulata: connessione chiusa di colpo, senza arrivederci");
            if (cliente is not null)
            {
                cliente.Client.LingerState = new LingerOption(true, 0); // RST, come una rete che sparisce
                cliente.Dispose();
            }
            return;
        }
        scrivi("INTERRUZIONE simulata: il telefono tace (niente pong, video né stato)");
        muto = true;
        // Si resta in silenzio per la durata della pausa (o finché il computer chiude).
        var silenzio = opzioni.RiconnettiDopo ?? TimeSpan.FromSeconds(30);
        try { await Task.Delay(silenzio, annulla); } catch (OperationCanceledException) { }
        cliente?.Dispose();
    }

    private async Task<Benvenuto?> AttendiBenvenutoAsync(CancellationToken annulla)
    {
        using var limite = CancellationTokenSource.CreateLinkedTokenSource(annulla);
        limite.CancelAfter(TimeSpan.FromSeconds(opzioni.AttesaAbbinamento));
        try
        {
            while (true)
            {
                var messaggio = await ricevuti.Reader.ReadAsync(limite.Token);
                switch (messaggio)
                {
                    case Benvenuto benvenuto: return benvenuto;
                    case Approvazione approvazione:
                        scrivi($"CODICE {approvazione.Codice}: il computer chiede conferma («Consenti» sul PC)");
                        break;
                    case Arrivederci: return null;
                }
            }
        }
        catch (OperationCanceledException) when (!annulla.IsCancellationRequested) { return null; }
        catch (ChannelClosedException) { return null; }
    }

    private Capacita Capacita()
    {
        var formati = new List<FormatoSupportato>();
        foreach (var (l, a) in new[] { (3840, 2160), (1920, 1080), (1280, 720), (960, 540), (640, 360) })
            if (l * a <= opzioni.Larghezza * opzioni.Altezza) formati.Add(new FormatoSupportato(l, a, opzioni.Fps));
        if (formati.Count == 0 || formati[0].Larghezza != opzioni.Larghezza)
            formati.Insert(0, new FormatoSupportato(opzioni.Larghezza, opzioni.Altezza, opzioni.Fps));
        return new Capacita(["grandangolo", "principale", "frontale"], 5, true, IsoMinimo: 50, IsoMassimo: 3200,
            Filtri: Filtri.Tutti, Sfondo: true, Pelle: true, Inquadratura: true, LuceVolto: true, Scritta: true,
            DoppiaVista: false, Postura: true, Gobbo: true, Audio: opzioni.Audio, Formati: formati, Specchia: true,
            Pro: opzioni.Pro ? true : null, SceltaCollegamento: false, SfondiPronti: SfondiPronti.Tutti, Immagini: false,
            Calore: true, EffettiSulComputer: opzioni.EffettiSulComputer, SceltaQualita: true);
    }

    private StatoTelefono Stato()
    {
        lock (blocco)
            return new StatoTelefono(opzioni.Batteria, opzioni.InCarica, opzioni.Temperatura, obiettivo,
                Filtro: filtro, Sfondo: sfondo, Pausa: inPausa ? MotiviPausa.NessunaApp : null, Specchia: specchia,
                Zoom: zoom, Torcia: torcia, Esposizione: esposizione, Bianco: 0, Iso: 0, Tempo: 0,
                Collegamento: new StatoCollegamento(StradeCollegamento.Wifi, PreferenzeCollegamento.Automatico,
                    [new StradaCollegamento(StradeCollegamento.Wifi, ultimaLatenza)]),
                Qualita: qualita, Audio: opzioni.Audio ? audioAcceso : null);
    }

    private async Task StatoPeriodicoAsync(CancellationToken annulla)
    {
        try
        {
            while (!annulla.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromSeconds(5), annulla);
                if (!muto) await InviaAsync(Stato(), annulla);
            }
        }
        catch (Exception) { }
    }

    private async Task VideoAsync(CancellationToken annulla)
    {
        try
        {
            (int, int, int) formatoInviato = default;
            CodificatorePcm? codificatore = null;
            Disegno? disegno = null;
            var prossimo = vita.Elapsed;
            while (!annulla.IsCancellationRequested)
            {
                (int L, int A, int Fps) adesso;
                lock (blocco) adesso = formato;
                var intervallo = TimeSpan.FromSeconds(1.0 / Math.Max(1, adesso.Fps));
                if (muto || inPausa)
                {
                    formatoInviato = default; // alla ripresa: di nuovo «formato» e un fotogramma chiave
                    await Task.Delay(intervallo, annulla);
                    prossimo = vita.Elapsed;
                    continue;
                }
                if (formatoInviato != adesso)
                {
                    codificatore = new CodificatorePcm(adesso.L, adesso.A);
                    disegno = new Disegno(adesso.L, adesso.A);
                    await InviaAsync(new FormatoVideo(Codec.H264, adesso.L, adesso.A, adesso.Fps), annulla);
                    scrivi($"Formato inviato: {adesso.L}×{adesso.A} a {adesso.Fps} fps (H.264 I_PCM)");
                    formatoInviato = adesso;
                }
                var cattura = Orologio.Adesso();
                disegno!.Disegna(FotogrammiInviati, DateTime.Now, vita.Elapsed.TotalSeconds, Righe(adesso), specchia);
                var dati = codificatore!.Codifica(disegno.Y, disegno.Cb, disegno.Cr);
                await ScriviAsync(new FotogrammaVideo(cattura, true, true, dati).ComePacchetto(), annulla);
                FotogrammiInviati++;
                if (FotogrammiInviati == 1 || FotogrammiInviati % (adesso.Fps * 10) == 0)
                    scrivi($"Video: {FotogrammiInviati} fotogrammi inviati ({dati.Length / 1024} KB l'uno)");
                prossimo += intervallo;
                var attesa = prossimo - vita.Elapsed;
                if (attesa > TimeSpan.Zero) await Task.Delay(attesa, annulla);
                else if (attesa < -intervallo * 5) prossimo = vita.Elapsed; // in ritardo: si salta, non si recupera
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception errore) when (errore is IOException or SocketException or ObjectDisposedException)
        {
            if (!muto) scrivi($"Video fermo: {errore.Message}");
        }
    }

    /// <summary>«comando audio»: con --audio il microfono si accende o si spegne; senza, il telefono lo ignora.</summary>
    private void CambiaAudio(bool acceso, CancellationToken annulla)
    {
        if (!opzioni.Audio)
        {
            scrivi("Audio chiesto ma il telefono non ha il microfono (capacita.audio falso): ignorato");
            return;
        }
        if (acceso == audioAcceso) return;
        audioAcceso = acceso;
        var generazione = Interlocked.Increment(ref generazioneAudio);
        scrivi(acceso ? "MICROFONO acceso dal computer" : "MICROFONO spento dal computer");
        if (acceso) _ = AudioAsync(generazione, annulla);
    }

    /// <summary>
    /// I frame di tono.aac (ADTS) senza intestazione, uno ogni 1024 campioni a 48 kHz, con il timestamp sull'orologio dei
    /// fotogrammi, come il telefono vero (Protocollo.md, «Audio»).
    /// </summary>
    private async Task AudioAsync(int generazione, CancellationToken annulla)
    {
        try
        {
            var frame = FrameAudio.Leggi(Path.Combine(AppContext.BaseDirectory, "tono.aac"));
            await InviaAsync(FormatoAudio.AAC48kMono(), annulla);
            scrivi($"Formato audio inviato: AAC-LC 48 kHz mono ({frame.Count} frame a ciclo)");
            var inizio = vita.Elapsed;
            var t0 = Orologio.Adesso();
            long n = 0;
            var spentoDopo = opzioni.MicrofonoSpentoDopo;
            while (!annulla.IsCancellationRequested && audioAcceso && generazione == Volatile.Read(ref generazioneAudio))
            {
                if (spentoDopo is { } dopo && vita.Elapsed - inizio >= dopo)
                {
                    spentoDopo = null;
                    audioAcceso = false;
                    scrivi("MICROFONO spento dal telefono (--microfono-spento-dopo)");
                    await InviaAsync(Stato(), annulla);
                    return;
                }
                if (muto || inPausa)
                {
                    await Task.Delay(20, annulla);
                    inizio = vita.Elapsed;
                    t0 = Orologio.Adesso();
                    n = 0;
                    continue;
                }
                var ts = t0 + (ulong)(n * 1_000_000L * FormatoAudio.CampioniPerPacchetto / 48_000);
                await ScriviAsync(new PacchettoAudio(ts, frame[(int)(n % frame.Count)]).ComePacchetto(), annulla);
                n++;
                PacchettiAudioInviati++;
                if (PacchettiAudioInviati == 1 || PacchettiAudioInviati % 470 == 0)
                    scrivi($"Audio: {PacchettiAudioInviati} pacchetti inviati");
                var prossimo = TimeSpan.FromTicks(n * TimeSpan.TicksPerSecond * FormatoAudio.CampioniPerPacchetto / 48_000);
                var attesa = prossimo - (vita.Elapsed - inizio);
                if (attesa > TimeSpan.Zero) await Task.Delay(attesa, annulla);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception errore) when (errore is IOException or SocketException or ObjectDisposedException or FileNotFoundException)
        {
            if (!muto) scrivi($"Audio fermo: {errore.Message}");
        }
    }

    private List<string> Righe((int L, int A, int Fps) adesso)
    {
        lock (blocco)
        {
            var righe = new List<string>
            {
                $"{opzioni.Nome} · {adesso.L}×{adesso.A} {adesso.Fps} FPS",
                $"OBIETTIVO {obiettivo}  ZOOM {zoom:0.0}  TORCIA {(torcia ? "SÌ" : "NO")}  ESP {esposizione:+0.0;-0.0;0.0}",
                $"FILTRO {filtro}  SFONDO {sfondo}  QUALITÀ {qualita}" + (inOnda == true ? "  IN ONDA" : ""),
            };
            if (ultimaLatenza is { } ms) righe.Add($"LATENZA {ms} MS");
            if (ultimoComando is { } comando) righe.Add($"ULTIMO COMANDO: {comando}");
            return righe;
        }
    }

    private void Applica(Comando c)
    {
        var parti = new List<string>();
        lock (blocco)
        {
            if (c.Obiettivo is { } o) { obiettivo = o; zoom = 1; parti.Add($"obiettivo {o}"); }
            if (c.Zoom is { } z) { zoom = Math.Clamp(z, 1, 5); parti.Add($"zoom {z:0.0}"); }
            if (c.Torcia is { } t) { torcia = t; parti.Add($"torcia {t}"); }
            if (c.Esposizione is { } e) { esposizione = e; parti.Add($"esposizione {e:0.0}"); }
            if (c.Specchia is { } s) { specchia = s; parti.Add($"specchia {s}"); }
            if (c.Filtro is { } f) { filtro = f; parti.Add($"filtro {f}"); }
            if (c.Sfondo is { } sf) { sfondo = sf; parti.Add($"sfondo {sf}"); }
            if (c.Qualita is { } q) { qualita = LivelliQualita.Normalizza(q); parti.Add($"qualità {qualita}"); }
            if (c.EffettiSulComputer is { } esc) parti.Add($"effetti sul computer {esc}");
            if (c.Scritta is { } sc) parti.Add($"scritta «{sc.Nome}»");
            if (c.Bianco is { } b) parti.Add($"bianco {b}");
            if (c.Iso is { } iso) parti.Add($"iso {iso}");
            if (c.Tempo is { } tempo) parti.Add($"tempo 1/{tempo}");
            if (c.Pelle is { } p) parti.Add($"pelle {p:0.00}");
            if (c.Calore is { } cal) parti.Add($"calore {cal:0.00}");
            if (c.Audio is { } a) parti.Add($"audio {a}");
            if (parti.Count == 0) parti.Add("(altro)");
            ultimoComando = string.Join(", ", parti);
        }
        scrivi($"Comando ricevuto: {ultimoComando}");
    }

    private async Task LeggiAsync(LettorePacchetti lettore, CancellationToken annulla)
    {
        var buffer = new byte[64 * 1024];
        try
        {
            while (!annulla.IsCancellationRequested)
            {
                while (lettore.Prossimo() is { } pacchetto)
                {
                    var chiaro = sicura!.Canale.Decifra(pacchetto);
                    if (chiaro.Tipo != TipoPacchetto.Controllo) continue; // immagini (tipo 4): non le chiediamo
                    var messaggio = CodificaMessaggi.DaPacchetto(chiaro);
                    await GestisciAsync(messaggio, annulla);
                }
                var letti = await flusso!.ReadAsync(buffer, annulla);
                if (letti == 0) break;
                lettore.Aggiungi(buffer.AsSpan(0, letti));
            }
        }
        catch (Exception errore) when (errore is not OperationCanceledException)
        {
            if (!muto) scrivi($"Lettura finita: {errore.GetType().Name} {errore.Message}");
        }
        catch (OperationCanceledException) { }
        ricevuti.Writer.TryComplete();
    }

    private async Task GestisciAsync(Messaggio messaggio, CancellationToken annulla)
    {
        switch (messaggio)
        {
            case Ping ping:
                if (!muto) await InviaAsync(new Pong(ping.T, Orologio.Adesso()), annulla);
                return;
            case Latenza latenza:
                lock (blocco) ultimaLatenza = latenza.Ms;
                return;
            case FormatoVideo richiesto:
                scrivi($"Il computer chiede {richiesto.Larghezza}×{richiesto.Altezza} a {richiesto.Fps} fps ({richiesto.Codec})");
                if (!opzioni.FormatoFisso)
                {
                    // Come il telefono vero: se non ce la fa scende, prima gli fps e poi la risoluzione, e lo dice.
                    var l = richiesto.Larghezza;
                    var a = richiesto.Altezza;
                    if (l * a > opzioni.Larghezza * opzioni.Altezza) (l, a) = (opzioni.Larghezza, opzioni.Altezza);
                    lock (blocco) formato = (l, a, Math.Min(richiesto.Fps, opzioni.Fps));
                }
                return;
            case Comando comando:
                Applica(comando);
                if (comando.Audio is { } audio) CambiaAudio(audio, annulla);
                if (!muto) await InviaAsync(Stato(), annulla);
                return;
            case PausaAutomatica pausa:
                scrivi($"Pausa automatica dal computer: {(pausa.Attiva ? "attiva" : "spenta")}");
                if (opzioni.RispettaPausa)
                {
                    inPausa = pausa.Attiva && inOnda != true;
                    if (!muto) await InviaAsync(Stato(), annulla);
                }
                return;
            case InOnda onda:
                scrivi($"In onda: {onda.Attivo}" + (onda.App is { } app ? $" ({app})" : ""));
                lock (blocco) inOnda = onda.Attivo;
                if (onda.Attivo && inPausa)
                {
                    inPausa = false;
                    if (!muto) await InviaAsync(Stato(), annulla);
                }
                return;
            case Anteprima anteprima:
                scrivi($"Anteprima sul computer: {(anteprima.Visibile ? "visibile" : "nascosta")}");
                return;
            case ChiediChiave:
                return; // ogni fotogramma è già una chiave
            case Arrivederci:
                chiusoDalComputer = true;
                ricevuti.Writer.TryWrite(messaggio);
                scrivi("Arrivederci dal computer");
                return;
            case Benvenuto or Approvazione:
                ricevuti.Writer.TryWrite(messaggio);
                return;
            case Gobbo gobbo:
                scrivi($"Gobbo: {(gobbo.Attivo is { } attivo ? (attivo ? "acceso" : "spento") : "aggiornato")}");
                return;
            case EffettiComputer effetti:
                scrivi($"Effetti sul computer: specchia {effetti.Specchia}, sfondo {effetti.Sfondo}, luce {effetti.LuceVolto}");
                return;
            default:
                scrivi($"Messaggio: {messaggio.GetType().Name}");
                return;
        }
    }

    private Task InviaAsync(Messaggio messaggio, CancellationToken annulla) =>
        ScriviAsync(CodificaMessaggi.ComePacchetto(messaggio), annulla);

    private async Task ScriviAsync(Pacchetto pacchetto, CancellationToken annulla)
    {
        await scrittura.WaitAsync(annulla);
        try
        {
            // Il contatore va avanti nell'ordine di scrittura: si cifra qui dentro.
            var daScrivere = sicura is null ? pacchetto : sicura.Canale.Cifra(pacchetto);
            await flusso!.WriteAsync(daScrivere.Codificato(), annulla);
        }
        finally { scrittura.Release(); }
    }

    private async Task<Pacchetto> LeggiUnoAsync(LettorePacchetti lettore, CancellationToken annulla)
    {
        var buffer = new byte[64 * 1024];
        while (true)
        {
            if (lettore.Prossimo() is { } pronto) return pronto;
            var letti = await flusso!.ReadAsync(buffer, annulla);
            if (letti == 0) throw new IOException("Il computer ha chiuso durante la stretta di mano");
            lettore.Aggiungi(buffer.AsSpan(0, letti));
        }
    }
}

/// <summary>I frame AAC grezzi di un file ADTS (l'intestazione di 7 o 9 byte si toglie).</summary>
public static class FrameAudio
{
    public static List<byte[]> Leggi(string percorso)
    {
        var dati = File.ReadAllBytes(percorso);
        var frame = new List<byte[]>();
        var i = 0;
        while (i + 7 <= dati.Length && dati[i] == 0xFF && (dati[i + 1] & 0xF0) == 0xF0)
        {
            var lunghezza = ((dati[i + 3] & 3) << 11) | (dati[i + 4] << 3) | (dati[i + 5] >> 5);
            var intestazione = (dati[i + 1] & 1) == 1 ? 7 : 9;
            if (lunghezza <= intestazione || i + lunghezza > dati.Length) break;
            frame.Add(dati[(i + intestazione)..(i + lunghezza)]);
            i += lunghezza;
        }
        if (frame.Count == 0) throw new FileNotFoundException($"Nessun frame AAC in {percorso}");
        return frame;
    }
}
