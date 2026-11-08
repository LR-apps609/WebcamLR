using System.Collections.Concurrent;
using System.Diagnostics;

namespace WebcamLR.Effetti;

/// <summary>Chi calcola la maschera della persona: il ritaglio con ONNX Runtime, o una finta nei test.</summary>
public interface IFonteMaschera : IDisposable
{
    /// <summary>La maschera per questo fotogramma (di solito già ridotto a un quarto). Bloccante.</summary>
    MascheraPersona Calcola(ImmagineBgra immagine);

    /// <summary>Per il registro: dove gira e quale modello («scheda video, modello pieno»).</summary>
    string Descrizione { get; }

    /// <summary>Dove gira davvero (scheda video o processore).</summary>
    Acceleratore InUso { get; }

    /// <summary>Il modello in uso adesso (può passare dal pieno al leggero).</summary>
    ModelloRitaglio Modello { get; }

    /// <summary>Perché si è lasciata la scheda video o il modello pieno; null se no.</summary>
    string? MotivoRipiego { get; }
}

/// <summary>Il ritaglio della libreria come fonte della maschera.</summary>
public sealed class FonteRitaglio(RitaglioPersona ritaglio) : IFonteMaschera
{
    public MascheraPersona Calcola(ImmagineBgra immagine) =>
        ritaglio.Calcola(immagine.Dati, immagine.Larghezza, immagine.Altezza, immagine.Passo);

    public string Descrizione =>
        $"{(ritaglio.InUso == Acceleratore.SchedaVideo ? "scheda video" : "processore")}, modello {(ritaglio.Modello == ModelloRitaglio.Pieno ? "pieno" : "leggero")}";

    public string? MotivoRipiego => ritaglio.MotivoRipiego;

    public Acceleratore InUso => ritaglio.InUso;

    public ModelloRitaglio Modello => ritaglio.Modello;

    public void Dispose() => ritaglio.Dispose();

    /// <summary>
    /// La fonte per un livello: il veloce chiede il modello leggero, gli altri il pieno (con il ripiego automatico).
    /// <paramref name="acceleratore"/>: <see cref="Acceleratore.Processore"/> quando la scheda video si è persa.
    /// </summary>
    public static IFonteMaschera PerLivello(LivelloResa livello, string? cartellaModelli = null,
        Acceleratore acceleratore = Acceleratore.Automatico) =>
        new FonteRitaglio(RitaglioPersona.Crea(new OpzioniRitaglio
        {
            Modello = livello == LivelloResa.Veloce ? ModelloRitaglio.Leggero : ModelloRitaglio.Pieno,
            CartellaModelli = cartellaModelli,
            Acceleratore = acceleratore,
        }));
}

/// <summary>Un thread solo che esegue i lavori in ordine (come una coda seriale di Grand Central Dispatch).</summary>
public sealed class CodaSeriale : IDisposable
{
    private readonly BlockingCollection<Action> lavori = new();
    private readonly Thread filo;

    public CodaSeriale(string nome)
    {
        filo = new Thread(Ciclo) { IsBackground = true, Name = nome, Priority = ThreadPriority.AboveNormal };
        filo.Start();
    }

    public void Accoda(Action lavoro)
    {
        try { lavori.Add(lavoro); }
        catch (InvalidOperationException) { }
    }

    private void Ciclo()
    {
        foreach (var lavoro in lavori.GetConsumingEnumerable())
        {
            try { lavoro(); }
            catch (Exception) { }
        }
    }

    public void Dispose() => lavori.CompleteAdding();
}

/// <summary>
/// Quando scendere di qualità (come regolaQualita del Mac): se, in media su circa 2 secondi, la maschera o la resa
/// superano l'85% del tempo di un fotogramma, un gradino più in basso. Il tempo di un fotogramma è la media della metà
/// centrale degli ultimi 30 intervalli d'arrivo (un intoppo del Wi-Fi, una raffica di due fotogrammi o una pausa non
/// contano), mai sotto 1/60 di secondo. I primi fotogrammi dopo <see cref="Azzera"/> o una fonte nuova non contano: la
/// scheda video si scalda alla prima maschera (DirectML compila gli shader, 1–2 s). Non risale mai da sola: niente
/// sbalzi di qualità (riparte dal pieno con un video o un telefono nuovo).
/// </summary>
public sealed class SceltaLivello
{
    public const int FotogrammiPerDecidere = 60;
    public const double QuotaFotogramma = 0.85;

