using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Come è collegato il telefono (aggiornamento 1.2, Documenti/Protocollo.md «Tipo di collegamento attivo»):
/// ognuno lo ricava dal proprio lato, senza messaggi nuovi.
/// </summary>
public enum TipoCollegamento
{
    WiFi,
    CavoUsb,
    CavoDiRete,
    /// <summary>Il PC è collegato all'Hotspot personale dell'iPhone (rete 172.20.10.0/28), in Wi-Fi o con il cavo.</summary>
    Hotspot,
}

/// <summary>Una scheda di rete del PC: tipo e indirizzi, per riconoscere da quale è arrivato il telefono.</summary>
public sealed record SchedaDiRete(NetworkInterfaceType Tipo, IReadOnlyList<IPAddress> Indirizzi);

public static class Collegamenti
{
    public static string Testo(this TipoCollegamento tipo) => tipo switch
    {
        TipoCollegamento.CavoUsb => "Cavo USB",
        TipoCollegamento.CavoDiRete => "Cavo di rete",
        TipoCollegamento.Hotspot => "Hotspot",
        _ => "Wi-Fi",
    };

    /// <summary>Un consiglio quando esiste un collegamento migliore; null se è già il migliore.</summary>
    public static string? Consiglio(this TipoCollegamento tipo) => tipo switch
    {
        TipoCollegamento.CavoUsb => null,
        TipoCollegamento.Hotspot => "Collegato all'Hotspot personale dell'iPhone. Con il cavo USB non serve l'hotspot ed è più stabile.",
        TipoCollegamento.CavoDiRete => "Il PC è sul cavo di rete, l'iPhone in Wi-Fi. Con il cavo USB il video è ancora più stabile.",
        _ => "Collegato in Wi-Fi. Con il cavo USB il video è più stabile e intanto l'iPhone si ricarica.",
    };

    /// <summary>Il tipo di una scheda di rete di Windows; null se non è né Wi-Fi né cavo di rete.</summary>
    public static TipoCollegamento? DaScheda(NetworkInterfaceType tipo) => tipo switch
    {
        NetworkInterfaceType.Wireless80211 => TipoCollegamento.WiFi,
        NetworkInterfaceType.Ethernet or NetworkInterfaceType.GigabitEthernet or NetworkInterfaceType.FastEthernetT
            or NetworkInterfaceType.FastEthernetFx or NetworkInterfaceType.Ethernet3Megabit => TipoCollegamento.CavoDiRete,
        _ => null,
    };

    /// <summary>
    /// Dall'indirizzo locale della connessione: la scheda del PC che ha quell'indirizzo dice se il telefono
    /// è arrivato dal Wi-Fi o dal cavo di rete. Null se nessuna scheda lo ha (per esempio 127.0.0.1).
    /// </summary>
    public static TipoCollegamento? Da(IPAddress locale, IEnumerable<SchedaDiRete> schede)
    {
        if (locale.IsIPv4MappedToIPv6) locale = locale.MapToIPv4();
        if (DallHotspot(locale)) return TipoCollegamento.Hotspot;
        foreach (var scheda in schede)
        {
            if (scheda.Indirizzi.Any(indirizzo => (indirizzo.IsIPv4MappedToIPv6 ? indirizzo.MapToIPv4() : indirizzo).Equals(locale)))
                return DaScheda(scheda.Tipo);
        }
        return null;
    }

    /// <summary>L'Hotspot personale dell'iPhone dà ai computer indirizzi 172.20.10.1–14.</summary>
    public static bool DallHotspot(IPAddress indirizzo)
    {
        if (indirizzo.AddressFamily != AddressFamily.InterNetwork) return false;
        var parti = indirizzo.GetAddressBytes();
        return parti[0] == 172 && parti[1] == 20 && parti[2] == 10 && parti[3] < 16;
    }

    /// <summary>Per una connessione appena arrivata: dal cavo USB, oppure dalla scheda di rete che l'ha ricevuta.</summary>
    public static TipoCollegamento? DellaPresa(Socket presa, bool viaCavo)
    {
        if (viaCavo) return TipoCollegamento.CavoUsb;
        try
        {
            return presa.LocalEndPoint is IPEndPoint locale ? Da(locale.Address, SchedeAttive()) : null;
        }
        catch (Exception) { return null; }
    }

    /// <summary>Le schede di rete accese del PC.</summary>
    public static IEnumerable<SchedaDiRete> SchedeAttive() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(scheda => scheda.OperationalStatus == OperationalStatus.Up)
            .Select(scheda => new SchedaDiRete(scheda.NetworkInterfaceType,
                scheda.GetIPProperties().UnicastAddresses.Select(u => u.Address).ToList()));
}
