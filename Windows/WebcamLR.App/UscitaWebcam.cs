using System.Runtime.InteropServices;
using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;
using Windows.Media;
using Windows.Media.Playback;
using WebcamLR.Protocollo;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// Passa il video del telefono alla webcam «WebcamLR» (1.24). Un secondo decodificatore hardware, separato da quello
/// dell'anteprima (che quindi non rallenta), lavora solo mentre un'app usa la webcam: la sorgente dentro Frame Server
/// crea la memoria condivisa e vi segna il suo battito. Ogni fotogramma decodificato la scheda video lo porta alla
/// misura giusta, il processore lo converte in NV12 (con bande nere o tagliato, specchiato solo se richiesto) e lo
/// scrive nella memoria condivisa, tutto fuori dal thread dell'interfaccia. La misura è quella del formato che l'app
/// ha scelto (da 640×360 al 4K, P12), letta a ogni fotogramma: un cambio di formato vale dal fotogramma dopo. La
/// frequenza (30 o 60 fps) la tiene la sorgente, che ripete l'ultimo fotogramma quando serve.
/// </summary>
public sealed class UscitaWebcam : IDisposable
{
    /// <summary>Dopo questo tempo senza app che usano la webcam il decodificatore si ferma.</summary>
    private const int SpegnimentoMs = 5000;

    private readonly object blocco = new();
    private readonly AnteprimaVideo decodificatore = new();
    private readonly Timer controllo;
    private MemoriaCondivisa? memoria;
    private (int Larghezza, int Altezza, Codec Codec)? formato;
    private MediaPlayer? lettore;
    private long ultimoUso;
    private bool inUso;
    private int fpsChiesti;
    private bool chiusa;

    // Il fotogramma in lavorazione: uno alla volta, gli altri si saltano.
    private int copiaInCorso;
    private VideoFrame? superficie;
    private VideoFrame? copiaCpu;

    /// <summary>Vero se la webcam è installata: senza, non si cerca nemmeno la memoria condivisa.</summary>
    public bool Abilitata { get; set; }
    public Inquadratura Inquadratura { get; set; } = Inquadratura.Adatta;
    /// <summary>Specchia anche per chi guarda (di solito no: Zoom e Meet specchiano già l'anteprima di chi parla).</summary>
    public bool Specchia { get; set; }

    /// <summary>Un'app ha aperto o chiuso la webcam. Arriva su un thread qualsiasi.</summary>
    public event Action<bool>? InUsoCambiato;
    /// <summary>Una riga per il registro del collegamento.</summary>
    public event Action<string>? Evento;

    /// <summary>L'app che usa la webcam ha scelto un'altra frequenza (30 o 60 fps). Arriva su un thread qualsiasi.</summary>
    public event Action<int>? FpsChiestiCambiato;

    public bool InUso { get { lock (blocco) return inUso; } }

    /// <summary>I fotogrammi al secondo del formato scelto dall'app che usa la webcam; 0 se nessuna la usa.</summary>
    public int FpsChiesti { get { lock (blocco) return fpsChiesti; } }

    public UscitaWebcam()
    {
        controllo = new Timer(_ => Controlla(), null, 1000, 1000);
    }

    /// <summary>Il formato del video del telefono (dal messaggio «formato»): se la webcam è in uso si riparte con questo.</summary>
    public void Formato(int larghezza, int altezza, Codec codec)
    {
        lock (blocco)
        {
            formato = (larghezza, altezza, codec);
            if (lettore is not null) AvviaDecodifica();
        }
    }

    /// <summary>Dal thread di rete, per ogni fotogramma: costa nulla se la webcam non è in uso.</summary>
    public void Accoda(FotogrammaVideo fotogramma)
    {
        if (Volatile.Read(ref lettore) is null) return;
        decodificatore.Accoda(fotogramma);
    }

    /// <summary>Telefono scollegato: la webcam passa all'immagine di attesa dopo un secondo.</summary>
    public void Ferma()
    {
        lock (blocco)
        {
            formato = null;
            FermaDecodifica();
        }
    }

    private void Controlla()
    {
        bool cambiato, adesso, fpsCambiati;
        int fpsAdesso;
        var descrizione = "";
        try
        {
            lock (blocco)
            {
                if (chiusa) return;
                if (Abilitata && memoria is null)
                {
                    memoria = MemoriaCondivisa.Apri();
                    if (memoria is not null) Evento?.Invoke("Webcam: collegata alla sorgente di Windows");
                }
                var ora = Environment.TickCount64;
                adesso = Abilitata && memoria is not null && memoria.Anello.InUso(ora);
                cambiato = adesso != inUso;
                inUso = adesso;
                if (cambiato && adesso)
                {
                    var (l, a, _) = memoria!.Anello.Richiesta();
                    var fps = memoria.Anello.FpsChiesti;
                    descrizione = fps > 0 ? $" ({l}×{a} a {fps} fps)" : $" ({l}×{a})";
                }
                fpsAdesso = adesso ? memoria!.Anello.FpsChiesti : 0;
                fpsCambiati = fpsAdesso != fpsChiesti;
                fpsChiesti = fpsAdesso;
                if (adesso)
                {
                    ultimoUso = ora;
                    if (lettore is null && formato is not null) AvviaDecodifica();
                }
                else if (lettore is not null && ora - ultimoUso > SpegnimentoMs)
                {
                    FermaDecodifica();
                }
            }
        }
        catch (Exception errore)
        {
            Evento?.Invoke($"Webcam: {errore.Message}");
            return;
        }
        if (cambiato)
        {
            Evento?.Invoke(adesso ? $"Webcam: un'app la sta usando{descrizione}" : "Webcam: nessuna app la usa");
            InUsoCambiato?.Invoke(adesso);
        }
        if (fpsCambiati) FpsChiestiCambiato?.Invoke(fpsAdesso);
    }

