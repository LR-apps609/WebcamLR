import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import Observation

/// P09 Volto e scrivania (`doppiaVista` nel protocollo), come «Vista scrivania» di Continuity.
///
/// Uso vero: iPhone sul supporto, con la fotocamera posteriore rivolta verso chi parla (il modo consigliato).
/// La frontale vede il volto ma non la scrivania, e la posteriore guarda dall'altra parte: due obiettivi
/// insieme (`AVCaptureMultiCamSession`) non servono a nulla. Basta il **Grandangolo 0,5× rivolto verso
/// l'utente**: in un solo fotogramma ci sono il volto (in alto al centro) e il piano della scrivania (in basso).
/// Da quel fotogramma si ritagliano due zone:
///
/// - **volto**: un riquadro nella metà alta, centrato sul volto più grande (analisi `.volti`, centro levigato);
///   senza volto, al centro;
/// - **scrivania**: un trapezio nella parte bassa, raddrizzato con `CIPerspectiveCorrection`, allungato in
///   verticale (la prospettiva schiaccia la profondità) e girato di 180°: i fogli sulla scrivania sono girati
///   verso chi parla, quindi per la fotocamera sono capovolti. Con lo specchio acceso basta il capovolgimento
///   verticale, perché quello orizzontale l'ha già fatto la cattura.
///
/// Composizione: affiancate (volto a sinistra, scrivania a destra) oppure scrivania a tutto schermo con il volto
/// in un riquadro in alto a destra. Le dimensioni del video non cambiano. Funziona su ogni iPhone con il
/// Grandangolo 0,5×; senza, `capacita.doppiaVista` è falso.
///
/// Fase `.doppiaVista`: dopo sfondo e pelle (che usano maschera e volti del fotogramma intero, e così valgono
/// anche nei due ritagli), prima di inquadratura, filtro e scritta. L'inquadratura automatica resta sospesa
/// mentre la doppia vista è accesa (lo zoom taglierebbe la scrivania); filtro, regolazioni e scritta valgono
/// sul video composto. `trasformazione(per:)` resta l'identità: dopo non c'è nessun effetto che usi coordinate.
final class EffettoDoppiaVista: Effetto, @unchecked Sendable {
    enum Disposizione: String, CaseIterable, Identifiable, Sendable {
        /// Volto a sinistra, scrivania a destra, metà e metà.
        case affiancate
        /// Scrivania a tutto schermo, volto in un riquadro in alto a destra.
        case riquadro

        var id: String { rawValue }

        var nome: String {
            switch self {
            case .affiancate: "Affiancate"
            case .riquadro: "Scrivania e riquadro"
            }
        }
    }

    struct Impostazioni: Equatable, Sendable {
        var accesa = false
        var disposizione: Disposizione = .affiancate
        /// L'uscita della cattura è specchiata (Impostazioni › Specchia).
        var specchiato = false
    }

    let nome = "Volto e scrivania"

    /// Il trapezio della scrivania, normalizzato con l'origine in basso a sinistra: largo in basso (vicino al
    /// telefono), stretto in alto (lontano). Da tarare con le prove vere.
    private static let scrivaniaBassoSinistra = CGPoint(x: 0.12, y: 0.0)
    private static let scrivaniaBassoDestra = CGPoint(x: 0.88, y: 0.0)
    private static let scrivaniaAltoSinistra = CGPoint(x: 0.3, y: 0.34)
    private static let scrivaniaAltoDestra = CGPoint(x: 0.7, y: 0.34)
    /// Quanto allungare in verticale la scrivania raddrizzata: la prospettiva la schiaccia.
    private static let allungamentoScrivania: CGFloat = 2
    /// Altezza del ritaglio del volto, in frazione dell'altezza del fotogramma.
    private static let altezzaVolto: CGFloat = 0.5
    /// Colore dietro i due riquadri (il fondo di Stile, 0x0F1413).
    private static let fondo = CIColor(red: 15 / 255, green: 20 / 255, blue: 19 / 255)

    private let blocco = NSLock()
    /// Protette da `blocco`.
    private var interne = Impostazioni()

    // Solo sulla coda di cattura: il centro del volto levigato (normalizzato, origine in basso a sinistra).
    private var centroVolto = CGPoint(x: 0.5, y: 0.75)