    /// <summary>I fotogrammi che non contano dopo un azzeramento o una fonte nuova (come il riscaldamento di MisuraVelocita).</summary>
    public const int FotogrammiDiRiscaldamento = 5;

    /// <summary>Il fotogramma più breve che si considera (ms): oltre i 60 fps non si va.</summary>
    public const double FotogrammaMinimoMs = 1000.0 / 60;

    private readonly Queue<ulong> intervalli = new();
    private double somma, sommaMaschera, sommaResa;
    private int conta;
    private int daScartare = FotogrammiDiRiscaldamento;

    public LivelloResa Livello { get; private set; } = LivelloResa.Pieno;

    /// <summary>Il tempo tra due fotogrammi arrivati (µs).</summary>
    public void Intervallo(ulong microsecondi)
    {
        intervalli.Enqueue(microsecondi);
        while (intervalli.Count > 30) intervalli.Dequeue();
    }

    /// <summary>La fonte della maschera è nuova (aperta, riaperta, cambiata): i prossimi fotogrammi scaldano la scheda video.</summary>
    public void FonteNuova() => daScartare = FotogrammiDiRiscaldamento;

    /// <summary>I tempi di un fotogramma reso; il livello nuovo quando scende, altrimenti null.</summary>
    public LivelloResa? Aggiungi(double mascheraMs, double resaMs, out double fotogrammaMs)
    {
        fotogrammaMs = 0;
        if (daScartare > 0)
        {
            daScartare--;
            return null;
        }
        somma += Math.Max(mascheraMs, resaMs);
        sommaMaschera += mascheraMs;
        sommaResa += resaMs;
        conta++;
        if (conta < FotogrammiPerDecidere) return null;
        var media = somma / conta;
        var maschera = sommaMaschera / conta;
        var resa = sommaResa / conta;
        somma = sommaMaschera = sommaResa = 0;
        conta = 0;
        if (intervalli.Count == 0 || Livello == LivelloResa.Veloce) return null;
        fotogrammaMs = TempoFotogrammaMs();
        if (media <= fotogrammaMs * QuotaFotogramma) return null;
        // La maschera è il collo di bottiglia (in media sulla finestra): subito al modello leggero; altrimenti prima il
        // bordo leggero.
        Livello = maschera > resa ? LivelloResa.Veloce : Livello + 1;
        return Livello;
    }

    /// <summary>La media della metà centrale degli intervalli (ms), almeno <see cref="FotogrammaMinimoMs"/>.</summary>
    private double TempoFotogrammaMs()
    {
        var ordinati = intervalli.Order().ToArray();
        int via = ordinati.Length / 4, quanti = ordinati.Length - 2 * via;
        double totale = 0;
        for (var i = via; i < via + quanti; i++) totale += ordinati[i];
        return Math.Max(totale / quanti / 1000.0, FotogrammaMinimoMs);
    }

    public void Azzera()
    {
        Livello = LivelloResa.Pieno;
        intervalli.Clear();
        somma = sommaMaschera = sommaResa = 0;
        conta = 0;
        daScartare = FotogrammiDiRiscaldamento;
    }
}

