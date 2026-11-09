using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using WebcamLR.Protocollo;
using Xunit;
using Xunit.Abstractions;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// La prova di durata misura memoria, timer e maniglie di tutto il processo: gira da sola, dopo le altre.
/// </summary>
[CollectionDefinition(Nome, DisableParallelization = true)]
public sealed class CollezioneProvaDurata
{
    public const string Nome = "Prova di durata";
}

/// <summary>La prova lunga gira solo con <c>WEBCAMLR_PROVA_LUNGA=1</c>; altrimenti risulta saltata.</summary>
public sealed class ProvaLungaAttribute : FactAttribute
{
    public const string Variabile = "WEBCAMLR_PROVA_LUNGA";

    public ProvaLungaAttribute()
    {
        if (Environment.GetEnvironmentVariable(Variabile) != "1")
            Skip = $"Prova lunga: si lancia con {Variabile}=1 (vedi Documenti/Windows - installazione e prova.md).";
    }
}

/// <summary>
/// Qualità 20 · prova di durata del ricevitore: un telefono simulato su loopback parla con il ricevitore vero
/// (Ascoltatore, SessioneComputer, ElencoTelefoni, MicrofonoTelefono, collegati come fa la finestra) per una sessione
/// lunga: video a 30 fps con fotogrammi chiave ogni 2 s (20–60 kB), audio AAC finto ogni 1024 campioni, stato ogni 5 s,
/// ping/pong e latenza ogni secondo, cambi di formato (metà senza fotogramma chiave: il computer deve chiederlo),
/// cadute di rete improvvise e silenzi del telefono (chiusi dal ricevitore dopo 10 s), con lo stesso telefono che torna.
/// Il tempo della sessione è accelerato: il ricevitore fa ping e statistiche ogni secondo simulato
/// (<c>intervallo</c> = 1 s / accelerazione) e il telefono manda quello che manderebbe in quel secondo; ritardi e latenze
/// restano reali. Si verifica: nessuna caduta non voluta, fotogrammi in ordine e tutti consegnati (solo una caduta
/// improvvisa può perdere la coda in volo), memoria gestita, timer, maniglie e sessioni vecchie che non restano,
/// latenza che non cresce, nessuna eccezione non osservata.
/// </summary>
[Collection(CollezioneProvaDurata.Nome)]
public class ProvaDurataTest(ITestOutputHelper uscita)
{
    /// <summary>L'orologio del telefono è avanti di 5 s rispetto al computer, come in TelefonoSimulatoTest.</summary>
    private const ulong AvantiTelefono = 5_000_000;
    private const int Fps = 30;
    /// <summary>Un fotogramma chiave ogni 2 secondi, come l'encoder del telefono.</summary>
    private const int OgniChiave = 60;
    /// <summary>Un frame AAC: 1024 campioni a 48 kHz.</summary>
    private const double PacchettiAudioAlSecondo = 48_000 / 1024.0;

    /// <summary>
    /// Cosa succede nella sessione simulata: durata e accelerazione, e ogni quanti secondi simulati gli eventi.
    /// Cambi di formato, cadute e silenzi cadono in momenti diversi.
    /// </summary>
    public sealed record Copione(TimeSpan Durata, double Accelerazione)
    {
        public double SecondiStato { get; init; } = 5;
        public double SecondiFormato { get; init; } = 150;
        public double SecondiCaduta { get; init; } = 210;
        /// <summary>Un silenzio ogni tanto: uno breve (4 s, poi il telefono riprende), uno lungo (chiuso dopo 10 s), e così via.</summary>
        public double SecondiSilenzio { get; init; } = 330;
        public double PrimoSilenzio { get; init; } = 165;
        /// <summary>
        /// La rete cade senza chiusura e il telefono torna con una connessione nuova prima che il ricevitore se ne accorga:
        /// la sessione nuova prende il posto di quella vecchia, che il computer chiude.
        /// </summary>
        public double SecondiSostituzione { get; init; } = 270;
        /// <summary>Quanto il telefono resta fuori dopo una caduta prima di ricollegarsi (secondi simulati).</summary>
        public double SecondiFuori { get; init; } = 2;
    }

    /// <summary>
    /// La prova di ogni giorno: 10 minuti di sessione in circa 15 secondi (accelerazione 40), con tre cambi di formato,
    /// due cadute improvvise, un silenzio breve e uno lungo, due ritorni prima che la sessione vecchia sia chiusa.
    /// </summary>
    [Fact]
    public async Task DieciMinutiDiSessioneAccelerati()
    {
        var esito = await EseguiAsync(new Copione(TimeSpan.FromMinutes(10), Accelerazione: 40));
        Assert.InRange(esito.Reale, TimeSpan.Zero, TimeSpan.FromSeconds(40));
    }

    /// <summary>
    /// La prova lunga: un'ora di sessione. Accelerata (40) di serie, in un paio di minuti; con
    /// <c>WEBCAMLR_PROVA_LUNGA_ACCELERAZIONE=1</c> un'ora vera, con ping e statistiche ogni secondo come nella finestra.
    /// </summary>
    [ProvaLunga]
    [Trait("Categoria", "ProvaLunga")]
    public async Task UnOraDiSessione()
    {
        var accelerazione = double.TryParse(Environment.GetEnvironmentVariable("WEBCAMLR_PROVA_LUNGA_ACCELERAZIONE"),
            System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var scelta) && scelta >= 1
            ? scelta : 40;
        var minuti = int.TryParse(Environment.GetEnvironmentVariable("WEBCAMLR_PROVA_LUNGA_MINUTI"), out var m) && m > 0 ? m : 60;
        await EseguiAsync(new Copione(TimeSpan.FromMinutes(minuti), accelerazione));
    }

