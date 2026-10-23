using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace WebcamLR.Protocollo;

public enum Piattaforma { Iphone, Android, Mac, Windows }

public enum Codec { H264, Hevc }

/// <summary>Gli stessi livelli dello stato termico di iOS.</summary>
public enum Temperatura { Normale, Calda, MoltoCalda, Critica }

/// <summary>Un messaggio di controllo: JSON con il campo "tipo" più i campi del messaggio.</summary>
public abstract record Messaggio;

public sealed record Ciao(int Versione, string Nome, Piattaforma Piattaforma, string VersioneApp) : Messaggio;

public sealed record Benvenuto(int Versione, string Nome, Piattaforma Piattaforma) : Messaggio;

public sealed record FormatoVideo(Codec Codec, int Larghezza, int Altezza, int Fps) : Messaggio;

/// <param name="Batteria">Da 0 a 100, oppure -1 se non nota.</param>
public sealed record StatoTelefono(int Batteria, bool InCarica, Temperatura Temperatura, string Obiettivo) : Messaggio;

/// <param name="T">Orologio del computer, in microsecondi.</param>
public sealed record Ping(ulong T) : Messaggio;

/// <param name="T">Copiato dal ping.</param>
/// <param name="Telefono">Orologio del telefono, in microsecondi.</param>
public sealed record Pong(ulong T, ulong Telefono) : Messaggio;

/// <param name="Ms">Latenza misurata dal computer, in millisecondi.</param>
public sealed record Latenza(int Ms) : Messaggio;

/// <summary>Cosa il computer può comandare su questo telefono.</summary>
public sealed record Capacita(IReadOnlyList<string> Obiettivi, double ZoomMassimo, bool Torcia,
    double? IsoMinimo = null, double? IsoMassimo = null) : Messaggio
{
    public bool Equals(Capacita? altra) =>
        altra is not null && Obiettivi.SequenceEqual(altra.Obiettivi) && ZoomMassimo == altra.ZoomMassimo && Torcia == altra.Torcia
        && IsoMinimo == altra.IsoMinimo && IsoMassimo == altra.IsoMassimo;

    public override int GetHashCode() => HashCode.Combine(Obiettivi.Count, ZoomMassimo, Torcia);
}

/// <summary>Comandi della fotocamera dal computer: si applicano solo i campi presenti.</summary>
/// <param name="Esposizione">Compensazione in stop, da -2 a +2.</param>
/// <param name="Bianco">Kelvin da 2500 a 7500; 0 = automatico.</param>
/// <param name="Fuoco">Per ora solo "continuo".</param>
/// <param name="Iso">ISO manuale; 0 = automatico.</param>
/// <param name="Tempo">Tempo di posa come denominatore (60 = 1/60 s); 0 = automatico.</param>
public sealed record Comando(string? Obiettivo = null, double? Zoom = null, bool? Torcia = null,
    double? Esposizione = null, int? Bianco = null, string? Fuoco = null, double? Iso = null, int? Tempo = null) : Messaggio;

/// <summary>Un'app sta usando davvero la webcam virtuale: l'unico caso in cui si mostra il rosso.</summary>
public sealed record InOnda(bool Attivo, string? App = null) : Messaggio;

public sealed record Arrivederci : Messaggio;

/// <summary>Un tipo che questa versione non conosce: si ignora.</summary>
public sealed record Sconosciuto(string Tipo) : Messaggio;

public static class CodificaMessaggi
{
    private static readonly JsonSerializerOptions Opzioni = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.KebabCaseLower) },
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
        Arrivederci => "arrivederci",
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
            "arrivederci" => new Arrivederci(),
            _ => new Sconosciuto(tipo),
        };
    }

    public static Pacchetto ComePacchetto(Messaggio messaggio) =>
        new(TipoPacchetto.Controllo, 0, Codifica(messaggio));

    public static Messaggio DaPacchetto(Pacchetto pacchetto) =>
        pacchetto.Tipo == TipoPacchetto.Controllo
            ? Decodifica(pacchetto.Contenuto)
            : throw new ErroreProtocollo("Non è un pacchetto di controllo");
}
