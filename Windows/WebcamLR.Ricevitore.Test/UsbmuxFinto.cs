using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Channels;
using System.Xml;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Un usbmuxd finto su loopback, come il servizio di Apple su 127.0.0.1:27015. Volutamente indipendente
/// dal codice provato: legge le intestazioni byte per byte e i plist con XmlDocument, scrive le risposte a mano.
/// </summary>
public sealed class UsbmuxFinto : IAsyncDisposable
{
    /// <summary>Una richiesta ricevuta: intestazione grezza e campi del plist.</summary>
    public sealed record Richiesta(uint Lunghezza, uint Versione, uint Tipo, uint Etichetta, string Xml, Dictionary<string, string> Campi);

    private readonly TcpListener ascolto;
    private readonly CancellationTokenSource fine = new();
    private readonly List<Socket> prese = new();
    private readonly SemaphoreSlim scritturaAscolto = new(1, 1);
    private NetworkStream? flussoAscolto;
    private int tentativi;

    /// <summary>Esito del Connect: numero del tentativo (da 1) → Number del Result (0 = riuscito).</summary>
    public Func<int, int> EsitoConnect { get; set; } = _ => 0;

    /// <summary>
    /// Con un telefono finto: dopo un Connect riuscito la connessione si unisce alla prima connessione
    /// arrivata su <see cref="PortaTelefono"/>, come fa il cavo con la porta 52741 dell'iPhone.
    /// </summary>
    public TcpListener? LatoTelefono { get; private set; }

    public int Porta => ((IPEndPoint)ascolto.LocalEndpoint).Port;
    public int PortaTelefono => ((IPEndPoint)LatoTelefono!.LocalEndpoint).Port;

