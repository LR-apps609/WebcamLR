import CoreGraphics
import CoreImage
import CoreMedia
import Foundation

/// P04 Inquadratura automatica: uno zoom digitale che tiene il volto (o tutti i volti) al centro del video,
/// con movimenti morbidi, come farebbe un operatore.
///
/// - Bersaglio: l'unione dei rettangoli dei volti di `AnalisiFotogramma` (un risultato ogni 3 fotogrammi),
///   con aria attorno (il volto occupa circa un terzo dell'altezza) e il volto un po' sopra il centro.
///   Zoom da 1× a `zoomMassimo` (1,6×): oltre, l'immagine perderebbe troppa definizione.
/// - Zona morta: il bersaglio cambia solo se il nuovo si sposta di più del 6% del riquadro o lo zoom di più
///   dell'8%: piccoli movimenti della testa non fanno tremare l'immagine.
/// - Movimento: una molla smorzata in modo critico su centro e zoom (arriva senza oscillare in circa un
///   secondo e mezzo); tra un risultato dell'analisi e il successivo è la molla a interpolare.
/// - Nessun volto per 2 secondi: si torna piano all'inquadratura intera (molla più lenta).
/// - Spenta mentre è zoomata: torna morbida all'inquadratura intera, poi l'effetto si spegne del tutto.
/// - Le dimensioni e le proporzioni del video non cambiano: si ritaglia e si riscala alla misura d'ingresso.
///
/// Scelta: sempre la versione digitale, anche sugli iPhone che hanno Center Stage sulla frontale (iOS 17+).
/// Center Stage di sistema vale per tutta l'app, cambia il campo visivo del formato, limita lo zoom e
/// funziona solo con alcuni formati della frontale; la versione digitale funziona con ogni obiettivo, con
/// tutte le risoluzioni e dà lo stesso risultato su ogni iPhone. L'anteprima del telefono la mostra (B2:
/// con un effetto acceso l'anteprima è il video elaborato, come lo riceve il computer).
///
/// Posizione nella pipeline: dopo gli effetti che usano la maschera della persona o i volti nelle coordinate
/// del fotogramma intero (sfondo, pelle), prima della scritta (che non va ritagliata).
final class InquadraturaAutomatica: Effetto, @unchecked Sendable {
    let nome = "Inquadratura automatica"
    static let zoomMassimo: CGFloat = 1.6

    /// Centro del riquadro (normalizzato, origine in basso a sinistra come Core Image) e zoom.
    private struct Riquadro {
        var x: CGFloat = 0.5
        var y: CGFloat = 0.5
        var zoom: CGFloat = 1
    }

    private let blocco = NSLock()
    // Protetti da `blocco`.
    private var accesoInterno = false
    private var inRitorno = false

    // Solo sulla coda di cattura.
    private var attuale = Riquadro()
    private var velocita = Riquadro(x: 0, y: 0, zoom: 0)
    private var bersaglio = Riquadro()
    private var ultimoIstante: CMTime = .invalid
    private var ultimoVolto: TimeInterval = 0
    private var ultimaAnalisiUsata: TimeInterval = 0

    /// Dall'interfaccia o dal computer.
    var acceso: Bool {
        get { blocco.withLock { accesoInterno } }
        set {
            blocco.withLock {
                // Spenta mentre è zoomata: resta attiva finché non è tornata all'inquadratura intera.
                if accesoInterno && !newValue { inRitorno = true }
                if newValue { inRitorno = false }
                accesoInterno = newValue
            }
        }
    }

    var attivo: Bool {
        blocco.withLock { accesoInterno || inRitorno }
    }