    // MARK: il computer

    /// <summary>Quello che il ricevitore vede di una sessione: fotogrammi in ordine, chiavi, chiusura.</summary>
    private sealed class Tracciato(SessioneComputer sessione, int numero)
    {
        public readonly WeakReference<SessioneComputer> Sessione = new(sessione);
        public readonly int Numero = numero;
        public long Primo = -1;
        public long Ultimo = -1;
        public long Fotogrammi;
        public long FuoriOrdine;
        public long ChiaveSbagliata;
        public ulong UltimoTimestamp;
        public long TimestampIndietro;
        /// <summary>Come un decodificatore: dopo l'inizio o un formato nuovo serve un fotogramma chiave.</summary>
        public bool HaChiave;
        public long SenzaChiave;
        public long Audio;
        public long AudioFuoriOrdine;
        public long UltimoAudio = -1;
        public long Stati;
        public long Formati;
        public long Statistiche;
        public int Silenzi;
        public int Riprese;
        public volatile bool Chiusa;
        public bool ChiusaDalComputer;
        public bool ChiusaDalTelefono;
        /// <summary>Al momento della chiusura il telefono stava facendo una caduta o un silenzio voluti.</summary>
        public bool Voluta;
    }

    /// <summary>
    /// Il PC: ascolto su loopback, elenco dei telefoni e microfono, collegati come in MainWindow.Telefoni.cs.
    /// Le misure vanno in tabelle già pronte (per minuto simulato), così la prova stessa non fa crescere la memoria.
    /// </summary>
    private sealed class Computer : IDisposable
    {
        public readonly Ascoltatore Ascoltatore = new(IPAddress.Loopback, porta: 0);
        public readonly ElencoTelefoni Elenco = new();
        public readonly Abbinamento Abbinamento;
        public readonly MicrofonoTelefono Microfono = new(_ => new DecodificatoreFinto());
        public readonly ConcurrentQueue<Tracciato> Tracciati = new();
        public readonly ConcurrentQueue<EsitoArrivo> Esiti = new();
        public readonly TimeSpan Intervallo;
        private readonly Func<ulong> orologioSilenzio;
        private int sessioni;

        /// <summary>Latenze per minuto simulato, a gruppi di 5 ms (l'ultimo raccoglie da 1 s in su).</summary>
        public readonly int[,] Latenze;
        public const int Gruppi = 200;
        public long StatisticheSenzaLatenza;
        public long TroppiFotogrammiNelSecondo;
        public int NonVolute;
        public volatile bool CadutaInCorso;
        public volatile int MinutoAttuale;
        public Tracciato? Attuale => Volatile.Read(ref attuale);
        private Tracciato? attuale;

        public Computer(Abbinamento abbinamento, Copione copione, Func<ulong> orologioSilenzio)
        {
            Abbinamento = abbinamento;
            this.orologioSilenzio = orologioSilenzio;
            Intervallo = TimeSpan.FromSeconds(1 / copione.Accelerazione);
            Latenze = new int[(int)Math.Ceiling(copione.Durata.TotalMinutes) + 2, Gruppi];
            Ascoltatore.NuovoTelefono += Accetta;
        }

