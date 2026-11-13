namespace WebcamLR.Collaudo;

/// <summary>
/// L'immagine sintetica del telefono finto, disegnata direttamente in YUV 4:2:0: sfondo in sfumatura che cambia colore,
/// una barra che scorre, un cerchio che rimbalza e un orologio grande con i centesimi, così in ogni schermata si vede che il
/// video scorre e da quando. Sotto: nome del telefono, numero del fotogramma, misura e i comandi ricevuti dal computer.
/// Testo con un carattere 5×7 fatto a mano (solo maiuscole, cifre e qualche segno).
/// </summary>
public sealed class Disegno
{
    public int Larghezza { get; }
    public int Altezza { get; }
    public byte[] Y { get; }
    public byte[] Cb { get; }
    public byte[] Cr { get; }

    public Disegno(int larghezza, int altezza)
    {
        Larghezza = larghezza;
        Altezza = altezza;
        Y = new byte[larghezza * altezza];
        Cb = new byte[larghezza / 2 * (altezza / 2)];
        Cr = new byte[larghezza / 2 * (altezza / 2)];
    }

    /// <summary>Disegna il fotogramma <paramref name="numero"/>; <paramref name="righe"/> vanno sotto l'orologio.</summary>
    public void Disegna(long numero, DateTime ora, double secondi, IReadOnlyList<string> righe, bool specchia)
    {
        // Sfondo: luminanza in sfumatura verticale, colore che gira lentamente (un giro ogni 20 s).
        var angolo = secondi * Math.PI * 2 / 20;
        var (u0, v0) = ((byte)(128 + 40 * Math.Cos(angolo)), (byte)(128 + 40 * Math.Sin(angolo)));
        for (var r = 0; r < Altezza; r++)
            Array.Fill(Y, (byte)(40 + 60 * r / Altezza), r * Larghezza, Larghezza);
        Array.Fill(Cb, u0);
        Array.Fill(Cr, v0);

        // Una barra verticale chiara che attraversa lo schermo in 4 secondi.
        var larghezzaBarra = Math.Max(8, Larghezza / 40);
        var xBarra = (int)(secondi / 4 % 1 * (Larghezza + larghezzaBarra)) - larghezzaBarra;
        Rettangolo(xBarra, 0, larghezzaBarra, Altezza, 200, 128, 128);

        // Un cerchio corallo che rimbalza.
        var raggio = Math.Max(10, Altezza / 12);
        var xc = (int)(raggio + Math.Abs(secondi * 0.37 % 2 - 1) * (Larghezza - 2 * raggio));
        var yc = (int)(raggio + Math.Abs(secondi * 0.53 % 2 - 1) * (Altezza - 2 * raggio));
        Cerchio(xc, yc, raggio, 150, 90, 200);

        // L'orologio, grande al centro, su una fascia scura.
        var orologio = ora.ToString("HH:mm:ss.ff");
        var scala = Math.Max(2, Larghezza / (orologio.Length * 6) * 7 / 10);
        var larghezzaTesto = orologio.Length * 6 * scala;
        var yTesto = Altezza / 2 - 7 * scala / 2;
        Rettangolo(0, yTesto - scala * 2, Larghezza, 11 * scala, 16, 128, 128);
        Testo(orologio, (Larghezza - larghezzaTesto) / 2, yTesto, scala, 235);

        // Le righe di informazioni, più piccole.
        var piccola = Math.Max(1, scala / 3);
        var y = yTesto + 11 * scala;
        foreach (var riga in righe.Prepend($"FOTOGRAMMA {numero}"))
        {
            if (y + 8 * piccola > Altezza) break;
            Rettangolo(scala, y - piccola, riga.Length * 6 * piccola + 2 * piccola, 9 * piccola, 16, 128, 128);
            Testo(riga, scala + piccola, y, piccola, 235);
            y += 10 * piccola;
        }
        if (specchia) Specchia();
    }

    private void Specchia()
    {
        foreach (var (piano, larghezza) in new[] { (Y, Larghezza), (Cb, Larghezza / 2), (Cr, Larghezza / 2) })
            for (var r = 0; r < piano.Length / larghezza; r++) Array.Reverse(piano, r * larghezza, larghezza);
    }

