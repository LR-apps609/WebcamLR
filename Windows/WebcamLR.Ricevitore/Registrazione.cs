using System.Threading.Channels;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

public enum EsitoRegistrazione
{
    Salvata,
    /// <summary>Meno di un secondo (o nessun fotogramma chiave): il file non resta.</summary>
    TroppoBreve,
    /// <summary>Il video è cambiato (misura, obiettivo, codec): il file è chiuso e salvato fino a lì.</summary>
    VideoCambiato,
    /// <summary>Errore di scrittura prima del primo frammento completo: non c'è niente da tenere, il file non resta.</summary>
    Interrotta,
    /// <summary>Disco pieno: il file resta fino all'ultimo frammento completo (la durata è quella salvata).</summary>
    DiscoPieno,
    /// <summary>Un altro errore di scrittura (disco staccato, permessi): il file resta fino all'ultimo frammento completo.</summary>
    ErroreDiScrittura,
}

/// <summary>Come è finita una registrazione.</summary>
public sealed record FineRegistrazione(EsitoRegistrazione Esito, string File, TimeSpan Durata, long Byte)
{
    /// <summary>Vero se il file è sul disco e si può mostrare.</summary>
    public bool FileSalvato => Esito is EsitoRegistrazione.Salvata or EsitoRegistrazione.VideoCambiato
        or EsitoRegistrazione.DiscoPieno or EsitoRegistrazione.ErroreDiScrittura;

    /// <summary>Fermata da un errore, con una parte salvata: la frase dice quanto.</summary>
    public bool SalvataInParte => Esito is EsitoRegistrazione.DiscoPieno or EsitoRegistrazione.ErroreDiScrittura;
}

/// <summary>
/// Una registrazione in corso, vista dalla finestra: quella che copia il video del telefono (<see cref="Registrazione"/>)
/// o quella che ricomprime l'immagine elaborata dal motore effetti (RegistrazioneElaborata nell'app).
/// </summary>
public interface IRegistrazione
{
    string File { get; }

    /// <summary>Byte già nel file (circa, per «Ferma · 00:12 · 8,4 MB»).</summary>
    long Byte { get; }

    TimeSpan Durata { get; }

    /// <summary>La registrazione si è chiusa da sola (video cambiato, disco pieno); dopo, FermaAsync dà lo stesso esito.</summary>
    event Action<FineRegistrazione>? FinitaDaSola;

    /// <summary>Chiude il file e dice com'è andata. Si può chiamare più volte.</summary>
    Task<FineRegistrazione> FermaAsync();
}

/// <summary>
/// Una registrazione in corso (P18): i fotogrammi arrivano dal thread di rete, il file si scrive su un altro thread
/// con lo <see cref="ScrittoreMp4"/>, senza ricomprimere. Se il disco è lento i fotogrammi in eccesso si saltano fino
/// al prossimo fotogramma chiave (mai un fotogramma che dipende da uno saltato), e la rete non aspetta mai il disco.
/// Il file è frammentato (windows.md 1.3 e 1.4): con un errore del disco si ferma all'ultimo frammento completo e resta.
/// </summary>
public sealed class Registrazione : IRegistrazione
{
    /// <summary>Circa 4 secondi a 30 fps: oltre, il disco non tiene il passo.</summary>
    private const int MassimoInAttesa = 120;

    private readonly Stream flusso;
    private readonly ScrittoreMp4 scrittore;
    private readonly Channel<FotogrammaVideo> coda =
        Channel.CreateBounded<FotogrammaVideo>(new BoundedChannelOptions(MassimoInAttesa) { SingleReader = true, FullMode = BoundedChannelFullMode.DropWrite });
    private readonly object blocco = new();
    private readonly Task<FineRegistrazione> lavoro;
    private bool attendiChiave;
    private long byteScritti;
    private long tempoScritto;

    public string File { get; }

    /// <summary>Byte già nel file, per «Ferma · 00:12 · 8,4 MB».</summary>
    public long Byte => Interlocked.Read(ref byteScritti);

    /// <summary>La durata già scritta, dai timestamp del telefono.</summary>
    public TimeSpan Durata => TimeSpan.FromTicks(Interlocked.Read(ref tempoScritto));

    /// <summary>
    /// La registrazione si è chiusa da sola (video cambiato, disco pieno). Arriva sul thread di scrittura, una volta;
    /// dopo, <see cref="FermaAsync"/> restituisce lo stesso esito.
    /// </summary>
    public event Action<FineRegistrazione>? FinitaDaSola;

    private Registrazione(Stream flusso, string file, Codec codec, int larghezza, int altezza, DateTime adesso)
    {
        this.flusso = flusso;
        File = file;
        scrittore = new ScrittoreMp4(flusso, codec, larghezza, altezza, adesso);
        lavoro = Task.Run(ScriviAsync);
    }

