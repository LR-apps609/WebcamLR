using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Il microfono del telefono su Windows (W2): anello anti-jitter, posto nel tempo dei frame, ricampionamento,
/// deriva della scheda audio e livello. Senza Media Foundation né WASAPI: decodificatore finto e orologio finto.
/// </summary>
public class MicrofonoTest
{
    /// <summary>Un frame AAC dura 1024 campioni a 48 kHz: 21 333 µs.</summary>
    private const ulong DurataFrame = 21_333;

    // MARK: linea del tempo e anello

    [Fact]
    public void IndiceComeSulMac()
    {
        Assert.Equal(48UL, LineaAudio.Indice(1_000));
        Assert.Equal(48_000UL, LineaAudio.Indice(1_000_000));
        Assert.Equal(1024UL, LineaAudio.Indice(DurataFrame + 1));
        Assert.Equal(0UL, LineaAudio.Indice(20));
    }

    [Fact]
    public void AnelloRestituisceCiòCheÈScrittoNelSuoMomento()
    {
        var anello = new AnelloAudio();
        var tratto = Enumerable.Range(0, 1024).Select(i => 0.5f).ToArray();
        anello.Scrivi(10_000, tratto);
        anello.Scrivi(11_024, tratto); // attaccato: nessuna dissolvenza
        Assert.Equal(12_048UL, anello.Fine);

        var letti = new float[2048];
        // Il primo tratto entra con una dissolvenza di 128 campioni (era dopo un buco), e chi legge risale in 64.
        Assert.Equal(2048, anello.Leggi(10_000, 1, letti));
        Assert.True(letti[0] < 0.01f);
        Assert.Equal(0.5f, letti[500], 3);
        // Nel punto di giunzione nessuno scalino.
        Assert.Equal(0.5f, letti[1023], 3);
        Assert.Equal(0.5f, letti[1024], 3);
        Assert.Equal(0.5f, letti[2047], 3);
    }

    [Fact]
    public void DopoLaFineIlSilenzioArrivaSenzaScalino()
    {
        var anello = new AnelloAudio();
        anello.Scrivi(1_000, Enumerable.Repeat(1f, 1024).ToArray());
        var letti = new float[1024 + 200];
        Assert.Equal(1024, anello.Leggi(1_000, 1, letti));
        // Oltre la fine si tiene l'ultimo valore e lo si porta a zero in 64 campioni.
        Assert.True(letti[1024] is > 0.9f and < 1f);
        Assert.True(letti[1024 + 32] is > 0.4f and < 0.6f);
        Assert.Equal(0f, letti[1024 + 64]);
        Assert.Equal(0f, letti[^1]);
    }

    [Fact]
    public void BucoESovrapposizioneConDissolvenze()
    {
        var anello = new AnelloAudio();
        anello.Scrivi(0 + 5_000, Enumerable.Repeat(1f, 1024).ToArray());
        // Buco di 100 campioni: la coda scende a zero, il buco è silenzio, il frame dopo risale.
        anello.Scrivi(5_000 + 1024 + 100, Enumerable.Repeat(1f, 1024).ToArray());
        var letti = new float[1];
        anello.Leggi(5_000 + 1023, 1, letti);
        Assert.Equal(0f, letti[0], 3);
        anello.Leggi(5_000 + 1024 + 50, 1, letti);
        Assert.Equal(0f, letti[0], 3);

        // Sovrapposizione (il ritardo è cambiato): dal vecchio al nuovo in 128 campioni, poi solo il nuovo.
        var sovrapposto = new AnelloAudio();
        sovrapposto.Scrivi(1_000, Enumerable.Repeat(1f, 2000).ToArray());
        sovrapposto.Scrivi(2_000, Enumerable.Repeat(-1f, 1024).ToArray());
        var tutto = new float[3000];
        sovrapposto.Leggi(1_000, 1, tutto);
        Assert.Equal(1f, tutto[900], 3);
        Assert.True(tutto[1000 + 64] is > -0.1f and < 0.1f);
        Assert.Equal(-1f, tutto[1000 + 200], 3);
        // La fine è dopo il tratto nuovo: il resto del vecchio non vale più.
        Assert.Equal(3_024UL, sovrapposto.Fine);
    }

