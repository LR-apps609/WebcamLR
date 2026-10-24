using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using QRCoder;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>Una scheda di rete del PC come la vede la scelta degli indirizzi per il QR code.</summary>
/// <param name="Nome">Il nome della connessione («Wi-Fi», «vEthernet (WSL)»).</param>
/// <param name="Descrizione">Il nome del dispositivo («Intel(R) Wi-Fi 6 AX201», «Hyper-V Virtual Ethernet Adapter»).</param>
/// <param name="ConGateway">La scheda ha un gateway predefinito: di solito è la rete «vera», da mettere prima.</param>
public sealed record SchedaPerQR(string Nome, string Descrizione, NetworkInterfaceType Tipo, IReadOnlyList<IPAddress> Indirizzi,
    bool ConGateway = false);

/// <summary>
/// Indirizzi IPv4 del computer nella rete locale e QR code per l'iPhone (funzione 2, aggiornamento 1.10).
/// Il QR elenca tutti gli indirizzi utili, il più probabile per primo: il telefono li prova tutti insieme
/// e usa il primo che risponde.
/// </summary>
public static class IndirizziLocali
{
    /// <summary>Oltre questi indirizzi il QR diventa fitto e difficile da inquadrare.</summary>
    public const int MassimoIndirizzi = 6;

    /// <summary>
    /// Parole che nel nome o nella descrizione indicano una scheda virtuale: macchine virtuali, WSL, Docker,
    /// VPN. Il telefono non le raggiunge, e nel QR farebbero solo perdere tempo.
    /// Non c'è «Virtual» da solo: «Microsoft Wi-Fi Direct Virtual Adapter» è l'hotspot mobile di Windows,
    /// a cui il telefono può essere collegato davvero.
    /// </summary>
    private static readonly string[] ParoleVirtuali =
    [
        "Hyper-V", "vEthernet", "VirtualBox", "VMware", "WSL", "Docker", "Parallels", "VPN", "TAP-Windows",
        "Wintun", "WireGuard", "OpenVPN", "Tailscale", "ZeroTier", "Hamachi", "AnyConnect", "GlobalProtect",
        "PANGP", "Fortinet", "NordLynx", "Mullvad", "Npcap", "Loopback", "Teredo", "isatap", "Kernel Debug",
        "Bluetooth",
    ];

    /// <summary>Parole delle reti fatte con un cavo diretto (USB, Thunderbolt), senza router: vanno per ultime.</summary>
    private static readonly string[] ParoleCavoDiretto = ["USB", "Thunderbolt", "RNDIS", "Apple Mobile Device"];

    /// <summary>Gli indirizzi da mettere nel QR code, in ordine.</summary>
    public static IReadOnlyList<string> Ipv4() => Scegli(Schede());

    /// <summary>Le schede di rete accese del PC. Una scheda che non risponde si salta.</summary>
    public static IReadOnlyList<SchedaPerQR> Schede()
    {
        var schede = new List<SchedaPerQR>();
        NetworkInterface[] tutte;
        try { tutte = NetworkInterface.GetAllNetworkInterfaces(); }
        catch (NetworkInformationException) { return schede; }
        foreach (var scheda in tutte)
        {
            try
            {
                if (scheda.OperationalStatus != OperationalStatus.Up) continue;
                var proprieta = scheda.GetIPProperties();
                schede.Add(new SchedaPerQR(scheda.Name, scheda.Description, scheda.NetworkInterfaceType,
                    proprieta.UnicastAddresses.Select(u => u.Address).ToList(),
                    proprieta.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork
                                                        && !g.Address.Equals(IPAddress.Any))));
            }
            catch (Exception) { }
        }
        return schede;
    }

    /// <summary>
    /// La scelta, provata con i test: niente loopback, niente schede virtuali (riconosciute dal nome o dal tipo),
    /// 169.254.x.x solo se non c'è nient'altro. Ordine: Wi-Fi, cavo di rete, Hotspot personale dell'iPhone
    /// (172.20.10.x), poi i cavi diretti USB e Thunderbolt (senza gateway) e il resto. A pari tipo prima le schede con un gateway.
    /// </summary>
    public static IReadOnlyList<string> Scegli(IEnumerable<SchedaPerQR> schede)
    {
        var candidati = new List<(IPAddress Indirizzo, int Priorita, bool ConGateway, int Ordine)>();
        var ordine = 0;
        foreach (var scheda in schede)
        {
            if (Virtuale(scheda)) continue;
            foreach (var grezzo in scheda.Indirizzi)
            {
                var indirizzo = grezzo.IsIPv4MappedToIPv6 ? grezzo.MapToIPv4() : grezzo;
                if (indirizzo.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(indirizzo)) continue;
                candidati.Add((indirizzo, Priorita(scheda, indirizzo), scheda.ConGateway, ordine++));
            }
        }
        var utili = candidati.Where(c => !Automatico(c.Indirizzo)).ToList();
        // Senza nessuna rete vera (per esempio un cavo diretto senza DHCP) anche 169.254 può servire.
        if (utili.Count == 0) utili = candidati;
        return utili
            .OrderBy(c => c.Priorita)
            .ThenBy(c => c.ConGateway ? 0 : 1)
            .ThenBy(c => c.Ordine)
            .Select(c => c.Indirizzo.ToString())
            .Distinct()
            .Take(MassimoIndirizzi)
            .ToList();
    }

    /// <summary>0 Wi-Fi, 1 cavo di rete, 2 Hotspot dell'iPhone, 3 cavo diretto USB o Thunderbolt, 4 il resto.</summary>
    public static int Priorita(SchedaPerQR scheda, IPAddress indirizzo)
    {
        if (Collegamenti.DallHotspot(indirizzo)) return 2;
        // Un adattatore USB con il gateway è un cavo di rete verso il router, non un cavo diretto.
        if (!scheda.ConGateway && Contiene(scheda, ParoleCavoDiretto)) return 3;
        return Collegamenti.DaScheda(scheda.Tipo) switch
        {
            TipoCollegamento.WiFi => 0,
            TipoCollegamento.CavoDiRete => 1,
            _ => 4,
        };
    }

    /// <summary>Scheda virtuale (VPN, Hyper-V, VirtualBox, WSL, Docker…) o di servizio (loopback, tunnel).</summary>
    public static bool Virtuale(SchedaPerQR scheda) =>
        scheda.Tipo is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel or NetworkInterfaceType.Ppp
        || Contiene(scheda, ParoleVirtuali);

    /// <summary>169.254.x.x: l'indirizzo che Windows si dà da solo quando la rete non risponde.</summary>
    public static bool Automatico(IPAddress indirizzo)
    {
        if (indirizzo.AddressFamily != AddressFamily.InterNetwork) return false;
        var parti = indirizzo.GetAddressBytes();
        return parti[0] == 169 && parti[1] == 254;
    }

    private static bool Contiene(SchedaPerQR scheda, IEnumerable<string> parole) =>
        parole.Any(parola => scheda.Nome.Contains(parola, StringComparison.OrdinalIgnoreCase)
                             || scheda.Descrizione.Contains(parola, StringComparison.OrdinalIgnoreCase));

    /// <summary>Il QR code da mostrare, come immagine PNG; null se il computer non ha una rete.</summary>
    public static byte[]? QRCodePng(Associazione associazione, int pixelPerModulo = 8)
    {
        using var generatore = new QRCodeGenerator();
        using var dati = generatore.CreateQrCode(associazione.Testo, QRCodeGenerator.ECCLevel.M);
        return new PngByteQRCode(dati).GetGraphic(pixelPerModulo);
    }
}
