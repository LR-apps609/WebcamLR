using System.Diagnostics;
using System.Net;
using System.Threading.Channels;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Qualità 18 (Protocollo.md, «Pausa automatica»): la regola dei tempi con un orologio finto, poi un telefono simulato
/// su loopback che si comporta come l'iPhone e l'Android: nessuna app, pausa, un'app apre la webcam, ripresa da un
/// fotogramma chiave.
/// </summary>
public class PausaAutomaticaTest
{
    private static readonly TimeSpan Limite = TimeSpan.FromSeconds(15);
    private static readonly long AttesaMs = (long)RegolaPausaAutomatica.Attesa.TotalMilliseconds;

    private static UsoVideo Uso(bool interruttore = true, bool saLeggere = true, bool webcam = false, bool registra = false,
        bool guardata = false) => new(interruttore, saLeggere, webcam, registra, guardata);

    // MARK: la regola, a tempi finti

    [Fact]
    public void DopoVentiSecondiSenzaAppLaPausa()
    {
        Assert.Equal(20, Servizio.SecondiPausaAutomatica);
        var regola = new RegolaPausaAutomatica();
        Assert.False(regola.Valuta(Uso(), 1_000));
        Assert.Equal(TimeSpan.FromSeconds(20), regola.MancaAllaPausa(1_000));
        Assert.False(regola.Valuta(Uso(), 1_000 + AttesaMs - 1));
        Assert.Equal(RegolaPausaAutomatica.ControlloNormale, regola.Controllo);
        Assert.True(regola.Valuta(Uso(), 1_000 + AttesaMs));
        Assert.True(regola.Pausa);
        Assert.Null(regola.MancaAllaPausa(1_000 + AttesaMs));
        // In pausa si controlla l'uso della webcam più spesso: la ripresa sta sotto il secondo.
        Assert.Equal(RegolaPausaAutomatica.ControlloRapido, regola.Controllo);
        Assert.True(regola.Valuta(Uso(), 1_000 + 10 * AttesaMs));
    }

    [Fact]
    public void UnAppCheApreLaWebcamTogliePausaSubitoEIlContoRiparte()
    {
        var regola = new RegolaPausaAutomatica();
        regola.Valuta(Uso(), 0);
        Assert.True(regola.Valuta(Uso(), AttesaMs));
        Assert.False(regola.Valuta(Uso(webcam: true), AttesaMs + 10));
        Assert.Equal(RegolaPausaAutomatica.ControlloNormale, regola.Controllo);
        // L'app chiude: altri 20 secondi interi prima della pausa, non subito.
        Assert.False(regola.Valuta(Uso(), AttesaMs + 5_000));
        Assert.False(regola.Valuta(Uso(), 2 * AttesaMs + 4_999));
        Assert.True(regola.Valuta(Uso(), 2 * AttesaMs + 5_000));
    }

    [Theory]
    [InlineData(false, true, false, false, false)] // interruttore spento
    [InlineData(true, false, false, false, false)] // uso non leggibile (Mac con l'Apple ID gratuito, webcam non installata)
    [InlineData(true, true, true, false, false)]   // un'app usa la webcam
    [InlineData(true, true, false, true, false)]   // si registra
    [InlineData(true, true, false, false, true)]   // la finestra è in primo piano, o c'è la mini
    public void QuandoIlVideoServeMaiPausa(bool interruttore, bool saLeggere, bool webcam, bool registra, bool guardata)
    {
        var uso = Uso(interruttore, saLeggere, webcam, registra, guardata);
        Assert.True(uso.Serve);
        var regola = new RegolaPausaAutomatica();
        for (long t = 0; t <= 10 * AttesaMs; t += 1_000) Assert.False(regola.Valuta(uso, t));
        Assert.Null(regola.MancaAllaPausa(10 * AttesaMs));
    }

    [Fact]
    public void SenzaLetturaDellUsoLaFunzioneRestaSpenta()
    {
        Assert.False(Uso(saLeggere: false).Possibile);
        Assert.False(Uso(interruttore: false).Possibile);
        Assert.True(Uso().Possibile);
        Assert.False(Uso().Serve);
    }

