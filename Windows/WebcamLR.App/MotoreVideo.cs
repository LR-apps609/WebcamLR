using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;
using Windows.Media;
using Windows.Media.Playback;
using WebcamLR.Effetti;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Il punto unico da cui le uscite prendono l'immagine del telefono nella webcam, con gli effetti sul computer
/// (Documenti/Effetti su Windows.md): un decodificatore hardware in modalità «frame server» (come quello della webcam),
/// ogni fotogramma copiato dalla scheda video alla memoria e dato al <see cref="MotoreEffetti"/>. L'immagine elaborata va
/// all'anteprima e alla finestra mini (MainWindow.MotoreEffetti.cs), alla webcam virtuale (<see cref="UscitaWebcam.Scrivi"/>),
/// alle foto (<see cref="PrendiAsync"/>) e alla registrazione (<see cref="RegistrazioneElaborata"/>).
/// Con gli effetti spenti l'anteprima resta quella hardware di sempre (MediaPlayerElement) e le altre uscite ricevono il
/// fotogramma com'è, solo se servono (webcam in uso, registrazione, foto chiesta): altrimenti qui non si copia niente.
/// Prima versione sul processore (la resa del motore): la scheda video scala e decodifica, il resto lo fa la CPU.
/// </summary>
public sealed class MotoreVideo : IDisposable
{
    private readonly object blocco = new();
    private readonly AnteprimaVideo decodificatore = new();
    private readonly MotoreEffetti motore;
    private MediaPlayer? lettore;
    private bool abilitato;
    private bool chiuso;

    // Il fotogramma in copia: uno alla volta, gli altri si saltano (il motore ne tiene già uno in attesa).
    private int copiaInCorso;
    private VideoFrame? superficie;
    private VideoFrame? copiaCpu;
    private TaskCompletionSource<SoftwareBitmap?>? richiestaFoto;
    /// <summary>Cambia a ogni Formato e Ferma: un fotogramma di prima non arriva più alle uscite.</summary>
    private int generazione;

    /// <summary>Le scelte e le immagini del motore: le scrive la finestra (AggiornaMotore).</summary>
    public StatoEffettiComputer Stato { get; } = new();

    /// <summary>Vero se, oltre agli effetti, qualcuno vuole i fotogrammi anche com'è (webcam in uso, registrazione).</summary>
    public Func<bool>? ServonoFotogrammi { get; set; }

    /// <summary>
    /// Un fotogramma per le uscite: l'immagine e se è elaborata dal motore. Arriva su un thread del motore o del pool;
    /// chi lo riceve lo usa subito o lo copia (l'immagine torna in giro appena l'evento finisce, o dopo
    /// <see cref="MotoreEffetti.ImmaginiInUscita"/> immagini se elaborata).
    /// </summary>
    public event Action<ImmagineBgra, bool>? Fotogramma;

    /// <summary>Da vetro all'anteprima elaborata (lo misura la finestra quando la mostra), mediana di un secondo.</summary>
    public MisuraRitardo RitardoAnteprima { get; } = new();

    /// <summary>Una riga per il registro (decodifica che non parte).</summary>
    public event Action<string>? Evento;

    public MotoreVideo()
    {
        motore = new MotoreEffetti(Stato, livello => FonteRitaglio.PerLivello(livello));
    }

    /// <summary>
    /// Vero se le uscite devono prendere l'immagine da qui (effetti accesi o in dissolvenza): allora la webcam, le foto e
    /// l'anteprima non mostrano mai il fotogramma non elaborato.
    /// </summary>
    public bool Attivo => motore.Attivo;

    /// <summary>La differenza tra gli orologi dell'ultimo fotogramma, per il ritardo da vetro a uscita.</summary>
    public long? Scarto => decodificatore.Scarto;

    public MotoreEffetti.Misure PrendiMisure() => motore.PrendiMisure();

    public IReadOnlyList<MotoreEffetti.Nota> PrendiNote() => motore.PrendiNote();

    /// <summary>Il motore lavora solo con un telefono nella webcam.</summary>
    public void Abilita(bool acceso)
    {
        lock (blocco) abilitato = acceso;
        motore.Abilita(acceso);
    }

    /// <summary>Apre il modello in anticipo (lo sfondo è appena stato acceso): il primo fotogramma non aspetta.</summary>
    public void Prepara() => motore.Prepara();

