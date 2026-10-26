using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace WebcamLR.Protocollo;

/// <summary>Sconosciuta: un valore che questa versione non conosce (non si manda mai).</summary>
public enum Piattaforma { Iphone, Android, Mac, Windows, Sconosciuta }

/// <summary>Un codec sconosciuto si legge come H264 (Protocollo.md, «Valori sconosciuti»).</summary>
public enum Codec { H264, Hevc }

/// <summary>Gli stessi livelli dello stato termico di iOS. Un livello sconosciuto si legge come Normale.</summary>
public enum Temperatura { Normale, Calda, MoltoCalda, Critica }

/// <summary>Un messaggio di controllo: JSON con il campo "tipo" più i campi del messaggio.</summary>
public abstract record Messaggio;

public sealed record Ciao(int Versione, string Nome, Piattaforma Piattaforma, string VersioneApp) : Messaggio;

public sealed record Benvenuto(int Versione, string Nome, Piattaforma Piattaforma) : Messaggio;

public sealed record FormatoVideo(Codec Codec, int Larghezza, int Altezza, int Fps) : Messaggio;

/// <param name="Batteria">Da 0 a 100, oppure -1 se non nota.</param>
/// <remarks>Gli effetti (facoltativi) sono quelli attuali, anche se cambiati sul telefono.</remarks>
/// <param name="Scritta">Nome vuoto = nessuna scritta.</param>
/// <param name="Audio">Il microfono sta inviando audio.</param>
/// <param name="Pausa">Perché il telefono non manda video (<see cref="MotiviPausa"/>); null = non è in pausa.</param>
/// <param name="Specchia">Il video inviato è specchiato: l'unica fonte di verità per i due lati.</param>
/// <remarks>Zoom, Torcia, Esposizione, Bianco, Iso e Tempo (facoltativi): i comandi della fotocamera attuali, come in <see cref="Comando"/>.</remarks>
/// <param name="Collegamento">La strada in uso, la preferenza e le strade disponibili (Protocollo.md, «Scelta del collegamento»).</param>
public sealed record StatoTelefono(int Batteria, bool InCarica, Temperatura Temperatura, string Obiettivo,
    string? Filtro = null, Regolazioni? Regolazioni = null, string? Sfondo = null, double? IntensitaSfondo = null,
    double? Pelle = null, bool? Inquadratura = null, bool? LuceVolto = null, Scritta? Scritta = null,
    bool? DoppiaVista = null, bool? Postura = null, bool? Audio = null, string? Pausa = null,
    StatoGobbo? Gobbo = null, bool? Specchia = null, double? Zoom = null, bool? Torcia = null,
    double? Esposizione = null, int? Bianco = null, double? Iso = null, int? Tempo = null,
    StatoCollegamento? Collegamento = null) : Messaggio;

/// <param name="T">Orologio del computer, in microsecondi.</param>
public sealed record Ping(ulong T) : Messaggio;

/// <param name="T">Copiato dal ping.</param>
/// <param name="Telefono">Orologio del telefono, in microsecondi.</param>
public sealed record Pong(ulong T, ulong Telefono) : Messaggio;

/// <param name="Ms">Latenza misurata dal computer, in millisecondi.</param>
public sealed record Latenza(int Ms) : Messaggio;

