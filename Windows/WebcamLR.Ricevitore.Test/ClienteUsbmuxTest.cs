using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Il client usbmux (cavo USB, 1.7) contro un usbmuxd finto su loopback.</summary>
public class ClienteUsbmuxTest
{
    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan Riprova = TimeSpan.FromMilliseconds(150);

    private static ClienteUsbmux Cliente(int porta) =>
        new(new IPEndPoint(IPAddress.Loopback, porta), Riprova, attesaServizio: TimeSpan.FromMilliseconds(150));

    /// <summary>Raccoglie eventi e stati del client per i controlli.</summary>
    private sealed class Osservatore
    {
        public readonly Channel<Socket> Prese = Channel.CreateUnbounded<Socket>();
        public readonly Channel<StatoCavo> Stati = Channel.CreateUnbounded<StatoCavo>();

        public Osservatore(ClienteUsbmux cliente)
        {
            cliente.TelefonoViaCavo += presa => Prese.Writer.TryWrite(presa);
            cliente.StatoCambiato += stato => Stati.Writer.TryWrite(stato);
        }

        public async Task AttendiStatoAsync(StatoCavo voluto)
        {
            using var tempo = new CancellationTokenSource(Limite);
            while (await Stati.Reader.ReadAsync(tempo.Token) != voluto) { }
        }
    }

    private static int PortaLibera()
    {
        var prova = new TcpListener(IPAddress.Loopback, 0);
        prova.Start();
        var porta = ((IPEndPoint)prova.LocalEndpoint).Port;
        prova.Stop();
        return porta;
    }

    [Fact]
    public async Task ServizioAssenteSeLaPortaRifiuta()
    {
        await using var cliente = Cliente(PortaLibera());
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await osservatore.AttendiStatoAsync(StatoCavo.ServizioAssente);
        Assert.True(cliente.Verificato);
        Assert.Equal(StatoCavo.ServizioAssente, cliente.Stato);
        Assert.False(cliente.IPhoneAlCavo);
    }

