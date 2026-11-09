namespace WebcamLR.Ricevitore;

// Qualità 14: la coda di ricezione che si adatta (Documenti/Protocollo.md, «Latenza»). Senza Windows, provata con tempi
// finti in CodaAdattivaTest.cs. La stessa logica del Mac (Mac/Sorgenti/CodaAdattiva.swift).

/// <summary>
/// Quanto far aspettare i fotogrammi sul computer prima di mostrarli: il meno possibile con la rete stabile, un po' di
/// più solo quando il ritardo varia (jitter), mai oltre <see cref="Tetto"/>.
/// <para>
/// Per ogni fotogramma si guarda il suo <b>margine</b>: quanto prima del suo momento di uscita è pronto (negativo = in
/// ritardo, si vedrà uno scatto). Degli ultimi <see cref="Finestra"/> margini si prende il «basso»: il più piccolo dopo
/// aver lasciato fuori i <see cref="Tollerati"/> peggiori (una pausa isolata della rete non fa crescere la coda, una che
/// torna sì). Se il basso è sopra <see cref="Obiettivo"/> di oltre <see cref="Isteresi"/>, la coda si accorcia; se è
/// sotto l'obiettivo, si allunga (ma il fotogramma arrivato prima non aspetta mai oltre il tetto); ogni volta di al massimo <see cref="PassoMassimo"/> per fotogramma (circa il 6% a
/// 30 fps, invisibile). I margini già in finestra si correggono dello stesso passo: non si conta due volte.
/// </para>
/// <para>
/// Due modi d'uso. Windows (il lettore di sistema decide quando mostrare, dal tempo dei campioni): il margine è
/// l'anticipo del campione sulla posizione del lettore, con <see cref="Aggiungi"/>; il risultato accorcia (positivo) o
/// allunga (negativo) la linea del tempo, e <see cref="Spostamento"/> è il totale. Mac (l'immagine decodificata esce a
/// un istante scelto da noi): <see cref="Uscita"/> dà l'istante, cattura più un ritardo che si adatta.
/// </para>
/// Nessun tetto allo spostamento totale: la deriva lenta tra l'orologio del telefono e quello del computer si accumula
/// per tutta la chiamata (collaudo 38). Il tetto è sulla profondità della coda. Solo su un thread (o sotto blocco).
/// </summary>
public sealed class CodaAdattiva
{
    /// <summary>Quanti margini si guardano: 5 secondi a 30 fps.</summary>
    public const int Finestra = 150;
    /// <summary>Prima di questi margini non si cambia nulla: non si sa ancora come arriva il video.</summary>
    public const int Minimi = 30;
    /// <summary>I fotogrammi più in ritardo, su una finestra intera, che non fanno crescere la coda (il 2%).</summary>
    public const int Tollerati = 3;
    /// <summary>Di quanto si sposta la coda, al massimo, a ogni fotogramma (µs).</summary>
    public const long PassoMassimo = 2_000;
    /// <summary>Sopra l'obiettivo di meno di questo (µs) non si accorcia: niente avanti e indietro di continuo.</summary>
    public const long Isteresi = 3_000;
    /// <summary>La coda più profonda (µs): oltre, meglio uno scatto che altro ritardo.</summary>
    public const long Tetto = 100_000;
    /// <summary>Un margine oltre questo (µs) non è credibile (posizione del lettore ferma, orologi cambiati).</summary>
    public const long MargineAssurdo = 2_000_000;

    /// <summary>
    /// Windows: il lettore deve avere il campione prima del suo momento, per decodificarlo (era la soglia fissa di
    /// 20 ms del recupero di prima).
    /// </summary>
    public const long ObiettivoWindows = 12_000;
    /// <summary>Mac: l'immagine è già decodificata, basta la precisione del timer.</summary>
    public const long ObiettivoMac = 2_000;

    private readonly Queue<long> margini = new();
    private readonly long[] ordinati = new long[Finestra];
    /// <summary>Per <see cref="Uscita"/>: dalla cattura all'uscita (µs); null prima del primo fotogramma.</summary>
    private long? ritardoUscita;

    public CodaAdattiva(long obiettivo = ObiettivoWindows) => Obiettivo = obiettivo;

    /// <summary>Il margine voluto per il «basso» della finestra (µs).</summary>
    public long Obiettivo { get; }

    /// <summary>Di quanto la coda è stata accorciata in tutto (µs); negativo se è stata allungata più che accorciata.</summary>
    public long Spostamento { get; private set; }

    /// <summary>La profondità della coda adesso: il margine più grande della finestra (µs), cioè quanto aspetta il
    /// fotogramma arrivato prima. 0 senza misure.</summary>
    public long Profondita => margini.Count == 0 ? 0 : Math.Max(0, margini.Max());