/// <summary>Cosa il computer può comandare su questo telefono.</summary>
/// <param name="Filtri">Filtri disponibili (<see cref="WebcamLR.Protocollo.Filtri"/>), nell'ordine in cui mostrarli.</param>
/// <param name="Sfondo">Sfondo sfocato o sostituito.</param>
/// <param name="DoppiaVista">Volto e scrivania con due obiettivi insieme (serve la multicamera).</param>
/// <param name="Audio">Microfono disponibile.</param>
/// <param name="Formati">Risoluzioni dell'obiettivo attuale con i fotogrammi al secondo massimi.</param>
/// <param name="Specchia">Il telefono sa specchiare il video inviato dal vivo.</param>
/// <param name="Pro">WebcamLR Pro è sbloccato su questo telefono; assente = gratis.</param>
/// <param name="SceltaCollegamento">Il telefono sa cambiare strada e accetta <see cref="Comando.Collegamento"/>.</param>
public sealed record Capacita(IReadOnlyList<string> Obiettivi, double ZoomMassimo, bool Torcia,
    double? IsoMinimo = null, double? IsoMassimo = null,
    IReadOnlyList<string>? Filtri = null, bool? Sfondo = null, bool? Pelle = null, bool? Inquadratura = null,
    bool? LuceVolto = null, bool? Scritta = null, bool? DoppiaVista = null, bool? Postura = null,
    bool? Gobbo = null, bool? Audio = null, IReadOnlyList<FormatoSupportato>? Formati = null,
    bool? Specchia = null, bool? Pro = null, bool? SceltaCollegamento = null) : Messaggio
{
    public bool Equals(Capacita? altra) =>
        altra is not null && Obiettivi.SequenceEqual(altra.Obiettivi) && ZoomMassimo == altra.ZoomMassimo && Torcia == altra.Torcia
        && IsoMinimo == altra.IsoMinimo && IsoMassimo == altra.IsoMassimo
        && Uguali(Filtri, altra.Filtri) && Sfondo == altra.Sfondo && Pelle == altra.Pelle
        && Inquadratura == altra.Inquadratura && LuceVolto == altra.LuceVolto && Scritta == altra.Scritta
        && DoppiaVista == altra.DoppiaVista && Postura == altra.Postura && Gobbo == altra.Gobbo
        && Audio == altra.Audio && Uguali(Formati, altra.Formati) && Specchia == altra.Specchia
        && Pro == altra.Pro && SceltaCollegamento == altra.SceltaCollegamento;

    private static bool Uguali<T>(IReadOnlyList<T>? a, IReadOnlyList<T>? b) =>
        a is null ? b is null : b is not null && a.SequenceEqual(b);

    public override int GetHashCode() => HashCode.Combine(Obiettivi.Count, ZoomMassimo, Torcia);
}

/// <summary>Comandi della fotocamera e degli effetti dal computer: si applicano solo i campi presenti.</summary>
/// <param name="Esposizione">Compensazione in stop, da -2 a +2.</param>
/// <param name="Bianco">Kelvin da 2500 a 7500; 0 = automatico.</param>
/// <param name="Fuoco">Per ora solo "continuo".</param>
/// <param name="Iso">ISO manuale; 0 = automatico.</param>
/// <param name="Tempo">Tempo di posa come denominatore (60 = 1/60 s); 0 = automatico.</param>
/// <param name="Filtro">Uno dei <see cref="Filtri"/>; "naturale" = nessun filtro.</param>
/// <param name="Sfondo">Uno dei <see cref="ModiSfondo"/>.</param>
/// <param name="IntensitaSfondo">Da 0 a 1.</param>
/// <param name="Pelle">Ritocco della pelle, da 0 (spento) a 1.</param>
/// <param name="Inquadratura">Inquadratura automatica che segue il volto.</param>
/// <param name="LuceVolto">Esposizione con priorità al volto.</param>
/// <param name="Scritta">Sottopancia; nome vuoto = togli la scritta.</param>
/// <param name="Postura">Promemoria della postura sul telefono.</param>
/// <param name="Audio">Microfono acceso o spento.</param>
/// <param name="Specchia">Specchia il video inviato; il telefono conferma in <see cref="StatoTelefono.Specchia"/>.</param>
/// <param name="Collegamento">La strada preferita (<see cref="PreferenzeCollegamento"/>); il telefono conferma in <see cref="StatoTelefono.Collegamento"/>.</param>
public sealed record Comando(string? Obiettivo = null, double? Zoom = null, bool? Torcia = null,
    double? Esposizione = null, int? Bianco = null, string? Fuoco = null, double? Iso = null, int? Tempo = null,
    string? Filtro = null, Regolazioni? Regolazioni = null, string? Sfondo = null, double? IntensitaSfondo = null,
    double? Pelle = null, bool? Inquadratura = null, bool? LuceVolto = null, Scritta? Scritta = null,
    bool? DoppiaVista = null, bool? Postura = null, bool? Audio = null, bool? Specchia = null,
    string? Collegamento = null) : Messaggio;

/// <summary>Un'app sta usando davvero la webcam virtuale: l'unico caso in cui si mostra il rosso.</summary>
public sealed record InOnda(bool Attivo, string? App = null) : Messaggio;

/// <summary>La finestra di anteprima del computer è visibile: qualcuno sta guardando.</summary>
public sealed record Anteprima(bool Visibile) : Messaggio;

