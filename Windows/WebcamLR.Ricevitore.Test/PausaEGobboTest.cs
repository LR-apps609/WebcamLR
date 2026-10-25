using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

public class PausaEGobboTest
{
    private static StatoTelefono Stato(string? pausa = null) => new(80, false, Temperatura.Normale, "principale", Pausa: pausa);

    [Fact]
    public void MotiviDellaPausa()
    {
        Assert.False(PausaIntelligente.InPausa(null));
        Assert.False(PausaIntelligente.InPausa(Stato()));
        Assert.True(PausaIntelligente.InPausa(Stato(MotiviPausa.FacciaInGiu)));
        Assert.Equal("Il telefono è a faccia in giù", PausaIntelligente.Motivo(MotiviPausa.FacciaInGiu));
        Assert.Equal("Nessuna app usa la webcam", PausaIntelligente.Motivo(MotiviPausa.NessunaApp));
        Assert.Equal("In pausa dal telefono", PausaIntelligente.Motivo(MotiviPausa.Utente));
        // Un motivo sconosciuto è una pausa qualsiasi.
        Assert.True(PausaIntelligente.InPausa(Stato("batteria-scarica")));
        Assert.Equal("Il telefono ha messo in pausa il video", PausaIntelligente.Motivo("batteria-scarica"));
        Assert.EndsWith(".", PausaIntelligente.Suggerimento("batteria-scarica"));
    }

    [Theory]
    [InlineData(true, false, false, false, true)]   // finestra aperta
    [InlineData(true, true, false, false, false)]   // ridotta a icona
    [InlineData(false, false, false, false, false)] // nascosta accanto all'orologio
    [InlineData(true, false, true, false, true)]    // finestra mini
    [InlineData(false, false, false, true, true)]   // nascosta ma registra: il video serve
    [InlineData(true, true, false, true, true)]
    public void QuandoLAnteprimaEVisibile(bool mostrata, bool ridotta, bool mini, bool registra, bool attesa) =>
        Assert.Equal(attesa, PausaIntelligente.AnteprimaVisibile(mostrata, ridotta, mini, registra));

    [Fact]
    public void Chiede60FpsUnaVoltaPerPeriodoDUso()
    {
        var richiesta = new Richiesta60Fps();
        var attuale = new FormatoVideo(Codec.H264, 1920, 1080, 30);
        FormatoSupportato[] formati = [new(3840, 2160, 30), new(1920, 1080, 60), new(1280, 720, 60)];

        // Webcam a 30 fps, o nessuna app: niente.
        Assert.Null(richiesta.Valuta(true, 30, attuale, formati));
        Assert.Null(richiesta.Valuta(false, 60, attuale, formati));
        // App a 60 fps e telefono a 30: si chiede, una volta sola.
        Assert.Equal(new FormatoVideo(Codec.H264, 1920, 1080, 60), richiesta.Valuta(true, 60, attuale, formati));
        Assert.True(richiesta.Chiesta);
        Assert.Null(richiesta.Valuta(true, 60, attuale, formati));
        // Il telefono già a 60: niente. L'app chiude la webcam: al prossimo uso si richiede.
        Assert.Null(richiesta.Valuta(true, 60, attuale with { Fps = 60 }, formati));
        Assert.Null(richiesta.Valuta(false, 0, attuale, formati));
        Assert.False(richiesta.Chiesta);
        Assert.NotNull(richiesta.Valuta(true, 60, attuale, formati));
    }

    [Fact]
    public void Non60FpsSeIlTelefonoNonCeLaFa()
    {
        var richiesta = new Richiesta60Fps();
        var attuale = new FormatoVideo(Codec.Hevc, 3840, 2160, 30);
        // In 4K il telefono arriva a 30: non si chiede (stessa risoluzione, come sul Mac), e si può riprovare se
        // le capacità cambiano (altro obiettivo).
        Assert.Null(richiesta.Valuta(true, 60, attuale, [new(3840, 2160, 30), new(1920, 1080, 60)]));
        Assert.False(richiesta.Chiesta);
        // Risoluzione non elencata: non ci arriva.
        Assert.Null(Richiesta60Fps.Scegli(new FormatoVideo(Codec.H264, 1440, 1080, 30), [new(1920, 1080, 60)]));
        // Il 4K resta a 30 fps (1.14), anche se il telefono dichiara di più o non dice niente.
        Assert.Null(Richiesta60Fps.Scegli(attuale, [new(3840, 2160, 60)]));
        Assert.Null(richiesta.Valuta(true, 60, attuale, null));
        var hd = new FormatoVideo(Codec.H264, 1920, 1080, 30);
        // Al massimo quello che dichiara.
        Assert.Equal(hd with { Fps = 50 }, Richiesta60Fps.Scegli(hd, [new(1920, 1080, 50)]));
        // Senza «formati» si chiede e si guarda la risposta.
        Assert.Equal(hd with { Fps = 60 }, richiesta.Valuta(true, 60, hd, null));
    }

