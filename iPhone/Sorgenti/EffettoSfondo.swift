import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import Stile
import SwiftUI
import UIKit
import WebcamLRProtocollo

/// Sfondo sfocato o sostituito (P14), con la maschera della persona di `AnalisiFotogramma`
/// (`VNGeneratePersonSegmentationRequest`, `.balanced`).
///
/// Terza prova (27 ottobre, punto A): prima la maschera arrivava 10 volte al secondo e si mediava con le precedenti,
/// quindi il bordo restava indietro (pezzi di testa sotto lo sfondo, scie); si ingrandiva a scalini e la sfocatura
/// dell'immagine intera faceva colare i colori della persona nello sfondo (alone). Adesso:
/// 1. **Cadenza.** Con lo sfondo acceso Vision analizza ogni fotogramma (al massimo 32 al secondo: a 60 fps uno sì e
///    uno no), e la pipeline aspetta per qualche millisecondo la maschera *del fotogramma che sta elaborando*
///    (`AnalisiFotogramma.aspettaMaschera`): di solito il bordo è quello del fotogramma stesso, al peggio di quello
///    prima. Con il telefono molto caldo `.fast` e 15 al secondo.
/// 2. **Filtro nel tempo che non ritarda** (`filtraNelTempo`, alla risoluzione della maschera): dove la maschera
///    nuova è diversa dalla precedente (|nuova − vecchia| ≥ 0,1, cioè un movimento) si prende la nuova e basta; solo
///    dove cambia poco (lo sfarfallio del bordo fermo) si mescola, con almeno il 60% della nuova.
/// 3. **Bordo rifinito** (`mascheraRifinita`): la maschera si porta alla risoluzione del video con
///    `CIEdgePreserveUpsampleFilter`, guidato dall'immagine stessa (il bordo segue capelli e spalle veri, non i
///    pixel grossi della maschera), poi una piuma fissa e una soglia morbida (smoothstep). Oltre il 1080p (4K) si
///    rifinisce a 1080 e l'ultimo ingrandimento ×2 è bilineare, già liscio.
/// 4. **Sfocatura senza alone** (`sfocataSenzaAlone`): lo sfondo si sfoca *senza la persona*. Si toglie la persona
///    (immagine × (1 − maschera allargata), con la maschera nell'alfa), si sfoca, poi si divide per l'alfa sfocato:
///    è la sfocatura «normalizzata», in cui ogni punto prende colore solo dallo sfondo vicino.
/// 5. **Costo.** Tutto su GPU nello stesso grafo Core Image della pipeline; l'unica resa a parte è la maschera
///    filtrata (piccola, circa 0,2 milioni di pixel). La sfocatura si calcola in piccolo con un raggio fisso (2,5 px)
///    e l'intensità cambia la riduzione: nessun filtro nuovo da compilare quando cambia il livello (punto B).
///
/// - «Sfocato»: `intensita` 0…1 → raggio (sigma) 32 × intensità^1,6 px a 1080p, proporzionale alla risoluzione (punto C):
///   0,25 «Poco» ≈ 3,5 px (lo sfondo si riconosce), 0,55 «Medio» ≈ 12 px, 1 «Tanto» = 32 px.
/// - «Sostituito»: l'immagine data con `impostaImmagine(_:)` (uno sfondo pronto del bundle o l'immagine personale
///   mandata dal computer, già letta da `EffettiVisivi` fuori dalla coda di cattura), disegnata una volta alla
///   misura del video e tenuta in un buffer (IOSurface, nessuna copia per fotogramma). Finché non c'è, il fondo di
///   `Tema`. `intensita` = quanto è netto il bordo.
/// - Con «Ritratto» di iOS acceso lo sfondo è già sfocato dal sistema: «sfocato» non si somma (resta scelto, ma
///   l'effetto si spegne). «Sostituito» invece funziona lo stesso.
final class EffettoSfondo: Effetto, @unchecked Sendable {
    struct Impostazioni: Equatable, Sendable {
        /// Uno dei `ModiSfondo`.
        var modo = ModiSfondo.nessuno
        var intensita = 0.5
        /// «Ritratto» (Effetti video di iOS) acceso: lo sfondo è già sfocato.
        var ritrattoDiSistema = false
    }

    let nome = "Sfondo"
    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var interne = Impostazioni()
    private var immagineScelta: CGImage?
    private var versioneImmagine = 0

