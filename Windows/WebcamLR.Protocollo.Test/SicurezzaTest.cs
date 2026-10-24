using System.Security.Cryptography;
using System.Text;
using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Protocollo.Test;

/// <summary>Collegamento sicuro (versione 2): Documenti/Protocollo.md, «Collegamento sicuro».</summary>
public class SicurezzaTest
{
    private static (SessioneSicura Telefono, SessioneSicura Computer, Prova Prova) StrettaCompleta(
        IdentitaDispositivo idTelefono, IdentitaDispositivo idComputer, string? gettone = null)
    {
        using var telefono = new StrettaTelefono(idTelefono);
        using var computer = new StrettaComputer(idComputer);
        // Come in rete: i messaggi passano per il JSON.
        var apertura = (Stretta)CodificaMessaggi.Decodifica(CodificaMessaggi.Codifica(telefono.Apertura));
        var (risposta, sessioneComputer) = computer.Rispondi(apertura);
        var rispostaInRete = (Stretta)CodificaMessaggi.Decodifica(CodificaMessaggi.Codifica(risposta));
        var (sessioneTelefono, prova) = telefono.Completa(rispostaInRete, gettone);
        return (sessioneTelefono, sessioneComputer, prova);
    }

    [Fact]
    public void StrettaDiManoECanaleNelleDueDirezioni()
    {
        using var idTelefono = IdentitaDispositivo.Nuova();
        using var idComputer = IdentitaDispositivo.Nuova();
        var (telefono, computer, prova) = StrettaCompleta(idTelefono, idComputer, "gettone");

        Assert.Equal(idComputer.Impronta, telefono.ImprontaAltro);
        Assert.Equal(idTelefono.Impronta, computer.ImprontaAltro);
        Assert.Equal(telefono.Codice, computer.Codice);
        Assert.Matches("^[0-9]{4}$", telefono.Codice);
        Assert.True(StrettaComputer.ProvaValida(prova, computer));
        Assert.Equal("gettone", prova.Gettone);

        // Telefono → computer: video e controllo, nell'ordine.
        var video = new FotogrammaVideo(123, true, true, [0, 0, 0, 1, 0x65, 1, 2, 3]).ComePacchetto();
        var ciao = CodificaMessaggi.ComePacchetto(new Ciao(2, "iPhone di Ledion", Piattaforma.Iphone, "0.10"));
        var videoCifrato = telefono.Canale.Cifra(video);
        var ciaoCifrato = telefono.Canale.Cifra(ciao);
        Assert.Equal(video.Flag | CanaleCifrato.FlagCifrato, videoCifrato.Flag);
        Assert.Equal(video.Contenuto.Length + 16, videoCifrato.Contenuto.Length);
        Assert.DoesNotContain(Encoding.UTF8.GetString(ciaoCifrato.Contenuto), "Ledion");
        Assert.Equal(video, computer.Canale.Decifra(videoCifrato));
        Assert.Equal(ciao, computer.Canale.Decifra(ciaoCifrato));

        // Computer → telefono.
        var ping = CodificaMessaggi.ComePacchetto(new Ping(42));
        Assert.Equal(ping, telefono.Canale.Decifra(computer.Canale.Cifra(ping)));
    }

    [Fact]
    public void PacchettoAlteratoRipetutoOInChiaroChiudeLaConnessione()
    {
        using var idTelefono = IdentitaDispositivo.Nuova();
        using var idComputer = IdentitaDispositivo.Nuova();
        var (telefono, computer, _) = StrettaCompleta(idTelefono, idComputer);
        var ping = CodificaMessaggi.ComePacchetto(new Ping(1));

        var primo = computer.Canale.Cifra(ping);
        var alterato = primo with { Contenuto = (byte[])primo.Contenuto.Clone() };
        alterato.Contenuto[0] ^= 1;
        Assert.Throws<ErroreProtocollo>(() => telefono.Canale.Decifra(alterato));

        Assert.Equal(ping, telefono.Canale.Decifra(primo));
        // Lo stesso pacchetto una seconda volta: il contatore è già avanti.
        Assert.Throws<ErroreProtocollo>(() => telefono.Canale.Decifra(primo));
        Assert.Throws<ErroreProtocollo>(() => telefono.Canale.Decifra(ping));

        // Tipo cambiato nell'intestazione: i dati associati non tornano.
        var secondo = computer.Canale.Cifra(ping);
        Assert.Throws<ErroreProtocollo>(() => telefono.Canale.Decifra(secondo with { Tipo = TipoPacchetto.Video }));
    }

    [Fact]
    public void ComputerFalsoNonPassa()
    {
        using var idTelefono = IdentitaDispositivo.Nuova();
        using var idComputer = IdentitaDispositivo.Nuova();
        using var intruso = IdentitaDispositivo.Nuova();
        using var telefono = new StrettaTelefono(idTelefono);
        using var computer = new StrettaComputer(intruso);
        var (risposta, _) = computer.Rispondi(telefono.Apertura);

        // L'intruso dichiara l'identità del computer vero ma non sa firmare con la sua chiave.
        var falsa = risposta with { Identita = Convert.ToBase64String(idComputer.Pubblica) };
        Assert.Throws<ErroreProtocollo>(() => telefono.Completa(falsa));
        // Senza firma.
        Assert.Throws<ErroreProtocollo>(() => telefono.Completa(risposta with { Firma = null }));
    }

