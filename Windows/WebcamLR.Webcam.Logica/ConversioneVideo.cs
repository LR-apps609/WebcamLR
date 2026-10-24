namespace WebcamLR.Webcam;

/// <summary>Un rettangolo in pixel. Per NV12 posizione e dimensioni sono sempre pari.</summary>
public readonly record struct Riquadro(int X, int Y, int Larghezza, int Altezza)
{
    public static Riquadro Intero(int larghezza, int altezza) => new(0, 0, larghezza, altezza);
}

/// <summary>Come il video del telefono entra nel formato della webcam quando le proporzioni sono diverse.</summary>
public enum Inquadratura
{
    /// <summary>Tutto il video, con bande nere ai lati o sopra e sotto.</summary>
    Adatta,
    /// <summary>Riempie la webcam tagliando i bordi del video.</summary>
    Riempi,
}

public static class Inquadrature
{
    /// <summary>
    /// Quale parte del video (sorgente) va in quale parte della webcam (destinazione).
    /// Il video verticale di un telefono in una webcam 16:9: «Adatta» lo mette al centro con le bande nere,
    /// «Riempi» ne tiene la fascia centrale.
    /// </summary>
    public static (Riquadro Sorgente, Riquadro Destinazione) Calcola(
        int larghezzaSorgente, int altezzaSorgente, int larghezzaDestinazione, int altezzaDestinazione, Inquadratura modo)
    {
        if (larghezzaSorgente <= 0 || altezzaSorgente <= 0 || larghezzaDestinazione <= 0 || altezzaDestinazione <= 0)
            throw new ArgumentException("Dimensioni non valide");
        var scalaX = (double)larghezzaDestinazione / larghezzaSorgente;
        var scalaY = (double)altezzaDestinazione / altezzaSorgente;
        if (modo == Inquadratura.Adatta)
        {
            var scala = Math.Min(scalaX, scalaY);
            var larghezza = Math.Min(larghezzaDestinazione, Pari(Math.Round(larghezzaSorgente * scala)));
            var altezza = Math.Min(altezzaDestinazione, Pari(Math.Round(altezzaSorgente * scala)));
            var destinazione = new Riquadro(
                PariGiu((larghezzaDestinazione - larghezza) / 2), PariGiu((altezzaDestinazione - altezza) / 2), larghezza, altezza);
            return (Riquadro.Intero(larghezzaSorgente, altezzaSorgente), destinazione);
        }
        else
        {
            var scala = Math.Max(scalaX, scalaY);
            var larghezza = Math.Min(larghezzaSorgente, Math.Max(1, (int)Math.Round(larghezzaDestinazione / scala)));
            var altezza = Math.Min(altezzaSorgente, Math.Max(1, (int)Math.Round(altezzaDestinazione / scala)));
            var sorgente = new Riquadro((larghezzaSorgente - larghezza) / 2, (altezzaSorgente - altezza) / 2, larghezza, altezza);
            return (sorgente, Riquadro.Intero(larghezzaDestinazione, altezzaDestinazione));
        }
    }

    /// <summary>
    /// Le dimensioni a cui chiedere il fotogramma al decodificatore (che scala sulla scheda video) perché poi la parte
    /// da usare passi pixel per pixel: così il processore converte soltanto in NV12, senza scalare. Un video 4K non si
    /// copia mai intero dalla scheda video. Unica eccezione: «Riempi» con un video verticale chiederebbe un fotogramma
    /// enorme (1920×3413), allora ci si ferma a circa il doppio dei pixel della webcam e il resto lo scala il processore.
    /// </summary>
    public static (int Larghezza, int Altezza) DimensioneIntermedia(
        int larghezzaSorgente, int altezzaSorgente, int larghezzaDestinazione, int altezzaDestinazione, Inquadratura modo)
    {
        if (modo == Inquadratura.Adatta)
        {
            var (_, destinazione) = Calcola(larghezzaSorgente, altezzaSorgente, larghezzaDestinazione, altezzaDestinazione, modo);
            return (destinazione.Larghezza, destinazione.Altezza);
        }
        var scala = Math.Max((double)larghezzaDestinazione / larghezzaSorgente, (double)altezzaDestinazione / altezzaSorgente);
        var limite = Math.Sqrt(2.0 * larghezzaDestinazione * altezzaDestinazione / ((double)larghezzaSorgente * altezzaSorgente));
        var usata = Math.Min(scala, limite);
        return (Pari(Math.Round(larghezzaSorgente * usata)), Pari(Math.Round(altezzaSorgente * usata)));
    }

    private static int Pari(double valore) => Math.Max(2, (int)valore & ~1);
    private static int PariGiu(int valore) => Math.Max(0, valore & ~1);
}

