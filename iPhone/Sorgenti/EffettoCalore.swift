import CoreImage
import Foundation

/// «Calore» (quarta prova, gratis): il viso un po' più caldo di serie. Una correzione leggera del bilanciamento del
/// bianco verso il caldo, sull'intera immagine e prima di tutti gli altri effetti (fase `calore`).
///
/// - `forza` 0…1: 0 = i colori della fotocamera (l'effetto è spento e non costa nulla); 1 = come una luce più calda
///   di 500 K (da 6500 a 6000 K). Il telefono propone 0,3.
/// - Una sola matrice diagonale (`CIColorMatrix`) nello spazio di lavoro lineare del contesto pieno: è un
///   adattamento di von Kries (guadagni per canale dal bianco a 6000 K a quello a 6500 K, sul luogo del bianco diurno,
///   in sRGB lineare), normalizzato perché la luminanza del bianco resti 1. Tinta neutra (nessuno spostamento
///   verde–magenta oltre a quello del luogo del bianco), nessuna saturazione forzata, nessuna lettura dei vicini:
///   costa quanto la conversione YCbCr → RGB → YCbCr che la pipeline fa comunque con un effetto acceso.
/// - Nessuna analisi, nessuna geometria: mai saltato quando la resa è in affanno (`essenziale`), così il colore del
///   video non salta tra caldo e neutro.
final class EffettoCalore: Effetto, @unchecked Sendable {
    let nome = "Calore"
    private let blocco = NSLock()
    private var forzaInterna = 0.0

    /// I guadagni di rosso, verde e blu a forza 1 (500 K più caldo, luminanza del bianco invariata).
    private static let guadagniPieni: (r: CGFloat, g: CGFloat, b: CGFloat) = (1.0467, 0.9946, 0.9158)

    /// Da 0 (spento) a 1.
    var forza: Double {
        get { blocco.withLock { forzaInterna } }
        set {
            let limitata = newValue.isFinite ? min(max(newValue, 0), 1) : 0
            blocco.withLock { forzaInterna = limitata }
        }
    }

    var attivo: Bool {
        forza > 0.001
    }

    var essenziale: Bool { true }

    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage {
        let forza = CGFloat(self.forza)
        guard forza > 0.001 else { return immagine }
        let pieni = Self.guadagniPieni
        let r = 1 + (pieni.r - 1) * forza
        let g = 1 + (pieni.g - 1) * forza
        let b = 1 + (pieni.b - 1) * forza
        return immagine.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }
}
