using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class SezioneAppTest
{
    [Fact]
    public void TestoConEDatiTecnici()
    {
        var testo = SegnalazioneBug.Testo("  Il video si blocca  ", [("Versione", "0.12"), ("Latenza", "51 ms")]);
        Assert.Equal("Il video si blocca\n\n— Dati tecnici —\nVersione: 0.12\nLatenza: 51 ms", testo);
        Assert.Equal("Il video si blocca", SegnalazioneBug.Testo("Il video si blocca", null));
    }

    [Fact]
    public void RegistroAllegatoDopoIDatiTecnici()
    {
        var testo = SegnalazioneBug.Testo("Si blocca", [("Versione", "1.0")], "10:00:01  Collegato\n10:00:05  Caduto\n");
        Assert.Equal("Si blocca\n\n— Dati tecnici —\nVersione: 1.0\n\n— Registro del collegamento —\n10:00:01  Collegato\n10:00:05  Caduto", testo);
        Assert.Equal("Si blocca", SegnalazioneBug.Testo("Si blocca", null, "  "));
    }

    [Fact]
    public void MailSoloConUnIndirizzo()
    {
        Assert.Null(SegnalazioneBug.Mail("", "testo"));
        var mail = SegnalazioneBug.Mail("assistenza@esempio.it", "Riga 1\nRiga & 2");
        Assert.NotNull(mail);
        Assert.StartsWith("mailto:assistenza@esempio.it?subject=WebcamLR%3A%20segnalazione&body=Riga%201%0ARiga%20%26%202",
            mail!.OriginalString);
    }

    [Fact]
    public void GuidaSenzaSezioniVuote()
    {
        Assert.All(Guida.Sezioni, sezione => Assert.NotEmpty(sezione.Passi));
        Assert.Equal(5, InfoApp.VantaggiPro.Count);
    }
}
