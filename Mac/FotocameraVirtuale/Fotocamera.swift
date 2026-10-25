import Accelerate
import CoreMediaIO
import CoreText
import Foundation
import IOKit.audio
import os.log
import Stile
import SwiftUI

// Webcam virtuale WebcamLR (funzione 11). Ha due flussi:
// - «video», in uscita: quello che vedono Zoom, FaceTime e le altre app: 1920×1080 e 1280×720 a 30 o 60 fps,
//   3840×2160 a 30 fps (P12);
// - «ingresso», in entrata: l'app WebcamLR ci mette le immagini dell'iPhone (UscitaWebcam.swift),
//   già adattate a 1920×1080 (o 3840×2160, se il telefono manda il 4K) con le bande scure ai lati.
// Il ritmo dell'uscita segue il formato scelto dall'app di chiamata (30 o 60 volte al secondo), anche se
// il telefono manda meno immagini: l'ultima si ripete, già adattata.
// Senza immagini recenti dall'app (oltre 1 secondo) manda l'immagine di attesa:
// «WebcamLR · Apri WebcamLR sul telefono», disegnata una volta sola per formato.
// L'uscita è il video com'è arrivato dal telefono, senza specchi aggiunti qui: «Specchia» lo fa il telefono (1.14).
// L'anteprima di sé la specchiano poi, se vogliono, le app di chiamata.
// Tutto in BGRA a 32 bit (kCVPixelFormatType_32BGRA), come le immagini che arrivano dall'app.

/// Un formato dell'uscita: le app scelgono tra questi.
private struct Formato {
    let larghezza: Int32
    let altezza: Int32
    let fps: Int32

    /// La durata di un fotogramma.
    var durata: CMTime { CMTime(value: 1, timescale: fps) }
    /// Come lo legge l'app (UscitaWebcam.leggiFormato): «1920x1080@60».
    var testo: String { "\(larghezza)x\(altezza)@\(fps)" }
}

