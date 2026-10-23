import AppKit
import Foundation
import Observation

/// Foto e registrazioni dal Mac (funzione 35 del round 1), condivise da finestra, menu e barra in alto.
/// Tutto sulla coda principale; il lavoro sul video lo fa lo `Schermo` sulla sua coda.
@Observable
@MainActor
final class Riprese {
    /// Sotto questa soglia di spazio libero compare l'avviso durante la registrazione (funzione 37).
    static let spazioMinimo: Int64 = 2_000_000_000

    /// Una frase breve dopo una foto o una registrazione; sparisce da sola.
    private(set) var avviso: String?
    /// Quando è iniziata la registrazione in corso; nil se non si registra.
    private(set) var inizioRegistrazione: Date?
    /// Byte già scritti nel file della registrazione, aggiornati ogni secondo.
    private(set) var dimensioneRegistrazione: Int64 = 0
    /// Byte liberi sul disco della registrazione, solo quando sono meno di `spazioMinimo`.
    private(set) var spazioScarso: Int64?

    @ObservationIgnored private let schermo: Schermo
    @ObservationIgnored private var fileRegistrazione: URL?
    @ObservationIgnored private var compitoRegistrazione: Task<Void, Never>?
    @ObservationIgnored private var compitoAvviso: Task<Void, Never>?

    init(schermo: Schermo) {
        self.schermo = schermo
    }

    var registra: Bool { inizioRegistrazione != nil }

    // MARK: - Foto

    /// Foto dal computer: salva in Immagini › WebcamLR e la mostra nel Finder.
    func scattaFoto() {
        schermo.fotografa { immagine in
            Task { @MainActor in
                do {
                    guard let immagine else { throw Fotografia.Errore.nessunVideo }
                    let file = try Fotografia.salva(immagine)
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    self.mostra("Foto salvata in Immagini › WebcamLR")
                } catch {
                    self.mostra(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Registrazione

    func alternaRegistrazione() {
        if registra { fermaRegistrazione() } else { avviaRegistrazione() }
    }

    func avviaRegistrazione() {
        guard !registra else { return }
        do {
            let file = try Fotografia.nuovaRegistrazione()
            schermo.avviaRegistrazione(in: file)
            fileRegistrazione = file
            inizioRegistrazione = .now
            dimensioneRegistrazione = 0
            spazioScarso = nil
            controllaSpazio()
            compitoRegistrazione?.cancel()
            compitoRegistrazione = Task { [weak self] in
                var secondi = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    secondi += 1
                    self.leggiDimensione()
                    // Lo spazio libero cambia piano: basta guardarlo ogni 5 secondi.
                    if secondi % 5 == 0 { self.controllaSpazio() }
                }
            }
        } catch {
            mostra(error.localizedDescription)
        }
    }

    func fermaRegistrazione() {
        guard registra else { return }
        compitoRegistrazione?.cancel()
        compitoRegistrazione = nil
        inizioRegistrazione = nil
        fileRegistrazione = nil
        spazioScarso = nil
        schermo.fermaRegistrazione { file in
            Task { @MainActor in
                if let file {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    self.mostra("Registrazione salvata in Filmati › WebcamLR")
                } else {
                    self.mostra("Niente da salvare: la registrazione parte dal primo fotogramma chiave.")
                }
            }
        }
    }

    /// Dimensione del file in scrittura (funzione 37). Si legge dal disco ogni volta, senza cache.
    private func leggiDimensione() {
        guard let file = fileRegistrazione,
              let attributi = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)),
              let byte = attributi[.size] as? NSNumber else { return }
        dimensioneRegistrazione = byte.int64Value
    }

    /// Spazio libero «per le cose importanti», lo stesso numero che usa il Finder (funzione 37).
    private func controllaSpazio() {
        guard let file = fileRegistrazione else { return }
        var cartella = file.deletingLastPathComponent()
        cartella.removeAllCachedResourceValues()
        guard let valori = try? cartella.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let liberi = valori.volumeAvailableCapacityForImportantUsage else { return }
        spazioScarso = liberi < Self.spazioMinimo ? liberi : nil
    }

    // MARK: - Utilità

    static func testoByte(_ byte: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byte, countStyle: .file)
    }

    func mostra(_ testo: String) {
        compitoAvviso?.cancel()
        avviso = testo
        compitoAvviso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            self.avviso = nil
        }
    }
}