/// <summary>
/// Conversione dei fotogrammi in NV12 (il formato della webcam), con i coefficienti BT.709 a gamma ridotta
/// (16–235), gli stessi dichiarati nei formati della sorgente.
/// </summary>
public static unsafe class ConversioneVideo
{
    public const byte YNero = 16;
    public const byte UVNeutro = 128;

    /// <summary>Riempie un fotogramma NV12 di nero.</summary>
    public static void RiempiNero(Span<byte> nv12, int larghezza, int altezza)
    {
        var luminanza = larghezza * altezza;
        nv12[..luminanza].Fill(YNero);
        nv12.Slice(luminanza, luminanza / 2).Fill(UVNeutro);
    }

    /// <summary>BT.709, gamma ridotta, in virgola fissa (8 bit): il bianco dà 235, il nero 16, i grigi crominanza 128.</summary>
    public static byte Luminanza(int r, int g, int b) => (byte)(((47 * r + 157 * g + 16 * b + 128) >> 8) + 16);
    public static byte Cb(int r, int g, int b) => (byte)(((-26 * r - 86 * g + 112 * b + 128) >> 8) + 128);
    public static byte Cr(int r, int g, int b) => (byte)(((112 * r - 102 * g - 10 * b + 128) >> 8) + 128);

    /// <summary>
    /// Converte la parte <paramref name="sorgente"/> di un'immagine BGRA (come la dà Windows) nella parte
    /// <paramref name="destinazione"/> di un fotogramma NV12; fuori dalla destinazione mette il nero.
    /// Se le due parti hanno la stessa misura copia pixel per pixel, altrimenti scala (bilineare).
    /// </summary>
    /// <param name="passo">Byte per riga dell'immagine BGRA (almeno larghezza × 4).</param>
    /// <param name="specchia">Specchia in orizzontale (solo se l'utente lo vuole anche nella webcam).</param>
    public static void BgraInNv12(ReadOnlySpan<byte> bgra, int larghezzaSorgente, int altezzaSorgente, int passo, Riquadro sorgente,
        Span<byte> nv12, int larghezzaDestinazione, int altezzaDestinazione, Riquadro destinazione, bool specchia)
    {
        ControllaNv12(larghezzaDestinazione, altezzaDestinazione, nv12.Length);
        ControllaRiquadroPari(destinazione, larghezzaDestinazione, altezzaDestinazione);
        if (sorgente.X < 0 || sorgente.Y < 0 || sorgente.Larghezza <= 0 || sorgente.Altezza <= 0
            || sorgente.X + sorgente.Larghezza > larghezzaSorgente || sorgente.Y + sorgente.Altezza > altezzaSorgente)
            throw new ArgumentException("La parte da prendere esce dall'immagine", nameof(sorgente));
        if (passo < larghezzaSorgente * 4 || bgra.Length < (long)passo * (altezzaSorgente - 1) + larghezzaSorgente * 4)
            throw new ArgumentException("Immagine BGRA troppo piccola", nameof(bgra));

        // Per ogni colonna e riga della destinazione: i due pixel vicini nella sorgente e il peso (0–256) del secondo.
        var colonne = Campionamento(destinazione.Larghezza, sorgente.X, sorgente.Larghezza, specchia);
        var righe = Campionamento(destinazione.Altezza, sorgente.Y, sorgente.Altezza, false);
        var dritto = sorgente.Larghezza == destinazione.Larghezza && sorgente.Altezza == destinazione.Altezza;

        fixed (byte* s = bgra)
        fixed (byte* d = nv12)
        {
            var parametri = new Parametri
            {
                Sorgente = (nint)s, Passo = passo, Destinazione = (nint)d,
                Larghezza = larghezzaDestinazione, Altezza = altezzaDestinazione, Riquadro = destinazione,
                Colonne = colonne, Righe = righe, Dritto = dritto,
            };
            var righeCrominanza = altezzaDestinazione / 2;
            if ((long)larghezzaDestinazione * altezzaDestinazione >= 640 * 360)
                Parallel.For(0, righeCrominanza, riga => ConvertiCoppiaDiRighe(parametri, riga));
            else
                for (var riga = 0; riga < righeCrominanza; riga++) ConvertiCoppiaDiRighe(parametri, riga);
        }
    }

    private sealed class Parametri
    {
        public nint Sorgente;
        public int Passo;
        public nint Destinazione;
        public int Larghezza;
        public int Altezza;
        public Riquadro Riquadro;
        public required Campione[] Colonne;
        public required Campione[] Righe;
        public bool Dritto;
    }

    private readonly record struct Campione(int Primo, int Secondo, int Peso);

