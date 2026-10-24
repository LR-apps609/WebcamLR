using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Le unità NAL di un fotogramma Annex B (Documenti/Protocollo.md, «Tipo 2 · video»): i codici di inizio
/// <c>00 00 01</c> o <c>00 00 00 01</c> separano le unità.
/// </summary>
public static class AnnexB
{
    /// <summary>Inizio e lunghezza di ogni unità, senza codici di inizio.</summary>
    public static List<(int Inizio, int Lunghezza)> Unita(ReadOnlySpan<byte> dati)
    {
        var unita = new List<(int, int)>();
        var inizio = -1;
        var i = 0;
        while (i + 2 < dati.Length)
        {
            if (dati[i] == 0 && dati[i + 1] == 0 && dati[i + 2] == 1)
            {
                if (inizio >= 0) Aggiungi(unita, dati, inizio, i);
                i += 3;
                inizio = i;
                continue;
            }
            i++;
        }
        if (inizio >= 0) Aggiungi(unita, dati, inizio, dati.Length);
        return unita;
    }

    private static void Aggiungi(List<(int, int)> unita, ReadOnlySpan<byte> dati, int inizio, int fine)
    {
        // Gli zeri prima del codice di inizio successivo (il primo byte di 00 00 00 01) non sono dell'unità.
        while (fine > inizio && dati[fine - 1] == 0) fine--;
        if (fine > inizio) unita.Add((inizio, fine - inizio));
    }

    /// <summary>Il tipo dell'unità: 5 bit in H.264, 6 bit in HEVC.</summary>
    public static int Tipo(Codec codec, byte primo) => codec == Codec.Hevc ? (primo >> 1) & 0x3F : primo & 0x1F;

    public const int H264Sps = 7, H264Pps = 8, H264Delimitatore = 9;
    public const int HevcVps = 32, HevcSps = 33, HevcPps = 34, HevcDelimitatore = 35;

    /// <summary>
    /// Toglie i byte di prevenzione (<c>00 00 03</c> → <c>00 00</c>) per leggere i campi di SPS e VPS.
    /// </summary>
    public static byte[] SenzaPrevenzione(ReadOnlySpan<byte> unita)
    {
        var uscita = new List<byte>(unita.Length);
        var zeri = 0;
        foreach (var b in unita)
        {
            if (zeri >= 2 && b == 3)
            {
                zeri = 0;
                continue;
            }
            uscita.Add(b);
            zeri = b == 0 ? zeri + 1 : 0;
        }
        return [.. uscita];
    }
}

/// <summary>Legge i campi a bit (u(n) e ue(v)) di un SPS senza byte di prevenzione.</summary>
public sealed class LettoreBit(byte[] dati, int primoByte = 0)
{
    private long posizione = primoByte * 8L;

    public uint Bit(int quanti)
    {
        uint valore = 0;
        for (var i = 0; i < quanti; i++)
        {
            var indice = (int)(posizione >> 3);
            if (indice >= dati.Length) throw new FormatException("Parametri del codec troncati");
            valore = (valore << 1) | (uint)((dati[indice] >> (7 - (int)(posizione & 7))) & 1);
            posizione++;
        }
        return valore;
    }

    /// <summary>Esponenziale di Golomb senza segno.</summary>
    public uint Ue()
    {
        var zeri = 0;
        while (Bit(1) == 0)
        {
            if (++zeri > 31) throw new FormatException("Parametri del codec non validi");
        }
        return zeri == 0 ? 0 : (uint)((1L << zeri) - 1 + Bit(zeri));
    }
}

/// <summary>
/// I parametri del codec (SPS e PPS, più il VPS per HEVC) presi da un fotogramma chiave, e il record di
/// configurazione che li porta nel file MP4 (<c>avcC</c> per H.264, <c>hvcC</c> per HEVC; ISO/IEC 14496-15).
/// </summary>
public sealed class ParametriVideo
{
    public Codec Codec { get; }
    public IReadOnlyList<byte[]> Vps { get; }
    public IReadOnlyList<byte[]> Sps { get; }
    public IReadOnlyList<byte[]> Pps { get; }

    private ParametriVideo(Codec codec, List<byte[]> vps, List<byte[]> sps, List<byte[]> pps)
    {
        Codec = codec;
        Vps = vps;
        Sps = sps;
        Pps = pps;
    }

