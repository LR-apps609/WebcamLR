import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import UIKit
import WebcamLRProtocollo

/// Gli sfondi già pronti per «sostituito», più la foto scelta dall'utente.
enum SfondoPronto: String, CaseIterable, Identifiable, Sendable {
    /// Sfumatura da studio con i colori di LR Apps (verde-grigio scuro, un alone ciano).
    case studio
    /// Un ufficio luminoso e sfocato: finestra, mensola, una pianta.
    case ufficio
    /// Tinta unita scura.
    case scuro
    /// La foto scelta con «La tua foto», salvata nel contenitore dell'app.
    case foto

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .studio: "Studio"
        case .ufficio: "Ufficio"
        case .scuro: "Scuro"
        case .foto: "La tua foto"
        }
    }
}

/// Sfondo sfocato o sostituito (P14), con la maschera della persona di `AnalisiFotogramma`
/// (`VNGeneratePersonSegmentationRequest`, `.balanced`, circa 10 volte al secondo su un'altra coda).
///
/// - La maschera arriva piccola e a frequenza ridotta: ogni maschera nuova si mescola con la precedente (media
///   mobile, sulla GPU, alla sua risoluzione) e così il bordo non sfarfalla; poi si sfuma e si allarga
///   all'immagine. Fino alla prima maschera il video passa intatto.
/// - «Sfocato»: la sfocatura si calcola a un quarto della risoluzione (un ottavo con la qualità ridotta) e si
///   riporta a piena misura: costa poco anche con il raggio massimo. `intensita` 0…1 = raggio da 6 a 36 px a 1080p.
/// - «Sostituito»: uno degli `SfondoPronto`, disegnato una volta alla misura del video e tenuto in un buffer
///   (IOSurface, nessuna copia per fotogramma). `intensita` = quanto è netto il bordo.
/// - Con «Ritratto» di iOS acceso lo sfondo è già sfocato dal sistema: «sfocato» non si somma (resta scelto, ma
///   l'effetto si spegne e il foglio «Effetti» lo dice). «Sostituito» invece funziona lo stesso.
final class EffettoSfondo: Effetto, @unchecked Sendable {
    struct Impostazioni: Equatable, Sendable {
        /// Uno dei `ModiSfondo`.
        var modo = ModiSfondo.nessuno
        var intensita = 0.5
        var sfondo = SfondoPronto.studio
        /// «Ritratto» (Effetti video di iOS) acceso: lo sfondo è già sfocato.
        var ritrattoDiSistema = false
    }

    let nome = "Sfondo"
    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var interne = Impostazioni()
    private var fotoUtente: CGImage?
    private var versioneFoto = 0

    // Solo sulla coda di cattura.
    private var mascheraLivellata: CVPixelBuffer?
    private var mascheraRiserva: CVPixelBuffer?
    private var ultimaMaschera: TimeInterval = -1
    private var sfondoDisegnato: (chiave: String, immagine: CIImage)?

    /// Peso della maschera nuova nella media mobile: più alto segue prima i movimenti, più basso sfarfalla meno.
    private static let pesoMascheraNuova: CGFloat = 0.65
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    var impostazioni: Impostazioni {
        get { blocco.withLock { interne } }
        set { blocco.withLock { interne = newValue } }
    }

