namespace WebcamLR.Webcam;

/// <summary>
/// Le operazioni sulle immagini che servono alla schermata di attesa, tutte in NV12 (il formato della webcam) o su
/// maschere di opacità: ricampionare (anche tagliando per riempire), sfocare, mescolare due immagini, scrivere un
/// colore attraverso una maschera. Codice semplice e senza eccezioni nascoste: gira dentro Frame Server e dentro le app.
/// </summary>
public static unsafe class ImmaginiNv12
{
    /// <summary>
    /// Ricampiona la parte (<paramref name="x"/>, <paramref name="y"/>, <paramref name="l"/>, <paramref name="a"/>, in
    /// pixel della sorgente, anche frazionari) di un piano con <paramref name="canali"/> byte per pixel (1 per la
    /// luminanza e le maschere, 2 per la crominanza U/V di NV12) in tutto il piano di destinazione: bilineare quando
    /// ingrandisce, media dei pixel coperti quando rimpicciolisce (testi nitidi, niente scalini né sfarfallio).
    /// </summary>
    /// <param name="passoSorgente">Byte per riga della sorgente.</param>
    /// <param name="passoDestinazione">Byte per riga della destinazione.</param>
    public static void Ricampiona(ReadOnlySpan<byte> sorgente, int larghezzaSorgente, int altezzaSorgente, int passoSorgente, int canali,
        double x, double y, double l, double a, Span<byte> destinazione, int larghezzaDestinazione, int altezzaDestinazione, int passoDestinazione)
    {
        if (larghezzaSorgente <= 0 || altezzaSorgente <= 0 || larghezzaDestinazione <= 0 || altezzaDestinazione <= 0 || l <= 0 || a <= 0)
            return;
        var colonne = Pesi(larghezzaDestinazione, x, l, larghezzaSorgente);
        var righe = Pesi(altezzaDestinazione, y, a, altezzaSorgente);

        // Solo le righe della sorgente che servono, già ricampionate in orizzontale.
        var primaRiga = righe.Min(p => p.Inizio);
        var ultimaRiga = righe.Max(p => p.Inizio + p.Pesi.Length - 1);
        var larghezzaRiga = larghezzaDestinazione * canali;
        var intermedio = new float[(ultimaRiga - primaRiga + 1) * larghezzaRiga];
        for (var r = primaRiga; r <= ultimaRiga; r++)
        {
            var riga = sorgente.Slice(r * passoSorgente, larghezzaSorgente * canali);
            var uscita = intermedio.AsSpan((r - primaRiga) * larghezzaRiga, larghezzaRiga);
            for (var i = 0; i < larghezzaDestinazione; i++)
            {
                var p = colonne[i];
                for (var c = 0; c < canali; c++)
                {
                    var somma = 0f;
                    for (var k = 0; k < p.Pesi.Length; k++) somma += riga[(p.Inizio + k) * canali + c] * p.Pesi[k];
                    uscita[i * canali + c] = somma;
                }
            }
        }
        for (var j = 0; j < altezzaDestinazione; j++)
        {
            var p = righe[j];
            var uscita = destinazione.Slice(j * passoDestinazione, larghezzaRiga);
            for (var i = 0; i < larghezzaRiga; i++)
            {
                var somma = 0f;
                for (var k = 0; k < p.Pesi.Length; k++) somma += intermedio[(p.Inizio + k - primaRiga) * larghezzaRiga + i] * p.Pesi[k];
                uscita[i] = Byte(somma);
            }
        }
    }

    /// <summary>Un pixel della destinazione: dal pixel <see cref="Inizio"/> della sorgente, con questi pesi (somma 1).</summary>
    private readonly record struct Peso(int Inizio, float[] Pesi);

