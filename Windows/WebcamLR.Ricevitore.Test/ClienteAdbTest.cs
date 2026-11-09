using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Il cavo di Android (Qualità 17) contro un server di adb finto su loopback.</summary>
public class ClienteAdbTest
{
    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan Riprova = TimeSpan.FromMilliseconds(150);

    private static ClienteAdb Cliente(int porta, Func<CancellationToken, Task<bool>>? avvia = null, TimeSpan? pausaAvvio = null) =>
        new(new IPEndPoint(IPAddress.Loopback, porta), Riprova, attesaServizio: TimeSpan.FromMilliseconds(150), pausaAvvio: pausaAvvio)
        {
            AvviaServer = avvia,
        };

    private sealed class Osservatore
    {
        public readonly Channel<Socket> Prese = Channel.CreateUnbounded<Socket>();
        public readonly Channel<StatoCavo> Stati = Channel.CreateUnbounded<StatoCavo>();
        public readonly Channel<bool> Elenchi = Channel.CreateUnbounded<bool>();

        public Osservatore(ClienteAdb cliente)
        {
            cliente.TelefonoViaCavo += presa => Prese.Writer.TryWrite(presa);
            cliente.StatoCambiato += stato => Stati.Writer.TryWrite(stato);
            cliente.ElencoCambiato += () => Elenchi.Writer.TryWrite(true);
        }

        public async Task AttendiStatoAsync(StatoCavo voluto)
        {
            using var tempo = new CancellationTokenSource(Limite);
            while (await Stati.Reader.ReadAsync(tempo.Token) != voluto) { }
        }

        public Task<Socket> PresaAsync() => Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
    }

    private static int PortaLibera()
    {
        var prova = new TcpListener(IPAddress.Loopback, 0);
        prova.Start();
        var porta = ((IPEndPoint)prova.LocalEndpoint).Port;
        prova.Stop();
        return porta;
    }

    private static async Task AttendiAsync(Func<bool> condizione)
    {
        using var tempo = new CancellationTokenSource(Limite);
        while (!condizione()) await Task.Delay(20, tempo.Token);
    }

    [Fact]
    public async Task ServerAssenteEAdbMancante()
    {
        var avvii = 0;
        await using var cliente = Cliente(PortaLibera(), _ =>
        {
            Interlocked.Increment(ref avvii);
            return Task.FromResult(false);
        });
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await osservatore.AttendiStatoAsync(StatoCavo.ServizioAssente);
        await AttendiAsync(() => cliente.AdbMancante);
        // Si riprova a raggiungere il server ogni 150 ms, ma adb si cerca al massimo una volta al minuto.
        await Task.Delay(Riprova * 5);
        Assert.Equal(1, Volatile.Read(ref avvii));
        Assert.False(cliente.TelefonoAlCavo);
    }

    [Fact]
    public async Task ServerAvviatoDaNoiVieneTrovato()
    {
        var porta = PortaLibera();
        AdbFinto? adb = null;
        await using var cliente = Cliente(porta, _ =>
        {
            // «adb start-server»: il server parte sulla porta di sempre.
            adb ??= new AdbFinto(porta);
            return Task.FromResult(true);
        });
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
        Assert.False(cliente.AdbMancante);
        await adb!.DisposeAsync();
    }

    [Fact]
    public async Task UnServerGiaAccesoNonSiRiavvia()
    {
        await using var adb = new AdbFinto();
        var avvii = 0;
        await using var cliente = Cliente(adb.Porta, _ =>
        {
            Interlocked.Increment(ref avvii);
            return Task.FromResult(true);
        });
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
        Assert.Equal(0, avvii);
        Assert.Equal("0012host:track-devices", await adb.Richieste.Reader.ReadAsync().AsTask().WaitAsync(Limite));
    }

    [Fact]
    public async Task TelefonoProntoApreTransportEPorta52741()
    {
        await using var adb = new AdbFinto();
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);
        Assert.Equal("0012host:track-devices", await adb.Richieste.Reader.ReadAsync());

        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");
        var presa = await osservatore.PresaAsync();
        Assert.Equal("001ahost:transport:R58N12ABCDE", await adb.Richieste.Reader.ReadAsync());
        Assert.Equal("0009tcp:52741", await adb.Richieste.Reader.ReadAsync());
        await osservatore.AttendiStatoAsync(StatoCavo.Collegato);
        Assert.True(cliente.TelefonoAlCavo);
        Assert.True(cliente.EMia(presa));

