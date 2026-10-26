namespace WebcamLR.Ricevitore;

// I pezzi del microfono del telefono su Windows (W2), senza Windows: linea del tempo, anello anti-jitter, posto nel tempo
// di ogni frame, ricampionamento a 48 kHz e livello. La stessa logica del Mac (Mac/Sorgenti/MicrofonoTelefono.swift e
// Mac/Microfono/App/CollegamentoMicrofono.c), provata con i test in WebcamLR.Ricevitore.Test/MicrofonoTest.cs.
// Decodificatore AAC (Media Foundation) e uscita audio (WASAPI) sono in WebcamLR.Microfono, solo per Windows.

/// <summary>
/// La linea del tempo comune, come sul Mac: l'indice di ogni campione è l'orologio del computer (<c>Orologio</c>, in
/// microsecondi) espresso in campioni a 48 kHz. Ogni campione si scrive nel punto in cui va ascoltato.
/// </summary>
public static class LineaAudio
{
    public const int Frequenza = 48_000;

    /// <summary>Microsecondi → indice (48 campioni ogni millisecondo), come anello_indice_da_microsecondi sul Mac.</summary>
    public static ulong Indice(ulong microsecondi) => microsecondi / 1000 * 48 + microsecondi % 1000 * 48 / 1000;
}

/// <summary>
/// Il buffer anti-jitter: un anello di campioni mono a 48 kHz indicizzato dalla linea del tempo comune, come la memoria
/// condivisa del Mac (AnelloMicrofono.h). Chi riceve scrive ogni frame nel suo momento; l'uscita audio legge il tratto
/// di «adesso». Dove non c'è niente esce silenzio, con dissolvenze brevi: niente clic.
/// Un solo scrittore e un solo lettore, su thread diversi: un blocco breve protegge tutto.
/// </summary>
public sealed class AnelloAudio
{
    /// <summary>Potenza di 2: 32768 campioni = 683 ms. Basta per il ritardo massimo (300 ms) più il margine.</summary>
    public const int Capacita = 32_768;
    private const ulong Maschera = Capacita - 1;
    /// <summary>Dissolvenze di chi scrive: 128 campioni = 2,7 ms, niente clic e nessun buco percepibile.</summary>
    public const int Dissolvenza = 128;
    /// <summary>Dissolvenza di chi legge quando l'audio manca o torna, come nel driver del Mac.</summary>
    public const int PassiGuadagno = 64;

    private readonly float[] campioni = new float[Capacita];
    private readonly object blocco = new();
    /// <summary>Indice dopo l'ultimo campione scritto; validi sono [fine − capacità, fine). 0 = vuoto.</summary>
    private ulong fine;
    // Solo chi legge.
    private float guadagno;
    private float ultimoCampione;

    public ulong Fine
    {
        get { lock (blocco) return fine; }
    }

    /// <summary>Svuota tutto: dopo, chi legge trova silenzio finché non arriva un frame nuovo.</summary>
    public void Azzera()
    {
        lock (blocco)
        {
            fine = 0;
            Array.Clear(campioni);
        }
    }

