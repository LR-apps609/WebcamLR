using System.Globalization;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Il gobbo dal lato del computer (Documenti/Protocollo.md, «Gobbo»): ricorda testo, velocità, dimensione e dove è
/// arrivato il telefono, per rimandare tutto quando lo stesso telefono si ricollega. Il testo vive sul telefono solo per
/// la sessione. Non è thread-safe: la usa solo il thread dell'interfaccia.
/// </summary>
public sealed class MemoriaGobbo
{
    public const double VelocitaPredefinita = 1.0;

    /// <summary>L'ultimo testo mandato al telefono (già tagliato).</summary>
    public string Testo { get; private set; } = "";
    public double Velocita { get; private set; } = VelocitaPredefinita;
    public string Dimensione { get; private set; } = DimensioniGobbo.Media;
    /// <summary>Scorre: dall'ultimo stato del telefono, o dall'ultimo comando.</summary>
    public bool Attivo { get; private set; }
    /// <summary>Da 0 a 1, dall'ultimo stato del telefono.</summary>
    public double Posizione { get; private set; }
    /// <summary>Vero dopo il primo testo mandato a questo telefono.</summary>
    public bool Inviato { get; private set; }

    /// <summary>Il testo come lo riceve il telefono: al massimo 20 000 caratteri, senza spezzare un carattere doppio (emoji).</summary>
    public static string Taglia(string testo)
    {
        var normale = testo.Replace("\r\n", "\n").Replace('\r', '\n');
        if (normale.Length <= Gobbo.LunghezzaMassima) return normale;
        var fine = Gobbo.LunghezzaMassima;
        if (char.IsHighSurrogate(normale[fine - 1])) fine--;
        return normale[..fine];
    }

    public static double VelocitaValida(double velocita) =>
        double.IsFinite(velocita) ? Math.Clamp(velocita, Gobbo.VelocitaMinima, Gobbo.VelocitaMassima) : VelocitaPredefinita;

    public static string DimensioneValida(string? dimensione) =>
        dimensione is DimensioniGobbo.Piccola or DimensioniGobbo.Grande ? dimensione : DimensioniGobbo.Media;

    /// <summary>
    /// Prepara il messaggio da mandare (testo tagliato, velocità nei limiti, dimensione valida) e lo ricorda.
    /// Un testo nuovo riparte dall'inizio, come sul telefono.
    /// </summary>
    public Gobbo Prepara(Gobbo gobbo)
    {
        var pronto = gobbo with
        {
            Testo = gobbo.Testo is { } t ? Taglia(t) : null,
            Velocita = gobbo.Velocita is double v ? VelocitaValida(v) : null,
            Dimensione = gobbo.Dimensione is { } d ? DimensioneValida(d) : null,
            Posizione = gobbo.Posizione is double p ? (double.IsFinite(p) ? Math.Clamp(p, 0, 1) : 0) : null,
        };
        if (pronto.Testo is { } testo)
        {
            Testo = testo;
            Inviato = true;
            Posizione = 0;
        }
        if (pronto.Velocita is double velocita) Velocita = velocita;
        if (pronto.Dimensione is { } dimensione) Dimensione = dimensione;
        if (pronto.Attivo is bool attivo) Attivo = attivo;
        if (pronto.Posizione is double posizione) Posizione = posizione;
        return pronto;
    }

    /// <summary>Velocità e dimensione scelte prima di mandare il testo: si ricordano e partono con il testo.</summary>
    public void Imposta(double? velocita = null, string? dimensione = null)
    {
        if (velocita is double v) Velocita = VelocitaValida(v);
        if (dimensione is not null) Dimensione = DimensioneValida(dimensione);
    }

    /// <summary>Lo stato del gobbo dal telefono; vero se è cambiato qualcosa da mostrare.</summary>
    public bool Stato(StatoGobbo? stato)
    {
        if (stato is null || !Inviato) return false;
        var posizione = double.IsFinite(stato.Posizione) ? Math.Clamp(stato.Posizione, 0, 1) : Posizione;
        if (stato.Attivo == Attivo && posizione == Posizione) return false;
        Attivo = stato.Attivo;
        Posizione = posizione;
        return true;
    }

    /// <summary>Per lo stesso telefono che torna: il gobbo completo, dall'ultima posizione; null se non c'era un gobbo.</summary>
    public Gobbo? DaRimandare() =>
        Inviato ? new Gobbo(Testo, Velocita, Attivo, Dimensione, Posizione) : null;

    /// <summary>Un altro telefono: il testo resta nella finestra, ma a quel telefono non è mai arrivato.</summary>
    public void Azzera()
    {
        Inviato = false;
        Attivo = false;
        Posizione = 0;
    }

    /// <summary>«42%», per la barra di avanzamento.</summary>
    public static string TestoPosizione(double posizione) =>
        $"{Math.Round(Math.Clamp(posizione, 0, 1) * 100):0}%";

    /// <summary>«1,5 righe al secondo» («1.5 lines per second» in inglese).</summary>
    public static string TestoVelocita(double velocita) =>
        TestiRicevitore.T("Gobbo_Velocita", Lingua.Decimale(VelocitaValida(velocita), "0.0"));

    /// <summary>«1.234 / 20.000 caratteri» («1,234 / 20,000 characters» in inglese).</summary>
    public static string TestoCaratteri(int caratteri) =>
        TestiRicevitore.T("Gobbo_Caratteri", Lingua.Migliaia(caratteri), Lingua.Migliaia(Gobbo.LunghezzaMassima));
}
