using System.Buffers.Binary;
using System.Text;

namespace WebcamLR.Ricevitore;

/// <summary>Quanto di un MP4 frammentato si legge per intero: fin dove, quanti frammenti, quanto dura.</summary>
/// <param name="Fine">Il byte dopo l'ultimo frammento completo (o dopo moov, se non ce n'è nessuno); 0 se manca anche moov.</param>
public sealed record ParteLeggibile(long Fine, int Frammenti, TimeSpan Durata);

/// <summary>
/// Legge un MP4 frammentato rimasto a metà (windows.md 1.4): la registrazione con gli effetti, scritta da Media Foundation,
/// dopo un errore del disco si taglia all'ultimo frammento completo e si dice quanto dura. Guarda solo le scatole in
/// cima al file e, dentro moov e moof, quelle che servono per i tempi (mdhd, trex, tfhd, tfdt, trun) di una traccia
/// video sola. Non si fida delle dimensioni: una scatola che va oltre la fine del file conta come tagliata.
/// </summary>
public static class FrammentiMp4
{
    /// <summary>Legge il flusso dall'inizio (posizione e contenuto non cambiano).</summary>
    public static ParteLeggibile Leggi(Stream flusso)
    {
        var lunghezza = flusso.Length;
        long posizione = 0, fineLeggibile = 0;
        uint scala = 0, durataPredefinita = 0;
        var frammenti = 0;
        long fineTempi = 0;
        (long Durata, bool Valida)? moofInAttesa = null;
        Span<byte> intestazione = stackalloc byte[16];
        while (posizione + 8 <= lunghezza)
        {
            flusso.Position = posizione;
            if (!LeggiTutto(flusso, intestazione[..8])) break;
            long dimensione = BinaryPrimitives.ReadUInt32BigEndian(intestazione);
            var tipo = Encoding.ASCII.GetString(intestazione.Slice(4, 4));
            var testa = 8;
            if (dimensione == 1)
            {
                if (!LeggiTutto(flusso, intestazione.Slice(8, 8))) break;
                dimensione = (long)BinaryPrimitives.ReadUInt64BigEndian(intestazione[8..]);
                testa = 16;
            }
            else if (dimensione == 0)
            {
                dimensione = lunghezza - posizione;
            }
            if (dimensione < testa || posizione + dimensione > lunghezza) break;
            switch (tipo)
            {
                case "moov":
                    var moov = Contenuto(flusso, posizione + testa, dimensione - testa);
                    (scala, durataPredefinita) = TempiDelMoov(moov);
                    fineLeggibile = posizione + dimensione;
                    break;
                case "moof":
                    moofInAttesa = scala == 0 ? (0, false) : DurataDelMoof(Contenuto(flusso, posizione + testa, dimensione - testa), durataPredefinita);
                    break;
                case "mdat":
                    if (moofInAttesa is { } moof)
                    {
                        frammenti++;
                        fineLeggibile = posizione + dimensione;
                        if (moof.Valida) fineTempi = Math.Max(fineTempi, moof.Durata);
                    }
                    moofInAttesa = null;
                    break;
            }
            posizione += dimensione;
        }
        var durata = scala == 0 ? TimeSpan.Zero : TimeSpan.FromSeconds((double)fineTempi / scala);
        return new ParteLeggibile(fineLeggibile, frammenti, durata);
    }

    private static bool LeggiTutto(Stream flusso, Span<byte> dove)
    {
        var letti = 0;
        while (letti < dove.Length)
        {
            var n = flusso.Read(dove[letti..]);
            if (n == 0) return false;
            letti += n;
        }
        return true;
    }

    private static byte[] Contenuto(Stream flusso, long da, long quanti)
    {
        // moov e moof sono piccoli; un valore assurdo non deve allocare gigabyte.
        if (quanti > 64 << 20) return [];
        var dati = new byte[quanti];
        flusso.Position = da;
        return LeggiTutto(flusso, dati) ? dati : [];
    }

