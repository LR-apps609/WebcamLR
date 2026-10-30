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
        Assert.Contains("en/WebcamLR.Ricevitore.resources.dll", ContenutoPacchetto.Obbligatori);
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
        Assert.Contains("Reti private", CodiciInstallazione.Descrivi(CodiciInstallazione.FirewallFallito, LinguaAttesa.Italiano));
        Assert.False(CodiciInstallazione.ÈRiuscita(CodiciInstallazione.FirewallFallito));
    }
}

public class ChiusuraAppTest
{
    private const string Cartella = @"C:\Users\Ledion\AppData\Local\Programs\WebcamLR";

    [Theory]
    [InlineData(@"C:\Users\Ledion\AppData\Local\Programs\WebcamLR\WebcamLR.exe", true)]
    [InlineData(@"c:\users\ledion\appdata\local\programs\webcamlr\WebcamLR.exe", true)]
    [InlineData(null, true)]
    [InlineData("", true)]
    [InlineData(@"C:\Users\Ledion\AppData\Local\Programs\WebcamLR.vecchia-20261030\WebcamLR.exe", false)]
    [InlineData(@"D:\Prove\WebcamLR\WebcamLR.exe", false)]
    public void ChiudeSoloLaCopiaInstallata(string? percorso, bool daChiudere)
    {
        Assert.Equal(daChiudere, ChiusuraApp.DaChiudere(percorso, Cartella));
        Assert.Equal(daChiudere, ChiusuraApp.DaChiudere(percorso, Cartella + "\\"));
    }

    [Theory]
    [InlineData(false, true, true, AvvisoAppAperta.Nessuno)]
    [InlineData(true, false, null, AvvisoAppAperta.Aperta)]
    [InlineData(true, true, false, AvvisoAppAperta.Aperta)]
    [InlineData(true, true, true, AvvisoAppAperta.ApertaVideoInUso)]
    [InlineData(true, true, null, AvvisoAppAperta.ApertaForseVideoInUso)]
    public void AvvisoSecondoQuelloCheSiSa(bool aperta, bool webcam, bool? inUso, AvvisoAppAperta atteso)
    {
        Assert.Equal(atteso, ChiusuraApp.Avviso(aperta, webcam, inUso));
    }

    [Fact]
    public void PrimaChiedePoiAspettaQuindiciSecondiPoiForza()
    {
        Assert.Equal("--esci", ChiusuraApp.ArgomentoEsci);
        Assert.Equal(TimeSpan.FromSeconds(15), ChiusuraApp.AttesaUscita);
        Assert.Equal(PassoChiusura.ChiediUscita, ChiusuraApp.Prossimo(false, false, TimeSpan.Zero));
        Assert.Equal(PassoChiusura.Aspetta, ChiusuraApp.Prossimo(false, true, TimeSpan.FromSeconds(5)));
        Assert.Equal(PassoChiusura.Aspetta, ChiusuraApp.Prossimo(false, true, TimeSpan.FromSeconds(14.9)));
        Assert.Equal(PassoChiusura.Forza, ChiusuraApp.Prossimo(false, true, TimeSpan.FromSeconds(15)));
        Assert.Equal(PassoChiusura.Fatto, ChiusuraApp.Prossimo(true, true, TimeSpan.FromSeconds(3)));
        // Mai a forza senza aver chiesto prima: niente più «finestra nascosta = chiusa subito».
        Assert.Equal(PassoChiusura.ChiediUscita, ChiusuraApp.Prossimo(false, false, TimeSpan.FromMinutes(1)));
    }

    [Fact]
    public void AvanzamentoInMegabyte()
    {
        Assert.Equal((12, (int?)30, (int?)40), AvanzamentoDownload.Calcola(12L * 1024 * 1024, 30L * 1024 * 1024));
        Assert.Equal((0, (int?)30, (int?)0), AvanzamentoDownload.Calcola(0, 30L * 1024 * 1024));
        Assert.Equal((30, (int?)30, (int?)100), AvanzamentoDownload.Calcola(30L * 1024 * 1024, 30L * 1024 * 1024));
        Assert.Equal((5, (int?)null, (int?)null), AvanzamentoDownload.Calcola(5L * 1024 * 1024 + 10, null));
        Assert.Equal((0, (int?)null, (int?)null), AvanzamentoDownload.Calcola(100, 0));
        // Un server che manda più di quanto annunciato non supera il 100%.
        Assert.Equal((2, (int?)2, (int?)100), AvanzamentoDownload.Calcola(3L * 1024 * 1024, 2L * 1024 * 1024));
    }
}

