using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Channels;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Un server di adb finto su loopback, come quello vero su 127.0.0.1:5037. Volutamente indipendente dal codice provato:
/// legge le richieste byte per byte e scrive le risposte a mano («OKAY», «FAIL» con il messaggio, gli elenchi).
/// Capisce solo quello che usa WebcamLR: host:track-devices, host:transport:seriale e poi tcp:porta.
/// </summary>
public sealed class AdbFinto : IAsyncDisposable
{
    private readonly TcpListener ascolto;
    private readonly CancellationTokenSource fine = new();
    private readonly List<Socket> prese = new();
    private readonly SemaphoreSlim scritturaElenco = new(1, 1);
    private readonly List<NetworkStream> elenchi = new();
    private string elenco = "";
    private int tentativi;

    /// <summary>Esito di «tcp:porta»: numero del tentativo (da 1) → vero = l'app sul telefono ascolta.</summary>
    public Func<int, bool> AppInAscolto { get; set; } = _ => true;

    /// <summary>Con un telefono finto: dopo «tcp:52741» riuscito la connessione si unisce alla prima su <see cref="PortaTelefono"/>.</summary>
    public TcpListener? LatoTelefono { get; }

    public int Porta => ((IPEndPoint)ascolto.LocalEndpoint).Port;
    public int PortaTelefono => ((IPEndPoint)LatoTelefono!.LocalEndpoint).Port;