/// <summary>Il gobbo: testo che scorre sullo schermo del telefono. Si applicano solo i campi presenti.</summary>
/// <param name="Testo">Al massimo <see cref="LunghezzaMassima"/> caratteri; il telefono taglia il resto.</param>
/// <param name="Velocita">Righe al secondo, da 0.5 a 3.</param>
/// <param name="Dimensione">Una delle <see cref="DimensioniGobbo"/>.</param>
/// <param name="Posizione">Da 0 (inizio) a 1 (fine): salta a quel punto.</param>
public sealed record Gobbo(string? Testo = null, double? Velocita = null, bool? Attivo = null,
    string? Dimensione = null, double? Posizione = null) : Messaggio
{
    public const int LunghezzaMassima = 20_000;
    public const double VelocitaMinima = 0.5;
    public const double VelocitaMassima = 3.0;
}

/// <summary>Dal telefono: com'è codificato l'audio dei pacchetti di tipo 3.</summary>
/// <param name="Codec">Per ora solo <see cref="AacLC"/>.</param>
/// <param name="Frequenza">Campioni al secondo (48000).</param>
/// <param name="Configurazione">AudioSpecificConfig (ISO 14496-3) in base64.</param>
public sealed record FormatoAudio(string Codec, int Frequenza, int Canali, string Configurazione) : Messaggio
{
    public const string AacLC = "aac-lc";

    /// <summary>Campioni in ogni pacchetto AAC-LC (21,33 ms a 48 kHz).</summary>
    public const int CampioniPerPacchetto = 1024;

    /// <summary>AudioSpecificConfig di AAC-LC, 48 kHz, mono: 0x11 0x88.</summary>
    public static ReadOnlySpan<byte> ConfigurazioneAAC48kMono => [0x11, 0x88];

    /// <summary>Il formato standard: AAC-LC, 48 kHz, mono.</summary>
    public static FormatoAudio AAC48kMono() => new(AacLC, 48_000, 1, Convert.ToBase64String(ConfigurazioneAAC48kMono));
}

public sealed record Arrivederci : Messaggio;

/// <summary>Stretta di mano del collegamento sicuro (versione 2), in chiaro: byte in base64.</summary>
/// <param name="Chiave">Chiave pubblica ECDH effimera, 65 byte.</param>
/// <param name="Identita">Chiave pubblica di firma permanente, 65 byte.</param>
/// <param name="Firma">Solo dal computer: la sua firma sulla trascrizione.</param>
public sealed record Stretta(int Versione, string Chiave, string Identita, string? Firma = null) : Messaggio;

/// <summary>Dal telefono, già cifrata: la sua firma sulla trascrizione, e il gettone se viene dal QR code.</summary>
public sealed record Prova(string Firma, string? Gettone = null) : Messaggio;

/// <summary>Dal computer: il telefono non è ancora fidato, l'utente deve confermare con questo codice.</summary>
public sealed record Approvazione(string Codice) : Messaggio;

/// <summary>Un tipo che questa versione non conosce: si ignora.</summary>
public sealed record Sconosciuto(string Tipo) : Messaggio;

/// <summary>Correzioni dell'immagine, ognuna da -1 a 1 (0 = neutra).</summary>
public sealed record Regolazioni(double? Luminosita = null, double? Contrasto = null, double? Saturazione = null,
    double? Nitidezza = null);

/// <summary>Sottopancia: nome e, se c'è, ruolo.</summary>
public sealed record Scritta(string Nome, string? Ruolo = null)
{
    /// <summary>Da mandare per togliere la scritta.</summary>
    public static Scritta Nessuna { get; } = new("");
}

/// <summary>Dove è arrivato il gobbo sul telefono.</summary>
/// <param name="Posizione">Da 0 a 1.</param>
public sealed record StatoGobbo(bool Attivo, double Posizione);

/// <summary>Una risoluzione che il telefono sa inviare, con i fotogrammi al secondo massimi.</summary>
public sealed record FormatoSupportato(int Larghezza, int Altezza, int FpsMassimo);

/// <summary>Come il telefono è collegato e come può esserlo (Protocollo.md, «Scelta del collegamento»).</summary>
/// <param name="Attivo">La strada in uso (<see cref="StradeCollegamento"/>); un nome sconosciuto si mostra come generico.</param>
/// <param name="Preferenza"><see cref="PreferenzeCollegamento"/>; una sconosciuta vale come automatico.</param>
/// <param name="Strade">Le strade disponibili ora; se manca vale come elenco vuoto.</param>
public sealed record StatoCollegamento(string Attivo, string Preferenza, IReadOnlyList<StradaCollegamento>? Strade = null)
{
    public IReadOnlyList<StradaCollegamento> Strade { get; init; } = Strade ?? [];