    [Fact]
    public async Task ServizioInstallatoDopoVieneTrovato()
    {
        var porta = PortaLibera();
        await using var cliente = Cliente(porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await osservatore.AttendiStatoAsync(StatoCavo.ServizioAssente);

        // «Dispositivi Apple» installata mentre WebcamLR è aperta: si riprova da soli.
        await using var usbmux = new UsbmuxFinto(porta);
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
    }

    [Fact]
    public async Task ListenConIntestazioneEPlistGiusti()
    {
        await using var usbmux = new UsbmuxFinto();
        await using var cliente = Cliente(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();

        var listen = await usbmux.Richieste.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.Equal(1u, listen.Versione);
        Assert.Equal(8u, listen.Tipo);
        Assert.Equal((uint)(16 + System.Text.Encoding.UTF8.GetByteCount(listen.Xml)), listen.Lunghezza);
        Assert.Equal("Listen", listen.Campi["MessageType"]);
        Assert.Equal("WebcamLR", listen.Campi["ProgName"]);
        Assert.Equal("WebcamLR", listen.Campi["ClientVersionString"]);
        Assert.Contains("<!DOCTYPE plist", listen.Xml);
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
    }

    [Fact]
    public async Task AttachedPortaAlConnectVersoLaPorta52741InOrdineDiRete()
    {
        await using var usbmux = new UsbmuxFinto();
        await using var cliente = Cliente(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);

        await usbmux.AttaccaAsync(42);
        var connect = await usbmux.Connect.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.Equal("Connect", connect.Campi["MessageType"]);
        Assert.Equal("i:42", connect.Campi["DeviceID"]);
        // 52741 = 0xCE05 → in ordine di rete 0x05CE = 1486.
        Assert.Equal("i:1486", connect.Campi["PortNumber"]);
        Assert.Equal(1u, connect.Versione);
        Assert.Equal(8u, connect.Tipo);

        // Con Result 0 la connessione passa a chi la usa, e il cavo è «collegato».
        var presa = await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        await osservatore.AttendiStatoAsync(StatoCavo.Collegato);
        Assert.True(cliente.IPhoneAlCavo);

        // È proprio il canale: ciò che scrive l'«iPhone» arriva, senza byte del Result davanti.
        var latoTelefono = await usbmux.CanaliAperti.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        await latoTelefono.WriteAsync(new byte[] { 1, 2, 3 });
        var ricevuti = new byte[3];
        var letti = 0;
        while (letti < 3) letti += await presa.ReceiveAsync(ricevuti.AsMemory(letti), SocketFlags.None);
        Assert.Equal(new byte[] { 1, 2, 3 }, ricevuti);
        presa.Dispose();
    }

    [Fact]
    public async Task ConnessioneDiReteIgnorata()
    {
        await using var usbmux = new UsbmuxFinto();
        await using var cliente = Cliente(usbmux.Porta);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);

        // Un iPhone sincronizzato in Wi-Fi: non è il cavo.
        await usbmux.AttaccaAsync(3, tipo: "Network");
        await Task.Delay(Riprova * 4);
        Assert.Equal(0, usbmux.Tentativi);
        Assert.False(cliente.IPhoneAlCavo);
    }

    [Fact]
    public async Task RiprovaIlConnectFinchéLAppNonRisponde()
    {
        await using var usbmux = new UsbmuxFinto { EsitoConnect = tentativo => tentativo <= 2 ? 3 : 0 };
        await using var cliente = Cliente(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);

        var orologio = Stopwatch.StartNew();
        await usbmux.AttaccaAsync(1);
        var presa = await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        // Due rifiuti (WebcamLR chiusa sull'iPhone), poi riesce: tre Connect, uno ogni intervallo.
        Assert.Equal(3, usbmux.Tentativi);
        Assert.True(orologio.Elapsed >= Riprova * 2 * 0.9, $"Riprovato troppo presto: {orologio.Elapsed}");
        Assert.False(osservatore.Prese.Reader.TryRead(out _));
        presa.Dispose();
    }

    [Fact]
    public async Task RicollegaQuandoLaSessioneFinisce()
    {
        await using var usbmux = new UsbmuxFinto();
        await using var cliente = Cliente(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);

        var prima = await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        await osservatore.AttendiStatoAsync(StatoCavo.Collegato);
        // La sessione si chiude (per esempio l'app sull'iPhone è stata chiusa): si torna in ascolto e si riprova.
        prima.Dispose();
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
        var seconda = await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.NotSame(prima, seconda);
        Assert.Equal(2, usbmux.Tentativi);
        seconda.Dispose();
    }

    [Fact]
    public async Task SospesoNonRicollegaFinoAlProssimoCavo()
    {
        await using var usbmux = new UsbmuxFinto();
        await using var cliente = Cliente(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);

        var presa = await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        // «Scollega» sul PC: niente ricollegamento automatico.
        cliente.Sospendi(presa);
        presa.Dispose();
        await Task.Delay(Riprova * 5);
        Assert.Equal(1, usbmux.Tentativi);

        // Cavo staccato e ricollegato: si ricomincia.
        await usbmux.StaccaAsync(1);
        await usbmux.AttaccaAsync(2);
        (await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
        Assert.Equal(2, usbmux.Tentativi);
    }

    [Fact]
    public async Task DetachedFermaITentativi()
    {
        await using var usbmux = new UsbmuxFinto { EsitoConnect = _ => 3 };
        await using var cliente = Cliente(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);

        await usbmux.AttaccaAsync(9);
        await usbmux.Connect.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        await usbmux.Connect.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.True(cliente.IPhoneAlCavo);

        await usbmux.StaccaAsync(9);
        await Task.Delay(Riprova * 2);
        Assert.False(cliente.IPhoneAlCavo);
        var dopoDetached = usbmux.Tentativi;
        await Task.Delay(Riprova * 5);
        Assert.Equal(dopoDetached, usbmux.Tentativi);
        Assert.Equal(StatoCavo.InAscolto, cliente.Stato);
    }

    [Fact]
    public async Task ServizioCheSiFermaVieneRitrovato()
    {
        await using var usbmux = new UsbmuxFinto();
        await using var cliente = Cliente(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
        await usbmux.Richieste.Reader.ReadAsync().AsTask().WaitAsync(Limite);

        usbmux.ChiudiAscolto();
        await osservatore.AttendiStatoAsync(StatoCavo.ServizioAssente);
        // Il client riprova da solo e manda un nuovo Listen.
        Assert.Equal("Listen", (await usbmux.Richieste.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Campi["MessageType"]);
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
    }

    /// <summary>
    /// Dall'inizio alla fine sul «cavo»: usbmuxd finto che unisce la connessione al telefono finto cifrato,
    /// e la sessione del computer creata come per il Wi-Fi. Stretta di mano, QR code, benvenuto, video, arrivederci.
    /// </summary>
    [Fact]
    public async Task SessioneSicuraCompletaSulCavo()
    {
        await using var usbmux = new UsbmuxFinto(conTelefono: true);
        await using var cliente = Cliente(usbmux.Porta);
        using var idComputer = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer);
        var sessioneCreata = new TaskCompletionSource<SessioneComputer>(TaskCreationOptions.RunContinuationsAsynchronously);
        var salutato = new TaskCompletionSource<Ciao>(TaskCreationOptions.RunContinuationsAsynchronously);
        var formato = new TaskCompletionSource<FormatoVideo>(TaskCreationOptions.RunContinuationsAsynchronously);
        var fotogramma = new TaskCompletionSource<FotogrammaVideo>(TaskCreationOptions.RunContinuationsAsynchronously);
        var chiusa = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Socket? presaCavo = null;
        cliente.TelefonoViaCavo += presa =>
        {
            presaCavo = presa;
            // Esattamente come una connessione arrivata dal Wi-Fi.
            var sessione = new SessioneComputer(presa, "PC di prova", abbinamento, TimeSpan.FromMilliseconds(200));
            sessione.Salutato += ciao => salutato.TrySetResult(ciao);
            sessione.FormatoRicevuto += f => formato.TrySetResult(f);
            sessione.FotogrammaRicevuto += f => fotogramma.TrySetResult(f);
            sessione.Chiusa += () => chiusa.TrySetResult();
            sessione.Avvia();
            sessioneCreata.TrySetResult(sessione);
        };
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(5);

        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(usbmux.PortaTelefono, "iPhone sul cavo", gettone: abbinamento.Gettone).WaitAsync(Limite);
        Assert.Equal("PC di prova", (await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite)).Nome);
        Assert.Equal("iPhone sul cavo", (await salutato.Task.WaitAsync(Limite)).Nome);
        Assert.Equal(idComputer.Impronta, telefono.ImprontaComputer);
        var sessione = await sessioneCreata.Task;
        Assert.Equal(telefono.Identita.Impronta, sessione.ImprontaTelefono);
        Assert.True(abbinamento.Fidato(telefono.Identita.Impronta));
        Assert.Equal(StatoCavo.Collegato, cliente.Stato);

        // Video e comandi passano cifrati sul cavo.
        await telefono.InviaAsync(new FormatoVideo(Codec.Hevc, 1920, 1080, 30));
        Assert.Equal(Codec.Hevc, (await formato.Task.WaitAsync(Limite)).Codec);
        await telefono.InviaAsync(new FotogrammaVideo(Orologio.Adesso(), true, true, new byte[5000]).ComePacchetto());
        Assert.Equal(5000, (await fotogramma.Task.WaitAsync(Limite)).Dati.Length);
        await sessione.ComandaAsync(new Comando(Zoom: 2));
        Assert.Equal(new Comando(Zoom: 2), await telefono.AttendiAsync<Comando>().WaitAsync(Limite));

        // «Scollega» dal PC: arrivederci sul cavo; il cavo resta sospeso fino al prossimo collegamento.
        cliente.Sospendi(presaCavo!);
        await sessione.ChiudiAsync();
        await telefono.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        await chiusa.Task.WaitAsync(Limite);
        Assert.True(sessione.ChiusaDalComputer);
        await sessione.DisposeAsync();
        await Task.Delay(Riprova * 4);
        Assert.Equal(1, usbmux.Tentativi);
    }
}