    [Fact]
    public void LetturaFrazionariaInterpola()
    {
        var anello = new AnelloAudio();
        anello.Scrivi(10_000, Enumerable.Range(0, 1000).Select(i => i / 1000f).ToArray());
        var letti = new float[100];
        anello.Leggi(10_500.5, 1, letti);
        // Il guadagno risale in 64 campioni: si guarda dopo.
        Assert.Equal(0.5805f, letti[80], 3);
    }

    // MARK: posto nel tempo

    [Fact]
    public void FramePuntualiSiAttacanoEInRitardoSiTaglia()
    {
        var tempi = new TempiAudio();
        const long scarto = 5_000_000; // il telefono è avanti di 5 s
        const ulong adesso = 100_000_000;
        // Catturato 30 ms fa: si ascolta fra 40 ms (ritardo predefinito 70 ms).
        var timestamp = (ulong)((long)adesso - 30_000 + scarto);
        var primo = tempi.Posiziona(timestamp, scarto, adesso, 1024);
        Assert.Equal((LineaAudio.Indice(adesso + 40_000), 0), primo);

        // Il prossimo, con 3 µs di errore di arrotondamento: attaccato al primo, senza buchi.
        var secondo = tempi.Posiziona(timestamp + DurataFrame + 3, scarto, adesso + 1_000, 1024);
        Assert.Equal(primo!.Value.Posizione + 1024, secondo!.Value.Posizione);

        // Un frame arrivato tardi (andava ascoltato 5 ms fa): la parte passata, più il margine, si salta.
        var tardi = new TempiAudio();
        var inRitardo = tardi.Posiziona((ulong)((long)adesso - 75_000 + scarto), scarto, adesso, 1024);
        Assert.Equal((int)TempiAudio.Margine + 240, inRitardo!.Value.Inizio);
        Assert.Equal(LineaAudio.Indice(adesso) + TempiAudio.Margine, inRitardo.Value.Posizione);
        // Del tutto passato: si butta.
        Assert.Null(tardi.Posiziona((ulong)((long)adesso - 200_000 + scarto), scarto, adesso, 1024));
        // Orologi assurdi: fuori dall'anello.
        Assert.Null(tardi.Posiziona((ulong)((long)adesso + 10_000_000 + scarto), scarto, adesso, 1024));
        Assert.Null(tardi.Posiziona(0, long.MaxValue, adesso, 1024));
    }

    [Fact]
    public void IlRitardoSegueIlVideoConIsteresiENeiLimiti()
    {
        var tempi = new TempiAudio();
        Assert.Equal(TempiAudio.RitardoPredefinito, tempi.Ritardo);
        tempi.AggiornaRitardo(85); // 15 ms in più: non cambia
        Assert.Equal(70_000, tempi.Ritardo);
        tempi.AggiornaRitardo(120);
        Assert.Equal(120_000, tempi.Ritardo);
        tempi.AggiornaRitardo(20); // sotto il minimo
        Assert.Equal(TempiAudio.RitardoMinimo, tempi.Ritardo);
        tempi.AggiornaRitardo(2_000); // sopra il massimo
        Assert.Equal(TempiAudio.RitardoMassimo, tempi.Ritardo);
        tempi.AggiornaRitardo(null);
        Assert.Equal(TempiAudio.RitardoMassimo, tempi.Ritardo);
    }

    // MARK: ricampionamento

    [Fact]
    public void A48kMonoPassaCosì()
    {
        var ricampionatore = new RicampionatoreAudio(48_000, 1);
        var uscita = new List<float>();
        ricampionatore.Converti(new[] { 0.1f, 0.2f, 0.3f }, uscita);
        Assert.Equal(new[] { 0.1f, 0.2f, 0.3f }, uscita);
    }

