using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Threading.Channels;
using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// P21, «Più telefoni insieme»: due telefoni diversi collegati allo stesso PC, ognuno con il suo video; il terzo non
/// entra; scambio, scollegamento di uno, ricollegamento e precedenza del cavo per ogni telefono. Con i telefoni finti
/// su loopback e le sessioni create come fa la finestra.
/// </summary>
public class PiuTelefoniTest
{
    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(15);

    /// <summary>Il PC: un ascolto «Wi-Fi» e uno che fa da cavo USB, e l'elenco dei telefoni.</summary>
    private sealed class Computer : IDisposable
    {
        public readonly ElencoTelefoni Elenco;
        public readonly Ascoltatore WiFi = new(IPAddress.Loopback, porta: 0);
        public readonly Ascoltatore Cavo = new(IPAddress.Loopback, porta: 0);
        public readonly Abbinamento Abbinamento;
        public readonly Channel<Arrivo> Arrivi = Channel.CreateUnbounded<Arrivo>();
        public readonly Channel<string> NonAmmessi = Channel.CreateUnbounded<string>();
        public readonly Channel<TelefonoCollegato> Persi = Channel.CreateUnbounded<TelefonoCollegato>();
        public readonly ConcurrentDictionary<SessioneComputer, int> Fotogrammi = new();
        private readonly bool precontrollo;

        public Computer(Abbinamento abbinamento, int massimo = ElencoTelefoni.MassimoPredefinito, bool precontrollo = true)
        {
            Abbinamento = abbinamento;
            Elenco = new ElencoTelefoni(massimo);
            this.precontrollo = precontrollo;
            WiFi.NuovoTelefono += presa => Accetta(presa, TipoCollegamento.WiFi);
            Cavo.NuovoTelefono += presa => Accetta(presa, TipoCollegamento.CavoUsb);
        }

        private void Accetta(Socket presa, TipoCollegamento tipo)
        {
            var nuova = new SessioneComputer(presa, "PC di prova", Abbinamento, TimeSpan.FromMilliseconds(200))
            {
                Collegamento = tipo,
                Ammetti = precontrollo ? Elenco.PuoEntrare : null,
            };
            nuova.NonAmmesso += ciao => NonAmmessi.Writer.TryWrite(ciao.Nome);
            nuova.Salutato += ciao =>
            {
                var arrivo = Elenco.Accogli(nuova, ciao);
                if (arrivo.DaChiudere is { } daChiudere) _ = daChiudere.ChiudiAsync();
                Arrivi.Writer.TryWrite(arrivo);
            };
            nuova.FormatoRicevuto += formato => { if (Elenco.Di(nuova) is { } telefono) telefono.Formato = formato; };
            nuova.FotogrammaRicevuto += _ => Fotogrammi.AddOrUpdate(nuova, 1, (_, n) => n + 1);
            nuova.Chiusa += () => { if (Elenco.Perso(nuova) is { } telefono) Persi.Writer.TryWrite(telefono); };
            nuova.Avvia();
        }

        public async Task<Arrivo> ArrivoAsync() => await Arrivi.Reader.ReadAsync().AsTask().WaitAsync(Limite);

        public void Dispose()
        {
            WiFi.Dispose();
            Cavo.Dispose();
        }
    }

    private static Abbinamento Fidati(IdentitaDispositivo computer, params IdentitaDispositivo[] telefoni) =>
        new(computer, telefoni.ToDictionary(t => t.Impronta, _ => "iPhone"))
        {
            ChiediConferma = (_, _, _) => throw new InvalidOperationException("Non doveva chiedere"),
        };

