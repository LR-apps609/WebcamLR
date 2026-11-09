namespace WebcamLR.Effetti;

/// <summary>
/// La qualità della resa con lo sfondo acceso, che si adatta al PC (Qualità 6, come Google Meet): scende presto se il PC
/// non regge i fotogrammi al secondo e risale piano quando c'è margine (<see cref="SceltaLivello"/>). In ordine, dal più
/// bello al più leggero; il filtro nel tempo della maschera (<see cref="FiltroTemporale"/>, <see cref="MediaNelMovimento"/>,
/// <see cref="IsteresiMaschera"/>) resta acceso a tutti i livelli: costa meno di un millisecondo. Con lo sfondo sostituito
/// il bordo pulito si salta ai livelli con il bordo bilineare; dove si compone (scheda video o processore) lo sceglie il
/// <see cref="Compositore"/>, e il tempo misurato è quello vero, scheda video compresa.
/// </summary>
public enum LivelloResa
{
    /// <summary>Modello pieno, maschera a ogni fotogramma, bordo rifinito con il filtro guidato a metà risoluzione.</summary>
    Pieno,
    /// <summary>Come il pieno, ma il bordo rifinito a un quarto della risoluzione (costa quattro volte meno).</summary>
    BordoLeggero,
    /// <summary>
    /// Modello pieno con il bordo a un quarto, ma la maschera un fotogramma sì e uno no: quello in mezzo riusa la maschera
    /// del precedente (la persona si sposta di poco in 33 ms). Dimezza il lavoro del ritaglio.
    /// </summary>
    MascheraAlterna,
    /// <summary>Modello leggero e bordo bilineare, senza filtro guidato: per i PC lenti.</summary>
    Veloce,
    /// <summary>Come il veloce, con la maschera un fotogramma sì e uno no: l'ultimo gradino.</summary>
    Minimo,
}

/// <summary>Che cosa cambia a ogni livello (la resa e il motore leggono queste, non i nomi dei livelli).</summary>
public static class GradiniLivello
{
    /// <summary>Il modello leggero invece del pieno.</summary>
    public static bool ConModelloLeggero(this LivelloResa livello) => livello >= LivelloResa.Veloce;

    /// <summary>La maschera un fotogramma sì e uno no.</summary>
    public static bool ConMascheraAlterna(this LivelloResa livello) =>
        livello is LivelloResa.MascheraAlterna or LivelloResa.Minimo;

    /// <summary>Il bordo rifinito a metà risoluzione (solo il pieno).</summary>
    public static bool ConBordoAMeta(this LivelloResa livello) => livello == LivelloResa.Pieno;

    /// <summary>Il bordo bilineare, senza filtro guidato.</summary>
    public static bool ConBordoBilineare(this LivelloResa livello) => livello >= LivelloResa.Veloce;
}

/// <summary>Un cambio di livello deciso da <see cref="SceltaLivello"/>, con le medie della finestra che l'ha deciso.</summary>
public readonly record struct CambioLivello(LivelloResa Da, LivelloResa A, double MascheraMs, double ResaMs, double FotogrammaMs)
{
    /// <summary>Vero se la qualità sale (c'era margine), falso se scende (il PC non reggeva).</summary>
    public bool Salita => A < Da;
}

/// <summary>
/// La scala dei livelli (Qualità 6, «qualità che si adatta al PC»), separata dal motore e provata con tempi finti.
///
/// Si misura a finestre di <see cref="FinestraUs"/> (2 s) con i tempi di ogni fotogramma reso (maschera e resa: due code
/// che lavorano in parallelo, quindi conta la più lenta delle due medie) e si confronta con il tempo di un fotogramma: la
/// media della metà centrale degli ultimi 30 intervalli d'arrivo (un intoppo del Wi-Fi, una raffica di due fotogrammi o
/// una pausa non contano), mai sotto quello dei fps dichiarati dal telefono (<see cref="Fps"/>: 33 ms a 30 fps, 17 ms a
/// 60) né, se non li dice, sotto 1/60 di secondo.
/// - <b>Scende</b> appena una finestra supera l'85% del fotogramma: di un gradino che alleggerisce la coda più lenta
///   (<see cref="Giu"/>). Il fotogramma dopo il cambio riparte da una finestra nuova.
/// - <b>Risale</b> di un gradino dopo <see cref="FinestreDiMarginePerSalire"/> finestre di fila (10 s) sotto il 50% del
///   fotogramma. Se poi ricade entro <see cref="ProvaRisalitaUs"/> (30 s) dal gradino appena preso, la prossima volta
///   aspetta il doppio (20 s, 40 s… fino a 160 s): un PC al limite non fa avanti e indietro ogni 12 secondi. Dopo 30 s
///   tenuti si torna all'attesa normale.
/// I primi <see cref="FotogrammiDiRiscaldamento"/> fotogrammi dopo <see cref="Azzera"/> o una fonte nuova non contano: la
/// scheda video si scalda alla prima maschera (DirectML compila gli shader, 1–2 s).
/// Non è thread-safe: il motore la usa sotto il suo blocco.
/// </summary>
public sealed class SceltaLivello
{
    /// <summary>Quanto dura una finestra di misura (µs).</summary>
    public const ulong FinestraUs = 2_000_000;

