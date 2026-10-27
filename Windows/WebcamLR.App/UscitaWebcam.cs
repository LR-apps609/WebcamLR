using System.Diagnostics;
using System.Runtime.InteropServices;
using Windows.Graphics.DirectX;
using Windows.Graphics.Imaging;
using Windows.Media;
using Windows.Media.Playback;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// Passa il video del telefono alla webcam «WebcamLR» (1.24). Un secondo decodificatore hardware, separato da quello
/// dell'anteprima (che quindi non rallenta), lavora solo mentre un'app usa la webcam: la sorgente dentro Frame Server
/// (Windows 11) o il filtro DirectShow dentro l'app (Windows 10, P23) segna il suo battito nella memoria condivisa. Ogni fotogramma decodificato la scheda video lo porta alla
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

    /// <summary>
    /// Windows 11: si apre l'anello globale creato dalla sorgente in Frame Server. Windows 10 (P23): l'app crea quello
    /// locale della sessione, che il filtro DirectShow apre dentro ogni app che usa la webcam.
    /// </summary>
    public TipoWebcam Tipo { get; set; } = TipoWebcam.MediaFoundation;

    /// <summary>Dopo un errore di creazione dell'anello locale non si riprova a ogni secondo.</summary>
    private long prossimaCreazione;
    public Inquadratura Inquadratura { get; set; } = Inquadratura.Adatta;

    // Schermata di attesa della webcam (come sul Mac): perché non c'è video, in che stile, l'immagine personale (Pro).
    private StatoAttesa statoAttesa = StatoAttesa.NonCollegata;
    private StileAttesa stileAttesa = StileAttesa.WebcamLR;
    private (byte[] Bgra, int Larghezza, int Altezza, int Passo)? immaginePersonale;
    private bool immagineScritta;
    private static LinguaAttesa LinguaApp => Testi.LinguaWebcam;

    /// <summary>
    /// Perché la webcam non mostra il video e con che stile (senza Pro sempre «WebcamLR»). Si scrive subito nella memoria
    /// condivisa e poi ogni secondo, che fa anche da battito: senza battito da 2,5 s la webcam sa che l'app è chiusa.
    /// Da qualsiasi thread.
    /// </summary>
    public void ImpostaAttesa(StatoAttesa stato, StileAttesa stile)
    {
        lock (blocco)
        {
            if (statoAttesa == stato && stileAttesa == stile) return;
            statoAttesa = stato;
            stileAttesa = stile;
            try { memoria?.Anello.ImpostaAttesa(stato, stile, LinguaApp, Environment.TickCount64); } catch (Exception) { }
        }
    }

    /// <summary>L'immagine personale della schermata di attesa (BGRA); null per toglierla. Si riscrive a ogni memoria riaperta.</summary>
    public void ImpostaImmaginePersonale(byte[]? bgra, int larghezza, int altezza, int passo)
    {
        lock (blocco)
        {
            immaginePersonale = bgra is null ? null : (bgra, larghezza, altezza, passo);
            immagineScritta = false;
            ScriviImmaginePersonale();
        }
    }

    /// <summary>Dentro il blocco.</summary>
    private void ScriviImmaginePersonale()
    {
        if (memoria is null || immagineScritta) return;
        try
        {
            if (immaginePersonale is { } immagine)
                memoria.Anello.ScriviImmaginePersonaleBgra(immagine.Bgra, immagine.Larghezza, immagine.Altezza, immagine.Passo);
            else
                memoria.Anello.TogliImmaginePersonale();
            immagineScritta = true;
        }
        catch (Exception errore)
        {
            immagineScritta = true;
            Evento?.Invoke(Testi.T("Webcam_ImmagineNonScritta", errore.Message));
        }
    }
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

    /// <summary>
    /// Dal thread di rete, per ogni fotogramma: costa nulla se la webcam non è in uso. <paramref name="scarto"/>: la
    /// differenza tra gli orologi della sessione, per il ritardo da vetro a uscita.
    /// </summary>
    public void Accoda(FotogrammaVideo fotogramma, long? scarto = null)
    {
        if (Volatile.Read(ref lettore) is null) return;
        decodificatore.Accoda(fotogramma, scarto);
    }

    /// <summary>Da vetro alla scrittura nella memoria condivisa (decodificato, scalato, convertito): mediana di un secondo.</summary>
    private readonly MisuraRitardo consegna = new();
    /// <summary>L'attesa nella sorgente della webcam fino alla consegna all'app di chiamata (µs), letta ogni secondo.</summary>
    private long? attesaSorgente;

    /// <summary>
    /// Da vetro alla webcam (ms): fino alla memoria condivisa, più l'attesa nella sorgente quando la sorgente la dice
    /// (una webcam installata da una versione di prima non la dice). Null se la webcam non riceve il video.
    /// </summary>
    public int? RitardoMs
    {
        get
        {
            if (consegna.Valore(Orologio.Adesso()) is not int ms) return null;
            long? attesa;
            lock (blocco) attesa = attesaSorgente;
            return ms + (int)((attesa ?? 0) / 1000);
        }
    }

    /// <summary>L'attesa nella sorgente (ms) per il registro; null se non si sa.</summary>
    public int? AttesaSorgenteMs
    {
        get { lock (blocco) return attesaSorgente is long us ? (int)(us / 1000) : null; }
    }

    /// <summary>Quanto il lettore della webcam ha accorciato la sua linea del tempo (ms), per il registro.</summary>
    public int RecuperatoMs => (int)(decodificatore.Recuperato / 1000);

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
                if (Abilitata && memoria is null && Environment.TickCount64 >= prossimaCreazione)
                {
                    if (Tipo == TipoWebcam.MediaFoundation)
                    {
                        memoria = MemoriaCondivisa.Apri();
                        immagineScritta = false;
                        if (memoria is not null) Evento?.Invoke(Testi.T("Webcam_CollegataSorgente"));
                    }
                    else
                    {
                        // Windows 10: niente Frame Server, l'anello «Local\» lo crea l'app (o il filtro, se è arrivato prima).
                        try
                        {
                            memoria = MemoriaCondivisa.Crea(NomiAnello.Locale);
                            immagineScritta = false;
                            Evento?.Invoke(Testi.T("Webcam_MemoriaPronta"));
                        }
                        catch (Exception errore)
                        {
                            prossimaCreazione = Environment.TickCount64 + 30_000;
                            Evento?.Invoke(Testi.T("Webcam_MemoriaAssente", errore.Message));
                        }
                    }
                }
                var ora = Environment.TickCount64;
                if (memoria is not null)
                {
                    // Ogni secondo: lo stato di attesa fa anche da battito dell'app.
                    memoria.Anello.ImpostaAttesa(statoAttesa, stileAttesa, LinguaApp, ora);
                    ScriviImmaginePersonale();
                }
                adesso = Abilitata && memoria is not null && memoria.Anello.InUso(ora);
                cambiato = adesso != inUso;
                inUso = adesso;
                if (cambiato && adesso)
                {
                    var (l, a, _) = memoria!.Anello.Richiesta();
                    var fps = memoria.Anello.FpsChiesti;
                    descrizione = fps > 0 ? Testi.T("Webcam_FormatoChiesto", l, a, fps) : $" ({l}×{a})";
                }
                fpsAdesso = adesso ? memoria!.Anello.FpsChiesti : 0;
                attesaSorgente = adesso ? memoria!.Anello.AttesaSorgente(Stopwatch.GetTimestamp(), Stopwatch.Frequency) : null;
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
            Evento?.Invoke(Testi.T("Webcam_Riga", errore.Message));
            return;
        }
        if (cambiato)
        {
            Evento?.Invoke(adesso ? Testi.T("Webcam_InUso", descrizione) : Testi.T("Webcam_NessunaApp"));
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
        nuovo.MediaFailed += (_, evento) => Evento?.Invoke(Testi.T("Webcam_NonSiDecodifica", evento.ErrorMessage));
        Volatile.Write(ref lettore, nuovo);
        Evento?.Invoke(Testi.T("Webcam_VideoVersoApp", f.Larghezza, f.Altezza));
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
            // Il fotogramma del telefono che si sta copiando, per il ritardo da vetro a uscita.
            var mostrato = decodificatore.Mostrato(origine);
            var scarto = decodificatore.Scarto;
            // La scheda video scala il fotogramma alla misura intermedia.
            origine.CopyFrameToVideoSurface(superficie.Direct3DSurface);
            avviata = true;
            _ = ConvertiEScriviAsync(m, superficie, copiaCpu!, camera, modo, Specchia, mostrato, scarto);
        }
        catch (Exception) { }
        finally
        {
            if (!avviata) Volatile.Write(ref copiaInCorso, 0);
        }
    }

    private async Task ConvertiEScriviAsync(MemoriaCondivisa m, VideoFrame gpu, VideoFrame cpu, FormatoWebcam camera,
        Inquadratura modo, bool specchia, ulong? mostrato, long? scarto)
    {
        try
        {
            // Dalla scheda video alla memoria, poi la conversione sul pool di thread.
            await gpu.CopyToAsync(cpu);
            await Task.Run(() => Scrivi(m, cpu.SoftwareBitmap, camera, modo, specchia));
            // Scritto nella memoria condivisa: da qui la sorgente lo consegna (la sua attesa la misura lei).
            if (mostrato is ulong timestamp && scarto is long differenza)
            {
                var adesso = Orologio.Adesso();
                if (RitardoVetro.Ms(timestamp, differenza, adesso) is int ms) consegna.Aggiungi(ms, adesso);
            }
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
            // La webcam passa subito a «non collegata», senza aspettare che il battito manchi.
            try { memoria?.Anello.SegnalaChiusura(); } catch (Exception) { }
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
