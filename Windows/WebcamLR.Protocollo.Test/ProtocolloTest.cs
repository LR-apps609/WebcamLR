using System.Text;
using System.Text.Json.Nodes;
using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Protocollo.Test;

public class ProtocolloTest
{
    [Fact]
    public void IntestazioneBigEndian()
    {
        var dati = new Pacchetto(TipoPacchetto.Video, 3, new byte[258]).Codificato();
        Assert.Equal(new byte[] { 2, 3, 0, 0, 1, 2 }, dati[..6]);
        Assert.Equal(264, dati.Length);
    }

    [Fact]
    public void LetturaAPezzi()
    {
        var primo = new Pacchetto(TipoPacchetto.Controllo, 0, Encoding.UTF8.GetBytes("abc"));
        var secondo = new Pacchetto(TipoPacchetto.Audio, 0, [1, 2, 3, 4]);
        var flusso = primo.Codificato().Concat(secondo.Codificato()).ToArray();

        var lettore = new LettorePacchetti();
        var letti = new List<Pacchetto>();
        foreach (var b in flusso)
        {
            lettore.Aggiungi([b]);
            while (lettore.Prossimo() is { } pacchetto) letti.Add(pacchetto);
        }
        Assert.Equal([primo, secondo], letti);
    }

    [Fact]
    public void TipoSconosciutoChiudeLaConnessione()
    {
        var lettore = new LettorePacchetti();
        lettore.Aggiungi([9, 0, 0, 0, 0, 0]);
        Assert.Throws<ErroreProtocollo>(() => lettore.Prossimo());
    }