        private void Accetta(Socket presa)
        {
            var nuova = new SessioneComputer(presa, "PC di prova", Abbinamento, Intervallo)
            {
                Collegamento = TipoCollegamento.WiFi,
                Ammetti = Elenco.PuoEntrare,
                OrologioSilenzio = orologioSilenzio,
            };
            var tracciato = new Tracciato(nuova, Interlocked.Increment(ref sessioni));
            Tracciati.Enqueue(tracciato);
            nuova.Salutato += ciao =>
            {
                var arrivo = Elenco.Accogli(nuova, ciao);
                Esiti.Enqueue(arrivo.Esito);
                if (arrivo.DaChiudere is { } daChiudere) _ = ChiudiAsync(daChiudere);
                Volatile.Write(ref attuale, tracciato);
            };
            nuova.FormatoRicevuto += formato =>
            {
                if (Elenco.Di(nuova) is { } telefono) telefono.Formato = formato;
                tracciato.Formati++;
                tracciato.HaChiave = false;
            };
            nuova.FotogrammaRicevuto += fotogramma =>
            {
                // I primi 8 byte sono il numero del fotogramma, il nono dice se il telefono l'ha mandato come chiave.
                var numero = BinaryPrimitives.ReadInt64BigEndian(fotogramma.Dati);
                if (tracciato.Primo < 0) tracciato.Primo = numero;
                else if (numero != tracciato.Ultimo + 1) tracciato.FuoriOrdine++;
                tracciato.Ultimo = numero;
                tracciato.Fotogrammi++;
                if (fotogramma.Chiave != (fotogramma.Dati[8] == 1)) tracciato.ChiaveSbagliata++;
                if (fotogramma.Timestamp < tracciato.UltimoTimestamp) tracciato.TimestampIndietro++;
                tracciato.UltimoTimestamp = fotogramma.Timestamp;
                if (fotogramma.Chiave) tracciato.HaChiave = true;
                else if (!tracciato.HaChiave) tracciato.SenzaChiave++;
            };
            nuova.StatoRicevuto += stato =>
            {
                tracciato.Stati++;
                if (Elenco.Di(nuova) is not { } telefono) return;
                telefono.AggiornaStato(stato);
                telefono.Avvisi.Aggiorna(stato);
                telefono.AggiornaStrade(stato, Elenco.Orologio());
            };
            nuova.CapacitaRicevute += capacita => { if (Elenco.Di(nuova) is { } telefono) telefono.Capacita = capacita; };
            nuova.StatisticheAggiornate += statistiche =>
            {
                tracciato.Statistiche++;
                if (Elenco.Di(nuova) is { } telefono)
                {
                    telefono.Statistiche = statistiche;
                    telefono.StoriaLatenza.Aggiungi(statistiche.LatenzaMs);
                }
                // Più di due secondi di fotogrammi in un secondo: il telefono recupera un ritardo (o il ricevitore è lento).
                if (statistiche.Fps * Intervallo.TotalSeconds > 2 * Fps) Interlocked.Increment(ref TroppiFotogrammiNelSecondo);
                if (statistiche.Fps == 0) return;
                if (statistiche.LatenzaMs is not int ms)
                {
                    Interlocked.Increment(ref StatisticheSenzaLatenza);
                    return;
                }
                var minuto = Math.Min(MinutoAttuale, Latenze.GetLength(0) - 1);
                Interlocked.Increment(ref Latenze[minuto, Math.Clamp(ms / 5, 0, Gruppi - 1)]);
            };
            nuova.FormatoAudioRicevuto += Microfono.Imposta;
            nuova.AudioRicevuto += audio =>
            {
                var numero = BinaryPrimitives.ReadInt64BigEndian(audio.Dati.AsSpan(1));
                if (tracciato.UltimoAudio >= 0 && numero != tracciato.UltimoAudio + 1) tracciato.AudioFuoriOrdine++;
                tracciato.UltimoAudio = numero;
                tracciato.Audio++;
                Microfono.Ricevi(audio, nuova.ScartoOrologi, nuova.LatenzaVideoMs);
            };
            nuova.Silenzio += () => tracciato.Silenzi++;
            nuova.Ripresa += () => tracciato.Riprese++;
            nuova.Chiusa += () =>
            {
                tracciato.ChiusaDalComputer = nuova.ChiusaDalComputer;
                tracciato.ChiusaDalTelefono = nuova.ChiusaDalTelefono;
                tracciato.Voluta = CadutaInCorso || nuova.ChiusaDalComputer;
                if (!tracciato.Voluta) Interlocked.Increment(ref NonVolute);
                tracciato.Chiusa = true;
                // Come la finestra: il telefono resta nell'elenco in attesa che torni, il microfono riparte da capo.
                if (Elenco.Perso(nuova) is not null) Microfono.Ferma();
            };
            nuova.Avvia();
        }

        /// <summary>Come ChiudiSessioneAsync della finestra: arrivederci, poi chiusura; un errore di rete non conta.</summary>
        public static async Task ChiudiAsync(SessioneComputer sessione)
        {
            try
            {
                await sessione.ChiudiAsync();
                await sessione.DisposeAsync();
            }
            catch (Exception) { }
        }

        public void Dispose()
        {
            Ascoltatore.Dispose();
            Microfono.Dispose();
        }
    }

    /// <summary>Un «AAC» finto: ogni frame dà 1024 campioni con il valore del primo byte / 100.</summary>
    private sealed class DecodificatoreFinto : IDecodificatoreAudio
    {
        public int Frequenza => 48_000;
        public int Canali => 1;

        public int Decodifica(ReadOnlySpan<byte> frame, Span<float> uscita)
        {
            uscita[..1024].Fill(frame[0] / 100f);
            return 1024;
        }

        public void Dispose() { }
    }

    // MARK: le misure

    private sealed record Campione(int Minuto, long Memoria, long Timer, int Maniglie, int Thread, long InCoda, long Fotogrammi);

    private static int Maniglie()
    {
        try
        {
            return OperatingSystem.IsLinux()
                ? Directory.GetFileSystemEntries("/proc/self/fd").Length
                : Process.GetCurrentProcess().HandleCount;
        }
        catch (Exception) { return -1; }
    }

    private static long MemoriaDopoGc()
    {
        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        return GC.GetTotalMemory(forceFullCollection: true);
    }

    private static Campione Misura(int minuto, long fotogrammi)
    {
        var memoria = MemoriaDopoGc();
        return new Campione(minuto, memoria, Timer.ActiveCount, Maniglie(), ThreadPool.ThreadCount, ThreadPool.PendingWorkItemCount,
            fotogrammi);
    }

    private static async Task<bool> ScollegaDalComputerAsync(ElencoTelefoni elenco, TelefonoCollegato telefono)
    {
        if (elenco.Rimuovi(telefono) is not { } daChiudere) return false;
        await Computer.ChiudiAsync(daChiudere);
        return true;
    }

    /// <summary>Il risultato, per il controllo della durata reale.</summary>
    public sealed record Esito(TimeSpan Reale);

    // MARK: il telefono e la sessione

    private async Task<Esito> EseguiAsync(Copione copione)
    {
        var nonOsservate = new ConcurrentQueue<Exception>();
        void SuNonOsservata(object? _, UnobservedTaskExceptionEventArgs e) => nonOsservate.Enqueue(e.Exception);
        TaskScheduler.UnobservedTaskException += SuNonOsservata;
        try
        {
            return await EseguiConNonOsservateAsync(copione, nonOsservate);
        }
        finally
        {
            TaskScheduler.UnobservedTaskException -= SuNonOsservata;
        }
    }