    [Fact]
    public void Da44100A48000SenzaScaliniFraIFrame()
    {
        var ricampionatore = new RicampionatoreAudio(44_100, 1);
        var uscita = new List<float>();
        var frame = new float[1024];
        const double tono = 1_000;
        long campione = 0;
        for (var f = 0; f < 43; f++) // circa un secondo
        {
            for (var i = 0; i < frame.Length; i++, campione++) frame[i] = (float)Math.Sin(2 * Math.PI * tono * campione / 44_100);
            ricampionatore.Converti(frame, uscita);
        }
        // Quanti: proporzionali alle frequenze (a meno dei due campioni tenuti per interpolare).
        var attesi = campione * 48_000.0 / 44_100;
        Assert.InRange(uscita.Count, attesi - 4, attesi + 1);
        // Lo stesso tono a 48 kHz: confronto con il seno atteso (stesso istante, a meno del campione di avvio).
        var errore = 0.0;
        for (var k = 200; k < uscita.Count - 10; k++)
        {
            // L'uscita k è all'istante k/48000 meno un campione d'ingresso (quello tenuto per interpolare).
            var istante = k / 48_000.0 - 1.0 / 44_100;
            errore = Math.Max(errore, Math.Abs(uscita[k] - Math.Sin(2 * Math.PI * tono * istante)));
        }
        Assert.True(errore < 0.01, $"errore massimo {errore}");
    }

    [Fact]
    public void StereoDiventaMono()
    {
        var ricampionatore = new RicampionatoreAudio(48_000, 2);
        var uscita = new List<float>();
        var stereo = new float[2 * 100];
        for (var i = 0; i < 100; i++) { stereo[2 * i] = 0.2f; stereo[2 * i + 1] = 0.6f; }
        ricampionatore.Converti(stereo, uscita);
        ricampionatore.Converti(stereo, uscita);
        Assert.True(uscita.Count >= 195);
        Assert.Equal(0.4f, uscita[150], 4);
    }

    // MARK: livello

    [Fact]
    public void LivelloDaMenoSessantaAZeroDecibel()
    {
        Assert.Equal(0, LivelloAudio.Livello(0));
        Assert.Equal(1, LivelloAudio.Livello(1));
        Assert.Equal(0.5, LivelloAudio.Livello(Math.Pow(10, -30 / 20.0)), 6);

        var livello = new LivelloAudio();
        var mezzo = Enumerable.Repeat(0.5f, 1024).ToArray();
        Assert.NotNull(livello.Aggiungi(mezzo, 1_000_000)); // il primo esce subito
        Assert.Null(livello.Aggiungi(mezzo, 1_050_000));    // poi uno ogni 100 ms
        var valore = livello.Aggiungi(mezzo, 1_100_000);
        Assert.Equal(LivelloAudio.Livello(0.5), valore!.Value, 6);
    }

    // MARK: tutto insieme

    /// <summary>Un «AAC» finto: ogni byte del frame diventa 1024 campioni con quel valore / 100.</summary>
    private sealed class DecodificatoreFinto(int frequenza = 48_000, int canali = 1) : IDecodificatoreAudio
    {
        public int Frequenza { get; } = frequenza;
        public int Canali { get; } = canali;
        public int Creati;
        public bool Chiuso;

        public int Decodifica(ReadOnlySpan<byte> frame, Span<float> uscita)
        {
            if (frame[0] == 0xFF) return -1;
            var n = 1024 * Canali;
            uscita[..n].Fill(frame[0] / 100f);
            return n;
        }

        public void Dispose() => Chiuso = true;
    }

    private sealed class OrologioFinto
    {
        public ulong Adesso = 50_000_000;
        public ulong Leggi() => Adesso;
    }