    [Fact]
    public void Fotogramma()
    {
        var fotogramma = new FotogrammaVideo(0x0102030405060708, true, true, [0, 0, 0, 1, 0x65]);
        var pacchetto = fotogramma.ComePacchetto();
        Assert.Equal(3, pacchetto.Flag);
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, pacchetto.Contenuto[..8]);
        Assert.Equal(fotogramma, FotogrammaVideo.DaPacchetto(pacchetto));
    }

    /// <summary>Lo stesso JSON che produce il pacchetto Swift (Protocollo/Tests).</summary>
    [Fact]
    public void CiaoComeNelDocumento()
    {
        const string swift = """{"nome":"iPhone di Ledion","piattaforma":"iphone","tipo":"ciao","versione":1,"versioneApp":"0.1"}""";
        var csharp = Encoding.UTF8.GetString(CodificaMessaggi.Codifica(new Ciao(1, "iPhone di Ledion", Piattaforma.Iphone, "0.1")));
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(swift), JsonNode.Parse(csharp)), csharp);
        Assert.Equal(new Ciao(1, "iPhone di Ledion", Piattaforma.Iphone, "0.1"), CodificaMessaggi.Decodifica(Encoding.UTF8.GetBytes(swift)));
    }

    [Fact]
    public void ComandoManualeComeNelDocumento()
    {
        const string swift = """{"iso":400,"tempo":50,"tipo":"comando"}""";
        var csharp = Encoding.UTF8.GetString(CodificaMessaggi.Codifica(new Comando(Iso: 400, Tempo: 50)));
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(swift), JsonNode.Parse(csharp)), csharp);
        Assert.Equal(new Comando(Iso: 400, Tempo: 50), CodificaMessaggi.Decodifica(Encoding.UTF8.GetBytes(swift)));
    }

    [Fact]
    public void CapacitaComeNelDocumento()
    {
        const string swift = """{"isoMassimo":3264,"isoMinimo":34,"obiettivi":["principale","frontale"],"tipo":"capacita","torcia":true,"zoomMassimo":5}""";
        var attese = new Capacita(["principale", "frontale"], 5, true, IsoMinimo: 34, IsoMassimo: 3264);
        var csharp = Encoding.UTF8.GetString(CodificaMessaggi.Codifica(attese));
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(swift), JsonNode.Parse(csharp)), csharp);
        Assert.Equal(attese, CodificaMessaggi.Decodifica(Encoding.UTF8.GetBytes(swift)));
    }

    [Fact]
    public void ValoriEnumeratiComeNelDocumento()
    {
        var json = Encoding.UTF8.GetString(CodificaMessaggi.Codifica(new StatoTelefono(78, false, Temperatura.MoltoCalda, "principale")));
        Assert.Contains("\"temperatura\":\"molto-calda\"", json);
        Assert.Contains("\"inCarica\":false", json);
        var formato = Encoding.UTF8.GetString(CodificaMessaggi.Codifica(new FormatoVideo(Codec.H264, 1920, 1080, 30)));
        Assert.Contains("\"codec\":\"h264\"", formato);
    }

    [Fact]
    public void AndataERitorno()
    {
        Messaggio[] messaggi =
        [
            new Benvenuto(1, "PC-STUDIO", Piattaforma.Windows),
            new FormatoVideo(Codec.Hevc, 3840, 2160, 30),
            new StatoTelefono(-1, true, Temperatura.Normale, "frontale"),
            new Ping(123),
            new Pong(123, 456),
            new Latenza(38),
            new Capacita(["grandangolo", "principale"], 10, true, 32, 3072),
            new Comando(Iso: 400, Tempo: 60),
            new Comando("tele", 1.5, false, -0.5, 0, "continuo"),
            new InOnda(true, "Zoom"),
            new InOnda(false),
            new Comando(Regolazioni: new Regolazioni(Nitidezza: -1), Scritta: Scritta.Nessuna),
            new StatoTelefono(40, false, Temperatura.Normale, "frontale", Filtri.BiancoNero, new Regolazioni(0, 0, 0, 0),
                ModiSfondo.Sostituito, 1, 0.5, true, false, new Scritta("Ledion"), true, false, true,
                MotiviPausa.FacciaInGiu, new StatoGobbo(false, 1), Specchia: false, Zoom: 2, Torcia: true,
                Esposizione: 0.5, Bianco: 4300, Iso: 400, Tempo: 60),
            new Comando(Specchia: false),
            new Capacita(["principale"], 5, true, Specchia: true),
            new Capacita(["principale"], 2, false, Filtri: Filtri.Tutti, Pelle: true, Inquadratura: true, LuceVolto: true,
                Scritta: true, Postura: true, Gobbo: true, Formati: [new FormatoSupportato(1280, 720, 60)]),
            new Anteprima(true),
            new Gobbo(Attivo: false),
            new Gobbo(Velocita: 3, Dimensione: DimensioniGobbo.Grande, Posizione: 0),
            FormatoAudio.AAC48kMono(),
            new Arrivederci(),
        ];
        foreach (var messaggio in messaggi)
        {
            Assert.Equal(messaggio, CodificaMessaggi.DaPacchetto(CodificaMessaggi.ComePacchetto(messaggio)));
        }
    }

    /// <summary>Lo stesso JSON del test Swift «testComandoComeNelDocumento»: i campi assenti non compaiono.</summary>
    [Fact]
    public void ComandoComeNelDocumento()
    {
        const string swift = """{"bianco":4300,"esposizione":0.3,"tipo":"comando"}""";
        var csharp = Encoding.UTF8.GetString(CodificaMessaggi.Codifica(new Comando(Esposizione: 0.3, Bianco: 4300)));
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(swift), JsonNode.Parse(csharp)), csharp);
        Assert.Equal(new Comando(Esposizione: 0.3, Bianco: 4300), CodificaMessaggi.Decodifica(Encoding.UTF8.GetBytes(swift)));
    }

    /// <summary>Codifica uguale (come JSON) al testo di Swift e Kotlin, e lettura che ridà il messaggio.</summary>
    private static void ComeSwift(string swift, Messaggio messaggio)
    {
        var csharp = Encoding.UTF8.GetString(CodificaMessaggi.Codifica(messaggio));
        Assert.True(JsonNode.DeepEquals(JsonNode.Parse(swift), JsonNode.Parse(csharp)), csharp);
        Assert.Equal(messaggio, CodificaMessaggi.Decodifica(Encoding.UTF8.GetBytes(swift)));
    }

    /// <summary>Lo stesso JSON di «testComandoEffettiComeNelDocumento» (Swift) e «comandoEffettiComeNelDocumento» (Kotlin).</summary>
    [Fact]
    public void ComandoEffettiComeNelDocumento()
    {
        const string swift = """{"audio":true,"doppiaVista":false,"filtro":"cinema","inquadratura":true,"intensitaSfondo":0.5,"luceVolto":true,"pelle":0.25,"postura":true,"regolazioni":{"contrasto":-0.5,"luminosita":0.25,"nitidezza":0,"saturazione":0.75},"scritta":{"nome":"Ledion","ruolo":"Sviluppatore"},"sfondo":"sfocato","tipo":"comando"}""";
        ComeSwift(swift, new Comando(Filtro: Filtri.Cinema,
            Regolazioni: new Regolazioni(Luminosita: 0.25, Contrasto: -0.5, Saturazione: 0.75, Nitidezza: 0),
            Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.5, Pelle: 0.25, Inquadratura: true, LuceVolto: true,
            Scritta: new Scritta("Ledion", "Sviluppatore"), DoppiaVista: false, Postura: true, Audio: true));
    }

    [Fact]
    public void GobboComeNelDocumento()
    {
        const string swift = """{"attivo":true,"dimensione":"media","testo":"Buongiorno a tutti.\nOggi parliamo del progetto.","tipo":"gobbo","velocita":1.5}""";
        ComeSwift(swift, new Gobbo("Buongiorno a tutti.\nOggi parliamo del progetto.", 1.5, true, DimensioniGobbo.Media));
    }

    [Fact]
    public void StatoConEffettiComeNelDocumento()
    {
        const string swift = """{"batteria":80,"filtro":"naturale","gobbo":{"attivo":true,"posizione":0.25},"inCarica":true,"obiettivo":"principale","pausa":"nessuna-app","temperatura":"normale","tipo":"stato"}""";
        ComeSwift(swift, new StatoTelefono(80, true, Temperatura.Normale, "principale", Filtro: Filtri.Naturale,
            Pausa: MotiviPausa.NessunaApp, Gobbo: new StatoGobbo(true, 0.25)));
    }

    [Fact]
    public void CapacitaEffettiComeNelDocumento()
    {
        const string swift = """{"audio":true,"doppiaVista":false,"filtri":["naturale","cinema"],"formati":[{"altezza":1080,"fpsMassimo":60,"larghezza":1920},{"altezza":2160,"fpsMassimo":30,"larghezza":3840}],"obiettivi":["principale"],"sfondo":true,"tipo":"capacita","torcia":true,"zoomMassimo":5}""";
        ComeSwift(swift, new Capacita(["principale"], 5, true, Filtri: [Filtri.Naturale, Filtri.Cinema], Sfondo: true,
            DoppiaVista: false, Audio: true, Formati: [new FormatoSupportato(1920, 1080, 60), new FormatoSupportato(3840, 2160, 30)]));
    }

    /// <summary>Lo stesso JSON di «testSpecchioComeNelDocumento» (Swift) e «specchioComeNelDocumento» (Kotlin).</summary>
    [Fact]
    public void SpecchioComeNelDocumento()
    {
        ComeSwift("""{"specchia":true,"tipo":"comando"}""", new Comando(Specchia: true));
        ComeSwift("""{"batteria":80,"bianco":0,"esposizione":-0.5,"inCarica":true,"iso":0,"obiettivo":"frontale","specchia":true,"tempo":0,"temperatura":"normale","tipo":"stato","torcia":false,"zoom":1.5}""",
            new StatoTelefono(80, true, Temperatura.Normale, "frontale", Specchia: true, Zoom: 1.5, Torcia: false,
                Esposizione: -0.5, Bianco: 0, Iso: 0, Tempo: 0));
        ComeSwift("""{"obiettivi":["frontale"],"specchia":true,"tipo":"capacita","torcia":false,"zoomMassimo":5}""",
            new Capacita(["frontale"], 5, false, Specchia: true));
    }

    [Fact]
    public void AnteprimaEFormatoAudioComeNelDocumento()
    {
        ComeSwift("""{"tipo":"anteprima","visibile":false}""", new Anteprima(false));
        ComeSwift("""{"canali":1,"codec":"aac-lc","configurazione":"EYg=","frequenza":48000,"tipo":"formato-audio"}""",
            FormatoAudio.AAC48kMono());
    }

    /// <summary>I telefoni vecchi mandano stato senza i campi nuovi; i valori futuri e i campi sconosciuti non sono errori.</summary>
    [Fact]
    public void MessaggiVecchiSenzaCampiNuovi()
    {
        Assert.Equal(new StatoTelefono(50, false, Temperatura.Calda, "tele"),
            CodificaMessaggi.Decodifica("""{"tipo":"stato","batteria":50,"inCarica":false,"temperatura":"calda","obiettivo":"tele"}"""u8));
        Assert.Equal(new Comando(Filtro: "futuro"),
            CodificaMessaggi.Decodifica("""{"tipo":"comando","filtro":"futuro","nuovo":{"a":1}}"""u8));
    }

    [Fact]
    public void PacchettoAudioInquadrato()
    {
        var audio = new PacchettoAudio(0x0102030405060708, [0x21, 0x10, 0x04]);
        var pacchetto = audio.ComePacchetto();
        Assert.Equal(TipoPacchetto.Audio, pacchetto.Tipo);
        Assert.Equal(0, pacchetto.Flag);
        Assert.Equal(new byte[] { 3, 0, 0, 0, 0, 11, 1, 2, 3, 4, 5, 6, 7, 8, 0x21, 0x10, 0x04 }, pacchetto.Codificato());
        Assert.Equal(audio, PacchettoAudio.DaPacchetto(pacchetto));

        var lettore = new LettorePacchetti();
        lettore.Aggiungi(pacchetto.Codificato());
        Assert.Equal(audio, PacchettoAudio.DaPacchetto(lettore.Prossimo()!));
        Assert.Throws<ErroreProtocollo>(() => PacchettoAudio.DaPacchetto(new Pacchetto(TipoPacchetto.Audio, 0, [1, 2, 3])));
        Assert.Throws<ErroreProtocollo>(() => PacchettoAudio.DaPacchetto(new Pacchetto(TipoPacchetto.Video, 0, pacchetto.Contenuto)));
        Assert.Equal(new byte[] { 0x11, 0x88 }, FormatoAudio.ConfigurazioneAAC48kMono.ToArray());
    }

    [Fact]
    public void TipoDiMessaggioSconosciutoSiIgnora()
    {
        Assert.Equal(new Sconosciuto("futuro"), CodificaMessaggi.Decodifica("""{"tipo":"futuro","x":1}"""u8));
    }
}

