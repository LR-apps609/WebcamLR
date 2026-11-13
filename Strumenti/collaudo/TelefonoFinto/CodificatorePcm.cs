namespace WebcamLR.Collaudo;

/// <summary>
/// Un codificatore H.264 minimo per il collaudo, senza librerie: ogni fotogramma è un IDR fatto solo di macroblocchi
/// I_PCM (i campioni Y, Cb, Cr scritti così come sono). Profilo Baseline, CAVLC, una fetta per fotogramma. Il flusso è
/// grande (circa 1,4 MB a 1280×720) ma ogni decodificatore H.264 lo legge, compreso quello di Windows, e ogni fotogramma
/// è una chiave con SPS e PPS davanti, come chiede Protocollo.md («Tipo 2 · video»).
/// </summary>
public sealed class CodificatorePcm
{
    public int Larghezza { get; }
    public int Altezza { get; }
    private readonly int macroblocchiLarghi;
    private readonly int macroblocchiAlti;
    private readonly byte[] sps;
    private readonly byte[] pps;
    private int idrId;

    public CodificatorePcm(int larghezza, int altezza)
    {
        if (larghezza < 16 || altezza < 16 || larghezza % 2 != 0 || altezza % 2 != 0)
            throw new ArgumentException("Larghezza e altezza: pari e almeno 16");
        Larghezza = larghezza;
        Altezza = altezza;
        macroblocchiLarghi = (larghezza + 15) / 16;
        macroblocchiAlti = (altezza + 15) / 16;
        sps = Nal(0x67, CreaSps());
        pps = Nal(0x68, CreaPps());
    }

    /// <summary>
    /// Un fotogramma in formato Annex B (SPS, PPS, fetta IDR). I piani sono 4:2:0: <paramref name="y"/> è
    /// Larghezza×Altezza, <paramref name="cb"/> e <paramref name="cr"/> (Larghezza/2)×(Altezza/2).
    /// </summary>
    public byte[] Codifica(byte[] y, byte[] cb, byte[] cr)
    {
        var fetta = Nal(0x65, CreaFetta(y, cb, cr));
        var uscita = new byte[sps.Length + pps.Length + fetta.Length];
        sps.CopyTo(uscita, 0);
        pps.CopyTo(uscita, sps.Length);
        fetta.CopyTo(uscita, sps.Length + pps.Length);
        return uscita;
    }

    private byte[] CreaSps()
    {
        var b = new ScrittoreBit();
        b.Bit(66, 8);            // profile_idc: Baseline
        b.Bit(0b1100_0000, 8);   // constraint_set0 e set1
        b.Bit(51, 8);            // level_idc 5.1: fino al 4K, nessun limite che dia fastidio
        b.Ue(0);                 // seq_parameter_set_id
        b.Ue(0);                 // log2_max_frame_num_minus4
        b.Ue(2);                 // pic_order_cnt_type 2: ordine di uscita = ordine di decodifica
        b.Ue(1);                 // max_num_ref_frames
        b.Bit(0, 1);             // gaps_in_frame_num_value_allowed_flag
        b.Ue((uint)macroblocchiLarghi - 1);
        b.Ue((uint)macroblocchiAlti - 1);
        b.Bit(1, 1);             // frame_mbs_only_flag
        b.Bit(1, 1);             // direct_8x8_inference_flag
        var tagliaDestra = macroblocchiLarghi * 16 - Larghezza;
        var tagliaSotto = macroblocchiAlti * 16 - Altezza;
        if (tagliaDestra > 0 || tagliaSotto > 0)
        {
            b.Bit(1, 1);         // frame_cropping_flag (unità di 2 campioni in 4:2:0)
            b.Ue(0);
            b.Ue((uint)tagliaDestra / 2);
            b.Ue(0);
            b.Ue((uint)tagliaSotto / 2);
        }
        else b.Bit(0, 1);
        b.Bit(1, 1);             // vui_parameters_present_flag
        b.Bit(0, 1);             // aspect_ratio_info_present_flag
        b.Bit(0, 1);             // overscan_info_present_flag
        b.Bit(0, 1);             // video_signal_type_present_flag
        b.Bit(0, 1);             // chroma_loc_info_present_flag
        b.Bit(0, 1);             // timing_info_present_flag
        b.Bit(0, 1);             // nal_hrd_parameters_present_flag
        b.Bit(0, 1);             // vcl_hrd_parameters_present_flag
        b.Bit(0, 1);             // pic_struct_present_flag
        b.Bit(1, 1);             // bitstream_restriction_flag: nessun riordino, il decodificatore non trattiene fotogrammi
        b.Bit(1, 1);             // motion_vectors_over_pic_boundaries_flag
        b.Ue(0);                 // max_bytes_per_pic_denom
        b.Ue(0);                 // max_bits_per_mb_denom
        b.Ue(16);                // log2_max_mv_length_horizontal
        b.Ue(16);                // log2_max_mv_length_vertical
        b.Ue(0);                 // max_num_reorder_frames
        b.Ue(1);                 // max_dec_frame_buffering
        b.Chiudi();
        return b.Dati();
    }

