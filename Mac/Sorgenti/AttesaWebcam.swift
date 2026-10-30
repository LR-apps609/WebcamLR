import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import CoreVideo
import Foundation
import ImageIO
import Observation
import os.log
import Stile
import SwiftUI
import WebcamLRProtocollo

// Schermata di attesa: quello che vedono Zoom e le altre app di chiamata (webcam virtuale) e la finestra di WebcamLR
// quando il video del telefono non c'è. Al posto dell'immagine provvisoria verde: fondo quasi nero con la sfumatura
// verde di Stile, il logo piccolo, un titolo in Barlow Condensed e una riga piccola sotto.
//
// Chi fa cosa:
// - `OsservatoreAttesa` (coda principale) segue il `Ricevitore` e dice a ogni `Schermo` e alla webcam perché il video
//   non c'è: telefono non collegato, collegamento interrotto, pausa (`StatoAttesa`).
// - `ProgrammaAttesa` decide istante per istante se mostrare il video o l'attesa: tiene l'ultima immagine 2 secondi
//   dopo una caduta e lascia vincere le immagini che arrivano davvero.
// - `UscitaWebcam` disegna l'attesa e la manda all'estensione nel flusso di ingresso, con le dissolvenze; lo `Schermo`
//   la mette sopra il video della finestra. L'estensione (Mac/FotocameraVirtuale/Fotocamera.swift) ha la sua copia
//   di «La webcam non è collegata» per quando l'app è chiusa: stesso disegno, misure da tenere uguali.
//
// Le immagini si disegnano una volta per stato, stile e misura, non per fotogramma.

/// Perché il video del telefono non c'è.
enum StatoAttesa: Hashable, Sendable {
    /// Nessun telefono collegato (o WebcamLR per Mac chiusa, nell'estensione).
    case nonCollegata
    /// Il telefono si è perso durante l'uso: si aspetta che torni.
    case interrotta
    /// Il telefono è in pausa (`stato.pausa`: sottofondo, fotocamera interrotta, faccia in giù, dall'utente; «nessuna
    /// app» solo i telefoni di prima del 27 ottobre), con il motivo del protocollo per la riga sotto. In sottofondo
    /// anche se il collegamento è caduto: il telefono torna da solo quando si riapre l'app.
    case pausa(motivo: String)

    var titolo: String {
        switch self {
        case .nonCollegata: String(localized: "La webcam non è collegata")
        case .interrotta: String(localized: "Collegamento interrotto")
        case .pausa: String(localized: "Webcam in pausa")
        }
    }

    var sottotitolo: String? {
        switch self {
        case .nonCollegata: String(localized: "Apri WebcamLR sul telefono")
        case .interrotta: String(localized: "Riconnessione in corso…")
        case .pausa(let motivo): Ricevitore.testoPausa(motivo)
        }
    }
}

/// Lo stile della schermata di attesa, scelto in Impostazioni (WebcamLR Pro). Senza Pro vale sempre `webcamLR`.
enum StileAttesa: String, CaseIterable, Sendable {
    /// Il disegno di WebcamLR, con il motivo scritto.
    case webcamLR = "webcamlr"
    /// Tutto nero, senza scritte.
    case nero
    /// Un'immagine scelta dall'utente, che riempie il riquadro (tagliando i bordi se serve), senza scritte.
    case immagine
    /// L'ultima immagine del telefono sfocata e scurita, con il motivo scritto sopra.
    case sfocata
}

/// I dati condivisi della schermata di attesa, letti da più code (webcam, schermi, Impostazioni): tutto sotto `blocco`.
final class AttesaWebcam: @unchecked Sendable {
    static let condivisa = AttesaWebcam()

    /// La chiave in UserDefaults dello stile scelto (resta anche senza Pro: torna valido quando Pro si sblocca).
    static let chiaveStile = "schermataAttesa"

    /// Quello che serve a chi disegna, letto in un colpo solo.
    struct Istantanea: Sendable {
        /// Perché la webcam non ha video (il telefono scelto per la webcam); nil se il video dovrebbe esserci.
        let statoWebcam: StatoAttesa?
        /// Lo stile da usare adesso: quello scelto se Pro è attivo (e, per l'immagine, se c'è), altrimenti `webcamLR`.
        let stile: StileAttesa
        /// Cresce a ogni cambio di stile o d'immagine: chi tiene immagini già disegnate le rifà.
        let versione: Int
    }

