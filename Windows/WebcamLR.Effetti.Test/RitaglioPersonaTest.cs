using System.Diagnostics;
using Xunit;
using Xunit.Abstractions;

namespace WebcamLR.Effetti.Test;

/// <summary>Il ritaglio vero, con ONNX Runtime sul processore (anche su Linux).</summary>
public class RitaglioPersonaTest(ITestOutputHelper uscita)
{
    private static readonly OpzioniRitaglio SoloProcessore = new()
    {
        Acceleratore = Acceleratore.Processore,
        RipiegoAutomatico = false,
        FiltroNelTempo = false,
    };

    [Theory]
    [InlineData(ModelloRitaglio.Leggero, "sintetica-leggero.bin", 256, 144)]
    [InlineData(ModelloRitaglio.Pieno, "sintetica-pieno.bin", 256, 256)]
    public void ComeIlRiferimentoDiPython(ModelloRitaglio modello, string riferimento, int larghezza, int altezza)
    {
        var (bgra, l, a) = Immagini.LeggiPpm(Immagini.Dati("sintetica.ppm.gz"));
        using var r = RitaglioPersona.Crea(SoloProcessore with { Modello = modello });
        Assert.Equal(Acceleratore.Processore, r.InUso);
        var m = r.Calcola(bgra, l, a);
        Assert.Equal(modello, m.Modello);
        Assert.Equal((larghezza, altezza), (m.Larghezza, m.Altezza));

        var atteso = File.ReadAllBytes(Immagini.Dati(riferimento));
        Assert.Equal(atteso.Length, m.Valori.Length);
        var massima = 0;
        for (var i = 0; i < atteso.Length; i++) massima = Math.Max(massima, Math.Abs(atteso[i] - m.Valori[i]));
        uscita.WriteLine($"{modello}: differenza massima dal riferimento {massima}/255, {m.Millisecondi:0.0} ms");
        Assert.True(massima <= 2, $"differenza {massima}");
    }

    [Fact]
    public void IlLeggeroTrovaLaPersonaDisegnata()
    {
        // Il modello pieno non riconosce una persona disegnata (è addestrato su foto): qui si prova il leggero.
        var (bgra, l, a) = Immagini.LeggiPpm(Immagini.Dati("sintetica.ppm.gz"));
        using var r = RitaglioPersona.Crea(SoloProcessore with { Modello = ModelloRitaglio.Leggero });
        var m = r.Calcola(bgra, l, a);
        Assert.True(m.Valore(0.5f, 0.42f) > 0.9f, "viso");
        Assert.True(m.Valore(0.5f, 0.9f) > 0.9f, "spalle");
        Assert.True(m.Valore(0.05f, 0.05f) < 0.1f, "angolo");
        Assert.True(m.Valore(0.15f, 0.28f) < 0.1f, "quadro");
    }

    [Fact]
    public void SenzaSchedaVideoSiRipiegaSulLeggero()
    {
        if (OperatingSystem.IsWindows()) return; // su Windows c'è DirectML: lo prova Ledion (Documenti/Effetti su Windows.md)
        using var r = RitaglioPersona.Crea();
        Assert.Equal(Acceleratore.Processore, r.InUso);
        Assert.Equal(ModelloRitaglio.Leggero, r.Modello);
        Assert.NotNull(r.MotivoRipiego);
        Assert.Throws<PlatformNotSupportedException>(() => RitaglioPersona.Crea(new OpzioniRitaglio { Acceleratore = Acceleratore.SchedaVideo }));
    }

    [Fact]
    public void ModelloMancanteOSbagliato()
    {
        var vuota = Directory.CreateTempSubdirectory("webcamlr-modelli-").FullName;
        try
        {
            Assert.Throws<FileNotFoundException>(() => RitaglioPersona.Crea(SoloProcessore with { CartellaModelli = vuota }));
            // Il leggero al posto del pieno: ingresso diverso, si rifiuta invece di dare una maschera senza senso.
            File.Copy(Path.Combine(AppContext.BaseDirectory, "Modelli", "ritaglio_persona_leggero.onnx"), Path.Combine(vuota, "ritaglio_persona.onnx"));
            Assert.Throws<InvalidDataException>(() => RitaglioPersona.Crea(SoloProcessore with { CartellaModelli = vuota }));
        }
        finally { Directory.Delete(vuota, true); }
    }

