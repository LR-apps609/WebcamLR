using WebcamLR.Effetti;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Qualità 7 e 8 sul PC: bokeh e mosaico (stili della sfocatura, gratis) e il verde per il chroma key (uno sfondo
/// sostituito, di Pro). Sono scelte del PC: non vanno al telefono, e il telecomando vede «sfocato» o «sostituito».
/// </summary>
public class SfondiNuoviTest
{
    private static StatoTelefono Stato(string obiettivo = "frontale", bool sfocaturaSistema = false) =>
        new(80, false, Temperatura.Normale, obiettivo, SfocaturaSistema: sfocaturaSistema);

    private static readonly ValoriEffetti Bokeh = RegoleEffettiComputer.Iniziali with
    {
        Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55, Sfocatura = StiliSfocatura.Bokeh,
    };

    private static readonly ValoriEffetti Verde = RegoleEffettiComputer.Iniziali with
    {
        Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondoVerde.Id,
    };

    [Fact]
    public void BokehEMosaicoSonoGratisComeLaSfocatura()
    {
        foreach (var stile in new[] { StiliSfocatura.Bokeh, StiliSfocatura.Mosaico })
        {
            var m = RegoleMotore.Da(Bokeh with { Sfocatura = stile }, pro: false, Stato(), null, logo: false);
            Assert.Equal(ModiSfondo.Sfocato, m.Sfondo);
            Assert.Equal(stile, m.Sfocatura);
            Assert.Equal(0.55, m.IntensitaSfondo);
        }
        // Uno stile sconosciuto (preferenze di una versione più nuova) vale la sfocatura normale.
        Assert.Equal(StiliSfocatura.Normale, RegoleMotore.Da(Bokeh with { Sfocatura = "acquerello" }, false, Stato(), null, false).Sfocatura);
        // Mai sopra Ritratto del telefono, e mai con la posteriore: come la sfocatura.
        Assert.Equal(ModiSfondo.Nessuno, RegoleMotore.Da(Bokeh, false, Stato(sfocaturaSistema: true), null, false).Sfondo);
        Assert.Equal(ModiSfondo.Nessuno, RegoleMotore.Da(Bokeh, false, Stato("principale"), null, false).Sfondo);
    }

    [Fact]
    public void LoStileValeSoloConLoSfocato()
    {
        var spento = RegoleMotore.Da(Bokeh with { Sfondo = ModiSfondo.Nessuno }, true, Stato(), null, false);
        Assert.Equal(StiliSfocatura.Normale, spento.Sfocatura);
        var sostituito = RegoleMotore.Da(Bokeh with { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondiPronti.Libreria }, true,
            Stato(), SfondiPronti.Libreria, false);
        Assert.Equal(StiliSfocatura.Normale, sostituito.Sfocatura);
    }

    [Fact]
    public void IlVerdeEDiProComeGliSfondi()
    {
        var immagine = RegoleSfondo.ImmagineAttuale(Verde, SfondiPronti.Tutti);
        Assert.Equal(SfondoVerde.Id, immagine);
        // Anche se il «telefono» non lo elenca: non è un'immagine da avere.
        Assert.Equal(SfondoVerde.Id, RegoleSfondo.ImmagineAttuale(Verde, []));
        Assert.Equal(ModiSfondo.Nessuno, RegoleMotore.Da(Verde, pro: false, Stato(), immagine, false).Sfondo);
        var pro = RegoleMotore.Da(Verde, pro: true, Stato(), immagine, false);
        Assert.Equal(ModiSfondo.Sostituito, pro.Sfondo);
        Assert.Equal(SfondoVerde.Id, pro.ImmagineSfondo);
        Assert.Equal("Schermo verde", RegoleSfondo.Nome(SfondoVerde.Id));
    }

    [Fact]
    public void IlTelecomandoVedeSfocatoOSostituito()
    {
        Assert.Equal(ModiSfondo.Sfocato, RegoleTelecomando.Stato(Bokeh, false, Stato(), null).Sfondo);
        Assert.Equal(ModiSfondo.Sfocato, RegoleTelecomando.Stato(Bokeh with { Sfocatura = StiliSfocatura.Mosaico }, false, Stato(), null).Sfondo);
        Assert.Equal(ModiSfondo.Sostituito, RegoleTelecomando.Stato(Verde, true, Stato(), SfondoVerde.Id).Sfondo);
        Assert.Equal(ModiSfondo.Nessuno, RegoleTelecomando.Stato(Verde, false, Stato(), SfondoVerde.Id).Sfondo);
    }

    [Fact]
    public void SfocaDalTelefonoRiaccendeLUltimoStile()
    {
        // Il bokeh spento dal telefono e poi riacceso: torna il bokeh (lo stile resta nelle scelte del PC).
        var spento = Bokeh.Applica(RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: ModiSfondo.Nessuno), Stato(), LivelloSfocatura.Medio)!);
        Assert.Equal(ModiSfondo.Nessuno, spento.Sfondo);
        var riacceso = spento.Applica(RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: ModiSfondo.Sfocato), Stato(), LivelloSfocatura.Tanto)!);
        Assert.Equal(ModiSfondo.Sfocato, riacceso.Sfondo);
        Assert.Equal(StiliSfocatura.Bokeh, riacceso.Sfocatura);
        Assert.Equal(1.0, riacceso.IntensitaSfondo);
    }

    [Fact]
    public void LoStileNonVaAlTelefono()
    {
        var controllo = new ControlloEffetti(sulComputer: true, iniziali: RegoleEffettiComputer.Iniziali);
        var cambiati = 0;
        controllo.Cambiati += () => cambiati++;
        var comando = controllo.Sfoca(0.55, 0, StiliSfocatura.Mosaico);
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.55), comando);
        Assert.Equal(StiliSfocatura.Mosaico, controllo.Valori.Sfocatura);
        Assert.True(cambiati > 0);
        // Senza stile resta quello di prima; uno sconosciuto vale normale.
        controllo.Sfoca(1, 10);
        Assert.Equal(StiliSfocatura.Mosaico, controllo.Valori.Sfocatura);
        controllo.Sfoca(1, 20, "acquerello");
        Assert.Equal(StiliSfocatura.Normale, controllo.Valori.Sfocatura);
        // Lo stato del telefono non lo tocca.
        controllo.Sfoca(1, 30, StiliSfocatura.Bokeh);
        controllo.Stato(Stato() with { Sfondo = ModiSfondo.Nessuno }, 40);
        Assert.Equal(StiliSfocatura.Bokeh, controllo.Valori.Sfocatura);
    }

    [Fact]
    public void LoStileSiSalvaNellePreferenze()
    {
        Assert.Equal(StiliSfocatura.Bokeh, RegoleEffettiComputer.DaTesto(RegoleEffettiComputer.InTesto(Bokeh)).Sfocatura);
        Assert.Equal(Verde.ImmagineSfondo, RegoleEffettiComputer.DaTesto(RegoleEffettiComputer.InTesto(Verde)).ImmagineSfondo);
        // Preferenze di prima, senza lo stile: la sfocatura normale.
        Assert.Equal(StiliSfocatura.Normale, RegoleEffettiComputer.DaTesto("{\"Sfondo\":\"sfocato\",\"IntensitaSfondo\":0.5}").Sfocatura);
        Assert.Equal(StiliSfocatura.Normale, RegoleEffettiComputer.DaTesto("{\"Sfondo\":\"sfocato\",\"Sfocatura\":\"marziano\"}").Sfocatura);
    }

    [Fact]
    public void IlClicRiaccendeIlVerdeSoloConPro()
    {
        var spento = ValoriEffetti.Iniziali;
        Assert.Equal(SfondoVerde.Id, RegoleSfondo.Clic(spento, SfondoVerde.Id, true, ["libreria"], false));
        Assert.Equal(RegoleSfondo.Sfocatura, RegoleSfondo.Clic(spento, SfondoVerde.Id, false, ["libreria"], false));
    }

    [Fact]
    public void INomiDegliStili()
    {
        Assert.Equal("Normale", NomiEffetti.StileSfocatura(StiliSfocatura.Normale));
        Assert.Equal("Obiettivo (bokeh)", NomiEffetti.StileSfocatura(StiliSfocatura.Bokeh));
        Assert.Equal("Mosaico", NomiEffetti.StileSfocatura(StiliSfocatura.Mosaico));
        Assert.Equal("Normale", NomiEffetti.StileSfocatura("acquerello"));
    }
}
