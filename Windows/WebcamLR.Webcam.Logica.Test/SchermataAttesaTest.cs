using System.Globalization;
using System.Text.RegularExpressions;
using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

/// <summary>Testi, colori e disegno della schermata di attesa (come quella del Mac).</summary>
public class SchermataAttesaTest
{
    private static readonly StatoAttesa[] Stati = [StatoAttesa.NonCollegata, StatoAttesa.Interrotta, StatoAttesa.Pausa];
    private static readonly LinguaAttesa[] DueLingue = [LinguaAttesa.Italiano, LinguaAttesa.Inglese];

    [Fact]
    public void TestiComeSulMac()
    {
        Assert.Equal("La webcam non è collegata", TestiAttesa.Titolo(StatoAttesa.NonCollegata, LinguaAttesa.Italiano));
        Assert.Equal("Apri WebcamLR sul telefono", TestiAttesa.Sottotitolo(StatoAttesa.NonCollegata, LinguaAttesa.Italiano));
        Assert.Equal("Collegamento interrotto", TestiAttesa.Titolo(StatoAttesa.Interrotta, LinguaAttesa.Italiano));
        Assert.Equal("Riconnessione in corso…", TestiAttesa.Sottotitolo(StatoAttesa.Interrotta, LinguaAttesa.Italiano));
        Assert.Equal("Webcam in pausa", TestiAttesa.Titolo(StatoAttesa.Pausa, LinguaAttesa.Italiano));
        Assert.Null(TestiAttesa.Sottotitolo(StatoAttesa.Pausa, LinguaAttesa.Italiano));
        Assert.Equal("The webcam is not connected", TestiAttesa.Titolo(StatoAttesa.NonCollegata, LinguaAttesa.Inglese));
        Assert.Null(TestiAttesa.Titolo(StatoAttesa.Nessuna, LinguaAttesa.Italiano));
    }

    [Fact]
    public void TestiUgualiAlCatalogoDelMac()
    {
        var catalogo = File.ReadAllText(Path.Combine(Radice(), "Mac", "Risorse", "Localizable.xcstrings"));
        foreach (var stato in Stati)
        {
            foreach (var italiano in new[] { TestiAttesa.Titolo(stato, LinguaAttesa.Italiano), TestiAttesa.Sottotitolo(stato, LinguaAttesa.Italiano) })
            {
                if (italiano is null) continue;
                var inglese = italiano == TestiAttesa.Titolo(stato, LinguaAttesa.Italiano)
                    ? TestiAttesa.Titolo(stato, LinguaAttesa.Inglese) : TestiAttesa.Sottotitolo(stato, LinguaAttesa.Inglese);
                // La voce italiana e, subito dopo, la sua traduzione inglese.
                var voce = Regex.Match(catalogo, "\"" + Regex.Escape(italiano) + "\"\\s*:\\s*\\{.*?\"en\".*?\"value\"\\s*:\\s*\"([^\"]*)\"", RegexOptions.Singleline);
                Assert.True(voce.Success, $"«{italiano}» non è nel catalogo del Mac");
                Assert.Equal(voce.Groups[1].Value, inglese);
            }
        }
    }