    private static Peso[] Pesi(int numero, double inizio, double lunghezza, int limite)
    {
        var scala = lunghezza / numero;
        var pesi = new Peso[numero];
        for (var i = 0; i < numero; i++)
        {
            float[] valori;
            int primo;
            if (scala > 1)
            {
                // Rimpicciolire: ogni pixel della sorgente pesa quanto la parte coperta dal pixel di destinazione.
                var da = inizio + i * scala;
                var a = da + scala;
                primo = Math.Clamp((int)Math.Floor(da), 0, limite - 1);
                var ultimo = Math.Clamp((int)Math.Ceiling(a) - 1, primo, limite - 1);
                valori = new float[ultimo - primo + 1];
                for (var k = primo; k <= ultimo; k++)
                    valori[k - primo] = (float)Math.Max(0, Math.Min(a, k + 1) - Math.Max(da, k));
            }
            else
            {
                // Ingrandire: bilineare tra i due pixel più vicini.
                var centro = Math.Clamp(inizio + (i + 0.5) * scala - 0.5, 0, limite - 1);
                primo = Math.Min((int)Math.Floor(centro), limite - 1);
                var frazione = centro - primo;
                valori = primo + 1 < limite ? [(float)(1 - frazione), (float)frazione] : [1f];
            }
            var totale = valori.Sum();
            if (totale <= 0)
            {
                Array.Clear(valori);
                valori[0] = 1;
            }
            else
            {
                for (var k = 0; k < valori.Length; k++) valori[k] /= totale;
            }
            pesi[i] = new Peso(primo, valori);
        }
        return pesi;
    }

    /// <summary>
    /// Un fotogramma NV12 che riempie tutta la destinazione mantenendo le proporzioni: i bordi in più restano fuori,
    /// come «Riempi» (l'immagine personale, lo sfondo sfocato).
    /// </summary>
    public static void Riempi(ReadOnlySpan<byte> sorgente, int larghezzaSorgente, int altezzaSorgente,
        Span<byte> destinazione, int larghezzaDestinazione, int altezzaDestinazione)
    {
        var scala = Math.Max((double)larghezzaDestinazione / larghezzaSorgente, (double)altezzaDestinazione / altezzaSorgente);
        var l = larghezzaDestinazione / scala;
        var a = altezzaDestinazione / scala;
        var x = (larghezzaSorgente - l) / 2;
        var y = (altezzaSorgente - a) / 2;
        var luminanzaS = larghezzaSorgente * altezzaSorgente;
        var luminanzaD = larghezzaDestinazione * altezzaDestinazione;
        Ricampiona(sorgente, larghezzaSorgente, altezzaSorgente, larghezzaSorgente, 1, x, y, l, a,
            destinazione, larghezzaDestinazione, altezzaDestinazione, larghezzaDestinazione);
        Ricampiona(sorgente[luminanzaS..], larghezzaSorgente / 2, altezzaSorgente / 2, larghezzaSorgente, 2, x / 2, y / 2, l / 2, a / 2,
            destinazione[luminanzaD..], larghezzaDestinazione / 2, altezzaDestinazione / 2, larghezzaDestinazione);
    }

    /// <summary>Larghezza dello sfondo sfocato: tanto è sfocato, e si ingrandisce una volta sola per misura.</summary>
    public const int LarghezzaSfocata = 192;

    /// <summary>
    /// L'ultima immagine del telefono rimpicciolita, sfocata e scurita: lo sfondo dello stile «sfocata». Come sul Mac
    /// (sfocatura gaussiana di 12 su 480 pixel, luminosità −0,22, saturazione 0,7), qui con tre passate di media mobile.
    /// </summary>
    public static (byte[] Nv12, int Larghezza, int Altezza) Sfoca(ReadOnlySpan<byte> nv12, int larghezza, int altezza)
    {
        var l = LarghezzaSfocata;
        var a = Math.Max(2, (int)Math.Round((double)altezza * l / larghezza / 2) * 2);
        var piccola = new byte[FormatoWebcam.DimensioneNv12(l, a)];
        var luminanza = larghezza * altezza;
        Ricampiona(nv12, larghezza, altezza, larghezza, 1, 0, 0, larghezza, altezza, piccola, l, a, l);
        Ricampiona(nv12[luminanza..], larghezza / 2, altezza / 2, larghezza, 2, 0, 0, larghezza / 2.0, altezza / 2.0,
            piccola.AsSpan(l * a), l / 2, a / 2, l);
        for (var passata = 0; passata < 3; passata++)
        {
            MediaMobile(piccola.AsSpan(0, l * a), l, a, 1, 4);
            MediaMobile(piccola.AsSpan(l * a), l / 2, a / 2, 2, 2);
        }
        for (var i = 0; i < l * a; i++) piccola[i] = (byte)Math.Max(ConversioneVideo.YNero, piccola[i] - 48);
        for (var i = l * a; i < piccola.Length; i++) piccola[i] = (byte)(128 + (piccola[i] - 128) * 7 / 10);
        return (piccola, l, a);
    }

