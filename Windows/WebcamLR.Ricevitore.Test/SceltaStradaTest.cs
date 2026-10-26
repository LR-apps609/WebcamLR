using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// La strada del collegamento (interfaccia finale): la regola «Automatico» senza sbalzi, la scelta a mano, la
/// preferenza che arriva dal telefono e il menu dell'etichetta sul video.
/// </summary>
public class SceltaStradaTest
{
    private const long Secondo = 1000;

    [Theory]
    [InlineData(null, "automatico")]
    [InlineData("wifi", "wifi")]
    [InlineData("cavo", "cavo")]
    [InlineData("automatico", "automatico")]
    [InlineData("satellite", "automatico")]
    public void PreferenzaSconosciutaValeAutomatico(string? valore, string atteso) =>
        Assert.Equal(atteso, PreferenzaCollegamento.Normalizza(valore));

    [Fact]
    public void AutomaticoIlCavoVinceSulWiFiMaNonSubitoDopoUnCambio()
    {
        var regola = new RegolaCollegamento();
        // In Wi-Fi, arriva il cavo: un passaggio (il gesto voluto).
        Assert.Equal(DecisioneStrada.PassaAllaNuova, regola.Decidi(nuovaViaCavo: true, inUsoViaCavo: false, inUsoAttiva: true, 0));
        // Il Wi-Fi non scavalca il cavo che funziona.
        Assert.Equal(DecisioneStrada.TieniQuellaInUso, regola.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: true, 5 * Secondo));
        // Il cavo si stacca: si passa al Wi-Fi senza fermare il video, ed è un cambio.
        Assert.Equal(DecisioneStrada.PassaAllaNuova, regola.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: false, 10 * Secondo));
        // Il cavo torna dopo 10 secondi: niente cambio (la pausa dei 30 secondi).
        Assert.True(regola.InPausa(20 * Secondo));
        Assert.Equal(DecisioneStrada.TieniQuellaInUso, regola.Decidi(nuovaViaCavo: true, inUsoViaCavo: false, inUsoAttiva: true, 20 * Secondo));
        // Passati 30 secondi dall'ultimo cambio: il cavo che arriva si usa.
        Assert.False(regola.InPausa(40 * Secondo));
        Assert.Equal(DecisioneStrada.PassaAllaNuova, regola.Decidi(nuovaViaCavo: true, inUsoViaCavo: false, inUsoAttiva: true, 40 * Secondo));
    }

    [Fact]
    public void AutomaticoIlWiFiDelTelefonoCheScegliePrendeIlPostoDelCavo()
    {
        // Il telefono segue la regola anche lui: se apre il Wi-Fi mentre è sul cavo vuole cambiare (come sul Mac).
        var regola = new RegolaCollegamento();
        Assert.Equal(DecisioneStrada.PassaAllaNuova,
            regola.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: true, 0, telefonoSceglie: true));
        // Il cavo che torna subito dopo aspetta i 30 secondi.
        Assert.Equal(DecisioneStrada.TieniQuellaInUso,
            regola.Decidi(nuovaViaCavo: true, inUsoViaCavo: false, inUsoAttiva: true, 10 * Secondo, telefonoSceglie: true));
        // Con «Cavo USB» scelto resta il cavo anche così.
        var cavo = new RegolaCollegamento();
        cavo.Imposta(PreferenzaCollegamento.Cavo, 0);
        Assert.Equal(DecisioneStrada.TieniQuellaInUso,
            cavo.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: true, 0, telefonoSceglie: true));
    }

    [Fact]
    public void LaStessaStradaPassaSempreSenzaContareComeCambio()
    {
        var regola = new RegolaCollegamento();
        Assert.Equal(DecisioneStrada.PassaAllaNuova, regola.Decidi(nuovaViaCavo: false, inUsoViaCavo: false, inUsoAttiva: true, 0));
        Assert.False(regola.InPausa(1));
        Assert.Equal(DecisioneStrada.PassaAllaNuova, regola.Decidi(nuovaViaCavo: true, inUsoViaCavo: true, inUsoAttiva: true, 1));
        Assert.False(regola.InPausa(2));
    }

    [Fact]
    public void SceltaAManoResta()
    {
        var wifi = new RegolaCollegamento();
        Assert.True(wifi.Imposta(PreferenzaCollegamento.WiFi, 0));
        // Il cavo arriva: resta il Wi-Fi. Il Wi-Fi torna mentre si usava il cavo (dopo una caduta): si torna al Wi-Fi.
        Assert.Equal(DecisioneStrada.TieniQuellaInUso, wifi.Decidi(nuovaViaCavo: true, inUsoViaCavo: false, inUsoAttiva: true, 0));
        Assert.Equal(DecisioneStrada.PassaAllaNuova, wifi.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: true, Secondo));
        // Anche subito dopo un cambio: la pausa vale solo per «Automatico».
        Assert.Equal(DecisioneStrada.PassaAllaNuova, wifi.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: true, 2 * Secondo));

        var cavo = new RegolaCollegamento();
        cavo.Imposta(PreferenzaCollegamento.Cavo, 0);
        Assert.Equal(DecisioneStrada.TieniQuellaInUso, cavo.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: true, 0));
        Assert.Equal(DecisioneStrada.PassaAllaNuova, cavo.Decidi(nuovaViaCavo: true, inUsoViaCavo: false, inUsoAttiva: true, Secondo));
        // Il cavo scelto si stacca: si usa il Wi-Fi per non perdere il video.
        Assert.Equal(DecisioneStrada.PassaAllaNuova, cavo.Decidi(nuovaViaCavo: false, inUsoViaCavo: true, inUsoAttiva: false, 2 * Secondo));
    }

    [Fact]
    public void LaPreferenzaDelTelefonoNonCancellaUnaSceltaAppenaFatta()
    {
        var regola = new RegolaCollegamento();
        Assert.False(regola.Imposta("automatico", 0));
        Assert.True(regola.Imposta("cavo", 10 * Secondo));
        // Uno stato partito prima del comando dice ancora «automatico»: non conta.
        Assert.False(regola.DalTelefono("automatico", 11 * Secondo));
        Assert.Equal(PreferenzaCollegamento.Cavo, regola.Preferenza);
        // Più tardi il telefono cambia da sé: vale la sua.
        Assert.True(regola.DalTelefono("wifi", 20 * Secondo));
        Assert.Equal(PreferenzaCollegamento.WiFi, regola.Preferenza);
        // Un telefono che non la manda non cambia niente.
        Assert.False(regola.DalTelefono(null, 30 * Secondo));
        Assert.Equal(PreferenzaCollegamento.WiFi, regola.Preferenza);
    }

    [Fact]
    public void MenuConLatenzaEPiuVeloceOra()
    {
        var strade = new StradeTelefono("wifi", "automatico", [new("wifi", 38), new("cavo", 9), new("satellite", 1)]);
        Assert.True(MenuCollegamento.Cliccabile(saScegliere: true, strade));
        Assert.False(MenuCollegamento.Cliccabile(saScegliere: false, strade));
        Assert.False(MenuCollegamento.Cliccabile(saScegliere: true, null));
        Assert.False(MenuCollegamento.Cliccabile(saScegliere: true, strade with { Strade = [new("wifi", 38)] }));

        var voci = MenuCollegamento.Voci(strade, "wifi");
        Assert.Equal(["automatico", "wifi", "cavo"], voci.Select(v => v.Preferenza));
        Assert.Equal([false, true, false], voci.Select(v => v.Scelta));
        // «Più veloce ora» è solo un'informazione: va al cavo anche se la scelta è il Wi-Fi.
        Assert.Equal([false, false, true], voci.Select(v => v.PiuVeloce));
        using (Lingua.Provvisoria(Lingua.Italiano))
        {
            Assert.Equal("Automatico", voci[0].Testo);
            Assert.Equal("Wi-Fi · 38 ms", voci[1].Testo);
            Assert.Equal("Cavo USB · 9 ms", voci[2].Testo);
        }
        using (Lingua.Provvisoria(Lingua.Inglese))
        {
            Assert.Equal("Automatic", voci[0].Testo);
            Assert.Equal("USB cable · 9 ms", voci[2].Testo);
        }
    }

    [Fact]
    public void PiuVeloceSoloConDueLatenzeNote()
    {
        var voci = MenuCollegamento.Voci(new StradeTelefono("wifi", "boh", [new("wifi", 38), new("cavo", null)]), "boh");
        Assert.All(voci, v => Assert.False(v.PiuVeloce));
        Assert.True(voci[0].Scelta);
        Assert.Null(voci[2].Ms);
    }

    [Fact]
    public void StradeUgualiPerValore()
    {
        var a = new StradeTelefono("wifi", "automatico", [new("wifi", 38)]);
        var b = new StradeTelefono("wifi", "automatico", [new("wifi", 38)]);
        Assert.Equal(a, b);
        Assert.NotEqual(a, b with { Strade = [new("wifi", 40)] });
    }

    [Fact]
    public void ContrattoDalProtocollo()
    {
        Assert.True(ContrattoCollegamento.SaScegliere(new Capacita(["1x"], 5, true) { SceltaCollegamento = true }));
        Assert.False(ContrattoCollegamento.SaScegliere(new Capacita(["1x"], 5, true)));
        Assert.Null(ContrattoCollegamento.Strade(new StatoTelefono(80, false, Temperatura.Normale, "1x")));
        var stato = new StatoTelefono(80, false, Temperatura.Normale, "1x")
        {
            Collegamento = new StatoCollegamento("cavo", "sconosciuta", [new StradaCollegamento("wifi", 38), new StradaCollegamento("cavo", null)]),
        };
        Assert.Equal(new StradeTelefono("cavo", "automatico", [new("wifi", 38), new("cavo", null)]), ContrattoCollegamento.Strade(stato));
        Assert.True(ContrattoCollegamento.ViaCavo(stato, TipoCollegamento.WiFi));
        Assert.False(ContrattoCollegamento.ViaCavo(stato with { Collegamento = new StatoCollegamento("hotspot", "automatico") }, TipoCollegamento.CavoUsb));
        Assert.False(ContrattoCollegamento.ViaCavo(stato with { Collegamento = new StatoCollegamento("rete", "automatico") }, null));
        // Un telefono che non dice la strada: da come è arrivata la connessione.
        var vecchio = new StatoTelefono(80, false, Temperatura.Normale, "1x");
        Assert.True(ContrattoCollegamento.ViaCavo(vecchio, TipoCollegamento.CavoUsb));
        Assert.False(ContrattoCollegamento.ViaCavo(vecchio, TipoCollegamento.Hotspot));
        Assert.Null(ContrattoCollegamento.ViaCavo(null, null));
        Assert.Equal("wifi", ContrattoCollegamento.Comando("wifi").Collegamento);
        Assert.Equal("automatico", ContrattoCollegamento.Comando("altro").Collegamento);
    }
}