    /// <summary>
    /// Scrive un tratto a partire da <paramref name="posizione"/>. Dopo un buco la coda già scritta scende a zero e il
    /// tratto nuovo entra con una dissolvenza; una sovrapposizione diventa una dissolvenza incrociata.
    /// Porting di microfono_scrivi (CollegamentoMicrofono.c).
    /// </summary>
    public void Scrivi(ulong posizione, ReadOnlySpan<float> tratto)
    {
        var quanti = tratto.Length;
        if (quanti == 0 || quanti > Capacita / 2) return;
        lock (blocco)
        {
            // Molto prima della fine: ormai fuori dall'anello.
            if (posizione + Capacita < fine) return;
            if (posizione > fine)
            {
                var buco = posizione - fine;
                if (fine > 0 && buco < Capacita)
                {
                    var passi = Math.Min(fine, (ulong)Dissolvenza);
                    for (ulong k = 0; k < passi; k++)
                    {
                        var indice = fine - passi + k;
                        campioni[indice & Maschera] *= 1f - (float)(k + 1) / passi;
                    }
                }
                var daAzzerare = Math.Min(buco, (ulong)Capacita);
                for (var i = posizione - daAzzerare; i < posizione; i++) campioni[i & Maschera] = 0f;
                for (var k = 0; k < quanti; k++)
                {
                    var valore = tratto[k];
                    if (k < Dissolvenza) valore *= (float)(k + 1) / Dissolvenza;
                    campioni[(posizione + (ulong)k) & Maschera] = valore;
                }
            }
            else
            {
                for (var k = 0; k < quanti; k++)
                {
                    var indice = posizione + (ulong)k;
                    var valore = tratto[k];
                    if (indice < fine && k < Dissolvenza)
                    {
                        var peso = (float)(k + 1) / Dissolvenza;
                        valore = campioni[indice & Maschera] * (1f - peso) + valore * peso;
                    }
                    campioni[indice & Maschera] = valore;
                }
            }
            // La fine è sempre dopo il tratto nuovo: quello che c'era dopo era della linea del tempo vecchia.
            fine = posizione + (ulong)quanti;
        }
    }

    /// <summary>
    /// Legge <c>uscita.Length</c> campioni a partire da <paramref name="inizio"/> (anche frazionario), avanzando di
    /// <paramref name="passo"/> per campione: il passo leggermente diverso da 1 assorbe la deriva tra l'orologio della
    /// scheda audio e quello del computer. Fra due campioni si interpola. Dove manca l'audio si tiene l'ultimo valore e
    /// lo si porta a zero in <see cref="PassiGuadagno"/> campioni; quando torna, risale. Restituisce quanti erano validi.
    /// </summary>
    public int Leggi(double inizio, double passo, Span<float> uscita)
    {
        var validi = 0;
        var salita = 1f / PassiGuadagno;
        lock (blocco)
        {
            var primo = fine > Capacita ? fine - Capacita : 0;
            for (var k = 0; k < uscita.Length; k++)
            {
                var posizione = inizio + k * passo;
                var valido = false;
                if (posizione >= 0)
                {
                    var intero = (ulong)posizione;
                    if (fine > 0 && intero >= primo && intero < fine)
                    {
                        valido = true;
                        var frazione = (float)(posizione - intero);
                        var a = campioni[intero & Maschera];
                        // L'ultimo campione scritto non ha un successivo: si usa così.
                        var b = intero + 1 < fine ? campioni[(intero + 1) & Maschera] : a;
                        ultimoCampione = a + (b - a) * frazione;
                    }
                }
                if (valido)
                {
                    validi++;
                    if (guadagno < 1f) guadagno = Math.Min(1f, guadagno + salita);
                }
                else if (guadagno > 0f)
                {
                    guadagno = Math.Max(0f, guadagno - salita);
                }
                uscita[k] = ultimoCampione * guadagno;
            }
        }
        return validi;
    }
}

/// <summary>
/// Dove va ogni frame nella linea del tempo: cattura (timestamp del telefono meno la differenza tra gli orologi) più il
/// ritardo, che segue la latenza del video (60–300 ms) così voce e labbra arrivano insieme e fa da riserva contro i
/// ritardi della rete. Porting di MicrofonoTelefono.elabora (Mac). Solo sul thread di chi riceve.
/// </summary>
public sealed class TempiAudio
{
    public const long RitardoMinimo = 60_000;
    public const long RitardoMassimo = 300_000;
    public const long RitardoPredefinito = 70_000;
    /// <summary>Il ritardo cambia solo per differenze maggiori: ogni cambio è un piccolo salto (con dissolvenza).</summary>
    public const long IsteresiRitardo = 20_000;
    /// <summary>Un frame entro 10 ms dal punto atteso si attacca al precedente: niente buchi per gli arrotondamenti.</summary>
    public const ulong Tolleranza = 480;
    /// <summary>
    /// Chi legge arriva al massimo fino a «adesso» (su Windows legge 20 ms indietro, <see cref="MicrofonoTelefono.RitardoLettura"/>):
    /// si scrive almeno 2 ms più avanti, come sul Mac.
    /// </summary>
    public const ulong Margine = 96;
    /// <summary>Correzione fissa del ritardo del decodificatore AAC, in campioni: da misurare con il battito di mani.</summary>
    public const ulong CorrezioneDecodifica = 0;