    /// <summary>I parametri di un fotogramma, oppure null se mancano (o non sono di questo codec).</summary>
    public static ParametriVideo? Da(Codec codec, ReadOnlySpan<byte> dati, List<(int Inizio, int Lunghezza)> unita)
    {
        List<byte[]> vps = [], sps = [], pps = [];
        foreach (var (inizio, lunghezza) in unita)
        {
            var nal = dati.Slice(inizio, lunghezza);
            if (nal.Length < 2) continue;
            var tipo = AnnexB.Tipo(codec, nal[0]);
            if (codec == Codec.Hevc)
            {
                if (tipo == AnnexB.HevcVps) vps.Add(nal.ToArray());
                else if (tipo == AnnexB.HevcSps) sps.Add(nal.ToArray());
                else if (tipo == AnnexB.HevcPps) pps.Add(nal.ToArray());
            }
            else
            {
                if (tipo == AnnexB.H264Sps) sps.Add(nal.ToArray());
                else if (tipo == AnnexB.H264Pps) pps.Add(nal.ToArray());
            }
        }
        if (sps.Count == 0 || pps.Count == 0 || (codec == Codec.Hevc && vps.Count == 0)) return null;
        // Un SPS H.264 ha almeno profilo, vincoli e livello; uno HEVC almeno profilo e livello generali (15 byte).
        if (codec == Codec.H264 ? sps[0].Length < 4 : sps[0].Length < 15) return null;
        return new ParametriVideo(codec, vps, sps, pps);
    }

    /// <summary>Vero se sono e restano gli stessi: un SPS diverso vuol dire video diverso (misura, obiettivo, codec).</summary>
    public bool Uguali(ParametriVideo altri) =>
        Codec == altri.Codec && Stessi(Vps, altri.Vps) && Stessi(Sps, altri.Sps) && Stessi(Pps, altri.Pps);

    private static bool Stessi(IReadOnlyList<byte[]> a, IReadOnlyList<byte[]> b) =>
        a.Count == b.Count && a.Zip(b).All(c => c.First.AsSpan().SequenceEqual(c.Second));

    /// <summary>Vero se l'unità è un parametro del codec o un delimitatore: nel file stanno nel record di configurazione.</summary>
    public static bool FuoriDalCampione(Codec codec, byte primo)
    {
        var tipo = AnnexB.Tipo(codec, primo);
        return codec == Codec.Hevc
            ? tipo is AnnexB.HevcVps or AnnexB.HevcSps or AnnexB.HevcPps or AnnexB.HevcDelimitatore
            : tipo is AnnexB.H264Sps or AnnexB.H264Pps or AnnexB.H264Delimitatore;
    }

    /// <summary>Il contenuto della scatola <c>avcC</c> o <c>hvcC</c>, senza la sua intestazione.</summary>
    public byte[] RecordConfigurazione() => Codec == Codec.Hevc ? RecordHevc() : RecordH264();

    /// <summary>
    /// AVCDecoderConfigurationRecord. Per i profili High (100, 110, 122, 144) anche formato cromatico e profondità,
    /// letti dall'SPS: l'iPhone codifica in High.
    /// </summary>
    private byte[] RecordH264()
    {
        var sps = Sps[0];
        var uscita = new List<byte> { 1, sps[1], sps[2], sps[3], 0xFF, (byte)(0xE0 | Sps.Count) };
        foreach (var s in Sps) AggiungiConLunghezza(uscita, s);
        uscita.Add((byte)Pps.Count);
        foreach (var p in Pps) AggiungiConLunghezza(uscita, p);
        if (sps[1] is 100 or 110 or 122 or 144)
        {
            var (croma, profonditaLuma, profonditaCroma) = InfoH264(sps);
            uscita.Add((byte)(0xFC | croma));
            uscita.Add((byte)(0xF8 | profonditaLuma));
            uscita.Add((byte)(0xF8 | profonditaCroma));
            uscita.Add(0);
        }
        return [.. uscita];
    }

    /// <summary>Formato cromatico e profondità (meno 8) dall'SPS H.264; 4:2:0 a 8 bit se non si riesce a leggere.</summary>
    public static (int Croma, int ProfonditaLuma, int ProfonditaCroma) InfoH264(byte[] sps)
    {
        try
        {
            var bit = new LettoreBit(AnnexB.SenzaPrevenzione(sps), 4);
            bit.Ue(); // seq_parameter_set_id
            var croma = (int)bit.Ue();
            if (croma == 3) bit.Bit(1);
            var luma = (int)bit.Ue();
            var crominanza = (int)bit.Ue();
            if (croma > 3 || luma > 7 || crominanza > 7) return (1, 0, 0);
            return (croma, luma, crominanza);
        }
        catch (FormatException)
        {
            return (1, 0, 0);
        }
    }

