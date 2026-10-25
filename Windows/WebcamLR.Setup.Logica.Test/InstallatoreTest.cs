using WebcamLR.Setup;
using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Setup.Test;

public class PercorsiTest
{
    private static readonly Percorsi P = new(@"C:\Users\Ledion\AppData\Local",
        @"C:\Users\Ledion\AppData\Roaming\Microsoft\Windows\Start Menu\Programs", @"C:\Program Files\");

    [Fact]
    public void AppPerLUtenteWebcamInProgrammi()
    {
        Assert.Equal(@"C:\Users\Ledion\AppData\Local\Programs\WebcamLR", P.CartellaApp);
        Assert.Equal(@"C:\Users\Ledion\AppData\Local\Programs\WebcamLR\WebcamLR.exe", P.Eseguibile);
        Assert.Equal(@"C:\Users\Ledion\AppData\Local\Programs\WebcamLR\Disinstalla WebcamLR.exe", P.Disinstallatore);
        Assert.Equal(@"C:\Users\Ledion\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\WebcamLR.lnk", P.Collegamento);
        Assert.Equal(@"C:\Users\Ledion\AppData\Local\Programs\WebcamLR\Webcam\WebcamLR.Webcam.Installa.exe", P.InstallatoreWebcam);
        Assert.Equal(@"C:\Program Files\WebcamLR\Webcam", P.CartellaWebcamInstallata);
        Assert.Equal(@"C:\Users\Ledion\AppData\Local\WebcamLR\Installazione.txt", P.Registro);
        // Togliere la webcam (che cancella la sua cartella in Programmi) non deve mai toccare l'app.
        Assert.False(P.CartellaWebcamInstallata.StartsWith(P.CartellaApp, StringComparison.OrdinalIgnoreCase));
        // La chiave di «App installate» è dell'utente (HKCU), senza «SOFTWARE\Classes» o HKLM.
        Assert.StartsWith(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\", DatiProdotto.ChiaveDisinstallazione);
    }

    [Fact]
    public void LaRegolaDelFirewallAccettaIlPercorsoInstallato()
    {
        Assert.True(RegolaFirewall.ProgrammaValido(P.Eseguibile));
    }
}

public class ValoriDisinstallazioneTest
{
    [Fact]
    public void ValoriPerAppInstallate()
    {
        var p = new Percorsi(@"C:\Users\L\AppData\Local", @"C:\Start", @"C:\Program Files");
        var valori = ValoriDisinstallazione.Crea(p, "1.2.3", 5000, new DateTime(2026, 10, 25)).ToDictionary(v => v.Nome, v => v.Valore);
        Assert.Equal("WebcamLR", valori["DisplayName"]);
        Assert.Equal("1.2.3", valori["DisplayVersion"]);
        Assert.Equal("LR Apps", valori["Publisher"]);
        Assert.Equal("\"C:\\Users\\L\\AppData\\Local\\Programs\\WebcamLR\\Disinstalla WebcamLR.exe\" /disinstalla", valori["UninstallString"]);
        Assert.Equal("\"C:\\Users\\L\\AppData\\Local\\Programs\\WebcamLR\\Disinstalla WebcamLR.exe\" /disinstalla /silenzioso", valori["QuietUninstallString"]);
        Assert.Equal("20261025", valori["InstallDate"]);
        Assert.Equal(5, valori["EstimatedSize"]);
        Assert.Equal(1, valori["VersionMajor"]);
        Assert.Equal(2, valori["VersionMinor"]);
        Assert.Equal(1, valori["NoModify"]);
        Assert.Equal(@"C:\Users\L\AppData\Local\Programs\WebcamLR\WebcamLR.exe,0", valori["DisplayIcon"]);
    }
}

public class ArgomentiTest
{
    [Theory]
    [InlineData(new string[0], true, Modalità.Installa, false, false)]
    [InlineData(new string[0], false, Modalità.Disinstalla, false, false)]
    [InlineData(new[] { "/disinstalla" }, true, Modalità.Disinstalla, false, false)]
    [InlineData(new[] { "/disinstalla", "/silenzioso" }, false, Modalità.Disinstalla, true, false)]
    [InlineData(new[] { "/S", "/webcam" }, true, Modalità.Installa, true, true)]
    [InlineData(new[] { "--quiet", "-uninstall" }, true, Modalità.Disinstalla, true, false)]
    public void Leggi(string[] argomenti, bool haPacchetto, Modalità modalità, bool silenzioso, bool webcam)
    {
        Assert.Equal(new Argomenti(modalità, silenzioso, webcam), Argomenti.Leggi(argomenti, haPacchetto));
    }

    [Theory]
    [InlineData("1.0", "1.0.0", 0)]
    [InlineData("1.9", "1.10", -1)]
    [InlineData("2.0", "1.99.9", 1)]
    [InlineData(null, "0.0", 0)]
    [InlineData("1.x", "1.0", 0)]
    public void Versioni(string? a, string? b, int segno)
    {
        Assert.Equal(segno, Math.Sign(WebcamLR.Setup.Versioni.Confronta(a, b)));
    }
}

public class ContenutoPacchettoTest
{
    [Fact]
    public void ServonoAppDisinstallatoreEWebcam()
    {
        var completo = ContenutoPacchetto.Obbligatori.Select(v => v.Replace('/', '\\')).Append("Altro.dll").ToList();
        Assert.Empty(ContenutoPacchetto.Mancanti(completo));
        Assert.Contains("Webcam/WebcamLR.Webcam.comhost.dll", ContenutoPacchetto.Obbligatori);
        Assert.Contains("Webcam/WebcamLR.Webcam.DirectShow.comhost.dll", ContenutoPacchetto.Obbligatori);
        var mancanti = ContenutoPacchetto.Mancanti(["WebcamLR.exe"]);
        Assert.Contains("Disinstalla WebcamLR.exe", mancanti);
        Assert.DoesNotContain("WebcamLR.exe", mancanti);
    }

    [Theory]
    [InlineData("WebcamLR.exe", @"C:\A\WebcamLR.exe")]
    [InlineData("Webcam/x86/f.dll", @"C:\A\Webcam\x86\f.dll")]
    [InlineData(@"Webcam\f.dll", @"C:\A\Webcam\f.dll")]
    [InlineData("../fuori.exe", null)]
    [InlineData("Webcam/../../fuori.exe", null)]
    [InlineData("/assoluto.exe", null)]
    [InlineData("C:/Windows/x.dll", null)]
    [InlineData("", null)]
    public void NessunaVoceEsceDallaCartella(string voce, string? attesa)
    {
        Assert.Equal(attesa, ContenutoPacchetto.Destinazione(@"C:\A\", voce));
    }
}

public class RequisitiRuntimeTest
{
    private const string App = """
        { "runtimeOptions": { "tfm": "net8.0", "framework": { "name": "Microsoft.NETCore.App", "version": "8.0.0" } } }
        """;
    private const string Desktop = """
        { "runtimeOptions": { "frameworks": [ { "name": "Microsoft.NETCore.App", "version": "8.0.2" },
          { "name": "Microsoft.WindowsDesktop.App", "version": "8.0.1" } ], } }
        """;

    [Fact]
    public void LeggeEUnisce()
    {
        var tutti = RequisitiRuntime.Unisci(RequisitiRuntime.Leggi(App).Concat(RequisitiRuntime.Leggi(Desktop)));
        Assert.Equal([new("Microsoft.NETCore.App", "8.0.2"), new RuntimeRichiesto("Microsoft.WindowsDesktop.App", "8.0.1")], tutti);
        Assert.Empty(RequisitiRuntime.Leggi("non è json"));
        // Il runtime desktop basta anche per quello di base.
        Assert.Equal([new RuntimeRichiesto("Microsoft.WindowsDesktop.App", "8.0.1")], RequisitiRuntime.DaInstallare(tutti));
    }

    [Fact]
    public void IndirizziUfficiali()
    {
        Assert.Equal("https://aka.ms/dotnet/8.0/dotnet-runtime-win-x64.exe",
            RequisitiRuntime.IndirizzoDownload(new("Microsoft.NETCore.App", "8.0.0"), "x64"));
        Assert.Null(RequisitiRuntime.IndirizzoDownload(new("Altro", "8.0.0"), "x64"));
        Assert.True(RequisitiRuntime.InstallazioneRiuscita(3010));
        Assert.False(RequisitiRuntime.InstallazioneRiuscita(1603));
    }

    [Fact]
    public void InstallatoSeCèLaStessaVersioneOPiùNuova()
    {
        var cartella = Directory.CreateTempSubdirectory("dotnet-finto").FullName;
        try
        {
            Directory.CreateDirectory(Path.Combine(cartella, "shared", "Microsoft.NETCore.App", "8.0.5"));
            Directory.CreateDirectory(Path.Combine(cartella, "shared", "Microsoft.NETCore.App", "9.0.0-preview.1"));
            Assert.True(RequisitiRuntime.Installato(new("Microsoft.NETCore.App", "8.0.0"), cartella));
            Assert.False(RequisitiRuntime.Installato(new("Microsoft.NETCore.App", "8.0.6"), cartella));
            Assert.False(RequisitiRuntime.Installato(new("Microsoft.NETCore.App", "9.0.0"), cartella));
            Assert.False(RequisitiRuntime.Installato(new("Microsoft.WindowsDesktop.App", "8.0.0"), cartella));
        }
        finally { Directory.Delete(cartella, recursive: true); }
    }
}

public class RegolaFirewallTest
{
    [Fact]
    public void ArgomentiDiNetsh()
    {
        const string exe = @"C:\Users\Ledion Rama\AppData\Local\Programs\WebcamLR\WebcamLR.exe";
        Assert.Equal("advfirewall firewall add rule name=\"WebcamLR\" dir=in action=allow program=\"" + exe
                     + "\" enable=yes profile=private description=\"" + RegolaFirewall.Descrizione + "\"",
            RegolaFirewall.ArgomentiAggiungi(exe));
        Assert.Equal("advfirewall firewall delete rule name=\"WebcamLR\" program=\"" + exe + "\"", RegolaFirewall.ArgomentiTogli(exe));
        Assert.DoesNotContain('"', RegolaFirewall.Descrizione);
    }

    [Theory]
    [InlineData(@"C:\Users\L\AppData\Local\Programs\WebcamLR\WebcamLR.exe", true)]
    [InlineData(@"D:\WebcamLR\Windows\WebcamLR.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\WebcamLR.exe", true)]
    [InlineData(@"C:\Windows\System32\cmd.exe", false)]
    [InlineData(@"WebcamLR.exe", false)]
    [InlineData(@"C:\x\WebcamLR.exe"" & calc", false)]
    [InlineData(@"\\server\share\WebcamLR.exe", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void SoloWebcamLRConPercorsoCompleto(string? programma, bool valido)
    {
        Assert.Equal(valido, RegolaFirewall.ProgrammaValido(programma));
    }

    [Fact]
    public void CodiceDelFirewallSpiegato()
    {
        Assert.Contains("Reti private", CodiciInstallazione.Descrivi(CodiciInstallazione.FirewallFallito));
        Assert.False(CodiciInstallazione.ÈRiuscita(CodiciInstallazione.FirewallFallito));
    }
}