    private async Task<Esito> EseguiConNonOsservateAsync(Copione copione, ConcurrentQueue<Exception> nonOsservate)
    {
        var limite = TimeSpan.FromSeconds(15);
        var durataSimulata = copione.Durata.TotalSeconds;
        var accelerazione = copione.Accelerazione;
        // Il telefono finto non deve fermarsi da solo prima della fine.
        var vitaTelefono = TimeSpan.FromSeconds(durataSimulata / accelerazione) + TimeSpan.FromMinutes(5);

        using var idComputer = IdentitaDispositivo.Nuova();
        using var idTelefono = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer, new Dictionary<string, string> { [idTelefono.Impronta] = "iPhone di prova" })
        {
            ChiediConferma = (_, _, _) => throw new InvalidOperationException("Non doveva chiedere"),
        };
        // L'orologio del silenzio: quello vero più i salti dei silenzi simulati.
        long salto = 0;
        ulong OrologioSilenzio() => Orologio.Adesso() + (ulong)Interlocked.Read(ref salto);
        static ulong OrologioTelefono() => Orologio.Adesso() + AvantiTelefono;

        using var pc = new Computer(abbinamento, copione, OrologioSilenzio);
        var campioni = new Campione[(int)Math.Ceiling(copione.Durata.TotalMinutes) + 4];
        var quantiCampioni = 0;

        // La scheda audio: legge 10 ms alla volta dal microfono, come l'uscita WASAPI.
        using var fineAudio = new CancellationTokenSource();
        var campioniLetti = 0L;
        var schedaAudio = Task.Run(async () =>
        {
            var periodo = new float[480];
            while (!fineAudio.IsCancellationRequested)
            {
                campioniLetti += pc.Microfono.Leggi(periodo);
                try { await Task.Delay(10, fineAudio.Token); } catch (OperationCanceledException) { }
            }
        });

        // Lo stato del telefono simulato.
        var formati = new[]
        {
            new FormatoVideo(Codec.H264, 1920, 1080, Fps),
            new FormatoVideo(Codec.H264, 1280, 720, Fps),
            new FormatoVideo(Codec.Hevc, 1920, 1080, Fps),
        };
        var formato = formati[0];
        var cambiFormato = 0;
        var episodiSenzaChiave = 0;
        long numeroFotogramma = 0;
        long numeroAudio = 0;
        long statiInviati = 0;
        long saltatiDalTelefono = 0;
        long chiediChiave = 0;
        long latenzeAlTelefono = 0;
        var chiaveChiesta = 0;
        var inAttesaDellaRichiesta = false;
        var cadute = 0;
        var silenziBrevi = 0;
        var silenziLunghi = 0;
        var sostituzioni = 0;
        var casuale = new Random(20);
        TaskCompletionSource arrivederci = null!;
        // Per ogni sessione: il primo e l'ultimo fotogramma mandati.
        var mandati = new List<(long Primo, long Ultimo, string Fine)>();
        var eventi = new List<string>();

        TelefonoFinto? telefono = null;
        CancellationTokenSource? fineLettura = null;
        Task? lettura = null;
        long primoDellaSessione = 0;

        async Task CollegaAsync()
        {
            fineLettura = new CancellationTokenSource();
            telefono = new TelefonoFinto(idTelefono, OrologioTelefono, vitaTelefono);
            var suoArrivederci = arrivederci = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var arrivi = pc.Esiti.Count;
            await telefono.CollegaAsync(pc.Ascoltatore.Porta, "iPhone di prova");
            await telefono.AttendiAsync<Benvenuto>().WaitAsync(limite);
            var fineAttesa = DateTime.UtcNow + limite;
            while (pc.Esiti.Count == arrivi)
            {
                if (DateTime.UtcNow > fineAttesa) throw new TimeoutException("Nessun arrivo nell'elenco");
                await Task.Delay(1);
            }
            var questo = telefono;
            var token = fineLettura.Token;
            // Il telefono legge ciò che manda il computer: latenza, chiedi-chiave, anteprima, arrivederci.
            lettura = Task.Run(async () =>
            {
                try
                {
                    while (true)
                    {
                        var messaggio = await questo.Ricevuti.Reader.ReadAsync(token);
                        switch (messaggio)
                        {
                            case ChiediChiave:
                                Interlocked.Increment(ref chiediChiave);
                                Volatile.Write(ref chiaveChiesta, 1);
                                break;
                            case Latenza:
                                Interlocked.Increment(ref latenzeAlTelefono);
                                break;
                            case Arrivederci:
                                suoArrivederci.TrySetResult();
                                break;
                        }
                    }
                }
                catch (OperationCanceledException) { }
            });
            await telefono.InviaAsync(new Capacita(["grandangolo", "principale"], 5, true, Audio: true));
            await telefono.InviaAsync(formato);
            await telefono.InviaAsync(FormatoAudio.AAC48kMono());
            primoDellaSessione = numeroFotogramma;
            // Dopo il collegamento il telefono parte sempre da un fotogramma chiave.
            Volatile.Write(ref chiaveChiesta, 1);
            inAttesaDellaRichiesta = false;
        }

        Task ScollegaTelefonoAsync() => ChiudiTelefonoAsync(telefono!, fineLettura!, lettura!);

        static async Task ChiudiTelefonoAsync(TelefonoFinto quale, CancellationTokenSource suaFine, Task suaLettura)
        {
            suaFine.Cancel();
            await quale.DisposeAsync();
            await suaLettura;
            suaFine.Dispose();
        }

        Task AttendiAsync(Func<bool> condizione, string cosa) => AttendiConMotivoAsync(condizione, () => cosa);

