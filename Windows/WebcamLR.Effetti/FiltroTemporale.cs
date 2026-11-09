namespace WebcamLR.Effetti;

/// <summary>
/// Filtro nel tempo della maschera, senza ritardo (lo stesso di Android, AnalisiImmagine.kt): dove la maschera cambia
/// poco (il tremolio del bordo tra un fotogramma e l'altro) resta un filo di quella di prima, dove cambia molto (la
/// persona si muove) vale subito la nuova. Così niente scie e niente fotogrammi di attesa.
/// </summary>
public sealed class FiltroTemporale
{
    /// <summary>Peso della maschera nuova quando non cambia nulla.</summary>
    public const float PesoMinimo = 0.7f;

    /// <summary>Di quanto sale il peso della nuova per ogni unità di differenza (a 0,1 di differenza vale già 1).</summary>
    public const float Pendenza = 3f;

    private float[]? precedente;

    /// <summary>Filtra <paramref name="maschera"/> sul posto (valori in [0, 1]) e la ricorda per la prossima.</summary>
    public void Applica(Span<float> maschera)
    {
        if (precedente is null || precedente.Length != maschera.Length)
        {
            precedente = maschera.ToArray();
            return;
        }
        for (var i = 0; i < maschera.Length; i++)
        {
            var nuova = maschera[i];
            var peso = MathF.Min(1f, PesoMinimo + Pendenza * MathF.Abs(nuova - precedente[i]));
            var v = nuova * peso + precedente[i] * (1f - peso);
            maschera[i] = v;
            precedente[i] = v;
        }
    }

    /// <summary>Dimentica la maschera di prima (cambio di telefono, di modello, scena nuova).</summary>
    public void Dimentica() => precedente = null;
}

/// <summary>
/// Media nel tempo della maschera che dipende dal movimento dell'immagine, dopo <see cref="FiltroTemporale"/> (variante
/// «D*» del banco di qualità, Documenti/Qualità sfondo - banco.md): dove l'immagine è ferma la maschera nuova pesa
/// <see cref="PesoFermo"/> e il bordo smette di tremolare; dove l'immagine cambia il peso sale fino a 1 e la persona non
/// lascia scia. Il movimento è la differenza di luminanza tra due fotogrammi alla misura della maschera, in media su 5×5.
/// Stessi conti (e arrotondamenti) di Strumenti/banco_sfondo/varianti.py, classe C.
/// </summary>
public sealed class MediaNelMovimento
{
    /// <summary>Peso della maschera nuova dove l'immagine non si muove.</summary>
    public const float PesoFermo = 0.35f;

    /// <summary>Di quanto sale il peso per ogni unità di differenza di luminanza (0..1).</summary>
    public const float Pendenza = 12f;

    /// <summary>Raggio della media del movimento (5×5).</summary>
    public const int Raggio = 2;

    private float[]? media, lumaPrecedente, luma, movimento, appoggio, pesi;

    /// <summary>
    /// Il peso della maschera nuova usato per ogni punto nell'ultima <see cref="Applica"/> (tra <see cref="PesoFermo"/> e
    /// 1; tutto 1 alla prima maschera): dice a <see cref="IsteresiMaschera"/> dove l'immagine è ferma.
    /// </summary>
    public ReadOnlySpan<float> Pesi => pesi;

    /// <summary>
    /// Filtra <paramref name="maschera"/> sul posto (valori in [0, 1], <paramref name="larghezza"/> ×
    /// <paramref name="altezza"/>); <paramref name="rgb"/> è l'immagine alla stessa misura, RGB interlacciato in [0, 1].
    /// </summary>
    public void Applica(Span<float> maschera, ReadOnlySpan<float> rgb, int larghezza, int altezza)
    {
        var n = larghezza * altezza;
        if (maschera.Length != n || rgb.Length < n * 3) throw new ArgumentException("Misure diverse tra maschera e immagine");
        if (luma is null || luma.Length != n)
        {
            luma = new float[n];
            movimento = new float[n];
            appoggio = new float[n];
            pesi = new float[n];
            media = lumaPrecedente = null;
        }
        for (var i = 0; i < n; i++) luma[i] = 0.2126f * rgb[i * 3] + 0.7152f * rgb[i * 3 + 1] + 0.0722f * rgb[i * 3 + 2];
        if (media is null || lumaPrecedente is null)
        {
            media = maschera.ToArray();
            lumaPrecedente = (float[])luma.Clone();
            Array.Fill(pesi!, 1f);
            return;
        }
        for (var i = 0; i < n; i++) movimento![i] = MathF.Abs(luma[i] - lumaPrecedente[i]);
        (lumaPrecedente, luma) = (luma, lumaPrecedente);
        MediaQuadrata(movimento!, appoggio!, larghezza, altezza);
        for (var i = 0; i < n; i++)
        {
            var peso = Math.Clamp(PesoFermo + Pendenza * movimento![i], PesoFermo, 1f);
            pesi![i] = peso;
            var v = media[i] + (maschera[i] - media[i]) * peso;
            media[i] = v;
            maschera[i] = v;
        }
    }

    /// <summary>Dimentica le maschere e l'immagine di prima (cambio di modello, scena nuova).</summary>
    public void Dimentica() => media = lumaPrecedente = null;