public class AssociazioneTest
{
    /// <summary>Lo stesso testo che produce il pacchetto Swift (Protocollo/Tests, AssociazioneTests).</summary>
    [Fact]
    public void QRComeNelDocumento()
    {
        var associazione = new Associazione(["192.168.1.20", "10.0.0.5"], 52740, "MacBook Air");
        Assert.Equal("webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=MacBook%20Air&v=2", associazione.Testo);
        Assert.Equal(associazione, Associazione.Leggi(associazione.Testo));
    }

    [Fact]
    public void QRSicuroComeNelDocumento()
    {
        var associazione = new Associazione(["192.168.1.20"], 52740, "MacBook Air", 2, "837DWUtYbfrElEqZA-g3UQ", "q_1-Zx");
        Assert.Equal("webcamlr://collega?h=192.168.1.20&p=52740&n=MacBook%20Air&v=2&k=837DWUtYbfrElEqZA-g3UQ&g=q_1-Zx",
            associazione.Testo);
        Assert.Equal(associazione, Associazione.Leggi(associazione.Testo));
        Assert.Null(Associazione.Leggi("webcamlr://collega?h=1.2.3.4&v=1")!.Impronta);
    }

    [Fact]
    public void NomeConCaratteriSpeciali()
    {
        var associazione = new Associazione(["192.168.1.20"], 52740, "Studio & Casa+1");
        Assert.Equal("webcamlr://collega?h=192.168.1.20&p=52740&n=Studio%20%26%20Casa%2B1&v=2", associazione.Testo);
        Assert.Equal("Studio & Casa+1", Associazione.Leggi(associazione.Testo)?.Nome);
    }

    [Fact]
    public void AltriQRSiIgnorano()
    {
        Assert.Null(Associazione.Leggi("https://example.com"));
        Assert.Null(Associazione.Leggi("webcamlr://collega?p=52740"));
    }
}
