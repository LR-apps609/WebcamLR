using System.Runtime.InteropServices;
using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

/// <summary>
/// Quello che la webcam consegna fotogramma per fotogramma, con l'anello su memoria normale al posto di quella condivisa:
/// l'app scrive video e stato come farebbe WebcamLR, il compositore risponde come la sorgente o il filtro DirectShow.
/// </summary>
public sealed unsafe class CompositoreWebcamTest : IDisposable
{
    private static readonly FormatoWebcam Formato = new(640, 360, 30);
    private readonly byte* memoria;
    private readonly AnelloFotogrammi anello;
    private readonly List<string> righe = [];
    private readonly CompositoreWebcam compositore;

    public CompositoreWebcamTest()
    {
        memoria = (byte*)NativeMemory.AllocZeroed((nuint)AnelloFotogrammi.DimensioneTotale);
        anello = new AnelloFotogrammi(memoria, AnelloFotogrammi.DimensioneTotale);
        anello.Prepara();
        compositore = new CompositoreWebcam(LinguaAttesa.Italiano, righe.Add);
    }

    public void Dispose() => NativeMemory.Free(memoria);

    private byte[] Consegna(long adesso) => compositore.Fotogramma(anello, Formato, adesso).AsSpan(0, Formato.Byte).ToArray();

    private static byte[] Attesa(StatoAttesa stato, StileAttesa stile = StileAttesa.WebcamLR, LinguaAttesa lingua = LinguaAttesa.Italiano) =>
        DisegnoAttesa.CreaNv12(stato, stile, lingua, Formato.Larghezza, Formato.Altezza);

    /// <summary>L'app: stato ogni secondo come battito, un fotogramma grigio di valore <paramref name="grigio"/>.</summary>
    private void App(long adesso, StatoAttesa stato = StatoAttesa.Nessuna, byte? grigio = null, StileAttesa stile = StileAttesa.WebcamLR)
    {
        anello.ImpostaAttesa(stato, stile, LinguaAttesa.Automatica, adesso);
        if (grigio is { } g) anello.Scrivi(SchermataAttesaTest.Piena(Formato.Larghezza, Formato.Altezza, g), Formato.Larghezza, Formato.Altezza, adesso);
    }

    /// <summary>
    /// L'attesa nella sorgente (ritardo «da vetro a uscita»): dalla scrittura dell'app alla prima consegna di ogni
    /// fotogramma nuovo; le ripetizioni (uscita a 60 fps, telefono a 30) non contano. La mediana di un secondo va nell'anello.
    /// </summary>
    [Fact]
    public void LAttesaNellaSorgenteSiMisuraUnaVoltaPerFotogramma()
    {
        const long frequenza = 1_000_000; // un tick = 1 µs
        long tick = 0;
        var misuratore = new CompositoreWebcam(LinguaAttesa.Italiano, orologioTick: () => tick, frequenza: frequenza);
        for (var n = 0; n < 40; n++)
        {
            var t = 1000L + n * 33;
            // L'app scrive al tick t·1000; la sorgente consegna 4 ms dopo, e ripete lo stesso fotogramma 16 ms dopo.
            anello.ImpostaAttesa(StatoAttesa.Nessuna, StileAttesa.WebcamLR, LinguaAttesa.Automatica, t);
            anello.Scrivi(SchermataAttesaTest.Piena(Formato.Larghezza, Formato.Altezza, 90), Formato.Larghezza, Formato.Altezza, t,
                istanteTick: t * 1000);
            tick = t * 1000 + 4_000;
            misuratore.Fotogramma(anello, Formato, t + 4);
            tick = t * 1000 + 20_000;
            misuratore.Fotogramma(anello, Formato with { Fps = 60 }, t + 20);
        }
        Assert.Equal(4_000, misuratore.UltimaAttesa);
        Assert.Equal(4_000, anello.AttesaSorgente(tick, frequenza));
    }

