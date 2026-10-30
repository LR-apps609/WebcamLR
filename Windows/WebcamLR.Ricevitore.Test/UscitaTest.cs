using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class UscitaTest
{
    private static readonly string[] Nessuno = [];

    [Fact]
    public void SenzaNullaInCorsoSiEsceSubito()
    {
        Assert.Null(DomandaUscita.Crea(inOnda: false, Nessuno, registrando: false, Nessuno));
    }

    [Fact]
    public void ZoomInOndaDiceChiUsaIlVideo()
    {
        var domanda = DomandaUscita.Crea(inOnda: true, ["Zoom"], registrando: false, ["iPhone di Ledion"])!;
        Assert.Equal("Uscire da WebcamLR?", domanda.Titolo);
        Assert.Equal("Zoom sta usando il video: si fermerà e chi ti guarda vedrà «La webcam non è collegata».", domanda.Testo);
        Assert.Equal("Esci", domanda.Esci);
        Assert.Equal("Annulla", domanda.Annulla);
    }

    [Fact]
    public void InOndaConLaRegistrazioneEPiuApp()
    {
        var domanda = DomandaUscita.Crea(inOnda: true, ["Zoom", "Teams", "OBS"], registrando: true, Nessuno)!;
        Assert.Equal("Zoom, Teams e OBS stanno usando il video: si fermerà e chi ti guarda vedrà «La webcam non è collegata». "
                     + "La registrazione si chiude e si salva in Video › WebcamLR.", domanda.Testo);
        // Windows non dice quale app: «Un'app».
        Assert.StartsWith("Un'app sta usando il video", DomandaUscita.Crea(true, Nessuno, false, Nessuno)!.Testo);
    }

    [Fact]
    public void SoloUnTelefonoCollegatoOLaRegistrazione()
    {
        Assert.Equal("«Pixel 8» si scollegherà.", DomandaUscita.Crea(false, Nessuno, false, ["Pixel 8"])!.Testo);
        Assert.Equal("I telefoni collegati si scollegheranno.", DomandaUscita.Crea(false, Nessuno, false, ["Pixel 8", "iPhone"])!.Testo);
        Assert.Equal("La registrazione si chiude e si salva in Video › WebcamLR. «Pixel 8» si scollegherà.",
            DomandaUscita.Crea(false, Nessuno, true, ["Pixel 8"])!.Testo);
    }

    [Fact]
    public void InInglese()
    {
        using (Lingua.Provvisoria(Lingua.Inglese))
        {
            var domanda = DomandaUscita.Crea(true, ["Zoom", "Teams"], true, Nessuno)!;
            Assert.Equal("Exit WebcamLR?", domanda.Titolo);
            Assert.Equal("Zoom and Teams are using the video: it will stop and people will see “The webcam is not connected”. "
                         + "The recording will be closed and saved to Videos › WebcamLR.", domanda.Testo);
            Assert.Equal("Exit", domanda.Esci);
            Assert.Equal("Cancel", domanda.Annulla);
        }
    }

    [Fact]
    public void LaNotificaDellaXLaPrimaVoltaESempreRegistrandoOInOnda()
    {
        var avviso = new AvvisoFinestraNascosta();
        Assert.True(avviso.Serve(registrando: false, inOnda: false));
        Assert.False(avviso.Serve(registrando: false, inOnda: false));
        Assert.True(avviso.Serve(registrando: true, inOnda: false));
        Assert.True(avviso.Serve(registrando: false, inOnda: true));
        Assert.False(avviso.Serve(registrando: false, inOnda: false));
        var (titolo, testo) = AvvisoFinestraNascosta.Notifica(registrando: true);
        Assert.Equal("WebcamLR è ancora attiva accanto all'orologio", titolo);
        Assert.Equal("La webcam e la registrazione continuano. Per chiuderla: clic destro sull'icona › Esci da WebcamLR.", testo);
    }

    [Theory]
    [InlineData(@"""C:\Users\Ledion Rama\AppData\Local\Programs\WebcamLR\WebcamLR.exe"" --esci", true)]
    [InlineData(@"C:\Programmi\WebcamLR\WebcamLR.exe --ESCI", true)]
    [InlineData(@"""C:\Users\Ledion Rama\AppData\Local\Programs\WebcamLR\WebcamLR.exe""", false)]
    [InlineData(@"""C:\cartella --esci\WebcamLR.exe""", false)]
    [InlineData(@"WebcamLR.exe --avvio", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void ArgomentoEsciNellaRigaDiComando(string? riga, bool chiesta)
    {
        Assert.Equal(chiesta, UscitaRichiesta.Chiesta(riga));
    }

    [Fact]
    public void ArgomentoEsciNegliArgomenti()
    {
        Assert.Equal("--esci", UscitaRichiesta.Argomento);
        Assert.True(UscitaRichiesta.Chiesta([@"C:\x\WebcamLR.exe", "--esci"]));
        Assert.False(UscitaRichiesta.Chiesta([@"C:\x\WebcamLR.exe", "--avvio"]));
    }
}
