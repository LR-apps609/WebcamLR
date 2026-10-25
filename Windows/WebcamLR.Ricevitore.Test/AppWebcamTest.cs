using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>«App che usano la webcam»: i nomi dalle chiavi della privacy di Windows.</summary>
public class AppWebcamTest
{
    [Theory]
    [InlineData("C:#Program Files#Zoom#bin#Zoom.exe", "Zoom")]
    [InlineData("C:#Program Files (x86)#Microsoft#Edge#Application#msedge.exe", "Edge")]
    [InlineData("C:#Users#ledion#AppData#Local#Discord#app-1.0#Discord.exe", "Discord")]
    [InlineData("C:#Program Files#obs-studio#bin#64bit#obs64.exe", "OBS")]
    [InlineData("Microsoft.WindowsCamera_8wekyb3d8bbwe", "Fotocamera")]
    [InlineData("MSTeams_8wekyb3d8bbwe", "Teams")]
    [InlineData("5319275A.WhatsAppDesktop_cv1g1gvanyjgm", "WhatsApp")]
    [InlineData("C:#Strumenti#nuovaapp.exe", "Nuovaapp")]
    public void NomiLeggibili(string chiave, string nome) => Assert.Equal(nome, AppWebcam.Nome(chiave));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("C:#Users#ledion#WebcamLR#WebcamLR.exe")]
    public void NienteNome(string? chiave) => Assert.Null(AppWebcam.Nome(chiave));

    [Fact]
    public void SoloQuelleInUsoSenzaDoppioni()
    {
        var elenco = AppWebcam.Elenco([
            ("C:#Program Files#Zoom#bin#Zoom.exe", 1000, 0),
            ("MSTeams_8wekyb3d8bbwe", 1000, 0),
            ("C:#x#ms-teams.exe", 1000, 0),
            ("C:#x#chrome.exe", 1000, 2000),
            ("C:#x#firefox.exe", 0, 0),
        ]);
        Assert.Equal(["Teams", "Zoom"], elenco);
    }
}
