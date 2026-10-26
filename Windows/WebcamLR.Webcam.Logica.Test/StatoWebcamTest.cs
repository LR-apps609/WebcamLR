using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

public class StatoWebcamTest
{
    [Theory]
    [InlineData(19045, false)] // Windows 10 22H2
    [InlineData(21999, false)]
    [InlineData(22000, true)]  // Windows 11 21H2
    [InlineData(26100, true)]  // Windows 11 24H2
    public void MediaFoundationSoloSuWindows11(int build, bool supportato)
    {
        Assert.Equal(supportato, NomiWebcam.WindowsSupportato(build));
        // P23: Windows 10 non resta senza webcam, ha il filtro DirectShow.
        Assert.Equal(supportato ? TipoWebcam.MediaFoundation : TipoWebcam.DirectShow, NomiWebcam.TipoPer(build));
    }

    [Fact]
    public void OgniStatoHaUnaFrase()
    {
        foreach (var tipo in Enum.GetValues<TipoWebcam>())
        foreach (var stato in Enum.GetValues<StatoWebcam>())
            Assert.False(string.IsNullOrWhiteSpace(CodiciInstallazione.Descrivi(stato, tipo, LinguaAttesa.Italiano)));
        // Su Windows 10 si dice subito cosa non funziona: Fotocamera di Windows e nuovo Teams.
        Assert.Contains("Windows 10", CodiciInstallazione.Descrivi(StatoWebcam.NonInstallata, TipoWebcam.DirectShow, LinguaAttesa.Italiano));
        Assert.Contains("Teams nel browser", CodiciInstallazione.Descrivi(StatoWebcam.NonInstallata, TipoWebcam.DirectShow, LinguaAttesa.Italiano));
        Assert.DoesNotContain("non c'è ancora", CodiciInstallazione.Descrivi(StatoWebcam.NonInstallata, TipoWebcam.DirectShow, LinguaAttesa.Italiano));
    }

    [Fact]
    public void RiuscitaSenza32BitÈUnaRiuscitaConIstruzioni()
    {
        Assert.True(CodiciInstallazione.ÈRiuscita(CodiciInstallazione.Riuscita));
        Assert.True(CodiciInstallazione.ÈRiuscita(CodiciInstallazione.RiuscitaSenza32Bit));
        Assert.False(CodiciInstallazione.ÈRiuscita(CodiciInstallazione.CopiaFallita));
        Assert.False(CodiciInstallazione.ÈRiuscita(CodiciInstallazione.Annullata));
        var testo = CodiciInstallazione.Descrivi(CodiciInstallazione.RiuscitaSenza32Bit, LinguaAttesa.Italiano);
        Assert.Contains("x86", testo);
        Assert.Contains("Ripara", testo);
    }

    [Fact]
    public void InIngleseSeWindowsNonÈInItaliano()
    {
        Assert.Equal("Done.", CodiciInstallazione.Descrivi(CodiciInstallazione.Riuscita, LinguaAttesa.Inglese));
        Assert.Contains("Private networks", CodiciInstallazione.Descrivi(CodiciInstallazione.FirewallFallito, LinguaAttesa.Inglese));
        Assert.Contains("Report a bug", CodiciInstallazione.Descrivi(77, LinguaAttesa.Inglese));
        foreach (var tipo in Enum.GetValues<TipoWebcam>())
        foreach (var stato in Enum.GetValues<StatoWebcam>())
        {
            var inglese = CodiciInstallazione.Descrivi(stato, tipo, LinguaAttesa.Inglese);
            Assert.NotEqual(CodiciInstallazione.Descrivi(stato, tipo, LinguaAttesa.Italiano), inglese);
            Assert.DoesNotContain("«", inglese);
        }
    }

    [Fact]
    public void CodiciInParole()
    {
        Assert.Equal("Fatto.", CodiciInstallazione.Descrivi(CodiciInstallazione.Riuscita, LinguaAttesa.Italiano));
        Assert.Contains("Annullato", CodiciInstallazione.Descrivi(CodiciInstallazione.Annullata, LinguaAttesa.Italiano));
        Assert.Contains("0x80004005", CodiciInstallazione.Descrivi(unchecked((int)0x80004005), LinguaAttesa.Italiano));
        Assert.Contains("app desktop", CodiciInstallazione.Descrivi(unchecked((int)0x80070005), LinguaAttesa.Italiano));
        // Mai «errore sconosciuto» (Glossario): il codice e cosa fare.
        Assert.Contains("77", CodiciInstallazione.Descrivi(77, LinguaAttesa.Italiano));
        Assert.Contains("Segnala un bug", CodiciInstallazione.Descrivi(77, LinguaAttesa.Italiano));
    }

