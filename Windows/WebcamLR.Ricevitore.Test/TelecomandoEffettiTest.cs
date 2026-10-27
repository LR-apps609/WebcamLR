using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Il telefono come telecomando degli effetti del PC (Protocollo.md, «Effetti sul computer»), come il Mac.</summary>
public class TelecomandoEffettiTest
{
    private static readonly Capacita Nuovo = new(["frontale"], 5, false, EffettiSulComputer: true);
    private static readonly Capacita DiPrima = new(["frontale"], 5, false);
    private static readonly EffettiComputer Spenti = new(false, ModiSfondo.Nessuno, false);
    private static readonly EffettiComputer Sfocato = new(true, ModiSfondo.Sfocato, false);

    private static StatoTelefono Stato(string obiettivo = "frontale", bool sfocaturaSistema = false, bool luceSistema = false) =>
        new(80, false, Temperatura.Normale, obiettivo, SfocaturaSistema: sfocaturaSistema, LuceSistema: luceSistema);

    // MARK: la decisione alla prima capacità

    [Fact]
    public void UnTelefonoCheLoSaFareDiventaTelecomando()
    {
        var t = new TelecomandoEffetti();
        Assert.Equal<Messaggio>([new Comando(EffettiSulComputer: true), Sfocato], t.Decidi(Nuovo, Sfocato));
        Assert.True(t.Attivo);
        Assert.Equal(Sfocato, t.Inviati);
        // Le capacità dopo la prima (cambio di obiettivo, Pro) non decidono di nuovo.
        Assert.Empty(t.Decidi(Nuovo, Spenti));
        Assert.Empty(t.Decidi(DiPrima, Spenti));
    }

    [Fact]
    public void UnTelefonoDiPrimaRiceveLoSpegnimento()
    {
        var t = new TelecomandoEffetti();
        Assert.Equal<Messaggio>([RegoleEffettiComputer.SpegniEffettiDelTelefono], t.Decidi(DiPrima, Spenti));
        Assert.False(t.Attivo);
        // Un telefono di prima non riceve mai «effetti».
        Assert.Null(t.DaMandare(Sfocato, sempre: true));
        Assert.Empty(t.Decidi(Nuovo with { EffettiSulComputer = false }, Spenti));
    }

    [Fact]
    public void ASessioneNuovaSiDecideDiNuovo()
    {
        var t = new TelecomandoEffetti();
        t.Decidi(Nuovo, Sfocato);
        t.NuovaSessione();
        Assert.Null(t.Attivo);
        Assert.Null(t.Inviati);
        Assert.Null(t.DaMandare(Sfocato));
        Assert.Equal(2, t.Decidi(Nuovo, Sfocato).Count);
    }

    [Fact]
    public void ConLInterruttoreSpentoNienteDiNuovo()
    {
        var t = new TelecomandoEffetti();
        Assert.Empty(t.Decidi(Nuovo, Spenti, sulComputer: false));
        Assert.Null(t.Attivo);
    }

    // MARK: «effetti» solo quando cambia

    [Fact]
    public void EffettiSoloQuandoCambia()
    {
        var t = new TelecomandoEffetti();
        t.Decidi(Nuovo, Spenti);
        Assert.Null(t.DaMandare(Spenti));
        Assert.Equal(Sfocato, t.DaMandare(Sfocato));
        Assert.Null(t.DaMandare(Sfocato));
        // Come risposta a «chiedi-effetto»: anche se non cambia.
        Assert.Equal(Sfocato, t.DaMandare(Sfocato, sempre: true));
        t.Dimentica();
        Assert.Equal(Sfocato, t.DaMandare(Sfocato));
    }

    // MARK: lo stato con le regole del motore

    private static readonly ValoriEffetti Accesi = RegoleEffettiComputer.Iniziali with
    {
        Specchia = true, Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55, LuceVolto = true,
    };

    [Fact]
    public void LoStatoEQuelloDelMotore()
    {
        Assert.Equal(new EffettiComputer(true, ModiSfondo.Sfocato, true), RegoleTelecomando.Stato(Accesi, false, Stato(), null));
        Assert.Equal(Spenti, RegoleTelecomando.Stato(RegoleEffettiComputer.Iniziali, true, Stato(), null));
        // Con la posteriore niente specchio e niente sfondo; la luce resta.
        Assert.Equal(new EffettiComputer(false, ModiSfondo.Nessuno, true), RegoleTelecomando.Stato(Accesi, true, Stato("principale"), null));
        // Ritratto e Luce da studio del telefono: le nostre restano spente.
        Assert.Equal(new EffettiComputer(true, ModiSfondo.Nessuno, false),
            RegoleTelecomando.Stato(Accesi, true, Stato(sfocaturaSistema: true, luceSistema: true), null));
    }

