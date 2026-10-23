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
            new Capacita(["grandangolo", "principale"], 10, true),
            new Comando("tele", 1.5, false, -0.5, 0, "continuo"),
            new InOnda(true, "Zoom"),
            new InOnda(false),
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
        Assert.Equal("webcamlr://collega?h=192.168.1.20,10.0.0.5&p=52740&n=MacBook%20Air&v=1", associazione.Testo);
        Assert.Equal(associazione, Associazione.Leggi(associazione.Testo));
    }

    [Fact]
    public void NomeConCaratteriSpeciali()
    {
        var associazione = new Associazione(["192.168.1.20"], 52740, "Studio & Casa+1");
        Assert.Equal("webcamlr://collega?h=192.168.1.20&p=52740&n=Studio%20%26%20Casa%2B1&v=1", associazione.Testo);
        Assert.Equal("Studio & Casa+1", Associazione.Leggi(associazione.Testo)?.Nome);
    }

    [Fact]
    public void AltriQRSiIgnorano()
    {
        Assert.Null(Associazione.Leggi("https://example.com"));
        Assert.Null(Associazione.Leggi("webcamlr://collega?p=52740"));
    }
}
