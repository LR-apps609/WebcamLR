using System.Diagnostics;
using Microsoft.ML.OnnxRuntime;

namespace WebcamLR.Effetti;

/// <summary>Dove gira il modello.</summary>
public enum Acceleratore
{
    /// <summary>La scheda video con DirectML se c'è (Windows 10 1903+, DirectX 12), altrimenti il processore.</summary>
    Automatico,
    /// <summary>Solo la scheda video (DirectML): se non si apre, errore.</summary>
    SchedaVideo,
    /// <summary>Solo il processore.</summary>
    Processore,
}

/// <summary>Come creare il <see cref="RitaglioPersona"/>.</summary>
public sealed record OpzioniRitaglio
{
    public ModelloRitaglio Modello { get; init; } = ModelloRitaglio.Pieno;
    public Acceleratore Acceleratore { get; init; } = Acceleratore.Automatico;

    /// <summary>
    /// Se vero: senza scheda video si parte già dal modello leggero, e se il pieno risulta troppo lento
    /// (<see cref="MisuraVelocita"/>) si passa al leggero per il resto della sessione.
    /// </summary>
    public bool RipiegoAutomatico { get; init; } = true;

    /// <summary>Filtro nel tempo senza ritardo (<see cref="FiltroTemporale"/>).</summary>
    public bool FiltroNelTempo { get; init; } = true;

    /// <summary>Cartella dei .onnx; null: «Modelli» accanto all'exe.</summary>
    public string? CartellaModelli { get; init; }

    /// <summary>Indice della scheda video per DirectML (0 = quella principale).</summary>
    public int SchedaVideo { get; init; }

    /// <summary>Fili del processore per il modello; 0 = scelta di ONNX Runtime.</summary>
    public int Fili { get; init; }
}

/// <summary>
/// La maschera della persona alla misura del modello (256×256 o 256×144), 0 = sfondo, 255 = persona, righe dall'alto.
/// Copre tutto il fotogramma dato: si applica con le coordinate normalizzate (u, v) del fotogramma, come una texture
/// R8 stirata, anche se le proporzioni sono diverse.
/// <paramref name="Volto"/>: con il modello pieno, la classe «pelle del volto» alla stessa misura (0–255), per trovare il
/// volto senza un rilevatore a parte (<see cref="VoltoDallaMaschera"/>); null con il leggero.
/// </summary>
public sealed record MascheraPersona(byte[] Valori, int Larghezza, int Altezza, ModelloRitaglio Modello, double Millisecondi,
    byte[]? Volto = null)
{
    /// <summary>Valore in [0, 1] nel punto (u, v) del fotogramma (0..1), con interpolazione bilineare.</summary>
    public float Valore(float u, float v)
    {
        var x = Math.Clamp(u * Larghezza - 0.5f, 0f, Larghezza - 1f);
        var y = Math.Clamp(v * Altezza - 0.5f, 0f, Altezza - 1f);
        int x0 = (int)x, y0 = (int)y;
        int x1 = Math.Min(x0 + 1, Larghezza - 1), y1 = Math.Min(y0 + 1, Altezza - 1);
        float fx = x - x0, fy = y - y0;
        float a = Valori[y0 * Larghezza + x0], b = Valori[y0 * Larghezza + x1];
        float c = Valori[y1 * Larghezza + x0], d = Valori[y1 * Larghezza + x1];
        return ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy) / 255f;
    }
}

/// <summary>
/// Ritaglia la persona da un fotogramma BGRA con ONNX Runtime: DirectML sulla scheda video (Windows), il processore
/// come ripiego. Non è pensato per più thread insieme: le chiamate si mettono in fila.
/// Uso: <c>using var r = RitaglioPersona.Crea(); var m = r.Calcola(bgra, 1920, 1080);</c>
/// </summary>
public sealed class RitaglioPersona : IDisposable
{
    private readonly object blocco = new();
    private readonly OpzioniRitaglio opzioni;
    private readonly string cartella;
    private readonly FiltroTemporale filtro = new();
    private readonly MisuraVelocita misura = new();
    private Motore motore;
    private bool ripiegoTentato;

    /// <summary>Il modello in uso adesso (può passare da Pieno a Leggero durante la sessione).</summary>
    public ModelloRitaglio Modello => motore.Descrizione.Modello;

    /// <summary>Dove gira davvero: <see cref="Acceleratore.SchedaVideo"/> o <see cref="Acceleratore.Processore"/>.</summary>
    public Acceleratore InUso { get; }

