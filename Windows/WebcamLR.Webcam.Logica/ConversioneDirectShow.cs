namespace WebcamLR.Webcam;

/// <summary>
/// Dal fotogramma NV12 della memoria condivisa ai formati del filtro DirectShow (Windows 10): YUY2, NV12 con un altro
/// passo, RGB24. Lavora dentro il processo dell'app che usa la webcam (Zoom, Chrome, OBS…): niente memoria nuova a
/// ogni fotogramma, e righe in parallelo solo dal 720p in su. BT.709 a gamma ridotta, come la conversione dell'app.
/// </summary>
public static class ConversioneDirectShow
{
    /// <summary>
    /// Converte <paramref name="nv12"/> (righe senza margine, larghezza × altezza del formato) nello spazio dato
    /// dall'app, con <paramref name="passo"/> byte per riga (almeno <see cref="FormatoDirectShow.BytePerRiga"/>:
    /// un renderer può chiederne di più). Restituisce i byte usati.
    /// </summary>
    public static int Converti(ReadOnlySpan<byte> nv12, FormatoDirectShow formato, Span<byte> destinazione, int passo)
    {
        int l = formato.Larghezza, a = formato.Altezza;
        if (l <= 0 || a <= 0 || l % 2 != 0 || a % 2 != 0) throw new ArgumentException($"Misura non valida: {l}×{a}");
        if (nv12.Length < FormatoWebcam.DimensioneNv12(l, a)) throw new ArgumentException("Fotogramma NV12 troppo piccolo", nameof(nv12));
        if (passo < formato.BytePerRiga) throw new ArgumentException("Passo troppo piccolo", nameof(passo));
        var usati = formato.Codifica == CodificaDirectShow.Nv12 ? passo * a * 3 / 2 : passo * a;
        if (destinazione.Length < usati) throw new ArgumentException("Spazio di destinazione troppo piccolo", nameof(destinazione));
        switch (formato.Codifica)
        {
            case CodificaDirectShow.Nv12: Nv12ConPasso(nv12, l, a, destinazione, passo); break;
            case CodificaDirectShow.Yuy2: Nv12InYuy2(nv12, l, a, destinazione, passo); break;
            default: Nv12InRgb24(nv12, l, a, destinazione, passo); break;
        }
        return usati;
    }

    /// <summary>NV12 → NV12: una copia unica se il passo coincide, altrimenti riga per riga.</summary>
    public static void Nv12ConPasso(ReadOnlySpan<byte> nv12, int larghezza, int altezza, Span<byte> destinazione, int passo)
    {
        var righe = altezza * 3 / 2;
        if (passo == larghezza)
        {
            nv12[..(larghezza * righe)].CopyTo(destinazione);
            return;
        }
        for (var y = 0; y < righe; y++)
            nv12.Slice(y * larghezza, larghezza).CopyTo(destinazione.Slice(y * passo, larghezza));
    }

    /// <summary>
    /// NV12 (4:2:0) → YUY2 (4:2:2, Y0 U Y1 V): ogni coppia di righe usa la stessa riga di crominanza.
    /// </summary>
    public static unsafe void Nv12InYuy2(ReadOnlySpan<byte> nv12, int larghezza, int altezza, Span<byte> destinazione, int passo)
    {
        fixed (byte* s = nv12)
        fixed (byte* d = destinazione)
        {
            var p = new Puntatori((nint)s, (nint)d, larghezza, altezza, passo);
            PerRiga(altezza, larghezza, p, static (p, y) =>
            {
                var luma = (byte*)p.Sorgente + (long)y * p.Larghezza;
                var croma = (byte*)p.Sorgente + (long)p.Larghezza * p.Altezza + (long)(y / 2) * p.Larghezza;
                var uscita = (byte*)p.Destinazione + (long)y * p.Passo;
                for (var x = 0; x < p.Larghezza; x += 2)
                {
                    uscita[0] = luma[x];
                    uscita[1] = croma[x];
                    uscita[2] = luma[x + 1];
                    uscita[3] = croma[x + 1];
                    uscita += 4;
                }
            });
        }
    }

    /// <summary>
    /// NV12 → RGB24 (B, G, R) dal basso verso l'alto, come vuole una bitmap con altezza positiva.
    /// BT.709 inverso a gamma ridotta in virgola fissa: R = 1,164·(Y−16) + 1,793·(V−128) e così via.
    /// </summary>
    public static unsafe void Nv12InRgb24(ReadOnlySpan<byte> nv12, int larghezza, int altezza, Span<byte> destinazione, int passo)
    {
        fixed (byte* s = nv12)
        fixed (byte* d = destinazione)
        {
            var p = new Puntatori((nint)s, (nint)d, larghezza, altezza, passo);
            PerRiga(altezza, larghezza, p, static (p, y) =>
            {
                var luma = (byte*)p.Sorgente + (long)y * p.Larghezza;
                var croma = (byte*)p.Sorgente + (long)p.Larghezza * p.Altezza + (long)(y / 2) * p.Larghezza;
                // Bitmap dal basso: la riga y dell'immagine è la riga (altezza − 1 − y) in memoria.
                var uscita = (byte*)p.Destinazione + (long)(p.Altezza - 1 - y) * p.Passo;
                for (var x = 0; x < p.Larghezza; x += 2)
                {
                    int u = croma[x] - 128, v = croma[x + 1] - 128;
                    var rossoV = 459 * v + 128;
                    var verdeUV = -55 * u - 136 * v + 128;
                    var bluU = 541 * u + 128;
                    for (var k = 0; k < 2; k++)
                    {
                        var c = 298 * (luma[x + k] - 16);
                        uscita[0] = Limita((c + bluU) >> 8);
                        uscita[1] = Limita((c + verdeUV) >> 8);
                        uscita[2] = Limita((c + rossoV) >> 8);
                        uscita += 3;
                    }
                }
            });
        }
    }

    private static byte Limita(int valore) => (byte)Math.Clamp(valore, 0, 255);

    private readonly record struct Puntatori(nint Sorgente, nint Destinazione, int Larghezza, int Altezza, int Passo);

    private static void PerRiga(int altezza, int larghezza, Puntatori p, Action<Puntatori, int> riga)
    {
        if ((long)larghezza * altezza >= 1280 * 720)
            Parallel.For(0, altezza, y => riga(p, y));
        else
            for (var y = 0; y < altezza; y++) riga(p, y);
    }
}
