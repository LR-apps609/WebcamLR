using System.IO.Compression;
using System.Text;

namespace WebcamLR.Effetti.Test;

/// <summary>Lettura e scrittura di immagini semplici (PPM, PGM) per i test, senza librerie.</summary>
internal static class Immagini
{
    public static string Dati(string nome) => Path.Combine(AppContext.BaseDirectory, "Dati", nome);

    /// <summary>Un PPM binario (P6, 8 bit), anche compresso .gz, in BGRA.</summary>
    public static (byte[] Bgra, int Larghezza, int Altezza) LeggiPpm(string percorso)
    {
        using var file = File.OpenRead(percorso);
        using Stream flusso = percorso.EndsWith(".gz") ? new GZipStream(file, CompressionMode.Decompress) : file;
        using var memoria = new MemoryStream();
        flusso.CopyTo(memoria);
        var dati = memoria.ToArray();
        var pos = 0;
        string Parola()
        {
            while (char.IsWhiteSpace((char)dati[pos])) pos++;
            var inizio = pos;
            while (!char.IsWhiteSpace((char)dati[pos])) pos++;
            return Encoding.ASCII.GetString(dati, inizio, pos - inizio);
        }
        if (Parola() != "P6") throw new InvalidDataException("Non è un PPM P6");
        var l = int.Parse(Parola());
        var a = int.Parse(Parola());
        if (Parola() != "255") throw new InvalidDataException("Solo 8 bit");
        pos++;
        var bgra = new byte[l * a * 4];
        for (int i = 0, j = pos; i < bgra.Length; i += 4, j += 3)
        {
            bgra[i] = dati[j + 2];
            bgra[i + 1] = dati[j + 1];
            bgra[i + 2] = dati[j];
            bgra[i + 3] = 255;
        }
        return (bgra, l, a);
    }

    /// <summary>Scrive una maschera come PGM (P5), per guardarla.</summary>
    public static void ScriviPgm(string percorso, MascheraPersona m)
    {
        using var f = File.Create(percorso);
        f.Write(Encoding.ASCII.GetBytes($"P5\n{m.Larghezza} {m.Altezza}\n255\n"));
        f.Write(m.Valori);
    }
}
