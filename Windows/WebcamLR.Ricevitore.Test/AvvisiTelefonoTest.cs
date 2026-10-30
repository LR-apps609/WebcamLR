using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class AvvisiTelefonoTest
{
    private static StatoTelefono Stato(int batteria, bool inCarica = false, Temperatura temperatura = Temperatura.Normale) =>
        new(batteria, inCarica, temperatura, "principale");

    [Fact]
    public void IlCaldoVinceSullaBatteria()
    {
        Assert.Equal(AvvisoTelefono.Critico, SorveglianzaAvvisi.Da(Stato(5, temperatura: Temperatura.Critica)));
        Assert.Equal(AvvisoTelefono.MoltoCaldo, SorveglianzaAvvisi.Da(Stato(5, temperatura: Temperatura.MoltoCalda)));
        Assert.Equal(AvvisoTelefono.BatteriaBassa, SorveglianzaAvvisi.Da(Stato(5, temperatura: Temperatura.Calda)));
    }

    [Fact]
    public void BatteriaBassaSoloSenzaCaricatore()
    {
        Assert.Equal(AvvisoTelefono.Nessuno, SorveglianzaAvvisi.Da(Stato(10, inCarica: true)));
        Assert.Equal(AvvisoTelefono.Nessuno, SorveglianzaAvvisi.Da(Stato(-1)));
        Assert.Equal(AvvisoTelefono.Nessuno, SorveglianzaAvvisi.Da(Stato(20)));
        Assert.Equal(AvvisoTelefono.BatteriaBassa, SorveglianzaAvvisi.Da(Stato(19)));
    }

    [Fact]
    public void UnaSolaNotificaSeLaBatteriaBalla()
    {
        var sorveglianza = new SorveglianzaAvvisi();
        Assert.Null(sorveglianza.Aggiorna(Stato(21)));
        Assert.Equal(AvvisoTelefono.BatteriaBassa, sorveglianza.Aggiorna(Stato(19)));
        Assert.Null(sorveglianza.Aggiorna(Stato(20)));
        Assert.Null(sorveglianza.Aggiorna(Stato(19)));
        Assert.Null(sorveglianza.Aggiorna(Stato(24)));
        Assert.Equal(AvvisoTelefono.BatteriaBassa, sorveglianza.Attuale);
        // Dal 25% l'avviso si spegne; sotto il 20% torna.
        Assert.Null(sorveglianza.Aggiorna(Stato(25)));
        Assert.Equal(AvvisoTelefono.Nessuno, sorveglianza.Attuale);
        Assert.Equal(AvvisoTelefono.BatteriaBassa, sorveglianza.Aggiorna(Stato(18)));
    }

    [Fact]
    public void IlCaricatoreSpegneLAvviso()
    {
        var sorveglianza = new SorveglianzaAvvisi();
        sorveglianza.Aggiorna(Stato(10));
        Assert.Null(sorveglianza.Aggiorna(Stato(10, inCarica: true)));
        Assert.Equal(AvvisoTelefono.Nessuno, sorveglianza.Attuale);
    }

    [Fact]
    public void DaBatteriaACaldoENuovoAvviso()
    {
        var sorveglianza = new SorveglianzaAvvisi();
        sorveglianza.Aggiorna(Stato(10));
        Assert.Equal(AvvisoTelefono.MoltoCaldo, sorveglianza.Aggiorna(Stato(10, temperatura: Temperatura.MoltoCalda)));
        sorveglianza.Azzera();
        Assert.Equal(AvvisoTelefono.Nessuno, sorveglianza.Attuale);
    }

    [Fact]
    public void TestiConLaPercentuale()
    {
        var (titolo, _) = SorveglianzaAvvisi.Testi(AvvisoTelefono.BatteriaBassa, Stato(12));
        Assert.Equal("Batteria del telefono al 12%.", titolo);
    }

    [Fact]
    public void UnaRigaNelRegistroAInizioEFine()
    {
        Assert.Null(SorveglianzaAvvisi.RigaRegistro(AvvisoTelefono.Nessuno, AvvisoTelefono.Nessuno, Stato(50)));
        Assert.Null(SorveglianzaAvvisi.RigaRegistro(AvvisoTelefono.MoltoCaldo, AvvisoTelefono.MoltoCaldo, Stato(50)));
        Assert.Equal("Il telefono è molto caldo.",
            SorveglianzaAvvisi.RigaRegistro(AvvisoTelefono.Nessuno, AvvisoTelefono.MoltoCaldo, Stato(50, temperatura: Temperatura.MoltoCalda)));
        Assert.Equal("Il telefono è troppo caldo.",
            SorveglianzaAvvisi.RigaRegistro(AvvisoTelefono.MoltoCaldo, AvvisoTelefono.Critico, Stato(50, temperatura: Temperatura.Critica)));
        Assert.Equal("Il telefono non è più caldo.", SorveglianzaAvvisi.RigaRegistro(AvvisoTelefono.Critico, AvvisoTelefono.Nessuno, Stato(50)));
        Assert.Equal("Batteria del telefono al 15%.", SorveglianzaAvvisi.RigaRegistro(AvvisoTelefono.Nessuno, AvvisoTelefono.BatteriaBassa, Stato(15)));
        Assert.Equal("La batteria del telefono non è più bassa.",
            SorveglianzaAvvisi.RigaRegistro(AvvisoTelefono.BatteriaBassa, AvvisoTelefono.Nessuno, Stato(15, inCarica: true)));
    }
}
