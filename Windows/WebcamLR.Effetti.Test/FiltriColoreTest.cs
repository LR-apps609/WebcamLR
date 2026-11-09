using WebcamLR.Protocollo;
using Xunit;
using Xunit.Abstractions;

namespace WebcamLR.Effetti.Test;

/// <summary>
/// Qualità 12: i filtri di colore sull'immagine intera, anche nella composizione dello sfondo (scheda video e processore,
/// con gli stessi interi), e quanto costano.
/// </summary>
public class FiltriColoreTest(ITestOutputHelper uscita)
{
    private static readonly string[] FiltriVeri = Filtri.Tutti.Where(f => f != Filtri.Naturale).ToArray();

    /// <summary>
    /// I conti di Composizione.hlsl (funzione Colore) in C#, con le tabelle e le righe che riceve la scheda video
    /// (<see cref="CatenaColore.StadiPerSchedaVideo"/>): un pixel BGRA, sul posto.
    /// </summary>
    private static void ComeLoShader(CatenaColore catena, Span<byte> pixel)
    {
        int r = pixel[2], g = pixel[1], b = pixel[0];
        foreach (var (ingresso, m, somma, usc) in catena.StadiPerSchedaVideo())
        {
            int ir = ingresso[0][r], ig = ingresso[1][g], ib = ingresso[2][b];
            var nr = Math.Clamp((m[0] * ir + m[1] * ig + m[2] * ib + somma[0]) >> 12, 0, 4095);
            var ng = Math.Clamp((m[3] * ir + m[4] * ig + m[5] * ib + somma[1]) >> 12, 0, 4095);
            var nb = Math.Clamp((m[6] * ir + m[7] * ig + m[8] * ib + somma[2]) >> 12, 0, 4095);
            (r, g, b) = (usc[0][nr], usc[1][ng], usc[2][nb]);
        }
        (pixel[2], pixel[1], pixel[0]) = ((byte)r, (byte)g, (byte)b);
    }

    public static IEnumerable<object[]> Catene()
    {
        foreach (var filtro in Filtri.Tutti)
        {
            yield return [filtro, 0.0, 0.0, 0.0];
            yield return [filtro, 0.2, -0.3, 0.5];
        }
        // Solo le regolazioni, e una catena solo per canale (Luminoso senza regolazioni è già sopra).
        yield return [Filtri.Naturale, 0.0, 0.4, 0.0];
    }

    [Theory]
    [MemberData(nameof(Catene))]
    public void LeTabelleDellaSchedaVideoDannoLoStessoRisultatoAlBit(string filtro, double luminosita, double contrasto, double saturazione)
    {
        var catena = RicetteColore.Catena(filtro, luminosita, contrasto, saturazione);
        if (catena is null)
        {
            Assert.Equal(Filtri.Naturale, filtro);
            return;
        }
        Assert.InRange(catena.StadiInteri, 1, PianoComposizione.MassimoStadiColore);
        // Tutti i grigi e 20 000 colori a caso: la catena del processore (anche con AVX2) e i conti dello shader.
        var caso = new Random(12);
        var pixel = new byte[(256 + 20_000) * 4];
        for (var i = 0; i < pixel.Length; i += 4)
        {
            if (i / 4 < 256) pixel[i] = pixel[i + 1] = pixel[i + 2] = (byte)(i / 4);
            else (pixel[i], pixel[i + 1], pixel[i + 2]) = ((byte)caso.Next(256), (byte)caso.Next(256), (byte)caso.Next(256));
            pixel[i + 3] = 255;
        }
        var shader = pixel.ToArray();
        catena.Applica(pixel);
        for (var i = 0; i < shader.Length; i += 4) ComeLoShader(catena, shader.AsSpan(i, 4));
        Assert.Equal(pixel, shader);
    }

