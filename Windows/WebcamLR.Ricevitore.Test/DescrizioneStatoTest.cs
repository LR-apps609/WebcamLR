using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class DescrizioneStatoTest
{
    [Fact]
    public void CollegatoConLaQualita()
    {
        Assert.Equal("WebcamLR · Collegato a iPhone di Ledion · Ottimo",
            DescrizioneStato.Suggerimento(StatoCollegamento.Collegato, "iPhone di Ledion", 42));
        Assert.Equal("Collegato a iPhone di Ledion · Debole",
            DescrizioneStato.Riga(StatoCollegamento.Collegato, "iPhone di Ledion", 180));
    }

    [Fact]
    public void SenzaLatenzaSenzaQualita()
    {
        Assert.Equal("Collegato a iPhone", DescrizioneStato.Riga(StatoCollegamento.Collegato, "iPhone"));
        Assert.Equal("Riconnessione a iPhone…", DescrizioneStato.Riga(StatoCollegamento.Riconnessione, "iPhone", 40));
        Assert.Equal("WebcamLR · Nessun telefono", DescrizioneStato.Suggerimento(StatoCollegamento.NessunTelefono, "iPhone"));
        Assert.Equal("Collegato a un telefono", DescrizioneStato.Riga(StatoCollegamento.Collegato, " "));
    }

    [Fact]
    public void NomeLungoTagliato()
    {
        var testo = DescrizioneStato.Suggerimento(StatoCollegamento.Collegato, new string('a', 200), 40);
        Assert.Equal(DescrizioneStato.LunghezzaMassimaSuggerimento, testo.Length);
        Assert.EndsWith("…", testo);
    }
}
