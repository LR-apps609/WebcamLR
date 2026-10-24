import Accelerate
import CoreMediaIO
import CoreText
import Foundation
import IOKit.audio
import os.log
import Stile
import SwiftUI

// Webcam virtuale WebcamLR (funzione 11). Ha due flussi:
// - «video», in uscita: quello che vedono Zoom, FaceTime e le altre app, a 1920×1080 o 1280×720, 30 fps;
// - «ingresso», in entrata: l'app WebcamLR ci mette le immagini dell'iPhone (UscitaWebcam.swift),
//   già adattate a 1920×1080 con le bande scure ai lati.
// Senza immagini recenti dall'app (oltre 1 secondo) manda l'immagine di attesa:
// «WebcamLR · Apri WebcamLR sul telefono», disegnata una volta sola per formato.
// L'uscita non è mai specchiata: l'anteprima di sé la specchiano le app di chiamata.
// Tutto in BGRA a 32 bit (kCVPixelFormatType_32BGRA), come le immagini che arrivano dall'app.

/// Un formato dell'uscita: le app scelgono tra questi.
private struct Formato {
    let larghezza: Int32
    let altezza: Int32
}

private let formatiUscita = [Formato(larghezza: 1920, altezza: 1080), Formato(larghezza: 1280, altezza: 720)]
/// L'app manda sempre 1920×1080 (UscitaWebcam.larghezza/altezza).
private let formatoIngresso = Formato(larghezza: 1920, altezza: 1080)
private let fotogrammiAlSecondo: Int32 = 30
private let formatoPixel = kCVPixelFormatType_32BGRA
private let registro = Logger(subsystem: "it.lrapps.webcamlr.mac.fotocamera", category: "fotocamera")

/// Solo l'app WebcamLR può mettere immagini nel flusso di ingresso.
private let identificativoApp = "it.lrapps.webcamlr.mac"

// Identificativi fissi: le app ricordano la webcam scelta tra un avvio e l'altro.
// L'app cerca la webcam con idDispositivo (UscitaWebcam.uidDispositivo): cambiarli insieme.
private let idDispositivo = UUID(uuidString: "6F1D2C64-1B8E-4C5A-9E0A-57C3B1A4D2E1")!
private let idFlusso = UUID(uuidString: "9A2B7E10-3C4D-4F6A-8B1E-2D5C6A7B8C90")!
private let idFlussoIngresso = UUID(uuidString: "3E8C1F42-7A6B-4D19-B2C5-0F9E8D7C6B5A")!
/// L'app riconosce il flusso di ingresso da questa parola nel nome (UscitaWebcam.flussoDiIngresso).
private let nomeFlussoIngresso = "WebcamLR · ingresso"

extension CMIOExtensionProperty {
    /// Proprietà personalizzata «inon»: "1" se un'app sta usando la webcam, "0" altrimenti.
    /// L'app la legge con CoreMediaIO (UscitaWebcam.leggiInOnda).
    static let inOnda = CMIOExtensionProperty(rawValue: "4cc_inon_glob_0000")
}

/// Oltre questo tempo senza immagini dall'app si passa all'immagine di attesa.
private let validitaImmagineApp: UInt64 = 1_000_000_000

/// I caratteri di Stile (Barlow Condensed), se Xcode ha messo il pacchetto delle risorse nell'estensione.
/// Non si usa Caratteri.registra(): se il pacchetto mancasse, Bundle.module fermerebbe l'estensione.
private let caratteriPronti: Bool = {
    let candidati = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0?.appendingPathComponent("Stile_Stile.bundle") }
    for cartella in candidati {
        guard let pacchetto = Bundle(url: cartella) else { continue }
        var trovati = false
        for nome in ["BarlowCondensed-Bold", "BarlowCondensed-SemiBold"] {
            if let url = pacchetto.url(forResource: nome, withExtension: "ttf", subdirectory: "Caratteri") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                trovati = true
            }
        }
        if trovati { return true }
    }
    registro.info("Caratteri di Stile non trovati: l'immagine di attesa usa quelli di sistema")
    return false
}()

final class SorgenteDispositivo: NSObject, CMIOExtensionDeviceSource {
    private(set) var dispositivo: CMIOExtensionDevice!
    private var sorgenteFlusso: SorgenteFlusso!
    private var sorgenteIngresso: SorgenteFlusso!
    private let codaTimer = DispatchQueue(label: "fotocamera.timer", qos: .userInteractive)

