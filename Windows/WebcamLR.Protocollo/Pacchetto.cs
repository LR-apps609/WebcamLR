using System.Buffers.Binary;
using System.Security.Cryptography;

namespace WebcamLR.Protocollo;

public enum TipoPacchetto : byte
{
    Controllo = 1,
    Video = 2,
    Audio = 3,
    /// <summary>Dal computer al telefono, solo se Capacita.Immagini (vedi <see cref="PacchettoImmagine"/>).</summary>
    Immagine = 4,
}

public sealed class ErroreProtocollo(string messaggio) : Exception(messaggio);

/// <summary>Un pacchetto: 6 byte di intestazione (tipo, flag, lunghezza big-endian) e il contenuto.</summary>
public sealed record Pacchetto(TipoPacchetto Tipo, byte Flag, byte[] Contenuto)
{
    public const int LunghezzaIntestazione = 6;
    public const int LunghezzaMassima = 16 * 1024 * 1024;

    public byte[] Codificato()
    {
        var dati = new byte[LunghezzaIntestazione + Contenuto.Length];
        dati[0] = (byte)Tipo;
        dati[1] = Flag;
        BinaryPrimitives.WriteUInt32BigEndian(dati.AsSpan(2, 4), (uint)Contenuto.Length);
        Contenuto.CopyTo(dati, LunghezzaIntestazione);
        return dati;
    }

    public bool Equals(Pacchetto? altro) =>
        altro is not null && Tipo == altro.Tipo && Flag == altro.Flag && Contenuto.AsSpan().SequenceEqual(altro.Contenuto);

    public override int GetHashCode() => HashCode.Combine(Tipo, Flag, Contenuto.Length);
}

/// <summary>Raccoglie i byte che arrivano dalla connessione e restituisce i pacchetti completi.</summary>
public sealed class LettorePacchetti
{
    private byte[] buffer = new byte[64 * 1024];
    private int occupati;

    public void Aggiungi(ReadOnlySpan<byte> dati)
    {
        if (occupati + dati.Length > buffer.Length)
        {
            Array.Resize(ref buffer, Math.Max(buffer.Length * 2, occupati + dati.Length));
        }
        dati.CopyTo(buffer.AsSpan(occupati));
        occupati += dati.Length;
    }

    /// <summary>Il prossimo pacchetto completo, oppure null se servono altri byte.</summary>
    public Pacchetto? Prossimo()
    {
        if (occupati < Pacchetto.LunghezzaIntestazione) return null;

        var tipo = buffer[0];
        var flag = buffer[1];
        var lunghezza = BinaryPrimitives.ReadUInt32BigEndian(buffer.AsSpan(2, 4));

        if (!Enum.IsDefined(typeof(TipoPacchetto), tipo))
            throw new ErroreProtocollo($"Tipo di pacchetto sconosciuto: {tipo}");
        if (lunghezza > Pacchetto.LunghezzaMassima)
            throw new ErroreProtocollo($"Pacchetto troppo grande: {lunghezza} byte");

        var totale = Pacchetto.LunghezzaIntestazione + (int)lunghezza;
        if (occupati < totale) return null;

        var contenuto = buffer.AsSpan(Pacchetto.LunghezzaIntestazione, (int)lunghezza).ToArray();
        buffer.AsSpan(totale, occupati - totale).CopyTo(buffer);
        occupati -= totale;
        return new Pacchetto((TipoPacchetto)tipo, flag, contenuto);
    }
}

/// <summary>Un fotogramma video compresso (Annex B) con il suo timestamp in microsecondi.</summary>
public sealed record FotogrammaVideo(ulong Timestamp, bool Chiave, bool ConParametri, byte[] Dati)
{
    public const byte FlagChiave = 1 << 0;
    public const byte FlagParametri = 1 << 1;

    public Pacchetto ComePacchetto()
    {
        var contenuto = new byte[8 + Dati.Length];
        BinaryPrimitives.WriteUInt64BigEndian(contenuto, Timestamp);
        Dati.CopyTo(contenuto, 8);
        var flag = (byte)((Chiave ? FlagChiave : 0) | (ConParametri ? FlagParametri : 0));
        return new Pacchetto(TipoPacchetto.Video, flag, contenuto);
    }

