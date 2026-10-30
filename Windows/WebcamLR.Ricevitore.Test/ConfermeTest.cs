using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Passo 4 della 1.0 beta 2: niente gesti distruttivi a sorpresa (windows.md 1.8, 2.10, 2.11).</summary>
public class ConfermeTest
{
    private static readonly string[] Nessuna = [];

    [Fact]
    public void ScollegaSubitoSeNessunoUsaIlVideoENonSiRegistra()
    {
        Assert.Null(Conferme.Scollega("iPhone di Ledion", nellaWebcam: true, inOnda: false, Nessuna, registrando: false));
        // Il telefono che non è nella webcam non va alle app né nella registrazione: si scollega subito.
        Assert.Null(Conferme.Scollega("Pixel 8", nellaWebcam: false, inOnda: true, ["Zoom"], registrando: true));
    }

    [Fact]
    public void ScollegaInOndaComeNelDocumento()
    {
        var domanda = Conferme.Scollega("iPhone di Ledion", true, true, ["Zoom"], false)!;
        Assert.Equal("Scollegare «iPhone di Ledion»?", domanda.Titolo);
        Assert.Equal("Zoom sta usando il video: si fermerà.", domanda.Testo);
        Assert.Equal("Scollega", domanda.Conferma);
        Assert.Equal("Annulla", domanda.Annulla);
    }

    [Fact]
    public void ScollegaConRegistrazionePiuAppEAltroTelefono()
    {
        Assert.Equal("Zoom e Teams stanno usando il video: si fermerà. La registrazione si chiude e si salva in Video › WebcamLR.",
            Conferme.Scollega("iPhone", true, true, ["Zoom", "Teams", "Zoom"], true)!.Testo);
        Assert.Equal("La registrazione si chiude e si salva in Video › WebcamLR.",
            Conferme.Scollega("iPhone", true, false, Nessuna, true)!.Testo);
        // Windows non dice quale app; con un secondo telefono il video passa a lui invece di fermarsi.
        Assert.Equal("Un'app sta usando il video: si fermerà.", Conferme.Scollega("iPhone", true, true, Nessuna, false)!.Testo);
        Assert.Equal("Zoom sta usando il video: passerà a «Pixel 8».", Conferme.Scollega("iPhone", true, true, ["Zoom"], false, "Pixel 8")!.Testo);
    }

    [Fact]
    public void ProfiliEFidati()
    {
        var elimina = Conferme.EliminaProfilo("Riunione");
        Assert.Equal("Eliminare il profilo «Riunione»?", elimina.Titolo);
        Assert.Equal(("Elimina", "Annulla"), (elimina.Conferma, elimina.Annulla));
        var sostituisci = Conferme.SostituisciProfilo("Riunione");
        Assert.Equal("C'è già un profilo «Riunione»: sostituirlo?", sostituisci.Titolo);
        Assert.Equal("Sostituisci", sostituisci.Conferma);
        var fidato = Conferme.RimuoviFidato("Pixel 8");
        Assert.Equal("Rimuovere «Pixel 8» dai telefoni fidati?", fidato.Titolo);
        Assert.Equal("La prossima volta dovrai confermarlo con il codice.", fidato.Testo);
        Assert.Equal("Rimuovi", fidato.Conferma);
    }

    [Fact]
    public void NomeGiaUsatoSenzaBadareAMaiuscoleESpazi()
    {
        string[] salvati = ["Riunione", "Diretta sera"];
        Assert.Equal("Riunione", Conferme.NomeGiaUsato(" riunione ", salvati));
        Assert.Equal("Diretta sera", Conferme.NomeGiaUsato("DIRETTA SERA", salvati));
        Assert.Null(Conferme.NomeGiaUsato("Lezione", salvati));
    }

    [Fact]
    public void WebcamInUsoSoloSeInOnda()
    {
        Assert.Null(Conferme.WebcamInUso(false, ["Zoom"]));
        Assert.Equal("Zoom la sta usando adesso: chi ti guarda perderà il video.", Conferme.WebcamInUso(true, ["Zoom"]));
        Assert.Equal("Un'app la sta usando adesso: chi ti guarda perderà il video.", Conferme.WebcamInUso(true, Nessuna));
        Assert.StartsWith("Zoom, Teams e OBS la stanno usando", Conferme.WebcamInUso(true, ["Zoom", "Teams", "OBS"]));
    }

    [Fact]
    public void InInglese()
    {
        using (Lingua.Provvisoria(Lingua.Inglese))
        {
            var domanda = Conferme.Scollega("Ledion’s iPhone", true, true, ["Zoom"], true)!;
            Assert.Equal("Disconnect “Ledion’s iPhone”?", domanda.Titolo);
            Assert.Equal("Zoom is using the video: it will stop. The recording will be closed and saved to Videos › WebcamLR.", domanda.Testo);
            Assert.Equal(("Disconnect", "Cancel"), (domanda.Conferma, domanda.Annulla));
            Assert.Equal("Delete the “Meeting” profile?", Conferme.EliminaProfilo("Meeting").Titolo);
            Assert.Equal("There’s already a “Meeting” profile. Replace it?", Conferme.SostituisciProfilo("Meeting").Titolo);
            Assert.Equal("Remove “Pixel 8” from trusted phones?", Conferme.RimuoviFidato("Pixel 8").Titolo);
            Assert.Equal("Zoom is using it right now: people will lose your video.", Conferme.WebcamInUso(true, ["Zoom"]));
        }
    }

    [Fact]
    public void AzzeraSiAnnullaPerOttoSecondiUnaVolta()
    {
        var annulla = new AnnullaPerPoco<Regolazioni>();
        Assert.False(annulla.Disponibile(0));
        Assert.Null(annulla.Annulla(0));
        var prima = new Regolazioni(0.2, -0.1, 0, 0.3);
        annulla.Ricorda(prima, 1_000);
        Assert.True(annulla.Disponibile(8_999));
        Assert.Same(prima, annulla.Annulla(8_999));
        // Una volta sola: il secondo Ctrl+Z non rimette niente.
        Assert.Null(annulla.Annulla(9_000));
        annulla.Ricorda(prima, 10_000);
        Assert.False(annulla.Disponibile(18_000));
        Assert.Null(annulla.Annulla(18_000));
        annulla.Ricorda(prima, 20_000);
        annulla.Dimentica();
        Assert.False(annulla.Disponibile(20_001));
    }

    [Fact]
    public void CodiceDiConfermaScaduto()
    {
        // Il telefono andato via dopo pochi secondi non è «tempo scaduto»; dopo il minuto sì.
        Assert.False(Conferme.TempoScaduto(TimeSpan.FromSeconds(5)));
        Assert.True(Conferme.TempoScaduto(SessioneComputer.AttesaConferma));
        Assert.True(Conferme.TempoScaduto(SessioneComputer.AttesaConferma - TimeSpan.FromMilliseconds(300)));
        Assert.Equal("Tempo scaduto: «Pixel 8» non è stato collegato. Riprova dal telefono.", Conferme.CodiceScaduto("Pixel 8"));
        Assert.Equal("Tempo scaduto: «il telefono» non è stato collegato. Riprova dal telefono.", Conferme.CodiceScaduto(" "));
    }
}
