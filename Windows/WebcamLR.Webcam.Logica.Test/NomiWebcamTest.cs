using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

public class NomiWebcamTest
{
    [Theory]
    [InlineData("WebcamLR")]
    [InlineData("webcamlr")]
    [InlineData("WebcamLR (Windows Virtual Camera)")]
    [InlineData("WebcamLR (Windows Test Virtual Camera)")]
    [InlineData("  WebcamLR (Windows Virtual Camera) ")]
    public void RiconosceIlNomeConQuelloCheAggiungeWindows(string nome) => Assert.True(NomiWebcam.ÈLaWebcam(nome));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Integrated Camera")]
    [InlineData("WebcamLR2")]
    [InlineData("WebcamLR (altro)")]
    [InlineData("OBS Virtual Camera")]
    public void NonScambiaAltreFotocamere(string? nome) => Assert.False(NomiWebcam.ÈLaWebcam(nome));

    [Fact]
    public void ClsidTraGraffeComeLoVuoleMFCreateVirtualCamera()
    {
        Assert.Equal("{" + NomiWebcam.Clsid + "}", NomiWebcam.ClsidTraGraffe);
        Assert.True(Guid.TryParseExact(NomiWebcam.ClsidTraGraffe, "B", out _));
    }

    [Fact]
    public void OggettiCondivisiNelloSpazioGlobale()
    {
        // La sorgente gira nella sessione 0, l'app in quella dell'utente: senza «Global\» non si vedrebbero.
        Assert.StartsWith(@"Global\", NomiWebcam.NomeMemoria);
        Assert.StartsWith(@"Global\", NomiWebcam.NomeEvento);
    }

    [Theory]
    [InlineData(NomiWebcam.SddlMemoria)]
    [InlineData(NomiWebcam.SddlEvento)]
    public void PermessiPerLocalServiceELUtenteCollegato(string sddl)
    {
        Assert.StartsWith("D:P", sddl);
        Assert.Contains("(A;;GA;;;LS)", sddl);
        Assert.Contains("(A;;GA;;;SY)", sddl);
        Assert.Matches(@"\(A;;(GA|GRGW);;;IU\)", sddl);
    }
}