    /// <summary>Crea il file (che non deve esistere) e comincia. Un errore del disco arriva come eccezione.</summary>
    /// <remarks>
    /// Senza il buffer di FileStream: lo scrittore manda già pezzi grandi (un frammento alla volta), e dopo un errore
    /// il file si deve poter accorciare senza che il buffer provi di nuovo a scrivere.
    /// </remarks>
    public static Registrazione Avvia(string file, Codec codec, int larghezza, int altezza, DateTime adesso)
    {
        var flusso = new FileStream(file, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read, bufferSize: 0);
        return new Registrazione(flusso, file, codec, larghezza, altezza, adesso);
    }

    /// <summary>Come l'altro Avvia, su un flusso già aperto (per le prove: un disco che si riempie).</summary>
    public static Registrazione Avvia(Stream flusso, string file, Codec codec, int larghezza, int altezza, DateTime adesso) =>
        new(flusso, file, codec, larghezza, altezza, adesso);

    /// <summary>Dal thread di rete, per ogni fotogramma: non aspetta mai.</summary>
    public void Accoda(FotogrammaVideo fotogramma)
    {
        lock (blocco)
        {
            if (attendiChiave)
            {
                if (!fotogramma.Chiave) return;
                attendiChiave = false;
            }
            if (!coda.Writer.TryWrite(fotogramma)) attendiChiave = true;
        }
    }

    /// <summary>Chiude il file e dice com'è andata. Si può chiamare più volte.</summary>
    public async Task<FineRegistrazione> FermaAsync()
    {
        coda.Writer.TryComplete();
        return await lavoro.ConfigureAwait(false);
    }

    private async Task<FineRegistrazione> ScriviAsync()
    {
        try
        {
            await foreach (var fotogramma in coda.Reader.ReadAllAsync().ConfigureAwait(false))
            {
                var esito = scrittore.Aggiungi(fotogramma.Dati, fotogramma.Chiave, fotogramma.Timestamp);
                Interlocked.Exchange(ref byteScritti, scrittore.Byte);
                Interlocked.Exchange(ref tempoScritto, scrittore.Durata.Ticks);
                if (esito != EsitoCampione.FormatoCambiato) continue;
                coda.Writer.TryComplete();
                var fine = Chiudi(EsitoRegistrazione.VideoCambiato);
                Avvisa(fine);
                return fine;
            }
            return Chiudi(EsitoRegistrazione.Salvata);
        }
        catch (Exception errore) when (errore is IOException or UnauthorizedAccessException or ObjectDisposedException)
        {
            coda.Writer.TryComplete();
            var fine = DopoErrore(errore);
            Avvisa(fine);
            return fine;
        }
    }

    /// <summary>Chiude il file; troppo breve, lo cancella.</summary>
    private FineRegistrazione Chiudi(EsitoRegistrazione esito)
    {
        if (scrittore.Campioni == 0 || scrittore.Durata < Riprese.DurataMinima) return Scarta(EsitoRegistrazione.TroppoBreve);
        try
        {
            scrittore.Concludi();
            flusso.Dispose();
            Interlocked.Exchange(ref byteScritti, scrittore.Byte);
        }
        catch (Exception errore) when (errore is IOException or UnauthorizedAccessException or ObjectDisposedException)
        {
            return DopoErrore(errore);
        }
        return new FineRegistrazione(esito, File, scrittore.Durata, scrittore.Byte);
    }

    /// <summary>
    /// Errore di scrittura (windows.md 1.4): il file si ferma all'ultimo frammento completo e resta, con la durata
    /// salvata. Solo se non c'è nemmeno un secondo da tenere si cancella.
    /// </summary>
    private FineRegistrazione DopoErrore(Exception errore)
    {
        var salvata = scrittore.ChiudiDopoErrore();
        if (scrittore.Frammenti == 0 || salvata < Riprese.DurataMinima) return Scarta(EsitoRegistrazione.Interrotta);
        var byteSalvati = scrittore.ByteSalvati;
        try { flusso.Dispose(); } catch (Exception) { }
        Interlocked.Exchange(ref byteScritti, byteSalvati);
        Interlocked.Exchange(ref tempoScritto, salvata.Ticks);
        var esito = Riprese.EDiscoPieno(errore, SpazioLibero()) ? EsitoRegistrazione.DiscoPieno : EsitoRegistrazione.ErroreDiScrittura;
        return new FineRegistrazione(esito, File, salvata, byteSalvati);
    }

    /// <summary>Lo spazio libero sul disco del file, se si riesce a leggerlo.</summary>
    private long? SpazioLibero()
    {
        try
        {
            var radice = Path.GetPathRoot(Path.GetFullPath(File));
            return string.IsNullOrEmpty(radice) ? null : new DriveInfo(radice).AvailableFreeSpace;
        }
        catch (Exception) { return null; }
    }

    /// <summary>Un file non riuscito o troppo breve non resta sul disco (magari già pieno).</summary>
    private FineRegistrazione Scarta(EsitoRegistrazione esito)
    {
        try { flusso.Dispose(); } catch (Exception) { }
        try { System.IO.File.Delete(File); } catch (Exception) { }
        return new FineRegistrazione(esito, File, scrittore.Durata, 0);
    }

    private void Avvisa(FineRegistrazione fine)
    {
        try { FinitaDaSola?.Invoke(fine); } catch (Exception) { }
    }
}
