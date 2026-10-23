import CoreImage
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import os.log

/// Manda le immagini dell'iPhone alla webcam virtuale (round 2): le adatta a 1920×1080 con bande nere
/// e le mette nel flusso «ingresso» dell'estensione (Mac/FotocameraVirtuale/Fotocamera.swift).
/// Serve l'account sviluppatore a pagamento: senza, la webcam virtuale non c'è e questa classe non trova nulla.
final class UscitaWebcam: @unchecked Sendable {
    /// L'identificativo del dispositivo creato dall'estensione (idDispositivo in Fotocamera.swift).
    private static let uidDispositivo = "6F1D2C64-1B8E-4C5A-9E0A-57C3B1A4D2E1"
    private static let larghezza = 1920
    private static let altezza = 1080

    private let registro = Logger(subsystem: "it.lrapps.webcamlr.mac", category: "uscita-webcam")
    private let contesto = CIContext()
    private var pool: CVPixelBufferPool?
    private var dispositivo: CMIOObjectID = 0
    private var flusso: CMIOStreamID = 0
    private var codaIngresso: CMSimpleQueue?
    private var ultimoTentativo: UInt64 = 0

    /// Chiamata sulla coda dello `Schermo` per ogni immagine decodificata.
    func invia(_ immagine: CVPixelBuffer) {
        guard let codaIngresso = codaIngresso ?? collega() else { return }
        guard CMSimpleQueueGetCount(codaIngresso) < CMSimpleQueueGetCapacity(codaIngresso),
              let campione = adatta(immagine) else { return }
        CMSimpleQueueEnqueue(codaIngresso, element: Unmanaged.passRetained(campione).toOpaque())
    }

    // MARK: - Collegamento all'estensione

    /// Cerca la webcam virtuale e apre il suo flusso di ingresso; ci riprova al massimo ogni 2 secondi.
    private func collega() -> CMSimpleQueue? {
        let adesso = DispatchTime.now().uptimeNanoseconds
        guard adesso - ultimoTentativo > 2_000_000_000 else { return nil }
        ultimoTentativo = adesso

        guard let trovato = Self.cercaDispositivo(), let ingresso = Self.flussoDiIngresso(di: trovato) else { return nil }
        var coda: Unmanaged<CMSimpleQueue>?
        let esito = CMIOStreamCopyBufferQueue(ingresso, { _, _, _ in }, nil, &coda)
        guard esito == noErr, let nuova = coda?.takeRetainedValue() else {
            registro.error("Flusso di ingresso non disponibile: \(esito)")
            return nil
        }
        guard CMIODeviceStartStream(trovato, ingresso) == noErr else {
            registro.error("Avvio del flusso di ingresso non riuscito")
            return nil
        }
        dispositivo = trovato
        flusso = ingresso
        codaIngresso = nuova
        registro.info("Collegata alla webcam virtuale")
        return nuova
    }

    func scollega() {
        if codaIngresso != nil {
            CMIODeviceStopStream(dispositivo, flusso)
        }
        codaIngresso = nil
    }

    private static func indirizzo(_ selettore: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selettore),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func elenco(_ oggetto: CMIOObjectID, _ selettore: Int) -> [CMIOObjectID] {
        var proprieta = indirizzo(selettore)
        var dimensione: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(oggetto, &proprieta, 0, nil, &dimensione) == noErr, dimensione > 0 else { return [] }
        var elementi = [CMIOObjectID](repeating: 0, count: Int(dimensione) / MemoryLayout<CMIOObjectID>.size)
        var usati: UInt32 = 0
        guard CMIOObjectGetPropertyData(oggetto, &proprieta, 0, nil, dimensione, &usati, &elementi) == noErr else { return [] }
        return elementi
    }

    private static func cercaDispositivo() -> CMIOObjectID? {
        for candidato in elenco(CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices) {
            var proprieta = indirizzo(kCMIODevicePropertyDeviceUID)
            var uid: Unmanaged<CFString>?
            var dimensione = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard CMIOObjectGetPropertyData(candidato, &proprieta, 0, nil, dimensione, &dimensione, &uid) == noErr,
                  let testo = uid.map({ $0.takeRetainedValue() as String }) else { continue }
            if testo == uidDispositivo { return candidato }
        }
        return nil
    }

    /// Il flusso in entrata (direzione 1); se la direzione non si legge, il secondo flusso creato dall'estensione.
    private static func flussoDiIngresso(di dispositivo: CMIOObjectID) -> CMIOStreamID? {
        let flussi = elenco(dispositivo, kCMIODevicePropertyStreams)
        for flusso in flussi {
            var proprieta = indirizzo(kCMIOStreamPropertyDirection)
            var direzione: UInt32 = 0
            var dimensione = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(flusso, &proprieta, 0, nil, dimensione, &dimensione, &direzione) == noErr, direzione == 1 {
                return flusso
            }
        }
        return flussi.count > 1 ? flussi[1] : nil
    }

    // MARK: - Adattamento a 1920×1080

    private func adatta(_ immagine: CVPixelBuffer) -> CMSampleBuffer? {
        if pool == nil {
            let attributi: NSDictionary = [
                kCVPixelBufferWidthKey: Self.larghezza,
                kCVPixelBufferHeightKey: Self.altezza,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributi, &pool)
        }
        guard let pool else { return nil }
        var destinazioneCreata: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destinazioneCreata) == kCVReturnSuccess,
              let destinazione = destinazioneCreata else { return nil }

        // Adatta senza tagliare: un video verticale resta intero, con bande nere ai lati.
        let sorgente = CIImage(cvPixelBuffer: immagine)
        let area = CGRect(x: 0, y: 0, width: Self.larghezza, height: Self.altezza)
        let scala = min(area.width / sorgente.extent.width, area.height / sorgente.extent.height)
        let scalata = sorgente.transformed(by: CGAffineTransform(scaleX: scala, y: scala))
        let centrata = scalata.transformed(by: CGAffineTransform(translationX: (area.width - scalata.extent.width) / 2 - scalata.extent.minX,
                                                                 y: (area.height - scalata.extent.height) / 2 - scalata.extent.minY))
        let composta = centrata.composited(over: CIImage(color: .black).cropped(to: area))
        contesto.render(composta, to: destinazione)

        var descrizioneCreata: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: destinazione,
                                                     formatDescriptionOut: &descrizioneCreata)
        guard let descrizione = descrizioneCreata else { return nil }
        var tempi = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                       decodeTimeStamp: .invalid)
        var campioneCreato: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: destinazione, dataReady: true,
                                           makeDataReadyCallback: nil, refcon: nil, formatDescription: descrizione,
                                           sampleTiming: &tempi, sampleBufferOut: &campioneCreato)
        return campioneCreato
    }
}
