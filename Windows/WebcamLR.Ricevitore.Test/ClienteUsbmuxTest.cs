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
        // Sospeso non conta come «iPhone al cavo»: la diagnosi non deve dire che si ricollega da solo.
        Assert.False(cliente.IPhoneAlCavo);

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

    // Attesa crescente quando il telefono rifiuta il cavo: 150, 300, 600, 1200, 2400 ms, poi 5 s.
    private static readonly TimeSpan Massima = TimeSpan.FromSeconds(5);
    /// <summary>Molto sotto l'attesa dopo quattro rifiuti (2,4 s): il ritmo normale di un tentativo ogni intervallo.</summary>
    private static readonly TimeSpan Svelto = TimeSpan.FromMilliseconds(800);

    private static ClienteUsbmux ClienteConAttesa(int porta) =>
        new(new IPEndPoint(IPAddress.Loopback, porta), Riprova, attesaServizio: TimeSpan.FromMilliseconds(150), attesaMassima: Massima);

    /// <summary>Un usbmuxd finto che segna quando arriva ogni Connect; <paramref name="esito"/> come EsitoConnect.</summary>
    private static (UsbmuxFinto Usbmux, List<TimeSpan> Tempi) UsbmuxCronometrato(Func<int, int>? esito = null)
    {
        var orologio = Stopwatch.StartNew();
        var tempi = new List<TimeSpan>();
        var usbmux = new UsbmuxFinto
        {
            EsitoConnect = tentativo =>
            {
                lock (tempi) tempi.Add(orologio.Elapsed);
                return esito?.Invoke(tentativo) ?? 0;
            },
        };
        return (usbmux, tempi);
    }

    private static TimeSpan Distanza(List<TimeSpan> tempi, int da, int a)
    {
        lock (tempi) return tempi[a - 1] - tempi[da - 1];
    }

    /// <summary>Il telefono chiude prima del «ciao»: la sessione chiude la presa, come SessioneComputer.</summary>
    private static async Task RifiutaAsync(Osservatore osservatore, int volte)
    {
        for (var i = 0; i < volte; i++)
            (await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
    }

    [Fact]
    public void AttesaDopoRifiutiRaddoppiaFinoAlMassimo()
    {
        var cliente = new ClienteUsbmux();
        Assert.Equal(TimeSpan.FromSeconds(2), cliente.AttesaDopoRifiuti(0));
        Assert.Equal(TimeSpan.FromSeconds(2), cliente.AttesaDopoRifiuti(1));
        Assert.Equal(TimeSpan.FromSeconds(4), cliente.AttesaDopoRifiuti(2));
        Assert.Equal(TimeSpan.FromSeconds(8), cliente.AttesaDopoRifiuti(3));
        Assert.Equal(TimeSpan.FromSeconds(16), cliente.AttesaDopoRifiuti(4));
        Assert.Equal(TimeSpan.FromSeconds(30), cliente.AttesaDopoRifiuti(5));
        Assert.Equal(TimeSpan.FromSeconds(30), cliente.AttesaDopoRifiuti(50));
    }

    [Fact]
    public async Task ChiusoPrimaDellaStrettaLAttesaCresce()
    {
        var (usbmux, tempi) = UsbmuxCronometrato();
        await using var chiusura = usbmux;
        await using var cliente = ClienteConAttesa(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        var eventi = Channel.CreateUnbounded<string>();
        cliente.Evento += testo => eventi.Writer.TryWrite(testo);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);

        // Quattro connessioni chiuse dal telefono prima di essere accettate: cinque Connect.
        await RifiutaAsync(osservatore, 4);
        await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.Equal(5, usbmux.Tentativi);
        // Dopo il primo rifiuto il ritmo di sempre; poi 300, 600, 1200 ms.
        Assert.True(Distanza(tempi, 2, 3) >= TimeSpan.FromMilliseconds(270), $"Secondo tentativo troppo presto: {Distanza(tempi, 2, 3)}");
        Assert.True(Distanza(tempi, 3, 4) >= TimeSpan.FromMilliseconds(540), $"Terzo tentativo troppo presto: {Distanza(tempi, 3, 4)}");
        Assert.True(Distanza(tempi, 4, 5) >= TimeSpan.FromMilliseconds(1080), $"Quarto tentativo troppo presto: {Distanza(tempi, 4, 5)}");
        Assert.True(Distanza(tempi, 4, 5) > Distanza(tempi, 1, 2));

        // Una riga per gradino: quattro rifiuti, quattro righe sull'attesa.
        var righe = new List<string>();
        while (eventi.Reader.TryRead(out var riga)) righe.Add(riga);
        Assert.Equal(4, righe.Count(r => r.Contains("riprovo tra")));
    }

    [Fact]
    public async Task AlMassimoUnaRigaSola()
    {
        var (usbmux, _) = UsbmuxCronometrato();
        await using var chiusura = usbmux;
        // Massimo già al secondo rifiuto: i rifiuti successivi non scrivono più nulla.
        await using var cliente = new ClienteUsbmux(new IPEndPoint(IPAddress.Loopback, usbmux.Porta), Riprova,
            attesaServizio: TimeSpan.FromMilliseconds(150), attesaMassima: TimeSpan.FromMilliseconds(250));
        var osservatore = new Osservatore(cliente);
        var righe = 0;
        cliente.Evento += testo => { if (testo.Contains("riprovo tra")) Interlocked.Increment(ref righe); };
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);

        await RifiutaAsync(osservatore, 6);
        await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        // Primo rifiuto (150 ms) e secondo (250 ms, il massimo): poi silenzio.
        Assert.Equal(2, Volatile.Read(ref righe));
    }

    [Fact]
    public async Task RicollegareIlCavoRiparteDaCapo()
    {
        var (usbmux, _) = UsbmuxCronometrato();
        await using var chiusura = usbmux;
        await using var cliente = ClienteConAttesa(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);
        await RifiutaAsync(osservatore, 4);

        // Il prossimo tentativo sarebbe tra 2,4 s: il cavo staccato e ricollegato riparte subito, al ritmo normale.
        await usbmux.StaccaAsync(1);
        await usbmux.AttaccaAsync(2);
        var orologio = Stopwatch.StartNew();
        await RifiutaAsync(osservatore, 2);
        Assert.True(orologio.Elapsed < Svelto, $"Dopo il nuovo cavo troppo lento: {orologio.Elapsed}");
        (await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
        Assert.Equal(7, usbmux.Tentativi);
    }

    [Fact]
    public async Task StrettaRiuscitaRiparteDaCapo()
    {
        var (usbmux, tempi) = UsbmuxCronometrato();
        await using var chiusura = usbmux;
        await using var cliente = ClienteConAttesa(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);
        await RifiutaAsync(osservatore, 3);

        // Questa volta il telefono accetta («ciao»), poi la sessione finisce: si riprova subito, non tra 1,2 s.
        var accettata = await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        cliente.StrettaRiuscita(accettata);
        accettata.Dispose();
        var seguente = await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.True(Distanza(tempi, 4, 5) < Svelto, $"Dopo un collegamento accettato troppo lento: {Distanza(tempi, 4, 5)}");
        // E il rifiuto seguente è di nuovo il primo.
        seguente.Dispose();
        (await osservatore.Prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
        Assert.True(Distanza(tempi, 5, 6) < Svelto, $"Primo rifiuto dopo l'accettazione troppo lento: {Distanza(tempi, 5, 6)}");
    }

    [Fact]
    public async Task AppChiusaResta2SecondiAncheDopoIRifiuti()
    {
        // Tre connessioni rifiutate dal telefono, poi WebcamLR chiusa sull'iPhone (Result diverso da 0).
        var (usbmux, tempi) = UsbmuxCronometrato(tentativo => tentativo <= 3 ? 0 : 3);
        await using var chiusura = usbmux;
        await using var cliente = ClienteConAttesa(usbmux.Porta);
        var osservatore = new Osservatore(cliente);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);
        await RifiutaAsync(osservatore, 3);

        // Il Connect dopo il terzo rifiuto aspetta 600 ms; quelli che falliscono dopo restano al ritmo normale.
        for (var i = 0; i < 4; i++) await usbmux.Connect.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        await usbmux.Connect.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        await usbmux.Connect.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.True(Distanza(tempi, 3, 4) >= TimeSpan.FromMilliseconds(540), $"Dopo il rifiuto troppo presto: {Distanza(tempi, 3, 4)}");
        Assert.True(Distanza(tempi, 4, 5) >= Riprova * 0.9 && Distanza(tempi, 4, 5) < Svelto, $"App chiusa: {Distanza(tempi, 4, 5)}");
        Assert.True(Distanza(tempi, 5, 6) >= Riprova * 0.9 && Distanza(tempi, 5, 6) < Svelto, $"App chiusa: {Distanza(tempi, 5, 6)}");
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