    /// <summary>La strada con la latenza più bassa tra quelle misurate: solo un'informazione («più veloce ora»).</summary>
    [JsonIgnore]
    public string? PiuVeloce => Strade.Where(s => s.Ms is not null).MinBy(s => s.Ms)?.Tipo;

    public bool Equals(StatoCollegamento? altro) =>
        altro is not null && Attivo == altro.Attivo && Preferenza == altro.Preferenza && Strade.SequenceEqual(altro.Strade);

    public override int GetHashCode() => HashCode.Combine(Attivo, Preferenza, Strade.Count);
}

/// <summary>Una strada per arrivare al computer, con l'ultima latenza misurata su di essa (null se mai misurata).</summary>
public sealed record StradaCollegamento(string Tipo, int? Ms = null);

/// <summary>Le strade di <see cref="StatoCollegamento.Attivo"/> e <see cref="StradaCollegamento.Tipo"/>.</summary>
public static class StradeCollegamento
{
    public const string Wifi = "wifi";
    public const string Cavo = "cavo";
    public const string Hotspot = "hotspot";
    public const string WifiDiretto = "wifiDiretto";
    public const string Rete = "rete";
}

/// <summary>Le preferenze di <see cref="Comando.Collegamento"/>. Una sconosciuta vale come automatico.</summary>
public static class PreferenzeCollegamento
{
    public const string Automatico = "automatico";
    public const string Wifi = "wifi";
    public const string Cavo = "cavo";
    public static IReadOnlyList<string> Tutte { get; } = [Automatico, Wifi, Cavo];
}

/// <summary>Filtri del telefono. Un filtro sconosciuto si tratta come "naturale".</summary>
public static class Filtri
{
    public const string Naturale = "naturale";
    public const string Caldo = "caldo";
    public const string Freddo = "freddo";
    public const string Luminoso = "luminoso";
    public const string Cinema = "cinema";
    public const string Vivido = "vivido";
    public const string Tenue = "tenue";
    public const string BiancoNero = "bianco-nero";
    public const string Seppia = "seppia";
    public const string Notte = "notte";

    public static IReadOnlyList<string> Tutti { get; } =
        [Naturale, Caldo, Freddo, Luminoso, Cinema, Vivido, Tenue, BiancoNero, Seppia, Notte];
}

public static class ModiSfondo
{
    public const string Nessuno = "nessuno";
    public const string Sfocato = "sfocato";
    public const string Sostituito = "sostituito";
}

/// <summary>Perché il telefono è in pausa. Un motivo sconosciuto si mostra come una pausa qualsiasi.</summary>
public static class MotiviPausa
{
    public const string FacciaInGiu = "faccia-in-giu";
    public const string NessunaApp = "nessuna-app";
    public const string Utente = "utente";
}

public static class DimensioniGobbo
{
    public const string Piccola = "piccola";
    public const string Media = "media";
    public const string Grande = "grande";
}

public static class CodificaMessaggi
{
    private static readonly JsonSerializerOptions Opzioni = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        // Un valore enumerato sconosciuto non fa fallire il messaggio: diventa il ripiego del documento.
        Converters =
        {
            new EnumTollerante<Piattaforma>(Piattaforma.Sconosciuta),
            new EnumTollerante<Codec>(Codec.H264),
            new EnumTollerante<Temperatura>(Temperatura.Normale),
            new JsonStringEnumConverter(JsonNamingPolicy.KebabCaseLower),
        },
        // Nei comandi i campi assenti non si scrivono: il telefono applica solo quelli presenti.
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static string Tipo(Messaggio messaggio) => messaggio switch
    {
        Ciao => "ciao",
        Benvenuto => "benvenuto",
        FormatoVideo => "formato",
        StatoTelefono => "stato",
        Ping => "ping",
        Pong => "pong",
        Latenza => "latenza",
        Capacita => "capacita",
        Comando => "comando",
        InOnda => "in-onda",
        Anteprima => "anteprima",
        Gobbo => "gobbo",
        FormatoAudio => "formato-audio",
        Arrivederci => "arrivederci",
        Stretta => "stretta",
        Prova => "prova",
        Approvazione => "approvazione",
        Sconosciuto s => s.Tipo,
        _ => throw new ArgumentException($"Messaggio non previsto: {messaggio.GetType().Name}"),
    };

