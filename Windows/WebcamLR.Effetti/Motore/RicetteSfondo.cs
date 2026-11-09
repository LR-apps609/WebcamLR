namespace WebcamLR.Effetti;

/// <summary>
/// Qualità 7 e 8: i fondi piccoli del bokeh e del mosaico, sul processore, a un quarto (o a un ottavo) della misura. Il
/// passo a piena risoluzione resta quello di sempre (<see cref="IComposizione"/>, scheda video o processore): il bokeh è
/// un fondo piccolo come lo sfocato, il mosaico un fondo piccolo con un pixel per quadretto, ingrandito «al più vicino»
/// (<see cref="PianoComposizione.FondoAQuadretti"/>) così i quadretti restano netti.
///
/// Come per lo sfocato, la persona esce dal conto come peso (persona allargata: 1 − (2m − 0,3), mai sotto 0,01), così il
/// suo colore non entra nello sfondo vicino al bordo.
/// </summary>
public static unsafe class RicetteSfondo
{
    // MARK: bokeh

    /// <summary>
    /// Raggio del disco (in pixel della misura piena) per un'intensità: 2σ della sfocatura normale
    /// (<see cref="Compositore.SigmaSfocatura"/>). Un disco pieno di raggio 2σ ha la stessa deviazione standard della
    /// gaussiana di sigma σ: lo sfondo è sfocato «quanto» con la sfocatura normale, ma le luci diventano dischi.
    /// </summary>
    public static double RaggioBokeh(double intensita, int latoCortoPieno) =>
        2 * Compositore.SigmaSfocatura(intensita) * latoCortoPieno / 1080.0;

    /// <summary>
    /// Quanto si espandono le luci prima del disco: la luminanza lineare Y diventa Y / (1 − c·Y), cioè una luce piena vale
    /// 10 volte il bianco (c = 0,9) e un grigio medio quasi come prima (0,2 → 0,24). Dopo il disco si comprime con
    /// l'inversa esatta, Y / (1 + c·Y): una zona uniforme (una parete chiara) torna identica, mentre una luce piccola,
    /// sparsa sul disco, resta un disco chiaro invece di spegnersi come nella sfocatura normale. È quello che fa un
    /// obiettivo con le luci che il sensore aveva tagliato al bianco.
    /// </summary>
    public const float EspansioneLuci = 0.9f;

    /// <summary>Raggio massimo del disco nella misura piccola: oltre costa troppo (e a un quarto 24 px sono già 96 px a 1080p).</summary>
    public const int RaggioMassimo = 24;

    /// <summary>
    /// Oltre questo raggio (pixel della misura piccola) il disco si fa un gradino più in piccolo (da un quarto a un ottavo,
    /// al massimo a un sedicesimo): il costo va con il raggio, e un disco grande, ingrandito, resta un disco.
    /// </summary>
    public const double RaggioPerScendere = 10;

    /// <summary>
    /// Il gradino della piramide sotto il quarto (0 = il quarto) per un disco di <paramref name="raggioPieno"/> pixel a piena
    /// misura su un video largo <paramref name="larghezzaPiena"/>: almeno <paramref name="minimo"/>, poi giù finché il raggio
    /// supera <see cref="RaggioPerScendere"/>.
    /// </summary>
    public static int GradinoDisco(double raggioPieno, int minimo)
    {
        var gradino = Math.Clamp(minimo, 0, 2);
        while (gradino < 2 && raggioPieno / (4 << gradino) > RaggioPerScendere) gradino++;
        return gradino;
    }

    private static readonly float[] Lineare = Enumerable.Range(0, 256).Select(i => MathF.Pow(i / 255f, 2.2f)).ToArray();

    /// <summary>Da lineare (0..1, 4096 gradini) a sRGB in byte.</summary>
    private static readonly byte[] DaLineare = Enumerable.Range(0, 4096)
        .Select(i => (byte)Math.Clamp(MathF.Pow(i / 4095f, 1 / 2.2f) * 255f + 0.5f, 0f, 255f)).ToArray();

    /// <summary>Il fattore che espande un colore di luminanza lineare <paramref name="y"/> (0..1): 1 / (1 − c·Y).</summary>
    public static float Espandi(float y) => 1f / (1f - EspansioneLuci * Math.Clamp(y, 0f, 1f));

    /// <summary>Il fattore che comprime un colore espanso di luminanza <paramref name="y"/> (≥ 0): 1 / (1 + c·Y).</summary>
    public static float Comprimi(float y) => 1f / (1f + EspansioneLuci * Math.Max(y, 0f));

