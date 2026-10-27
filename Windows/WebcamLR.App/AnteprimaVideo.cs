using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Channels;
using Windows.Media.Core;
using Windows.Media.MediaProperties;
using Windows.Media.Playback;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Mostra il video H.264 del telefono nella finestra (funzione 4 su Windows), con il decodificatore
/// hardware del sistema: i fotogrammi Annex B vanno a una MediaStreamSource in tempo reale.
/// Ritardo «da vetro a uscita» (Protocollo.md, «Latenza»): per ogni campione si tiene quale fotogramma del telefono è
/// (<see cref="TracciaFotogrammi"/>); dalla posizione del lettore si sa quale si vede adesso e da quanto è stato catturato
/// (<see cref="Ritardo"/>). Se il lettore tiene i fotogrammi più del necessario (il primo era arrivato tardi), la linea del
/// tempo si accorcia piano piano (<see cref="RecuperoRitardo"/>).
/// </summary>
public sealed class AnteprimaVideo : IDisposable
{
    /// <summary>
    /// Oltre questi fotogrammi in attesa il PC è indietro: si salta al prossimo fotogramma chiave. Erano 10 (un terzo di
    /// secondo a 30 fps); 6 bastano contro i salti della rete e tengono il ritardo sotto i 200 ms anche nel caso peggiore.
    /// </summary>
    private const int MassimoInAttesa = 6;

    private readonly object blocco = new();
    // Una coda per ogni lettore: una richiesta rimasta in attesa sul lettore vecchio non deve
    // rubare il primo fotogramma chiave a quello nuovo.
    private Channel<FotogrammaVideo>? attesa;
    private MediaStreamSource? sorgente;
    private MediaPlayer? lettore;
    /// <summary>Tempi dei campioni dal primo fotogramma; dopo una pausa del telefono la linea del tempo continua senza buchi.</summary>
    private readonly TempiVideo tempi = new();
    private bool attendiChiave = true;
    private int inAttesa;
    // Ritardo da vetro a uscita e recupero dell'attesa (sotto blocco, tranne le classi che hanno il loro).
    private readonly TracciaFotogrammi traccia = new();
    private readonly RecuperoRitardo recupero = new();
    private long ultimoTempo = -1;
    private long? scarto;

    /// <summary>Da vetro a ciò che il lettore mostra adesso (mediana di un secondo), da qualsiasi thread.</summary>
    public MisuraRitardo Ritardo { get; } = new();

    /// <summary>Quanto la linea del tempo del lettore è stata accorciata (µs), per il registro.</summary>
    public long Recuperato
    {
        get { lock (blocco) return recupero.Spostamento; }
    }

    /// <summary>
    /// Il fotogramma del telefono che il lettore <paramref name="lettore"/> mostra adesso (timestamp del telefono), dalla
    /// sua posizione; null se non si sa. Per la webcam (<see cref="UscitaWebcam"/>), da qualsiasi thread.
    /// </summary>
    public ulong? Mostrato(MediaPlayer lettore)
    {
        try { return traccia.Mostrato(lettore.PlaybackSession.Position.Ticks / 10); }
        catch (Exception) { return null; }
    }

    /// <summary>L'ultima differenza tra gli orologi data con <see cref="Accoda"/>.</summary>
    public long? Scarto
    {
        get { lock (blocco) return scarto; }
    }

    /// <summary>
    /// Il primo fotogramma chiave del lettore nuovo è passato al decodificatore e il lettore è in riproduzione:
    /// l'immagine è a schermo (1.11, misura dell'avvio). Una volta per lettore, su un thread di sistema.
    /// </summary>
    public event Action? PrimaImmagine;

    // Per PrimaImmagine, del lettore attuale (sotto blocco).
    private bool campioneDato;
    private bool inRiproduzione;
    private bool primaAvvisata;

    public int Larghezza { get; private set; }
    public int Altezza { get; private set; }

    /// <summary>Crea un nuovo lettore per queste dimensioni; il precedente viene chiuso.</summary>
    /// <remarks>HEVC richiede l'estensione «Video HEVC» di Microsoft Store; senza, Windows non mostra nulla.</remarks>
    /// <param name="perFotogrammi">Per la webcam (1.24): il lettore non disegna in una finestra ma dà ogni fotogramma
    /// decodificato con l'evento VideoFrameAvailable. Va deciso prima di dargli la sorgente.</param>
    public MediaPlayer Avvia(int larghezza, int altezza, Codec codec = Codec.H264, bool perFotogrammi = false)
    {
        Ferma();
        Larghezza = larghezza;
        Altezza = altezza;

        var proprieta = codec == Codec.Hevc ? VideoEncodingProperties.CreateHevc() : VideoEncodingProperties.CreateH264();
        proprieta.Width = (uint)larghezza;
        proprieta.Height = (uint)altezza;
        var nuova = new MediaStreamSource(new VideoStreamDescriptor(proprieta))
        {
            BufferTime = TimeSpan.Zero,
            IsLive = true,
            CanSeek = false,
        };
        var coda = Channel.CreateUnbounded<FotogrammaVideo>(new UnboundedChannelOptions { SingleReader = true });
        nuova.SampleRequested += (origine, evento) => SuRichiesta(origine, evento, coda);

        var nuovo = new MediaPlayer { RealTimePlayback = true, AutoPlay = true, IsMuted = true, IsVideoFrameServerEnabled = perFotogrammi };
        nuovo.PlaybackSession.PlaybackStateChanged += (sessione, _) =>
        {
            if (sessione.PlaybackState == MediaPlaybackState.Playing) Segna(nuova, riproduzione: true);
        };
        nuovo.Source = MediaSource.CreateFromMediaStreamSource(nuova);

        lock (blocco)
        {
            sorgente = nuova;
            lettore = nuovo;
            attesa = coda;
            inAttesa = 0;
            tempi.Azzera();
            traccia.Azzera();
            recupero.Azzera();
            ultimoTempo = -1;
            attendiChiave = true;
            campioneDato = false;
            inRiproduzione = false;
            primaAvvisata = false;
        }
        return nuovo;
    }

