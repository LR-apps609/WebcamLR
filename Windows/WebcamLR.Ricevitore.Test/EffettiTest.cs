using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class EffettiTest
{
    private static StatoTelefono Stato() => new(80, false, Temperatura.Normale, "principale");

    [Fact]
    public void NomiItalianiDeiFiltri()
    {
        Assert.Equal(["Naturale", "Caldo", "Freddo", "Luminoso", "Cinema", "Vivido", "Tenue", "Bianco e nero", "Seppia", "Notte"],
            Filtri.Tutti.Select(NomiEffetti.Filtro));
        // Un filtro di un telefono più nuovo si mostra comunque, leggibile.
        Assert.Equal("Pellicola anni 70", NomiEffetti.Filtro("pellicola-anni-70"));
        Assert.Equal(["Nessuno", "Sfocato", "Sostituito"], NomiEffetti.ModiSfondo.Select(NomiEffetti.Sfondo));
        Assert.Equal("40%", NomiEffetti.Percentuale(0.4));
    }

    [Fact]
    public void SconosciutiComeNelProtocollo()
    {
        Assert.Equal(Filtri.Naturale, NomiEffetti.FiltroValido("ultravioletto"));
        Assert.Equal("ultravioletto", NomiEffetti.FiltroValido("ultravioletto", ["naturale", "ultravioletto"]));
        Assert.Equal(ModiSfondo.Nessuno, NomiEffetti.SfondoValido("acquario"));
        Assert.Equal(ModiSfondo.Sfocato, NomiEffetti.SfondoValido("sfocato"));
    }

    [Fact]
    public void SoloQuelloCheIlTelefonoDichiara()
    {
        var vecchio = DisponibilitaEffetti.Da(new Capacita(["principale"], 5, true));
        Assert.False(vecchio.Qualcuno);
        Assert.False(vecchio.Regolazioni);

        var nuovo = DisponibilitaEffetti.Da(new Capacita(["principale"], 5, true, Filtri: ["caldo", "cinema"], Sfondo: true,
            Scritta: true, DoppiaVista: false, Gobbo: true));
        Assert.True(nuovo.Qualcuno);
        // «naturale» c'è sempre, in testa.
        Assert.Equal(["naturale", "caldo", "cinema"], nuovo.Filtri);
        Assert.True(nuovo.Regolazioni);
        Assert.True(nuovo.Sfondo && nuovo.Scritta && nuovo.Gobbo);
        Assert.False(nuovo.Pelle || nuovo.DoppiaVista || nuovo.Postura || nuovo.Inquadratura || nuovo.LuceVolto);
    }

    [Fact]
    public void LoStatoAggiornaIValoriNeiLimiti()
    {
        var controllo = new ControlloEffetti();
        var stato = Stato() with
        {
            Filtro = "cinema",
            Regolazioni = new Regolazioni(0.25, -3, null, 0),
            Sfondo = "acquario",
            IntensitaSfondo = 0.7,
            Pelle = 2,
            Inquadratura = true,
            Scritta = new Scritta("Ledion", "Sviluppatore"),
            Postura = true,
        };
        Assert.True(controllo.Stato(stato, 0));
        var v = controllo.Valori;
        Assert.Equal("cinema", v.Filtro);
        Assert.Equal((0.25, -1.0, 0.0, 0.0), (v.Luminosita, v.Contrasto, v.Saturazione, v.Nitidezza));
        Assert.Equal(ModiSfondo.Nessuno, v.Sfondo);
        Assert.Equal(0.7, v.IntensitaSfondo);
        Assert.Equal(1, v.Pelle);
        Assert.True(v.Inquadratura && v.Postura && v.ScrittaMostrata);
        Assert.False(v.LuceVolto);
        // Lo stesso stato una seconda volta non cambia nulla da ridisegnare.
        Assert.False(controllo.Stato(stato, 10));
        // Uno stato senza effetti (telefono vecchio) lascia i valori come sono.
        Assert.False(controllo.Stato(Stato(), 20));
    }

    [Fact]
    public void ICursoriSiRaccolgonoInUnSoloComando()
    {
        var controllo = new ControlloEffetti();
        Assert.True(controllo.Cambia(new Comando(Pelle: 0.1), 0));
        Assert.False(controllo.Cambia(new Comando(Pelle: 0.2), 30));
        Assert.False(controllo.Cambia(new Comando(Regolazioni: new Regolazioni(Luminosita: 0.5)), 50));
        Assert.False(controllo.Cambia(new Comando(Regolazioni: new Regolazioni(Contrasto: -0.5)), 60));
        Assert.True(controllo.InAttesa);
        Assert.Equal(new Comando(Pelle: 0.2, Regolazioni: new Regolazioni(0.5, -0.5)), controllo.Scaduto());
        Assert.False(controllo.InAttesa);
        Assert.Null(controllo.Scaduto());
        // Dopo l'invio il prossimo cambio fa ripartire l'attesa.
        Assert.True(controllo.Cambia(new Comando(Pelle: 0.3), 200));
    }

    [Fact]
    public void UnInterruttorePorteConSeICursoriInAttesa()
    {
        var controllo = new ControlloEffetti();
        controllo.Cambia(new Comando(IntensitaSfondo: 0.8), 0);
        var subito = controllo.Subito(new Comando(Sfondo: ModiSfondo.Sfocato), 10);
        Assert.Equal(new Comando(Sfondo: "sfocato", IntensitaSfondo: 0.8), subito);
        Assert.Null(controllo.Scaduto());
        Assert.Equal(ModiSfondo.Sfocato, controllo.Valori.Sfondo);
        Assert.Equal(0.8, controllo.Valori.IntensitaSfondo);
    }

    [Fact]
    public void LoStatoVecchioNonRiportaIndietroIlCursore()
    {
        var controllo = new ControlloEffetti(protezione: TimeSpan.FromMilliseconds(1000));
        controllo.Cambia(new Comando(Pelle: 0.6), 0);
        // Uno stato partito dal telefono prima del comando: la pelle resta quella del cursore, il resto si aggiorna.
        controllo.Stato(Stato() with { Pelle = 0.1, Filtro = "seppia" }, 50);
        Assert.Equal(0.6, controllo.Valori.Pelle);
        Assert.Equal("seppia", controllo.Valori.Filtro);
        controllo.Scaduto();
        controllo.Stato(Stato() with { Pelle = 0.1 }, 500);
        Assert.Equal(0.6, controllo.Valori.Pelle);
        // Passata la protezione, vale il telefono (per esempio cambiata sul telefono).
        Assert.True(controllo.Stato(Stato() with { Pelle = 0.1 }, 1200));
        Assert.Equal(0.1, controllo.Valori.Pelle);
    }

    [Fact]
    public void UnAltroTelefonoRipartedaCapo()
    {
        var controllo = new ControlloEffetti();
        controllo.Capacita(new Capacita(["principale"], 5, true, Filtri: ["naturale"]));
        controllo.Cambia(new Comando(Filtro: "caldo"), 0);
        controllo.Azzera();
        Assert.Equal(ValoriEffetti.Iniziali, controllo.Valori);
        Assert.False(controllo.Disponibili.Qualcuno);
        Assert.Null(controllo.Scaduto());
    }

    [Fact]
    public void CapacitaUgualiNonRidisegnano()
    {
        var controllo = new ControlloEffetti();
        Assert.True(controllo.Capacita(new Capacita(["principale"], 5, true, Filtri: ["naturale", "caldo"], Pelle: true)));
        Assert.False(controllo.Capacita(new Capacita(["principale", "tele"], 10, false, Filtri: ["naturale", "caldo"], Pelle: true)));
        Assert.True(controllo.Capacita(new Capacita(["principale"], 5, true, Filtri: ["naturale", "caldo"], Pelle: true, DoppiaVista: true)));
    }

    [Fact]
    public void ScrittaDaMandare()
    {
        Assert.Equal(new Scritta("Ledion", "Sviluppatore"), Comandi.Scritta(" Ledion ", "Sviluppatore ", mostra: true));
        Assert.Equal(new Scritta("Ledion"), Comandi.Scritta("Ledion", "  ", mostra: true));
        // Spenta o senza nome: la scritta vuota, che la toglie.
        Assert.Equal(Scritta.Nessuna, Comandi.Scritta("Ledion", "Sviluppatore", mostra: false));
        Assert.Equal(Scritta.Nessuna, Comandi.Scritta("   ", "Sviluppatore", mostra: true));
        Assert.Equal("""{"tipo":"comando","scritta":{"nome":""}}""",
            System.Text.Encoding.UTF8.GetString(CodificaMessaggi.Codifica(new Comando(Scritta: Comandi.Scritta(null, null, true)))));
    }

    [Fact]
    public void UnireDueComandi()
    {
        var unito = Comandi.Unisci(new Comando(Zoom: 2, Filtro: "caldo", Regolazioni: new Regolazioni(Luminosita: 0.1, Nitidezza: 0.2)),
            new Comando(Filtro: "freddo", Regolazioni: new Regolazioni(Luminosita: 0.3), Postura: true));
        Assert.Equal(new Comando(Zoom: 2, Filtro: "freddo", Regolazioni: new Regolazioni(Luminosita: 0.3, Nitidezza: 0.2), Postura: true), unito);
        Assert.Equal(new Comando(Calore: 0.4, Pelle: 0.2), Comandi.Unisci(new Comando(Calore: 0.1), new Comando(Calore: 0.4, Pelle: 0.2)));
    }

    /// <summary>«Calore» (gratis): si mostra solo con <c>capacita.calore</c>, segue <c>stato.calore</c> nei limiti 0…1.</summary>
    [Fact]
    public void CaloreDalTelefono()
    {
        Assert.False(DisponibilitaEffetti.Da(new Capacita(["frontale"], 5, false)).Calore);
        var solo = DisponibilitaEffetti.Da(new Capacita(["frontale"], 5, false, Calore: true));
        Assert.True(solo.Calore && solo.Qualcuno);
        Assert.NotEqual(DisponibilitaEffetti.Nessuno, solo);

        var controllo = new ControlloEffetti();
        Assert.Equal(0, controllo.Valori.Calore);
        Assert.True(controllo.Stato(Stato() with { Calore = 0.3 }, 0));
        Assert.Equal(0.3, controllo.Valori.Calore);
        controllo.Stato(Stato() with { Calore = 7 }, 10);
        Assert.Equal(1, controllo.Valori.Calore);
        // Un telefono che non lo manda lascia il valore com'è.
        Assert.False(controllo.Stato(Stato(), 20));
        // Il cursore: un comando solo, e lo stato vecchio non lo riporta indietro.
        Assert.True(controllo.Cambia(new Comando(Calore: 0.6), 30));
        controllo.Stato(Stato() with { Calore = 0.3 }, 40);
        Assert.Equal(0.6, controllo.Valori.Calore);
        Assert.Equal(new Comando(Calore: 0.6), controllo.Scaduto());
        // «Neutro» parte subito.
        Assert.Equal(new Comando(Calore: 0), controllo.Subito(new Comando(Calore: 0), 50));
        Assert.Equal(0, controllo.Valori.Calore);
        // Gratis: senza Pro il comando resta.
        Assert.Equal(new Comando(Calore: 0.5), RegolePro.SenzaPro(new Comando(Calore: 0.5)));
        Assert.Equal(1, ValoriSicuri.Sanifica(Stato() with { Calore = 3 }).Calore);
        Assert.Null(ValoriSicuri.Sanifica(Stato() with { Calore = double.NaN }).Calore);
    }
}
