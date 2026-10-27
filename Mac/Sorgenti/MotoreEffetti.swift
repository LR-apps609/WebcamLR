import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import ImageIO
import Metal
import Vision
import WebcamLRProtocollo

// Il motore effetti del Mac (27 ottobre, «effetti sul computer, come iVCam»): sfocatura e sfondi, calore, filtri e
// regolazioni, ritocco della pelle, luce sul volto, inquadratura automatica, specchio, scritta e logo. Il telefono
// manda il video com'è (solo fotocamera e codifica); il Mac lo elabora UNA volta, dopo la decodifica, e la stessa
// immagine elaborata va a tutte le uscite: anteprima della finestra, finestra mini, webcam virtuale, foto e
// registrazione (Schermo.swift, `pubblica`).
//
// Percorso di un fotogramma (uno `MotoreEffetti` per `Schermo`, acceso solo per il telefono nella webcam):
//   coda dello Schermo: decodifica → `elabora` (non aspetta mai)
//   coda di analisi:    Vision sulla persona (`VNGeneratePersonSegmentationRequest`) sul fotogramma più recente; i
//                       volti (`VNDetectFaceRectanglesRequest`) con una chiamata separata, 10 volte al secondo
//   coda di resa:       un solo grafo Core Image su Metal con la maschera → buffer nuovo (stesso formato YCbCr e
//                       stessi allegati di colore del decodificatore, IOSurface) → `consegna`
// Vision e la resa vanno in parallelo (prova di Ledion, 27 ottobre: con Vision in fila davanti alla resa il motore
// scartava 4 fotogrammi al secondo quando il video arrivava a gruppi, e il video scattava). Ogni fotogramma va alla
// resa appena entra, nell'ordine di arrivo, e non si scarta mai per la maschera:
// - se Vision è libera, analizza QUESTO fotogramma e la resa aspetta la sua maschera al massimo un fotogramma
//   (`CasellaMaschera`): di solito arriva in tempo (Vision 22-27 ms contro 33) ed è la maschera dello stesso istante,
//   senza la persona «in ritardo» sul bordo (lezione della quarta prova sull'iPhone);
// - se Vision è occupata (o non finisce in tempo), il fotogramma si rende con l'ultima maschera filtrata, se non ha
//   più di 0,3 s (`maschereVecchieValide`), e Vision passa al fotogramma più recente appena è libera.
// Si scarta solo se la resa stessa resta indietro di più di `resaMassimeInCoda` fotogrammi: allora il Mac davvero
// non tiene il ritmo, e la qualità scende (`regolaQualita`).
// Senza effetti accesi `elabora` risponde falso e l'immagine decodificata va alle uscite com'è (costo zero).

/// Le scelte che il motore applica, già con le regole di WebcamLR Pro (le decide il `Ricevitore`).
struct ImpostazioniMotore: Equatable, Sendable {
    var filtro = Filtri.naturale
    var luminosita = 0.0
    var contrasto = 0.0
    var saturazione = 0.0
    var nitidezza = 0.0
    /// Uno dei `ModiSfondo`.
    var sfondo = ModiSfondo.nessuno
    /// Sfocato: quanto sfocare (Poco 0,25, Medio 0,55, Tanto 1). Sostituito: quanto è netto il bordo.
    var intensitaSfondo = 0.5
    /// Con lo sfondo sostituito: uno degli `SfondiPronti` o `SfondiPronti.personale`.
    var immagineSfondo: String?
    var pelle = 0.0
    var luceVolto = false
    var inquadratura = false
    var calore = 0.0
    var specchia = false
    /// La scritta (nome vuoto = nessuna) e il logo.
    var nome = ""
    var ruolo = ""
    var logo = false

    var sfondoAcceso: Bool { sfondo == ModiSfondo.sfocato || sfondo == ModiSfondo.sostituito }
    var servonoVolti: Bool { pelle > 0.001 || luceVolto || inquadratura }
    var regolazioniAccese: Bool { luminosita != 0 || contrasto != 0 || saturazione != 0 || nitidezza != 0 }
    var scrittaAccesa: Bool { !nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || logo }

    /// Niente da fare: il video passa com'è.
    var spente: Bool {
        !sfondoAcceso && !servonoVolti && filtro == Filtri.naturale && !regolazioniAccese && calore <= 0.001
            && !specchia && !scrittaAccesa
    }
}

/// Le scelte e le immagini del motore, condivise da tutti gli schermi: le scrive il `Ricevitore` (coda principale),
/// le legge ogni motore sulle sue code.
final class StatoMotoreEffetti: @unchecked Sendable {
    static let condiviso = StatoMotoreEffetti()

    struct Istantanea {
        var impostazioni: ImpostazioniMotore
        /// L'immagine dello sfondo sostituito già letta, con il suo id e una versione (cambia a ogni immagine nuova).
        var sfondo: (id: String, immagine: CGImage, versione: Int)?
        var logo: (immagine: CGImage, versione: Int)?
        /// Diagnosi nascosta (⌥ clic su «Sfondo»): il video mostra la maschera rifinita in bianco e nero.
        var mascheraVisibile: Bool
    }

    private let blocco = NSLock()
    private var impostazioniInterne = ImpostazioniMotore()
    private var sfondo: (id: String, immagine: CGImage, versione: Int)?
    private var logo: (immagine: CGImage, versione: Int)?
    private var versione = 0
    private var mascheraVisibileInterna = false

    /// Diagnosi nascosta: con lo sfondo acceso, al posto del video la maschera rifinita (bianco = persona).
    var mascheraVisibile: Bool {
        get { blocco.withLock { mascheraVisibileInterna } }
        set { blocco.withLock { mascheraVisibileInterna = newValue } }
    }

    var impostazioni: ImpostazioniMotore {
        blocco.lock()
        defer { blocco.unlock() }
        return impostazioniInterne
    }

    func imposta(_ nuove: ImpostazioniMotore) {
        blocco.lock()
        impostazioniInterne = nuove
        blocco.unlock()
    }

    /// L'immagine di uno sfondo (già ridotta e dritta); nil per toglierla.
    func impostaSfondo(id: String, immagine: CGImage?) {
        blocco.lock()
        versione += 1
        sfondo = immagine.map { (id: id, immagine: $0, versione: versione) }
        blocco.unlock()
    }

    func impostaLogo(_ immagine: CGImage?) {
        blocco.lock()
        versione += 1
        logo = immagine.map { (immagine: $0, versione: versione) }
        blocco.unlock()
    }

    func istantanea() -> Istantanea {
        blocco.lock()
        defer { blocco.unlock() }
        return Istantanea(impostazioni: impostazioniInterne, sfondo: sfondo, logo: logo,
                          mascheraVisibile: mascheraVisibileInterna)
    }
}

/// Il motore di uno `Schermo`. Tutte le funzioni pubbliche si possono chiamare da qualsiasi coda.
final class MotoreEffetti: @unchecked Sendable {
    /// L'interruttore interno: vero = gli effetti di immagine li fa il Mac (questo motore) e non il telefono.
    /// Falso = come prima del 27 ottobre (comandi al telefono, motore spento).
    static let effettiSulComputer = true

    /// La qualità, che scende da sola solo se il Mac non regge i fotogrammi al secondo (e non risale finché il video
    /// non cambia misura o il telefono non cambia). Si parte da `iniziale`.
    /// - `.accurato`: maschera `.accurate`, bordo rifinito. Oggi non si usa: nella prova di Ledion restava indietro di
    ///   secondi (la stanza nitida senza nessuno). Se un giorno si riprova e non regge il ritmo, si passa a `.pieno`.
    /// - `.pieno`: maschera `.balanced` a ogni fotogramma, bordo rifinito guidato dal colore (`CIEdgePreserveUpsampleFilter`).
    ///   Apple (WWDC21, «Detect people, faces, and poses using Vision») indica `.accurate` per le foto e `.balanced` per
    ///   il video; la maschera `.accurate` ha 64 volte i pixel di quella `.fast` e una misura pubblica dà circa 60 ms per
    ///   immagine su un iPhone 13 (forum sviluppatori Apple, 714775). È il livello di partenza.
    /// - `.bordoLeggero`: maschera `.balanced`, bordo con ingrandimento bilineare (costa molto meno sulla scheda video).
    /// - `.veloce`: maschera `.fast` e bordo bilineare, per i Mac Intel lenti.
    enum Livello: Int, Comparable, Sendable {
        case accurato
        case pieno
        case bordoLeggero
        case veloce