        async Task AttendiConMotivoAsync(Func<bool> condizione, Func<string> cosa)
        {
            var fine = DateTime.UtcNow + limite;
            while (!condizione())
            {
                if (DateTime.UtcNow > fine) throw new TimeoutException(cosa());
                await Task.Delay(1);
            }
        }

        // Tutto ciò che il telefono ha mandato in questa sessione è arrivato.
        Task TuttoArrivatoAsync() => AttendiConMotivoAsync(
            () => pc.Attuale is { } t && (t.Ultimo == numeroFotogramma - 1 || (t.Primo < 0 && primoDellaSessione == numeroFotogramma)),
            () => $"Fotogrammi non arrivati: a {Simulato():0} s simulati la sessione {pc.Attuale?.Numero} (chiusa {pc.Attuale?.Chiusa}) " +
            $"è al {pc.Attuale?.Ultimo} di {numeroFotogramma - 1} (primo {pc.Attuale?.Primo}, mandato {primoDellaSessione}, stati {pc.Attuale?.Stati}, statistiche {pc.Attuale?.Statistiche}), sessioni {pc.Tracciati.Count}, esiti {string.Join(",", pc.Esiti)}");

        var orologio = Stopwatch.StartNew();
        double Simulato() => orologio.Elapsed.TotalSeconds * accelerazione;
        async Task AspettaSimulatoAsync(double secondi)
        {
            var reale = TimeSpan.FromSeconds(secondi / accelerazione);
            await Task.Delay(reale > TimeSpan.FromMilliseconds(20) ? reale : TimeSpan.FromMilliseconds(20));
        }

        await CollegaAsync();
        var telefonoNellElenco = Assert.Single(pc.Elenco.Telefoni);

        double prossimoStato = 0;
        var prossimoFormato = copione.SecondiFormato;
        var prossimaCaduta = copione.SecondiCaduta;
        var prossimoSilenzio = copione.PrimoSilenzio;
        var prossimaSostituzione = copione.SecondiSostituzione;
        var prossimoMinuto = 1;
        long indiceVideo = 0;
        long indiceAudio = 0;
        var batteria = 100;