    private static async Task<(TelefonoFinto Telefono, Arrivo Arrivo)> CollegaAsync(Computer pc, IdentitaDispositivo id, string nome,
        bool viaCavo = false)
    {
        var telefono = new TelefonoFinto(id);
        await telefono.CollegaAsync(viaCavo ? pc.Cavo.Porta : pc.WiFi.Porta, nome);
        var arrivo = await pc.ArrivoAsync();
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);
        return (telefono, arrivo);
    }

    private static async Task MandaVideoAsync(TelefonoFinto telefono, int fotogrammi)
    {
        await telefono.InviaAsync(new FormatoVideo(Codec.H264, 1280, 720, 30));
        for (var i = 0; i < fotogrammi; i++)
            await telefono.InviaAsync(new FotogrammaVideo(Orologio.Adesso(), i == 0, i == 0, new byte[500]).ComePacchetto());
    }

    private static async Task AttendiAsync(Func<bool> condizione)
    {
        var fine = DateTime.UtcNow + Limite;
        while (!condizione())
        {
            if (DateTime.UtcNow > fine) throw new TimeoutException();
            await Task.Delay(20);
        }
    }

    [Fact]
    public async Task DueTelefoniDiversiInsiemeOgnunoConIlSuoVideo()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB));

        var (a, arrivoA) = await CollegaAsync(pc, idA, "iPhone");
        await using var _a = a;
        var (b, arrivoB) = await CollegaAsync(pc, idB, "iPhone");
        await using var _b = b;

        // Due telefoni chiamati entrambi «iPhone» sono telefoni diversi: si riconoscono dal codice di sicurezza.
        Assert.Equal(EsitoArrivo.Nuovo, arrivoA.Esito);
        Assert.Equal(EsitoArrivo.Nuovo, arrivoB.Esito);
        Assert.Null(arrivoB.DaChiudere);
        Assert.Equal(2, pc.Elenco.Conteggio);
        // Il primo va nella webcam; il secondo resta accanto, così una chiamata in corso non cambia immagine.
        Assert.Same(arrivoA.Telefono, pc.Elenco.Selezionato);
        Assert.Same(arrivoB.Telefono, pc.Elenco.Altro);

        // Ognuno il suo video, ognuno i suoi comandi.
        await MandaVideoAsync(a, 5);
        await MandaVideoAsync(b, 8);
        var sessioneA = arrivoA.Telefono!.Sessione!;
        var sessioneB = arrivoB.Telefono!.Sessione!;
        await AttendiAsync(() => pc.Fotogrammi.GetValueOrDefault(sessioneA) == 5 && pc.Fotogrammi.GetValueOrDefault(sessioneB) == 8);
        await AttendiAsync(() => arrivoA.Telefono.Formato is not null && arrivoB.Telefono.Formato is not null);

        await sessioneB.ComandaAsync(new Comando(Zoom: 2));
        await sessioneA.ComandaAsync(new Comando(Torcia: true));
        Assert.Equal(new Comando(Zoom: 2), await b.AttendiAsync<Comando>().WaitAsync(Limite));
        Assert.Equal(new Comando(Torcia: true), await a.AttendiAsync<Comando>().WaitAsync(Limite));
    }

    [Fact]
    public async Task IlTerzoTelefonoNonEntraENonFaDomande()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var idC = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB));

        var (a, _) = await CollegaAsync(pc, idA, "iPhone di Ledion");
        await using var _a = a;
        var (b, _) = await CollegaAsync(pc, idB, "iPhone di Sara");
        await using var _b = b;

        // Anche con il QR code: il gettone non si consuma e il telefono non diventa fidato.
        var gettone = pc.Abbinamento.Gettone;
        await using var c = new TelefonoFinto(idC);
        await c.CollegaAsync(pc.WiFi.Porta, "Pixel", gettone);
        await c.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.Equal("Pixel", await pc.NonAmmessi.Reader.ReadAsync().AsTask().WaitAsync(Limite));
        Assert.Equal(gettone, pc.Abbinamento.Gettone);
        Assert.False(pc.Abbinamento.Fidato(idC.Impronta));
        Assert.Equal(2, pc.Elenco.Conteggio);
        Assert.False(pc.Arrivi.Reader.TryRead(out _));
        Assert.Equal("«Pixel» non si è collegato: scollega uno dei due telefoni e riprova.", ElencoTelefoni.MessaggioPieno("Pixel"));
    }

    [Fact]
    public async Task SecondoTelefonoSoloConPro()
    {
        // WebcamLR Pro, come sul Mac: il secondo telefono entra solo se quello nella webcam ha sbloccato Pro.
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB));
        pc.Elenco.RichiedePro = true;

        var (a, arrivoA) = await CollegaAsync(pc, idA, "iPhone di Ledion");
        await using var _a = a;
        // Gratis (nessuna capacità, o pro falso): il secondo non entra e non fa domande.
        arrivoA.Telefono!.Capacita = new Capacita(["frontale"], 1, false, Pro: false);
        Assert.True(pc.Elenco.FuoriPerPro(idB.Impronta));
        Assert.False(pc.Elenco.PuoEntrare(idB.Impronta));
        await using (var b = new TelefonoFinto(idB))
        {
            await b.CollegaAsync(pc.WiFi.Porta, "Pixel");
            await b.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        }
        Assert.Equal("Pixel", await pc.NonAmmessi.Reader.ReadAsync().AsTask().WaitAsync(Limite));
        Assert.Equal(1, pc.Elenco.Conteggio);
        // Lo stesso telefono che torna entra sempre.
        Assert.True(pc.Elenco.PuoEntrare(idA.Impronta));
        Assert.False(pc.Elenco.FuoriPerPro(idA.Impronta));

        // Con Pro sul telefono nella webcam, il secondo entra.
        arrivoA.Telefono.Capacita = new Capacita(["frontale"], 1, false, Pro: true);
        Assert.False(pc.Elenco.FuoriPerPro(idB.Impronta));
        var (b2, arrivoB) = await CollegaAsync(pc, idB, "Pixel");
        await using var _b2 = b2;
        Assert.Equal(EsitoArrivo.Nuovo, arrivoB.Esito);
        Assert.Equal(2, pc.Elenco.Conteggio);
    }

    [Fact]
    public async Task SenzaProAncheSenzaPrecontrollo()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB), precontrollo: false);
        pc.Elenco.RichiedePro = true;
        var (a, _) = await CollegaAsync(pc, idA, "A");
        await using var _a = a;
        await using var b = new TelefonoFinto(idB);
        await b.CollegaAsync(pc.WiFi.Porta, "B");
        var arrivoB = await pc.ArrivoAsync();
        Assert.Equal(EsitoArrivo.SenzaPro, arrivoB.Esito);
        Assert.Null(arrivoB.Telefono);
        await b.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.Equal(1, pc.Elenco.Conteggio);
    }

    [Fact]
    public async Task DueArriviInsiemeConUnPostoSoloUnoEntra()
    {
        // Senza il controllo prima della fiducia, l'elenco decide da solo all'arrivo: il secondo è «Pieno» e si chiude.
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB), massimo: 1, precontrollo: false);

        var (a, arrivoA) = await CollegaAsync(pc, idA, "A");
        await using var _a = a;
        await using var b = new TelefonoFinto(idB);
        await b.CollegaAsync(pc.WiFi.Porta, "B");
        var arrivoB = await pc.ArrivoAsync();
        Assert.Equal(EsitoArrivo.Nuovo, arrivoA.Esito);
        Assert.Equal(EsitoArrivo.Pieno, arrivoB.Esito);
        Assert.Null(arrivoB.Telefono);
        await b.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.Equal(1, pc.Elenco.Conteggio);
    }

    [Fact]
    public async Task ScambioEScollegamentoDiUnoSolo()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var idC = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB, idC));

        var (a, arrivoA) = await CollegaAsync(pc, idA, "A");
        await using var _a = a;
        var (b, arrivoB) = await CollegaAsync(pc, idB, "B");
        await using var _b = b;
        var telefonoA = arrivoA.Telefono!;
        var telefonoB = arrivoB.Telefono!;

        // Clic sul riquadro piccolo: B va nella webcam, A nel riquadro.
        Assert.Same(telefonoB, pc.Elenco.Scambia());
        Assert.Same(telefonoB, pc.Elenco.Selezionato);
        Assert.Same(telefonoA, pc.Elenco.Altro);
        Assert.Same(telefonoB.Sessione, pc.Elenco.SessioneSelezionata);
        Assert.False(pc.Elenco.Seleziona(telefonoB));
        Assert.True(pc.Elenco.Seleziona(telefonoA));
        Assert.True(pc.Elenco.ESelezionato(telefonoA));

        // «Scollega» su A, che è nella webcam: A riceve l'arrivederci, B ci va da solo e resta collegato.
        var daChiudere = pc.Elenco.Rimuovi(telefonoA);
        Assert.NotNull(daChiudere);
        await daChiudere!.ChiudiAsync();
        await a.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.Same(telefonoB, pc.Elenco.Selezionato);
        Assert.Null(pc.Elenco.Altro);
        Assert.False(pc.Elenco.Contiene(telefonoA));
        // Tolto dal PC: la chiusura non lo rimette in attesa.
        await Task.Delay(300);
        Assert.False(pc.Persi.Reader.TryRead(out _));
        Assert.False(telefonoB.Sessione!.Terminata);
        await telefonoB.Sessione.ComandaAsync(new Comando(Zoom: 3));
        Assert.Equal(new Comando(Zoom: 3), await b.AttendiAsync<Comando>().WaitAsync(Limite));

        // Adesso c'è posto per un altro telefono.
        var (c, arrivoC) = await CollegaAsync(pc, idC, "C");
        await using var _c = c;
        Assert.Equal(EsitoArrivo.Nuovo, arrivoC.Esito);
        Assert.Same(telefonoB, pc.Elenco.Selezionato);
        Assert.Null(pc.Elenco.Rimuovi(telefonoA));
    }

    [Fact]
    public async Task LoStessoTelefonoTornaERitrovaIlSuoPosto()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var idC = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB, idC));

        var (a, arrivoA) = await CollegaAsync(pc, idA, "A");
        var (b, arrivoB) = await CollegaAsync(pc, idB, "B");
        await using var _b = b;
        var telefonoA = arrivoA.Telefono!;
        pc.Elenco.Seleziona(arrivoB.Telefono!);
        telefonoA.Comandi = telefonoA.Comandi.Applica(new Comando(Zoom: 2.5, Bianco: 4300));

        // A sparisce (rete persa): resta nell'elenco, in riconnessione, e tiene il suo posto.
        await a.DisposeAsync();
        Assert.Same(telefonoA, await pc.Persi.Reader.ReadAsync().AsTask().WaitAsync(Limite));
        Assert.True(telefonoA.InRiconnessione);
        Assert.Null(telefonoA.Sessione);
        Assert.Equal(1, telefonoA.Perdite);
        Assert.False(pc.Elenco.PuoEntrare(idC.Impronta));
        Assert.True(pc.Elenco.PuoEntrare(idA.Impronta));

        // Torna con una sessione nuova: stesso posto, stessi comandi da rimandare; B resta nella webcam.
        var (tornato, arrivo) = await CollegaAsync(pc, idA, "A");
        await using var _t = tornato;
        Assert.Equal(EsitoArrivo.StessoTelefono, arrivo.Esito);
        Assert.Same(telefonoA, arrivo.Telefono);
        Assert.Null(arrivo.DaChiudere);
        Assert.False(telefonoA.InRiconnessione);
        Assert.Same(arrivoB.Telefono, pc.Elenco.Selezionato);
        Assert.Equal(2, pc.Elenco.Conteggio);
        await telefonoA.Sessione!.ComandaAsync(telefonoA.Comandi.PerRicollegamento());
        Assert.Equal(new Comando(Zoom: 2.5, Torcia: false, Esposizione: 0, Bianco: 4300, Iso: 0, Tempo: 0),
            await tornato.AttendiAsync<Comando>().WaitAsync(Limite));
    }

    [Fact]
    public async Task PrecedenzaDelCavoPerOgniTelefono()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idA = IdentitaDispositivo.Nuova();
        using var idB = IdentitaDispositivo.Nuova();
        using var pc = new Computer(Fidati(idComputer, idA, idB));

        var (aWiFi, arrivoA) = await CollegaAsync(pc, idA, "A");
        await using var _aw = aWiFi;
        var (b, arrivoB) = await CollegaAsync(pc, idB, "B");
        await using var _b = b;
        var telefonoA = arrivoA.Telefono!;
        var sessioneB = arrivoB.Telefono!.Sessione;

        // A collegato anche al cavo: il cavo prende il posto del Wi-Fi, che riceve l'arrivederci. B non cambia.
        var (aCavo, cavo) = await CollegaAsync(pc, idA, "A", viaCavo: true);
        await using var _ac = aCavo;
        Assert.Equal(EsitoArrivo.CavoAlPostoDelWiFi, cavo.Esito);
        Assert.Same(telefonoA, cavo.Telefono);
        await aWiFi.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.True(telefonoA.Sessione!.ViaCavo);
        Assert.Equal(TipoCollegamento.CavoUsb, telefonoA.Collegamento);
        Assert.Same(telefonoA, pc.Elenco.Selezionato);
        Assert.Same(sessioneB, arrivoB.Telefono.Sessione);

        // A torna anche in Wi-Fi: resta il cavo, il Wi-Fi si chiude.
        await using var aDiNuovo = new TelefonoFinto(idA);
        await aDiNuovo.CollegaAsync(pc.WiFi.Porta, "A");
        var resta = await pc.ArrivoAsync();
        Assert.Equal(EsitoArrivo.RestaIlCavo, resta.Esito);
        await aDiNuovo.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.True(telefonoA.Sessione!.ViaCavo);
        Assert.False(telefonoA.Sessione.Terminata);
        Assert.Equal(2, pc.Elenco.Conteggio);

        // Anche B passa al cavo, per conto suo.
        var (bCavo, cavoB) = await CollegaAsync(pc, idB, "B", viaCavo: true);
        await using var _bc = bCavo;
        Assert.Equal(EsitoArrivo.CavoAlPostoDelWiFi, cavoB.Esito);
        await b.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        Assert.True(telefonoA.Sessione.ViaCavo && !telefonoA.Sessione.Terminata);
    }

    [Fact]
    public void ComandiDellaFotocameraPerTelefono()
    {
        var comandi = ComandiFotocamera.Iniziali
            .Applica(new Comando(Zoom: 3, Torcia: true, Esposizione: 0.34))
            .Applica(new Comando(Bianco: 4300))
            .Applica(new Comando(Iso: 800, Tempo: 50));
        Assert.Equal(new ComandiFotocamera(3, true, 0.34, false, 4300, true, 800, 50), comandi);
        Assert.Equal(new Comando(Zoom: 3, Torcia: true, Esposizione: 0.3, Bianco: 4300, Iso: 800, Tempo: 50), comandi.PerRicollegamento());

        // Obiettivo nuovo: lo zoom riparte da 1. ISO e tempo a 0, bianco a 0: di nuovo automatico.
        var automatico = comandi.Applica(new Comando(Obiettivo: "tele")).Applica(new Comando(Iso: 0, Tempo: 0, Bianco: 0));
        Assert.Equal(1, automatico.Zoom);
        Assert.False(automatico.Manuale);
        Assert.True(automatico.BiancoAutomatico);
        Assert.Equal(new Comando(Zoom: 1, Torcia: true, Esposizione: 0.3, Bianco: 0, Iso: 0, Tempo: 0), automatico.PerRicollegamento());
        // Gli effetti non toccano i comandi della fotocamera.
        Assert.Same(automatico, automatico.Applica(new Comando(Filtro: "cinema")));
    }

    [Theory]
    [InlineData(true, false, false, true, true)]
    [InlineData(true, false, false, false, false)]  // riquadro chiuso: il telefono può andare in pausa
    [InlineData(true, false, true, true, false)]    // finestra mini: solo il video nella webcam
    [InlineData(true, true, false, true, false)]    // ridotta a icona
    [InlineData(false, false, false, true, false)]  // nascosta accanto all'orologio
    public void AnteprimaDelTelefonoNelRiquadro(bool mostrata, bool ridotta, bool mini, bool riquadro, bool visibile) =>
        Assert.Equal(visibile, PausaIntelligente.AnteprimaAltroTelefono(mostrata, ridotta, mini, riquadro));
}