    private static Campione[] Campionamento(int misuraDestinazione, int inizioSorgente, int misuraSorgente, bool rovescia)
    {
        var campioni = new Campione[misuraDestinazione];
        var rapporto = (double)misuraSorgente / misuraDestinazione;
        for (var i = 0; i < misuraDestinazione; i++)
        {
            var posizione = rovescia ? misuraDestinazione - 1 - i : i;
            int primo, secondo, peso;
            if (misuraSorgente == misuraDestinazione)
            {
                primo = secondo = posizione;
                peso = 0;
            }
            else
            {
                var centro = Math.Clamp((posizione + 0.5) * rapporto - 0.5, 0, misuraSorgente - 1);
                primo = (int)centro;
                secondo = Math.Min(primo + 1, misuraSorgente - 1);
                peso = (int)Math.Round((centro - primo) * 256);
            }
            campioni[i] = new Campione(inizioSorgente + primo, inizioSorgente + secondo, peso);
        }
        return campioni;
    }

    private static void ConvertiCoppiaDiRighe(Parametri p, int rigaCrominanza)
    {
        var d = (byte*)p.Destinazione;
        var y0 = rigaCrominanza * 2;
        var riga0 = d + (long)y0 * p.Larghezza;
        var riga1 = riga0 + p.Larghezza;
        var rigaUV = d + (long)p.Larghezza * p.Altezza + (long)rigaCrominanza * p.Larghezza;
        var r = p.Riquadro;
        if (y0 < r.Y || y0 >= r.Y + r.Altezza)
        {
            new Span<byte>(riga0, p.Larghezza * 2).Fill(YNero);
            new Span<byte>(rigaUV, p.Larghezza).Fill(UVNeutro);
            return;
        }
        // Bande nere a sinistra e a destra.
        new Span<byte>(riga0, r.X).Fill(YNero);
        new Span<byte>(riga1, r.X).Fill(YNero);
        new Span<byte>(rigaUV, r.X).Fill(UVNeutro);
        var fine = r.X + r.Larghezza;
        new Span<byte>(riga0 + fine, p.Larghezza - fine).Fill(YNero);
        new Span<byte>(riga1 + fine, p.Larghezza - fine).Fill(YNero);
        new Span<byte>(rigaUV + fine, p.Larghezza - fine).Fill(UVNeutro);

        var campioneRiga0 = p.Righe[y0 - r.Y];
        var campioneRiga1 = p.Righe[y0 + 1 - r.Y];
        for (var x = 0; x < r.Larghezza; x += 2)
        {
            Pixel(p, p.Colonne[x], campioneRiga0, out var r00, out var g00, out var b00);
            Pixel(p, p.Colonne[x + 1], campioneRiga0, out var r01, out var g01, out var b01);
            Pixel(p, p.Colonne[x], campioneRiga1, out var r10, out var g10, out var b10);
            Pixel(p, p.Colonne[x + 1], campioneRiga1, out var r11, out var g11, out var b11);
            riga0[r.X + x] = Luminanza(r00, g00, b00);
            riga0[r.X + x + 1] = Luminanza(r01, g01, b01);
            riga1[r.X + x] = Luminanza(r10, g10, b10);
            riga1[r.X + x + 1] = Luminanza(r11, g11, b11);
            var rm = (r00 + r01 + r10 + r11 + 2) >> 2;
            var gm = (g00 + g01 + g10 + g11 + 2) >> 2;
            var bm = (b00 + b01 + b10 + b11 + 2) >> 2;
            rigaUV[r.X + x] = Cb(rm, gm, bm);
            rigaUV[r.X + x + 1] = Cr(rm, gm, bm);
        }
    }

    private static void Pixel(Parametri p, Campione colonna, Campione riga, out int rosso, out int verde, out int blu)
    {
        var s = (byte*)p.Sorgente;
        if (p.Dritto)
        {
            var px = s + (long)riga.Primo * p.Passo + colonna.Primo * 4;
            blu = px[0]; verde = px[1]; rosso = px[2];
            return;
        }
        var a = s + (long)riga.Primo * p.Passo + colonna.Primo * 4;
        var b = s + (long)riga.Primo * p.Passo + colonna.Secondo * 4;
        var c = s + (long)riga.Secondo * p.Passo + colonna.Primo * 4;
        var e = s + (long)riga.Secondo * p.Passo + colonna.Secondo * 4;
        int px2 = colonna.Peso, py = riga.Peso;
        blu = Mescola(a[0], b[0], c[0], e[0], px2, py);
        verde = Mescola(a[1], b[1], c[1], e[1], px2, py);
        rosso = Mescola(a[2], b[2], c[2], e[2], px2, py);
    }

    private static int Mescola(int a, int b, int c, int d, int pesoX, int pesoY)
    {
        var sopra = a * (256 - pesoX) + b * pesoX;
        var sotto = c * (256 - pesoX) + d * pesoX;
        return (sopra * (256 - pesoY) + sotto * pesoY + 32768) >> 16;
    }

