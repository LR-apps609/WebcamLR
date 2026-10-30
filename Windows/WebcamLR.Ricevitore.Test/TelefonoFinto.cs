using System.Net;
using System.Net.Sockets;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Un iPhone finto che parla il protocollo 2 come Collegamento.swift: stretta di mano, prova, poi tutto cifrato.
/// Risponde da solo ai ping; gli altri messaggi arrivano in <see cref="Ricevuti"/>.
/// </summary>
public sealed class TelefonoFinto : IAsyncDisposable
{
    private readonly TcpClient cliente = new();
    private readonly SemaphoreSlim scrittura = new(1, 1);
    private readonly CancellationTokenSource fine = new(TimeSpan.FromSeconds(20));
    private readonly Func<ulong> orologio;
    private NetworkStream flusso = null!;
    private Task? lettura;
    private SessioneSicura? sicura;

    public TelefonoFinto(IdentitaDispositivo? identita = null, Func<ulong>? orologio = null)
    {
        Identita = identita ?? IdentitaDispositivo.Nuova();
        this.orologio = orologio ?? Orologio.Adesso;
    }

    public IdentitaDispositivo Identita { get; }

    /// <summary>Vero: non risponde più ai ping (un telefono in sottofondo, sospeso dal sistema).</summary>
    public bool Muto
    {
        get => Volatile.Read(ref muto);
        set => Volatile.Write(ref muto, value);
    }
    private bool muto;
    public string? CodiceVisto => sicura?.Codice;
    public string? ImprontaComputer => sicura?.ImprontaAltro;
    public System.Threading.Channels.Channel<Messaggio> Ricevuti { get; } = System.Threading.Channels.Channel.CreateUnbounded<Messaggio>();
    public TaskCompletionSource Chiuso { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// <summary>Collega, stretta di mano, prova (con il gettone se c'è) e «ciao».</summary>
    public async Task CollegaAsync(int porta, string nome = "iPhone finto", string? gettone = null)
    {
        await cliente.ConnectAsync(IPAddress.Loopback, porta);
        flusso = cliente.GetStream();
        using var stretta = new StrettaTelefono(Identita);
        await ScriviAsync(CodificaMessaggi.ComePacchetto(stretta.Apertura));

        var lettore = new LettorePacchetti();
        var risposta = await LeggiUnoAsync(lettore);
        var (sessione, prova) = stretta.Completa((Stretta)CodificaMessaggi.DaPacchetto(risposta), gettone);
        sicura = sessione;
        lettura = LeggiAsync(lettore);
        await InviaAsync(prova);
        await InviaAsync(new Ciao(Servizio.VersioneProtocollo, nome, Piattaforma.Iphone, "0.10"));
    }

    /// <summary>Un telefono del round 1: manda «ciao» in chiaro, senza stretta di mano.</summary>
    public async Task CollegaSenzaSicurezzaAsync(int porta)
    {
        await cliente.ConnectAsync(IPAddress.Loopback, porta);
        flusso = cliente.GetStream();
        await ScriviAsync(CodificaMessaggi.ComePacchetto(new Ciao(1, "iPhone vecchio", Piattaforma.Iphone, "0.1")));
        lettura = LeggiAsync(new LettorePacchetti(), inChiaro: true);
    }

    public Task InviaAsync(Messaggio messaggio) => InviaAsync(CodificaMessaggi.ComePacchetto(messaggio));

    public Task InviaAsync(Pacchetto pacchetto) => ScriviAsync(pacchetto);

    /// <summary>Il prossimo messaggio del tipo voluto; gli altri si saltano.</summary>
    public async Task<T> AttendiAsync<T>() where T : Messaggio
    {
        while (true)
        {
            var messaggio = await Ricevuti.Reader.ReadAsync(fine.Token);
            if (messaggio is T voluto) return voluto;
        }
    }

    private async Task ScriviAsync(Pacchetto pacchetto)
    {
        await scrittura.WaitAsync();
        try
        {
            // Il contatore va avanti nell'ordine di scrittura: si cifra qui dentro.
            var daScrivere = sicura is null ? pacchetto : sicura.Canale.Cifra(pacchetto);
            await flusso.WriteAsync(daScrivere.Codificato(), fine.Token);
        }
        finally { scrittura.Release(); }
    }

    private async Task<Pacchetto> LeggiUnoAsync(LettorePacchetti lettore)
    {
        var buffer = new byte[64 * 1024];
        while (true)
        {
            if (lettore.Prossimo() is { } pronto) return pronto;
            var letti = await flusso.ReadAsync(buffer, fine.Token);
            if (letti == 0) throw new IOException("Chiusa durante la stretta di mano");
            lettore.Aggiungi(buffer.AsSpan(0, letti));
        }
    }

    private async Task LeggiAsync(LettorePacchetti lettore, bool inChiaro = false)
    {
        var buffer = new byte[64 * 1024];
        try
        {
            while (!fine.IsCancellationRequested)
            {
                while (lettore.Prossimo() is { } pacchetto)
                {
                    var chiaro = inChiaro ? pacchetto : sicura!.Canale.Decifra(pacchetto);
                    var messaggio = CodificaMessaggi.DaPacchetto(chiaro);
                    if (messaggio is Ping ping) { if (!Muto) await InviaAsync(new Pong(ping.T, orologio())); }
                    else Ricevuti.Writer.TryWrite(messaggio);
                }
                var letti = await flusso.ReadAsync(buffer, fine.Token);
                if (letti == 0) break;
                lettore.Aggiungi(buffer.AsSpan(0, letti));
            }
        }
        catch (Exception) { }
        Chiuso.TrySetResult();
    }

    public async ValueTask DisposeAsync()
    {
        fine.Cancel();
        cliente.Dispose();
        if (lettura is not null) await lettura;
    }
}