    [Fact]
    public void UnTelefonoNuovoFaRipartireIlConto()
    {
        var regola = new RegolaPausaAutomatica();
        regola.Valuta(Uso(), 0);
        Assert.True(regola.Valuta(Uso(), AttesaMs));
        regola.Riparti(AttesaMs + 100);
        Assert.False(regola.Pausa);
        Assert.False(regola.Valuta(Uso(), AttesaMs + 200));
        Assert.False(regola.Valuta(Uso(), 2 * AttesaMs + 99));
        Assert.True(regola.Valuta(Uso(), 2 * AttesaMs + 100));
        // Senza conto in corso (il video serve) Riparti non inventa nulla.
        regola.Valuta(Uso(webcam: true), 3 * AttesaMs);
        regola.Riparti(3 * AttesaMs);
        Assert.Null(regola.InutileDalMs);
    }

    [Fact]
    public void LOrologioCheTornaIndietroNonFaScattareLaPausa()
    {
        var regola = new RegolaPausaAutomatica();
        regola.Valuta(Uso(), 50_000);
        Assert.False(regola.Valuta(Uso(), 10_000));
        Assert.False(regola.Valuta(Uso(), 10_000 + AttesaMs - 1));
        Assert.True(regola.Valuta(Uso(), 10_000 + AttesaMs));
    }

    // MARK: con il telefono simulato

    /// <summary>Un ricevitore su loopback con una sessione, come la crea la finestra.</summary>
    private sealed class Ricevitore : IDisposable
    {
        public readonly Ascoltatore Ascoltatore = new(IPAddress.Loopback, porta: 0);
        public readonly TaskCompletionSource<SessioneComputer> Sessione = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly Channel<StatoTelefono> Stati = Channel.CreateUnbounded<StatoTelefono>();
        public readonly Channel<FotogrammaVideo> Fotogrammi = Channel.CreateUnbounded<FotogrammaVideo>();

        public Ricevitore(Abbinamento abbinamento, Action<SessioneComputer>? prepara = null)
        {
            Ascoltatore.NuovoTelefono += presa =>
            {
                var sessione = new SessioneComputer(presa, "PC di prova", abbinamento, TimeSpan.FromMilliseconds(200));
                sessione.StatoRicevuto += stato => Stati.Writer.TryWrite(stato);
                sessione.FotogrammaRicevuto += fotogramma => Fotogrammi.Writer.TryWrite(fotogramma);
                prepara?.Invoke(sessione);
                sessione.Avvia();
                Sessione.TrySetResult(sessione);
            };
        }

        public void Dispose() => Ascoltatore.Dispose();

        /// <summary>Butta i fotogrammi arrivati fin qui.</summary>
        public void SvuotaFotogrammi()
        {
            while (Fotogrammi.Reader.TryRead(out _)) { }
        }
    }

    /// <summary>
    /// Il telefono come SessioneTelefono (iPhone e Android): a «pausa-automatica» vera manda «stato» con la pausa
    /// «nessuna-app» e smette il video; a falsa manda «stato» senza pausa e riprende da un fotogramma chiave (o, con
    /// <paramref name="riprendeConChiave"/> falso, da un fotogramma qualsiasi, per vedere il computer chiederla).
    /// </summary>
    private sealed class TelefonoSimulato : IAsyncDisposable
    {
        private readonly TelefonoFinto telefono;
        private readonly bool riprendeConChiave;
        private readonly CancellationTokenSource fine = new();
        private readonly Task lettura;
        private readonly Task video;
        private int inPausa;
        private int prossimoChiave = 1;

        public readonly Channel<bool> Richieste = Channel.CreateUnbounded<bool>();
        public int ChiaviChieste;

        public TelefonoSimulato(TelefonoFinto telefono, bool riprendeConChiave = true)
        {
            this.telefono = telefono;
            this.riprendeConChiave = riprendeConChiave;
            lettura = Task.Run(LeggiAsync);
            video = Task.Run(MandaVideoAsync);
        }

