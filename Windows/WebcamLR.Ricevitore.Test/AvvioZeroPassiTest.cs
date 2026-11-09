using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Qualità 19 («avvio zero passi», Documenti/Avvio zero passi.md): un telefono già fidato che si collega arriva nella
/// webcam senza che nessuno tocchi nulla sul PC (nessuna domanda, nessun clic su «Usa», nessuna attesa voluta), e il
/// cavo riprova il Connect ogni secondo.
/// </summary>
public class AvvioZeroPassiTest
{
    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(15);

    /// <summary>
    /// Il PC come in MainWindow.Telefoni.cs: ascolto su loopback, sessioni con <c>Ammetti</c> dell'elenco, all'«ciao»
    /// <see cref="ElencoTelefoni.Accogli"/>; i fotogrammi del telefono nella webcam vanno all'uscita.
    /// </summary>
    private sealed class Computer : IDisposable
    {
        public readonly Ascoltatore Ascoltatore = new(IPAddress.Loopback, porta: 0);
        public readonly ElencoTelefoni Elenco = new();
        public readonly Channel<Arrivo> Arrivi = Channel.CreateUnbounded<Arrivo>();
        /// <summary>I fotogrammi arrivati all'uscita (webcam): solo quelli del telefono scelto.</summary>
        public readonly Channel<FotogrammaVideo> Uscita = Channel.CreateUnbounded<FotogrammaVideo>();
        public readonly Abbinamento Abbinamento;

        public Computer(Abbinamento abbinamento)
        {
            Abbinamento = abbinamento;
            Ascoltatore.NuovoTelefono += Accetta;
        }

        private void Accetta(Socket presa)
        {
            var nuova = new SessioneComputer(presa, "PC di prova", Abbinamento, TimeSpan.FromMilliseconds(200))
            {
                Collegamento = TipoCollegamento.WiFi,
                Ammetti = Elenco.PuoEntrare,
            };
            nuova.Salutato += ciao => Arrivi.Writer.TryWrite(Elenco.Accogli(nuova, ciao));
            nuova.FotogrammaRicevuto += fotogramma =>
            {
                if (Elenco.Di(nuova) is { } telefono && Elenco.ESelezionato(telefono)) Uscita.Writer.TryWrite(fotogramma);
            };
            nuova.Chiusa += () => Elenco.Perso(nuova);
            nuova.Avvia();
        }

        public void Dispose() => Ascoltatore.Dispose();
    }

    private static Abbinamento ConFidato(IdentitaDispositivo computer, IdentitaDispositivo telefono) =>
        new(computer, new Dictionary<string, string> { [telefono.Impronta] = "iPhone di Ledion" })
        {
            ChiediConferma = (_, _, _) => throw new InvalidOperationException("Un telefono fidato non va chiesto"),
        };

    /// <summary>Fino al «benvenuto»: nessuna «approvazione» (il codice di conferma) per un telefono fidato.</summary>
    private static async Task AttendiBenvenutoSenzaDomandeAsync(TelefonoFinto telefono)
    {
        while (true)
        {
            var messaggio = await telefono.Ricevuti.Reader.ReadAsync().AsTask().WaitAsync(Limite);
            Assert.IsNotType<Approvazione>(messaggio);
            if (messaggio is Benvenuto) return;
        }
    }

    private static async Task MandaVideoAsync(TelefonoFinto telefono)
    {
        await telefono.InviaAsync(new FormatoVideo(Codec.H264, 1920, 1080, 30));
        await telefono.InviaAsync(new FotogrammaVideo(Orologio.Adesso(), true, true, new byte[1500]).ComePacchetto());
    }

    [Fact]
    public async Task TelefonoFidatoArrivaInOndaSenzaAzioni()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idTelefono = IdentitaDispositivo.Nuova();
        using var pc = new Computer(ConFidato(idComputer, idTelefono));

        await using var telefono = new TelefonoFinto(idTelefono);
        var orologio = Stopwatch.StartNew();
        await telefono.CollegaAsync(pc.Ascoltatore.Porta, "iPhone di Ledion");
        await AttendiBenvenutoSenzaDomandeAsync(telefono);
        // Nessuna attesa voluta tra il collegamento e il «benvenuto»: solo stretta di mano e prova (pochi ms; il
        // margine copre una macchina di prova lenta, non un conto alla rovescia).
        Assert.True(orologio.Elapsed < TimeSpan.FromSeconds(3), $"Benvenuto dopo {orologio.Elapsed}");

        // Il primo telefono va nella webcam da solo: nessun clic su «Usa questa prospettiva».
        var arrivo = await pc.Arrivi.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.Equal(EsitoArrivo.Nuovo, arrivo.Esito);
        Assert.NotNull(arrivo.Telefono);
        Assert.True(pc.Elenco.ESelezionato(arrivo.Telefono!));
        // Con un'app che usa la webcam il telefono riceve il rosso «in onda».
        Assert.Equal(new InOnda(true, Selezionato: true), pc.Elenco.InOndaPer(arrivo.Telefono!, webcamInUso: true));