        while (true)
        {
            var adesso = Simulato();
            if (adesso >= durataSimulata) break;
            pc.MinutoAttuale = (int)(adesso / 60);

            // Ogni minuto simulato: memoria (dopo GC), timer, maniglie, thread, lavoro in coda.
            if (adesso >= prossimoMinuto * 60)
            {
                campioni[Math.Min(quantiCampioni++, campioni.Length - 1)] = Misura(prossimoMinuto, numeroFotogramma);
                prossimoMinuto++;
                if (batteria > 40) batteria--;
                continue;
            }

            if (adesso >= prossimaCaduta)
            {
                // Caduta improvvisa della rete: il telefono sparisce a metà del flusso e torna dopo 2 secondi.
                prossimaCaduta += copione.SecondiCaduta;
                var inizioEvento = orologio.Elapsed;
                var corrente = pc.Attuale!;
                pc.CadutaInCorso = true;
                mandati.Add((primoDellaSessione, numeroFotogramma - 1, "caduta"));
                await ScollegaTelefonoAsync();
                await AttendiAsync(() => corrente.Chiusa, "La caduta non chiude la sessione");
                await AspettaSimulatoAsync(copione.SecondiFuori);
                await CollegaAsync();
                pc.CadutaInCorso = false;
                cadute++;
                eventi.Add($"{adesso:0} s caduta: {(orologio.Elapsed - inizioEvento).TotalMilliseconds:0} ms, silenzi {pc.Tracciati.Sum(t => t.Silenzi)}");
                continue;
            }

            if (adesso >= prossimoSilenzio)
            {
                // Il telefono smette di mandare e di rispondere (rete persa senza chiusura). Dopo 3 s «Riconnessione»
                // (Silenzio); quello breve riprende a 4 s (Ripresa), quello lungo arriva a 11 s e il ricevitore chiude.
                prossimoSilenzio += copione.SecondiSilenzio;
                var inizioEvento = orologio.Elapsed;
                var lungo = (silenziBrevi + silenziLunghi) % 2 == 1;
                await TuttoArrivatoAsync();
                var corrente = pc.Attuale!;
                telefono!.Muto = true;
                // Un pong partito prima di «muto» arriva ancora (e varrebbe come ripresa): si aspetta che sia arrivato.
                await Task.Delay(pc.Intervallo * 2 + TimeSpan.FromMilliseconds(30));
                Interlocked.Add(ref salto, 4_000_000);
                await AttendiAsync(() => corrente.Silenzi == 1, "Nessun «Riconnessione» dopo 4 s di silenzio");
                if (!lungo)
                {
                    telefono.Muto = false;
                    silenziBrevi++;
                    eventi.Add($"{adesso:0} s silenzio breve: {(orologio.Elapsed - inizioEvento).TotalMilliseconds:0} ms, silenzi {pc.Tracciati.Sum(t => t.Silenzi)}");
                    continue;
                }
                pc.CadutaInCorso = true;
                mandati.Add((primoDellaSessione, numeroFotogramma - 1, "silenzio"));
                Interlocked.Add(ref salto, 7_000_000);
                await telefono.Chiuso.Task.WaitAsync(limite);
                await AttendiAsync(() => corrente.Chiusa, "Il silenzio non chiude la sessione");
                await ScollegaTelefonoAsync();
                await CollegaAsync();
                pc.CadutaInCorso = false;
                silenziLunghi++;
                eventi.Add($"{adesso:0} s silenzio lungo: {(orologio.Elapsed - inizioEvento).TotalMilliseconds:0} ms, silenzi {pc.Tracciati.Sum(t => t.Silenzi)}");
                continue;
            }

            if (adesso >= prossimaSostituzione)
            {
                // Il telefono torna con una connessione nuova mentre quella vecchia è ancora aperta (muta): la nuova la
                // sostituisce e il computer chiude la vecchia con «arrivederci».
                prossimaSostituzione += copione.SecondiSostituzione;
                var inizioEvento = orologio.Elapsed;
                await TuttoArrivatoAsync();
                var corrente = pc.Attuale!;
                mandati.Add((primoDellaSessione, numeroFotogramma - 1, "sostituita"));
                var (vecchio, vecchiaFine, vecchiaLettura, vecchioArrivederci) = (telefono!, fineLettura!, lettura!, arrivederci);
                vecchio.Muto = true;
                await CollegaAsync();
                await AttendiAsync(() => corrente.Chiusa, "La sessione sostituita non si chiude");
                Assert.True(corrente.ChiusaDalComputer);
                await vecchioArrivederci.Task.WaitAsync(limite);
                await vecchio.Chiuso.Task.WaitAsync(limite);
                await ChiudiTelefonoAsync(vecchio, vecchiaFine, vecchiaLettura);
                sostituzioni++;
                eventi.Add($"{adesso:0} s sostituzione: {(orologio.Elapsed - inizioEvento).TotalMilliseconds:0} ms, silenzi {pc.Tracciati.Sum(t => t.Silenzi)}");
                continue;
            }

            if (adesso >= prossimoFormato)
            {
                // Cambio di formato; una volta su due il primo fotogramma non è chiave e il computer deve chiederlo.
                prossimoFormato += copione.SecondiFormato;
                formato = formati[++cambiFormato % formati.Length];
                await telefono!.InviaAsync(formato);
                if (cambiFormato % 2 == 1) Volatile.Write(ref chiaveChiesta, 1);
                else
                {
                    // Fino alla richiesta del computer niente fotogrammi chiave, nemmeno quello fisso ogni 2 secondi.
                    Volatile.Write(ref chiaveChiesta, 0);
                    inAttesaDellaRichiesta = true;
                    episodiSenzaChiave++;
                }
            }

            if (adesso >= prossimoStato)
            {
                prossimoStato += copione.SecondiStato;
                await telefono!.InviaAsync(new StatoTelefono(batteria, false, Temperatura.Normale, "principale", Audio: true,
                    Zoom: 1, Torcia: false));
                statiInviati++;
            }

            // Il video del secondo simulato: se il telefono resta indietro di più di mezzo secondo salta fotogrammi, come
            // l'encoder vero (non manda un mucchio di fotogrammi vecchi).
            var dovuti = (long)(adesso * Fps);
            var indietro = dovuti - indiceVideo;
            if (indietro > Fps / 2)
            {
                saltatiDalTelefono += indietro;
                indiceVideo = dovuti;
            }
            var mandato = false;
            while (indiceVideo <= dovuti)
            {
                var chiesta = Interlocked.Exchange(ref chiaveChiesta, 0) == 1;
                if (chiesta) inAttesaDellaRichiesta = false;
                var chiave = chiesta || (indiceVideo % OgniChiave == 0 && !inAttesaDellaRichiesta);
                var dati = new byte[chiave ? casuale.Next(45_000, 60_000) : casuale.Next(18_000, 35_000)];
                BinaryPrimitives.WriteInt64BigEndian(dati, numeroFotogramma++);
                dati[8] = chiave ? (byte)1 : (byte)0;
                // 30 ms tra cattura e invio, come in TelefonoSimulatoTest.
                await telefono!.InviaAsync(new FotogrammaVideo(OrologioTelefono() - 30_000, chiave, chiave, dati).ComePacchetto());
                indiceVideo++;
                mandato = true;
            }

            var audioDovuti = (long)(adesso * PacchettiAudioAlSecondo);
            if (audioDovuti - indiceAudio > PacchettiAudioAlSecondo / 2) indiceAudio = audioDovuti;
            while (indiceAudio <= audioDovuti)
            {
                var dati = new byte[casuale.Next(180, 280)];
                dati[0] = 40;
                BinaryPrimitives.WriteInt64BigEndian(dati.AsSpan(1), numeroAudio++);
                await telefono!.InviaAsync(new PacchettoAudio(OrologioTelefono() - 20_000, dati).ComePacchetto());
                indiceAudio++;
                mandato = true;
            }

            if (!mandato)
            {
                // Fino al prossimo fotogramma o pacchetto audio.
                var prossimo = Math.Min((indiceVideo) / (double)Fps, indiceAudio / PacchettiAudioAlSecondo);
                var attesa = TimeSpan.FromSeconds(Math.Max(0, prossimo - Simulato()) / accelerazione);
                if (attesa >= TimeSpan.FromMilliseconds(1)) await Task.Delay(attesa);
                else await Task.Yield();
            }
        }

        // Fine della sessione: tutto arrivato, ultima misura con la sessione ancora aperta, poi «Scollega» dal computer.
        await TuttoArrivatoAsync();
        mandati.Add((primoDellaSessione, numeroFotogramma - 1, "scollega"));
        var reale = orologio.Elapsed;
        var finale = Misura(prossimoMinuto, numeroFotogramma);
        var ultimo = pc.Attuale!;
        var vive = pc.Tracciati.Count(t => t != ultimo && t.Sessione.TryGetTarget(out _));
        var scartoOrologi = pc.Elenco.SessioneSelezionata?.ScartoOrologi;

