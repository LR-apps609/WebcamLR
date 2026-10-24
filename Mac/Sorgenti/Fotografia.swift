import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Foto dal computer (funzione 35): l'ultima immagine dell'iPhone in Immagini › WebcamLR.
enum Fotografia {
    enum Errore: LocalizedError {
        case nessunVideo
        case salvataggio
        case registrazione

        var errorDescription: String? {
            switch self {
            case .nessunVideo: "Non c'è ancora video: collega l'iPhone e riprova."
            case .salvataggio: "Non riesco a salvare in Immagini › WebcamLR: controlla lo spazio sul disco e riprova."
            case .registrazione: "Non riesco a creare la registrazione in Filmati › WebcamLR: controlla lo spazio sul disco e riprova."
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
        try fileLibero(in: cartella(.moviesDirectory), estensione: "mov")
    }

    /// «WebcamLR <data>», con « (2)», « (3)»… se esiste già: due foto nello stesso secondo
    /// non si sovrascrivono, e una registrazione non trova il file già lì (non partirebbe).
    static func fileLibero(in cartella: URL, estensione: String) -> URL {
        let base = "WebcamLR \(nomeData())"
        var file = cartella.appending(path: "\(base).\(estensione)")
        var numero = 2
        while FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            file = cartella.appending(path: "\(base) (\(numero)).\(estensione)")
            numero += 1
        }
        return file
    }

    static func nomeData() -> String {
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        return formato.string(from: .now)
    }

    /// Salva in PNG e restituisce il file, per mostrarlo nel Finder.
    static func salva(_ immagine: CGImage) throws -> URL {
        let file = try fileLibero(in: cartella(), estensione: "png")
        guard let destinazione = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Errore.salvataggio
        }
        CGImageDestinationAddImage(destinazione, immagine, nil)
        guard CGImageDestinationFinalize(destinazione) else { throw Errore.salvataggio }
        return file
    }
}
