import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import Stile
import SwiftUI
import UIKit
import WebcamLRProtocollo

/// Sfondo sfocato o sostituito (P14), con la maschera della persona di `AnalisiFotogramma`
/// (`VNGeneratePersonSegmentationRequest`, `.balanced`, circa 10 volte al secondo su un'altra coda).
///
/// - La maschera arriva piccola e a frequenza ridotta: ogni maschera nuova si mescola con la precedente (media
///   mobile, sulla GPU, alla sua risoluzione) e così il bordo non sfarfalla; poi si sfuma e si allarga
///   all'immagine. Fino alla prima maschera il video passa intatto.
/// - «Sfocato»: la sfocatura si calcola a un quarto della risoluzione (un ottavo con la qualità ridotta) e si
///   riporta a piena misura: costa poco anche con il raggio massimo. `intensita` 0…1 = raggio da 10 a 42 px a 1080p
///   (bug 7: «Poco» dal computer è una sfocatura morbida ma visibile, tipo bokeh leggero; prima partiva da 6 px e
///   a intensità bassa quasi non si vedeva).
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
            sfondo = immagineSfondo(estensione: estensione)
        } else {
            sfondo = sfocata(immagine, intensita: intensita, qualita: info.qualita)
        }
        let unione = CIFilter.blendWithMask()
        unione.inputImage = immagine
        unione.backgroundImage = sfondo
        unione.maskImage = maschera
        return unione.outputImage ?? immagine
    }

    /// 1.14: dopo un cambio di geometria (specchio, obiettivo, rotazione) la media mobile non deve mescolare la
    /// maschera vecchia con quella nuova: si riparte dalla prima maschera nuova (fino ad allora video intatto).
    func geometriaCambiata(_ cambio: CambioGeometria) {
        mascheraLivellata = nil
        ultimaMaschera = -1
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
        let raggio = (10 + intensita * 32) * riferimento
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