    [Fact]
    public void Chiede60FpsAncheInVerticale()
    {
        var verticale = new FormatoVideo(Codec.H264, 1080, 1920, 30);
        Assert.Equal(verticale with { Fps = 60 }, Richiesta60Fps.Scegli(verticale, [new(1920, 1080, 60)]));
    }

    [Fact]
    public void LaPausaNonDiventaUnBucoNelVideo()
    {
        var tempi = new TempiVideo();
        Assert.Equal(0, tempi.Microsecondi(5_000_000));
        Assert.Equal(33_333, tempi.Microsecondi(5_033_333));
        // 20 secondi di pausa: il fotogramma dopo arriva un passo dopo, non 20 secondi dopo.
        Assert.Equal(66_666, tempi.Microsecondi(25_033_333));
        Assert.Equal(99_999, tempi.Microsecondi(25_066_666));
        // Piccoli passi indietro restano: la somma torna giusta.
        Assert.Equal(83_333, tempi.Microsecondi(25_050_000));
        Assert.Equal(116_666, tempi.Microsecondi(25_083_333));
        // Orologio del telefono ripartito (indietro di molto): si continua.
        Assert.Equal(149_999, tempi.Microsecondi(1_000));
        tempi.Azzera();
        Assert.Equal(0, tempi.Microsecondi(42));
    }

    [Fact]
    public void GobboRicordaERimanda()
    {
        var gobbo = new MemoriaGobbo();
        Assert.Null(gobbo.DaRimandare());
        // Lo stato del gobbo prima di averne mandato uno non conta.
        Assert.False(gobbo.Stato(new StatoGobbo(true, 0.5)));

        gobbo.Imposta(velocita: 2, dimensione: DimensioniGobbo.Grande);
        var primo = gobbo.Prepara(new Gobbo("Buongiorno a tutti.\r\nOggi parliamo del progetto.", gobbo.Velocita, true, gobbo.Dimensione));
        Assert.Equal(new Gobbo("Buongiorno a tutti.\nOggi parliamo del progetto.", 2, true, "grande"), primo);
        Assert.True(gobbo.Inviato);

        Assert.True(gobbo.Stato(new StatoGobbo(true, 0.42)));
        Assert.False(gobbo.Stato(new StatoGobbo(true, 0.42)));
        Assert.Equal("42%", MemoriaGobbo.TestoPosizione(gobbo.Posizione));
        Assert.True(gobbo.Stato(new StatoGobbo(false, 0.5)));

        // Lo stesso telefono si ricollega: il gobbo completo, dall'ultima posizione.
        Assert.Equal(new Gobbo("Buongiorno a tutti.\nOggi parliamo del progetto.", 2, false, "grande", 0.5), gobbo.DaRimandare());

        // Un altro telefono: niente da rimandare, il testo resta per «Avvia».
        gobbo.Azzera();
        Assert.Null(gobbo.DaRimandare());
        Assert.Equal("Buongiorno a tutti.\nOggi parliamo del progetto.", gobbo.Testo);
    }

    [Fact]
    public void GobboNeiLimitiDelProtocollo()
    {
        var gobbo = new MemoriaGobbo();
        var pronto = gobbo.Prepara(new Gobbo(new string('a', 25_000), Velocita: 9, Dimensione: "enorme", Posizione: 4));
        Assert.Equal(Gobbo.LunghezzaMassima, pronto.Testo!.Length);
        Assert.Equal(Gobbo.VelocitaMassima, pronto.Velocita);
        Assert.Equal(DimensioniGobbo.Media, pronto.Dimensione);
        Assert.Equal(1, pronto.Posizione);
        Assert.Equal(Gobbo.VelocitaMinima, gobbo.Prepara(new Gobbo(Velocita: 0.1)).Velocita);
        // Un carattere doppio (emoji) a cavallo del limite non si spezza.
        var emoji = new string('a', Gobbo.LunghezzaMassima - 1) + "😀";
        Assert.Equal(Gobbo.LunghezzaMassima - 1, MemoriaGobbo.Taglia(emoji).Length);
        // Un testo nuovo riparte dall'inizio.
        gobbo.Stato(new StatoGobbo(true, 0.7));
        gobbo.Prepara(new Gobbo("Altro testo"));
        Assert.Equal(0, gobbo.Posizione);
    }

    [Fact]
    public void TestiDelGobbo()
    {
        Assert.Equal("1,5 righe al secondo", MemoriaGobbo.TestoVelocita(1.5));
        Assert.Equal("1.234 / 20.000 caratteri", MemoriaGobbo.TestoCaratteri(1234));
    }
}