    [Fact]
    public void OgniTestoÈDisegnatoUgualeAlGeneratore()
    {
        var generatore = File.ReadAllText(Path.Combine(Radice(), "Strumenti", "genera_testi_attesa.py"));
        foreach (var lingua in DueLingue)
        {
            foreach (var stato in Stati)
            {
                foreach (var titolo in new[] { true, false })
                {
                    var testo = titolo ? TestiAttesa.Titolo(stato, lingua) : TestiAttesa.Sottotitolo(stato, lingua);
                    var chiave = TestiAttesa.Chiave(stato, lingua, titolo);
                    if (testo is null)
                    {
                        Assert.Null(MaschereTesti.Trova(chiave));
                        continue;
                    }
                    var breve = chiave[3..];
                    Assert.Contains($"\"{breve}\": \"{testo}\"", generatore);
                    var maschera = MaschereTesti.Trova(chiave);
                    Assert.NotNull(maschera);
                    Assert.Equal(maschera!.Larghezza * maschera.Altezza, maschera.Opacita.Length);
                    // Barlow Condensed da 168 e Barlow da 68 a 2160 righe: righe alte circa 200 e 80 pixel.
                    Assert.InRange(maschera.Altezza, titolo ? 180 : 70, titolo ? 220 : 95);
                    Assert.Contains((byte)255, maschera.Opacita);
                    // Margine vuoto a sinistra e a destra: niente lettere tagliate.
                    for (var y = 0; y < maschera.Altezza; y++)
                    {
                        Assert.Equal(0, maschera.Opacita[y * maschera.Larghezza]);
                        Assert.Equal(0, maschera.Opacita[y * maschera.Larghezza + maschera.Larghezza - 1]);
                    }
                }
            }
        }
        Assert.Equal(2160, MaschereTesti.AltezzaRiferimento);
        Assert.Equal(10, MaschereTesti.Chiavi.Count);
    }

    [Theory]
    [InlineData("it-IT", LinguaAttesa.Italiano)]
    [InlineData("it-CH", LinguaAttesa.Italiano)]
    [InlineData("it", LinguaAttesa.Italiano)]
    [InlineData("en-US", LinguaAttesa.Inglese)]
    [InlineData("de-DE", LinguaAttesa.Inglese)]
    [InlineData("", LinguaAttesa.Inglese)]
    public void ItalianoSoloSeWindowsÈInItaliano(string cultura, LinguaAttesa attesa)
    {
        Assert.Equal(attesa, Lingue.DaCultura(new CultureInfo(cultura)));
    }

    [Fact]
    public void LinguaDaLangIdEScelta()
    {
        Assert.Equal(LinguaAttesa.Italiano, Lingue.DaLangId(0x0410)); // it-IT
        Assert.Equal(LinguaAttesa.Italiano, Lingue.DaLangId(0x0810)); // it-CH
        Assert.Equal(LinguaAttesa.Inglese, Lingue.DaLangId(0x0409));
        Assert.Equal(LinguaAttesa.Inglese, Lingue.DaLangId(0x0407));
        // Quella dell'app vince; senza, quella del sistema.
        Assert.Equal(LinguaAttesa.Inglese, Lingue.Risolvi(LinguaAttesa.Inglese, LinguaAttesa.Italiano));
        Assert.Equal(LinguaAttesa.Italiano, Lingue.Risolvi(LinguaAttesa.Automatica, LinguaAttesa.Italiano));
        Assert.Equal(LinguaAttesa.Inglese, Lingue.Risolvi(LinguaAttesa.Automatica, LinguaAttesa.Automatica));
        Assert.Contains(LinguaDiSistema.Leggi(), DueLingue);
    }

    [Fact]
    public void ColoriUgualiAStile()
    {
        var tema = File.ReadAllText(Path.Combine(Radice(), "Stile", "Sources", "Stile", "Tema.swift"));
        foreach (var (nome, colore) in new[]
        {
            ("sfumaturaChiara", ColoriStile.SfumaturaChiara), ("sfumaturaScura", ColoriStile.SfumaturaScura),
            ("fondo", ColoriStile.Fondo), ("testo", ColoriStile.Testo), ("testoSecondario", ColoriStile.TestoSecondario),
        })
        {
            var trovato = Regex.Match(tema, $@"static let {nome} = Color\(esadecimale: 0x([0-9A-Fa-f]{{6}})\)");
            Assert.True(trovato.Success, $"{nome} non trovato in Tema.swift");
            Assert.Equal("#" + trovato.Groups[1].Value.ToUpperInvariant(), colore.Esadecimale);
        }
        var componenti = File.ReadAllText(Path.Combine(Radice(), "Stile", "Sources", "Stile", "Componenti.swift"));
        var celle = Regex.Match(componenti, @"celle: \[\[UInt32\]\] = \[(.*?)\n    \]", RegexOptions.Singleline);
        Assert.True(celle.Success);
        var valori = Regex.Matches(celle.Groups[1].Value, "0x([0-9A-Fa-f]{6})").Select(m => "#" + m.Groups[1].Value.ToUpperInvariant()).ToArray();
        Assert.Equal(9, valori.Length);
        for (var i = 0; i < 9; i++) Assert.Equal(valori[i], ColoriStile.CelleLogo[i / 3, i % 3].Esadecimale);
    }