/// <summary>N6 (beta 4): le decisioni delle due Task Dialog dell'installatore.</summary>
public class PianoInstallazioneTest
{
    [Theory]
    [InlineData(null, "1.0.4", CasoInstallazione.Nuova)]
    [InlineData("", "1.0.4", CasoInstallazione.Nuova)]
    [InlineData("1.0.3", "1.0.4", CasoInstallazione.Aggiornamento)]
    [InlineData("1.0.9", "1.0.10", CasoInstallazione.Aggiornamento)]
    [InlineData("1.0.4", "1.0.4", CasoInstallazione.StessaVersione)]
    [InlineData("1.0.4.0", "1.0.4", CasoInstallazione.StessaVersione)]
    [InlineData("1.1", "1.0.4", CasoInstallazione.PiuRecenteInstallata)]
    public void IlCasoDallaVersioneInstallata(string? installata, string nuova, CasoInstallazione atteso)
    {
        Assert.Equal(atteso, PianoInstallazione.Caso(installata, nuova));
    }

    [Theory]
    // Webcam già installata: niente casella (si aggiorna da sola).
    [InlineData(true, 22631, false)]
    // Windows 11 e Windows 10 1809 o più: la casella c'è.
    [InlineData(false, 22631, true)]
    [InlineData(false, 17763, true)]
    // Prima di 1809 la webcam non si può avere.
    [InlineData(false, 17134, false)]
    public void LaCasellaDellaWebcamSoloSeServe(bool giàInstallata, int build, bool attesa)
    {
        Assert.Equal(attesa, PianoInstallazione.MostraCasellaWebcam(giàInstallata, build));
    }

    [Theory]
    [InlineData(true, 22631, false, false, false, true)]   // già installata: si aggiorna, anche con la casella tolta
    [InlineData(false, 22631, false, false, true, true)]   // casella spuntata
    [InlineData(false, 22631, false, false, false, false)] // casella tolta
    [InlineData(false, 22631, true, true, false, true)]    // /silenzioso /webcam
    [InlineData(false, 22631, true, false, true, false)]   // /silenzioso senza /webcam: la casella non c'è
    [InlineData(false, 17134, false, false, true, false)]  // Windows troppo vecchio
    public void LaWebcamDaConfigurare(bool giàInstallata, int build, bool silenzioso, bool argomento, bool casella, bool attesa)
    {
        Assert.Equal(attesa, PianoInstallazione.WebcamDaConfigurare(giàInstallata, build, silenzioso, argomento, casella));
    }

    [Fact]
    public void LEsitoPerLaFinestraFinale()
    {
        Assert.Equal(EsitoConfigurazione.SenzaPermesso, PianoInstallazione.Esito(CodiciInstallazione.Annullata, true, false));
        Assert.Equal(EsitoConfigurazione.WebcamInstallata, PianoInstallazione.Esito(CodiciInstallazione.Riuscita, true, false));
        // La webcam c'era già (o non è stata scelta): niente da dire.
        Assert.Equal(EsitoConfigurazione.Riuscita, PianoInstallazione.Esito(CodiciInstallazione.Riuscita, true, true));
        Assert.Equal(EsitoConfigurazione.Riuscita, PianoInstallazione.Esito(CodiciInstallazione.Riuscita, false, false));
        // Gli altri codici (anche la riuscita senza le app a 32 bit) li spiega CodiciInstallazione.Descrivi.
        Assert.Equal(EsitoConfigurazione.Problema, PianoInstallazione.Esito(CodiciInstallazione.FirewallFallito, false, false));
        Assert.Equal(EsitoConfigurazione.Problema, PianoInstallazione.Esito(CodiciInstallazione.RiuscitaSenza32Bit, true, false));
        Assert.True(PianoInstallazione.ServeAmministratore);
    }
}
