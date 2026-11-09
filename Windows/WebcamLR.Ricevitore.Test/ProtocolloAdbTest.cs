using System.Text;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Il protocollo con il server di adb (Qualità 17), la riga «Cavo USB» e dove si cerca adb: pura logica.</summary>
public class ProtocolloAdbTest
{
    [Theory]
    [InlineData("host:version", "000chost:version")]
    [InlineData("host:track-devices", "0012host:track-devices")]
    [InlineData("tcp:52741", "0009tcp:52741")]
    public void RichiestaConLunghezzaEsadecimale(string servizio, string attesa) =>
        Assert.Equal(attesa, Encoding.ASCII.GetString(ProtocolloAdb.Richiesta(servizio)));

    [Theory]
    [InlineData("0000", 0)]
    [InlineData("001a", 26)]
    [InlineData("001A", 26)]
    [InlineData("ffff", 65535)]
    public void LunghezzaInMaiuscoloOMinuscolo(string testo, int attesa) =>
        Assert.Equal(attesa, ProtocolloAdb.Lunghezza(Encoding.ASCII.GetBytes(testo)));

    [Theory]
    [InlineData("00g1")]
    [InlineData("12 4")]
    public void LunghezzaNonValida(string testo) =>
        Assert.Throws<FormatException>(() => ProtocolloAdb.Lunghezza(Encoding.ASCII.GetBytes(testo)));

    [Fact]
    public async Task OkayLeggeSoloQuattroByte()
    {
        // Dopo «OKAY» di tcp:52741 arriva già il telefono: quei byte non vanno consumati.
        using var flusso = new MemoryStream(Encoding.ASCII.GetBytes("OKAYabc"));
        Assert.True(await ProtocolloAdb.LeggiEsitoAsync(flusso, default));
        Assert.Equal(4, flusso.Position);
    }

    [Fact]
    public async Task FailPortaIlMessaggio()
    {
        using var flusso = new MemoryStream(Encoding.ASCII.GetBytes("FAIL0006closed"));
        var errore = await Assert.ThrowsAsync<RifiutoAdb>(() => ProtocolloAdb.LeggiEsitoAsync(flusso, default));
        Assert.Equal("closed", errore.Message);
    }

    [Fact]
    public async Task ChiusoPrimaDellaRisposta()
    {
        using var flusso = new MemoryStream(Encoding.ASCII.GetBytes("OK"));
        Assert.False(await ProtocolloAdb.LeggiEsitoAsync(flusso, default));
    }

    [Fact]
    public async Task BloccoConLunghezza()
    {
        using var flusso = new MemoryStream(Encoding.ASCII.GetBytes("000eR58N12\tdevice\n0000"));
        Assert.Equal("R58N12\tdevice\n", await ProtocolloAdb.LeggiBloccoAsync(flusso, default));
        Assert.Equal("", await ProtocolloAdb.LeggiBloccoAsync(flusso, default));
        Assert.Null(await ProtocolloAdb.LeggiBloccoAsync(flusso, default));
    }

    [Fact]
    public void ElencoConTabulazioni()
    {
        var elenco = ProtocolloAdb.LeggiElenco("R58N12ABCDE\tdevice\n0A1B2C3D\tunauthorized\r\n" +
            "emulator-5554\toffline\nXYZ\tno permissions (missing udev rules?); see [http://developer.android.com/tools/device.html]\n\n");
        Assert.Equal(
        [
            new DispositivoAdb("R58N12ABCDE", StatoDispositivoAdb.Pronto),
            new DispositivoAdb("0A1B2C3D", StatoDispositivoAdb.NonAutorizzato),
            new DispositivoAdb("emulator-5554", StatoDispositivoAdb.NonRaggiungibile),
            new DispositivoAdb("XYZ", StatoDispositivoAdb.Altro),
        ], elenco);
    }

    [Fact]
    public void ElencoNelFormatoLungo()
    {
        var elenco = ProtocolloAdb.LeggiElenco(
            "R58N12ABCDE            device usb:1-1 product:a52qnsxx model:SM_A525F device:a52q transport_id:3\n" +
            "0A1B2C3D               no permissions usb:1-2 transport_id:4\n" +
            "solo\n");
        Assert.Equal(
        [
            new DispositivoAdb("R58N12ABCDE", StatoDispositivoAdb.Pronto),
            new DispositivoAdb("0A1B2C3D", StatoDispositivoAdb.Altro),
        ], elenco);
    }

    [Theory]
    [InlineData("device", StatoDispositivoAdb.Pronto)]
    [InlineData("unauthorized", StatoDispositivoAdb.NonAutorizzato)]
    [InlineData("authorizing", StatoDispositivoAdb.InCorso)]
    [InlineData("connecting", StatoDispositivoAdb.InCorso)]
    [InlineData("offline", StatoDispositivoAdb.NonRaggiungibile)]
    [InlineData("recovery", StatoDispositivoAdb.Altro)]
    [InlineData("bootloader", StatoDispositivoAdb.Altro)]
    public void StatiDiAdb(string grezzo, StatoDispositivoAdb attesa) => Assert.Equal(attesa, ProtocolloAdb.Stato(grezzo));