    /// <summary>
    /// Chiamata dal thread di rete per ogni fotogramma ricevuto. <paramref name="scartoOrologi"/>: la differenza tra gli
    /// orologi della sessione (null finché non c'è un pong), per il ritardo da vetro a uscita.
    /// </summary>
    public void Accoda(FotogrammaVideo fotogramma, long? scartoOrologi = null)
    {
        Channel<FotogrammaVideo>? coda;
        lock (blocco)
        {
            if (scartoOrologi is not null) scarto = scartoOrologi;
            coda = attesa;
            if (sorgente is null || coda is null) return;
            if (attendiChiave)
            {
                if (!fotogramma.Chiave) return;
                attendiChiave = false;
            }
            // Oltre il triplo si scartano anche i fotogrammi chiave: se il lettore non chiede più campioni
            // (decodificatore HEVC mancante, MediaFailed) la coda crescerebbe di un fotogramma chiave alla volta, senza fine.
            if (inAttesa >= MassimoInAttesa && (!fotogramma.Chiave || inAttesa >= MassimoInAttesa * 3))
            {
                attendiChiave = true;
                return;
            }
            inAttesa++;
        }
        coda.Writer.TryWrite(fotogramma);
    }

    private async void SuRichiesta(MediaStreamSource origine, MediaStreamSourceSampleRequestedEventArgs evento,
        Channel<FotogrammaVideo> coda)
    {
        var rinvio = evento.Request.GetDeferral();
        try
        {
            var fotogramma = await coda.Reader.ReadAsync();
            MediaPlayer? suo;
            lock (blocco) suo = origine == sorgente ? lettore : null;
            // La posizione del lettore adesso: il tempo del fotogramma che si vede.
            long? posizione = null;
            try { if (suo is not null) posizione = suo.PlaybackSession.Position.Ticks / 10; }
            catch (Exception) { }
            TimeSpan tempo;
            long? scartoAdesso;
            lock (blocco)
            {
                if (origine != sorgente) return;
                inAttesa--;
                var micro = tempi.Microsecondi(fotogramma.Timestamp);
                if (posizione is long p && p > 0)
                {
                    // Il campione aspetterà (micro − p) prima di vedersi: se è sempre troppo, la linea del tempo si accorcia.
                    var corrente = micro - recupero.Spostamento;
                    recupero.Aggiungi(corrente - p);
                }
                if (recupero.Spostamento > 0) micro = Math.Max(micro - recupero.Spostamento, ultimoTempo + 1);
                ultimoTempo = micro;
                traccia.Aggiungi(micro, fotogramma.Timestamp);
                tempo = TimeSpan.FromTicks(micro * 10);
                scartoAdesso = scarto;
            }
            // Da vetro all'anteprima: il fotogramma che il lettore mostra adesso, da quando è stato catturato.
            if (posizione is long pos && scartoAdesso is long differenza && traccia.Mostrato(pos) is ulong mostrato)
            {
                var adesso = Orologio.Adesso();
                if (RitardoVetro.Ms(mostrato, differenza, adesso) is int ms) Ritardo.Aggiungi(ms, adesso);
            }
            var campione = MediaStreamSample.CreateFromBuffer(fotogramma.Dati.AsBuffer(), tempo);
            campione.KeyFrame = fotogramma.Chiave;
            evento.Request.Sample = campione;
            if (fotogramma.Chiave) Segna(origine, campione: true);
        }
        catch (ChannelClosedException) { }
        // async void: un errore qui (sorgente già chiusa) chiuderebbe l'app.
        catch (Exception) { }
        finally
        {
            try { rinvio.Complete(); } catch (Exception) { }
        }
    }

    /// <summary>Una delle due condizioni della prima immagine; quando ci sono tutte e due, l'avviso (una volta).</summary>
    private void Segna(MediaStreamSource origine, bool campione = false, bool riproduzione = false)
    {
        lock (blocco)
        {
            if (origine != sorgente || primaAvvisata) return;
            campioneDato |= campione;
            inRiproduzione |= riproduzione;
            if (!campioneDato || !inRiproduzione) return;
            primaAvvisata = true;
        }
        try { PrimaImmagine?.Invoke(); } catch (Exception) { }
    }

    public void Ferma()
    {
        MediaPlayer? vecchio;
        Channel<FotogrammaVideo>? vecchia;
        lock (blocco)
        {
            vecchio = lettore;
            vecchia = attesa;
            lettore = null;
            sorgente = null;
            attesa = null;
            inAttesa = 0;
            attendiChiave = true;
        }
        // Chiude la coda del lettore precedente: la sua richiesta in attesa finisce senza campione.
        vecchia?.Writer.TryComplete();
        vecchio?.Dispose();
    }

    public void Dispose()
    {
        Ferma();
    }
}
