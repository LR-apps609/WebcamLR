using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>WebcamLR Pro sul PC (capacita.pro), «Qualità video» e profili pronti, come sul Mac.</summary>
public class ProEProfiliTest
{
    private static Capacita Telefono(bool? pro = null, IReadOnlyList<FormatoSupportato>? formati = null) =>
        new(["grandangolo", "principale", "frontale"], 5, true, 25, 3200, Filtri: Filtri.Tutti, Sfondo: true, Pelle: true,
            Inquadratura: true, LuceVolto: true, Scritta: true, DoppiaVista: true, Postura: true, Gobbo: true,
            Formati: formati, Specchia: true, Pro: pro);

    [Fact]
    public void ProSoloSeIlTelefonoLoDice()
    {
        Assert.True(RegolePro.Attivo(Telefono(pro: true)));
        // Falso o assente (telefono vecchio) = gratis.
        Assert.False(RegolePro.Attivo(Telefono(pro: false)));
        Assert.False(RegolePro.Attivo(Telefono()));
        Assert.False(RegolePro.Attivo(null));

        // Il segno «PRO» solo con un telefono collegato e pronto: senza telefono i comandi sono già grigi.
        Assert.True(RegolePro.Bloccato(true, Telefono()));
        Assert.False(RegolePro.Bloccato(true, Telefono(pro: true)));
        Assert.False(RegolePro.Bloccato(false, Telefono()));
        Assert.False(RegolePro.Bloccato(true, null));
    }

    [Fact]
    public void GratisFinoA720pA30()
    {
        Assert.True(RegolePro.FormatoGratis(1280, 720, 30));
        Assert.True(RegolePro.FormatoGratis(720, 1280, 30));
        Assert.True(RegolePro.FormatoGratis(640, 360, 30));
        Assert.False(RegolePro.FormatoGratis(1280, 720, 60));
        Assert.False(RegolePro.FormatoGratis(1920, 1080, 30));
        Assert.False(RegolePro.FormatoGratis(3840, 2160, 30));
    }

    [Fact]
    public void SenzaProSpegnereSiPuoAccendereNo()
    {
        var tutto = new Comando(Filtro: Filtri.Cinema, Regolazioni: new Regolazioni(0.2), Sfondo: ModiSfondo.Sostituito,
            Pelle: 0.4, Inquadratura: true, Scritta: new Scritta("Ledion"), DoppiaVista: true, Iso: 400, Tempo: 60, Bianco: 4300,
            LuceVolto: true, Zoom: 2, Specchia: true);
        var gratis = RegolePro.SenzaPro(tutto);
        Assert.Equal(new Comando(LuceVolto: true, Zoom: 2, Specchia: true), gratis);

        var spegni = new Comando(Filtro: Filtri.Naturale, Regolazioni: new Regolazioni(0, 0, 0, 0), Sfondo: ModiSfondo.Sfocato,
            Pelle: 0, Inquadratura: false, Scritta: Scritta.Nessuna, DoppiaVista: false, Iso: 0, Tempo: 0, Bianco: 0);
        Assert.Equal(spegni, RegolePro.SenzaPro(spegni));

        Assert.True(RegolePro.Vuoto(RegolePro.SenzaPro(new Comando(Pelle: 0.5))));
        Assert.False(RegolePro.Vuoto(new Comando(Torcia: false)));
    }

    [Fact]
    public void TestiDiconoSulTelefono()
    {
        Assert.Contains("sul telefono", RegolePro.Sblocca);
        Assert.DoesNotContain("iPhone", RegolePro.Sblocca + RegolePro.Strada + RegolePro.SecondoTelefono);
        Assert.Contains("«iPhone di Sara»", RegolePro.MessaggioSecondoTelefono("iPhone di Sara"));
        Assert.StartsWith("Nessun telefono", RegolePro.StatoTelefono(null, null));
        Assert.Contains("Pro attivo", RegolePro.StatoTelefono("Pixel", Telefono(pro: true)));
        Assert.Contains("versione gratuita", RegolePro.StatoTelefono("Pixel", Telefono()));
    }