        Assert.Same(telefonoNellElenco, pc.Elenco.Selezionato);
        Assert.Single(pc.Elenco.Telefoni);
        Assert.Equal(cadute + silenziLunghi, telefonoNellElenco.Perdite);
        // Come «Scollega» nella finestra; in un metodo a parte, così la sessione non resta in una variabile di questo.
        Assert.True(await ScollegaDalComputerAsync(pc.Elenco, telefonoNellElenco));
        await arrivederci.Task.WaitAsync(limite);
        await ScollegaTelefonoAsync();
        fineAudio.Cancel();
        await schedaAudio;

        // Le sessioni chiuse, il telefono finto e l'ascolto chiusi: tutto si libera.
        pc.Dispose();
        await Task.Delay(100);
        var memoriaDopo = MemoriaDopoGc();
        var dopoLaChiusura = pc.Tracciati.Count(t => t.Sessione.TryGetTarget(out _));
        var timerDopo = Timer.ActiveCount;
        var maniglieDopo = Maniglie();

        // MARK: il rapporto
        var tracciati = pc.Tracciati.ToArray();
        var fotogrammiArrivati = tracciati.Sum(t => t.Fotogrammi);
        var persiInVolo = numeroFotogramma - fotogrammiArrivati;
        var tutte = new int[Computer.Gruppi];
        for (var minuto = 0; minuto < pc.Latenze.GetLength(0); minuto++)
            for (var g = 0; g < Computer.Gruppi; g++) tutte[g] += pc.Latenze[minuto, g];
        int? Percentile(int[] gruppi, double quota)
        {
            var totale = gruppi.Sum();
            if (totale == 0) return null;
            var soglia = (long)Math.Ceiling(totale * quota);
            long somma = 0;
            for (var g = 0; g < gruppi.Length; g++)
            {
                somma += gruppi[g];
                if (somma >= soglia) return g * 5 + 5;
            }
            return null;
        }
        int[] DelMinuto(int minuto) => Enumerable.Range(0, Computer.Gruppi).Select(g => pc.Latenze[minuto, g]).ToArray();

        var usati = campioni.Take(Math.Min(quantiCampioni, campioni.Length)).Append(finale).ToArray();
        var primo = usati[0];
        uscita.WriteLine($"Copione: {copione.Durata.TotalMinutes} minuti simulati, accelerazione {accelerazione}; durata reale {reale.TotalSeconds:0.0} s");
        uscita.WriteLine($"Fotogrammi: mandati {numeroFotogramma}, arrivati {fotogrammiArrivati}, persi in volo nelle cadute {persiInVolo}, " +
                         $"saltati dal telefono in ritardo {saltatiDalTelefono}; audio mandati {numeroAudio}, arrivati {tracciati.Sum(t => t.Audio)}, " +
                         $"campioni letti dalla scheda {campioniLetti}");
        uscita.WriteLine($"Sessioni {tracciati.Length}: cadute {cadute}, silenzi brevi {silenziBrevi} e lunghi {silenziLunghi}, " +
                         $"sostituite {sostituzioni}, chiusure non volute {pc.NonVolute}; " +
                         $"stati mandati {statiInviati}, arrivati {tracciati.Sum(t => t.Stati)}; formati cambiati {cambiFormato}; " +
                         $"episodi senza chiave {episodiSenzaChiave}, chiedi-chiave {chiediChiave}, fotogrammi senza chiave {tracciati.Sum(t => t.SenzaChiave)}");
        uscita.WriteLine($"Latenza (arrivo): p50 {Percentile(tutte, 0.5)} ms, p95 {Percentile(tutte, 0.95)} ms, p99 {Percentile(tutte, 0.99)} ms; " +
                         $"primo minuto p50 {Percentile(DelMinuto(0), 0.5)} ms, ultimo p50 {Percentile(DelMinuto(Math.Max(0, (int)(durataSimulata / 60) - 1)), 0.5)} ms; " +
                         $"statistiche senza latenza {pc.StatisticheSenzaLatenza}, latenze al telefono {latenzeAlTelefono}; scarto orologi {scartoOrologi} µs");
        uscita.WriteLine($"Memoria gestita: minuto 1 {primo.Memoria / 1024} kB, fine {finale.Memoria / 1024} kB, massimo {usati.Max(c => c.Memoria) / 1024} kB, " +
                         $"dopo la chiusura {memoriaDopo / 1024} kB");
        uscita.WriteLine($"Timer: {primo.Timer} → {finale.Timer} (dopo {timerDopo}); maniglie {primo.Maniglie} → {finale.Maniglie} (dopo {maniglieDopo}); " +
                         $"thread {primo.Thread} → {finale.Thread}; lavoro in coda {primo.InCoda} → {finale.InCoda}");
        uscita.WriteLine($"Sessioni vecchie ancora in memoria: {vive} (dopo la chiusura {dopoLaChiusura}); eccezioni non osservate {nonOsservate.Count}");
        foreach (var e in eventi) uscita.WriteLine("  " + e);
        foreach (var c in usati)
            uscita.WriteLine($"  minuto {c.Minuto,3}: memoria {c.Memoria / 1024,7} kB, timer {c.Timer,3}, maniglie {c.Maniglie,4}, thread {c.Thread,3}, in coda {c.InCoda,3}, fotogrammi {c.Fotogrammi}");

