using System.Diagnostics;
using WebcamLR.Effetti;
using WebcamLR.Protocollo;

// Uso: dotnet run -c Release -- <cartella con f00000.bgra…> <quanti> <larghezza> <altezza>
// Per ogni fotogramma scrive accanto: pieno_00000.bin e leggero_00000.bin (maschere di RitaglioPersona, filtro nel tempo
// acceso) e uscita_00000.bgra (Compositore.Rendi: sfocatura «Medio» 0,55, livello Pieno, maschera del modello pieno).
// Alla fine le mediane dei millisecondi.
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
