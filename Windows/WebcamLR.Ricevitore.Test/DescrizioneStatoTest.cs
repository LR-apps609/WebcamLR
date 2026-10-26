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
    public void NomeLungoTagliato()
    {
        var testo = DescrizioneStato.Suggerimento(FaseCollegamento.Collegato, new string('a', 200), 40);
        Assert.Equal(DescrizioneStato.LunghezzaMassimaSuggerimento, testo.Length);
        Assert.EndsWith("…", testo);
    }
}
