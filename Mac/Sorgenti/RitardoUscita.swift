import Foundation

// Il ritardo «da vetro a uscita» (Documenti/Protocollo.md, «Latenza»): dalla cattura sul telefono al fotogramma
// decodificato che esce nell'anteprima o nella webcam virtuale. La stessa logica di Windows
// (Windows/WebcamLR.Ricevitore/RitardoUscita.cs, provata in RitardoUscitaTest.cs).

/// Il conto del ritardo di un fotogramma, e quale ritardo mostrare.
enum RitardoVetro {
    /// Oltre questo valore la misura non è credibile (orologi appena cambiati, timestamp assurdo).
    static let massimoMs = 10_000

    /// Istante di cattura nell'orologio del Mac (µs): timestamp del telefono meno la differenza tra gli orologi.
    /// Valori dalla rete: aritmetica senza trabocchi; un valore assurdo esce dal controllo di `ms`.
    static func cattura(timestamp: UInt64, scarto: Int64) -> Int64 {
        Int64(truncatingIfNeeded: timestamp) &- scarto
    }

    /// I millisecondi dalla cattura (orologio del Mac, µs) ad `adesso`; nil se non credibili.
    static func ms(cattura: Int64, adesso: UInt64) -> Int? {
        let micro = Int64(truncatingIfNeeded: adesso) &- cattura
        guard micro >= 0, micro < Int64(massimoMs) * 1000 else { return nil }
        return Int(micro / 1000)
    }

    /// La latenza da mostrare e da mandare al telefono (`latenza.ms`): da vetro alla webcam se il telefono è nella webcam
    /// e un'app la usa, altrimenti da vetro all'anteprima, altrimenti fino all'arrivo sul Mac.
    static func latenza(webcam: Int?, anteprima: Int?, arrivo: Int?) -> Int? {
        webcam ?? anteprima ?? arrivo
    }

    /// «72 ms», oppure «—».
    static func testo(_ ms: Int?) -> String {
        ms.map { "\($0) ms" } ?? "—"
    }
}

/// La mediana di un secondo di misure, leggibile da chiunque senza azzerarla. Una misura vecchia di più di 2 secondi non
/// vale più: nessun fotogramma esce da lì. Da qualsiasi coda.
final class MisuraRitardo: @unchecked Sendable {
    static let finestra: UInt64 = 1_000_000
    static let scadenza: UInt64 = 2_000_000

    private let blocco = NSLock()
    private var campioni: [Int] = []
    private var inizio: UInt64 = 0
    private var ultimo: Int?
    private var istanteUltimo: UInt64 = 0

    func aggiungi(_ ms: Int, adesso: UInt64) {
        blocco.lock()
        defer { blocco.unlock() }
        if campioni.isEmpty { inizio = adesso }
        campioni.append(ms)
        if adesso &- min(inizio, adesso) >= Self.finestra { chiudi(adesso) }
    }

    /// La mediana dell'ultimo secondo concluso; nil se non c'è o se è più vecchia di 2 secondi.
    func valore(adesso: UInt64) -> Int? {
        blocco.lock()
        defer { blocco.unlock() }
        if !campioni.isEmpty, adesso &- min(inizio, adesso) >= Self.finestra { chiudi(adesso) }
        guard let ultimo, adesso &- min(istanteUltimo, adesso) <= Self.scadenza else { return nil }
        return ultimo
    }

    private func chiudi(_ adesso: UInt64) {
        campioni.sort()
        ultimo = campioni[campioni.count / 2]
        istanteUltimo = adesso
        campioni.removeAll(keepingCapacity: true)
    }
}

/// Il ritardo dell'audio resta stabile (le app di chiamata odiano il ritardo che oscilla): vale il massimo delle misure
/// degli ultimi 5 secondi. Sale subito (meglio la voce un attimo dopo le labbra che un buco), scende solo dopo 5 secondi
/// di valori più bassi. Solo su una coda.
struct StabilizzatoreRitardo {
    static let secondi: UInt64 = 5

    private var perSecondo: [(secondo: UInt64, massimo: Int)] = []

    mutating func aggiungi(_ ms: Int, adesso: UInt64) {
        let secondo = adesso / 1_000_000
        if let ultimo = perSecondo.last, ultimo.secondo == secondo {
            perSecondo[perSecondo.count - 1].massimo = max(ultimo.massimo, ms)
        } else {
            perSecondo.append((secondo, ms))
        }
        perSecondo.removeAll { secondo &- min($0.secondo, secondo) >= Self.secondi }
    }

    /// Il massimo degli ultimi 5 secondi; nil se non c'è nessuna misura.
    var voluto: Int? { perSecondo.map(\.massimo).max() }

    mutating func azzera() { perSecondo.removeAll() }
}