    // Lette e scritte solo su codaTimer.
    private var ultimaDaApp: CVPixelBuffer?
    private var istanteDaApp: UInt64 = 0
    private var utentiAttivi: UInt32 = 0
    private var indiceFormato = 0
    private var timer: DispatchSourceTimer?
    private var ingressoAttivo = false
    /// Cresce a ogni avvio o arresto dell'ingresso: un vecchio giro di lettura si ferma da solo
    /// e non ce ne sono mai due insieme.
    private var giroIngresso: UInt64 = 0
    private var riserve: [Int: CVPixelBufferPool] = [:]
    private var immaginiAttesa: [Int: CVPixelBuffer] = [:]
    private var avvisoRiservaDato = false
    private let attributiBuffer: NSDictionary = [kCVPixelBufferPoolAllocationThresholdKey: 8]

    init(nome: String) {
        super.init()
        dispositivo = CMIOExtensionDevice(localizedName: nome, deviceID: idDispositivo, legacyDeviceID: nil, source: self)

        let durata = CMTime(value: 1, timescale: fotogrammiAlSecondo)
        sorgenteFlusso = SorgenteFlusso(nome: "WebcamLR · video", id: idFlusso,
                                        formati: formatiUscita.map { Self.formatoFlusso($0, durata: durata) },
                                        direzione: .source, proprietario: self)
        sorgenteIngresso = SorgenteFlusso(nome: nomeFlussoIngresso, id: idFlussoIngresso,
                                          formati: [Self.formatoFlusso(formatoIngresso, durata: durata)],
                                          direzione: .sink, proprietario: self)
        do {
            // Prima l'uscita, poi l'ingresso: l'app, se non trova il nome, prende il secondo flusso.
            try dispositivo.addStream(sorgenteFlusso.flusso)
            try dispositivo.addStream(sorgenteIngresso.flusso)
        } catch {
            fatalError("Impossibile aggiungere il flusso video: \(error.localizedDescription)")
        }
    }