        public bool InPausa => Volatile.Read(ref inPausa) == 1;

        private static StatoTelefono Stato(string? pausa) => new(80, false, Temperatura.Normale, "frontale", Pausa: pausa);

        private async Task LeggiAsync()
        {
            try
            {
                while (true)
                {
                    var messaggio = await telefono.Ricevuti.Reader.ReadAsync(fine.Token);
                    switch (messaggio)
                    {
                        case PausaAutomatica richiesta:
                            Richieste.Writer.TryWrite(richiesta.Attiva);
                            if (richiesta.Attiva && !InPausa)
                            {
                                // Prima si ferma il video, poi si dice perché (come pausaCambiata).
                                Volatile.Write(ref inPausa, 1);
                                await telefono.InviaAsync(Stato(MotiviPausa.NessunaApp));
                            }
                            else if (!richiesta.Attiva && InPausa)
                            {
                                // Protocollo: prima lo «stato» senza pausa, poi il video da un fotogramma chiave.
                                await telefono.InviaAsync(Stato(null));
                                Volatile.Write(ref prossimoChiave, riprendeConChiave ? 1 : 0);
                                Volatile.Write(ref inPausa, 0);
                            }
                            break;
                        case ChiediChiave:
                            Interlocked.Increment(ref ChiaviChieste);
                            Volatile.Write(ref prossimoChiave, 1);
                            break;
                    }
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception) when (fine.IsCancellationRequested) { }
        }

        private async Task MandaVideoAsync()
        {
            try
            {
                await telefono.InviaAsync(new FormatoVideo(Codec.H264, 1280, 720, 30));
                while (!fine.IsCancellationRequested)
                {
                    if (!InPausa)
                    {
                        var chiave = Interlocked.Exchange(ref prossimoChiave, 0) == 1;
                        await telefono.InviaAsync(new FotogrammaVideo(Orologio.Adesso(), chiave, chiave, new byte[400]).ComePacchetto());
                    }
                    await Task.Delay(33, fine.Token);
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception) when (fine.IsCancellationRequested) { }
        }

        public async ValueTask DisposeAsync()
        {
            fine.Cancel();
            await Task.WhenAll(lettura, video);
        }
    }

    /// <summary>La finestra del computer: a ogni controllo la regola decide e la sessione manda solo i cambiamenti.</summary>
    private static Task ControllaAsync(RegolaPausaAutomatica regola, SessioneComputer sessione, UsoVideo uso, long adessoMs) =>
        sessione.SegnalaPausaAutomaticaAsync(regola.Valuta(uso, adessoMs));

    private static async Task<StatoTelefono> ProssimoStatoAsync(Ricevitore ricevitore) =>
        await ricevitore.Stati.Reader.ReadAsync().AsTask().WaitAsync(Limite);

    private static async Task<FotogrammaVideo> ProssimoFotogrammaAsync(Ricevitore ricevitore) =>
        await ricevitore.Fotogrammi.Reader.ReadAsync().AsTask().WaitAsync(Limite);

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task NessunaAppPausaPoiUnAppApreERiprendeDaUnFotogrammaChiave(bool riprendeConChiave)
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer);
        using var ricevitore = new Ricevitore(abbinamento);
        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta, gettone: abbinamento.Gettone);
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);
        var sessione = await ricevitore.Sessione.Task.WaitAsync(Limite);
        await using var simulato = new TelefonoSimulato(telefono, riprendeConChiave);

        // Subito dopo il benvenuto il computer dice sempre il suo valore: niente pausa.
        Assert.False(await simulato.Richieste.Reader.ReadAsync().AsTask().WaitAsync(Limite));
        Assert.True((await ProssimoFotogrammaAsync(ricevitore)).Chiave);

        // Nessuna app usa la webcam e nessuno guarda la finestra: per 20 secondi (finti) il video continua.
        var regola = new RegolaPausaAutomatica();
        long adesso = 100_000;
        for (var t = 0L; t < AttesaMs; t += 1_000) await ControllaAsync(regola, sessione, Uso(), adesso + t);
        Assert.False(sessione.PausaAutomaticaInviata);
        Assert.False(simulato.InPausa);
        await ProssimoFotogrammaAsync(ricevitore);

        // Al ventesimo secondo la pausa: il telefono la riceve una volta sola e lo dice nello stato.
        await ControllaAsync(regola, sessione, Uso(), adesso + AttesaMs);
        await ControllaAsync(regola, sessione, Uso(), adesso + AttesaMs + 250);
        Assert.True(await simulato.Richieste.Reader.ReadAsync().AsTask().WaitAsync(Limite));
        Assert.Equal(MotiviPausa.NessunaApp, (await ProssimoStatoAsync(ricevitore)).Pausa);
        Assert.True(sessione.PausaAutomaticaInviata);
        Assert.Equal(RegolaPausaAutomatica.ControlloRapido, regola.Controllo);
        // In pausa niente video, ma il collegamento resta vivo (ping e pong vanno avanti).
        await Task.Delay(150);
        ricevitore.SvuotaFotogrammi();
        await Task.Delay(400);
        Assert.False(ricevitore.Fotogrammi.Reader.TryRead(out _));
        Assert.False(sessione.Terminata);
        Assert.False(simulato.Richieste.Reader.TryRead(out _));

        // Un'app apre la webcam: al primo controllo la pausa finisce, e il video torna in meno di un secondo.
        var orologio = Stopwatch.StartNew();
        await ControllaAsync(regola, sessione, Uso(webcam: true), adesso + AttesaMs + 500);
        Assert.False(await simulato.Richieste.Reader.ReadAsync().AsTask().WaitAsync(Limite));
        Assert.Null((await ProssimoStatoAsync(ricevitore)).Pausa);
        var primo = await ProssimoFotogrammaAsync(ricevitore);
        if (riprendeConChiave)
        {
            Assert.True(primo.Chiave);
        }
        else
        {
            // Il primo dopo la pausa non è chiave: il computer la chiede subito, e arriva.
            Assert.False(primo.Chiave);
            while (!(await ProssimoFotogrammaAsync(ricevitore)).Chiave) { }
            Assert.Equal(1, Volatile.Read(ref simulato.ChiaviChieste));
        }
        Assert.True(orologio.Elapsed < TimeSpan.FromSeconds(1), $"Ripresa in {orologio.ElapsedMilliseconds} ms");
        Assert.False(sessione.PausaAutomaticaInviata);
        if (riprendeConChiave)
        {
            // Partito da una chiave: il computer non ne chiede altre.
            await Task.Delay(300);
            Assert.Equal(0, Volatile.Read(ref simulato.ChiaviChieste));
        }
    }

    /// <summary>
    /// Passaggio dal Wi-Fi al cavo, o finestra che ha già deciso prima del benvenuto: il valore impostato parte subito
    /// dopo il benvenuto, e la ripresa arriva anche se la sessione nuova non ha mai mandato la pausa.
    /// </summary>
    [Fact]
    public async Task IlValoreDellaPausaParteSubitoDopoIlBenvenuto()
    {
        using var idComputer = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer);
        using var ricevitore = new Ricevitore(abbinamento, sessione => sessione.PausaAutomaticaChiesta = true);
        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(ricevitore.Ascoltatore.Porta, gettone: abbinamento.Gettone);
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(Limite);
        Assert.True((await telefono.AttendiAsync<PausaAutomatica>().WaitAsync(Limite)).Attiva);
        var sessione = await ricevitore.Sessione.Task.WaitAsync(Limite);
        Assert.True(sessione.PausaAutomaticaInviata);
        // Lo stesso valore non riparte.
        await sessione.SegnalaPausaAutomaticaAsync(true);
        await sessione.SegnalaPausaAutomaticaAsync(false);
        await sessione.SegnalaPausaAutomaticaAsync(false);
        Assert.False((await telefono.AttendiAsync<PausaAutomatica>().WaitAsync(Limite)).Attiva);
        await Task.Delay(200);
        while (telefono.Ricevuti.Reader.TryRead(out var messaggio)) Assert.IsNotType<PausaAutomatica>(messaggio);
    }
}