    [Fact]
    public void SfondoSostituitoSoloConProEUnImmagine()
    {
        var sostituito = Accesi with { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondiPronti.Libreria };
        Assert.Equal(ModiSfondo.Nessuno, RegoleTelecomando.Stato(sostituito, false, Stato(), SfondiPronti.Libreria).Sfondo);
        Assert.Equal(ModiSfondo.Nessuno, RegoleTelecomando.Stato(sostituito, true, Stato(), null).Sfondo);
        Assert.Equal(ModiSfondo.Sostituito, RegoleTelecomando.Stato(sostituito, true, Stato(), SfondiPronti.Libreria).Sfondo);
    }

    // MARK: «chiedi-effetto»

    [Fact]
    public void SfocatoUsaLUltimoLivelloDelPC()
    {
        var c = RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: ModiSfondo.Sfocato), Stato(), LivelloSfocatura.Tanto);
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 1.0), c);
        var valori = RegoleEffettiComputer.Iniziali.Applica(c!);
        Assert.True(valori.SfondoSfocato);
        Assert.Equal(1.0, valori.IntensitaSfondo);
    }

    [Fact]
    public void NessunoSpegneAncheLoSfondoSostituito()
    {
        var c = RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: ModiSfondo.Nessuno), Stato(), LivelloSfocatura.Medio);
        var prima = RegoleEffettiComputer.Iniziali with { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondiPronti.Libreria };
        Assert.Equal(ModiSfondo.Nessuno, prima.Applica(c!).Sfondo);
    }

    [Fact]
    public void SpecchioELuce()
    {
        Assert.Equal(new Comando(Specchia: false, LuceVolto: true),
            RegoleTelecomando.Comando(new ChiediEffetto(Specchia: false, LuceVolto: true), Stato(), LivelloSfocatura.Medio));
        // Tutti e tre insieme, come nell'esempio del documento.
        Assert.Equal(new Comando(Specchia: false, Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.55, LuceVolto: true),
            RegoleTelecomando.Comando(new ChiediEffetto(false, ModiSfondo.Sfocato, true), Stato(), LivelloSfocatura.Medio));
    }

    [Fact]
    public void ConLaPosterioreSpecchioESfondoSiIgnorano()
    {
        Assert.Null(RegoleTelecomando.Comando(new ChiediEffetto(true, ModiSfondo.Sfocato), Stato("principale"), LivelloSfocatura.Medio));
        Assert.Equal(new Comando(LuceVolto: true),
            RegoleTelecomando.Comando(new ChiediEffetto(true, ModiSfondo.Nessuno, true), Stato("tele"), LivelloSfocatura.Medio));
        // Senza stato non si sa ancora: come la frontale (come il motore).
        Assert.Equal(new Comando(Specchia: true), RegoleTelecomando.Comando(new ChiediEffetto(Specchia: true), null, LivelloSfocatura.Medio));
    }

    [Fact]
    public void MaiSopraRitrattoOLuceDaStudio()
    {
        var sistema = Stato(sfocaturaSistema: true, luceSistema: true);
        Assert.Null(RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: ModiSfondo.Sfocato, LuceVolto: true), sistema, LivelloSfocatura.Medio));
        // Spegnere si può sempre.
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Nessuno, LuceVolto: false),
            RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: ModiSfondo.Nessuno, LuceVolto: false), sistema, LivelloSfocatura.Medio));
    }

    [Fact]
    public void UnoSfondoSconosciutoONienteSiIgnora()
    {
        Assert.Null(RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: ModiSfondo.Sostituito), Stato(), LivelloSfocatura.Medio));
        Assert.Null(RegoleTelecomando.Comando(new ChiediEffetto(Sfondo: "marziano"), Stato(), LivelloSfocatura.Medio));
        Assert.Null(RegoleTelecomando.Comando(new ChiediEffetto(), Stato(), LivelloSfocatura.Medio));
    }
}