    [Fact]
    public void FormatiTuttiSedicinoniENv12Pari()
    {
        Assert.Equal(FormatiWebcam.Massimo, FormatiWebcam.Tutti.MaxBy(f => f.Byte));
        foreach (var formato in FormatiWebcam.Tutti)
        {
            Assert.Equal(formato.Larghezza * 9, formato.Altezza * 16);
            Assert.True(AnelloFotogrammi.DimensioniValide(formato.Larghezza, formato.Altezza));
            Assert.Contains(formato.Fps, new[] { 30, 60 });
        }
        Assert.Equal(new FormatoWebcam(1280, 720, 30), FormatiWebcam.Cerca(1280, 720));
        Assert.Equal(FormatiWebcam.Predefinito, FormatiWebcam.Cerca(1, 1));
        Assert.Equal(new FormatoWebcam(3840, 2160, 30), FormatiWebcam.Massimo);
        Assert.Equal(FormatiWebcam.Tutti.Count, FormatiWebcam.Tutti.Distinct().Count());
    }

    [Fact]
    public void FormatiDiP12()
    {
        // I primi quattro restano quelli di sempre, nello stesso ordine; poi 60 fps e 4K.
        Assert.Equal(
            [new(1920, 1080, 30), new(1280, 720, 30), new(960, 540, 30), new(640, 360, 30),
             new(1920, 1080, 60), new(1280, 720, 60), new FormatoWebcam(3840, 2160, 30)],
            FormatiWebcam.Tutti);
    }

    [Fact]
    public void TrovaConMisuraEFrequenza()
    {
        Assert.Equal(new FormatoWebcam(1920, 1080, 60), FormatiWebcam.Trova(1920, 1080, 60, 1));
        Assert.Equal(new FormatoWebcam(1920, 1080, 30), FormatiWebcam.Trova(1920, 1080, 30, 1));
        // 30000/1001 e 60000/1001 (29,97 e 59,94) come le chiedono alcune app.
        Assert.Equal(new FormatoWebcam(1280, 720, 30), FormatiWebcam.Trova(1280, 720, 30000, 1001));
        Assert.Equal(new FormatoWebcam(1280, 720, 60), FormatiWebcam.Trova(1280, 720, 60000, 1001));
        // Senza frequenza: il primo con quella misura, a 30 fps.
        Assert.Equal(new FormatoWebcam(1920, 1080, 30), FormatiWebcam.Trova(1920, 1080, 0, 0));
        Assert.Equal(new FormatoWebcam(3840, 2160, 30), FormatiWebcam.Trova(3840, 2160, 30, 1));
        Assert.Null(FormatiWebcam.Trova(3840, 2160, 60, 1));
        Assert.Null(FormatiWebcam.Trova(640, 360, 60, 1));
        Assert.Null(FormatiWebcam.Trova(800, 600, 30, 1));
    }

    [Fact]
    public void RitmoSegueLaFrequenza()
    {
        const long frequenza = 10_000_000;
        var trenta = new RitmoWebcam(30, frequenza);
        Assert.Equal(333_333, trenta.Durata100ns);
        Assert.Equal(frequenza / 30, trenta.IntervalloTick);
        // Come prima di P12: tra 28 e 38 ms.
        Assert.Equal(frequenza * 28 / 1000, trenta.MinimoTick);
        Assert.Equal(frequenza * 38 / 1000, trenta.MassimoTick);

        var sessanta = new RitmoWebcam(60, frequenza);
        Assert.Equal(166_666, sessanta.Durata100ns);
        Assert.Equal(frequenza / 60, sessanta.IntervalloTick);
        Assert.Equal(frequenza * 14 / 1000, sessanta.MinimoTick);
        Assert.Equal(frequenza * 19 / 1000, sessanta.MassimoTick);
        // La finestra contiene sempre l'intervallo.
        foreach (var r in new[] { trenta, sessanta })
            Assert.True(r.MinimoTick < r.IntervalloTick && r.IntervalloTick < r.MassimoTick);
    }

    [Fact]
    public void ClsidValido()
    {
        Assert.True(Guid.TryParse(NomiWebcam.Clsid, out _));
        Assert.StartsWith("{", NomiWebcam.ClsidTraGraffe);
        Assert.StartsWith(@"Global\", NomiWebcam.NomeMemoria);
        Assert.Contains("(A;;GA;;;LS)", NomiWebcam.SddlMemoria);
    }
}
