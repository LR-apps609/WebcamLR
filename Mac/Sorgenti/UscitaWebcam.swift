import CoreImage
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import os.log
import Stile
import SwiftUI

/// Manda le immagini del telefono alla webcam virtuale (round 2): le adatta a 1920×1080 con bande scure
/// (fondo di Stile) e le mette nel flusso «ingresso» dell'estensione (Mac/FotocameraVirtuale/Fotocamera.swift).
/// Dalla P12 anche a 3840×2160, ma solo se un'app usa la webcam in 4K, la modalità avanzata è accesa
/// e il telefono manda davvero il 4K: altrimenti l'estensione ingrandisce l'immagine 1920×1080.
/// Serve l'account sviluppatore a pagamento: senza, la webcam virtuale non c'è e questa classe non trova nulla.
final class UscitaWebcam: @unchecked Sendable {
    /// Il formato scelto dalle app di chiamata (proprietà «fmto» dell'estensione), per esempio 1920×1080 a 60 fps.
    struct Formato: Equatable, Sendable {
        let larghezza: Int
        let altezza: Int
        let fps: Int
    }

    /// L'identificativo del dispositivo creato dall'estensione (idDispositivo in Fotocamera.swift).
    private static let uidDispositivo = "6F1D2C64-1B8E-4C5A-9E0A-57C3B1A4D2E1"
    /// Le due misure che l'estensione accetta nel flusso di ingresso (formatiIngresso in Fotocamera.swift).
    private static let normale = (larghezza: 1920, altezza: 1080)
    private static let quattroK = (larghezza: 3840, altezza: 2160)

    private let registro = Logger(subsystem: "it.lrapps.webcamlr.mac", category: "uscita-webcam")
    private let contesto = CIContext()
    /// Una riserva di immagini per misura (larghezza → riserva). Solo sulla coda dello `Schermo`.
    private var riserve: [Int: CVPixelBufferPool] = [:]
    /// Si può mandare il 4K (un'app usa la webcam in 4K e la modalità avanzata è accesa): lo decide il `Ricevitore`
    /// dalla coda principale, lo legge `invia` dalla coda dello `Schermo`.
    private let blocco = NSLock()
    private var permesso4K = false
    private var dispositivo: CMIOObjectID = 0
    private var flusso: CMIOStreamID = 0
    private var codaIngresso: CMSimpleQueue?
    private var ultimoTentativo: UInt64 = 0
    /// Da quando la coda verso l'estensione è piena: se resta piena, l'estensione non la svuota più
    /// (riavviata o sostituita da una nuova versione) e ci si ricollega.
    private var pienaDa: UInt64 = 0
    /// Il fondo delle bande ai lati, come la finestra dell'app.
    private static let fondo = CIImage(color: CIColor(cgColor: Tema.fondo.resolve(in: EnvironmentValues()).cgColor))

    /// Dal `Ricevitore`, ogni secondo: se vero e il telefono manda il 4K, l'estensione riceve 3840×2160.
    func imposta(quattroK: Bool) {
        blocco.lock()
        permesso4K = quattroK
        blocco.unlock()
    }

    /// Chiamata sulla coda dello `Schermo` per ogni immagine decodificata.
    func invia(_ immagine: CVPixelBuffer) {
        guard let codaIngresso = codaIngresso ?? collega() else { return }
        guard CMSimpleQueueGetCount(codaIngresso) < CMSimpleQueueGetCapacity(codaIngresso) else {
            let adesso = DispatchTime.now().uptimeNanoseconds
            if pienaDa == 0 {
                pienaDa = adesso
            } else if adesso - pienaDa > 2_000_000_000 {
                registro.info("La webcam virtuale non prende più le immagini: mi ricollego")
                scollega()
            }
            return
        }
        pienaDa = 0
        guard let campione = adatta(immagine) else { return }
        // La coda tiene un riferimento: lo rilascia chi la svuota (CoreMediaIO, verso l'estensione).
        let elemento = Unmanaged.passRetained(campione)
        if CMSimpleQueueEnqueue(codaIngresso, element: elemento.toOpaque()) != noErr {
            elemento.release()
        }
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
        pienaDa = 0
    }

    /// Legge la proprietà personalizzata «inon» dell'estensione: vero se un'app usa la webcam.
    /// nil se la webcam virtuale non c'è.
    static func leggiInOnda() -> Bool? {
        guard let dispositivo = cercaDispositivo() else { return nil }
        return leggiTesto("inon", di: dispositivo).map { $0 == "1" }
    }

    /// Legge la proprietà personalizzata «fmto» dell'estensione (P12): il formato scelto dalle app,
    /// scritto come «1920x1080@60». nil se la webcam virtuale non c'è o è una versione senza la proprietà.
    static func leggiFormato() -> Formato? {
        guard let dispositivo = cercaDispositivo(), let testo = leggiTesto("fmto", di: dispositivo) else { return nil }
        let parti = testo.split(separator: "@")
        guard parti.count == 2, let fps = Int(parti[1]) else { return nil }
        let misure = parti[0].split(separator: "x")
        guard misure.count == 2, let larghezza = Int(misure[0]), let altezza = Int(misure[1]) else { return nil }
        return Formato(larghezza: larghezza, altezza: altezza, fps: fps)
    }