/// <summary>
/// Il motore effetti di Windows (27 ottobre, «effetti sul computer, come iVCam»), lo stesso disegno del Mac
/// (Mac/Sorgenti/MotoreEffetti.swift): il telefono manda il video com'è, il PC lo elabora UNA volta dopo la decodifica e
/// la stessa immagine elaborata va a tutte le uscite (anteprima, finestra mini, webcam virtuale, foto, registrazione).
///
/// Percorso di un fotogramma:
///   chi decodifica:   <see cref="Elabora"/> (non aspetta mai)
///   coda di analisi:  riduzione a metà e a un quarto, maschera della persona per QUESTO fotogramma (dalla copia piccola),
///                     il volto dalla stessa maschera
///   coda di resa:     <see cref="Compositore"/> sul processore con la maschera dello stesso istante → un'immagine dal giro
///                     di uscita → consegna
/// Il fotogramma resta indietro solo il tempo della maschera e della resa: se la maschera è ancora occupata quando arriva
/// il fotogramma dopo, quello aspetta al suo posto (al massimo uno); se ne arriva un terzo, il più vecchio si scarta.
/// Senza effetti accesi <see cref="Elabora"/> risponde falso e l'immagine va alle uscite com'è (costo zero).
///
/// Riservatezza: con lo sfondo acceso un fotogramma senza maschera (errore, modello che si apre) usa l'ultima maschera
/// buona, se non ha più di mezzo secondo (una sagoma ferma lascerebbe vedere la stanza dove la persona si sposta); se
/// non ce n'è nessuna non si consegna (le uscite tengono l'ultima immagine elaborata). Mai lo sfondo vero.
/// Se la maschera fallisce più volte di fila (scheda video persa: driver aggiornato, sospensione, TDR) la fonte si chiude
/// e si riapre; dalla seconda volta sul processore.
/// </summary>
public sealed class MotoreEffetti : IDisposable
{
    /// <summary>Le immagini di uscita in giro: anteprima, mini, webcam, foto e registrazione insieme ne tengono qualcuna.</summary>
    public const int ImmaginiInUscita = 16;

    /// <summary>Errori della maschera di fila dopo i quali la fonte si chiude e si riapre.</summary>
    public const int ErroriPerRiaprire = 3;

    /// <summary>Riaperture al massimo, finché non torna una serie di maschere buone (niente giri senza fine).</summary>
    public const int RiapertureMassime = 3;

    /// <summary>Quante maschere buone di fila azzerano il conto delle riaperture (circa 10 s a 30 fps).</summary>
    public const int MaschereBuonePerDimenticare = 300;

    /// <summary>Quanto può essere vecchia (µs) l'ultima maschera buona usata al posto di quella che manca.</summary>
    public const ulong EtaMassimaMaschera = 500_000;

    /// <summary>I numeri dell'ultimo secondo, per le «Tappe» e il registro.</summary>
    /// <param name="EffettiMs">Dall'ingresso nel motore all'uscita (mediana di un secondo); null se il motore non lavora.</param>
    /// <param name="Fonte">Dove gira il ritaglio, se è aperto.</param>
    public sealed record Misure(int? EffettiMs, double? MascheraMs, double? ResaMs, LivelloResa Livello, int Scartati,
        int ErroriMaschera, (Acceleratore InUso, ModelloRitaglio Modello)? Fonte, int SenzaMaschera);

    /// <summary>Un avviso per il registro (lo scrive la finestra con i suoi testi).</summary>
    public abstract record Nota
    {
        public sealed record Livello(LivelloResa Nuovo, int MascheraMs, int ResaMs, int FotogrammaMs) : Nota;
        public sealed record ErroreMaschera(string Errore, int Totale) : Nota;
        public sealed record Fonte(Acceleratore InUso, ModelloRitaglio Modello, string? Motivo) : Nota;
        /// <summary>La maschera fallisce di fila: la fonte si chiude e si riapre (sul processore se <paramref name="SulProcessore"/>).</summary>
        public sealed record FonteRiaperta(int ErroriDiFila, bool SulProcessore) : Nota;
    }

    private sealed class Lavoro
    {
        public required ImmagineBgra Immagine;
        public required ulong Arrivo;
        public required int Generazione;
        public required Action<ImmagineBgra> Consegna;
        public ImmagineBgra? Meta, Quarto;
        public MascheraPersona? Maschera;
        public double MascheraMs;
    }

    private readonly StatoEffettiComputer stato;
    private readonly Func<LivelloResa, Acceleratore, IFonteMaschera> creaFonte;
    private readonly CodaSeriale codaAnalisi = new("Effetti: analisi");
    private readonly CodaSeriale codaResa = new("Effetti: resa");
    private readonly RiservaImmagini ingressi = new(8);
    private readonly RiservaImmagini riduzioni = new(12);
    private readonly Stopwatch orologio = Stopwatch.StartNew();

