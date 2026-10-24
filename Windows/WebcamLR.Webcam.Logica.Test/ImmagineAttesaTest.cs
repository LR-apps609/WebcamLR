using System.Text.RegularExpressions;
using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

public class ImmagineAttesaTest
{
    [Fact]
    public void ITestiUsanoSoloCaratteriDisegnati()
    {
        foreach (var testo in new[] { ImmagineAttesa.Titolo, ImmagineAttesa.Messaggio, ImmagineAttesa.Suggerimento })
            foreach (var carattere in testo)
                Assert.True(CarattereAPunti.Conosciuto(carattere), $"Manca il disegno di «{carattere}»");
    }

    [Fact]
    public void DisegniDiCinqueColonne()
    {
        foreach (var carattere in "WebcamLR in attesa del telefono Apri sull'iPhone·C")
        {
            var disegno = CarattereAPunti.Disegno(carattere);
            Assert.InRange(disegno.Length, 7, CarattereAPunti.Altezza);
            Assert.All(disegno, riga => Assert.Equal(CarattereAPunti.LarghezzaCarattere, riga.Length));
        }
    }

    [Theory]
    [InlineData(1920, 1080)]
    [InlineData(1280, 720)]
    [InlineData(960, 540)]
    [InlineData(640, 360)]
    public void FondoDelloStileETestoChiaro(int l, int a)
    {
        var bgra = ImmagineAttesa.CreaBgra(l, a);
        // L'angolo è il colore «Fondo» di App.xaml.
        Assert.Equal(ColoriStile.Fondo.Blu, bgra[0]);
        Assert.Equal(ColoriStile.Fondo.Verde, bgra[1]);
        Assert.Equal(ColoriStile.Fondo.Rosso, bgra[2]);
        // C'è testo chiaro e c'è il ciano del marchio.
        var chiari = 0;
        var ciano = 0;
        for (var i = 0; i < bgra.Length; i += 4)
        {
            if (bgra[i + 2] == ColoriStile.Testo.Rosso && bgra[i + 1] == ColoriStile.Testo.Verde) chiari++;
            if (bgra[i + 2] == ColoriStile.Ciano.Rosso && bgra[i + 1] == ColoriStile.Ciano.Verde) ciano++;
        }
        Assert.True(chiari > l * a / 400, $"testo chiaro: {chiari} pixel");
        Assert.True(ciano > l * a / 1000, $"ciano: {ciano} pixel");
        // Il testo sta tutto dentro l'immagine: i bordi restano fondo.
        for (var x = 0; x < l; x++)
        {
            Assert.Equal(ColoriStile.Fondo.Rosso, bgra[x * 4 + 2]);
            Assert.Equal(ColoriStile.Fondo.Rosso, bgra[((a - 1) * l + x) * 4 + 2]);
        }
    }

    [Fact]
    public void Nv12DellaMisuraGiusta()
    {
        var nv12 = ImmagineAttesa.CreaNv12(1280, 720);
        Assert.Equal(1280 * 720 * 3 / 2, nv12.Length);
        var fondo = ColoriStile.Fondo;
        Assert.Equal(ConversioneVideo.Luminanza(fondo.Rosso, fondo.Verde, fondo.Blu), nv12[0]);
    }

    [Fact]
    public void ColoriUgualiAdAppXaml()
    {
        var xaml = File.ReadAllText(Path.Combine(CartellaWindows(), "WebcamLR.App", "App.xaml"));
        foreach (var (nome, colore) in new[]
        {
            ("Fondo", ColoriStile.Fondo), ("Scheda", ColoriStile.Scheda), ("Linea", ColoriStile.Linea),
            ("Testo", ColoriStile.Testo), ("TestoSecondario", ColoriStile.TestoSecondario), ("Ciano", ColoriStile.Ciano),
        })
        {
            var trovato = Regex.Match(xaml, $"x:Key=\"{nome}\" Color=\"(#[0-9A-Fa-f]{{6}})\"");
            Assert.True(trovato.Success, $"{nome} non trovato in App.xaml");
            Assert.Equal(trovato.Groups[1].Value.ToUpperInvariant(), colore.Esadecimale);
        }
    }

    private static string CartellaWindows()
    {
        for (var cartella = new DirectoryInfo(AppContext.BaseDirectory); cartella is not null; cartella = cartella.Parent)
        {
            if (Directory.Exists(Path.Combine(cartella.FullName, "WebcamLR.App"))) return cartella.FullName;
        }
        throw new DirectoryNotFoundException("Cartella Windows non trovata");
    }
}

public class StatoWebcamTest
{
    [Theory]
    [InlineData(19045, false)] // Windows 10 22H2
    [InlineData(21999, false)]
    [InlineData(22000, true)]  // Windows 11 21H2
    [InlineData(26100, true)]  // Windows 11 24H2
    public void SoloWindows11(int build, bool supportato) => Assert.Equal(supportato, NomiWebcam.WindowsSupportato(build));

    [Fact]
    public void OgniStatoHaUnaFrase()
    {
        foreach (var stato in Enum.GetValues<StatoWebcam>())
            Assert.False(string.IsNullOrWhiteSpace(CodiciInstallazione.Descrivi(stato)));
        Assert.Contains("Windows 10", CodiciInstallazione.Descrivi(StatoWebcam.NonSupportata));
    }

    [Fact]
    public void CodiciInParole()
    {
        Assert.Equal("Fatto.", CodiciInstallazione.Descrivi(CodiciInstallazione.Riuscita));
        Assert.Contains("Annullato", CodiciInstallazione.Descrivi(CodiciInstallazione.Annullata));
        Assert.Contains("0x80004005", CodiciInstallazione.Descrivi(unchecked((int)0x80004005)));
        Assert.Contains("app desktop", CodiciInstallazione.Descrivi(unchecked((int)0x80070005)));
        Assert.Contains("sconosciuto", CodiciInstallazione.Descrivi(77));
    }

    [Fact]
    public void FormatiTuttiSedicinoniENv12Pari()
    {
        Assert.Equal(FormatiWebcam.Massimo, FormatiWebcam.Tutti.MaxBy(f => f.Byte));
        foreach (var formato in FormatiWebcam.Tutti)
        {
            Assert.Equal(formato.Larghezza * 9, formato.Altezza * 16);
            Assert.True(AnelloFotogrammi.DimensioniValide(formato.Larghezza, formato.Altezza));
            Assert.Equal(30, formato.Fps);
        }
        Assert.Equal(new FormatoWebcam(1280, 720, 30), FormatiWebcam.Cerca(1280, 720));
        Assert.Equal(FormatiWebcam.Predefinito, FormatiWebcam.Cerca(1, 1));
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
