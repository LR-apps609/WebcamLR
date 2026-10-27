using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Il microfono del telefono su Windows (W2), senza interfaccia e senza API di Windows: decodifica i pacchetti di tipo 3
/// con il decodificatore che gli si dà, li porta a 48 kHz mono, li mette nel loro momento nell'anello anti-jitter e misura
/// il livello. L'uscita audio (WASAPI, in WebcamLR.Microfono) chiama <see cref="Leggi"/> dal suo thread.
/// La sincronia con il video è quella del Mac (Documenti/Microfono Mac.md, «Sincronia con il video»).
/// </summary>
public sealed class MicrofonoTelefono : IDisposable
{
    /// <summary>
    /// Chi legge sta 20 ms dietro «adesso»: la scheda audio chiede un periodo (circa 10 ms) alla volta, e così ogni
    /// campione richiesto è già passato per la linea del tempo, cioè chi scrive ha già potuto metterlo al suo posto
    /// (come il driver del Mac, che legge l'istante del suo ciclo). La voce si sente 20 ms (più il buffer della scheda)
    /// dopo il momento scelto: meno di un fotogramma.
    /// </summary>
    public const double RitardoLettura = 960;
    /// <summary>Oltre 50 ms di distanza fra chi legge e «adesso» si salta: dopo una pausa della scheda audio o al via.</summary>
    public const double SaltoLettura = 2_400;
    /// <summary>Al massimo ±0,5% di velocità per seguire la deriva della scheda audio: non si sente sulla voce.</summary>
    public const double CorrezioneMassima = 0.005;
    /// <summary>Quanto si corregge per ogni campione di distanza (10 ms di distanza → 0,5%).</summary>
    private const double Guadagno = CorrezioneMassima / 480;
    /// <summary>La distanza si misura a ogni lettura, con il rumore dei risvegli del thread: si media.</summary>
    private const double Media = 0.05;
    /// <summary>Spazio per un frame decodificato (fino a 2048 campioni stereo, anche ad alte frequenze).</summary>
    private const int SpazioDecodifica = 16_384;

    private readonly Func<FormatoAudio, IDecodificatoreAudio?> creaDecodificatore;
    private readonly Func<ulong> orologio;
    private readonly object blocco = new();
    private readonly AnelloAudio anello = new();
    /// <summary>Il ritardo tiene conto dei 20 ms per cui chi legge sta dietro «adesso» (<see cref="RitardoLettura"/>).</summary>
    private readonly TempiAudio tempi = new(compensazione: (long)(RitardoLettura * 1_000_000 / LineaAudio.Frequenza));
    private readonly LivelloAudio livello = new();
    private readonly float[] decodificati = new float[SpazioDecodifica];
    private readonly List<float> convertiti = new(4096);

    // Sotto blocco (chi riceve).
    private FormatoAudio? formato;
    private IDecodificatoreAudio? decodificatore;
    private RicampionatoreAudio? ricampionatore;
    private bool decodificatoreFallito;
    private ulong ultimoAudio;
    private bool fermo = true;

    // Solo chi legge (il thread dell'uscita audio).
    private double? cursore;
    private double distanzaMedia;

    /// <param name="creaDecodificatore">Un decodificatore per il formato del telefono; null se non si può.</param>
    /// <param name="orologio">L'orologio del computer in microsecondi (Orologio.Adesso); diverso solo nei test.</param>
    public MicrofonoTelefono(Func<FormatoAudio, IDecodificatoreAudio?> creaDecodificatore, Func<ulong>? orologio = null)
    {
        this.creaDecodificatore = creaDecodificatore;
        this.orologio = orologio ?? Orologio.Adesso;
    }

    /// <summary>Il livello da 0 a 1, una decina di volte al secondo, sul thread di chi riceve.</summary>
    public event Action<double>? Livello;

    /// <summary>Il decodificatore non si è potuto creare o non decodifica: una volta per formato, per il registro.</summary>
    public event Action<string>? Errore;

    /// <summary>È arrivato audio decodificato nell'ultimo mezzo secondo.</summary>
    public bool AudioInArrivo
    {
        get
        {
            lock (blocco) return !fermo && orologio() - Math.Min(ultimoAudio, orologio()) < 500_000;
        }
    }

    /// <summary>Il ritardo attuale fra la cattura sul telefono e l'ascolto, in microsecondi.</summary>
    public long Ritardo
    {
        get { lock (blocco) return tempi.Ritardo; }
    }

    /// <summary>Distanza media (campioni) fra chi legge e il suo punto (adesso − 20 ms): per i test e la diagnosi.</summary>
    public double DistanzaLettura => distanzaMedia;

    /// <summary>Il <c>formato-audio</c> del telefono: il decodificatore si rifà al prossimo frame se è cambiato.</summary>
    public void Imposta(FormatoAudio nuovo)
    {
        lock (blocco)
        {
            if (nuovo == formato && (decodificatore is not null || decodificatoreFallito)) return;
            formato = nuovo;
            ChiudiDecodificatore();
            tempi.Azzera();
        }
    }