    private readonly object blocco = new();
    // Sotto blocco.
    private bool abilitato;
    private bool chiuso;
    private int generazione;
    private bool analisiOccupata;
    private Lavoro? inAttesa;
    private int inVolo;
    private int inResa;
    private bool inRitorno;
    private readonly SceltaLivello scelta = new();
    private (List<Rettangolo> Rettangoli, ulong Quando)? volti;
    private ulong ultimiVoltiChiesti;
    private ulong ultimoArrivo;
    private int scartati, erroriMaschera, senzaMaschera;
    private ulong ultimaNotaErrore;
    private readonly List<Nota> note = [];
    private double sommaMaschera, sommaResa;
    private int contaMaschera, contaResa;
    private readonly List<int> ritardi = [];
    private int? ritardoMs;
    private ulong inizioRitardi, istanteRitardo;
    private MascheraPersona? ultimaMaschera;
    private ulong arrivoUltimaMaschera;
    private (Acceleratore InUso, ModelloRitaglio Modello)? descrizioneFonte;

    // Solo sulla coda di analisi.
    private IFonteMaschera? fonte;
    private LivelloResa? livelloFonte;
    private int erroriDiFila, maschereBuone, riaperture;
    private bool soloProcessore;

    // Solo sulla coda di resa.
    private readonly Compositore compositore = new();
    private readonly ImmagineBgra?[] giro = new ImmagineBgra?[ImmaginiInUscita];
    private int prossimaUscita;
    private ulong ultimoArrivoResa;
    private (int L, int A)? misuraVideo;

    /// <param name="creaFonte">La fonte per un livello, sulla scheda video se c'è (<see cref="Acceleratore.Automatico"/>) o
    /// solo sul processore (dopo che la scheda video si è persa).</param>
    public MotoreEffetti(StatoEffettiComputer stato, Func<LivelloResa, Acceleratore, IFonteMaschera> creaFonte)
    {
        this.stato = stato;
        this.creaFonte = creaFonte;
    }

    /// <summary>Con una fonte che non sceglie dove gira (i test).</summary>
    public MotoreEffetti(StatoEffettiComputer stato, Func<LivelloResa, IFonteMaschera> creaFonte)
        : this(stato, (livello, _) => creaFonte(livello))
    {
    }

    /// <summary>Microsecondi dall'avvio del motore.</summary>
    private ulong Adesso => (ulong)(orologio.ElapsedTicks * 1_000_000.0 / Stopwatch.Frequency);

    /// <summary>Lavora solo per il telefono nella webcam (l'altro si vede com'è nel riquadro piccolo).</summary>
    public void Abilita(bool acceso)
    {
        bool cambiato;
        lock (blocco)
        {
            cambiato = abilitato != acceso;
            abilitato = acceso;
        }
        if (cambiato && !acceso) Azzera();
    }

    /// <summary>
    /// Vero se adesso un fotogramma passerebbe dal motore (effetti accesi, o in dissolvenza, o fotogrammi ancora in volo):
    /// le uscite prendono l'immagine dal motore e non dal decodificatore.
    /// </summary>
    public bool Attivo
    {
        get
        {
            var impostazioni = stato.Impostazioni;
            lock (blocco) return abilitato && !chiuso && (!impostazioni.Spente || inRitorno || inVolo > 0);
        }
    }

    /// <summary>
    /// Telefono andato, sessione nuova, stop: i fotogrammi ancora in lavorazione non arrivano più alle uscite (non
    /// rimettono un'immagine vecchia sopra la schermata di attesa); qualità e stato nel tempo ripartono da capo.
    /// </summary>
    public void Azzera()
    {
        lock (blocco)
        {
            generazione++;
            scelta.Azzera();
            volti = null;
            ultimoArrivo = 0;
            ultimaMaschera = null;
            if (inAttesa is { } vecchio)
            {
                inAttesa = null;
                inVolo--;
                ingressi.Restituisci(vecchio.Immagine);
            }
        }
        codaResa.Accoda(() =>
        {
            compositore.Azzera();
            ultimoArrivoResa = 0;
            misuraVideo = null;
        });
    }

    /// <summary>Un'immagine vuota per il prossimo fotogramma (riusata): chi decodifica la riempie e la dà a <see cref="Elabora"/>.</summary>
    public ImmagineBgra PrendiIngresso(int larghezza, int altezza) => ingressi.Prendi(larghezza, altezza);

    /// <summary>Un'immagine di <see cref="PrendiIngresso"/> che non è servita.</summary>
    public void RestituisciIngresso(ImmagineBgra immagine) => ingressi.Restituisci(immagine);

