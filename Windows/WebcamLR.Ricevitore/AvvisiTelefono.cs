using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>Cosa il telefono fa sapere e vale un avviso (round 2, funzioni 39 e 49). Il caldo viene prima della batteria.</summary>
public enum AvvisoTelefono
{
    Nessuno,
    BatteriaBassa,
    MoltoCaldo,
    Critico,
}

/// <summary>
/// Decide l'avviso dallo stato del telefono e dice quando è nuovo, per la barra sopra il video e le notifiche.
/// La batteria bassa scatta sotto il 20% senza caricatore e si spegne solo dal 25% o col caricatore,
/// così una batteria che balla tra 19 e 20 non manda una notifica al minuto.
/// </summary>
public sealed class SorveglianzaAvvisi
{
    public const int SogliaBatteria = 20;
    public const int SogliaBatteriaRientro = 25;

    public AvvisoTelefono Attuale { get; private set; }

    /// <summary>Restituisce l'avviso se è appena cambiato in uno nuovo da mostrare; null se nulla è cambiato o non c'è più avviso.</summary>
    public AvvisoTelefono? Aggiorna(StatoTelefono stato)
    {
        var prima = Attuale;
        Attuale = Da(stato, prima);
        return Attuale != prima && Attuale != AvvisoTelefono.Nessuno ? Attuale : null;
    }

    /// <summary>Telefono scollegato o nuovo: si riparte da capo.</summary>
    public void Azzera() => Attuale = AvvisoTelefono.Nessuno;

    public static AvvisoTelefono Da(StatoTelefono stato, AvvisoTelefono precedente = AvvisoTelefono.Nessuno)
    {
        if (stato.Temperatura == Temperatura.Critica) return AvvisoTelefono.Critico;
        if (stato.Temperatura == Temperatura.MoltoCalda) return AvvisoTelefono.MoltoCaldo;
        // Batteria negativa: il telefono non la conosce.
        if (stato.InCarica || stato.Batteria < 0) return AvvisoTelefono.Nessuno;
        var soglia = precedente == AvvisoTelefono.BatteriaBassa ? SogliaBatteriaRientro : SogliaBatteria;
        return stato.Batteria < soglia ? AvvisoTelefono.BatteriaBassa : AvvisoTelefono.Nessuno;
    }

    public static (string Titolo, string Messaggio) Testi(AvvisoTelefono avviso, StatoTelefono? stato) => avviso switch
    {
        AvvisoTelefono.Critico => ("Il telefono è troppo caldo.",
            "Il video potrebbe fermarsi: toglilo dal sole o dalla custodia e abbassa la qualità."),
        AvvisoTelefono.MoltoCaldo => ("Il telefono è molto caldo.",
            "Toglilo dal sole o dalla custodia; se continua, abbassa la qualità sul telefono."),
        AvvisoTelefono.BatteriaBassa => ($"Batteria del telefono al {stato?.Batteria ?? SogliaBatteria}%.",
            "Collega il caricatore per non perdere il video."),
        _ => ("", ""),
    };
}