    var impostazioni: Impostazioni {
        get { blocco.withLock { interne } }
        set { blocco.withLock { interne = newValue } }
    }

    var attivo: Bool { impostazioni.accesa }

    var analisiNecessarie: Set<TipoAnalisi> { [.volti] }

    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage {
        let attuali = impostazioni
        let estensione = immagine.extent
        guard estensione.width > 0, estensione.height > 0 else { return immagine }
        seguiVolto(contesto.volti)

        let boxVolto: CGRect
        let boxScrivania: CGRect
        switch attuali.disposizione {
        case .affiancate:
            let meta = (estensione.width / 2).rounded()
            boxVolto = CGRect(x: estensione.minX, y: estensione.minY, width: meta, height: estensione.height)
            boxScrivania = CGRect(x: estensione.minX + meta, y: estensione.minY,
                                  width: estensione.width - meta, height: estensione.height)
        case .riquadro:
            let margine = (estensione.width * 0.025).rounded()
            let larghezza = (estensione.width * 0.27).rounded()
            let altezza = min((larghezza * 4 / 3).rounded(), estensione.height - 2 * margine)
            boxScrivania = estensione
            boxVolto = CGRect(x: estensione.maxX - margine - larghezza, y: estensione.maxY - margine - altezza,
                              width: larghezza, height: altezza)
        }

        let fondo = CIImage(color: Self.fondo).cropped(to: estensione)
        let scrivania = self.scrivania(immagine, specchiato: attuali.specchiato, in: boxScrivania)
        var risultato = scrivania.composited(over: fondo)
        if attuali.disposizione == .riquadro {
            // Un bordo sottile scuro attorno al riquadro del volto, per staccarlo dalla scrivania.
            let bordo = max((estensione.height / 360).rounded(), 2)
            risultato = CIImage(color: Self.fondo).cropped(to: boxVolto.insetBy(dx: -bordo, dy: -bordo))
                .composited(over: risultato)
        }
        risultato = volto(immagine, in: boxVolto).composited(over: risultato)
        return risultato.cropped(to: estensione)
    }

    // MARK: - Interni (coda di cattura)

    /// Il centro del volto più grande nella metà alta, levigato; senza volti recenti torna piano al centro.
    private func seguiVolto(_ volti: VoltiRilevati?) {
        var bersaglio = CGPoint(x: 0.5, y: 0.75)
        if let volti, ProcessInfo.processInfo.systemUptime - volti.quando < 1,
           let principale = volti.rettangoli.filter({ $0.midY > 0.4 }).max(by: { $0.width * $0.height < $1.width * $1.height }) {
            bersaglio = CGPoint(x: principale.midX, y: principale.midY)
        }
        centroVolto.x += (bersaglio.x - centroVolto.x) * 0.08
        centroVolto.y += (bersaglio.y - centroVolto.y) * 0.08
    }

    /// Il riquadro del volto con le proporzioni di `box`, dentro il fotogramma.
    private func volto(_ immagine: CIImage, in box: CGRect) -> CIImage {
        let estensione = immagine.extent
        let altezza = estensione.height * Self.altezzaVolto
        let larghezza = min(altezza * box.width / box.height, estensione.width)
        let altezzaVera = larghezza * box.height / box.width
        var x = estensione.minX + centroVolto.x * estensione.width - larghezza / 2
        // Il volto un po' sopra il centro del riquadro, come in un'inquadratura normale.
        var y = estensione.minY + centroVolto.y * estensione.height - altezzaVera * 0.55
        x = min(max(x, estensione.minX), estensione.maxX - larghezza)
        y = min(max(y, estensione.minY), estensione.maxY - altezzaVera)
        return Self.riempi(immagine, sorgente: CGRect(x: x, y: y, width: larghezza, height: altezzaVera), box: box)
    }

