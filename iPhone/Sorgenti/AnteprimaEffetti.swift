import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Metal
import UIKit

/// L'anteprima con effetti (`PipelineEffetti.anteprimaConEffetti`, B2) e le istantanee per le miniature dei filtri.
///
/// - Con almeno un effetto attivo `PipelineEffetti.elabora` passa qui ogni buffer elaborato: si mostra in
///   `livello` (un `AVSampleBufferDisplayLayer` sopra l'anteprima grezza), subito, senza orologio. È lo stesso
///   buffer che va al codificatore: nessuna resa in più.
/// - Senza effetti `spegni()` nasconde il livello e si torna all'anteprima grezza (costo zero).
/// - L'anteprima con effetti mostra il video **come lo riceve il computer**: non è specchiata come quella grezza
///   della fotocamera frontale, così scritte e logo si leggono dritti.
/// - `istantanea()`: un fotogramma piccolo (lato corto 160 px) per le miniature dei filtri, preso dalla coda di
///   cattura al prossimo fotogramma. Il buffer della cattura non si tiene: si copia subito in piccolo.
final class AnteprimaEffetti: @unchecked Sendable {
    /// Da mettere sopra l'anteprima grezza, con la stessa cornice. Nascosto finché non arriva un buffer elaborato.
    let livello: AVSampleBufferDisplayLayer

    private let blocco = NSLock()
    // Protetti da `blocco`.
    /// Il livello è (o sta per essere) visibile.
    private var visibile = false
    private var richieste: [UUID: CheckedContinuation<CGImage?, Never>] = [:]
    // Solo sulla coda di cattura.
    private var descrizione: CMVideoFormatDescription?

    /// Lato corto dell'istantanea, in pixel: basta per miniature di 64 punti a 2× o 3×.
    private static let latoIstantanea: CGFloat = 160

    init() {
        livello = AVSampleBufferDisplayLayer()
        livello.videoGravity = .resizeAspect
        livello.backgroundColor = UIColor.black.cgColor
        livello.isHidden = true
    }

    // MARK: Dalla coda di cattura

    /// Un buffer elaborato da mostrare subito.
    func mostra(_ buffer: CVPixelBuffer) {
        guard let campione = campione(da: buffer) else { return }
        let renderer = livello.sampleBufferRenderer
        // Dopo un errore (per esempio l'app in sottofondo) il renderer va svuotato prima di accettare altro.
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            renderer.flush()
        }
        renderer.enqueue(campione)
        let daMostrare = blocco.withLock { () -> Bool in
            guard !visibile else { return false }
            visibile = true
            return true
        }
        if daMostrare {
            DispatchQueue.main.async { [livello] in
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                livello.isHidden = false
                CATransaction.commit()
            }
        }
    }

    /// Nessun effetto attivo: si torna all'anteprima grezza. Costa un blocco solo, se era già spento.
    func spegni() {
        let daNascondere = blocco.withLock { () -> Bool in
            guard visibile else { return false }
            visibile = false
            return true
        }
        guard daNascondere else { return }
        DispatchQueue.main.async { [livello] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            livello.isHidden = true
            CATransaction.commit()
            // L'ultimo fotogramma elaborato non deve ricomparire alla prossima accensione.
            livello.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
    }

    /// Per ogni fotogramma, prima degli effetti: se qualcuno aspetta un'istantanea, la prepara ora.
    func considera(_ buffer: CVPixelBuffer) {
        let attese: [CheckedContinuation<CGImage?, Never>] = blocco.withLock {
            guard !richieste.isEmpty else { return [] }
            let tutte = Array(richieste.values)
            richieste.removeAll()
            return tutte
        }
        guard !attese.isEmpty else { return }
        let immagine = Self.piccola(da: buffer)
        for attesa in attese { attesa.resume(returning: immagine) }
    }

    // MARK: Da qualsiasi thread

    /// Il prossimo fotogramma, in piccolo. `nil` se entro un secondo non arriva nulla (fotocamera ferma).
    func istantanea() async -> CGImage? {
        let id = UUID()
        return await withCheckedContinuation { (attesa: CheckedContinuation<CGImage?, Never>) in
            blocco.withLock { richieste[id] = attesa }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                let scaduta = self.blocco.withLock { self.richieste.removeValue(forKey: id) }
                scaduta?.resume(returning: nil)
            }
        }
    }

    // MARK: Interni

    private func campione(da buffer: CVPixelBuffer) -> CMSampleBuffer? {
        if descrizione == nil || !CMVideoFormatDescriptionMatchesImageBuffer(descrizione!, imageBuffer: buffer) {
            var nuova: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                         formatDescriptionOut: &nuova)
            descrizione = nuova
        }
        guard let descrizione else { return nil }
        var tempi = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        var creato: CMSampleBuffer?
        let esito = CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                             formatDescription: descrizione, sampleTiming: &tempi,
                                                             sampleBufferOut: &creato)
        guard esito == noErr, let campione = creato else { return nil }
        // Subito, senza orologio: è un'anteprima dal vivo.
        if let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: true),
           CFArrayGetCount(allegati) > 0 {
            let dizionario = unsafeBitCast(CFArrayGetValueAtIndex(allegati, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dizionario,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return campione
    }

    /// Il fotogramma rimpicciolito, in un'immagine indipendente dal buffer della cattura.
    private static func piccola(da buffer: CVPixelBuffer) -> CGImage? {
        let immagine = CIImage(cvPixelBuffer: buffer)
        let estensione = immagine.extent
        let latoCorto = min(estensione.width, estensione.height)
        guard latoCorto > 0 else { return nil }
        let scala = min(1, latoIstantanea / latoCorto)
        let piccola = immagine.transformed(by: CGAffineTransform(scaleX: scala, y: scala))
        return ContestiEffetti.immagini.createCGImage(piccola, from: piccola.extent.integral)
    }
}

/// I contesti Core Image degli effetti, oltre a quello della pipeline. Si creano in sottofondo all'avvio
/// (`prepara()`), così la coda di cattura non aspetta la prima volta.
enum ContestiEffetti {
    /// Immagini a colori piccole (istantanee, miniature dei filtri, sfondi): con la gestione del colore di serie.
    static let immagini: CIContext = {
        if let dispositivo = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: dispositivo, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    /// Maschere a un canale (persona): nessuna gestione del colore, i valori passano come sono.
    static let maschere: CIContext = {
        let opzioni: [CIContextOption: Any] = [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
                                               .cacheIntermediates: false]
        if let dispositivo = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: dispositivo, options: opzioni)
        }
        return CIContext(options: opzioni)
    }()

    static func prepara() {
        DispatchQueue.global(qos: .utility).async {
            _ = immagini
            _ = maschere
        }
    }
}