    [Fact]
    public void DalPacchettoAllUscitaNelMomentoGiusto()
    {
        var orologio = new OrologioFinto();
        var creati = 0;
        using var microfono = new MicrofonoTelefono(_ => { creati++; return new DecodificatoreFinto(); }, orologio.Leggi);
        var livelli = new List<double>();
        microfono.Livello += livelli.Add;
        microfono.Imposta(FormatoAudio.AAC48kMono());
        Assert.False(microfono.AudioInArrivo);

        const long scarto = -1_000_000; // il telefono è indietro di 1 s
        // Dieci frame catturati ogni 21,3 ms, arrivati 30 ms dopo.
        var primaCattura = orologio.Adesso;
        for (var i = 0; i < 10; i++)
        {
            var cattura = primaCattura + (ulong)i * DurataFrame;
            orologio.Adesso = cattura + 30_000;
            microfono.Ricevi(new PacchettoAudio((ulong)((long)cattura + scarto), [50]), scarto, latenzaVideoMs: null);
        }
        Assert.Equal(1, creati);
        Assert.True(microfono.AudioInArrivo);
        Assert.NotEmpty(livelli);

        // A cattura + 70 ms (il ritardo predefinito) l'audio è al suo posto; l'uscita lo legge 20 ms dopo.
        orologio.Adesso = primaCattura + 70_000 + 50_000 + 20_000;
        var uscita = new float[480];
        Assert.Equal(480, microfono.Leggi(uscita));
        Assert.Equal(0.5f, uscita[^1], 3);

        // Il formato non cambia: niente decodificatore nuovo. Spento: silenzio e livello a zero.
        microfono.Imposta(FormatoAudio.AAC48kMono());
        Assert.Equal(1, creati);
        microfono.Ferma();
        Assert.Equal(0, livelli[^1]);
        Assert.False(microfono.AudioInArrivo);
        microfono.Leggi(uscita);
        Assert.Equal(0, microfono.Leggi(uscita));
    }

    [Fact]
    public void SenzaPongSoloIlLivelloEUnFrameRovinatoRifàIlDecodificatore()
    {
        var orologio = new OrologioFinto();
        var decodificatori = new List<DecodificatoreFinto>();
        using var microfono = new MicrofonoTelefono(_ => { var d = new DecodificatoreFinto(); decodificatori.Add(d); return d; }, orologio.Leggi);
        var livelli = new List<double>();
        microfono.Livello += livelli.Add;
        microfono.Imposta(FormatoAudio.AAC48kMono());
        microfono.Ricevi(new PacchettoAudio(1, [80]), scarto: null, latenzaVideoMs: null);
        Assert.Single(livelli);
        orologio.Adesso += 100_000;
        Assert.Equal(0, microfono.Leggi(new float[480]));

        microfono.Ricevi(new PacchettoAudio(2, [0xFF]), scarto: 0, latenzaVideoMs: null);
        Assert.True(decodificatori[0].Chiuso);
        microfono.Ricevi(new PacchettoAudio(3, [10]), scarto: 0, latenzaVideoMs: null);
        Assert.Equal(2, decodificatori.Count);
    }

    [Fact]
    public void SenzaDecodificatoreLoDiceUnaVolta()
    {
        var errori = new List<string>();
        using var microfono = new MicrofonoTelefono(_ => null);
        microfono.Errore += errori.Add;
        microfono.Imposta(new FormatoAudio("opus", 48_000, 1, ""));
        microfono.Ricevi(new PacchettoAudio(1, [1]), 0, null);
        microfono.Ricevi(new PacchettoAudio(2, [1]), 0, null);
        Assert.Single(errori);
        Assert.Contains("opus", errori[0]);
    }

