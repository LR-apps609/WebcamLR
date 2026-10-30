using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class DescrizioneStatoTest
{
    [Fact]
    public void CollegatoConLaQualita()
    {
        Assert.Equal("WebcamLR · Collegato a iPhone di Ledion · Ottimo",
            DescrizioneStato.Suggerimento(FaseCollegamento.Collegato, "iPhone di Ledion", 42));
        Assert.Equal("Collegato a iPhone di Ledion · Debole",
            DescrizioneStato.Riga(FaseCollegamento.Collegato, "iPhone di Ledion", 180));
    }

    [Fact]
    public void SenzaLatenzaSenzaQualita()
    {
        Assert.Equal("Collegato a iPhone", DescrizioneStato.Riga(FaseCollegamento.Collegato, "iPhone"));
        Assert.Equal("Riconnessione a iPhone…", DescrizioneStato.Riga(FaseCollegamento.Riconnessione, "iPhone", 40));
        Assert.Equal("WebcamLR · Nessun telefono", DescrizioneStato.Suggerimento(FaseCollegamento.NessunTelefono, "iPhone"));
        Assert.Equal("Collegato a un telefono", DescrizioneStato.Riga(FaseCollegamento.Collegato, " "));
    }

    [Fact]
    public void VideoInArrivoConIlNomeVero()
    {
        Assert.Equal("Video in arrivo da Pixel 8", DescrizioneStato.VideoInArrivo("Pixel 8"));
        Assert.Equal("Video in arrivo da iPhone di Ledion", DescrizioneStato.VideoInArrivo(" iPhone di Ledion "));
        Assert.Equal("Video in arrivo dal telefono", DescrizioneStato.VideoInArrivo(null));
        Assert.Equal("Collegato a Pixel 8 · Ottimo", DescrizioneStato.Riga(FaseCollegamento.Collegato, "Pixel 8", 40));
    }

    [Theory]
    [InlineData(WebcamLR.Protocollo.Piattaforma.Iphone, "iPhone")]
    [InlineData(WebcamLR.Protocollo.Piattaforma.Android, "Android")]
    public void NomeDellaPiattaforma(WebcamLR.Protocollo.Piattaforma piattaforma, string atteso)
    {
        Assert.Equal(atteso, DescrizioneStato.NomePiattaforma(piattaforma));
    }

    [Fact]
    public void TreIconeAccantoAllOrologio()
    {
        Assert.Equal(IconaNotifica.Normale, DescrizioneStato.Icona(new StatoNotifica(FaseCollegamento.Collegato, "iPhone")));
        Assert.Equal(IconaNotifica.Normale, DescrizioneStato.Icona(new StatoNotifica(FaseCollegamento.NessunTelefono)));
        Assert.Equal(IconaNotifica.InOnda, DescrizioneStato.Icona(new StatoNotifica(FaseCollegamento.Collegato, InOnda: true)));
        // Registrare basta per il punto corallo, anche senza nessuna app.
        Assert.Equal(IconaNotifica.InOnda,
            DescrizioneStato.Icona(new StatoNotifica(FaseCollegamento.Collegato, Registrazione: TimeSpan.FromSeconds(3))));
        // La riconnessione vince anche in onda e registrando: è il problema da guardare.
        Assert.Equal(IconaNotifica.Riconnessione, DescrizioneStato.Icona(
            new StatoNotifica(FaseCollegamento.Riconnessione, "iPhone", InOnda: true, Registrazione: TimeSpan.Zero)));
    }

    [Fact]
    public void SuggerimentoConInOndaERegistrazione()
    {
        var stato = new StatoNotifica(FaseCollegamento.Collegato, "iPhone di Ledion", 40, InOnda: true, AppInUso: ["Zoom"],
            Registrazione: TimeSpan.FromSeconds(12 * 60 + 31));
        Assert.Equal("WebcamLR · In onda su Zoom · Registrazione 12:31", DescrizioneStato.Suggerimento(stato));
        Assert.Equal("In onda su Zoom · Registrazione 12:31", DescrizioneStato.Riga(stato));
        // Senza «in onda» resta il collegamento con la qualità, e la registrazione accanto.
        Assert.Equal("WebcamLR · Collegato a iPhone di Ledion · Ottimo · Registrazione 00:05", DescrizioneStato.Suggerimento(
            new StatoNotifica(FaseCollegamento.Collegato, "iPhone di Ledion", 40, Registrazione: TimeSpan.FromSeconds(5))));
        // In riconnessione si dicono tutte e due le cose; Windows non dice l'app: «In onda».
        Assert.Equal("Riconnessione a Pixel 8… · In onda", DescrizioneStato.Riga(
            new StatoNotifica(FaseCollegamento.Riconnessione, "Pixel 8", InOnda: true, AppInUso: [])));
        Assert.Equal("Nessun telefono · In onda su Zoom e Teams", DescrizioneStato.Riga(
            new StatoNotifica(FaseCollegamento.NessunTelefono, InOnda: true, AppInUso: ["Zoom", "Teams", "Zoom"])));
        // Come prima, senza nulla in più.
        Assert.Equal(DescrizioneStato.Suggerimento(FaseCollegamento.Collegato, "iPhone", 42),
            DescrizioneStato.Suggerimento(new StatoNotifica(FaseCollegamento.Collegato, "iPhone", 42)));
    }

    [Fact]
    public void TelefonoInPausaMentreUnAppTieneLaWebcam()
    {
        // La pillola: «In pausa» in ambra al posto di «In onda»; in pausa senza app resta calma, come «collegato».
        Assert.Equal(AspettoPillola.InPausa, DescrizioneStato.Pillola(FaseCollegamento.Collegato, inOnda: true, inPausa: true));
        Assert.Equal(AspettoPillola.InOnda, DescrizioneStato.Pillola(FaseCollegamento.Collegato, inOnda: true, inPausa: false));
        Assert.Equal(AspettoPillola.Collegato, DescrizioneStato.Pillola(FaseCollegamento.Collegato, inOnda: false, inPausa: true));
        Assert.Equal(AspettoPillola.Riconnessione, DescrizioneStato.Pillola(FaseCollegamento.Riconnessione, inOnda: true, inPausa: true));
        Assert.Equal(AspettoPillola.NessunTelefono, DescrizioneStato.Pillola(FaseCollegamento.NessunTelefono, inOnda: true, inPausa: true));

        // L'icona e il suggerimento: «In pausa» con il punto ambra, la registrazione accanto se c'è.
        var pausa = new StatoNotifica(FaseCollegamento.Collegato, "iPhone di Ledion", 40, InOnda: true, AppInUso: ["Zoom"], InPausa: true);
        Assert.Equal(IconaNotifica.InPausa, DescrizioneStato.Icona(pausa));
        Assert.Equal("WebcamLR · In pausa", DescrizioneStato.Suggerimento(pausa));
        Assert.Equal("In pausa · Registrazione 00:07", DescrizioneStato.Riga(pausa with { Registrazione = TimeSpan.FromSeconds(7) }));
        Assert.Equal(IconaNotifica.InPausa, DescrizioneStato.Icona(pausa with { Registrazione = TimeSpan.Zero }));
        // In pausa senza nessuna app: niente ambra, come prima.
        Assert.Equal(IconaNotifica.Normale, DescrizioneStato.Icona(pausa with { InOnda = false }));
        Assert.Equal("Collegato a iPhone di Ledion · Ottimo", DescrizioneStato.Riga(pausa with { InOnda = false }));
        // La riconnessione vince anche sulla pausa.
        Assert.Equal(IconaNotifica.Riconnessione, DescrizioneStato.Icona(pausa with { Fase = FaseCollegamento.Riconnessione }));
        Assert.Equal("Riconnessione a iPhone di Ledion… · In onda su Zoom",
            DescrizioneStato.Riga(pausa with { Fase = FaseCollegamento.Riconnessione }));
    }

    [Fact]
    public void InOndaNelRegistroUnaRigaPerCambio()
    {
        var registro = new RegistroInOnda();
        Assert.Null(registro.Cambio(false, []));
        // Windows dice l'app un attimo dopo: la prima riga è quella con il nome, se c'è già.
        Assert.Equal("In onda su Zoom", registro.Cambio(true, ["Zoom"]));
        Assert.Null(registro.Cambio(true, ["Zoom"]));
        // Un elenco vuoto per un giro non scrive nulla.
        Assert.Null(registro.Cambio(true, []));
        Assert.Equal("In onda su Zoom e Teams", registro.Cambio(true, ["Zoom", "Teams"]));
        Assert.Equal("Fuori onda", registro.Cambio(false, ["Zoom"]));
        Assert.Null(registro.Cambio(false, []));
        // Senza nomi: «In onda», poi il nome quando arriva.
        Assert.Equal("In onda", registro.Cambio(true, []));
        Assert.Equal("In onda su OBS", registro.Cambio(true, ["OBS"]));
    }

    [Fact]
    public void ComandoSpentoPerLAssistenteVocale()
    {
        Assert.Equal("Specchia, non disponibile: solo con la fotocamera frontale",
            DescrizioneStato.NonDisponibile("Specchia", "Solo con la fotocamera frontale"));
        Assert.Equal("Foto, non disponibile: collega un telefono per usarlo",
            DescrizioneStato.NonDisponibile("Foto", "Collega un telefono per usarlo."));
        // Le sigle restano maiuscole; senza nome resta il motivo.
        Assert.Equal("Sfondo, non disponibile: HEVC assente", DescrizioneStato.NonDisponibile("Sfondo", "HEVC assente"));
        Assert.Equal("Sblocca WebcamLR Pro sul telefono", DescrizioneStato.NonDisponibile(" ", "Sblocca WebcamLR Pro sul telefono."));
    }

    [Fact]
    public void NomeLungoTagliato()
    {
        var testo = DescrizioneStato.Suggerimento(FaseCollegamento.Collegato, new string('a', 200), 40);
        Assert.Equal(DescrizioneStato.LunghezzaMassimaSuggerimento, testo.Length);
        Assert.EndsWith("…", testo);
    }
}