    [Fact]
    public void ProvaDiUnAltroTelefonoNonPassa()
    {
        using var idTelefono = IdentitaDispositivo.Nuova();
        using var idComputer = IdentitaDispositivo.Nuova();
        var (_, computer, _) = StrettaCompleta(idTelefono, idComputer);
        var (_, _, provaAltraSessione) = StrettaCompleta(idTelefono, idComputer);
        Assert.False(StrettaComputer.ProvaValida(provaAltraSessione, computer));
        Assert.False(StrettaComputer.ProvaValida(new Prova("non-base64!"), computer));
    }

    [Fact]
    public void IdentitaSalvataERicaricata()
    {
        using var originale = IdentitaDispositivo.Nuova();
        using var ricaricata = IdentitaDispositivo.DaPkcs8(originale.EsportaPkcs8());
        Assert.Equal(originale.Pubblica, ricaricata.Pubblica);
        Assert.Equal(22, originale.Impronta.Length);
        Assert.True(Sicurezza.VerificaFirma(originale.Pubblica, [1, 2, 3], ricaricata.Firma([1, 2, 3])));
    }

    [Fact]
    public void MessaggiDellaStrettaComeNelDocumento()
    {
        const string swift = """{"chiave":"AQ==","firma":"Ag==","identita":"Aw==","tipo":"stretta","versione":2}""";
        var attesa = new Stretta(2, "AQ==", "Aw==", "Ag==");
        Assert.Equal(attesa, CodificaMessaggi.Decodifica(Encoding.UTF8.GetBytes(swift)));
        Assert.Equal(new Approvazione("0042"),
            CodificaMessaggi.Decodifica(CodificaMessaggi.Codifica(new Approvazione("0042"))));
        Assert.DoesNotContain("gettone", Encoding.UTF8.GetString(CodificaMessaggi.Codifica(new Prova("AQ=="))));
    }

    /// <summary>
    /// Valori di riferimento: gli stessi numeri sono in Protocollo/Tests (SicurezzaTests.swift).
    /// Se cambiano qui, Swift e C# non si capirebbero più.
    /// </summary>
    [Fact]
    public void ValoriDiRiferimentoUgualiInSwift()
    {
        var chiaveTelefono = Riempi(0x04, 0x11);
        var identitaTelefono = Riempi(0x04, 0x22);
        var chiaveComputer = Riempi(0x04, 0x33);
        var identitaComputer = Riempi(0x04, 0x44);
        var trascrizione = Sicurezza.Trascrizione(chiaveTelefono, identitaTelefono, chiaveComputer, identitaComputer);
        var (telefonoComputer, computerTelefono) = Sicurezza.ChiaviSessione(Enumerable.Repeat((byte)0x55, 32).ToArray(), trascrizione);

        using var aes = new AesGcm(telefonoComputer, 16);
        var testo = Encoding.UTF8.GetBytes("WebcamLR");
        var cifrato = new byte[testo.Length];
        var etichetta = new byte[16];
        aes.Encrypt(CanaleCifrato.Nonce(7), testo, cifrato, etichetta, new byte[] { 1, 0x80 });

        Assert.Equal(Riferimento.Trascrizione, Convert.ToHexString(trascrizione));
        Assert.Equal(Riferimento.Codice, Sicurezza.Codice(trascrizione));
        Assert.Equal(Riferimento.TelefonoComputer, Convert.ToHexString(telefonoComputer));
        Assert.Equal(Riferimento.ComputerTelefono, Convert.ToHexString(computerTelefono));
        Assert.Equal(Riferimento.Cifrato, Convert.ToHexString([.. cifrato, .. etichetta]));
        Assert.Equal(Riferimento.Impronta, Sicurezza.Impronta(identitaComputer));
    }

    private static byte[] Riempi(byte primo, byte resto) => [primo, .. Enumerable.Repeat(resto, 64)];

    private static class Riferimento
    {
        public const string Trascrizione = "B14EE9D3F111558B44FEDEC6A6ADAAFFF75D268D60C2C0B9FB26F7E1879CB76E";
        public const string Codice = "4696";
        public const string TelefonoComputer = "2644007CCCF250E04349A82D07209ECF5613AA1C6E8B1CE4E9175731094EEB51";
        public const string ComputerTelefono = "D7A232B410AC8E6B2F46810DD8B950DD9E45ABAE9A1F053F16D1ED103EE83BAE";
        public const string Cifrato = "3FD81BED90DA56B2F53C604C8EA349FE5998F721DB3D0E80";
        public const string Impronta = "837DWUtYbfrElEqZA-g3UQ";
    }
}
