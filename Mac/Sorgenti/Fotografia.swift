import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Foto dal computer (funzione 35): l'ultima immagine dell'iPhone in Immagini › WebcamLR.
enum Fotografia {
    enum Errore: LocalizedError {
        case nessunVideo
        case salvataggio

        var errorDescription: String? {
            switch self {
            case .nessunVideo: "Non c'è ancora video da fotografare."
            case .salvataggio: "Non riesco a salvare la foto in Immagini."
            }
        }
    }

    static func cartella() throws -> URL {
        guard let immagini = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first else {
            throw Errore.salvataggio
        }
        let cartella = immagini.appending(path: "WebcamLR", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        return cartella
    }

    /// Salva in PNG e restituisce il file, per mostrarlo nel Finder.
    static func salva(_ immagine: CGImage) throws -> URL {
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        let file = try cartella().appending(path: "WebcamLR \(formato.string(from: .now)).png")
        guard let destinazione = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Errore.salvataggio
        }
        CGImageDestinationAddImage(destinazione, immagine, nil)
        guard CGImageDestinationFinalize(destinazione) else { throw Errore.salvataggio }
        return file
    }
}