    private ulong? cursore;

    public long Ritardo { get; private set; } = RitardoPredefinito;

    /// <summary>Si ricomincia da capo: il prossimo frame non si attacca al precedente.</summary>
    public void Azzera() => cursore = null;

    /// <summary>Il ritardo segue la latenza del video, dentro 60–300 ms, e cambia solo oltre i 20 ms di differenza.</summary>
    public void AggiornaRitardo(int? latenzaVideoMs)
    {
        if (latenzaVideoMs is not int ms) return;
        var voluto = Math.Clamp((long)ms * 1000, RitardoMinimo, RitardoMassimo);
        if (Math.Abs(voluto - Ritardo) > IsteresiRitardo) Ritardo = voluto;
    }

    /// <summary>
    /// Il posto del frame (primo campione da scrivere) e quanti campioni iniziali saltare perché già passati;
    /// null se il frame va buttato (tutto in ritardo, o orologi assurdi).
    /// </summary>
    /// <param name="timestamp">Microsecondi del primo campione, sull'orologio del telefono.</param>
    /// <param name="scarto">Orologio del telefono meno orologio del computer (il pong più rapido).</param>
    /// <param name="adessoMicro">L'orologio del computer adesso.</param>
    /// <param name="quanti">I campioni del frame a 48 kHz.</param>
    public (ulong Posizione, int Inizio)? Posiziona(ulong timestamp, long scarto, ulong adessoMicro, int quanti)
    {
        if (quanti <= 0) return null;
        // Valori dalla rete: aritmetica senza trabocchi, un orologio assurdo esce qui.
        var ascolto = unchecked((long)timestamp - scarto + Ritardo);
        if (ascolto <= 0) return null;
        var posizione = LineaAudio.Indice((ulong)ascolto) + CorrezioneDecodifica;
        if (cursore is ulong atteso)
        {
            var distanza = posizione > atteso ? posizione - atteso : atteso - posizione;
            if (distanza <= Tolleranza) posizione = atteso;
        }
        var adesso = LineaAudio.Indice(adessoMicro);
        var inizio = 0;
        if (posizione < adesso + Margine)
        {
            var saltati = adesso + Margine - posizione;
            if (saltati >= (ulong)quanti)
            {
                cursore = null;
                return null;
            }
            inizio = (int)saltati;
            posizione += saltati;
        }
        // Troppo avanti (orologi impazziti): fuori dall'anello.
        if (posizione >= adesso + AnelloAudio.Capacita / 2)
        {
            cursore = null;
            return null;
        }
        cursore = posizione + (ulong)(quanti - inizio);
        return (posizione, inizio);
    }
}

/// <summary>
/// Da qualsiasi frequenza e numero di canali a mono 48 kHz. I telefoni mandano 48 kHz mono (Protocollo.md, «Audio») e
/// allora i campioni passano così; un telefono a 44,1 kHz o stereo si converte qui, con l'interpolazione cubica
/// (Catmull-Rom) e lo stato fra un frame e l'altro, così fra i frame non ci sono scalini.
/// Per scendere da frequenze più alte (96 kHz) non filtra: nessun telefono lo fa, e la voce resta comprensibile.
/// </summary>
public sealed class RicampionatoreAudio
{
    private readonly List<float> lavoro = new();
    /// <summary>Posizione di lettura in campioni d'ingresso, rispetto all'inizio di <see cref="lavoro"/>.</summary>
    private double posizione = 1;

    public RicampionatoreAudio(int frequenza, int canali)
    {
        Frequenza = frequenza > 0 ? frequenza : LineaAudio.Frequenza;
        Canali = Math.Max(1, canali);
        Azzera();
    }

