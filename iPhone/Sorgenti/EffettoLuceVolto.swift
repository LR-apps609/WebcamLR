import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation

/// «Luce sul volto» (P08, bug 5): una luce ad anello virtuale, leggera. Prima la funzione spostava solo il punto
/// dell'esposizione sul volto (`FunzioniVolto.seguiLuce`, che resta): nel video non si vedeva quasi nulla.
///
/// - Dove: un'ellisse morbida attorno al volto principale (il più grande di `AnalisiFotogramma`), un po' più
///   grande del rettangolo e scesa verso il mento; il bordo sfuma fino a zero, quindi nessun alone netto.
/// - Quanto: una curva di tono nello spazio percettivo che solleva ombre e mezzitoni di circa +0,4 EV (+0,25 EV
///   nelle luci) e lascia il bianco al suo posto: niente luci bruciate. Stessa curva sui tre canali, nessuna
///   dominante di colore.
/// - Morbida nel tempo: il rettangolo del volto si leviga e la luce entra ed esce in circa mezzo secondo quando il
///   volto compare o sparisce (niente scatti).
/// - Gratis. Va prima dell'inquadratura (`FaseEffetto.luceVolto`): lavora sul fotogramma intero, come la pelle.
///   Con la sfocatura dello sfondo accesa schiarisce il volto già ritagliato dalla persona; da sola basta a
///   mandare il video nella pipeline (con i colori della cattura, bug 6).
final class EffettoLuceVolto: Effetto, @unchecked Sendable {
    let nome = "Luce sul volto"

    private let blocco = NSLock()
    private var accesoInterno = false

    // Solo sulla coda di cattura.
    private var volto: CGRect?
    /// Da 0 (spenta) a 1 (piena): sale quando c'è un volto, scende quando non c'è.
    private var presenza: CGFloat = 0
    private var ultimoIstante: CMTime = .invalid

    /// Secondi per entrare o uscire del tutto.
    private static let dissolvenza: Double = 0.5
    /// Peso del rettangolo nuovo nella media mobile del volto (per fotogramma).
    private static let pesoVoltoNuovo: CGFloat = 0.25

    /// Dall'interfaccia o dal computer (`FunzioniVolto.impostaLuceVolto`).
    var acceso: Bool {
        get { blocco.withLock { accesoInterno } }
        set { blocco.withLock { accesoInterno = newValue } }
    }

    var attivo: Bool { acceso }

    var analisiNecessarie: Set<TipoAnalisi> { [.volti] }

    func applica(_ immagine: CIImage, contesto info: InfoFotogramma) -> CIImage {
        let estensione = immagine.extent
        let passo = passoDissolvenza(info.istante)

        // Il volto principale, se il risultato è fresco.
        var trovato: CGRect?
        if let volti = info.volti, ProcessInfo.processInfo.systemUptime - volti.quando < 1 {
            trovato = volti.rettangoli
                .map { info.inImmagine($0) }
                .filter { $0.intersects(estensione) && $0.height > 8 }
                .max { $0.width * $0.height < $1.width * $1.height }
        }
        if let trovato {
            volto = volto.map { Self.mescola($0, trovato, peso: Self.pesoVoltoNuovo) } ?? trovato
            presenza = min(presenza + passo, 1)
        } else {
            presenza = max(presenza - passo, 0)
        }
        guard let volto, presenza > 0.01 else {
            if presenza <= 0.01 { self.volto = nil }
            return immagine
        }

        // Ellisse attorno al volto: più larga e più alta del rettangolo, centrata appena sotto (mento e collo).
        let centro = CGPoint(x: volto.midX, y: volto.midY - volto.height * 0.08)
        let semiasseX = volto.width * 1.0
        let semiasseY = volto.height * 1.25
        let zona = CGRect(x: centro.x - semiasseX, y: centro.y - semiasseY,
                          width: semiasseX * 2, height: semiasseY * 2)
            .intersection(estensione).integral
        guard !zona.isEmpty else { return immagine }

        let disco = CIFilter.radialGradient()
        disco.center = .zero
        disco.radius0 = 0.35
        disco.radius1 = 1
        disco.color0 = CIColor(red: 1, green: 1, blue: 1)
        disco.color1 = CIColor(red: 0, green: 0, blue: 0)
        guard let ellisse = disco.outputImage?
            .transformed(by: CGAffineTransform(scaleX: semiasseX, y: semiasseY)
                .concatenating(CGAffineTransform(translationX: centro.x, y: centro.y)))
            .cropped(to: zona) else { return immagine }
        let maschera = Self.scala(ellisse, per: presenza)

        let originale = immagine.cropped(to: zona)
        let illuminata = Self.solleva(originale)
        let unione = CIFilter.blendWithMask()
        unione.inputImage = illuminata
        unione.backgroundImage = originale
        unione.maskImage = maschera
        guard let risultato = unione.outputImage?.cropped(to: zona) else { return immagine }
        return risultato.composited(over: immagine)
    }

    func geometriaCambiata(_ cambio: CambioGeometria) {
        // Il volto levigato era nella geometria di prima: si riparte dal primo volto nuovo.
        volto = nil
        presenza = 0
    }

    // MARK: Interni

    /// Quanto avanza la dissolvenza in questo fotogramma (dai tempi dei fotogrammi: vale a 24, 30 e 60 fps).
    private func passoDissolvenza(_ istante: CMTime) -> CGFloat {
        defer { ultimoIstante = istante }
        var durata = 1.0 / 30
        if ultimoIstante.isValid, istante.isValid {
            let differenza = CMTimeSubtract(istante, ultimoIstante).seconds
            if differenza.isFinite, differenza > 0, differenza < 0.5 { durata = differenza }
        }
        return CGFloat(durata / Self.dissolvenza)
    }

    private static func mescola(_ vecchio: CGRect, _ nuovo: CGRect, peso: CGFloat) -> CGRect {
        CGRect(x: vecchio.minX + (nuovo.minX - vecchio.minX) * peso,
               y: vecchio.minY + (nuovo.minY - vecchio.minY) * peso,
               width: vecchio.width + (nuovo.width - vecchio.width) * peso,
               height: vecchio.height + (nuovo.height - vecchio.height) * peso)
    }

    /// Ombre e mezzitoni più chiari, bianco fermo: curva di tono in sRGB (percettivo), poi di nuovo lineare come
    /// lo spazio di lavoro della pipeline. In lineare circa +0,4 EV a metà, +0,25 EV nelle luci.
    private static func solleva(_ immagine: CIImage) -> CIImage {
        let percettiva = immagine.applyingFilter("CILinearToSRGBToneCurve")
        let curva = CIFilter.toneCurve()
        curva.inputImage = percettiva
        curva.point0 = CGPoint(x: 0, y: 0)
        curva.point1 = CGPoint(x: 0.25, y: 0.29)
        curva.point2 = CGPoint(x: 0.5, y: 0.565)
        curva.point3 = CGPoint(x: 0.75, y: 0.81)
        curva.point4 = CGPoint(x: 1, y: 1)
        return (curva.outputImage ?? percettiva).applyingFilter("CISRGBToneCurveToLinear")
    }

    /// Valori × `fattore`, alfa a 1.
    private static func scala(_ maschera: CIImage, per fattore: CGFloat) -> CIImage {
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