    /// <summary>
    /// La scheda audio ha il suo orologio: qui va più veloce o più lenta dello 0,1% (molto più di una scheda vera).
    /// Chi legge segue «adesso» regolando il passo: la distanza resta piccola e non salta mai, per dieci minuti.
    /// </summary>
    [Theory]
    [InlineData(0.001)]
    [InlineData(-0.001)]
    [InlineData(0.0)]
    public void LaLetturaSegueLaDerivaDellaSchedaAudio(double deriva)
    {
        var orologio = new OrologioFinto();
        using var microfono = new MicrofonoTelefono(_ => new DecodificatoreFinto(), orologio.Leggi);
        var periodo = new float[480]; // 10 ms di scheda audio
        var tempoVero = (double)orologio.Adesso;
        var casuale = new Random(7);
        var distanzaMassima = 0.0;
        for (var giro = 0; giro < 60_000; giro++)
        {
            // 480 campioni della scheda durano 10 ms ÷ (1 + deriva) sull'orologio del computer; il thread si sveglia ±1 ms.
            tempoVero += 10_000 / (1 + deriva);
            orologio.Adesso = (ulong)(tempoVero + casuale.Next(-1_000, 1_000));
            microfono.Leggi(periodo);
            if (giro > 3_000) distanzaMassima = Math.Max(distanzaMassima, Math.Abs(microfono.DistanzaLettura));
        }
        // Meno di 3 ms in media: ben dentro i 50 ms oltre i quali si salterebbe, e dentro il margine di chi scrive.
        Assert.True(distanzaMassima < 144, $"distanza massima {distanzaMassima} campioni");
    }

    /// <summary>
    /// La rete in mezzo: ogni frame arriva fra 10 e 50 ms dopo la cattura, a volte fuori ordine. Con il ritardo di 70 ms
    /// l'uscita, che legge 10 ms alla volta, trova sempre l'audio: nessun buco per cinque secondi.
    /// </summary>
    [Fact]
    public void IlBufferAntiJitterAssorbeLaRete()
    {
        var orologio = new OrologioFinto();
        using var microfono = new MicrofonoTelefono(_ => new DecodificatoreFinto(), orologio.Leggi);
        microfono.Imposta(FormatoAudio.AAC48kMono());
        const long scarto = 123_456;
        var inizio = orologio.Adesso;
        var casuale = new Random(3);
        // (istante d'arrivo, cattura) di 250 frame, poi le letture ogni 10 ms: tutto in ordine di tempo.
        var eventi = new List<(ulong Quando, ulong? Cattura)>();
        for (var i = 0; i < 250; i++)
        {
            var cattura = inizio + (ulong)(i * 21_333.33);
            eventi.Add((cattura + (ulong)casuale.Next(10_000, 50_000), cattura));
        }
        for (var t = inizio; t < inizio + 5_200_000; t += 10_000) eventi.Add((t, null));
        var buchi = 0;
        var letture = 0;
        var periodo = new float[480];
        foreach (var (quando, cattura) in eventi.OrderBy(e => e.Quando))
        {
            orologio.Adesso = quando;
            if (cattura is ulong c)
            {
                microfono.Ricevi(new PacchettoAudio((ulong)((long)c + scarto), [40]), scarto, latenzaVideoMs: null);
                continue;
            }
            var validi = microfono.Leggi(periodo);
            // Dal primo audio (cattura + 70 ms + 20 ms di lettura) fino all'ultimo frame, tutto pieno.
            if (quando < inizio + 150_000 || quando > inizio + 5_000_000) continue;
            letture++;
            if (validi < periodo.Length) buchi++;
        }
        Assert.True(letture > 400);
        Assert.Equal(0, buchi);
    }

