namespace WebcamLR.Effetti;

/// <summary>
/// Il volto dalla maschera della persona (niente rilevatore a parte): con il modello pieno dalla classe «pelle del volto»
/// del multiclasse (il riquadro della pelle del viso: dalla fronte al mento), con il leggero dalla testa, cioè la cima della
/// persona. Coordinate normalizzate del fotogramma, origine in alto a sinistra.
/// </summary>
public static class VoltoDallaMaschera
{
    /// <summary>Sotto questa parte della maschera (punti del volto o righe della testa) non c'è un volto.</summary>
    public const double PunteggioMinimo = 0.002;

    /// <param name="larghezzaVideo">e <paramref name="altezzaVideo"/>: per le proporzioni della testa (la maschera è stirata).</param>
    public static Rettangolo? Stima(MascheraPersona maschera, int larghezzaVideo, int altezzaVideo)
    {
        if (maschera.Volto is { } volto) return DaPelle(volto, maschera.Larghezza, maschera.Altezza);
        return DallaTesta(maschera.Valori, maschera.Larghezza, maschera.Altezza, larghezzaVideo, altezzaVideo);
    }

    /// <summary>Il riquadro dei punti di pelle del volto (sopra metà), tolti il 2% più esterno per lato (orecchie, mani).</summary>
    public static Rettangolo? DaPelle(byte[] volto, int larghezza, int altezza)
    {
        var colonne = new int[larghezza];
        var righe = new int[altezza];
        var totale = 0;
        for (var y = 0; y < altezza; y++)
        {
            for (var x = 0; x < larghezza; x++)
            {
                if (volto[y * larghezza + x] < 128) continue;
                colonne[x]++;
                righe[y]++;
                totale++;
            }
        }
        if (totale < PunteggioMinimo * larghezza * altezza) return null;
        var (x0, x1) = Estremi(colonne, totale);
        var (y0, y1) = Estremi(righe, totale);
        return new Rettangolo((double)x0 / larghezza, (double)y0 / altezza, (double)(x1 - x0 + 1) / larghezza, (double)(y1 - y0 + 1) / altezza);
    }

    /// <summary>
    /// La testa: la prima riga dall'alto con abbastanza persona, la larghezza della persona poco sotto (la testa, prima
    /// delle spalle), un volto alto 1,3 volte la sua larghezza. Grossolano ma stabile: serve a inquadrare e a illuminare.
    /// </summary>
    public static Rettangolo? DallaTesta(byte[] persona, int larghezza, int altezza, int larghezzaVideo, int altezzaVideo)
    {
        var minimo = Math.Max(2, larghezza / 50);
        var cima = -1;
        for (var y = 0; y < altezza && cima < 0; y++)
        {
            var conta = 0;
            for (var x = 0; x < larghezza; x++) if (persona[y * larghezza + x] >= 128) conta++;
            if (conta >= minimo) cima = y;
        }
        if (cima < 0 || cima > altezza * 0.8) return null;
        // La riga della testa: il 6–12% dell'altezza sotto la cima. Larghezza e centro: mediana delle righe.
        var larghezze = new List<int>();
        var centri = new List<double>();
        var fine = Math.Min(altezza - 1, cima + Math.Max(2, (int)(altezza * 0.12)));
        for (var y = cima + Math.Max(1, (int)(altezza * 0.04)); y <= fine; y++)
        {
            int primo = -1, ultimo = -1;
            for (var x = 0; x < larghezza; x++)
            {
                if (persona[y * larghezza + x] < 128) continue;
                if (primo < 0) primo = x;
                ultimo = x;
            }
            if (primo < 0) continue;
            larghezze.Add(ultimo - primo + 1);
            centri.Add((primo + ultimo + 1) / 2.0);
        }
        if (larghezze.Count == 0) return null;
        larghezze.Sort();
        centri.Sort();
        var larghezzaTesta = (double)larghezze[larghezze.Count / 2] / larghezza;
        var centro = centri[centri.Count / 2] / larghezza;
        // Il volto è un po' più stretto della testa (capelli) e comincia poco sotto la cima.
        var larghezzaVolto = larghezzaTesta * 0.8;
        var altezzaVolto = larghezzaVolto * 1.3 * larghezzaVideo / Math.Max(1, altezzaVideo);
        var alto = (double)cima / altezza + altezzaVolto * 0.15;
        return new Rettangolo(centro - larghezzaVolto / 2, alto, larghezzaVolto, Math.Min(altezzaVolto, 1 - alto));
    }

    private static (int Primo, int Ultimo) Estremi(int[] conti, int totale)
    {
        var taglio = totale * 0.02;
        int primo = 0, ultimo = conti.Length - 1;
        double somma = 0;
        for (; primo < conti.Length - 1; primo++)
        {
            somma += conti[primo];
            if (somma > taglio) break;
        }
        somma = 0;
        for (; ultimo > primo; ultimo--)
        {
            somma += conti[ultimo];
            if (somma > taglio) break;
        }
        return (primo, ultimo);
    }
}

