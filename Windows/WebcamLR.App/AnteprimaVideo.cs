using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Channels;
using Windows.Media.Core;
using Windows.Media.MediaProperties;
using Windows.Media.Playback;
using WebcamLR.Protocollo;

namespace WebcamLR;

/// <summary>
/// Mostra il video H.264 dell'iPhone nella finestra (funzione 4 su Windows), con il decodificatore
/// hardware del sistema: i fotogrammi Annex B vanno a una MediaStreamSource in tempo reale.
/// </summary>
public sealed class AnteprimaVideo : IDisposable
{
    /// <summary>Oltre questi fotogrammi in attesa il PC è indietro: si salta al prossimo fotogramma chiave.</summary>
    private const int MassimoInAttesa = 10;

    private readonly object blocco = new();
    // Una coda per ogni lettore: una richiesta rimasta in attesa sul lettore vecchio non deve
    // rubare il primo fotogramma chiave a quello nuovo.
    private Channel<FotogrammaVideo>? attesa;
    private MediaStreamSource? sorgente;
    private MediaPlayer? lettore;
    private ulong? primoTimestamp;
    private bool attendiChiave = true;
    private int inAttesa;

    public int Larghezza { get; private set; }
    public int Altezza { get; private set; }

    /// <summary>Crea un nuovo lettore per queste dimensioni; il precedente viene chiuso.</summary>
    public MediaPlayer Avvia(int larghezza, int altezza)
    {
        Ferma();
        Larghezza = larghezza;
        Altezza = altezza;

        var proprieta = VideoEncodingProperties.CreateH264();
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

        var nuovo = new MediaPlayer { RealTimePlayback = true, AutoPlay = true, IsMuted = true };
        nuovo.Source = MediaSource.CreateFromMediaStreamSource(nuova);

        lock (blocco)
        {
            sorgente = nuova;
            lettore = nuovo;
            attesa = coda;
            inAttesa = 0;
            primoTimestamp = null;
            attendiChiave = true;
        }
        return nuovo;
    }

    /// <summary>Chiamata dal thread di rete per ogni fotogramma ricevuto.</summary>
    public void Accoda(FotogrammaVideo fotogramma)
    {
        Channel<FotogrammaVideo>? coda;
        lock (blocco)
        {
            coda = attesa;
            if (sorgente is null || coda is null) return;
            if (attendiChiave)
            {
                if (!fotogramma.Chiave) return;
                attendiChiave = false;
            }
            if (inAttesa >= MassimoInAttesa && !fotogramma.Chiave)
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
            TimeSpan tempo;
            lock (blocco)
            {
                if (origine != sorgente) return;
                inAttesa--;
                primoTimestamp ??= fotogramma.Timestamp;
                tempo = TimeSpan.FromTicks((long)(fotogramma.Timestamp - Math.Min(primoTimestamp.Value, fotogramma.Timestamp)) * 10);
            }
            var campione = MediaStreamSample.CreateFromBuffer(fotogramma.Dati.AsBuffer(), tempo);
            campione.KeyFrame = fotogramma.Chiave;
            evento.Request.Sample = campione;
        }
        catch (ChannelClosedException) { }
        // async void: un errore qui (sorgente già chiusa) chiuderebbe l'app.
        catch (Exception) { }
        finally
        {
            try { rinvio.Complete(); } catch (Exception) { }
        }
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