    /// <summary>Una finestra con meno fotogrammi resi (video a 5 fps, fotogrammi scartati) non decide.</summary>
    public const int FotogrammiPerFinestra = 10;

    /// <summary>Oltre questa parte del fotogramma (in media sulla finestra) il PC non regge: si scende.</summary>
    public const double QuotaFotogramma = 0.85;

    /// <summary>Sotto questa parte del fotogramma c'è margine per il gradino sopra (che costa fino al doppio).</summary>
    public const double QuotaRisalita = 0.5;

    /// <summary>Finestre di margine di fila per risalire di un gradino (10 s), raddoppiate a ogni ricaduta.</summary>
    public const int FinestreDiMarginePerSalire = 5;

    /// <summary>Raddoppi al massimo dell'attesa per risalire: 10 s × 2⁴ = 160 s.</summary>
    public const int RicaduteMassime = 4;

    /// <summary>Una risalita è riuscita se il gradino preso regge per tanto così (µs); se ricade prima, l'attesa raddoppia.</summary>
    public const ulong ProvaRisalitaUs = 30_000_000;

    /// <summary>Un buco tra due fotogrammi resi più lungo di così (µs: sfondo spento e riacceso, video fermo) apre una finestra nuova.</summary>
    public const ulong PausaUs = 1_000_000;

    /// <summary>I fotogrammi che non contano dopo un azzeramento o una fonte nuova (come il riscaldamento di MisuraVelocita).</summary>
    public const int FotogrammiDiRiscaldamento = 5;

    /// <summary>Il fotogramma più breve che si considera (ms) se il telefono non dice i suoi fps: oltre i 60 fps non si va.</summary>
    public const double FotogrammaMinimoMs = 1000.0 / 60;

    private readonly LivelloResa iniziale;
    private readonly Queue<ulong> intervalli = new();
    private int fps;
    private int daScartare = FotogrammiDiRiscaldamento;
    // La finestra in corso.
    private ulong inizioFinestra, ultimoFotogramma;
    private double sommaMaschera, sommaResa;
    private int conta;
    // La risalita.
    private int finestreDiMargine;
    private int ricadute;
    private (LivelloResa Livello, ulong Quando)? ultimaSalita;

    /// <param name="iniziale">Il livello di partenza e dopo ogni <see cref="Azzera"/>: il pieno nell'app, un altro nei test.</param>
    public SceltaLivello(LivelloResa iniziale = LivelloResa.Pieno)
    {
        this.iniziale = iniziale;
        Livello = iniziale;
    }

    public LivelloResa Livello { get; private set; }

    /// <summary>Quante finestre di margine di fila servono adesso per risalire (5, poi 10, 20… dopo le ricadute).</summary>
    public int FinestrePerSalire => FinestreDiMarginePerSalire << ricadute;

    /// <summary>Il tempo tra due fotogrammi arrivati (µs).</summary>
    public void Intervallo(ulong microsecondi)
    {
        intervalli.Enqueue(microsecondi);
        while (intervalli.Count > 30) intervalli.Dequeue();
    }

    /// <summary>I fps del video dichiarati dal telefono (messaggio «formato»); 0 = non detti. Restano dopo <see cref="Azzera"/>.</summary>
    public void Fps(int fotogrammiAlSecondo) => fps = Math.Max(0, fotogrammiAlSecondo);

    /// <summary>La fonte della maschera è nuova (aperta, riaperta, cambiata): i prossimi fotogrammi scaldano la scheda video.</summary>
    public void FonteNuova() => daScartare = FotogrammiDiRiscaldamento;

    /// <summary>
    /// Il tempo di un fotogramma (ms) con cui si confronta: la media della metà centrale degli intervalli, almeno quello
    /// dei fps dichiarati (o 1/60 s). Null se non si sa ancora nulla.
    /// </summary>
    public double? FotogrammaMs
    {
        get
        {
            var minimo = fps > 0 ? 1000.0 / fps : FotogrammaMinimoMs;
            if (intervalli.Count == 0) return fps > 0 ? minimo : null;
            var ordinati = intervalli.Order().ToArray();
            int via = ordinati.Length / 4, quanti = ordinati.Length - 2 * via;
            double totale = 0;
            for (var i = via; i < via + quanti; i++) totale += ordinati[i];
            return Math.Max(totale / quanti / 1000.0, minimo);
        }
    }

