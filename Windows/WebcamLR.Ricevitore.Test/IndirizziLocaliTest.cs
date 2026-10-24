using System.Net;
using System.Net.NetworkInformation;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class IndirizziLocaliTest
{
    private static SchedaPerQR Scheda(string nome, string descrizione, NetworkInterfaceType tipo, string indirizzi, bool gateway = false) =>
        new(nome, descrizione, tipo, indirizzi.Split(',').Select(IPAddress.Parse).ToList(), gateway);

    private static readonly SchedaPerQR WiFi = Scheda("Wi-Fi", "Intel(R) Wi-Fi 6 AX201 160MHz", NetworkInterfaceType.Wireless80211, "192.168.1.20", gateway: true);
    private static readonly SchedaPerQR CavoDiRete = Scheda("Ethernet", "Realtek PCIe GbE Family Controller", NetworkInterfaceType.Ethernet, "10.0.0.5", gateway: true);
    private static readonly SchedaPerQR Hotspot = Scheda("Ethernet 3", "Apple Mobile Device Ethernet", NetworkInterfaceType.Ethernet, "172.20.10.2", gateway: true);
    private static readonly SchedaPerQR Thunderbolt = Scheda("Ethernet 4", "Thunderbolt(TM) Networking", NetworkInterfaceType.Ethernet, "192.168.50.1");
    private static readonly SchedaPerQR Loopback = Scheda("Loopback Pseudo-Interface 1", "Software Loopback Interface 1", NetworkInterfaceType.Loopback, "127.0.0.1");
    /// <summary>Il Tethering USB di Android: il telefono fa da router sul cavo (DHCP con gateway).</summary>
    private static readonly SchedaPerQR TetheringAndroid = Scheda("Ethernet 5", "Remote NDIS based Internet Sharing Device", NetworkInterfaceType.Ethernet, "192.168.42.100", gateway: true);

    [Fact]
    public void IndirizziVeriSenzaLoopback()
    {
        foreach (var indirizzo in IndirizziLocali.Ipv4())
        {
            Assert.DoesNotContain("127.0.0.1", indirizzo);
            Assert.Equal(4, indirizzo.Split('.').Length);
        }
    }

    [Fact]
    public void WiFiPoiCavoPoiHotspotPoiCavoDiretto()
    {
        // Elencate da Windows in ordine sparso: il QR le mette nell'ordine giusto.
        var scelti = IndirizziLocali.Scegli([Thunderbolt, Loopback, Hotspot, CavoDiRete, WiFi]);
        Assert.Equal(["192.168.1.20", "10.0.0.5", "172.20.10.2", "192.168.50.1"], scelti);
    }

    [Fact]
    public void TetheringAndroidNelQRDopoWiFiECavoDiRete()
    {
        // Prima avrebbe contato come un cavo di rete qualsiasi: ora ha il posto della rete del telefono.
        var scelti = IndirizziLocali.Scegli([TetheringAndroid, Thunderbolt, CavoDiRete, WiFi]);
        Assert.Equal(["192.168.1.20", "10.0.0.5", "192.168.42.100", "192.168.50.1"], scelti);
    }

    [Theory]
    [InlineData("Remote NDIS based Internet Sharing Device", true)]
    [InlineData("Remote NDIS based Internet Sharing Device #2", false)]
    [InlineData("SAMSUNG Mobile USB Remote NDIS Network Device", true)]
    [InlineData("UsbNcm Host Device", true)]
    [InlineData("UsbNcm Host Device", false)]
    public void TetheringAndroidRiconosciutoEMaiVirtuale(string descrizione, bool gateway)
    {
        // Senza gateway (telefono senza dati mobili) resta la rete del telefono, non un cavo diretto qualsiasi.
        var tethering = Scheda("Ethernet 8", descrizione, NetworkInterfaceType.Ethernet, "10.12.34.56", gateway);
        Assert.False(IndirizziLocali.Virtuale(tethering));
        Assert.Equal(2, IndirizziLocali.Priorita(tethering, IPAddress.Parse("10.12.34.56")));
        Assert.Equal(["192.168.1.20", "10.12.34.56"], IndirizziLocali.Scegli([tethering, WiFi]));
    }

    [Fact]
    public void SoloIlTetheringBastaPerIlQR()
    {
        // Il PC senza Wi-Fi né cavo di rete, solo con il telefono sul cavo.
        Assert.Equal(["192.168.42.100"], IndirizziLocali.Scegli([Loopback, TetheringAndroid]));
    }

    [Theory]
    [InlineData("vEthernet (WSL)", "Hyper-V Virtual Ethernet Adapter")]
    [InlineData("vEthernet (Default Switch)", "Hyper-V Virtual Ethernet Adapter #2")]
    [InlineData("Ethernet 2", "VirtualBox Host-Only Ethernet Adapter")]
    [InlineData("VMware Network Adapter VMnet8", "VMware Virtual Ethernet Adapter for VMnet8")]
    [InlineData("vEthernet (DockerNAT)", "Hyper-V Virtual Ethernet Adapter #3")]
    [InlineData("Ethernet 5", "TAP-Windows Adapter V9")]
    [InlineData("NordLynx", "NordLynx Tunnel")]
    [InlineData("Tailscale", "Tailscale Tunnel")]
    [InlineData("Connessione VPN", "WAN Miniport (IKEv2)")]
    [InlineData("Connessione di rete Bluetooth", "Bluetooth Device (Personal Area Network)")]
    public void SchedeVirtualiEscluse(string nome, string descrizione)
    {
        var virtuale = Scheda(nome, descrizione, NetworkInterfaceType.Ethernet, "172.28.16.1");
        Assert.True(IndirizziLocali.Virtuale(virtuale));
        Assert.Equal(["192.168.1.20"], IndirizziLocali.Scegli([virtuale, WiFi]));
    }

    [Fact]
    public void TunnelEPppEsclusiDalTipo()
    {
        Assert.True(IndirizziLocali.Virtuale(Scheda("Qualsiasi", "Qualsiasi", NetworkInterfaceType.Tunnel, "10.8.0.2")));
        Assert.True(IndirizziLocali.Virtuale(Scheda("Qualsiasi", "Qualsiasi", NetworkInterfaceType.Ppp, "10.8.0.2")));
        Assert.False(IndirizziLocali.Virtuale(WiFi));
    }

    [Fact]
    public void HotspotMobileDiWindowsResta()
    {
        // Il telefono collegato all'hotspot del PC: la scheda «virtuale» di Wi-Fi Direct è una rete vera.
        var hotspotPc = Scheda("Connessione alla rete locale (LAN)* 2", "Microsoft Wi-Fi Direct Virtual Adapter #2",
            NetworkInterfaceType.Wireless80211, "192.168.137.1");
        Assert.False(IndirizziLocali.Virtuale(hotspotPc));
        Assert.Equal(["192.168.1.20", "192.168.137.1"], IndirizziLocali.Scegli([hotspotPc, WiFi]));
    }

    [Fact]
    public void AdattatoreUsbConGatewayEUnCavoDiRete()
    {
        var dongle = Scheda("Ethernet 6", "Realtek USB GbE Family Controller", NetworkInterfaceType.Ethernet, "192.168.1.30", gateway: true);
        Assert.Equal(1, IndirizziLocali.Priorita(dongle, IPAddress.Parse("192.168.1.30")));
        Assert.Equal(3, IndirizziLocali.Priorita(Thunderbolt, IPAddress.Parse("192.168.50.1")));
    }

    [Fact]
    public void Automatico169SoloSeNonCeAltro()
    {
        var diretto = Scheda("Ethernet 4", "Thunderbolt(TM) Networking", NetworkInterfaceType.Ethernet, "169.254.10.20");
        Assert.Equal(["192.168.1.20"], IndirizziLocali.Scegli([diretto, WiFi]));
        Assert.Equal(["169.254.10.20"], IndirizziLocali.Scegli([diretto, Loopback]));
        Assert.Empty(IndirizziLocali.Scegli([Loopback]));
    }

    [Fact]
    public void APariTipoPrimaLaSchedaConGateway()
    {
        var senzaRouter = Scheda("Ethernet 7", "Intel(R) Ethernet Connection I219-V", NetworkInterfaceType.Ethernet, "192.168.10.1");
        Assert.Equal(["10.0.0.5", "192.168.10.1"], IndirizziLocali.Scegli([senzaRouter, CavoDiRete]));
    }

    [Fact]
    public void SoloIpv4SenzaDoppioniEAlMassimoSei()
    {
        var doppia = Scheda("Wi-Fi", "Intel(R) Wi-Fi", NetworkInterfaceType.Wireless80211, "fe80::1,192.168.1.20,192.168.1.20,::ffff:192.168.1.21");
        Assert.Equal(["192.168.1.20", "192.168.1.21"], IndirizziLocali.Scegli([doppia]));
        var tante = Scheda("Ethernet", "Intel", NetworkInterfaceType.Ethernet, string.Join(",", Enumerable.Range(1, 9).Select(i => $"10.0.0.{i}")));
        Assert.Equal(IndirizziLocali.MassimoIndirizzi, IndirizziLocali.Scegli([tante]).Count);
    }

    [Fact]
    public void TuttiGliIndirizziNelQR()
    {
        var indirizzi = IndirizziLocali.Scegli([CavoDiRete, WiFi]);
        var testo = new Associazione(indirizzi, 52740, "PC di prova").Testo;
        Assert.StartsWith("webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740", testo);
    }

    [Fact]
    public void QRCodeInPng()
    {
        var png = IndirizziLocali.QRCodePng(new Associazione(["192.168.1.20"], 52740, "PC di prova"));
        Assert.NotNull(png);
        Assert.Equal(new byte[] { 0x89, (byte)'P', (byte)'N', (byte)'G' }, png![..4]);
    }
}