    /// <summary>
    /// Il margine di un fotogramma, con la coda già corretta di <see cref="Spostamento"/>. Restituisce di quanto
    /// accorciarla adesso (positivo), allungarla (negativo) o 0; <see cref="Spostamento"/> cambia dello stesso valore.
    /// </summary>
    public long Aggiungi(long margine)
    {
        if (margine > MargineAssurdo || margine < -MargineAssurdo)
        {
            margini.Clear();
            return 0;
        }
        margini.Enqueue(margine);
        if (margini.Count > Finestra) margini.Dequeue();
        if (margini.Count < Minimi) return 0;

        var quanti = margini.Count;
        margini.CopyTo(ordinati, 0);
        Array.Sort(ordinati, 0, quanti);
        var basso = ordinati[Tollerati * quanti / Finestra];
        var alto = ordinati[quanti - 1];

        long passo = 0;
        if (alto > Tetto)
        {
            // Troppo profonda (il primo fotogramma era arrivato tardi, o una rete pessima): si accorcia comunque.
            passo = Math.Min(PassoMassimo, alto - Tetto);
        }
        else if (basso > Obiettivo + Isteresi)
        {
            passo = Math.Min(PassoMassimo, basso - Obiettivo);
        }
        else if (basso < Obiettivo)
        {
            // Più profonda solo fino al tetto: il fotogramma arrivato prima non aspetta mai più di così.
            passo = -Math.Min(Math.Min(PassoMassimo, Obiettivo - basso), Math.Max(0, Tetto - alto));
        }
        if (passo == 0) return 0;
        Spostamento += passo;
        // I margini in fila valevano per la coda di prima: accorciata, sono più piccoli dello stesso passo.
        for (var i = 0; i < quanti; i++)
        {
            var valore = margini.Dequeue();
            margini.Enqueue(valore - passo);
        }
        return passo;
    }

    /// <summary>
    /// Mac: l'istante (orologio del computer, µs) in cui far uscire un'immagine catturata a <paramref name="cattura"/>
    /// (già nell'orologio del computer) e pronta <paramref name="adesso"/>. Può essere già passato (immagine in ritardo).
    /// Null se il transito non è credibile: l'immagine esce subito e non entra nelle misure.
    /// </summary>
    public ulong? Uscita(long cattura, ulong adesso)
    {
        var transito = unchecked((long)adesso - cattura);
        if (transito < 0 || transito >= RitardoVetro.MassimoMs * 1000L) return null;
        // Il primo fotogramma, o gli orologi cambiati di colpo: si riparte da questo, con il margine voluto.
        if (ritardoUscita is not long ritardo || Math.Abs(ritardo - transito) > MargineAssurdo)
        {
            margini.Clear();
            ritardo = transito + Obiettivo;
        }
        ritardo -= Aggiungi(ritardo - transito);
        ritardoUscita = ritardo;
        return (ulong)Math.Max(cattura + ritardo, 0);
    }

    /// <summary>
    /// Scarta i vecchi invece di accumulare ritardo: delle immagini in fila (con il loro istante di uscita, in ordine),
    /// quante delle prime buttare perché ce n'è una più recente già al suo momento. Si mostra solo l'ultima scaduta.
    /// </summary>
    /// <param name="anticipo">Un'immagine è al suo momento se il suo istante è entro questo da adesso (µs).</param>
    public static int DaScartare(IReadOnlyList<ulong> istanti, ulong adesso, ulong anticipo)
    {
        var scadute = 0;
        while (scadute < istanti.Count && istanti[scadute] <= adesso + anticipo) scadute++;
        return Math.Max(scadute - 1, 0);
    }

    public void Azzera()
    {
        margini.Clear();
        Spostamento = 0;
        ritardoUscita = null;
    }
}

/// <summary>
/// Qualità 14: la latenza divisa nelle sue parti, per i numeri del computer. Rete: dalla cattura all'arrivo sul computer
/// (comprende la codifica sul telefono). Coda: l'attesa sul computer prima di essere mostrato (<see cref="CodaAdattiva"/>).
/// Decodifica: il resto fino all'anteprima (decodifica e disegno, e gli effetti del computer se accesi).
/// </summary>
public static class PartiLatenza
{
    /// <summary>Da vetro all'anteprima meno rete e coda; null se manca una delle tre, mai sotto zero.</summary>
    public static int? Decodifica(int? anteprimaMs, int? reteMs, int? codaMs) =>
        anteprimaMs is int totale && reteMs is int rete && codaMs is int coda ? Math.Max(0, totale - rete - coda) : null;
}
