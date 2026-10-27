import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import Stile
import SwiftUI
import WebcamLRProtocollo

// Le ricette degli effetti del motore del Mac (MotoreEffetti.swift), portate dall'iPhone perché il risultato sia lo
// stesso: EffettoFiltro.swift, la regolazioni di PipelineEffetti.swift, EffettoCalore.swift, EffettoPelle.swift,
// EffettoLuceVolto.swift, EffettoScritta.swift ed EffettoSfondo.swift. Solo funzioni senza stato: lo stato nel tempo
// (maschera filtrata, volto levigato, molla dell'inquadratura) resta nel motore, sulla sua coda di resa.
// Spazio di lavoro lineare (sRGB esteso), come sul telefono: le curve si applicano in uno spazio percettivo.

/// I dieci filtri del protocollo, uguali a quelli dell'iPhone (`RicetteFiltri` in EffettoFiltro.swift).
enum RicetteFiltriMac {
    /// Un identificativo sconosciuto vale `naturale`, come dice il protocollo.
    static func normalizzato(_ filtro: String) -> String {
        Filtri.tutti.contains(filtro) ? filtro : Filtri.naturale
    }

    /// `leggero`: senza i passaggi con un vicinato (vignettatura di «Cinema», riduzione del rumore di «Notte»).
    static func applica(_ filtro: String, a immagine: CIImage, leggero: Bool = false) -> CIImage {
        let estensione = immagine.extent
        let risultato: CIImage
        switch filtro {
        case Filtri.caldo:
            risultato = controlli(matrice(immagine, r: 1.07, g: 1.0, b: 0.88), saturazione: 1.05)
        case Filtri.freddo:
            let freddo = controlli(matrice(immagine, r: 0.92, g: 0.98, b: 1.08), saturazione: 0.97)
            risultato = percettivo(freddo) { curva($0, [(0, 0), (0.25, 0.25), (0.5, 0.51), (0.75, 0.77), (1, 1)]) }
        case Filtri.luminoso:
            risultato = percettivo(immagine) {
                curva($0, [(0, 0.04), (0.25, 0.33), (0.5, 0.59), (0.75, 0.81), (1, 1)])
            }
        case Filtri.cinema:
            var cinema = percettivo(immagine) { sRGB in
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

    // MARK: Mattoni (usati anche dalle altre ricette)

    /// Applica `trasforma` in sRGB (percettivo) e torna allo spazio lineare.
    static func percettivo(_ immagine: CIImage, _ trasforma: (CIImage) -> CIImage) -> CIImage {
        let sRGB = immagine.applyingFilter("CILinearToSRGBToneCurve")
        return trasforma(sRGB).applyingFilter("CISRGBToneCurveToLinear")
    }

    static func curva(_ immagine: CIImage, _ punti: [(CGFloat, CGFloat)]) -> CIImage {
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
    static func matrice(_ immagine: CIImage, r: CGFloat, g: CGFloat, b: CGFloat,
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

    static func mescola(sopra: CIImage, sotto: CIImage, maschera: CIImage) -> CIImage {
        let filtro = CIFilter.blendWithMask()
        filtro.inputImage = sopra
        filtro.backgroundImage = sotto
        filtro.maskImage = maschera
        return filtro.outputImage ?? sotto
    }

    /// Valori × `fattore`, alfa a 1 (per le maschere).
    static func scala(_ maschera: CIImage, per fattore: CGFloat) -> CIImage {
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

/// Le altre ricette, uguali all'iPhone.
enum RicetteEffetti {
    // MARK: Calore (EffettoCalore.swift)

    /// I guadagni di rosso, verde e blu a forza 1 (500 K più caldo, luminanza del bianco invariata): adattamento di
    /// von Kries dal bianco a 6000 K a quello a 6500 K, in sRGB lineare. Stessa matrice dell'iPhone.
    static let guadagniCalore: (r: CGFloat, g: CGFloat, b: CGFloat) = (1.0467, 0.9946, 0.9158)

    static func calore(_ immagine: CIImage, forza valore: Double) -> CIImage {
        let forza = CGFloat(min(max(valore, 0), 1))
        guard forza > 0.001 else { return immagine }
        let pieni = guadagniCalore
        return RicetteFiltriMac.matrice(immagine, r: 1 + (pieni.r - 1) * forza, g: 1 + (pieni.g - 1) * forza,
                                        b: 1 + (pieni.b - 1) * forza)
    }

    // MARK: Regolazioni (RegolazioniBase in PipelineEffetti.swift)

    static func regolazioni(_ immagine: CIImage, luminosita: Double, contrasto: Double, saturazione: Double,
                            nitidezza: Double) -> CIImage {
        func limita(_ valore: Double) -> Double { valore.isFinite ? min(max(valore, -1), 1) : 0 }
        let luce = limita(luminosita)
        let contr = limita(contrasto)
        let satur = limita(saturazione)
        let nitid = limita(nitidezza)
        var risultato = immagine
        if luce != 0 || contr != 0 || satur != 0 {
            // CIColorControls: luminosità -1…1 (troppo forte: se ne usa un quarto), contrasto e saturazione attorno a 1.
            risultato = risultato.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: luce * 0.25,
                kCIInputContrastKey: 1 + contr * 0.5,
                kCIInputSaturationKey: 1 + satur
            ])
        }
        if nitid > 0 {
            // Solo sulla luminanza: niente aloni colorati. Fino a 0,8.
            risultato = risultato.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: nitid * 0.8])
        } else if nitid < 0 {
            // Negativa: un velo morbido, al massimo 1,5 pixel a 1080p.
            let raggio = -nitid * 1.5 * Double(max(immagine.extent.height, 1)) / 1080
            risultato = risultato.clampedToExtent().applyingGaussianBlur(sigma: raggio).cropped(to: immagine.extent)
        }
        return risultato
    }

    // MARK: Ritocco della pelle (EffettoPelle.swift, reso sicuro sul Mac)

    /// Oltre circa 1/25 di differenza dalla versione sfocata, misurata in sRGB (percettivo), è un dettaglio (occhi,
    /// sopracciglia, bocca, contorno del viso), non pelle: lì non si leviga. Prima la differenza si misurava in spazio
    /// lineare, dove nelle zone scure è minima: occhi e sopracciglia passavano per pelle e, con il raggio grande, il
    /// viso usciva sfocato (prova di Ledion).
    private static let sensibilitaBordi: CGFloat = 25
    /// Forza massima della levigatura: anche al massimo resta metà della grana vera.
    private static let forzaMassimaPelle: CGFloat = 0.5

    /// `volti`: i rettangoli dei volti in pixel dell'immagine. `leggero`: a forza dimezzata (la maschera dei dettagli
    /// resta: senza, il ritocco potrebbe sfocare occhi e bocca).
    static func pelle(_ immagine: CIImage, forza valore: Double, volti: [CGRect], leggero: Bool) -> CIImage {
        let forza = CGFloat(min(max(valore.isFinite ? valore : 0, 0), 1))
        let estensione = immagine.extent
        let rettangoli = volti.filter { $0.intersects(estensione) && $0.height > 8 }
        guard forza > 0.001, let altezzaMassima = rettangoli.map(\.height).max() else { return immagine }
        // La zona contiene per intero i dischi di `mascheraVolti` (raggio esterno 0,72 del lato): nessun taglio dritto.
        var zona = CGRect.null
        for rettangolo in rettangoli {
            let lato = max(rettangolo.width, rettangolo.height) * 0.75
            let centro = CGPoint(x: rettangolo.midX, y: rettangolo.midY - rettangolo.height * 0.04)
            zona = zona.union(CGRect(x: centro.x - lato, y: centro.y - lato, width: lato * 2, height: lato * 2))
        }
        zona = zona.intersection(estensione).integral
        guard !zona.isEmpty else { return immagine }

        // Raggio piccolo: dallo 0,25% allo 0,55% dell'altezza del volto (1-2 px per un volto di 400 px), mai oltre 3 px.
        // Toglie la grana della pelle, non i lineamenti (prima arrivava all'1,8%: 7 px).
        let sigma = min(max(1, altezzaMassima * (0.0025 + 0.003 * forza)), 3)
        let sfocata = immagine.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: zona)

        let prodotto = CIFilter.multiplyCompositing()
        prodotto.inputImage = mascheraVolti(rettangoli, zona: zona)
        prodotto.backgroundImage = mascheraPelle(originale: immagine, sfocata: sfocata, zona: zona, raggio: sigma)
        let senzaMaschera = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: zona)
        let maschera = RicetteFiltriMac.scala(prodotto.outputImage ?? senzaMaschera,
                                              per: forzaMassimaPelle * (leggero ? 0.5 : 1) * forza)
        let levigata = RicetteFiltriMac.mescola(sopra: sfocata, sotto: immagine.cropped(to: zona), maschera: maschera)
            .cropped(to: zona)
        return levigata.composited(over: immagine)
    }

    /// Un disco morbido per volto, centrato appena sotto il centro del rettangolo (guance e bocca).
    private static func mascheraVolti(_ rettangoli: [CGRect], zona: CGRect) -> CIImage {
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

    /// Bianco dove l'originale differisce poco dalla versione sfocata (pelle), nero sui dettagli veri. La differenza si
    /// misura in sRGB (le zone scure contano quanto le chiare) e il nero si allarga di `raggio` (minimo locale): anche
    /// i pixel accanto a un dettaglio restano com'erano.
    private static func mascheraPelle(originale: CIImage, sfocata: CIImage, zona: CGRect, raggio: CGFloat) -> CIImage {
        let differenza = CIFilter.colorAbsoluteDifference()
        differenza.inputImage = originale.cropped(to: zona).applyingFilter("CILinearToSRGBToneCurve")
        differenza.inputImage2 = sfocata.applyingFilter("CILinearToSRGBToneCurve")
        guard let assoluta = differenza.outputImage else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: zona)
        }
        let peso = -sensibilitaBordi / 3
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
        let pelle = (limiti.outputImage ?? assoluta).cropped(to: zona)
        let minimo = CIFilter.morphologyMinimum()
        minimo.inputImage = pelle.clampedToExtent()
        minimo.radius = Float(max(1, raggio.rounded()))
        return (minimo.outputImage ?? pelle).cropped(to: zona)
    }