/// <summary>
/// L'inquadratura automatica (come InquadraturaAutomatica.swift dell'iPhone e MollaInquadratura del Mac): uno zoom digitale
/// da 1× a 1,6× che tiene i volti al centro, con una molla smorzata in modo critico (arriva senza oscillare in circa un
/// secondo e mezzo), una zona morta contro i tremolii e il ritorno lento all'inquadratura intera senza volti per 2
/// secondi o da spenta. Coordinate normalizzate con l'origine in alto (sul Mac in basso: il segno di y cambia).
/// </summary>
public sealed class MollaInquadratura
{
    public const double ZoomMassimo = 1.6;

    /// <summary>Centro (normalizzato) e zoom del riquadro da mostrare.</summary>
    public readonly record struct Riquadro(double X, double Y, double Zoom)
    {
        public static Riquadro Intero => new(0.5, 0.5, 1);

        /// <summary>Il rettangolo da ritagliare, in pixel di un'immagine <paramref name="larghezza"/>×<paramref name="altezza"/>.</summary>
        public (double X, double Y, double Larghezza, double Altezza) Ritaglio(int larghezza, int altezza)
        {
            var l = larghezza / Zoom;
            var a = altezza / Zoom;
            return (X * larghezza - l / 2, Y * altezza - a / 2, l, a);
        }
    }

    private Riquadro attuale = Riquadro.Intero;
    private (double X, double Y, double Zoom) velocita;
    private Riquadro bersaglio = Riquadro.Intero;
    private ulong ultimoVolto;
    private ulong ultimaAnalisi;
    private ulong tempo;

    /// <summary>Di nuovo all'inquadratura intera, ferma.</summary>
    public void Azzera()
    {
        attuale = bersaglio = Riquadro.Intero;
        velocita = default;
        ultimoVolto = ultimaAnalisi = tempo = 0;
    }

    /// <summary>Ancora zoomata: il motore deve continuare a lavorare anche da spenta.</summary>
    public bool InMovimento => attuale.Zoom > 1.002;

    /// <summary>
    /// Un passo della molla. <paramref name="volti"/>: normalizzati, null se vecchi; <paramref name="quando"/>: l'istante
    /// dell'analisi (µs). Restituisce il riquadro da ritagliare, o null all'inquadratura intera.
    /// </summary>
    public Riquadro? Passo(IReadOnlyList<Rettangolo>? volti, ulong? quando, bool acceso, double dt)
    {
        tempo += (ulong)(dt * 1_000_000);
        if (acceso && volti is not null && quando is ulong q && q != ultimaAnalisi)
        {
            ultimaAnalisi = q;
            if (volti.Count > 0)
            {
                ultimoVolto = tempo;
                var nuovo = RiquadroPer(volti);
                var soglia = 0.06 / bersaglio.Zoom;
                if (Math.Abs(nuovo.X - bersaglio.X) > soglia || Math.Abs(nuovo.Y - bersaglio.Y) > soglia
                    || Math.Abs(nuovo.Zoom - bersaglio.Zoom) / bersaglio.Zoom > 0.08)
                    bersaglio = nuovo;
            }
        }
        var senzaVolti = !acceso || tempo - ultimoVolto > 2_000_000;
        if (senzaVolti) bersaglio = Riquadro.Intero;
        var omega = senzaVolti ? 1.3 : 2.8;
        var (x, vx) = Molla(attuale.X, velocita.X, bersaglio.X, omega, dt);
        var (y, vy) = Molla(attuale.Y, velocita.Y, bersaglio.Y, omega, dt);
        var (z, vz) = Molla(attuale.Zoom, velocita.Zoom, bersaglio.Zoom, omega, dt);
        velocita = (vx, vy, vz);
        z = Math.Clamp(z, 1, ZoomMassimo);
        var meta = 0.5 / z;
        attuale = new Riquadro(Math.Clamp(x, meta, 1 - meta), Math.Clamp(y, meta, 1 - meta), z);
        if (attuale.Zoom <= 1.002)
        {
            if (!acceso)
            {
                attuale = Riquadro.Intero;
                velocita = default;
            }
            return null;
        }
        return attuale;
    }

    private static Riquadro RiquadroPer(IReadOnlyList<Rettangolo> volti)
    {
        var unione = volti[0];
        for (var i = 1; i < volti.Count; i++) unione = unione.Unione(volti[i]);
        var necessario = Math.Max(Math.Max(unione.Altezza * 3.2, unione.Larghezza * 2.2), 1 / ZoomMassimo);
        var zoom = Math.Clamp(1 / necessario, 1, ZoomMassimo);
        // Il volto un po' sopra il centro (origine in alto: il centro del riquadro scende).
        return new Riquadro(unione.CentroX, unione.CentroY + 0.12 / zoom, zoom);
    }

    private static (double Valore, double Velocita) Molla(double valore, double velocita, double verso, double omega, double dt)
    {
        var accelerazione = omega * omega * (verso - valore) - 2 * omega * velocita;
        velocita += accelerazione * dt;
        return (valore + velocita * dt, velocita);
    }
}
