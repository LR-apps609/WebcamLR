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

    public static string Testo(this QualitaCollegamento qualita) => qualita switch
    {
        QualitaCollegamento.Ottima => "Ottimo",
        QualitaCollegamento.Buona => "Buono",
        _ => "Debole",
    };

    /// <summary>Tacche piene su tre, come il segnale del telefono.</summary>
    public static int Tacche(this QualitaCollegamento qualita) => qualita switch
    {
        QualitaCollegamento.Ottima => 3,
        QualitaCollegamento.Buona => 2,
        _ => 1,
    };
}
