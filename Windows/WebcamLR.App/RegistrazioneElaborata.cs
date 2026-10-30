using System.Diagnostics;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading.Channels;
using Windows.Media.Core;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;
using Windows.Storage.Streams;
using WebcamLR.Effetti;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// La registrazione con gli effetti sul computer: l'immagine elaborata dal motore (la stessa dell'anteprima e della
/// webcam) ricompressa in H.264 dal codificatore hardware di Windows (MediaTranscoder, da una MediaStreamSource di
/// fotogrammi BGRA) in un MP4 in Video › WebcamLR. Senza audio, come la registrazione di prima. I fotogrammi arrivano dal
/// motore e non aspettano mai il disco: oltre 8 in coda (circa un quarto di secondo) si saltano.
/// I tempi sono quelli d'arrivo sul PC: il video dura quanto la registrazione, anche se qualche fotogramma si salta.
/// </summary>
/// <remarks>
/// MP4 frammentato (1.0 beta 2, windows.md 1.3 e 1.4): il contenitore del profilo è
/// <c>MFTranscodeContainerType_FMPEG4</c> di Media Foundation, scritto come GUID perché MediaEncodingSubtypes non ha un
/// nome per lui. Se il codificatore di questo Windows non lo accetta si torna all'MP4 normale (indice alla fine, come
/// prima) e il registro lo dice. Con il file frammentato un errore del disco lascia il file fino all'ultimo frammento
/// completo (FrammentiMp4 lo trova e taglia il resto).
/// </remarks>
public sealed class RegistrazioneElaborata : IRegistrazione
{
    private const int MassimoInAttesa = 8;

    private readonly Channel<(byte[] Dati, TimeSpan Tempo)> coda =
        Channel.CreateBounded<(byte[], TimeSpan)>(new BoundedChannelOptions(MassimoInAttesa) { SingleReader = true, FullMode = BoundedChannelFullMode.DropWrite });
    private readonly Stack<byte[]> liberi = new();
    private readonly object blocco = new();
    private readonly int larghezza, altezza;
    private readonly Stopwatch orologio = new();
    private Task<FineRegistrazione> lavoro = Task.FromResult(new FineRegistrazione(EsitoRegistrazione.Interrotta, "", TimeSpan.Zero, 0));
    private long tempoScritto;
    private TimeSpan ultimoTempo = TimeSpan.MinValue;
    private bool videoCambiato;
    private int frammentata = -1;

    /// <summary>MFTranscodeContainerType_FMPEG4 (mfidl.h): MP4 frammentato.</summary>
    private const string ContenitoreFrammentato = "{9BA876F1-419F-4B77-A1E0-35959D9D4004}";

    /// <summary>Vero se il codificatore ha accettato il contenitore frammentato; null finché non è partito.</summary>
    public bool? Frammentata => Volatile.Read(ref frammentata) switch { 1 => true, 0 => false, _ => null };

    public string File { get; }

    /// <summary>Circa: il file cresce mentre il codificatore scrive.</summary>
    public long Byte
    {
        get
        {
            try { return new FileInfo(File).Length; }
            catch (Exception) { return 0; }
        }
    }

    public TimeSpan Durata => TimeSpan.FromTicks(Interlocked.Read(ref tempoScritto));

    public event Action<FineRegistrazione>? FinitaDaSola;

    private RegistrazioneElaborata(string file, int larghezza, int altezza)
    {
        File = file;
        this.larghezza = larghezza;
        this.altezza = altezza;
    }

