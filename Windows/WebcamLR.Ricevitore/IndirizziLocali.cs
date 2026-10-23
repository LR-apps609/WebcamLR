using System.Net.NetworkInformation;
using System.Net.Sockets;
using QRCoder;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>Indirizzi IPv4 del computer nella rete locale e QR code per l'iPhone (funzione 2).</summary>
public static class IndirizziLocali
{
    /// <summary>Wi-Fi per primo, poi cavo, poi il resto; niente loopback né 169.254.x.x.</summary>
    public static IReadOnlyList<string> Ipv4() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(s => s.OperationalStatus == OperationalStatus.Up
                        && s.NetworkInterfaceType is not (NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel))
            .OrderBy(s => s.NetworkInterfaceType switch
            {
                NetworkInterfaceType.Wireless80211 => 0,
                NetworkInterfaceType.Ethernet => 1,
                _ => 2,
            })
            .SelectMany(s => s.GetIPProperties().UnicastAddresses)
            .Select(u => u.Address)
            .Where(a => a.AddressFamily == AddressFamily.InterNetwork && !a.ToString().StartsWith("169.254.") && !System.Net.IPAddress.IsLoopback(a))
            .Select(a => a.ToString())
            .Distinct()
            .ToList();

    /// <summary>Il QR code da mostrare, come immagine PNG; null se il computer non ha una rete.</summary>
    public static byte[]? QRCodePng(Associazione associazione, int pixelPerModulo = 8)
    {
        using var generatore = new QRCodeGenerator();
        using var dati = generatore.CreateQrCode(associazione.Testo, QRCodeGenerator.ECCLevel.M);
        return new PngByteQRCode(dati).GetGraphic(pixelPerModulo);
    }
}
