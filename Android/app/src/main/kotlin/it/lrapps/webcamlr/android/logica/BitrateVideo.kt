package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Codec

/**
 * Il bitrate della qualità scelta, prima dell'adattamento alla rete (`AdattamentoRete`, che lo abbassa da solo se la
 * rete non regge). Il video va solo dal telefono al computer, in rete locale o con il cavo: si può essere generosi.
 * Stessi numeri dell'iPhone (Codificatore.swift): H.264 a 30 fps 720p 8, 1080p 16, 4K 40 Mbit/s; 60 fps ×1,5
 * (1080p60 = 24 Mbit/s); HEVC ×0,65; con il cavo (USB o di rete) ×1,5.
 */
object BitrateVideo {
    const val MBIT = 1_000_000

    fun base(larghezza: Int, altezza: Int, fps: Int, codec: Codec, cavo: Boolean): Int {
        val pixel = larghezza.toLong() * altezza
        // Le soglie stanno a metà strada tra le qualità: 720p, 1080p e 4K (in orizzontale o in verticale).
        val a30 = when {
            pixel <= 1_500_000L -> 8.0
            pixel <= 4_000_000L -> 16.0
            else -> 40.0
        }
        val mbit = a30 *
            (if (fps > 30) 1.5 else 1.0) *
            (if (codec == Codec.HEVC) 0.65 else 1.0) *
            (if (cavo) 1.5 else 1.0)
        return (mbit * MBIT).toInt()
    }
}
