using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class IndirizziLocaliTest
{
    [Fact]
    public void IndirizziSenzaLoopback()
    {
        foreach (var indirizzo in IndirizziLocali.Ipv4())
        {
            Assert.DoesNotContain("127.0.0.1", indirizzo);
            Assert.False(indirizzo.StartsWith("169.254."));
            Assert.Equal(4, indirizzo.Split('.').Length);
        }
    }

    [Fact]
    public void QRCodeInPng()
    {
        var png = IndirizziLocali.QRCodePng(new Associazione(["192.168.1.20"], 52740, "PC di prova"));
        Assert.NotNull(png);
        Assert.Equal(new byte[] { 0x89, (byte)'P', (byte)'N', (byte)'G' }, png![..4]);
    }
}