    [Theory]
    [InlineData(1920, 1080)]
    [InlineData(1280, 720)]
    [InlineData(960, 540)]
    [InlineData(640, 360)]
    [InlineData(3840, 2160)]
    public void DisegnoDiWebcamLR(int l, int a)
    {
        var nv12 = DisegnoAttesa.CreaNv12(StatoAttesa.NonCollegata, StileAttesa.WebcamLR, LinguaAttesa.Italiano, l, a);
        Assert.Equal(l * a * 3 / 2, nv12.Length);
        // Fondo quasi nero e verde: l'angolo in alto a sinistra un po' più chiaro di quello in basso a destra.
        int alto = Y(nv12, l, 2, 2), basso = Y(nv12, l, l - 3, a - 3);
        Assert.InRange(alto, 16, 32);
        Assert.InRange(basso, 16, 24);
        Assert.True(alto > basso);
        var (u, v) = UV(nv12, l, a, 2, 2);
        Assert.True(u <= 128 && v < 128, $"verde: U {u}, V {v}");

        // Il quadratino centrale del logo è corallo (crominanza rossa).
        var d = DisegnoAttesa.Calcola(l, a, conSottotitolo: true);
        var cella = d.LatoLogo * 0.18;
        var passo = d.LatoLogo * 0.23;
        var cx = (int)(d.SinistraLogo + passo + cella / 2);
        var cy = (int)(d.AltoLogo + passo + cella / 2);
        var (_, vCorallo) = UV(nv12, l, a, cx, cy);
        Assert.True(vCorallo > 160, $"corallo: V {vCorallo}");
        Assert.InRange(Y(nv12, l, cx, cy), 120, 170);

        // Titolo chiaro e riga sotto in salvia, nelle loro fasce; sopra il logo e in fondo solo il fondo.
        Assert.True(ChiariNellaFascia(nv12, l, d.CentroTitolo, 30 * d.Unita, 200) > l * d.Unita * 2, "titolo");
        Assert.True(ChiariNellaFascia(nv12, l, d.CentroSottotitolo, 14 * d.Unita, 130) > l * d.Unita / 2, "riga sotto");
        Assert.Equal(0, ChiariNellaFascia(nv12, l, a * 0.15, a * 0.1, 60));
        Assert.Equal(0, ChiariNellaFascia(nv12, l, a * 0.9, a * 0.08, 60));
    }

    [Fact]
    public void LaPausaNonHaLaRigaSottoEScendeUnPo()
    {
        const int l = 1280, a = 720;
        var pausa = DisegnoAttesa.CreaNv12(StatoAttesa.Pausa, StileAttesa.WebcamLR, LinguaAttesa.Italiano, l, a);
        var con = DisegnoAttesa.Calcola(l, a, true);
        var senza = DisegnoAttesa.Calcola(l, a, false);
        Assert.True(senza.CentroTitolo > con.CentroTitolo);
        Assert.True(ChiariNellaFascia(pausa, l, senza.CentroTitolo, 30 * senza.Unita, 200) > 0);
        Assert.Equal(0, ChiariNellaFascia(pausa, l, senza.CentroSottotitolo + 10 * senza.Unita, 10 * senza.Unita, 100));
    }