        static func < (a: Livello, b: Livello) -> Bool { a.rawValue < b.rawValue }

        /// Il livello di partenza: `.pieno` (`.balanced`, quella che Apple indica per il video). `.accurate` è pensata
        /// per le foto: nella prova di Ledion la maschera restava indietro di secondi (stanza nitida senza nessuno).
        static let iniziale: Livello = .pieno

        /// Per il registro.
        var descrizione: String {
            switch self {
            case .accurato: String(localized: "maschera .accurate, bordo rifinito")
            case .pieno: String(localized: "maschera .balanced, bordo rifinito")
            case .bordoLeggero: String(localized: "maschera .balanced, bordo bilineare")
            case .veloce: String(localized: "maschera .fast, bordo bilineare")
            }
        }

        var qualitaVision: VNGeneratePersonSegmentationRequest.QualityLevel {
            switch self {
            case .accurato: .accurate
            case .pieno, .bordoLeggero: .balanced
            case .veloce: .fast
            }
        }

        /// Con il bordo bilineare (più leggero sulla scheda video) invece di quello rifinito.
        var conBordoBilineare: Bool { self >= .bordoLeggero }
    }

    /// I numeri dell'ultimo secondo, per le «Tappe» e il registro.
    struct Misure: Sendable {
        /// Dall'ingresso nel motore all'uscita (mediana di un secondo); nil se il motore non lavora.
        var effettiMs: Int?
        /// Media dell'ultimo secondo: una maschera di Vision, una resa.
        var visionMs: Double?
        var resaMs: Double?
        var livello: Livello
        /// Fotogrammi scartati dal motore (solo se la resa resta indietro) e maschere di Vision fallite, dall'inizio.
        var scartati: Int
        var erroriVision: Int
        /// Fotogrammi resi con la maschera di un fotogramma precedente (Vision occupata o in ritardo), dall'inizio.
        var maschereRiusate: Int
    }

    /// Un avviso per il registro (lo scrive il `Ricevitore` con i suoi testi).
    enum Nota: Sendable {
        /// La qualità è scesa: tempi medi in ms, il tempo di un fotogramma e i fotogrammi persi dalla resa nella finestra.
        case livello(Livello, visionMs: Int, resaMs: Int, fotogrammaMs: Int, persi: Int)
        case erroreVision(String, totale: Int)
        /// Nessun buffer libero nel pool di uscita: il fotogramma non è stato elaborato.
        case poolEsaurito(totale: Int)
        /// La misura della maschera di Vision e del fotogramma, una volta (e di nuovo se cambiano), con il livello.
        case maschera(larghezza: Int, altezza: Int, fotogrammaLarghezza: Int, fotogrammaAltezza: Int, livello: Livello)
    }

    private struct Lavoro {
        let immagine: CVPixelBuffer
        /// `Orologio.adesso()` all'ingresso (µs).
        let arrivo: UInt64
        let consegna: (CVPixelBuffer) -> Void
        /// Dove arriva la maschera di Vision di questo fotogramma; nil se Vision era occupata con un altro.
        var casella: CasellaMaschera?
        /// La maschera di questo fotogramma, se è arrivata in tempo (la mette la resa).
        var maschera: CVPixelBuffer?
    }

    // MARK: Contesti (uno per tutta l'app, su Metal)

    /// Lo spazio dei colori quando gli allegati del decodificatore non bastano a dirlo.
    private static let spazio709 = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    private static let nero = CIImage(color: CIColor(red: 0, green: 0, blue: 0))

