using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Gli effetti sul computer: comandi al telefono, regole Pro del motore, preferenze, colonna «Effetti».</summary>
public class EffettiComputerTest
{
    private static readonly Capacita Telefono = new(["frontale", "principale"], 5, true, Filtri: [Filtri.Naturale, Filtri.Caldo],
        Sfondo: true, DoppiaVista: true, Postura: true, Gobbo: true, Pro: true);

    private static StatoTelefono Stato(string obiettivo = "frontale", bool sfocaturaSistema = false, bool luceSistema = false) =>
        new(80, false, Temperatura.Normale, obiettivo, SfocaturaSistema: sfocaturaSistema, LuceSistema: luceSistema);

    [Fact]
    public void LInterruttoreEAccesoDiSerie() => Assert.True(EffettiComputer.EffettiSulComputer);

    [Fact]
    public void AllArrivoIlTelefonoSpegneISuoiEffetti()
    {
        var c = EffettiComputer.SpegniEffettiDelTelefono;
        Assert.Equal(ModiSfondo.Nessuno, c.Sfondo);
        Assert.Equal(Filtri.Naturale, c.Filtro);
        Assert.Equal(new Regolazioni(0, 0, 0, 0), c.Regolazioni);
        Assert.Equal(0, c.Pelle);
        Assert.Equal(0, c.Calore);
        Assert.Equal("", c.Scritta!.Nome);
        Assert.False(c.Specchia);
        Assert.False(c.Inquadratura);
        // Doppia vista, postura e fotocamera non si toccano; il logo del telefono non si cancella.
        Assert.Null(c.DoppiaVista);
        Assert.Null(c.Postura);
        Assert.Null(c.Zoom);
        Assert.Null(c.TogliLogo);
        // Così come va sul filo (Protocollo.md: i campi a null non si scrivono).
        var json = System.Text.Encoding.UTF8.GetString(CodificaMessaggi.Codifica(c));
        Assert.Contains("\"sfondo\":\"nessuno\"", json);
        Assert.Contains("\"specchia\":false", json);
        Assert.DoesNotContain("doppiaVista", json);
    }

    [Fact]
    public void AlTelefonoNonVannoGliEffettiDiImmagine()
    {
        Assert.Null(EffettiComputer.PerIlTelefono(new Comando(Filtro: Filtri.Caldo, Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.5)));
        Assert.Null(EffettiComputer.PerIlTelefono(new Comando(Specchia: true, Calore: 0.3, TogliLogo: true, ImmagineSfondo: "ufficio")));
        var misto = EffettiComputer.PerIlTelefono(new Comando(Zoom: 2, Pelle: 0.4, DoppiaVista: true, Postura: false, Scritta: new Scritta("Ledion")));
        Assert.Equal(new Comando(Zoom: 2, DoppiaVista: true, Postura: false), misto);
    }

    [Fact]
    public void LeCapacitaDegliEffettiLeDaIlComputer()
    {
        var c = EffettiComputer.CapacitaEffetti(Telefono with { Sfondo = false, Pro = false })!;
        Assert.Equal(Filtri.Tutti, c.Filtri);
        Assert.True(c.Sfondo == true && c.Pelle == true && c.Inquadratura == true && c.LuceVolto == true && c.Scritta == true);
        Assert.True(c.Calore == true && c.Specchia == true && c.Immagini == true);
        Assert.Equal(SfondiPronti.Tutti, c.SfondiPronti);
        // Del telefono restano doppia vista, postura, gobbo e Pro.
        Assert.True(c.DoppiaVista == true && c.Gobbo == true);
        Assert.False(c.Pro == true);
        Assert.Null(EffettiComputer.CapacitaEffetti(null));
        Assert.Same(Telefono, EffettiComputer.CapacitaEffetti(Telefono, sulComputer: false));
    }

