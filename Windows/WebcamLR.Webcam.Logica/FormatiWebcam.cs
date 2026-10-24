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
    /// </summary>
    public static readonly IReadOnlyList<FormatoWebcam> Tutti =
    [
        new(1920, 1080, 30),
        new(1280, 720, 30),
        new(960, 540, 30),
        new(640, 360, 30),
    ];

    public static FormatoWebcam Predefinito => Tutti[0];

    /// <summary>Il fotogramma più grande che passa nella memoria condivisa.</summary>
    public static FormatoWebcam Massimo => Tutti[0];

    /// <summary>Il formato offerto con queste dimensioni, oppure quello predefinito.</summary>
    public static FormatoWebcam Cerca(int larghezza, int altezza)
    {
        foreach (var formato in Tutti)
        {
            if (formato.Larghezza == larghezza && formato.Altezza == altezza) return formato;
        }
        return Predefinito;
    }
}
