using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class TipoCollegamentoTest
{
    private static readonly SchedaDiRete[] Schede =
    [
        new(NetworkInterfaceType.Loopback, [IPAddress.Loopback]),
        new(NetworkInterfaceType.Ethernet, [IPAddress.Parse("10.0.0.5"), IPAddress.Parse("fe80::1")]),
        new(NetworkInterfaceType.Wireless80211, [IPAddress.Parse("192.168.1.20")]),
        new(NetworkInterfaceType.GigabitEthernet, [IPAddress.Parse("192.168.50.2")]),
        new(NetworkInterfaceType.Tunnel, [IPAddress.Parse("100.64.0.3")]),
    ];

    [Theory]
    [InlineData("192.168.1.20", TipoCollegamento.WiFi)]
    [InlineData("10.0.0.5", TipoCollegamento.CavoDiRete)]
    [InlineData("192.168.50.2", TipoCollegamento.CavoDiRete)]
    [InlineData("::ffff:192.168.1.20", TipoCollegamento.WiFi)]   // IPv4 dentro IPv6, come su una presa doppia
    [InlineData("172.20.10.3", TipoCollegamento.Hotspot)]
    public void DallaSchedaCheHaLIndirizzo(string locale, TipoCollegamento atteso)
    {
        Assert.Equal(atteso, Collegamenti.Da(IPAddress.Parse(locale), Schede));
    }

    [Theory]
    [InlineData("127.0.0.1")]      // loopback: né Wi-Fi né cavo di rete
    [InlineData("100.64.0.3")]     // VPN
    [InlineData("192.168.9.9")]    // nessuna scheda
    public void SconosciutoSenzaSchedaWiFiOCavo(string locale)
    {
        Assert.Null(Collegamenti.Da(IPAddress.Parse(locale), Schede));
    }

    [Fact]
    public void HotspotSoloNellaSuaRete()
    {
        Assert.True(Collegamenti.DallHotspot(IPAddress.Parse("172.20.10.14")));
        Assert.False(Collegamenti.DallHotspot(IPAddress.Parse("172.20.10.17")));
        Assert.False(Collegamenti.DallHotspot(IPAddress.Parse("172.20.11.2")));
        Assert.False(Collegamenti.DallHotspot(IPAddress.IPv6Loopback));
    }

    [Fact]
    public void TestiComeNelGlossario()
    {
        Assert.Equal("Wi-Fi", TipoCollegamento.WiFi.Testo());
        Assert.Equal("Cavo USB", TipoCollegamento.CavoUsb.Testo());
        Assert.Equal("Cavo di rete", TipoCollegamento.CavoDiRete.Testo());
        Assert.Null(TipoCollegamento.CavoUsb.Consiglio());
        Assert.Contains("cavo USB", TipoCollegamento.WiFi.Consiglio());
    }

    [Fact]
    public async Task PresaDalCavoEPresaInLoopback()
    {
        using var ascolto = new TcpListener(IPAddress.Loopback, 0);
        ascolto.Start();
        using var cliente = new TcpClient();
        await cliente.ConnectAsync(IPAddress.Loopback, ((IPEndPoint)ascolto.LocalEndpoint).Port);
        using var presa = await ascolto.AcceptSocketAsync();
        // Dal cavo USB la presa è verso il servizio di Apple su 127.0.0.1: conta che arriva dal cavo.
        Assert.Equal(TipoCollegamento.CavoUsb, Collegamenti.DellaPresa(presa, viaCavo: true));
        // Dalla rete, su loopback, nessuna scheda Wi-Fi o di rete: sconosciuto, l'indicatore non compare.
        Assert.Null(Collegamenti.DellaPresa(presa, viaCavo: false));
    }
}