    /// <summary>I campi dell'SPS HEVC che servono a hvcC.</summary>
    public readonly record struct InfoSpsHevc(byte[] ProfiloGenerale, int SottostratiMeno1, bool AnnidamentoTemporale,
        int Croma, int ProfonditaLuma, int ProfonditaCroma, int Larghezza, int Altezza);

    /// <summary>
    /// Legge profile_tier_level generale (12 byte: spazio, livello, profilo, 32 bit di compatibilità, 48 di vincoli,
    /// livello), i sottostrati, formato cromatico, misura e profondità (H.265, 7.3.2.2).
    /// </summary>
    public static InfoSpsHevc InfoHevc(byte[] sps)
    {
        var dati = AnnexB.SenzaPrevenzione(sps);
        var bit = new LettoreBit(dati, 2);
        bit.Bit(4); // sps_video_parameter_set_id
        var sottostrati = (int)bit.Bit(3);
        var annidamento = bit.Bit(1) == 1;
        var profilo = new byte[12];
        for (var i = 0; i < 12; i++) profilo[i] = (byte)bit.Bit(8);
        var profiloPresente = new bool[sottostrati];
        var livelloPresente = new bool[sottostrati];
        for (var i = 0; i < sottostrati; i++)
        {
            profiloPresente[i] = bit.Bit(1) == 1;
            livelloPresente[i] = bit.Bit(1) == 1;
        }
        if (sottostrati > 0)
        {
            for (var i = sottostrati; i < 8; i++) bit.Bit(2);
        }
        for (var i = 0; i < sottostrati; i++)
        {
            if (profiloPresente[i]) { bit.Bit(32); bit.Bit(32); bit.Bit(24); }
            if (livelloPresente[i]) bit.Bit(8);
        }
        bit.Ue(); // sps_seq_parameter_set_id
        var croma = (int)bit.Ue();
        if (croma == 3) bit.Bit(1);
        var larghezza = (int)bit.Ue();
        var altezza = (int)bit.Ue();
        if (bit.Bit(1) == 1)
        {
            bit.Ue(); bit.Ue(); bit.Ue(); bit.Ue();
        }
        var luma = (int)bit.Ue();
        var crominanza = (int)bit.Ue();
        return new InfoSpsHevc(profilo, sottostrati, annidamento, croma, luma, crominanza, larghezza, altezza);
    }

    /// <summary>HEVCDecoderConfigurationRecord, con i tre gruppi VPS, SPS e PPS.</summary>
    private byte[] RecordHevc()
    {
        var info = InfoHevc(Sps[0]);
        var uscita = new List<byte> { 1 };
        uscita.AddRange(info.ProfiloGenerale);          // spazio/livello/profilo, compatibilità, vincoli, livello
        uscita.Add(0xF0); uscita.Add(0x00);              // min_spatial_segmentation_idc = 0
        uscita.Add(0xFC);                                // parallelismType = 0 (sconosciuto)
        uscita.Add((byte)(0xFC | (info.Croma & 3)));
        uscita.Add((byte)(0xF8 | (info.ProfonditaLuma & 7)));
        uscita.Add((byte)(0xF8 | (info.ProfonditaCroma & 7)));
        uscita.Add(0); uscita.Add(0);                    // avgFrameRate sconosciuta
        // constantFrameRate 0, numTemporalLayers, temporalIdNested, lengthSizeMinusOne = 3 (lunghezze su 4 byte).
        uscita.Add((byte)(((info.SottostratiMeno1 + 1) & 7) << 3 | (info.AnnidamentoTemporale ? 1 << 2 : 0) | 3));
        uscita.Add(3);
        foreach (var (tipo, gruppo) in new[] { (AnnexB.HevcVps, Vps), (AnnexB.HevcSps, Sps), (AnnexB.HevcPps, Pps) })
        {
            uscita.Add((byte)(0x80 | tipo)); // array_completeness = 1: i parametri stanno solo qui
            uscita.Add((byte)(gruppo.Count >> 8));
            uscita.Add((byte)gruppo.Count);
            foreach (var p in gruppo) AggiungiConLunghezza(uscita, p);
        }
        return [.. uscita];
    }

    private static void AggiungiConLunghezza(List<byte> uscita, byte[] dati)
    {
        uscita.Add((byte)(dati.Length >> 8));
        uscita.Add((byte)dati.Length);
        uscita.AddRange(dati);
    }
}
