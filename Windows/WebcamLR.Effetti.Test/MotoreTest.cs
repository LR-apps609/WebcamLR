using System.Diagnostics;
using WebcamLR.Protocollo;
using Xunit;
using Xunit.Abstractions;

namespace WebcamLR.Effetti.Test;

/// <summary>Le ricette, la resa sul processore e il motore (code, riservatezza, fine sessione), senza Windows.</summary>
public class MotoreTest(ITestOutputHelper uscita)
{
    // MARK: immagini di prova

    /// <summary>Persona rossa a sinistra (colonne &lt; metà), sfondo a scacchi verde chiaro/scuro a destra.</summary>
    private static ImmagineBgra Scena(int l, int a)
    {
        var immagine = new ImmagineBgra(l, a);
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var o = (y * l + x) * 4;
                if (x < l / 2)
                {
                    immagine.Dati[o + 2] = 200;
                    immagine.Dati[o + 1] = 40;
                    immagine.Dati[o] = 40;
                }
                else
                {
                    var chiaro = ((x / 8) + (y / 8)) % 2 == 0;
                    immagine.Dati[o + 1] = (byte)(chiaro ? 220 : 60);
                    immagine.Dati[o + 2] = 30;
                    immagine.Dati[o] = 30;
                }
                immagine.Dati[o + 3] = 255;
            }
        }
        return immagine;
    }

    /// <summary>La maschera esatta della scena: persona nella metà sinistra.</summary>
    private static MascheraPersona MascheraScena(int l = 256, int a = 144)
    {
        var valori = new byte[l * a];
        for (var y = 0; y < a; y++)
            for (var x = 0; x < l / 2; x++) valori[y * l + x] = 255;
        return new MascheraPersona(valori, l, a, ModelloRitaglio.Leggero, 1);
    }

    private static StatoEffettiComputer.Istantanea Con(ImpostazioniMotore impostazioni, (string, ImmagineBgra, int)? sfondo = null) =>
        new(impostazioni, sfondo, null, null);

    private static (byte B, byte G, byte R) Pixel(ImmagineBgra immagine, int x, int y)
    {
        var o = (y * immagine.Larghezza + x) * 4;
        return (immagine.Dati[o], immagine.Dati[o + 1], immagine.Dati[o + 2]);
    }

    // MARK: ricette di colore

    [Fact]
    public void NaturaleSenzaRegolazioniNonFaNiente()
    {
        Assert.Null(RicetteColore.Catena(Filtri.Naturale, 0, 0, 0));
        Assert.Null(RicetteColore.Catena("sconosciuto", 0, 0, 0));
        Assert.Null(RicetteColore.Calore(0));
    }

    [Fact]
    public void CaloreScaldaIlGrigioETieneIlBianco()
    {
        var catena = CatenaColore.Da([RicetteColore.Calore(1)!])!;
        Assert.True(catena.SoloPerCanale);
        byte[] grigio = [128, 128, 128, 255, 255, 255, 255, 255];
        catena.Applica(grigio);
        // B, G, R: il rosso sale, il blu scende.
        Assert.True(grigio[2] > 128 && grigio[0] < 128, $"grigio {grigio[2]},{grigio[1]},{grigio[0]}");
        // Il bianco del rosso resta al massimo (guadagno > 1, tagliato), il verde quasi uguale.
        Assert.Equal(255, grigio[6]);
        Assert.InRange((int)grigio[5], 250, 255);
    }

    [Fact]
    public void BiancoNeroDaGrigi()
    {
        var catena = RicetteColore.Catena(Filtri.BiancoNero, 0, 0, 0)!;
        byte[] pixel = [30, 160, 220, 255];
        catena.Applica(pixel);
        Assert.InRange(Math.Abs(pixel[0] - pixel[2]), 0, 1);
        Assert.InRange(Math.Abs(pixel[1] - pixel[2]), 0, 1);
    }

    [Fact]
    public void TuttiIFiltriSiCompilanoENonRovesciano()
    {
        foreach (var filtro in Filtri.Tutti.Where(f => f != Filtri.Naturale))
        {
            var catena = RicetteColore.Catena(filtro, 0, 0, 0);
            Assert.NotNull(catena);
            // Più chiaro resta più chiaro (le curve sono monotone).
            byte[] scuro = [60, 60, 60, 255], chiaro = [180, 180, 180, 255];
            catena!.Applica(scuro);
            catena.Applica(chiaro);
            var lumScuro = scuro[0] + scuro[1] + scuro[2];
            var lumChiaro = chiaro[0] + chiaro[1] + chiaro[2];
            Assert.True(lumChiaro > lumScuro, filtro);
        }
    }

    [Fact]
    public void OttoPixelInsiemeComeUnoAllaVolta()
    {
        // Con 8 pixel o più la catena usa le letture a gruppi (AVX2, se c'è); da soli il ciclo normale: stesso risultato.
        var catena = RicetteColore.Catena(Filtri.Cinema, 0.3, -0.2, 0.4)!;
        var caso = new Random(7);
        var riga = new byte[4 * 37];
        caso.NextBytes(riga);
        var unoAllaVolta = (byte[])riga.Clone();
        catena.Applica(riga);
        for (var i = 0; i < 37; i++) catena.Applica(unoAllaVolta.AsSpan(i * 4, 4));
        Assert.Equal(unoAllaVolta, riga);
    }

    [Fact]
    public void LuminositaPositivaSchiarisce()
    {
        var catena = RicetteColore.Catena(Filtri.Naturale, 1, 0, 0)!;
        byte[] pixel = [100, 100, 100, 255];
        catena.Applica(pixel);
        Assert.True(pixel[0] > 100);
    }

    [Fact]
    public void CurvaPassaPerIPunti()
    {
        var curva = Colore.Curva([(0, 0.04), (0.25, 0.33), (0.5, 0.59), (0.75, 0.81), (1, 1)]);
        Assert.Equal(0.33, curva(0.25), 6);
        Assert.Equal(0.59, curva(0.5), 6);
        Assert.Equal(1, curva(1), 6);
    }

    // MARK: mattoni

    [Fact]
    public void MiscelaVettorialeUgualeAQuellaSemplice()
    {
        var caso = new Random(3);
        var n = 4 * 131;
        var sopra = new byte[n];
        var sotto = new byte[n];
        var alfa = new byte[n];
        caso.NextBytes(sopra);
        caso.NextBytes(sotto);
        caso.NextBytes(alfa);
        var atteso = new byte[n];
        for (var i = 0; i < n; i++) atteso[i] = (byte)Math.Round((sopra[i] * alfa[i] + sotto[i] * (255 - alfa[i])) / 255.0);
        Compositore.Miscela(sopra, sotto, alfa);
        for (var i = 0; i < n; i++) Assert.InRange(sopra[i] - atteso[i], -1, 1);
    }

    [Fact]
    public void SogliaAttornoA042()
    {
        var uscita = new byte[3];
        Elaborazione.SogliaMorbida([0.42f, 0.0f, 1.0f], uscita, 0.5f);
        Assert.InRange((int)uscita[0], 126, 129);
        Assert.Equal(0, uscita[1]);
        Assert.Equal(255, uscita[2]);
    }

    [Theory]
    [InlineData(0.25, 0)]
    [InlineData(0.55, 1)]
    [InlineData(1.0, 2)]
    public void GradinoDellaSfocatura(double intensita, int gradino) =>
        Assert.Equal(gradino, Compositore.GradinoSfocatura(Compositore.SigmaSfocatura(intensita)));

    [Fact]
    public void FiltroGuidatoSegueIlBordoDellaGuida()
    {
        // Guida: bordo netto alla colonna 40. Maschera: bordo morbido spostato (colonne 30–50).
        int l = 80, a = 20;
        var guida = new float[l * a];
        var p = new float[l * a];
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                guida[y * l + x] = x < 40 ? 0.9f : 0.1f;
                p[y * l + x] = Math.Clamp((50 - x) / 20f, 0, 1);
            }
        }
        var q = Elaborazione.FiltroGuidato(guida, p, l, a, 4, 1e-3f);
        // Lontano dal bordo il filtro tiene la maschera; vicino, il salto si concentra sul bordo vero.
        Assert.True(q[10 * l + 38] - q[10 * l + 42] > p[10 * l + 38] - p[10 * l + 42]);
    }

    // MARK: resa

    [Fact]
    public void SfocaturaSenzaAloneNonPortaLaPersonaNelloSfondo()
    {
        var scena = Scena(640, 360);
        var compositore = new Compositore();
        var uscitaImmagine = new ImmagineBgra(640, 360);
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 1 };
        Assert.True(compositore.Rendi(new IngressoResa(scena, null, null, MascheraScena(), null, null, 1 / 30.0), Con(imp),
            LivelloResa.Pieno, uscitaImmagine));
        // Persona intatta lontano dal bordo.
        Assert.Equal((40, 40, 200), ((int, int, int))Pixel(uscitaImmagine, 100, 180));
        // Sfondo sfocato: gli scacchi diventano un verde medio, e accanto alla persona niente rosso (niente alone).
        for (var x = 340; x < 640; x += 20)
        {
            var (b, g, r) = Pixel(uscitaImmagine, x, 180);
            Assert.True(r < 50, $"rosso {r} alla colonna {x}");
            Assert.InRange((int)g, 90, 190);
        }
    }

    [Fact]
    public void SfondoSostituitoPrendeLImmagine()
    {
        var scena = Scena(320, 180);
        var blu = new ImmagineBgra(64, 36);
        for (var i = 0; i < blu.Dati.Length; i += 4)
        {
            blu.Dati[i] = 250;
            blu.Dati[i + 3] = 255;
        }
        var compositore = new Compositore();
        var risultato = new ImmagineBgra(320, 180);
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondiPronti.Ufficio, IntensitaSfondo = 1 };
        Assert.True(compositore.Rendi(new IngressoResa(scena, null, null, MascheraScena(), null, null, 1 / 30.0),
            Con(imp, (SfondiPronti.Ufficio, blu, 1)), LivelloResa.Pieno, risultato));
        Assert.Equal((250, 0, 0), ((int, int, int))Pixel(risultato, 300, 90));
        Assert.Equal((40, 40, 200), ((int, int, int))Pixel(risultato, 40, 90));
    }

    [Fact]
    public void SenzaMascheraLoSfondoNonSiConsegna()
    {
        var scena = Scena(160, 90);
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato };
        Assert.False(new Compositore().Rendi(new IngressoResa(scena, null, null, null, null, null, 1 / 30.0), Con(imp),
            LivelloResa.Pieno, new ImmagineBgra(160, 90)));
    }

    [Fact]
    public void SpecchioGiraLeColonne()
    {
        var scena = Scena(64, 36);
        var risultato = new ImmagineBgra(64, 36);
        Assert.True(new Compositore().Rendi(new IngressoResa(scena, null, null, null, null, null, 1 / 30.0),
            Con(new ImpostazioniMotore { Specchia = true }), LivelloResa.Pieno, risultato));
        for (var x = 0; x < 64; x++) Assert.Equal(Pixel(scena, x, 5), Pixel(risultato, 63 - x, 5));
    }

    [Fact]
    public void LuceSulVoltoSchiarisceSoloIlVolto()
    {
        var grigio = new ImmagineBgra(320, 180);
        for (var i = 0; i < grigio.Dati.Length; i++) grigio.Dati[i] = 90;
        var compositore = new Compositore();
        var risultato = new ImmagineBgra(320, 180);
        var volto = new Rettangolo(0.4, 0.3, 0.2, 0.3);
        for (var i = 0; i < 20; i++)
            compositore.Rendi(new IngressoResa(grigio, null, null, null, [volto], (ulong)i * 33_000, 1 / 30.0),
                Con(new ImpostazioniMotore { LuceVolto = true }), LivelloResa.Pieno, risultato);
        Assert.True(Pixel(risultato, 160, 90).B > 100);
        Assert.Equal(90, Pixel(risultato, 5, 5).B);
    }

    [Fact]
    public void LogoInAltoADestra()
    {
        var scena = new ImmagineBgra(1920, 1080);
        var logo = new ImmagineBgra(100, 50);
        for (var i = 0; i < logo.Dati.Length; i += 4)
        {
            logo.Dati[i + 2] = 255;
            logo.Dati[i + 3] = 255;
        }
        var risultato = new ImmagineBgra(1920, 1080);
        var istantanea = new StatoEffettiComputer.Istantanea(new ImpostazioniMotore { Logo = true }, null, (logo, 1), null);
        new Compositore().Rendi(new IngressoResa(scena, null, null, null, null, null, 1 / 30.0), istantanea, LivelloResa.Pieno, risultato);
        var (mx, my) = Compositore.Margini(1920, 1080);
        Assert.Equal(255, Pixel(risultato, 1920 - mx - 5, my + 5).R);
        Assert.Equal(0, Pixel(risultato, 1920 - mx + 5, my + 5).R);
        Assert.Equal((194, 97), Compositore.MisuraLogo(100, 50, 1920, 1080));
    }

    // MARK: volti e inquadratura

    [Fact]
    public void TestaDallaMaschera()
    {
        // Una persona: testa (cerchio) al centro in alto, spalle larghe sotto.
        int l = 256, a = 144;
        var valori = new byte[l * a];
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var testa = Math.Pow((x - 128) / 20.0, 2) + Math.Pow((y - 45) / 30.0, 2) <= 1;
                var spalle = y > 80 && Math.Abs(x - 128) < 70;
                if (testa || spalle) valori[y * l + x] = 255;
            }
        }
        var volto = VoltoDallaMaschera.Stima(new MascheraPersona(valori, l, a, ModelloRitaglio.Leggero, 1), 1920, 1080);
        Assert.NotNull(volto);
        Assert.InRange(volto!.Value.CentroX, 0.45, 0.55);
        Assert.InRange(volto.Value.Y, 0.08, 0.3);
        Assert.InRange(volto.Value.Larghezza, 0.08, 0.2);
    }

    [Fact]
    public void VoltoDallaPelleDelVolto()
    {
        int l = 256, a = 256;
        var volto = new byte[l * a];
        for (var y = 60; y < 120; y++)
            for (var x = 110; x < 150; x++) volto[y * l + x] = 255;
        var stima = VoltoDallaMaschera.Stima(new MascheraPersona(new byte[l * a], l, a, ModelloRitaglio.Pieno, 1, volto), 1920, 1080);
        Assert.NotNull(stima);
        Assert.InRange(stima!.Value.X, 105 / 256.0, 115 / 256.0);
        Assert.InRange(stima.Value.Basso, 115 / 256.0, 121 / 256.0);
    }

    [Fact]
    public void InquadraturaSiAvvicinaAlVoltoETorna()
    {
        var molla = new MollaInquadratura();
        var volto = new Rettangolo(0.6, 0.2, 0.08, 0.14);
        MollaInquadratura.Riquadro? riquadro = null;
        for (var i = 0; i < 90; i++) riquadro = molla.Passo([volto], (ulong)(i / 3 + 1), true, 1 / 30.0);
        Assert.NotNull(riquadro);
        Assert.InRange(riquadro!.Value.Zoom, 1.4, MollaInquadratura.ZoomMassimo);
        Assert.True(riquadro.Value.X > 0.55);
        // Spenta: torna all'inquadratura intera.
        for (var i = 0; i < 300; i++) riquadro = molla.Passo(null, null, false, 1 / 30.0);
        Assert.Null(riquadro);
        Assert.False(molla.InMovimento);
    }

    // MARK: livello

    [Fact]
    public void IlLivelloScendeSoloSeNonSiRegge()
    {
        var scelta = new SceltaLivello();
        for (var i = 0; i < 30; i++) scelta.Intervallo(33_333);
        for (var i = 0; i < SceltaLivello.FotogrammiPerDecidere; i++) Assert.Null(scelta.Aggiungi(10, 12, out _));
        Assert.Equal(LivelloResa.Pieno, scelta.Livello);
        // La resa troppo lenta: prima il bordo leggero.
        LivelloResa? nuovo = null;
        for (var i = 0; i < SceltaLivello.FotogrammiPerDecidere; i++) nuovo ??= scelta.Aggiungi(10, 40, out _);
        Assert.Equal(LivelloResa.BordoLeggero, nuovo);
        // La maschera troppo lenta: subito il veloce.
        nuovo = null;
        for (var i = 0; i < SceltaLivello.FotogrammiPerDecidere; i++) nuovo ??= scelta.Aggiungi(45, 10, out _);
        Assert.Equal(LivelloResa.Veloce, nuovo);
        scelta.Azzera();
        Assert.Equal(LivelloResa.Pieno, scelta.Livello);
    }

    // MARK: motore

    private sealed class FonteFinta(Func<MascheraPersona>? calcola = null, SemaphoreSlim? via = null) : IFonteMaschera
    {
        public int Chiamate;

        public MascheraPersona Calcola(ImmagineBgra immagine)
        {
            Interlocked.Increment(ref Chiamate);
            via?.Wait(5000);
            return (calcola ?? (() => MascheraScena()))();
        }

        public string Descrizione => "finta";
        public string? MotivoRipiego => null;
        public Acceleratore InUso => Acceleratore.Processore;
        public ModelloRitaglio Modello => ModelloRitaglio.Leggero;
        public void Dispose() { }
    }

    private static ImmagineBgra Riempita(MotoreEffetti motore, int l = 320, int a = 180)
    {
        var immagine = motore.PrendiIngresso(l, a);
        Scena(l, a).Dati.CopyTo(immagine.Dati, 0);
        return immagine;
    }

    [Fact]
    public void SpentoPassaCome()
    {
        var stato = new StatoEffettiComputer();
        using var motore = new MotoreEffetti(stato, _ => new FonteFinta());
        motore.Abilita(true);
        Assert.False(motore.Elabora(Riempita(motore), _ => { }));
        Assert.False(motore.Attivo);
        stato.Imposta(new ImpostazioniMotore { Calore = 0.3 });
        Assert.True(motore.Attivo);
        motore.Abilita(false);
        Assert.False(motore.Elabora(Riempita(motore), _ => { }));
    }

    [Fact]
    public void SfocaturaConsegnaConLaMascheraDelloStessoIstante()
    {
        var stato = new StatoEffettiComputer();
        stato.Imposta(new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55 });
        var fonte = new FonteFinta();
        using var motore = new MotoreEffetti(stato, _ => fonte);
        motore.Abilita(true);
        var consegnate = new List<ulong?>();
        using var fatto = new SemaphoreSlim(0);
        for (var i = 0; i < 5; i++)
        {
            var immagine = Riempita(motore);
            immagine.Timestamp = (ulong)i;
            Assert.True(motore.Elabora(immagine, u =>
            {
                lock (consegnate) consegnate.Add(u.Timestamp);
                fatto.Release();
            }));
            Assert.True(fatto.Wait(5000));
        }
        Assert.Equal([0UL, 1UL, 2UL, 3UL, 4UL], consegnate.Select(t => t!.Value));
        Assert.Equal(5, fonte.Chiamate);
        var misure = motore.PrendiMisure();
        Assert.NotNull(misure.MascheraMs);
        Assert.Equal((Acceleratore.Processore, ModelloRitaglio.Leggero), misure.Fonte);
    }

    [Fact]
    public void AlMassimoUnoInAttesaGliAltriSiScartano()
    {
        var stato = new StatoEffettiComputer();
        stato.Imposta(new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato });
        using var via = new SemaphoreSlim(0);
        using var motore = new MotoreEffetti(stato, _ => new FonteFinta(via: via));
        motore.Abilita(true);
        var consegnate = new List<ulong>();
        using var fatto = new SemaphoreSlim(0);
        for (var i = 0; i < 4; i++)
        {
            var immagine = Riempita(motore);
            immagine.Timestamp = (ulong)i;
            motore.Elabora(immagine, u =>
            {
                lock (consegnate) consegnate.Add(u.Timestamp!.Value);
                fatto.Release();
            });
        }
        // Il primo è in analisi, il quarto aspetta; il secondo e il terzo sono scartati.
        via.Release(10);
        Assert.True(fatto.Wait(5000));
        Assert.True(fatto.Wait(5000));
        Assert.Equal([0UL, 3UL], consegnate);
        Assert.Equal(2, motore.PrendiMisure().Scartati);
    }

    [Fact]
    public void DopoAzzeraIlFotogrammaInLavorazioneNonArriva()
    {
        var stato = new StatoEffettiComputer();
        stato.Imposta(new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato });
        using var via = new SemaphoreSlim(0);
        using var motore = new MotoreEffetti(stato, _ => new FonteFinta(via: via));
        motore.Abilita(true);
        var arrivate = 0;
        motore.Elabora(Riempita(motore), _ => Interlocked.Increment(ref arrivate));
        Thread.Sleep(50);
        motore.Azzera();
        via.Release(10);
        Thread.Sleep(300);
        Assert.Equal(0, arrivate);
    }

    [Fact]
    public void MascheraMancanteUsaLUltimaBuonaENonMaiLoSfondoVero()
    {
        var stato = new StatoEffettiComputer();
        stato.Imposta(new ImpostazioniMotore { Sfondo = ModiSfondo.Sostituito, IntensitaSfondo = 1 });
        var chiamate = 0;
        var fonte = new FonteFinta(() => ++chiamate == 1 ? MascheraScena() : throw new InvalidOperationException("prova"));
        using var motore = new MotoreEffetti(stato, _ => fonte);
        motore.Abilita(true);
        var risultati = new List<ImmagineBgra>();
        using var fatto = new SemaphoreSlim(0);
        for (var i = 0; i < 3; i++)
        {
            motore.Elabora(Riempita(motore), u =>
            {
                lock (risultati) risultati.Add(u.Copia());
                fatto.Release();
            });
            Assert.True(fatto.Wait(5000));
        }
        // Lo sfondo (a destra) è sempre quello sostituito (il fondo di Tema), anche senza maschera nuova.
        foreach (var r in risultati) Assert.Equal(Compositore.ColoreFondo.G, Pixel(r, 300, 90).G);
        Assert.Contains(motore.PrendiNote(), n => n is MotoreEffetti.Nota.ErroreMaschera);

        // Senza nessuna maschera buona: niente consegna.
        using var altro = new MotoreEffetti(stato, _ => new FonteFinta(() => throw new InvalidOperationException("mai")));
        altro.Abilita(true);
        var arrivate = 0;
        altro.Elabora(Riempita(altro), _ => Interlocked.Increment(ref arrivate));
        Thread.Sleep(300);
        Assert.Equal(0, arrivate);
    }

    // MARK: tempi

    [Fact]
    public void TempiA1080p()
    {
        var scena = Scena(1920, 1080);
        var compositore = new Compositore();
        var risultato = new ImmagineBgra(1920, 1080);
        var maschera = MascheraScena(256, 256);
        // Come nel motore: le riduzioni le fa l'analisi, non la resa.
        var meta = Elaborazione.Dimezza(scena);
        var quarto = Elaborazione.Dimezza(meta);
        void Misura(string nome, ImpostazioniMotore imp, LivelloResa livello = LivelloResa.Pieno)
        {
            var ingresso = new IngressoResa(scena, meta, quarto, imp.SfondoAcceso ? maschera : null, [new Rettangolo(0.2, 0.2, 0.12, 0.2)], 1, 1 / 30.0);
            // Prima un giro di riscaldamento (il compilatore ottimizza i cicli dopo qualche decina di chiamate), poi la mediana.
            for (var i = 0; i < 25; i++) compositore.Rendi(ingresso, Con(imp), livello, risultato);
            var tempi = new List<double>();
            for (var i = 0; i < 15; i++)
            {
                var orologio = Stopwatch.StartNew();
                compositore.Rendi(ingresso, Con(imp), livello, risultato);
                tempi.Add(orologio.Elapsed.TotalMilliseconds);
            }
            tempi.Sort();
            var ms = tempi[tempi.Count / 2];
            uscita.WriteLine($"{nome}: {ms:0.0} ms (mediana)");
            Assert.True(ms < 500, nome);
        }
        uscita.WriteLine($"Processori: {Environment.ProcessorCount}, vettori {System.Numerics.Vector<byte>.Count} byte");
        Misura("solo calore", new ImpostazioniMotore { Calore = 0.3 });
        Misura("filtro cinema + regolazioni", new ImpostazioniMotore { Filtro = Filtri.Cinema, Luminosita = 0.2, Saturazione = 0.3 });
        Misura("sfocatura Poco", new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.25 });
        Misura("sfocatura Medio", new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55 });
        Misura("sfocatura Tanto + calore", new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 1, Calore = 0.3 });
        Misura("sfocatura Medio, bordo leggero", new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55 }, LivelloResa.BordoLeggero);
        Misura("sfocatura Medio, veloce", new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55 }, LivelloResa.Veloce);
        Misura("sostituito", new ImpostazioniMotore { Sfondo = ModiSfondo.Sostituito, IntensitaSfondo = 0.5 });
        Misura("pelle + luce + specchio", new ImpostazioniMotore { Pelle = 0.6, LuceVolto = true, Specchia = true });
        Misura("tutto", new ImpostazioniMotore
        {
            Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55, Calore = 0.3, Pelle = 0.5, LuceVolto = true,
            Filtro = Filtri.Caldo, Contrasto = 0.2, Nitidezza = 0.3, Specchia = true, Inquadratura = true,
        });
        var orologio2 = Stopwatch.StartNew();
        Elaborazione.Dimezza(Elaborazione.Dimezza(scena, meta), quarto);
        uscita.WriteLine($"riduzione a metà e a un quarto (analisi): {orologio2.Elapsed.TotalMilliseconds:0.0} ms");
    }
}
