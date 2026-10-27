using System.Numerics;

namespace WebcamLR.Effetti;

/// <summary>
/// I mattoni della resa sul processore: riduzioni, sfocatura gaussiana, filtro guidato, campionamento della maschera,
/// soglia morbida, ricampionamento. Funzioni senza stato; le più pesanti dividono le righe tra i processori
/// (Parallel.For), leggono e scrivono con i puntatori e usano i vettori del processore (System.Numerics, SIMD) dove i
/// dati sono contigui.
/// </summary>
public static unsafe class Elaborazione
{
    /// <summary>Righe per pezzo nei cicli paralleli: abbastanza per non spendere più a dividere che a calcolare.</summary>
    internal const int RighePerPezzo = 16;

    /// <summary>Un ciclo sulle righe diviso in pezzi tra i processori.</summary>
    public static void PerRighe(int altezza, Action<int, int> pezzo)
    {
        var pezzi = (altezza + RighePerPezzo - 1) / RighePerPezzo;
        if (pezzi <= 1)
        {
            pezzo(0, altezza);
            return;
        }
        Parallel.For(0, pezzi, i => pezzo(i * RighePerPezzo, Math.Min(altezza, (i + 1) * RighePerPezzo)));
    }

    /// <summary>Metà misura (media di 2×2 pixel), per BGRA. Le misure dispari perdono l'ultima riga o colonna.</summary>
    public static ImmagineBgra Dimezza(ImmagineBgra sorgente, ImmagineBgra? destinazione = null)
    {
        var l = Math.Max(1, sorgente.Larghezza / 2);
        var a = Math.Max(1, sorgente.Altezza / 2);
        var d = destinazione is { } esistente && esistente.Larghezza == l && esistente.Altezza == a ? esistente : new ImmagineBgra(l, a);
        var passo = sorgente.Passo;
        if (sorgente.Larghezza < 2 || sorgente.Altezza < 2)
        {
            // Una riga o una colonna sola: il pixel più vicino.
            for (var y = 0; y < a; y++)
                for (var x = 0; x < l; x++)
                    sorgente.Dati.AsSpan(Math.Min(2 * y, sorgente.Altezza - 1) * passo + Math.Min(2 * x, sorgente.Larghezza - 1) * 4, 4)
                        .CopyTo(d.Dati.AsSpan((y * l + x) * 4, 4));
        }
        else
        {
            PerRighe(a, (inizio, fine) =>
            {
                fixed (byte* s = sorgente.Dati, t = d.Dati)
                {
                    for (var y = inizio; y < fine; y++)
                    {
                        var r0 = s + 2 * y * passo;
                        var r1 = r0 + passo;
                        var o = t + y * l * 4;
                        for (var x = 0; x < l; x++, r0 += 8, r1 += 8, o += 4)
                        {
                            o[0] = (byte)((r0[0] + r0[4] + r1[0] + r1[4] + 2) >> 2);
                            o[1] = (byte)((r0[1] + r0[5] + r1[1] + r1[5] + 2) >> 2);
                            o[2] = (byte)((r0[2] + r0[6] + r1[2] + r1[6] + 2) >> 2);
                            o[3] = (byte)((r0[3] + r0[7] + r1[3] + r1[7] + 2) >> 2);
                        }
                    }
                }
            });
        }
        d.Timestamp = sorgente.Timestamp;
        return d;
    }

    /// <summary>La luminosità (0..1, pesi Rec. 709 sui valori sRGB) di ogni pixel: la guida del filtro guidato.</summary>
    public static float[] Luminosita(ImmagineBgra immagine, float[]? destinazione = null)
    {
        var n = immagine.Larghezza * immagine.Altezza;
        var d = destinazione?.Length == n ? destinazione : new float[n];
        fixed (byte* s = immagine.Dati)
        fixed (float* t = d)
        {
            var p = s;
            for (var i = 0; i < n; i++, p += 4) t[i] = (0.0722f / 255f) * p[0] + (0.7152f / 255f) * p[1] + (0.2126f / 255f) * p[2];
        }
        return d;
    }