    // Solo sulla coda di cattura.
    private var mascheraFiltrata: CVPixelBuffer?
    private var mascheraRiserva: CVPixelBuffer?
    private var ultimaMaschera: TimeInterval = -1
    private var sfondoDisegnato: (chiave: String, immagine: CIImage)?

    /// Filtro nel tempo: peso della maschera nuova = 0,6 + 4 × |nuova − vecchia|, al massimo 1.
    private static let pesoMinimo: CGFloat = 0.6
    private static let guadagnoDifferenza: CGFloat = 4
    /// La rifinitura del bordo lavora al massimo a questo lato corto (il 1080p intero; il 4K a metà).
    private static let latoGuida: CGFloat = 1080
    /// Raggio fisso della sfocatura nell'immagine ridotta: l'intensità cambia solo la riduzione.
    private static let sigmaPiccola: CGFloat = 2.5
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    var impostazioni: Impostazioni {
        get { blocco.withLock { interne } }
        set { blocco.withLock { interne = newValue } }
    }

    /// L'immagine di «sostituito», già dritta e ridotta (lato lungo al massimo 1920 px). `nil` = il fondo di `Tema`.
    func impostaImmagine(_ immagine: CGImage?) {
        blocco.withLock {
            immagineScelta = immagine
            versioneImmagine += 1
        }
    }

    var attivo: Bool {
        let attuali = impostazioni
        switch attuali.modo {
        case ModiSfondo.sfocato: return !attuali.ritrattoDiSistema
        case ModiSfondo.sostituito: return true
        default: return false
        }
    }

    var analisiNecessarie: Set<TipoAnalisi> { [.persona] }

    /// Il raggio (sigma) della sfocatura a 1080p per un'intensità 0…1 (punto C): livelli ben distinti.
    static func sigmaSfocatura(_ intensita: Double) -> Double {
        let limitata = min(max(intensita, 0), 1)
        return max(1.5, 32 * pow(limitata, 1.6))
    }

    func applica(_ immagine: CIImage, contesto info: InfoFotogramma) -> CIImage {
        let attuali = impostazioni
        // Una maschera vecchia (effetto appena riacceso, analisi ferma) non si usa: meglio il video intatto.
        guard let nuova = info.maschera, ProcessInfo.processInfo.systemUptime - nuova.quando < 0.5,
              let filtrata = filtraNelTempo(nuova) else { return immagine }
        let intensita = CGFloat(min(max(attuali.intensita, 0), 1))
        let sostituito = attuali.modo == ModiSfondo.sostituito
        let bassa = CIImage(cvPixelBuffer: filtrata, options: [.colorSpace: NSNull()])

        // Bordo: con «sostituito» e intensità alta più netto (larghezza della soglia da 0,8 a 0,2).
        let morbidezza = sostituito ? 0.8 - 0.6 * intensita : 0.5
        let maschera = mascheraRifinita(bassa, immagine: immagine, info: info, morbidezza: morbidezza)

        let sfondo: CIImage
        if sostituito {
            sfondo = immagineSfondo(estensione: immagine.extent)
        } else {
            sfondo = sfocataSenzaAlone(immagine, bassa: bassa, info: info, intensita: Double(intensita))
        }
        let unione = CIFilter.blendWithMask()
        unione.inputImage = immagine
        unione.backgroundImage = sfondo
        unione.maskImage = maschera
        return unione.outputImage ?? immagine
    }

    /// 1.14: dopo un cambio di geometria (specchio, obiettivo, rotazione) il filtro nel tempo non deve mescolare la
    /// maschera vecchia con quella nuova: si riparte dalla prima maschera nuova (fino ad allora video intatto).
    func geometriaCambiata(_ cambio: CambioGeometria) {
        mascheraFiltrata = nil
        ultimaMaschera = -1
    }

    // MARK: Maschera

