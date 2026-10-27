namespace WebcamLR.Effetti;

/// <summary>
/// Pre e post elaborazione sul processore (sulla scheda video la faranno gli shader, Documenti/Effetti su Windows.md).
/// </summary>
public static class Preparazione
{
    /// <summary>
    /// Riduce un'immagine BGRA (8 bit per canale, righe di <paramref name="passo"/> byte) alla misura del modello, in RGB
    /// float con la disposizione NHWC: per ogni punto del modello la media dei pixel che copre (niente scalettature
    /// quando si passa da 1080p a 256). Se l'immagine è più piccola del modello si prende il pixel più vicino.
    /// L'immagine si stira: con 16:9 nel modello quadrato la persona risulta più stretta, come in MediaPipe.
    /// </summary>
    public static void BgraInRgb(ReadOnlySpan<byte> bgra, int larghezza, int altezza, int passo,
        Span<float> destinazione, int larghezzaDest, int altezzaDest, float scala, float spostamento)
    {
        ControllaImmagine(bgra, larghezza, altezza, passo);
        if (destinazione.Length < larghezzaDest * altezzaDest * 3)
            throw new ArgumentException("Destinazione troppo piccola", nameof(destinazione));

        // Colonne di partenza di ogni punto, calcolate una volta sola.
        Span<int> x0 = larghezzaDest <= 1024 ? stackalloc int[larghezzaDest + 1] : new int[larghezzaDest + 1];
        for (var x = 0; x <= larghezzaDest; x++) x0[x] = (int)((long)x * larghezza / larghezzaDest);

        var d = 0;
        for (var y = 0; y < altezzaDest; y++)
        {
            var ya = (int)((long)y * altezza / altezzaDest);
            var yb = Math.Max(ya + 1, (int)((long)(y + 1) * altezza / altezzaDest));
            for (var x = 0; x < larghezzaDest; x++)
            {
                var xa = x0[x];
                var xb = Math.Max(xa + 1, x0[x + 1]);
                int b = 0, g = 0, r = 0;
                for (var yy = ya; yy < yb; yy++)
                {
                    var riga = bgra.Slice(yy * passo + xa * 4, (xb - xa) * 4);
                    for (var i = 0; i < riga.Length; i += 4)
                    {
                        b += riga[i];
                        g += riga[i + 1];
                        r += riga[i + 2];
                    }
                }
                var n = (float)((yb - ya) * (xb - xa));
                destinazione[d++] = r / n * scala + spostamento;
                destinazione[d++] = g / n * scala + spostamento;
                destinazione[d++] = b / n * scala + spostamento;
            }
        }
    }

    /// <summary>
    /// La persona dall'uscita del modello, in [0, 1]: con più classi (softmax, somma 1) 1 − sfondo, così capelli, pelle,
    /// vestiti e accessori contano tutti; con un canale solo, quel canale.
    /// </summary>
    public static void Persona(ReadOnlySpan<float> uscita, int canali, Span<float> persona)
    {
        if (uscita.Length < persona.Length * canali) throw new ArgumentException("Uscita troppo corta", nameof(uscita));
        if (canali == 1)
        {
            for (var i = 0; i < persona.Length; i++) persona[i] = Math.Clamp(uscita[i], 0f, 1f);
            return;
        }
        for (int i = 0, j = 0; i < persona.Length; i++, j += canali) persona[i] = Math.Clamp(1f - uscita[j], 0f, 1f);
    }

    internal static void ControllaImmagine(ReadOnlySpan<byte> bgra, int larghezza, int altezza, int passo)
    {
        if (larghezza <= 0 || altezza <= 0) throw new ArgumentException("Misura dell'immagine non valida");
        if (passo < larghezza * 4) throw new ArgumentException("Passo minore della riga", nameof(passo));
        if (bgra.Length < (long)passo * (altezza - 1) + larghezza * 4)
            throw new ArgumentException("Immagine più corta di quanto dichiarato", nameof(bgra));
    }
}