    private struct Chiave: Hashable {
        let stato: StatoAttesa
        let stile: StileAttesa
        let larghezza: Int
        let altezza: Int
    }

    private let registro = Logger(subsystem: "it.lrapps.webcamlr.mac", category: "attesa")
    private let blocco = NSLock()
    private var statoWebcam: StatoAttesa? = .nonCollegata
    private var scelta: StileAttesa
    private var pro = false
    private var personale: CGImage?
    private var versione = 0
    /// Le immagini già disegnate (tranne «sfocata», che dipende dall'ultima immagine di chi la chiede).
    private var disegnate: [Chiave: CGImage] = [:]

    private init() {
        scelta = UserDefaults.standard.string(forKey: Self.chiaveStile).flatMap(StileAttesa.init(rawValue:)) ?? .webcamLR
        personale = Self.leggiImmaginePersonale()
    }

    // MARK: - Stato e scelte

    func istantanea() -> Istantanea {
        blocco.lock()
        defer { blocco.unlock() }
        return Istantanea(statoWebcam: statoWebcam, stile: stileEffettivo, versione: versione)
    }

    /// Sotto `blocco`.
    private var stileEffettivo: StileAttesa {
        guard pro else { return .webcamLR }
        if scelta == .immagine && personale == nil { return .webcamLR }
        return scelta
    }

    /// Lo stile scelto dall'utente, anche se adesso non vale (senza Pro).
    var sceltaUtente: StileAttesa {
        blocco.lock()
        defer { blocco.unlock() }
        return scelta
    }

    /// Da Impostazioni.
    func scegli(_ stile: StileAttesa) {
        UserDefaults.standard.set(stile.rawValue, forKey: Self.chiaveStile)
        blocco.lock()
        if stile != scelta {
            scelta = stile
            versione += 1
        }
        blocco.unlock()
    }

    /// Dall'`OsservatoreAttesa`: WebcamLR Pro sbloccato sul telefono (`Ricevitore.proAttivo`).
    func imposta(pro nuovo: Bool) {
        blocco.lock()
        if nuovo != pro {
            pro = nuovo
            versione += 1
        }
        blocco.unlock()
    }

    /// Dall'`OsservatoreAttesa`: perché il telefono scelto per la webcam non manda video (nil se lo manda).
    func imposta(statoWebcam nuovo: StatoAttesa?) {
        blocco.lock()
        statoWebcam = nuovo
        blocco.unlock()
    }

    // MARK: - Immagine personale

    /// L'immagine personale, per l'anteprima in Impostazioni; nil se non è stata scelta.
    var immaginePersonale: CGImage? {
        blocco.lock()
        defer { blocco.unlock() }
        return personale
    }

    /// Dove resta l'immagine personale: nel contenitore dell'app (sandbox). L'estensione non la legge da qui
    /// (gira come utente di sistema): la riceve già disegnata, nel flusso di ingresso come il video.
    private static var fileImmagine: URL {
        URL.applicationSupportDirectory
            .appending(path: "Schermata di attesa", directoryHint: .isDirectory)
            .appending(path: "immagine", directoryHint: .notDirectory)
    }

    /// Un'immagine scelta o trascinata in Impostazioni: si controlla che si apra, si copia nel contenitore
    /// e vale subito. Falso se non è un'immagine leggibile.
    func salvaImmagine(_ dati: Data) -> Bool {
        guard let immagine = Self.decodifica(dati) else { return false }
        do {
            let file = Self.fileImmagine
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try dati.write(to: file, options: .atomic)
        } catch {
            registro.error("Immagine di attesa non salvata: \(error.localizedDescription, privacy: .public)")
            return false
        }
        blocco.lock()
        personale = immagine
        disegnate = [:]
        versione += 1
        blocco.unlock()
        return true
    }

    private static func leggiImmaginePersonale() -> CGImage? {
        guard let dati = try? Data(contentsOf: fileImmagine) else { return nil }
        return decodifica(dati)
    }