    public static byte[] Codifica(Messaggio messaggio)
    {
        var oggetto = new JsonObject { ["tipo"] = Tipo(messaggio) };
        if (messaggio is not (Arrivederci or Sconosciuto))
        {
            var campi = JsonSerializer.SerializeToNode(messaggio, messaggio.GetType(), Opzioni)!.AsObject();
            foreach (var (chiave, valore) in campi.ToList())
            {
                campi.Remove(chiave);
                oggetto[chiave] = valore;
            }
        }
        return Encoding.UTF8.GetBytes(oggetto.ToJsonString());
    }

    public static Messaggio Decodifica(ReadOnlySpan<byte> json)
    {
        var nodo = JsonNode.Parse(json) as JsonObject ?? throw new ErroreProtocollo("Il messaggio non è un oggetto JSON");
        var tipo = nodo["tipo"]?.GetValue<string>() ?? throw new ErroreProtocollo("Manca il campo tipo");
        return tipo switch
        {
            "ciao" => nodo.Deserialize<Ciao>(Opzioni)!,
            "benvenuto" => nodo.Deserialize<Benvenuto>(Opzioni)!,
            "formato" => nodo.Deserialize<FormatoVideo>(Opzioni)!,
            "stato" => nodo.Deserialize<StatoTelefono>(Opzioni)!,
            "ping" => nodo.Deserialize<Ping>(Opzioni)!,
            "pong" => nodo.Deserialize<Pong>(Opzioni)!,
            "latenza" => nodo.Deserialize<Latenza>(Opzioni)!,
            "capacita" => nodo.Deserialize<Capacita>(Opzioni)!,
            "comando" => nodo.Deserialize<Comando>(Opzioni)!,
            "in-onda" => nodo.Deserialize<InOnda>(Opzioni)!,
            "anteprima" => nodo.Deserialize<Anteprima>(Opzioni)!,
            "gobbo" => nodo.Deserialize<Gobbo>(Opzioni)!,
            "formato-audio" => nodo.Deserialize<FormatoAudio>(Opzioni)!,
            "arrivederci" => new Arrivederci(),
            "stretta" => nodo.Deserialize<Stretta>(Opzioni)!,
            "prova" => nodo.Deserialize<Prova>(Opzioni)!,
            "approvazione" => nodo.Deserialize<Approvazione>(Opzioni)!,
            _ => new Sconosciuto(tipo),
        };
    }

    /// <summary>Valori enumerati in kebab-case; uno sconosciuto (o non testuale) diventa <paramref name="ripiego"/>.</summary>
    private sealed class EnumTollerante<T>(T ripiego) : JsonConverter<T> where T : struct, Enum
    {
        private static readonly Dictionary<string, T> PerNome =
            Enum.GetValues<T>().ToDictionary(v => JsonNamingPolicy.KebabCaseLower.ConvertName(v.ToString()));

        public override T Read(ref Utf8JsonReader lettore, Type tipo, JsonSerializerOptions opzioni)
        {
            if (lettore.TokenType != JsonTokenType.String)
            {
                lettore.Skip();
                return ripiego;
            }
            return PerNome.TryGetValue(lettore.GetString()!, out var valore) ? valore : ripiego;
        }

        public override void Write(Utf8JsonWriter scrittore, T valore, JsonSerializerOptions opzioni) =>
            scrittore.WriteStringValue(JsonNamingPolicy.KebabCaseLower.ConvertName(valore.ToString()));
    }

    public static Pacchetto ComePacchetto(Messaggio messaggio) =>
        new(TipoPacchetto.Controllo, 0, Codifica(messaggio));

    public static Messaggio DaPacchetto(Pacchetto pacchetto) =>
        pacchetto.Tipo == TipoPacchetto.Controllo
            ? Decodifica(pacchetto.Contenuto)
            : throw new ErroreProtocollo("Non è un pacchetto di controllo");

    /// <summary>
    /// Come <see cref="DaPacchetto"/>, ma un messaggio che non si riesce a leggere (JSON non valido, campo del tipo
    /// sbagliato) dà null invece di un errore: dopo la prova si salta solo quel messaggio (Protocollo.md, «Valori sconosciuti»).
    /// </summary>
    public static Messaggio? DaPacchettoSeLeggibile(Pacchetto pacchetto)
    {
        try
        {
            return DaPacchetto(pacchetto);
        }
        catch (Exception e) when (e is ErroreProtocollo or JsonException or InvalidOperationException or FormatException
                                      or NotSupportedException or ArgumentException)
        {
            return null;
        }
    }
}