    var analisiNecessarie: Set<TipoAnalisi> { [.volti] }

    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage {
        let estensione = immagine.extent
        guard !estensione.isInfinite, !estensione.isEmpty else { return immagine }
        let acceso = self.acceso
        let adesso = ProcessInfo.processInfo.systemUptime

        // Tempo dal fotogramma precedente: la molla va alla stessa velocità a 24, 30 e 60 fps.
        var dt: CGFloat = 1.0 / 30
        if ultimoIstante.isValid, contesto.istante.isValid {
            let differenza = CMTimeSubtract(contesto.istante, ultimoIstante).seconds
            if differenza.isFinite, differenza > 0 { dt = CGFloat(min(differenza, 0.1)) }
        }
        ultimoIstante = contesto.istante

        // Un risultato nuovo dell'analisi, non più vecchio di un secondo.
        if acceso, let volti = contesto.volti, adesso - volti.quando < 1, volti.quando != ultimaAnalisiUsata {
            ultimaAnalisiUsata = volti.quando
            if !volti.rettangoli.isEmpty {
                ultimoVolto = adesso
                let nuovo = Self.riquadro(per: volti.rettangoli)
                let soglia = 0.06 / bersaglio.zoom
                if abs(nuovo.x - bersaglio.x) > soglia || abs(nuovo.y - bersaglio.y) > soglia
                    || abs(nuovo.zoom - bersaglio.zoom) / bersaglio.zoom > 0.08 {
                    bersaglio = nuovo
                }
            }
        }
        let senzaVolti = !acceso || adesso - ultimoVolto > 2
        if senzaVolti { bersaglio = Riquadro() }

        // Molla smorzata in modo critico: più lenta quando si torna all'inquadratura intera.
        let omega: CGFloat = senzaVolti ? 1.3 : 2.8
        Self.molla(&attuale.x, &velocita.x, verso: bersaglio.x, omega: omega, dt: dt)
        Self.molla(&attuale.y, &velocita.y, verso: bersaglio.y, omega: omega, dt: dt)
        Self.molla(&attuale.zoom, &velocita.zoom, verso: bersaglio.zoom, omega: omega, dt: dt)
        attuale.zoom = min(max(attuale.zoom, 1), Self.zoomMassimo)
        let meta = 0.5 / attuale.zoom
        attuale.x = min(max(attuale.x, meta), 1 - meta)
        attuale.y = min(max(attuale.y, meta), 1 - meta)

        // Arrivata all'inquadratura intera: niente da fare. Se era spenta, ora si spegne del tutto.
        let ferma = abs(velocita.x) < 0.0005 && abs(velocita.y) < 0.0005 && abs(velocita.zoom) < 0.0005
        if attuale.zoom < 1.002 {
            if !acceso && ferma {
                blocco.withLock { if !accesoInterno { inRitorno = false } }
                attuale = Riquadro()
                velocita = Riquadro(x: 0, y: 0, zoom: 0)
                ultimoIstante = .invalid
            }
            return immagine
        }

        let larghezza = estensione.width / attuale.zoom
        let altezza = estensione.height / attuale.zoom
        let ritaglio = CGRect(x: estensione.minX + attuale.x * estensione.width - larghezza / 2,
                              y: estensione.minY + attuale.y * estensione.height - altezza / 2,
                              width: larghezza, height: altezza)
        let trasformazione = CGAffineTransform(translationX: -ritaglio.minX, y: -ritaglio.minY)
            .concatenating(CGAffineTransform(scaleX: attuale.zoom, y: attuale.zoom))
            .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
        // `clampedToExtent`: ai bordi del ritaglio la scalatura non pesca pixel trasparenti.
        return immagine.clampedToExtent().cropped(to: ritaglio).transformed(by: trasformazione)
    }

    /// Il riquadro che contiene tutti i volti con aria attorno.
    private static func riquadro(per volti: [CGRect]) -> Riquadro {
        var unione = volti[0]
        for volto in volti.dropFirst() { unione = unione.union(volto) }
        // Il riquadro (1/zoom del fotogramma, in entrambe le direzioni) deve contenere il volto alto circa un terzo
        // e largo meno di metà: con più persone vince la larghezza.
        let necessario = max(unione.height * 3.2, unione.width * 2.2, 1 / zoomMassimo)
        let zoom = min(max(1 / necessario, 1), zoomMassimo)
        // Il volto un po' sopra il centro (origine in basso: il centro del riquadro scende).
        return Riquadro(x: unione.midX, y: unione.midY - 0.12 / zoom, zoom: zoom)
    }

    private static func molla(_ valore: inout CGFloat, _ velocita: inout CGFloat, verso: CGFloat,
                              omega: CGFloat, dt: CGFloat) {
        let accelerazione = omega * omega * (verso - valore) - 2 * omega * velocita
        velocita += accelerazione * dt
        valore += velocita * dt
    }
}
