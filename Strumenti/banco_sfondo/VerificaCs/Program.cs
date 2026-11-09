using System.Diagnostics;
using WebcamLR.Effetti;
using WebcamLR.Protocollo;

// Uso: dotnet run -c Release -- <cartella con f00000.bgra…> <quanti> <larghezza> <altezza>
// Per ogni fotogramma scrive accanto: pieno_00000.bin e leggero_00000.bin (maschere di RitaglioPersona, filtro nel tempo
// acceso) e uscita_00000.bgra (Compositore.Rendi: sfocatura «Medio» 0,55, livello Pieno, maschera del modello pieno).
// Alla fine le mediane dei millisecondi.
// Oppure: dotnet run -c Release -- --tempi-modelli <cartella con modnet_photographic(_portrait_matting).onnx> [processore]
// (Documenti/Prova MODNet.md): solo la rete, pieno e leggero di MediaPipe contro MODNet a 256×160, 512×288 e 896×512,
// sulla scheda video con DirectML (Windows) o sul processore; mediana di 50 esecuzioni dopo 10 di riscaldamento.
if (args.Length > 0 && args[0] == "--tempi-modelli")
{
    TempiModelli.Esegui(args[1], args.Length > 2 && args[2] == "processore");
    return;
}
var cartella = args[0];
var quanti = int.Parse(args[1]);
int l = int.Parse(args[2]), a = int.Parse(args[3]);
var modelli = Path.Combine(AppContext.BaseDirectory, "Modelli");
using var pieno = RitaglioPersona.Crea(new OpzioniRitaglio
{
    Modello = ModelloRitaglio.Pieno, Acceleratore = Acceleratore.Processore, RipiegoAutomatico = false, CartellaModelli = modelli,
});
using var leggero = RitaglioPersona.Crea(new OpzioniRitaglio
{
    Modello = ModelloRitaglio.Leggero, Acceleratore = Acceleratore.Processore, RipiegoAutomatico = false, CartellaModelli = modelli,
});
var compositore = new Compositore();
var istantanea = new StatoEffettiComputer.Istantanea(
    new ImpostazioniMotore { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55 }, null, null, null);
var uscita = new ImmagineBgra(l, a);
List<double> tPieno = [], tLeggero = [], tResa = [];
for (var i = 0; i < quanti; i++)
{
    var file = Path.Combine(cartella, $"f{i:00000}.bgra");
    if (!File.Exists(file)) break;
    var immagine = new ImmagineBgra(l, a, File.ReadAllBytes(file));
    var mp = pieno.Calcola(immagine.Dati, l, a);
    var ml = leggero.Calcola(immagine.Dati, l, a);
    File.WriteAllBytes(Path.Combine(cartella, $"pieno_{i:00000}.bin"), mp.Valori);
    File.WriteAllBytes(Path.Combine(cartella, $"leggero_{i:00000}.bin"), ml.Valori);
    var orologio = Stopwatch.StartNew();
    if (!compositore.Rendi(new IngressoResa(immagine, null, null, mp, null, null, 1 / 30.0), istantanea, LivelloResa.Pieno, uscita))
        throw new InvalidOperationException("resa senza maschera");
    var ms = orologio.Elapsed.TotalMilliseconds;
    File.WriteAllBytes(Path.Combine(cartella, $"uscita_{i:00000}.bgra"), uscita.Dati);
    if (i >= 5)
    {
        tPieno.Add(mp.Millisecondi);
        tLeggero.Add(ml.Millisecondi);
        tResa.Add(ms);
    }
}
// Il bordo da solo, sull'ultimo fotogramma: A (a, b al quarto, applicati a metà) contro B (a, b a metà, applicati
// alla misura piena, raggio 4 a metà = 8 px a 1080p). Con le funzioni pubbliche di Elaborazione, 30 ripetizioni.
var ultimo = new ImmagineBgra(l, a, File.ReadAllBytes(Path.Combine(cartella, "f00000.bgra")));
var maschera = pieno.Calcola(ultimo.Dati, l, a);
var meta = Elaborazione.Dimezza(ultimo);
var quarto = Elaborazione.Dimezza(meta);
var lavagna = new Elaborazione.LavagnaGuidato();
var alfaA = new byte[meta.Larghezza * meta.Altezza];
var alfaB = new byte[l * a];
List<double> tBordoA = [], tBordoB = [];
for (var r = 0; r < 35; r++)
{
    var o = Stopwatch.StartNew();
    var pq = Elaborazione.Campiona(maschera.Valori, maschera.Larghezza, maschera.Altezza, quarto.Larghezza, quarto.Altezza);
    var q = Elaborazione.FiltroGuidatoVeloce(Elaborazione.Luminosita(meta), meta.Larghezza, meta.Altezza,
        Elaborazione.Luminosita(quarto), pq, quarto.Larghezza, quarto.Altezza, 2, 1e-3f, lavagna);
    Elaborazione.SogliaMorbida(q, alfaA, 0.5f);
    if (r >= 5) tBordoA.Add(o.Elapsed.TotalMilliseconds);
    o.Restart();
    var pm = Elaborazione.Campiona(maschera.Valori, maschera.Larghezza, maschera.Altezza, meta.Larghezza, meta.Altezza);
    var qb = Elaborazione.FiltroGuidatoVeloce(Elaborazione.Luminosita(ultimo), l, a,
        Elaborazione.Luminosita(meta), pm, meta.Larghezza, meta.Altezza, 4, 1e-3f, lavagna);
    Elaborazione.SogliaMorbida(qb, alfaB, 0.4f);
    if (r >= 5) tBordoB.Add(o.Elapsed.TotalMilliseconds);
}

