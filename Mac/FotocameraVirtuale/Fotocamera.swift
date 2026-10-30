import Accelerate
import CoreMediaIO
import CoreText
import Foundation
import IOKit.audio
import os.log
import Stile
import SwiftUI
import VideoToolbox

// Webcam virtuale WebcamLR (funzione 11). Ha due flussi:
// - «video», in uscita: quello che vedono Zoom, FaceTime e le altre app: 1920×1080 e 1280×720 a 30 o 60 fps,
//   3840×2160 a 30 fps (P12);
// - «ingresso», in entrata: l'app WebcamLR ci mette le immagini dell'iPhone (UscitaWebcam.swift),
//   già adattate a 1920×1080 (o 3840×2160, se il telefono manda il 4K) con le bande scure ai lati.
// Il ritmo dell'uscita segue il formato scelto dall'app di chiamata (30 o 60 volte al secondo), anche se
// il telefono manda meno immagini: l'ultima si ripete, già adattata. Il ritmo si aggancia alle immagini dell'app
// (`riallinea`): ogni immagine nuova aspetta al massimo mezzo fotogramma, di solito un quarto, ed esce sempre la più
// recente. Quanto aspetta lo dice la proprietà «ritd» (ritardo «da vetro a uscita», Protocollo.md «Latenza»).
// La schermata di attesa (telefono non collegato, collegamento interrotto, pausa, e gli stili di WebcamLR Pro)
// la disegna l'app e la manda qui come il video (UscitaWebcam e AttesaWebcam.swift): l'estensione non sa nulla di stati.
// Solo se dall'app non arriva più niente per 2 secondi (WebcamLR per Mac chiusa o bloccata) l'ultima immagine
// si dissolve in mezzo secondo nella sua schermata: «WebcamLR è chiusa · Apri WebcamLR sul Mac» (passo 7: prima diceva
// «sul telefono», ma è il Mac da aprire), disegnata una volta sola per formato con il disegno dell'app
// (AttesaWebcam.disegnaFondo e disegnaTesti). Su Windows la webcam dice lo stesso, con «sul computer».
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
    /// Proprietà personalizzata «ritd»: quanti millisecondi un'immagine dell'app aspetta qui dentro prima di uscire verso
    /// le app di chiamata (mediana dell'ultimo secondo), per il ritardo «da vetro a uscita» (Protocollo.md, «Latenza»).
    /// Vuota se nessuna app usa la webcam. L'app la legge con CoreMediaIO (UscitaWebcam.leggiAttesaEstensione).
    static let attesaUscita = CMIOExtensionProperty(rawValue: "4cc_ritd_glob_0000")
}

/// Oltre questo tempo senza immagini dall'app l'ultima resta ferma e poi si passa all'immagine di attesa.
/// L'app manda la sua attesa almeno 5 volte al secondo: si arriva qui solo se l'app non manda più nulla.
private let validitaImmagineApp: UInt64 = 2_000_000_000
/// La dissolvenza dall'ultima immagine all'attesa: mezzo secondo, in pochi passi già mescolati
/// (uno alla volta, tenuto finché serve: a 60 fps ogni passo vale per più fotogrammi).
private let durataDissolvenza: UInt64 = 500_000_000
private let passiDissolvenza: UInt64 = 8

