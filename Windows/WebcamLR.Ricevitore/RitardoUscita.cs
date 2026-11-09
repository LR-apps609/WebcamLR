namespace WebcamLR.Ricevitore;

// Il ritardo «da vetro a uscita» (Documenti/Protocollo.md, «Latenza»): dalla cattura sul telefono al fotogramma
// decodificato che esce nell'anteprima o nella webcam. Pezzi senza Windows, provati in RitardoUscitaTest.cs.
// La stessa logica del Mac (Mac/Sorgenti/RitardoUscita.swift).

/// <summary>Il conto del ritardo di un fotogramma, dalla cattura (orologio del telefono) a «adesso» (orologio del computer).</summary>
public static class RitardoVetro
{
    /// <summary>Oltre questo valore la misura non è credibile (orologi appena cambiati, timestamp assurdo).</summary>
    public const int MassimoMs = 10_000;

    /// <param name="timestampTelefono">Il timestamp di cattura del fotogramma, in µs sull'orologio del telefono.</param>
    /// <param name="scarto">Orologio del telefono meno orologio del computer (il pong più rapido), in µs.</param>
    /// <param name="adesso">L'orologio del computer quando il fotogramma esce, in µs.</param>
    /// <returns>I millisecondi da vetro a uscita, oppure null se non credibili.</returns>
    public static int? Ms(ulong timestampTelefono, long scarto, ulong adesso)
    {
        // Valori dalla rete: aritmetica senza trabocchi, un orologio assurdo esce dal controllo qui sotto.
        var cattura = unchecked((long)timestampTelefono - scarto);
        var micro = unchecked((long)adesso - cattura);
        if (micro < 0 || micro >= MassimoMs * 1000L) return null;
        return (int)(micro / 1000);
    }

    /// <summary>
    /// La latenza da mostrare e da mandare al telefono (<c>latenza.ms</c>): da vetro alla webcam se il telefono è nella
    /// webcam e la webcam riceve il video, altrimenti da vetro all'anteprima, altrimenti fino all'arrivo sul computer.
    /// </summary>
    public static int? Latenza(int? webcamMs, int? anteprimaMs, int? arrivoMs) => webcamMs ?? anteprimaMs ?? arrivoMs;
}

/// <summary>
/// Ogni 30 secondi, mentre il video arriva e si misura, una riga con le tappe del ritardo nel registro: è quella da
/// mandare a Claude dopo una prova (Documenti/Prove webcam virtuale.md). Una volta al secondo, sul thread dell'interfaccia.
/// </summary>
public sealed class RitardoNelRegistro
{
    public const int IntervalloSecondi = 30;

    private int secondi;

    /// <summary>Vero quando è il momento di scrivere la riga; senza misure si riparte da zero.</summary>
    public bool Conta(Statistiche statistiche)
    {
        if (statistiche.LatenzaMs is null || statistiche.Fps == 0)
        {
            secondi = 0;
            return false;
        }
        if (++secondi < IntervalloSecondi) return false;
        secondi = 0;
        return true;
    }

    /// <summary>«72 ms», oppure «—» se non si sa.</summary>
    public static string Testo(int? ms) => ms is int valore ? $"{valore} ms" : "—";
}

/// <summary>
/// La mediana di un secondo di misure, leggibile da chiunque senza azzerarla (anteprima, webcam, sessione).
/// Una misura vecchia di più di 2 secondi non vale più: nessun fotogramma esce da lì.
/// Da qualsiasi thread.
/// </summary>
public sealed class MisuraRitardo
{
    public const ulong Finestra = 1_000_000;
    public const ulong Scadenza = 2_000_000;

    private readonly object blocco = new();
    private readonly List<int> campioni = new();
    private ulong inizio;
    private int? valore;
    private ulong istanteValore;

    public void Aggiungi(int ms, ulong adesso)
    {
        lock (blocco)
        {
            if (campioni.Count == 0) inizio = adesso;
            campioni.Add(ms);
            if (adesso - Math.Min(inizio, adesso) >= Finestra) Chiudi(adesso);
        }
    }

