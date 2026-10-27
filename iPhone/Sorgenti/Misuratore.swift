import Foundation

/// Il misuratore delle prestazioni (qualità ed efficienza, 27 ottobre): fotogrammi spediti al secondo, millisecondi
/// degli effetti per fotogramma, maschere della persona al secondo e bitrate reale. Codificatore, pipeline e analisi
/// contano da qualsiasi coda (un blocco e qualche somma: niente costo per fotogramma); la sessione legge ogni
/// 2 secondi (`leggi`), che riparte da zero. I numeri vanno nei Dettagli («Prestazioni») e, con gli effetti accesi,
/// nel registro del collegamento ogni 10 secondi.
final class Misuratore: @unchecked Sendable {
    struct Lettura: Equatable, Sendable {
        /// Fotogrammi usciti dal codificatore al secondo (quelli che partono verso il computer).
        var fps: Double = 0
        /// Bit al secondo usciti dal codificatore.
        var bitrate: Double = 0
        /// Millisecondi medi degli effetti per fotogramma, attesa della maschera compresa; `nil` senza effetti.
        var msEffetti: Double?
        /// Maschere della persona (Vision) al secondo; 0 senza sfondo.
        var maschere: Double = 0
    }

    /// Una sessione alla volta: un misuratore solo, come il registro.
    static let condiviso = Misuratore()

    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var inizio = ProcessInfo.processInfo.systemUptime
    private var fotogrammi = 0
    private var byte = 0
    private var tempoEffetti: TimeInterval = 0
    private var fotogrammiConEffetti = 0
    private var maschere = 0

    /// Dal codificatore: un fotogramma compresso di `quanti` byte, pronto da spedire.
    func fotogrammaCodificato(byte quanti: Int) {
        blocco.withLock {
            fotogrammi += 1
            byte += quanti
        }
    }

    /// Dalla pipeline: un fotogramma con effetti, elaborato in `durata` secondi.
    func effetti(durata: TimeInterval) {
        blocco.withLock {
            tempoEffetti += durata
            fotogrammiConEffetti += 1
        }
    }

    /// Dall'analisi: una maschera della persona nuova.
    func maschera() {
        blocco.withLock { maschere += 1 }
    }

    /// Le medie dall'ultima lettura a adesso; poi si ricomincia a contare.
    func leggi() -> Lettura {
        blocco.withLock { () -> Lettura in
            let adesso = ProcessInfo.processInfo.systemUptime
            let secondi = max(adesso - inizio, 0.001)
            let lettura = Lettura(fps: Double(fotogrammi) / secondi,
                                  bitrate: Double(byte) * 8 / secondi,
                                  msEffetti: fotogrammiConEffetti > 0
                                      ? tempoEffetti / Double(fotogrammiConEffetti) * 1000 : nil,
                                  maschere: Double(maschere) / secondi)
            inizio = adesso
            fotogrammi = 0
            byte = 0
            tempoEffetti = 0
            fotogrammiConEffetti = 0
            maschere = 0
            return lettura
        }
    }

    /// La riga compatta «30 fps · 15,8 Mbit/s · effetti 9 ms · 30 maschere/s · normale».
    static func testo(_ lettura: Lettura, temperatura: String) -> String {
        var parti = ["\(Int(lettura.fps.rounded())) fps",
                     (lettura.bitrate / 1_000_000).formatted(.number.precision(.fractionLength(1))) + " Mbit/s"]
        if let ms = lettura.msEffetti {
            parti.append(String(localized: "effetti \(Int(ms.rounded())) ms"))
        }
        if lettura.maschere > 0 {
            parti.append(String(localized: "\(Int(lettura.maschere.rounded())) maschere/s"))
        }
        parti.append(temperatura)
        return parti.joined(separator: " · ")
    }
}
