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

    // MARK: Ritocco della pelle (Qualità 11, come RicettePersona.Pelle su Windows)

    /// Il ritocco della pelle, come il «beauty» delle app di webcam ma senza effetto plastica. Gli stessi passi e numeri
    /// di Windows (`RegolePelle`), con i filtri di sistema di Core Image (niente kernel Metal propri), in sRGB:
    /// 1. un filtro guidato della luma con sé stessa (He, Sun e Tang, i conti di `coefficientiGuida`), che conserva i
    ///    bordi: a = var / (var + ε), b = (1 − a)·media, poi media(a)·Y + media(b); le medie su una griglia a metà (a un
    ///    quarto con `leggero`) della zona dei volti, con un raggio del 2% dell'altezza del volto;
    /// 2. il ritorno della grana fine (la luma meno la sua gaussiana di 0,7 px) dove il filtro ha levigato;
    /// 3. solo sulla pelle: il peso dal colore (tabella 3D di `RegolePelle.pesoColore`) spento vicino ai bordi veri
    ///    (varianza locale), un'ellisse attorno a ogni volto e le zone protette (occhi e bocca dai punti del volto di
    ///    Vision);
    /// 4. la luma cambia con la stessa differenza su rosso, verde e blu; il colore va verso quello medio della pelle
    ///    attorno (media pesata con il colore), a luma ferma: i rossori si attenuano, la tinta della pelle resta.
    /// `volti` e `protette`: rettangoli in pixel dell'immagine. `leggero`: livelli bassi, griglia a un quarto, niente
    /// grana e tre quarti della forza. `verificato`: i conti di `verificaAritmetica` tornano (senza, niente ritocco).
    static func pelle(_ immagine: CIImage, forza valore: Double, volti: [CGRect], protette: [CGRect], leggero: Bool,
                      verificato: Bool) -> CIImage {
        var forza = CGFloat(min(max(valore.isFinite ? valore : 0, 0), 1))
        let estensione = immagine.extent
        let rettangoli = volti.filter { $0.intersects(estensione) && $0.height > 8 }
        guard verificato, forza > 0.001, let altezzaMassima = rettangoli.map(\.height).max() else { return immagine }
        let eps = RegolePelle.epsilon(forza)
        if leggero { forza *= RegolePelle.forzaLeggero }
        // Le ellissi dei volti (centro 4% più in basso: origine in basso, quindi − 0,04·altezza).
        let ellissi = rettangoli.map { r in
            (centro: CGPoint(x: r.midX, y: r.midY - r.height * 0.04),
             sx: r.width / 2 * RegolePelle.ellisseEsterna, sy: r.height / 2 * RegolePelle.ellisseEsterna)
        }
        var zona = CGRect.null
        for e in ellissi {
            zona = zona.union(CGRect(x: e.centro.x - e.sx, y: e.centro.y - e.sy, width: e.sx * 2, height: e.sy * 2))
        }
        zona = zona.intersection(estensione).integral
        let passo: CGFloat = leggero ? 4 : 2
        guard !zona.isEmpty, zona.width >= passo * 4, zona.height >= passo * 4 else { return immagine }

        // Tutto con l'origine della zona in (0, 0); alla fine si torna al posto.
        let allOrigine = CGAffineTransform(translationX: -zona.minX, y: -zona.minY)
        let piena = CGRect(origin: .zero, size: zona.size)
        let sRGB = immagine.applyingFilter("CILinearToSRGBToneCurve").transformed(by: allOrigine).cropped(to: piena)
        let luma = lumaSRGB(sRGB).cropped(to: piena)
        // La griglia: la zona ridotta di `passo` (prima una gaussiana di mezzo passo, come la media di Windows).
        let misuraGriglia = CGRect(x: 0, y: 0, width: (piena.width / passo).rounded(.down),
                                   height: (piena.height / passo).rounded(.down))
        let versoGriglia = CGAffineTransform(scaleX: misuraGriglia.width / piena.width, y: misuraGriglia.height / piena.height)
        func inGriglia(_ immagine: CIImage) -> CIImage {
            immagine.clampedToExtent().applyingGaussianBlur(sigma: Double(passo / 2)).transformed(by: versoGriglia)
                .cropped(to: misuraGriglia)
        }
        func inPiena(_ immagine: CIImage) -> CIImage {
            immagine.transformed(by: versoGriglia.inverted()).clampedToExtent().cropped(to: piena)
        }
        let lumaGriglia = inGriglia(luma)
        let coloreGriglia = inGriglia(sRGB)
        let raggio = max(1, Int((altezzaMassima * RegolePelle.raggioVolto / passo).rounded()))
        let sigma = RegolePelle.sigma(raggio: raggio)

        // 1. Il filtro guidato: (media(a), media(b)) alla misura piena; Ys = media(a)·(Y − 0,5) + media(b).
        let coefficienti = inPiena(coefficientiGuida(guida: lumaGriglia, maschera: lumaGriglia, misura: misuraGriglia,
                                                     sigma: sigma, eps: eps))
        let uno = CIVector(x: 1, y: 0, z: 0, w: 0)
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let lumaEUno = canali(luma, r: uno, g: zero, b: zero, scostamento: CIVector(x: -0.5, y: 1, z: 0, w: 1))
        let somme = CIVector(x: 1, y: 1, z: 0, w: 0)
        let levigata = canali(moltiplica(coefficienti, lumaEUno), r: somme, g: somme, b: somme)
        let meno = CIVector(x: -1, y: 0, z: 0, w: 0)
        var differenza = somma(levigata, canali(luma, r: meno, g: meno, b: meno), misura: piena)   // Ys − Y
        // 2. La grana fine, dove il filtro ha levigato: ritorno · (1 − media(a)) · (Y − gaussiana(Y)).
        if !leggero {
            let sfocata = luma.clampedToExtent().applyingGaussianBlur(sigma: 0.7).cropped(to: piena)
            let grana = somma(luma, canali(sfocata, r: meno, g: meno, b: meno), misura: piena)
            let g = RegolePelle.ritornoGrana
            let rigaLevigato = CIVector(x: -g, y: 0, z: 0, w: 0)
            let levigato = canali(coefficienti, r: rigaLevigato, g: rigaLevigato, b: rigaLevigato,
                                  scostamento: CIVector(x: g, y: g, z: g, w: 1))
            differenza = somma(differenza, moltiplica(levigato, grana), misura: piena)
        }

        // 3. Il peso della pelle sulla griglia: colore × lontano dai bordi, appena ammorbidito; poi alla misura piena.
        let pesoColore = applicaCubo(coloreGriglia, cuboPelle, lato: latoCuboPelle).cropped(to: misuraGriglia)
        let bordo = pesoBordo(varianzaLocale(lumaGriglia, misura: misuraGriglia, sigma: sigma))
        let pesoPelle = inPiena(moltiplica(pesoColore, bordo).clampedToExtent()
            .applyingGaussianBlur(sigma: Double(RegolePelle.sigma(raggio: 1))).cropped(to: misuraGriglia))

        // 4. Il colore medio della pelle attorno: media(peso · (c + ½)) / media(peso), con un piccolo peso neutro
        // (0,01) che tiene la divisione tra 0 e 1. c = (R − Y, B − Y) in rosso e blu.
        let rigaR = CIVector(x: 1 - 0.2126, y: -0.7152, z: -0.0722, w: 0)
        let rigaB = CIVector(x: -0.2126, y: -0.7152, z: 1 - 0.0722, w: 0)
        let colorePiu = lineare(canali(coloreGriglia, r: rigaR, g: zero, b: rigaB,
                                       scostamento: CIVector(x: 0.5, y: 0.5, z: 0.5, w: 1)), pendenza: 1, scostamento: 0)
        let sigmaColore = Double(RegolePelle.sigma(raggio: 2 * raggio))
        func mediaColore(_ immagine: CIImage, piu: CGFloat) -> CIImage {
            canali(immagine.clampedToExtent().applyingGaussianBlur(sigma: sigmaColore).cropped(to: misuraGriglia),
                   r: uno, g: CIVector(x: 0, y: 1, z: 0, w: 0), b: CIVector(x: 0, y: 0, z: 1, w: 0),
                   scostamento: CIVector(x: piu, y: piu, z: piu, w: 1))
        }
        let numeratore = mediaColore(moltiplica(colorePiu, pesoColore), piu: 0.005)
        let denominatore = mediaColore(pesoColore, piu: 0.01)
        let mediaPiu = inPiena(lineare(dividi(numeratore, per: denominatore), pendenza: 1, scostamento: 0))
        // k · (media − c) in rosso e blu, il verde che tiene ferma la luma.
        let cPiena = canali(sRGB, r: rigaR, g: zero, b: rigaB)
        let scarto = somma(canali(mediaPiu, r: uno, g: zero, b: CIVector(x: 0, y: 0, z: 1, w: 0),
                                  scostamento: CIVector(x: -0.5, y: 0, z: -0.5, w: 1)),
                           canali(cPiena, r: meno, g: zero, b: CIVector(x: 0, y: 0, z: -1, w: 0)), misura: piena)
        let k = RegolePelle.uniformaColore
        let spostaColore = canali(scarto, r: CIVector(x: k, y: 0, z: 0, w: 0),
                                  g: CIVector(x: -0.2126 * k / 0.7152, y: 0, z: -0.0722 * k / 0.7152, w: 0),
                                  b: CIVector(x: 0, y: 0, z: k, w: 0))

        // La pelle ritoccata in sRGB, poi mescolata con il peso: forza × ellisse × pelle × zone protette.
        let ritoccata = lineare(somma(sRGB, somma(differenza, spostaColore, misura: piena), misura: piena),
                                pendenza: 1, scostamento: 0)
        var peso = moltiplica(RicetteFiltriMac.scala(mascheraEllissi(ellissi, zona: zona).transformed(by: allOrigine)
                                                        .cropped(to: piena), per: forza), pesoPelle)
        if !protette.isEmpty {
            peso = moltiplica(peso, mascheraProtette(protette, zona: zona).transformed(by: allOrigine).cropped(to: piena))
        }
        return RicetteFiltriMac.mescola(sopra: ritoccata, sotto: sRGB, maschera: peso)
            .cropped(to: piena)
            .applyingFilter("CISRGBToneCurveToLinear")
            .transformed(by: allOrigine.inverted())
            .cropped(to: zona)
            .composited(over: immagine)
    }

    /// I numeri del ritocco della pelle e della luce sul volto: gli stessi di `RegolePelle` su Windows
    /// (Windows/WebcamLR.Effetti/Motore/RicettePersona.cs). Tecnica e misure: Documenti/Ritocco pelle - banco.md.
    enum RegolePelle {
        /// Raggio delle medie del filtro guidato, in parte dell'altezza del volto: 2%, 8 px per un volto di 400 px.
        static let raggioVolto: CGFloat = 0.02
        /// ε sulla luma sRGB 0…1: (0,015 + 0,025·forza)². Sotto √ε di deviazione locale (pori, macchie) si leviga.
        static func epsilon(_ forza: CGFloat) -> CGFloat {
            let s = 0.015 + 0.025 * min(max(forza, 0), 1)
            return s * s
        }
        /// Quanta grana fine torna sulla pelle levigata.
        static let ritornoGrana: CGFloat = 0.35
        /// Quanto il colore va verso quello medio della pelle attorno.
        static let uniformaColore: CGFloat = 0.5
        /// Ai livelli bassi (senza grana) tre quarti della forza.
        static let forzaLeggero: CGFloat = 0.75
        /// L'ellisse attorno a ogni volto, in parti dei semiassi del rettangolo: piena fino a 1, niente oltre 1,4.
        static let ellisseInterna: CGFloat = 1.0
        static let ellisseEsterna: CGFloat = 1.4
        /// Vicino ai bordi veri il ritocco si spegne: varianza locale della luma da 0,0016 a 0,0064 (smoothstep).
        static let bordoInizio: CGFloat = 0.0016
        static let bordoLarghezza: CGFloat = 0.0048
        /// La crominanza (Cb, Cr BT.601 in byte) ruotata verso la tinta della pelle (130°): pesi su R, G, B in byte.
        static let pesiU = (r: 0.49148, g: -0.10780, b: -0.38368)
        static let pesiV = (r: -0.19213, g: 0.52289, b: -0.33076)

        /// Quanto un colore sRGB (byte 0…255) è pelle, 0…1: tinta entro circa ±12° da quella della pelle (fino a ±24°)
        /// e almeno un po' di colore (il bianco degli occhi, i capelli neri e i grigi restano fuori).
        static func pesoColore(r: Double, g: Double, b: Double) -> Double {
            let u = pesiU.r * r + pesiU.g * g + pesiU.b * b
            let v = pesiV.r * r + pesiV.g * g + pesiV.b * b
            return min(max((0.45 * u - abs(v)) / 4, 0), 1) * min(max((u - 5) / 4, 0), 1)
        }

        /// La sigma della gaussiana con la stessa varianza della media quadrata di raggio `raggio` usata su Windows.
        static func sigma(raggio: Int) -> CGFloat {
            CGFloat((Double(raggio) * Double(raggio + 1) / 3).squareRoot())
        }

        /// L'ellisse della luce: centro più in basso del 6% dell'altezza, semiassi 0,8 della larghezza e 1 dell'altezza.
        static let luceCentro: CGFloat = 0.06
        static let luceLarghezza: CGFloat = 0.8
        static let luceAltezza: CGFloat = 1.0

        /// Il guadagno più alto per un pixel con il canale più alto a `massimo` (sRGB 0…1): quel canale arriva al più a
        /// metà strada da 254/255, quindi resta sotto il bianco pieno e il colore non cambia.
        static func tettoLuce(_ massimo: Double) -> Double {
            let limite = 254.0 / 255
            return massimo <= 0 || massimo >= limite ? 1 : (massimo + (limite - massimo) * 0.5) / massimo
        }

        /// La curva della luce (circa +0,4 EV su ombre e mezzitoni, il bianco al suo posto), cubica monotona di
        /// Fritsch–Carlson sui cinque punti, come `Colore.Curva` su Windows.
        static func curvaLuce(_ x: Double) -> Double {
            let px: [Double] = [0, 0.25, 0.5, 0.75, 1]
            let py: [Double] = [0, 0.29, 0.565, 0.81, 1]
            let n = px.count
            var d = [Double](repeating: 0, count: n - 1)
            for i in 0..<(n - 1) { d[i] = (py[i + 1] - py[i]) / (px[i + 1] - px[i]) }
            var m = [Double](repeating: 0, count: n)
            m[0] = d[0]
            m[n - 1] = d[n - 2]
            for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
            for i in 0..<(n - 1) {
                if d[i] == 0 {
                    m[i] = 0
                    m[i + 1] = 0
                    continue
                }
                let a = m[i] / d[i]
                let b = m[i + 1] / d[i]
                let s = a * a + b * b
                if s > 9 {
                    let t = 3 / s.squareRoot()
                    m[i] = t * a * d[i]
                    m[i + 1] = t * b * d[i]
                }
            }
            if x <= px[0] { return py[0] }
            if x >= px[n - 1] { return py[n - 1] }
            var i = 0
            while i < n - 2 && x > px[i + 1] { i += 1 }
            let h = px[i + 1] - px[i]
            let t = (x - px[i]) / h
            let t2 = t * t
            let t3 = t2 * t
            return (2 * t3 - 3 * t2 + 1) * py[i] + (t3 - 2 * t2 + t) * h * m[i]
                + (-2 * t3 + 3 * t2) * py[i + 1] + (t3 - t2) * h * m[i + 1]
        }
    }

    /// Il peso della pelle dal colore sRGB come tabella 3D per `CIColorCube` (grigio, alfa 1).
    private static let latoCuboPelle = 64
    private static let cuboPelle: Data = cubo(lato: latoCuboPelle) { r, g, b in
        let peso = RegolePelle.pesoColore(r: r * 255, g: g * 255, b: b * 255)
        return (peso, peso, peso)
    }

    /// La luce piena sul volto come tabella 3D (sRGB → sRGB): lo stesso guadagno sui tre canali, dalla curva della luce
    /// sulla luma, con il tetto dei chiari.
    private static let latoCuboLuce = 32
    private static let cuboLuce: Data = cubo(lato: latoCuboLuce) { r, g, b in
        let massimo = max(r, g, b)
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard massimo > 0, luma > 0 else { return (r, g, b) }
        let guadagno = min(RegolePelle.curvaLuce(luma) / luma, RegolePelle.tettoLuce(massimo))
        return (r * guadagno, g * guadagno, b * guadagno)
    }

    /// Una tabella 3D per `CIColorCube`: RGBA in Float, il rosso che cambia più in fretta, poi il verde, poi il blu.
    private static func cubo(lato n: Int, _ f: (Double, Double, Double) -> (Double, Double, Double)) -> Data {
        var valori = [Float](repeating: 1, count: n * n * n * 4)
        let passo = 1 / Double(n - 1)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let (x, y, z) = f(Double(r) * passo, Double(g) * passo, Double(b) * passo)
                    let i = ((b * n + g) * n + r) * 4
                    valori[i] = Float(x)
                    valori[i + 1] = Float(y)
                    valori[i + 2] = Float(z)
                }
            }
        }
        return valori.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// `CIColorCube` sui valori così come sono (qui sRGB già codificati: la tabella è in sRGB).
    private static func applicaCubo(_ immagine: CIImage, _ dati: Data, lato: Int) -> CIImage {
        let filtro = CIFilter.colorCube()
        filtro.inputImage = immagine
        filtro.cubeDimension = Float(lato)
        filtro.cubeData = dati
        return filtro.outputImage ?? immagine
    }

    /// La luma sRGB (pesi Rec. 709) di un'immagine già in sRGB, in tutti i canali, tra 0 e 1, alfa 1.
    private static func lumaSRGB(_ sRGB: CIImage) -> CIImage {
        let pesi = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        return lineare(canali(sRGB, r: pesi, g: pesi, b: pesi), pendenza: 1, scostamento: 0)
    }

    /// media(Y²) − media(Y)² con la luma centrata (Y − 0,5, come in `coefficientiGuida`), non sotto zero, grigia.
    private static func varianzaLocale(_ luma: CIImage, misura: CGRect, sigma: CGFloat) -> CIImage {
        func media(_ immagine: CIImage) -> CIImage {
            immagine.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: misura)
        }
        let uno = CIVector(x: 1, y: 0, z: 0, w: 0)
        let centrata = canali(luma, r: uno, g: uno, b: uno, scostamento: CIVector(x: -0.5, y: -0.5, z: -0.5, w: 1))
        let mediaQuadrati = media(moltiplica(centrata, centrata))
        let mediaY = media(centrata)
        let meno = CIVector(x: -1, y: 0, z: 0, w: 0)
        let varianza = somma(mediaQuadrati, canali(moltiplica(mediaY, mediaY), r: meno, g: meno, b: meno), misura: misura)
        return lineare(varianza, pendenza: 1, scostamento: 0)
    }

    /// 1 lontano dai bordi, 0 sui bordi veri: 1 − smoothstep((var − inizio) / larghezza), grigio.
    private static func pesoBordo(_ varianza: CIImage) -> CIImage {
        let t = lineare(varianza, pendenza: 1 / RegolePelle.bordoLarghezza,
                        scostamento: -RegolePelle.bordoInizio / RegolePelle.bordoLarghezza)
        let inverso = CIFilter.colorPolynomial()
        inverso.inputImage = t
        let unoMenoSmoothstep = CIVector(x: 1, y: 0, z: -3, w: 2)
        inverso.redCoefficients = unoMenoSmoothstep
        inverso.greenCoefficients = unoMenoSmoothstep
        inverso.blueCoefficients = unoMenoSmoothstep
        inverso.alphaCoefficients = CIVector(x: 1, y: 0, z: 0, w: 0)
        return inverso.outputImage ?? t
    }

    /// Un'ellisse morbida per volto (piena fino a `ellisseInterna`, niente oltre `ellisseEsterna`), la più forte.
    private static func mascheraEllissi(_ ellissi: [(centro: CGPoint, sx: CGFloat, sy: CGFloat)], zona: CGRect) -> CIImage {
        var maschera = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: zona)
        for e in ellissi where e.sx > 0 && e.sy > 0 {
            let disco = CIFilter.radialGradient()
            disco.center = .zero
            disco.radius0 = Float(RegolePelle.ellisseInterna / RegolePelle.ellisseEsterna)
            disco.radius1 = 1
            disco.color0 = CIColor(red: 1, green: 1, blue: 1)
            disco.color1 = CIColor(red: 0, green: 0, blue: 0)
            guard let ellisse = disco.outputImage?
                .transformed(by: CGAffineTransform(scaleX: e.sx, y: e.sy)
                    .concatenating(CGAffineTransform(translationX: e.centro.x, y: e.centro.y)))
                .cropped(to: zona) else { continue }
            let massimo = CIFilter.maximumCompositing()
            massimo.inputImage = ellisse
            massimo.backgroundImage = maschera
            maschera = massimo.outputImage ?? maschera
        }
        return maschera
    }

    /// Le zone protette (occhi con le sopracciglia, bocca): un'ellisse inscritta in ogni rettangolo, nera fino a 0,75 del
    /// raggio, bianca da 1,1 in fuori; si tiene il minimo. Come `RegolePelle.Protezione` su Windows.
    private static func mascheraProtette(_ zone: [CGRect], zona: CGRect) -> CIImage {
        var maschera = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: zona)
        for z in zone where z.width > 0 && z.height > 0 {
            let disco = CIFilter.radialGradient()
            disco.center = .zero
            disco.radius0 = 0.75
            disco.radius1 = 1.1
            disco.color0 = CIColor(red: 0, green: 0, blue: 0)
            disco.color1 = CIColor(red: 1, green: 1, blue: 1)
            guard let ellisse = disco.outputImage?
                .transformed(by: CGAffineTransform(scaleX: z.width / 2, y: z.height / 2)
                    .concatenating(CGAffineTransform(translationX: z.midX, y: z.midY)))
                .cropped(to: zona) else { continue }
            let minimo = CIFilter.minimumCompositing()
            minimo.inputImage = ellisse
            minimo.backgroundImage = maschera
            maschera = minimo.outputImage ?? maschera
        }
        return maschera
    }

    // MARK: Luce sul volto (EffettoLuceVolto.swift, la parte «schiarisci il viso»; Qualità 11)

    /// Un'ellisse morbida attorno al volto (`volto` in pixel, già levigato; smoothstep dal 30% del raggio al bordo),
    /// schiarita con la curva della luce applicata alla luma: lo stesso guadagno sui tre canali (tabella 3D
    /// `cuboLuce`), con il canale più alto che si prende al massimo metà dello spazio fino a 254/255. Niente chiari
    /// bruciati e niente colore cambiato (prima la curva andava canale per canale e spegneva le pelli chiare).
    /// La mescolanza in sRGB, come su Windows. `presenza` 0…1 per la dissolvenza.
    static func luceVolto(_ immagine: CIImage, volto: CGRect, presenza: CGFloat) -> CIImage {
        let estensione = immagine.extent
        guard presenza > 0.01 else { return immagine }
        let centro = CGPoint(x: volto.midX, y: volto.midY - volto.height * RegolePelle.luceCentro)
        let semiasseX = volto.width * RegolePelle.luceLarghezza
        let semiasseY = volto.height * RegolePelle.luceAltezza
        let zona = CGRect(x: centro.x - semiasseX, y: centro.y - semiasseY, width: semiasseX * 2, height: semiasseY * 2)
            .intersection(estensione).integral
        guard !zona.isEmpty, semiasseX > 0, semiasseY > 0 else { return immagine }
        let disco = CIFilter.radialGradient()
        disco.center = .zero
        disco.radius0 = 0.3
        disco.radius1 = 1
        disco.color0 = CIColor(red: 1, green: 1, blue: 1)
        disco.color1 = CIColor(red: 0, green: 0, blue: 0)
        guard let ellisse = disco.outputImage?
            .transformed(by: CGAffineTransform(scaleX: semiasseX, y: semiasseY)
                .concatenating(CGAffineTransform(translationX: centro.x, y: centro.y)))
            .cropped(to: zona) else { return immagine }
        // Rampa lineare tra 0,3 e 1 → smoothstep (la soglia morbida larga 1 centrata a metà).
        let maschera = RicetteFiltriMac.scala(sogliaMorbida(ellisse, larghezza: 1, centro: 0.5), per: presenza)
        let originale = immagine.cropped(to: zona)
        return RicetteFiltriMac.percettivo(originale) { sRGB in
            let illuminata = applicaCubo(sRGB, cuboLuce, lato: latoCuboLuce)
            return RicetteFiltriMac.mescola(sopra: illuminata, sotto: sRGB, maschera: maschera)
        }
        .cropped(to: zona)
        .composited(over: immagine)
    }

    // MARK: Sfondo (EffettoSfondo.swift)

    /// Raggio (sigma) della sfocatura a 1080p per un'intensità 0…1: 42 × intensità^1,3 (più forte dell'iPhone, che
    /// usa 32 × intensità^1,6). Poco (0,25) ≈ 7 px, lo sfondo morbido ma riconoscibile; Medio (0,55) ≈ 19 px, come la
    /// sfocatura di Meet; Tanto (1) = 42 px, lo sfondo non si legge più. Ogni livello è circa il doppio del precedente.
    static func sigmaSfocatura(_ intensita: Double) -> Double {
        let limitata = intensita.isFinite ? min(max(intensita, 0), 1) : 0.5
        return max(1.5, 42 * pow(limitata, 1.3))
    }

    /// Raggio fisso della sfocatura nell'immagine ridotta: l'intensità cambia solo la riduzione. 4 px (non meno): con
    /// la riduzione forte di «Tanto» (un decimo) l'ingrandimento bilineare resta liscio, senza quadretti.
    static let sigmaPiccola: CGFloat = 4

    // MARK: Bordo della persona: guided filter (He, Sun, Tang)

    // Come Meet e Teams: la maschera piccola di Vision si porta alla misura del video seguendo i bordi veri
    // dell'immagine. Il guided filter (He, Sun, Tang, «Guided Image Filtering», PAMI 2013) cerca, in ogni finestra, la
    // retta q = a·I + b che meglio approssima la maschera p a partire dalla luma I del fotogramma:
    //   a = cov(I, p) / (var(I) + ε),  b = media(p) − a·media(I),  q = media(a)·I + media(b).
    // Dove l'immagine ha un bordo (var(I) grande rispetto a ε) la maschera lo segue; dove è piatta (var(I) ≪ ε) a ≈ 0 e
    // la maschera resta quella di Vision, solo smussata: niente «colate» tra due bianchi vicini (maglietta e cuscino).
    // Versione «fast» (He e Sun 2015): a e b si calcolano a `latoGuida`, si ingrandiscono e q si calcola con la luma
    // a piena risoluzione. Solo filtri di sistema (niente kernel Metal propri): le operazioni tra due immagini passano da
    // `somma` (fusione con maschera costante a metà) e `CIMultiplyCompositing`, l'unica divisione da `dividi`
    // (`CIDivideBlendMode` nei due ordini) con i valori tenuti tra 0 e 1; `verificaAritmetica` prova i tre conti una volta
    // all'avvio. Varianza e covarianza vere della finestra, media(I²) − Ī² e media(I·p) − Ī·p̄, con la luma centrata
    // (I − 0,5, tra −0,5 e 0,5) perché in mezza precisione l'errore resti molto sotto ε. (La media di (I − Ī)² con Ī
    // locale, usata prima, misura solo i dettagli fini: nella simulazione il bordo si agganciava 2-5 volte peggio.)

    /// Lato corto a cui si calcolano a e b: 540 per il 1080p (un quarto dei pixel).
    static let latoGuida: CGFloat = 540
    /// Raggio delle medie locali (sigma della gaussiana) alla misura della guida: circa 8 px a 1080p.
    static let raggioGuida: CGFloat = 4
    /// ε sulla luma percettiva 0…1: la maschera segue un gradino dell'immagine da circa il 6% di contrasto (2√ε) in su.
    static let epsilonGuida: CGFloat = 0.001
    /// Tetto di |a| che tiene la divisione tra 0 e 1. Con p tra 0 e 1, |cov| ≤ ½·√var, quindi |a| ≤ 1 / (4√ε) ≈ 7,9:
    /// 8 non taglia mai.
    private static let limiteA: CGFloat = 8
    /// Centro della soglia del bordo: poco sopra la metà. La zona grigia di Vision (fino a circa 0,45, dove è incerta:
    /// un cuscino chiaro accanto alla persona) va con lo sfondo; capelli e spalle li tiene il guided filter. Nella
    /// simulazione 0,55 con larghezza 0,2 toglie il cuscino senza tagliare una felpa scura; 0,65 la taglia.
    static let centroSoglia: CGFloat = 0.55

    /// La maschera (piccola, già filtrata nel tempo, grigia) alla misura dell'immagine, con il bordo rifinito.
    /// - `leggero` falso: guided filter guidato dalla luma del video (vedi sopra), poi soglia morbida.
    /// - `leggero`: ingrandimento bilineare a metà risoluzione, piuma 1,5 px e poi la soglia.
    /// `morbidezza`: larghezza della soglia (vedi `sogliaMorbida`).
    static func mascheraRifinita(_ bassa: CIImage, immagine: CIImage, morbidezza: CGFloat,
                                 centro: CGFloat = RicetteEffetti.centroSoglia, leggero: Bool) -> CIImage {
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
        // (I − 0,5, 1): la stessa luma centrata usata per a e b.
        let lumaEUno = canali(luma, r: uno, g: zero, b: zero, scostamento: CIVector(x: -0.5, y: 1, z: 0, w: 1))
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
    /// `sigma` ed `eps`: quelli del bordo della persona, o del ritocco della pelle (Qualità 11, guida = maschera = luma).
    private static func coefficientiGuida(guida: CIImage, maschera: CIImage, misura: CGRect,
                                          sigma: CGFloat = raggioGuida, eps: CGFloat = epsilonGuida) -> CIImage {
        func media(_ immagine: CIImage) -> CIImage {
            immagine.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: misura)
        }
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        let primo = CIVector(x: 1, y: 0, z: 0, w: 0)
        let secondo = CIVector(x: 0, y: 1, z: 0, w: 0)
        // (I, p): la luma centrata (I − 0,5) nel rosso, la maschera nel verde.
        let insieme = somma(canali(guida, r: primo, g: zero, b: zero, scostamento: CIVector(x: -0.5, y: 0, z: 0, w: 1)),
                            canali(maschera, r: zero, g: primo, b: zero), misura: misura)
        let medie = media(insieme)                                                     // (Ī, p̄)
        let mediaProdotti = media(moltiplica(insieme, canali(insieme, r: primo, g: primo, b: zero)))  // (media(I²), media(I·p))
        let prodottoMedie = moltiplica(medie, canali(medie, r: primo, g: primo, b: zero))              // (Ī², Ī·p̄)
        let differenza = somma(mediaProdotti, canali(prodottoMedie, r: CIVector(x: -1, y: 0, z: 0, w: 0),
                                                     g: CIVector(x: 0, y: -1, z: 0, w: 0), b: zero), misura: misura)
        let momenti = limitaMomenti(differenza)                                       // (var, cov)
        // r = (a + k) / 2k = ((cov + k·(var + ε)) / 2k) / (var + ε), sempre tra 0 e 1 (k = `limiteA`). Anche
        // numeratore e denominatore restano tra 0 e 1 (var ≤ 0,25 con la luma centrata): nessun taglio possibile.
        let k = limiteA
        let rigaNumeratore = CIVector(x: 0.5, y: 1 / (2 * k), z: 0, w: 0)
        let numeratore = canali(momenti, r: rigaNumeratore, g: rigaNumeratore, b: rigaNumeratore,
                                scostamento: CIVector(x: eps / 2, y: eps / 2, z: eps / 2, w: 1))
        let denominatore = canali(momenti, r: primo, g: primo, b: primo, scostamento: CIVector(x: eps, y: eps, z: eps, w: 1))
        let rapporto = lineare(dividi(numeratore, per: denominatore), pendenza: 1, scostamento: 0)
        // (a, a, 1) × (1, Ī, p̄) = (a, a·Ī, p̄), poi (a, b = p̄ − a·Ī).
        let aDoppio = CIVector(x: 2 * k, y: 0, z: 0, w: 0)
        let conA = canali(rapporto, r: aDoppio, g: aDoppio, b: zero, scostamento: CIVector(x: -k, y: -k, z: 1, w: 1))
        let conMedie = canali(medie, r: zero, g: primo, b: secondo, scostamento: CIVector(x: 1, y: 0, z: 0, w: 1))
        let coefficienti = canali(moltiplica(conA, conMedie), r: primo, g: CIVector(x: 0, y: -1, z: 1, w: 0), b: zero)
        return media(coefficienti)
    }

    /// (var, cov): la varianza non sotto zero (arrotondamenti della mezza precisione), la covarianza com'è, anche
    /// negativa (persona scura su fondo chiaro). `verificaAritmetica` prova che il negativo passa.
    private static func limitaMomenti(_ momenti: CIImage) -> CIImage {
        let limiti = CIFilter.colorClamp()
        limiti.inputImage = momenti
        limiti.minComponents = CIVector(x: 0, y: -1, z: -1, w: 1)
        limiti.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return limiti.outputImage ?? momenti
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

    /// Prova, una volta, che su questo Mac `somma`, `moltiplica` e `dividi` fanno i conti come serve al guided filter:
    /// valori negativi e sopra 1 senza tagli (scarti, covarianza, b), e la divisione giusta. Pixel veri (non colori
    /// costanti, che Core Image potrebbe calcolare a parte) resi con il contesto del motore, senza spazio di colore.
    /// Falso: il motore usa il bordo semplice (bilineare) invece del guided filter, e lo scrive nel registro.
    static func verificaAritmetica(_ contesto: CIContext) -> Bool {
        let x: [Float] = [-0.6, 0.9, 0.3, -0.05]
        let y: [Float] = [0.7, -0.4, 0.95, -0.8]
        let numeratori: [Float] = [0, 0.05, 0.1, 0.2]
        let denominatori: [Float] = [0.004, 0.1, 0.4, 0.25]
        let misura = CGRect(x: 0, y: 0, width: x.count, height: 1)
        let prove: [(CIImage, [Float])] = [
            (somma(pixelDiProva(x), pixelDiProva(y), misura: misura), zip(x, y).map { $0 + $1 }),
            (moltiplica(pixelDiProva(x), pixelDiProva(y)), zip(x, y).map { $0 * $1 }),
            (dividi(pixelDiProva(numeratori), per: pixelDiProva(denominatori)), zip(numeratori, denominatori).map { $0 / $1 }),
            // La covarianza (verde) negativa deve passare da `limitaMomenti`: copiata in tutti i canali, resta y.
            (canali(limitaMomenti(pixelDiProva(y)), r: CIVector(x: 0, y: 1, z: 0, w: 0), g: CIVector(x: 0, y: 1, z: 0, w: 0),
                    b: CIVector(x: 0, y: 1, z: 0, w: 0)), y),
        ]
        for (immagine, attesi) in prove {
            var pixel = [Float](repeating: .nan, count: attesi.count * 4)
            pixel.withUnsafeMutableBytes { byte in
                guard let base = byte.baseAddress else { return }
                contesto.render(immagine.cropped(to: misura), toBitmap: base, rowBytes: attesi.count * 16, bounds: misura,
                                format: .RGBAf, colorSpace: nil)
            }
            for (indice, atteso) in attesi.enumerated() {
                for canale in 0..<3 where !(abs(pixel[indice * 4 + canale] - atteso) < 0.01) { return false }
            }
        }
        return true
    }

    /// Una riga di pixel grigi con i valori dati (come sono, nessuno spazio di colore), alfa 1.
    private static func pixelDiProva(_ valori: [Float]) -> CIImage {
        var pixel: [Float] = []
        for valore in valori { pixel += [valore, valore, valore, 1] }
        let dati = pixel.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: dati, bytesPerRow: valori.count * 16,
                       size: CGSize(width: valori.count, height: 1), format: .RGBAf, colorSpace: nil)
    }

    /// numeratore / denominatore canale per canale, per 0 ≤ numeratore ≤ denominatore (risultato tra 0 e 1), alfa 1.
    /// La documentazione di `CIDivideBlendMode` non dice con certezza quale dei due operandi sia il numeratore
    /// («Divides the background image sample color from the source image sample color»): si fanno tutte e due le
    /// divisioni e si tiene la minore. Una è il rapporto voluto (≤ 1), l'altra il suo inverso (≥ 1, o tagliato a 1, o
    /// infinito dove il numeratore è 0): il minimo è sempre il rapporto giusto, qualunque sia l'ordine vero.
    static func dividi(_ numeratore: CIImage, per denominatore: CIImage) -> CIImage {
        let prima = CIFilter.divideBlendMode()
        prima.inputImage = denominatore
        prima.backgroundImage = numeratore
        let seconda = CIFilter.divideBlendMode()
        seconda.inputImage = numeratore
        seconda.backgroundImage = denominatore
        guard let uno = prima.outputImage, let due = seconda.outputImage else { return numeratore }
        let minimo = CIFilter.minimumCompositing()
        minimo.inputImage = uno
        minimo.backgroundImage = due
        return minimo.outputImage ?? uno
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
    static func sogliaMorbida(_ maschera: CIImage, larghezza: CGFloat,
                              centro: CGFloat = RicetteEffetti.centroSoglia) -> CIImage {
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
        guard estensione.width > 0, estensione.height > 0 else { return immagine }
        let riferimento = min(estensione.width, estensione.height) / 1080
        return sfocataSenzaAlone(immagine, bassa: bassa, sigmaPiena: CGFloat(sigmaSfocatura(intensita)) * riferimento, fine: fine)
    }

    /// Come sopra, con la sigma in pixel della misura piena (il mosaico la sceglie dal lato dei quadretti).
    static func sfocataSenzaAlone(_ immagine: CIImage, bassa: CIImage, sigmaPiena sigma: CGFloat, fine: Bool) -> CIImage {
        let scala = min(1, sigmaPiccola / max(sigma, 0.1))
        return sfondoSenzaPersona(immagine, bassa: bassa, scala: scala, fine: fine) { aperta, misura in
            if fine {
                // Un po' di «bokeh»: un disco (raggio 1,6 σ, le luci diventano cerchi morbidi come in un obiettivo) e una
                // gaussiana piccola che ne smussa l'orlo; insieme valgono una gaussiana di sigma `sigmaPiccola`. In lineare,
                // quindi le luci pesano quanto in un obiettivo vero. Costa poco: l'immagine è già ridotta.
                let disco = CIFilter.discBlur()
                disco.inputImage = aperta
                disco.radius = Float(sigmaPiccola * 1.6)
                return (disco.outputImage ?? aperta)
                    .applyingGaussianBlur(sigma: Double(sigmaPiccola * 0.6))
                    .cropped(to: misura)
            }
            return aperta.applyingGaussianBlur(sigma: Double(sigmaPiccola)).cropped(to: misura)
        }
    }

    /// Il cuore delle sfocature senza alone: riduce l'immagine a `scala`, toglie la persona allargata (alfa), passa
    /// `prima` sui colori ridotti, sfoca con `sfoca` (immagine aperta ai bordi, misura piccola), divide per l'alfa
    /// sfocato, passa `dopo` e riporta alla misura piena.
    private static func sfondoSenzaPersona(_ immagine: CIImage, bassa: CIImage, scala: CGFloat, fine: Bool,
                                           prima: (CIImage) -> CIImage = { $0 }, dopo: (CIImage) -> CIImage = { $0 },
                                           sfoca: (CIImage, CGRect) -> CIImage) -> CIImage {
        let estensione = immagine.extent
        let misuraBassa = bassa.extent
        guard misuraBassa.width > 0, misuraBassa.height > 0, estensione.width > 0, estensione.height > 0 else {
            return immagine
        }
        let riferimento = min(estensione.width, estensione.height) / 1080
        let riduzione = CGAffineTransform(scaleX: scala, y: scala)
        let ridotta = fine && scala < 1
            ? immagine.transformed(by: riduzione, highQualityDownsample: true)
            : immagine.transformed(by: riduzione)
        let misura = ridotta.extent
        let piccola = prima(ridotta.cropped(to: misura))
        let allaPiccola = CGAffineTransform(scaleX: estensione.width / misuraBassa.width,
                                            y: estensione.height / misuraBassa.height)
            .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
            .concatenating(riduzione)
        // La persona esce già da 0,1 (bordo e capelli incerti compresi: il loro colore non deve sbavare nello sfondo) ed
        // è piena da 0,5; mai del tutto (0,99), così l'alfa sfocato non arriva mai a zero.
        // Allargata di circa 12 px (a 1080p) prima: Vision sta spesso qualche pixel dentro il bordo vero, e senza
        // allargarla i pixel chiari del bordo entravano nella sfocatura (nella simulazione un alone di +25/255 attorno a
        // una persona chiara su fondo scuro; con 12 px +4).
        let allargata = CIFilter.morphologyMaximum()
        allargata.inputImage = lineare(bassa.transformed(by: allaPiccola), pendenza: 2.5, scostamento: -0.25, massimo: 0.99)
            .clampedToExtent()
        allargata.radius = Float(max(1, 12 * riferimento * scala))
        let persona = (allargata.outputImage ?? allargata.inputImage ?? CIImage(color: .black))
            .cropped(to: misura)
        let senzaPersona = RicetteFiltriMac.mescola(sopra: CIImage(color: CIColor.clear).cropped(to: misura),
                                                    sotto: piccola, maschera: persona)
        let aperta = senzaPersona.cropped(to: misura).clampedToExtent()
        let sfocata = sfoca(aperta, misura)
        let normalizzata = dopo(sfocata
            .unpremultiplyingAlpha()
            .settingAlphaOne(in: misura)
            .cropped(to: misura))
        let ritorno = CGAffineTransform(translationX: -misura.minX, y: -misura.minY)
            .concatenating(CGAffineTransform(scaleX: estensione.width / max(misura.width, 1),
                                             y: estensione.height / max(misura.height, 1)))
            .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
        return normalizzata.transformed(by: ritorno).clampedToExtent().cropped(to: estensione)
    }

    // MARK: Bokeh e mosaico (Qualità 7 e 8; come Windows, WebcamLR.Effetti/Motore/RicetteSfondo.cs)

    /// Raggio del disco (pixel a 1080p) per un'intensità: 2σ della sfocatura normale. Un disco pieno di raggio 2σ ha la
    /// stessa deviazione standard della gaussiana di sigma σ: lo sfondo è sfocato «quanto» con la sfocatura normale, ma
    /// le luci diventano dischi.
    static func raggioBokeh(_ intensita: Double) -> CGFloat { CGFloat(2 * sigmaSfocatura(intensita)) }

    /// Il raggio del disco nell'immagine ridotta: la riduzione si sceglie perché resti questo (al massimo un quarto della
    /// misura). `CIBokehBlur` costa con il quadrato del raggio: 12 px a un ottavo valgono 96 px a 1080p.
    static let raggioBokehPiccolo: CGFloat = 12

    /// Da quale valore lineare (0..1) un canale conta come «luce forte»: 0,6 è circa 200/255 in sRGB.
    static let sogliaLuci: CGFloat = 0.6
    /// Quanto si espande una luce sopra la soglia: v + 20·(v − 0,6), cioè il bianco vale 9 volte. Dopo il disco si
    /// comprime con l'inversa esatta (b − 20/21·(b − 0,6) sopra la soglia): una zona uniforme torna identica, una luce
    /// piccola, sparsa sul disco, resta un disco chiaro. Solo filtri di sistema (matrice, limiti e `somma`).
    static let guadagnoLuci: CGFloat = 20

    /// v + k·max(v − soglia, 0), canale per canale, alfa 1 (valori sopra 1: il contesto lavora in virgola mobile).
    static func espandiLuci(_ immagine: CIImage) -> CIImage {
        let misura = immagine.extent
        let sopra = lineare(immagine, pendenza: guadagnoLuci, scostamento: -guadagnoLuci * sogliaLuci, massimo: 1000)
        return somma(immagine, sopra, misura: misura)
    }

    /// L'inversa di `espandiLuci`: b − k/(1 + k)·max(b − soglia, 0).
    static func comprimiLuci(_ immagine: CIImage) -> CIImage {
        let misura = immagine.extent
        let sopra = lineare(immagine, pendenza: 1, scostamento: -sogliaLuci, massimo: 1000)
        let meno = -guadagnoLuci / (1 + guadagnoLuci)
        let togli = canali(sopra, r: CIVector(x: meno, y: 0, z: 0, w: 0), g: CIVector(x: 0, y: meno, z: 0, w: 0),
                           b: CIVector(x: 0, y: 0, z: meno, w: 0))
        return somma(immagine, togli, misura: misura)
    }

    /// Lo sfondo «come un obiettivo», senza la persona: in piccolo (perché il disco resti `raggioBokehPiccolo`), luci
    /// espanse, `CIBokehBlur` (disco morbido con un filo di anello, come le lenti vere), diviso per l'alfa sfocato, luci
    /// compresse con l'inversa. In lineare (lo spazio di lavoro del motore).
    static func sfocataBokeh(_ immagine: CIImage, bassa: CIImage, intensita: Double) -> CIImage {
        let estensione = immagine.extent
        guard estensione.width > 0, estensione.height > 0 else { return immagine }
        let raggio = raggioBokeh(intensita) * min(estensione.width, estensione.height) / 1080
        let scala = min(0.25, raggioBokehPiccolo / max(raggio, 0.1))
        return sfondoSenzaPersona(immagine, bassa: bassa, scala: scala, fine: true, prima: espandiLuci, dopo: comprimiLuci) {
            aperta, misura in
            let bokeh = CIFilter.bokehBlur()
            bokeh.inputImage = aperta
            bokeh.radius = Float(max(1, raggio * scala))
            bokeh.ringAmount = 0.15
            bokeh.ringSize = 0.1
            bokeh.softness = 1
            return (bokeh.outputImage ?? aperta).cropped(to: misura)
        }
    }

    /// Il lato di un quadretto (pixel a 1080p) per un'intensità: 12 + 36 × intensità (Poco 21, Medio 32, Tanto 48),
    /// come Windows.
    static func latoQuadretto(_ intensita: Double) -> CGFloat {
        let limitata = intensita.isFinite ? min(max(intensita, 0), 1) : 0.5
        return CGFloat(12 + 36 * limitata)
    }

    /// Lo sfondo a quadretti, senza la persona: lo sfondo senza alone sfocato di un terzo del quadretto (così il colore al
    /// centro, quello che prende `CIPixellate`, vale la media del quadretto) e poi `CIPixellate`, con la griglia che parte
    /// dall'angolo in alto a sinistra. I quadretti restano netti: la composizione li mette sotto la persona così come sono.
    static func mosaico(_ immagine: CIImage, bassa: CIImage, intensita: Double) -> CIImage {
        let estensione = immagine.extent
        guard estensione.width > 0, estensione.height > 0 else { return immagine }
        let lato = max(4, latoQuadretto(intensita) * min(estensione.width, estensione.height) / 1080)
        let fondo = sfocataSenzaAlone(immagine, bassa: bassa, sigmaPiena: lato / 3, fine: false)
        let quadretti = CIFilter.pixellate()
        quadretti.inputImage = fondo.clampedToExtent()
        quadretti.scale = Float(lato)
        quadretti.center = CGPoint(x: estensione.minX, y: estensione.maxY)
        return (quadretti.outputImage ?? fondo).cropped(to: estensione)
    }

    /// La persona pronta per uno sfondo sostituito (`maschera`: quella rifinita, alla misura dell'immagine).
    /// 1. Bordo pulito (non in `leggero`): dove la maschera è parziale (capelli, orlo), il pixel è un misto di persona e
    ///    vecchio sfondo; lì il colore si prende sempre più dall'interno sicuro della persona (media normalizzata dei
    ///    pixel con maschera ≥ 0,95), così il vecchio sfondo non resta come alone chiaro o scuro sui capelli.
    /// 2. Light wrap: lo sfondo nuovo, sfocato, entra per pochi pixel sul bordo della persona («screen», al massimo il
    ///    35% proprio sull'orlo e niente già a 10-15 px all'interno): la persona sembra illuminata dallo stesso ambiente.
    /// `luce` falso (schermo verde per il chroma key): solo il bordo pulito, niente light wrap.
    static func personaSuSfondoNuovo(_ immagine: CIImage, maschera: CIImage, sfondo: CIImage, leggero: Bool,
                                     luce: Bool = true) -> CIImage {
        let estensione = immagine.extent
        guard estensione.width > 0, estensione.height > 0, !estensione.isInfinite else { return immagine }
        let unita = min(estensione.width, estensione.height) / 1080
        var persona = immagine
        if !leggero {
            // Peso dell'interno: 0 sotto 0,75, 1 da 0,95; mai sotto 0,01 (l'alfa sfocato non arriva a zero).
            let interno = lineare(lineare(maschera, pendenza: 5, scostamento: -3.75), pendenza: 0.99, scostamento: 0.01)
            let colorePersona = mediaNormalizzata(immagine, peso: interno, sigma: 8 * unita, scala: 0.25)
            // Fiducia nel pixel vero: 1 con la maschera piena, 0 sotto 0,6.
            let fiducia = lineare(maschera, pendenza: 2.5, scostamento: -1.5)
            persona = RicetteFiltriMac.mescola(sopra: immagine, sotto: colorePersona, maschera: fiducia)
                .cropped(to: estensione)
        }
        guard luce else { return persona }
        let sfondoMorbido = sfocataRidotta(sfondo.cropped(to: estensione), sigma: 14 * unita, scala: 0.25)
        let mascheraMorbida = sfocataRidotta(maschera, sigma: 3 * unita, scala: 0.25)
        // m · (1 − m sfocata): circa 0,5 sull'orlo interno, 0 dentro la persona e fuori.
        let banda = moltiplica(maschera, lineare(mascheraMorbida, pendenza: -1, scostamento: 1))
        // Leggero: nella simulazione 0,7 / 0,35 schiariva l'orlo dei capelli scuri su uno sfondo chiaro di +29/255 (alone
        // beige); 0,3 / 0,15 lo porta a circa +9 e l'effetto resta.
        let peso = lineare(banda, pendenza: 0.3, scostamento: 0, massimo: 0.15)
        let schermo = CIFilter.screenBlendMode()
        schermo.inputImage = sfondoMorbido
        schermo.backgroundImage = persona
        let avvolta = schermo.outputImage ?? persona
        return RicetteFiltriMac.mescola(sopra: avvolta, sotto: persona, maschera: peso).cropped(to: estensione)
    }

    /// Sfocata in piccolo (`scala` della misura, sigma `sigma` in pixel dell'immagine) e riportata alla misura.
    private static func sfocataRidotta(_ immagine: CIImage, sigma: CGFloat, scala: CGFloat) -> CIImage {
        let estensione = immagine.extent
        guard estensione.width > 0, estensione.height > 0, !estensione.isInfinite else { return immagine }
        let riduzione = CGAffineTransform(translationX: -estensione.minX, y: -estensione.minY)
            .concatenating(CGAffineTransform(scaleX: scala, y: scala))
        let misura = CGRect(x: 0, y: 0, width: max((estensione.width * scala).rounded(.up), 1),
                            height: max((estensione.height * scala).rounded(.up), 1))
        return immagine.transformed(by: riduzione)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(sigma * scala, 0.5)))
            .cropped(to: misura)
            .transformed(by: riduzione.inverted())
            .clampedToExtent()
            .cropped(to: estensione)
    }

    /// Media dei colori pesata da `peso` (grigia, mai zero), in piccolo: Σ colore·peso / Σ peso nel vicinato.
    private static func mediaNormalizzata(_ immagine: CIImage, peso: CIImage, sigma: CGFloat, scala: CGFloat) -> CIImage {
        let estensione = immagine.extent
        guard estensione.width > 0, estensione.height > 0, !estensione.isInfinite else { return immagine }
        let riduzione = CGAffineTransform(translationX: -estensione.minX, y: -estensione.minY)
            .concatenating(CGAffineTransform(scaleX: scala, y: scala))
        let misura = CGRect(x: 0, y: 0, width: max((estensione.width * scala).rounded(.up), 1),
                            height: max((estensione.height * scala).rounded(.up), 1))
        // Colore premoltiplicato per il peso (alfa = peso), sfocato, poi diviso per l'alfa sfocato.
        let pesata = RicetteFiltriMac.mescola(sopra: immagine.transformed(by: riduzione),
                                              sotto: CIImage(color: CIColor.clear),
                                              maschera: peso.transformed(by: riduzione))
        return pesata
            .cropped(to: misura)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(sigma * scala, 0.5)))
            .cropped(to: misura)
            .unpremultiplyingAlpha()
            .settingAlphaOne(in: misura)
            .transformed(by: riduzione.inverted())
            .clampedToExtent()
            .cropped(to: estensione)
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