    [Fact]
    public void QualitaDalleCapacita()
    {
        // Senza «formati»: le tre scelte comuni.
        Assert.Equal([new OpzioneQualita(1280, 720, 30), new(1920, 1080, 30), new(1920, 1080, 60)], OpzioneQualita.Elenco(null));
        // Con i formati: 30 e 60 dove ci arriva, il 4K solo a 30 anche se il telefono dichiara 60.
        var capacita = Telefono(formati: [new(3840, 2160, 60), new(1920, 1080, 60), new(1280, 720, 30)]);
        Assert.Equal([new OpzioneQualita(1280, 720, 30), new(1920, 1080, 30), new(1920, 1080, 60), new(3840, 2160, 30)],
            OpzioneQualita.Elenco(capacita));
        Assert.Equal("1080p · 60 fps", new OpzioneQualita(1920, 1080, 60).Testo);
    }

    [Fact]
    public void QualitaGratisConLeSceltePro()
    {
        var capacita = Telefono(formati: [new(3840, 2160, 30), new(1920, 1080, 60), new(1280, 720, 60)]);
        var (libere, bloccate) = OpzioneQualita.Menu(capacita, bloccoPro: true);
        Assert.Equal([new OpzioneQualita(1280, 720, 30)], libere);
        Assert.Equal(OpzioneQualita.SceltePro, bloccate);
        Assert.All(bloccate, o => Assert.True(o.SoloPro));
        // Con Pro tutto libero, niente bloccato.
        var (tutte, nessuna) = OpzioneQualita.Menu(capacita, bloccoPro: false);
        Assert.Equal(OpzioneQualita.Elenco(capacita), tutte);
        Assert.Empty(nessuna);
    }

    [Fact]
    public void QualitaAttualeDalleStatistiche()
    {
        var opzioni = OpzioneQualita.Elenco(null);
        Assert.Equal(new OpzioneQualita(1920, 1080, 60), OpzioneQualita.Attuale(new Statistiche(1920, 1080, 58, 8, 40), opzioni));
        Assert.Equal(new OpzioneQualita(1920, 1080, 30), OpzioneQualita.Attuale(new Statistiche(1080, 1920, 29, 8, 40), opzioni));
        Assert.Null(OpzioneQualita.Attuale(new Statistiche(0, 0, 0, 0, null), opzioni));
        Assert.Null(OpzioneQualita.Attuale(null, opzioni));
    }

    [Fact]
    public void RichiestaDelFormato()
    {
        var attuale = new FormatoVideo(Codec.H264, 1920, 1080, 30);
        FormatoSupportato[] formati = [new(3840, 2160, 60), new(1920, 1080, 60), new(1280, 720, 30)];
        // Il 4K si chiede a 30 e in HEVC.
        Assert.Equal(new FormatoVideo(Codec.Hevc, 3840, 2160, 30), OpzioneQualita.Richiesta(3840, 2160, 60, attuale, formati, pro: true));
        // Lo stesso codec di prima sotto il 4K.
        Assert.Equal(new FormatoVideo(Codec.H264, 1920, 1080, 60), OpzioneQualita.Richiesta(1920, 1080, 60, attuale, formati, pro: true));
        // Non oltre ciò che il telefono dichiara.
        Assert.Equal(new FormatoVideo(Codec.H264, 1280, 720, 30), OpzioneQualita.Richiesta(1280, 720, 60, attuale, formati, pro: true));
        // Già così: niente da chiedere.
        Assert.Null(OpzioneQualita.Richiesta(1920, 1080, 30, attuale, formati, pro: true));
        // Risoluzione non elencata.
        Assert.Null(OpzioneQualita.Richiesta(2560, 1440, 30, attuale, formati, pro: true));
        // In verticale i lati si scambiano.
        var verticale = new FormatoVideo(Codec.Hevc, 1080, 1920, 30);
        Assert.Equal(new FormatoVideo(Codec.Hevc, 1080, 1920, 60), OpzioneQualita.Richiesta(1920, 1080, 60, verticale, formati, pro: true));
        // Gratis: sopra 720p30 non si chiede nulla, 720p30 sì.
        Assert.Null(OpzioneQualita.Richiesta(1920, 1080, 60, attuale, formati, pro: false));
        Assert.Equal(new FormatoVideo(Codec.H264, 1280, 720, 30), OpzioneQualita.Richiesta(1280, 720, 30, attuale, formati, pro: false));
        // Senza formato attuale (il telefono non ha ancora detto nulla): HEVC.
        Assert.Equal(new FormatoVideo(Codec.Hevc, 1920, 1080, 30), OpzioneQualita.Richiesta(1920, 1080, 30, null, null, pro: true));
    }