    private static func formatoFlusso(_ formato: Formato, durata: CMTime) -> CMIOExtensionStreamFormat {
        var descrizione: CMFormatDescription?
        let esito = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: formatoPixel,
                                                   width: formato.larghezza, height: formato.altezza, extensions: nil,
                                                   formatDescriptionOut: &descrizione)
        guard esito == noErr, let descrizione else {
            fatalError("Formato video non valido: \(esito)")
        }
        return CMIOExtensionStreamFormat(formatDescription: descrizione, maxFrameDuration: durata,
                                         minFrameDuration: durata, validFrameDurations: nil)
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel, .inOnda]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let proprieta = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            proprieta.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            proprieta.model = "WebcamLR"
        }
        if properties.contains(.inOnda) {
            proprieta.setPropertyState(statoInOnda, forProperty: .inOnda)
        }
        return proprieta
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: - In onda

    /// Avvisa che la proprietà «inOnda» è cambiata: l'app mostra il rosso e lo dice all'iPhone.
    /// (Non uno spazio condiviso: l'estensione gira come utente di sistema, non come l'utente.)
    /// Fuori da codaTimer: se CoreMediaIO rileggesse la proprietà subito, `statoInOnda` non si bloccherebbe.
    private func segnalaInOnda(utenti: UInt32) {
        registro.info("Webcam \(utenti > 0 ? "in onda" : "libera", privacy: .public) (\(utenti) app)")
        dispositivo?.notifyPropertiesChanged([.inOnda: Self.stato(utenti: utenti)])
    }

    /// Letto dalle richieste di proprietà, che arrivano da un'altra coda.
    private var statoInOnda: CMIOExtensionPropertyState<AnyObject> {
        codaTimer.sync { Self.stato(utenti: utentiAttivi) }
    }

    private static func stato(utenti: UInt32) -> CMIOExtensionPropertyState<AnyObject> {
        CMIOExtensionPropertyState(value: (utenti > 0 ? "1" : "0") as NSString)
    }

    // MARK: - Avvio e arresto dell'uscita

    // Avvio, arresto e formato arrivano dalle code di CoreMediaIO, mai da codaTimer: sync non si blocca.
    func avviaInvio() {
        let utenti = codaTimer.sync { () -> UInt32 in
            utentiAttivi += 1
            avviaTimerSeServe()
            return utentiAttivi
        }
        segnalaInOnda(utenti: utenti)
    }

    func fermaInvio() {
        let utenti = codaTimer.sync { () -> UInt32 in
            if utentiAttivi > 1 {
                utentiAttivi -= 1
            } else {
                utentiAttivi = 0
                timer?.cancel()
                timer = nil
            }
            return utentiAttivi
        }
        segnalaInOnda(utenti: utenti)
    }

    func cambiaFormato(_ indice: Int) {
        guard formatiUscita.indices.contains(indice) else { return }
        codaTimer.sync { indiceFormato = indice }
        registro.info("Formato \(formatiUscita[indice].larghezza)×\(formatiUscita[indice].altezza)")
    }

    /// Su codaTimer.
    private func avviaTimerSeServe() {
        guard timer == nil else { return }
        let nuovo = DispatchSource.makeTimerSource(flags: .strict, queue: codaTimer)
        nuovo.schedule(deadline: .now(), repeating: 1.0 / Double(fotogrammiAlSecondo), leeway: .milliseconds(1))
        nuovo.setEventHandler { [weak self] in self?.inviaFotogramma() }
        nuovo.resume()
        timer = nuovo
    }

    // MARK: - Ingresso dall'app

    func avviaIngresso(client: CMIOExtensionClient) {
        codaTimer.async {
            self.ingressoAttivo = true
            self.giroIngresso &+= 1
            self.consuma(da: client, giro: self.giroIngresso)
        }
    }

    func fermaIngresso() {
        codaTimer.async {
            self.ingressoAttivo = false
            self.giroIngresso &+= 1
        }
    }

    /// Su codaTimer. Prende le immagini che l'app mette nel flusso di ingresso, una dopo l'altra.
    private func consuma(da client: CMIOExtensionClient, giro: UInt64) {
        guard ingressoAttivo, giro == giroIngresso else { return }
        sorgenteIngresso.flusso.consumeSampleBuffer(from: client) { [weak self] campione, sequenza, _, _, _ in
            guard let self else { return }
            let immagine: CVPixelBuffer? = campione.flatMap { CMSampleBufferGetImageBuffer($0) }
            guard let immagine else {
                // Niente di pronto o un errore: si riprova tra poco, senza girare a vuoto.
                self.codaTimer.asyncAfter(deadline: .now() + .milliseconds(10)) { self.consuma(da: client, giro: giro) }
                return
            }
            let uscita = CMIOExtensionScheduledOutput(sequenceNumber: sequenza, hostTimeInNanoseconds: Self.adessoNanosecondi())
            self.sorgenteIngresso.flusso.notifyScheduledOutputChanged(uscita)
            let arrivo = DispatchTime.now().uptimeNanoseconds
            self.codaTimer.async {
                self.ultimaDaApp = immagine
                self.istanteDaApp = arrivo
                self.consuma(da: client, giro: giro)
            }
        }
    }

    // MARK: - Uscita verso le app

    /// Su codaTimer, 30 volte al secondo mentre almeno un'app usa la webcam.
    private func inviaFotogramma() {
        let indice = indiceFormato
        if let immagine = ultimaDaApp, DispatchTime.now().uptimeNanoseconds &- istanteDaApp < validitaImmagineApp {
            if let adattata = adatta(immagine, indice: indice) {
                invia(adattata)
                return
            }
        } else {
            ultimaDaApp = nil
        }
        if let attesa = immagineAttesa(indice: indice) {
            invia(attesa)
        }
    }

    /// L'immagine dell'app è già 1920×1080: si manda com'è, o si riduce per il formato 1280×720.
    private func adatta(_ immagine: CVPixelBuffer, indice: Int) -> CVPixelBuffer? {
        let formato = formatiUscita[indice]
        guard CVPixelBufferGetPixelFormatType(immagine) == formatoPixel else { return nil }
        if CVPixelBufferGetWidth(immagine) == Int(formato.larghezza), CVPixelBufferGetHeight(immagine) == Int(formato.altezza) {
            return immagine
        }
        guard let riserva = riserva(indice: indice) else { return nil }
        var creato: CVPixelBuffer?
        let esito = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, riserva, attributiBuffer, &creato)
        guard esito == kCVReturnSuccess, let destinazione = creato else {
            if !avvisoRiservaDato {
                avvisoRiservaDato = true
                registro.error("Buffer video esauriti: \(esito)")
            }
            return nil
        }
        CVPixelBufferLockBaseAddress(immagine, .readOnly)
        CVPixelBufferLockBaseAddress(destinazione, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destinazione, [])
            CVPixelBufferUnlockBaseAddress(immagine, .readOnly)
        }
        guard let baseSorgente = CVPixelBufferGetBaseAddress(immagine),
              let baseDestinazione = CVPixelBufferGetBaseAddress(destinazione) else { return nil }
        var sorgente = vImage_Buffer(data: baseSorgente,
                                     height: vImagePixelCount(CVPixelBufferGetHeight(immagine)),
                                     width: vImagePixelCount(CVPixelBufferGetWidth(immagine)),
                                     rowBytes: CVPixelBufferGetBytesPerRow(immagine))
        var arrivo = vImage_Buffer(data: baseDestinazione,
                                   height: vImagePixelCount(CVPixelBufferGetHeight(destinazione)),
                                   width: vImagePixelCount(CVPixelBufferGetWidth(destinazione)),
                                   rowBytes: CVPixelBufferGetBytesPerRow(destinazione))
        // vImage tratta i quattro canali allo stesso modo: va bene anche per BGRA.
        let errore = vImageScale_ARGB8888(&sorgente, &arrivo, nil, vImage_Flags(kvImageNoFlags))
        return errore == kvImageNoError ? destinazione : nil
    }

    private func riserva(indice: Int) -> CVPixelBufferPool? {
        if let esistente = riserve[indice] { return esistente }
        var nuova: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, Self.attributiPixel(formatiUscita[indice]), &nuova)
        riserve[indice] = nuova
        return nuova
    }

    private static func attributiPixel(_ formato: Formato) -> NSDictionary {
        [
            kCVPixelBufferWidthKey: formato.larghezza,
            kCVPixelBufferHeightKey: formato.altezza,
            kCVPixelBufferPixelFormatTypeKey: formatoPixel,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
    }

    private func invia(_ buffer: CVPixelBuffer) {
        var descrizioneCreata: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                     formatDescriptionOut: &descrizioneCreata)
        guard let descrizione = descrizioneCreata else { return }
        let adesso = CMClockGetTime(CMClockGetHostTimeClock())
        var tempi = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: fotogrammiAlSecondo),
                                       presentationTimeStamp: adesso, decodeTimeStamp: .invalid)
        var campioneCreato: CMSampleBuffer?
        let creato = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true,
                                                        makeDataReadyCallback: nil, refcon: nil,
                                                        formatDescription: descrizione, sampleTiming: &tempi,
                                                        sampleBufferOut: &campioneCreato)
        guard creato == noErr, let campione = campioneCreato else { return }
        sorgenteFlusso.flusso.send(campione, discontinuity: [],
                                   hostTimeInNanoseconds: UInt64(adesso.seconds * Double(NSEC_PER_SEC)))
    }

    private static func adessoNanosecondi() -> UInt64 {
        UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * Double(NSEC_PER_SEC))
    }

    // MARK: - Immagine di attesa

    /// Disegnata una volta per formato e poi riusata: le app la ricevono 30 volte al secondo senza costi.
    private func immagineAttesa(indice: Int) -> CVPixelBuffer? {
        if let pronta = immaginiAttesa[indice] { return pronta }
        let formato = formatiUscita[indice]
        var creato: CVPixelBuffer?
        let esito = CVPixelBufferCreate(kCFAllocatorDefault, Int(formato.larghezza), Int(formato.altezza), formatoPixel,
                                        Self.attributiPixel(formato), &creato)
        guard esito == kCVReturnSuccess, let buffer = creato else {
            registro.error("Immagine di attesa non creata: \(esito)")
            return nil
        }
        Self.disegnaAttesa(in: buffer)
        immaginiAttesa[indice] = buffer
        return buffer
    }

    /// Fondo scuro di Stile, «WebcamLR», un tratto ciano e «Apri WebcamLR sul telefono».
    private static func disegnaAttesa(in buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let spazio = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let larghezza = CVPixelBufferGetWidth(buffer)
        let altezza = CVPixelBufferGetHeight(buffer)
        // BGRA in memoria = primo canale alfa premoltiplicato, ordine dei byte little-endian.
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let contesto = CGContext(data: base, width: larghezza, height: altezza, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: spazio,
                                       bitmapInfo: info) else { return }
        let w = CGFloat(larghezza)
        let h = CGFloat(altezza)
        let scala = h / 1080

        contesto.setFillColor(colore(Tema.fondo))
        contesto.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let titolo = caratteriPronti ? "BarlowCondensed-Bold" : "HelveticaNeue-Bold"
        let sottotitolo = caratteriPronti ? "BarlowCondensed-SemiBold" : "HelveticaNeue-Medium"
        // In CoreGraphics l'origine è in basso: y cresce verso l'alto.
        scrivi("WebcamLR", carattere: titolo, dimensione: 132 * scala, colore: colore(Tema.testo),
               centroY: h / 2 + 70 * scala, larghezza: w, in: contesto)
        contesto.setFillColor(colore(Tema.ciano))
        contesto.fill(CGRect(x: (w - 96 * scala) / 2, y: h / 2 - 3 * scala, width: 96 * scala, height: 6 * scala))
        scrivi("Apri WebcamLR sul telefono", carattere: sottotitolo, dimensione: 56 * scala,
               colore: colore(Tema.testoSecondario), centroY: h / 2 - 70 * scala, larghezza: w, in: contesto)
        contesto.flush()
    }

    private static func colore(_ colore: Color) -> CGColor {
        colore.resolve(in: EnvironmentValues()).cgColor
    }

    private static func scrivi(_ testo: String, carattere: String, dimensione: CGFloat, colore: CGColor,
                               centroY: CGFloat, larghezza: CGFloat, in contesto: CGContext) {
        let font = CTFontCreateWithName(carattere as CFString, dimensione, nil)
        let attributi: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
            NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): colore
        ]
        let riga = CTLineCreateWithAttributedString(NSAttributedString(string: testo, attributes: attributi))
        var salita: CGFloat = 0
        var discesa: CGFloat = 0
        var interlinea: CGFloat = 0
        let ampiezza = CGFloat(CTLineGetTypographicBounds(riga, &salita, &discesa, &interlinea))
        contesto.textPosition = CGPoint(x: (larghezza - ampiezza) / 2, y: centroY - (salita - discesa) / 2)
        CTLineDraw(riga, contesto)
    }
}