static double Mediana(List<double> v) => v.Count == 0 ? double.NaN : v.Order().ElementAt(v.Count / 2);
Console.WriteLine(string.Create(System.Globalization.CultureInfo.InvariantCulture,
    $"{{\"pieno_ms\": {Mediana(tPieno):0.00}, \"leggero_ms\": {Mediana(tLeggero):0.00}, \"resa_A_ms\": {Mediana(tResa):0.00}, \"bordo_A_ms\": {Mediana(tBordoA):0.00}, \"bordo_B_ms\": {Mediana(tBordoB):0.00}}}"));

/// <summary>I millisecondi della sola rete per i modelli della prova MODNet, con DirectML se c'è.</summary>
static class TempiModelli
{
    public static void Esegui(string cartellaModnet, bool soloProcessore)
    {
        var mediapipe = Path.Combine(AppContext.BaseDirectory, "Modelli");
        // Il nome del banco o quello del file scaricato (è lo stesso modello).
        var modnet = new[] { "modnet_photographic.onnx", "modnet_photographic_portrait_matting.onnx" }
            .Select(n => Path.Combine(cartellaModnet, n)).FirstOrDefault(File.Exists) ?? Path.Combine(cartellaModnet, "modnet_photographic.onnx");
        var prove = new (string Nome, string File, long[] Forma)[]
        {
            ("pieno 256×256", Path.Combine(mediapipe, "ritaglio_persona.onnx"), [1, 256, 256, 3]),
            ("leggero 256×144", Path.Combine(mediapipe, "ritaglio_persona_leggero.onnx"), [1, 144, 256, 3]),
            ("MODNet 256×160", modnet, [1, 3, 160, 256]),
            ("MODNet 512×288", modnet, [1, 3, 288, 512]),
            ("MODNet 896×512", modnet, [1, 3, 512, 896]),
        };
        var dml = !soloProcessore && OperatingSystem.IsWindows();
        Console.WriteLine(dml ? "Scheda video (DirectML, scheda 0)" : $"Processore ({Environment.ProcessorCount} processori logici)");
        foreach (var (nome, file, forma) in prove)
        {
            try
            {
                Console.WriteLine($"{nome}: {Misura(file, forma, dml):0.0} ms");
            }
            catch (Exception e)
            {
                Console.WriteLine($"{nome}: non misurato ({e.Message})");
            }
        }
    }

    private static double Misura(string file, long[] forma, bool dml)
    {
        using var so = new Microsoft.ML.OnnxRuntime.SessionOptions
        {
            GraphOptimizationLevel = Microsoft.ML.OnnxRuntime.GraphOptimizationLevel.ORT_ENABLE_ALL,
        };
        if (dml)
        {
            // Come RitaglioPersona: DirectML vuole l'esecuzione in sequenza e niente schema di memoria.
            so.EnableMemoryPattern = false;
            so.ExecutionMode = Microsoft.ML.OnnxRuntime.ExecutionMode.ORT_SEQUENTIAL;
            so.AppendExecutionProvider_DML(0);
        }
        using var sessione = new Microsoft.ML.OnnxRuntime.InferenceSession(file, so);
        var nomeIngresso = sessione.InputMetadata.Keys.First();
        var dati = new float[forma.Aggregate(1L, (x, y) => x * y)];
        for (var i = 0; i < dati.Length; i++) dati[i] = (i % 97) / 97f - 0.5f;
        using var ingresso = Microsoft.ML.OnnxRuntime.OrtValue.CreateTensorValueFromMemory(dati, forma);
        using var esecuzione = new Microsoft.ML.OnnxRuntime.RunOptions();
        var tempi = new List<double>();
        for (var i = 0; i < 60; i++)
        {
            var o = Stopwatch.StartNew();
            using var uscite = sessione.Run(esecuzione, [nomeIngresso], [ingresso], sessione.OutputNames);
            if (i >= 10) tempi.Add(o.Elapsed.TotalMilliseconds);
        }
        tempi.Sort();
        return tempi[tempi.Count / 2];
    }
}
