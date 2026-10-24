import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import WebcamLRProtocollo

/// I dieci filtri del protocollo (P13) come ricette Core Image: solo operazioni per pixel (matrici di colore,
/// curve, saturazione) che Core Image fonde in un solo passaggio sulla GPU. Le uniche con un vicinato sono la
/// vignettatura di «Cinema» e la riduzione del rumore di «Notte», saltate con la qualità ridotta.
///
/// Lo spazio di lavoro della pipeline è lineare: le curve si applicano in uno spazio percettivo (sRGB), così i
/// punti della curva fanno quello che ci si aspetta su ombre e luci.
enum RicetteFiltri {
    /// Il nome mostrato sul telefono (il protocollo fissa solo gli identificativi).
    static func nome(_ filtro: String) -> String {
        switch filtro {
        case Filtri.caldo: String(localized: "Caldo")
        case Filtri.freddo: String(localized: "Freddo")
        case Filtri.luminoso: String(localized: "Luminoso")
        case Filtri.cinema: String(localized: "Cinema")
        case Filtri.vivido: String(localized: "Vivido")
        case Filtri.tenue: String(localized: "Tenue")
        case Filtri.biancoNero: String(localized: "Bianco e nero")
        case Filtri.seppia: String(localized: "Seppia")
        case Filtri.notte: String(localized: "Notte")
        default: String(localized: "Naturale")
        }
    }

    /// Un identificativo sconosciuto vale `naturale`, come dice il protocollo.
    static func normalizzato(_ filtro: String) -> String {
        Filtri.tutti.contains(filtro) ? filtro : Filtri.naturale
    }

    /// `leggero`: qualità ridotta della pipeline (o miniature), senza i passaggi con un vicinato.
    static func applica(_ filtro: String, a immagine: CIImage, leggero: Bool = false) -> CIImage {
        let estensione = immagine.extent
        let risultato: CIImage
        switch filtro {
        case Filtri.caldo:
            // Rossi un po' su, blu giù: pelle più viva, senza diventare arancione.
            risultato = controlli(matrice(immagine, r: 1.07, g: 1.0, b: 0.88), saturazione: 1.05)
        case Filtri.freddo:
            // Blu su, rossi giù; luci appena più alte per bianchi puliti.
            let freddo = controlli(matrice(immagine, r: 0.92, g: 0.98, b: 1.08), saturazione: 0.97)
            risultato = percettivo(freddo) { curva($0, [(0, 0), (0.25, 0.25), (0.5, 0.51), (0.75, 0.77), (1, 1)]) }
        case Filtri.luminoso:
            // Ombre sollevate, contrasto morbido, luci intatte.
            risultato = percettivo(immagine) {
                curva($0, [(0, 0.04), (0.25, 0.33), (0.5, 0.59), (0.75, 0.81), (1, 1)])
            }
        case Filtri.cinema:
            var cinema = percettivo(immagine) { sRGB in
                // Ombre verso il ciano, luci calde: si mescolano con la luminosità come maschera.
                let ombre = matrice(sRGB, r: 0.90, g: 1.0, b: 1.06, bias: (0, 0.004, 0.012))
                let luci = matrice(sRGB, r: 1.07, g: 1.0, b: 0.90)
                let mescolata = mescola(sopra: luci, sotto: ombre, maschera: luminanza(sRGB))
                let contrasto = curva(mescolata, [(0, 0.02), (0.25, 0.20), (0.5, 0.5), (0.75, 0.80), (1, 0.98)])
                return controlli(contrasto, saturazione: 0.92)
            }
            if !leggero {
                let vignetta = CIFilter.vignetteEffect()
                vignetta.inputImage = cinema
                vignetta.center = CGPoint(x: estensione.midX, y: estensione.midY)
                vignetta.radius = Float(hypot(estensione.width, estensione.height) * 0.4)
                vignetta.intensity = 0.35
                cinema = vignetta.outputImage ?? cinema
            }
            risultato = cinema
        case Filtri.vivido:
            let vibranza = CIFilter.vibrance()
            vibranza.inputImage = immagine
            vibranza.amount = 0.5
            risultato = controlli(vibranza.outputImage ?? immagine, saturazione: 1.12, contrasto: 1.04)
        case Filtri.tenue:
            let smorzata = controlli(immagine, saturazione: 0.72)
            risultato = percettivo(smorzata) {
                curva($0, [(0, 0.06), (0.25, 0.29), (0.5, 0.52), (0.75, 0.75), (1, 0.96)])
            }
        case Filtri.biancoNero:
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = immagine
            risultato = percettivo(mono.outputImage ?? immagine) {
                curva($0, [(0, 0), (0.25, 0.23), (0.5, 0.5), (0.75, 0.78), (1, 1)])
            }
        case Filtri.seppia:
            let seppia = CIFilter.sepiaTone()
            seppia.inputImage = immagine
            seppia.intensity = 0.75
            risultato = percettivo(seppia.outputImage ?? immagine) {
                curva($0, [(0, 0.04), (0.25, 0.27), (0.5, 0.51), (0.75, 0.75), (1, 0.97)])
            }
        case Filtri.notte:
            // Più luce (mezzo stop), ombre aperte, un po' meno colore (il rumore è soprattutto di colore).
            let esposizione = CIFilter.exposureAdjust()
            esposizione.inputImage = immagine
            esposizione.ev = 0.5
            var notte = percettivo(esposizione.outputImage ?? immagine) {
                curva($0, [(0, 0.03), (0.25, 0.34), (0.5, 0.60), (0.75, 0.82), (1, 1)])
            }
            notte = controlli(notte, saturazione: 0.95)
            if !leggero {
                let rumore = CIFilter.noiseReduction()
                rumore.inputImage = notte
                rumore.noiseLevel = 0.03
                rumore.sharpness = 0.3
                notte = rumore.outputImage ?? notte
            }
            risultato = notte
        default:
            return immagine
        }
        return risultato.cropped(to: estensione)
    }