    /// <summary>Il formato del video del telefono nella webcam (messaggio «formato»): il decodificatore riparte.</summary>
    public void Formato(int larghezza, int altezza, Codec codec)
    {
        lock (blocco)
        {
            if (chiuso) return;
            generazione++;
            FermaDecodifica();
            motore.Azzera();
            var nuovo = decodificatore.Avvia(larghezza, altezza, codec, perFotogrammi: true);
            nuovo.VideoFrameAvailable += SuFotogramma;
            nuovo.MediaFailed += (_, evento) => Evento?.Invoke(Testi.T("Effetti_NonSiDecodifica", evento.ErrorMessage));
            Volatile.Write(ref lettore, nuovo);
        }
    }

    /// <summary>Dal thread di rete, per ogni fotogramma del telefono nella webcam.</summary>
    public void Accoda(FotogrammaVideo fotogramma, long? scarto)
    {
        if (Volatile.Read(ref lettore) is null) return;
        decodificatore.Accoda(fotogramma, scarto);
    }

    /// <summary>
    /// Telefono scollegato o cambiato: il decodificatore si ferma e i fotogrammi ancora nel motore non arrivano più alle
    /// uscite (non rimettono un'immagine vecchia sopra la schermata di attesa).
    /// </summary>
    public void Ferma()
    {
        lock (blocco)
        {
            generazione++;
            FermaDecodifica();
            richiestaFoto?.TrySetResult(null);
            richiestaFoto = null;
        }
        motore.Azzera();
        RitardoAnteprima.Azzera();
    }

    /// <summary>Con il blocco preso.</summary>
    private void FermaDecodifica()
    {
        var vecchio = Interlocked.Exchange(ref lettore, null);
        if (vecchio is null) return;
        vecchio.VideoFrameAvailable -= SuFotogramma;
        decodificatore.Ferma();
    }

    /// <summary>
    /// L'immagine che le uscite mostrano adesso (elaborata se gli effetti sono accesi), per «Foto» e «Copia il fotogramma»:
    /// il prossimo fotogramma, oppure null se non arriva entro <paramref name="attesa"/>.
    /// </summary>
    public async Task<SoftwareBitmap?> PrendiAsync(TimeSpan attesa)
    {
        TaskCompletionSource<SoftwareBitmap?> attuale;
        lock (blocco)
        {
            if (lettore is null) return null;
            richiestaFoto ??= new TaskCompletionSource<SoftwareBitmap?>(TaskCreationOptions.RunContinuationsAsynchronously);
            attuale = richiestaFoto;
        }
        if (await Task.WhenAny(attuale.Task, Task.Delay(attesa)) != attuale.Task)
        {
            lock (blocco)
            {
                if (richiestaFoto == attuale) richiestaFoto = null;
            }
            attuale.TrySetResult(null);
        }
        return await attuale.Task;
    }

    /// <summary>Sul thread del lettore: copia il fotogramma sulla scheda video, il resto continua altrove.</summary>
    private void SuFotogramma(MediaPlayer origine, object _)
    {
        bool serve;
        lock (blocco) serve = abilitato && !chiuso && origine == lettore && (richiestaFoto is not null || motore.Attivo);
        try { serve |= abilitato && ServonoFotogrammi?.Invoke() == true; }
        catch (Exception) { }
        if (!serve) return;
        if (Interlocked.Exchange(ref copiaInCorso, 1) == 1) return;
        var avviata = false;
        try
        {
            var larghezza = (int)origine.PlaybackSession.NaturalVideoWidth;
            var altezza = (int)origine.PlaybackSession.NaturalVideoHeight;
            if (larghezza <= 0 || altezza <= 0) return;
            if (superficie is null || superficie.Direct3DSurface.Description.Width != larghezza
                || superficie.Direct3DSurface.Description.Height != altezza)
            {
                superficie?.Dispose();
                copiaCpu?.Dispose();
                superficie = VideoFrame.CreateAsDirect3D11SurfaceBacked(DirectXPixelFormat.B8G8R8A8UIntNormalized, larghezza, altezza);
                copiaCpu = new VideoFrame(BitmapPixelFormat.Bgra8, larghezza, altezza, BitmapAlphaMode.Ignore);
            }
            // Il fotogramma del telefono che si sta copiando, per il ritardo da vetro a uscita.
            var mostrato = decodificatore.Mostrato(origine);
            int suaGenerazione;
            lock (blocco) suaGenerazione = generazione;
            origine.CopyFrameToVideoSurface(superficie.Direct3DSurface);
            avviata = true;
            _ = ScaricaAsync(superficie, copiaCpu!, mostrato, suaGenerazione);
        }
        catch (Exception) { }
        finally
        {
            if (!avviata) Volatile.Write(ref copiaInCorso, 0);
        }
    }