    /// <summary>Media mobile di raggio dato, prima per righe poi per colonne, con i bordi ripetuti.</summary>
    private static void MediaMobile(Span<byte> piano, int larghezza, int altezza, int canali, int raggio)
    {
        var lato = 2 * raggio + 1;
        var riga = new byte[Math.Max(larghezza, altezza) * canali];
        for (var y = 0; y < altezza; y++)
        {
            piano.Slice(y * larghezza * canali, larghezza * canali).CopyTo(riga);
            for (var c = 0; c < canali; c++)
            {
                for (var x = 0; x < larghezza; x++)
                {
                    var somma = 0;
                    for (var k = -raggio; k <= raggio; k++) somma += riga[Math.Clamp(x + k, 0, larghezza - 1) * canali + c];
                    piano[(y * larghezza + x) * canali + c] = (byte)((somma + lato / 2) / lato);
                }
            }
        }
        for (var x = 0; x < larghezza; x++)
        {
            for (var c = 0; c < canali; c++)
            {
                for (var y = 0; y < altezza; y++) riga[y] = piano[(y * larghezza + x) * canali + c];
                for (var y = 0; y < altezza; y++)
                {
                    var somma = 0;
                    for (var k = -raggio; k <= raggio; k++) somma += riga[Math.Clamp(y + k, 0, altezza - 1)];
                    piano[(y * larghezza + x) * canali + c] = (byte)((somma + lato / 2) / lato);
                }
            }
        }
    }

    /// <summary>
    /// <paramref name="sopra"/> su <paramref name="sotto"/> con l'opacità data (0–256), byte per byte: vale per
    /// luminanza e crominanza insieme, perché NV12 è una trasformazione lineare dei colori.
    /// </summary>
    public static void Mescola(ReadOnlySpan<byte> sotto, ReadOnlySpan<byte> sopra, Span<byte> uscita, int opacita256)
    {
        var p = Math.Clamp(opacita256, 0, 256);
        var q = 256 - p;
        var n = Math.Min(uscita.Length, Math.Min(sotto.Length, sopra.Length));
        fixed (byte* s = sotto, o = sopra, u = uscita)
        {
            for (var i = 0; i < n; i++) u[i] = (byte)((s[i] * q + o[i] * p + 128) >> 8);
        }
    }