    [Fact]
    public void LingueEStatiDannoImmaginiDiverse()
    {
        var immagini = new List<byte[]>();
        foreach (var lingua in DueLingue)
            foreach (var stato in Stati)
                immagini.Add(DisegnoAttesa.CreaNv12(stato, StileAttesa.WebcamLR, lingua, 640, 360));
        for (var i = 0; i < immagini.Count; i++)
            for (var j = i + 1; j < immagini.Count; j++)
                Assert.False(immagini[i].AsSpan().SequenceEqual(immagini[j]), $"{i} e {j} uguali");
        // «Nessuna» si disegna come «non collegata».
        Assert.Equal(DisegnoAttesa.CreaNv12(StatoAttesa.NonCollegata, StileAttesa.WebcamLR, LinguaAttesa.Inglese, 640, 360),
            DisegnoAttesa.CreaNv12(StatoAttesa.Nessuna, StileAttesa.WebcamLR, LinguaAttesa.Inglese, 640, 360));
    }

    [Fact]
    public void StileNero()
    {
        var nv12 = DisegnoAttesa.CreaNv12(StatoAttesa.Interrotta, StileAttesa.Nero, LinguaAttesa.Italiano, 640, 360);
        Assert.True(nv12.AsSpan(0, 640 * 360).IndexOfAnyExcept((byte)16) < 0);
        Assert.True(nv12.AsSpan(640 * 360).IndexOfAnyExcept((byte)128) < 0);
    }

    [Fact]
    public void StileImmagineRiempieSenzaScritte()
    {
        // Immagine 4:3 con una banda chiara al centro e i bordi scuri: riempiendo il 16:9 si tagliano sopra e sotto.
        var personale = new ImmagineNv12(400, 300, Piena(400, 300, 50));
        for (var y = 140; y < 160; y++) personale.Dati.AsSpan(y * 400, 400).Fill(200);
        var nv12 = DisegnoAttesa.CreaNv12(StatoAttesa.NonCollegata, StileAttesa.Immagine, LinguaAttesa.Italiano, 1280, 720, personale);
        Assert.InRange(Y(nv12, 1280, 640, 360), 190, 200);
        Assert.InRange(Y(nv12, 1280, 10, 10), 49, 51);
        Assert.InRange(Y(nv12, 1280, 1270, 710), 49, 51);
        // Nessun testo e nessun logo.
        Assert.Equal(0, ChiariNellaFascia(nv12, 1280, DisegnoAttesa.Calcola(1280, 720, true).CentroSottotitolo, 10, 120));
        // Senza immagine vale il disegno di WebcamLR.
        Assert.Equal(DisegnoAttesa.CreaNv12(StatoAttesa.NonCollegata, StileAttesa.WebcamLR, LinguaAttesa.Italiano, 640, 360),
            DisegnoAttesa.CreaNv12(StatoAttesa.NonCollegata, StileAttesa.Immagine, LinguaAttesa.Italiano, 640, 360));
    }

    [Fact]
    public void StileSfocataScurisceEScriveSopra()
    {
        var chiara = Piena(1280, 720, 200);
        var (sfocata, ls, as_) = ImmaginiNv12.Sfoca(chiara, 1280, 720);
        Assert.Equal((192, 108), (ls, as_));
        Assert.Equal(152, sfocata[0]);
        var nv12 = DisegnoAttesa.CreaNv12(StatoAttesa.Interrotta, StileAttesa.Sfocata, LinguaAttesa.Italiano, 1280, 720, new ImmagineNv12(ls, as_, sfocata));
        Assert.Equal(152, Y(nv12, 1280, 5, 5));
        var d = DisegnoAttesa.Calcola(1280, 720, true);
        Assert.True(ChiariNellaFascia(nv12, 1280, d.CentroTitolo, 20 * d.Unita, 215) > 0);
    }

    [Fact]
    public void SfocaturaAmmorbidisceUnoSpigolo()
    {
        // Metà sinistra nera, metà destra bianca: dopo la sfocatura il passaggio è graduale.
        var nv12 = Piena(640, 360, 16);
        for (var y = 0; y < 360; y++) nv12.AsSpan(y * 640 + 320, 320).Fill(235);
        var (sfocata, l, _) = ImmaginiNv12.Sfoca(nv12, 640, 360);
        var riga = sfocata.AsSpan(50 * l, l).ToArray();
        Assert.Equal(16, riga[0]);
        Assert.InRange(riga[l / 2], 60, 140);
        Assert.InRange(riga[l / 2 + 3], riga[l / 2], 235);
    }