    /// Con la gestione del colore: lavoro in lineare (sRGB esteso, mezza precisione), come sull'iPhone.
    private static let contesto: CIContext = {
        var opzioni: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let lineare = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) { opzioni[.workingColorSpace] = lineare }
        if let dispositivo = MTLCreateSystemDefaultDevice(), let codaComandi = dispositivo.makeCommandQueue() {
            return CIContext(mtlCommandQueue: codaComandi, options: opzioni)
        }
        return CIContext(options: opzioni)
    }()

    /// Per le maschere: valori come sono, senza gestione del colore.
    private static let contestoMaschere: CIContext = {
        let opzioni: [CIContextOption: Any] = [.cacheIntermediates: false, .workingColorSpace: NSNull(),
                                               .outputColorSpace: NSNull()]
        if let dispositivo = MTLCreateSystemDefaultDevice(), let codaComandi = dispositivo.makeCommandQueue() {
            return CIContext(mtlCommandQueue: codaComandi, options: opzioni)
        }
        return CIContext(options: opzioni)
    }()

    // MARK: Stato

    private let codaAnalisi = DispatchQueue(label: "it.lrapps.webcamlr.effetti.analisi", qos: .userInteractive)
    private let codaResa = DispatchQueue(label: "it.lrapps.webcamlr.effetti.resa", qos: .userInteractive)

    /// Protegge tutto ciò che è segnato «sotto `blocco`».
    private let blocco = NSLock()
    // Sotto `blocco`.
    private var abilitato = false
    private var analisiOccupata = false
    /// Il fotogramma più recente arrivato mentre Vision era occupata (già mandato alla resa): Vision lo analizza appena
    /// è libera, e la sua maschera serve ai fotogrammi dopo.
    private var daAnalizzare: (immagine: CVPixelBuffer, arrivo: UInt64)?
    /// Una maschera arrivata senza un fotogramma che la aspetti (fotogramma già reso, o analisi del più recente): la
    /// prossima resa la mette nel filtro nel tempo.
    private var mascheraSciolta: (maschera: CVPixelBuffer, arrivo: UInt64)?
    /// Fotogrammi entrati e non ancora consegnati (o scartati): finché ce n'è uno, passano tutti dal motore, così
    /// l'ordine non cambia.
    private var inVolo = 0
    private var inResa = 0
    /// Luce sul volto o inquadratura spente ma ancora in dissolvenza: il motore lavora finché non sono a riposo.
    private var inRitorno = false
    private var livello = Livello.iniziale
    /// I volti dell'ultima analisi (normalizzati, origine in basso a sinistra come Vision e Core Image) e quando.
    private var volti: (rettangoli: [CGRect], quando: UInt64)?
    private var ultimiVoltiChiesti: UInt64 = 0
    /// Gli ultimi 30 intervalli tra due fotogrammi (µs): il tempo di un fotogramma è la loro media. Non il più breve: il
    /// video arriva dalla rete a gruppi (Wi-Fi, USB), due fotogrammi a pochi ms l'uno dall'altro sono normali, e con il
    /// minimo il «tempo di un fotogramma» diventava di 2-5 ms: la qualità scendeva a `.veloce` in pochi secondi su
    /// qualsiasi Mac (maschera `.fast` e bordo bilineare, prova vera di Ledion). La media non sente i gruppi.
    private var intervalli: [UInt64] = []
    private var ultimoArrivo: UInt64 = 0
    private var scartati = 0
    private var maschereRiusate = 0
    /// Per `regolaQualita`, dall'inizio della finestra: tempi di Vision e fotogrammi scartati dalla resa.
    private var finestraVision = 0.0
    private var finestraContaVision = 0
    private var finestraPersi = 0
    private var erroriVision = 0
    private var ultimaNotaErrore: UInt64 = 0
    private var poolEsauriti = 0
    private var ultimaNotaPool: UInt64 = 0
    private var note: [Nota] = []
    private var sommaVision = 0.0
    private var contaVision = 0
    private var sommaResa = 0.0
    private var contaResa = 0
    private let ritardo = MisuraRitardo()

    // Solo sulla coda di analisi.
    private var richiestaPersona: VNGeneratePersonSegmentationRequest?
    private var sequenza: VNSequenceRequestHandler?
    private var livelloRichiesta: Livello?
    private let richiestaVolti = VNDetectFaceRectanglesRequest()

    // Solo sulla coda di resa.
    private var pool: CVPixelBufferPool?
    private var formatoPool: (formato: OSType, larghezza: Int, altezza: Int)?
    private var mascheraFiltrata: CVPixelBuffer?
    private var mascheraRiserva: CVPixelBuffer?
    /// Quando è arrivata l'ultima maschera nuova di Vision (0 = mai): una maschera vecchia vale al massimo
    /// `maschereVecchieValide`, poi si sfoca tutto il fotogramma.
    private var arrivoMascheraNuova: UInt64 = 0
    /// Solo le persone vere nella maschera (un peluche preso per persona va con lo sfondo): ZonaPersona.swift.
    private let zonaPersona = ZonaPersona()
    /// L'ultimo fotogramma consegnato con lo sfondo già applicato: si ripete se un fotogramma non si può fare con lo
    /// sfondo (maschera mancante, resa fallita, pool esaurito). Mai l'originale con lo sfondo vero.
    private var ultimaConSfondo: CVPixelBuffer?
    private var sfondoPronto: (chiave: String, immagine: CIImage)?
    private var scrittaPronta: (chiave: String, scritta: CIImage?, logo: CIImage?)?
    private var inquadratura = MollaInquadratura()
    private var voltoLuce: CGRect?
    private var presenzaLuce: CGFloat = 0
    private var ultimoArrivoResa: UInt64 = 0
    private var misuraVideo: (larghezza: Int, altezza: Int)?
    /// Le misure di maschera e fotogramma già scritte nel registro (`Nota.maschera`).
    private var misureMascheraNotate: String?
    /// La finestra per decidere se scendere di qualità: somma dei tempi di resa, e quanti fotogrammi resi.
    private var finestraResa = 0.0
    private var finestraConta = 0
    /// La prima finestra dopo una partenza non conta: Vision carica il modello e i primi fotogrammi costano il doppio.
    private var finestraDiRiscaldamento = true
    /// Finestre difficili di fila: si scende solo dopo `finestreDifficiliPerScendere`, mai per un momento storto
    /// (un'altra app che usa la scheda video per un attimo).
    private var finestreDifficili = 0

    /// Quanti fotogrammi resi in una finestra (circa 5 secondi a 30 fps). Prima erano 2 secondi: troppo pochi, un
    /// gruppo di fotogrammi arrivati insieme bastava a far scendere la qualità.
    private static let fotogrammiPerDecidere = 150
    private static let finestreDifficiliPerScendere = 2
    /// La resa è troppo lenta se in media supera questa parte del tempo di un fotogramma.
    private static let quotaFotogramma = 0.85
    /// Vision è troppo lenta se in media supera questo multiplo del tempo di un fotogramma. Va in parallelo alla resa:
    /// fino a un fotogramma e mezzo la maschera si rinnova comunque quasi a ogni fotogramma (e intanto vale l'ultima);
    /// oltre, la persona resterebbe indietro sul bordo. Prima si scendeva a `.fast` già con Vision a 26 ms su 33.
    private static let quotaVision = 1.5
    /// Si scende se la resa perde più di questa parte dei fotogrammi della finestra (1 su 50).
    private static let quotaPersi = 0.02
    /// Quanti fotogrammi possono aspettare la resa. Il video dalla rete arriva anche a gruppi di 3-4 dopo una pausa:
    /// con 2 (prima) il terzo del gruppo si scartava anche su un Mac scarico.
    private static let resaMassimeInCoda = 4
    /// Quanto la resa aspetta al massimo la maschera del suo fotogramma (µs): un fotogramma (la media degli
    /// intervalli), tra 20 e 42 ms. Oltre si rende con l'ultima maschera: il video non si ferma ad aspettare Vision.
    private static let attesaMinima: UInt64 = 20_000
    private static let attesaMassima: UInt64 = 42_000
    /// Peso della maschera nuova nel filtro nel tempo: 0,6 + 4 × |nuova − vecchia|, al massimo 1.
    private static let pesoMinimo: CGFloat = 0.6
    private static let guadagnoDifferenza: CGFloat = 4
    /// Per quanto si riusa l'ultima maschera se Vision non ne dà una nuova (µs): poi la persona di prima non tiene
    /// più nitido quello che c'è ora.
    private static let maschereVecchieValide: UInt64 = 300_000

    // MARK: Interfaccia

    /// Dal `Ricevitore`: il motore lavora solo per il telefono nella webcam (l'altro si vede com'è nella miniatura).
    func abilita(_ acceso: Bool) {
        blocco.lock()
        let cambiato = abilitato != acceso
        abilitato = acceso
        blocco.unlock()
        if cambiato, !acceso { azzera() }
    }

    /// Lo `Schermo` si svuota (telefono andato, sessione nuova): la qualità e lo stato nel tempo ripartono da capo.
    func azzera() {
        blocco.lock()
        livello = .iniziale
        volti = nil
        intervalli = []
        ultimoArrivo = 0
        daAnalizzare = nil
        mascheraSciolta = nil
        finestraVision = 0
        finestraContaVision = 0
        finestraPersi = 0
        blocco.unlock()
        codaResa.async {
            self.mascheraFiltrata = nil
            self.mascheraRiserva = nil
            self.arrivoMascheraNuova = 0
            self.ultimaConSfondo = nil
            self.inquadratura = MollaInquadratura()
            self.voltoLuce = nil
            self.presenzaLuce = 0
            self.ultimoArrivoResa = 0
            self.misuraVideo = nil
            self.misureMascheraNotate = nil
            self.finestraResa = 0
            self.finestraConta = 0
            self.finestraDiRiscaldamento = true
            self.finestreDifficili = 0
        }
    }

    /// Sulla coda dello `Schermo`, per ogni immagine decodificata. Falso: nessun effetto, l'immagine va alle uscite
    /// com'è. Vero: il motore la elabora e chiama `consegna` (dalla sua coda di resa) con l'immagine nuova; un
    /// fotogramma scartato (Mac in affanno) non viene consegnato.
    func elabora(_ immagine: CVPixelBuffer, consegna: @escaping (CVPixelBuffer) -> Void) -> Bool {
        let impostazioni = StatoMotoreEffetti.condiviso.impostazioni
        let arrivo = Orologio.adesso()
        blocco.lock()
        defer { blocco.unlock() }
        guard abilitato, !impostazioni.spente || inRitorno || inVolo > 0 else { return false }
        if ultimoArrivo != 0, arrivo > ultimoArrivo {
            intervalli.append(arrivo - ultimoArrivo)
            if intervalli.count > 30 { intervalli.removeFirst(intervalli.count - 30) }
        }
        ultimoArrivo = arrivo
        let lavoro = Lavoro(immagine: immagine, arrivo: arrivo, consegna: consegna)

        if impostazioni.sfondoAcceso {
            // Alla resa subito, nell'ordine di arrivo. Vision libera: analizza questo fotogramma e la resa ne aspetta
            // la maschera al massimo un fotogramma. Vision occupata: il fotogramma usa l'ultima maschera e Vision
            // prende il più recente appena finisce (quello che aspettava prima è già alla resa: nessuno si scarta).
            var conMaschera = lavoro
            if analisiOccupata {
                daAnalizzare = (immagine, arrivo)
            } else {
                analisiOccupata = true
                let casella = CasellaMaschera(scadenza: arrivo + attesaMaschera())
                conMaschera.casella = casella
                codaAnalisi.async { self.analizza(immagine, arrivo: arrivo, casella: casella) }
            }
            inVolo += 1
            mandaAllaResa(conMaschera)
            return true
        }
        // Senza sfondo: i volti (se servono) in sottofondo, al massimo 10 al secondo; la resa subito con gli ultimi.
        if impostazioni.servonoVolti, !analisiOccupata, arrivo &- ultimiVoltiChiesti >= 100_000 {
            analisiOccupata = true
            ultimiVoltiChiesti = arrivo
            codaAnalisi.async { self.analizzaSoloVolti(immagine) }
        }
        inVolo += 1
        mandaAllaResa(lavoro)
        return true
    }

    /// Gli ultimi numeri; azzera le medie del secondo. Dalla coda principale, una volta al secondo.
    func misure() -> Misure {
        let adesso = Orologio.adesso()
        blocco.lock()
        defer { blocco.unlock() }
        let risultato = Misure(effettiMs: ritardo.valore(adesso: adesso),
                               visionMs: contaVision > 0 ? sommaVision / Double(contaVision) : nil,
                               resaMs: contaResa > 0 ? sommaResa / Double(contaResa) : nil,
                               livello: livello, scartati: scartati, erroriVision: erroriVision,
                               maschereRiusate: maschereRiusate)
        sommaVision = 0
        contaVision = 0
        sommaResa = 0
        contaResa = 0
        return risultato
    }

    /// Gli avvisi nati dall'ultima chiamata (cambi di qualità, errori di Vision).
    func prendiNote() -> [Nota] {
        blocco.lock()
        defer { blocco.unlock() }
        let prese = note
        note = []
        return prese
    }

    // MARK: Analisi (coda di analisi)

    /// Sotto `blocco`: alla resa, se non ce ne sono già `resaMassimeInCoda` in coda. Altrimenti si scarta: la resa non
    /// tiene il ritmo (lo conta `regolaQualita`), e così il ritardo non cresce.
    private func mandaAllaResa(_ lavoro: Lavoro) {
        guard inResa < Self.resaMassimeInCoda else {
            inVolo -= 1
            scartati += 1
            finestraPersi += 1
            // La sua maschera, se Vision la sta facendo, serve ai prossimi.
            lavoro.casella?.abbandona()
            return
        }
        inResa += 1
        codaResa.async { self.rendi(lavoro) }
    }

    /// Sotto `blocco`: quanto la resa aspetta la maschera di un fotogramma (µs), cioè un fotogramma.
    private func attesaMaschera() -> UInt64 {
        guard !intervalli.isEmpty else { return Self.attesaMassima }
        let media = intervalli.reduce(0, +) / UInt64(intervalli.count)
        return min(max(media, Self.attesaMinima), Self.attesaMassima)
    }

    /// La richiesta della persona per il livello attuale: si rifà (con una sequenza nuova) solo quando il livello
    /// cambia, mai a metà sequenza.
    private func richiestaPerLivello() -> (VNGeneratePersonSegmentationRequest, VNSequenceRequestHandler) {
        let voluto = blocco.withLock { livello }
        if let richiestaPersona, let sequenza, livelloRichiesta == voluto { return (richiestaPersona, sequenza) }
        let richiesta = VNGeneratePersonSegmentationRequest()
        richiesta.qualityLevel = voluto.qualitaVision
        richiesta.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let nuova = VNSequenceRequestHandler()
        richiestaPersona = richiesta
        sequenza = nuova
        livelloRichiesta = voluto
        return (richiesta, nuova)
    }

    /// La maschera della persona per `immagine`. `casella`: la resa di questo fotogramma la aspetta; nil se il
    /// fotogramma è già alla resa (analisi del più recente) e la maschera serve solo ai prossimi.
    private func analizza(_ immagine: CVPixelBuffer, arrivo: UInt64, casella: CasellaMaschera?) {
        let inizio = Orologio.adesso()
        let (richiesta, sequenza) = richiestaPerLivello()
        var maschera: CVPixelBuffer?
        do {
            try sequenza.perform([richiesta], on: immagine, orientation: .up)
            maschera = richiesta.results?.first?.pixelBuffer
        } catch {
            contaErrore(error)
        }
        let visionMs = Double(Orologio.adesso() &- inizio) / 1000
        // Prima la maschera alla resa che la aspetta, poi i volti: la resa non aspetta anche quelli.
        let presa = casella?.consegna(maschera) ?? false
        let impostazioni = StatoMotoreEffetti.condiviso.impostazioni
        let voltiDovuti = blocco.withLock { () -> Bool in
            guard impostazioni.servonoVolti, arrivo &- ultimiVoltiChiesti >= 100_000 else { return false }
            ultimiVoltiChiesti = arrivo
            return true
        }
        if voltiDovuti { cercaVolti(immagine) }
        blocco.lock()
        sommaVision += visionMs
        contaVision += 1
        finestraVision += visionMs
        finestraContaVision += 1
        // Nessuno l'ha presa (fotogramma già reso o scartato): la usa la prossima resa, se è la più recente.
        if !presa, let maschera, arrivo > (mascheraSciolta?.arrivo ?? 0) {
            mascheraSciolta = (maschera, arrivo)
        }
        liberaAnalisi()
        blocco.unlock()
    }

    private func analizzaSoloVolti(_ immagine: CVPixelBuffer) {
        cercaVolti(immagine)
        blocco.lock()
        liberaAnalisi()
        blocco.unlock()
    }

    /// Sotto `blocco`: il fotogramma più recente arrivato intanto (già alla resa), o l'analisi libera.
    private func liberaAnalisi() {
        if let prossimo = daAnalizzare {
            daAnalizzare = nil
            codaAnalisi.async { self.analizza(prossimo.immagine, arrivo: prossimo.arrivo, casella: nil) }
        } else {
            analisiOccupata = false
        }
    }

    /// I volti, con una chiamata separata da quella della persona: l'errore di una non fa perdere l'altra.
    private func cercaVolti(_ immagine: CVPixelBuffer) {
        let gestore = VNImageRequestHandler(cvPixelBuffer: immagine, orientation: .up, options: [:])
        do {
            try gestore.perform([richiestaVolti])
            let trovati = (richiestaVolti.results ?? []).map(\.boundingBox)
            let adesso = Orologio.adesso()
            blocco.withLock { volti = (rettangoli: trovati, quando: adesso) }
        } catch {
            contaErrore(error)
        }
    }

    /// Ogni pool esaurito si conta; nel registro il primo subito, poi al massimo uno ogni 10 secondi.
    private func contaPoolEsaurito() {
        let adesso = Orologio.adesso()
        blocco.withLock {
            poolEsauriti += 1
            if ultimaNotaPool == 0 || adesso &- ultimaNotaPool >= 10_000_000 {
                ultimaNotaPool = adesso
                note.append(.poolEsaurito(totale: poolEsauriti))
            }
        }
    }

    /// Ogni errore di Vision si conta; nel registro il primo subito, poi al massimo uno ogni 10 secondi.
    private func contaErrore(_ errore: Error) {
        let adesso = Orologio.adesso()
        blocco.withLock {
            erroriVision += 1
            if ultimaNotaErrore == 0 || adesso &- ultimaNotaErrore >= 10_000_000 {
                ultimaNotaErrore = adesso
                note.append(.erroreVision(errore.localizedDescription, totale: erroriVision))
            }
        }
    }

    // MARK: Resa (coda di resa)

    private func rendi(_ daRendere: Lavoro) {
        var lavoro = daRendere
        let ingresso = lavoro.immagine
        let istantanea = StatoMotoreEffetti.condiviso.istantanea()
        let impostazioni = istantanea.impostazioni
        // La maschera di questo fotogramma, se Vision la sta facendo: al massimo fino alla scadenza della casella (un
        // fotogramma dall'arrivo), poi si va avanti con l'ultima. L'attesa non conta nel tempo di resa.
        if impostazioni.sfondoAcceso {
            lavoro.maschera = lavoro.casella?.attendi()
        } else {
            lavoro.casella?.abbandona()
        }
        let inizio = Orologio.adesso()
        // nil = non si consegna (con lo sfondo acceso e nessuna immagine con lo sfondo da ripetere).
        var consegnata: CVPixelBuffer? = ingresso
        defer {
            if let consegnata { lavoro.consegna(consegnata) }
            let fine = Orologio.adesso()
            blocco.withLock {
                inVolo -= 1
                inResa -= 1
            }
            ritardo.aggiungi(Int((fine &- lavoro.arrivo) / 1000), adesso: fine)
        }
        let larghezza = CVPixelBufferGetWidth(ingresso)
        let altezza = CVPixelBufferGetHeight(ingresso)
        if let misura = misuraVideo, misura.larghezza != larghezza || misura.altezza != altezza {
            // Altro obiettivo, telefono girato, altra risoluzione: si riparte da capo, qualità compresa.
            mascheraFiltrata = nil
            mascheraRiserva = nil
            arrivoMascheraNuova = 0
            ultimaConSfondo = nil
            inquadratura = MollaInquadratura()
            voltoLuce = nil
            presenzaLuce = 0
            finestraResa = 0
            finestraConta = 0
            finestraDiRiscaldamento = true
            finestreDifficili = 0
            blocco.withLock {
                livello = .iniziale
                volti = nil
                mascheraSciolta = nil
            }
        }
        misuraVideo = (larghezza, altezza)
        // Le maschere nuove nel filtro nel tempo, prima di tutto il resto (anche se poi la resa non riesce, il filtro
        // resta aggiornato): quella arrivata senza fotogramma (più vecchia), poi quella di questo fotogramma.
        var nuova: CVPixelBuffer?
        if impostazioni.sfondoAcceso {
            let sciolta = blocco.withLock { () -> (maschera: CVPixelBuffer, arrivo: UInt64)? in
                defer { mascheraSciolta = nil }
                return mascheraSciolta
            }
            if let sciolta, sciolta.arrivo > arrivoMascheraNuova,
               Self.trascorso(da: sciolta.arrivo, a: lavoro.arrivo) < Self.maschereVecchieValide,
               filtraNelTempo(sciolta.maschera) != nil {
                arrivoMascheraNuova = sciolta.arrivo
            }
            nuova = lavoro.maschera.flatMap { filtraNelTempo($0) }
            if nuova != nil {
                arrivoMascheraNuova = max(arrivoMascheraNuova, lavoro.arrivo)
            } else {
                blocco.withLock { maschereRiusate += 1 }
            }
        }
        // Privacy: con lo sfondo acceso, se il fotogramma non si può fare con lo sfondo, si ripete l'ultimo fatto con
        // lo sfondo (o non si consegna nulla): mai l'originale con lo sfondo vero.
        let ripiego = impostazioni.sfondoAcceso ? ultimaConSfondo : ingresso
        guard let uscita = bufferDiUscita(come: ingresso) else {
            contaPoolEsaurito()
            consegnata = ripiego
            return
        }
        Self.copiaAllegatiColore(da: ingresso, a: uscita)

        let (livelloAttuale, voltiAttuali) = blocco.withLock { (livello, volti) }
        let leggero = livelloAttuale.conBordoBilineare
        if let maschera = lavoro.maschera {
            let mascheraL = CVPixelBufferGetWidth(maschera)
            let mascheraA = CVPixelBufferGetHeight(maschera)
            let misure = "\(mascheraL)x\(mascheraA) \(larghezza)x\(altezza) \(livelloAttuale.rawValue)"
            if misure != misureMascheraNotate {
                misureMascheraNotate = misure
                blocco.withLock {
                    note.append(.maschera(larghezza: mascheraL, altezza: mascheraA, fotogrammaLarghezza: larghezza,
                                          fotogrammaAltezza: altezza, livello: livelloAttuale))
                }
            }
        }
        let dt = passo(lavoro.arrivo)
        // Volti di non più di un secondo fa, normalizzati e in pixel.
        var voltiFreschi: [CGRect]?
        if let trovati = voltiAttuali, lavoro.arrivo &- min(trovati.quando, lavoro.arrivo) < 1_000_000 {
            voltiFreschi = trovati.rettangoli
        }
        let voltiPixel = (voltiFreschi ?? []).map {
            CGRect(x: $0.minX * CGFloat(larghezza), y: $0.minY * CGFloat(altezza),
                   width: $0.width * CGFloat(larghezza), height: $0.height * CGFloat(altezza))
        }

        // Lo stesso spazio di colore per leggere e scrivere (quello degli allegati del decodificatore): un pixel che
        // nessun effetto tocca esce identico (bug 6 dell'iPhone).
        let originale = CIImage(cvPixelBuffer: ingresso)
        let spazio = originale.colorSpace ?? Self.spazio709
        let estensione = originale.extent
        var immagine = originale
        // Con la diagnosi accesa: la maschera rifinita, che alla fine prende il posto dell'immagine.
        var mascheraDaMostrare: CIImage?

        // 1. Calore: prima di tutto, su tutta l'immagine (gratis).
        immagine = RicetteEffetti.calore(immagine, forza: impostazioni.calore)
        // 2. Sfondo, con la maschera di questo fotogramma; se non è arrivata in tempo (Vision occupata o in ritardo,
        // errore), l'ultima maschera filtrata di non più di 0,3 s; senza nessuna maschera, il ripiego.
        if impostazioni.sfondoAcceso {
            let bassa: CIImage
            let recente = Self.trascorso(da: arrivoMascheraNuova, a: lavoro.arrivo) < Self.maschereVecchieValide
            if let filtrata = nuova ?? (recente ? mascheraFiltrata : nil) {
                // Campionamento lineare esplicito: la maschera piccola si ingrandisce di 3-10 volte e, se Core Image la
                // campionasse al pixel più vicino, la soglia dopo ne mostrerebbe gli scalini.
                bassa = CIImage(cvPixelBuffer: filtrata, options: [.colorSpace: NSNull()]).samplingLinear()
            } else if arrivoMascheraNuova != 0 {
                // Maschera troppo vecchia: nessuna persona, tutto sfocato (o tutto sfondo). Mai lo sfondo vero.
                bassa = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
            } else {
                consegnata = ripiego
                return
            }
            // Solo le persone con un volto o un corpo umano (analisi propria, 4 volte al secondo, su un'altra coda).
            let bassaPersona = zonaPersona.applica(a: bassa, fotogramma: ingresso, arrivo: lavoro.arrivo)
            let intensita = CGFloat(min(max(impostazioni.intensitaSfondo, 0), 1))
            let sostituito = impostazioni.sfondo == ModiSfondo.sostituito
            // Soglia centrata a metà e stretta (il bordo morbido lo dà il guided filter): la zona incerta di Vision va
            // con lo sfondo. Con «sostituito» e intensità alta il bordo è più netto (larghezza da 0,45 a 0,2).
            let morbidezza = sostituito ? 0.45 - 0.25 * intensita : 0.3
            let bordo = RicetteEffetti.mascheraRifinita(bassaPersona, immagine: immagine, morbidezza: morbidezza,
                                                        leggero: leggero)
            let fondo = sostituito
                ? immagineSfondo(istantanea, voluta: impostazioni.immagineSfondo, estensione: estensione)
                : RicetteEffetti.sfocataSenzaAlone(immagine, bassa: bassaPersona, intensita: Double(intensita),
                                                   fine: !leggero)
            // Con lo sfondo sostituito: bordo pulito dal vecchio sfondo e light wrap del nuovo.
            let persona = sostituito
                ? RicetteEffetti.personaSuSfondoNuovo(immagine, maschera: bordo, sfondo: fondo, leggero: leggero)
                : immagine
            immagine = RicetteFiltriMac.mescola(sopra: persona, sotto: fondo, maschera: bordo)
            if istantanea.mascheraVisibile {
                // I valori della maschera sono lineari per il contesto: con la curva inversa il grigio a schermo è il
                // valore vero (0,5 = grigio medio, non un grigio chiaro).
                // Metà sinistra: la maschera di Vision com'è (solo ingrandita); metà destra: dopo la rifinitura del bordo.
                // Così si vede se l'errore è di Vision o nostro.
                let grezza = bassa
                    .transformed(by: CGAffineTransform(scaleX: estensione.width / max(bassa.extent.width, 1),
                                                       y: estensione.height / max(bassa.extent.height, 1))
                        .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY)))
                    .clampedToExtent()
                let sinistra = CGRect(x: estensione.minX, y: estensione.minY, width: (estensione.width / 2).rounded(),
                                      height: estensione.height)
                mascheraDaMostrare = RicetteEffetti.grigio(grezza).cropped(to: sinistra)
                    .composited(over: bordo)
                    .applyingFilter("CISRGBToneCurveToLinear")
            }
        } else {
            mascheraFiltrata = nil
            ultimaConSfondo = nil
        }
        // 3. Ritocco della pelle, solo attorno ai volti.
        if impostazioni.pelle > 0.001 {
            immagine = RicetteEffetti.pelle(immagine, forza: impostazioni.pelle, volti: voltiPixel, leggero: leggero)
        }
        // 4. Luce sul volto: il volto più grande, levigato, con una dissolvenza di mezzo secondo.
        immagine = luce(immagine, volti: voltiPixel, acceso: impostazioni.luceVolto, dt: dt)
        // 5. Inquadratura automatica: ritaglio che segue i volti, dopo gli effetti che usano le coordinate intere.
        let zoom = inquadratura.passo(volti: voltiFreschi, quando: voltiAttuali?.quando, acceso: impostazioni.inquadratura,
                                      dt: dt)
        if let zoom {
            immagine = immagine.clampedToExtent().cropped(to: zoom.ritaglio(in: estensione))
                .transformed(by: zoom.trasformazione(in: estensione))
        }
        // 6-7. Filtro, poi le regolazioni dell'utente sul risultato del filtro.
        immagine = RicetteFiltriMac.applica(RicetteFiltriMac.normalizzato(impostazioni.filtro), a: immagine, leggero: leggero)
        if impostazioni.regolazioniAccese {
            immagine = RicetteEffetti.regolazioni(immagine, luminosita: impostazioni.luminosita, contrasto: impostazioni.contrasto,
                                                  saturazione: impostazioni.saturazione, nitidezza: impostazioni.nitidezza)
        }
        // 8. Specchio: uno solo, uguale per la finestra, le app, le foto e la registrazione.
        if impostazioni.specchia {
            immagine = immagine.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                                                  tx: estensione.minX + estensione.maxX, ty: 0))
        }
        // 9. Scritta e logo, dopo lo specchio: si leggono sempre dritti.
        if impostazioni.scrittaAccesa {
            immagine = scritta(immagine, impostazioni: impostazioni, logo: istantanea.logo, estensione: estensione)
        }
        blocco.withLock { inRitorno = inquadratura.inMovimento || presenzaLuce > 0.01 }
        if let mascheraDaMostrare { immagine = mascheraDaMostrare }

        // Sopra un nero opaco grande quanto il fotogramma: ogni pixel del buffer (riusato dal pool) si riscrive.
        immagine = immagine.cropped(to: estensione).composited(over: Self.nero.cropped(to: estensione))
        let destinazione = CIRenderDestination(pixelBuffer: uscita)
        destinazione.colorSpace = spazio
        do {
            let compito = try Self.contesto.startTask(toRender: immagine, to: destinazione)
            _ = try compito.waitUntilCompleted()
        } catch {
            consegnata = ripiego
            return
        }
        consegnata = uscita
        if impostazioni.sfondoAcceso { ultimaConSfondo = uscita }
        let resaMs = Double(Orologio.adesso() &- inizio) / 1000
        blocco.withLock {
            sommaResa += resaMs
            contaResa += 1
        }
        if impostazioni.sfondoAcceso { regolaQualita(resaMs: resaMs) }
    }

    /// I µs da `da` ad `a`; 0 se `da` è dopo (una maschera di un fotogramma arrivato dopo quello che si rende).
    private static func trascorso(da: UInt64, a: UInt64) -> UInt64 {
        a > da ? a - da : 0
    }

    /// Secondi dal fotogramma precedente passato dalla resa (per molle e dissolvenze: stessa velocità a 24, 30 e 60 fps).
    private func passo(_ arrivo: UInt64) -> CGFloat {
        defer { ultimoArrivoResa = arrivo }
        guard ultimoArrivoResa != 0, arrivo > ultimoArrivoResa else { return 1.0 / 30 }
        return CGFloat(min(Double(arrivo - ultimoArrivoResa) / 1_000_000, 0.1))
    }

    /// Scende di un gradino solo se il Mac davvero non tiene il ritmo, per due finestre di fila di circa 5 secondi:
    /// - la resa perde fotogrammi (più del 2%) o in media supera l'85% del tempo di un fotogramma: il video scatterebbe;
    /// - Vision in media supera un fotogramma e mezzo: la maschera si rinnoverebbe troppo di rado.
    /// Vision sotto un fotogramma e mezzo non basta (prima sì: con Vision a 26 ms su 33 si scendeva a `.fast`): ora va
    /// in parallelo alla resa e, se tarda, il fotogramma usa l'ultima maschera. Il tempo di un fotogramma è la media
    /// degli ultimi 30 intervalli. Mai risale da solo: niente sbalzi di qualità.
    private func regolaQualita(resaMs: Double) {
        finestraResa += resaMs
        finestraConta += 1
        guard finestraConta >= Self.fotogrammiPerDecidere else { return }
        let resaMedia = finestraResa / Double(finestraConta)
        let resi = finestraConta
        finestraResa = 0
        finestraConta = 0
        let riscaldamento = finestraDiRiscaldamento
        finestraDiRiscaldamento = false
        let scesa = blocco.withLock { () -> Bool in
            let visionMedia = finestraContaVision > 0 ? finestraVision / Double(finestraContaVision) : 0
            let persi = finestraPersi
            finestraVision = 0
            finestraContaVision = 0
            finestraPersi = 0
            guard !riscaldamento, intervalli.count >= 10, livello < .veloce else { return false }
            // Mai sotto il tempo di un fotogramma a 60 fps: con i fotogrammi arrivati a gruppi la media può uscire di
            // pochi ms (nella prova di Ledion «3 ms»), e la qualità scendeva a `.fast` dopo 3 secondi.
            let fotogrammaMs = max(Double(intervalli.reduce(0, +)) / Double(intervalli.count) / 1000, 1000.0 / 60)
            let resaIndietro = resaMedia > fotogrammaMs * Self.quotaFotogramma
                || Double(persi) > Double(resi + persi) * Self.quotaPersi
            let visionIndietro = visionMedia > fotogrammaMs * Self.quotaVision
            guard resaIndietro || visionIndietro else {
                finestreDifficili = 0
                return false
            }
            finestreDifficili += 1
            guard finestreDifficili >= Self.finestreDifficiliPerScendere else { return false }
            finestreDifficili = 0
            // Da `.accurate` si passa sempre a `.balanced` con il bordo rifinito. Poi: se è solo Vision a restare
            // indietro, subito a `.fast`; se è la resa, prima il bordo leggero.
            if livello == .accurato {
                livello = .pieno
            } else {
                livello = !resaIndietro ? .veloce : Livello(rawValue: livello.rawValue + 1) ?? .veloce
            }
            note.append(.livello(livello, visionMs: Int(visionMedia.rounded()), resaMs: Int(resaMedia.rounded()),
                                 fotogrammaMs: Int(fotogrammaMs.rounded()), persi: persi))
            return true
        }
        // Al livello nuovo la prima finestra è di nuovo di riscaldamento (Vision ricarica il modello).
        if scesa { finestraDiRiscaldamento = true }
    }

    // MARK: Pezzi della resa

    /// La maschera filtrata nel tempo, alla risoluzione di Vision. Dove la maschera cambia (un movimento) vale la nuova;
    /// dove cambia poco si mescola con la precedente: il bordo fermo non sfarfalla, quello in movimento non resta indietro.
    private func filtraNelTempo(_ nuova: CVPixelBuffer) -> CVPixelBuffer? {
        let larghezza = CVPixelBufferGetWidth(nuova)
        let altezza = CVPixelBufferGetHeight(nuova)
        guard larghezza > 0, altezza > 0 else { return mascheraFiltrata }
        var riserva = mascheraRiserva
        if let attuale = riserva, CVPixelBufferGetWidth(attuale) != larghezza || CVPixelBufferGetHeight(attuale) != altezza {
            riserva = nil
        }
        if riserva == nil { riserva = Self.creaBufferBGRA(larghezza: larghezza, altezza: altezza) }
        guard let destinazione = riserva else { return mascheraFiltrata }
        let ingresso = RicetteEffetti.grigio(CIImage(cvPixelBuffer: nuova, options: [.colorSpace: NSNull()]))
        var risultato = ingresso
        if let precedente = mascheraFiltrata,
           CVPixelBufferGetWidth(precedente) == larghezza, CVPixelBufferGetHeight(precedente) == altezza {
            let vecchia = CIImage(cvPixelBuffer: precedente, options: [.colorSpace: NSNull()])
            let differenza = CIFilter.differenceBlendMode()
            differenza.inputImage = ingresso
            differenza.backgroundImage = vecchia
            let peso = RicetteEffetti.lineare(differenza.outputImage ?? ingresso, pendenza: Self.guadagnoDifferenza,
                                              scostamento: Self.pesoMinimo)
            risultato = RicetteFiltriMac.mescola(sopra: ingresso, sotto: vecchia, maschera: peso)
        }
        // Valori come sono (nessuno spazio di colore) e resa finita prima di tornare: la legge subito dopo l'altro
        // contesto, su un'altra coda di comandi Metal, che non aspetterebbe un lavoro solo programmato.
        let scrittura = CIRenderDestination(pixelBuffer: destinazione)
        scrittura.colorSpace = nil
        let area = CGRect(x: 0, y: 0, width: larghezza, height: altezza)
        do {
            let compito = try Self.contestoMaschere.startTask(toRender: risultato.cropped(to: area), to: scrittura)
            _ = try compito.waitUntilCompleted()
        } catch {
            return mascheraFiltrata
        }
        // Due buffer a turno: quello appena scritto diventa il «precedente» della prossima volta. La resa è sincrona
        // e su una coda sola: quando si riscrive la riserva, nessuno la sta leggendo.
        mascheraRiserva = mascheraFiltrata
        mascheraFiltrata = destinazione
        return destinazione
    }

    /// L'immagine dello sfondo sostituito alla misura del video, disegnata una volta e poi riusata finché non cambia.
    /// Finché non è pronta (si legge in sottofondo), il fondo di `Tema`.
    private func immagineSfondo(_ istantanea: StatoMotoreEffetti.Istantanea, voluta: String?, estensione: CGRect) -> CIImage {
        let spostamento = CGAffineTransform(translationX: estensione.minX, y: estensione.minY)
        guard let sfondo = istantanea.sfondo, voluta == nil || sfondo.id == voluta else {
            return CIImage(color: RicetteEffetti.coloreFondo).cropped(to: estensione)
        }
        let larghezza = Int(estensione.width)
        let altezza = Int(estensione.height)
        let chiave = "\(sfondo.versione)-\(larghezza)x\(altezza)"
        if let sfondoPronto, sfondoPronto.chiave == chiave { return sfondoPronto.immagine.transformed(by: spostamento) }
        guard let disegnato = RicetteEffetti.sfondoDisegnato(sfondo.immagine, larghezza: larghezza, altezza: altezza) else {
            return CIImage(color: RicetteEffetti.coloreFondo).cropped(to: estensione)
        }
        let immagine = CIImage(cgImage: disegnato)
        sfondoPronto = (chiave, immagine)
        return immagine.transformed(by: spostamento)
    }

    /// La luce sul volto, morbida nel tempo: rettangolo levigato (25% del nuovo per fotogramma), entra ed esce in
    /// mezzo secondo quando il volto compare o sparisce o quando la si accende e spegne.
    private func luce(_ immagine: CIImage, volti: [CGRect], acceso: Bool, dt: CGFloat) -> CIImage {
        let passoDissolvenza = dt / 0.5
        let estensione = immagine.extent
        let trovato = acceso ? volti.filter { $0.intersects(estensione) && $0.height > 8 }
            .max { $0.width * $0.height < $1.width * $1.height } : nil
        if let trovato {
            if let vecchio = voltoLuce {
                let peso: CGFloat = 0.25
                voltoLuce = CGRect(x: vecchio.minX + (trovato.minX - vecchio.minX) * peso,
                                   y: vecchio.minY + (trovato.minY - vecchio.minY) * peso,
                                   width: vecchio.width + (trovato.width - vecchio.width) * peso,
                                   height: vecchio.height + (trovato.height - vecchio.height) * peso)
            } else {
                voltoLuce = trovato
            }
            presenzaLuce = min(presenzaLuce + passoDissolvenza, 1)
        } else {
            presenzaLuce = max(presenzaLuce - passoDissolvenza, 0)
        }
        guard let volto = voltoLuce, presenzaLuce > 0.01 else {
            if presenzaLuce <= 0.01 { voltoLuce = nil }
            return immagine
        }
        return RicetteEffetti.luceVolto(immagine, volto: volto, presenza: presenzaLuce)
    }

    /// Scritta e logo disegnati una volta e tenuti finché testo, logo o misura non cambiano.
    private func scritta(_ immagine: CIImage, impostazioni: ImpostazioniMotore, logo: (immagine: CGImage, versione: Int)?,
                         estensione: CGRect) -> CIImage {
        let video = CGSize(width: estensione.width, height: estensione.height)
        let nome = impostazioni.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruolo = impostazioni.ruolo.trimmingCharacters(in: .whitespacesAndNewlines)
        let versioneLogo = impostazioni.logo ? (logo?.versione ?? -1) : -1
        let chiave = "\(nome)|\(ruolo)|\(versioneLogo)|\(Int(video.width))x\(Int(video.height))"
        if scrittaPronta?.chiave != chiave {
            scrittaPronta = (chiave,
                             nome.isEmpty ? nil : RicetteEffetti.sottopancia(nome: nome, ruolo: ruolo, video: video),
                             impostazioni.logo ? logo.flatMap { RicetteEffetti.logo($0.immagine, video: video) } : nil)
        }
        var risultato = immagine
        let spostamento = CGAffineTransform(translationX: estensione.minX, y: estensione.minY)
        if let disegnata = scrittaPronta?.scritta { risultato = disegnata.transformed(by: spostamento).composited(over: risultato) }
        if let disegnato = scrittaPronta?.logo { risultato = disegnato.transformed(by: spostamento).composited(over: risultato) }
        return risultato
    }

    // MARK: Buffer

    /// Solo matrice YCbCr, primarie e curva di trasferimento, come il decodificatore: livello, Core Image, webcam
    /// virtuale e registrazione li usano.
    private static let chiaviColore: [CFString] = [kCVImageBufferYCbCrMatrixKey, kCVImageBufferColorPrimariesKey,
                                                   kCVImageBufferTransferFunctionKey]

    private static func copiaAllegatiColore(da ingresso: CVPixelBuffer, a uscita: CVPixelBuffer) {
        for chiave in chiaviColore {
            if let valore = CVBufferCopyAttachment(ingresso, chiave, nil) {
                CVBufferSetAttachment(uscita, chiave, valore, .shouldPropagate)
            } else {
                CVBufferRemoveAttachment(uscita, chiave)
            }
        }
    }

    /// Quanti buffer di uscita: ognuno resta occupato finché tutte le uscite lo tengono (livello della finestra,
    /// finestra mini, webcam virtuale, foto, registrazione, `ultimaConSfondo`), più quelli in resa e i 4-5 che
    /// aspettano nella riserva di riproduzione dello `Schermo` (fino a 120 ms di video).
    private static let bufferMinimi = 16
    private static let bufferMassimi = 22

    /// Un buffer vuoto dal pool, con formato e misura del decodificatore; nil se il pool è esaurito.
    private func bufferDiUscita(come ingresso: CVPixelBuffer) -> CVPixelBuffer? {
        let formato = CVPixelBufferGetPixelFormatType(ingresso)
        let larghezza = CVPixelBufferGetWidth(ingresso)
        let altezza = CVPixelBufferGetHeight(ingresso)
        if pool == nil || formatoPool?.formato != formato || formatoPool?.larghezza != larghezza
            || formatoPool?.altezza != altezza {
            pool = Self.creaPool(formato: formato, larghezza: larghezza, altezza: altezza)
            formatoPool = (formato, larghezza, altezza)
        }
        guard let pool else { return nil }
        var uscita: CVPixelBuffer?
        let attributi = [kCVPixelBufferPoolAllocationThresholdKey as String: Self.bufferMassimi] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributi, &uscita)
                == kCVReturnSuccess else { return nil }
        return uscita
    }

    private static func creaPool(formato: OSType, larghezza: Int, altezza: Int) -> CVPixelBufferPool? {
        let attributiBuffer: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: formato,
            kCVPixelBufferWidthKey as String: larghezza,
            kCVPixelBufferHeightKey as String: altezza,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let attributiPool: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: bufferMinimi]
        var pool: CVPixelBufferPool?
        let esito = CVPixelBufferPoolCreate(kCFAllocatorDefault, attributiPool as CFDictionary,
                                            attributiBuffer as CFDictionary, &pool)
        return esito == kCVReturnSuccess ? pool : nil
    }

    /// Buffer BGRA per la maschera filtrata (i quattro canali uguali).
    private static func creaBufferBGRA(larghezza: Int, altezza: Int) -> CVPixelBuffer? {
        let attributi: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var buffer: CVPixelBuffer?
        let esito = CVPixelBufferCreate(kCFAllocatorDefault, larghezza, altezza, kCVPixelFormatType_32BGRA,
                                        attributi as CFDictionary, &buffer)
        return esito == kCVReturnSuccess ? buffer : nil
    }
}