    // MARK: Luce sul volto (EffettoLuceVolto.swift, la parte «schiarisci il viso»)

    /// Un'ellisse morbida attorno al volto (`volto` in pixel, già levigato), schiarita con una curva di tono che
    /// solleva ombre e mezzitoni (circa +0,4 EV) e lascia il bianco al suo posto. `presenza` 0…1 per la dissolvenza.
    static func luceVolto(_ immagine: CIImage, volto: CGRect, presenza: CGFloat) -> CIImage {
        let estensione = immagine.extent
        guard presenza > 0.01 else { return immagine }
        let centro = CGPoint(x: volto.midX, y: volto.midY - volto.height * 0.08)
        let semiasseX = volto.width * 1.0
        let semiasseY = volto.height * 1.25
        let zona = CGRect(x: centro.x - semiasseX, y: centro.y - semiasseY, width: semiasseX * 2, height: semiasseY * 2)
            .intersection(estensione).integral
        guard !zona.isEmpty, semiasseX > 0, semiasseY > 0 else { return immagine }
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
        let maschera = RicetteFiltriMac.scala(ellisse, per: presenza)
        let originale = immagine.cropped(to: zona)
        let illuminata = RicetteFiltriMac.percettivo(originale) {
            RicetteFiltriMac.curva($0, [(0, 0), (0.25, 0.29), (0.5, 0.565), (0.75, 0.81), (1, 1)])
        }
        let risultato = RicetteFiltriMac.mescola(sopra: illuminata, sotto: originale, maschera: maschera).cropped(to: zona)
        return risultato.composited(over: immagine)
    }

