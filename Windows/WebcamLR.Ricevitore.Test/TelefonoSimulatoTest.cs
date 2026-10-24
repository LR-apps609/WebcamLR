using System.Net;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Un iPhone finto parla con il ricevitore vero sulla rete locale della macchina, con il protocollo 2:
/// stretta di mano, abbinamento, ping/pong, video con 30 ms di ritardo simulato, latenza, comandi, chiusura.
/// </summary>
public class TelefonoSimulatoTest
{
    private const ulong AvantiTelefono = 5_000_000; // l'orologio del telefono è avanti di 5 s
    private const ulong RitardoSimulato = 30_000;   // 30 ms tra cattura e arrivo

    private static ulong OrologioTelefono() => Orologio.Adesso() + AvantiTelefono;

    /// <summary>Un ricevitore in ascolto su loopback, con le sessioni create come fa la finestra.</summary>
    private sealed class Ricevitore : IDisposable
    {
        public readonly Ascoltatore Ascoltatore = new(IPAddress.Loopback, porta: 0);
        public readonly TaskCompletionSource<SessioneComputer> Sessione = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource<Ciao> Salutato = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource Chiusa = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly Abbinamento Abbinamento;

        public Ricevitore(Abbinamento abbinamento, Action<SessioneComputer>? prepara = null)
        {
            Abbinamento = abbinamento;
            Ascoltatore.NuovoTelefono += presa =>
            {
                var sessione = new SessioneComputer(presa, "PC di prova", abbinamento, TimeSpan.FromMilliseconds(200));
                sessione.Salutato += ciao => Salutato.TrySetResult(ciao);
                sessione.Chiusa += () => Chiusa.TrySetResult();
                prepara?.Invoke(sessione);
                sessione.Avvia();
                Sessione.TrySetResult(sessione);
            };
        }

        public void Dispose() => Ascoltatore.Dispose();
    }

    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(15);

