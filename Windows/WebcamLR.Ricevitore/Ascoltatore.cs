using System.Net;
using System.Net.Sockets;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Resta in ascolto dei telefoni sulla porta 52740 (o un'altra se occupata).
/// L'annuncio in rete (mDNS, `_webcamlr._tcp`) lo fa l'app Windows con le API di sistema.
/// Se l'ascolto cade (scheda di rete reimpostata, risveglio dallo stop), si riapre da solo sulla stessa
/// porta (1.12); se nel frattempo la porta è stata presa da un altro programma, su un'altra, e
/// <see cref="Riaperto"/> lo dice, così annuncio e QR code si rifanno.
/// </summary>
public sealed class Ascoltatore : IDisposable
{
    /// <summary>Un telefono si è collegato; arriva sul thread di rete, subito dopo l'accettazione.</summary>
    public event Action<Socket>? NuovoTelefono;
    /// <summary>L'ascolto è caduto e si è riaperto (la porta può essere cambiata); arriva sul thread di rete.</summary>
    public event Action<int>? Riaperto;

    /// <summary>Attese tra un tentativo e l'altro di riaprire: la prima breve, poi fino a 5 secondi.</summary>
    private static readonly TimeSpan PrimaAttesa = TimeSpan.FromMilliseconds(200);
    private static readonly TimeSpan AttesaMassima = TimeSpan.FromSeconds(5);

    private readonly IPAddress indirizzo;
    private readonly object blocco = new();
    private readonly CancellationTokenSource annulla = new();
    private TcpListener ascolto;
    private int porta;
    private bool attivo;
    /// <summary>Completato da <see cref="Controlla"/>: interrompe l'attesa tra due tentativi di riaprire.</summary>
    private TaskCompletionSource sveglia = NuovaSveglia();

    public int Porta => Volatile.Read(ref porta);

    /// <summary>Falso mentre l'ascolto è caduto e si sta riaprendo.</summary>
    public bool Attivo
    {
        get { lock (blocco) return attivo; }
    }

    public Ascoltatore(IPAddress? indirizzo = null, int porta = Servizio.PortaPredefinita)
    {
        this.indirizzo = indirizzo ?? IPAddress.Any;
        ascolto = Apri(this.indirizzo, porta);
        this.porta = ((IPEndPoint)ascolto.LocalEndpoint).Port;
        attivo = true;
        _ = AscoltaAsync(annulla.Token);
    }

    /// <summary>La porta voluta, oppure una qualsiasi se è occupata.</summary>
    private static TcpListener Apri(IPAddress indirizzo, int porta)
    {
        var nuovo = new TcpListener(indirizzo, porta);
        try
        {
            nuovo.Start();
            return nuovo;
        }
        catch (SocketException errore) when (errore.SocketErrorCode == SocketError.AddressAlreadyInUse && porta != 0)
        {
            nuovo = new TcpListener(indirizzo, 0);
            nuovo.Start();
            return nuovo;
        }
    }

    /// <summary>
    /// Dopo un cambio di rete o il risveglio: se l'ascolto è caduto si riprova subito, senza aspettare il prossimo tentativo.
    /// </summary>
    public void Controlla()
    {
        TaskCompletionSource vecchia;
        lock (blocco)
        {
            if (attivo) return;
            vecchia = sveglia;
            sveglia = NuovaSveglia();
        }
        vecchia.TrySetResult();
    }

    /// <summary>
    /// Chiude l'ascolto attuale come se fosse caduto: si riapre da solo sulla stessa porta.
    /// Per i test, e per ripartire puliti quando Windows non avvisa della caduta.
    /// </summary>
    public void Riapri()
    {
        TcpListener attuale;
        lock (blocco) attuale = ascolto;
        try { attuale.Stop(); } catch (Exception) { }
    }

    private async Task AscoltaAsync(CancellationToken annullato)
    {
        while (!annullato.IsCancellationRequested)
        {
            TcpListener attuale;
            lock (blocco) attuale = ascolto;
            await AccettaAsync(attuale, annullato);
            if (annullato.IsCancellationRequested) return;
            lock (blocco) attivo = false;
            try { attuale.Stop(); } catch (Exception) { }
            if (!await RiapriAsync(annullato)) return;
        }
    }

    /// <summary>Accetta finché l'ascolto funziona; torna quando è caduto o annullato.</summary>
    private async Task AccettaAsync(TcpListener attuale, CancellationToken annullato)
    {
        var erroriDiFila = 0;
        while (!annullato.IsCancellationRequested)
        {
            Socket presa;
            try
            {
                presa = await attuale.AcceptSocketAsync(annullato);
                erroriDiFila = 0;
            }
            catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (InvalidOperationException) { return; }   // ascolto fermato (Stop)
            // Un telefono che chiude prima di essere accettato (su Windows: «nome di rete non più disponibile»)
            // non deve fermare l'ascolto: senza, nessun telefono si collegherebbe più fino al riavvio dell'app.
            // Tanti errori di fila, invece, vogliono dire che l'ascolto è morto: si riapre.
            catch (SocketException errore) when (errore.SocketErrorCode is not (SocketError.OperationAborted or SocketError.Interrupted
                                                                                  or SocketError.NotSocket or SocketError.InvalidArgument))
            {
                if (++erroriDiFila >= 20) return;
                try { await Task.Delay(50, annullato); } catch (OperationCanceledException) { return; }
                continue;
            }
            catch (SocketException) { return; }
            try { NuovoTelefono?.Invoke(presa); }
            catch (Exception) { presa.Dispose(); }
        }
    }

    /// <summary>Riapre sulla stessa porta, riprovando con attese crescenti; falso se annullato.</summary>
    private async Task<bool> RiapriAsync(CancellationToken annullato)
    {
        var attesa = PrimaAttesa;
        while (!annullato.IsCancellationRequested)
        {
            Task svegliata;
            lock (blocco) svegliata = sveglia.Task;
            using (var fine = CancellationTokenSource.CreateLinkedTokenSource(annullato))
            {
                await Task.WhenAny(Task.Delay(attesa, fine.Token), svegliata);
                fine.Cancel();
            }
            if (annullato.IsCancellationRequested) return false;
            try
            {
                var nuovo = Apri(indirizzo, Porta);
                int nuovaPorta;
                lock (blocco)
                {
                    if (annullato.IsCancellationRequested)
                    {
                        nuovo.Stop();
                        return false;
                    }
                    ascolto = nuovo;
                    attivo = true;
                    nuovaPorta = ((IPEndPoint)nuovo.LocalEndpoint).Port;
                    Volatile.Write(ref porta, nuovaPorta);
                }
                Riaperto?.Invoke(nuovaPorta);
                return true;
            }
            catch (SocketException) { }
            attesa = attesa * 2 < AttesaMassima ? attesa * 2 : AttesaMassima;
        }
        return false;
    }

    private static TaskCompletionSource NuovaSveglia() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    public void Dispose()
    {
        annulla.Cancel();
        TcpListener attuale;
        lock (blocco)
        {
            attuale = ascolto;
            attivo = false;
        }
        attuale.Stop();
    }
}