    /// La foto dell'utente, già girata dritta e ridotta (lato lungo al massimo 1920 px). `nil` per toglierla.
    func impostaFoto(_ immagine: CGImage?) {
        blocco.withLock {
            fotoUtente = immagine
            versioneFoto += 1
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

    func applica(_ immagine: CIImage, contesto info: InfoFotogramma) -> CIImage {
        let attuali = impostazioni
        // Una maschera vecchia (effetto appena riacceso, analisi ferma) non si usa: meglio il video intatto.
        guard let nuova = info.maschera, ProcessInfo.processInfo.systemUptime - nuova.quando < 1,
              let livellata = livella(nuova) else { return immagine }
        let estensione = immagine.extent
        let intensita = CGFloat(min(max(attuali.intensita, 0), 1))
        let sostituito = attuali.modo == ModiSfondo.sostituito

        // Bordo: sfumato alla risoluzione della maschera (costa pochissimo), più o meno netto.
        var maschera = CIImage(cvPixelBuffer: livellata, options: [.colorSpace: NSNull()])
        let misuraMaschera = maschera.extent
        let piuma = sostituito ? 0.6 + (1 - intensita) * 2.4 : 1.2
        maschera = maschera.clampedToExtent().applyingGaussianBlur(sigma: Double(piuma)).cropped(to: misuraMaschera)
        // Contrasto della maschera: con «sostituito» e intensità alta il bordo è più deciso.
        let pendenza: CGFloat = sostituito ? 1.2 + intensita * 1.8 : 1.6
        maschera = Self.contrasto(maschera, pendenza: pendenza)
        // Dalla maschera al fotogramma d'origine, poi dove l'hanno spostato gli effetti prima (inquadratura).
        let scala = CGAffineTransform(scaleX: CGFloat(info.larghezza) / max(misuraMaschera.width, 1),
                                      y: CGFloat(info.altezza) / max(misuraMaschera.height, 1))
        maschera = maschera.transformed(by: scala.concatenating(info.trasformazione))
            .clampedToExtent()
            .cropped(to: estensione)

        let sfondo: CIImage
        if sostituito {
            sfondo = immagineSfondo(attuali.sfondo, estensione: estensione)
        } else {
            sfondo = sfocata(immagine, intensita: intensita, qualita: info.qualita)
        }
        let unione = CIFilter.blendWithMask()
        unione.inputImage = immagine
        unione.backgroundImage = sfondo
        unione.maskImage = maschera
        return unione.outputImage ?? immagine
    }

    // MARK: Maschera

    /// La maschera mediata nel tempo. Si rifà solo quando arriva una maschera nuova (circa 10 volte al secondo).
    private func livella(_ nuova: MascheraPersona) -> CVPixelBuffer? {
        guard nuova.quando != ultimaMaschera else { return mascheraLivellata }
        ultimaMaschera = nuova.quando
        let larghezza = CVPixelBufferGetWidth(nuova.maschera)
        let altezza = CVPixelBufferGetHeight(nuova.maschera)
        guard larghezza > 0, altezza > 0 else { return mascheraLivellata }

        var riserva = mascheraRiserva
        if let attuale = riserva,
           CVPixelBufferGetWidth(attuale) != larghezza || CVPixelBufferGetHeight(attuale) != altezza {
            riserva = nil
        }
        if riserva == nil { riserva = Self.creaBuffer(larghezza: larghezza, altezza: altezza) }
        guard let destinazione = riserva else { return mascheraLivellata }

        let ingresso = Self.grigio(CIImage(cvPixelBuffer: nuova.maschera, options: [.colorSpace: NSNull()]))
        var risultato = ingresso
        if let precedente = mascheraLivellata,
           CVPixelBufferGetWidth(precedente) == larghezza, CVPixelBufferGetHeight(precedente) == altezza {
            // vecchia × (1 - peso) + nuova × peso.
            let vecchia = CIImage(cvPixelBuffer: precedente, options: [.colorSpace: NSNull()])
            let media = CIFilter.dissolveTransition()
            media.inputImage = vecchia
            media.targetImage = ingresso
            media.time = Float(Self.pesoMascheraNuova)
            risultato = media.outputImage ?? ingresso
        }
        ContestiEffetti.maschere.render(risultato, to: destinazione,
                                        bounds: CGRect(x: 0, y: 0, width: larghezza, height: altezza),
                                        colorSpace: nil)
        // Due buffer a turno: quello appena scritto diventa il «precedente» della prossima volta.
        mascheraRiserva = mascheraLivellata
        mascheraLivellata = destinazione
        return destinazione
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

    /// (valore - 0,5) × pendenza + 0,5, tra 0 e 1.
    private static func contrasto(_ maschera: CIImage, pendenza: CGFloat) -> CIImage {
        let scostamento = 0.5 - 0.5 * pendenza
        let filtro = CIFilter.colorMatrix()
        filtro.inputImage = maschera
        filtro.rVector = CIVector(x: pendenza, y: 0, z: 0, w: 0)
        filtro.gVector = CIVector(x: 0, y: pendenza, z: 0, w: 0)
        filtro.bVector = CIVector(x: 0, y: 0, z: pendenza, w: 0)
        filtro.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        filtro.biasVector = CIVector(x: scostamento, y: scostamento, z: scostamento, w: 0)
        let limiti = CIFilter.colorClamp()
        limiti.inputImage = filtro.outputImage ?? maschera
        limiti.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        limiti.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return limiti.outputImage ?? maschera
    }

    /// Buffer BGRA per la maschera mediata (i quattro canali uguali): il formato che Core Image scrive sempre.
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

    private func sfocata(_ immagine: CIImage, intensita: CGFloat, qualita: QualitaEffetti) -> CIImage {
        let estensione = immagine.extent
        let riferimento = min(estensione.width, estensione.height) / 1080
        let raggio = (6 + intensita * 30) * riferimento
        let riduzione: CGFloat = qualita == .ridotta ? 0.125 : 0.25
        let piccola: CIImage
        if qualita == .ridotta {
            piccola = immagine.transformed(by: CGAffineTransform(scaleX: riduzione, y: riduzione))
        } else {
            // Lanczos: rimpicciolendo così tanto la semplice interpolazione lascerebbe un fondo che brulica.
            let scala = CIFilter.lanczosScaleTransform()
            scala.inputImage = immagine
            scala.scale = Float(riduzione)
            scala.aspectRatio = 1
            piccola = scala.outputImage ?? immagine.transformed(by: CGAffineTransform(scaleX: riduzione, y: riduzione))
        }
        let misura = piccola.extent
        let sfocata = piccola.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(raggio * riduzione))
            .cropped(to: misura)
        let ritorno = CGAffineTransform(scaleX: estensione.width / max(misura.width, 1),
                                        y: estensione.height / max(misura.height, 1))
        return sfocata.transformed(by: ritorno).clampedToExtent().cropped(to: estensione)
    }

    // MARK: Sostituito

    /// Lo sfondo scelto alla misura del video, disegnato una volta e poi riusato finché non cambia.
    private func immagineSfondo(_ scelto: SfondoPronto, estensione: CGRect) -> CIImage {
        let (foto, versione) = blocco.withLock { (fotoUtente, versioneFoto) }
        let effettivo: SfondoPronto = scelto == .foto && foto == nil ? .studio : scelto
        let larghezza = Int(estensione.width)
        let altezza = Int(estensione.height)
        let chiave = "\(effettivo.rawValue)-\(versione)-\(larghezza)x\(altezza)"
        if let sfondoDisegnato, sfondoDisegnato.chiave == chiave {
            return sfondoDisegnato.immagine.transformed(by: CGAffineTransform(translationX: estensione.minX,
                                                                              y: estensione.minY))
        }
        guard let buffer = Self.disegna(effettivo, foto: foto, larghezza: larghezza, altezza: altezza) else {
            return CIImage(color: CIColor(red: 0.086, green: 0.125, blue: 0.122)).cropped(to: estensione)
        }
        let immagine = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: Self.sRGB])
        sfondoDisegnato = (chiave, immagine)
        return immagine.transformed(by: CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
    }

    /// Disegna lo sfondo in un buffer BGRA della misura del video (una volta per scelta e misura).
    static func disegna(_ scelto: SfondoPronto, foto: CGImage?, larghezza: Int, altezza: Int) -> CVPixelBuffer? {
        guard larghezza > 0, altezza > 0,
              let buffer = creaBuffer(larghezza: larghezza, altezza: altezza) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let contesto = CGContext(data: base, width: larghezza, height: altezza, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: sRGB,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        let misura = CGSize(width: larghezza, height: altezza)
        // Coordinate come UIKit (origine in alto a sinistra).
        contesto.translateBy(x: 0, y: CGFloat(altezza))
        contesto.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(contesto)
        defer { UIGraphicsPopContext() }
        switch scelto {
        case .studio:
            disegnaStudio(contesto, misura: misura)
        case .ufficio:
            disegnaUfficio(contesto, misura: misura)
        case .scuro:
            disegnaScuro(contesto, misura: misura)
        case .foto:
            if let foto {
                disegnaFoto(foto, in: contesto, misura: misura)
            } else {
                disegnaStudio(contesto, misura: misura)
            }
        }
        return buffer
    }

    /// Una miniatura dello sfondo pronto, per il foglio «Effetti» (non serve per la foto: c'è già).
    static func miniatura(_ scelto: SfondoPronto, misura: CGSize) -> UIImage {
        let formato = UIGraphicsImageRendererFormat()
        formato.opaque = true
        return UIGraphicsImageRenderer(size: misura, format: formato).image { contesto in
            switch scelto {
            case .ufficio: disegnaUfficio(contesto.cgContext, misura: misura)
            case .scuro: disegnaScuro(contesto.cgContext, misura: misura)
            case .studio, .foto: disegnaStudio(contesto.cgContext, misura: misura)
            }
        }
    }

    private static func colore(_ esadecimale: UInt32, _ alfa: CGFloat = 1) -> CGColor {
        UIColor(red: CGFloat(esadecimale >> 16 & 0xFF) / 255, green: CGFloat(esadecimale >> 8 & 0xFF) / 255,
                blue: CGFloat(esadecimale & 0xFF) / 255, alpha: alfa).cgColor
    }

    private static func verticale(_ contesto: CGContext, misura: CGSize, alto: CGColor, basso: CGColor) {
        guard let sfumatura = CGGradient(colorsSpace: sRGB, colors: [alto, basso] as CFArray,
                                         locations: [0, 1]) else { return }
        contesto.drawLinearGradient(sfumatura, start: .zero, end: CGPoint(x: 0, y: misura.height), options: [])
    }

    /// Una macchia morbida: dal colore pieno al trasparente. Sembra già sfocata.
    private static func macchia(_ contesto: CGContext, centro: CGPoint, raggio: CGFloat, colore: CGColor) {
        guard let trasparente = colore.copy(alpha: 0),
              let sfumatura = CGGradient(colorsSpace: sRGB, colors: [colore, trasparente] as CFArray,
                                         locations: [0, 1]) else { return }
        contesto.drawRadialGradient(sfumatura, startCenter: centro, startRadius: 0, endCenter: centro,
                                    endRadius: raggio, options: [])
    }

    /// I colori della bozza: fondo 0F1413, pannelli 232D2A, un alone ciano 6CBCC4 in alto a destra.
    private static func disegnaStudio(_ contesto: CGContext, misura: CGSize) {
        verticale(contesto, misura: misura, alto: colore(0x232D2A), basso: colore(0x0F1413))
        let lato = max(misura.width, misura.height)
        macchia(contesto, centro: CGPoint(x: misura.width * 0.72, y: misura.height * 0.28), raggio: lato * 0.55,
                colore: colore(0x6CBCC4, 0.16))
        macchia(contesto, centro: CGPoint(x: misura.width * 0.18, y: misura.height * 0.9), raggio: lato * 0.45,
                colore: colore(0x1D3436, 0.6))
    }

    /// Un ufficio chiaro fuori fuoco: parete calda, finestra luminosa, mensola di legno, una pianta, una lampada.
    private static func disegnaUfficio(_ contesto: CGContext, misura: CGSize) {
        verticale(contesto, misura: misura, alto: colore(0xD3CCC2), basso: colore(0xA99F93))
        let lato = max(misura.width, misura.height)
        let w = misura.width
        let h = misura.height
        macchia(contesto, centro: CGPoint(x: w * 0.16, y: h * 0.32), raggio: lato * 0.32, colore: colore(0xF6F2EA, 0.95))
        macchia(contesto, centro: CGPoint(x: w * 0.62, y: h * 0.42), raggio: lato * 0.22, colore: colore(0x9C7B5B, 0.45))
        macchia(contesto, centro: CGPoint(x: w * 0.88, y: h * 0.58), raggio: lato * 0.2, colore: colore(0x6F8F6A, 0.6))
        macchia(contesto, centro: CGPoint(x: w * 0.42, y: h * 0.16), raggio: lato * 0.14, colore: colore(0xF6D9A8, 0.55))
        macchia(contesto, centro: CGPoint(x: w * 0.5, y: h * 1.05), raggio: lato * 0.45, colore: colore(0x7D7368, 0.5))
    }

    private static func disegnaScuro(_ contesto: CGContext, misura: CGSize) {
        contesto.setFillColor(colore(0x16201F))
        contesto.fill(CGRect(origin: .zero, size: misura))
        macchia(contesto, centro: CGPoint(x: misura.width / 2, y: misura.height * 0.4),
                raggio: max(misura.width, misura.height) * 0.6, colore: colore(0x1B2321, 0.9))
    }

    /// La foto a riempire (come «aspect fill»), centrata.
    private static func disegnaFoto(_ foto: CGImage, in contesto: CGContext, misura: CGSize) {
        let origine = CGSize(width: foto.width, height: foto.height)
        guard origine.width > 0, origine.height > 0 else { return }
        let scala = max(misura.width / origine.width, misura.height / origine.height)
        let disegnata = CGSize(width: origine.width * scala, height: origine.height * scala)
        let rettangolo = CGRect(x: (misura.width - disegnata.width) / 2, y: (misura.height - disegnata.height) / 2,
                                width: disegnata.width, height: disegnata.height)
        // `UIImage.draw` tiene conto del contesto girato come UIKit.
        UIImage(cgImage: foto).draw(in: rettangolo)
    }
}