    [Fact]
    public void QuattroProfiliComeSulMac()
    {
        Assert.Equal(["riunione", "lezione", "diretta", "colloquio"], ProfiloPronto.Tutti.Select(p => p.Id));
        Assert.Equal(["Riunione", "Lezione", "Diretta", "Colloquio"], ProfiloPronto.Tutti.Select(p => p.Nome));
        Assert.Equal(60, ProfiloPronto.Diretta.Fps);
        Assert.False(ProfiloPronto.Diretta.LuceVolto);
        Assert.Same(ProfiloPronto.Colloquio, ProfiloPronto.Cerca("colloquio"));
        Assert.Null(ProfiloPronto.Cerca("festa"));
        Assert.Contains("sfondo sfocato", ProfiloPronto.Colloquio.Riepilogo);
        Assert.StartsWith("1080p60", ProfiloPronto.Diretta.Riepilogo);
    }

    [Fact]
    public void IlProfiloMandaSoloCiòCheIlTelefonoSaFare()
    {
        var completo = ProfiloPronto.Colloquio.Comando(Telefono(pro: true));
        Assert.Equal(new Comando(LuceVolto: true, Inquadratura: true, DoppiaVista: false, Filtro: Filtri.Naturale,
            Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.35, Pelle: 0.2), completo);

        // Un telefono senza doppia vista, sfondo né pelle: «Lezione» senza quella parte.
        var semplice = new Capacita(["principale"], 3, false, LuceVolto: true, Inquadratura: true);
        Assert.Equal(new Comando(LuceVolto: true, Inquadratura: false), ProfiloPronto.Lezione.Comando(semplice));
        // Un telefono senza effetti: niente da mandare.
        Assert.Null(ProfiloPronto.Riunione.Comando(new Capacita(["principale"], 3, false)));
    }

    [Fact]
    public void PersonalizzatoQuandoSiCambiaQualcosa()
    {
        var capacita = Telefono(pro: true);
        var valori = ProfiloPronto.Colloquio.Applica(ValoriEffetti.Iniziali, capacita);
        Assert.Equal((ProfiloPronto.Colloquio, false), ProfiloPronto.Stato("colloquio", valori, capacita));
        // Il telefono rimanda i valori con i suoi decimali: è ancora il profilo.
        Assert.Equal((ProfiloPronto.Colloquio, false),
            ProfiloPronto.Stato("colloquio", valori with { IntensitaSfondo = 0.349, Pelle = 0.21 }, capacita));
        // L'utente cambia il filtro: «Personalizzato».
        Assert.Equal((null, true), ProfiloPronto.Stato("colloquio", valori with { Filtro = Filtri.Cinema }, capacita));
        // Lo specchio non fa parte del profilo.
        Assert.Equal((ProfiloPronto.Colloquio, false), ProfiloPronto.Stato("colloquio", valori with { Specchia = true }, capacita));
        // Nessun profilo scelto.
        Assert.Equal((null, false), ProfiloPronto.Stato(null, valori, capacita));
    }

    [Fact]
    public void LezioneConLaFrontaleLoDice()
    {
        var capacita = Telefono(pro: true);
        Assert.NotNull(ProfiloPronto.Lezione.Avviso(capacita, "frontale"));
        Assert.Null(ProfiloPronto.Lezione.Avviso(capacita, "grandangolo"));
        Assert.Null(ProfiloPronto.Riunione.Avviso(capacita, "frontale"));
    }
}

/// <summary>Specchio unico (1.14), «Sfoca sfondo» a un clic e i comandi della fotocamera che seguono lo «stato».</summary>
public class SpecchioEStatoTest
{
    private static StatoTelefono Stato(string obiettivo = "frontale") => new(80, false, Temperatura.Normale, obiettivo);