    [Theory]
    [InlineData("R58N12ABCDE", true)]
    [InlineData("0123456789ABCDEF", true)]
    [InlineData("192.168.1.5:5555", false)]
    [InlineData("emulator-5554", false)]
    [InlineData("adb-R58N12ABCDE-x1y2z3._adb-tls-connect._tcp", false)]
    [InlineData("", false)]
    public void SoloIlCavo(string seriale, bool attesa) => Assert.Equal(attesa, ProtocolloAdb.ViaUsb(seriale));

    [Fact]
    public void AdbSiCercaNellOrdineGiusto()
    {
        var variabili = new Dictionary<string, string>
        {
            ["ANDROID_HOME"] = Path.Combine("C:", "sdk"),
            ["LOCALAPPDATA"] = Path.Combine("C:", "Utente", "AppData", "Local"),
            ["PATH"] = string.Join(';', Path.Combine("C:", "Windows"), Path.Combine("C:", "sdk", "platform-tools"), "  "),
        };
        var app = Path.Combine("C:", "Utente", "AppData", "Local", "WebcamLR");
        var candidati = TrovaAdb.Candidati(n => variabili.GetValueOrDefault(n), app);
        Assert.Equal(
        [
            Path.Combine(app, "platform-tools", "adb.exe"),
            Path.Combine("C:", "sdk", "platform-tools", "adb.exe"),
            Path.Combine("C:", "Utente", "AppData", "Local", "Android", "sdk", "platform-tools", "adb.exe"),
            Path.Combine("C:", "Windows", "adb.exe"),
        ], candidati);
        Assert.Equal(candidati[1], TrovaAdb.Primo(candidati, p => p == candidati[1] || p == candidati[3]));
        Assert.Null(TrovaAdb.Primo(candidati, _ => false));
    }

    private static readonly SituazioneCavo Assente = new(true, StatoCavo.ServizioAssente, false);
    private static readonly SituazioneCavo InAscolto = new(true, StatoCavo.InAscolto, false);

    [Fact]
    public void RigaCavoConDueCavi()
    {
        var nonCercato = new SituazioneCavo(false, StatoCavo.ServizioAssente, false);
        Assert.Equal(StatoRigaCavo.InUsoAndroid, RigaCavo.Stato(true, true, InAscolto, InAscolto));
        Assert.Equal(StatoRigaCavo.InUso, RigaCavo.Stato(true, false, InAscolto, Assente));
        Assert.Equal(StatoRigaCavo.Verifica, RigaCavo.Stato(false, false, nonCercato, nonCercato));
        Assert.Equal(StatoRigaCavo.NonDisponibile, RigaCavo.Stato(false, false, Assente, Assente));
        // Solo adb c'è (niente «Dispositivi Apple»): il cavo si può usare, con un Android.
        Assert.Equal(StatoRigaCavo.NessunTelefono, RigaCavo.Stato(false, false, Assente, InAscolto));
        Assert.Equal(StatoRigaCavo.NessunTelefono, RigaCavo.Stato(false, false, InAscolto, nonCercato));
        Assert.Equal(StatoRigaCavo.ApriApp, RigaCavo.Stato(false, false, Assente, InAscolto with { TelefonoAlCavo = true }));
        Assert.Equal(StatoRigaCavo.DaAutorizzare, RigaCavo.Stato(false, false, InAscolto with { TelefonoAlCavo = true },
            InAscolto with { DaAutorizzare = 1 }));
        Assert.Equal(StatoRigaCavo.Collegato, RigaCavo.Stato(false, false, Assente, new SituazioneCavo(true, StatoCavo.Collegato, true)));
    }

    [Fact]
    public void DiagnosiAndroidDaAutorizzarePrimaDellApp()
    {
        var base_ = new SituazioneRete(true, ProfiloRete.Privata, StatoFirewall.Consentito, StatoCavo.InAscolto, false);
        Assert.DoesNotContain(Diagnosi.Problemi(base_), p => p.Id.StartsWith("android", StringComparison.Ordinal));

        var daAutorizzare = Diagnosi.Problemi(base_ with { Android = InAscolto with { DaAutorizzare = 1 } });
        var problema = Assert.Single(daAutorizzare, p => p.Id.StartsWith("android", StringComparison.Ordinal));
        Assert.Equal("android-da-autorizzare", problema.Id);
        Assert.Equal("cavo-android", problema.IdDomanda);
        Assert.False(problema.Grave);
        Assert.NotNull(DomandeFrequenti.Risposta(problema.IdDomanda));

        var alCavo = Diagnosi.Problemi(base_ with { Android = InAscolto with { TelefonoAlCavo = true } });
        Assert.Contains(alCavo, p => p.Id == "android-al-cavo");

        // Collegato: niente da dire.
        var collegato = Diagnosi.Problemi(base_ with { Android = new SituazioneCavo(true, StatoCavo.Collegato, true) });
        Assert.DoesNotContain(collegato, p => p.Id.StartsWith("android", StringComparison.Ordinal));
    }
}