    private void Rettangolo(int x, int y, int l, int a, byte luce, byte u, byte v)
    {
        var x0 = Math.Max(0, x);
        var x1 = Math.Min(Larghezza, x + l);
        var y0 = Math.Max(0, y);
        var y1 = Math.Min(Altezza, y + a);
        if (x0 >= x1 || y0 >= y1) return;
        for (var r = y0; r < y1; r++) Array.Fill(Y, luce, r * Larghezza + x0, x1 - x0);
        for (var r = y0 / 2; r < (y1 + 1) / 2 && r < Altezza / 2; r++)
        {
            var inizio = r * (Larghezza / 2) + x0 / 2;
            var quanti = Math.Min((x1 + 1) / 2, Larghezza / 2) - x0 / 2;
            Array.Fill(Cb, u, inizio, quanti);
            Array.Fill(Cr, v, inizio, quanti);
        }
    }

    private void Cerchio(int xc, int yc, int raggio, byte luce, byte u, byte v)
    {
        for (var dy = -raggio; dy <= raggio; dy++)
        {
            var mezza = (int)Math.Sqrt(raggio * raggio - dy * dy);
            Rettangolo(xc - mezza, yc + dy, 2 * mezza, 1, luce, u, v);
        }
    }

    private void Testo(string testo, int x, int y, int scala, byte luce)
    {
        foreach (var carattere in testo.ToUpperInvariant())
        {
            if (Caratteri.TryGetValue(carattere, out var righe))
                for (var r = 0; r < 7; r++)
                for (var c = 0; c < 5; c++)
                    if ((righe[r] >> (4 - c) & 1) == 1)
                        Rettangolo(x + c * scala, y + r * scala, scala, scala, luce, 128, 128);
            x += 6 * scala;
        }
    }

    /// <summary>Carattere 5×7: sette righe, cinque bit ciascuna (il bit 4 è a sinistra).</summary>
    private static readonly Dictionary<char, byte[]> Caratteri = new()
    {
        ['0'] = [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
        ['1'] = [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        ['2'] = [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
        ['3'] = [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
        ['4'] = [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
        ['5'] = [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        ['6'] = [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
        ['7'] = [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        ['8'] = [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
        ['9'] = [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        ['A'] = [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        ['B'] = [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        ['C'] = [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
        ['D'] = [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
        ['E'] = [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
        ['F'] = [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        ['G'] = [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F],
        ['H'] = [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        ['I'] = [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
        ['J'] = [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
        ['K'] = [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
        ['L'] = [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        ['M'] = [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
        ['N'] = [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
        ['O'] = [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        ['P'] = [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        ['Q'] = [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
        ['R'] = [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        ['S'] = [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E],
        ['T'] = [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        ['U'] = [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
        ['V'] = [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        ['W'] = [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A],
        ['X'] = [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        ['Y'] = [0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04],
        ['Z'] = [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        ['À'] = [0x08, 0x04, 0x0E, 0x11, 0x1F, 0x11, 0x11],
        ['È'] = [0x08, 0x04, 0x1F, 0x10, 0x1E, 0x10, 0x1F],
        ['É'] = [0x02, 0x04, 0x1F, 0x10, 0x1E, 0x10, 0x1F],
        ['Ì'] = [0x08, 0x04, 0x0E, 0x04, 0x04, 0x04, 0x0E],
        ['Ò'] = [0x08, 0x04, 0x0E, 0x11, 0x11, 0x11, 0x0E],
        ['Ù'] = [0x08, 0x04, 0x11, 0x11, 0x11, 0x11, 0x0E],
        [':'] = [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
        ['.'] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
        [','] = [0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08],
        ['-'] = [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
        ['+'] = [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
        ['/'] = [0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10],
        ['×'] = [0x00, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x00],
        ['%'] = [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03],
        ['('] = [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02],
        [')'] = [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08],
        ['\''] = [0x04, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
        ['«'] = [0x00, 0x05, 0x0A, 0x14, 0x0A, 0x05, 0x00],
        ['»'] = [0x00, 0x14, 0x0A, 0x05, 0x0A, 0x14, 0x00],
        ['·'] = [0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00, 0x00],
        ['='] = [0x00, 0x00, 0x1F, 0x00, 0x1F, 0x00, 0x00],
        ['_'] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F],
        ['?'] = [0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04],
        ['!'] = [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
    };
}
