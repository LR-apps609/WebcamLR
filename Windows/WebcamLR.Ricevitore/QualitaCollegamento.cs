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