    public Channel<Richiesta> Richieste { get; } = Channel.CreateUnbounded<Richiesta>();
    public Channel<Richiesta> Connect { get; } = Channel.CreateUnbounded<Richiesta>();
    /// <summary>Le connessioni dopo un Connect riuscito, quando non c'è un telefono finto: il lato dell'iPhone.</summary>
    public Channel<NetworkStream> CanaliAperti { get; } = Channel.CreateUnbounded<NetworkStream>();
    public TaskCompletionSource InAscolto { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public UsbmuxFinto(int porta = 0, bool conTelefono = false)
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

    public int Tentativi => Volatile.Read(ref tentativi);

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
            var richiesta = await LeggiAsync(flusso);
            if (richiesta is null) return;
            Richieste.Writer.TryWrite(richiesta);
            switch (richiesta.Campi["MessageType"])
            {
                case "Listen":
                    flussoAscolto = flusso;
                    await InviaAsync(flusso, richiesta.Etichetta, Risultato(0));
                    InAscolto.TrySetResult();
                    // La connessione resta aperta per gli avvisi Attached e Detached.
                    await LeggiAsync(flusso);
                    break;
                case "Connect":
                    var numero = EsitoConnect(Interlocked.Increment(ref tentativi));
                    Connect.Writer.TryWrite(richiesta);
                    await InviaAsync(flusso, richiesta.Etichetta, Risultato(numero));
                    if (numero != 0)
                    {
                        flusso.Dispose();
                        return;
                    }
                    if (LatoTelefono is null)
                    {
                        CanaliAperti.Writer.TryWrite(flusso);
                        return;
                    }
                    var telefono = await LatoTelefono.AcceptSocketAsync(fine.Token);
                    lock (prese) prese.Add(telefono);
                    var flussoTelefono = new NetworkStream(telefono, ownsSocket: true);
                    // Il cavo: i byte passano nei due sensi finché uno dei due chiude.
                    await Task.WhenAny(Travasa(flusso, flussoTelefono), Travasa(flussoTelefono, flusso));
                    flusso.Dispose();
                    flussoTelefono.Dispose();
                    break;
            }
        }
        catch (Exception) { }
    }

    private async Task Travasa(Stream da, Stream a)
    {
        try { await da.CopyToAsync(a, fine.Token); }
        catch (Exception) { }
    }

    /// <summary>Un iPhone collegato: avviso Attached sulla connessione del Listen.</summary>
    public Task AttaccaAsync(int dispositivo, string tipo = "USB") => InviaAsync(flussoAscolto!, 0,
        $"<dict><key>DeviceID</key><integer>{dispositivo}</integer><key>MessageType</key><string>Attached</string>" +
        $"<key>Properties</key><dict><key>ConnectionSpeed</key><integer>480000000</integer><key>ConnectionType</key><string>{tipo}</string>" +
        $"<key>DeviceID</key><integer>{dispositivo}</integer><key>LocationID</key><integer>0</integer><key>ProductID</key><integer>4776</integer>" +
        $"<key>SerialNumber</key><string>00008110-000A1B2C3D4E5F6A</string><key>UDID</key><string>00008110-000A1B2C3D4E5F6A</string>" +
        "<key>Abilitato</key><true/></dict></dict>");

    public Task StaccaAsync(int dispositivo) => InviaAsync(flussoAscolto!, 0,
        $"<dict><key>DeviceID</key><integer>{dispositivo}</integer><key>MessageType</key><string>Detached</string></dict>");

    /// <summary>Il servizio si ferma: chiude la connessione del Listen.</summary>
    public void ChiudiAscolto() => flussoAscolto?.Dispose();

    private static string Risultato(int numero) =>
        $"<dict><key>MessageType</key><string>Result</string><key>Number</key><integer>{numero}</integer></dict>";

    private async Task InviaAsync(Stream flusso, uint etichetta, string dizionario)
    {
        var xml = Encoding.UTF8.GetBytes("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n" +
            $"<plist version=\"1.0\">\n{dizionario}\n</plist>\n");
        var messaggio = new byte[16 + xml.Length];
        BinaryPrimitives.WriteUInt32LittleEndian(messaggio.AsSpan(0), (uint)messaggio.Length);
        BinaryPrimitives.WriteUInt32LittleEndian(messaggio.AsSpan(4), 1);
        BinaryPrimitives.WriteUInt32LittleEndian(messaggio.AsSpan(8), 8);
        BinaryPrimitives.WriteUInt32LittleEndian(messaggio.AsSpan(12), etichetta);
        xml.CopyTo(messaggio, 16);
        await scritturaAscolto.WaitAsync();
        try { await flusso.WriteAsync(messaggio); }
        finally { scritturaAscolto.Release(); }
    }

    private static async Task<Richiesta?> LeggiAsync(Stream flusso)
    {
        var intestazione = new byte[16];
        if (!await LeggiTuttoAsync(flusso, intestazione)) return null;
        var lunghezza = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(0));
        var corpo = new byte[lunghezza - 16];
        if (!await LeggiTuttoAsync(flusso, corpo)) return null;
        var xml = Encoding.UTF8.GetString(corpo);
        var documento = new XmlDocument { XmlResolver = null };
        using (var lettore = XmlReader.Create(new StringReader(xml), new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore }))
            documento.Load(lettore);
        var campi = new Dictionary<string, string>();
        var dict = documento.SelectSingleNode("/plist/dict")!;
        string? chiave = null;
        foreach (XmlNode nodo in dict.ChildNodes)
        {
            if (nodo is not XmlElement elemento) continue;
            if (elemento.Name == "key") chiave = elemento.InnerText;
            else if (chiave is not null) campi[chiave] = elemento.Name == "integer" ? "i:" + elemento.InnerText : elemento.InnerText;
        }
        return new Richiesta(lunghezza, BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(4)),
            BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(8)), BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(12)), xml, campi);
    }

    private static async Task<bool> LeggiTuttoAsync(Stream flusso, byte[] buffer)
    {
        var letti = 0;
        while (letti < buffer.Length)
        {
            var n = await flusso.ReadAsync(buffer.AsMemory(letti));
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
