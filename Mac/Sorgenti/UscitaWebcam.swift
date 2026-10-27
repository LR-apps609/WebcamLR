import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import os.log
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Manda le immagini del telefono alla webcam virtuale (round 2): le adatta a 1920×1080 con bande scure
/// (fondo di Stile) e le mette nel flusso «ingresso» dell'estensione (Mac/FotocameraVirtuale/Fotocamera.swift).
/// Dalla P12 anche a 3840×2160, ma solo se un'app usa la webcam in 4K
/// e il telefono manda davvero il 4K: altrimenti l'estensione ingrandisce l'immagine 1920×1080.
/// Serve l'account sviluppatore a pagamento: senza, la webcam virtuale non c'è e questa classe non trova nulla
/// (e non disegna nulla: la schermata di attesa parte solo dopo il primo collegamento all'estensione).
///
/// Schermata di attesa (AttesaWebcam.swift): quando il telefono scelto non manda video, qui si disegna l'attesa
/// (una volta per stato, stile e misura) e si manda all'estensione come se fosse video: 5 volte al secondo quando è ferma
/// (l'estensione la ripete al ritmo dell'app di chiamata), a ogni passo durante le dissolvenze. Così l'estensione
/// non deve sapere nulla di stati e stili, e l'immagine personale non deve arrivare fin lì come file.
/// Se WebcamLR per Mac è chiusa, l'estensione mostra da sé «La webcam non è collegata».
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
    /// Una riserva di immagini per misura (larghezza → riserva). Solo sotto `bloccoSorgente` (video e attesa).
    private var riserve: [Int: CVPixelBufferPool] = [:]
    /// La descrizione delle immagini adattate, rifatta solo quando cambia la misura (come in `UscitaMini`).
    /// Solo sotto `bloccoSorgente` (video e attesa).
    private var descrizioneUscita: CMVideoFormatDescription?
    /// Si può mandare il 4K (un'app usa la webcam in 4K): lo decide il `Ricevitore`
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

    // Schermata di attesa: tutto sotto `bloccoSorgente`, come il resto dell'invio.

    /// Una dissolvenza in corso: da quale immagine, quando è cominciata e quanto dura.
    private struct Dissolvenza {
        let da: CIImage
        let inizio: UInt64
        let durata: UInt64
    }

    /// L'attesa già disegnata in un buffer pronto da mandare, e per cosa.
    private struct AttesaPronta {
        let stato: StatoAttesa
        let versione: Int
        let larghezza: Int
        let buffer: CVPixelBuffer
    }

    /// Le dissolvenze: verso l'attesa (dopo la tenuta di 2 secondi) e di ritorno al video.
    private static let durataEntrata: UInt64 = 500_000_000
    private static let durataUscita: UInt64 = 300_000_000
    /// Ogni quanto si rimanda l'attesa ferma: l'estensione tiene buona un'immagine per 2 secondi e la ripete da sé.
    private static let intervalloAttesa: UInt64 = 200_000_000

    /// Fino a 30 volte al secondo, dal primo collegamento all'estensione (`collega`), sulla sua coda.
    private let codaAttesa = DispatchQueue(label: "it.lrapps.webcamlr.attesa-webcam", qos: .userInitiated)
    private var timerAttesa: DispatchSourceTimer?
    private var programma = ProgrammaAttesa()
    /// L'attesa che l'estensione sta ricevendo; nil quando riceve il video.
    private var mostrata: StatoAttesa?
    private var attesa: AttesaPronta?
    private var dissolvenza: Dissolvenza?
    /// L'ultima immagine del telefono già adattata: da qui parte la dissolvenza ed esce lo stile «sfocata».
    private var ultimaViva: CVPixelBuffer?
    private var ultimoInvioAttesa: UInt64 = 0

    /// Dal `Ricevitore`, ogni secondo: se vero e il telefono manda il 4K, l'estensione riceve 3840×2160.
    func imposta(quattroK: Bool) {
        blocco.lock()
        permesso4K = quattroK
        blocco.unlock()
    }

    /// Più telefoni insieme (P21): lo `Schermo` del telefono scelto per la webcam; nil finché la webcam
    /// virtuale non è collegata (`Ricevitore.collegaWebcamVirtuale`) o se non c'è un telefono.
    /// Sotto `bloccoSorgente`, che tiene anche il resto dell'invio: ogni schermo chiama dalla sua coda,
    /// e durante un cambio due schermi non devono mai lavorare qui insieme (riserve e coda non sono condivisibili).
    private let bloccoSorgente = NSLock()
    private var sorgente: ObjectIdentifier?

    /// Dal `Ricevitore`, sulla coda principale: quale schermo va nella webcam. Il cambio vale dalla prossima
    /// immagine decodificata: ogni schermo decodifica sempre, quindi non si aspetta un fotogramma chiave.
    func scegli(_ nuova: ObjectIdentifier?) {
        bloccoSorgente.lock()
        sorgente = nuova
        bloccoSorgente.unlock()
    }

    /// Dalla coda di uno `Schermo`: passa solo se è quello scelto. `cattura`: l'istante di cattura nell'orologio del Mac
    /// (µs), per il ritardo da vetro a uscita.
    func invia(_ immagine: CVPixelBuffer, cattura: Int64?, da: ObjectIdentifier) {
        bloccoSorgente.lock()
        defer { bloccoSorgente.unlock() }
        guard da == sorgente else { return }
        invia(immagine, cattura: cattura)
    }

    // MARK: - Da vetro a uscita (Protocollo.md, «Latenza»)

    /// Da vetro alla coda verso l'estensione (decodificato e adattato): mediana di un secondo.
    private let consegna = MisuraRitardo()
    /// Un'app usa la webcam, e quanto aspetta un'immagine dentro l'estensione prima di uscire (proprietà «ritd»;
    /// nil con un'estensione che non la dice). Dal `Ricevitore`, ogni secondo; sotto `blocco`.
    private var inOnda = false
    private var attesaEstensioneMs: Int?

    func imposta(inOnda: Bool, attesaEstensioneMs: Int?) {
        blocco.lock()
        self.inOnda = inOnda
        self.attesaEstensioneMs = attesaEstensioneMs
        blocco.unlock()
    }

    /// Da vetro alla webcam (ms): fino all'estensione più l'attesa dentro l'estensione; nil se nessuna app usa la webcam
    /// o se non arriva video. Da qualsiasi coda.
    var ritardoMs: Int? {
        blocco.lock()
        let inOnda = self.inOnda
        let attesa = attesaEstensioneMs
        blocco.unlock()
        guard inOnda, let fino = consegna.valore(adesso: Orologio.adesso()) else { return nil }
        return fino + (attesa ?? 0)
    }

    /// L'attesa dentro l'estensione (ms) per il registro; nil se non si sa.
    var attesaEstensione: Int? {
        blocco.lock()
        defer { blocco.unlock() }
        return inOnda ? attesaEstensioneMs : nil
    }

    /// Un'immagine decodificata dello schermo scelto (sotto `bloccoSorgente`).
    private func invia(_ immagine: CVPixelBuffer, cattura: Int64?) {
        let adesso = DispatchTime.now().uptimeNanoseconds
        programma.imposta(AttesaWebcam.condivisa.istantanea().statoWebcam, adesso: adesso)
        programma.vivo(adesso: adesso)
        // Le immagini vere vincono (ProgrammaAttesa); se per un attimo non è così, l'attesa la manda il timer.
        guard programma.attesa(adesso: adesso) == nil else { return }
        if mostrata != nil {
            // Il video torna: l'attesa svanisce sopra le prime immagini.
            dissolvenza = attesa.map { Dissolvenza(da: CIImage(cvPixelBuffer: $0.buffer), inizio: adesso, durata: Self.durataUscita) }
            mostrata = nil
            attesa = nil
        }
        guard let codaIngresso = codaPronta() else { return }
        var sopra: (immagine: CIImage, progresso: Double)?
        if let dissolvenza {
            let progresso = Self.progresso(dissolvenza, adesso: adesso)
            if progresso < 1 {
                sopra = (dissolvenza.da, progresso)
            } else {
                self.dissolvenza = nil
            }
        }
        guard let adattata = adatta(immagine, sopra: sopra) else { return }
        if sopra == nil { ultimaViva = adattata }
        guard accoda(adattata, in: codaIngresso), let cattura else { return }
        let fine = Orologio.adesso()
        if let ms = RitardoVetro.ms(cattura: cattura, adesso: fine) { consegna.aggiungi(ms, adesso: fine) }
    }

    /// La coda verso l'estensione, se c'è posto (sotto `bloccoSorgente`). Se resta piena, l'estensione non la svuota più
    /// (riavviata o sostituita da una nuova versione) e ci si ricollega.
    private func codaPronta() -> CMSimpleQueue? {
        guard let codaIngresso = codaIngresso ?? collega() else { return nil }
        guard CMSimpleQueueGetCount(codaIngresso) < CMSimpleQueueGetCapacity(codaIngresso) else {
            let adesso = DispatchTime.now().uptimeNanoseconds
            if pienaDa == 0 {
                pienaDa = adesso
            } else if adesso - pienaDa > 2_000_000_000 {
                registro.info("La webcam virtuale non prende più le immagini: mi ricollego")
                scollega()
            }
            return nil
        }
        pienaDa = 0
        return codaIngresso
    }

    /// Mette un'immagine già pronta (1920×1080 o 3840×2160, BGRA) nella coda verso l'estensione.
    /// Vero se l'immagine è entrata nella coda.
    @discardableResult
    private func accoda(_ buffer: CVPixelBuffer, in codaIngresso: CMSimpleQueue) -> Bool {
        guard let pronto = campione(buffer) else { return false }
        // La coda tiene un riferimento: lo rilascia chi la svuota (CoreMediaIO, verso l'estensione).
        let elemento = Unmanaged.passRetained(pronto)
        if CMSimpleQueueEnqueue(codaIngresso, element: elemento.toOpaque()) != noErr {
            elemento.release()
            return false
        }
        return true
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
        avviaAttesa()
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

    /// Legge la proprietà personalizzata «appl» dell'estensione: le firme delle app che usano la webcam
    /// (per esempio «us.zoom.xos»; «?» per un'app senza firma leggibile). Vuoto se nessuna;
    /// nil se la webcam virtuale non c'è o è una versione senza la proprietà.
    static func leggiApp() -> [String]? {
        guard let dispositivo = cercaDispositivo(), let testo = leggiTesto("appl", di: dispositivo) else { return nil }
        return testo.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
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

    /// Legge la proprietà personalizzata «ritd» dell'estensione: quanti millisecondi un'immagine dell'app aspetta
    /// dentro l'estensione prima di uscire verso le app di chiamata (mediana dell'ultimo secondo). nil se la webcam
    /// virtuale non c'è, se è una versione senza la proprietà o se nessuna app la usa.
    static func leggiAttesaEstensione() -> Int? {
        guard let dispositivo = cercaDispositivo(), let testo = leggiTesto("ritd", di: dispositivo) else { return nil }
        return Int(testo)
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

    /// `sopra`: durante il ritorno dall'attesa, l'attesa che svanisce sopra il video (progresso da 0 a 1).
    private func adatta(_ immagine: CVPixelBuffer, sopra: (immagine: CIImage, progresso: Double)? = nil) -> CVPixelBuffer? {
        let (larghezza, altezza) = misura(per: immagine)
        guard let destinazione = nuovoBuffer(larghezza: larghezza, altezza: altezza) else { return nil }

        // Adatta senza tagliare: un video verticale resta intero, con bande scure ai lati. Il video com'è arrivato,
        // mai specchiato qui: «Specchia» (1.14) lo fa il telefono, e lo vedono uguale le app, il telefono e il Mac.
        // Colore: YCbCr → RGB con la matrice e la gamma del flusso (BT.709 a gamma ridotta dal telefono), poi i valori
        // così come sono, letti e scritti nello stesso spazio (sRGB, quello che le app di chiamata danno a un'immagine
        // BGRA senza indicazioni): come una webcam vera, niente conversione da curva 709 a sRGB che schiarirebbe i
        // mezzitoni (il viso) rispetto al telefono.
        let sorgente = CIImage(cvPixelBuffer: immagine, options: [.colorSpace: Self.spazioUscita])
        let area = CGRect(x: 0, y: 0, width: larghezza, height: altezza)
        let scala = min(area.width / sorgente.extent.width, area.height / sorgente.extent.height)
        let scalata = Self.ridimensiona(sorgente, scala: scala)
        let centrata = scalata.transformed(by: CGAffineTransform(translationX: (area.width - scalata.extent.width) / 2 - scalata.extent.minX,
                                                                 y: (area.height - scalata.extent.height) / 2 - scalata.extent.minY))
        var composta = centrata.composited(over: Self.fondo.cropped(to: area))
        if let sopra {
            composta = Self.dissolvi(da: sopra.immagine, a: composta, progresso: sopra.progresso)
        }
        contesto.render(composta, to: destinazione)
        return destinazione
    }

    /// Lo spazio in cui si leggono le immagini del telefono e si scrivono quelle per l'estensione (vedi `adatta`).
    private static let spazioUscita = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Ingrandisce o riduce con il filtro di Lanczos (Core Image, sulla scheda video): nitido e senza scalini, anche
    /// riducendo un 4K o un video verticale, dove il semplice campionamento bilineare di una trasformazione perde dettaglio
    /// e fa tremolare i bordi sottili. I bordi si ripetono prima del filtro e si tagliano dopo: niente orlo trasparente
    /// che si mescolerebbe con le bande scure.
    private static func ridimensiona(_ immagine: CIImage, scala: CGFloat) -> CIImage {
        guard abs(scala - 1) > 0.001 else { return immagine }
        let filtro = CIFilter.lanczosScaleTransform()
        filtro.inputImage = immagine.clampedToExtent()
        filtro.scale = Float(scala)
        filtro.aspectRatio = 1
        let area = CGRect(x: immagine.extent.minX * scala, y: immagine.extent.minY * scala,
                          width: immagine.extent.width * scala, height: immagine.extent.height * scala)
        guard let scalata = filtro.outputImage else {
            return immagine.transformed(by: CGAffineTransform(scaleX: scala, y: scala))
        }
        return scalata.cropped(to: area)
    }

    private func nuovoBuffer(larghezza: Int, altezza: Int) -> CVPixelBuffer? {
        guard let riserva = riserva(larghezza: larghezza, altezza: altezza) else { return nil }
        var creato: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, riserva, &creato) == kCVReturnSuccess else { return nil }
        return creato
    }

    /// Il campione per la coda verso l'estensione, con la descrizione rifatta solo quando cambia la misura.
    private func campione(_ destinazione: CVPixelBuffer) -> CMSampleBuffer? {
        let descrizione: CMVideoFormatDescription
        if let attuale = descrizioneUscita, CMVideoFormatDescriptionMatchesImageBuffer(attuale, imageBuffer: destinazione) {
            descrizione = attuale
        } else {
            var descrizioneCreata: CMFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: destinazione,
                                                         formatDescriptionOut: &descrizioneCreata)
            guard let creata = descrizioneCreata else { return nil }
            descrizioneUscita = creata
            descrizione = creata
        }
        var tempi = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                       decodeTimeStamp: .invalid)
        var campioneCreato: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: destinazione, dataReady: true,
                                           makeDataReadyCallback: nil, refcon: nil, formatDescription: descrizione,
                                           sampleTiming: &tempi, sampleBufferOut: &campioneCreato)
        return campioneCreato
    }

    // MARK: - Schermata di attesa

    /// Dal primo collegamento all'estensione (sotto `bloccoSorgente`); poi resta per tutta la vita dell'app:
    /// è anche quello che ritenta il collegamento quando non arriva video.
    private func avviaAttesa() {
        guard timerAttesa == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: codaAttesa)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.bloccoSorgente.lock()
            self.passoAttesa()
            self.bloccoSorgente.unlock()
        }
        timerAttesa = timer
        timer.resume()
    }

    /// Sotto `bloccoSorgente`, fino a 30 volte al secondo. Se il video non c'è, manda l'attesa o un passo della dissolvenza;
    /// se c'è, non fa nulla (le immagini passano da `invia`).
    private func passoAttesa() {
        let adesso = DispatchTime.now().uptimeNanoseconds
        let istantanea = AttesaWebcam.condivisa.istantanea()
        programma.imposta(istantanea.statoWebcam, adesso: adesso)
        guard let voluta = programma.attesa(adesso: adesso) else { return }
        if voluta != mostrata {
            // Parte da quello che l'estensione sta mostrando: l'ultima immagine del telefono o l'attesa di prima.
            let da = mostrata == nil ? ultimaViva.map { CIImage(cvPixelBuffer: $0) } : attesa.map { CIImage(cvPixelBuffer: $0.buffer) }
            dissolvenza = da.map { Dissolvenza(da: $0, inizio: adesso, durata: Self.durataEntrata) }
            mostrata = voluta
            ultimoInvioAttesa = 0
        }
        guard let codaIngresso = codaPronta(), let ferma = attesaPronta(voluta, istantanea: istantanea) else { return }
        if let dissolvenza {
            let progresso = Self.progresso(dissolvenza, adesso: adesso)
            if progresso < 1 {
                // Un passo della dissolvenza, con Core Image nella riserva delle immagini adattate.
                if let misto = nuovoBuffer(larghezza: CVPixelBufferGetWidth(ferma), altezza: CVPixelBufferGetHeight(ferma)) {
                    contesto.render(Self.dissolvi(da: dissolvenza.da, a: CIImage(cvPixelBuffer: ferma), progresso: progresso), to: misto)
                    accoda(misto, in: codaIngresso)
                    ultimoInvioAttesa = adesso
                }
                return
            }
            self.dissolvenza = nil
            ultimoInvioAttesa = 0
        }
        // Ferma: la stessa immagine, già disegnata, ogni `intervalloAttesa`.
        guard adesso &- ultimoInvioAttesa >= Self.intervalloAttesa else { return }
        accoda(ferma, in: codaIngresso)
        ultimoInvioAttesa = adesso
    }

    /// L'attesa disegnata una volta per stato, stile e misura (la misura dell'ultima immagine mandata: 1080p o 4K).
    private func attesaPronta(_ stato: StatoAttesa, istantanea: AttesaWebcam.Istantanea) -> CVPixelBuffer? {
        let larghezza = ultimaViva.map { CVPixelBufferGetWidth($0) } ?? Self.normale.larghezza
        let altezza = ultimaViva.map { CVPixelBufferGetHeight($0) } ?? Self.normale.altezza
        if let attesa, attesa.stato == stato, attesa.versione == istantanea.versione, attesa.larghezza == larghezza {
            return attesa.buffer
        }
        let sfondo = istantanea.stile == .sfocata ? ultimaViva.flatMap { AttesaWebcam.sfocata($0, contesto: contesto) } : nil
        guard let immagine = AttesaWebcam.condivisa.immagine(stato, stile: istantanea.stile, sfondo: sfondo,
                                                              larghezza: larghezza, altezza: altezza),
              let buffer = AttesaWebcam.buffer(da: immagine) else { return nil }
        attesa = AttesaPronta(stato: stato, versione: istantanea.versione, larghezza: larghezza, buffer: buffer)
        return buffer
    }

    /// Da 0 a 1, con partenza e arrivo morbidi.
    private static func progresso(_ dissolvenza: Dissolvenza, adesso: UInt64) -> Double {
        let lineare = min(1, Double(adesso &- dissolvenza.inizio) / Double(dissolvenza.durata))
        return lineare * lineare * (3 - 2 * lineare)
    }

    /// `da` che si dissolve in `a`; `da` si adatta alla misura di `a` se serve (per esempio dal 4K all'attesa in 1080p).
    private static func dissolvi(da: CIImage, a: CIImage, progresso: Double) -> CIImage {
        let area = a.extent
        var partenza = da
        if da.extent.size != area.size, da.extent.width > 0, da.extent.height > 0 {
            partenza = da.transformed(by: CGAffineTransform(scaleX: area.width / da.extent.width, y: area.height / da.extent.height))
        }
        let filtro = CIFilter.dissolveTransition()
        filtro.inputImage = partenza
        filtro.targetImage = a
        filtro.time = Float(progresso)
        return (filtro.outputImage ?? a).cropped(to: area)
    }
}