    /// <summary>
    /// Per ogni fotogramma decodificato, da qualsiasi thread. Falso: nessun effetto, l'immagine resta di chi chiama e va
    /// alle uscite com'è. Vero: il motore la prende e, dalla sua coda di resa, chiama <paramref name="consegna"/> con
    /// l'immagine elaborata (valida finché non ne arrivano altre <see cref="ImmaginiInUscita"/> − 1: chi la tiene di più
    /// la copia). Un fotogramma scartato (PC in affanno) non viene consegnato.
    /// </summary>
    public bool Elabora(ImmagineBgra immagine, Action<ImmagineBgra> consegna)
    {
        var impostazioni = stato.Impostazioni;
        var arrivo = Adesso;
        Lavoro lavoro;
        bool voltiOra;
        lock (blocco)
        {
            if (!abilitato || chiuso || (impostazioni.Spente && !inRitorno && inVolo == 0)) return false;
            if (ultimoArrivo != 0 && arrivo > ultimoArrivo) scelta.Intervallo(arrivo - ultimoArrivo);
            ultimoArrivo = arrivo;
            lavoro = new Lavoro { Immagine = immagine, Arrivo = arrivo, Generazione = generazione, Consegna = consegna };
            inVolo++;
            if (impostazioni.SfondoAcceso)
            {
                // La maschera di questo fotogramma: il fotogramma aspetta l'analisi al suo posto, chi decodifica no.
                if (analisiOccupata)
                {
                    if (inAttesa is { } vecchio)
                    {
                        inVolo--;
                        scartati++;
                        ingressi.Restituisci(vecchio.Immagine);
                    }
                    inAttesa = lavoro;
                }
                else
                {
                    analisiOccupata = true;
                    codaAnalisi.Accoda(() => Analizza(lavoro));
                }
                return true;
            }
            // Senza sfondo: i volti (se servono) in sottofondo, al massimo 10 al secondo; la resa subito con gli ultimi.
            voltiOra = impostazioni.ServonoVolti && !analisiOccupata && arrivo - Math.Min(ultimiVoltiChiesti, arrivo) >= 100_000;
            if (voltiOra)
            {
                analisiOccupata = true;
                ultimiVoltiChiesti = arrivo;
            }
        }
        if (voltiOra)
        {
            // La copia piccola si fa qui, prima della resa (che poi rimette in giro l'immagine).
            var meta = Elaborazione.Dimezza(immagine, riduzioni.Prendi(Math.Max(1, immagine.Larghezza / 2), Math.Max(1, immagine.Altezza / 2)));
            var quarto = Elaborazione.Dimezza(meta, riduzioni.Prendi(Math.Max(1, meta.Larghezza / 2), Math.Max(1, meta.Altezza / 2)));
            riduzioni.Restituisci(meta);
            int l = immagine.Larghezza, a = immagine.Altezza;
            codaAnalisi.Accoda(() => AnalizzaSoloVolti(quarto, l, a));
        }
        lock (blocco) MandaAllaResa(lavoro);
        return true;
    }

    /// <summary>Gli ultimi numeri; azzera le medie del secondo. Una volta al secondo.</summary>
    public Misure PrendiMisure()
    {
        var adesso = Adesso;
        lock (blocco)
        {
            ChiudiRitardi(adesso);
            var effetti = ritardoMs is int ms && adesso - Math.Min(istanteRitardo, adesso) <= 2_000_000 ? ms : (int?)null;
            var misure = new Misure(effetti, contaMaschera > 0 ? sommaMaschera / contaMaschera : null,
                contaResa > 0 ? sommaResa / contaResa : null, scelta.Livello, scartati, erroriMaschera, descrizioneFonte, senzaMaschera);
            sommaMaschera = sommaResa = 0;
            contaMaschera = contaResa = 0;
            return misure;
        }
    }

    /// <summary>Gli avvisi nati dall'ultima chiamata (qualità scesa, errori della maschera, fonte aperta).</summary>
    public IReadOnlyList<Nota> PrendiNote()
    {
        lock (blocco)
        {
            var prese = note.ToList();
            note.Clear();
            return prese;
        }
    }