    /// <summary>Sulla rete locale: il telefono finto manda formato-audio e pacchetti audio, la sessione li passa avanti.</summary>
    [Fact]
    public async Task LaSessionePassaFormatoEPacchettiAudio()
    {
        var limite = TimeSpan.FromSeconds(15);
        using var idComputer = IdentitaDispositivo.Nuova();
        var abbinamento = new Abbinamento(idComputer);
        using var ascoltatore = new Ascoltatore(System.Net.IPAddress.Loopback, porta: 0);
        var formato = new TaskCompletionSource<FormatoAudio>(TaskCreationOptions.RunContinuationsAsynchronously);
        var audio = new TaskCompletionSource<PacchettoAudio>(TaskCreationOptions.RunContinuationsAsynchronously);
        var statistiche = new TaskCompletionSource<Statistiche>(TaskCreationOptions.RunContinuationsAsynchronously);
        var sessione = new TaskCompletionSource<SessioneComputer>(TaskCreationOptions.RunContinuationsAsynchronously);
        ascoltatore.NuovoTelefono += presa =>
        {
            var nuova = new SessioneComputer(presa, "PC di prova", abbinamento, TimeSpan.FromMilliseconds(200));
            nuova.FormatoAudioRicevuto += f => formato.TrySetResult(f);
            nuova.AudioRicevuto += a => audio.TrySetResult(a);
            nuova.StatisticheAggiornate += s => { if (s.PacchettiAudio > 0) statistiche.TrySetResult(s); };
            nuova.Avvia();
            sessione.TrySetResult(nuova);
        };
        await using var telefono = new TelefonoFinto();
        await telefono.CollegaAsync(ascoltatore.Porta, gettone: abbinamento.Gettone);
        await telefono.AttendiAsync<Benvenuto>().WaitAsync(limite);

        // Un formato assurdo si ignora, quello vero passa.
        await telefono.InviaAsync(new FormatoAudio("aac-lc", 5_000_000, 1, "EYg="));
        await telefono.InviaAsync(FormatoAudio.AAC48kMono());
        Assert.Equal(FormatoAudio.AAC48kMono(), await formato.Task.WaitAsync(limite));

        using var fine = new CancellationTokenSource(limite);
        var invio = Task.Run(async () =>
        {
            while (!fine.IsCancellationRequested && !statistiche.Task.IsCompleted)
            {
                await telefono.InviaAsync(new PacchettoAudio(42, [0x21, 0x10, 0x04]).ComePacchetto());
                await Task.Delay(21);
            }
        });
        var arrivato = await audio.Task.WaitAsync(limite);
        Assert.Equal(42UL, arrivato.Timestamp);
        Assert.Equal(new byte[] { 0x21, 0x10, 0x04 }, arrivato.Dati);
        Assert.True((await statistiche.Task.WaitAsync(limite)).PacchettiAudio > 0);
        await invio;
        // Il telefono finto risponde ai ping: la differenza fra gli orologi c'è.
        var attiva = await sessione.Task;
        for (var i = 0; i < 50 && attiva.ScartoOrologi is null; i++) await Task.Delay(100);
        Assert.NotNull(attiva.ScartoOrologi);
        await attiva.ChiudiAsync();
    }

    [Fact]
    public void FormatoAudioSanificato()
    {
        Assert.Equal(FormatoAudio.AAC48kMono(), ValoriSicuri.Sanifica(FormatoAudio.AAC48kMono()));
        Assert.NotNull(ValoriSicuri.Sanifica(new FormatoAudio("aac-lc", 44_100, 2, "EhA=")));
        Assert.Null(ValoriSicuri.Sanifica(new FormatoAudio("aac-lc", 1_000_000, 1, "EYg=")));
        Assert.Null(ValoriSicuri.Sanifica(new FormatoAudio("aac-lc", 48_000, 0, "EYg=")));
        Assert.Null(ValoriSicuri.Sanifica(new FormatoAudio("aac-lc", 48_000, 1, new string('A', 1000))));
    }