    // MARK: Sfondo (EffettoSfondo.swift)

    /// Raggio (sigma) della sfocatura a 1080p per un'intensità 0…1: 32 × intensità^1,6, come sull'iPhone.
    /// Poco (0,25) ≈ 3,5 px, un bokeh leggero in cui lo sfondo si riconosce; Medio (0,55) ≈ 12 px; Tanto (1) = 32 px.
    static func sigmaSfocatura(_ intensita: Double) -> Double {
        let limitata = min(max(intensita, 0), 1)
        return max(1.5, 32 * pow(limitata, 1.6))
    }

    /// Raggio fisso della sfocatura nell'immagine ridotta: l'intensità cambia solo la riduzione.
    static let sigmaPiccola: CGFloat = 2.5

    // MARK: Bordo della persona: guided filter (He, Sun, Tang)

    // Come Meet e Teams: la maschera piccola di Vision si porta alla misura del video seguendo i bordi veri
    // dell'immagine. Il guided filter (He, Sun, Tang, «Guided Image Filtering», PAMI 2013) cerca, in ogni finestra, la
    // retta q = a·I + b che meglio approssima la maschera p a partire dalla luma I del fotogramma:
    //   a = cov(I, p) / (var(I) + ε),  b = media(p) − a·media(I),  q = media(a)·I + media(b).
    // Dove l'immagine ha un bordo (var(I) grande rispetto a ε) la maschera lo segue; dove è piatta (var(I) ≪ ε) a ≈ 0 e
    // la maschera resta quella di Vision, solo smussata: niente «colate» tra due bianchi vicini (maglietta e cuscino).
    // Versione «fast» (He e Sun 2015): a e b si calcolano a `latoGuida`, si ingrandiscono e q si calcola con la luma
    // a piena risoluzione. Solo filtri di sistema (niente kernel Metal propri): le operazioni tra due immagini passano da
    // `somma` (fusione con maschera costante a metà) e `CIMultiplyCompositing`, l'unica divisione da `CIDivideBlendMode`
    // con i valori tenuti tra 0 e 1. Varianza e covarianza come media di (I − Ī)(p − p̄) con Ī e p̄ locali: in mezza
    // precisione (il formato di lavoro del contesto) la formula media(I²) − Ī² perderebbe tutte le cifre.

