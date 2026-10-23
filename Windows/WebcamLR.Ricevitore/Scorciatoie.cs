namespace WebcamLR.Ricevitore;

/// <summary>
/// Scorciatoie da tastiera della finestra (round 2, funzione 43), come sul Mac:
/// 1–4 scelgono l'obiettivo nell'ordine dell'elenco, + e − cambiano lo zoom a passi di 0,5×.
/// </summary>
public static class Scorciatoie
{
    public const double PassoZoom = 0.5;
    public const int ObiettiviConTasto = 4;

    /// <summary>Il tasto <paramref name="numero"/> (1–4) diventa l'indice dell'obiettivo, se c'è.</summary>
    public static int? Obiettivo(int numero, int obiettiviDisponibili) =>
        numero >= 1 && numero <= Math.Min(ObiettiviConTasto, obiettiviDisponibili) ? numero - 1 : null;

    /// <summary>
    /// Lo zoom dopo un + (<paramref name="verso"/> = 1) o un − (−1): si va al passo successivo,
    /// così da 1,3× un + porta a 1,5× e un − a 1×. Mai sotto 1× né sopra il massimo del telefono.
    /// </summary>
    public static double Zoom(double attuale, double massimo, int verso)
    {
        const double tolleranza = 1e-6;
        var passi = attuale / PassoZoom;
        var prossimo = verso > 0
            ? (Math.Floor(passi + tolleranza) + 1) * PassoZoom
            : (Math.Ceiling(passi - tolleranza) - 1) * PassoZoom;
        return Math.Clamp(prossimo, 1, Math.Max(1, massimo));
    }
}