    /// <summary>Crea il file (che non deve esistere) e fa partire il codificatore. Un errore arriva come eccezione.</summary>
    public static async Task<RegistrazioneElaborata> AvviaAsync(string file, int larghezza, int altezza, int fps)
    {
        var cartella = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(file)!);
        var nuovo = await cartella.CreateFileAsync(Path.GetFileName(file), CreationCollisionOption.FailIfExists);
        var flusso = await nuovo.OpenAsync(FileAccessMode.ReadWrite);
        var registrazione = new RegistrazioneElaborata(file, larghezza & ~1, altezza & ~1);
        registrazione.lavoro = registrazione.ScriviAsync(flusso, Math.Clamp(fps, 15, 60));
        return registrazione;
    }

    /// <summary>
    /// Dal motore, per ogni immagine elaborata: si copia e si mette in coda, senza aspettare. Un'immagine di un'altra
    /// misura (altro obiettivo, telefono girato) chiude il file: è un video solo.
    /// </summary>
    public void Accoda(ImmagineBgra immagine)
    {
        if (immagine.Larghezza < larghezza || immagine.Altezza < altezza
            || (immagine.Larghezza & ~1) != larghezza || (immagine.Altezza & ~1) != altezza)
        {
            lock (blocco) videoCambiato = true;
            coda.Writer.TryComplete();
            return;
        }
        byte[] dati;
        TimeSpan tempo;
        lock (blocco)
        {
            if (!orologio.IsRunning) orologio.Start();
            tempo = orologio.Elapsed;
            if (tempo <= ultimoTempo) return;
            dati = liberi.Count > 0 ? liberi.Pop() : new byte[larghezza * altezza * 4];
        }
        if (immagine.Larghezza == larghezza) immagine.Dati.AsSpan(0, dati.Length).CopyTo(dati);
        else ImmagineBgra.CopiaRighe(immagine.Dati, immagine.Passo, dati, larghezza * 4, larghezza, altezza);
        if (coda.Writer.TryWrite((dati, tempo)))
        {
            lock (blocco) ultimoTempo = tempo;
        }
        else
        {
            lock (blocco) liberi.Push(dati);
        }
    }

    public async Task<FineRegistrazione> FermaAsync()
    {
        coda.Writer.TryComplete();
        return await lavoro.ConfigureAwait(false);
    }

    private async Task<FineRegistrazione> ScriviAsync(IRandomAccessStream flusso, int fps)
    {
        try
        {
            MediaStreamSource NuovaSorgente()
            {
                var proprieta = VideoEncodingProperties.CreateUncompressed(MediaEncodingSubtypes.Bgra8, (uint)larghezza, (uint)altezza);
                proprieta.FrameRate.Numerator = (uint)fps;
                proprieta.FrameRate.Denominator = 1;
                var sorgente = new MediaStreamSource(new VideoStreamDescriptor(proprieta)) { CanSeek = false, BufferTime = TimeSpan.Zero };
                sorgente.Starting += (_, evento) => evento.Request.SetActualStartPosition(TimeSpan.Zero);
                sorgente.SampleRequested += SuRichiesta;
                return sorgente;
            }

            var codificatore = new MediaTranscoder { HardwareAccelerationEnabled = true };
            // Prima il contenitore frammentato; se questo Windows non lo accetta, l'MP4 di prima, con una sorgente nuova
            // e il file di nuovo vuoto.
            PrepareTranscodeResult? preparato = null;
            try
            {
                preparato = await codificatore.PrepareMediaStreamSourceTranscodeAsync(NuovaSorgente(), flusso, Profilo(fps, frammentato: true));
                if (!preparato.CanTranscode) preparato = null;
            }
            catch (Exception) { }
            Volatile.Write(ref frammentata, preparato is null ? 0 : 1);
            if (preparato is null)
            {
                flusso.Seek(0);
                flusso.Size = 0;
                preparato = await codificatore.PrepareMediaStreamSourceTranscodeAsync(NuovaSorgente(), flusso, Profilo(fps, frammentato: false));
            }
            if (!preparato.CanTranscode)
            {
                flusso.Dispose();
                return Finisci(Scarta(EsitoRegistrazione.Interrotta));
            }
            await preparato.TranscodeAsync().AsTask().ConfigureAwait(false);
            flusso.Dispose();
            var durata = Durata;
            if (durata < Riprese.DurataMinima) return Finisci(Scarta(EsitoRegistrazione.TroppoBreve));
            bool cambiato;
            lock (blocco) cambiato = videoCambiato;
            var fine = new FineRegistrazione(cambiato ? EsitoRegistrazione.VideoCambiato : EsitoRegistrazione.Salvata, File, durata, Byte);
            return cambiato ? Finisci(fine) : fine;
        }
        catch (Exception errore)
        {
            coda.Writer.TryComplete();
            try { flusso.Dispose(); } catch (Exception) { }
            return Finisci(DopoErrore(errore));
        }
    }

    /// <summary>H.264 in MP4, frammentato o no, con la misura e il ritmo del motore.</summary>
    private MediaEncodingProfile Profilo(int fps, bool frammentato)
    {
        var profilo = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
        profilo.Audio = null;
        if (frammentato) profilo.Container.Subtype = ContenitoreFrammentato;
        profilo.Video.Width = (uint)larghezza;
        profilo.Video.Height = (uint)altezza;
        profilo.Video.FrameRate.Numerator = (uint)fps;
        profilo.Video.FrameRate.Denominator = 1;
        // Circa 0,15 bit per pixel: 9 Mbit/s a 1080p30, come un video del telefono a buona qualità.
        profilo.Video.Bitrate = (uint)Math.Clamp((long)larghezza * altezza * fps * 15 / 100, 2_000_000, 40_000_000);
        return profilo;
    }

    /// <summary>
    /// Il codificatore si è fermato con un errore (di solito il disco pieno, windows.md 1.4). Con il file frammentato si
    /// tiene fino all'ultimo frammento completo e si dice quanto dura; senza frammenti (o con l'MP4 normale, che senza
    /// indice non si legge) il file non resta.
    /// </summary>
    private FineRegistrazione DopoErrore(Exception errore)
    {
        if (Frammentata != true) return Scarta(EsitoRegistrazione.Interrotta);
        try
        {
            ParteLeggibile parte;
            using (var file = new FileStream(File, FileMode.Open, FileAccess.ReadWrite, FileShare.Read, bufferSize: 0))
            {
                parte = FrammentiMp4.Leggi(file);
                if (parte.Frammenti == 0 || parte.Durata < Riprese.DurataMinima) return Scarta(EsitoRegistrazione.Interrotta);
                if (file.Length > parte.Fine) file.SetLength(parte.Fine);
            }
            long? liberi = null;
            try { liberi = new DriveInfo(Path.GetPathRoot(File)!).AvailableFreeSpace; } catch (Exception) { }
            var esito = Riprese.EDiscoPieno(errore, liberi) ? EsitoRegistrazione.DiscoPieno : EsitoRegistrazione.ErroreDiScrittura;
            return new FineRegistrazione(esito, File, parte.Durata, parte.Fine);
        }
        catch (Exception)
        {
            return Scarta(EsitoRegistrazione.Interrotta);
        }
    }

    /// <summary>Il codificatore chiede il prossimo fotogramma: aspetta quello dal motore; a coda chiusa, il video finisce.</summary>
    private async void SuRichiesta(MediaStreamSource origine, MediaStreamSourceSampleRequestedEventArgs evento)
    {
        var rinvio = evento.Request.GetDeferral();
        try
        {
            if (await coda.Reader.WaitToReadAsync() && coda.Reader.TryRead(out var fotogramma))
            {
                var campione = MediaStreamSample.CreateFromBuffer(fotogramma.Dati.AsBuffer(), fotogramma.Tempo);
                campione.KeyFrame = true;
                evento.Request.Sample = campione;
                Interlocked.Exchange(ref tempoScritto, fotogramma.Tempo.Ticks);
                // Il buffer torna in giro quando il codificatore ha finito con il campione.
                var dati = fotogramma.Dati;
                campione.Processed += (_, _) =>
                {
                    lock (blocco) if (liberi.Count < MassimoInAttesa + 4) liberi.Push(dati);
                };
            }
            else
            {
                evento.Request.Sample = null;
            }
        }
        // async void: un errore qui (sorgente già chiusa) chiuderebbe l'app.
        catch (Exception) { }
        finally
        {
            try { rinvio.Complete(); } catch (Exception) { }
        }
    }

    /// <summary>Un file non riuscito o troppo breve non resta sul disco.</summary>
    private FineRegistrazione Scarta(EsitoRegistrazione esito)
    {
        try { System.IO.File.Delete(File); } catch (Exception) { }
        return new FineRegistrazione(esito, File, Durata, 0);
    }

    /// <summary>
    /// Finita per un motivo suo (errore, video cambiato): la finestra lo sa. Se intanto era già stata fermata con «Ferma»,
    /// la finestra lo ignora (la registrazione non è più quella in corso).
    /// </summary>
    private FineRegistrazione Finisci(FineRegistrazione fine)
    {
        try { FinitaDaSola?.Invoke(fine); } catch (Exception) { }
        return fine;
    }
}