final class SorgenteFlusso: NSObject, CMIOExtensionStreamSource {
    private(set) var flusso: CMIOExtensionStream!
    let direzione: CMIOExtensionStream.Direction
    private let formati: [CMIOExtensionStreamFormat]
    private weak var proprietario: SorgenteDispositivo?
    private var indiceAttivo = 0
    private var clientIngresso: CMIOExtensionClient?

    init(nome: String, id: UUID, formati: [CMIOExtensionStreamFormat], direzione: CMIOExtensionStream.Direction,
         proprietario: SorgenteDispositivo) {
        self.formati = formati
        self.direzione = direzione
        self.proprietario = proprietario
        super.init()
        flusso = CMIOExtensionStream(localizedName: nome, streamID: id, direction: direzione, clockType: .hostTime, source: self)
    }

    var formats: [CMIOExtensionStreamFormat] {
        formati
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        if direzione == .sink {
            return [.streamActiveFormatIndex, .streamFrameDuration, .streamSinkBufferQueueSize,
                    .streamSinkBuffersRequiredForStartup, .streamSinkBufferUnderrunCount, .streamSinkEndOfData]
        }
        return [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let proprieta = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            proprieta.activeFormatIndex = indiceAttivo
        }
        if properties.contains(.streamFrameDuration) {
            proprieta.frameDuration = CMTime(value: 1, timescale: fotogrammiAlSecondo)
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            proprieta.sinkBufferQueueSize = 1
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            proprieta.sinkBuffersRequiredForStartup = 1
        }
        return proprieta
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        // La durata del fotogramma resta 1/30: l'unica offerta. Si cambia solo il formato.
        if let indice = streamProperties.activeFormatIndex, formati.indices.contains(indice) {
            indiceAttivo = indice
            if direzione == .source { proprietario?.cambiaFormato(indice) }
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        guard direzione == .sink else { return true }
        // Il flusso di ingresso è solo per l'app WebcamLR: un'altra app non può sostituirne il video.
        // Senza firma leggibile si lascia passare, per non bloccare WebcamLR stessa.
        let firma: String? = client.signingID
        if let firma, !firma.contains(identificativoApp) {
            registro.error("Ingresso rifiutato a \(firma, privacy: .public)")
            return false
        }
        clientIngresso = client
        return true
    }

    func startStream() throws {
        guard let proprietario else { return }
        if direzione == .sink {
            if let clientIngresso { proprietario.avviaIngresso(client: clientIngresso) }
        } else {
            proprietario.avviaInvio()
        }
    }

    func stopStream() throws {
        guard let proprietario else { return }
        if direzione == .sink {
            proprietario.fermaIngresso()
        } else {
            proprietario.fermaInvio()
        }
    }
}

final class SorgenteProvider: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var sorgenteDispositivo: SorgenteDispositivo!

    init(codaClient: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: codaClient)
        sorgenteDispositivo = SorgenteDispositivo(nome: "WebcamLR")
        do {
            try provider.addDevice(sorgenteDispositivo.dispositivo)
        } catch {
            fatalError("Impossibile aggiungere la webcam: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let proprieta = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            proprieta.manufacturer = "LR apps"
        }
        return proprieta
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
