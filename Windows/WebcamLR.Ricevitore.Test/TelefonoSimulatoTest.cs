using System.Net;
using System.Net.Sockets;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Un iPhone finto parla con il ricevitore vero sulla rete locale della macchina:
/// saluto, ping/pong, video con 30 ms di ritardo simulato, latenza, chiusura.
/// </summary>
public class TelefonoSimulatoTest
{
    private const ulong AvantiTelefono = 5_000_000; // l'orologio del telefono è avanti di 5 s
    private const ulong RitardoSimulato = 30_000;   // 30 ms tra cattura e arrivo

    private static ulong OrologioTelefono() => Orologio.Adesso() + AvantiTelefono;

    [Fact]
    public async Task SessioneCompleta()
    {
        using var ascoltatore = new Ascoltatore(IPAddress.Loopback, porta: 0);
        var sessioneCreata = new TaskCompletionSource<SessioneComputer>(TaskCreationOptions.RunContinuationsAsynchronously);
        var salutato = new TaskCompletionSource<Ciao>(TaskCreationOptions.RunContinuationsAsynchronously);
        var statisticheConLatenza = new TaskCompletionSource<Statistiche>(TaskCreationOptions.RunContinuationsAsynchronously);
        var chiusa = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var capacitaRicevute = new TaskCompletionSource<Capacita>(TaskCreationOptions.RunContinuationsAsynchronously);

        ascoltatore.NuovoTelefono += presa =>
        {
            var sessione = new SessioneComputer(presa, "PC di prova", TimeSpan.FromMilliseconds(200));
            sessione.Salutato += ciao => salutato.TrySetResult(ciao);
            // La prima stima degli orologi può essere imprecisa (avvio a freddo): come nell'uso reale,
            // la latenza si stabilizza dopo qualche ping. Si controlla la terza misura.
            var misure = 0;
            sessione.StatisticheAggiornate += s =>
            {
                if (s.LatenzaMs is not null && s.Fps > 0 && Interlocked.Increment(ref misure) >= 3) statisticheConLatenza.TrySetResult(s);
            };
            sessione.Chiusa += () => chiusa.TrySetResult();
            sessione.CapacitaRicevute += c => capacitaRicevute.TrySetResult(c);
            sessione.Avvia();
            sessioneCreata.TrySetResult(sessione);
        };

        using var telefono = new TcpClient();
        await telefono.ConnectAsync(IPAddress.Loopback, ascoltatore.Porta);
        var flusso = telefono.GetStream();
        var scrittura = new SemaphoreSlim(1, 1);
        async Task Invia(Pacchetto p)
        {
            await scrittura.WaitAsync();
            try { await flusso.WriteAsync(p.Codificato()); } finally { scrittura.Release(); }
        }

        var benvenuto = new TaskCompletionSource<Benvenuto>(TaskCreationOptions.RunContinuationsAsynchronously);
        var ultimaLatenzaSulTelefono = -1;
        var arrivederci = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var comandoRicevuto = new TaskCompletionSource<Comando>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var fine = new CancellationTokenSource(TimeSpan.FromSeconds(15));

        // Il telefono legge: risponde ai ping come fa Collegamento.swift.
        var lettura = Task.Run(async () =>
        {
            var lettore = new LettorePacchetti();
            var buffer = new byte[64 * 1024];
            while (!fine.IsCancellationRequested)
            {
                int letti;
                try { letti = await flusso.ReadAsync(buffer, fine.Token); } catch { break; }
                if (letti == 0) break;
                lettore.Aggiungi(buffer.AsSpan(0, letti));
                while (lettore.Prossimo() is { } pacchetto)
                {
                    switch (CodificaMessaggi.DaPacchetto(pacchetto))
                    {
                        case Benvenuto b: benvenuto.TrySetResult(b); break;
                        case Ping ping: await Invia(CodificaMessaggi.ComePacchetto(new Pong(ping.T, OrologioTelefono()))); break;
                        case Latenza l: ultimaLatenzaSulTelefono = l.Ms; break;
                        case Arrivederci: arrivederci.TrySetResult(); break;
                        case Comando comando: comandoRicevuto.TrySetResult(comando); break;
                    }
                }
            }
        });

        await Invia(CodificaMessaggi.ComePacchetto(new Ciao(1, "iPhone finto", Piattaforma.Iphone, "0.1")));
        Assert.Equal("PC di prova", (await benvenuto.Task.WaitAsync(fine.Token)).Nome);
        Assert.Equal("iPhone finto", (await salutato.Task.WaitAsync(fine.Token)).Nome);
        await Invia(CodificaMessaggi.ComePacchetto(new FormatoVideo(Codec.H264, 1920, 1080, 30)));

        // Video: 30 fotogrammi al secondo, ciascuno «catturato» 30 ms prima di partire.
        var video = Task.Run(async () =>
        {
            var chiave = true;
            while (!fine.IsCancellationRequested && !statisticheConLatenza.Task.IsCompleted)
            {
                var fotogramma = new FotogrammaVideo(OrologioTelefono() - RitardoSimulato, chiave, chiave, new byte[2000]);
                chiave = false;
                await Invia(fotogramma.ComePacchetto());
                await Task.Delay(33);
            }
        });

        var statistiche = await statisticheConLatenza.Task.WaitAsync(fine.Token);
        Assert.Equal(1920, statistiche.Larghezza);
        // Almeno i 30 ms simulati; il margine in alto copre l'avvio a freddo su una macchina lenta.
        Assert.InRange(statistiche.LatenzaMs!.Value, 25, 250);
        Assert.InRange(Volatile.Read(ref ultimaLatenzaSulTelefono), 25, 250);
        await video;

        // Round 4: il telefono dice cosa si può comandare, il computer manda un comando.
        await Invia(CodificaMessaggi.ComePacchetto(new Capacita(["grandangolo", "principale", "tele"], 10, true,
            IsoMinimo: 34, IsoMassimo: 3264)));
        var capacita = await capacitaRicevute.Task.WaitAsync(fine.Token);
        Assert.Equal(3, capacita.Obiettivi.Count);
        Assert.Equal((34.0, 3264.0), (capacita.IsoMinimo, capacita.IsoMassimo));
        var sessioneAttiva = await sessioneCreata.Task;
        await sessioneAttiva.ComandaAsync(new Comando(Obiettivo: "tele", Iso: 800, Tempo: 50));
        Assert.Equal(new Comando(Obiettivo: "tele", Iso: 800, Tempo: 50), await comandoRicevuto.Task.WaitAsync(fine.Token));

        // «Scollega» dal computer: il telefono riceve l'arrivederci e la sessione si chiude.
        var sessione = await sessioneCreata.Task;
        await sessione.ChiudiAsync();
        await arrivederci.Task.WaitAsync(fine.Token);
        await chiusa.Task.WaitAsync(fine.Token);
        await sessione.DisposeAsync();
        fine.Cancel();
        await lettura;
    }
}