    /// <summary>Perché si è lasciata la scheda video o il modello pieno (testo tecnico per il registro); null se no.</summary>
    public string? MotivoRipiego { get; private set; }

    /// <summary>Media dei ms per maschera del modello pieno (dopo il riscaldamento).</summary>
    public double MediaMs => misura.MediaMs;

    private RitaglioPersona(OpzioniRitaglio opzioni, string cartella, Motore motore, Acceleratore inUso, string? motivo)
    {
        this.opzioni = opzioni;
        this.cartella = cartella;
        this.motore = motore;
        InUso = inUso;
        MotivoRipiego = motivo;
    }

    public static RitaglioPersona Crea(OpzioniRitaglio? opzioni = null)
    {
        opzioni ??= new OpzioniRitaglio();
        var cartella = opzioni.CartellaModelli ?? Path.Combine(AppContext.BaseDirectory, "Modelli");
        string? motivo = null;

        if (opzioni.Acceleratore != Acceleratore.Processore)
        {
            if (!OperatingSystem.IsWindows())
            {
                if (opzioni.Acceleratore == Acceleratore.SchedaVideo)
                    throw new PlatformNotSupportedException("DirectML c'è solo su Windows");
                motivo = "DirectML c'è solo su Windows";
            }
            else
            {
                try
                {
                    var motore = Motore.Apri(DescrizioneModello.Di(opzioni.Modello), cartella, opzioni, directMl: true);
                    return new RitaglioPersona(opzioni, cartella, motore, Acceleratore.SchedaVideo, null);
                }
                catch (Exception e) when (opzioni.Acceleratore == Acceleratore.Automatico)
                {
                    motivo = "DirectML non disponibile: " + e.Message;
                }
            }
        }

        var modello = opzioni.Modello;
        if (motivo is not null && modello == ModelloRitaglio.Pieno && opzioni.RipiegoAutomatico)
        {
            modello = ModelloRitaglio.Leggero;
            motivo += "; modello leggero sul processore";
        }
        var cpu = Motore.Apri(DescrizioneModello.Di(modello), cartella, opzioni, directMl: false);
        return new RitaglioPersona(opzioni, cartella, cpu, Acceleratore.Processore, motivo);
    }

    /// <summary>
    /// La maschera della persona per un fotogramma BGRA (8 bit per canale; <paramref name="passo"/> = byte per riga,
    /// 0 = larghezza × 4). Bloccante: va chiamata fuori dal thread dell'interfaccia.
    /// </summary>
    public MascheraPersona Calcola(ReadOnlySpan<byte> bgra, int larghezza, int altezza, int passo = 0)
    {
        if (passo == 0) passo = larghezza * 4;
        Preparazione.ControllaImmagine(bgra, larghezza, altezza, passo);
        lock (blocco)
        {
            var orologio = Stopwatch.StartNew();
            var m = motore;
            var d = m.Descrizione;
            Preparazione.BgraInRgb(bgra, larghezza, altezza, passo, m.Ingresso, d.Larghezza, d.Altezza, d.Scala, d.Spostamento);
            m.Esegui();
            Preparazione.Persona(m.Uscita, d.Canali, m.Persona);
            if (opzioni.FiltroNelTempo) filtro.Applica(m.Persona);
            var valori = new byte[m.Persona.Length];
            for (var i = 0; i < valori.Length; i++) valori[i] = (byte)(m.Persona[i] * 255f + 0.5f);
            byte[]? volto = null;
            if (d.Canali > Preparazione.ClassePelleVolto)
            {
                volto = new byte[m.Persona.Length];
                Preparazione.Classe(m.Uscita, d.Canali, Preparazione.ClassePelleVolto, volto);
            }
            var ms = orologio.Elapsed.TotalMilliseconds;

            if (d.Modello == ModelloRitaglio.Pieno && opzioni.RipiegoAutomatico && !ripiegoTentato && misura.Aggiungi(ms))
            {
                ripiegoTentato = true;
                MotivoRipiego = $"modello pieno troppo lento: {misura.MediaMs:0} ms per maschera";
                try
                {
                    motore = Motore.Apri(DescrizioneModello.Leggero, cartella, opzioni, directMl: InUso == Acceleratore.SchedaVideo);
                    m.Dispose();
                    filtro.Dimentica();
                }
                catch (Exception e)
                {
                    // Si resta sul pieno: lento, ma la maschera c'è.
                    MotivoRipiego += "; il leggero non si apre: " + e.Message;
                }
            }
            return new MascheraPersona(valori, d.Larghezza, d.Altezza, d.Modello, ms, volto);
        }
    }