    /// Lato corto a cui si calcolano a e b: 540 per il 1080p (un quarto dei pixel).
    static let latoGuida: CGFloat = 540
    /// Raggio delle medie locali (sigma della gaussiana) alla misura della guida: circa 8 px a 1080p.
    static let raggioGuida: CGFloat = 4
    /// ε sulla luma percettiva 0…1: sotto circa il 6% di contrasto locale (√0,004) la maschera non segue l'immagine.
    static let epsilonGuida: CGFloat = 0.004
    /// Tetto di |a| che tiene la divisione tra 0 e 1. Con p tra 0 e 1, |a| ≤ 1 / (2√ε) ≈ 7,9: 8 non taglia mai.
    private static let limiteA: CGFloat = 8
    /// Centro della soglia del bordo: a metà. La zona grigia di Vision (0,2-0,5, dove è incerta: un cuscino chiaro
    /// accanto alla persona) va con lo sfondo; capelli e spalle li tiene il guided filter, non una soglia bassa.
    static let centroSoglia: CGFloat = 0.5

    /// La maschera (piccola, già filtrata nel tempo, grigia) alla misura dell'immagine, con il bordo rifinito.
    /// - `leggero` falso: guided filter guidato dalla luma del video (vedi sopra), poi soglia morbida.
    /// - `leggero`: ingrandimento bilineare a metà risoluzione, piuma 1,5 px e poi la soglia.
    /// `morbidezza`: larghezza della soglia (vedi `sogliaMorbida`).
    static func mascheraRifinita(_ bassa: CIImage, immagine: CIImage, morbidezza: CGFloat,
                                 centro: CGFloat = centroSoglia, leggero: Bool) -> CIImage {
        let estensione = immagine.extent
        let misuraBassa = bassa.extent
        guard misuraBassa.width > 0, misuraBassa.height > 0, estensione.width > 0, estensione.height > 0,
              !misuraBassa.isInfinite, !estensione.isInfinite else {
            return bassa
        }
        let dallaBassa = CGAffineTransform(translationX: -misuraBassa.minX, y: -misuraBassa.minY)
        if leggero {
            let misuraMezza = CGRect(x: 0, y: 0, width: max((estensione.width / 2).rounded(.down), 1),
                                     height: max((estensione.height / 2).rounded(.down), 1))
            let mezza = bassa
                .transformed(by: dallaBassa.concatenating(CGAffineTransform(scaleX: misuraMezza.width / misuraBassa.width,
                                                                            y: misuraMezza.height / misuraBassa.height)))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 1.5)
                .cropped(to: misuraMezza)
            let alFotogramma = CGAffineTransform(scaleX: estensione.width / misuraMezza.width,
                                                 y: estensione.height / misuraMezza.height)
                .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
            return sogliaMorbida(mezza, larghezza: morbidezza, centro: centro)
                .transformed(by: alFotogramma)
                .clampedToExtent()
                .cropped(to: estensione)
        }