/// Dove Vision lascia la maschera di un fotogramma che la resa aspetta, al massimo fino a `scadenza`. Se la resa smette
/// di aspettare (o il fotogramma non si rende), la maschera che arriva dopo non va persa: `consegna` risponde falso e
/// il motore la tiene per i fotogrammi dopo (`mascheraSciolta`). Da qualsiasi coda.
private final class CasellaMaschera: @unchecked Sendable {
    /// `Orologio.adesso()` oltre il quale la resa non aspetta più (µs).
    let scadenza: UInt64
    private let blocco = NSLock()
    private let pronta = DispatchSemaphore(value: 0)
    private var maschera: CVPixelBuffer?
    private var consegnata = false
    private var abbandonata = false

    init(scadenza: UInt64) {
        self.scadenza = scadenza
    }

    /// Da Vision (nil se non è riuscita). Vero se la resa del fotogramma la prende; falso se è già andata avanti.
    func consegna(_ nuova: CVPixelBuffer?) -> Bool {
        blocco.lock()
        guard !abbandonata else {
            blocco.unlock()
            return false
        }
        maschera = nuova
        consegnata = true
        blocco.unlock()
        pronta.signal()
        return true
    }

    /// Dalla resa: la maschera, aspettando al massimo fino a `scadenza`; nil se Vision non ha finito in tempo o non
    /// l'ha data. Dopo un nil la casella è abbandonata: una maschera tardiva va ai fotogrammi dopo.
    func attendi() -> CVPixelBuffer? {
        let adesso = Orologio.adesso()
        if scadenza > adesso {
            _ = pronta.wait(timeout: .now() + .microseconds(Int(scadenza - adesso)))
        }
        return blocco.withLock { () -> CVPixelBuffer? in
            guard consegnata else {
                abbandonata = true
                return nil
            }
            return maschera
        }
    }