/// I caratteri di Stile (Barlow Condensed e Barlow), se Xcode ha messo il pacchetto delle risorse nell'estensione.
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
        // Barlow per la riga sotto il titolo; se mancasse, il carattere di sistema.
        if let url = pacchetto.url(forResource: "Barlow-Medium", withExtension: "ttf", subdirectory: "Caratteri") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
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
    /// L'ultima immagine dell'app mandata alle app di chiamata, e per quale formato: da qui parte la dissolvenza.
    private var ultimaInviata: CVPixelBuffer?
    private var ultimaInviataPer = -1
    /// La dissolvenza verso l'attesa in corso: da quale immagine, quando è cominciata, il passo già mescolato.
    private var dissolvenzaDa: CVPixelBuffer?
    private var dissolvenzaInizio: UInt64 = 0
    private var passoMescolato: UInt64 = .max
    private var mescolata: CVPixelBuffer?

    // Ritmo dell'uscita agganciato alle immagini dell'app (vedi `riallinea`) e attesa misurata qui dentro.
    /// L'immagine dell'app arrivata dopo l'ultimo invio, non ancora mandata.
    private var nuovaDaApp = false
    /// Il colpo del timer più recente (anche virtuale, dopo un riallineamento): il prossimo è a `ultimoColpo + durata`.
    private var ultimoColpo: UInt64 = 0
    /// Quando è uscita l'ultima immagine nuova dell'app.
    private var ultimoNuovoInviato: UInt64 = 0
    /// Attese (ns) dall'arrivo alla prima uscita di ogni immagine nuova, per la mediana di ogni secondo.
    private var attese: [UInt64] = []
    private var inizioAttese: UInt64 = 0
    private var attesaMs: Int?
    private var istanteAttesa: UInt64 = 0

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
        [.deviceTransportType, .deviceModel, .inOnda, .formatoAttivo, .appInUso, .attesaUscita]
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
        if properties.contains(.attesaUscita) {
            proprieta.setPropertyState(statoAttesa, forProperty: .attesaUscita)
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

    /// Letto dalle richieste di proprietà, come `statoInOnda`: l'attesa qui dentro in millisecondi, vuota se non si sa
    /// (nessuna app usa la webcam, o la misura è più vecchia di 2 secondi).
    private var statoAttesa: CMIOExtensionPropertyState<AnyObject> {
        let testo = codaTimer.sync { () -> String in
            let adesso = DispatchTime.now().uptimeNanoseconds
            guard timer != nil, let attesaMs, adesso &- istanteAttesa < 2_000_000_000 else { return "" }
            return String(attesaMs)
        }
        return CMIOExtensionPropertyState(value: testo as NSString)
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
        nuovo.setEventHandler { [weak self] in
            guard let self else { return }
            self.ultimoColpo = DispatchTime.now().uptimeNanoseconds
            self.inviaFotogramma()
        }
        nuovo.resume()
        timer = nuovo
    }

    /// La durata di un fotogramma del formato attuale, in nanosecondi.
    private var durataNanosecondi: UInt64 { 1_000_000_000 / UInt64(formatiUscita[indiceFormato].fps) }

    /// Su codaTimer, all'arrivo di un'immagine nuova dall'app. Ritmo regolare senza più di mezzo fotogramma in più:
    /// il timer batte al ritmo del formato, ma se l'immagine aspetterebbe il prossimo colpo per più di mezzo fotogramma
    /// (è arrivata appena dopo un colpo) esce subito e il timer si riallinea a un quarto di fotogramma dopo l'arrivo.
    /// Da lì le immagini successive (stesso ritmo, con un po' di variazione della rete) arrivano poco prima di un colpo e
    /// aspettano circa un quarto di fotogramma: l'uscita resta regolare. Non si esce mai prima di 3/4 di fotogramma
    /// dall'ultima immagine nuova: con il telefono più veloce dell'uscita (60 → 30) il ritmo resta quello dell'uscita.
    private func riallinea(arrivo: UInt64) {
        guard let timer else { return }
        let durata = durataNanosecondi
        let prossimo = ultimoColpo &+ durata
        let attesa = prossimo > arrivo ? prossimo - arrivo : 0
        guard attesa > durata / 2, arrivo &- ultimoNuovoInviato >= durata * 3 / 4 else { return }
        inviaFotogramma()
        let quarto = durata / 4
        timer.schedule(deadline: .now() + .nanoseconds(Int(durata + quarto)), repeating: .nanoseconds(Int(durata)),
                       leeway: .milliseconds(1))
        ultimoColpo = arrivo &+ quarto
    }

    /// Su codaTimer, alla prima uscita di un'immagine nuova: quanto ha aspettato qui dentro. La mediana di ogni secondo
    /// è la proprietà «ritd».
    private func misuraAttesa(adesso: UInt64) {
        guard nuovaDaApp else { return }
        nuovaDaApp = false
        ultimoNuovoInviato = adesso
        if attese.isEmpty { inizioAttese = adesso }
        attese.append(adesso &- istanteDaApp)
        guard adesso &- inizioAttese >= 1_000_000_000 else { return }
        attese.sort()
        attesaMs = Int(attese[attese.count / 2] / 1_000_000)
        istanteAttesa = adesso
        attese.removeAll(keepingCapacity: true)
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
                self.nuovaDaApp = true
                // Se l'app ne ha messe più d'una in coda, la prossima lettura arriva subito e prende il posto di questa:
                // esce sempre la più recente.
                self.riallinea(arrivo: arrivo)
                self.consuma(da: client, giro: giro)
            }
        }
    }

    // MARK: - Uscita verso le app

    /// Su codaTimer, 30 o 60 volte al secondo (il formato scelto) mentre almeno un'app usa la webcam.
    private func inviaFotogramma() {
        let indice = indiceFormato
        let adesso = DispatchTime.now().uptimeNanoseconds
        if let immagine = ultimaDaApp, adesso &- istanteDaApp < validitaImmagineApp {
            dissolvenzaDa = nil
            mescolata = nil
            if let pronta = adatta(immagine, indice: indice) {
                invia(pronta, indice: indice)
                misuraAttesa(adesso: adesso)
                ultimaInviata = pronta
                ultimaInviataPer = indice
            } else if let precedente = adattata, adattataPer == indice {
                // Buffer esauriti per un attimo (un'app li tiene ancora): si ripete l'ultima immagine,
                // non si passa all'immagine di attesa mentre il telefono è collegato.
                invia(precedente, indice: indice)
            }
            return
        }
        if ultimaDaApp != nil {
            // L'app non manda più nulla da 2 secondi: l'ultima immagine si dissolve nell'attesa.
            if let ultima = ultimaInviata, ultimaInviataPer == indice {
                dissolvenzaDa = ultima
                dissolvenzaInizio = adesso
                passoMescolato = .max
            }
            ultimaDaApp = nil
        }
        adattataDa = nil
        adattata = nil
        adattataPer = -1
        ultimaInviata = nil
        guard let attesa = immagineAttesa(indice: indice) else { return }
        if let da = dissolvenzaDa {
            let trascorso = adesso &- dissolvenzaInizio
            if trascorso < durataDissolvenza, CVPixelBufferGetWidth(da) == CVPixelBufferGetWidth(attesa),
               CVPixelBufferGetHeight(da) == CVPixelBufferGetHeight(attesa) {
                let passo = trascorso * passiDissolvenza / durataDissolvenza
                if passo != passoMescolato {
                    // Opacità dell'attesa da 1/9 a 8/9: l'ultimo passo è l'attesa stessa.
                    mescolata = mescola(da, attesa, opacita: CGFloat(passo + 1) / CGFloat(passiDissolvenza + 1), indice: indice)
                    passoMescolato = passo
                }
                if let mescolata {
                    invia(mescolata, indice: indice)
                    return
                }
            } else {
                dissolvenzaDa = nil
                mescolata = nil
            }
        }
        invia(attesa, indice: indice)
    }

    /// Un passo della dissolvenza: `attesa` sopra `da` con l'opacità data, in un buffer della riserva.
    /// Con CoreGraphics, una volta per passo (non per fotogramma), su codaTimer.
    private func mescola(_ da: CVPixelBuffer, _ attesa: CVPixelBuffer, opacita: CGFloat, indice: Int) -> CVPixelBuffer? {
        guard let riserva = riserva(formatiUscita[indice]) else { return nil }
        var creato: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, riserva, attributiBuffer as CFDictionary, &creato) == kCVReturnSuccess,
              let destinazione = creato else { return nil }
        var immagineDa: CGImage?
        var immagineArrivo: CGImage?
        VTCreateCGImageFromCVPixelBuffer(da, options: nil, imageOut: &immagineDa)
        VTCreateCGImageFromCVPixelBuffer(attesa, options: nil, imageOut: &immagineArrivo)
        guard let immagineDa, let immagineArrivo else { return nil }
        CVPixelBufferLockBaseAddress(destinazione, [])
        defer { CVPixelBufferUnlockBaseAddress(destinazione, []) }
        let larghezza = CVPixelBufferGetWidth(destinazione)
        let altezza = CVPixelBufferGetHeight(destinazione)
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB),
              let contesto = CGContext(data: CVPixelBufferGetBaseAddress(destinazione), width: larghezza, height: altezza,
                                       bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(destinazione), space: spazio,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let area = CGRect(x: 0, y: 0, width: larghezza, height: altezza)
        contesto.draw(immagineDa, in: area)
        contesto.setAlpha(opacita)
        contesto.draw(immagineArrivo, in: area)
        contesto.flush()
        return destinazione
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
        let esito = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, riserva, attributiBuffer as CFDictionary, &creato)
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

    /// Fondo quasi nero con la sfumatura verde del logo, il logo piccolo, «WebcamLR è chiusa»
    /// e «Apri WebcamLR sul Mac». Niente corallo a parte il centro del logo: il corallo è il colore di «in onda».
    /// Lo stesso disegno, con le stesse misure, dell'app (AttesaWebcam.disegnaFondo e disegnaTesti): cambiarli insieme.
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
        // in alto a sinistra (chiaro) a quello in basso a destra (scuro), come il fondo del logo,
        // poi scurita della metà, con i bordi ancora un po' più scuri.
        let area = CGRect(x: 0, y: 0, width: w, height: h)
        contesto.setFillColor(CGColor(gray: 0, alpha: 1))
        contesto.fill(area)
        if let sfumatura = CGGradient(colorsSpace: spazio,
                                      colors: [colore(Tema.sfumaturaChiara), colore(Tema.sfumaturaScura)] as CFArray,
                                      locations: [0, 1]) {
            contesto.drawLinearGradient(sfumatura, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        }
        contesto.setFillColor(CGColor(gray: 0, alpha: 0.5))
        contesto.fill(area)
        if let bordi = CGGradient(colorsSpace: spazio,
                                  colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.45)] as CFArray,
                                  locations: [0.35, 1]) {
            let centro = CGPoint(x: w / 2, y: h / 2)
            contesto.drawRadialGradient(bordi, startCenter: centro, startRadius: 0, endCenter: centro,
                                        endRadius: hypot(w, h) / 2, options: [.drawsAfterEndLocation])
        }

        // Titolo e riga sotto: il gruppo scende un po' per restare al centro.
        let spostamento = -26 * scala

        // Il logo piccolo: tre quadratini per riga, misure in centesimi del lato come in Stile (18, passo 23).
        let lato = 120 * scala
        let cella = lato * 0.18
        let passo = lato * 0.23
        let inizioX = (w - (2 * passo + cella)) / 2
        let inizioY = h / 2 + 76 * scala + spostamento
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

        // Barlow Condensed per il titolo e Barlow per la riga sotto; senza il pacchetto di Stile, Helvetica.
        let titolo = CTFontCreateWithName((caratteriPronti ? "BarlowCondensed-Bold" : "HelveticaNeue-Bold") as CFString,
                                          84 * scala, nil)
        let sottotitolo = CTFontCreateWithName((caratteriPronti ? "Barlow-Medium" : "HelveticaNeue-Medium") as CFString,
                                               34 * scala, nil)
        // Tradotti nel catalogo dei testi della webcam virtuale (FotocameraVirtuale/Localizable.xcstrings, P22).
        // L'estensione gira in un processo di sistema, non dell'utente: segue la lingua del Mac (quella scelta
        // all'installazione di macOS; italiano, altrimenti inglese), non quella scelta per l'app in Lingua e zona › Applicazioni.
        scrivi(String(localized: "WebcamLR è chiusa"), carattere: titolo, colore: colore(Tema.testo),
               centroY: h / 2 + 10 * scala + spostamento, larghezza: w, in: contesto)
        scrivi(String(localized: "Apri WebcamLR sul Mac"), carattere: sottotitolo, colore: colore(Tema.testoSecondario),
               centroY: h / 2 - 56 * scala + spostamento, larghezza: w, in: contesto)
        contesto.flush()
    }

    private static func colore(_ colore: Color) -> CGColor {
        colore.resolve(in: EnvironmentValues()).cgColor
    }

    private static func scrivi(_ testo: String, carattere font: CTFont, colore: CGColor,
                               centroY: CGFloat, larghezza: CGFloat, in contesto: CGContext) {
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