        // Tutto con l'origine in (0, 0); alla fine si torna all'origine dell'immagine.
        let piena = CGRect(origin: .zero, size: estensione.size)
        let allOrigine = CGAffineTransform(translationX: -estensione.minX, y: -estensione.minY)
        let riduzione = min(1, latoGuida / min(piena.width, piena.height))
        let misuraGuida = CGRect(x: 0, y: 0, width: max((piena.width * riduzione).rounded(), 1),
                                 height: max((piena.height * riduzione).rounded(), 1))
        let versoGuida = CGAffineTransform(scaleX: misuraGuida.width / piena.width, y: misuraGuida.height / piena.height)
        // La guida: luma percettiva, calcolata sul fotogramma già nello spazio di lavoro (lineare) e riportata in sRGB.
        let luma = lumaGuida(immagine.transformed(by: allOrigine)).cropped(to: piena)
        let guida = luma.transformed(by: versoGuida).clampedToExtent().cropped(to: misuraGuida)
        // p: la maschera di Vision ingrandita in modo bilineare alla misura della guida.
        let p = grigio(bassa)
            .transformed(by: dallaBassa.concatenating(CGAffineTransform(scaleX: misuraGuida.width / misuraBassa.width,
                                                                        y: misuraGuida.height / misuraBassa.height)))
            .clampedToExtent()
            .cropped(to: misuraGuida)
        // media(a), media(b) alla misura piena (bilineare), poi q = media(a)·I + media(b) con la luma piena.
        let coefficienti = coefficientiGuida(guida: guida, maschera: p, misura: misuraGuida)
            .transformed(by: versoGuida.inverted())
            .clampedToExtent()
            .cropped(to: piena)
        let uno = CIVector(x: 1, y: 0, z: 0, w: 0)
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let lumaEUno = canali(luma, r: uno, g: zero, b: zero, scostamento: CIVector(x: 0, y: 1, z: 0, w: 1))
        let somme = CIVector(x: 1, y: 1, z: 0, w: 0)
        let q = canali(moltiplica(coefficienti, lumaEUno), r: somme, g: somme, b: somme)
        return sogliaMorbida(q, larghezza: morbidezza, centro: centro)
            .cropped(to: piena)
            .transformed(by: allOrigine.inverted())
            .cropped(to: estensione)
    }

    /// La luma percettiva (sRGB, pesi Rec. 709) tra 0 e 1 in tutti i canali, alfa 1: la guida del bordo. In lineare le
    /// differenze tra scuri (capelli su un fondo scuro) sarebbero quasi nulle.
    static func lumaGuida(_ immagine: CIImage) -> CIImage {
        let pesi = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        let luma = canali(immagine.applyingFilter("CILinearToSRGBToneCurve"), r: pesi, g: pesi, b: pesi)
        let limiti = CIFilter.colorClamp()
        limiti.inputImage = luma
        limiti.minComponents = CIVector(x: 0, y: 0, z: 0, w: 1)
        limiti.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return limiti.outputImage ?? luma
    }

    /// media(a) nel rosso e media(b) nel verde, alla misura della guida. `guida` e `maschera` grigie, alfa 1.
    private static func coefficientiGuida(guida: CIImage, maschera: CIImage, misura: CGRect) -> CIImage {
        func media(_ immagine: CIImage) -> CIImage {
            immagine.clampedToExtent().applyingGaussianBlur(sigma: Double(raggioGuida)).cropped(to: misura)
        }
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let primo = CIVector(x: 1, y: 0, z: 0, w: 0)
        let secondo = CIVector(x: 0, y: 1, z: 0, w: 0)
        // (I, p): la luma nel rosso, la maschera nel verde.
        let insieme = somma(canali(guida, r: primo, g: zero, b: zero), canali(maschera, r: zero, g: primo, b: zero),
                            misura: misura)
        let medie = media(insieme)                                                     // (Ī, p̄)
        let scarti = somma(insieme, canali(medie, r: CIVector(x: -1, y: 0, z: 0, w: 0),
                                           g: CIVector(x: 0, y: -1, z: 0, w: 0), b: zero), misura: misura)  // (I − Ī, p − p̄)
        let prodotti = moltiplica(scarti, canali(scarti, r: primo, g: primo, b: zero))   // ((I − Ī)², (I − Ī)(p − p̄))
        let momenti = media(prodotti)                                                  // (var, cov)
        // r = (a + k) / 2k = (cov + k·(var + ε)) / (2k·(var + ε)), sempre tra 0 e 1 (k = `limiteA`).
        let k = limiteA
        let eps = epsilonGuida
        let rigaNumeratore = CIVector(x: k, y: 1, z: 0, w: 0)
        let numeratore = canali(momenti, r: rigaNumeratore, g: rigaNumeratore, b: rigaNumeratore,
                                scostamento: CIVector(x: k * eps, y: k * eps, z: k * eps, w: 1))
        let rigaDenominatore = CIVector(x: 2 * k, y: 0, z: 0, w: 0)
        let denominatore = canali(momenti, r: rigaDenominatore, g: rigaDenominatore, b: rigaDenominatore,
                                  scostamento: CIVector(x: 2 * k * eps, y: 2 * k * eps, z: 2 * k * eps, w: 1))
        // `CIDivideBlendMode`: risultato = sfondo (backgroundImage) / sopra (inputImage).
        let divisione = CIFilter.divideBlendMode()
        divisione.inputImage = denominatore
        divisione.backgroundImage = numeratore
        let rapporto = lineare(divisione.outputImage ?? numeratore, pendenza: 1, scostamento: 0)
        // (a, a, 1) × (1, Ī, p̄) = (a, a·Ī, p̄), poi (a, b = p̄ − a·Ī).
        let aDoppio = CIVector(x: 2 * k, y: 0, z: 0, w: 0)
        let conA = canali(rapporto, r: aDoppio, g: aDoppio, b: zero, scostamento: CIVector(x: -k, y: -k, z: 1, w: 1))
        let conMedie = canali(medie, r: zero, g: primo, b: secondo, scostamento: CIVector(x: 1, y: 0, z: 0, w: 1))
        let coefficienti = canali(moltiplica(conA, conMedie), r: primo, g: CIVector(x: 0, y: -1, z: 1, w: 0), b: zero)
        return media(coefficienti)
    }

    /// `CIColorMatrix` con le righe date per rosso, verde e blu, alfa = `scostamento.w` (di solito 1).
    static func canali(_ immagine: CIImage, r: CIVector, g: CIVector, b: CIVector,
                       scostamento: CIVector = CIVector(x: 0, y: 0, z: 0, w: 1)) -> CIImage {
        let filtro = CIFilter.colorMatrix()
        filtro.inputImage = immagine
        filtro.rVector = r
        filtro.gVector = g
        filtro.bVector = b
        filtro.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filtro.biasVector = scostamento
        return filtro.outputImage ?? immagine
    }

    /// Mezzo in tutti i canali, alfa 1, come valore di lavoro (dal nero, che è 0 in ogni spazio di colore).
    private static let meta = canali(CIImage(color: CIColor(red: 0, green: 0, blue: 0)),
                                     r: CIVector(x: 0, y: 0, z: 0, w: 0), g: CIVector(x: 0, y: 0, z: 0, w: 0),
                                     b: CIVector(x: 0, y: 0, z: 0, w: 0),
                                     scostamento: CIVector(x: 0.5, y: 0.5, z: 0.5, w: 1))

    /// a + b canale per canale, alfa 1, anche con valori negativi o sopra 1: (2a)·½ + (2b)·½ con `CIBlendWithMask` e
    /// una maschera costante a metà (i metodi di fusione «somma» e «differenza» potrebbero tagliare a 0 o a 1).
    private static func somma(_ a: CIImage, _ b: CIImage, misura: CGRect) -> CIImage {
        let doppio = CIVector(x: 2, y: 0, z: 0, w: 0)
        func per2(_ immagine: CIImage) -> CIImage {
            canali(immagine, r: doppio, g: CIVector(x: 0, y: 2, z: 0, w: 0), b: CIVector(x: 0, y: 0, z: 2, w: 0))
        }
        return RicetteFiltriMac.mescola(sopra: per2(a), sotto: per2(b), maschera: meta.cropped(to: misura))
            .cropped(to: misura)
    }

    /// a × b canale per canale (con alfa 1 entrambe).
    static func moltiplica(_ a: CIImage, _ b: CIImage) -> CIImage {
        let filtro = CIFilter.multiplyCompositing()
        filtro.inputImage = a
        filtro.backgroundImage = b
        return filtro.outputImage ?? a
    }

    /// Soglia morbida attorno a `centro`, larga `larghezza`: t = (valore − (centro − larghezza/2)) / larghezza
    /// tra 0 e 1, poi smoothstep 3t² − 2t³.
    static func sogliaMorbida(_ maschera: CIImage, larghezza: CGFloat, centro: CGFloat = centroSoglia) -> CIImage {
        let ampiezza = min(max(larghezza, 0.05), 1)
        let pendenza = 1 / ampiezza
        let rampa = lineare(maschera, pendenza: pendenza, scostamento: -(centro - ampiezza / 2) * pendenza)
        let curva = CIFilter.colorPolynomial()
        curva.inputImage = rampa
        let smoothstep = CIVector(x: 0, y: 0, z: 3, w: -2)
        curva.redCoefficients = smoothstep
        curva.greenCoefficients = smoothstep
        curva.blueCoefficients = smoothstep
        curva.alphaCoefficients = CIVector(x: 1, y: 0, z: 0, w: 0)
        return curva.outputImage ?? rampa
    }

    /// Il primo canale copiato negli altri, alfa a 1: la maschera a un canale diventa grigia comunque la si legga.
    static func grigio(_ immagine: CIImage) -> CIImage {
        let primo = CIVector(x: 1, y: 0, z: 0, w: 0)
        let filtro = CIFilter.colorMatrix()
        filtro.inputImage = immagine
        filtro.rVector = primo
        filtro.gVector = primo
        filtro.bVector = primo
        filtro.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filtro.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filtro.outputImage ?? immagine
    }

    /// valore × pendenza + scostamento, tra 0 e `massimo`; alfa a 1.
    static func lineare(_ maschera: CIImage, pendenza: CGFloat, scostamento: CGFloat, massimo: CGFloat = 1) -> CIImage {
        let filtro = CIFilter.colorMatrix()
        filtro.inputImage = maschera
        filtro.rVector = CIVector(x: pendenza, y: 0, z: 0, w: 0)
        filtro.gVector = CIVector(x: 0, y: pendenza, z: 0, w: 0)
        filtro.bVector = CIVector(x: 0, y: 0, z: pendenza, w: 0)
        filtro.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        filtro.biasVector = CIVector(x: scostamento, y: scostamento, z: scostamento, w: 1)
        let limiti = CIFilter.colorClamp()
        limiti.inputImage = filtro.outputImage ?? maschera
        limiti.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        limiti.maxComponents = CIVector(x: massimo, y: massimo, z: massimo, w: 1)
        return limiti.outputImage ?? maschera
    }

    /// Lo sfondo sfocato senza la persona (sfocatura normalizzata, niente alone), alla misura dell'immagine.
    /// La persona (allargata) esce dall'immagine come alfa, si sfoca in piccolo con un raggio fisso e si divide per
    /// l'alfa sfocato: ogni punto prende colore solo dallo sfondo vicino. `bassa`: la maschera piccola filtrata.
    static func sfocataSenzaAlone(_ immagine: CIImage, bassa: CIImage, intensita: Double, fine: Bool) -> CIImage {
        let estensione = immagine.extent
        let misuraBassa = bassa.extent
        guard misuraBassa.width > 0, misuraBassa.height > 0, estensione.width > 0, estensione.height > 0 else {
            return immagine
        }
        let riferimento = min(estensione.width, estensione.height) / 1080
        let sigma = CGFloat(sigmaSfocatura(intensita)) * riferimento
        let scala = min(1, sigmaPiccola / max(sigma, 0.1))
        let riduzione = CGAffineTransform(scaleX: scala, y: scala)
        let piccola = fine && scala < 1
            ? immagine.transformed(by: riduzione, highQualityDownsample: true)
            : immagine.transformed(by: riduzione)
        let misura = piccola.extent
        let allaPiccola = CGAffineTransform(scaleX: estensione.width / misuraBassa.width,
                                            y: estensione.height / misuraBassa.height)
            .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
            .concatenating(riduzione)
        let persona = lineare(bassa.transformed(by: allaPiccola), pendenza: 2, scostamento: -0.3, massimo: 0.99)
            .clampedToExtent()
            .cropped(to: misura)
        let senzaPersona = RicetteFiltriMac.mescola(sopra: CIImage(color: CIColor.clear).cropped(to: misura),
                                                    sotto: piccola, maschera: persona)
        let sfocata = senzaPersona
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(sigmaPiccola))
            .cropped(to: misura)
            .unpremultiplyingAlpha()
            .settingAlphaOne(in: misura)
        let ritorno = CGAffineTransform(translationX: -misura.minX, y: -misura.minY)
            .concatenating(CGAffineTransform(scaleX: estensione.width / max(misura.width, 1),
                                             y: estensione.height / max(misura.height, 1)))
            .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
        return sfocata.transformed(by: ritorno).clampedToExtent().cropped(to: estensione)
    }

    /// Il fondo di `Tema` (verde scuro), quando non c'è ancora l'immagine dello sfondo.
    static let coloreFondo = CIColor(cgColor: Tema.fondo.resolve(in: EnvironmentValues()).cgColor)

    /// Un'immagine a riempire (come «aspect fill»), centrata, alla misura `larghezza`×`altezza` (CGImage in sRGB).
    static func sfondoDisegnato(_ immagine: CGImage, larghezza: Int, altezza: Int) -> CGImage? {
        guard larghezza > 0, altezza > 0, immagine.width > 0, immagine.height > 0,
              let spazio = CGColorSpace(name: CGColorSpace.sRGB),
              let contesto = CGContext(data: nil, width: larghezza, height: altezza, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: spazio, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let misura = CGSize(width: larghezza, height: altezza)
        let origine = CGSize(width: immagine.width, height: immagine.height)
        let scala = max(misura.width / origine.width, misura.height / origine.height)
        let disegnata = CGSize(width: origine.width * scala, height: origine.height * scala)
        contesto.interpolationQuality = .high
        contesto.draw(immagine, in: CGRect(x: (misura.width - disegnata.width) / 2, y: (misura.height - disegnata.height) / 2,
                                           width: disegnata.width, height: disegnata.height))
        return contesto.makeImage()
    }

    // MARK: Scritta e logo (EffettoScritta.swift)

    /// Margini di sicurezza: 4,5% dei lati in orizzontale, 6% in verticale (la barra delle app di chiamata).
    private static func margini(_ video: CGSize) -> CGSize {
        CGSize(width: (video.width * 0.045).rounded(), height: (video.height * 0.06).rounded())
    }

    private static func colore(_ colore: Color, alfa: CGFloat = 1) -> CGColor {
        colore.resolve(in: EnvironmentValues()).cgColor.copy(alpha: alfa) ?? CGColor(gray: 0, alpha: alfa)
    }

    /// Il sottopancia (nome e ruolo) già al suo posto nel video, in basso a sinistra (origine in basso, come Core
    /// Image): barra scura arrotondata, filo dell'accento a sinistra, nome in Barlow Condensed Bold e ruolo in maiuscolo.
    /// Misure in proporzione al lato corto del video, come sull'iPhone.
    static func sottopancia(nome: String, ruolo: String, video: CGSize) -> CIImage? {
        let unita = min(video.width, video.height) / 1080
        guard unita > 0 else { return nil }
        let margini = Self.margini(video)
        let carattereNome = CTFontCreateWithName("BarlowCondensed-Bold" as CFString, 52 * unita, nil)
        let carattereRuolo = CTFontCreateWithName("BarlowCondensed-SemiBold" as CFString, 26 * unita, nil)
        let attributiNome: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): carattereNome,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): colore(Tema.testo)
        ]
        let attributiRuolo: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): carattereRuolo,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): colore(Tema.accentoChiaro),
            NSAttributedString.Key(rawValue: kCTKernAttributeName as String): 1.6 * unita
        ]
        let filo = (6 * unita).rounded()
        let orizzontale = (26 * unita).rounded()
        let verticale = (14 * unita).rounded()
        let spazioRighe = (2 * unita).rounded()
        // Al massimo il 60% della larghezza: un nome lunghissimo si tronca con «…».
        let larghezzaMassima = Double(max(video.width * 0.6 - filo - orizzontale * 2, 40 * unita))
        let rigaNome = riga(nome, attributi: attributiNome, larghezzaMassima: larghezzaMassima)
        let rigaRuolo = ruolo.isEmpty ? nil : riga(ruolo.uppercased(), attributi: attributiRuolo, larghezzaMassima: larghezzaMassima)
        let altezzaNome = ceil(CTFontGetAscent(carattereNome) + CTFontGetDescent(carattereNome))
        let altezzaRuolo = rigaRuolo == nil ? 0 : ceil(CTFontGetAscent(carattereRuolo) + CTFontGetDescent(carattereRuolo))
        let larghezzaTesto = ceil(max(rigaNome.larghezza, rigaRuolo?.larghezza ?? 0))
        let barra = CGSize(width: filo + orizzontale * 2 + larghezzaTesto,
                           height: verticale * 2 + altezzaNome + (rigaRuolo == nil ? 0 : spazioRighe + altezzaRuolo))
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB),
              let contesto = CGContext(data: nil, width: Int(barra.width), height: Int(barra.height), bitsPerComponent: 8,
                                       bytesPerRow: 0, space: spazio,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let forma = CGPath(roundedRect: CGRect(origin: .zero, size: barra), cornerWidth: 14 * unita,
                           cornerHeight: 14 * unita, transform: nil)
        contesto.addPath(forma)
        contesto.setFillColor(colore(Tema.fondo, alfa: 0.8))
        contesto.fillPath()
        contesto.saveGState()
        contesto.addPath(forma)
        contesto.clip()
        contesto.setFillColor(colore(Tema.accento))
        contesto.fill(CGRect(x: 0, y: 0, width: filo, height: barra.height))
        contesto.restoreGState()
        // Origine in basso: il nome in alto nella barra, il ruolo sotto.
        let x = filo + orizzontale
        contesto.textPosition = CGPoint(x: x, y: barra.height - verticale - CTFontGetAscent(carattereNome))
        CTLineDraw(rigaNome.linea, contesto)
        if let rigaRuolo {
            contesto.textPosition = CGPoint(x: x, y: verticale + CTFontGetDescent(carattereRuolo))
            CTLineDraw(rigaRuolo.linea, contesto)
        }
        guard let immagine = contesto.makeImage() else { return nil }
        return CIImage(cgImage: immagine).transformed(by: CGAffineTransform(translationX: margini.width, y: margini.height))
    }

    /// Una riga di testo, troncata con «…» oltre `larghezzaMassima`.
    private static func riga(_ testo: String, attributi: [NSAttributedString.Key: Any],
                             larghezzaMassima: Double) -> (linea: CTLine, larghezza: CGFloat) {
        let linea = CTLineCreateWithAttributedString(NSAttributedString(string: testo, attributes: attributi))
        var larghezza = CGFloat(CTLineGetTypographicBounds(linea, nil, nil, nil))
        guard Double(larghezza) > larghezzaMassima else { return (linea, larghezza) }
        let puntini = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributi))
        guard let troncata = CTLineCreateTruncatedLine(linea, larghezzaMassima, .end, puntini) else {
            return (linea, larghezza)
        }
        larghezza = CGFloat(CTLineGetTypographicBounds(troncata, nil, nil, nil))
        return (troncata, larghezza)
    }

    /// Il logo in alto a destra, al massimo il 9% dell'altezza e il 22% della larghezza, con la sua trasparenza.
    static func logo(_ logo: CGImage, video: CGSize) -> CIImage? {
        let origine = CGSize(width: logo.width, height: logo.height)
        guard origine.width > 0, origine.height > 0, video.width > 0, video.height > 0 else { return nil }
        let margini = Self.margini(video)
        let scala = min(min(video.width, video.height) * 0.09 / origine.height, video.width * 0.22 / origine.width)
        let misura = CGSize(width: (origine.width * scala).rounded(), height: (origine.height * scala).rounded())
        guard misura.width >= 1, misura.height >= 1,
              let spazio = CGColorSpace(name: CGColorSpace.sRGB),
              let contesto = CGContext(data: nil, width: Int(misura.width), height: Int(misura.height), bitsPerComponent: 8,
                                       bytesPerRow: 0, space: spazio,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        contesto.interpolationQuality = .high
        contesto.draw(logo, in: CGRect(origin: .zero, size: misura))
        guard let immagine = contesto.makeImage() else { return nil }
        return CIImage(cgImage: immagine).transformed(by: CGAffineTransform(
            translationX: video.width - margini.width - misura.width,
            y: video.height - margini.height - misura.height))
    }
}