    [Fact]
    public void IlPulsanteSegueLoStatoDelTelefono()
    {
        var effetti = new ControlloEffetti();
        Assert.False(effetti.Valori.Specchia);
        // Specchiato sul telefono: il PC lo mostra.
        Assert.True(effetti.Stato(Stato() with { Specchia = true }, 0));
        Assert.True(effetti.Valori.Specchia);
        // Clic sul PC: il comando gira lo specchio di adesso.
        Assert.Equal(new Comando(Specchia: false), effetti.AlternaSpecchio(10_000));
        Assert.False(effetti.Valori.Specchia);
        // Uno stato partito prima del clic non lo riporta indietro…
        effetti.Stato(Stato() with { Specchia = true }, 10_500);
        Assert.False(effetti.Valori.Specchia);
        // …ma passato l'attimo lo stato vince sempre: è l'unica fonte di verità.
        effetti.Stato(Stato() with { Specchia = true }, 12_000);
        Assert.True(effetti.Valori.Specchia);
        // Un telefono che non manda «specchia» non cambia nulla.
        effetti.Stato(Stato(), 20_000);
        Assert.True(effetti.Valori.Specchia);
    }

    [Fact]
    public void UnireDueComandiTieneLoSpecchio()
    {
        Assert.Equal(new Comando(Specchia: true, Pelle: 0.3), Comandi.Unisci(new Comando(Specchia: true), new Comando(Pelle: 0.3)));
        Assert.Equal(["specchia"], CampoEffetto.Di(new Comando(Specchia: false)));
    }

    [Fact]
    public void SfocaSfondoAUnClic()
    {
        var effetti = new ControlloEffetti();
        effetti.Stato(Stato() with { IntensitaSfondo = 0.7 }, 0);
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.7), effetti.AlternaSfocatura(5_000));
        Assert.True(effetti.Valori.SfondoSfocato);
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Nessuno), effetti.AlternaSfocatura(6_000));
        Assert.False(effetti.Valori.SfondoSfocato);
        // Con lo sfondo sostituito il pulsante è spento e un clic sfoca.
        effetti.Stato(Stato() with { Sfondo = ModiSfondo.Sostituito }, 20_000);
        Assert.False(effetti.Valori.SfondoSfocato);
        Assert.Equal(ModiSfondo.Sfocato, effetti.AlternaSfocatura(21_000).Sfondo);
    }

    [Fact]
    public void ZoomTorciaEsposizioneSeguonoIlTelefono()
    {
        var allineamento = new AllineamentoFotocamera();
        var capacita = new Capacita(["principale", "frontale"], 5, true, 25, 3200);
        var comandi = ComandiFotocamera.Iniziali;
        var stato = Stato("principale") with { Zoom = 2.5, Torcia = true, Esposizione = -0.5, Bianco = 4300, Iso = 400, Tempo = 50 };
        comandi = allineamento.Allinea(comandi, stato, null, capacita, 0);
        Assert.Equal(new ComandiFotocamera(2.5, true, -0.5, false, 4300, true, 400, 50), comandi);
        // ISO e tempo a 0: esposizione automatica; bianco 0: automatico.
        comandi = allineamento.Allinea(comandi, stato with { Iso = 0, Tempo = 0, Bianco = 0 }, "principale", capacita, 1000);
        Assert.False(comandi.Manuale);
        Assert.True(comandi.BiancoAutomatico);
    }

    [Fact]
    public void IlComandoAppenaMandatoNonTornaIndietro()
    {
        var allineamento = new AllineamentoFotocamera();
        var comandi = ComandiFotocamera.Iniziali with { Zoom = 3 };
        allineamento.Segna(new Comando(Zoom: 3), 10_000);
        // Lo stato partito prima del comando dice ancora 1: per un attimo vale il PC.
        comandi = allineamento.Allinea(comandi, Stato() with { Zoom = 1 }, "frontale", null, 10_400);
        Assert.Equal(3, comandi.Zoom);
        // Poi vale il telefono (per esempio un pizzico).
        comandi = allineamento.Allinea(comandi, Stato() with { Zoom = 1.8 }, "frontale", null, 12_000);
        Assert.Equal(1.8, comandi.Zoom);
    }

    [Fact]
    public void TelefonoVecchioCambioDiObiettivo()
    {
        var allineamento = new AllineamentoFotocamera();
        var comandi = ComandiFotocamera.Iniziali with { Zoom = 2, Torcia = true };
        // Senza i campi della 1.14: allo stesso obiettivo nulla cambia, a un obiettivo nuovo zoom 1 e torcia spenta.
        Assert.Equal(comandi, allineamento.Allinea(comandi, Stato("principale"), "principale", null, 0));
        var dopo = allineamento.Allinea(comandi, Stato("frontale"), "principale", null, 0);
        Assert.Equal(1, dopo.Zoom);
        Assert.False(dopo.Torcia);
    }

    [Fact]
    public void ValoriFuoriMisuraNeiLimiti()
    {
        var allineamento = new AllineamentoFotocamera();
        var capacita = new Capacita(["principale"], 4, true, 50, 1600);
        var comandi = allineamento.Allinea(ComandiFotocamera.Iniziali,
            Stato("principale") with { Zoom = 40, Esposizione = 9, Bianco = 99_999, Iso = 10_000, Tempo = 60 }, null, capacita, 0);
        Assert.Equal(4, comandi.Zoom);
        Assert.Equal(2, comandi.Esposizione);
        Assert.Equal(7500, comandi.Bianco);
        Assert.Equal(1600, comandi.Iso);
        // Senza i limiti ISO del telefono niente esposizione manuale.
        Assert.False(allineamento.Allinea(ComandiFotocamera.Iniziali, Stato() with { Iso = 400, Tempo = 60 }, null, null, 0).Manuale);
    }
}

