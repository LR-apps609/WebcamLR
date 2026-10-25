using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>A che punto è il collegamento, per il menu e l'icona accanto all'orologio.</summary>
public enum StatoCollegamento
{
    NessunTelefono,
    Collegato,
    Riconnessione,
}

/// <summary>Lo stato in una riga di parole (round 2, funzioni 44 e 45), senza millisecondi.</summary>
public static class DescrizioneStato
{
    /// <summary>Windows taglia il testo dell'icona accanto all'orologio a 127 caratteri.</summary>
    public const int LunghezzaMassimaSuggerimento = 127;

    /// <summary>Per esempio «Collegato a iPhone di Ledion · Ottimo».</summary>
    public static string Riga(StatoCollegamento stato, string? nomeTelefono, int? latenzaMs = null)
    {
        var nome = string.IsNullOrWhiteSpace(nomeTelefono) ? "un telefono" : nomeTelefono.Trim();
        return stato switch
        {
            StatoCollegamento.Collegato when latenzaMs is int ms => $"Collegato a {nome} · {Qualita.Da(ms).Testo()}",
            StatoCollegamento.Collegato => $"Collegato a {nome}",
            StatoCollegamento.Riconnessione => $"Riconnessione a {nome}…",
            _ => "Nessun telefono",
        };
    }

    /// <summary>Nella modalità semplice: «Video in arrivo da Pixel 8», o «dal telefono» se il nome manca.</summary>
    public static string VideoInArrivo(string? nomeTelefono) =>
        string.IsNullOrWhiteSpace(nomeTelefono) ? "Video in arrivo dal telefono" : $"Video in arrivo da {nomeTelefono.Trim()}";

    /// <summary>Il nome della piattaforma da mostrare («iPhone», «Android»), dal campo «piattaforma» di «ciao».</summary>
    public static string NomePiattaforma(Piattaforma piattaforma) => piattaforma switch
    {
        Piattaforma.Iphone => "iPhone",
        Piattaforma.Android => "Android",
        Piattaforma.Mac => "Mac",
        Piattaforma.Windows => "Windows",
        _ => "Altro",
    };

    /// <summary>Il testo al passaggio del mouse sull'icona: «WebcamLR · » e la riga, tagliato se serve.</summary>
    public static string Suggerimento(StatoCollegamento stato, string? nomeTelefono, int? latenzaMs = null)
    {
        var testo = $"WebcamLR · {Riga(stato, nomeTelefono, latenzaMs)}";
        return testo.Length <= LunghezzaMassimaSuggerimento ? testo : testo[..(LunghezzaMassimaSuggerimento - 1)] + "…";
    }
}