    /// La maschera filtrata nel tempo, alla risoluzione di Vision. Si rifà solo quando arriva una maschera nuova.
    /// Dove la maschera cambia (un movimento) vale la nuova; dove cambia poco si mescola con la precedente, così il
    /// bordo fermo non sfarfalla ma quello in movimento non resta mai indietro.
    private func filtraNelTempo(_ nuova: MascheraPersona) -> CVPixelBuffer? {
        guard nuova.quando != ultimaMaschera else { return mascheraFiltrata }
        ultimaMaschera = nuova.quando
        let larghezza = CVPixelBufferGetWidth(nuova.maschera)
        let altezza = CVPixelBufferGetHeight(nuova.maschera)
        guard larghezza > 0, altezza > 0 else { return mascheraFiltrata }

        var riserva = mascheraRiserva
        if let attuale = riserva,
           CVPixelBufferGetWidth(attuale) != larghezza || CVPixelBufferGetHeight(attuale) != altezza {
            riserva = nil
        }
        if riserva == nil { riserva = Self.creaBuffer(larghezza: larghezza, altezza: altezza) }
        guard let destinazione = riserva else { return mascheraFiltrata }

        let ingresso = Self.grigio(CIImage(cvPixelBuffer: nuova.maschera, options: [.colorSpace: NSNull()]))
        var risultato = ingresso
        if let precedente = mascheraFiltrata,
           CVPixelBufferGetWidth(precedente) == larghezza, CVPixelBufferGetHeight(precedente) == altezza {
            let vecchia = CIImage(cvPixelBuffer: precedente, options: [.colorSpace: NSNull()])
            // |nuova − vecchia| (tutte e due opache: la differenza dei valori).
            let differenza = CIFilter.differenceBlendMode()
            differenza.inputImage = ingresso
            differenza.backgroundImage = vecchia
            let peso = Self.lineare(differenza.outputImage ?? ingresso, pendenza: Self.guadagnoDifferenza,
                                    scostamento: Self.pesoMinimo)
            // nuova × peso + vecchia × (1 − peso).
            let media = CIFilter.blendWithMask()
            media.inputImage = ingresso
            media.backgroundImage = vecchia
            media.maskImage = peso
            risultato = media.outputImage ?? ingresso
        }
        ContestiEffetti.maschere.render(risultato, to: destinazione,
                                        bounds: CGRect(x: 0, y: 0, width: larghezza, height: altezza),
                                        colorSpace: nil)
        // Due buffer a turno: quello appena scritto diventa il «precedente» della prossima volta.
        mascheraRiserva = mascheraFiltrata
        mascheraFiltrata = destinazione
        return destinazione
    }