    /// <summary>
    /// Prepara la maschera in anticipo (apre il modello), così il primo fotogramma con lo sfondo non aspetta l'apertura.
    /// Da chiamare quando si accende lo sfondo. La scheda video si scalda alla prima maschera: quei tempi non contano per
    /// la qualità (<see cref="SceltaLivello.FonteNuova"/>).
    /// </summary>
    public void Prepara() => codaAnalisi.Accoda(() => FontePerLivello());

    // MARK: analisi (coda di analisi)

    /// <summary>Sotto blocco: alla resa, se non ce ne sono già due in coda (altrimenti si scarta: il ritardo resta basso).</summary>
    private void MandaAllaResa(Lavoro lavoro)
    {
        if (inResa >= 2)
        {
            inVolo--;
            scartati++;
            ingressi.Restituisci(lavoro.Immagine);
            Libera(lavoro);
            return;
        }
        inResa++;
        codaResa.Accoda(() => Rendi(lavoro));
    }

    private IFonteMaschera? FontePerLivello()
    {
        LivelloResa voluto;
        lock (blocco) voluto = scelta.Livello;
        // Il pieno e il bordo leggero usano lo stesso modello: si rifà solo passando al veloce.
        var serve = voluto == LivelloResa.Veloce ? LivelloResa.Veloce : LivelloResa.Pieno;
        if (fonte is not null && livelloFonte == serve) return fonte;
        fonte?.Dispose();
        fonte = null;
        try
        {
            fonte = creaFonte(serve, soloProcessore ? Acceleratore.Processore : Acceleratore.Automatico);
            livelloFonte = serve;
            lock (blocco)
            {
                descrizioneFonte = (fonte.InUso, fonte.Modello);
                note.Add(new Nota.Fonte(fonte.InUso, fonte.Modello, fonte.MotivoRipiego));
                scelta.FonteNuova();
            }
        }
        catch (Exception errore)
        {
            ContaErrore(errore);
            livelloFonte = null;
        }
        return fonte;
    }

    private void Analizza(Lavoro lavoro)
    {
        var inizio = Adesso;
        var inCalcolo = false;
        try
        {
            lavoro.Meta = Elaborazione.Dimezza(lavoro.Immagine, riduzioni.Prendi(Math.Max(1, lavoro.Immagine.Larghezza / 2), Math.Max(1, lavoro.Immagine.Altezza / 2)));
            lavoro.Quarto = Elaborazione.Dimezza(lavoro.Meta, riduzioni.Prendi(Math.Max(1, lavoro.Meta.Larghezza / 2), Math.Max(1, lavoro.Meta.Altezza / 2)));
            if (FontePerLivello() is { } f)
            {
                var precedente = descrizioneFonte;
                inCalcolo = true;
                lavoro.Maschera = f.Calcola(lavoro.Quarto);
                inCalcolo = false;
                MascheraBuona();
                if ((f.InUso, f.Modello) != precedente)
                {
                    lock (blocco)
                    {
                        descrizioneFonte = (f.InUso, f.Modello);
                        note.Add(new Nota.Fonte(f.InUso, f.Modello, f.MotivoRipiego));
                    }
                }
            }
        }
        catch (Exception errore)
        {
            ContaErrore(errore);
            if (inCalcolo) ErroreDellaFonte();
        }
        lavoro.MascheraMs = (Adesso - inizio) / 1000.0;
        // I volti dalla stessa maschera, se servono.
        if (lavoro.Maschera is { } maschera && stato.Impostazioni.ServonoVolti)
            SegnaVolti(maschera, lavoro.Immagine.Larghezza, lavoro.Immagine.Altezza, lavoro.Arrivo);
        lock (blocco)
        {
            sommaMaschera += lavoro.MascheraMs;
            contaMaschera++;
            if (lavoro.Maschera is not null && lavoro.Generazione == generazione)
            {
                ultimaMaschera = lavoro.Maschera;
                arrivoUltimaMaschera = lavoro.Arrivo;
            }
            else if (ultimaMaschera is not null && lavoro.Generazione == generazione
                && lavoro.Arrivo - Math.Min(arrivoUltimaMaschera, lavoro.Arrivo) <= EtaMassimaMaschera)
            {
                // Riservatezza: niente maschera per questo fotogramma, si usa l'ultima buona (se è recente; altrimenti
                // niente consegna, vedi Compositore).
                lavoro.Maschera = ultimaMaschera;
                senzaMaschera++;
            }
            if (lavoro.Generazione != generazione)
            {
                inVolo--;
                ingressi.Restituisci(lavoro.Immagine);
                Libera(lavoro);
            }
            else
            {
                MandaAllaResa(lavoro);
            }
            LiberaAnalisi();
        }
    }

