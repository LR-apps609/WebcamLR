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

    static func cartella(_ tipo: FileManager.SearchPathDirectory = .picturesDirectory) throws -> URL {
        guard let base = FileManager.default.urls(for: tipo, in: .userDomainMask).first else {
            throw Errore.salvataggio
        }
        let cartella = base.appending(path: "WebcamLR", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        return cartella
    }

    /// Il file per una nuova registrazione, in Filmati › WebcamLR.
    static func nuovaRegistrazione() throws -> URL {
        try cartella(.moviesDirectory).appending(path: "WebcamLR \(nomeData()).mov")
    }

    static func nomeData() -> String {
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        return formato.string(from: .now)
    }

    /// Salva in PNG e restituisce il file, per mostrarlo nel Finder.
    static func salva(_ immagine: CGImage) throws -> URL {
        let file = try cartella().appending(path: "WebcamLR \(nomeData()).png")
        guard let destinazione = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Errore.salvataggio
        }
        CGImageDestinationAddImage(destinazione, immagine, nil)
        guard CGImageDestinationFinalize(destinazione) else { throw Errore.salvataggio }
        return file
    }
}
