using System.Globalization;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Avvio rapido misurato (1.11): il tempo dall'arrivo della connessione (accettazione TCP o canale del cavo)
/// al primo fotogramma decodificato e mostrato, con le tappe in mezzo per capire dove si perde tempo.
/// Si scrive da qualsiasi thread; ogni tappa conta solo la prima volta.
/// </summary>
public sealed class MisuraAvvio
{
    private readonly object blocco = new();
    private readonly Func<ulong> orologio;
    private ulong? stretta;
    private ulong? benvenuto;
    private ulong? primoFotogramma;
    private ulong? mostrato;
    private bool conConferma;

    /// <param name="arrivo">L'istante dell'accettazione (orologio monotono in µs); di serie adesso.</param>
    /// <param name="orologio">Solo per i test.</param>
    public MisuraAvvio(ulong? arrivo = null, Func<ulong>? orologio = null)
    {
        this.orologio = orologio ?? Orologio.Adesso;
        Arrivo = arrivo ?? this.orologio();
    }

    public ulong Arrivo { get; }

    /// <summary>Risposta alla stretta di mano spedita.</summary>
    public void Stretta() => Segna(ref stretta);

    /// <summary>Telefono accettato, «benvenuto» spedito.</summary>
    public void Benvenuto() => Segna(ref benvenuto);

    /// <summary>Arrivato il primo fotogramma video (cifrato e decifrato).</summary>
    public void PrimoFotogramma() => Segna(ref primoFotogramma);

    /// <summary>L'utente ha dovuto confermare il telefono: il tempo comprende la sua risposta.</summary>
    public void Conferma()
    {
        lock (blocco) conConferma = true;
    }

    /// <summary>Il primo fotogramma è a schermo. Vero solo la prima volta: allora va scritto nel registro.</summary>
    public bool Mostrato()
    {
        lock (blocco)
        {
            if (mostrato is not null) return false;
            mostrato = orologio();
            return true;
        }
    }

    /// <summary>Dall'arrivo al primo fotogramma a schermo; null finché non c'è.</summary>
    public TimeSpan? Totale
    {
        get { lock (blocco) return Durata(mostrato); }
    }

    /// <summary>«Avvio: 0,9 s», per la modalità avanzata; null finché il video non è a schermo.</summary>
    public string? Testo => Totale is { } totale ? TestoDi(totale) : null;

    /// <summary>La riga del registro: il totale e le tappe in millisecondi dall'arrivo.</summary>
    public string? Riga
    {
        get
        {
            lock (blocco)
            {
                if (Durata(mostrato) is not { } totale) return null;
                var tappe = new List<string>();
                if (Durata(stretta) is { } s) tappe.Add(TestiRicevitore.T("Avvio_Stretta", Millisecondi(s)));
                if (Durata(benvenuto) is { } b) tappe.Add(TestiRicevitore.T("Avvio_Benvenuto", Millisecondi(b)));
                if (Durata(primoFotogramma) is { } f) tappe.Add(TestiRicevitore.T("Avvio_PrimoFotogramma", Millisecondi(f)));
                tappe.Add(TestiRicevitore.T("Avvio_ASchermo", Millisecondi(totale)));
                var riga = $"{TestoDi(totale)} ({string.Join(" · ", tappe)})";
                return conConferma ? TestiRicevitore.T("Avvio_ConConferma", riga) : riga;
            }
        }
    }

    /// <summary>Secondi con un decimale: «Avvio: 0,9 s» («Startup: 0.9 s» in inglese); sotto il decimo «Avvio: 0,1 s».</summary>
    public static string TestoDi(TimeSpan durata)
    {
        var secondi = Math.Max(0.1, Math.Round(durata.TotalSeconds, 1, MidpointRounding.AwayFromZero));
        return TestiRicevitore.T("Avvio_Testo", Lingua.Decimale(secondi, "0.0"));
    }

    private static string Millisecondi(TimeSpan durata) => $"{(long)Math.Round(durata.TotalMilliseconds)} ms";

    private void Segna(ref ulong? tappa)
    {
        lock (blocco) tappa ??= orologio();
    }

    private TimeSpan? Durata(ulong? tappa) =>
        tappa is { } fine ? TimeSpan.FromTicks((long)(fine - Math.Min(fine, Arrivo)) * 10) : null;
}