    /// <summary>
    /// Lo sfondo «come un obiettivo», piccolo come <paramref name="piccola"/>:
    /// 1. in luce lineare (le luci pesano come in un obiettivo vero), le luci espanse (<see cref="EspansioneLuci"/>);
    /// 2. ogni punto pesato dallo sfondo (la persona allargata esce dal conto);
    /// 3. un disco pieno di raggio <paramref name="raggio"/> (pixel della misura piccola): somma per righe con le somme
    ///    cumulate di ogni riga, quindi (2r + 1) letture per punto e non π r²;
    /// 4. diviso per il peso sfocato, compresso con l'inversa dell'espansione, di nuovo in sRGB.
    /// Dove non c'è sfondo vicino (dentro una persona grande) resta il colore del punto: tanto è coperto dalla persona.
    /// </summary>
    /// <param name="persona">La maschera alla misura di <paramref name="piccola"/>, 0..1.</param>
    /// <param name="calore">Le tabelle del calore (R, G, B), da applicare prima; null = niente.</param>
    /// <param name="lavagna">Il posto per le somme cumulate, riusato da un fotogramma all'altro (null = uno nuovo).</param>
    public static ImmagineBgra Bokeh(ImmagineBgra piccola, float[] persona, double raggio, byte[][]? calore,
        ImmagineBgra? destinazione = null, LavagnaBokeh? lavagna = null)
    {
        int l = piccola.Larghezza, a = piccola.Altezza, n = l * a;
        if (persona.Length < n) throw new ArgumentException("Maschera più piccola dell'immagine", nameof(persona));
        var r = Math.Clamp((int)Math.Round(raggio), 1, RaggioMassimo);
        var s = piccola.Dati;
        // Somme cumulate per riga, 4 canali (B, G, R spinti e pesati; peso): (l + 1) punti per riga, il primo a zero.
        var passo = (l + 1) * 4;
        lavagna ??= new LavagnaBokeh();
        if (lavagna.Cumulate.Length < passo * a) lavagna.Cumulate = new float[passo * a];
        var cumulate = lavagna.Cumulate;
        Elaborazione.PerRighe(a, (inizio, fine) =>
        {
            for (var y = inizio; y < fine; y++)
            {
                var o = y * passo;
                float sb = 0, sg = 0, sr = 0, sw = 0;
                for (var x = 0; x < l; x++)
                {
                    var i = y * l + x;
                    var w = 1f - Math.Clamp(2f * persona[i] - 0.3f, 0f, 0.99f);
                    byte b = s[i * 4], g = s[i * 4 + 1], rr = s[i * 4 + 2];
                    if (calore is not null)
                    {
                        b = calore[2][b];
                        g = calore[1][g];
                        rr = calore[0][rr];
                    }
                    float lb = Lineare[b], lg = Lineare[g], lr = Lineare[rr];
                    var k = Espandi(0.0722f * lb + 0.7152f * lg + 0.2126f * lr) * w;
                    sb += lb * k;
                    sg += lg * k;
                    sr += lr * k;
                    sw += w;
                    var c = o + (x + 1) * 4;
                    cumulate[c] = sb;
                    cumulate[c + 1] = sg;
                    cumulate[c + 2] = sr;
                    cumulate[c + 3] = sw;
                }
            }
        });
        // La mezza larghezza del disco per ogni riga di distanza.
        var meta = new int[2 * r + 1];
        for (var dy = -r; dy <= r; dy++) meta[dy + r] = (int)Math.Floor(Math.Sqrt(r * r - dy * dy) + 0.5);
        var uscita = destinazione is { } pronta && pronta.Larghezza == l && pronta.Altezza == a ? pronta : new ImmagineBgra(l, a);
        var d = uscita.Dati;
        Elaborazione.PerRighe(a, (inizio, fine) =>
        {
            // Con i puntatori: il giro interno fa (2r + 1) × 8 letture per punto, senza i controlli dei limiti.
            fixed (float* pc = cumulate)
            fixed (int* pm = meta)
            fixed (byte* ps = s, pd = d)
            fixed (byte* tabella = DaLineare)
            {
                for (var y = inizio; y < fine; y++)
                {
                    int dyMin = Math.Max(-r, -y), dyMax = Math.Min(r, a - 1 - y);
                    for (var x = 0; x < l; x++)
                    {
                        float sb = 0, sg = 0, sr = 0, sw = 0;
                        var punti = 0;
                        for (var dy = dyMin; dy <= dyMax; dy++)
                        {
                            var h = pm[dy + r];
                            int x0 = x - h < 0 ? 0 : x - h, x1 = x + h >= l ? l - 1 : x + h;
                            var riga = pc + (y + dy) * passo;
                            float* q1 = riga + (x1 + 1) * 4, q0 = riga + x0 * 4;
                            sb += q1[0] - q0[0];
                            sg += q1[1] - q0[1];
                            sr += q1[2] - q0[2];
                            sw += q1[3] - q0[3];
                            punti += x1 - x0 + 1;
                        }
                        var i = (y * l + x) * 4;
                        if (sw > 0.02f * punti)
                        {
                            sb /= sw;
                            sg /= sw;
                            sr /= sw;
                            var k = Comprimi(0.0722f * sb + 0.7152f * sg + 0.2126f * sr) * 4095f;
                            pd[i] = tabella[(int)(Math.Clamp(sb * k, 0f, 4095f) + 0.5f)];
                            pd[i + 1] = tabella[(int)(Math.Clamp(sg * k, 0f, 4095f) + 0.5f)];
                            pd[i + 2] = tabella[(int)(Math.Clamp(sr * k, 0f, 4095f) + 0.5f)];
                        }
                        else
                        {
                            pd[i] = ps[i];
                            pd[i + 1] = ps[i + 1];
                            pd[i + 2] = ps[i + 2];
                        }
                        pd[i + 3] = 255;
                    }
                }
            }
        });
        return uscita;
    }