    /// Al massimo 3840 pixel sul lato lungo (basta per il 4K), girata secondo l'orientamento della foto.
    private static func decodifica(_ dati: Data) -> CGImage? {
        guard let sorgente = CGImageSourceCreateWithData(dati as CFData, nil) else { return nil }
        let opzioni: NSDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3840
        ]
        return CGImageSourceCreateThumbnailAtIndex(sorgente, 0, opzioni as CFDictionary)
    }

    // MARK: - Disegno

    /// La schermata di attesa per questo stato, nello stile dato, della misura data. Disegnata una volta e poi riusata,
    /// tranne «sfocata»: lì `sfondo` è l'ultima immagine già sfocata (`sfocata(_:contesto:)`) di chi la chiede.
    /// Da qualsiasi coda.
    func immagine(_ stato: StatoAttesa, stile: StileAttesa, sfondo: CGImage? = nil, larghezza: Int, altezza: Int) -> CGImage? {
        let chiave = Chiave(stato: stato, stile: stile, larghezza: larghezza, altezza: altezza)
        blocco.lock()
        let pronta = stile == .sfocata ? nil : disegnate[chiave]
        let personale = self.personale
        blocco.unlock()
        if let pronta { return pronta }
        let nuova = Self.disegna(stato, stile: stile, personale: personale, sfondo: sfondo, larghezza: larghezza, altezza: altezza)
        if stile != .sfocata, let nuova {
            blocco.lock()
            disegnate[chiave] = nuova
            blocco.unlock()
        }
        return nuova
    }

    /// L'ultima immagine del telefono, rimpicciolita, sfocata e scurita: lo sfondo dello stile «sfocata».
    /// Piccola (480 pixel): tanto è sfocata, e si ingrandisce senza costi quando si disegna.
    static func sfocata(_ immagine: CVPixelBuffer, contesto: CIContext) -> CGImage? {
        // Letta in sRGB come nella webcam (UscitaWebcam.adatta): l'immagine YCbCr dello `Schermo` e quella già adattata
        // danno lo stesso fondo.
        let originale = CIImage(cvPixelBuffer: immagine, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        guard originale.extent.width > 0 else { return nil }
        let scala = 480 / originale.extent.width
        let piccola = originale.transformed(by: CGAffineTransform(scaleX: scala, y: scala))
        let scurisci = CIFilter.colorControls()
        scurisci.inputImage = piccola.clampedToExtent().applyingGaussianBlur(sigma: 12).cropped(to: piccola.extent)
        scurisci.brightness = -0.22
        scurisci.saturation = 0.7
        guard let sfocata = scurisci.outputImage else { return nil }
        return contesto.createCGImage(sfocata, from: piccola.extent)
    }

    /// Un'immagine già disegnata in un buffer BGRA su IOSurface, come quelli che l'estensione accetta.
    static func buffer(da immagine: CGImage) -> CVPixelBuffer? {
        let attributi: NSDictionary = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var creato: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, immagine.width, immagine.height, kCVPixelFormatType_32BGRA,
                                  attributi as CFDictionary, &creato) == kCVReturnSuccess, let buffer = creato else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let contesto = contestoBGRA(dati: CVPixelBufferGetBaseAddress(buffer), larghezza: immagine.width,
                                          altezza: immagine.height, righe: CVPixelBufferGetBytesPerRow(buffer)) else { return nil }
        contesto.draw(immagine, in: CGRect(x: 0, y: 0, width: immagine.width, height: immagine.height))
        contesto.flush()
        return buffer
    }

    /// BGRA in memoria = primo canale alfa premoltiplicato, ordine dei byte little-endian (come nell'estensione).
    private static func contestoBGRA(dati: UnsafeMutableRawPointer?, larghezza: Int, altezza: Int, righe: Int) -> CGContext? {
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGContext(data: dati, width: larghezza, height: altezza, bitsPerComponent: 8, bytesPerRow: righe,
                         space: spazio, bitmapInfo: info)
    }

    private static func disegna(_ stato: StatoAttesa, stile: StileAttesa, personale: CGImage?, sfondo: CGImage?,
                                larghezza: Int, altezza: Int) -> CGImage? {
        guard larghezza > 0, altezza > 0,
              let contesto = contestoBGRA(dati: nil, larghezza: larghezza, altezza: altezza, righe: 0) else { return nil }
        let area = CGRect(x: 0, y: 0, width: larghezza, height: altezza)
        contesto.interpolationQuality = .high
        contesto.setFillColor(CGColor(gray: 0, alpha: 1))
        contesto.fill(area)
        if stile == .nero {
            // Solo nero.
        } else if stile == .immagine, let personale {
            contesto.draw(personale, in: riempi(CGSize(width: personale.width, height: personale.height), in: area))
        } else if stile == .sfocata, let sfondo {
            contesto.draw(sfondo, in: riempi(CGSize(width: sfondo.width, height: sfondo.height), in: area))
            disegnaTesti(stato, in: contesto, area: area)
        } else {
            disegnaFondo(in: contesto, area: area)
            disegnaTesti(stato, in: contesto, area: area)
        }
        return contesto.makeImage()
    }

    /// Il rettangolo che copre tutta l'area mantenendo le proporzioni (i bordi in più restano fuori).
    private static func riempi(_ misura: CGSize, in area: CGRect) -> CGRect {
        guard misura.width > 0, misura.height > 0 else { return area }
        let scala = max(area.width / misura.width, area.height / misura.height)
        let larghezza = misura.width * scala
        let altezza = misura.height * scala
        return CGRect(x: area.midX - larghezza / 2, y: area.midY - altezza / 2, width: larghezza, height: altezza)
    }

    /// Fondo quasi nero: la sfumatura del logo (Tema.sfumaturaChiara → sfumaturaScura, dall'alto a sinistra al basso
    /// a destra) scurita della metà, e i bordi ancora un po' più scuri. Uguale in Fotocamera.swift (disegnaAttesa).
    private static func disegnaFondo(in contesto: CGContext, area: CGRect) {
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let w = area.width
        let h = area.height
        // In CoreGraphics l'origine è in basso: y cresce verso l'alto.
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
    }

    /// Il logo piccolo, il titolo e la riga sotto, centrati. Misure per un'immagine alta 1080, in scala per le altre.
    /// Uguali in Fotocamera.swift (disegnaAttesa): se cambiano qui, cambiano anche lì.
    private static func disegnaTesti(_ stato: StatoAttesa, in contesto: CGContext, area: CGRect) {
        let w = area.width
        let h = area.height
        let scala = h / 1080
        // Senza riga sotto il gruppo scende un po', per restare al centro.
        let spostamento = (stato.sottotitolo == nil ? -52 : -26) * scala

        // Il logo: tre quadratini per riga, misure in centesimi del lato come in Stile (18, passo 23).
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
                contesto.setFillColor(colore(Color(esadecimale: LogoWebcamLR.celle[riga][colonna])))
                contesto.fillPath()
            }
        }

        scrivi(stato.titolo, carattere: CTFontCreateWithName("BarlowCondensed-Bold" as CFString, 84 * scala, nil),
               colore: colore(Tema.testo), centroY: h / 2 + 10 * scala + spostamento, larghezza: w, in: contesto)
        if let sottotitolo = stato.sottotitolo {
            scrivi(sottotitolo, carattere: CTFontCreateWithName("Barlow-Medium" as CFString, 34 * scala, nil),
                   colore: colore(Tema.testoSecondario), centroY: h / 2 - 56 * scala + spostamento, larghezza: w, in: contesto)
        }
    }

    private static func colore(_ colore: Color) -> CGColor {
        colore.resolve(in: EnvironmentValues()).cgColor
    }

    private static func scrivi(_ testo: String, carattere: CTFont, colore: CGColor, centroY: CGFloat,
                               larghezza: CGFloat, in contesto: CGContext) {
        let attributi: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: kCTFontAttributeName as String): carattere,
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

