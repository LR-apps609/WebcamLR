import CoreImage
import Foundation
import Stile
import SwiftUI
import UIKit

/// Sottopancia con nome e ruolo e logo piccolo (P17), sopra a tutto (`FaseEffetto.scritta`).
///
/// - Sottopancia in basso a sinistra: barra scura arrotondata e un po' trasparente, filo dell'accento a sinistra, nome in
///   Barlow Condensed Bold e ruolo in maiuscolo (caratteri e colori di `Stile`), dentro i margini di sicurezza.
///   Misure in proporzione al lato corto del video: a 720p, 1080p e 4K occupa la stessa parte dell'immagine.
/// - Logo in alto a destra, al massimo il 9% dell'altezza, con la trasparenza del file.
/// - Si disegna con UIKit una volta sola e si tiene come `CIImage` finché testo, logo o misura non cambiano.
/// - Specchio: la connessione di cattura specchia il video **prima** degli effetti, e la scritta si aggiunge dopo.
///   Così chi guarda la legge sempre dritta, con o senza «Specchia l'immagine inviata»: non serve disegnarla al
///   contrario. (Solo l'anteprima di sé nell'app di chiamata, se quell'app la specchia, la mostra rovesciata.)
final class EffettoScritta: Effetto, @unchecked Sendable {
    struct Contenuto: Equatable, Sendable {
        var nome = ""
        var ruolo = ""
        var mostraLogo = true
    }

    let nome = "Scritta"
    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var interno = Contenuto()
    private var logo: CGImage?
    private var versioneLogo = 0
    // Solo sulla coda di cattura.
    private var disegnate: (chiave: String, scritta: CIImage?, logo: CIImage?)?

    var contenuto: Contenuto {
        get { blocco.withLock { interno } }
        set { blocco.withLock { interno = newValue } }
    }

    /// Il logo già ridotto (lato lungo al massimo 512 px); `nil` per toglierlo.
    func impostaLogo(_ immagine: CGImage?) {
        blocco.withLock {
            logo = immagine
            versioneLogo += 1
        }
    }

    var attivo: Bool {
        blocco.withLock {
            !interno.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (interno.mostraLogo && logo != nil)
        }
    }

    /// 1.14: nome e logo non devono sparire quando la resa è in affanno (costano poco: immagini già disegnate).
    var essenziale: Bool { true }

    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage {
        let (attuale, logoAttuale, versione) = blocco.withLock { (interno, logo, versioneLogo) }
        let estensione = immagine.extent
        let misura = CGSize(width: estensione.width, height: estensione.height)
        let chiave = "\(attuale.nome)|\(attuale.ruolo)|\(attuale.mostraLogo)|\(versione)|\(Int(misura.width))x\(Int(misura.height))"
        if disegnate?.chiave != chiave {
            let nome = attuale.nome.trimmingCharacters(in: .whitespacesAndNewlines)
            let ruolo = attuale.ruolo.trimmingCharacters(in: .whitespacesAndNewlines)
            disegnate = (chiave,
                         nome.isEmpty ? nil : Self.sottopancia(nome: nome, ruolo: ruolo, video: misura),
                         attuale.mostraLogo ? logoAttuale.flatMap { Self.logo($0, video: misura) } : nil)
        }
        var risultato = immagine
        let spostamento = CGAffineTransform(translationX: estensione.minX, y: estensione.minY)
        if let scritta = disegnate?.scritta {
            risultato = scritta.transformed(by: spostamento).composited(over: risultato)
        }
        if let logo = disegnate?.logo {
            risultato = logo.transformed(by: spostamento).composited(over: risultato)
        }
        return risultato
    }

    // MARK: Disegno

    /// Margini di sicurezza: 4,5% dei lati in orizzontale, 6% in verticale (la barra delle app di chiamata).
    private static func margini(_ video: CGSize) -> CGSize {
        CGSize(width: (video.width * 0.045).rounded(), height: (video.height * 0.06).rounded())
    }

    /// 1.14: i colori di `Tema` (fondo verde scuro, accento salvia), non più il ciano e il fondo della vecchia bozza.
    private static let coloreNome = UIColor(Tema.testo)
    private static let coloreRuolo = UIColor(Tema.accentoChiaro)
    private static let coloreBarra = UIColor(Tema.fondo).withAlphaComponent(0.8)
    private static let coloreFilo = UIColor(Tema.accento)