    /// <summary>
    /// La maschera del modello (stirata su tutto il fotogramma) alla misura <paramref name="larghezza"/>×
    /// <paramref name="altezza"/>, bilineare, in 0..1.
    /// </summary>
    public static float[] Campiona(byte[] maschera, int larghezzaMaschera, int altezzaMaschera, int larghezza, int altezza,
        float[]? destinazione = null)
    {
        var d = destinazione?.Length == larghezza * altezza ? destinazione : new float[larghezza * altezza];
        var (x0, x1, fx) = Campionamento(larghezza, larghezzaMaschera);
        var (y0, y1, fy) = Campionamento(altezza, altezzaMaschera);
        for (var y = 0; y < altezza; y++)
        {
            var a = y0[y] * larghezzaMaschera;
            var b = y1[y] * larghezzaMaschera;
            var wy = fy[y];
            for (var x = 0; x < larghezza; x++)
            {
                var sopra = maschera[a + x0[x]] + (maschera[a + x1[x]] - maschera[a + x0[x]]) * fx[x];
                var sotto = maschera[b + x0[x]] + (maschera[b + x1[x]] - maschera[b + x0[x]]) * fx[x];
                d[y * larghezza + x] = (sopra + (sotto - sopra) * wy) * (1f / 255f);
            }
        }
        return d;
    }

    /// <summary>Per ogni punto della destinazione: i due vicini nella sorgente e il peso del secondo (centri dei pixel).</summary>
    public static (int[] Primo, int[] Secondo, float[] Peso) Campionamento(int destinazione, int sorgente)
    {
        var primo = new int[destinazione];
        var secondo = new int[destinazione];
        var peso = new float[destinazione];
        var scala = (double)sorgente / destinazione;
        for (var i = 0; i < destinazione; i++)
        {
            var p = Math.Clamp((i + 0.5) * scala - 0.5, 0, sorgente - 1);
            primo[i] = (int)p;
            secondo[i] = Math.Min(primo[i] + 1, sorgente - 1);
            peso[i] = (float)(p - primo[i]);
        }
        return (primo, secondo, peso);
    }

    /// <summary>Gli inversi del numero di pixel nella finestra di raggio r per ogni posizione (i bordi ne hanno meno).</summary>
    private static float[] InversiFinestra(int n, int raggio)
    {
        var inversi = new float[n];
        for (var i = 0; i < n; i++) inversi[i] = 1f / (Math.Min(i + raggio, n - 1) - Math.Max(i - raggio, 0) + 1);
        return inversi;
    }

    /// <summary>
    /// Media su una finestra (2r+1)² con i bordi ristretti (la media dei soli pixel dentro l'immagine), in due passate
    /// con somme scorrevoli: costa uguale per qualsiasi raggio.
    /// </summary>
    public static void MediaQuadrata(float[] ingresso, float[] uscita, int larghezza, int altezza, int raggio, float[] appoggio)
    {
        var inversiX = InversiFinestra(larghezza, raggio);
        var inversiY = InversiFinestra(altezza, raggio);
        // Orizzontale, riga per riga.
        PerRighe(altezza, (inizio, fine) =>
        {
            fixed (float* s0 = ingresso, d0 = appoggio, inv = inversiX)
            {
                for (var y = inizio; y < fine; y++)
                {
                    var s = s0 + y * larghezza;
                    var d = d0 + y * larghezza;
                    float somma = 0;
                    var primo = Math.Min(raggio, larghezza - 1);
                    for (var x = 0; x <= primo; x++) somma += s[x];
                    for (var x = 0; x < larghezza; x++)
                    {
                        d[x] = somma * inv[x];
                        var entra = x + raggio + 1;
                        var esce = x - raggio;
                        if (entra < larghezza) somma += s[entra];
                        if (esce >= 0) somma -= s[esce];
                    }
                }
            }
        });
        // Verticale, a gruppi di colonne: righe intere alla volta (la memoria si legge in ordine), con i vettori.
        var gruppi = Math.Max(1, Math.Min(Environment.ProcessorCount * 2, larghezza / 64));
        Parallel.For(0, gruppi, g =>
        {
            var x0 = g * larghezza / gruppi;
            var n = (g + 1) * larghezza / gruppi - x0;
            var somme = new float[n];
            var primo = Math.Min(raggio, altezza - 1);
            for (var y = 0; y <= primo; y++) Somma(somme, appoggio, y * larghezza + x0, n, 1);
            for (var y = 0; y < altezza; y++)
            {
                Scala(somme, uscita, y * larghezza + x0, n, inversiY[y]);
                var entra = y + raggio + 1;
                var esce = y - raggio;
                if (entra < altezza) Somma(somme, appoggio, entra * larghezza + x0, n, 1);
                if (esce >= 0) Somma(somme, appoggio, esce * larghezza + x0, n, -1);
            }
        });
    }

