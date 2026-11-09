using System.Diagnostics;
using WebcamLR.Protocollo;
using Xunit;
using Xunit.Abstractions;

namespace WebcamLR.Effetti.Test;

/// <summary>
/// Qualità 7 e 8: bokeh, mosaico e verde per il chroma key, su immagini sintetiche, sul processore (la scheda video fa gli
/// stessi conti: ComposizioneTest.IlProcessoreFaIContiDelloShader e la verifica all'apertura).
/// </summary>
public class SfondiNuoviTest(ITestOutputHelper uscita)
{
    private const byte RossoPersona = 200;

    /// <summary>
    /// Persona rossa nella parte sinistra (colonne &lt; <paramref name="bordo"/>), sfondo da <paramref name="sfondo"/> a destra.
    /// </summary>
    private static ImmagineBgra Scena(int l, int a, int bordo, Func<int, int, (byte B, byte G, byte R)> sfondo)
    {
        var immagine = new ImmagineBgra(l, a);
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var (b, g, r) = x < bordo ? ((byte)40, (byte)40, RossoPersona) : sfondo(x, y);
                var o = (y * l + x) * 4;
                immagine.Dati[o] = b;
                immagine.Dati[o + 1] = g;
                immagine.Dati[o + 2] = r;
                immagine.Dati[o + 3] = 255;
            }
        }
        return immagine;
    }

    /// <summary>La maschera esatta: persona nelle colonne &lt; <paramref name="parte"/> × larghezza.</summary>
    private static MascheraPersona Maschera(double parte, int l = 256, int a = 144)
    {
        var valori = new byte[l * a];
        for (var y = 0; y < a; y++)
            for (var x = 0; x < (int)(l * parte); x++) valori[y * l + x] = 255;
        return new MascheraPersona(valori, l, a, ModelloRitaglio.Leggero, 1);
    }

    private static (int B, int G, int R) Pixel(ImmagineBgra immagine, int x, int y)
    {
        var o = (y * immagine.Larghezza + x) * 4;
        return (immagine.Dati[o], immagine.Dati[o + 1], immagine.Dati[o + 2]);
    }

    private static ImmagineBgra Rendi(ImmagineBgra scena, MascheraPersona maschera, ImpostazioniMotore imp,
        LivelloResa livello = LivelloResa.Pieno)
    {
        var risultato = new ImmagineBgra(scena.Larghezza, scena.Altezza);
        Assert.True(new Compositore().Rendi(new IngressoResa(scena, null, null, maschera, null, null, 1 / 30.0),
            new StatoEffettiComputer.Istantanea(imp, null, null, null), livello, risultato));
        return risultato;
    }

    // MARK: stili e livelli

    [Fact]
    public void UnoStileSconosciutoValeNormale()
    {
        Assert.Equal(StiliSfocatura.Normale, StiliSfocatura.Valido(null));
        Assert.Equal(StiliSfocatura.Normale, StiliSfocatura.Valido("acquerello"));
        Assert.Equal(StiliSfocatura.Bokeh, StiliSfocatura.Valido(StiliSfocatura.Bokeh));
        Assert.Equal(StiliSfocatura.Mosaico, StiliSfocatura.Valido(StiliSfocatura.Mosaico));
    }

    [Theory]
    [InlineData(LivelloResa.Pieno, StiliSfocatura.Bokeh)]
    [InlineData(LivelloResa.BordoLeggero, StiliSfocatura.Bokeh)]
    [InlineData(LivelloResa.MascheraAlterna, StiliSfocatura.Bokeh)]
    [InlineData(LivelloResa.Veloce, StiliSfocatura.Normale)]
    [InlineData(LivelloResa.Minimo, StiliSfocatura.Normale)]
    public void IlBokehAiLivelliVelociTornaNormale(LivelloResa livello, string atteso)
    {
        Assert.Equal(atteso, StiliSfocatura.AlLivello(StiliSfocatura.Bokeh, livello));
        // Il mosaico costa poco: resta a tutti i livelli.
        Assert.Equal(StiliSfocatura.Mosaico, StiliSfocatura.AlLivello(StiliSfocatura.Mosaico, livello));
    }

    // MARK: mosaico

    [Fact]
    public void IlMosaicoFaQuadrettiNettiDelloSfondo()
    {
        // Sfondo a sfumatura (ogni colonna diversa): nel mosaico ogni quadretto è di un colore solo.
        const int l = 640, a = 360;
        var scena = Scena(l, a, l / 4, (x, y) => ((byte)(x * 255 / l), (byte)(y * 255 / a), 30));
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, Sfocatura = StiliSfocatura.Mosaico, IntensitaSfondo = 1 };
        var risultato = Rendi(scena, Maschera(0.25), imp);
        var (colonne, righe) = RicetteSfondo.Griglia(l, a, 1);
        uscita.WriteLine($"griglia {colonne}×{righe}, lato {RicetteSfondo.LatoQuadretto(1, a)} px");
        Assert.Equal(RicetteSfondo.LatoQuadretto(1, a), 16);
        // Un quadretto lontano dalla persona: tutti i suoi pixel uguali. Il quadretto j ha le righe y con ⌊y · righe / A⌋ = j.
        static int Inizio(int i, int quanti, int lato) => (i * lato + quanti - 1) / quanti;
        int i = 30, j = 10;
        int x0 = Inizio(i, colonne, l), x1 = Inizio(i + 1, colonne, l), y0 = Inizio(j, righe, a), y1 = Inizio(j + 1, righe, a);
        var primo = Pixel(risultato, x0, y0);
        for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++) Assert.Equal(primo, Pixel(risultato, x, y));
        // Il quadretto accanto è di un altro colore, e il salto è netto (da un pixel all'altro).
        var accanto = Pixel(risultato, x1, y0);
        Assert.NotEqual(primo, accanto);
        Assert.Equal(accanto, Pixel(risultato, x1 + 3, y1 - 1));
        // Il colore è la media del quadretto: la sfumatura al centro del quadretto.
        Assert.InRange(primo.B, (x0 + x1) / 2 * 255 / l - 6, (x0 + x1) / 2 * 255 / l + 6);
        // La persona resta com'è.
        Assert.Equal((40, 40, (int)RossoPersona), Pixel(risultato, 40, 180));
    }

    [Fact]
    public void IlMosaicoNonPortaLaPersonaNeiQuadrettiSullOrlo()
    {
        // Persona rossa, sfondo verde: i quadretti appena a destra del bordo restano verdi (senza il peso dello sfondo
        // prenderebbero mezzo rosso).
        const int l = 640, a = 360;
        var scena = Scena(l, a, 330, (_, _) => (30, 180, 30));
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, Sfocatura = StiliSfocatura.Mosaico, IntensitaSfondo = 1 };
        var risultato = Rendi(scena, Maschera(330.0 / 640), imp);
        for (var x = 345; x < 400; x += 3)
        {
            var (_, g, r) = Pixel(risultato, x, 180);
            Assert.True(r < 60, $"rosso {r} alla colonna {x}");
            Assert.True(g > 150, $"verde {g} alla colonna {x}");
        }
    }

    [Fact]
    public void IQuadrettiCresconoConLIntensita()
    {
        Assert.Equal(21, RicetteSfondo.LatoQuadretto(0.25, 1080));
        Assert.Equal(32, RicetteSfondo.LatoQuadretto(0.55, 1080));
        Assert.Equal(48, RicetteSfondo.LatoQuadretto(1, 1080));
        Assert.Equal((40, 22), RicetteSfondo.Griglia(1920, 1080, 1));
        Assert.Equal(4, RicetteSfondo.LatoQuadretto(0, 100));
    }

    // MARK: verde

    [Fact]
    public void IlVerdeEPienoEIlBordoENetto()
    {
        const int l = 320, a = 180;
        // Il vecchio sfondo chiaro (una parete): il filtro guidato non ha colori simili alla persona a cui agganciarsi.
        var scena = Scena(l, a, l / 2, (x, y) => (x + y) % 2 == 0 ? ((byte)215, (byte)215, (byte)215) : ((byte)200, (byte)205, (byte)210));
        var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondoVerde.Id, IntensitaSfondo = 0 };
        var risultato = Rendi(scena, Maschera(0.5), imp);
        var verde = ((int)SfondoVerde.Colore.B, (int)SfondoVerde.Colore.G, (int)SfondoVerde.Colore.R);
        Assert.Equal((0x40, 0xB1, 0x00), verde);
        // Tutto lo sfondo è esattamente #00B140, anche vicino alla persona: niente light wrap, niente verde sfocato.
        for (var y = 0; y < a; y += 7)
            for (var x = l / 2 + 4; x < l; x++) Assert.Equal(verde, Pixel(risultato, x, y));
        // La persona è intatta fino a pochi pixel dal bordo (il light wrap la schiarirebbe di più verso l'orlo).
        for (var x = 0; x < l / 2 - 3; x++) Assert.Equal((40, 40, (int)RossoPersona), Pixel(risultato, x, 90));
        // Il passaggio è stretto: al massimo 6 colonne miste (né persona né verde) a 320 px.
        var miste = 0;
        for (var x = 0; x < l; x++)
        {
            var p = Pixel(risultato, x, 90);
            if (p != verde && p != (40, 40, (int)RossoPersona)) miste++;
        }
        uscita.WriteLine($"colonne miste sul bordo: {miste}");
        Assert.InRange(miste, 0, 6);
    }

    [Fact]
    public void IlVerdeNonDipendeDallIntensitaNeDalLivello()
    {
        const int l = 320, a = 180;
        var scena = Scena(l, a, l / 2, (_, _) => (200, 200, 200));
        var verde = ((int)SfondoVerde.Colore.B, (int)SfondoVerde.Colore.G, (int)SfondoVerde.Colore.R);
        foreach (var livello in Enum.GetValues<LivelloResa>())
        {
            foreach (var intensita in new[] { 0.0, 1.0 })
            {
                var imp = new ImpostazioniMotore { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondoVerde.Id, IntensitaSfondo = intensita };
                var risultato = Rendi(scena, Maschera(0.5), imp, livello);
                Assert.Equal(verde, Pixel(risultato, 300, 20));
                Assert.Equal((40, 40, (int)RossoPersona), Pixel(risultato, 20, 90));
            }
        }
    }

    // MARK: bokeh

    /// <summary>
    /// Sfondo scuro (20) con una luce bianca 8×8 da (<paramref name="cx"/> − 4, <paramref name="cy"/> − 4): una lampadina
    /// lontana, 2×2 pixel pieni a un quarto della misura se il centro è un multiplo di 4.
    /// </summary>
    private static ImmagineBgra ScenaConLuce(int l, int a, int cx, int cy) =>
        Scena(l, a, l / 4, (x, y) => x >= cx - 4 && x < cx + 4 && y >= cy - 4 && y < cy + 4
            ? ((byte)255, (byte)255, (byte)255) : ((byte)20, (byte)20, (byte)20));

    [Fact]
    public void ConIlBokehUnaLuceDiventaUnDisco()
    {
        const int l = 640, a = 360, cx = 440, cy = 180;
        var scena = ScenaConLuce(l, a, cx, cy);
        var bokeh = Rendi(scena, Maschera(0.25), new ImpostazioniMotore
        {
            Sfondo = ModiSfondo.Sfocato, Sfocatura = StiliSfocatura.Bokeh, IntensitaSfondo = 1,
        });
        var normale = Rendi(scena, Maschera(0.25), new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 1 });
        var raggio = RicetteSfondo.RaggioBokeh(1, a);
        uscita.WriteLine($"raggio del disco {raggio:0.0} px");
        var profiloBokeh = Enumerable.Range(0, 40).Select(d => Pixel(bokeh, cx + d, cy).G).ToArray();
        var profiloNormale = Enumerable.Range(0, 40).Select(d => Pixel(normale, cx + d, cy).G).ToArray();
        uscita.WriteLine("bokeh:   " + string.Join(" ", profiloBokeh));
        uscita.WriteLine("normale: " + string.Join(" ", profiloNormale));
        // Un disco: chiaro e quasi piatto dentro (dal centro a 0,6 del raggio), scuro fuori (oltre 1,4 raggi).
        var dentro = profiloBokeh[..(int)(raggio * 0.6)];
        Assert.True(dentro.Min() > 90, $"dentro il disco il minimo è {dentro.Min()}");
        Assert.True(dentro.Max() - dentro.Min() < dentro.Max() / 3, $"il disco non è piatto: {dentro.Min()}–{dentro.Max()}");
        Assert.True(profiloBokeh[(int)(raggio * 1.4)] < 35, $"fuori dal disco {profiloBokeh[(int)(raggio * 1.4)]}");
        // La sfocatura normale spegne la luce: a metà raggio il bokeh è molto più chiaro.
        var meta = (int)(raggio * 0.5);
        Assert.True(profiloBokeh[meta] > profiloNormale[meta] + 40, $"a metà raggio: bokeh {profiloBokeh[meta]}, normale {profiloNormale[meta]}");
    }

    [Fact]
    public void IlBokehTieneIColoriMediDelloSfondo()
    {
        // Senza luci forti il bokeh non schiarisce né scurisce: uno sfondo grigio medio resta grigio medio.
        const int l = 320, a = 180;
        var scena = Scena(l, a, l / 4, (x, y) => (x / 6 + y / 6) % 2 == 0 ? ((byte)150, (byte)150, (byte)150) : ((byte)90, (byte)90, (byte)90));
        var risultato = Rendi(scena, Maschera(0.25), new ImpostazioniMotore
        {
            Sfondo = ModiSfondo.Sfocato, Sfocatura = StiliSfocatura.Bokeh, IntensitaSfondo = 1,
        });
        for (var x = 160; x < 320; x += 16)
        {
            var (b, g, r) = Pixel(risultato, x, 90);
            Assert.InRange(g, 105, 135);
            Assert.Equal(b, g);
            Assert.Equal(r, g);
        }
    }

    [Fact]
    public void IlBokehNonPortaLaPersonaNelloSfondo()
    {
        const int l = 640, a = 360;
        var scena = Scena(l, a, 330, (_, _) => (30, 180, 30));
        var risultato = Rendi(scena, Maschera(330.0 / 640), new ImpostazioniMotore
        {
            Sfondo = ModiSfondo.Sfocato, Sfocatura = StiliSfocatura.Bokeh, IntensitaSfondo = 1,
        });
        Assert.Equal((40, 40, (int)RossoPersona), Pixel(risultato, 100, 180));
        for (var x = 345; x < 420; x += 5)
        {
            var (_, _, r) = Pixel(risultato, x, 180);
            Assert.True(r < 50, $"rosso {r} alla colonna {x}");
        }
    }

    [Fact]
    public void AlLivelloVeloceIlBokehEUgualeAllaSfocaturaNormale()
    {
        const int l = 320, a = 180;
        var scena = ScenaConLuce(l, a, 220, 90);
        var bokeh = Rendi(scena, Maschera(0.25), new ImpostazioniMotore
        {
            Sfondo = ModiSfondo.Sfocato, Sfocatura = StiliSfocatura.Bokeh, IntensitaSfondo = 1,
        }, LivelloResa.Veloce);
        var normale = Rendi(scena, Maschera(0.25), new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 1 },
            LivelloResa.Veloce);
        Assert.Equal(normale.Dati, bokeh.Dati);
    }

    [Fact]
    public void QuantoCostanoBokehEMosaicoA1080p()
    {
        // Solo il fondo piccolo, sul processore, come lo fa la resa (il passo a piena risoluzione è lo stesso dello sfocato).
        // Nel registro del test i tempi; il limite è largo (macchine di prova lente): conta l'ordine di grandezza.
        const int l = 1920, a = 1080;
        var scena = ScenaConLuce(l, a, 1300, 500);
        var quarto = Elaborazione.Dimezza(Elaborazione.Dimezza(scena));
        var persona = Elaborazione.Campiona(Maschera(0.25).Valori, 256, 144, quarto.Larghezza, quarto.Altezza);
        var lavagna = new RicetteSfondo.LavagnaBokeh();
        ImmagineBgra? fondo = null;
        double Misura(Action azione)
        {
            azione();
            var orologio = Stopwatch.StartNew();
            for (var i = 0; i < 10; i++) azione();
            return orologio.Elapsed.TotalMilliseconds / 10;
        }
        var raggio = RicetteSfondo.RaggioBokeh(1, a) * quarto.Larghezza / l;
        var bokeh = Misura(() => fondo = RicetteSfondo.Bokeh(quarto, persona, raggio, null, fondo, lavagna));
        var raggioMedio = RicetteSfondo.RaggioBokeh(0.55, a) * quarto.Larghezza / l;
        var bokehMedio = Misura(() => fondo = RicetteSfondo.Bokeh(quarto, persona, raggioMedio, null, fondo, lavagna));
        var ottavo = Elaborazione.Dimezza(quarto);
        var personaOttavo = Elaborazione.Campiona(Maschera(0.25).Valori, 256, 144, ottavo.Larghezza, ottavo.Altezza);
        ImmagineBgra? fondoOttavo = null;
        var bokehOttavo = Misura(() => fondoOttavo = RicetteSfondo.Bokeh(ottavo, personaOttavo, raggio / 2, null, fondoOttavo, lavagna));
        var (colonne, righe) = RicetteSfondo.Griglia(l, a, 0.55);
        ImmagineBgra? quadretti = null;
        var mosaico = Misura(() => quadretti = RicetteSfondo.Mosaico(quarto, persona, colonne, righe, null, quadretti));
        uscita.WriteLine($"1080p: bokeh Tanto a un quarto {bokeh:0.0} ms (raggio {raggio:0.0} px), a un ottavo {bokehOttavo:0.0} ms " +
                         $"(quello che si usa: gradino {RicetteSfondo.GradinoDisco(RicetteSfondo.RaggioBokeh(1, a), 0)}); " +
                         $"bokeh Medio a un quarto {bokehMedio:0.0} ms (raggio {raggioMedio:0.0} px); mosaico Medio {mosaico:0.0} ms ({colonne}×{righe})");
        // Tanto a 1080p si fa a un ottavo (raggio 16 > 10 al quarto), Medio al quarto.
        Assert.Equal(1, RicetteSfondo.GradinoDisco(RicetteSfondo.RaggioBokeh(1, a), 0));
        Assert.Equal(0, RicetteSfondo.GradinoDisco(RicetteSfondo.RaggioBokeh(0.55, a), 0));
        Assert.InRange(bokeh, 0, 250);
        Assert.InRange(mosaico, 0, 100);
    }
}
