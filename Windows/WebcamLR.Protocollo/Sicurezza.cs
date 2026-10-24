using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace WebcamLR.Protocollo;

/// <summary>
/// Collegamento sicuro, versione 2 del protocollo (Documenti/Protocollo.md, «Collegamento sicuro»).
/// Solo crittografia di .NET: ECDSA e ECDH P-256, HKDF-SHA256, AES-256-GCM.
/// </summary>
public static class Sicurezza
{
    public const int VersioneSicura = 2;
    public const int LunghezzaChiavePubblica = 65;
    public const int LunghezzaFirma = 64;

    private static readonly byte[] EtichettaTrascrizione = Encoding.UTF8.GetBytes("WebcamLR v2");
    private static readonly byte[] EtichettaCodice = Encoding.UTF8.GetBytes("WebcamLR codice");
    private static readonly byte[] InfoTelefonoComputer = Encoding.UTF8.GetBytes("WebcamLR v2 telefono-computer");
    private static readonly byte[] InfoComputerTelefono = Encoding.UTF8.GetBytes("WebcamLR v2 computer-telefono");

    /// <summary>I primi 16 byte di SHA-256 della chiave pubblica, in base64url senza «=».</summary>
    public static string Impronta(byte[] chiavePubblica) => Base64Url(SHA256.HashData(chiavePubblica).AsSpan(0, 16));

    /// <summary>16 byte casuali per il QR code: chi li rimanda ha visto lo schermo del computer.</summary>
    public static string NuovoGettone() => Base64Url(RandomNumberGenerator.GetBytes(16));

    /// <summary>T = SHA-256("WebcamLR v2" ‖ chiave telefono ‖ identità telefono ‖ chiave computer ‖ identità computer).</summary>
    public static byte[] Trascrizione(byte[] chiaveTelefono, byte[] identitaTelefono, byte[] chiaveComputer, byte[] identitaComputer)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        hash.AppendData(EtichettaTrascrizione);
        hash.AppendData(chiaveTelefono);
        hash.AppendData(identitaTelefono);
        hash.AppendData(chiaveComputer);
        hash.AppendData(identitaComputer);
        return hash.GetHashAndReset();
    }

    /// <summary>Le 4 cifre da confrontare sui due schermi alla prima volta.</summary>
    public static string Codice(byte[] trascrizione)
    {
        var impronta = SHA256.HashData([.. EtichettaCodice, .. trascrizione]);
        return (BinaryPrimitives.ReadUInt32BigEndian(impronta) % 10000).ToString("D4");
    }

    /// <summary>Le due chiavi AES della sessione, una per direzione.</summary>
    public static (byte[] TelefonoComputer, byte[] ComputerTelefono) ChiaviSessione(byte[] segreto, byte[] trascrizione) => (
        HKDF.DeriveKey(HashAlgorithmName.SHA256, segreto, 32, trascrizione, InfoTelefonoComputer),
        HKDF.DeriveKey(HashAlgorithmName.SHA256, segreto, 32, trascrizione, InfoComputerTelefono));

    /// <summary>Verifica una firma ECDSA P-256 / SHA-256 in formato r ‖ s; falso anche se la chiave non è valida.</summary>
    public static bool VerificaFirma(byte[] chiavePubblica, byte[] dati, byte[] firma)
    {
        if (firma.Length != LunghezzaFirma || !ChiaveValida(chiavePubblica)) return false;
        try
        {
            using var chiave = ECDsa.Create(ParametriPubblici(chiavePubblica));
            return chiave.VerifyData(dati, firma, HashAlgorithmName.SHA256);
        }
        catch (CryptographicException)
        {
            return false;
        }
    }

    internal static bool ChiaveValida(byte[] chiavePubblica) =>
        chiavePubblica.Length == LunghezzaChiavePubblica && chiavePubblica[0] == 0x04;

    internal static ECParameters ParametriPubblici(byte[] chiavePubblica) => new()
    {
        Curve = ECCurve.NamedCurves.nistP256,
        Q = new ECPoint { X = chiavePubblica[1..33], Y = chiavePubblica[33..65] },
    };

    /// <summary>X9.63 non compresso: 04 ‖ X ‖ Y.</summary>
    internal static byte[] DaParametri(ECParameters parametri) => [0x04, .. parametri.Q.X!, .. parametri.Q.Y!];

    public static string Base64Url(ReadOnlySpan<byte> dati) =>
        Convert.ToBase64String(dati).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    internal static byte[] DaBase64(string testo, int lunghezza)
    {
        try
        {
            var dati = Convert.FromBase64String(testo);
            return dati.Length == lunghezza ? dati : throw new ErroreProtocollo("Lunghezza non valida nella stretta di mano");
        }
        catch (FormatException)
        {
            throw new ErroreProtocollo("Base64 non valido nella stretta di mano");
        }
    }
}

/// <summary>La coppia di chiavi di firma permanente di un dispositivo.</summary>
public sealed class IdentitaDispositivo : IDisposable
{
    private readonly ECDsa chiave;