    [Fact]
    public void RicampionaMediaEIngrandisce()
    {
        // 4×2 → 2×1: la media dei pixel coperti.
        byte[] sorgente = [0, 100, 200, 250, 0, 100, 200, 250];
        var piccola = new byte[2];
        ImmaginiNv12.Ricampiona(sorgente, 4, 2, 4, 1, 0, 0, 4, 2, piccola, 2, 1, 2);
        Assert.InRange(piccola[0], 40, 60);
        Assert.InRange(piccola[1], 205, 230);
        // Un'immagine uniforme resta uniforme a qualsiasi misura.
        var uniforme = Enumerable.Repeat((byte)77, 30 * 20).ToArray();
        var grande = new byte[97 * 53];
        ImmaginiNv12.Ricampiona(uniforme, 30, 20, 30, 1, 0, 0, 30, 20, grande, 97, 53, 97);
        Assert.True(grande.AsSpan().IndexOfAnyExcept((byte)77) < 0);
    }

    [Fact]
    public void MescolaDaUnoAllAltro()
    {
        byte[] a = [0, 100, 255], b = [255, 200, 0];
        var uscita = new byte[3];
        ImmaginiNv12.Mescola(a, b, uscita, 0);
        Assert.Equal(a, uscita);
        ImmaginiNv12.Mescola(a, b, uscita, 256);
        Assert.Equal(b, uscita);
        ImmaginiNv12.Mescola(a, b, uscita, 128);
        Assert.Equal(new byte[] { 128, 150, 128 }, uscita);
    }

    [Fact]
    public void RettangoloArrotondatoConAngoliSfumati()
    {
        var (maschera, x, y, l, a) = ImmaginiNv12.RettangoloArrotondato(10.5, 20, 20, 20, 4);
        Assert.Equal((10, 20, 21, 20), (x, y, l, a));
        Assert.Equal(255, maschera[10 * l + 10]);       // centro pieno
        Assert.InRange(maschera[10 * l], 100, 155);      // bordo a metà pixel
        Assert.InRange(maschera[0], 0, 40);              // angolo arrotondato
    }

    // ── Aiuti ──

    internal static byte[] Piena(int l, int a, byte luminanza)
    {
        var nv12 = new byte[l * a * 3 / 2];
        nv12.AsSpan(0, l * a).Fill(luminanza);
        nv12.AsSpan(l * a).Fill(128);
        return nv12;
    }

    internal static int Y(byte[] nv12, int l, int x, int y) => nv12[y * l + x];

    private static (int U, int V) UV(byte[] nv12, int l, int a, int x, int y)
    {
        var i = l * a + (y / 2) * l + (x / 2) * 2;
        return (nv12[i], nv12[i + 1]);
    }

    /// <summary>Quanti pixel hanno la luminanza almeno <paramref name="soglia"/> nella fascia orizzontale centrata su <paramref name="centro"/>.</summary>
    private static int ChiariNellaFascia(byte[] nv12, int l, double centro, double mezzaAltezza, int soglia)
    {
        var a = nv12.Length * 2 / 3 / l;
        var conta = 0;
        for (var y = Math.Max(0, (int)(centro - mezzaAltezza)); y < Math.Min(a, (int)(centro + mezzaAltezza)); y++)
            for (var x = 0; x < l; x++)
                if (nv12[y * l + x] >= soglia) conta++;
        return conta;
    }

    internal static string Radice()
    {
        for (var cartella = new DirectoryInfo(AppContext.BaseDirectory); cartella is not null; cartella = cartella.Parent)
        {
            if (Directory.Exists(Path.Combine(cartella.FullName, "Stile")) && Directory.Exists(Path.Combine(cartella.FullName, "Windows")))
                return cartella.FullName;
        }
        throw new DirectoryNotFoundException("Radice della repository non trovata");
    }
}