    /// Una proprietà personalizzata di testo dell'estensione, dal suo codice di quattro lettere (come in Fotocamera.swift).
    private static func leggiTesto(_ codice: String, di dispositivo: CMIOObjectID) -> String? {
        let selettore = codice.utf8.reduce(0) { ($0 << 8) | Int($1) }
        var proprieta = indirizzo(selettore)
        guard CMIOObjectHasProperty(dispositivo, &proprieta) else { return nil }
        var valore: Unmanaged<CFString>?
        let dimensione = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var usati: UInt32 = 0
        guard CMIOObjectGetPropertyData(dispositivo, &proprieta, 0, nil, dimensione, &usati, &valore) == noErr else { return nil }
        return valore.map { $0.takeRetainedValue() as String }
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
            let dimensione = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var usati: UInt32 = 0
            guard CMIOObjectGetPropertyData(candidato, &proprieta, 0, nil, dimensione, &usati, &uid) == noErr,
                  let testo = uid.map({ $0.takeRetainedValue() as String }) else { continue }
            if testo == uidDispositivo { return candidato }
        }
        return nil
    }

    /// Il flusso «ingresso» dell'estensione (`.sink`), riconosciuto dal nome («WebcamLR · ingresso»
    /// in Fotocamera.swift). Se il nome non si legge, il secondo flusso, come nell'esempio di Apple:
    /// l'estensione crea prima «video» e poi «ingresso». Le regole sulla direzione dei flussi sono ambigue
    /// e un errore manderebbe le immagini nel flusso sbagliato senza nessun avviso.
    private static func flussoDiIngresso(di dispositivo: CMIOObjectID) -> CMIOStreamID? {
        let flussi = elenco(dispositivo, kCMIODevicePropertyStreams)
        for candidato in flussi {
            var proprieta = indirizzo(kCMIOObjectPropertyName)
            var nome: Unmanaged<CFString>?
            let dimensione = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var usati: UInt32 = 0
            guard CMIOObjectGetPropertyData(candidato, &proprieta, 0, nil, dimensione, &usati, &nome) == noErr,
                  let testo = nome.map({ $0.takeRetainedValue() as String }) else { continue }
            if testo.contains("ingresso") { return candidato }
        }
        return flussi.count > 1 ? flussi[1] : nil
    }

    // MARK: - Adattamento a 1920×1080 (o 3840×2160)

    /// 3840×2160 solo se è permesso e il telefono manda il 4K (anche in verticale): ingrandire qui
    /// un'immagine più piccola sposterebbe solo più dati verso l'estensione, che sa ingrandire da sola.
    private func misura(per immagine: CVPixelBuffer) -> (larghezza: Int, altezza: Int) {
        blocco.lock()
        let permesso = permesso4K
        blocco.unlock()
        let latoLungo = max(CVPixelBufferGetWidth(immagine), CVPixelBufferGetHeight(immagine))
        return permesso && latoLungo >= Self.quattroK.larghezza ? Self.quattroK : Self.normale
    }

    private func riserva(larghezza: Int, altezza: Int) -> CVPixelBufferPool? {
        if let esistente = riserve[larghezza] { return esistente }
        let attributi: NSDictionary = [
            kCVPixelBufferWidthKey: larghezza,
            kCVPixelBufferHeightKey: altezza,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        var nuova: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributi, &nuova)
        riserve[larghezza] = nuova
        return nuova
    }

    private func adatta(_ immagine: CVPixelBuffer) -> CMSampleBuffer? {
        let (larghezza, altezza) = misura(per: immagine)
        guard let riserva = riserva(larghezza: larghezza, altezza: altezza) else { return nil }
        var destinazioneCreata: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, riserva, &destinazioneCreata) == kCVReturnSuccess,
              let destinazione = destinazioneCreata else { return nil }

        // Adatta senza tagliare: un video verticale resta intero, con bande scure ai lati. Mai specchiato:
        // l'anteprima di sé la specchiano le app di chiamata; «Specchia» del Mac vale solo per l'anteprima qui.
        let sorgente = CIImage(cvPixelBuffer: immagine)
        let area = CGRect(x: 0, y: 0, width: larghezza, height: altezza)
        let scala = min(area.width / sorgente.extent.width, area.height / sorgente.extent.height)
        let scalata = sorgente.transformed(by: CGAffineTransform(scaleX: scala, y: scala))
        let centrata = scalata.transformed(by: CGAffineTransform(translationX: (area.width - scalata.extent.width) / 2 - scalata.extent.minX,
                                                                 y: (area.height - scalata.extent.height) / 2 - scalata.extent.minY))
        let composta = centrata.composited(over: Self.fondo.cropped(to: area))
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
