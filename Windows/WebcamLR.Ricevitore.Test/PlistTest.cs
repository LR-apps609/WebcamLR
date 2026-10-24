using System.Buffers.Binary;
using System.Text;
using System.Xml;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class PlistTest
{
    [Fact]
    public void ScriveUnPlistXmlValido()
    {
        var dati = Plist.Scrivi(new Dictionary<string, object>
        {
            ["MessageType"] = "Connect",
            ["DeviceID"] = 7L,
            ["PortNumber"] = 1486,
            ["Nome"] = "Tom & Jerry <test>",
            ["Vero"] = true,
        });
        var testo = Encoding.UTF8.GetString(dati);
        Assert.StartsWith("<?xml version=\"1.0\" encoding=\"UTF-8\"?>", testo);
        Assert.Contains("<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\"", testo);

        // Letto con XmlDocument, senza il nostro lettore.
        var documento = new XmlDocument { XmlResolver = null };
        using (var lettore = XmlReader.Create(new MemoryStream(dati), new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore }))
            documento.Load(lettore);
        var dict = documento.SelectSingleNode("/plist[@version='1.0']/dict")!;
        Assert.Equal("MessageType", dict.SelectSingleNode("key[1]")!.InnerText);
        Assert.Equal("Connect", dict.SelectSingleNode("key[1]/following-sibling::*[1]")!.InnerText);
        Assert.Equal("integer", dict.SelectSingleNode("key[.='PortNumber']/following-sibling::*[1]")!.Name);
        Assert.Equal("1486", dict.SelectSingleNode("key[.='PortNumber']/following-sibling::*[1]")!.InnerText);
        Assert.Equal("Tom & Jerry <test>", dict.SelectSingleNode("key[.='Nome']/following-sibling::*[1]")!.InnerText);
        Assert.Equal("true", dict.SelectSingleNode("key[.='Vero']/following-sibling::*[1]")!.Name);
    }

    [Fact]
    public void LeggeUnAvvisoAttachedComeQuelloDiApple()
    {
        const string xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>DeviceID</key>
                <integer>12</integer>
                <key>MessageType</key>
                <string>Attached</string>
                <key>Properties</key>
                <dict>
                    <key>ConnectionSpeed</key>
                    <integer>480000000</integer>
                    <key>ConnectionType</key>
                    <string>USB</string>
                    <key>LocationID</key>
                    <integer>-1</integer>
                    <key>EscapedFullServiceName</key>
                    <data>
                    AQID
                    BA==
                    </data>
                    <key>Interfacce</key>
                    <array><string>usb</string><real>1.5</real><false/></array>
                </dict>
            </dict>
            </plist>
            """;
        var plist = Plist.Leggi(Encoding.UTF8.GetBytes(xml));
        Assert.Equal(12L, plist["DeviceID"]);
        Assert.Equal("Attached", plist["MessageType"]);
        var proprieta = Assert.IsType<Dictionary<string, object>>(plist["Properties"]);
        Assert.Equal("USB", proprieta["ConnectionType"]);
        Assert.Equal(480000000L, proprieta["ConnectionSpeed"]);
        Assert.Equal(-1L, proprieta["LocationID"]);
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, proprieta["EscapedFullServiceName"]);
        Assert.Equal(new List<object> { "usb", 1.5, false }, proprieta["Interfacce"]);
    }

    [Fact]
    public void ScrittoERiletto()
    {
        var originale = new Dictionary<string, object>
        {
            ["MessageType"] = "Listen",
            ["ClientVersionString"] = "WebcamLR",
            ["kLibUSBMuxVersion"] = 3,
            ["Interno"] = new Dictionary<string, object> { ["A"] = "à è ì", ["B"] = false },
        };
        var riletto = Plist.Leggi(Plist.Scrivi(originale));
        Assert.Equal("Listen", riletto["MessageType"]);
        Assert.Equal(3L, riletto["kLibUSBMuxVersion"]);
        var interno = Assert.IsType<Dictionary<string, object>>(riletto["Interno"]);
        Assert.Equal("à è ì", interno["A"]);
        Assert.Equal(false, interno["B"]);
    }

    [Theory]
    [InlineData("non è xml")]
    [InlineData("<plist version=\"1.0\"><array/></plist>")]
    [InlineData("<plist version=\"1.0\"><dict><key>A</key><integer>dieci</integer></dict></plist>")]
    [InlineData("<plist version=\"1.0\"><dict><string>senza chiave</string></dict></plist>")]
    public void PlistSbagliatoDaErrore(string xml)
    {
        Assert.Throws<FormatException>(() => Plist.Leggi(Encoding.UTF8.GetBytes(xml)));
    }

    [Fact]
    public void NonScaricaLaDtdNeEntitaEsterne()
    {
        // Un'entità esterna non deve essere risolta (né letta da disco o rete).
        const string xml = """
            <?xml version="1.0"?>
            <!DOCTYPE plist [<!ENTITY segreto SYSTEM "file:///etc/passwd">]>
            <plist version="1.0"><dict><key>A</key><string>&segreto;</string></dict></plist>
            """;
        try
        {
            var plist = Plist.Leggi(Encoding.UTF8.GetBytes(xml));
            Assert.DoesNotContain("root", (string)plist["A"]);
        }
        catch (FormatException) { }
    }

    [Fact]
    public void IntestazioneUsbmuxLittleEndian()
    {
        var messaggio = MessaggioUsbmux.Codifica(0x01020304, new Dictionary<string, object> { ["MessageType"] = "Listen" });
        Assert.Equal((uint)messaggio.Length, BinaryPrimitives.ReadUInt32LittleEndian(messaggio));
        // Byte per byte: versione 1, tipo 8, etichetta 0x01020304 scritte dal byte meno significativo.
        Assert.Equal(new byte[] { 1, 0, 0, 0, 8, 0, 0, 0, 4, 3, 2, 1 }, messaggio[4..16]);
        Assert.Equal((byte)(messaggio.Length & 0xFF), messaggio[0]);
        Assert.StartsWith("<?xml", Encoding.UTF8.GetString(messaggio, 16, messaggio.Length - 16));
    }

    [Fact]
    public async Task LeggeUnMessaggioSenzaUnByteDiPiu()
    {
        var messaggio = MessaggioUsbmux.Codifica(5, new Dictionary<string, object> { ["MessageType"] = "Result", ["Number"] = 0 });
        // Dopo il Result arrivano già i byte dell'iPhone: devono restare nel flusso.
        var flusso = new MemoryStream([.. messaggio, 0xAA, 0xBB]);
        var letto = await MessaggioUsbmux.LeggiAsync(flusso, CancellationToken.None);
        Assert.NotNull(letto);
        Assert.Equal(5u, letto!.Etichetta);
        Assert.Equal("Result", letto.Tipo);
        Assert.Equal(0, letto.Numero("Number"));
        Assert.Equal(0xAA, flusso.ReadByte());
    }

    [Fact]
    public async Task IntestazioneSbagliataDaErrore()
    {
        var messaggio = MessaggioUsbmux.Codifica(1, new Dictionary<string, object> { ["MessageType"] = "Result" });
        var tipoBinario = (byte[])messaggio.Clone();
        tipoBinario[8] = 7; // plist binario: non lo usiamo
        await Assert.ThrowsAsync<FormatException>(() => MessaggioUsbmux.LeggiAsync(new MemoryStream(tipoBinario), CancellationToken.None));
        var troppoLungo = (byte[])messaggio.Clone();
        BinaryPrimitives.WriteUInt32LittleEndian(troppoLungo, 0x7FFFFFFF);
        await Assert.ThrowsAsync<FormatException>(() => MessaggioUsbmux.LeggiAsync(new MemoryStream(troppoLungo), CancellationToken.None));
        // Chiusa a metà: nessun messaggio.
        Assert.Null(await MessaggioUsbmux.LeggiAsync(new MemoryStream(messaggio[..20]), CancellationToken.None));
    }

    [Fact]
    public void PortaInOrdineDiRete()
    {
        Assert.Equal(1486, ClienteUsbmux.InOrdineDiRete(52741));
        Assert.Equal(0x05CE, ClienteUsbmux.InOrdineDiRete(0xCE05));
        Assert.Equal(52741, ClienteUsbmux.InOrdineDiRete(ClienteUsbmux.InOrdineDiRete(52741)));
    }
}