    /// <summary>somme[i] += segno × dati[inizio + i].</summary>
    private static void Somma(float[] somme, float[] dati, int inizio, int n, float segno)
    {
        var i = 0;
        if (Vector.IsHardwareAccelerated)
        {
            var vs = new Vector<float>(segno);
            for (; i <= n - Vector<float>.Count; i += Vector<float>.Count)
                (new Vector<float>(somme, i) + vs * new Vector<float>(dati, inizio + i)).CopyTo(somme, i);
        }
        for (; i < n; i++) somme[i] += segno * dati[inizio + i];
    }

    /// <summary>uscita[inizio + i] = somme[i] × fattore.</summary>
    private static void Scala(float[] somme, float[] uscita, int inizio, int n, float fattore)
    {
        var i = 0;
        if (Vector.IsHardwareAccelerated)
        {
            var vf = new Vector<float>(fattore);
            for (; i <= n - Vector<float>.Count; i += Vector<float>.Count)
                (new Vector<float>(somme, i) * vf).CopyTo(uscita, inizio + i);
        }
        for (; i < n; i++) uscita[inizio + i] = somme[i] * fattore;
    }

    /// <summary>
    /// Filtro guidato (He, Sun e Tang): la maschera <paramref name="p"/> rifatta seguendo i bordi della guida
    /// <paramref name="guida"/> (la luminosità del video). È il «bordo guidato dal colore»: dove la guida ha un bordo
    /// (capelli contro il muro) il bordo della maschera si sposta lì. <paramref name="eps"/> piccolo = segue di più.
    /// </summary>
    public static float[] FiltroGuidato(float[] guida, float[] p, int larghezza, int altezza, int raggio, float eps,
        LavagnaGuidato? lavagna = null, bool soloCoefficienti = false)
    {
        var n = larghezza * altezza;
        lavagna ??= new LavagnaGuidato();
        lavagna.Prepara(n);
        var (mI, mP, mIP, mII, a, b, appoggio, q, prodotto) =
            (lavagna.MI, lavagna.MP, lavagna.MIP, lavagna.MII, lavagna.A, lavagna.B, lavagna.Appoggio, lavagna.Q, lavagna.Prodotto);
        Per(guida, p, prodotto, n);
        MediaQuadrata(prodotto, mIP, larghezza, altezza, raggio, appoggio);
        Per(guida, guida, prodotto, n);
        MediaQuadrata(prodotto, mII, larghezza, altezza, raggio, appoggio);
        MediaQuadrata(guida, mI, larghezza, altezza, raggio, appoggio);
        MediaQuadrata(p, mP, larghezza, altezza, raggio, appoggio);
        var i = 0;
        if (Vector.IsHardwareAccelerated)
        {
            var veps = new Vector<float>(eps);
            for (; i <= n - Vector<float>.Count; i += Vector<float>.Count)
            {
                var vI = new Vector<float>(mI, i);
                var vP = new Vector<float>(mP, i);
                var va = (new Vector<float>(mIP, i) - vI * vP) / (new Vector<float>(mII, i) - vI * vI + veps);
                va.CopyTo(a, i);
                (vP - va * vI).CopyTo(b, i);
            }
        }
        for (; i < n; i++)
        {
            a[i] = (mIP[i] - mI[i] * mP[i]) / (mII[i] - mI[i] * mI[i] + eps);
            b[i] = mP[i] - a[i] * mI[i];
        }
        MediaQuadrata(a, mI, larghezza, altezza, raggio, appoggio);
        MediaQuadrata(b, mP, larghezza, altezza, raggio, appoggio);
        if (soloCoefficienti) return mI;
        i = 0;
        if (Vector.IsHardwareAccelerated)
        {
            for (; i <= n - Vector<float>.Count; i += Vector<float>.Count)
                (new Vector<float>(mI, i) * new Vector<float>(guida, i) + new Vector<float>(mP, i)).CopyTo(q, i);
        }
        for (; i < n; i++) q[i] = mI[i] * guida[i] + mP[i];
        return q;
    }

