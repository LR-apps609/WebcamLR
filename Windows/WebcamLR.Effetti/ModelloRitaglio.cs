namespace WebcamLR.Effetti;

/// <summary>Quale modello ritaglia la persona (Documenti/Effetti su Windows.md, «Modello scelto»).</summary>
public enum ModelloRitaglio
{
    /// <summary>
    /// MediaPipe Selfie Multiclass 256×256 (16 MB): sei classi (sfondo, capelli, pelle del corpo, pelle del volto,
    /// vestiti, accessori), persona = 1 − sfondo. Il bordo dei capelli migliore; per la scheda video.
    /// </summary>
    Pieno,

    /// <summary>
    /// MediaPipe Selfie Segmenter «landscape» 144×256 (0,4 MB): una sola uscita, la persona. Bordo più grossolano ma
    /// pochi millisecondi anche sul processore: il ripiego per i PC senza DirectX 12 o troppo lenti.
    /// </summary>
    Leggero,
}

/// <summary>Come si usa un modello: file, misura dell'ingresso, normalizzazione dei colori, forma dell'uscita.</summary>
public sealed record DescrizioneModello(
    ModelloRitaglio Modello,
    string File,
    int Larghezza,
    int Altezza,
    /// <summary>Valore dato al modello = byte × Scala + Spostamento (RGB).</summary>
    float Scala,
    float Spostamento,
    /// <summary>Canali in uscita: 6 classi (softmax già applicato nel modello) o 1 (la persona).</summary>
    int Canali)
{
    /// <summary>Nomi dell'ingresso e dell'uscita, uguali per tutti e due (Strumenti/converti_ritaglio_onnx.py).</summary>
    public const string NomeIngresso = "immagine";

    /// <summary>RGB in [-1, 1] (metadati del .tflite: media 127,5, deviazione 127,5).</summary>
    public static readonly DescrizioneModello Pieno =
        new(ModelloRitaglio.Pieno, "ritaglio_persona.onnx", 256, 256, 1f / 127.5f, -1f, 6);

    /// <summary>RGB in [0, 1] (metadati del .tflite: media 0, deviazione 255).</summary>
    public static readonly DescrizioneModello Leggero =
        new(ModelloRitaglio.Leggero, "ritaglio_persona_leggero.onnx", 256, 144, 1f / 255f, 0f, 1);

    public static DescrizioneModello Di(ModelloRitaglio modello) => modello == ModelloRitaglio.Pieno ? Pieno : Leggero;

    public string NomeUscita => Canali == 1 ? "persona" : "classi";
}
