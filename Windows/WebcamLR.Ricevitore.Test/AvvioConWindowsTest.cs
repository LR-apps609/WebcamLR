using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class AvvioConWindowsTest
{
    private sealed class RegistroFinto : IRegistroAvvio
    {
        public Dictionary<string, string> Valori { get; } = new();
        public string? Leggi(string nome) => Valori.GetValueOrDefault(nome);
        public void Scrivi(string nome, string valore) => Valori[nome] = valore;
        public void Elimina(string nome) => Valori.Remove(nome);
    }

    private const string Percorso = @"C:\Programmi\WebcamLR\WebcamLR.exe";

    [Fact]
    public void AccendeESpegne()
    {
        var registro = new RegistroFinto();
        var avvio = new AvvioConWindows(registro, Percorso);
        Assert.False(avvio.Attivo);

        avvio.Imposta(true);
        Assert.True(avvio.Attivo);
        Assert.Equal(@"""C:\Programmi\WebcamLR\WebcamLR.exe"" --avvio", registro.Valori["WebcamLR"]);

        avvio.Imposta(false);
        Assert.False(avvio.Attivo);
        Assert.Empty(registro.Valori);
    }

    [Fact]
    public void UnaVoceCheVaAltroveNonConta()
    {
        var registro = new RegistroFinto();
        registro.Scrivi("WebcamLR", @"""D:\Vecchia\WebcamLR.exe"" --avvio");
        var avvio = new AvvioConWindows(registro, Percorso);
        Assert.False(avvio.Attivo);

        // Accendendo, la voce passa a questo exe.
        avvio.Imposta(true);
        Assert.True(avvio.Attivo);
        Assert.Equal(avvio.Comando, registro.Valori["WebcamLR"]);
    }

    [Fact]
    public void MaiuscoleNelPercorso()
    {
        var registro = new RegistroFinto();
        registro.Scrivi("WebcamLR", @"""c:\programmi\webcamlr\webcamlr.exe"" --avvio");
        Assert.True(new AvvioConWindows(registro, Percorso).Attivo);
    }

    [Fact]
    public void ArgomentoDiAvvio()
    {
        Assert.True(AvvioConWindows.AvviatoDaWindows([Percorso, "--avvio"]));
        Assert.True(AvvioConWindows.AvviatoDaWindows(["--AVVIO"]));
        Assert.False(AvvioConWindows.AvviatoDaWindows([Percorso]));
    }
}