    public static FotogrammaVideo DaPacchetto(Pacchetto pacchetto)
    {
        if (pacchetto.Tipo != TipoPacchetto.Video || pacchetto.Contenuto.Length < 8)
            throw new ErroreProtocollo("Pacchetto video non valido");
        return new FotogrammaVideo(
            BinaryPrimitives.ReadUInt64BigEndian(pacchetto.Contenuto),
            (pacchetto.Flag & FlagChiave) != 0,
            (pacchetto.Flag & FlagParametri) != 0,
            pacchetto.Contenuto[8..]);
    }

    public bool Equals(FotogrammaVideo? altro) =>
        altro is not null && Timestamp == altro.Timestamp && Chiave == altro.Chiave
        && ConParametri == altro.ConParametri && Dati.AsSpan().SequenceEqual(altro.Dati);

    public override int GetHashCode() => HashCode.Combine(Timestamp, Chiave, ConParametri, Dati.Length);
}

/// <summary>
/// Un pacchetto audio AAC-LC grezzo (senza ADTS), con il timestamp del primo campione in microsecondi,
/// sullo stesso orologio del video. La configurazione viaggia nel messaggio formato-audio.
/// </summary>
public sealed record PacchettoAudio(ulong Timestamp, byte[] Dati)
{
    public Pacchetto ComePacchetto()
    {
        var contenuto = new byte[8 + Dati.Length];
        BinaryPrimitives.WriteUInt64BigEndian(contenuto, Timestamp);
        Dati.CopyTo(contenuto, 8);
        return new Pacchetto(TipoPacchetto.Audio, 0, contenuto);
    }

    public static PacchettoAudio DaPacchetto(Pacchetto pacchetto)
    {
        if (pacchetto.Tipo != TipoPacchetto.Audio || pacchetto.Contenuto.Length < 8)
            throw new ErroreProtocollo("Pacchetto audio non valido");
        return new PacchettoAudio(BinaryPrimitives.ReadUInt64BigEndian(pacchetto.Contenuto), pacchetto.Contenuto[8..]);
    }

    public bool Equals(PacchettoAudio? altro) =>
        altro is not null && Timestamp == altro.Timestamp && Dati.AsSpan().SequenceEqual(altro.Dati);

    public override int GetHashCode() => HashCode.Combine(Timestamp, Dati.Length);
}

/// <summary>A cosa serve l'immagine di un pacchetto di tipo 4.</summary>
public enum UsoImmagine : byte
{
    Sfondo = 1,
    Logo = 2,
}

/// <summary>Un'immagine dal computer al telefono (pacchetto di tipo 4): 1 byte uso seguito dai byte di un file JPEG o PNG.</summary>
public sealed record PacchettoImmagine(UsoImmagine Uso, byte[] Dati)
{
    /// <summary>Byte massimi del file (8 MiB).</summary>
    public const int DimensioneMassima = 8 * 1024 * 1024;

    public Pacchetto ComePacchetto()
    {
        var contenuto = new byte[1 + Dati.Length];
        contenuto[0] = (byte)Uso;
        Dati.CopyTo(contenuto, 1);
        return new Pacchetto(TipoPacchetto.Immagine, 0, contenuto);
    }

    /// <summary>Un uso sconosciuto, un file vuoto o più grande di 8 MiB danno <see cref="ErroreProtocollo"/>: il pacchetto si scarta.</summary>
    public static PacchettoImmagine DaPacchetto(Pacchetto pacchetto)
    {
        var contenuto = pacchetto.Contenuto;
        if (pacchetto.Tipo != TipoPacchetto.Immagine || contenuto.Length < 2 || contenuto.Length - 1 > DimensioneMassima
            || !Enum.IsDefined(typeof(UsoImmagine), contenuto[0]))
            throw new ErroreProtocollo("Pacchetto immagine non valido");
        return new PacchettoImmagine((UsoImmagine)contenuto[0], contenuto[1..]);
    }

    /// <summary>L'impronta di questo file, come in StatoTelefono.ImmaginePersonale e StatoTelefono.Logo.</summary>
    public string Impronta => ImprontaDi(Dati);

    /// <summary>I primi 16 caratteri esadecimali minuscoli dello SHA-256 dei byte del file.</summary>
    public static string ImprontaDi(ReadOnlySpan<byte> dati) =>
        Convert.ToHexString(SHA256.HashData(dati).AsSpan(0, 8)).ToLowerInvariant();

    public bool Equals(PacchettoImmagine? altro) =>
        altro is not null && Uso == altro.Uso && Dati.AsSpan().SequenceEqual(altro.Dati);

    public override int GetHashCode() => HashCode.Combine(Uso, Dati.Length);
}