    /// <summary>
    /// Il filtro guidato «veloce» (He e Sun, 2015): i coefficienti si calcolano sulla guida piccola
    /// (<paramref name="guidaBassa"/>, con la maschera alla stessa misura) e si ingrandiscono, poi si applicano alla guida
    /// grande (<paramref name="guidaAlta"/>): quasi la stessa resa a un quarto del costo.
    /// </summary>
    public static float[] FiltroGuidatoVeloce(float[] guidaAlta, int larghezzaAlta, int altezzaAlta, float[] guidaBassa,
        float[] pBassa, int larghezzaBassa, int altezzaBassa, int raggioBasso, float eps, LavagnaGuidato lavagna, float[]? uscita = null)
    {
        FiltroGuidato(guidaBassa, pBassa, larghezzaBassa, altezzaBassa, raggioBasso, eps, lavagna, soloCoefficienti: true);
        var mediaA = lavagna.MI;
        var mediaB = lavagna.MP;
        var q = uscita?.Length == larghezzaAlta * altezzaAlta ? uscita : new float[larghezzaAlta * altezzaAlta];
        var (x0, x1, fx) = Campionamento(larghezzaAlta, larghezzaBassa);
        var (y0, y1, fy) = Campionamento(altezzaAlta, altezzaBassa);
        PerRighe(altezzaAlta, (inizio, fine) =>
        {
            for (var y = inizio; y < fine; y++)
            {
                int r0 = y0[y] * larghezzaBassa, r1 = y1[y] * larghezzaBassa;
                var wy = fy[y];
                var o = y * larghezzaAlta;
                for (var x = 0; x < larghezzaAlta; x++)
                {
                    int c0 = x0[x], c1 = x1[x];
                    var wx = fx[x];
                    var aSopra = mediaA[r0 + c0] + (mediaA[r0 + c1] - mediaA[r0 + c0]) * wx;
                    var aSotto = mediaA[r1 + c0] + (mediaA[r1 + c1] - mediaA[r1 + c0]) * wx;
                    var bSopra = mediaB[r0 + c0] + (mediaB[r0 + c1] - mediaB[r0 + c0]) * wx;
                    var bSotto = mediaB[r1 + c0] + (mediaB[r1 + c1] - mediaB[r1 + c0]) * wx;
                    q[o + x] = (aSopra + (aSotto - aSopra) * wy) * guidaAlta[o + x] + bSopra + (bSotto - bSopra) * wy;
                }
            }
        });
        return q;
    }

    private static void Per(float[] x, float[] y, float[] uscita, int n)
    {
        var i = 0;
        if (Vector.IsHardwareAccelerated)
        {
            for (; i <= n - Vector<float>.Count; i += Vector<float>.Count)
                (new Vector<float>(x, i) * new Vector<float>(y, i)).CopyTo(uscita, i);
        }
        for (; i < n; i++) uscita[i] = x[i] * y[i];
    }