    // MARK: mosaico

    /// <summary>
    /// Il lato di un quadretto (pixel della misura piena) per un'intensità: 12 + 36 × intensità a 1080p, cioè Poco (0,25)
    /// 21 px, Medio (0,55) 32 px, Tanto (1) 48 px. Mai sotto 4.
    /// </summary>
    public static int LatoQuadretto(double intensita, int latoCortoPieno)
    {
        var limitata = double.IsFinite(intensita) ? Math.Clamp(intensita, 0, 1) : 0.5;
        return Math.Max(4, (int)Math.Round((12 + 36 * limitata) * latoCortoPieno / 1080.0));
    }

    /// <summary>Colonne e righe dei quadretti per un video l×a: quadretti di circa <see cref="LatoQuadretto"/> per lato.</summary>
    public static (int Colonne, int Righe) Griglia(int larghezza, int altezza, double intensita)
    {
        var lato = LatoQuadretto(intensita, Math.Min(larghezza, altezza));
        return (Math.Max(1, (int)Math.Round((double)larghezza / lato)), Math.Max(1, (int)Math.Round((double)altezza / lato)));
    }

    /// <summary>
    /// Un pixel per quadretto: la media dei colori dello sfondo nel quadretto (pesata come nel bokeh, così un quadretto
    /// sull'orlo prende il colore dello sfondo e non quello della persona). Il quadretto i copre, nella misura piena, le
    /// colonne da i·L/colonne a (i + 1)·L/colonne: le stesse che prende l'ingrandimento «al più vicino» della composizione.
    /// </summary>
    public static ImmagineBgra Mosaico(ImmagineBgra piccola, float[] persona, int colonne, int righe, byte[][]? calore,
        ImmagineBgra? destinazione = null)
    {
        int l = piccola.Larghezza, a = piccola.Altezza;
        if (persona.Length < l * a) throw new ArgumentException("Maschera più piccola dell'immagine", nameof(persona));
        colonne = Math.Clamp(colonne, 1, l);
        righe = Math.Clamp(righe, 1, a);
        var s = piccola.Dati;
        var uscita = destinazione is { } pronta && pronta.Larghezza == colonne && pronta.Altezza == righe
            ? pronta : new ImmagineBgra(colonne, righe);
        var d = uscita.Dati;
        for (var j = 0; j < righe; j++)
        {
            int y0 = j * a / righe, y1 = Math.Max(y0 + 1, (j + 1) * a / righe);
            for (var i = 0; i < colonne; i++)
            {
                int x0 = i * l / colonne, x1 = Math.Max(x0 + 1, (i + 1) * l / colonne);
                float sb = 0, sg = 0, sr = 0, sw = 0;
                for (var y = y0; y < y1; y++)
                {
                    for (var x = x0; x < x1; x++)
                    {
                        var p = y * l + x;
                        var w = 1f - Math.Clamp(2f * persona[p] - 0.3f, 0f, 0.99f);
                        byte b = s[p * 4], g = s[p * 4 + 1], r = s[p * 4 + 2];
                        if (calore is not null)
                        {
                            b = calore[2][b];
                            g = calore[1][g];
                            r = calore[0][r];
                        }
                        sb += b * w;
                        sg += g * w;
                        sr += r * w;
                        sw += w;
                    }
                }
                var o = (j * colonne + i) * 4;
                var inv = 1f / Math.Max(sw, 1e-6f);
                d[o] = (byte)Math.Min(255f, sb * inv + 0.5f);
                d[o + 1] = (byte)Math.Min(255f, sg * inv + 0.5f);
                d[o + 2] = (byte)Math.Min(255f, sr * inv + 0.5f);
                d[o + 3] = 255;
            }
        }
        return uscita;
    }

    /// <summary>Le somme cumulate del bokeh, riusate (a 1080p, a un quarto, circa 2 MB).</summary>
    public sealed class LavagnaBokeh
    {
        public float[] Cumulate = [];
    }
}