    private IdentitaDispositivo(ECDsa chiave)
    {
        this.chiave = chiave;
        Pubblica = Sicurezza.DaParametri(chiave.ExportParameters(false));
    }

    public static IdentitaDispositivo Nuova() => new(ECDsa.Create(ECCurve.NamedCurves.nistP256));

    /// <summary>Da una chiave salvata con <see cref="EsportaPkcs8"/>.</summary>
    public static IdentitaDispositivo DaPkcs8(byte[] dati)
    {
        var chiave = ECDsa.Create();
        chiave.ImportPkcs8PrivateKey(dati, out _);
        return new IdentitaDispositivo(chiave);
    }

    public byte[] EsportaPkcs8() => chiave.ExportPkcs8PrivateKey();

    /// <summary>Chiave pubblica, 65 byte X9.63.</summary>
    public byte[] Pubblica { get; }

    public string Impronta => Sicurezza.Impronta(Pubblica);

    /// <summary>Firma ECDSA SHA-256, formato r ‖ s di 64 byte (il predefinito di .NET).</summary>
    public byte[] Firma(byte[] dati) => chiave.SignData(dati, HashAlgorithmName.SHA256);

    public void Dispose() => chiave.Dispose();
}

/// <summary>Chiave ECDH P-256 per una sola connessione.</summary>
public sealed class ChiaveEffimera : IDisposable
{
    private readonly ECDiffieHellman chiave = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);

    public ChiaveEffimera()
    {
        Pubblica = Sicurezza.DaParametri(chiave.ExportParameters(false));
    }

    public byte[] Pubblica { get; }

    /// <summary>La coordinata x del punto condiviso, 32 byte, come CryptoKit.</summary>
    public byte[] Segreto(byte[] altraPubblica)
    {
        if (!Sicurezza.ChiaveValida(altraPubblica)) throw new ErroreProtocollo("Chiave effimera non valida");
        try
        {
            using var altra = ECDiffieHellman.Create(Sicurezza.ParametriPubblici(altraPubblica));
            return chiave.DeriveRawSecretAgreement(altra.PublicKey);
        }
        catch (CryptographicException)
        {
            throw new ErroreProtocollo("Chiave effimera non valida");
        }
    }

    public void Dispose() => chiave.Dispose();
}

/// <summary>
/// Cifra e decifra i pacchetti dopo la stretta di mano: AES-256-GCM, un contatore per direzione.
/// Chi usa <see cref="Cifra"/> deve scrivere i pacchetti nello stesso ordine in cui li cifra.
/// </summary>
public sealed class CanaleCifrato : IDisposable
{
    public const byte FlagCifrato = 0x80;
    public const int LunghezzaEtichetta = 16;

    private readonly AesGcm invio;
    private readonly AesGcm ricezione;
    private readonly object bloccoInvio = new();
    private ulong contatoreInvio;
    private ulong contatoreRicezione;

    public CanaleCifrato(byte[] chiaveInvio, byte[] chiaveRicezione)
    {
        invio = new AesGcm(chiaveInvio, LunghezzaEtichetta);
        ricezione = new AesGcm(chiaveRicezione, LunghezzaEtichetta);
    }

    public Pacchetto Cifra(Pacchetto chiaro)
    {
        var flag = (byte)(chiaro.Flag | FlagCifrato);
        var contenuto = new byte[chiaro.Contenuto.Length + LunghezzaEtichetta];
        lock (bloccoInvio)
        {
            invio.Encrypt(Nonce(contatoreInvio), chiaro.Contenuto,
                contenuto.AsSpan(0, chiaro.Contenuto.Length), contenuto.AsSpan(chiaro.Contenuto.Length),
                [(byte)chiaro.Tipo, flag]);
            contatoreInvio++;
        }
        return new Pacchetto(chiaro.Tipo, flag, contenuto);
    }

    /// <summary>Un pacchetto ripetuto, mancante o alterato è un errore: la connessione va chiusa.</summary>
    public Pacchetto Decifra(Pacchetto cifrato)
    {
        if ((cifrato.Flag & FlagCifrato) == 0) throw new ErroreProtocollo("Pacchetto in chiaro dopo la stretta di mano");
        if (cifrato.Contenuto.Length < LunghezzaEtichetta) throw new ErroreProtocollo("Pacchetto cifrato troppo corto");
        var lunghezza = cifrato.Contenuto.Length - LunghezzaEtichetta;
        var chiaro = new byte[lunghezza];
        try
        {
            ricezione.Decrypt(Nonce(contatoreRicezione), cifrato.Contenuto.AsSpan(0, lunghezza),
                cifrato.Contenuto.AsSpan(lunghezza), chiaro, [(byte)cifrato.Tipo, cifrato.Flag]);
        }
        catch (CryptographicException)
        {
            throw new ErroreProtocollo("Pacchetto cifrato non valido");
        }
        contatoreRicezione++;
        return new Pacchetto(cifrato.Tipo, (byte)(cifrato.Flag & ~FlagCifrato), chiaro);
    }