/// Decide se mostrare il video o la schermata di attesa, e quale. Un valore per chi mostra (la webcam, ogni `Schermo`),
/// usato solo dalla sua coda.
struct ProgrammaAttesa {
    /// Dopo una caduta l'ultima immagine resta ferma per 2 secondi, poi si passa all'attesa.
    static let tenuta: UInt64 = 2_000_000_000

    /// Dall'`OsservatoreAttesa`; all'inizio nessun telefono.
    private(set) var stato: StatoAttesa? = .nonCollegata
    /// Quando `stato` è cambiato l'ultima volta.
    private var statoDa: UInt64 = 0
    /// L'ultima immagine vera arrivata; 0 se non ne è mai arrivata una.
    private var ultimoVivo: UInt64 = 0
    /// L'ultima attesa decisa: resta finché arriva il video.
    private var ultimaAttesa: StatoAttesa = .nonCollegata

    mutating func imposta(_ nuovo: StatoAttesa?, adesso: UInt64) {
        guard nuovo != stato else { return }
        stato = nuovo
        statoDa = adesso
    }

    /// È arrivata un'immagine vera.
    mutating func vivo(adesso: UInt64) {
        ultimoVivo = adesso
    }

    /// nil: si mostra il video. Altrimenti l'attesa da mostrare.
    /// - Le immagini arrivate dopo l'ultimo cambio di stato vincono (lo `stato` arriva sempre un po' dopo il video).
    /// - Collegamento interrotto: l'ultima immagine resta per `tenuta`, poi l'attesa.
    /// - Senza stato (il telefono dovrebbe mandare): se il video si ferma per `tenuta` è un'interruzione;
    ///   se non è ancora arrivato, resta l'attesa di prima (per esempio la pausa, finché il video riparte).
    mutating func attesa(adesso: UInt64) -> StatoAttesa? {
        let recente = ultimoVivo != 0 && adesso &- ultimoVivo < Self.tenuta
        let deciso: StatoAttesa?
        if let stato {
            deciso = recente && (ultimoVivo > statoDa || stato == .interrotta) ? nil : stato
        } else if recente {
            deciso = nil
        } else if ultimoVivo != 0 && ultimoVivo > statoDa {
            deciso = .interrotta
        } else {
            deciso = ultimaAttesa
        }
        if let deciso { ultimaAttesa = deciso }
        return deciso
    }
}