/// I primi due restano ai loro posti (indici 0 e 1, come prima della P12): le app ricordano il formato scelto.
/// Il 4K è sempre in elenco (decidono le app); l'app gli manda immagini 4K solo quando il telefono manda il 4K,
/// altrimenti qui si ingrandisce l'immagine 1920×1080.
private let formatiUscita = [
    Formato(larghezza: 1920, altezza: 1080, fps: 30),
    Formato(larghezza: 1280, altezza: 720, fps: 30),
    Formato(larghezza: 1920, altezza: 1080, fps: 60),
    Formato(larghezza: 1280, altezza: 720, fps: 60),
    Formato(larghezza: 3840, altezza: 2160, fps: 30)
]
/// L'app manda 1920×1080 fino a 60 fps, oppure 3840×2160 a 30 fps (UscitaWebcam).
/// Qui si accetta qualsiasi dimensione in BGRA: le immagini si adattano al formato dell'uscita.
private let formatiIngresso = [
    Formato(larghezza: 1920, altezza: 1080, fps: 60),
    Formato(larghezza: 3840, altezza: 2160, fps: 30)
]
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
    /// Proprietà personalizzata «fmto»: il formato scelto dalle app, come «1920x1080@60» (P12).
    /// L'app la legge con CoreMediaIO (UscitaWebcam.leggiFormato): decide se mandare il 4K e se chiedere 60 fps al telefono.
    static let formatoAttivo = CMIOExtensionProperty(rawValue: "4cc_fmto_glob_0000")
    /// Proprietà personalizzata «appl»: le app che stanno usando la webcam, una per riga, con l'identificativo
    /// della firma (per esempio «us.zoom.xos»); «?» per un'app senza firma leggibile, vuota se nessuna.
    /// L'app la legge con CoreMediaIO (UscitaWebcam.leggiApp) e mostra «In uso» sulla scheda giusta.
    static let appInUso = CMIOExtensionProperty(rawValue: "4cc_appl_glob_0000")
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
    /// Le app che hanno avviato l'uscita: identificativo del client → firma («?» se non si legge).
    /// Un client esce dall'elenco quando si scollega dall'estensione o quando nessuno usa più la webcam:
    /// CoreMediaIO non dice quale client ferma il flusso.
    private var appAttive: [UUID: String] = [:]
    private var indiceFormato = 0
    private var timer: DispatchSourceTimer?
    private var ingressoAttivo = false
    /// Cresce a ogni avvio o arresto dell'ingresso: un vecchio giro di lettura si ferma da solo
    /// e non ce ne sono mai due insieme.
    private var giroIngresso: UInt64 = 0
    private var riserve: [Int: CVPixelBufferPool] = [:]
    private var immaginiAttesa: [Int: CVPixelBuffer] = [:]
    /// L'ultima immagine dell'app già adattata al formato: con il telefono a 30 fps e l'uscita a 60
    /// la stessa immagine si manda due volte senza ridimensionarla di nuovo (conta soprattutto per il 4K).
    private var adattataDa: CVPixelBuffer?
    private var adattataPer = -1
    private var adattata: CVPixelBuffer?
    private var avvisoRiservaDato = false
    private let attributiBuffer: NSDictionary = [kCVPixelBufferPoolAllocationThresholdKey: 8]

    init(nome: String) {
        super.init()
        dispositivo = CMIOExtensionDevice(localizedName: nome, deviceID: idDispositivo, legacyDeviceID: nil, source: self)

        sorgenteFlusso = SorgenteFlusso(nome: "WebcamLR · video", id: idFlusso,
                                        formati: formatiUscita.map { Self.formatoFlusso($0) },
                                        durate: formatiUscita.map { $0.durata },
                                        direzione: .source, proprietario: self)
        sorgenteIngresso = SorgenteFlusso(nome: nomeFlussoIngresso, id: idFlussoIngresso,
                                          formati: formatiIngresso.map { Self.formatoFlusso($0) },
                                          durate: formatiIngresso.map { $0.durata },
                                          direzione: .sink, proprietario: self)
        do {
            // Prima l'uscita, poi l'ingresso: l'app, se non trova il nome, prende il secondo flusso.
            try dispositivo.addStream(sorgenteFlusso.flusso)
            try dispositivo.addStream(sorgenteIngresso.flusso)
        } catch {
            fatalError("Impossibile aggiungere il flusso video: \(error.localizedDescription)")
        }
    }

    /// Una durata sola per formato: 30 e 60 fps sono formati diversi, così ogni app sceglie dall'elenco.
    private static func formatoFlusso(_ formato: Formato) -> CMIOExtensionStreamFormat {
        let durata = formato.durata
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
        [.deviceTransportType, .deviceModel, .inOnda, .formatoAttivo, .appInUso]
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
        if properties.contains(.formatoAttivo) {
            proprieta.setPropertyState(statoFormato, forProperty: .formatoAttivo)
        }
        if properties.contains(.appInUso) {
            proprieta.setPropertyState(statoApp, forProperty: .appInUso)
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

    /// Letto dalle richieste di proprietà, come `statoInOnda`.
    private var statoFormato: CMIOExtensionPropertyState<AnyObject> {
        codaTimer.sync { Self.stato(formato: indiceFormato) }
    }

    private static func stato(formato indice: Int) -> CMIOExtensionPropertyState<AnyObject> {
        CMIOExtensionPropertyState(value: formatiUscita[indice].testo as NSString)
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
                appAttive = [:]
                timer?.cancel()
                timer = nil
            }
            return utentiAttivi
        }
        segnalaInOnda(utenti: utenti)
        segnalaApp()
    }

    // MARK: - Quali app usano la webcam

    /// Un'app sta per avviare l'uscita (`authorizedToStartStream` del flusso «video»). Dalle code di CoreMediaIO.
    func appInArrivo(_ client: CMIOExtensionClient) {
        let firma: String? = client.signingID
        let nome = firma.map { $0.isEmpty ? "?" : $0 } ?? "?"
        let id = client.clientID
        codaTimer.sync { appAttive[id] = nome }
        registro.info("Webcam chiesta da \(nome, privacy: .public)")
        segnalaApp()
    }

    /// Un client si è scollegato dall'estensione (SorgenteProvider.disconnect): se usava la webcam, esce dall'elenco.
    func clienteScollegato(_ id: UUID) {
        let tolta = codaTimer.sync { appAttive.removeValue(forKey: id) != nil }
        if tolta { segnalaApp() }
    }

    /// Fuori da codaTimer, come `segnalaInOnda`.
    private func segnalaApp() {
        dispositivo?.notifyPropertiesChanged([.appInUso: statoApp])
    }

    /// Letto dalle richieste di proprietà, come `statoInOnda`. Una firma per riga, senza doppioni, in ordine.
    private var statoApp: CMIOExtensionPropertyState<AnyObject> {
        let elenco = codaTimer.sync { Array(Set(appAttive.values)).sorted() }
        return CMIOExtensionPropertyState(value: elenco.joined(separator: "\n") as NSString)
    }

    func cambiaFormato(_ indice: Int) {
        guard formatiUscita.indices.contains(indice) else { return }
        codaTimer.sync {
            let prima = formatiUscita[indiceFormato].fps
            indiceFormato = indice
            // Il ritmo segue il formato: con un'app già collegata il timer riparte a 30 o 60 fps.
            if timer != nil, prima != formatiUscita[indice].fps {
                timer?.cancel()
                timer = nil
                avviaTimerSeServe()
            }
        }
        let formato = formatiUscita[indice]
        registro.info("Formato \(formato.larghezza)×\(formato.altezza) a \(formato.fps) fps")
        dispositivo?.notifyPropertiesChanged([.formatoAttivo: Self.stato(formato: indice)])
    }

    /// Su codaTimer. Un colpo per fotogramma del formato attuale (30 o 60 al secondo).
    private func avviaTimerSeServe() {
        guard timer == nil else { return }
        let nuovo = DispatchSource.makeTimerSource(flags: .strict, queue: codaTimer)
        nuovo.schedule(deadline: .now(), repeating: 1.0 / Double(formatiUscita[indiceFormato].fps), leeway: .milliseconds(1))
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
                // Niente di pronto o un errore: si riprova tra poco, senza girare a vuoto. 4 ms: a 60 fps
                // un'immagine arriva ogni 16,7 ms e non deve aspettare quasi un fotogramma intero.
                self.codaTimer.asyncAfter(deadline: .now() + .milliseconds(4)) { self.consuma(da: client, giro: giro) }
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

    /// Su codaTimer, 30 o 60 volte al secondo (il formato scelto) mentre almeno un'app usa la webcam.
    private func inviaFotogramma() {
        let indice = indiceFormato
        if let immagine = ultimaDaApp, DispatchTime.now().uptimeNanoseconds &- istanteDaApp < validitaImmagineApp {
            if let pronta = adatta(immagine, indice: indice) {
                invia(pronta, indice: indice)
            } else if let precedente = adattata, adattataPer == indice {
                // Buffer esauriti per un attimo (un'app li tiene ancora): si ripete l'ultima immagine,
                // non si passa all'immagine di attesa mentre il telefono è collegato.
                invia(precedente, indice: indice)
            }
            return
        }
        ultimaDaApp = nil
        adattataDa = nil
        adattata = nil
        adattataPer = -1
        if let attesa = immagineAttesa(indice: indice) {
            invia(attesa, indice: indice)
        }
    }

    /// L'immagine dell'app è 1920×1080 o 3840×2160: si manda com'è se ha già la misura del formato,
    /// altrimenti si riduce (720p, o 1080p da un 4K) o si ingrandisce (4K da 1080p).
    private func adatta(_ immagine: CVPixelBuffer, indice: Int) -> CVPixelBuffer? {
        let formato = formatiUscita[indice]
        guard CVPixelBufferGetPixelFormatType(immagine) == formatoPixel else { return nil }
        if CVPixelBufferGetWidth(immagine) == Int(formato.larghezza), CVPixelBufferGetHeight(immagine) == Int(formato.altezza) {
            return immagine
        }
        // La stessa immagine di prima (uscita più veloce del telefono): già pronta.
        if let gia = adattata, adattataDa === immagine, adattataPer == indice {
            return gia
        }
        guard let riserva = riserva(formato) else { return nil }
        var creato: CVPixelBuffer?
        let esito = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, riserva, attributiBuffer, &creato)
        guard esito == kCVReturnSuccess, let destinazione = creato else {
            if !avvisoRiservaDato {
                avvisoRiservaDato = true
                registro.error("Buffer video esauriti: \(esito)")
            }
            return nil
        }
        guard Self.scala(immagine, in: destinazione) else { return nil }
        adattataDa = immagine
        adattataPer = indice
        adattata = destinazione
        return destinazione
    }

    /// Ridimensiona con vImage, senza tagliare: le immagini dell'app sono sempre 16:9 come l'uscita.
    private static func scala(_ immagine: CVPixelBuffer, in destinazione: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(immagine, .readOnly)
        CVPixelBufferLockBaseAddress(destinazione, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destinazione, [])
            CVPixelBufferUnlockBaseAddress(immagine, .readOnly)
        }
        guard let baseSorgente = CVPixelBufferGetBaseAddress(immagine),
              let baseDestinazione = CVPixelBufferGetBaseAddress(destinazione) else { return false }
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
        return errore == kvImageNoError
    }

    /// Una riserva per misura (30 e 60 fps della stessa risoluzione la dividono).
    private func riserva(_ formato: Formato) -> CVPixelBufferPool? {
        let chiave = Int(formato.larghezza)
        if let esistente = riserve[chiave] { return esistente }
        var nuova: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, Self.attributiPixel(formato), &nuova)
        riserve[chiave] = nuova
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

    private func invia(_ buffer: CVPixelBuffer, indice: Int) {
        var descrizioneCreata: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                     formatDescriptionOut: &descrizioneCreata)
        guard let descrizione = descrizioneCreata else { return }
        let adesso = CMClockGetTime(CMClockGetHostTimeClock())
        var tempi = CMSampleTimingInfo(duration: formatiUscita[indice].durata,
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

    /// Disegnata una volta per misura (30 e 60 fps la dividono) e poi riusata: le app la ricevono
    /// 30 o 60 volte al secondo senza costi.
    private func immagineAttesa(indice: Int) -> CVPixelBuffer? {
        let formato = formatiUscita[indice]
        if let pronta = immaginiAttesa[Int(formato.larghezza)] { return pronta }
        var creato: CVPixelBuffer?
        let esito = CVPixelBufferCreate(kCFAllocatorDefault, Int(formato.larghezza), Int(formato.altezza), formatoPixel,
                                        Self.attributiPixel(formato), &creato)
        guard esito == kCVReturnSuccess, let buffer = creato else {
            registro.error("Immagine di attesa non creata: \(esito)")
            return nil
        }
        Self.disegnaAttesa(in: buffer)
        immaginiAttesa[Int(formato.larghezza)] = buffer
        return buffer
    }

    /// I nove quadratini del logo, riga per riga dall'alto: gli stessi di LogoWebcamLR, presi da Stile.
    private static let celleLogo = LogoWebcamLR.celle

    /// Il fondo verde scuro sfumato del logo, il logo, «WebcamLR» e «Apri WebcamLR sul telefono».
    /// Niente corallo a parte il centro del logo: il corallo è il colore di «in onda».
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

        // In CoreGraphics l'origine è in basso: y cresce verso l'alto. La sfumatura va dall'angolo
        // in alto a sinistra (chiaro) a quello in basso a destra (scuro), come il fondo del logo.
        contesto.setFillColor(colore(Tema.fondo))
        contesto.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let sfumatura = CGGradient(colorsSpace: spazio,
                                      colors: [colore(Tema.sfumaturaChiara), colore(Tema.sfumaturaScura)] as CFArray,
                                      locations: [0, 1]) {
            contesto.drawLinearGradient(sfumatura, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        }

        // Il logo: tre quadratini per riga, misure in centesimi del lato come in Stile (18, passo 23).
        let lato = 150 * scala
        let cella = lato * 0.18
        let passo = lato * 0.23
        let inizioX = (w - (2 * passo + cella)) / 2
        let inizioY = h / 2 + 150 * scala
        for riga in 0..<3 {
            for colonna in 0..<3 {
                let rettangolo = CGRect(x: inizioX + CGFloat(colonna) * passo,
                                        y: inizioY + CGFloat(2 - riga) * passo,
                                        width: cella, height: cella)
                contesto.addPath(CGPath(roundedRect: rettangolo, cornerWidth: lato * 0.04, cornerHeight: lato * 0.04, transform: nil))
                contesto.setFillColor(colore(Color(esadecimale: celleLogo[riga][colonna])))
                contesto.fillPath()
            }
        }

        let titolo = caratteriPronti ? "BarlowCondensed-Bold" : "HelveticaNeue-Bold"
        let sottotitolo = caratteriPronti ? "BarlowCondensed-SemiBold" : "HelveticaNeue-Medium"
        scrivi("WebcamLR", carattere: titolo, dimensione: 132 * scala, colore: colore(Tema.testo),
               centroY: h / 2 + 30 * scala, larghezza: w, in: contesto)
        // Tradotto nel catalogo dei testi della webcam virtuale (FotocameraVirtuale/Localizable.xcstrings, P22).
        // L'estensione gira in un processo di sistema, non dell'utente: segue la lingua del Mac (quella scelta
        // all'installazione di macOS), non quella scelta per l'app in Lingua e zona › Applicazioni.
        scrivi(String(localized: "Apri WebcamLR sul telefono"), carattere: sottotitolo, dimensione: 56 * scala,
               colore: colore(Tema.salviaChiara), centroY: h / 2 - 80 * scala, larghezza: w, in: contesto)
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
    /// La durata di un fotogramma di ogni formato, nello stesso ordine.
    private let durate: [CMTime]
    private weak var proprietario: SorgenteDispositivo?
    private var indiceAttivo = 0
    private var clientIngresso: CMIOExtensionClient?

    init(nome: String, id: UUID, formati: [CMIOExtensionStreamFormat], durate: [CMTime],
         direzione: CMIOExtensionStream.Direction, proprietario: SorgenteDispositivo) {
        self.formati = formati
        self.durate = durate
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
            proprieta.frameDuration = durate.indices.contains(indiceAttivo) ? durate[indiceAttivo] : CMTime(value: 1, timescale: 30)
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            // Qualche posto in più di uno: a 60 fps (o con un'immagine 4K da copiare) un posto solo si trova
            // spesso occupato e l'app scarta l'immagine. Si prende sempre la più recente: l'attesa resta breve.
            proprieta.sinkBufferQueueSize = 3
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            proprieta.sinkBuffersRequiredForStartup = 1
        }
        return proprieta
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        // Ogni formato ha una durata sola (30 e 60 fps sono formati diversi): conta solo il formato scelto,
        // e con lui cambia il ritmo dell'uscita.
        if let indice = streamProperties.activeFormatIndex, formati.indices.contains(indice) {
            indiceAttivo = indice
            if direzione == .source { proprietario?.cambiaFormato(indice) }
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        guard direzione == .sink else {
            // L'uscita è per tutte le app; si annota quale la chiede, per «In uso» sulla sua scheda.
            proprietario?.appInArrivo(client)
            return true
        }
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

    func disconnect(from client: CMIOExtensionClient) {
        sorgenteDispositivo.clienteScollegato(client.clientID)
    }

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