    private static byte[] CreaPps()
    {
        var b = new ScrittoreBit();
        b.Ue(0);                 // pic_parameter_set_id
        b.Ue(0);                 // seq_parameter_set_id
        b.Bit(0, 1);             // entropy_coding_mode_flag: CAVLC
        b.Bit(0, 1);             // bottom_field_pic_order_in_frame_present_flag
        b.Ue(0);                 // num_slice_groups_minus1
        b.Ue(0);                 // num_ref_idx_l0_default_active_minus1
        b.Ue(0);                 // num_ref_idx_l1_default_active_minus1
        b.Bit(0, 1);             // weighted_pred_flag
        b.Bit(0, 2);             // weighted_bipred_idc
        b.Se(0);                 // pic_init_qp_minus26
        b.Se(0);                 // pic_init_qs_minus26
        b.Se(0);                 // chroma_qp_index_offset
        b.Bit(1, 1);             // deblocking_filter_control_present_flag
        b.Bit(0, 1);             // constrained_intra_pred_flag
        b.Bit(0, 1);             // redundant_pic_cnt_present_flag
        b.Chiudi();
        return b.Dati();
    }

    private byte[] CreaFetta(byte[] y, byte[] cb, byte[] cr)
    {
        var dimensione = macroblocchiLarghi * macroblocchiAlti * (384 + 2) + 32;
        var b = new ScrittoreBit(dimensione);
        b.Ue(0);                 // first_mb_in_slice
        b.Ue(7);                 // slice_type: I (tutte le fette)
        b.Ue(0);                 // pic_parameter_set_id
        b.Bit(0, 4);             // frame_num (IDR: 0)
        b.Ue((uint)(idrId++ & 0xFFFF)); // idr_pic_id: due IDR di fila devono averlo diverso
        b.Bit(0, 1);             // no_output_of_prior_pics_flag
        b.Bit(0, 1);             // long_term_reference_flag
        b.Se(0);                 // slice_qp_delta
        b.Ue(1);                 // disable_deblocking_filter_idc: niente filtro
        var larghezzaCroma = Larghezza / 2;
        var altezzaCroma = Altezza / 2;
        for (var my = 0; my < macroblocchiAlti; my++)
        for (var mx = 0; mx < macroblocchiLarghi; mx++)
        {
            b.Ue(25);            // mb_type: I_PCM
            b.Allinea();         // pcm_alignment_zero_bit
            for (var r = 0; r < 16; r++)
            {
                var riga = Math.Min(my * 16 + r, Altezza - 1);
                for (var c = 0; c < 16; c++)
                    b.Byte(Campione(y[riga * Larghezza + Math.Min(mx * 16 + c, Larghezza - 1)]));
            }
            foreach (var piano in new[] { cb, cr })
                for (var r = 0; r < 8; r++)
                {
                    var riga = Math.Min(my * 8 + r, altezzaCroma - 1);
                    for (var c = 0; c < 8; c++)
                        b.Byte(Campione(piano[riga * larghezzaCroma + Math.Min(mx * 8 + c, larghezzaCroma - 1)]));
                }
        }
        b.Chiudi();
        return b.Dati();
    }

    /// <summary>Le prime versioni di H.264 vietano lo zero nei campioni PCM: si parte da 1.</summary>
    private static byte Campione(byte valore) => valore == 0 ? (byte)1 : valore;

    /// <summary>Codice di inizio, intestazione NAL e contenuto con i byte di prevenzione (00 00 03).</summary>
    private static byte[] Nal(byte intestazione, byte[] rbsp)
    {
        var uscita = new List<byte>(rbsp.Length + rbsp.Length / 64 + 8) { 0, 0, 0, 1, intestazione };
        var zeri = 0;
        foreach (var valore in rbsp)
        {
            if (zeri >= 2 && valore <= 3)
            {
                uscita.Add(3);
                zeri = 0;
            }
            uscita.Add(valore);
            zeri = valore == 0 ? zeri + 1 : 0;
        }
        return uscita.ToArray();
    }

    /// <summary>Scrive bit per bit (big-endian), con i codici Exp-Golomb di H.264.</summary>
    private sealed class ScrittoreBit(int capacita = 64)
    {
        private byte[] dati = new byte[Math.Max(capacita, 16)];
        private int posizione;   // in byte
        private int bitLiberi = 8;
        private int corrente;

        public void Bit(uint valore, int quanti)
        {
            for (var i = quanti - 1; i >= 0; i--)
            {
                corrente = (corrente << 1) | (int)((valore >> i) & 1);
                if (--bitLiberi == 0) Svuota();
            }
        }

        public void Ue(uint valore)
        {
            var v = valore + 1;
            var lunghezza = 32 - System.Numerics.BitOperations.LeadingZeroCount(v);
            Bit(0, lunghezza - 1);
            Bit(v, lunghezza);
        }

        public void Se(int valore) => Ue(valore <= 0 ? (uint)(-2 * valore) : (uint)(2 * valore - 1));

        public void Allinea()
        {
            while (bitLiberi != 8) Bit(0, 1);
        }

        public void Byte(byte valore)
        {
            if (bitLiberi != 8) { Bit(valore, 8); return; }
            Spazio();
            dati[posizione++] = valore;
        }

        /// <summary>rbsp_trailing_bits: un 1 e gli zeri fino al byte.</summary>
        public void Chiudi()
        {
            Bit(1, 1);
            Allinea();
        }

        public byte[] Dati() => dati.AsSpan(0, posizione).ToArray();

        private void Svuota()
        {
            Spazio();
            dati[posizione++] = (byte)corrente;
            corrente = 0;
            bitLiberi = 8;
        }

        private void Spazio()
        {
            if (posizione >= dati.Length) Array.Resize(ref dati, dati.Length * 2);
        }
    }
}
