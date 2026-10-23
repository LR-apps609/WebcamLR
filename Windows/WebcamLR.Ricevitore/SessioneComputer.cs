using System.Net.Sockets;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>Numeri mostrati sotto l'anteprima, aggiornati ogni secondo.</summary>
public sealed record Statistiche(int Larghezza, int Altezza, int Fps, double MegabitAlSecondo, int? LatenzaMs);

/// <summary>
/// La connessione con un telefono, lato computer: la stessa logica di Mac/Sorgenti/SessioneComputer.swift.
/// Gli eventi arrivano su thread di sistema: l'interfaccia li riporta sul proprio thread.
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

    private readonly Socket presa;
    private readonly NetworkStream flusso;
    private readonly string nomeComputer;
    private readonly TimeSpan intervallo;
    private readonly CancellationTokenSource annulla = new();
    private readonly SemaphoreSlim scrittura = new(1, 1);
    private readonly MisuraLatenza latenza = new();
    private readonly object blocco = new();

    private FormatoVideo? formato;
    private int fotogrammiUltimoSecondo;
    private long byteUltimoSecondo;
    private ulong ultimoPacchetto = Orologio.Adesso();
    private bool inSilenzio;
    private int chiusa;
    private Task? lavoro;

    /// <param name="intervallo">Ogni quanto mandare ping e statistiche: 1 secondo, più breve solo nei test.</param>
    public SessioneComputer(Socket presa, string nomeComputer, TimeSpan? intervallo = null)
    {
        this.presa = presa;
        presa.NoDelay = true;
        flusso = new NetworkStream(presa, ownsSocket: true);
        this.nomeComputer = nomeComputer;
        this.intervallo = intervallo ?? TimeSpan.FromSeconds(1);
    }

    public void Avvia() => lavoro = Task.WhenAll(LeggiAsync(annulla.Token), OgniSecondoAsync(annulla.Token));

    /// <summary>Chiusura voluta: manda «arrivederci», così il telefono non si ricollega da solo.</summary>
    public async Task ChiudiAsync()
    {
        try { await InviaAsync(new Arrivederci()); } catch { }
        Termina();
    }

    /// <summary>Comandi della fotocamera verso il telefono (round 4): solo i campi presenti.</summary>
    public Task ComandaAsync(Comando comando) => InviaAsync(comando);

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
        catch (Exception) when (annullato.IsCancellationRequested) { }
        catch (IOException) { }
        catch (ErroreProtocollo) { }
        catch (ObjectDisposedException) { }
        Termina();
    }

    private async Task GestisciAsync(Pacchetto pacchetto)
    {
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
                await GestisciAsync(CodificaMessaggi.DaPacchetto(pacchetto), adesso);
                break;
            case TipoPacchetto.Video:
                var fotogramma = FotogrammaVideo.DaPacchetto(pacchetto);
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
            case Ciao ciao:
                await InviaAsync(new Benvenuto(Servizio.VersioneProtocollo, nomeComputer, Piattaforma.Windows));
                Salutato?.Invoke(ciao);
                break;
            case Pong pong:
                lock (blocco) latenza.AggiungiPong(pong.T, pong.Telefono, adesso);
                break;
            case FormatoVideo nuovo:
                lock (blocco) formato = nuovo;
                FormatoRicevuto?.Invoke(nuovo);
                break;
            case StatoTelefono stato:
                StatoRicevuto?.Invoke(stato);
                break;
            case Capacita capacita:
                CapacitaRicevute?.Invoke(capacita);
                break;
            case Arrivederci:
                Termina();
                break;
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
                        byteUltimoSecondo * 8 / 1_000_000.0 / secondi, ultima);
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

    private async Task InviaAsync(Messaggio messaggio)
    {
        var dati = CodificaMessaggi.ComePacchetto(messaggio).Codificato();
        await scrittura.WaitAsync();
        try { await flusso.WriteAsync(dati); }
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