    [Fact]
    public void IlFiltroNelTempoTieneFermaUnaScenaFerma()
    {
        var (bgra, l, a) = Immagini.LeggiPpm(Immagini.Dati("sintetica.ppm.gz"));
        using var r = RitaglioPersona.Crea(SoloProcessore with { Modello = ModelloRitaglio.Leggero, FiltroNelTempo = true });
        var prima = r.Calcola(bgra, l, a);
        var seconda = r.Calcola(bgra, l, a);
        Assert.Equal(prima.Valori, seconda.Valori);
    }

    [Fact]
    public void PassoConRiempimentoEFotogrammaGrande()
    {
        // 1920×1080 con 64 byte in più per riga, come una superficie della scheda video.
        var (piccola, l, a) = Immagini.LeggiPpm(Immagini.Dati("sintetica.ppm.gz"));
        const int L = 1920, A = 1080, passo = L * 4 + 64;
        var grande = new byte[passo * A];
        for (var y = 0; y < A; y++)
            for (var x = 0; x < L; x++)
                Array.Copy(piccola, (y * a / A * l + x * l / L) * 4, grande, y * passo + x * 4, 4);
        using var r = RitaglioPersona.Crea(SoloProcessore with { Modello = ModelloRitaglio.Leggero });
        var m = r.Calcola(grande, L, A, passo);
        Assert.True(m.Valore(0.5f, 0.42f) > 0.9f);
        Assert.True(m.Valore(0.05f, 0.05f) < 0.1f);
    }

    [Fact]
    public void TempiSulProcessore()
    {
        var (bgra, l, a) = Immagini.LeggiPpm(Immagini.Dati("sintetica.ppm.gz"));
        foreach (var modello in new[] { ModelloRitaglio.Leggero, ModelloRitaglio.Pieno })
        {
            using var r = RitaglioPersona.Crea(SoloProcessore with { Modello = modello });
            for (var i = 0; i < 3; i++) r.Calcola(bgra, l, a);
            const int n = 10;
            var orologio = Stopwatch.StartNew();
            for (var i = 0; i < n; i++) r.Calcola(bgra, l, a);
            uscita.WriteLine($"{modello}: {orologio.Elapsed.TotalMilliseconds / n:0.0} ms per maschera ({Environment.ProcessorCount} processori)");
        }

        // Solo la riduzione di un fotogramma 1080p alla misura del modello (sulla scheda video la farà uno shader).
        var grande = new byte[1920 * 1080 * 4];
        var rgb = new float[256 * 256 * 3];
        var tempo = Stopwatch.StartNew();
        for (var i = 0; i < 10; i++) Preparazione.BgraInRgb(grande, 1920, 1080, 1920 * 4, rgb, 256, 256, 1f, 0f);
        uscita.WriteLine($"Riduzione da 1920×1080 a 256×256: {tempo.Elapsed.TotalMilliseconds / 10:0.0} ms");
    }

    /// <summary>
    /// Su una foto vera, fuori dalla repository: WEBCAMLR_IMMAGINE_PROVA = percorso di un PPM (anche .ppm.gz). Scrive le
    /// maschere in PGM accanto e, se ci sono «&lt;nome&gt;-pieno.bin» e «&lt;nome&gt;-leggero.bin», le confronta.
    /// </summary>
    [Fact]
    public void FotoVeraSeIndicata()
    {
        var percorso = Environment.GetEnvironmentVariable("WEBCAMLR_IMMAGINE_PROVA");
        if (string.IsNullOrEmpty(percorso)) return;
        var (bgra, l, a) = Immagini.LeggiPpm(percorso);
        var base_ = percorso.Replace(".ppm.gz", "").Replace(".ppm", "");
        foreach (var modello in new[] { ModelloRitaglio.Pieno, ModelloRitaglio.Leggero })
        {
            using var r = RitaglioPersona.Crea(SoloProcessore with { Modello = modello });
            var m = r.Calcola(bgra, l, a);
            var nome = modello == ModelloRitaglio.Pieno ? "pieno" : "leggero";
            Immagini.ScriviPgm($"{base_}-cs-{nome}.pgm", m);
            var rif = $"{base_}-{nome}.bin";
            if (File.Exists(rif))
            {
                var atteso = File.ReadAllBytes(rif);
                var massima = atteso.Select((v, i) => Math.Abs(v - m.Valori[i])).Max();
                uscita.WriteLine($"{modello}: differenza massima {massima}/255");
                Assert.True(massima <= 2);
            }
        }
    }
}
