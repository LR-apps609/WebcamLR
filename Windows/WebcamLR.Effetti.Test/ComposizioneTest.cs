using WebcamLR.Protocollo;
using Xunit;
using Xunit.Abstractions;

namespace WebcamLR.Effetti.Test;

/// <summary>
/// Qualità 4 e 5: il passo a piena risoluzione dello sfondo (bordo pulito, light wrap, calore, miscela), sul processore
/// e, su Windows, sulla scheda video; la scelta tra le due e il ripiego.
/// </summary>
public class ComposizioneTest(ITestOutputHelper uscita)
{
    /// <summary>Un'immagine di un colore solo.</summary>
    private static ImmagineBgra Tinta(int l, int a, byte b, byte g, byte r)
    {
        var immagine = new ImmagineBgra(l, a);
        for (var i = 0; i < l * a * 4; i += 4)
        {
            immagine.Dati[i] = b;
            immagine.Dati[i + 1] = g;
            immagine.Dati[i + 2] = r;
            immagine.Dati[i + 3] = 255;
        }
        return immagine;
    }

    /// <summary>
    /// Il pixel atteso con i valori campionati in virgola mobile alla posizione del pixel, come lo shader:
    /// <see cref="RegoleBordo.Canale"/> con il bilineare di <see cref="Elaborazione.Campionamento"/>.
    /// </summary>
    private static ImmagineBgra Riferimento(PianoComposizione piano)
    {
        var src = piano.Sorgente;
        int l = src.Larghezza, a = src.Altezza;
        var uscita = new ImmagineBgra(l, a);
        var fondo = piano.FondoPieno ?? piano.FondoPiccolo!;
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var alfa = Bilineare(piano.Alfa, piano.LarghezzaAlfa, piano.AltezzaAlfa, 1, 0, x, y, l, a) / 255f;
                var morbida = piano.MascheraMorbida is { } mm
                    ? Bilineare(mm, piano.LarghezzaMorbida, piano.AltezzaMorbida, 1, 0, x, y, l, a) / 255f
                    : 0f;
                for (var k = 0; k < 3; k++)
                {
                    float? colore = piano.ColorePersona is { } c ? Bilineare(c.Dati, c.Larghezza, c.Altezza, 4, k, x, y, l, a) : null;
                    float? sfondo = piano.SfondoMorbido is { } s ? Bilineare(s.Dati, s.Larghezza, s.Altezza, 4, k, x, y, l, a) : null;
                    var v = RegoleBordo.Canale(src.Dati[(y * l + x) * 4 + k], alfa,
                        Bilineare(fondo.Dati, fondo.Larghezza, fondo.Altezza, 4, k, x, y, l, a), colore, piano.Calore?[2 - k], sfondo, morbida);
                    uscita.Dati[(y * l + x) * 4 + k] = (byte)Math.Clamp(Math.Floor(v + 0.5), 0, 255);
                }
                uscita.Dati[(y * l + x) * 4 + 3] = 255;
            }
        }
        return uscita;
    }

    private static float Bilineare(byte[] dati, int lp, int ap, int canali, int k, int x, int y, int l, int a)
    {
        var px = Math.Clamp((x + 0.5) * lp / l - 0.5, 0, lp - 1);
        var py = Math.Clamp((y + 0.5) * ap / a - 0.5, 0, ap - 1);
        int x0 = (int)px, y0 = (int)py, x1 = Math.Min(x0 + 1, lp - 1), y1 = Math.Min(y0 + 1, ap - 1);
        float fx = (float)(px - x0), fy = (float)(py - y0);
        float V(int xx, int yy) => dati[(yy * lp + xx) * canali + k];
        var sopra = V(x0, y0) + (V(x1, y0) - V(x0, y0)) * fx;
        var sotto = V(x0, y1) + (V(x1, y1) - V(x0, y1)) * fx;
        return sopra + (sotto - sopra) * fy;
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void IlProcessoreFaIContiDelloShader(bool sostituito)
    {
        // Gli stessi conti di Composizione.hlsl (RegoleBordo.Canale con il bilineare in virgola mobile): il processore
        // arrotonda i valori ingranditi ai byte, quindi al massimo 2 di differenza.
        var piano = PianoDiProva.Crea(320, 180, sostituito);
        var cpu = new ImmagineBgra(320, 180);
        new ComposizioneProcessore().Componi(piano, cpu);
        var (massima, media) = PianoDiProva.Differenza(cpu, Riferimento(piano));
        uscita.WriteLine($"{(sostituito ? "sostituito" : "sfocato")}: differenza massima {massima}, media {media:0.000}");
        Assert.InRange(massima, 0, 2);
        Assert.InRange(media, 0, 0.3);
    }

    /// <summary>
    /// Persona grigio scuro (60) nella metà sinistra, vecchio sfondo bianco (250) a destra; l'orlo (colonne 76–83 di 160)
    /// è un misto dei due, con la maschera che scende da 1 a 0 sugli stessi pixel.
    /// </summary>
    private static (ImmagineBgra Sorgente, byte[] Alfa) OrloMisto(int l, int a)
    {
        var src = new ImmagineBgra(l, a);
        var alfa = new byte[l * a];
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var m = Math.Clamp((l / 2 + 4 - x) / 8f, 0f, 1f);
                var v = (byte)Math.Round(60 * m + 250 * (1 - m));
                var o = (y * l + x) * 4;
                src.Dati[o] = src.Dati[o + 1] = src.Dati[o + 2] = v;
                src.Dati[o + 3] = 255;
                alfa[y * l + x] = (byte)Math.Round(m * 255);
            }
        }
        return (src, alfa);
    }

    [Fact]
    public void IlBordoPulitoTogliIlVecchioSfondo()
    {
        // Sfondo nuovo nero: dove la maschera è parziale il vecchio bianco resterebbe come un alone chiaro. Con il bordo
        // pulito il colore viene dall'interno della persona (60).
        const int l = 160, a = 40;
        var (src, alfa) = OrloMisto(l, a);
        var nero = Tinta(l, a, 0, 0, 0);
        var colore = Tinta(l / 4, a / 4, 60, 60, 60);
        var senza = new ImmagineBgra(l, a);
        var con = new ImmagineBgra(l, a);
        var cpu = new ComposizioneProcessore();
        cpu.Componi(new PianoComposizione { Sorgente = src, Alfa = alfa, LarghezzaAlfa = l, AltezzaAlfa = a, FondoPieno = nero }, senza);
        cpu.Componi(new PianoComposizione
        {
            Sorgente = src, Alfa = alfa, LarghezzaAlfa = l, AltezzaAlfa = a, FondoPieno = nero, ColorePersona = colore,
        }, con);
        for (var x = 78; x <= 82; x++)
        {
            var m = alfa[20 * l + x] / 255f;
            int prima = senza.Dati[(20 * l + x) * 4], dopo = con.Dati[(20 * l + x) * 4];
            // Senza: il misto con il bianco × alfa; con: verso il grigio della persona quanto meno ci si fida del pixel.
            var f = RegoleBordo.Fiducia(m);
            var atteso = (src.Dati[(20 * l + x) * 4] * f + 60 * (1 - f)) * m;
            Assert.True(dopo < prima - 10, $"colonna {x}: {prima} → {dopo}");
            Assert.InRange(dopo, (int)atteso - 2, (int)atteso + 2);
        }
        // Dentro la persona non cambia nulla.
        Assert.Equal(senza.Dati[(20 * l + 20) * 4], con.Dati[(20 * l + 20) * 4]);
    }

    [Fact]
    public void IlLightWrapSchiarisceSoloLOrlo()
    {
        // Persona scura sopra uno sfondo nuovo chiaro: il light wrap porta un po' di quella luce sull'orlo interno,
        // al massimo il 15%, niente dentro la persona e niente nello sfondo.
        const int l = 160, a = 40;
        var src = Tinta(l, a, 50, 50, 50);
        var alfa = new byte[l * a];
        for (var y = 0; y < a; y++)
            for (var x = 0; x < l; x++)
                alfa[y * l + x] = (byte)Math.Round(Math.Clamp((l / 2 + 2 - x) / 4f, 0f, 1f) * 255);
        var chiaro = Tinta(l, a, 240, 240, 240);
        var morbida = new byte[l / 4 * (a / 4)];
        for (var y = 0; y < a / 4; y++)
            for (var x = 0; x < l / 4; x++)
                morbida[y * (l / 4) + x] = (byte)Math.Round(Math.Clamp((l / 8 + 1 - x) / 3f, 0f, 1f) * 255);
        var senza = new ImmagineBgra(l, a);
        var con = new ImmagineBgra(l, a);
        var cpu = new ComposizioneProcessore();
        cpu.Componi(new PianoComposizione { Sorgente = src, Alfa = alfa, LarghezzaAlfa = l, AltezzaAlfa = a, FondoPieno = chiaro }, senza);
        cpu.Componi(new PianoComposizione
        {
            Sorgente = src, Alfa = alfa, LarghezzaAlfa = l, AltezzaAlfa = a, FondoPieno = chiaro,
            SfondoMorbido = Tinta(l / 4, a / 4, 240, 240, 240), MascheraMorbida = morbida, LarghezzaMorbida = l / 4, AltezzaMorbida = a / 4,
        }, con);
        int Px(ImmagineBgra i, int x) => i.Dati[(20 * l + x) * 4];
        Assert.Equal(Px(senza, 10), Px(con, 10));     // dentro: alfa 1, maschera morbida 1
        Assert.Equal(Px(senza, 150), Px(con, 150));   // fuori: alfa 0
        var schiarito = Enumerable.Range(70, 14).Max(x => Px(con, x) - Px(senza, x));
        Assert.InRange(schiarito, 3, (int)(0.15 * (240 - 50)) + 1);
        Assert.All(Enumerable.Range(0, l), x => Assert.True(Px(con, x) >= Px(senza, x)));
    }

    [Fact]
    public void ConLoSfondoSostitutoIlCompositorePreparaBordoPulitoELuce()
    {
        // Dalla resa vera: persona rossa su un vecchio sfondo verde a scacchi, sfondo nuovo blu. Lontano dal bordo la
        // persona e lo sfondo nuovo restano esatti; nella fascia del bordo il verde del vecchio sfondo cala rispetto al
        // livello bilineare (senza bordo pulito).
        const int l = 320, a = 180;
        var scena = new ImmagineBgra(l, a);
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var o = (y * l + x) * 4;
                if (x < l / 2) (scena.Dati[o], scena.Dati[o + 1], scena.Dati[o + 2]) = ((byte)40, (byte)40, (byte)200);
                else (scena.Dati[o], scena.Dati[o + 1], scena.Dati[o + 2]) = ((byte)30, (byte)230, (byte)30);
                scena.Dati[o + 3] = 255;
            }
        }
        // Maschera un po' più larga della persona: l'orlo prende il verde.
        var valori = new byte[256 * 144];
        for (var y = 0; y < 144; y++)
            for (var x = 0; x < 256; x++)
                valori[y * 256 + x] = (byte)Math.Round(Math.Clamp((134 - x) / 8f, 0f, 1f) * 255);
        var maschera = new MascheraPersona(valori, 256, 144, ModelloRitaglio.Leggero, 1);
        var blu = Tinta(64, 36, 250, 0, 0);
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondiPronti.Ufficio, IntensitaSfondo = 0.55 };
        var istantanea = new StatoEffettiComputer.Istantanea(imp, (SfondiPronti.Ufficio, blu, 1), null, null);
        ImmagineBgra Rendi(LivelloResa livello)
        {
            var uscitaImmagine = new ImmagineBgra(l, a);
            Assert.True(new Compositore().Rendi(new IngressoResa(scena, null, null, maschera, null, null, 1 / 30.0), istantanea, livello,
                uscitaImmagine));
            return uscitaImmagine;
        }
        var pieno = Rendi(LivelloResa.Pieno);
        var bilineare = Rendi(LivelloResa.Veloce);
        int G(ImmagineBgra i, int x) => i.Dati[(90 * l + x) * 4 + 1];
        Assert.Equal((40, 40, 200), (pieno.Dati[(90 * l + 20) * 4], pieno.Dati[(90 * l + 20) * 4 + 1], pieno.Dati[(90 * l + 20) * 4 + 2]));
        Assert.Equal((250, 0, 0), (pieno.Dati[(90 * l + 310) * 4], pieno.Dati[(90 * l + 310) * 4 + 1], pieno.Dati[(90 * l + 310) * 4 + 2]));
        var verdePieno = Enumerable.Range(150, 30).Sum(x => G(pieno, x));
        var verdeBilineare = Enumerable.Range(150, 30).Sum(x => G(bilineare, x));
        uscita.WriteLine($"verde nella fascia del bordo: pieno {verdePieno}, bilineare {verdeBilineare}");
        Assert.True(verdePieno < verdeBilineare * 0.8, $"pieno {verdePieno}, bilineare {verdeBilineare}");
    }

    // MARK: scheda video o processore (Qualità 5)

    /// <summary>Una «scheda video» finta: scrive un grigio fisso (così si vede chi ha composto), o lancia un errore.</summary>
    private sealed class SchedaFinta(Func<int, bool>? fallisce = null) : IComposizione
    {
        public int Chiamate;
        public bool Chiusa;
        public string Descrizione => "scheda video, finta";
        public bool SullaSchedaVideo => true;

        public void Componi(PianoComposizione piano, ImmagineBgra destinazione)
        {
            var n = ++Chiamate;
            if (fallisce?.Invoke(n) == true) throw new InvalidOperationException("dispositivo rimosso");
            Array.Fill(destinazione.Dati, (byte)7);
        }

        public void Dispose() => Chiusa = true;
    }

    private static readonly ImpostazioniMotore Sfocato = new() { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55 };

    /// <summary>Rende finché <paramref name="fatto"/> non è vero (la scheda video si apre in sottofondo), al massimo 5 s.</summary>
    private static ImmagineBgra RendiFinche(Compositore compositore, Func<ImmagineBgra, bool> fatto)
    {
        var scena = Tinta(160, 90, 30, 120, 200);
        var maschera = new MascheraPersona(Enumerable.Repeat((byte)128, 256 * 144).ToArray(), 256, 144, ModelloRitaglio.Leggero, 1);
        var risultato = new ImmagineBgra(160, 90);
        var fine = DateTime.UtcNow.AddSeconds(5);
        do
        {
            Assert.True(compositore.Rendi(new IngressoResa(scena, null, null, maschera, null, null, 1 / 30.0),
                new StatoEffettiComputer.Istantanea(Sfocato, null, null, null), LivelloResa.Pieno, risultato));
            if (fatto(risultato)) return risultato;
            Thread.Sleep(5);
        } while (DateTime.UtcNow < fine);
        return risultato;
    }

    private static bool Finta(ImmagineBgra i) => i.Dati[0] == 7 && i.Dati[1] == 7;

    [Fact]
    public void LaSchedaVideoSiApreInSottofondoEPoiCompone()
    {
        var scheda = new SchedaFinta();
        using var compositore = new Compositore(() => scheda);
        Assert.False(compositore.ComponeSullaSchedaVideo);
        Assert.True(Finta(RendiFinche(compositore, Finta)));
        Assert.True(compositore.ComponeSullaSchedaVideo);
        var cambi = compositore.PrendiCambi();
        Assert.Equal([new CambioComposizione(true, "scheda video, finta", null)], cambi);
        compositore.Dispose();
        Assert.True(scheda.Chiusa);
    }

    [Fact]
    public void SeLaSchedaVideoNonSiApreRestaIlProcessore()
    {
        var tentativi = 0;
        using var compositore = new Compositore(() =>
        {
            Interlocked.Increment(ref tentativi);
            throw new NotSupportedException("Direct3D 11 (livello 11.0) non si apre");
        });
        var cambi = new List<CambioComposizione>();
        RendiFinche(compositore, _ =>
        {
            cambi.AddRange(compositore.PrendiCambi());
            return cambi.Count > 0;
        });
        Assert.Equal([new CambioComposizione(false, "processore", "Direct3D 11 (livello 11.0) non si apre")], cambi);
        // Non si riprova: altri fotogrammi, sempre il processore, nessun tentativo in più.
        for (var i = 0; i < 5; i++) Assert.False(Finta(RendiFinche(compositore, _ => true)));
        Assert.Equal(1, tentativi);
        Assert.False(compositore.ComponeSullaSchedaVideo);
    }

    [Fact]
    public void SchedaVideoPersaIlFotogrammaSiRifaSulProcessoreESiRiapreUnaVolta()
    {
        // Un compositore solo sul processore dà il fotogramma atteso.
        using var soloProcessore = new Compositore();
        var atteso = RendiFinche(soloProcessore, _ => true);
        var aperture = 0;
        var schede = new List<SchedaFinta>();
        using var compositore = new Compositore(() =>
        {
            Interlocked.Increment(ref aperture);
            var nuova = new SchedaFinta(_ => true); // ogni composizione fallisce (TDR)
            lock (schede) schede.Add(nuova);
            return nuova;
        });
        var cambi = new List<CambioComposizione>();
        // Ogni fotogramma con la scheda che fallisce esce comunque, uguale a quello del processore.
        // La riapertura avviene in sottofondo: su una macchina lenta (GitHub CI) può servire più di 40 giri,
        // quindi si aspetta a tempo (fino a 10 s) e non a numero di fotogrammi.
        var orologio = System.Diagnostics.Stopwatch.StartNew();
        while (orologio.Elapsed < TimeSpan.FromSeconds(10) && cambi.Count(c => !c.SullaSchedaVideo) < 2)
        {
            var r = RendiFinche(compositore, _ => true);
            Assert.Equal(atteso.Dati, r.Dati);
            cambi.AddRange(compositore.PrendiCambi());
            Thread.Sleep(5);
        }
        // Presa, persa (si riapre), presa di nuovo, persa per sempre.
        Assert.Equal([true, false, true, false], cambi.Select(c => c.SullaSchedaVideo));
        Assert.Contains("si riapre", cambi[1].Motivo);
        Assert.DoesNotContain("si riapre", cambi[3].Motivo);
        Assert.Equal(2, aperture);
        Assert.All(schede, s => Assert.True(s.Chiusa));
        Assert.All(schede, s => Assert.Equal(Compositore.ErroriSchedaVideoPerLasciare, s.Chiamate));
        for (var i = 0; i < 5; i++) RendiFinche(compositore, _ => true);
        Assert.Equal(2, aperture);
    }

    [Fact]
    public void UnErroreIsolatoNonFaLasciareLaSchedaVideo()
    {
        var scheda = new SchedaFinta(n => n % 2 == 0); // un fotogramma sì e uno no
        using var compositore = new Compositore(() => scheda);
        RendiFinche(compositore, Finta);
        for (var i = 0; i < 10; i++) RendiFinche(compositore, _ => true);
        Assert.True(compositore.ComponeSullaSchedaVideo);
        Assert.False(scheda.Chiusa);
    }

    [Fact]
    public void IlMotoreScriveDoveSiComponeLoSfondo()
    {
        var stato = new StatoEffettiComputer();
        stato.Imposta(Sfocato);
        var scheda = new SchedaFinta();
        using var motore = new MotoreEffetti(stato, _ => new FonteMascheraFissa(), creaComposizione: () => scheda);
        motore.Abilita(true);
        var note = new List<MotoreEffetti.Nota>();
        var fine = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < fine && !note.OfType<MotoreEffetti.Nota.Composizione>().Any())
        {
            using var fatto = new SemaphoreSlim(0);
            var immagine = motore.PrendiIngresso(160, 90);
            Assert.True(motore.Elabora(immagine, _ => fatto.Release()));
            fatto.Wait(2000);
            note.AddRange(motore.PrendiNote());
        }
        var nota = Assert.Single(note.OfType<MotoreEffetti.Nota.Composizione>());
        Assert.True(nota.SullaSchedaVideo);
        Assert.Equal("scheda video, finta", nota.Descrizione);
    }

    private sealed class FonteMascheraFissa : IFonteMaschera
    {
        public MascheraPersona Calcola(ImmagineBgra immagine) =>
            new(Enumerable.Repeat((byte)200, 256 * 144).ToArray(), 256, 144, ModelloRitaglio.Leggero, 1);

        public string Descrizione => "fissa";
        public Acceleratore InUso => Acceleratore.Processore;
        public ModelloRitaglio Modello => ModelloRitaglio.Leggero;
        public string? MotivoRipiego => null;
        public void Dispose() { }
    }

    [Fact]
    public void SchedaVideoVeraComeIlProcessore()
    {
        // Su Linux (e macOS) Direct3D 11 non c'è: l'errore è chiaro e il motore resta sul processore.
        if (!OperatingSystem.IsWindows())
        {
            var errore = Assert.Throws<PlatformNotSupportedException>(() => ComposizioneSchedaVideo.Crea(ancheSoftware: true));
            uscita.WriteLine($"niente scheda video qui: {errore.Message}");
            return;
        }
        // Su Windows (anche la CI, con WARP): Crea compila lo shader e si verifica; poi tre fotogrammi a 1080p contro il
        // processore, con i tempi.
        using var gpu = ComposizioneSchedaVideo.Crea(ancheSoftware: true);
        uscita.WriteLine(gpu.Descrizione);
        var cpu = new ComposizioneProcessore();
        foreach (var sostituito in new[] { false, true })
        {
            var piano = PianoDiProva.Crea(1920, 1080, sostituito);
            var attesa = new ImmagineBgra(1920, 1080);
            var ottenuta = new ImmagineBgra(1920, 1080);
            cpu.Componi(piano, attesa);
            var orologio = System.Diagnostics.Stopwatch.StartNew();
            for (var i = 0; i < 3; i++) gpu.Componi(piano, ottenuta);
            var (massima, media) = PianoDiProva.Differenza(attesa, ottenuta);
            uscita.WriteLine($"{(sostituito ? "sostituito" : "sfocato")}: {orologio.Elapsed.TotalMilliseconds / 3:0.0} ms per fotogramma, " +
                             $"differenza massima {massima}, media {media:0.000}");
            Assert.InRange(massima, 0, ComposizioneSchedaVideo.DifferenzaMassima);
            Assert.InRange(media, 0, ComposizioneSchedaVideo.DifferenzaMediaMassima);
        }
    }
}