/// Segue il `Ricevitore` (Observation) e passa a ogni `Schermo` e alla webcam il motivo dell'attesa e Pro sì o no.
/// Sulla coda principale. Basta avviarlo una volta con `osserva(_:)`; chiamarlo di nuovo non raddoppia nulla.
@MainActor
final class OsservatoreAttesa {
    static let condiviso = OsservatoreAttesa()

    private weak var ricevitore: Ricevitore?

    func osserva(_ ricevitore: Ricevitore) {
        guard self.ricevitore !== ricevitore else { return }
        self.ricevitore = ricevitore
        segui()
    }

    /// Applica lo stato e si riarma al prossimo cambio di ciò che ha letto (withObservationTracking avvisa una volta sola).
    private func segui() {
        guard let ricevitore else { return }
        withObservationTracking {
            applica(ricevitore)
        } onChange: { [weak self] in
            Task { @MainActor in self?.segui() }
        }
    }

    private func applica(_ ricevitore: Ricevitore) {
        AttesaWebcam.condivisa.imposta(pro: ricevitore.proAttivo)
        for telefono in ricevitore.telefoni {
            telefono.schermo.imposta(attesa: Self.stato(di: telefono))
        }
        let attivo = ricevitore.attivo
        // Senza telefoni `schermo` è quello vuoto, dietro al QR code.
        if attivo == nil { ricevitore.schermo.imposta(attesa: .nonCollegata) }
        AttesaWebcam.condivisa.imposta(statoWebcam: attivo.map { Self.stato(di: $0) } ?? .nonCollegata)
    }

    /// In sottofondo: pausa, anche con il collegamento caduto (Protocollo.md, «Pausa intelligente»). Riconnessione:
    /// interrotta. Collegato ma in pausa: pausa. Altrimenti il video dovrebbe arrivare.
    private static let motiviNoti: Set<String> = [MotiviPausa.sottofondo, MotiviPausa.fotocameraInterrotta,
                                                  MotiviPausa.facciaInGiu, MotiviPausa.nessunaApp, MotiviPausa.utente]

    private static func stato(di telefono: TelefonoCollegato) -> StatoAttesa? {
        if telefono.inSottofondo { return .pausa(motivo: MotiviPausa.sottofondo) }
        if telefono.collegamento == .riconnessione { return .interrotta }
        // Un motivo sconosciuto si mostra come una pausa qualsiasi: uno solo, così le immagini già disegnate (una per
        // stato) non crescono con ogni testo che un telefono può mandare.
        if let motivo = telefono.statoTelefono?.pausa { return .pausa(motivo: motiviNoti.contains(motivo) ? motivo : "") }
        return nil
    }
}