    /// Il fotogramma non si rende con lo sfondo (scartato, sfondo spento): la maschera, se arriva, va ai prossimi.
    func abbandona() {
        blocco.withLock {
            if !consegnata { abbandonata = true }
        }
    }
}

/// L'inquadratura automatica (come InquadraturaAutomatica.swift dell'iPhone): uno zoom digitale da 1× a 1,6× che tiene
/// i volti al centro, con una molla smorzata in modo critico (arriva senza oscillare in circa un secondo e mezzo), una
/// zona morta contro i tremolii e il ritorno lento all'inquadratura intera senza volti per 2 secondi o da spenta.
struct MollaInquadratura {
    static let zoomMassimo: CGFloat = 1.6

    struct Riquadro {
        var x: CGFloat = 0.5
        var y: CGFloat = 0.5
        var zoom: CGFloat = 1
    }

    private var attuale = Riquadro()
    private var velocita = Riquadro(x: 0, y: 0, zoom: 0)
    private var bersaglio = Riquadro()
    private var ultimoVolto: UInt64 = 0
    private var ultimaAnalisi: UInt64 = 0
    private var tempo: UInt64 = 0

    /// Ancora zoomata o in movimento: il motore deve continuare a lavorare anche da spenta.
    var inMovimento: Bool { attuale.zoom > 1.002 }