        // MARK: i controlli
        // Nessuna caduta non voluta, nessun «Riconnessione»; ogni sessione dello stesso telefono che torna lo sostituisce.
        Assert.Equal(0, pc.NonVolute);
        Assert.Equal(1 + cadute + silenziLunghi + sostituzioni, tracciati.Length);
        // «Riconnessione» solo nei silenzi voluti, e la ripresa solo in quelli brevi.
        Assert.Equal(silenziBrevi + silenziLunghi, tracciati.Sum(t => t.Silenzi));
        Assert.Equal(silenziBrevi, tracciati.Sum(t => t.Riprese));
        Assert.Equal(sostituzioni, tracciati.Count(t => t.ChiusaDalComputer) - 1);
        Assert.Equal(EsitoArrivo.Nuovo, pc.Esiti.First());
        Assert.All(pc.Esiti.Skip(1), e => Assert.Equal(EsitoArrivo.StessoTelefono, e));

        // I fotogrammi: in ordine, ognuno con la sua chiave, timestamp in avanti; tutti, tranne la coda in volo alla caduta.
        Assert.All(tracciati, t => Assert.Equal((0L, 0L, 0L, 0L), (t.FuoriOrdine, t.ChiaveSbagliata, t.TimestampIndietro, t.AudioFuoriOrdine)));
        Assert.Equal(mandati.Count, tracciati.Length);
        // Una sessione può restare vuota se due eventi cadono uno dopo l'altro (il telefono torna e se ne va subito).
        var persiInCoda = 0L;
        foreach (var (t, m) in tracciati.OrderBy(t => t.Numero).Zip(mandati))
        {
            if (m.Ultimo < m.Primo)
            {
                Assert.Equal(0, t.Fotogrammi);
                continue;
            }
            if (m.Fine == "caduta" && t.Fotogrammi == 0)
            {
                persiInCoda += m.Ultimo - m.Primo + 1;
                continue;
            }
            Assert.Equal(m.Primo, t.Primo);
            if (m.Fine == "caduta") Assert.InRange(t.Ultimo, m.Primo, m.Ultimo);
            else Assert.Equal(m.Ultimo, t.Ultimo);
            Assert.Equal(t.Ultimo - t.Primo + 1, t.Fotogrammi);
            persiInCoda += m.Ultimo - t.Ultimo;
        }
        Assert.Equal(numeroFotogramma, fotogrammiArrivati + persiInCoda);
        Assert.True(fotogrammiArrivati > 0.95 * numeroFotogramma, "Troppi fotogrammi persi");
        // Gli stati: al massimo uno perso in volo per caduta.
        Assert.InRange(tracciati.Sum(t => t.Stati), statiInviati - cadute, statiInviati);

        // Fotogramma chiave su richiesta: ogni cambio di formato senza chiave è stato chiesto e risolto presto.
        Assert.InRange(Interlocked.Read(ref chiediChiave), episodiSenzaChiave, 2L * episodiSenzaChiave + 1);
        Assert.InRange(tracciati.Sum(t => t.SenzaChiave), episodiSenzaChiave, (long)episodiSenzaChiave * Fps);

        // Ping, pong e latenza: lo scarto degli orologi è quello del telefono, la latenza resta bassa e non cresce.
        Assert.NotNull(scartoOrologi);
        Assert.InRange(scartoOrologi!.Value, (long)AvantiTelefono - 50_000, (long)AvantiTelefono + 50_000);
        Assert.True(Interlocked.Read(ref latenzeAlTelefono) > durataSimulata / 2, "Il telefono non riceve la latenza ogni secondo");
        Assert.InRange(Percentile(tutte, 0.5) ?? int.MaxValue, 25, 250);
        var ultimoMinuto = Percentile(DelMinuto(Math.Max(0, (int)(durataSimulata / 60) - 1)), 0.5) ?? int.MaxValue;
        Assert.InRange(ultimoMinuto, 25, (Percentile(DelMinuto(1), 0.5) ?? 0) + 100);

        // Il microfono riceve tutto e la scheda audio legge.
        Assert.True(tracciati.Sum(t => t.Audio) > 0.95 * numeroAudio, "Troppo audio perso");
        Assert.True(campioniLetti > 0, "La scheda audio non ha letto nulla");

        // Risorse: memoria gestita, timer e maniglie non crescono; le sessioni chiuse se ne vanno; nessuna eccezione persa.
        Assert.InRange(finale.Memoria - primo.Memoria, long.MinValue, 8L * 1024 * 1024);
        Assert.InRange(finale.Timer - primo.Timer, long.MinValue, 4);
        // Maniglie: si contano a sessioni chiuse e dopo il GC. Su Windows, mentre la sessione è aperta, il runtime tiene
        // maniglie sue (pool dei thread, porte di completamento) che crescono un poco nei primi minuti: a fine sessione
        // la GitHub CI ne ha viste +11, e +7 dopo la chiusura. Una perdita vera resta: cresce con le sessioni.
        // Il riferimento è il secondo minuto: nel primo il pool dei thread di Windows si allarga ancora (10 → 12 thread,
        // +11 maniglie sulla GitHub CI) e poi resta fermo. Una perdita vera cresce con le sessioni, dopo.
        var riferimento = usati.Length > 2 ? usati[1] : primo;
        if (riferimento.Maniglie >= 0) Assert.InRange(maniglieDopo - riferimento.Maniglie, int.MinValue, 8);
        Assert.InRange(finale.InCoda, 0, 200);
        Assert.Equal(0, vive);
        Assert.Equal(0, dopoLaChiusura);
        GC.Collect();
        GC.WaitForPendingFinalizers();
        Assert.Empty(nonOsservate);
        return new Esito(reale);
    }
}
