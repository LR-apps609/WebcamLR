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

    /// <summary>
    /// La riga del registro quando l'avviso cambia (windows.md 2.1 e N4): all'inizio il titolo dell'avviso, alla fine
    /// che il caldo o la batteria bassa sono passati. Null se non è cambiato nulla.
    /// </summary>
    public static string? RigaRegistro(AvvisoTelefono prima, AvvisoTelefono dopo, StatoTelefono? stato)
    {
        if (prima == dopo) return null;
        if (dopo != AvvisoTelefono.Nessuno) return Testi(dopo, stato).Titolo;
        return prima == AvvisoTelefono.BatteriaBassa ? TestiRicevitore.T("Avviso_BatteriaFinito") : TestiRicevitore.T("Avviso_CaldoFinito");
    }

    /// <summary>
    /// Il caldo ha la precedenza, ma una batteria bassa insieme non resta nascosta (collaudo 20, t18 B3: al 7% con il
    /// telefono molto caldo il PC diceva solo del caldo): si aggiunge al messaggio.
    /// </summary>
    public static (string Titolo, string Messaggio) Testi(AvvisoTelefono avviso, StatoTelefono? stato) => avviso switch
    {
        AvvisoTelefono.Critico => (TestiRicevitore.T("Avviso_CriticoTitolo"), ConBatteria(TestiRicevitore.T("Avviso_Critico"), stato)),
        AvvisoTelefono.MoltoCaldo => (TestiRicevitore.T("Avviso_MoltoCaldoTitolo"), ConBatteria(TestiRicevitore.T("Avviso_MoltoCaldo"), stato)),
        AvvisoTelefono.BatteriaBassa => (TestiRicevitore.T("Avviso_BatteriaTitolo", stato?.Batteria ?? SogliaBatteria), TestiRicevitore.T("Avviso_Batteria")),
        _ => ("", ""),
    };

    private static string ConBatteria(string messaggio, StatoTelefono? stato) =>
        stato is { InCarica: false, Batteria: >= 0 and < SogliaBatteria } s
            ? $"{messaggio} {TestiRicevitore.T("Avviso_BatteriaTitolo", s.Batteria)} {TestiRicevitore.T("Avviso_Batteria")}"
            : messaggio;
}