    [Fact]
    public void ConIlCaloreLaCatenaStaNellaComposizione()
    {
        // Senza sfondo il calore entra nella catena (Compositore.Catena con il calore): anche così al massimo due stadi.
        foreach (var filtro in FiltriVeri)
        {
            var stadi = new List<StadioColore>();
            stadi.Add(RicetteColore.Calore(0.8)!);
            stadi.AddRange(RicetteColore.Filtro(filtro));
            stadi.Add(RicetteColore.Regolazioni(0.3, 0.3, 0.3)!);
            Assert.InRange(CatenaColore.Da(stadi)!.StadiInteri, 1, 2);
        }
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public void NellaComposizioneIlFiltroVaSuPersonaEFondo(bool sostituito, bool quadretti)
    {
        // Composizione con il filtro = composizione senza, poi il filtro su tutta l'immagine: al bit.
        foreach (var filtro in FiltriVeri)
        {
            var con = PianoDiProva.Crea(160, 90, sostituito, quadretti, filtro, regolazioni: true);
            var senza = PianoDiProva.Crea(160, 90, sostituito, quadretti);
            var ottenuta = new ImmagineBgra(160, 90);
            var attesa = new ImmagineBgra(160, 90);
            var cpu = new ComposizioneProcessore();
            cpu.Componi(con, ottenuta);
            cpu.Componi(senza, attesa);
            for (var y = 0; y < 90; y++) con.Colore!.Applica(attesa.Riga(y));
            Assert.True(attesa.Dati.SequenceEqual(ottenuta.Dati), filtro);
        }
    }

    [Theory]
    [InlineData(false, false, Filtri.Cinema)]
    [InlineData(true, false, Filtri.Seppia)]
    [InlineData(false, false, Filtri.Vivido)]
    [InlineData(false, true, Filtri.BiancoNero)]
    [InlineData(true, false, Filtri.Freddo)]
    public void ConIlFiltroIlProcessoreRestaVicinoAiContiDelloShader(bool sostituito, bool quadretti, string filtro)
    {
        // Lo shader compone in virgola mobile, arrotonda ai byte e poi applica le stesse tabelle intere: il riferimento è
        // quello di ComposizioneTest con il filtro dopo. Il processore compone in interi (al massimo 2 di differenza): il
        // filtro la allarga solo sui pochi pixel scuri e saturi, dove un canale vicino allo zero passa dalla parte ripida
        // della curva sRGB (fino a 10), ma in media resta sotto la soglia della scheda video. Per questo la verifica
        // all'apertura prova il colore a parte, al bit (ComposizioneSchedaVideo.ConfrontaColore).
        var piano = PianoDiProva.Crea(320, 180, sostituito, quadretti, filtro, regolazioni: true);
        var cpu = new ImmagineBgra(320, 180);
        new ComposizioneProcessore().Componi(piano, cpu);
        var shader = ComposizioneTest.Riferimento(piano);
        for (var y = 0; y < 180; y++) piano.Colore!.Applica(shader.Riga(y));
        var (massima, media) = PianoDiProva.Differenza(cpu, shader);
        var oltre = 0;
        for (var i = 0; i < cpu.Dati.Length; i++)
            if (i % 4 != 3 && Math.Abs(cpu.Dati[i] - shader.Dati[i]) > ComposizioneSchedaVideo.DifferenzaMassima) oltre++;
        uscita.WriteLine($"{(sostituito ? "sostituito" : quadretti ? "mosaico" : "sfocato")}, {filtro} e regolazioni: " +
                         $"differenza massima {massima}, media {media:0.000}, valori oltre 4: {oltre} su {320 * 180 * 3}");
        Assert.InRange(massima, 0, 16);
        Assert.InRange(media, 0, ComposizioneSchedaVideo.DifferenzaMediaMassima / 4);
        Assert.InRange(oltre, 0, 320 * 180 * 3 / 1000);
    }

    [Fact]
    public void IlConfrontoDelColoreTrovaUnoShaderSbagliato()
    {
        // ConfrontaColore con il processore al posto della scheda video: 0. Con una «scheda» che sbaglia le tabelle di un
        // livello (come un errore nello shader): la verifica lo vede.
        foreach (var (sostituito, quadretti, filtro, regolazioni) in ComposizioneSchedaVideo.ProveColore)
        {
            Assert.Equal(0, ComposizioneSchedaVideo.ConfrontaColore(new ComposizioneProcessore(), 200, 112, sostituito, quadretti, filtro, regolazioni));
            Assert.True(ComposizioneSchedaVideo.ConfrontaColore(new Sbagliata(), 200, 112, sostituito, quadretti, filtro, regolazioni)
                        > ComposizioneSchedaVideo.DifferenzaMassimaColore, filtro);
        }
    }

    /// <summary>Compone sul processore e, con il colore, alza di 2 il rosso.</summary>
    private sealed class Sbagliata : IComposizione
    {
        public string Descrizione => "sbagliata";
        public bool SullaSchedaVideo => true;

        public void Componi(PianoComposizione piano, ImmagineBgra destinazione)
        {
            new ComposizioneProcessore().Componi(piano, destinazione);
            if (piano.Colore is null) return;
            for (var i = 2; i < destinazione.Dati.Length; i += 4) destinazione.Dati[i] = (byte)Math.Min(255, destinazione.Dati[i] + 2);
        }

        public void Dispose() { }
    }

    /// <summary>Una composizione finta che ricorda il piano e compone sul processore.</summary>
    private sealed class Registratrice : IComposizione
    {
        public readonly ComposizioneProcessore Processore = new();
        public PianoComposizione? Ultimo;
        public string Descrizione => "scheda video, che registra";
        public bool SullaSchedaVideo => true;

        public void Componi(PianoComposizione piano, ImmagineBgra destinazione)
        {
            Ultimo = piano;
            Processore.Componi(piano, destinazione);
        }

        public void Dispose() { }
    }

    private static ImmagineBgra Scena(int l, int a)
    {
        var scena = new ImmagineBgra(l, a);
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var o = (y * l + x) * 4;
                (scena.Dati[o], scena.Dati[o + 1], scena.Dati[o + 2], scena.Dati[o + 3]) =
                    ((byte)(30 + x), (byte)(200 - y), (byte)((x * 3 + y) % 256), (byte)255);
            }
        }
        return scena;
    }

    private static MascheraPersona MetaPersona() => new(Enumerable.Range(0, 256 * 144).Select(i => (byte)(i % 256 < 128 ? 230 : 10)).ToArray(),
        256, 144, ModelloRitaglio.Leggero, 1);

    /// <summary>Rende finché la composizione finta non è aperta (si apre in sottofondo), al massimo 5 s.</summary>
    private static ImmagineBgra Rendi(Compositore compositore, ImpostazioniMotore imp, Registratrice? scheda, IReadOnlyList<Rettangolo>? volti = null)
    {
        var scena = Scena(160, 90);
        var risultato = new ImmagineBgra(160, 90);
        var fine = DateTime.UtcNow.AddSeconds(5);
        do
        {
            Assert.True(compositore.Rendi(new IngressoResa(scena, null, null, imp.SfondoAcceso ? MetaPersona() : null, volti, 0, 1 / 30.0),
                new StatoEffettiComputer.Istantanea(imp, null, null, null), LivelloResa.Pieno, risultato));
            if (scheda is null || scheda.Ultimo is not null) return risultato;
            Thread.Sleep(5);
        } while (DateTime.UtcNow < fine);
        return risultato;
    }

    [Fact]
    public void ConLoSfondoIlFiltroVaNellaComposizione()
    {
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55, Filtro = Filtri.Caldo, Contrasto = 0.2 };
        var scheda = new Registratrice();
        using var compositore = new Compositore(() => scheda);
        var conScheda = Rendi(compositore, imp, scheda);
        Assert.NotNull(scheda.Ultimo?.Colore);
        // Lo stesso fotogramma sul processore solo: identico (il filtro è nella composizione anche lì).
        using var soloProcessore = new Compositore();
        Assert.Equal(Rendi(soloProcessore, imp, null).Dati, conScheda.Dati);
        // E uguale allo sfondo senza filtro con il filtro dopo, su tutta l'immagine.
        using var senza = new Compositore();
        var attesa = Rendi(senza, imp with { Filtro = Filtri.Naturale, Contrasto = 0 }, null);
        var catena = RicetteColore.Catena(Filtri.Caldo, 0, 0.2, 0)!;
        for (var y = 0; y < attesa.Altezza; y++) catena.Applica(attesa.Riga(y));
        Assert.Equal(attesa.Dati, conScheda.Dati);
    }

    [Fact]
    public void ConLaPelleIlFiltroRestaDopo()
    {
        // Il ritocco della pelle lavora sui colori veri: con un volto e la pelle accesa il filtro non va nella composizione.
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55, Filtro = Filtri.BiancoNero, Pelle = 0.5 };
        var scheda = new Registratrice();
        using var compositore = new Compositore(() => scheda);
        var risultato = Rendi(compositore, imp, scheda, [new Rettangolo(0.2, 0.2, 0.3, 0.4)]);
        Assert.NotNull(scheda.Ultimo);
        Assert.Null(scheda.Ultimo!.Colore);
        // Il filtro c'è lo stesso, dopo: bianco e nero.
        for (var i = 0; i < risultato.Dati.Length; i += 4)
            Assert.InRange(Math.Abs(risultato.Dati[i] - risultato.Dati[i + 2]), 0, 1);
    }

    [Fact]
    public void SenzaSfondoIlFiltroVaSuTuttaLImmagine()
    {
        foreach (var filtro in FiltriVeri)
        {
            using var compositore = new Compositore();
            var risultato = Rendi(compositore, new ImpostazioniMotore { Filtro = filtro }, null);
            var attesa = Scena(160, 90);
            var catena = RicetteColore.Catena(filtro, 0, 0, 0)!;
            for (var y = 0; y < attesa.Altezza; y++) catena.Applica(attesa.Riga(y));
            if (filtro == Filtri.Cinema) continue; // con la vignettatura dopo
            Assert.True(attesa.Dati.SequenceEqual(risultato.Dati), filtro);
        }
    }

    [Fact]
    public void QuantoCostaIlFiltroA1080p()
    {
        // Il filtro da solo (una riga alla volta, come la resa) e nella composizione dello sfocato sul processore. Sulla
        // scheda video la composizione con il filtro costa al processore solo il viaggio del fotogramma.
        var piano = PianoDiProva.Crea(1920, 1080, false, false, Filtri.Caldo, regolazioni: true);
        var senza = PianoDiProva.Crea(1920, 1080, false);
        var cpu = new ComposizioneProcessore();
        var destinazione = new ImmagineBgra(1920, 1080);
        double Misura(Action azione)
        {
            for (var i = 0; i < 3; i++) azione();
            var tempi = new List<double>();
            for (var i = 0; i < 15; i++)
            {
                var orologio = System.Diagnostics.Stopwatch.StartNew();
                azione();
                tempi.Add(orologio.Elapsed.TotalMilliseconds);
            }
            tempi.Sort();
            return tempi[tempi.Count / 2];
        }
        var soloFiltro = Misura(() => Elaborazione.PerRighe(1080, (inizio, fine) =>
        {
            for (var y = inizio; y < fine; y++) piano.Colore!.Applica(destinazione.Riga(y));
        }));
        var composizione = Misura(() => cpu.Componi(senza, destinazione));
        var conFiltro = Misura(() => cpu.Componi(piano, destinazione));
        uscita.WriteLine($"1080p, {Environment.ProcessorCount} processori: filtro Caldo + regolazioni da solo {soloFiltro:0.0} ms; " +
                         $"composizione dello sfocato {composizione:0.0} ms, con il filtro dentro {conFiltro:0.0} ms");
        // Larghissimo: è una misura, non una gara (la macchina è condivisa).
        Assert.InRange(soloFiltro, 0, 200);
    }
}
