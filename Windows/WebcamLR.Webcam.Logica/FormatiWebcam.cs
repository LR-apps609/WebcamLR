namespace WebcamLR.Webcam;

/// <summary>Un formato che la webcam offre alle app: sempre NV12, progressivo.</summary>
public readonly record struct FormatoWebcam(int Larghezza, int Altezza, int Fps)
{
    /// <summary>Byte di un fotogramma NV12: luminanza piena più crominanza a metà in entrambe le direzioni.</summary>
    public int Byte => DimensioneNv12(Larghezza, Altezza);

    public static int DimensioneNv12(int larghezza, int altezza) => larghezza * altezza * 3 / 2;

    public override string ToString() => $"{Larghezza}×{Altezza} a {Fps} fps";
}

public static class FormatiWebcam
{
    /// <summary>
    /// Tutti 16:9, il primo è quello scelto se l'app non chiede nulla. Zoom e Teams scelgono 720p o 1080p da soli;
    /// i formati piccoli servono alle app che vogliono poco (anteprime, reti lente) senza far scalare a loro.
    /// 60 fps (1080p e 720p) e 4K a 30 fps (P12) per OBS e per chi registra: in fondo, così i primi restano quelli
    /// di sempre e le app che prendono il primo formato adatto non cambiano scelta.
    /// </summary>
    public static readonly IReadOnlyList<FormatoWebcam> Tutti =
    [
        new(1920, 1080, 30),
        new(1280, 720, 30),
        new(960, 540, 30),
        new(640, 360, 30),
        new(1920, 1080, 60),
        new(1280, 720, 60),
        new(3840, 2160, 30),
    ];

    public static FormatoWebcam Predefinito => Tutti[0];

    /// <summary>Il fotogramma più grande che passa nella memoria condivisa (4K).</summary>
    public static FormatoWebcam Massimo { get; } = Tutti.MaxBy(f => f.Byte);

    /// <summary>Il formato offerto con queste dimensioni (il primo, cioè a 30 fps), oppure quello predefinito.</summary>
    public static FormatoWebcam Cerca(int larghezza, int altezza) => Trova(larghezza, altezza, 0, 0) ?? Predefinito;

    /// <summary>
    /// Il formato offerto con queste dimensioni e questa frequenza (MF_MT_FRAME_RATE: numeratore e denominatore).
    /// Senza frequenza (0) vale il primo con quelle dimensioni. Null se non è uno dei nostri.
    /// </summary>
    public static FormatoWebcam? Trova(int larghezza, int altezza, uint numeratore, uint denominatore)
    {
        var fps = numeratore == 0 || denominatore == 0 ? 0 : (int)Math.Round((double)numeratore / denominatore);
        foreach (var formato in Tutti)
        {
            if (formato.Larghezza != larghezza || formato.Altezza != altezza) continue;
            if (fps == 0 || formato.Fps == fps) return formato;
        }
        return null;
    }
}

/// <summary>
/// Il ritmo di consegna della sorgente per una frequenza: la durata di un fotogramma e, con l'app che manda video,
/// la finestra in cui si aspetta il suo fotogramma nuovo (dall'84 al 114% dell'intervallo: 28–38 ms a 30 fps,
/// 14–19 ms a 60 fps). <paramref name="Frequenza"/>: i tick al secondo dell'orologio (Stopwatch.Frequency).
/// </summary>
public readonly record struct RitmoWebcam(int Fps, long Frequenza)
{
    /// <summary>La durata di un fotogramma in unità da 100 ns (333 333 a 30 fps, 166 666 a 60 fps).</summary>
    public long Durata100ns => 10_000_000L / Fps;
    public long IntervalloTick => Frequenza / Fps;
    public long MinimoTick => Frequenza * 84 / (100L * Fps);
    public long MassimoTick => Frequenza * 114 / (100L * Fps);
}