/// <summary>Messaggi strani dalla rete: nei limiti prima della finestra.</summary>
public class ValoriSicuriTest
{
    [Fact]
    public void CapacitaRotte()
    {
        var rotta = new Capacita(null!, double.PositiveInfinity, true, IsoMinimo: 800, IsoMassimo: 100,
            Filtri: ["", "caldo", "caldo", new string('x', 500)], Formati: [new(0, 0, 30), new(1920, 1080, 60), null!, new(99999, 10, 30)]);
        var sana = ValoriSicuri.Sanifica(rotta);
        Assert.Empty(sana.Obiettivi);
        Assert.Equal(1, sana.ZoomMassimo);
        Assert.Null(sana.IsoMinimo);
        Assert.Null(sana.IsoMassimo);
        Assert.Equal(2, sana.Filtri!.Count);
        Assert.Equal(ValoriSicuri.VoceMassima, sana.Filtri[1].Length);
        Assert.Equal([new FormatoSupportato(1920, 1080, 60)], sana.Formati);
        Assert.Equal(100, ValoriSicuri.Sanifica(new Capacita(["principale"], 1e300, false)).ZoomMassimo);
    }

    [Fact]
    public void StatoRotto()
    {
        var rotto = new StatoTelefono(999, false, (Temperatura)42, null!, Scritta: new Scritta(null!, new string('r', 300)),
            Zoom: -3, Esposizione: 1e9, Bianco: 100, Tempo: -5, Gobbo: new StatoGobbo(true, 7));
        var sano = ValoriSicuri.Sanifica(rotto);
        Assert.Equal(-1, sano.Batteria);
        Assert.Equal(Temperatura.Normale, sano.Temperatura);
        Assert.Equal("", sano.Obiettivo);
        Assert.Equal("", sano.Scritta!.Nome);
        Assert.Equal(80, sano.Scritta.Ruolo!.Length);
        Assert.Equal(1, sano.Zoom);
        Assert.Equal(2, sano.Esposizione);
        Assert.Equal(2500, sano.Bianco);
        Assert.Equal(0, sano.Tempo);
        Assert.Equal(1, sano.Gobbo!.Posizione);
        // Il resto della finestra regge: la scritta con il nome nullo non è «mostrata».
        Assert.False(ValoriEffetti.Iniziali.Applica(new Comando(Scritta: new Scritta(null!))).ScrittaMostrata);
    }

    [Fact]
    public void NomeEFormato()
    {
        var ciao = ValoriSicuri.Sanifica(new Ciao(2, null!, Piattaforma.Android, null!));
        Assert.Equal("Telefono", ciao.Nome);
        Assert.Equal("", ciao.VersioneApp);
        Assert.Equal("iPhone di Ledion", ValoriSicuri.Sanifica(new Ciao(2, "iPhone\u0000 di Ledion\n", Piattaforma.Iphone, "1.0")).Nome.Replace("  ", " "));
        Assert.Equal(ValoriSicuri.NomeMassimo, ValoriSicuri.Sanifica(new Ciao(2, new string('n', 5000), Piattaforma.Iphone, "1")).Nome.Length);

        Assert.NotNull(ValoriSicuri.Sanifica(new FormatoVideo(Codec.Hevc, 3840, 2160, 30)));
        Assert.Null(ValoriSicuri.Sanifica(new FormatoVideo(Codec.H264, 0, 1080, 30)));
        Assert.Null(ValoriSicuri.Sanifica(new FormatoVideo(Codec.H264, 100_000, 1080, 30)));
        Assert.Null(ValoriSicuri.Sanifica(new FormatoVideo(Codec.H264, 1920, 1080, 0)));
        Assert.Null(ValoriSicuri.Sanifica(new FormatoVideo((Codec)9, 1920, 1080, 30)));
    }
}

