using System.Globalization;
using System.Text;
using System.Xml;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Plist XML minimo per usbmux (Documenti/Protocollo.md, «usbmux in breve»): scrive dizionari di testi e numeri,
/// legge le risposte (Result, Attached, Detached) con System.Xml, senza codice di terzi.
/// Tipi letti: dict → Dictionary, array → List, string, integer → long, real → double, true/false → bool,
/// data → byte[], date → DateTime.
/// </summary>
public static class Plist
{
    private const string Intestazione =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n";

    /// <summary>Il plist XML di un dizionario, in UTF-8. Valori ammessi: string, numeri interi, bool, dizionari.</summary>
    public static byte[] Scrivi(IReadOnlyDictionary<string, object> dizionario)
    {
        var testo = new StringBuilder(Intestazione);
        testo.Append("<plist version=\"1.0\">\n");
        ScriviValore(testo, dizionario);
        testo.Append("</plist>\n");
        return Encoding.UTF8.GetBytes(testo.ToString());
    }

    private static void ScriviValore(StringBuilder testo, object valore)
    {
        switch (valore)
        {
            case string stringa:
                testo.Append("<string>").Append(Escape(stringa)).Append("</string>\n");
                break;
            case bool vero:
                testo.Append(vero ? "<true/>\n" : "<false/>\n");
                break;
            case int or long or uint or ushort or short or byte:
                testo.Append("<integer>").Append(Convert.ToInt64(valore, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture)).Append("</integer>\n");
                break;
            case IReadOnlyDictionary<string, object> dizionario:
                testo.Append("<dict>\n");
                foreach (var (chiave, interno) in dizionario)
                {
                    testo.Append("<key>").Append(Escape(chiave)).Append("</key>\n");
                    ScriviValore(testo, interno);
                }
                testo.Append("</dict>\n");
                break;
            default:
                throw new ArgumentException($"Tipo non previsto nel plist: {valore.GetType().Name}");
        }
    }

    private static string Escape(string testo) =>
        testo.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    /// <summary>Legge un plist XML il cui elemento principale è un dizionario.</summary>
    /// <exception cref="FormatException">Se non è un plist XML con un dizionario.</exception>
    public static Dictionary<string, object> Leggi(ReadOnlySpan<byte> dati)
    {
        // Niente DTD né risorse esterne: il DOCTYPE di Apple si ignora, nessun accesso a Internet.
        var impostazioni = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Ignore,
            XmlResolver = null,
            IgnoreComments = true,
            IgnoreWhitespace = true,
        };
        var documento = new XmlDocument { XmlResolver = null };
        try
        {
            using var flusso = new MemoryStream(dati.ToArray());
            using var lettore = XmlReader.Create(flusso, impostazioni);
            documento.Load(lettore);
        }
        catch (XmlException errore)
        {
            throw new FormatException("Plist non leggibile", errore);
        }
        var radice = documento.DocumentElement;
        if (radice is not { Name: "plist" } || Elementi(radice).FirstOrDefault() is not { Name: "dict" } dizionario)
            throw new FormatException("Il plist non contiene un dizionario");
        return LeggiDizionario(dizionario);
    }

    private static IEnumerable<XmlElement> Elementi(XmlNode nodo) => nodo.ChildNodes.OfType<XmlElement>();

    private static Dictionary<string, object> LeggiDizionario(XmlElement elemento)
    {
        var risultato = new Dictionary<string, object>();
        string? chiave = null;
        foreach (var figlio in Elementi(elemento))
        {
            if (figlio.Name == "key")
            {
                chiave = figlio.InnerText;
                continue;
            }
            if (chiave is null) throw new FormatException("Valore senza chiave nel plist");
            risultato[chiave] = LeggiValore(figlio);
            chiave = null;
        }
        return risultato;
    }

    private static object LeggiValore(XmlElement elemento) => elemento.Name switch
    {
        "string" => elemento.InnerText,
        "integer" => long.TryParse(elemento.InnerText.Trim(), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var numero)
            ? numero
            : throw new FormatException($"Numero non valido: {elemento.InnerText}"),
        "real" => double.Parse(elemento.InnerText.Trim(), CultureInfo.InvariantCulture),
        "true" => true,
        "false" => false,
        "data" => Convert.FromBase64String(string.Concat(elemento.InnerText.Where(c => !char.IsWhiteSpace(c)))),
        "date" => DateTime.Parse(elemento.InnerText.Trim(), CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal),
        "dict" => LeggiDizionario(elemento),
        "array" => Elementi(elemento).Select(LeggiValore).ToList(),
        _ => throw new FormatException($"Tipo non previsto nel plist: {elemento.Name}"),
    };
}
