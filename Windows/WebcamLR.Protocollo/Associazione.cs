using System.Net;

namespace WebcamLR.Protocollo;

/// <summary>
/// Il contenuto del QR code che il computer mostra per farsi trovare senza mDNS (funzione 2).
/// Formato in Documenti/Protocollo.md: webcamlr://collega?h=&lt;indirizzi&gt;&amp;p=&lt;porta&gt;&amp;n=&lt;nome&gt;&amp;v=1
/// </summary>
/// <param name="Impronta">Versione 2: impronta della chiave del computer (k).</param>
/// <param name="Gettone">Versione 2: gettone di abbinamento (g).</param>
public sealed record Associazione(IReadOnlyList<string> Indirizzi, ushort Porta, string Nome, int Versione = Servizio.VersioneProtocollo,
    string? Impronta = null, string? Gettone = null)
{
    public string Testo =>
        $"webcamlr://collega?h={string.Join(",", Indirizzi.Select(Uri.EscapeDataString))}" +
        $"&p={Porta}&n={Uri.EscapeDataString(Nome)}&v={Versione}" +
        (Impronta is null ? "" : $"&k={Impronta}") + (Gettone is null ? "" : $"&g={Gettone}");

    /// <summary>Legge un QR code di WebcamLR; null se non lo è.</summary>
    public static Associazione? Leggi(string testo)
    {
        const string inizio = "webcamlr://collega?";
        if (!testo.StartsWith(inizio, StringComparison.Ordinal)) return null;
        var valori = new Dictionary<string, string>();
        foreach (var coppia in testo[inizio.Length..].Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var uguale = coppia.IndexOf('=');
            if (uguale <= 0) continue;
            valori.TryAdd(coppia[..uguale], coppia[(uguale + 1)..]);
        }
        var indirizzi = valori.GetValueOrDefault("h", "").Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.UnescapeDataString).ToList();
        if (indirizzi.Count == 0) return null;
        var porta = ushort.TryParse(valori.GetValueOrDefault("p"), out var p) ? p : Servizio.PortaPredefinita;
        var nome = Uri.UnescapeDataString(valori.GetValueOrDefault("n", ""));
        var versione = int.TryParse(valori.GetValueOrDefault("v"), out var v) ? v : Servizio.VersioneProtocollo;
        return new Associazione(indirizzi, porta, nome.Length > 0 ? nome : indirizzi[0], versione,
            valori.GetValueOrDefault("k") is { Length: > 0 } k ? k : null,
            valori.GetValueOrDefault("g") is { Length: > 0 } g ? g : null);
    }

    public bool Equals(Associazione? altra) =>
        altra is not null && Indirizzi.SequenceEqual(altra.Indirizzi) && Porta == altra.Porta
        && Nome == altra.Nome && Versione == altra.Versione && Impronta == altra.Impronta && Gettone == altra.Gettone;

    public override int GetHashCode() => HashCode.Combine(Indirizzi.Count, Porta, Nome, Versione);
}