    /// La scrivania raddrizzata, girata per chi guarda e ritagliata con le proporzioni di `box`.
    private func scrivania(_ immagine: CIImage, specchiato: Bool, in box: CGRect) -> CIImage {
        let estensione = immagine.extent
        func punto(_ normalizzato: CGPoint) -> CIVector {
            CIVector(x: estensione.minX + normalizzato.x * estensione.width,
                     y: estensione.minY + normalizzato.y * estensione.height)
        }
        let raddrizzata = immagine.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": punto(Self.scrivaniaAltoSinistra),
            "inputTopRight": punto(Self.scrivaniaAltoDestra),
            "inputBottomLeft": punto(Self.scrivaniaBassoSinistra),
            "inputBottomRight": punto(Self.scrivaniaBassoDestra)
        ])
        let base = raddrizzata.extent
        guard base.width > 1, base.height > 1, base.width.isFinite, base.height.isFinite else {
            return CIImage(color: Self.fondo).cropped(to: box)
        }
        // 180° attorno al centro (con lo specchio basta il capovolgimento verticale), poi l'allungamento.
        let girata = raddrizzata.transformed(by: CGAffineTransform(translationX: -base.midX, y: -base.midY)
            .concatenating(CGAffineTransform(scaleX: specchiato ? 1 : -1, y: -Self.allungamentoScrivania))
            .concatenating(CGAffineTransform(translationX: base.midX, y: base.midY)))
        let disponibile = girata.extent
        // Le proporzioni di `box`, al centro dello spazio disponibile.
        var sorgente = disponibile
        let proporzioneBox = box.width / box.height
        if disponibile.width / disponibile.height > proporzioneBox {
            sorgente.size.width = disponibile.height * proporzioneBox
            sorgente.origin.x = disponibile.midX - sorgente.width / 2
        } else {
            sorgente.size.height = disponibile.width / proporzioneBox
            sorgente.origin.y = disponibile.midY - sorgente.height / 2
        }
        return Self.riempi(girata, sorgente: sorgente, box: box)
    }

    /// `sorgente` dell'immagine portato a riempire `box`.
    private static func riempi(_ immagine: CIImage, sorgente: CGRect, box: CGRect) -> CIImage {
        guard sorgente.width > 0, sorgente.height > 0 else { return CIImage(color: fondo).cropped(to: box) }
        let trasformazione = CGAffineTransform(translationX: -sorgente.minX, y: -sorgente.minY)
            .concatenating(CGAffineTransform(scaleX: box.width / sorgente.width, y: box.height / sorgente.height))
            .concatenating(CGAffineTransform(translationX: box.minX, y: box.minY))
        // Bordi ripetuti prima di scalare: niente orli trasparenti ai lati dei riquadri.
        return immagine.clampedToExtent().cropped(to: sorgente).transformed(by: trasformazione).cropped(to: box)
    }
}

/// Stato di «Volto e scrivania» per l'interfaccia e il protocollo. Non si salva: accenderla cambia l'obiettivo,
/// e all'avvio di una sessione nuova l'iPhone riparte con l'obiettivo di sempre. La disposizione invece resta.
@Observable
@MainActor
final class DoppiaVista {
    enum Chiave {
        static let disposizione = "doppiaVista.disposizione"
    }

    private(set) var attiva = false
    private(set) var disposizione: EffettoDoppiaVista.Disposizione
    /// Serve il Grandangolo 0,5× (posteriore).
    let disponibile = Obiettivo.disponibili.contains(.grandangolo)

    let effetto = EffettoDoppiaVista()

    init() {
        disposizione = EffettoDoppiaVista.Disposizione(rawValue: UserDefaults.standard.string(forKey: Chiave.disposizione) ?? "")
            ?? .affiancate
        effetto.impostazioni.disposizione = disposizione
    }

    /// Solo l'effetto: obiettivo e inquadratura li gestisce la sessione (`SessioneTelefono.impostaDoppiaVista`).
    func imposta(_ accesa: Bool) {
        let nuova = accesa && disponibile
        guard nuova != attiva else { return }
        attiva = nuova
        effetto.impostazioni.accesa = nuova
    }

    func impostaDisposizione(_ nuova: EffettoDoppiaVista.Disposizione) {
        guard nuova != disposizione else { return }
        disposizione = nuova
        effetto.impostazioni.disposizione = nuova
        UserDefaults.standard.set(nuova.rawValue, forKey: Chiave.disposizione)
    }

    /// Da chiamare quando la fotocamera parte con lo specchio scelto nelle Impostazioni.
    func impostaSpecchio(_ specchiato: Bool) {
        effetto.impostazioni.specchiato = specchiato
    }
}
