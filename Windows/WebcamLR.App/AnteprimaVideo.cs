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

    private readonly Channel<FotogrammaVideo> attesa = Channel.CreateUnbounded<FotogrammaVideo>(
        new UnboundedChannelOptions { SingleReader = true });
    private readonly object blocco = new();
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
        nuova.SampleRequested += SuRichiesta;

        var nuovo = new MediaPlayer { RealTimePlayback = true, AutoPlay = true, IsMuted = true };
        nuovo.Source = MediaSource.CreateFromMediaStreamSource(nuova);

        lock (blocco)
        {
            sorgente = nuova;
            lettore = nuovo;
            primoTimestamp = null;
            attendiChiave = true;
        }
        return nuovo;
    }

    /// <summary>Chiamata dal thread di rete per ogni fotogramma ricevuto.</summary>
    public void Accoda(FotogrammaVideo fotogramma)
    {
        lock (blocco)
        {
            if (sorgente is null) return;
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
        attesa.Writer.TryWrite(fotogramma);
    }

    private async void SuRichiesta(MediaStreamSource origine, MediaStreamSourceSampleRequestedEventArgs evento)
    {
        var rinvio = evento.Request.GetDeferral();
        try
        {
            var fotogramma = await attesa.Reader.ReadAsync();
            TimeSpan tempo;
            lock (blocco)
            {
                inAttesa--;
                if (origine != sorgente) return;
                primoTimestamp ??= fotogramma.Timestamp;
                tempo = TimeSpan.FromTicks((long)(fotogramma.Timestamp - Math.Min(primoTimestamp.Value, fotogramma.Timestamp)) * 10);
            }
            var campione = MediaStreamSample.CreateFromBuffer(fotogramma.Dati.AsBuffer(), tempo);
            campione.KeyFrame = fotogramma.Chiave;
            evento.Request.Sample = campione;
        }
        catch (ChannelClosedException) { }
        finally
        {
            rinvio.Complete();
        }
    }

    public void Ferma()
    {
        MediaPlayer? vecchio;
        lock (blocco)
        {
            vecchio = lettore;
            lettore = null;
            sorgente = null;
            attendiChiave = true;
        }
        // Svuota i fotogrammi del lettore precedente.
        while (attesa.Reader.TryRead(out _))
        {
            lock (blocco) inAttesa = Math.Max(0, inAttesa - 1);
        }
        vecchio?.Dispose();
    }

    public void Dispose()
    {
        Ferma();
        attesa.Writer.TryComplete();
    }
}
