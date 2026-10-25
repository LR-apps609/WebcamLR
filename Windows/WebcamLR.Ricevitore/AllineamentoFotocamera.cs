using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// I comandi della fotocamera seguono il telefono (dalla 1.14, Documenti/Protocollo.md «Comandi della fotocamera in
/// stato»), come sul Mac (TelefonoCollegato.allineaControlli): pizzico, cambio di obiettivo, torcia spenta dalla
/// frontale, ISO e tempo scelti sul telefono. I valori appena mandati dal PC restano per <see cref="Precedenza"/>:
/// lo <c>stato</c> partito prima del comando non riporta indietro un cursore. Un telefono di prima della 1.14 non manda
/// questi campi: allora, a ogni cambio di obiettivo, zoom a 1 e torcia spenta, come fa il telefono.
/// Non è thread-safe: la usa solo il thread dell'interfaccia.
/// </summary>
public sealed class AllineamentoFotocamera
{
    public static readonly TimeSpan PrecedenzaPredefinita = TimeSpan.FromMilliseconds(1500);

    private const string Zoom = "zoom", Torcia = "torcia", Esposizione = "esposizione", Bianco = "bianco", Manuale = "isoTempo";

    private readonly Dictionary<string, long> toccati = [];

    public AllineamentoFotocamera(TimeSpan? precedenza = null)
    {
        Precedenza = precedenza ?? PrecedenzaPredefinita;
    }

    public TimeSpan Precedenza { get; }

    /// <summary>Un comando della fotocamera parte dal PC: per un attimo lo <c>stato</c> non sovrascrive quei valori.</summary>
    public void Segna(Comando comando, long adessoMs)
    {
        if (comando.Zoom is not null || comando.Obiettivo is not null) toccati[Zoom] = adessoMs;
        if (comando.Torcia is not null || comando.Obiettivo is not null) toccati[Torcia] = adessoMs;
        if (comando.Esposizione is not null) toccati[Esposizione] = adessoMs;
        if (comando.Bianco is not null) toccati[Bianco] = adessoMs;
        if (comando.Iso is not null || comando.Tempo is not null) toccati[Manuale] = adessoMs;
    }

    /// <summary>Un altro telefono, o lo stesso che riparte: niente precedenze in sospeso.</summary>
    public void Azzera() => toccati.Clear();

    /// <summary>
    /// I comandi come li deve mostrare il PC dopo questo <c>stato</c>. <paramref name="obiettivoPrima"/>: quello dello
    /// <c>stato</c> precedente (null al primo). <paramref name="capacita"/>: per lo zoom massimo e i limiti ISO.
    /// </summary>
    public ComandiFotocamera Allinea(ComandiFotocamera attuali, StatoTelefono stato, string? obiettivoPrima,
        Capacita? capacita, long adessoMs)
    {
        bool Libero(string chiave) => !toccati.TryGetValue(chiave, out var quando) || adessoMs - quando >= (long)Precedenza.TotalMilliseconds;
        var nuovi = attuali;
        var obiettivoCambiato = obiettivoPrima is not null && obiettivoPrima != stato.Obiettivo;
        if (stato.Zoom is double zoom)
        {
            if (Libero(Zoom) && double.IsFinite(zoom))
            {
                var massimo = capacita is { ZoomMassimo: > 1 and var m } && double.IsFinite(m) ? m : Math.Max(1, zoom);
                nuovi = nuovi with { Zoom = Math.Clamp(zoom, 1, Math.Max(1, massimo)) };
            }
        }
        else if (obiettivoCambiato)
        {
            nuovi = nuovi with { Zoom = 1 };
        }
        if (stato.Torcia is bool torcia)
        {
            if (Libero(Torcia)) nuovi = nuovi with { Torcia = torcia };
        }
        else if (obiettivoCambiato)
        {
            nuovi = nuovi with { Torcia = false };
        }
        if (stato.Esposizione is double esposizione && double.IsFinite(esposizione) && Libero(Esposizione))
            nuovi = nuovi with { Esposizione = Math.Clamp(Math.Round(esposizione, 1), -2, 2) };
        if (stato.Bianco is int bianco && Libero(Bianco))
            nuovi = bianco <= 0 ? nuovi with { BiancoAutomatico = true } : nuovi with { BiancoAutomatico = false, Bianco = Math.Clamp(bianco, 2500, 7500) };
        if (stato.Iso is double iso && stato.Tempo is int tempo && Libero(Manuale))
        {
            var limiti = capacita is { IsoMinimo: double minimo, IsoMassimo: double massimo2 } && massimo2 > minimo;
            var manuale = iso > 0 && tempo > 0 && double.IsFinite(iso) && limiti;
            nuovi = manuale
                ? nuovi with { Manuale = true, Iso = Math.Clamp(iso, capacita!.IsoMinimo!.Value, capacita.IsoMassimo!.Value), Tempo = tempo }
                : nuovi with { Manuale = false };
        }
        return nuovi;
    }
}