    /// <summary>La mediana dell'ultimo secondo concluso; null se non c'è o se è più vecchia di 2 secondi.</summary>
    public int? Valore(ulong adesso)
    {
        lock (blocco)
        {
            if (campioni.Count > 0 && adesso - Math.Min(inizio, adesso) >= Finestra) Chiudi(adesso);
            return valore is int v && adesso - Math.Min(istanteValore, adesso) <= Scadenza ? v : null;
        }
    }

    public void Azzera()
    {
        lock (blocco)
        {
            campioni.Clear();
            valore = null;
        }
    }

    private void Chiudi(ulong adesso)
    {
        campioni.Sort();
        valore = campioni[campioni.Count / 2];
        istanteValore = adesso;
        campioni.Clear();
    }
}

/// <summary>
/// Quale fotogramma del telefono è quello che il lettore mostra adesso: per ogni campione dato al decodificatore si
/// tengono il suo tempo nella linea del lettore e il timestamp del telefono; dalla posizione del lettore si risale al
/// fotogramma con il tempo più grande non oltre la posizione. Gli ultimi 128 fotogrammi bastano (4 secondi a 30 fps).
/// Da qualsiasi thread.
/// </summary>
public sealed class TracciaFotogrammi
{
    public const int Capacita = 128;
    /// <summary>La posizione del lettore può essere un pelo prima del tempo del fotogramma appena mostrato.</summary>
    public const long Tolleranza = 2_000;

    private readonly object blocco = new();
    private readonly (long Tempo, ulong Timestamp)[] posti = new (long, ulong)[Capacita];
    private int quanti;
    private int prossimo;

    /// <param name="tempo">Il tempo del campione nella linea del lettore, in µs.</param>
    /// <param name="timestampTelefono">Il timestamp di cattura del fotogramma (orologio del telefono).</param>
    public void Aggiungi(long tempo, ulong timestampTelefono)
    {
        lock (blocco)
        {
            posti[prossimo] = (tempo, timestampTelefono);
            prossimo = (prossimo + 1) % Capacita;
            quanti = Math.Min(quanti + 1, Capacita);
        }
    }

    /// <summary>Il timestamp del telefono del fotogramma mostrato alla <paramref name="posizione"/> (µs); null se nessuno.</summary>
    public ulong? Mostrato(long posizione)
    {
        lock (blocco)
        {
            ulong? trovato = null;
            var migliore = long.MinValue;
            for (var i = 0; i < quanti; i++)
            {
                var (tempo, timestamp) = posti[i];
                if (tempo <= posizione + Tolleranza && tempo > migliore)
                {
                    migliore = tempo;
                    trovato = timestamp;
                }
            }
            return trovato;
        }
    }

    public void Azzera()
    {
        lock (blocco)
        {
            quanti = 0;
            prossimo = 0;
        }
    }
}

/// <summary>
/// Il ritardo dell'audio deve restare stabile (le app di chiamata odiano il ritardo che oscilla): vale il massimo delle
/// misure degli ultimi 5 secondi. Così sale subito (meglio la voce un attimo dopo le labbra che un buco) e scende solo
/// dopo 5 secondi di valori più bassi. Solo su un thread.
/// </summary>
public sealed class StabilizzatoreRitardo
{
    public const int Secondi = 5;

    private readonly List<(ulong Secondo, int Massimo)> secondi = new();

    public void Aggiungi(int ms, ulong adesso)
    {
        var secondo = adesso / 1_000_000;
        if (secondi.Count > 0 && secondi[^1].Secondo == secondo)
        {
            secondi[^1] = (secondo, Math.Max(secondi[^1].Massimo, ms));
        }
        else
        {
            secondi.Add((secondo, ms));
        }
        secondi.RemoveAll(s => secondo - Math.Min(s.Secondo, secondo) >= Secondi);
    }

    /// <summary>Il massimo degli ultimi 5 secondi; null se non c'è nessuna misura.</summary>
    public int? Voluto => secondi.Count == 0 ? null : secondi.Max(s => s.Massimo);

    public void Azzera() => secondi.Clear();
}