    /// <summary>
    /// Un pacchetto di tipo 3 dalla sessione. <paramref name="scarto"/>: la differenza tra gli orologi del video
    /// (null finché non c'è un pong); <paramref name="latenzaVideoMs"/>: il ritardo «da vetro a uscita» del video
    /// (o, finché non c'è, la latenza del video), da cui il ritardo stabile dell'audio. L'audio non suona all'arrivo ma al
    /// suo momento: un fotogramma chiave grande che lo fa arrivare tardi non sposta niente.
    /// </summary>
    public void Ricevi(PacchettoAudio pacchetto, long? scarto, int? latenzaVideoMs)
    {
        if (pacchetto.Dati.Length == 0) return;
        double? daMandare = null;
        lock (blocco)
        {
            fermo = false;
            if (Decodificatore() is not { } attuale || ricampionatore is null) return;
            int quanti;
            try { quanti = attuale.Decodifica(pacchetto.Dati, decodificati); }
            catch (Exception) { quanti = -1; }
            if (quanti < 0)
            {
                // Un frame rovinato: si ricomincia con un decodificatore nuovo al prossimo.
                ChiudiDecodificatore();
                tempi.Azzera();
                return;
            }
            if (quanti == 0) return;
            convertiti.Clear();
            ricampionatore.Converti(decodificati.AsSpan(0, Math.Min(quanti, decodificati.Length)), convertiti);
            if (convertiti.Count == 0) return;
            var adesso = orologio();
            ultimoAudio = adesso;
            var campioni = System.Runtime.InteropServices.CollectionsMarshal.AsSpan(convertiti);
            daMandare = livello.Aggiungi(campioni, adesso);

            // Senza differenza di orologi non si sa quando è stato catturato: solo il livello.
            if (scarto is long differenza)
            {
                tempi.AggiornaRitardo(latenzaVideoMs, adesso);
                // Mai più di mezzo anello in un colpo (un frame è circa 1024 campioni).
                var tratto = campioni[..Math.Min(campioni.Length, AnelloAudio.Capacita / 2)];
                if (tempi.Posiziona(pacchetto.Timestamp, differenza, adesso, tratto.Length) is var (posizione, inizio))
                    anello.Scrivi(posizione, tratto[inizio..]);
            }
        }
        if (daMandare is double valore) Livello?.Invoke(valore);
    }

    /// <summary>Microfono spento, telefono cambiato o sessione chiusa: si ricomincia da capo, in silenzio.</summary>
    public void Ferma()
    {
        lock (blocco)
        {
            fermo = true;
            ChiudiDecodificatore();
            tempi.Azzera();
            livello.Azzera();
            anello.Azzera();
        }
        Livello?.Invoke(0);
    }

    /// <summary>
    /// Dal thread dell'uscita audio: i prossimi campioni da suonare (mono, 48 kHz), quelli di «adesso» sulla linea del
    /// tempo (20 ms fa, <see cref="RitardoLettura"/>). Il passo di lettura si regola appena (al massimo ±0,5%) per seguire la scheda audio, il cui orologio non è
    /// mai esattamente quello del computer; oltre 50 ms di distanza si salta. Restituisce quanti campioni erano audio.
    /// </summary>
    public int Leggi(Span<float> uscita)
    {
        if (uscita.IsEmpty) return 0;
        var adesso = (double)LineaAudio.Indice(orologio()) - RitardoLettura;
        if (cursore is not double attuale || Math.Abs(attuale - adesso) > SaltoLettura)
        {
            attuale = adesso;
            distanzaMedia = 0;
        }
        distanzaMedia += Media * (attuale - adesso - distanzaMedia);
        var passo = 1 - Math.Clamp(Guadagno * distanzaMedia, -CorrezioneMassima, CorrezioneMassima);
        var validi = anello.Leggi(attuale, passo, uscita);
        cursore = attuale + passo * uscita.Length;
        return validi;
    }

    /// <summary>L'uscita audio si è fermata o è ripartita: alla prossima lettura si riparte da «adesso».</summary>
    public void RiprendiLettura()
    {
        cursore = null;
        distanzaMedia = 0;
    }

    public void Dispose()
    {
        lock (blocco) ChiudiDecodificatore();
    }

    private IDecodificatoreAudio? Decodificatore()
    {
        if (decodificatore is not null) return decodificatore;
        if (decodificatoreFallito || formato is not { } attuale) return null;
        try { decodificatore = creaDecodificatore(attuale); }
        catch (Exception) { decodificatore = null; }
        if (decodificatore is null)
        {
            decodificatoreFallito = true;
            Errore?.Invoke(TestiRicevitore.T("Microfono_NonDecodificabile", attuale.Codec, attuale.Frequenza, attuale.Canali));
            return null;
        }
        ricampionatore = new RicampionatoreAudio(decodificatore.Frequenza, decodificatore.Canali);
        return decodificatore;
    }

    private void ChiudiDecodificatore()
    {
        try { decodificatore?.Dispose(); }
        catch (Exception) { }
        decodificatore = null;
        ricampionatore = null;
        decodificatoreFallito = false;
    }
}