    /// <summary>4 byte a zero ‖ contatore a 64 bit big-endian.</summary>
    public static byte[] Nonce(ulong contatore)
    {
        var nonce = new byte[12];
        BinaryPrimitives.WriteUInt64BigEndian(nonce.AsSpan(4), contatore);
        return nonce;
    }

    public void Dispose()
    {
        invio.Dispose();
        ricezione.Dispose();
    }
}

/// <summary>Cosa resta della stretta di mano: il canale e chi c'è dall'altra parte.</summary>
/// <param name="IdentitaAltro">La chiave pubblica di firma dell'altro dispositivo.</param>
/// <param name="Codice">Le 4 cifre da confrontare alla prima volta.</param>
public sealed record SessioneSicura(CanaleCifrato Canale, byte[] IdentitaAltro, byte[] Trascrizione, string Codice)
{
    public string ImprontaAltro => Sicurezza.Impronta(IdentitaAltro);
}

/// <summary>La stretta di mano dal lato del telefono (anche il telefono simulato dei test).</summary>
public sealed class StrettaTelefono(IdentitaDispositivo identita) : IDisposable
{
    private readonly ChiaveEffimera effimera = new();

    public Stretta Apertura => new(Sicurezza.VersioneSicura, Convert.ToBase64String(effimera.Pubblica),
        Convert.ToBase64String(identita.Pubblica));

    /// <summary>Verifica la risposta del computer; poi va mandata la <see cref="Prova"/>, già cifrata.</summary>
    public (SessioneSicura Sessione, Prova Prova) Completa(Stretta risposta, string? gettone = null)
    {
        if (risposta.Versione != Sicurezza.VersioneSicura || risposta.Firma is null)
            throw new ErroreProtocollo("Stretta di mano del computer non valida");
        var chiaveComputer = Sicurezza.DaBase64(risposta.Chiave, Sicurezza.LunghezzaChiavePubblica);
        var identitaComputer = Sicurezza.DaBase64(risposta.Identita, Sicurezza.LunghezzaChiavePubblica);
        var firma = Sicurezza.DaBase64(risposta.Firma, Sicurezza.LunghezzaFirma);

        var trascrizione = Sicurezza.Trascrizione(effimera.Pubblica, identita.Pubblica, chiaveComputer, identitaComputer);
        if (!Sicurezza.VerificaFirma(identitaComputer, trascrizione, firma))
            throw new ErroreProtocollo("La firma del computer non è valida");

        var (telefonoComputer, computerTelefono) = Sicurezza.ChiaviSessione(effimera.Segreto(chiaveComputer), trascrizione);
        var sessione = new SessioneSicura(new CanaleCifrato(telefonoComputer, computerTelefono), identitaComputer,
            trascrizione, Sicurezza.Codice(trascrizione));
        return (sessione, new Prova(Convert.ToBase64String(identita.Firma(trascrizione)), gettone));
    }

    public void Dispose() => effimera.Dispose();
}

/// <summary>La stretta di mano dal lato del computer.</summary>
public sealed class StrettaComputer(IdentitaDispositivo identita) : IDisposable
{
    private readonly ChiaveEffimera effimera = new();

    public (Stretta Risposta, SessioneSicura Sessione) Rispondi(Stretta apertura)
    {
        if (apertura.Versione != Sicurezza.VersioneSicura) throw new ErroreProtocollo("Versione del protocollo diversa");
        var chiaveTelefono = Sicurezza.DaBase64(apertura.Chiave, Sicurezza.LunghezzaChiavePubblica);
        var identitaTelefono = Sicurezza.DaBase64(apertura.Identita, Sicurezza.LunghezzaChiavePubblica);
        if (!Sicurezza.ChiaveValida(identitaTelefono)) throw new ErroreProtocollo("Identità del telefono non valida");

        var trascrizione = Sicurezza.Trascrizione(chiaveTelefono, identitaTelefono, effimera.Pubblica, identita.Pubblica);
        var (telefonoComputer, computerTelefono) = Sicurezza.ChiaviSessione(effimera.Segreto(chiaveTelefono), trascrizione);
        var risposta = new Stretta(Sicurezza.VersioneSicura, Convert.ToBase64String(effimera.Pubblica),
            Convert.ToBase64String(identita.Pubblica), Convert.ToBase64String(identita.Firma(trascrizione)));
        return (risposta, new SessioneSicura(new CanaleCifrato(computerTelefono, telefonoComputer), identitaTelefono,
            trascrizione, Sicurezza.Codice(trascrizione)));
    }

    /// <summary>Il telefono possiede davvero la chiave che ha dichiarato.</summary>
    public static bool ProvaValida(Prova prova, SessioneSicura sessione)
    {
        try
        {
            return Sicurezza.VerificaFirma(sessione.IdentitaAltro, sessione.Trascrizione,
                Sicurezza.DaBase64(prova.Firma, Sicurezza.LunghezzaFirma));
        }
        catch (ErroreProtocollo)
        {
            return false;
        }
    }

    public void Dispose() => effimera.Dispose();
}
