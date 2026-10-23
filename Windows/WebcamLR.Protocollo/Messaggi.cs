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

public sealed record Arrivederci : Messaggio;

/// <summary>Un tipo che questa versione non conosce: si ignora.</summary>
public sealed record Sconosciuto(string Tipo) : Messaggio;

public static class CodificaMessaggi
{
    private static readonly JsonSerializerOptions Opzioni = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.KebabCaseLower) },
    };

    public static string Tipo(Messaggio messaggio) => messaggio switch
    {
        Ciao => "ciao",
        Benvenuto => "benvenuto",
        FormatoVideo => "formato",
        StatoTelefono => "stato",
        Ping => "ping",
        Pong => "pong",
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