/// <summary>«Aggiornamento disponibile»: il file versione.json del sito, come sul Mac.</summary>
public class AggiornamentiTest
{
    [Fact]
    public void LeggeIlFileDelSito()
    {
        var letta = Aggiornamenti.Leggi("""
            {"versione":"1.0.1","build":3,"data":"2026-11-02","pagina":"https://lr-apps609.github.io/WebcamLR/download.html","novita":"Finestra nuova."}
            """);
        Assert.NotNull(letta);
        Assert.Equal("1.0.1 (3)", letta!.Testo);
        Assert.Equal("2 novembre 2026", letta.DataLeggibile);
        Assert.Equal(new Uri("https://lr-apps609.github.io/WebcamLR/download.html"), letta.Indirizzo);
        // La build anche come testo.
        Assert.Equal(7, Aggiornamenti.Leggi("""{"versione":"1.2","build":"7"}""")!.Build);
    }

    [Fact]
    public void IlPcPuòAvereLaSuaVersione()
    {
        var letta = Aggiornamenti.Leggi("""{"versione":"1.3","build":9,"windows":{"versione":"1.0.2"}}""");
        Assert.Equal("1.0.2", letta!.Versione);
        Assert.Null(letta.Build);
        // Un oggetto «windows» senza versione valida non conta.
        Assert.Equal("1.3", Aggiornamenti.Leggi("""{"versione":"1.3","windows":{"data":"x"}}""")!.Versione);
    }

    [Theory]
    [InlineData("")]
    [InlineData("non json")]
    [InlineData("[1,2]")]
    [InlineData("""{"build":3}""")]
    [InlineData("""{"versione":""}""")]
    [InlineData("""{"versione":"beta"}""")]
    [InlineData("""{"versione":12}""")]
    public void FileSbagliatoNonDiceNiente(string json) => Assert.Null(Aggiornamenti.Leggi(json));

    [Fact]
    public void SoloIndirizziSicuri()
    {
        Assert.Equal(new Uri(InfoApp.Download), new VersionePubblicata("2.0", null, null, "javascript:alert(1)", null).Indirizzo);
        Assert.Equal(new Uri(InfoApp.Download), new VersionePubblicata("2.0", null, null, "http://esempio.it", null).Indirizzo);
        Assert.Equal("domani", new VersionePubblicata("2.0", null, "domani", null, null).DataLeggibile);
    }

    [Fact]
    public void ConfrontoNumeroPerNumero()
    {
        Assert.Equal(1, Aggiornamenti.Confronta("1.10", "1.9"));
        Assert.Equal(0, Aggiornamenti.Confronta("1.0", "1.0.0"));
        Assert.Equal(-1, Aggiornamenti.Confronta("1.0", "1.0.1"));
        Assert.Equal(0, Aggiornamenti.Confronta("1.0.1 (3)", "1.0.1"));
        Assert.Equal(1, Aggiornamenti.Confronta("2", "1.99.99"));
        // Numeri enormi non fanno cadere niente.
        Assert.Equal(1, Aggiornamenti.Confronta("99999999999999.1", "1"));

        var nuova = new VersionePubblicata("1.0.0", 5, null, null, null);
        Assert.True(Aggiornamenti.PiuRecente(nuova, "1.0.0", 4));
        Assert.False(Aggiornamenti.PiuRecente(nuova, "1.0.0", 5));
        Assert.False(Aggiornamenti.PiuRecente(nuova with { Build = null }, "1.0.0", 0));
        Assert.True(Aggiornamenti.PiuRecente(new VersionePubblicata("1.1", null, null, null, null), "1.0.9", 99));
    }

    [Fact]
    public async Task SenzaReteNonDiceNiente()
    {
        using var client = new HttpClient(new GestoreRotto());
        Assert.Null(await Aggiornamenti.ScaricaAsync(client));
    }

    private sealed class GestoreRotto : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            throw new HttpRequestException("Nessuna rete");
    }
}
