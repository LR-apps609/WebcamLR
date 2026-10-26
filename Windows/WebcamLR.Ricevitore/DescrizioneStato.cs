using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// A che punto è il collegamento, per il menu e l'icona accanto all'orologio. Si chiamava «StatoCollegamento»: il nome
/// ora è del messaggio del protocollo (<c>stato.collegamento</c>, le strade del telefono).
/// </summary>
public enum StatoRicezione
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
    public static string Riga(StatoRicezione stato, string? nomeTelefono, int? latenzaMs = null)
    {
        var nome = string.IsNullOrWhiteSpace(nomeTelefono) ? TestiRicevitore.T("Stato_UnTelefono") : nomeTelefono.Trim();
        return stato switch
        {
            StatoRicezione.Collegato when latenzaMs is int ms => TestiRicevitore.T("Stato_CollegatoAQualita", nome, Qualita.Da(ms).Testo()),
            StatoRicezione.Collegato => TestiRicevitore.T("Stato_CollegatoA", nome),
            StatoRicezione.Riconnessione => TestiRicevitore.T("Stato_RiconnessioneA", nome),
            _ => TestiRicevitore.T("Stato_NessunTelefono"),
        };
    }

    /// <summary>Nella modalità semplice: «Video in arrivo da Pixel 8», o «dal telefono» se il nome manca.</summary>
    public static string VideoInArrivo(string? nomeTelefono) =>
        string.IsNullOrWhiteSpace(nomeTelefono) ? TestiRicevitore.T("Stato_VideoDalTelefono") : TestiRicevitore.T("Stato_VideoDa", nomeTelefono.Trim());

    /// <summary>Il nome della piattaforma da mostrare («iPhone», «Android»), dal campo «piattaforma» di «ciao».</summary>
    public static string NomePiattaforma(Piattaforma piattaforma) => piattaforma switch
    {
        Piattaforma.Iphone => "iPhone",
        Piattaforma.Android => "Android",
        Piattaforma.Mac => "Mac",
        Piattaforma.Windows => "Windows",
        _ => TestiRicevitore.T("Piattaforma_Altro"),
    };

    /// <summary>Il testo al passaggio del mouse sull'icona: «WebcamLR · » e la riga, tagliato se serve.</summary>
    public static string Suggerimento(StatoRicezione stato, string? nomeTelefono, int? latenzaMs = null)
    {
        var testo = $"WebcamLR · {Riga(stato, nomeTelefono, latenzaMs)}";
        return testo.Length <= LunghezzaMassimaSuggerimento ? testo : testo[..(LunghezzaMassimaSuggerimento - 1)] + "…";
    }
}