    public void Dispose()
    {
        lock (blocco) motore.Dispose();
    }

    /// <summary>Una sessione ONNX Runtime con i suoi buffer, riusati a ogni fotogramma.</summary>
    private sealed class Motore : IDisposable
    {
        public required DescrizioneModello Descrizione { get; init; }
        public required InferenceSession Sessione { get; init; }
        public required float[] Ingresso { get; init; }
        public required float[] Uscita { get; init; }
        public required float[] Persona { get; init; }
        public required OrtValue ValoreIngresso { get; init; }
        public required OrtValue ValoreUscita { get; init; }
        private readonly RunOptions esecuzione = new();
        private string[] nomiIngresso = [];
        private string[] nomiUscita = [];

        /// <summary>
        /// Le build ufficiali di ONNX Runtime per Windows hanno eventi di telemetria (TraceLogging, seguono le impostazioni
        /// di diagnostica di Windows). Li spegniamo una volta per processo, sull'ambiente unico di ONNX Runtime, prima che
        /// si crei qualsiasi sessione: un costruttore statico esplicito gira prima del primo <see cref="Apri"/>.
        /// Altrove (Linux, macOS: solo per i test) la chiamata non fa nulla.
        /// </summary>
        static Motore()
        {
            OrtEnv.Instance().DisableTelemetryEvents();
        }

        public static Motore Apri(DescrizioneModello d, string cartella, OpzioniRitaglio opzioni, bool directMl)
        {
            var percorso = Path.Combine(cartella, d.File);
            if (!File.Exists(percorso)) throw new FileNotFoundException("Modello mancante", percorso);
            using var so = new SessionOptions { GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL };
            if (directMl)
            {
                // DirectML chiede l'esecuzione in sequenza e niente schema di memoria (documentazione ONNX Runtime).
                so.EnableMemoryPattern = false;
                so.ExecutionMode = ExecutionMode.ORT_SEQUENTIAL;
                so.AppendExecutionProvider_DML(opzioni.SchedaVideo);
            }
            else if (opzioni.Fili > 0)
            {
                so.IntraOpNumThreads = opzioni.Fili;
            }
            var sessione = new InferenceSession(percorso, so);
            try
            {
                Controlla(sessione, d);
                var ingresso = new float[d.Altezza * d.Larghezza * 3];
                var uscita = new float[d.Altezza * d.Larghezza * d.Canali];
                return new Motore
                {
                    Descrizione = d,
                    Sessione = sessione,
                    Ingresso = ingresso,
                    Uscita = uscita,
                    Persona = new float[d.Altezza * d.Larghezza],
                    ValoreIngresso = OrtValue.CreateTensorValueFromMemory(ingresso, [1, d.Altezza, d.Larghezza, 3]),
                    ValoreUscita = OrtValue.CreateTensorValueFromMemory(uscita, [1, d.Altezza, d.Larghezza, d.Canali]),
                    nomiIngresso = [DescrizioneModello.NomeIngresso],
                    nomiUscita = [d.NomeUscita],
                };
            }
            catch
            {
                sessione.Dispose();
                throw;
            }
        }

        /// <summary>Il file deve essere quello atteso: un modello sbagliato darebbe una maschera senza senso.</summary>
        private static void Controlla(InferenceSession s, DescrizioneModello d)
        {
            if (!s.InputMetadata.TryGetValue(DescrizioneModello.NomeIngresso, out var i)
                || !i.Dimensions.SequenceEqual([1, d.Altezza, d.Larghezza, 3]))
                throw new InvalidDataException($"{d.File}: ingresso diverso da [1,{d.Altezza},{d.Larghezza},3]");
            if (!s.OutputMetadata.TryGetValue(d.NomeUscita, out var u)
                || !u.Dimensions.SequenceEqual([1, d.Altezza, d.Larghezza, d.Canali]))
                throw new InvalidDataException($"{d.File}: uscita diversa da [1,{d.Altezza},{d.Larghezza},{d.Canali}]");
        }

        public void Esegui() =>
            Sessione.Run(esecuzione, nomiIngresso, [ValoreIngresso], nomiUscita, [ValoreUscita]);

        public void Dispose()
        {
            ValoreIngresso.Dispose();
            ValoreUscita.Dispose();
            esecuzione.Dispose();
            Sessione.Dispose();
        }
    }
}