    /// Il sottopancia già al suo posto nel video (origine in basso a sinistra, come Core Image).
    static func sottopancia(nome: String, ruolo: String, video: CGSize) -> CIImage? {
        let unita = min(video.width, video.height) / 1080
        guard unita > 0 else { return nil }
        let margini = Self.margini(video)
        let paragrafo = NSMutableParagraphStyle()
        paragrafo.lineBreakMode = .byTruncatingTail
        let attributiNome: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "BarlowCondensed-Bold", size: 52 * unita) ?? .systemFont(ofSize: 48 * unita, weight: .bold),
            .foregroundColor: coloreNome,
            .paragraphStyle: paragrafo
        ]
        let attributiRuolo: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "BarlowCondensed-SemiBold", size: 26 * unita) ?? .systemFont(ofSize: 24 * unita, weight: .semibold),
            .foregroundColor: coloreRuolo,
            .kern: 1.6 * unita,
            .paragraphStyle: paragrafo
        ]
        let testoNome = NSAttributedString(string: nome, attributes: attributiNome)
        let testoRuolo = ruolo.isEmpty ? nil : NSAttributedString(string: ruolo.uppercased(), attributes: attributiRuolo)

        let filo = (6 * unita).rounded()
        let orizzontale = (26 * unita).rounded()
        let verticale = (14 * unita).rounded()
        let spazioRighe = (2 * unita).rounded()
        // Al massimo il 60% della larghezza: un nome lunghissimo si tronca con «…».
        let larghezzaTestoMassima = max(video.width * 0.6 - filo - orizzontale * 2, 40 * unita)
        let misuraNome = testoNome.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin], context: nil).size
        let misuraRuolo = testoRuolo?.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin], context: nil).size ?? .zero
        let larghezzaTesto = min(ceil(max(misuraNome.width, misuraRuolo.width)), larghezzaTestoMassima)
        let altezzaNome = ceil(misuraNome.height)
        let altezzaRuolo = testoRuolo == nil ? 0 : ceil(misuraRuolo.height)
        let barra = CGSize(width: filo + orizzontale * 2 + larghezzaTesto,
                           height: verticale * 2 + altezzaNome + (testoRuolo == nil ? 0 : spazioRighe + altezzaRuolo))

        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = false
        let disegno = UIGraphicsImageRenderer(size: barra, format: formato).image { contesto in
            let forma = UIBezierPath(roundedRect: CGRect(origin: .zero, size: barra), cornerRadius: 14 * unita)
            coloreBarra.setFill()
            forma.fill()
            contesto.cgContext.saveGState()
            forma.addClip()
            coloreFilo.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: filo, height: barra.height))
            contesto.cgContext.restoreGState()
            let x = filo + orizzontale
            testoNome.draw(with: CGRect(x: x, y: verticale, width: larghezzaTesto, height: altezzaNome),
                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            testoRuolo?.draw(with: CGRect(x: x, y: verticale + altezzaNome + spazioRighe, width: larghezzaTesto,
                                          height: altezzaRuolo),
                             options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
        guard let immagine = disegno.cgImage else { return nil }
        return CIImage(cgImage: immagine).transformed(by: CGAffineTransform(translationX: margini.width,
                                                                            y: margini.height))
    }

    /// Il logo in alto a destra, al massimo il 9% dell'altezza e il 22% della larghezza.
    static func logo(_ logo: CGImage, video: CGSize) -> CIImage? {
        let origine = CGSize(width: logo.width, height: logo.height)
        guard origine.width > 0, origine.height > 0, video.width > 0, video.height > 0 else { return nil }
        let margini = Self.margini(video)
        let scala = min(min(video.width, video.height) * 0.09 / origine.height, video.width * 0.22 / origine.width)
        let misura = CGSize(width: (origine.width * scala).rounded(), height: (origine.height * scala).rounded())
        guard misura.width >= 1, misura.height >= 1 else { return nil }
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = false
        let disegno = UIGraphicsImageRenderer(size: misura, format: formato).image { _ in
            UIImage(cgImage: logo).draw(in: CGRect(origin: .zero, size: misura))
        }
        guard let immagine = disegno.cgImage else { return nil }
        return CIImage(cgImage: immagine).transformed(by: CGAffineTransform(
            translationX: video.width - margini.width - misura.width,
            y: video.height - margini.height - misura.height))
    }
}
