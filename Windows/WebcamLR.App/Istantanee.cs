using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;
using Windows.Media;
using Windows.Media.Playback;
using WebcamLR.Protocollo;

namespace WebcamLR;

/// <summary>
/// L'immagine attuale del telefono per «Foto» e «Copia il fotogramma» (P18). L'anteprima disegna il video direttamente
/// nella finestra e non lascia leggere i fotogrammi: come sul Mac (decodifica parallela in Schermo.swift) c'è un secondo
/// decodificatore hardware, acceso mentre il telefono manda video, che dà ogni fotogramma con VideoFrameAvailable.
/// Di solito non fa nulla; solo quando si chiede una foto il fotogramma successivo viene copiato dalla scheda video
/// (al massimo 33 ms dopo a 30 fps). Così la foto è immediata, senza aspettare il prossimo fotogramma chiave.
/// </summary>
public sealed class Istantanee : IDisposable
{
    private readonly object blocco = new();
    private readonly AnteprimaVideo decodificatore = new();
    private MediaPlayer? lettore;
    private TaskCompletionSource<SoftwareBitmap?>? richiesta;

    /// <summary>Dal thread di rete, con il messaggio «formato»: il decodificatore riparte con il video nuovo.</summary>
    public void Formato(int larghezza, int altezza, Codec codec)
    {
        lock (blocco)
        {
            FermaInterno();
            var nuovo = decodificatore.Avvia(larghezza, altezza, codec, perFotogrammi: true);
            nuovo.VideoFrameAvailable += SuFotogramma;
            Volatile.Write(ref lettore, nuovo);
        }
    }

    /// <summary>Dal thread di rete, per ogni fotogramma.</summary>
    public void Accoda(FotogrammaVideo fotogramma)
    {
        if (Volatile.Read(ref lettore) is null) return;
        decodificatore.Accoda(fotogramma);
    }

    /// <summary>Telefono scollegato.</summary>
    public void Ferma()
    {
        lock (blocco) FermaInterno();
    }

    /// <summary>L'immagine attuale (BGRA), oppure null se il video non c'è o non arriva entro <paramref name="attesa"/>.</summary>
    public async Task<SoftwareBitmap?> PrendiAsync(TimeSpan attesa)
    {
        TaskCompletionSource<SoftwareBitmap?> attuale;
        lock (blocco)
        {
            if (lettore is null) return null;
            // Due richieste insieme (Foto e Copia) aspettano lo stesso fotogramma.
            richiesta ??= new TaskCompletionSource<SoftwareBitmap?>(TaskCreationOptions.RunContinuationsAsynchronously);
            attuale = richiesta;
        }
        if (await Task.WhenAny(attuale.Task, Task.Delay(attesa)) != attuale.Task)
        {
            lock (blocco)
            {
                if (richiesta == attuale) richiesta = null;
            }
            attuale.TrySetResult(null);
        }
        return await attuale.Task;
    }

    /// <summary>Con il blocco preso.</summary>
    private void FermaInterno()
    {
        var vecchio = Interlocked.Exchange(ref lettore, null);
        richiesta?.TrySetResult(null);
        richiesta = null;
        if (vecchio is null) return;
        vecchio.VideoFrameAvailable -= SuFotogramma;
        decodificatore.Ferma();
    }

    /// <summary>Sul thread del lettore: senza richieste non fa nulla.</summary>
    private void SuFotogramma(MediaPlayer origine, object _)
    {
        TaskCompletionSource<SoftwareBitmap?> attuale;
        lock (blocco)
        {
            if (richiesta is null || origine != lettore) return;
            attuale = richiesta;
            richiesta = null;
        }
        _ = CopiaAsync(origine, attuale);
    }

    /// <summary>La copia sulla scheda video avviene qui, dentro VideoFrameAvailable; il passaggio in memoria dopo.</summary>
    private static async Task CopiaAsync(MediaPlayer origine, TaskCompletionSource<SoftwareBitmap?> attuale)
    {
        try
        {
            var larghezza = (int)origine.PlaybackSession.NaturalVideoWidth;
            var altezza = (int)origine.PlaybackSession.NaturalVideoHeight;
            if (larghezza <= 0 || altezza <= 0)
            {
                attuale.TrySetResult(null);
                return;
            }
            using var superficie = VideoFrame.CreateAsDirect3D11SurfaceBacked(DirectXPixelFormat.B8G8R8A8UIntNormalized, larghezza, altezza);
            origine.CopyFrameToVideoSurface(superficie.Direct3DSurface);
            var immagine = await SoftwareBitmap.CreateCopyFromSurfaceAsync(superficie.Direct3DSurface, BitmapAlphaMode.Ignore);
            attuale.TrySetResult(immagine);
        }
        catch (Exception)
        {
            attuale.TrySetResult(null);
        }
    }

    public void Dispose()
    {
        Ferma();
        decodificatore.Dispose();
    }
}
