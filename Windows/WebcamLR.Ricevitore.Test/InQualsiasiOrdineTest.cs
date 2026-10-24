using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>1.12 «In qualsiasi ordine»: ascolto che si riapre da solo, risveglio dallo stop, cavo che riparte.</summary>
public class InQualsiasiOrdineTest
{
    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(15);

    private static async Task<Socket> CollegaAsync(int porta)
    {
        var presa = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        await presa.ConnectAsync(IPAddress.Loopback, porta).WaitAsync(Limite);
        return presa;
    }

    private static (Ascoltatore Ascoltatore, Channel<Socket> Accettate, Channel<int> Riaperture) Ascolto()
    {
        var ascoltatore = new Ascoltatore(IPAddress.Loopback, porta: 0);
        var accettate = Channel.CreateUnbounded<Socket>();
        var riaperture = Channel.CreateUnbounded<int>();
        ascoltatore.NuovoTelefono += presa => accettate.Writer.TryWrite(presa);
        ascoltatore.Riaperto += porta => riaperture.Writer.TryWrite(porta);
        return (ascoltatore, accettate, riaperture);
    }

    [Fact]
    public async Task AscoltoCadutoSiRiapreSullaStessaPorta()
    {
        var (ascoltatore, accettate, riaperture) = Ascolto();
        using var chiusura = ascoltatore;
        var porta = ascoltatore.Porta;
        using (await CollegaAsync(porta)) (await accettate.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();

        ascoltatore.Riapri();
        Assert.Equal(porta, await riaperture.Reader.ReadAsync().AsTask().WaitAsync(Limite));
        Assert.True(ascoltatore.Attivo);
        Assert.Equal(porta, ascoltatore.Porta);
        // E i telefoni si collegano di nuovo.
        using (await CollegaAsync(porta)) (await accettate.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
    }

    [Fact]
    public async Task PortaPresaNelFrattempoNeUsaUnAltra()
    {
        var (ascoltatore, accettate, riaperture) = Ascolto();
        using var chiusura = ascoltatore;
        var porta = ascoltatore.Porta;
        ascoltatore.Riapri();
        // Un altro programma prende la porta prima del nuovo tentativo (200 ms).
        var intruso = new TcpListener(IPAddress.Loopback, porta);
        try
        {
            intruso.Start();
        }
        catch (SocketException)
        {
            // Già riaperta sulla stessa porta: la situazione da provare non si è creata.
            return;
        }
        try
        {
            var nuova = await riaperture.Reader.ReadAsync().AsTask().WaitAsync(Limite);
            Assert.NotEqual(porta, nuova);
            Assert.Equal(nuova, ascoltatore.Porta);
            using (await CollegaAsync(nuova)) (await accettate.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
        }
        finally { intruso.Stop(); }
    }

    [Fact]
    public async Task ChiusoNonSiRiapre()
    {
        var (ascoltatore, _, riaperture) = Ascolto();
        ascoltatore.Dispose();
        await Task.Delay(500);
        Assert.False(riaperture.Reader.TryRead(out _));
        Assert.False(ascoltatore.Attivo);
    }

    [Fact]
    public void ControllaConAscoltoAttivoNonFaNulla()
    {
        var (ascoltatore, _, riaperture) = Ascolto();
        using var chiusura = ascoltatore;
        ascoltatore.Controlla();
        Assert.True(ascoltatore.Attivo);
        Assert.False(riaperture.Reader.TryRead(out _));
    }

    [Fact]
    public void RisveglioDalSaltoDellOrologio()
    {
        var sorveglianza = new SorveglianzaRisveglio(TimeSpan.FromSeconds(30));
        var adesso = new DateTime(2026, 10, 24, 18, 0, 0, DateTimeKind.Utc);
        Assert.False(sorveglianza.Controlla(adesso));
        Assert.False(sorveglianza.Controlla(adesso.AddSeconds(5)));
        Assert.False(sorveglianza.Controlla(adesso.AddSeconds(20)));
        // Coperchio chiuso per un'ora.
        Assert.True(sorveglianza.Controlla(adesso.AddHours(1)));
        Assert.False(sorveglianza.Controlla(adesso.AddHours(1).AddSeconds(5)));
    }

    [Fact]
    public async Task CavoRiprendeSubitoDopoIlRisveglio()
    {
        // Attesa crescente lunga (fino a 10 s): dopo quattro rifiuti il prossimo Connect sarebbe tra 1,2 s.
        var orologio = Stopwatch.StartNew();
        var tempi = new List<TimeSpan>();
        await using var usbmux = new UsbmuxFinto
        {
            EsitoConnect = _ =>
            {
                lock (tempi) tempi.Add(orologio.Elapsed);
                return 0;
            },
        };
        var riprova = TimeSpan.FromMilliseconds(150);
        await using var cliente = new ClienteUsbmux(new IPEndPoint(IPAddress.Loopback, usbmux.Porta), riprova,
            attesaServizio: TimeSpan.FromMilliseconds(150), attesaMassima: TimeSpan.FromSeconds(10));
        var prese = Channel.CreateUnbounded<Socket>();
        cliente.TelefonoViaCavo += presa => prese.Writer.TryWrite(presa);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);
        for (var i = 0; i < 4; i++) (await prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();

        // Il prossimo Connect aspetterebbe 1,2 s: dopo il risveglio parte subito.
        await Task.Delay(300);
        var prima = orologio.Elapsed;
        cliente.Riprendi();
        (await prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
        TimeSpan quinto;
        lock (tempi) quinto = tempi[4];
        Assert.True(quinto - prima < TimeSpan.FromMilliseconds(700), $"Dopo il risveglio troppo lento: {quinto - prima}");
        // E l'attesa crescente è ripartita da capo: il rifiuto seguente aspetta il ritmo normale.
        (await prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
        lock (tempi) Assert.True(tempi[5] - tempi[4] < TimeSpan.FromMilliseconds(700), $"Attesa non ripartita: {tempi[5] - tempi[4]}");
    }
}