    [Fact]
    public void LeSceltePassanoDallePreferenze()
    {
        var v = ValoriEffetti.Iniziali with
        {
            Filtro = Filtri.Cinema, Luminosita = 0.2, Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondiPronti.Personale,
            IntensitaSfondo = 0.7, Pelle = 0.4, LuceVolto = true, Inquadratura = true, Specchia = true, Calore = 0.6,
            Scritta = new Scritta("Ledion", "Sviluppatore"),
            // Doppia vista e postura sono del telefono: non si salvano.
            DoppiaVista = true,
        };
        var letti = EffettiComputer.DaTesto(EffettiComputer.InTesto(v));
        Assert.Equal(v with { DoppiaVista = false }, letti);
    }

    [Fact]
    public void PreferenzeMancantiORovinate()
    {
        Assert.Equal(0.3, EffettiComputer.DaTesto(null).Calore);
        Assert.Equal(EffettiComputer.Iniziali, EffettiComputer.DaTesto("{non è json"));
        var fuori = EffettiComputer.DaTesto("{\"Filtro\":\"marziano\",\"Calore\":7,\"Pelle\":-3,\"Sfondo\":\"strano\",\"Luminosita\":4}");
        Assert.Equal(Filtri.Naturale, fuori.Filtro);
        Assert.Equal(1, fuori.Calore);
        Assert.Equal(0, fuori.Pelle);
        Assert.Equal(ModiSfondo.Nessuno, fuori.Sfondo);
        Assert.Equal(1, fuori.Luminosita);
    }

    // MARK: regole del motore

    private static readonly ValoriEffetti Tutto = ValoriEffetti.Iniziali with
    {
        Filtro = Filtri.Caldo, Contrasto = 0.3, Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55, Pelle = 0.5,
        Inquadratura = true, LuceVolto = true, Specchia = true, Calore = 0.3, Scritta = new Scritta("Ledion", "LR Apps"),
    };

    [Fact]
    public void GratisSfocaturaCaloreLuceESpecchio()
    {
        var m = RegoleMotore.Da(Tutto, pro: false, Stato(), null, logo: true);
        Assert.Equal(ModiSfondo.Sfocato, m.Sfondo);
        Assert.Equal(0.55, m.IntensitaSfondo);
        Assert.Equal(0.3, m.Calore);
        Assert.True(m.LuceVolto);
        Assert.True(m.Specchia);
        // Il resto è di Pro.
        Assert.Equal(Filtri.Naturale, m.Filtro);
        Assert.Equal(0, m.Contrasto);
        Assert.Equal(0, m.Pelle);
        Assert.False(m.Inquadratura);
        Assert.Equal("", m.Nome);
        Assert.False(m.Logo);
    }

    [Fact]
    public void SfondoSostituitoSoloConPro()
    {
        var scelti = Tutto with { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = SfondiPronti.Libreria };
        Assert.Equal(ModiSfondo.Nessuno, RegoleMotore.Da(scelti, pro: false, Stato(), SfondiPronti.Libreria, false).Sfondo);
        var pro = RegoleMotore.Da(scelti, pro: true, Stato(), SfondiPronti.Libreria, true);
        Assert.Equal(ModiSfondo.Sostituito, pro.Sfondo);
        Assert.Equal(SfondiPronti.Libreria, pro.ImmagineSfondo);
        Assert.Equal(Filtri.Caldo, pro.Filtro);
        Assert.Equal(0.5, pro.Pelle);
        Assert.Equal("Ledion", pro.Nome);
        Assert.Equal("LR Apps", pro.Ruolo);
        Assert.True(pro.Logo);
    }

    [Fact]
    public void ConLaPosterioreNienteSpecchioENienteSfondo()
    {
        var m = RegoleMotore.Da(Tutto, pro: true, Stato("principale"), null, false);
        Assert.False(m.Specchia);
        Assert.Equal(ModiSfondo.Nessuno, m.Sfondo);
        // Gli altri effetti restano.
        Assert.Equal(0.3, m.Calore);
        Assert.Equal(Filtri.Caldo, m.Filtro);
        // Senza stato non si sa ancora: come la frontale.
        Assert.True(RegoleMotore.Da(Tutto, pro: true, null, null, false).Specchia);
    }