    /// <summary>Tutte le richieste ricevute, nell'ordine, così come sono arrivate (con le 4 cifre della lunghezza).</summary>
    public Channel<string> Richieste { get; } = Channel.CreateUnbounded<string>();
    /// <summary>I canali aperti quando non c'è un telefono finto: il lato del telefono.</summary>
    public Channel<NetworkStream> CanaliAperti { get; } = Channel.CreateUnbounded<NetworkStream>();
    public TaskCompletionSource InAscolto { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public AdbFinto(int porta = 0, bool conTelefono = false)
    {
        ascolto = new TcpListener(IPAddress.Loopback, porta);
        ascolto.Start();
        if (conTelefono)
        {
            LatoTelefono = new TcpListener(IPAddress.Loopback, 0);
            LatoTelefono.Start();
        }
        _ = AccettaAsync();
    }

    /// <summary>Quante volte è stato chiesto «tcp:…» (i tentativi di aprire il canale).</summary>
    public int Tentativi => Volatile.Read(ref tentativi);

    /// <summary>L'elenco nuovo («seriale\tstato\n» per riga), mandato a chi segue «host:track-devices».</summary>
    public async Task ImpostaElencoAsync(string nuovo)
    {
        List<NetworkStream> destinatari;
        lock (elenchi)
        {
            elenco = nuovo;
            destinatari = elenchi.ToList();
        }
        foreach (var flusso in destinatari) await ScriviAsync(flusso, Blocco(nuovo));
    }

    /// <summary>Il server si ferma: chiude le connessioni di «host:track-devices».</summary>
    public void ChiudiElenchi()
    {
        lock (elenchi)
        {
            foreach (var flusso in elenchi) flusso.Dispose();
            elenchi.Clear();
        }
    }

    private async Task AccettaAsync()
    {
        try
        {
            while (!fine.IsCancellationRequested)
            {
                var presa = await ascolto.AcceptSocketAsync(fine.Token);
                lock (prese) prese.Add(presa);
                _ = ServiAsync(presa);
            }
        }
        catch (Exception) { }
    }

    private async Task ServiAsync(Socket presa)
    {
        var flusso = new NetworkStream(presa, ownsSocket: true);
        try
        {
            var richiesta = await LeggiRichiestaAsync(flusso);
            if (richiesta is null) return;
            if (richiesta == "host:track-devices")
            {
                await ScriviAsync(flusso, Encoding.ASCII.GetBytes("OKAY"));
                string attuale;
                lock (elenchi)
                {
                    attuale = elenco;
                    elenchi.Add(flusso);
                }
                await ScriviAsync(flusso, Blocco(attuale));
                InAscolto.TrySetResult();
                // Resta aperta per gli elenchi nuovi; finisce quando il client chiude.
                await flusso.ReadAsync(new byte[1], fine.Token);
                return;
            }
            if (!richiesta.StartsWith("host:transport:", StringComparison.Ordinal))
            {
                await ScriviAsync(flusso, Fallito("unknown host service"));
                return;
            }
            var seriale = richiesta["host:transport:".Length..];
            bool pronto;
            lock (elenchi) pronto = elenco.Split('\n').Any(r => r == seriale + "\tdevice");
            if (!pronto)
            {
                await ScriviAsync(flusso, Fallito($"device '{seriale}' not found"));
                return;
            }
            await ScriviAsync(flusso, Encoding.ASCII.GetBytes("OKAY"));
            var porta = await LeggiRichiestaAsync(flusso);
            if (porta is null || !porta.StartsWith("tcp:", StringComparison.Ordinal)) return;
            if (!AppInAscolto(Interlocked.Increment(ref tentativi)))
            {
                // Come adbd quando nessuno ascolta sulla porta del telefono: il server dice «closed».
                await ScriviAsync(flusso, Fallito("closed"));
                return;
            }
            await ScriviAsync(flusso, Encoding.ASCII.GetBytes("OKAY"));
            if (LatoTelefono is null)
            {
                CanaliAperti.Writer.TryWrite(flusso);
                flusso = null!;
                return;
            }
            var telefono = await LatoTelefono.AcceptSocketAsync(fine.Token);
            lock (prese) prese.Add(telefono);
            using var flussoTelefono = new NetworkStream(telefono, ownsSocket: true);
            await Task.WhenAny(Travasa(flusso, flussoTelefono), Travasa(flussoTelefono, flusso));
        }
        catch (Exception) { }
        finally { flusso?.Dispose(); }
    }

    private async Task Travasa(Stream da, Stream a)
    {
        try { await da.CopyToAsync(a, fine.Token); }
        catch (Exception) { }
    }

    private static byte[] Blocco(string testo)
    {
        var corpo = Encoding.UTF8.GetBytes(testo);
        return Encoding.ASCII.GetBytes(corpo.Length.ToString("X4")).Concat(corpo).ToArray();
    }

    private static byte[] Fallito(string messaggio) => Encoding.ASCII.GetBytes("FAIL").Concat(Blocco(messaggio)).ToArray();

    private async Task ScriviAsync(Stream flusso, byte[] dati)
    {
        await scritturaElenco.WaitAsync();
        try { await flusso.WriteAsync(dati); }
        catch (Exception) { }
        finally { scritturaElenco.Release(); }
    }

    private async Task<string?> LeggiRichiestaAsync(Stream flusso)
    {
        var intestazione = new byte[4];
        if (!await LeggiTuttoAsync(flusso, intestazione)) return null;
        var lunghezza = Convert.ToInt32(Encoding.ASCII.GetString(intestazione), 16);
        var corpo = new byte[lunghezza];
        if (!await LeggiTuttoAsync(flusso, corpo)) return null;
        var testo = Encoding.ASCII.GetString(corpo);
        Richieste.Writer.TryWrite(Encoding.ASCII.GetString(intestazione) + testo);
        return testo;
    }

    private async Task<bool> LeggiTuttoAsync(Stream flusso, byte[] buffer)
    {
        var letti = 0;
        while (letti < buffer.Length)
        {
            var n = await flusso.ReadAsync(buffer.AsMemory(letti), fine.Token);
            if (n == 0) return false;
            letti += n;
        }
        return true;
    }

    public async ValueTask DisposeAsync()
    {
        fine.Cancel();
        ascolto.Stop();
        LatoTelefono?.Stop();
        ChiudiElenchi();
        lock (prese)
        {
            foreach (var presa in prese)
            {
                try { presa.Dispose(); } catch { }
            }
        }
        await Task.CompletedTask;
    }
}