    /// <summary>
    /// Scrive un colore attraverso una maschera di opacità nel fotogramma NV12, con l'angolo in alto a sinistra in
    /// (<paramref name="x0"/>, <paramref name="y0"/>). Le parti fuori dal fotogramma si tagliano.
    /// </summary>
    public static void Componi(Span<byte> nv12, int larghezza, int altezza, ReadOnlySpan<byte> maschera, int larghezzaMaschera,
        int altezzaMaschera, int x0, int y0, ColoreStile colore)
    {
        int yc = ConversioneVideo.Luminanza(colore.Rosso, colore.Verde, colore.Blu);
        int uc = ConversioneVideo.Cb(colore.Rosso, colore.Verde, colore.Blu);
        int vc = ConversioneVideo.Cr(colore.Rosso, colore.Verde, colore.Blu);
        var xa = Math.Max(0, x0);
        var ya = Math.Max(0, y0);
        var xb = Math.Min(larghezza, x0 + larghezzaMaschera);
        var yb = Math.Min(altezza, y0 + altezzaMaschera);
        if (xa >= xb || ya >= yb) return;
        for (var y = ya; y < yb; y++)
        {
            var riga = nv12.Slice(y * larghezza, larghezza);
            var rigaMaschera = maschera.Slice((y - y0) * larghezzaMaschera, larghezzaMaschera);
            for (var x = xa; x < xb; x++)
            {
                int alfa = rigaMaschera[x - x0];
                if (alfa == 0) continue;
                riga[x] = (byte)(riga[x] + ((yc - riga[x]) * alfa + (yc >= riga[x] ? 127 : -127)) / 255);
            }
        }
        // Crominanza: un campione ogni 2×2 pixel, con la media delle quattro opacità.
        var luminanza = larghezza * altezza;
        for (var cy = ya / 2; cy <= (yb - 1) / 2; cy++)
        {
            for (var cx = xa / 2; cx <= (xb - 1) / 2; cx++)
            {
                var somma = 0;
                for (var dy = 0; dy < 2; dy++)
                {
                    var my = cy * 2 + dy - y0;
                    if (my < 0 || my >= altezzaMaschera) continue;
                    for (var dx = 0; dx < 2; dx++)
                    {
                        var mx = cx * 2 + dx - x0;
                        if (mx >= 0 && mx < larghezzaMaschera) somma += maschera[my * larghezzaMaschera + mx];
                    }
                }
                if (somma == 0) continue;
                var i = luminanza + cy * larghezza + cx * 2;
                nv12[i] = (byte)(nv12[i] + (uc - nv12[i]) * somma / 1020);
                nv12[i + 1] = (byte)(nv12[i + 1] + (vc - nv12[i + 1]) * somma / 1020);
            }
        }
    }

    /// <summary>Una maschera rimpicciolita (o ingrandita) alla misura data.</summary>
    public static byte[] Scala(Maschera maschera, int larghezza, int altezza)
    {
        var uscita = new byte[larghezza * altezza];
        Ricampiona(maschera.Opacita, maschera.Larghezza, maschera.Altezza, maschera.Larghezza, 1, 0, 0, maschera.Larghezza, maschera.Altezza,
            uscita, larghezza, altezza, larghezza);
        return uscita;
    }

    /// <summary>
    /// Un rettangolo con gli angoli arrotondati come maschera di opacità, con i bordi sfumati (4×4 campioni per pixel).
    /// Restituisce la maschera e il suo angolo in alto a sinistra nel fotogramma.
    /// </summary>
    public static (byte[] Maschera, int X, int Y, int Larghezza, int Altezza) RettangoloArrotondato(double x, double y, double l, double a, double raggio)
    {
        var x0 = (int)Math.Floor(x);
        var y0 = (int)Math.Floor(y);
        var lm = (int)Math.Ceiling(x + l) - x0;
        var am = (int)Math.Ceiling(y + a) - y0;
        var maschera = new byte[Math.Max(0, lm * am)];
        raggio = Math.Clamp(raggio, 0, Math.Min(l, a) / 2);
        const int campioni = 4;
        for (var j = 0; j < am; j++)
        {
            for (var i = 0; i < lm; i++)
            {
                var dentro = 0;
                for (var sj = 0; sj < campioni; sj++)
                {
                    var py = y0 + j + (sj + 0.5) / campioni;
                    for (var si = 0; si < campioni; si++)
                    {
                        var px = x0 + i + (si + 0.5) / campioni;
                        if (Dentro(px, py, x, y, l, a, raggio)) dentro++;
                    }
                }
                maschera[j * lm + i] = (byte)((dentro * 255 + campioni * campioni / 2) / (campioni * campioni));
            }
        }
        return (maschera, x0, y0, lm, am);
    }

    private static bool Dentro(double px, double py, double x, double y, double l, double a, double r)
    {
        if (px < x || px > x + l || py < y || py > y + a) return false;
        var cx = Math.Clamp(px, x + r, x + l - r);
        var cy = Math.Clamp(py, y + r, y + a - r);
        var dx = px - cx;
        var dy = py - cy;
        return dx * dx + dy * dy <= r * r;
    }

    private static byte Byte(float valore) => valore <= 0 ? (byte)0 : valore >= 255 ? (byte)255 : (byte)(valore + 0.5f);
}