    /// Un passo della molla. `volti`: normalizzati, nil se vecchi; `quando`: l'istante dell'analisi (µs).
    /// Ritorna il riquadro da ritagliare, o nil all'inquadratura intera.
    mutating func passo(volti: [CGRect]?, quando: UInt64?, acceso: Bool, dt: CGFloat) -> Riquadro? {
        tempo &+= UInt64(dt * 1_000_000)
        if acceso, let volti, let quando, quando != ultimaAnalisi {
            ultimaAnalisi = quando
            if !volti.isEmpty {
                ultimoVolto = tempo
                let nuovo = Self.riquadro(per: volti)
                let soglia = 0.06 / bersaglio.zoom
                if abs(nuovo.x - bersaglio.x) > soglia || abs(nuovo.y - bersaglio.y) > soglia
                    || abs(nuovo.zoom - bersaglio.zoom) / bersaglio.zoom > 0.08 {
                    bersaglio = nuovo
                }
            }
        }
        let senzaVolti = !acceso || tempo &- ultimoVolto > 2_000_000
        if senzaVolti { bersaglio = Riquadro() }
        let omega: CGFloat = senzaVolti ? 1.3 : 2.8
        Self.molla(&attuale.x, &velocita.x, verso: bersaglio.x, omega: omega, dt: dt)
        Self.molla(&attuale.y, &velocita.y, verso: bersaglio.y, omega: omega, dt: dt)
        Self.molla(&attuale.zoom, &velocita.zoom, verso: bersaglio.zoom, omega: omega, dt: dt)
        attuale.zoom = min(max(attuale.zoom, 1), Self.zoomMassimo)
        let meta = 0.5 / attuale.zoom
        attuale.x = min(max(attuale.x, meta), 1 - meta)
        attuale.y = min(max(attuale.y, meta), 1 - meta)
        guard attuale.zoom > 1.002 else {
            if !acceso {
                attuale = Riquadro()
                velocita = Riquadro(x: 0, y: 0, zoom: 0)
            }
            return nil
        }
        return attuale
    }

