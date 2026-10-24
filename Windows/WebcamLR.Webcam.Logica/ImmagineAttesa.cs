namespace WebcamLR.Webcam;

/// <summary>Un colore della famiglia WebcamLR.</summary>
public readonly record struct ColoreStile(byte Rosso, byte Verde, byte Blu)
{
    public string Esadecimale => $"#{Rosso:X2}{Verde:X2}{Blu:X2}";
}

/// <summary>
/// I colori di Windows/WebcamLR.App/App.xaml che servono alla sorgente, che non vede l'app.
/// Un test controlla che restino uguali a quelli di App.xaml.
/// </summary>
public static class ColoriStile
{
    public static readonly ColoreStile Fondo = new(0x12, 0x18, 0x17);
    public static readonly ColoreStile Scheda = new(0x1F, 0x28, 0x26);
    public static readonly ColoreStile Linea = new(0x2A, 0x34, 0x31);
    public static readonly ColoreStile Testo = new(0xE3, 0xE8, 0xE5);
    public static readonly ColoreStile TestoSecondario = new(0xB3, 0xBD, 0xB9);
    public static readonly ColoreStile Ciano = new(0x6C, 0xBC, 0xC4);
}

/// <summary>
/// L'immagine che la webcam mostra quando l'app non manda fotogrammi da più di un secondo (telefono scollegato,
/// app chiusa): «WebcamLR · in attesa del telefono». Così Zoom, Teams e gli altri non si bloccano e non danno errore.
/// Scritta con un carattere a punti 5×7 disegnato qui: la sorgente gira dentro un servizio di Windows, senza caratteri
/// né librerie grafiche.
/// </summary>
public static class ImmagineAttesa
{
    public const string Titolo = "WebcamLR";
    public const string Messaggio = "in attesa del telefono";
    public const string Suggerimento = "Apri WebcamLR sul telefono";

    /// <summary>Un fotogramma NV12 pronto, della misura chiesta.</summary>
    public static byte[] CreaNv12(int larghezza, int altezza)
    {
        var bgra = CreaBgra(larghezza, altezza);
        var nv12 = new byte[FormatoWebcam.DimensioneNv12(larghezza, altezza)];
        var tutto = Riquadro.Intero(larghezza, altezza);
        ConversioneVideo.BgraInNv12(bgra, larghezza, altezza, larghezza * 4, tutto, nv12, larghezza, altezza, tutto, specchia: false);
        return nv12;
    }

    /// <summary>La stessa immagine in BGRA (per i test e per chi la volesse vedere).</summary>
    public static byte[] CreaBgra(int larghezza, int altezza)
    {
        var bgra = new byte[larghezza * altezza * 4];
        Rettangolo(bgra, larghezza, altezza, 0, 0, larghezza, altezza, ColoriStile.Fondo);

        // Misure pensate per 1080 righe, in proporzione per le altre.
        var unita = altezza / 1080.0;
        var puntoTitolo = Math.Max(2, (int)Math.Round(14 * unita));
        var puntoMessaggio = Math.Max(1, (int)Math.Round(7 * unita));
        var puntoSuggerimento = Math.Max(1, (int)Math.Round(4 * unita));

        var altezzaTitolo = CarattereAPunti.Altezza * puntoTitolo;
        var spazio = (int)Math.Round(40 * unita);
        var totale = altezzaTitolo + spazio * 2 + Math.Max(2, puntoMessaggio / 2 * 2) + CarattereAPunti.Altezza * puntoMessaggio + spazio * 2 + CarattereAPunti.Altezza * puntoSuggerimento;
        var y = (altezza - totale) / 2;

        // «WebcamLR» con «LR» in ciano, come nel marchio.
        var larghezzaTitolo = CarattereAPunti.Larghezza(Titolo, puntoTitolo);
        var x = (larghezza - larghezzaTitolo) / 2;
        x = Scrivi(bgra, larghezza, altezza, "Webcam", x, y, puntoTitolo, ColoriStile.Testo);
        Scrivi(bgra, larghezza, altezza, "LR", x, y, puntoTitolo, ColoriStile.Ciano);
        y += altezzaTitolo + spazio;

        // Una lineetta ciano tra il titolo e il messaggio.
        var lineetta = (int)Math.Round(120 * unita);
        var spessore = Math.Max(2, puntoMessaggio / 2 * 2);
        Rettangolo(bgra, larghezza, altezza, (larghezza - lineetta) / 2, y, lineetta, spessore, ColoriStile.Ciano);
        y += spessore + spazio;

        Scrivi(bgra, larghezza, altezza, Messaggio, (larghezza - CarattereAPunti.Larghezza(Messaggio, puntoMessaggio)) / 2, y, puntoMessaggio, ColoriStile.Testo);
        y += CarattereAPunti.Altezza * puntoMessaggio + spazio * 2;
        Scrivi(bgra, larghezza, altezza, Suggerimento, (larghezza - CarattereAPunti.Larghezza(Suggerimento, puntoSuggerimento)) / 2, y, puntoSuggerimento, ColoriStile.TestoSecondario);
        return bgra;
    }