    /// <summary>
    /// Porta un fotogramma NV12 a un'altra misura (bilineare), con le bande nere se le proporzioni cambiano.
    /// Serve alla sorgente quando l'app ha appena cambiato formato e c'è ancora un fotogramma della misura di prima.
    /// </summary>
    public static void ScalaNv12(ReadOnlySpan<byte> sorgente, int larghezzaSorgente, int altezzaSorgente,
        Span<byte> destinazione, int larghezzaDestinazione, int altezzaDestinazione)
    {
        ControllaNv12(larghezzaSorgente, altezzaSorgente, sorgente.Length);
        ControllaNv12(larghezzaDestinazione, altezzaDestinazione, destinazione.Length);
        var byteDestinazione = FormatoWebcam.DimensioneNv12(larghezzaDestinazione, altezzaDestinazione);
        if (larghezzaSorgente == larghezzaDestinazione && altezzaSorgente == altezzaDestinazione)
        {
            sorgente[..byteDestinazione].CopyTo(destinazione);
            return;
        }
        RiempiNero(destinazione, larghezzaDestinazione, altezzaDestinazione);
        var (_, r) = Inquadrature.Calcola(larghezzaSorgente, altezzaSorgente, larghezzaDestinazione, altezzaDestinazione, Inquadratura.Adatta);

        // Luminanza: un piano, un byte per pixel.
        var colonne = Campionamento(r.Larghezza, 0, larghezzaSorgente, false);
        var righe = Campionamento(r.Altezza, 0, altezzaSorgente, false);
        for (var y = 0; y < r.Altezza; y++)
        {
            var rs0 = sorgente.Slice(righe[y].Primo * larghezzaSorgente, larghezzaSorgente);
            var rs1 = sorgente.Slice(righe[y].Secondo * larghezzaSorgente, larghezzaSorgente);
            var rd = destinazione.Slice((r.Y + y) * larghezzaDestinazione + r.X, r.Larghezza);
            for (var x = 0; x < r.Larghezza; x++)
            {
                var c = colonne[x];
                rd[x] = (byte)Mescola(rs0[c.Primo], rs0[c.Secondo], rs1[c.Primo], rs1[c.Secondo], c.Peso, righe[y].Peso);
            }
        }

        // Crominanza: metà misura, U e V alternati.
        var luminanzaSorgente = larghezzaSorgente * altezzaSorgente;
        var luminanzaDestinazione = larghezzaDestinazione * altezzaDestinazione;
        var colonneUV = Campionamento(r.Larghezza / 2, 0, larghezzaSorgente / 2, false);
        var righeUV = Campionamento(r.Altezza / 2, 0, altezzaSorgente / 2, false);
        for (var y = 0; y < r.Altezza / 2; y++)
        {
            var rs0 = sorgente.Slice(luminanzaSorgente + righeUV[y].Primo * larghezzaSorgente, larghezzaSorgente);
            var rs1 = sorgente.Slice(luminanzaSorgente + righeUV[y].Secondo * larghezzaSorgente, larghezzaSorgente);
            var rd = destinazione.Slice(luminanzaDestinazione + (r.Y / 2 + y) * larghezzaDestinazione + r.X, r.Larghezza);
            for (var x = 0; x < r.Larghezza / 2; x++)
            {
                var c = colonneUV[x];
                for (var k = 0; k < 2; k++)
                {
                    rd[x * 2 + k] = (byte)Mescola(rs0[c.Primo * 2 + k], rs0[c.Secondo * 2 + k],
                        rs1[c.Primo * 2 + k], rs1[c.Secondo * 2 + k], c.Peso, righeUV[y].Peso);
                }
            }
        }
    }

    private static void ControllaNv12(int larghezza, int altezza, int byteDisponibili)
    {
        if (larghezza <= 0 || altezza <= 0 || larghezza % 2 != 0 || altezza % 2 != 0)
            throw new ArgumentException($"NV12 vuole misure pari: {larghezza}×{altezza}");
        if (byteDisponibili < FormatoWebcam.DimensioneNv12(larghezza, altezza))
            throw new ArgumentException("Spazio NV12 troppo piccolo");
    }

    private static void ControllaRiquadroPari(Riquadro r, int larghezza, int altezza)
    {
        if (r.X < 0 || r.Y < 0 || r.Larghezza <= 0 || r.Altezza <= 0 || r.X + r.Larghezza > larghezza || r.Y + r.Altezza > altezza
            || ((r.X | r.Y | r.Larghezza | r.Altezza) & 1) != 0)
            throw new ArgumentException("Riquadro di destinazione non valido (deve stare dentro ed essere pari)");
    }
}