    // MARK: Mattoni

    /// Applica `trasforma` in sRGB (percettivo) e torna allo spazio lineare della pipeline.
    private static func percettivo(_ immagine: CIImage, _ trasforma: (CIImage) -> CIImage) -> CIImage {
        let sRGB = immagine.applyingFilter("CILinearToSRGBToneCurve")
        return trasforma(sRGB).applyingFilter("CISRGBToneCurveToLinear")
    }

    private static func curva(_ immagine: CIImage, _ punti: [(CGFloat, CGFloat)]) -> CIImage {
        guard punti.count == 5 else { return immagine }
        let filtro = CIFilter.toneCurve()
        filtro.inputImage = immagine
        filtro.point0 = CGPoint(x: punti[0].0, y: punti[0].1)
        filtro.point1 = CGPoint(x: punti[1].0, y: punti[1].1)
        filtro.point2 = CGPoint(x: punti[2].0, y: punti[2].1)
        filtro.point3 = CGPoint(x: punti[3].0, y: punti[3].1)
        filtro.point4 = CGPoint(x: punti[4].0, y: punti[4].1)
        return filtro.outputImage ?? immagine
    }

    /// Guadagno per canale, più uno scostamento.
    private static func matrice(_ immagine: CIImage, r: CGFloat, g: CGFloat, b: CGFloat,
                                bias: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)) -> CIImage {
        let filtro = CIFilter.colorMatrix()
        filtro.inputImage = immagine
        filtro.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        filtro.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        filtro.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        filtro.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filtro.biasVector = CIVector(x: bias.0, y: bias.1, z: bias.2, w: 0)
        return filtro.outputImage ?? immagine
    }

    private static func controlli(_ immagine: CIImage, saturazione: Float = 1, contrasto: Float = 1) -> CIImage {
        let filtro = CIFilter.colorControls()
        filtro.inputImage = immagine
        filtro.saturation = saturazione
        filtro.contrast = contrasto
        filtro.brightness = 0
        return filtro.outputImage ?? immagine
    }

    /// Grigio con la luminosità (pesi Rec. 709), da usare come maschera.
    private static func luminanza(_ immagine: CIImage) -> CIImage {
        let pesi = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        let filtro = CIFilter.colorMatrix()
        filtro.inputImage = immagine
        filtro.rVector = pesi
        filtro.gVector = pesi
        filtro.bVector = pesi
        filtro.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filtro.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return filtro.outputImage ?? immagine
    }

    private static func mescola(sopra: CIImage, sotto: CIImage, maschera: CIImage) -> CIImage {
        let filtro = CIFilter.blendWithMask()
        filtro.inputImage = sopra
        filtro.backgroundImage = sotto
        filtro.maskImage = maschera
        return filtro.outputImage ?? sotto
    }
}

/// Il filtro scelto (P13). Spento con `naturale`. Va prima delle regolazioni (`FaseEffetto.filtro`): le
/// regolazioni dell'utente correggono il risultato del filtro, non il contrario.
final class EffettoFiltro: Effetto, @unchecked Sendable {
    let nome = "Filtro"
    private let blocco = NSLock()
    private var scelto = Filtri.naturale

    var filtro: String {
        get { blocco.withLock { scelto } }
        set {
            let normalizzato = RicetteFiltri.normalizzato(newValue)
            blocco.withLock { scelto = normalizzato }
        }
    }

    var attivo: Bool {
        filtro != Filtri.naturale
    }

    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage {
        RicetteFiltri.applica(filtro, a: immagine, leggero: contesto.qualita == .ridotta)
    }
}
