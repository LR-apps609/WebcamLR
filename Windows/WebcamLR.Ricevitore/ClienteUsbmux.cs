using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;

namespace WebcamLR.Ricevitore;

/// <summary>Un messaggio usbmux: l'etichetta dell'intestazione e il plist.</summary>
public sealed record MessaggioUsbmux(uint Etichetta, Dictionary<string, object> Contenuto)
{
    public const int LunghezzaIntestazione = 16;
    public const uint Versione = 1;
    public const uint TipoPlist = 8;
    /// <summary>Un messaggio più lungo di così non è usbmux: la connessione si chiude.</summary>
    public const int LunghezzaMassima = 1 << 20;

    public string? Tipo => Contenuto.GetValueOrDefault("MessageType") as string;

    /// <summary>Intestazione di 16 byte little-endian (lunghezza totale, versione 1, tipo 8, etichetta) e plist XML.</summary>
    public static byte[] Codifica(uint etichetta, IReadOnlyDictionary<string, object> contenuto)
    {
        var plist = Plist.Scrivi(contenuto);
        var messaggio = new byte[LunghezzaIntestazione + plist.Length];
        var intestazione = messaggio.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[0..], (uint)messaggio.Length);
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[4..], Versione);
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[8..], TipoPlist);
        BinaryPrimitives.WriteUInt32LittleEndian(intestazione[12..], etichetta);
        plist.CopyTo(messaggio, LunghezzaIntestazione);
        return messaggio;
    }

    /// <summary>
    /// Legge esattamente un messaggio, senza un byte di più: dopo un Connect riuscito ciò che segue
    /// è già la nostra connessione con l'iPhone. Null se la connessione si chiude prima di un messaggio intero.
    /// </summary>
    public static async Task<MessaggioUsbmux?> LeggiAsync(Stream flusso, CancellationToken annullato)
    {
        var intestazione = new byte[LunghezzaIntestazione];
        if (!await LeggiTuttoAsync(flusso, intestazione, annullato)) return null;
        var lunghezza = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(0));
        var versione = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(4));
        var tipo = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(8));
        var etichetta = BinaryPrimitives.ReadUInt32LittleEndian(intestazione.AsSpan(12));
        if (lunghezza < LunghezzaIntestazione || lunghezza > LunghezzaMassima)
            throw new FormatException($"Lunghezza usbmux non valida: {lunghezza}");
        if (versione != Versione || tipo != TipoPlist)
            throw new FormatException($"Messaggio usbmux non previsto (versione {versione}, tipo {tipo})");
        var contenuto = new byte[lunghezza - LunghezzaIntestazione];
        if (!await LeggiTuttoAsync(flusso, contenuto, annullato)) return null;
        return new MessaggioUsbmux(etichetta, Plist.Leggi(contenuto));
    }

    private static async Task<bool> LeggiTuttoAsync(Stream flusso, byte[] buffer, CancellationToken annullato)
    {
        var letti = 0;
        while (letti < buffer.Length)
        {
            var n = await flusso.ReadAsync(buffer.AsMemory(letti), annullato);
            if (n == 0) return false;
            letti += n;
        }
        return true;
    }

    /// <summary>Un numero del plist, qualunque sia il tipo con cui è stato letto.</summary>
    public long? Numero(string chiave) => Contenuto.GetValueOrDefault(chiave) switch
    {
        long numero => numero,
        double reale => (long)reale,
        string testo when long.TryParse(testo, out var numero) => numero,
        _ => null,
    };
}

/// <summary>
/// Il cavo USB dell'iPhone su Windows (aggiornamento 1.7), scritto da zero: parla con usbmux, il servizio di Apple
/// installato con l'app «Dispositivi Apple», su 127.0.0.1:27015 (Documenti/Protocollo.md, «Collegamento via cavo USB»).
/// Manda «Listen»; a ogni iPhone collegato con il cavo («Attached», ConnectionType USB) apre un'altra connessione
/// e chiede «Connect» verso la porta 52741 dell'iPhone. Con Result 0 quella connessione è un canale TCP verso
/// WebcamLR sull'iPhone: arriva con <see cref="ClienteCavo{TChiave}.TelefonoViaCavo"/> e si usa come una connessione
/// Wi-Fi. Tentativi, attese dopo un rifiuto, sospensione e pausa per scelta sono quelli di <see cref="ClienteCavo{TChiave}"/>
/// (Qualità 17: in comune con il cavo di Android, <see cref="ClienteAdb"/>).
/// </summary>
public sealed class ClienteUsbmux : ClienteCavo<long>
{
    public const int PortaServizio = 27015;
    public const string NomeProgramma = "WebcamLR";

    private readonly IPEndPoint servizio;
    private readonly TimeSpan attesaRisposta = TimeSpan.FromSeconds(5);
    private uint etichetta;