        // E il video arriva all'uscita della webcam.
        await MandaVideoAsync(telefono);
        var primo = await pc.Uscita.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.True(primo.Chiave);
        Assert.True(pc.Abbinamento.Fidato(idTelefono.Impronta));
    }

    /// <summary>
    /// Il telefono fidato cade (Wi-Fi perso, app riaperta) e torna con una sessione nuova: resta il telefono nella
    /// webcam, senza domande e senza clic.
    /// </summary>
    [Fact]
    public async Task TelefonoFidatoCheTornaRestaNellaWebcam()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idTelefono = IdentitaDispositivo.Nuova();
        using var pc = new Computer(ConFidato(idComputer, idTelefono));

        var primaVolta = new TelefonoFinto(idTelefono);
        await primaVolta.CollegaAsync(pc.Ascoltatore.Porta, "iPhone di Ledion");
        await AttendiBenvenutoSenzaDomandeAsync(primaVolta);
        var primo = await pc.Arrivi.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        // Caduta senza «arrivederci».
        await primaVolta.DisposeAsync();

        await using var tornato = new TelefonoFinto(idTelefono);
        await tornato.CollegaAsync(pc.Ascoltatore.Porta, "iPhone di Ledion");
        await AttendiBenvenutoSenzaDomandeAsync(tornato);
        var secondo = await pc.Arrivi.Reader.ReadAsync().AsTask().WaitAsync(Limite);
        Assert.Equal(EsitoArrivo.StessoTelefono, secondo.Esito);
        Assert.Same(primo.Telefono, secondo.Telefono);
        Assert.True(pc.Elenco.ESelezionato(secondo.Telefono!));
        Assert.Equal(1, pc.Elenco.Conteggio);

        await MandaVideoAsync(tornato);
        Assert.True((await pc.Uscita.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Chiave);
    }

    /// <summary>Un telefono nuovo, senza QR code, chiede ancora la conferma: la fiducia non si salta.</summary>
    [Fact]
    public async Task TelefonoNuovoChiedeAncoraLaConferma()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idFidato = IdentitaDispositivo.Nuova();
        var abbinamento = ConFidato(idComputer, idFidato);
        var domande = 0;
        abbinamento.ChiediConferma = (_, _, _) =>
        {
            Interlocked.Increment(ref domande);
            return Task.FromResult(false);
        };
        using var pc = new Computer(abbinamento);

        await using var sconosciuto = new TelefonoFinto();
        await sconosciuto.CollegaAsync(pc.Ascoltatore.Porta, "Telefono di qualcuno");
        await sconosciuto.AttendiAsync<Approvazione>().WaitAsync(Limite);
        await sconosciuto.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.Equal(1, Volatile.Read(ref domande));
        Assert.Equal(0, pc.Elenco.Conteggio);
        Assert.False(abbinamento.Fidato(sconosciuto.Identita.Impronta));
    }

    [Fact]
    public void IlCavoRiprovaOgniSecondoERifiutiComePrima()
    {
        Assert.Equal(TimeSpan.FromSeconds(1), ClienteUsbmux.IntervalloConnectPredefinito);
        // L'attesa dopo i rifiuti (telefono che chiude il cavo prima del «ciao») resta 2, 4, 8 … secondi.
        var cliente = new ClienteUsbmux();
        Assert.Equal(TimeSpan.FromSeconds(2), cliente.AttesaDopoRifiuti(1));
        Assert.Equal(TimeSpan.FromSeconds(4), cliente.AttesaDopoRifiuti(2));
    }

    /// <summary>
    /// L'iPhone è sul cavo ma l'app non ascolta ancora (Connect rifiutato da usbmux): con le attese di serie il PC
    /// riprova ogni secondo, non più ogni 2, così aprendo l'app il collegamento parte prima.
    /// </summary>
    [Fact]
    public async Task ConLAppChiusaIlConnectSiRiprovaOgniSecondo()
    {
        var orologio = Stopwatch.StartNew();
        var tempi = new List<TimeSpan>();
        await using var usbmux = new UsbmuxFinto
        {
            EsitoConnect = numero =>
            {
                lock (tempi) tempi.Add(orologio.Elapsed);
                // 3 = connessione rifiutata: WebcamLR sull'iPhone non è aperta. Dal quarto l'app risponde.
                return numero < 4 ? 3 : 0;
            },
        };
        await using var cliente = new ClienteUsbmux(new IPEndPoint(IPAddress.Loopback, usbmux.Porta));
        var prese = Channel.CreateUnbounded<Socket>();
        cliente.TelefonoViaCavo += presa => prese.Writer.TryWrite(presa);
        cliente.Avvia();
        await usbmux.InAscolto.Task.WaitAsync(Limite);
        await usbmux.AttaccaAsync(1);

        (await prese.Reader.ReadAsync().AsTask().WaitAsync(Limite)).Dispose();
        TimeSpan[] visti;
        lock (tempi) visti = tempi.ToArray();
        Assert.True(visti.Length >= 4, $"Tentativi: {visti.Length}");
        for (var i = 1; i < 4; i++)
        {
            var distanza = visti[i] - visti[i - 1];
            Assert.InRange(distanza, TimeSpan.FromMilliseconds(800), TimeSpan.FromMilliseconds(1700));
        }
    }
}
