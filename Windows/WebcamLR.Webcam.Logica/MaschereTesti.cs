using System.IO.Compression;
using System.Text;

namespace WebcamLR.Webcam;

/// <summary>Un testo già disegnato: opacità da 0 a 255, una riga dopo l'altra dall'alto.</summary>
public sealed record Maschera(int Larghezza, int Altezza, byte[] Opacita);

/// <summary>
/// I testi della schermata di attesa disegnati con Barlow Condensed e Barlow da Strumenti/genera_testi_attesa.py
/// (Risorse/TestiAttesa.bin, dentro la DLL), per un'immagine alta <see cref="AltezzaRiferimento"/>. Letti una volta.
/// </summary>
public static class MaschereTesti
{
    public const string NomeRisorsa = "WebcamLR.Webcam.TestiAttesa.bin";

    private static readonly Lazy<(int Altezza, Dictionary<string, Maschera> Maschere)> Dati = new(Leggi, LazyThreadSafetyMode.ExecutionAndPublication);

    /// <summary>L'altezza dell'immagine per cui sono disegnate (2160).</summary>
    public static int AltezzaRiferimento => Dati.Value.Altezza;

    public static IReadOnlyCollection<string> Chiavi => Dati.Value.Maschere.Keys;

    /// <summary>La maschera del testo, alla misura di riferimento; null se manca (allora la webcam non scrive quel testo).</summary>
    public static Maschera? Trova(string chiave) => Dati.Value.Maschere.TryGetValue(chiave, out var m) ? m : null;

    /// <summary>Mai un'eccezione: dentro Frame Server o Zoom una risorsa rovinata vuol dire solo niente testi.</summary>
    private static (int, Dictionary<string, Maschera>) Leggi()
    {
        try { return LeggiRisorsa(); }
        catch (Exception) { return (2160, new Dictionary<string, Maschera>(StringComparer.Ordinal)); }
    }

    private static (int, Dictionary<string, Maschera>) LeggiRisorsa()
    {
        var maschere = new Dictionary<string, Maschera>(StringComparer.Ordinal);
        using var risorsa = typeof(MaschereTesti).Assembly.GetManifestResourceStream(NomeRisorsa);
        if (risorsa is null) return (2160, maschere);
        using var zlib = new ZLibStream(risorsa, CompressionMode.Decompress);
        using var lettore = new BinaryReader(zlib, Encoding.UTF8);
        if (Encoding.ASCII.GetString(lettore.ReadBytes(4)) != "WLRT") return (2160, maschere);
        var versione = lettore.ReadUInt16();
        var altezza = lettore.ReadUInt16();
        var numero = lettore.ReadUInt16();
        if (versione != 1 || altezza == 0) return (2160, maschere);
        for (var i = 0; i < numero; i++)
        {
            var chiave = Encoding.UTF8.GetString(lettore.ReadBytes(lettore.ReadByte()));
            int l = lettore.ReadUInt16(), a = lettore.ReadUInt16();
            var opacita = lettore.ReadBytes(l * a);
            if (opacita.Length != l * a) break;
            maschere[chiave] = new Maschera(l, a, opacita);
        }
        return (altezza, maschere);
    }
}