    [Fact]
    public async Task SessioneCompletaConIlQRCode()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer);
        var statisticheConLatenza = new TaskCompletionSource<Statistiche>(TaskCreationOptions.RunContinuationsAsynchronously);
        var capacitaRicevute = new TaskCompletionSource<Capacita>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var ricevitore = new Ricevitore(abbinamento, sessione =>
        {
            // La prima stima degli orologi può essere imprecisa (avvio a freddo): si controlla la terza misura.
            var misure = 0;
            sessione.StatisticheAggiornate += s =>
            {
                if (s.LatenzaMs is not null && s.Fps > 0 && Interlocked.Increment(ref misure) >= 3) statisticheConLatenza.TrySetResult(s);
            };
            sessione.CapacitaRicevute += c => capacitaRicevute.TrySetResult(c);
        });

        await using var telefono = new TelefonoFinto(orologio: OrologioTelefono);
        var gettoneDelQR = abbinamento.Gettone;
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta, gettone: gettoneDelQR);

        // Con il gettone del QR code: niente conferma, e il telefono diventa fidato.
        Assert.Equal("PC di prova", (await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite)).Nome);
        Assert.Equal("iPhone finto", (await ricevitore.Salutato.Task.WaitAsync(Limite)).Nome);
        Assert.Equal(idComputer.Impronta, telefono.ImprontaComputer);
        Assert.True(abbinamento.Fidato(telefono.Identita.Impronta));
        Assert.NotEqual(gettoneDelQR, abbinamento.Gettone);

        await telefono.InviaAsync(new FormatoVideo(Codec.H264, 1920, 1080, 30));
        using var fineVideo = new CancellationTokenSource(Limite);
        var video = Task.Run(async () =>
        {
            var chiave = true;
            while (!fineVideo.IsCancellationRequested && !statisticheConLatenza.Task.IsCompleted)
            {
                await telefono.InviaAsync(new FotogrammaVideo(OrologioTelefono() - RitardoSimulato, chiave, chiave, new byte[2000]).ComePacchetto());
                chiave = false;
                await Task.Delay(33);
            }
        });

        var statistiche = await statisticheConLatenza.Task.WaitAsync(Limite);
        Assert.Equal(1920, statistiche.Larghezza);
        // Almeno i 30 ms simulati; il margine in alto copre l'avvio a freddo su una macchina lenta.
        Assert.InRange(statistiche.LatenzaMs!.Value, 25, 250);
        // Sul telefono conta l'ultima latenza: le prime, prima che gli orologi si allineino, si scartano.
        while (telefono.Ricevuti.Reader.TryRead(out _)) { }
        Assert.InRange((await telefono.AttendiAsync<Latenza>().WaitAsync(Limite)).Ms, 25, 250);
        await video;

        // Avvio misurato (1.11): le tappe dall'accettazione al primo fotogramma, in ordine; «a schermo» lo segna la finestra.
        var avviata = await ricevitore.Sessione.Task;
        Assert.Null(avviata.Avvio.Riga);
        Assert.True(avviata.Avvio.Mostrato());
        Assert.Matches(@"^Avvio: \d+,\d s \(stretta di mano \d+ ms · benvenuto \d+ ms · primo fotogramma \d+ ms · a schermo \d+ ms\)$",
            avviata.Avvio.Riga);
        Assert.InRange(avviata.Avvio.Totale!.Value, TimeSpan.Zero, Limite);

        // Il telefono dice cosa si può comandare, il computer manda un comando.
        await telefono.InviaAsync(new Capacita(["grandangolo", "principale", "tele"], 10, true, IsoMinimo: 34, IsoMassimo: 3264));
        var capacita = await capacitaRicevute.Task.WaitAsync(Limite);
        Assert.Equal((34.0, 3264.0), (capacita.IsoMinimo, capacita.IsoMassimo));
        var sessione = await ricevitore.Sessione.Task;
        await sessione.ComandaAsync(new Comando(Obiettivo: "tele", Iso: 800, Tempo: 50));
        Assert.Equal(new Comando(Obiettivo: "tele", Iso: 800, Tempo: 50), await telefono.AttendiAsync<Comando>().WaitAsync(Limite));

        // Un'app usa la webcam: il telefono riceve «in-onda» e mostra il rosso.
        await sessione.SegnalaAsync(new InOnda(true));
        Assert.Equal(new InOnda(true), await telefono.AttendiAsync<InOnda>().WaitAsync(Limite));

        // «Scollega» dal computer: il telefono riceve l'arrivederci e la sessione si chiude.
        await sessione.ChiudiAsync();
        await telefono.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        await ricevitore.Chiusa.Task.WaitAsync(Limite);
        await sessione.DisposeAsync();
    }

    [Fact]
    public async Task TelefonoNuovoConfermatoConLoStessoCodice()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        var salvati = new List<IReadOnlyDictionary<string, string>>();
        var abbinamento = new Abbinamento(idComputer, salva: salvati.Add);
        string? codiceSulComputer = null;
        abbinamento.ChiediConferma = (nome, codice, _) =>
        {
            Assert.Equal("iPhone di Ledion", nome);
            codiceSulComputer = codice;
            return Task.FromResult(true);
        };
        using var ricevitore = new Ricevitore(abbinamento);

        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta, "iPhone di Ledion");
        var approvazione = await telefono.AttendiAsync<Approvazione>().WaitAsync(Limite);
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);

        // Lo stesso codice sui due schermi.
        Assert.Equal(telefono.CodiceVisto, approvazione.Codice);
        Assert.Equal(telefono.CodiceVisto, codiceSulComputer);
        Assert.Equal("iPhone di Ledion", Assert.Single(salvati)[telefono.Identita.Impronta]);
    }

    [Fact]
    public async Task TelefonoFidatoNonChiedeConferma()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idTelefono = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer, new Dictionary<string, string> { [idTelefono.Impronta] = "iPhone" });
        abbinamento.ChiediConferma = (_, _, _) => throw new InvalidOperationException("Non doveva chiedere");
        using var ricevitore = new Ricevitore(abbinamento);

        await using var telefono = new TelefonoFinto(idTelefono);
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta);
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);
    }

    /// <summary>
    /// 1.12: il PC si riavvia (o l'app si chiude e si riapre) e il telefono già abbinato rientra da solo, senza
    /// domande: la chiave del PC e i telefoni fidati si rileggono da ciò che era stato salvato.
    /// </summary>
    [Fact]
    public async Task DopoIlRiavvioDelComputerIlTelefonoFidatoEntraSenzaDomande()
    {
        using var idTelefono = IdentitaDispositivo.Nuova();
        byte[] chiaveSalvata;
        IReadOnlyDictionary<string, string> fidatiSalvati = new Dictionary<string, string>();
        string improntaPrimaVolta;

        // Prima apertura dell'app: abbinamento con il QR code.
        using (var idComputer = IdentitaDispositivo.Nuova())
        {
            chiaveSalvata = idComputer.EsportaPkcs8();
            var abbinamento = new Abbinamento(idComputer, salva: fidati => fidatiSalvati = fidati);
            using var ricevitore = new Ricevitore(abbinamento);
            await using var telefono = new TelefonoFinto(idTelefono);
            await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta, gettone: abbinamento.Gettone);
            await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);
            improntaPrimaVolta = telefono.ImprontaComputer!;
        }

        // L'app riparte: stessa chiave, stessi fidati, gettone nuovo; nessuna domanda all'utente.
        using var ricaricata = IdentitaDispositivo.DaPkcs8(chiaveSalvata);
        var dopo = new Abbinamento(ricaricata, fidatiSalvati)
        {
            ChiediConferma = (_, _, _) => throw new InvalidOperationException("Non doveva chiedere"),
        };
        using var riavviato = new Ricevitore(dopo);
        await using var tornato = new TelefonoFinto(idTelefono);
        await tornato.CollegaAsync(riavviato.Ascoltatore.Porta);
        await tornato.AttendiAsync<Benvenuto>().WaitAsync(Limite);
        // Il telefono riconosce lo stesso computer: niente «L'identità di … è cambiata».
        Assert.Equal(improntaPrimaVolta, tornato.ImprontaComputer);
    }

    [Fact]
    public async Task TelefonoRifiutatoRiceveArrivederci()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer) { ChiediConferma = (_, _, _) => Task.FromResult(false) };
        using var ricevitore = new Ricevitore(abbinamento);

        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta, gettone: "gettone-sbagliato");
        await telefono.AttendiAsync<Arrivederci>().WaitAsync(Limite);
        await ricevitore.Chiusa.Task.WaitAsync(Limite);
        Assert.False(ricevitore.Salutato.Task.IsCompleted);
        Assert.Empty(abbinamento.Fidati);
    }

    [Fact]
    public async Task TelefonoDelProtocollo1VieneChiuso()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var ricevitore = new Ricevitore(new Abbinamento(idComputer));

        await using var telefono = new TelefonoFinto();
        await telefono.CollegaSenzaSicurezzaAsync(ricevitore.Ascoltatore.Porta);
        await ricevitore.Chiusa.Task.WaitAsync(Limite);
        await telefono.Chiuso.Task.WaitAsync(Limite);
        Assert.False(ricevitore.Salutato.Task.IsCompleted);
    }

    [Fact]
    public async Task MessaggioIllegibileChiudeSubito()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        using var idTelefono = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer, new Dictionary<string, string> { [idTelefono.Impronta] = "iPhone" });
        using var ricevitore = new Ricevitore(abbinamento);

        await using var telefono = new TelefonoFinto(idTelefono);
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta);
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);

        // Uno «stato» con la batteria scritta come testo: il JSON non si decodifica.
        var json = System.Text.Encoding.UTF8.GetBytes("{\"tipo\":\"stato\",\"batteria\":\"tanta\"}");
        await telefono.InviaAsync(new Pacchetto(TipoPacchetto.Controllo, 0, json));

        // Si chiude subito, non dopo i 10 secondi di silenzio.
        await ricevitore.Chiusa.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await telefono.Chiuso.Task.WaitAsync(Limite);
    }

    [Fact]
    public async Task SecondoCiaoNonApreUnAltraDomanda()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        var domande = 0;
        var risposta = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var abbinamento = new Abbinamento(idComputer)
        {
            ChiediConferma = (_, _, _) =>
            {
                Interlocked.Increment(ref domande);
                return risposta.Task;
            },
        };
        using var ricevitore = new Ricevitore(abbinamento);

        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta);
        await telefono.AttendiAsync<Approvazione>().WaitAsync(Limite);
        await telefono.InviaAsync(new Ciao(Servizio.VersioneProtocollo, "iPhone finto", Piattaforma.Iphone, "0.10"));
        await Task.Delay(300);

        risposta.SetResult(true);
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);
        Assert.Equal(1, Volatile.Read(ref domande));
    }
}