    /// <summary>Media (2r+1)² sul posto con i bordi ristretti, prima in orizzontale e poi in verticale, somme in double.</summary>
    private static void MediaQuadrata(float[] dati, float[] appoggio, int larghezza, int altezza)
    {
        Passata(dati, appoggio, larghezza, altezza, 1, larghezza);
        Passata(appoggio, dati, altezza, larghezza, larghezza, 1);
    }

    /// <summary>
    /// Una passata lungo un asse: <paramref name="lunghezza"/> punti a distanza <paramref name="passo"/>, per
    /// <paramref name="linee"/> linee a distanza <paramref name="passoLinea"/>.
    /// </summary>
    private static void Passata(float[] da, float[] a, int lunghezza, int linee, int passo, int passoLinea)
    {
        Span<double> somme = lunghezza <= 1024 ? stackalloc double[lunghezza + 1] : new double[lunghezza + 1];
        for (var linea = 0; linea < linee; linea++)
        {
            var base0 = linea * passoLinea;
            somme[0] = 0;
            for (var i = 0; i < lunghezza; i++) somme[i + 1] = somme[i] + da[base0 + i * passo];
            for (var i = 0; i < lunghezza; i++)
            {
                int alto = Math.Min(i + Raggio, lunghezza - 1) + 1, basso = Math.Max(i - Raggio, 0);
                a[base0 + i * passo] = (float)((somme[alto] - somme[basso]) / (alto - basso));
            }
        }
    }
}

/// <summary>
/// Isteresi nel tempo della maschera, dopo <see cref="MediaNelMovimento"/> (Qualità 4, come filtraNelTempo del Mac, tarata
/// sulla maschera di MediaPipe con il banco di qualità): ogni punto ricorda se è persona. Diventa persona quando la media
/// supera <see cref="SogliaSu"/>, torna sfondo sotto <see cref="SogliaGiu"/>; in mezzo resta com'era, e il valore si
/// sposta di <see cref="Spinta"/> dalla parte del suo stato, lontano dal centro della soglia del bordo (0,5). Così un
/// punto incerto non salta tra nitido e sfocato a ogni fotogramma (la felpa scura sul divano). La spinta vale solo dove
/// l'immagine è ferma: dove si muove (peso della media dal movimento verso 1) scende a zero e vale la maschera nuova,
/// niente scie.
/// Il filtro del Mac così com'è (media 0,3, isteresi 0,3/0,7, spinta 0,15) sulla maschera di MediaPipe peggiorava il
/// bordo (variante «Cm» del banco: MAD 137 → 190); questi valori, sopra D*, tolgono un po' di tremolio in tutte le clip
/// (in media −7%) e un po' di errore sul bordo (−2%; scuro su scuro −5%), con il dtSSD +2%
/// (Documenti/Effetti su Windows.md, «Qualità 4»).
/// </summary>
public sealed class IsteresiMaschera
{
    /// <summary>Sopra questa media un punto sfondo diventa persona.</summary>
    public const float SogliaSu = 0.6f;

    /// <summary>Sotto questa media un punto persona torna sfondo.</summary>
    public const float SogliaGiu = 0.4f;

    /// <summary>Di quanto si sposta il valore dalla parte del suo stato, dove l'immagine è ferma.</summary>
    public const float Spinta = 0.1f;

    /// <summary>Centro di partenza: alla prima maschera un punto è persona da qui in su.</summary>
    public const float Centro = 0.5f;

    private bool[]? persona;

    /// <summary>
    /// Filtra <paramref name="maschera"/> sul posto (valori in [0, 1]). <paramref name="pesi"/>: il peso della media dal
    /// movimento per ogni punto (<see cref="MediaNelMovimento.Pesi"/>); vuoto = immagine ferma ovunque.
    /// </summary>
    public void Applica(Span<float> maschera, ReadOnlySpan<float> pesi)
    {
        var n = maschera.Length;
        if (pesi.Length != 0 && pesi.Length != n) throw new ArgumentException("Misure diverse tra maschera e pesi", nameof(pesi));
        var daCapo = persona is null || persona.Length != n;
        if (daCapo) persona = new bool[n];
        const float scala = 1f / (1f - MediaNelMovimento.PesoFermo);
        for (var i = 0; i < n; i++)
        {
            var v = maschera[i];
            var p = daCapo ? v >= Centro : persona![i];
            if (p && v < SogliaGiu) p = false;
            else if (!p && v > SogliaSu) p = true;
            persona![i] = p;
            // 1 dove l'immagine è ferma (peso = PesoFermo), 0 dove si muove (peso 1). Alla prima maschera (nessun movimento
            // ancora misurato) come ferma, come il Mac: una scena ferma resta uguale dal primo fotogramma.
            var fermo = daCapo || pesi.Length == 0 ? 1f : 1f - (pesi[i] - MediaNelMovimento.PesoFermo) * scala;
            maschera[i] = Math.Clamp(v + (p ? Spinta : -Spinta) * fermo, 0f, 1f);
        }
    }

    /// <summary>Dimentica lo stato dei punti (cambio di modello, scena nuova).</summary>
    public void Dimentica() => persona = null;
}
