using System.Buffers.Binary;
using System.IO.Compression;
using ZXing;
using ZXing.Common;

namespace WebcamLR.Collaudo;

/// <summary>
/// Legge il QR code di WebcamLR da una schermata (PNG o BMP, come le salva Collaudo.psm1) con ZXing.Net (Apache 2.0),
/// senza System.Drawing: così funziona anche su Linux. Il PNG si decodifica qui (8 bit, non interlacciato), il BMP è
/// quello a 24 o 32 bit.
/// </summary>
public static class LettoreQr
{
    public static string? Leggi(string percorso)
    {
        var (larghezza, altezza, rgb) = Carica(File.ReadAllBytes(percorso));
        var sorgente = new RGBLuminanceSource(rgb, larghezza, altezza, RGBLuminanceSource.BitmapFormat.RGB24);
        var lettore = new BarcodeReaderGeneric
        {
            AutoRotate = false,
            Options = new DecodingOptions { PossibleFormats = [BarcodeFormat.QR_CODE], TryHarder = true },
        };
        var risultato = lettore.Decode(sorgente);
        if (risultato is null)
        {
            // Lo schermo scuro attorno al QR può confondere la soglia: si riprova con i colori invertiti.
            lettore.Options.TryInverted = true;
            risultato = lettore.Decode(sorgente);
        }
        return risultato?.Text;
    }

    private static (int, int, byte[]) Carica(byte[] file)
    {
        if (file.Length > 8 && file[0] == 0x89 && file[1] == (byte)'P') return Png(file);
        if (file.Length > 54 && file[0] == (byte)'B' && file[1] == (byte)'M') return Bmp(file);
        throw new InvalidDataException("Immagine non riconosciuta: servono PNG o BMP");
    }

    private static (int, int, byte[]) Bmp(byte[] file)
    {
        var inizio = BinaryPrimitives.ReadInt32LittleEndian(file.AsSpan(10));
        var larghezza = BinaryPrimitives.ReadInt32LittleEndian(file.AsSpan(18));
        var altezzaFirmata = BinaryPrimitives.ReadInt32LittleEndian(file.AsSpan(22));
        var bit = BinaryPrimitives.ReadInt16LittleEndian(file.AsSpan(28));
        if (bit != 24 && bit != 32) throw new InvalidDataException($"BMP a {bit} bit: servono 24 o 32");
        var altezza = Math.Abs(altezzaFirmata);
        var perPixel = bit / 8;
        var passo = (larghezza * perPixel + 3) / 4 * 4;
        var rgb = new byte[larghezza * altezza * 3];
        for (var r = 0; r < altezza; r++)
        {
            var rigaFile = altezzaFirmata > 0 ? altezza - 1 - r : r;
            for (var c = 0; c < larghezza; c++)
            {
                var o = inizio + rigaFile * passo + c * perPixel;
                var d = (r * larghezza + c) * 3;
                rgb[d] = file[o + 2];
                rgb[d + 1] = file[o + 1];
                rgb[d + 2] = file[o];
            }
        }
        return (larghezza, altezza, rgb);
    }

    private static (int, int, byte[]) Png(byte[] file)
    {
        int larghezza = 0, altezza = 0, tipoColore = 0, profondita = 8;
        byte[] tavolozza = [];
        var compressi = new MemoryStream();
        var posizione = 8;
        while (posizione + 8 <= file.Length)
        {
            var lunghezza = BinaryPrimitives.ReadInt32BigEndian(file.AsSpan(posizione));
            var tipo = System.Text.Encoding.ASCII.GetString(file, posizione + 4, 4);
            var dati = file.AsSpan(posizione + 8, lunghezza);
            if (tipo == "IHDR")
            {
                larghezza = BinaryPrimitives.ReadInt32BigEndian(dati);
                altezza = BinaryPrimitives.ReadInt32BigEndian(dati[4..]);
                profondita = dati[8];
                tipoColore = dati[9];
                if (profondita > 8 || (profondita < 8 && tipoColore is not (0 or 3)))
                    throw new InvalidDataException($"PNG a {profondita} bit con tipo di colore {tipoColore} non gestito");
                if (dati[12] != 0) throw new InvalidDataException("PNG interlacciato non gestito");
            }
            else if (tipo == "PLTE") tavolozza = dati.ToArray();
            else if (tipo == "IDAT") compressi.Write(dati);
            else if (tipo == "IEND") break;
            posizione += 12 + lunghezza;
        }
        var canali = tipoColore switch
        {
            0 or 3 => 1, 2 => 3, 4 => 2, 6 => 4,
            _ => throw new InvalidDataException($"PNG con tipo di colore {tipoColore} non gestito"),
        };
        compressi.Position = 0;
        using var zlib = new ZLibStream(compressi, CompressionMode.Decompress);
        var grezzi = new MemoryStream();
        zlib.CopyTo(grezzi);
        var dati2 = grezzi.ToArray();
        var passo = (larghezza * canali * profondita + 7) / 8;
        var perPixel = Math.Max(1, canali * profondita / 8);
        var righe = new byte[altezza * passo];
        var precedente = new byte[passo];
        for (var r = 0; r < altezza; r++)
        {
            var filtro = dati2[r * (passo + 1)];
            var riga = righe.AsSpan(r * passo, passo);
            dati2.AsSpan(r * (passo + 1) + 1, passo).CopyTo(riga);
            for (var i = 0; i < passo; i++)
            {
                int a = i >= perPixel ? riga[i - perPixel] : 0, b = precedente[i], c = i >= perPixel ? precedente[i - perPixel] : 0;
                riga[i] = filtro switch
                {
                    0 => riga[i],
                    1 => (byte)(riga[i] + a),
                    2 => (byte)(riga[i] + b),
                    3 => (byte)(riga[i] + (a + b) / 2),
                    4 => (byte)(riga[i] + Paeth(a, b, c)),
                    _ => throw new InvalidDataException($"PNG: filtro {filtro}"),
                };
            }
            riga.CopyTo(precedente);
        }
        var rgb = new byte[larghezza * altezza * 3];
        var massimo = (1 << profondita) - 1;
        for (var r = 0; r < altezza; r++)
        for (var x = 0; x < larghezza; x++)
        {
            var d = (r * larghezza + x) * 3;
            if (profondita < 8)
            {
                var bit = x * profondita;
                var valore = righe[r * passo + bit / 8] >> (8 - profondita - bit % 8) & massimo;
                for (var k = 0; k < 3; k++)
                    rgb[d + k] = tipoColore == 3 ? tavolozza[valore * 3 + k] : (byte)(valore * 255 / massimo);
                continue;
            }
            var o = r * passo + x * canali;
            for (var k = 0; k < 3; k++)
                rgb[d + k] = tipoColore == 3 ? tavolozza[righe[o] * 3 + k] : righe[o + (canali < 3 ? 0 : k)];
        }
        return (larghezza, altezza, rgb);
    }

    private static int Paeth(int a, int b, int c)
    {
        var p = a + b - c;
        int pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
        return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
    }
}
