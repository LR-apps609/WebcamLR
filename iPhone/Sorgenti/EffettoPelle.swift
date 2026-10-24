import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Ritocco della pelle (P15): leviga appena il viso, senza l'effetto «plastica».
///
/// - Solo dove ci sono i volti (`VNDetectFaceRectanglesRequest` di `AnalisiFotogramma`): una maschera morbida e
///   rotonda per ogni volto, un po' più grande del rettangolo (fronte e mento). Senza volti il video passa intatto.
/// - Levigatura «quasi bilaterale»: una sfocatura piccola (proporzionale al volto, calcolata a metà risoluzione
///   e solo attorno ai volti) mescolata all'originale **solo dove differisce poco** (la grana della pelle);
///   dove la differenza è grande (occhi, sopracciglia, labbra, capelli, bordi) resta l'originale.
/// - Anche al massimo si mescola al 75%: un po' di grana resta sempre. `forza` 0…1; il telefono propone 0,3.
/// - Con la qualità ridotta niente maschera dei bordi: solo la maschera dei volti, a forza dimezzata.
final class EffettoPelle: Effetto, @unchecked Sendable {
    let nome = "Pelle"
    private let blocco = NSLock()
    private var forzaInterna = 0.0

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

    var analisiNecessarie: Set<TipoAnalisi> { [.volti] }

    /// Quanto conta la differenza dalla versione sfocata: oltre circa 1/12 (spazio lineare) è un bordo, non pelle.
    private static let sensibilitaBordi: CGFloat = 12

    func applica(_ immagine: CIImage, contesto info: InfoFotogramma) -> CIImage {
        let forza = CGFloat(self.forza)
        guard let volti = info.volti, ProcessInfo.processInfo.systemUptime - volti.quando < 1 else { return immagine }
        let estensione = immagine.extent
        let rettangoli = volti.rettangoli.map { info.inImmagine($0) }.filter { $0.intersects(estensione) && $0.height > 8 }
        guard let altezzaMassima = rettangoli.map(\.height).max() else { return immagine }

        // La zona da lavorare: i volti con un margine; fuori non si calcola nulla.
        var zona = CGRect.null
        for rettangolo in rettangoli {
            zona = zona.union(rettangolo.insetBy(dx: -rettangolo.width * 0.4, dy: -rettangolo.height * 0.45))
        }
        zona = zona.intersection(estensione).integral
        guard !zona.isEmpty else { return immagine }

        let leggero = info.qualita == .ridotta
        // Sfocatura piccola, proporzionale al volto: circa 1–2% della sua altezza.
        let sigma = max(1.5, altezzaMassima * (0.008 + 0.01 * forza))
        let margine = sigma * 3
        let sorgente = immagine.clampedToExtent().cropped(to: zona.insetBy(dx: -margine, dy: -margine))
        let dimezza = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let sfocata = sorgente.transformed(by: dimezza)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(sigma * 0.5))
            .transformed(by: dimezza.inverted())
            .cropped(to: zona)

        var maschera = mascheraVolti(rettangoli, zona: zona)
        if !leggero {
            maschera = moltiplica(maschera, mascheraPelle(originale: immagine, sfocata: sfocata, zona: zona))
        }
        maschera = scala(maschera, per: (leggero ? 0.375 : 0.75) * forza)

        let unione = CIFilter.blendWithMask()
        unione.inputImage = sfocata
        unione.backgroundImage = immagine.cropped(to: zona)
        unione.maskImage = maschera
        guard let levigata = unione.outputImage?.cropped(to: zona) else { return immagine }
        return levigata.composited(over: immagine)
    }

    // MARK: Maschere

    /// Un disco morbido per volto, centrato appena sotto il centro del rettangolo (guance e bocca).
    private func mascheraVolti(_ rettangoli: [CGRect], zona: CGRect) -> CIImage {
        var maschera = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: zona)
        for rettangolo in rettangoli {
            let lato = max(rettangolo.width, rettangolo.height)
            let disco = CIFilter.radialGradient()
            disco.center = CGPoint(x: rettangolo.midX, y: rettangolo.midY - rettangolo.height * 0.04)
            disco.radius0 = Float(lato * 0.38)
            disco.radius1 = Float(lato * 0.72)
            disco.color0 = CIColor(red: 1, green: 1, blue: 1)
            disco.color1 = CIColor(red: 0, green: 0, blue: 0)
            guard let immagineDisco = disco.outputImage?.cropped(to: zona) else { continue }
            let massimo = CIFilter.maximumCompositing()
            massimo.inputImage = immagineDisco
            massimo.backgroundImage = maschera
            maschera = massimo.outputImage ?? maschera
        }
        return maschera
    }

    /// Bianco dove l'originale differisce poco dalla versione sfocata (pelle), nero sui bordi veri.
    private func mascheraPelle(originale: CIImage, sfocata: CIImage, zona: CGRect) -> CIImage {
        let differenza = CIFilter.colorAbsoluteDifference()
        differenza.inputImage = originale.cropped(to: zona)
        differenza.inputImage2 = sfocata
        guard let assoluta = differenza.outputImage else { return CIImage(color: .white).cropped(to: zona) }
        // 1 - sensibilità × media dei tre canali, tra 0 e 1.
        let peso = -Self.sensibilitaBordi / 3
        let riga = CIVector(x: peso, y: peso, z: peso, w: 0)
        let inversa = CIFilter.colorMatrix()
        inversa.inputImage = assoluta
        inversa.rVector = riga
        inversa.gVector = riga
        inversa.bVector = riga
        inversa.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        inversa.biasVector = CIVector(x: 1, y: 1, z: 1, w: 1)
        let limiti = CIFilter.colorClamp()
        limiti.inputImage = inversa.outputImage ?? assoluta
        limiti.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        limiti.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return (limiti.outputImage ?? assoluta).cropped(to: zona)
    }

    private func moltiplica(_ prima: CIImage, _ seconda: CIImage) -> CIImage {
        let prodotto = CIFilter.multiplyCompositing()
        prodotto.inputImage = prima
        prodotto.backgroundImage = seconda
        return prodotto.outputImage ?? prima
    }

    /// Valori × `fattore`, alfa a 1.
    private func scala(_ maschera: CIImage, per fattore: CGFloat) -> CIImage {
        let filtro = CIFilter.colorMatrix()
        filtro.inputImage = maschera
        filtro.rVector = CIVector(x: fattore, y: 0, z: 0, w: 0)
        filtro.gVector = CIVector(x: 0, y: fattore, z: 0, w: 0)
        filtro.bVector = CIVector(x: 0, y: 0, z: fattore, w: 0)
        filtro.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filtro.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return filtro.outputImage ?? maschera
    }
}