        // Dopo i due «OKAY» la connessione è il canale: i byte arrivano al telefono così come sono.
        var lato = await adb.CanaliAperti.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        await presa.SendAsync(new byte[] { 1, 2, 3 });
        var letti = new byte[3];
        await lato.ReadExactlyAsync(letti).AsTask().WaitAsync(Limite);
        Assert.Equal(new byte[] { 1, 2, 3 }, letti);
        presa.Dispose();
    }

    [Fact]
    public async Task NonAutorizzatoAspettaIlConsenso()
    {
        await using var adb = new AdbFinto();
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);

        await adb.ImpostaElencoAsync("R58N12ABCDE\tunauthorized\n");
        await AttendiAsync(() => cliente.DaAutorizzare == 1);
        await Task.Delay(Riprova * 3);
        // Nessun tentativo verso un telefono che non ha ancora detto «Consenti».
        Assert.Equal(0, adb.Tentativi);
        Assert.False(cliente.TelefonoAlCavo);

        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");
        (await osservatore.PresaAsync()).Dispose();
        Assert.Equal(0, cliente.DaAutorizzare);
    }

    [Fact]
    public async Task DebugWirelessEdEmulatoriNonSonoIlCavo()
    {
        await using var adb = new AdbFinto();
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);

        await adb.ImpostaElencoAsync("192.168.1.5:5555\tdevice\nemulator-5554\tdevice\n" +
            "adb-R58N12ABCDE-x1y2z3._adb-tls-connect._tcp\tdevice\n");
        await Task.Delay(Riprova * 4);
        Assert.Equal(0, adb.Tentativi);
        Assert.Empty(cliente.Elenco);
        Assert.False(osservatore.Prese.Reader.TryRead(out _));
    }

    [Fact]
    public async Task AppChiusaRiprovaSenzaAttesaCrescente()
    {
        await using var adb = new AdbFinto { AppInAscolto = tentativo => tentativo > 3 };
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);
        var orologio = System.Diagnostics.Stopwatch.StartNew();
        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");

        // Tre «FAIL closed» (WebcamLR chiusa sul telefono), poi l'app si apre: un tentativo per intervallo, non 2, 4, 8…
        (await osservatore.PresaAsync()).Dispose();
        Assert.Equal(4, adb.Tentativi);
        Assert.True(orologio.Elapsed < Riprova * 3 + TimeSpan.FromSeconds(2), $"Troppo lento: {orologio.Elapsed}");
    }

    [Fact]
    public async Task StaccatoDallElencoFermaITentativi()
    {
        await using var adb = new AdbFinto { AppInAscolto = _ => false };
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);
        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");
        await AttendiAsync(() => adb.Tentativi >= 2);

        await adb.ImpostaElencoAsync("");
        await AttendiAsync(() => !cliente.TelefonoAlCavo);
        var dopo = adb.Tentativi;
        await Task.Delay(Riprova * 4);
        Assert.InRange(adb.Tentativi, dopo, dopo + 1);
    }

    [Fact]
    public async Task SospesoNonRicollegaFinoAlProssimoCavo()
    {
        await using var adb = new AdbFinto();
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);
        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");

        var presa = await osservatore.PresaAsync();
        cliente.Sospendi(presa);
        presa.Dispose();
        await Task.Delay(Riprova * 5);
        Assert.Equal(1, adb.Tentativi);
        Assert.False(cliente.TelefonoAlCavo);

        // Cavo staccato e riattaccato: si ricomincia.
        await adb.ImpostaElencoAsync("");
        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");
        (await osservatore.PresaAsync()).Dispose();
        Assert.Equal(2, adb.Tentativi);
    }

    [Fact]
    public async Task LasciatoPerSceltaTornaConRiprendiScelti()
    {
        await using var adb = new AdbFinto();
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);
        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");

        var presa = await osservatore.PresaAsync();
        cliente.StrettaRiuscita(presa);
        // Il telefono preferisce il Wi-Fi: la sessione sul cavo si chiude per scelta.
        cliente.Sospendi(presa, perScelta: true);
        cliente.Sospendi(presa);
        presa.Dispose();
        await Task.Delay(Riprova * 4);
        Assert.Equal(1, adb.Tentativi);

        cliente.RiprendiScelti();
        (await osservatore.PresaAsync()).Dispose();
        Assert.Equal(2, adb.Tentativi);
    }

    [Fact]
    public async Task ServerCheSiFermaVieneRitrovato()
    {
        await using var adb = new AdbFinto();
        await using var cliente = Cliente(adb.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");
        (await osservatore.PresaAsync()).Dispose();

        // «adb kill-server» da un'altra app: la connessione dell'elenco si chiude, i telefoni si dimenticano.
        adb.ChiudiElenchi();
        await osservatore.AttendiStatoAsync(StatoCavo.ServizioAssente);
        await osservatore.AttendiStatoAsync(StatoCavo.InAscolto);
        // Il server rimanda l'elenco: il telefono torna.
        (await osservatore.PresaAsync()).Dispose();
    }

    /// <summary>
    /// Da un capo all'altro: il telefono Android finto ascolta «dietro» il server di adb finto, il PC apre il canale con
    /// host:transport e tcp:52741 e ne fa una sessione come quelle del Wi-Fi: stretta di mano, QR code, benvenuto, video.
    /// </summary>
    [Fact]
    public async Task SessioneSicuraCompletaSulCavoAndroid()
    {
        await using var adb = new AdbFinto(conTelefono: true);
        await using var cliente = Cliente(adb.Porta);
        using var idComputer = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer);
        var sessioneCreata = new TaskCompletionSource<SessioneComputer>(TaskCreationOptions.RunContinuationsAsynchronously);
        var salutato = new TaskCompletionSource<Ciao>(TaskCreationOptions.RunContinuationsAsynchronously);
        var fotogramma = new TaskCompletionSource<FotogrammaVideo>(TaskCreationOptions.RunContinuationsAsynchronously);
        var chiusa = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Socket? presaCavo = null;
        cliente.TelefonoViaCavo += presa =>
        {
            presaCavo = presa;
            var sessione = new SessioneComputer(presa, "PC di prova", abbinamento, TimeSpan.FromMilliseconds(200))
            {
                Collegamento = TipoCollegamento.CavoUsb,
            };
            sessione.Salutato += ciao => salutato.TrySetResult(ciao);
            sessione.FotogrammaRicevuto += f => fotogramma.TrySetResult(f);
            sessione.Chiusa += () => chiusa.TrySetResult();
            sessione.Avvia();
            sessioneCreata.TrySetResult(sessione);
        };
        cliente.Avvia();
        await adb.InAscolto.Task.WaitAsync(Limite);
        await adb.ImpostaElencoAsync("R58N12ABCDE\tdevice\n");

        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(adb.PortaTelefono, "Pixel sul cavo", gettone: abbinamento.Gettone,
            piattaforma: Piattaforma.Android).WaitAsync(Limite);
        Assert.Equal("PC di prova", (await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite)).Nome);
        var ciao = await salutato.Task.WaitAsync(Limite);
        Assert.Equal(Piattaforma.Android, ciao.Piattaforma);
        Assert.Equal(idComputer.Impronta, telefono.ImprontaComputer);
        var sessione = await sessioneCreata.Task;
        Assert.True(sessione.ViaCavo);
        Assert.True(abbinamento.Fidato(telefono.Identita.Impronta));
        Assert.Equal(StatoCavo.Collegato, cliente.Stato);

        await telefono.InviaAsync(new FotogrammaVideo(Orologio.Adesso(), true, true, new byte[5000]).ComePacchetto());
        Assert.Equal(5000, (await fotogramma.Task.WaitAsync(Limite)).Dati.Length);

        // «Scollega» dal PC: arrivederci sul cavo, poi niente ricollegamento automatico.
        cliente.Sospendi(presaCavo!);
        await sessione.ChiudiAsync();
        await telefono.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        await chiusa.Task.WaitAsync(Limite);
        await sessione.DisposeAsync();
        await Task.Delay(Riprova * 4);
        Assert.Equal(1, adb.Tentativi);
    }
}