    private static func riquadro(per volti: [CGRect]) -> Riquadro {
        var unione = volti[0]
        for volto in volti.dropFirst() { unione = unione.union(volto) }
        let necessario = max(unione.height * 3.2, unione.width * 2.2, 1 / zoomMassimo)
        let zoom = min(max(1 / necessario, 1), zoomMassimo)
        // Il volto un po' sopra il centro (origine in basso: il centro del riquadro scende).
        return Riquadro(x: unione.midX, y: unione.midY - 0.12 / zoom, zoom: zoom)
    }

    private static func molla(_ valore: inout CGFloat, _ velocita: inout CGFloat, verso: CGFloat, omega: CGFloat, dt: CGFloat) {
        let accelerazione = omega * omega * (verso - valore) - 2 * omega * velocita
        velocita += accelerazione * dt
        valore += velocita * dt
    }
}

extension MollaInquadratura.Riquadro {
    /// Il rettangolo da ritagliare nell'immagine.
    func ritaglio(in estensione: CGRect) -> CGRect {
        let larghezza = estensione.width / zoom
        let altezza = estensione.height / zoom
        return CGRect(x: estensione.minX + x * estensione.width - larghezza / 2,
                      y: estensione.minY + y * estensione.height - altezza / 2, width: larghezza, height: altezza)
    }

    /// Dal ritaglio alla misura intera dell'immagine.
    func trasformazione(in estensione: CGRect) -> CGAffineTransform {
        let area = ritaglio(in: estensione)
        return CGAffineTransform(translationX: -area.minX, y: -area.minY)
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(translationX: estensione.minX, y: estensione.minY))
    }
}
