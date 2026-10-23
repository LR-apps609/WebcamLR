import Foundation

/// Unità NAL in formato Annex B, separate dai codici di inizio `00 00 01` o `00 00 00 01`.
public enum AnnexB {
    public static let codiceInizio = Data([0, 0, 0, 1])

    /// Le unità NAL contenute in `dati`, senza codici di inizio.
    public static func unita(in dati: Data) -> [Data] {
        let byte = [UInt8](dati)
        var inizi: [(posizione: Int, lunghezzaCodice: Int)] = []
        var i = 0
        while i + 2 < byte.count {
            if byte[i] == 0, byte[i + 1] == 0 {
                if byte[i + 2] == 1 {
                    inizi.append((i, 3))
                    i += 3
                    continue
                }
                if i + 3 < byte.count, byte[i + 2] == 0, byte[i + 3] == 1 {
                    inizi.append((i, 4))
                    i += 4
                    continue
                }
            }
            i += 1
        }
        var risultato: [Data] = []
        for (indice, inizio) in inizi.enumerated() {
            let da = inizio.posizione + inizio.lunghezzaCodice
            let a = indice + 1 < inizi.count ? inizi[indice + 1].posizione : byte.count
            if da < a {
                risultato.append(Data(byte[da..<a]))
            }
        }
        return risultato
    }

    /// Unisce le unità NAL con i codici di inizio di 4 byte.
    public static func unisci(_ unita: [Data]) -> Data {
        var dati = Data()
        for nal in unita {
            dati.append(codiceInizio)
            dati.append(nal)
        }
        return dati
    }

    /// Tipo di un'unità NAL HEVC: 32 = VPS, 33 = SPS, 34 = PPS, 35 = delimitatore, 19–20 = fotogramma chiave.
    public static func tipoHEVC(_ nal: Data) -> UInt8 {
        guard let primo = nal.first else { return 0 }
        return (primo >> 1) & 0x3F
    }

    /// Tipo di un'unità NAL H.264: 5 = fotogramma chiave (IDR), 7 = SPS, 8 = PPS.
    public static func tipoH264(_ nal: Data) -> UInt8 {
        guard let primo = nal.first else { return 0 }
        return primo & 0x1F
    }
}