    /// <summary>Scrive il testo e restituisce la x dopo l'ultimo carattere.</summary>
    private static int Scrivi(byte[] bgra, int larghezza, int altezza, string testo, int x, int y, int punto, ColoreStile colore)
    {
        foreach (var carattere in testo)
        {
            var disegno = CarattereAPunti.Disegno(carattere);
            for (var riga = 0; riga < disegno.Length; riga++)
            {
                for (var colonna = 0; colonna < CarattereAPunti.LarghezzaCarattere; colonna++)
                {
                    if (disegno[riga][colonna] == '#')
                        Rettangolo(bgra, larghezza, altezza, x + colonna * punto, y + riga * punto, punto, punto, colore);
                }
            }
            x += (CarattereAPunti.LarghezzaCarattere + 1) * punto;
        }
        return x;
    }

    private static void Rettangolo(byte[] bgra, int larghezza, int altezza, int x, int y, int l, int a, ColoreStile colore)
    {
        var x0 = Math.Max(0, x);
        var y0 = Math.Max(0, y);
        var x1 = Math.Min(larghezza, x + l);
        var y1 = Math.Min(altezza, y + a);
        for (var riga = y0; riga < y1; riga++)
        {
            for (var colonna = x0; colonna < x1; colonna++)
            {
                var i = (riga * larghezza + colonna) * 4;
                bgra[i] = colore.Blu;
                bgra[i + 1] = colore.Verde;
                bgra[i + 2] = colore.Rosso;
                bgra[i + 3] = 255;
            }
        }
    }
}

/// <summary>Carattere a punti: 5 colonne, 7 righe sopra la linea di base e 2 sotto (per la «p»).</summary>
public static class CarattereAPunti
{
    public const int LarghezzaCarattere = 5;
    /// <summary>Righe di un carattere, compresa la parte sotto la linea di base.</summary>
    public const int Altezza = 9;

    public static int Larghezza(string testo, int punto) =>
        testo.Length == 0 ? 0 : (testo.Length * (LarghezzaCarattere + 1) - 1) * punto;

    public static bool Conosciuto(char carattere) => Disegni.ContainsKey(carattere);

    /// <summary>Il disegno del carattere; uno sconosciuto resta vuoto, come lo spazio.</summary>
    public static string[] Disegno(char carattere) => Disegni.TryGetValue(carattere, out var disegno) ? disegno : Disegni[' '];

    private static readonly Dictionary<char, string[]> Disegni = new()
    {
        [' '] = [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        ['·'] = [".....", ".....", ".....", "..#..", ".....", ".....", "....."],
        ['\''] = ["..#..", "..#..", ".#...", ".....", ".....", ".....", "....."],
        ['A'] = [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        ['C'] = [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        ['I'] = [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        ['L'] = ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        ['P'] = ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        ['R'] = ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        ['W'] = ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
        ['a'] = [".....", ".....", ".###.", "....#", ".####", "#...#", ".####"],
        ['b'] = ["#....", "#....", "####.", "#...#", "#...#", "#...#", "####."],
        ['c'] = [".....", ".....", ".###.", "#....", "#....", "#....", ".###."],
        ['d'] = ["....#", "....#", ".####", "#...#", "#...#", "#...#", ".####"],
        ['e'] = [".....", ".....", ".###.", "#...#", "#####", "#....", ".###."],
        ['f'] = ["..##.", ".#...", "####.", ".#...", ".#...", ".#...", ".#..."],
        ['h'] = ["#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#"],
        ['i'] = ["..#..", ".....", ".##..", "..#..", "..#..", "..#..", ".###."],
        ['l'] = [".##..", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        ['m'] = [".....", ".....", "##.#.", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
        ['n'] = [".....", ".....", "####.", "#...#", "#...#", "#...#", "#...#"],
        ['o'] = [".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###."],
        ['p'] = [".....", ".....", "####.", "#...#", "#...#", "#...#", "####.", "#....", "#...."],
        ['r'] = [".....", ".....", "#.##.", "##..#", "#....", "#....", "#...."],
        ['s'] = [".....", ".....", ".####", "#....", ".###.", "....#", "####."],
        ['t'] = [".#...", ".#...", "####.", ".#...", ".#...", ".#..#", "..##."],
        ['u'] = [".....", ".....", "#...#", "#...#", "#...#", "#...#", ".####"],
    };
}