    /// <summary>
    /// I tempi di un fotogramma reso con lo sfondo acceso e il suo istante (µs, lo stesso orologio degli intervalli);
    /// il cambio di livello se la finestra che chiude lo decide, altrimenti null.
    /// </summary>
    public CambioLivello? Aggiungi(double mascheraMs, double resaMs, ulong adessoUs)
    {
        if (daScartare > 0)
        {
            daScartare--;
            return null;
        }
        if (conta > 0 && (adessoUs < ultimoFotogramma || adessoUs - ultimoFotogramma > PausaUs)) ChiudiFinestra();
        if (conta == 0) inizioFinestra = adessoUs;
        ultimoFotogramma = adessoUs;
        sommaMaschera += mascheraMs;
        sommaResa += resaMs;
        conta++;
        if (conta < FotogrammiPerFinestra || adessoUs - inizioFinestra < FinestraUs) return null;
        var maschera = sommaMaschera / conta;
        var resa = sommaResa / conta;
        ChiudiFinestra();
        if (FotogrammaMs is not double fotogramma) return null;

        // Il gradino preso salendo ha retto per la prova: la prossima risalita aspetta di nuovo il tempo normale.
        if (ultimaSalita is { } salita && adessoUs - Math.Min(salita.Quando, adessoUs) >= ProvaRisalitaUs)
        {
            ultimaSalita = null;
            ricadute = 0;
        }
        var media = Math.Max(maschera, resa);
        if (media > fotogramma * QuotaFotogramma)
        {
            finestreDiMargine = 0;
            var giu = Giu(Livello, maschera, resa, fotogramma * QuotaFotogramma);
            if (giu == Livello) return null;
            // Ricaduto dal gradino appena preso: la prossima volta si aspetta il doppio.
            if (ultimaSalita?.Livello == Livello) ricadute = Math.Min(ricadute + 1, RicaduteMassime);
            ultimaSalita = null;
            return Cambia(giu, maschera, resa, fotogramma);
        }
        if (media > fotogramma * QuotaRisalita || Livello == LivelloResa.Pieno)
        {
            finestreDiMargine = 0;
            return null;
        }
        if (++finestreDiMargine < FinestrePerSalire) return null;
        finestreDiMargine = 0;
        var su = Livello - 1;
        ultimaSalita = (su, adessoUs);
        return Cambia(su, maschera, resa, fotogramma);
    }

    /// <summary>
    /// Il gradino sotto <paramref name="livello"/> che alleggerisce la coda più lenta: con la maschera lenta la maschera
    /// alterna (o subito il modello leggero, se anche dimezzata non ci starebbe), con la resa lenta il bordo più leggero.
    /// Dal veloce, il minimo in ogni caso (meno lavoro sul processore aiuta anche la resa). Dal minimo, niente.
    /// </summary>
    public static LivelloResa Giu(LivelloResa livello, double mascheraMs, double resaMs, double limiteMs)
    {
        var colloMaschera = mascheraMs > resaMs;
        return livello switch
        {
            LivelloResa.Pieno or LivelloResa.BordoLeggero when colloMaschera =>
                mascheraMs / 2 > limiteMs ? LivelloResa.Veloce : LivelloResa.MascheraAlterna,
            LivelloResa.Pieno => LivelloResa.BordoLeggero,
            LivelloResa.BordoLeggero or LivelloResa.MascheraAlterna => LivelloResa.Veloce,
            _ => LivelloResa.Minimo,
        };
    }

    private CambioLivello Cambia(LivelloResa nuovo, double maschera, double resa, double fotogramma)
    {
        var cambio = new CambioLivello(Livello, nuovo, maschera, resa, fotogramma);
        Livello = nuovo;
        return cambio;
    }

    private void ChiudiFinestra()
    {
        sommaMaschera = sommaResa = 0;
        conta = 0;
    }

    /// <summary>Telefono nuovo, sessione nuova, altra misura del video: si riparte dal livello iniziale (i fps restano).</summary>
    public void Azzera()
    {
        Livello = iniziale;
        intervalli.Clear();
        ChiudiFinestra();
        daScartare = FotogrammiDiRiscaldamento;
        finestreDiMargine = 0;
        ricadute = 0;
        ultimaSalita = null;
    }
}