    public int Frequenza { get; }
    public int Canali { get; }
    public bool Diretto => Frequenza == LineaAudio.Frequenza && Canali == 1;

    public void Azzera()
    {
        lavoro.Clear();
        // Due campioni di silenzio prima del primo: servono i vicini per interpolare.
        lavoro.Add(0f);
        lavoro.Add(0f);
        posizione = 1;
    }

    /// <summary>Campioni intercalati (tanti quanti i canali per ogni istante) → mono a 48 kHz, aggiunti a <paramref name="uscita"/>.</summary>
    public void Converti(ReadOnlySpan<float> intercalati, List<float> uscita)
    {
        var istanti = intercalati.Length / Canali;
        if (Diretto)
        {
            for (var i = 0; i < istanti; i++) uscita.Add(intercalati[i]);
            return;
        }
        for (var i = 0; i < istanti; i++)
        {
            var somma = 0f;
            for (var c = 0; c < Canali; c++) somma += intercalati[i * Canali + c];
            lavoro.Add(somma / Canali);
        }
        var passo = (double)Frequenza / LineaAudio.Frequenza;
        while (true)
        {
            var i = (int)posizione;
            if (i + 2 >= lavoro.Count) break;
            var u = (float)(posizione - i);
            float xm1 = lavoro[i - 1], x0 = lavoro[i], x1 = lavoro[i + 1], x2 = lavoro[i + 2];
            uscita.Add(x0 + 0.5f * u * (x1 - xm1 + u * (2f * xm1 - 5f * x0 + 4f * x1 - x2 + u * (3f * (x0 - x1) + x2 - xm1))));
            posizione += passo;
        }
        // Si tengono solo i campioni che servono ancora (dal precedente di quello attuale in poi).
        var togli = Math.Max(0, (int)posizione - 1);
        if (togli > 0)
        {
            lavoro.RemoveRange(0, Math.Min(togli, lavoro.Count));
            posizione -= togli;
        }
    }
}

/// <summary>
/// Il livello per l'indicatore: la media quadratica di un decimo di secondo, da −60 dB (0) a 0 dB (1), come sul Mac.
/// </summary>
public sealed class LivelloAudio
{
    public const ulong Intervallo = 100_000;

    private double sommaQuadrati;
    private int misurati;
    private ulong ultimo;

    /// <summary>Aggiunge dei campioni; ogni decimo di secondo restituisce il livello, altrimenti null.</summary>
    public double? Aggiungi(ReadOnlySpan<float> campioni, ulong adessoMicro)
    {
        foreach (var campione in campioni) sommaQuadrati += (double)campione * campione;
        misurati += campioni.Length;
        if (adessoMicro - Math.Min(ultimo, adessoMicro) < Intervallo || misurati == 0) return null;
        ultimo = adessoMicro;
        var livello = Livello(Math.Sqrt(sommaQuadrati / misurati));
        sommaQuadrati = 0;
        misurati = 0;
        return livello;
    }

    public void Azzera()
    {
        sommaQuadrati = 0;
        misurati = 0;
    }

    /// <summary>Media quadratica → 0…1 (da −60 a 0 dB).</summary>
    public static double Livello(double rms)
    {
        var decibel = 20 * Math.Log10(Math.Max(rms, 0.000_001));
        return Math.Clamp((decibel + 60) / 60, 0, 1);
    }
}

/// <summary>
/// Il decodificatore dei frame audio del telefono. Su Windows è quello AAC di Media Foundation (WebcamLR.Microfono),
/// nei test uno finto.
/// </summary>
public interface IDecodificatoreAudio : IDisposable
{
    /// <summary>La frequenza dei campioni che escono (di solito quella del telefono).</summary>
    int Frequenza { get; }
    int Canali { get; }

    /// <summary>
    /// Un frame compresso → campioni float intercalati in <paramref name="uscita"/>. Restituisce quanti valori ha scritto
    /// (0 se il decodificatore non ha ancora niente da dare), oppure −1 se il frame non si decodifica.
    /// </summary>
    int Decodifica(ReadOnlySpan<byte> frame, Span<float> uscita);
}