    /// La maschera alla misura dell'immagine, con il bordo rifinito.
    /// - Qualità piena (e sfondo prima di ogni zoom, come sempre): `CIEdgePreserveUpsampleFilter` guidato dal video,
    ///   a una risoluzione con il lato corto al massimo 1080; la maschera gli arriva già alla metà della guida, con le
    ///   proporzioni giuste. Poi piuma fissa (1 px della guida) e soglia morbida.
    /// - Qualità ridotta: ingrandita in modo bilineare a metà risoluzione, ammorbidita (1,5 px) e solo dopo la soglia,
    ///   così la soglia non mostra gli spigoli dell'ingrandimento.
    private func mascheraRifinita(_ bassa: CIImage, immagine: CIImage, info: InfoFotogramma,
                                  morbidezza: CGFloat) -> CIImage {
        let estensione = immagine.extent
        let misuraBassa = bassa.extent
        guard misuraBassa.width > 0, misuraBassa.height > 0, estensione.width > 0, estensione.height > 0 else {
            return bassa
        }
        if info.qualita == .piena, info.trasformazione.isIdentity, estensione.origin == .zero {
            let riduzione = min(1, Self.latoGuida / min(estensione.width, estensione.height))
            let guida = riduzione < 1
                ? immagine.transformed(by: CGAffineTransform(scaleX: riduzione, y: riduzione))
                : immagine
            let misuraGuida = CGRect(x: 0, y: 0, width: (estensione.width * riduzione).rounded(.down),
                                     height: (estensione.height * riduzione).rounded(.down))
            let misuraMezza = CGRect(x: 0, y: 0, width: (misuraGuida.width / 2).rounded(.down),
                                     height: (misuraGuida.height / 2).rounded(.down))
            let mezza = bassa
                .transformed(by: CGAffineTransform(scaleX: misuraMezza.width / misuraBassa.width,
                                                   y: misuraMezza.height / misuraBassa.height))
                .clampedToExtent()
                .cropped(to: misuraMezza)
            let rifinitura = CIFilter.edgePreserveUpsample()
            rifinitura.inputImage = guida.cropped(to: misuraGuida)
            rifinitura.smallImage = mezza
            rifinitura.spatialSigma = 3
            rifinitura.lumaSigma = 0.15
            let rifinita = (rifinitura.outputImage ?? mezza.transformed(by: CGAffineTransform(scaleX: 2, y: 2)))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 1)
                .cropped(to: misuraGuida)
            return Self.sogliaMorbida(rifinita, larghezza: morbidezza)
                .transformed(by: CGAffineTransform(scaleX: estensione.width / misuraGuida.width,
                                                   y: estensione.height / misuraGuida.height))
                .clampedToExtent()
                .cropped(to: estensione)
        }
        // Dalla maschera a metà del fotogramma d'origine, poi (dopo la soglia) al fotogramma intero e dove l'hanno
        // spostato gli effetti prima (inquadratura).
        let misuraMezza = CGRect(x: 0, y: 0, width: max(CGFloat(info.larghezza / 2), 1),
                                 height: max(CGFloat(info.altezza / 2), 1))
        let mezza = bassa
            .transformed(by: CGAffineTransform(scaleX: misuraMezza.width / misuraBassa.width,
                                               y: misuraMezza.height / misuraBassa.height))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 1.5)
            .cropped(to: misuraMezza)
        let alFotogramma = CGAffineTransform(scaleX: CGFloat(info.larghezza) / misuraMezza.width,
                                             y: CGFloat(info.altezza) / misuraMezza.height)
        return Self.sogliaMorbida(mezza, larghezza: morbidezza)
            .transformed(by: alFotogramma.concatenating(info.trasformazione))
            .clampedToExtent()
            .cropped(to: estensione)
    }

    /// Soglia morbida attorno a 0,5, larga `larghezza`: t = (valore − (0,5 − larghezza/2)) / larghezza tra 0 e 1,
    /// poi smoothstep 3t² − 2t³ (nessuno spigolo all'inizio e alla fine della sfumatura).
    private static func sogliaMorbida(_ maschera: CIImage, larghezza: CGFloat) -> CIImage {
        let ampiezza = min(max(larghezza, 0.05), 1)
        let pendenza = 1 / ampiezza
        let rampa = lineare(maschera, pendenza: pendenza, scostamento: -(0.5 - ampiezza / 2) * pendenza)
        let curva = CIFilter.colorPolynomial()
        curva.inputImage = rampa
        let smoothstep = CIVector(x: 0, y: 0, z: 3, w: -2)
        curva.redCoefficients = smoothstep
        curva.greenCoefficients = smoothstep
        curva.blueCoefficients = smoothstep
        curva.alphaCoefficients = CIVector(x: 1, y: 0, z: 0, w: 0)
        return curva.outputImage ?? rampa
    }

    /// Il primo canale copiato negli altri: la maschera a un canale diventa grigia comunque Core Image la legga.
    private static func grigio(_ immagine: CIImage) -> CIImage {
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

    /// valore × pendenza + scostamento, tra 0 e `massimo`; alfa a 1. I parametri sono solo numeri del filtro: cambiarli
    /// non crea filtri nuovi.
    private static func lineare(_ maschera: CIImage, pendenza: CGFloat, scostamento: CGFloat,
                                massimo: CGFloat = 1) -> CIImage {
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

    /// Buffer BGRA per la maschera filtrata (i quattro canali uguali): il formato che Core Image scrive sempre.
    private static func creaBuffer(larghezza: Int, altezza: Int) -> CVPixelBuffer? {
        let attributi: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var buffer: CVPixelBuffer?
        let esito = CVPixelBufferCreate(kCFAllocatorDefault, larghezza, altezza, kCVPixelFormatType_32BGRA,
                                        attributi as CFDictionary, &buffer)
        return esito == kCVReturnSuccess ? buffer : nil
    }

    // MARK: Sfocato

    /// Lo sfondo sfocato senza la persona (sfocatura normalizzata), alla misura dell'immagine.
    /// 1. Riduzione: `sigmaPiccola / sigma`, così in piccolo il raggio è sempre 2,5 px (con la qualità piena una
    ///    riduzione di qualità, che non brulica).
    /// 2. La persona, un po' allargata (soglia a 0,15…0,65), esce dall'immagine: colore × (1 − maschera) con
    ///    alfa (1 − maschera). La maschera arriva al massimo a 0,99: l'alfa non è mai 0 e la divisione dopo non
    ///    produce neri (dentro la persona, dove non c'è sfondo vicino, resta il suo colore, coperto comunque).
    /// 3. Sfocatura dei quattro canali, poi colore ÷ alfa (`unpremultiplyingAlpha`) e alfa a 1.
    /// 4. Ritorno alla misura dell'immagine (bilineare: dopo la sfocatura è liscia).
    private func sfocataSenzaAlone(_ immagine: CIImage, bassa: CIImage, info: InfoFotogramma,
                                   intensita: Double) -> CIImage {
        let estensione = immagine.extent
        let misuraBassa = bassa.extent
        guard misuraBassa.width > 0, misuraBassa.height > 0, estensione.width > 0, estensione.height > 0 else {
            return immagine
        }
        let riferimento = min(estensione.width, estensione.height) / 1080
        let sigma = CGFloat(Self.sigmaSfocatura(intensita)) * riferimento
        let scala = min(1, Self.sigmaPiccola / max(sigma, 0.1))
        let riduzione = CGAffineTransform(scaleX: scala, y: scala)
        let piccola = info.qualita == .piena && scala < 1
            ? immagine.transformed(by: riduzione, highQualityDownsample: true)
            : immagine.transformed(by: riduzione)
        let misura = piccola.extent

        let allaPiccola = CGAffineTransform(scaleX: CGFloat(info.larghezza) / misuraBassa.width,
                                            y: CGFloat(info.altezza) / misuraBassa.height)
            .concatenating(info.trasformazione)
            .concatenating(riduzione)
        let persona = Self.lineare(bassa.transformed(by: allaPiccola), pendenza: 2, scostamento: -0.3, massimo: 0.99)
            .clampedToExtent()
            .cropped(to: misura)
        let senzaPersona = CIFilter.blendWithMask()
        senzaPersona.inputImage = CIImage(color: CIColor.clear).cropped(to: misura)
        senzaPersona.backgroundImage = piccola
        senzaPersona.maskImage = persona
        let sfocata = (senzaPersona.outputImage ?? piccola)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(Self.sigmaPiccola))
            .cropped(to: misura)
            .unpremultiplyingAlpha()
            .settingAlphaOne(in: misura)
        let ritorno = CGAffineTransform(translationX: -misura.minX, y: -misura.minY)
            .concatenating(CGAffineTransform(scaleX: estensione.width / max(misura.width, 1),
                                             y: estensione.height / max(misura.height, 1)))
            .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
        return sfocata.transformed(by: ritorno).clampedToExtent().cropped(to: estensione)
    }

    // MARK: Sostituito

    /// L'immagine scelta alla misura del video, disegnata una volta e poi riusata finché non cambia.
    private func immagineSfondo(estensione: CGRect) -> CIImage {
        let (scelta, versione) = blocco.withLock { (immagineScelta, versioneImmagine) }
        let spostamento = CGAffineTransform(translationX: estensione.minX, y: estensione.minY)
        guard let scelta else {
            return CIImage(color: CIColor(color: UIColor(Tema.fondo))).cropped(to: estensione)
        }
        let larghezza = Int(estensione.width)
        let altezza = Int(estensione.height)
        let chiave = "\(versione)-\(larghezza)x\(altezza)"
        if let sfondoDisegnato, sfondoDisegnato.chiave == chiave {
            return sfondoDisegnato.immagine.transformed(by: spostamento)
        }
        guard let buffer = Self.disegna(scelta, larghezza: larghezza, altezza: altezza) else {
            return CIImage(color: CIColor(color: UIColor(Tema.fondo))).cropped(to: estensione)
        }
        let immagine = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: Self.sRGB])
        sfondoDisegnato = (chiave, immagine)
        return immagine.transformed(by: spostamento)
    }

    /// L'immagine a riempire (come «aspect fill»), centrata, in un buffer BGRA della misura del video.
    private static func disegna(_ immagine: CGImage, larghezza: Int, altezza: Int) -> CVPixelBuffer? {
        guard larghezza > 0, altezza > 0, immagine.width > 0, immagine.height > 0,
              let buffer = creaBuffer(larghezza: larghezza, altezza: altezza) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let contesto = CGContext(data: base, width: larghezza, height: altezza, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: sRGB,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let misura = CGSize(width: larghezza, height: altezza)
        let origine = CGSize(width: immagine.width, height: immagine.height)
        let scala = max(misura.width / origine.width, misura.height / origine.height)
        let disegnata = CGSize(width: origine.width * scala, height: origine.height * scala)
        // Core Graphics disegna l'immagine dritta nel suo sistema (origine in basso a sinistra), come la legge
        // Core Image dal buffer: non serve girare nulla.
        contesto.interpolationQuality = .high
        contesto.draw(immagine, in: CGRect(x: (misura.width - disegnata.width) / 2,
                                           y: (misura.height - disegnata.height) / 2,
                                           width: disegnata.width, height: disegnata.height))
        return buffer
    }
}
