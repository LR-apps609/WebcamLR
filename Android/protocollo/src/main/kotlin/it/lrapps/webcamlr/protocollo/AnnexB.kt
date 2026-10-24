package it.lrapps.webcamlr.protocollo

/** Unità NAL in formato Annex B, separate dai codici di inizio `00 00 01` o `00 00 00 01`. */
object AnnexB {
    val codiceInizio = byteArrayOf(0, 0, 0, 1)

    /** Le unità NAL contenute in `dati`, senza codici di inizio. */
    fun unita(dati: ByteArray): List<ByteArray> {
        val inizi = ArrayList<Pair<Int, Int>>() // posizione, lunghezza del codice
        var i = 0
        while (i + 2 < dati.size) {
            if (dati[i].toInt() == 0 && dati[i + 1].toInt() == 0) {
                if (dati[i + 2].toInt() == 1) {
                    inizi.add(i to 3)
                    i += 3
                    continue
                }
                if (i + 3 < dati.size && dati[i + 2].toInt() == 0 && dati[i + 3].toInt() == 1) {
                    inizi.add(i to 4)
                    i += 4
                    continue
                }
            }
            i++
        }
        val risultato = ArrayList<ByteArray>()
        for ((indice, inizio) in inizi.withIndex()) {
            val da = inizio.first + inizio.second
            val a = if (indice + 1 < inizi.size) inizi[indice + 1].first else dati.size
            if (da < a) risultato.add(dati.copyOfRange(da, a))
        }
        return risultato
    }

    /** Unisce le unità NAL con i codici di inizio di 4 byte. */
    fun unisci(unita: List<ByteArray>): ByteArray {
        val totale = unita.sumOf { it.size + 4 }
        val dati = ByteArray(totale)
        var posizione = 0
        for (nal in unita) {
            System.arraycopy(codiceInizio, 0, dati, posizione, 4)
            System.arraycopy(nal, 0, dati, posizione + 4, nal.size)
            posizione += 4 + nal.size
        }
        return dati
    }

    /** Tipo di un'unità NAL HEVC: 32 = VPS, 33 = SPS, 34 = PPS, 35 = delimitatore, 19–20 = fotogramma chiave. */
    fun tipoHEVC(nal: ByteArray): Int = if (nal.isEmpty()) 0 else (nal[0].toInt() shr 1) and 0x3F

    /** Tipo di un'unità NAL H.264: 5 = fotogramma chiave (IDR), 7 = SPS, 8 = PPS. */
    fun tipoH264(nal: ByteArray): Int = if (nal.isEmpty()) 0 else nal[0].toInt() and 0x1F
}