    private void AnalizzaSoloVolti(ImmagineBgra piccola, int larghezzaVideo, int altezzaVideo)
    {
        var inCalcolo = false;
        try
        {
            if (FontePerLivello() is { } f)
            {
                inCalcolo = true;
                var maschera = f.Calcola(piccola);
                inCalcolo = false;
                MascheraBuona();
                SegnaVolti(maschera, larghezzaVideo, altezzaVideo, Adesso);
            }
        }
        catch (Exception errore)
        {
            ContaErrore(errore);
            if (inCalcolo) ErroreDellaFonte();
        }
        riduzioni.Restituisci(piccola);
        lock (blocco) LiberaAnalisi();
    }

    private void SegnaVolti(MascheraPersona maschera, int larghezza, int altezza, ulong quando)
    {
        var volto = VoltoDallaMaschera.Stima(maschera, larghezza, altezza);
        lock (blocco) volti = (volto is { } v ? [v] : [], quando);
    }

    /// <summary>Sotto blocco: il prossimo fotogramma in attesa, o l'analisi libera.</summary>
    private void LiberaAnalisi()
    {
        if (inAttesa is { } prossimo)
        {
            inAttesa = null;
            codaAnalisi.Accoda(() => Analizza(prossimo));
        }
        else
        {
            analisiOccupata = false;
        }
    }

    /// <summary>Coda di analisi: una maschera calcolata, la fonte funziona.</summary>
    private void MascheraBuona()
    {
        erroriDiFila = 0;
        if (riaperture > 0 && ++maschereBuone >= MaschereBuonePerDimenticare)
        {
            riaperture = 0;
            maschereBuone = 0;
        }
    }

    /// <summary>
    /// Coda di analisi: la fonte ha lanciato un errore calcolando la maschera. Dopo <see cref="ErroriPerRiaprire"/> di fila
    /// (la scheda video si è persa: driver aggiornato, sospensione, TDR; ONNX Runtime non si riprende da solo) la fonte
    /// si chiude e il prossimo fotogramma la riapre: la prima volta come prima (DirectML su un dispositivo nuovo), dalla
    /// seconda solo sul processore. Al massimo <see cref="RiapertureMassime"/> volte finché non tornano maschere buone.
    /// </summary>
    private void ErroreDellaFonte()
    {
        maschereBuone = 0;
        if (++erroriDiFila < ErroriPerRiaprire || fonte is null || riaperture >= RiapertureMassime) return;
        var errori = erroriDiFila;
        erroriDiFila = 0;
        riaperture++;
        if (riaperture >= 2) soloProcessore = true;
        try { fonte.Dispose(); }
        catch (Exception) { }
        fonte = null;
        livelloFonte = null;
        lock (blocco) note.Add(new Nota.FonteRiaperta(errori, soloProcessore));
    }

    /// <summary>Ogni errore della maschera si conta; nel registro il primo subito, poi al massimo uno ogni 10 secondi.</summary>
    private void ContaErrore(Exception errore)
    {
        var adesso = Adesso;
        lock (blocco)
        {
            erroriMaschera++;
            if (ultimaNotaErrore == 0 || adesso - ultimaNotaErrore >= 10_000_000)
            {
                ultimaNotaErrore = Math.Max(adesso, 1);
                note.Add(new Nota.ErroreMaschera(errore.Message, erroriMaschera));
            }
        }
    }

    // MARK: resa (coda di resa)

