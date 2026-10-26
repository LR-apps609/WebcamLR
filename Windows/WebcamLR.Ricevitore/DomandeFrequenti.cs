using System.Globalization;
using System.Text;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Domande frequenti (1.4), dentro l'app e senza Internet: gli stessi testi di Stile/Sources/Stile/DomandeFrequenti.swift.
/// </summary>
public sealed record DomandaFrequente(string Id, string Domanda, string Risposta, IReadOnlyList<string> Parole)
{
    /// <summary>Vero se domanda, risposta o parole contengono tutte le parole cercate, senza badare a maiuscole e accenti.</summary>
    public bool Corrisponde(string ricerca)
    {
        var parti = Normalizza(ricerca).Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parti.Length == 0) return true;
        var testo = Normalizza(string.Join(" ", new[] { Domanda, Risposta }.Concat(Parole)));
        return parti.All(testo.Contains);
    }

    internal static string Normalizza(string testo)
    {
        var scomposto = testo.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var risultato = new StringBuilder(scomposto.Length);
        foreach (var carattere in scomposto)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(carattere) != UnicodeCategory.NonSpacingMark) risultato.Append(carattere);
        }
        return risultato.ToString();
    }
}

public static class DomandeFrequenti
{
    /// <summary>Nella lingua attuale; le parole di ricerca restano in italiano e valgono in tutte e due le lingue.</summary>
    public static IReadOnlyList<DomandaFrequente> Tutte =>
    [
        new("non-trova", TestiRicevitore.T("Domanda_NonTrova"),
            TestiRicevitore.T("Risposta_NonTrova"),
            ["cerca", "lista", "vuota", "compare", "trovato", "iphone", "android"]),
        new("rete-locale", TestiRicevitore.T("Domanda_ReteLocale"),
            TestiRicevitore.T("Risposta_ReteLocale"),
            ["permesso", "privacy", "negato", "iphone", "ios"]),
        new("rete-ospiti", TestiRicevitore.T("Domanda_ReteOspiti"),
            TestiRicevitore.T("Risposta_ReteOspiti"),
            ["albergo", "hotel", "ufficio", "scuola", "università", "pubblica", "isolamento", "hotspot"]),
        new("cavo", TestiRicevitore.T("Domanda_Cavo"),
            TestiRicevitore.T("Risposta_Cavo"),
            ["usb", "cavo", "lightning", "usb-c", "filo", "tethering", "android", "iphone"]),
        new("codice", TestiRicevitore.T("Domanda_Codice"),
            TestiRicevitore.T("Risposta_Codice"),
            ["4 cifre", "consentire", "abbinamento", "conferma"]),
        new("identita", TestiRicevitore.T("Domanda_Identita"),
            TestiRicevitore.T("Risposta_Identita"),
            ["sicurezza", "cambiata", "diverso"]),
        new("ritardo", TestiRicevitore.T("Domanda_Ritardo"),
            TestiRicevitore.T("Risposta_Ritardo"),
            ["lag", "latenza", "lento", "scatti", "ms", "millisecondi", "blocca"]),
        new("zoom-teams", TestiRicevitore.T("Domanda_ZoomTeams"),
            TestiRicevitore.T("Risposta_ZoomTeams"),
            ["zoom", "teams", "meet", "facetime", "obs", "videocamera", "webcam virtuale", "microfono", "audio"]),
        new("caldo", TestiRicevitore.T("Domanda_Caldo"),
            TestiRicevitore.T("Risposta_Caldo"),
            ["calore", "caldo", "scotta", "temperatura"]),
        new("batteria", TestiRicevitore.T("Domanda_Batteria"),
            TestiRicevitore.T("Risposta_Batteria"),
            ["batteria", "carica", "consumo"]),
        new("nero", TestiRicevitore.T("Domanda_Nero"),
            TestiRicevitore.T("Risposta_Nero"),
            ["nero", "schermo", "niente", "hevc", "vuoto"]),
        new("firewall", TestiRicevitore.T("Domanda_Firewall"),
            TestiRicevitore.T("Risposta_Firewall"),
            ["windows", "firewall", "defender", "rete pubblica", "tethering"]),
        new("qualita", TestiRicevitore.T("Domanda_Qualita"),
            TestiRicevitore.T("Risposta_Qualita"),
            ["qualità", "nitido", "4k", "1080p", "risoluzione", "luce"]),
        new("privacy", TestiRicevitore.T("Domanda_Privacy"),
            TestiRicevitore.T("Risposta_Privacy"),
            ["privacy", "sicuro", "internet", "cloud", "dati"]),
        new("aggiorna", TestiRicevitore.T("Domanda_Aggiorna"),
            TestiRicevitore.T("Risposta_Aggiorna"),
            ["aggiornare", "versione", "vecchia", "aggiornamento", "scarica"]),
        new("costo", TestiRicevitore.T("Domanda_Costo"),
            TestiRicevitore.T("Risposta_Costo"),
            ["prezzo", "costo", "gratis", "pro", "abbonamento", "filigrana", "pubblicità", "acquisto", "account"]),
    ];

    public static DomandaFrequente? Risposta(string id) => Tutte.FirstOrDefault(d => d.Id == id);

    public static IEnumerable<DomandaFrequente> Cerca(string ricerca) => Tutte.Where(d => d.Corrisponde(ricerca));
}