    /// <summary>Dalla scheda video alla memoria, poi al motore (o alle uscite com'è, con gli effetti spenti).</summary>
    private async Task ScaricaAsync(VideoFrame gpu, VideoFrame cpu, ulong? mostrato, int suaGenerazione)
    {
        ImmagineBgra? immagine = null;
        try
        {
            await gpu.CopyToAsync(cpu);
            immagine = await Task.Run(() => Copia(cpu.SoftwareBitmap));
        }
        catch (Exception) { }
        finally
        {
            // La copia sulla CPU è libera: il prossimo fotogramma può già partire.
            Volatile.Write(ref copiaInCorso, 0);
        }
        if (immagine is null) return;
        lock (blocco)
        {
            if (suaGenerazione != generazione || chiuso)
            {
                motore.RestituisciIngresso(immagine);
                return;
            }
        }
        immagine.Timestamp = mostrato;
        await Task.Run(() =>
        {
            try
            {
                if (motore.Elabora(immagine, elaborata => Consegna(elaborata, true, null))) return;
                Consegna(immagine, false, suaGenerazione);
            }
            catch (Exception) { }
            motore.RestituisciIngresso(immagine);
        });
    }

    private unsafe ImmagineBgra Copia(SoftwareBitmap bitmap)
    {
        using var dati = bitmap.LockBuffer(BitmapBufferAccessMode.Read);
        var piano = dati.GetPlaneDescription(0);
        using var riferimento = dati.CreateReference();
        WinRT.CastExtensions.As<IMemoryBufferByteAccess>(riferimento).GetBuffer(out var puntatore, out var capacita);
        var sorgente = new ReadOnlySpan<byte>(puntatore + piano.StartIndex, (int)capacita - piano.StartIndex);
        var immagine = motore.PrendiIngresso(piano.Width, piano.Height);
        ImmagineBgra.CopiaRighe(sorgente, piano.Stride, immagine.Dati, immagine.Passo, piano.Width, piano.Height);
        return immagine;
    }

    /// <summary>A tutte le uscite, e alla foto chiesta.</summary>
    /// <param name="suaGenerazione">Per un fotogramma non elaborato: la generazione di quando è partito (il motore
    /// controlla da sé quelli elaborati).</param>
    private void Consegna(ImmagineBgra immagine, bool elaborata, int? suaGenerazione)
    {
        // Gli effetti accesi ma questo fotogramma non elaborato (appena accesi, in passaggio): non si mostra.
        if (!elaborata && motore.Attivo) return;
        lock (blocco)
        {
            if (chiuso || (suaGenerazione is int g && g != generazione)) return;
        }
        try { Fotogramma?.Invoke(immagine, elaborata); }
        catch (Exception) { }
        TaskCompletionSource<SoftwareBitmap?>? foto;
        lock (blocco)
        {
            foto = richiestaFoto;
            richiestaFoto = null;
        }
        if (foto is null) return;
        try
        {
            var bitmap = SoftwareBitmap.CreateCopyFromBuffer(immagine.Dati.AsBuffer(0, immagine.Passo * immagine.Altezza),
                BitmapPixelFormat.Bgra8, immagine.Larghezza, immagine.Altezza, BitmapAlphaMode.Ignore);
            foto.TrySetResult(bitmap);
        }
        catch (Exception)
        {
            foto.TrySetResult(null);
        }
    }

    public void Dispose()
    {
        lock (blocco)
        {
            chiuso = true;
            FermaDecodifica();
            richiestaFoto?.TrySetResult(null);
        }
        motore.Dispose();
        decodificatore.Dispose();
    }

    /// <summary>L'accesso ai byte di un IMemoryBufferReference (windows.foundation.h).</summary>
    [ComImport, Guid("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private unsafe interface IMemoryBufferByteAccess
    {
        void GetBuffer(out byte* buffer, out uint capacity);
    }
}