    /// <summary>Le scatole figlie in [da, a): tipo, inizio del contenuto, fine.</summary>
    private static IEnumerable<(string Tipo, int Contenuto, int Fine)> Figli(byte[] dati, int da, int a)
    {
        var p = da;
        while (p + 8 <= a)
        {
            long dimensione = BinaryPrimitives.ReadUInt32BigEndian(dati.AsSpan(p));
            var tipo = Encoding.ASCII.GetString(dati, p + 4, 4);
            var testa = 8;
            if (dimensione == 1)
            {
                if (p + 16 > a) yield break;
                dimensione = (long)BinaryPrimitives.ReadUInt64BigEndian(dati.AsSpan(p + 8));
                testa = 16;
            }
            if (dimensione < testa || p + dimensione > a) yield break;
            yield return (tipo, p + testa, (int)(p + dimensione));
            p += (int)dimensione;
        }
    }

    private static (int Contenuto, int Fine)? Trova(byte[] dati, int da, int a, params string[] percorso)
    {
        (int, int)? attuale = (da, a);
        foreach (var tipo in percorso)
        {
            var (inizio, fine) = attuale.Value;
            attuale = null;
            foreach (var figlio in Figli(dati, inizio, fine))
            {
                if (figlio.Tipo != tipo) continue;
                attuale = (figlio.Contenuto, figlio.Fine);
                break;
            }
            if (attuale is null) return null;
        }
        return attuale;
    }

    /// <summary>La scala dei tempi della traccia (mdhd) e la durata predefinita dei campioni (trex).</summary>
    private static (uint Scala, uint DurataPredefinita) TempiDelMoov(byte[] moov)
    {
        uint scala = 0, durata = 0;
        if (Trova(moov, 0, moov.Length, "trak", "mdia", "mdhd") is (int mdhd, int fineMdhd) && fineMdhd - mdhd >= 24)
            scala = BinaryPrimitives.ReadUInt32BigEndian(moov.AsSpan(mdhd + (moov[mdhd] == 1 ? 20 : 12)));
        if (Trova(moov, 0, moov.Length, "mvex", "trex") is (int trex, int fineTrex) && fineTrex - trex >= 24)
            durata = BinaryPrimitives.ReadUInt32BigEndian(moov.AsSpan(trex + 12));
        return (scala, durata);
    }

    /// <summary>Dove finisce il frammento nella linea del tempo: base_media_decode_time più le durate dei campioni.</summary>
    private static (long Durata, bool Valida) DurataDelMoof(byte[] moof, uint durataTrex)
    {
        if (Trova(moof, 0, moof.Length, "traf") is not (int traf, int fineTraf)) return (0, false);
        long inizio = 0;
        var predefinita = durataTrex;
        long somma = 0;
        var trovatoTrun = false;
        foreach (var (tipo, c, fine) in Figli(moof, traf, fineTraf))
        {
            if (fine - c < 4) continue;
            var versione = moof[c];
            var flag = BinaryPrimitives.ReadUInt32BigEndian(moof.AsSpan(c)) & 0xFFFFFF;
            switch (tipo)
            {
                case "tfhd":
                {
                    var p = c + 8; // versione e flag, track_ID
                    if ((flag & 0x01) != 0) p += 8;
                    if ((flag & 0x02) != 0) p += 4;
                    if ((flag & 0x08) != 0 && p + 4 <= fine) predefinita = BinaryPrimitives.ReadUInt32BigEndian(moof.AsSpan(p));
                    break;
                }
                case "tfdt":
                    inizio = versione == 1 && fine - c >= 12
                        ? (long)BinaryPrimitives.ReadUInt64BigEndian(moof.AsSpan(c + 4))
                        : BinaryPrimitives.ReadUInt32BigEndian(moof.AsSpan(c + 4));
                    break;
                case "trun":
                {
                    if (fine - c < 8) break;
                    trovatoTrun = true;
                    var quanti = BinaryPrimitives.ReadUInt32BigEndian(moof.AsSpan(c + 4));
                    var p = c + 8;
                    if ((flag & 0x001) != 0) p += 4;
                    if ((flag & 0x004) != 0) p += 4;
                    var passo = 0;
                    foreach (var bit in new uint[] { 0x100, 0x200, 0x400, 0x800 }) if ((flag & bit) != 0) passo += 4;
                    for (var i = 0; i < quanti; i++)
                    {
                        if ((flag & 0x100) != 0)
                        {
                            if (p + 4 > fine) return (0, false);
                            somma += BinaryPrimitives.ReadUInt32BigEndian(moof.AsSpan(p));
                        }
                        else
                        {
                            somma += predefinita;
                        }
                        p += passo;
                    }
                    break;
                }
            }
        }
        return (inizio + somma, trovatoTrun);
    }
}