    /// <summary>Con il blocco preso.</summary>
    private void AvviaDecodifica()
    {
        if (formato is not { } f) return;
        FermaDecodifica();
        // Il decodificatore parte dal prossimo fotogramma chiave: al massimo 2 secondi di immagine di attesa.
        var nuovo = decodificatore.Avvia(f.Larghezza, f.Altezza, f.Codec, perFotogrammi: true);
        nuovo.VideoFrameAvailable += SuFotogramma;
        nuovo.MediaFailed += (_, evento) => Evento?.Invoke($"Webcam: il video non si decodifica ({evento.ErrorMessage})");
        Volatile.Write(ref lettore, nuovo);
        Evento?.Invoke($"Webcam: video {f.Larghezza}×{f.Altezza} verso le app");
    }

    /// <summary>Con il blocco preso.</summary>
    private void FermaDecodifica()
    {
        var vecchio = Interlocked.Exchange(ref lettore, null);
        if (vecchio is null) return;
        vecchio.VideoFrameAvailable -= SuFotogramma;
        decodificatore.Ferma();
    }

    /// <summary>Sul thread del lettore: copia il fotogramma sulla scheda video, il resto continua altrove.</summary>
    private void SuFotogramma(MediaPlayer origine, object _)
    {
        if (Interlocked.Exchange(ref copiaInCorso, 1) == 1) return;
        var avviata = false;
        try
        {
            var m = memoria;
            if (m is null || origine != Volatile.Read(ref lettore)) return;
            var (richiestaL, richiestaA, _) = m.Anello.Richiesta();
            var camera = FormatiWebcam.Cerca(richiestaL, richiestaA);
            var larghezzaVideo = (int)origine.PlaybackSession.NaturalVideoWidth;
            var altezzaVideo = (int)origine.PlaybackSession.NaturalVideoHeight;
            if (larghezzaVideo <= 0 || altezzaVideo <= 0) return;
            var modo = Inquadratura;
            var (larghezza, altezza) = Inquadrature.DimensioneIntermedia(larghezzaVideo, altezzaVideo, camera.Larghezza, camera.Altezza, modo);

            if (superficie is null || superficie.Direct3DSurface.Description.Width != larghezza
                || superficie.Direct3DSurface.Description.Height != altezza)
            {
                superficie?.Dispose();
                copiaCpu?.Dispose();
                superficie = VideoFrame.CreateAsDirect3D11SurfaceBacked(DirectXPixelFormat.B8G8R8A8UIntNormalized, larghezza, altezza);
                copiaCpu = new VideoFrame(BitmapPixelFormat.Bgra8, larghezza, altezza, BitmapAlphaMode.Ignore);
            }
            // La scheda video scala il fotogramma alla misura intermedia.
            origine.CopyFrameToVideoSurface(superficie.Direct3DSurface);
            avviata = true;
            _ = ConvertiEScriviAsync(m, superficie, copiaCpu!, camera, modo, Specchia);
        }
        catch (Exception) { }
        finally
        {
            if (!avviata) Volatile.Write(ref copiaInCorso, 0);
        }
    }

    private async Task ConvertiEScriviAsync(MemoriaCondivisa m, VideoFrame gpu, VideoFrame cpu, FormatoWebcam camera,
        Inquadratura modo, bool specchia)
    {
        try
        {
            // Dalla scheda video alla memoria, poi la conversione sul pool di thread.
            await gpu.CopyToAsync(cpu);
            await Task.Run(() => Scrivi(m, cpu.SoftwareBitmap, camera, modo, specchia));
        }
        catch (Exception) { }
        finally
        {
            Volatile.Write(ref copiaInCorso, 0);
        }
    }

    private static unsafe void Scrivi(MemoriaCondivisa m, SoftwareBitmap immagine, FormatoWebcam camera, Inquadratura modo, bool specchia)
    {
        using var dati = immagine.LockBuffer(BitmapBufferAccessMode.Read);
        var piano = dati.GetPlaneDescription(0);
        using var riferimento = dati.CreateReference();
        WinRT.CastExtensions.As<IMemoryBufferByteAccess>(riferimento).GetBuffer(out var puntatore, out var capacita);
        var sorgenteBgra = new ReadOnlySpan<byte>(puntatore + piano.StartIndex, (int)capacita - piano.StartIndex);
        var (parteVideo, parteWebcam) = Inquadrature.Calcola(piano.Width, piano.Height, camera.Larghezza, camera.Altezza, modo);
        var anello = m.Anello;
        var spazio = anello.IniziaScrittura(camera.Larghezza, camera.Altezza);
        ConversioneVideo.BgraInNv12(sorgenteBgra, piano.Width, piano.Height, piano.Stride, parteVideo,
            spazio, camera.Larghezza, camera.Altezza, parteWebcam, specchia);
        anello.ConcludiScrittura(Environment.TickCount64);
        m.Segnala();
    }

    public void Dispose()
    {
        lock (blocco)
        {
            chiusa = true;
            FermaDecodifica();
        }
        controllo.Dispose();
        decodificatore.Dispose();
        // La memoria resta finché il processo non esce: una conversione in corso la può ancora usare.
    }

    /// <summary>L'accesso ai byte di un IMemoryBufferReference (windows.foundation.h).</summary>
    [ComImport, Guid("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private unsafe interface IMemoryBufferByteAccess
    {
        void GetBuffer(out byte* buffer, out uint capacity);
    }
}