    /// <param name="servizio">Dove risponde usbmux: 127.0.0.1:27015, un'altra porta solo nei test.</param>
    /// <param name="intervalloRiprova">La base dell'attesa dopo un rifiuto: 2 secondi.</param>
    /// <param name="attesaServizio">Ogni quanto riprovare a raggiungere il servizio se manca: 5 secondi.</param>
    /// <param name="attesaMassima">Il limite dell'attesa che raddoppia quando il telefono rifiuta il cavo: 30 secondi.</param>
    /// <param name="intervalloConnect">Ogni quanto riprovare il Connect mentre l'app non risponde: 1 secondo.</param>
    public ClienteUsbmux(IPEndPoint? servizio = null, TimeSpan? intervalloRiprova = null, TimeSpan? attesaServizio = null,
        TimeSpan? attesaMassima = null, TimeSpan? intervalloConnect = null)
        : base(intervalloRiprova, attesaServizio, attesaMassima, intervalloConnect)
    {
        this.servizio = servizio ?? new IPEndPoint(IPAddress.Loopback, PortaServizio);
    }

    /// <summary>Come <see cref="ClienteCavo{TChiave}.TelefonoAlCavo"/>: un iPhone collegato con il cavo, non sospeso.</summary>
    public bool IPhoneAlCavo => TelefonoAlCavo;

    /// <summary>Il byte order di rete per PortNumber: 52741 (0xCE05) diventa 0x05CE = 1486.</summary>
    public static ushort InOrdineDiRete(ushort porta) => (ushort)((porta >> 8) | (porta << 8));

    protected override string Testo(EventoCavo evento, string? attesa = null) => evento switch
    {
        EventoCavo.ServizioTrovato => TestiRicevitore.T("Cavo_ServizioTrovato"),
        EventoCavo.ServizioFermo => TestiRicevitore.T("Cavo_ServizioFermo"),
        EventoCavo.TelefonoCollegato => TestiRicevitore.T("Cavo_IPhoneCollegato"),
        EventoCavo.TelefonoStaccato => TestiRicevitore.T("Cavo_IPhoneStaccato"),
        EventoCavo.Rifiutato => TestiRicevitore.T("Cavo_Rifiutato", attesa ?? ""),
        _ => TestiRicevitore.T("Cavo_Collegato"),
    };

    protected override async Task AscoltaServizioAsync(Action raggiunto, CancellationToken annullato)
    {
        using var presa = await ApriAsync(servizio, annullato);
        await using var flusso = new NetworkStream(presa, ownsSocket: false);
        var richiesta = ProssimaEtichetta();
        await flusso.WriteAsync(MessaggioUsbmux.Codifica(richiesta, Richiesta("Listen")), annullato);
        raggiunto();
        await AscoltaAsync(flusso, richiesta, annullato);
    }

    /// <summary>Legge gli avvisi del servizio finché la connessione resta aperta.</summary>
    private async Task AscoltaAsync(NetworkStream flusso, uint richiesta, CancellationToken annullato)
    {
        while (await MessaggioUsbmux.LeggiAsync(flusso, annullato) is { } messaggio)
        {
            switch (messaggio.Tipo)
            {
                case "Result" when messaggio.Etichetta == richiesta:
                    // Listen rifiutato: il servizio non è utilizzabile, si riprova più tardi.
                    if (messaggio.Numero("Number") != 0) return;
                    ServizioInAscolto();
                    break;
                case "Attached":
                    var proprieta = messaggio.Contenuto.GetValueOrDefault("Properties") as Dictionary<string, object>;
                    // Gli iPhone sincronizzati in Wi-Fi compaiono come «Network»: per noi conta solo il cavo.
                    if (proprieta?.GetValueOrDefault("ConnectionType") as string != "USB") break;
                    if (messaggio.Numero("DeviceID") is long collegato) Collega(collegato);
                    break;
                case "Detached":
                    if (messaggio.Numero("DeviceID") is long staccato) Stacca(staccato);
                    break;
            }
        }
    }

    /// <summary>Una connessione nuova al servizio e «Connect»: con Result 0 diventa il canale verso l'iPhone.</summary>
    protected override async Task<Socket?> ConnettiAsync(long id, CancellationToken annullato)
    {
        Socket? presa = null;
        try
        {
            presa = await ApriAsync(servizio, annullato);
            using var tempo = CancellationTokenSource.CreateLinkedTokenSource(annullato);
            tempo.CancelAfter(attesaRisposta);
            var richiesta = ProssimaEtichetta();
            var contenuto = Richiesta("Connect");
            contenuto["DeviceID"] = id;
            contenuto["PortNumber"] = (int)InOrdineDiRete(PortaTelefono);
            // Senza possedere la presa: chiudere il flusso non deve chiudere il canale verso l'iPhone.
            using var flusso = new NetworkStream(presa, ownsSocket: false);
            await flusso.WriteAsync(MessaggioUsbmux.Codifica(richiesta, contenuto), tempo.Token);
            var risposta = await MessaggioUsbmux.LeggiAsync(flusso, tempo.Token);
            if (risposta is { Tipo: "Result" } && risposta.Etichetta == richiesta && risposta.Numero("Number") == 0)
            {
                var pronta = presa;
                presa = null;
                return pronta;
            }
            return null;
        }
        catch (OperationCanceledException) when (annullato.IsCancellationRequested) { throw; }
        catch (Exception) { return null; }
        finally { presa?.Dispose(); }
    }

    private static Dictionary<string, object> Richiesta(string tipo) => new()
    {
        ["MessageType"] = tipo,
        ["ClientVersionString"] = NomeProgramma,
        ["ProgName"] = NomeProgramma,
        ["kLibUSBMuxVersion"] = 3,
    };

    private uint ProssimaEtichetta() => Interlocked.Increment(ref etichetta);
}