    [Fact]
    public void SenzaMemoriaCondivisaNonCollegata()
    {
        var uscita = compositore.Fotogramma(null, Formato, 1000);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata), uscita.AsSpan(0, Formato.Byte).ToArray());
        Assert.False(compositore.AppAttiva(1000));
    }

    [Fact]
    public void LaSchermataSiDisegnaUnaVoltaSola()
    {
        var prima = compositore.Fotogramma(anello, Formato, 1000);
        for (var t = 1033; t < 3000; t += 33) Assert.Same(prima, compositore.Fotogramma(anello, Formato, t));
        // Stessa misura a 60 fps: stessa immagine.
        Assert.Same(prima, compositore.Fotogramma(anello, Formato with { Fps = 60 }, 3100));
        Assert.Contains(righe, r => r.Contains("NonCollegata"));
    }

    [Fact]
    public void VideoPoiInterruzioneConTenutaEDissolvenza()
    {
        for (var t = 1000L; t <= 3000; t += 33)
        {
            App(t, grigio: 100);
            Assert.Equal(100, Consegna(t)[0]);
        }
        Assert.Null(compositore.Mostrata);
        Assert.True(compositore.AppAttiva(2990));

        // Il telefono si perde: l'app continua a dire «interrotta», niente più fotogrammi.
        long ultimo = 2980;
        for (var t = 3000L; t < ultimo + ProgrammaAttesa.TenutaMs; t += 33)
        {
            App(t, StatoAttesa.Interrotta);
            Assert.Equal(SchermataAttesaTest.Piena(640, 360, 100), Consegna(t));
        }
        // Poi la dissolvenza di mezzo secondo verso «Collegamento interrotto»: passi via via più vicini all'attesa.
        var attesa = Attesa(StatoAttesa.Interrotta);
        var inizio = ultimo + ProgrammaAttesa.TenutaMs;
        var distanze = new List<long>();
        for (var t = inizio; t < inizio + CompositoreWebcam.EntrataMs; t += 33)
        {
            App(t, StatoAttesa.Interrotta);
            distanze.Add(Distanza(Consegna(t), attesa));
        }
        Assert.True(distanze.First() > 0);
        for (var i = 1; i < distanze.Count; i++) Assert.True(distanze[i] <= distanze[i - 1]);
        App(inizio + 600, StatoAttesa.Interrotta);
        Assert.Equal(attesa, Consegna(inizio + 600));
        Assert.Equal(StatoAttesa.Interrotta, compositore.Mostrata);

        // Il telefono torna: il video vince subito, con l'attesa che svanisce sopra in 0,3 secondi.
        var ritorno = inizio + 2000;
        App(ritorno, grigio: 180);
        var primo = Consegna(ritorno);
        Assert.NotEqual(180, primo[0]);
        App(ritorno + CompositoreWebcam.UscitaMs, grigio: 180);
        Assert.Equal(SchermataAttesaTest.Piena(640, 360, 180), Consegna(ritorno + CompositoreWebcam.UscitaMs));
        Assert.Null(compositore.Mostrata);
    }

    [Fact]
    public void PausaSubitoConDissolvenza()
    {
        for (var t = 1000L; t <= 2000; t += 33)
        {
            App(t, grigio: 90);
            Consegna(t);
        }
        App(2010, StatoAttesa.Pausa);
        var primo = Consegna(2010);
        Assert.Equal(StatoAttesa.Pausa, compositore.Mostrata);
        Assert.NotEqual(Attesa(StatoAttesa.Pausa), primo);
        App(2600, StatoAttesa.Pausa);
        Assert.Equal(Attesa(StatoAttesa.Pausa), Consegna(2600));
    }

    [Fact]
    public void AppChiusaDopoDueSecondiNonCollegata()
    {
        for (var t = 1000L; t <= 2000; t += 33)
        {
            App(t, grigio: 120);
            Consegna(t);
        }
        anello.SegnalaChiusura();
        // L'ultima immagine fino a 2 secondi dall'ultimo fotogramma (1990), poi mezzo secondo di dissolvenza.
        for (var t = 2020L; t < 3990; t += 33) Assert.Equal(120, Consegna(t)[0]);
        for (var t = 3990L; t < 4600; t += 33) Consegna(t);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata), Consegna(4600));
    }

    [Fact]
    public void AppSparitaSenzaSalutareDopoIlBattito()
    {
        App(1000, StatoAttesa.Pausa);
        Assert.Equal(Attesa(StatoAttesa.Pausa), Consegna(1000));
        // L'app non scrive più (chiusa di colpo): oltre StatoAppMs vale chiusa, «non collegata».
        Consegna(1000 + NomiWebcam.StatoAppMs - 10);
        Assert.Equal(StatoAttesa.Pausa, compositore.Mostrata);
        Consegna(1000 + NomiWebcam.StatoAppMs + 10);
        Assert.Equal(StatoAttesa.NonCollegata, compositore.Mostrata);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata), Consegna(1000 + NomiWebcam.StatoAppMs + 600));
    }

    [Fact]
    public void LinguaDellAppEPoiDelSistema()
    {
        anello.ImpostaAttesa(StatoAttesa.NonCollegata, StileAttesa.WebcamLR, LinguaAttesa.Inglese, 1000);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata, lingua: LinguaAttesa.Inglese), Consegna(1000));
        // Il compositore è «di sistema italiano»: senza lingua scritta, italiano.
        anello.ImpostaAttesa(StatoAttesa.NonCollegata, StileAttesa.WebcamLR, LinguaAttesa.Automatica, 1100);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata), Consegna(1100));
    }

    [Fact]
    public void StiliDiPro()
    {
        App(1000, StatoAttesa.NonCollegata, stile: StileAttesa.Nero);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata, StileAttesa.Nero), Consegna(1000));

        // Immagine senza immagine personale: il disegno di WebcamLR. Con l'immagine: lei.
        App(1100, StatoAttesa.NonCollegata, stile: StileAttesa.Immagine);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata), Consegna(1100));
        anello.ScriviImmaginePersonale(SchermataAttesaTest.Piena(320, 180, 60), 320, 180);
        App(1200, StatoAttesa.NonCollegata, stile: StileAttesa.Immagine);
        Assert.Equal(SchermataAttesaTest.Piena(640, 360, 60), Consegna(1200));
        // Un'immagine nuova vale subito.
        anello.ScriviImmaginePersonale(SchermataAttesaTest.Piena(320, 180, 70), 320, 180);
        App(1300, StatoAttesa.NonCollegata, stile: StileAttesa.Immagine);
        Assert.Equal(70, Consegna(1300)[0]);
    }

    [Fact]
    public void SfocataDallUltimaImmagine()
    {
        for (var t = 1000L; t <= 2000; t += 33)
        {
            App(t, grigio: 200, stile: StileAttesa.Sfocata);
            Consegna(t);
        }
        App(2010, StatoAttesa.Pausa, stile: StileAttesa.Sfocata);
        Consegna(2010);
        App(2600, StatoAttesa.Pausa, stile: StileAttesa.Sfocata);
        var uscita = Consegna(2600);
        // Il grigio 200 scurito (−48) e il titolo chiaro sopra.
        Assert.Equal(152, uscita[0]);
        Assert.Contains(uscita.Take(640 * 360), y => y > 215);
    }

    [Fact]
    public void UnFotogrammaVecchioNonÈVideo()
    {
        // Rimasto nella memoria da prima (per esempio la webcam riaperta dopo un minuto): resta l'attesa.
        anello.Scrivi(SchermataAttesaTest.Piena(640, 360, 99), 640, 360, 1000);
        App(5000, StatoAttesa.Nessuna);
        Assert.Equal(Attesa(StatoAttesa.NonCollegata), Consegna(5000));
    }

    [Fact]
    public void FotogrammaDiAltraMisuraScalato()
    {
        anello.ImpostaAttesa(StatoAttesa.Nessuna, StileAttesa.WebcamLR, LinguaAttesa.Automatica, 1000);
        anello.Scrivi(SchermataAttesaTest.Piena(1280, 720, 140), 1280, 720, 1000);
        var uscita = Consegna(1000);
        Assert.Equal(140, uscita[0]);
        Assert.Equal(140, uscita[640 * 360 - 1]);
    }

    [Fact]
    public void CambioDiFormatoDuranteLaDissolvenza()
    {
        for (var t = 1000L; t <= 2000; t += 33)
        {
            App(t, grigio: 90);
            Consegna(t);
        }
        App(2010, StatoAttesa.Pausa);
        Consegna(2010);
        // Un'app sceglie 1280×720 a metà dissolvenza: niente miscugli di misure diverse, subito l'attesa giusta.
        var grande = new FormatoWebcam(1280, 720, 30);
        var uscita = compositore.Fotogramma(anello, grande, 2100).AsSpan(0, grande.Byte).ToArray();
        Assert.Equal(DisegnoAttesa.CreaNv12(StatoAttesa.Pausa, StileAttesa.WebcamLR, LinguaAttesa.Italiano, 1280, 720), uscita);
    }

    private static long Distanza(byte[] a, byte[] b)
    {
        long somma = 0;
        for (var i = 0; i < a.Length; i++) somma += Math.Abs(a[i] - b[i]);
        return somma;
    }
}