    /// <summary>I buffer del filtro guidato, riusati da un fotogramma all'altro.</summary>
    public sealed class LavagnaGuidato
    {
        public float[] MI = [], MP = [], MIP = [], MII = [], A = [], B = [], Appoggio = [], Prodotto = [], Q = [];

        public void Prepara(int n)
        {
            if (MI.Length == n) return;
            MI = new float[n]; MP = new float[n]; MIP = new float[n]; MII = new float[n];
            A = new float[n]; B = new float[n]; Appoggio = new float[n]; Prodotto = new float[n]; Q = new float[n];
        }
    }

    /// <summary>Centro della soglia del bordo: un po' sotto la metà, così capelli e cima della testa non escono «rasati».</summary>
    public const float CentroSoglia = 0.42f;

    /// <summary>
    /// Soglia morbida attorno a <see cref="CentroSoglia"/>, larga <paramref name="larghezza"/>: t tra 0 e 1, poi
    /// smoothstep 3t² − 2t³ (come sogliaMorbida del Mac). Risultato in byte 0–255, tanti quanti <paramref name="uscita"/>.
    /// </summary>
    public static void SogliaMorbida(float[] valori, byte[] uscita, float larghezza)
    {
        var ampiezza = Math.Clamp(larghezza, 0.05f, 1f);
        var inizio = CentroSoglia - ampiezza / 2;
        for (var i = 0; i < uscita.Length; i++)
        {
            var t = Math.Clamp((valori[i] - inizio) / ampiezza, 0f, 1f);
            uscita[i] = (byte)(t * t * (3 - 2 * t) * 255f + 0.5f);
        }
    }

    /// <summary>
    /// Sfocatura gaussiana separabile di un'immagine a <paramref name="canali"/> canali float interlacciati, con i bordi
    /// ripetuti. Nucleo fino a 3σ. Tutte e due le passate con i vettori: in orizzontale su una riga allungata ai bordi.
    /// </summary>
    public static void Gaussiana(float[] dati, int larghezza, int altezza, int canali, double sigma, float[] appoggio)
    {
        if (sigma < 0.3) return;
        var raggio = Math.Max(1, (int)Math.Ceiling(sigma * 3));
        var nucleo = new float[2 * raggio + 1];
        double somma = 0;
        for (var i = -raggio; i <= raggio; i++) somma += nucleo[i + raggio] = (float)Math.Exp(-i * i / (2 * sigma * sigma));
        for (var i = 0; i < nucleo.Length; i++) nucleo[i] = (float)(nucleo[i] / somma);
        var riga = larghezza * canali;
        PerRighe(altezza, (inizio, fine) =>
        {
            var allungata = new float[(larghezza + 2 * raggio) * canali];
            var accumulo = new float[riga];
            for (var y = inizio; y < fine; y++)
            {
                var o = y * riga;
                Array.Copy(dati, o, allungata, raggio * canali, riga);
                for (var k = 0; k < raggio; k++)
                {
                    Array.Copy(dati, o, allungata, k * canali, canali);
                    Array.Copy(dati, o + riga - canali, allungata, (raggio + larghezza + k) * canali, canali);
                }
                Array.Clear(accumulo);
                for (var k = 0; k < nucleo.Length; k++) Accumula(accumulo, allungata, k * canali, riga, nucleo[k]);
                Array.Copy(accumulo, 0, appoggio, o, riga);
            }
        });
        PerRighe(altezza, (inizio, fine) =>
        {
            var accumulo = new float[riga];
            for (var y = inizio; y < fine; y++)
            {
                Array.Clear(accumulo);
                for (var k = -raggio; k <= raggio; k++)
                    Accumula(accumulo, appoggio, Math.Clamp(y + k, 0, altezza - 1) * riga, riga, nucleo[k + raggio]);
                Array.Copy(accumulo, 0, dati, y * riga, riga);
            }
        });
    }

