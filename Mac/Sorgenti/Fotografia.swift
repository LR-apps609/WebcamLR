import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Foto dal computer (funzione 35): l'ultima immagine del telefono in Immagini › WebcamLR.
enum Fotografia {
    enum Errore: LocalizedError {
        case nessunVideo
        /// Il telefono è in pausa o il collegamento è interrotto: a schermo c'è l'attesa, non il video.
        case videoFermo
        case salvataggio
        case registrazione

        var errorDescription: String? {
            switch self {
            case .nessunVideo: String(localized: "Non c'è ancora video: collega il telefono e riprova.")
            case .videoFermo: String(localized: "Il video del telefono è fermo (in pausa o in attesa): riprova quando torna.")
            case .salvataggio: String(localized: "Non riesco a salvare in Immagini › WebcamLR: controlla lo spazio sul disco e riprova.")
            case .registrazione: String(localized: "Non riesco a creare la registrazione in Filmati › WebcamLR: controlla lo spazio sul disco e riprova.")
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

    /// Come `fileLibero`, ma il file si crea subito, vuoto e in modo esclusivo (O_EXCL): due foto salvate insieme
    /// non scelgono lo stesso nome mentre il PNG si codifica (il file comparirebbe solo alla fine).
    static func fileRiservato(in cartella: URL, estensione: String) throws -> URL {
        let base = "WebcamLR \(nomeData())"
        var file = cartella.appending(path: "\(base).\(estensione)")
        var numero = 2
        while true {
            let descrittore = open(file.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL, 0o644)
            if descrittore >= 0 {
                close(descrittore)
                return file
            }
            guard errno == EEXIST else { throw Errore.salvataggio }
            file = cartella.appending(path: "\(base) (\(numero)).\(estensione)")
            numero += 1
        }
    }

    static func nomeData() -> String {
        let formato = DateFormatter()
        // Nel nome del file: «WebcamLR 2026-10-24 alle 09.41.05», in inglese «… at 09.41.05» (P22).
        formato.dateFormat = String(localized: "yyyy-MM-dd 'alle' HH.mm.ss",
                                    comment: "Formato della data nel nome dei file di foto e registrazioni: tra apici il testo fisso.")
        return formato.string(from: .now)
    }

    /// Salva in PNG e restituisce il file, per mostrarlo nel Finder.
    static func salva(_ immagine: CGImage) throws -> URL {
        let file = try fileRiservato(in: cartella(), estensione: "png")
        guard let destinazione = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            try? FileManager.default.removeItem(at: file)
            throw Errore.salvataggio
        }
        CGImageDestinationAddImage(destinazione, immagine, nil)
        guard CGImageDestinationFinalize(destinazione) else {
            // Niente file vuoto nella cartella al posto della foto.
            try? FileManager.default.removeItem(at: file)
            throw Errore.salvataggio
        }
        return file
    }
}