    [Fact]
    public void TestiDellaRigaDelMicrofono()
    {
        var cavo = new DispositivoAudio("{2}", "CABLE Input (VB-Audio Virtual Cable)");
        var altoparlanti = new DispositivoAudio("{1}", "Altoparlanti (Realtek(R) Audio)");

        var senzaTelefono = StatoMicrofono.Descrivi(false, null, true, false, cavo, true, null);
        Assert.Equal(("attivo", "Collega un telefono per usarlo.", false, false),
            (senzaTelefono.Stato, senzaTelefono.Nota, senzaTelefono.Attivo, senzaTelefono.Utilizzabile));
        Assert.Null(StatoMicrofono.Descrivi(true, null, false, false, null, false, null).Nota);
        Assert.Equal("Il telefono non manda l'audio.", StatoMicrofono.Descrivi(true, false, true, false, cavo, true, null).Nota);

        // Senza cavo il testo onesto si vede anche da spento; con il cavo scelto, il nome del microfono da usare.
        var senzaCavo = StatoMicrofono.Descrivi(true, true, false, false, null, false, null);
        Assert.Equal("spento", senzaCavo.Stato);
        Assert.StartsWith("Su Windows il microfono del telefono si sente nelle app con un cavo audio virtuale", senzaCavo.Nota);
        Assert.True(senzaCavo.Utilizzabile);
        var conCavo = StatoMicrofono.Descrivi(true, true, true, true, cavo, true, null);
        Assert.Equal("Nelle app scegli «CABLE Output (VB-Audio Virtual Cable)» come microfono.", conCavo.Nota);
        Assert.True(conCavo.Attivo);
        Assert.Null(StatoMicrofono.Descrivi(true, true, false, false, cavo, true, null).Nota);
        Assert.Equal("In attesa dell'audio dal telefono…", StatoMicrofono.Descrivi(true, true, true, false, cavo, true, null).Nota);
        Assert.Equal("Scegli il cavo audio virtuale qui sotto: le app lo ricevono come microfono.",
            StatoMicrofono.Descrivi(true, true, true, true, null, true, null).Nota);
        Assert.Contains("serve un cavo audio virtuale", StatoMicrofono.Descrivi(true, true, true, true, altoparlanti, false, null).Nota);
        Assert.Equal("Uscita audio non disponibile: la scheda audio è stata staccata o disattivata.",
            StatoMicrofono.Descrivi(true, true, true, true, cavo, true, "la scheda audio è stata staccata o disattivata").Nota);
    }

    [Fact]
    public void CaviVirtualiEScelta()
    {
        Assert.True(UsciteAudio.ECavoVirtuale("CABLE Input (VB-Audio Virtual Cable)"));
        Assert.True(UsciteAudio.ECavoVirtuale("Voicemeeter Input (VB-Audio Voicemeeter VAIO)"));
        Assert.True(UsciteAudio.ECavoVirtuale("Line 1 (Virtual Audio Cable)"));
        Assert.False(UsciteAudio.ECavoVirtuale("Altoparlanti (Realtek(R) Audio)"));
        Assert.False(UsciteAudio.ECavoVirtuale(null));
        Assert.Equal("CABLE Output (VB-Audio Virtual Cable)", UsciteAudio.IngressoDelCavo("CABLE Input (VB-Audio Virtual Cable)"));
        Assert.Equal("Voicemeeter Output (VB-Audio Voicemeeter VAIO)", UsciteAudio.IngressoDelCavo("Voicemeeter Input (VB-Audio Voicemeeter VAIO)"));
        Assert.Null(UsciteAudio.IngressoDelCavo("Altoparlanti (Realtek(R) Audio)"));

        var altoparlanti = new DispositivoAudio("{1}", "Altoparlanti (Realtek(R) Audio)");
        var cavo = new DispositivoAudio("{2}", "CABLE Input (VB-Audio Virtual Cable)");
        var cuffie = new DispositivoAudio("{3}", "Cuffie (USB)");
        // Niente salvato: il primo cavo, mai gli altoparlanti da soli.
        Assert.Equal(cavo, UsciteAudio.Scelta([altoparlanti, cavo], null));
        Assert.Null(UsciteAudio.Scelta([altoparlanti, cuffie], null));
        // La scelta dell'utente vince, anche «nessuna»; se l'uscita salvata non c'è più, di nuovo il cavo.
        Assert.Equal(cuffie, UsciteAudio.Scelta([altoparlanti, cavo, cuffie], "{3}"));
        Assert.Null(UsciteAudio.Scelta([altoparlanti, cavo], ""));
        Assert.Equal(cavo, UsciteAudio.Scelta([altoparlanti, cavo], "{9}"));
    }
}
