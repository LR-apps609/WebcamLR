namespace WebcamLR.Ricevitore;

/// <summary>
/// Qualità del collegamento in parole (round 2): le stesse soglie di Stile/Sources/Stile/Qualita.swift.
/// Sotto i 100 ms la latenza è buona per una chiamata.
/// </summary>
public enum QualitaCollegamento
{
    Ottima,
    Buona,
    Debole,
}

public static class Qualita
{
    /// <param name="perdite">Fotogrammi saltati negli ultimi secondi: anche con poca latenza, se si salta è debole.</param>
    public static QualitaCollegamento Da(int latenzaMs, int perdite = 0) =>
        latenzaMs >= 150 || perdite >= 10 ? QualitaCollegamento.Debole
        : latenzaMs >= 80 || perdite > 0 ? QualitaCollegamento.Buona
        : QualitaCollegamento.Ottima;

    /// <summary>
    /// Collaudo 20 (t06 B4): il ritardo è «debole» ma la rete va bene da sola (sotto «Debole») e la parte del PC
    /// (decodifica, effetti, coda: <paramref name="latenzaMs"/> meno <paramref name="reteMs"/>) è più grande di quella della
    /// rete. Allora il chip non dà la colpa al Wi-Fi: dice che il PC è sotto sforzo. Senza la parte di rete, falso.
    /// </summary>
    /// <param name="reteMs">Dalla cattura all'arrivo sul computer (StatisticheVideo.ArrivoMs).</param>
    public static bool ColpaDelPc(int latenzaMs, int? reteMs) =>
        Da(latenzaMs) == QualitaCollegamento.Debole && reteMs is int rete && rete >= 0
        && Da(rete) != QualitaCollegamento.Debole && latenzaMs - rete > rete;

    public static string Testo(this QualitaCollegamento qualita) => qualita switch
    {
        QualitaCollegamento.Ottima => TestiRicevitore.T("Qualita_Ottimo"),
        QualitaCollegamento.Buona => TestiRicevitore.T("Qualita_Buono"),
        _ => TestiRicevitore.T("Qualita_Debole"),
    };

    /// <summary>Tacche piene su tre, come il segnale del telefono.</summary>
    public static int Tacche(this QualitaCollegamento qualita) => qualita switch
    {
        QualitaCollegamento.Ottima => 3,
        QualitaCollegamento.Buona => 2,
        _ => 1,
    };
}

/// <summary>
/// Collaudo 20 (t03 B5): il verdetto del chip («PC sotto sforzo» o qualità della rete) con un po' di memoria. Con numeri
/// quasi uguali (221 ms con la rete a 101, 217 con la rete a 114) il chip saltava da «PC sotto sforzo» a «Debole» e ritorno:
/// chi guarda non sa se cambiare Wi-Fi o chiudere programmi. Ora il verdetto cambia solo dopo
/// <see cref="SecondiPerCambiare"/> misure di fila che dicono l'altro.
/// </summary>
public sealed class VerdettoChip
{
    /// <summary>Le misure di fila (una al secondo) che servono per cambiare verdetto.</summary>
    public const int SecondiPerCambiare = 3;

    private int diFila;

    /// <summary>Il verdetto attuale: vero se il ritardo è del PC.</summary>
    public bool ColpaDelPc { get; private set; }

    /// <summary>Una misura nuova (una al secondo); il verdetto da mostrare.</summary>
    public bool Aggiungi(int latenzaMs, int? reteMs)
    {
        var adesso = Qualita.ColpaDelPc(latenzaMs, reteMs);
        if (adesso == ColpaDelPc)
        {
            diFila = 0;
            return ColpaDelPc;
        }
        if (++diFila >= SecondiPerCambiare)
        {
            ColpaDelPc = adesso;
            diFila = 0;
        }
        return ColpaDelPc;
    }

    /// <summary>Telefono nuovo o video fermo: si riparte senza verdetto.</summary>
    public void Azzera()
    {
        ColpaDelPc = false;
        diFila = 0;
    }
}