    private void Rendi(Lavoro lavoro)
    {
        var inizio = Adesso;
        ImmagineBgra? consegnata = null;
        try
        {
            var istantanea = stato.Prendi();
            var ingresso = lavoro.Immagine;
            int l = ingresso.Larghezza, a = ingresso.Altezza;
            if (misuraVideo is { } misura && (misura.L != l || misura.A != a))
            {
                // Altro obiettivo, telefono girato, altra risoluzione: si riparte da capo, qualità compresa.
                compositore.Azzera();
                lock (blocco)
                {
                    scelta.Azzera();
                    volti = null;
                    ultimaMaschera = null;
                }
            }
            misuraVideo = (l, a);
            LivelloResa livello;
            (List<Rettangolo> Rettangoli, ulong Quando)? voltiAttuali;
            lock (blocco)
            {
                livello = scelta.Livello;
                voltiAttuali = volti;
            }
            var dt = Passo(lavoro.Arrivo);
            // Volti di non più di un secondo fa.
            var freschi = voltiAttuali is { } v && lavoro.Arrivo - Math.Min(v.Quando, lavoro.Arrivo) < 1_000_000 ? v.Rettangoli : null;
            var uscita = giro[prossimaUscita];
            if (uscita is null || uscita.Larghezza != l || uscita.Altezza != a) uscita = giro[prossimaUscita] = new ImmagineBgra(l, a);
            prossimaUscita = (prossimaUscita + 1) % giro.Length;
            var maschera = istantanea.Impostazioni.SfondoAcceso ? lavoro.Maschera : null;
            if (compositore.Rendi(new IngressoResa(ingresso, lavoro.Meta, lavoro.Quarto, maschera, freschi, voltiAttuali?.Quando, dt),
                    istantanea, livello, uscita))
                consegnata = uscita;
            else
                lock (blocco) senzaMaschera++;
            var resaMs = (Adesso - inizio) / 1000.0;
            lock (blocco)
            {
                inRitorno = compositore.InRitorno;
                sommaResa += resaMs;
                contaResa++;
                if (istantanea.Impostazioni.SfondoAcceso && scelta.Aggiungi(lavoro.MascheraMs, resaMs, out var fotogrammaMs) is { } nuovo)
                    note.Add(new Nota.Livello(nuovo, (int)Math.Round(lavoro.MascheraMs), (int)Math.Round(resaMs), (int)Math.Round(fotogrammaMs)));
            }
        }
        catch (Exception errore)
        {
            // Un errore di resa: niente consegna (mai l'immagine non elaborata).
            ContaErrore(errore);
        }
        finally
        {
            bool valida;
            lock (blocco)
            {
                inVolo--;
                inResa--;
                valida = lavoro.Generazione == generazione && abilitato && !chiuso;
            }
            ingressi.Restituisci(lavoro.Immagine);
            Libera(lavoro);
            if (consegnata is not null && valida)
            {
                try { lavoro.Consegna(consegnata); }
                catch (Exception) { }
                var fine = Adesso;
                lock (blocco) AggiungiRitardo((int)((fine - lavoro.Arrivo) / 1000), fine);
            }
        }
    }

    private void Libera(Lavoro lavoro)
    {
        riduzioni.Restituisci(lavoro.Meta);
        riduzioni.Restituisci(lavoro.Quarto);
        lavoro.Meta = lavoro.Quarto = null;
    }

    /// <summary>Secondi dal fotogramma precedente passato dalla resa (molle e dissolvenze: stessa velocità a 24, 30 e 60 fps).</summary>
    private double Passo(ulong arrivo)
    {
        var precedente = ultimoArrivoResa;
        ultimoArrivoResa = arrivo;
        if (precedente == 0 || arrivo <= precedente) return 1.0 / 30;
        return Math.Min((arrivo - precedente) / 1_000_000.0, 0.1);
    }

    /// <summary>Sotto blocco: la mediana di un secondo del ritardo del motore.</summary>
    private void AggiungiRitardo(int ms, ulong adesso)
    {
        if (ritardi.Count == 0) inizioRitardi = adesso;
        ritardi.Add(ms);
        ChiudiRitardi(adesso);
    }

    private void ChiudiRitardi(ulong adesso)
    {
        if (ritardi.Count == 0 || adesso - Math.Min(inizioRitardi, adesso) < 1_000_000) return;
        ritardi.Sort();
        ritardoMs = ritardi[ritardi.Count / 2];
        istanteRitardo = adesso;
        ritardi.Clear();
    }

    public void Dispose()
    {
        lock (blocco)
        {
            chiuso = true;
            generazione++;
        }
        codaAnalisi.Accoda(() =>
        {
            fonte?.Dispose();
            fonte = null;
        });
        codaAnalisi.Dispose();
        codaResa.Dispose();
    }
}