    [Fact]
    public void MaiDueSfocatureNeDueLuci()
    {
        var m = RegoleMotore.Da(Tutto, pro: true, Stato(sfocaturaSistema: true, luceSistema: true), null, false);
        Assert.Equal(ModiSfondo.Nessuno, m.Sfondo);
        Assert.False(m.LuceVolto);
        // Lo sfondo sostituito si sceglie ancora sopra Ritratto.
        var sostituito = RegoleMotore.Da(Tutto with { Sfondo = ModiSfondo.Sostituito }, true, Stato(sfocaturaSistema: true), "ufficio", false);
        Assert.Equal(ModiSfondo.Sostituito, sostituito.Sfondo);
    }

    [Fact]
    public void ScrittaSpentaNonVaAlMotore()
    {
        var m = RegoleMotore.Da(Tutto with { Scritta = Scritta.Nessuna }, pro: true, Stato(), null, false);
        Assert.Equal("", m.Nome);
        Assert.True(RegoleMotore.Da(ValoriEffetti.Iniziali, pro: true, Stato(), null, false).Spente);
    }

    // MARK: la colonna «Effetti» con gli effetti sul computer

    [Fact]
    public void SulComputerLoStatoDelTelefonoNonCambiaLeScelte()
    {
        var controllo = new ControlloEffetti(sulComputer: true, iniziali: EffettiComputer.Iniziali);
        var cambi = 0;
        controllo.Cambiati += () => cambi++;
        controllo.Subito(new Comando(Filtro: Filtri.Seppia), 0);
        Assert.Equal(1, cambi);
        // Il telefono (spento dal PC) dice filtro naturale e calore 0: le scelte del PC restano; doppia vista sì.
        var stato = Stato() with { Filtro = Filtri.Naturale, Calore = 0, DoppiaVista = true, ImmaginePersonale = "abc" };
        Assert.True(controllo.Stato(stato, 10_000));
        Assert.Equal(Filtri.Seppia, controllo.Valori.Filtro);
        Assert.Equal(0.3, controllo.Valori.Calore);
        Assert.True(controllo.Valori.DoppiaVista);
        Assert.Null(controllo.Valori.ImmaginePersonale);
        Assert.True(controllo.ImpostaImmagini("pc", "logo"));
        Assert.Equal("pc", controllo.Valori.ImmaginePersonale);
        Assert.False(controllo.ImpostaImmagini("pc", "logo"));
    }

    [Fact]
    public void SulComputerTuttiGliEffettiAncheConUnTelefonoSemplice()
    {
        var controllo = new ControlloEffetti(sulComputer: true);
        controllo.Capacita(new Capacita(["frontale"], 1, false, Postura: true));
        var d = controllo.Disponibili;
        Assert.Equal(Filtri.Tutti, d.Filtri);
        Assert.True(d.Sfondo && d.Pelle && d.Inquadratura && d.LuceVolto && d.Scritta && d.Calore && d.Postura);
        Assert.False(d.DoppiaVista);
        Assert.False(d.Gobbo);
    }

    [Fact]
    public void SulComputerAzzeraTieneLeScelte()
    {
        var controllo = new ControlloEffetti(sulComputer: true);
        controllo.Subito(new Comando(Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 1, DoppiaVista: true), 0);
        controllo.Azzera();
        Assert.Equal(ModiSfondo.Sfocato, controllo.Valori.Sfondo);
        Assert.False(controllo.Valori.DoppiaVista);
        Assert.Equal(DisponibilitaEffetti.Nessuno, controllo.Disponibili);

        var telefono = new ControlloEffetti();
        telefono.Subito(new Comando(Sfondo: ModiSfondo.Sfocato), 0);
        telefono.Azzera();
        Assert.Equal(ModiSfondo.Nessuno, telefono.Valori.Sfondo);
    }
}