    /// <summary>accumulo[i] += peso × dati[inizio + i], con i vettori.</summary>
    private static void Accumula(float[] accumulo, float[] dati, int inizio, int n, float peso)
    {
        var i = 0;
        if (Vector.IsHardwareAccelerated)
        {
            var vw = new Vector<float>(peso);
            for (; i <= n - Vector<float>.Count; i += Vector<float>.Count)
                (new Vector<float>(accumulo, i) + vw * new Vector<float>(dati, inizio + i)).CopyTo(accumulo, i);
        }
        for (; i < n; i++) accumulo[i] += peso * dati[inizio + i];
    }

    /// <summary>
    /// Un'immagine «a riempire» (come aspect fill), centrata, alla misura <paramref name="larghezza"/>×
    /// <paramref name="altezza"/>, bilineare. Si fa una volta per immagine e misura, non per fotogramma.
    /// </summary>
    public static ImmagineBgra Riempi(ImmagineBgra immagine, int larghezza, int altezza)
    {
        var scala = Math.Max((double)larghezza / immagine.Larghezza, (double)altezza / immagine.Altezza);
        var l = larghezza / scala;
        var a = altezza / scala;
        var x0 = (immagine.Larghezza - l) / 2;
        var y0 = (immagine.Altezza - a) / 2;
        var uscita = new ImmagineBgra(larghezza, altezza);
        Ricampiona(immagine, x0, y0, l, a, uscita, specchia: false);
        for (var i = 3; i < uscita.Dati.Length; i += 4) uscita.Dati[i] = 255;
        return uscita;
    }

    /// <summary>
    /// La parte (<paramref name="x"/>, <paramref name="y"/>, <paramref name="l"/>×<paramref name="a"/>, in pixel, anche
    /// frazionari) dell'immagine portata su tutta la destinazione, bilineare; specchiata se richiesto.
    /// </summary>
    public static void Ricampiona(ImmagineBgra sorgente, double x, double y, double l, double a, ImmagineBgra destinazione, bool specchia)
    {
        var lD = destinazione.Larghezza;
        var aD = destinazione.Altezza;
        var colonne0 = new int[lD];
        var colonne1 = new int[lD];
        var pesiX = new int[lD];
        for (var i = 0; i < lD; i++)
        {
            var colonna = specchia ? lD - 1 - i : i;
            var p = Math.Clamp(x + (colonna + 0.5) * l / lD - 0.5, 0, sorgente.Larghezza - 1);
            colonne0[i] = (int)p * 4;
            colonne1[i] = Math.Min((int)p + 1, sorgente.Larghezza - 1) * 4;
            pesiX[i] = (int)((p - (int)p) * 256);
        }
        var passo = sorgente.Passo;
        PerRighe(aD, (inizio, fine) =>
        {
            fixed (byte* s = sorgente.Dati, d0 = destinazione.Dati)
            fixed (int* c0 = colonne0, c1 = colonne1, px = pesiX)
            {
                for (var r = inizio; r < fine; r++)
                {
                    var p = Math.Clamp(y + (r + 0.5) * a / aD - 0.5, 0, sorgente.Altezza - 1);
                    var riga0 = s + (int)p * passo;
                    var riga1 = s + Math.Min((int)p + 1, sorgente.Altezza - 1) * passo;
                    var wy = (int)((p - (int)p) * 256);
                    var d = d0 + r * destinazione.Passo;
                    for (var i = 0; i < lD; i++, d += 4)
                    {
                        var a0 = riga0 + c0[i];
                        var a1 = riga0 + c1[i];
                        var b0 = riga1 + c0[i];
                        var b1 = riga1 + c1[i];
                        var wx = px[i];
                        for (var k = 0; k < 4; k++)
                        {
                            var sopra = (a0[k] << 8) + (a1[k] - a0[k]) * wx;
                            var sotto = (b0[k] << 8) + (b1[k] - b0[k]) * wx;
                            d[k] = (byte)(((sopra << 8) + (sotto - sopra) * wy + 32768) >> 16);
                        }
                    }
                }
            }
        });
    }
}
