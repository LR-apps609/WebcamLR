using System.Net;
using System.Net.Sockets;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Resta in ascolto dei telefoni sulla porta 52740 (o un'altra se occupata).
/// L'annuncio in rete (mDNS, `_webcamlr._tcp`) lo fa l'app Windows con le API di sistema.
/// </summary>
public sealed class Ascoltatore : IDisposable
{
    public event Action<Socket>? NuovoTelefono;

    private readonly TcpListener ascolto;
    private readonly CancellationTokenSource annulla = new();

    public int Porta => ((IPEndPoint)ascolto.LocalEndpoint).Port;

    public Ascoltatore(IPAddress? indirizzo = null, int porta = Servizio.PortaPredefinita)
    {
        indirizzo ??= IPAddress.Any;
        try
        {
            ascolto = new TcpListener(indirizzo, porta);
            ascolto.Start();
        }
        catch (SocketException errore) when (errore.SocketErrorCode == SocketError.AddressAlreadyInUse)
        {
            ascolto = new TcpListener(indirizzo, 0);
            ascolto.Start();
        }
        _ = AccettaAsync(annulla.Token);
    }

    private async Task AccettaAsync(CancellationToken annullato)
    {
        try
        {
            while (!annullato.IsCancellationRequested)
            {
                var presa = await ascolto.AcceptSocketAsync(annullato);
                NuovoTelefono?.Invoke(presa);
            }
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
    }

    public void Dispose()
    {
        annulla.Cancel();
        ascolto.Stop();
    }
}
