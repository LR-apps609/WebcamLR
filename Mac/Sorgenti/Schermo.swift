import AVFoundation
import CoreImage
import CoreMedia
import QuartzCore
import VideoToolbox
import WebcamLRProtocollo

/// Decodifica i fotogrammi H.264 o HEVC (Annex B) con VideoToolbox, sul decodificatore hardware del Mac, in tempo reale
/// (funzione 4). Una decodifica sola per tutto: la stessa immagine va a `livello` (la finestra), alle foto (funzione 35),
/// alla webcam virtuale e alla finestra mini. L'immagine resta nel formato del decodificatore (YCbCr 4:2:0, a gamma ridotta
/// o piena come il flusso, di solito BT.709 come la manda il telefono): niente conversione in BGRA qui; il livello la
/// mostra così com'è e Core Image la converte una volta sola dove serve (UscitaWebcam).
/// Tutto il lavoro avviene sulla sua coda.
/// Dalla P21 c'è uno `Schermo` per ogni telefono collegato (più uno vuoto quando non ce n'è nessuno):
/// la finestra mini e la webcam virtuale prendono le immagini di quello scelto (`UscitaMini`, `UscitaWebcam`).
/// Sopra il video c'è la schermata di attesa (AttesaWebcam.swift), la stessa che vedono le app di chiamata:
/// compare con una dissolvenza quando il video non c'è e se ne va quando torna.
/// Dal 27 ottobre gli effetti di immagine li fa il Mac (`motore`, MotoreEffetti.swift): dopo la decodifica l'immagine
/// passa dal motore una volta sola, e `pubblica` dà a tutte le uscite (finestra, foto, webcam virtuale, finestra mini,
/// registrazione) quella già elaborata. Senza effetti accesi il motore non la tocca e non costa nulla.
final class Schermo: @unchecked Sendable {
    let livello = AVSampleBufferDisplayLayer()
    /// Il motore effetti di questo telefono: acceso dal `Ricevitore` solo per il telefono nella webcam.
    let motore = MotoreEffetti()
    /// Ogni immagine decodificata, sulla coda dello schermo (webcam virtuale e finestra mini, round 2 e P21).
    /// Si cambia con `inviaImmagini(a:)`: si legge sulla coda, quindi si scrive solo lì. Con l'istante di cattura
    /// nell'orologio del Mac (µs; nil se non si sa), per il ritardo da vetro a uscita della webcam.
    private var suImmagine: ((CVPixelBuffer, Int64?) -> Void)?
    /// Da vetro alla finestra: dalla cattura sul telefono all'immagine decodificata passata al livello (mediana di un
    /// secondo, Protocollo.md «Latenza»). Da qualsiasi coda.
    let ritardo = MisuraRitardo()
    /// La registrazione si è chiusa da sola (formato cambiato, disco pieno): il file, il perché e quanto è salvato.
    /// Arriva con `avviaRegistrazione`; solo sulla coda.
    private var suRegistrazioneInterrotta: (@Sendable (URL, InterruzioneRegistrazione) -> Void)?

    private let coda = DispatchQueue(label: "it.lrapps.webcamlr.schermo", qos: .userInteractive)
    private var formato: CMVideoFormatDescription?
    private var attendiChiave = true
    /// Dal messaggio `formato` del telefono (funzione 10).
    private var codec: Codec = .h264
    private var sessioneDecodifica: VTDecompressionSession?
    private var formatoDecodifica: CMVideoFormatDescription?
    /// La descrizione delle immagini decodificate per `livello`, rifatta solo quando cambiano misura o formato.
    private var formatoImmagini: CMVideoFormatDescription?
    private var ultimaImmagine: CVPixelBuffer?
    /// Cresce a ogni `svuota`: un fotogramma ancora nel motore effetti da prima non arriva più a `pubblica`. Solo sulla coda.
    private var generazione = 0
    /// Le pause più lunghe dall'ultima lettura (`prendiPause`), in µs: tra due fotogrammi catturati dal telefono, tra due
    /// arrivati al Mac, tra due mostrati. Dicono dove si ferma il video quando scatta.
    private let bloccoPause = NSLock()
    private var pause = Pause()
    private var ultimaCattura: UInt64 = 0
    private var ultimoArrivo: UInt64 = 0
    private var ultimaMostrata: UInt64 = 0

    struct Pause {
        var telefono: UInt64 = 0
        var arrivo: UInt64 = 0
        var mostrate: UInt64 = 0
    }
    /// La riserva di riproduzione (`RiservaRiproduzione`) e le immagini che vi aspettano, in ordine, con l'istante in
    /// cui escono (`Orologio`, µs). Solo sulla coda.
    private var riserva = RiservaRiproduzione()
    private var inRiserva: [(immagine: CVPixelBuffer, cattura: Int64, timestamp: UInt64, quando: UInt64)] = []
    /// Fa uscire la prima immagine della riserva al suo istante (creato in `init`, sulla coda).
    private var timerRiserva: DispatchSourceTimer?
    /// Per il registro (sotto `bloccoPause`): la riserva attuale (µs) e le immagini uscite in ritardo dall'ultima lettura.
    private var riservaAttuale: Int64 = 0
    private var uscitePiuTardi = 0
    private var registratore: Registratore?
    /// In attesa della prima immagine a schermo di una sessione (1.11): si chiama una volta e si toglie.
    private var avvisoMostrato: (@Sendable () -> Void)?
    /// Creato una volta: un CIContext nuovo a ogni foto costava decine di millisecondi.
    private let contestoFoto = CIContext()

    /// La schermata di attesa sopra il video: un livello figlio di `livello`, che lo segue nelle misure.
    /// Si tocca solo dalla coda principale.
    private let strato = CALayer()
    /// Video o attesa: solo sulla coda.
    private var programma = ProgrammaAttesa()
    /// Quello che `strato` mostra adesso (nil = nascosto) e con quale versione di stile e immagine. Solo sulla coda.
    private var mostrata: StatoAttesa?
    private var versioneMostrata = -1
    /// Ricontrolla 4 volte al secondo (la tenuta di 2 secondi dopo una caduta), sulla coda.
    private var timerAttesa: DispatchSourceTimer?

    init() {
        livello.videoGravity = .resizeAspect
        livello.backgroundColor = CGColor(gray: 0, alpha: 1)
        // Con «riempi» l'immagine va oltre i bordi: si taglia lì.
        livello.masksToBounds = true

        // Sempre a riempire il riquadro, sopra il video (zPosition: anche sopra ciò che il livello aggiunge da sé).
        strato.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        strato.frame = livello.bounds
        strato.contentsGravity = .resizeAspectFill
        strato.masksToBounds = true
        strato.zPosition = 10
        strato.opacity = 0
        // Niente animazioni implicite: le dissolvenze sono esplicite (`dissolvi`).
        strato.actions = ["contents": NSNull(), "opacity": NSNull(), "bounds": NSNull(), "position": NSNull()]
        livello.addSublayer(strato)

        // Il primo controllo dopo un attimo: i caratteri di Stile si registrano subito dopo il primo `Schermo`.
        let timer = DispatchSource.makeTimerSource(queue: coda)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.valutaAttesa() }
        timerAttesa = timer
        timer.resume()

        // Fermo finché la riserva non ha un'immagine da far uscire (`programmaRiserva`). Preciso al millisecondo: è
        // lui a dare il ritmo alle immagini.
        let uscita = DispatchSource.makeTimerSource(flags: .strict, queue: coda)
        uscita.schedule(deadline: .distantFuture)
        uscita.setEventHandler { [weak self] in self?.esciDallaRiserva() }
        timerRiserva = uscita
        uscita.resume()
    }

    deinit {
        timerAttesa?.cancel()
        timerRiserva?.cancel()
    }

    /// Riempi (il video copre tutto, tagliando i bordi) o adatta (si vede intero, con bande nere). Funzione 30.
    /// Da chiamare sulla coda principale, come ogni modifica ai livelli.
    func imposta(riempi: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        livello.videoGravity = riempi ? .resizeAspectFill : .resizeAspect
        CATransaction.commit()
    }

    /// Dove mandare ogni immagine decodificata (webcam virtuale e finestra mini); nil per nessuno.
    func inviaImmagini(a destinatario: ((CVPixelBuffer, Int64?) -> Void)?) {
        coda.async { self.suImmagine = destinatario }
    }

    /// Il telefono ha annunciato un formato: se il codec cambia, si riparte dal prossimo fotogramma chiave.
    func imposta(codec nuovo: Codec) {
        coda.async {
            guard nuovo != self.codec else { return }
            self.codec = nuovo
            self.formato = nil
            self.attendiChiave = true
        }
    }

    /// `mostrato`: chiamata (sulla coda dello schermo) appena un'immagine, da questo fotogramma o dai seguenti,
    /// è decodificata e passata al livello: chiude la misura dell'avvio (1.11).
    /// `cattura`: l'istante di cattura del fotogramma nell'orologio del Mac (µs), nil se non c'è ancora un `pong`.
    func mostra(_ fotogramma: FotogrammaVideo, cattura: Int64? = nil, mostrato: (@Sendable () -> Void)? = nil) {
        coda.async {
            if let mostrato { self.avvisoMostrato = mostrato }
            self.accoda(fotogramma, cattura: cattura)
        }
    }

    /// Dall'`OsservatoreAttesa` (AttesaWebcam.swift): perché il video di questo telefono non c'è; nil se dovrebbe esserci.
    func imposta(attesa: StatoAttesa?) {
        coda.async {
            guard attesa != self.programma.stato else { return }
            self.programma.imposta(attesa, adesso: DispatchTime.now().uptimeNanoseconds)
            self.valutaAttesa()
        }
    }

    func svuota() {
        motore.azzera()
        coda.async {
            self.generazione &+= 1
            // Sessione nuova: altro orologio del telefono, altra rete. La riserva riparte da zero.
            self.inRiserva.removeAll()
            self.riserva = RiservaRiproduzione()
            self.timerRiserva?.schedule(deadline: .distantFuture)
            self.livello.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            self.formato = nil
            self.attendiChiave = true
            self.chiudiDecodifica()
            self.formatoImmagini = nil
            self.ultimaImmagine = nil
            self.avvisoMostrato = nil
        }
    }

    /// L'ultima immagine ricevuta, per una foto; nil se non c'è ancora video.
    func fotografa(_ completamento: @escaping @Sendable (CGImage?) -> Void) {
        coda.async {
            guard let immagine = self.ultimaImmagine else { return completamento(nil) }
            let ci = CIImage(cvPixelBuffer: immagine)
            completamento(self.contestoFoto.createCGImage(ci, from: ci.extent))
        }
    }

    /// Le pause più lunghe dall'ultima volta (µs), poi da capo. Da qualsiasi coda.
    func prendiPause() -> Pause {
        bloccoPause.withLock {
            let prese = pause
            pause = Pause()
            return prese
        }
    }

    /// Per il registro: la riserva di riproduzione attuale (ms) e quante immagini sono uscite più tardi del loro
    /// istante (oltre 25 ms: lì il video scatta ancora) dall'ultima lettura. Da qualsiasi coda.
    func prendiRiserva() -> (ms: Int, inRitardo: Int) {
        bloccoPause.withLock {
            let lette = (ms: Int(riservaAttuale / 1000), inRitardo: uscitePiuTardi)
            uscitePiuTardi = 0
            return lette
        }
    }

    private func accoda(_ fotogramma: FotogrammaVideo, cattura: Int64?) {
        let arrivo = Orologio.adesso()
        bloccoPause.withLock {
            if ultimoArrivo != 0, arrivo > ultimoArrivo { pause.arrivo = max(pause.arrivo, arrivo - ultimoArrivo) }
            if ultimaCattura != 0, fotogramma.timestamp > ultimaCattura {
                pause.telefono = max(pause.telefono, fotogramma.timestamp - ultimaCattura)
            }
        }
        ultimoArrivo = arrivo
        ultimaCattura = fotogramma.timestamp
        let unita = AnnexB.unita(in: fotogramma.dati)
        let hevc = codec == .hevc
        let tipo: (Data) -> UInt8 = hevc ? AnnexB.tipoHEVC : AnnexB.tipoH264

        if hevc {
            if let vps = unita.first(where: { tipo($0) == 32 }),
               let sps = unita.first(where: { tipo($0) == 33 }),
               let pps = unita.first(where: { tipo($0) == 34 }),
               let nuovo = Self.descrizioneHEVC(vps: vps, sps: sps, pps: pps) {
                formato = nuovo
            }
        } else if let sps = unita.first(where: { tipo($0) == 7 }),
                  let pps = unita.first(where: { tipo($0) == 8 }),
                  let nuovo = Self.descrizione(sps: sps, pps: pps) {
            formato = nuovo
        }

        if attendiChiave {
            guard fotogramma.chiave else { return }
            attendiChiave = false
        }

        // Solo le unità con l'immagine: parametri e delimitatori stanno nel formato.
        let esclusi: Set<UInt8> = hevc ? [32, 33, 34, 35] : [7, 8, 9]
        let immagine = unita.filter { !esclusi.contains(tipo($0)) }
        guard let formatoAttuale = formato, !immagine.isEmpty,
              let campione = Self.campione(immagine, formato: formatoAttuale, chiave: fotogramma.chiave) else { return }
        registra(campione, formato: formatoAttuale, fotogramma: fotogramma)
        decodificaInImmagine(campione, formato: formatoAttuale, cattura: cattura, timestamp: fotogramma.timestamp)
    }

    // MARK: - Registrazione (funzione 35)

    /// Inizia a salvare il video. Con gli effetti sul Mac (`MotoreEffetti.effettiSulComputer`) si registra l'immagine
    /// già elaborata, ricompressa dal codificatore hardware del Mac (AVAssetWriter) con il codec del telefono: la
    /// registrazione è uguale a ciò che vedono la finestra e le app. Altrimenti il video così come arriva, già compresso.
    /// `suInterruzione`: il file si è chiuso da solo (formato cambiato, disco pieno), con il perché e quanto è salvato.
    func avviaRegistrazione(in file: URL, suInterruzione: @escaping @Sendable (URL, InterruzioneRegistrazione) -> Void) {
        coda.async {
            self.registratore = Registratore(file: file, elaborato: MotoreEffetti.effettiSulComputer)
            self.suRegistrazioneInterrotta = suInterruzione
        }
    }

    /// Chiude il file; `completamento` riceve il file, oppure nil se non è stato registrato nulla.
    func fermaRegistrazione(_ completamento: @escaping @Sendable (URL?) -> Void) {
        coda.async {
            guard let registratore = self.registratore else { return completamento(nil) }
            self.registratore = nil
            registratore.chiudi(completamento)
        }
    }

    private func registra(_ campione: CMSampleBuffer, formato: CMVideoFormatDescription, fotogramma: FotogrammaVideo) {
        guard let registratore, !registratore.elaborato else { return }
        if let causa = registratore.aggiungi(campione, formato: formato, fotogramma: fotogramma) {
            interrompiRegistrazione(registratore, causa: causa)
        }
    }

    /// Sulla coda: un'immagine già elaborata (o solo decodificata) nella registrazione ricompressa.
    private func registra(immagine: CVPixelBuffer, timestamp: UInt64) {
        guard let registratore, registratore.elaborato else { return }
        if let causa = registratore.aggiungi(immagine: immagine, timestamp: timestamp, hevc: codec == .hevc) {
            interrompiRegistrazione(registratore, causa: causa)
        }
    }

    /// Il formato è cambiato (altro obiettivo, telefono girato) o il disco è pieno: il file si chiude qui,
    /// e Riprese lo deve sapere, altrimenti continuerebbe a mostrare «Ferma». Con il disco pieno il file resta,
    /// leggibile fino all'ultimo frammento (punto 5).
    private func interrompiRegistrazione(_ registratore: Registratore, causa: InterruzioneRegistrazione.Causa) {
        self.registratore = nil
        let file = registratore.file
        let avviso = suRegistrazioneInterrotta
        registratore.chiudi(causa: causa) { esito in avviso?(file, esito) }
    }

    // MARK: - Schermata di attesa

    /// Sulla coda: decide se mostrare l'attesa e, se cambia, la disegna (una volta per stato) e la passa al livello.
    private func valutaAttesa() {
        let voluta = programma.attesa(adesso: DispatchTime.now().uptimeNanoseconds)
        let istantanea = AttesaWebcam.condivisa.istantanea()
        guard voluta != mostrata || (voluta != nil && istantanea.versione != versioneMostrata) else { return }
        let prima = mostrata
        mostrata = voluta
        versioneMostrata = istantanea.versione
        let strato = self.strato
        guard let voluta else {
            // Il video è tornato: l'attesa svanisce sopra la prima immagine nuova.
            DispatchQueue.main.async { Self.dissolvi(strato, a: 0, durata: 0.3) }
            return
        }
        let sfondo = istantanea.stile == .sfocata ? ultimaImmagine.flatMap { AttesaWebcam.sfocata($0, contesto: contestoFoto) } : nil
        guard let immagine = AttesaWebcam.condivisa.immagine(voluta, stile: istantanea.stile, sfondo: sfondo,
                                                              larghezza: 1920, altezza: 1080) else { return }
        // Dissolvenza sopra l'ultima immagine; subito se dietro non c'è niente (all'avvio, nessun telefono).
        let durata = ultimaImmagine == nil && prima == nil ? 0 : 0.5
        DispatchQueue.main.async {
            if prima != nil {
                // Da un'attesa all'altra (per esempio da «interrotto» a «non collegata»), o stile cambiato:
                // dissolvenza tra le due immagini.
                let transizione = CATransition()
                transizione.type = .fade
                transizione.duration = 0.4
                strato.add(transizione, forKey: "cambio")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            strato.contents = immagine
            CATransaction.commit()
            Self.dissolvi(strato, a: 1, durata: durata)
        }
    }

    /// Sulla coda principale. Parte dall'opacità che si vede adesso, anche a metà di un'altra dissolvenza: niente salti.
    private static func dissolvi(_ strato: CALayer, a opacita: Float, durata: Double) {
        let attuale = strato.presentation()?.opacity ?? strato.opacity
        strato.removeAnimation(forKey: "dissolvenza")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strato.opacity = opacita
        CATransaction.commit()
        guard durata > 0, attuale != opacita else { return }
        let animazione = CABasicAnimation(keyPath: "opacity")
        animazione.fromValue = attuale
        animazione.toValue = opacita
        animazione.duration = durata
        animazione.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        strato.add(animazione, forKey: "dissolvenza")
    }

    // MARK: - Decodifica in immagini

    private func decodificaInImmagine(_ campione: CMSampleBuffer, formato: CMVideoFormatDescription, cattura: Int64?,
                                      timestamp: UInt64) {
        if sessioneDecodifica == nil || !CMFormatDescriptionEqual(formato, otherFormatDescription: formatoDecodifica) {
            creaDecodifica(formato)
        }
        guard let sessione = sessioneDecodifica else { return }
        // Sincrona: l'immagine arriva prima che la chiamata finisca, sulla stessa coda. Senza flag: niente decodifica
        // asincrona né riordino (il telefono non usa fotogrammi B), ogni fotogramma esce appena decodificato.
        let esito = VTDecompressionSessionDecodeFrame(sessione, sampleBuffer: campione, flags: [], infoFlagsOut: nil) {
            [weak self] stato, _, immagine, _, _ in
            guard stato == noErr, let immagine, let self else { return }
            Schermo.completaColore(immagine)
            // Gli effetti del Mac: il motore elabora e consegna dalla sua coda; si torna qui per le uscite, se lo
            // schermo non è stato svuotato nel frattempo (telefono andato, sessione nuova).
            let generazione = self.generazione
            // Poi la riserva di riproduzione dà il ritmo a tutte le uscite.
            let elaborata = self.motore.elabora(immagine) { [weak self] uscita in
                self?.coda.async {
                    guard let self, self.generazione == generazione else { return }
                    self.accodaAlRitmo(uscita, cattura: cattura, timestamp: timestamp)
                }
            }
            if !elaborata { self.accodaAlRitmo(immagine, cattura: cattura, timestamp: timestamp) }
        }
        // Dopo lo stop del Mac la sessione può non valere più: senza rifarla finestra, foto, finestra mini
        // e webcam virtuale resterebbero ferme sull'ultima immagine. Si rifà dal prossimo fotogramma chiave
        // (una sessione nuova non sa decodificare quelli che dipendono dai precedenti).
        if Int(esito) == Int(kVTInvalidSessionErr) {
            chiudiDecodifica()
            attendiChiave = true
        }
    }

    // MARK: - Riserva di riproduzione

    /// Sulla coda: l'immagine pronta (decodificata e, se ci sono effetti, elaborata) passa dalla riserva di riproduzione.
    /// Esce all'istante di cattura sul telefono più un ritardo quasi fisso (`RiservaRiproduzione`): così finestra,
    /// webcam virtuale, finestra mini e registrazione ricevono le immagini al ritmo della fotocamera anche quando
    /// arrivano a gruppi dalla rete o dal motore effetti (prova di Ledion, 27 ottobre: una pausa di 110-160 ms ogni
    /// 2-3 secondi). Dopo il motore, così la riserva assorbe anche le sue variazioni. Senza l'istante di cattura
    /// (nessun `pong` ancora) l'immagine esce subito, come prima.
    private func accodaAlRitmo(_ immagine: CVPixelBuffer, cattura: Int64?, timestamp: UInt64) {
        let adesso = Orologio.adesso()
        guard let cattura, let istante = riserva.uscita(cattura: cattura, adesso: adesso) else {
            // Prima quelle che aspettano: l'ordine non cambia.
            esciDallaRiserva(tutte: true)
            pubblica(immagine, cattura: cattura, timestamp: timestamp)
            return
        }
        bloccoPause.withLock { riservaAttuale = riserva.attuale }
        // Mai prima di quella davanti, e mai oltre il tetto da adesso (orologi cambiati, valori strani).
        let limite = adesso + UInt64(RiservaRiproduzione.tetto) + Self.anticipoUscita
        let quando = max(min(istante, limite), inRiserva.last?.quando ?? 0)
        if quando + Self.ritardoVisibile < adesso { bloccoPause.withLock { uscitePiuTardi += 1 } }
        if inRiserva.isEmpty, quando <= adesso + Self.anticipoUscita {
            pubblica(immagine, cattura: cattura, timestamp: timestamp)
            return
        }
        inRiserva.append((immagine: immagine, cattura: cattura, timestamp: timestamp, quando: quando))
        // Un guasto non deve accumulare video: oltre 8 immagini (più di 250 ms a 30 fps) la prima esce subito.
        if inRiserva.count > Self.massimeInRiserva {
            let prima = inRiserva.removeFirst()
            pubblica(prima.immagine, cattura: prima.cattura, timestamp: prima.timestamp)
        }
        programmaRiserva()
    }

    /// Un'immagine esce se il suo istante è entro 1 ms (il timer non è più preciso di così).
    private static let anticipoUscita: UInt64 = 1_000
    /// Uscita più tardi del suo istante di oltre 25 ms: lì si vede ancora uno scatto (per il registro).
    private static let ritardoVisibile: UInt64 = 25_000
    private static let massimeInRiserva = 8

    /// Sulla coda (dal timer): le immagini arrivate al loro istante (o tutte), poi il timer per la prossima.
    private func esciDallaRiserva(tutte: Bool = false) {
        guard !inRiserva.isEmpty else { return }
        let adesso = Orologio.adesso()
        while let prima = inRiserva.first, tutte || prima.quando <= adesso + Self.anticipoUscita {
            inRiserva.removeFirst()
            pubblica(prima.immagine, cattura: prima.cattura, timestamp: prima.timestamp)
        }
        programmaRiserva()
    }

    /// Sulla coda: il timer all'istante della prima immagine in riserva; fermo se non ce n'è.
    private func programmaRiserva() {
        guard let prima = inRiserva.first else {
            timerRiserva?.schedule(deadline: .distantFuture)
            return
        }
        let adesso = Orologio.adesso()
        let attesa = prima.quando > adesso ? prima.quando - adesso : 0
        timerRiserva?.schedule(deadline: .now() + .microseconds(Int(attesa)), leeway: .microseconds(500))
    }

    /// Sulla coda: l'immagine da mostrare (già elaborata dal motore, se ci sono effetti) a tutte le uscite: finestra,
    /// foto, webcam virtuale e finestra mini (`suImmagine`), registrazione ricompressa.
    private func pubblica(_ immagine: CVPixelBuffer, cattura: Int64?, timestamp: UInt64) {
        ultimaImmagine = immagine
        mostraNelLivello(immagine)
        let mostrata = Orologio.adesso()
        bloccoPause.withLock {
            if ultimaMostrata != 0, mostrata > ultimaMostrata { pause.mostrate = max(pause.mostrate, mostrata - ultimaMostrata) }
        }
        ultimaMostrata = mostrata
        // Da vetro alla finestra: il livello mostra subito (DisplayImmediately). Comprende il tempo degli effetti.
        if let cattura {
            let adesso = Orologio.adesso()
            if let ms = RitardoVetro.ms(cattura: cattura, adesso: adesso) { ritardo.aggiungi(ms, adesso: adesso) }
        }
        suImmagine?(immagine, cattura)
        registra(immagine: immagine, timestamp: timestamp)
        programma.vivo(adesso: DispatchTime.now().uptimeNanoseconds)
        // Il video torna: l'attesa se ne va subito, senza aspettare il prossimo controllo.
        if mostrata != nil { valutaAttesa() }
        // La prima immagine di questa sessione è a schermo (1.11).
        if let avviso = avvisoMostrato {
            avvisoMostrato = nil
            avviso()
        }
    }

    /// Sulla coda: l'immagine appena elaborata (o decodificata) nel livello della finestra, da mostrare subito.
    private func mostraNelLivello(_ immagine: CVPixelBuffer) {
        guard let campione = Self.campioneDaMostrare(immagine, descrizione: &formatoImmagini) else { return }
        if livello.sampleBufferRenderer.status == .failed {
            livello.sampleBufferRenderer.flush()
        }
        livello.sampleBufferRenderer.enqueue(campione)
    }

    private func creaDecodifica(_ formato: CMVideoFormatDescription) {
        chiudiDecodifica()
        // Nessun formato dei pixel imposto: il decodificatore dà il suo (YCbCr 4:2:0, a gamma ridotta o piena come il
        // flusso), senza una conversione in BGRA a ogni fotogramma (un 4K in BGRA pesa più del doppio in memoria).
        // Su IOSurface: il livello, Core Image e la webcam virtuale lo usano senza copie.
        let attributi: NSDictionary = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
        ]
        // Il decodificatore hardware del Mac, quando c'è (su alcuni Mac Intel non è la scelta di serie).
        let specifica: NSDictionary = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true]
        var nuova: VTDecompressionSession?
        let esito = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formato,
                                                 decoderSpecification: specifica, imageBufferAttributes: attributi,
                                                 outputCallback: nil, decompressionSessionOut: &nuova)
        if esito == noErr, let nuova {
            // Video dal vivo: il decodificatore dà la precedenza alla latenza (anche con 60 Mbit/s dal cavo).
            VTSessionSetProperty(nuova, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            sessioneDecodifica = nuova
            formatoDecodifica = formato
        }
    }

    /// Un flusso senza i dati del colore (un telefono che non li scrive): BT.709, come lo manda l'iPhone e come lo dichiara
    /// la webcam su Windows. Senza, Core Image e il livello potrebbero usare la matrice BT.601 delle vecchie TV e i colori
    /// (il viso) uscirebbero spostati. La gamma (ridotta o piena) è già nel formato dei pixel scelto dal decodificatore.
    private static func completaColore(_ immagine: CVPixelBuffer) {
        let valori: [(CFString, CFString)] = [
            (kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2),
            (kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2),
            (kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2)
        ]
        for (chiave, valore) in valori where CVBufferCopyAttachment(immagine, chiave, nil) == nil {
            CVBufferSetAttachment(immagine, chiave, valore, .shouldPropagate)
        }
    }

    private func chiudiDecodifica() {
        if let sessioneDecodifica { VTDecompressionSessionInvalidate(sessioneDecodifica) }
        sessioneDecodifica = nil
        formatoDecodifica = nil
    }

    private static func descrizione(sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var formato: CMVideoFormatDescription?
        let esito = sps.withUnsafeBytes { bytesSPS in
            pps.withUnsafeBytes { bytesPPS in
                let puntatori = [
                    bytesSPS.bindMemory(to: UInt8.self).baseAddress!,
                    bytesPPS.bindMemory(to: UInt8.self).baseAddress!
                ]
                let dimensioni = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: puntatori, parameterSetSizes: dimensioni,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &formato)
            }
        }
        return esito == noErr ? formato : nil
    }

    private static func descrizioneHEVC(vps: Data, sps: Data, pps: Data) -> CMVideoFormatDescription? {
        var formato: CMVideoFormatDescription?
        let esito = vps.withUnsafeBytes { bytesVPS in
            sps.withUnsafeBytes { bytesSPS in
                pps.withUnsafeBytes { bytesPPS in
                    let puntatori = [
                        bytesVPS.bindMemory(to: UInt8.self).baseAddress!,
                        bytesSPS.bindMemory(to: UInt8.self).baseAddress!,
                        bytesPPS.bindMemory(to: UInt8.self).baseAddress!
                    ]
                    let dimensioni = [vps.count, sps.count, pps.count]
                    return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: 3,
                        parameterSetPointers: puntatori, parameterSetSizes: dimensioni,
                        nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &formato)
                }
            }
        }
        return esito == noErr ? formato : nil
    }

    /// Da Annex B ad AVCC: ogni unità preceduta dalla sua lunghezza in 4 byte.
    private static func campione(_ unita: [Data], formato: CMVideoFormatDescription, chiave: Bool) -> CMSampleBuffer? {
        var avcc = Data()
        for nal in unita {
            let lunghezza = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: lunghezza) { avcc.append(contentsOf: $0) }
            avcc.append(nal)
        }

        var bloccoCreato: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: avcc.count, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: avcc.count,
                                                 flags: 0, blockBufferOut: &bloccoCreato) == kCMBlockBufferNoErr,
              let blocco = bloccoCreato else { return nil }
        let copiato = avcc.withUnsafeBytes { byte in
            CMBlockBufferReplaceDataBytes(with: byte.baseAddress!, blockBuffer: blocco, offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copiato == kCMBlockBufferNoErr else { return nil }

        var campioneCreato: CMSampleBuffer?
        var dimensione = avcc.count
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: blocco, formatDescription: formato,
                                        sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &dimensione,
                                        sampleBufferOut: &campioneCreato) == noErr,
              let campione = campioneCreato else { return nil }

        if let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: true),
           CFArrayGetCount(allegati) > 0 {
            let allegato = unsafeBitCast(CFArrayGetValueAtIndex(allegati, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(allegato,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            // I fotogrammi non chiave vanno segnati: serve al file registrato per andare avanti e indietro.
            if !chiave {
                CFDictionarySetValue(allegato,
                                     Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                     Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
        }
        return campione
    }

    /// Un'immagine già decodificata in un campione per un `AVSampleBufferDisplayLayer`, da mostrare subito.
    /// `descrizione` si rifà solo quando cambiano misura o formato dei pixel.
    static func campioneDaMostrare(_ immagine: CVPixelBuffer, descrizione: inout CMVideoFormatDescription?) -> CMSampleBuffer? {
        if descrizione.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: immagine) }) ?? true {
            var creata: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: immagine,
                                                               formatDescriptionOut: &creata) == noErr,
                  let nuova = creata else { return nil }
            descrizione = nuova
        }
        guard let attuale = descrizione else { return nil }
        var tempi = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                       decodeTimeStamp: .invalid)
        var campioneCreato: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: immagine,
                                                       formatDescription: attuale, sampleTiming: &tempi,
                                                       sampleBufferOut: &campioneCreato) == noErr,
              let campione = campioneCreato else { return nil }
        mostraSubito(campione)
        return campione
    }

    /// Da mostrare appena arriva, senza orologio di presentazione: è il modo con meno latenza.
    static func mostraSubito(_ campione: CMSampleBuffer) {
        guard let allegati = CMSampleBufferGetSampleAttachmentsArray(campione, createIfNecessary: true),
              CFArrayGetCount(allegati) > 0 else { return }
        let allegato = unsafeBitCast(CFArrayGetValueAtIndex(allegati, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(allegato,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
}

/// La finestra mini (funzione 21): un livello solo per tutti i telefoni, che riceve le immagini già decodificate
/// dello schermo scelto (P21), senza una seconda decodifica e senza aspettare il prossimo fotogramma chiave.
/// Ogni `Schermo` chiama `mostra` dalla sua coda: il lucchetto lascia passare solo la sorgente scelta,
/// così durante un cambio due schermi non mettono mai immagini nel livello insieme.
final class UscitaMini: @unchecked Sendable {
    let livello = AVSampleBufferDisplayLayer()
    private let blocco = NSLock()
    /// Lo schermo che va nella finestra mini; nil a finestra chiusa.
    private var sorgente: ObjectIdentifier?
    private var formato: CMVideoFormatDescription?

    init() {
        livello.videoGravity = .resizeAspect
        livello.backgroundColor = CGColor(gray: 0, alpha: 1)
        livello.masksToBounds = true
    }

    /// Come `Schermo.imposta(riempi:)`, sulla coda principale.
    func imposta(riempi: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        livello.videoGravity = riempi ? .resizeAspectFill : .resizeAspect
        CATransaction.commit()
    }

    /// Quale schermo mostrare; nil = finestra chiusa (o nessun telefono): il livello si svuota.
    /// Cambiando telefono l'ultima immagine resta finché arriva la prima del nuovo (un fotogramma).
    func scegli(_ nuova: ObjectIdentifier?) {
        blocco.lock()
        defer { blocco.unlock() }
        guard nuova != sorgente else { return }
        sorgente = nuova
        if nuova == nil {
            livello.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            formato = nil
        }
    }

    /// Dalla coda di uno `Schermo`: l'immagine appena decodificata, così com'è (YCbCr su IOSurface).
    func mostra(_ immagine: CVPixelBuffer, da: ObjectIdentifier) {
        blocco.lock()
        defer { blocco.unlock() }
        guard da == sorgente, let campione = Schermo.campioneDaMostrare(immagine, descrizione: &formato) else { return }
        if livello.sampleBufferRenderer.status == .failed {
            livello.sampleBufferRenderer.flush()
        }
        livello.sampleBufferRenderer.enqueue(campione)
    }
}

/// Perché la registrazione si è chiusa da sola (M6) e quanto ne resta nel file.
struct InterruzioneRegistrazione: Sendable {
    enum Causa: Sendable {
        /// Altra misura o altri parametri del video (altro obiettivo, qualità, telefono girato).
        case formatoCambiato
        case discoPieno
        /// Un altro errore di scrittura (disco staccato, permessi…).
        case erroreScrittura
    }

    let causa: Causa
    /// Il file è rimasto sul disco e si apre: chiuso bene, o leggibile fino all'ultimo frammento.
    let salvato: Bool
    /// I secondi di video nel file (dopo un errore di scrittura, fino all'ultimo frammento completo).
    let secondi: Int
}

/// Scrive il video in un file .mov. Usato solo sulla coda dello `Schermo`.
/// - Non `elaborato`: i fotogrammi H.264 o HEVC così come arrivano, senza ricomprimerli.
/// - `elaborato` (effetti sul Mac): le immagini già elaborate, ricompresse dal codificatore hardware di macOS.
/// Il .mov è frammentato (`movieFragmentInterval`, punto 4): un crash, uno spegnimento o un disco pieno lasciano
/// un file che si apre fino all'ultimo frammento scritto, non un file senza indice.
private final class Registratore {
    /// Ogni 2 secondi un frammento sul disco: al massimo 2 secondi persi se il file non si chiude.
    static let intervalloFrammenti = CMTime(value: 2, timescale: 1)

    let file: URL
    let elaborato: Bool
    private var scrittore: AVAssetWriter?
    private var ingresso: AVAssetWriterInput?
    private var adattatore: AVAssetWriterInputPixelBufferAdaptor?
    private var formato: CMVideoFormatDescription?
    /// Con `elaborato`: la misura delle immagini del file.
    private var misura: (larghezza: Int, altezza: Int)?
    private var primoTimestamp: UInt64?
    /// L'ultimo istante scritto: AVAssetWriter vuole istanti sempre crescenti, e uno ripetuto lo fa fallire.
    private var ultimoTimestamp: UInt64?

    init(file: URL, elaborato: Bool) {
        self.file = file
        self.elaborato = elaborato
    }

    /// Con `elaborato`. Nil se va tutto bene; altrimenti la registrazione va chiusa, e il perché (la misura cambia
    /// o la scrittura fallisce). `timestamp`: l'istante di cattura del telefono (µs), come per i fotogrammi compressi.
    func aggiungi(immagine: CVPixelBuffer, timestamp: UInt64, hevc: Bool) -> InterruzioneRegistrazione.Causa? {
        let larghezza = CVPixelBufferGetWidth(immagine)
        let altezza = CVPixelBufferGetHeight(immagine)
        if scrittore == nil {
            guard let scrittoreCreato = try? AVAssetWriter(outputURL: file, fileType: .mov) else { return nil }
            scrittoreCreato.movieFragmentInterval = Self.intervalloFrammenti
            // Circa 8 bit per pixel al secondo: 16 Mbit/s a 1080p, 66 a 4K. Colori BT.709 come il flusso del telefono.
            let compressione: [String: Any] = [
                AVVideoAverageBitRateKey: larghezza * altezza * 8,
                AVVideoAllowFrameReorderingKey: false
            ]
            let colori: [String: Any] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
            let impostazioni: [String: Any] = [
                AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
                AVVideoWidthKey: larghezza,
                AVVideoHeightKey: altezza,
                AVVideoCompressionPropertiesKey: compressione,
                AVVideoColorPropertiesKey: colori
            ]
            let ingressoCreato = AVAssetWriterInput(mediaType: .video, outputSettings: impostazioni)
            ingressoCreato.expectsMediaDataInRealTime = true
            guard scrittoreCreato.canAdd(ingressoCreato) else { return nil }
            scrittoreCreato.add(ingressoCreato)
            let adattatoreCreato = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: ingressoCreato,
                                                                        sourcePixelBufferAttributes: nil)
            guard scrittoreCreato.startWriting() else { return nil }
            scrittoreCreato.startSession(atSourceTime: .zero)
            scrittore = scrittoreCreato
            ingresso = ingressoCreato
            adattatore = adattatoreCreato
            misura = (larghezza, altezza)
            primoTimestamp = timestamp
        }
        if scrittore?.status == .failed { return causaErrore() }
        guard let misura, misura.larghezza == larghezza, misura.altezza == altezza else { return .formatoCambiato }
        guard let ingressoAttivo = ingresso, ingressoAttivo.isReadyForMoreMediaData, let adattatore,
              let primo = primoTimestamp, timestamp >= primo,
              ultimoTimestamp.map({ timestamp > $0 }) ?? true else { return nil }
        let istante = CMTime(value: CMTimeValue(truncatingIfNeeded: timestamp - primo), timescale: 1_000_000)
        if adattatore.append(immagine, withPresentationTime: istante) { ultimoTimestamp = timestamp }
        return nil
    }

    /// Nil se va tutto bene; altrimenti la registrazione va chiusa, e il perché (formato cambiato, scrittura fallita).
    func aggiungi(_ campione: CMSampleBuffer, formato nuovo: CMVideoFormatDescription, fotogramma: FotogrammaVideo) -> InterruzioneRegistrazione.Causa? {
        if scrittore == nil {
            // Il file comincia da un fotogramma chiave.
            guard fotogramma.chiave, let scrittoreCreato = try? AVAssetWriter(outputURL: file, fileType: .mov) else { return nil }
            // Frammenti anche così come arriva, senza ricomprimere: il formato della traccia è già noto dal
            // `sourceFormatHint`, che l'intestazione del .mov frammentato vuole fin dall'inizio.
            scrittoreCreato.movieFragmentInterval = Self.intervalloFrammenti
            let ingressoCreato = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: nuovo)
            ingressoCreato.expectsMediaDataInRealTime = true
            guard scrittoreCreato.canAdd(ingressoCreato) else { return nil }
            scrittoreCreato.add(ingressoCreato)
            // Se non parte (per esempio il file esiste già), startSession solleverebbe un'eccezione.
            guard scrittoreCreato.startWriting() else { return nil }
            scrittoreCreato.startSession(atSourceTime: .zero)
            scrittore = scrittoreCreato
            ingresso = ingressoCreato
            formato = nuovo
            primoTimestamp = fotogramma.timestamp
        }
        // Disco pieno o errore di scrittura: lo scrittore non accetta più nulla, la registrazione va chiusa.
        if scrittore?.status == .failed { return causaErrore() }
        guard let formatoFile = formato, CMFormatDescriptionEqual(formatoFile, otherFormatDescription: nuovo) else { return .formatoCambiato }
        guard let ingressoAttivo = ingresso, ingressoAttivo.isReadyForMoreMediaData, let primo = primoTimestamp, fotogramma.timestamp >= primo,
              ultimoTimestamp.map({ fotogramma.timestamp > $0 }) ?? true else { return nil }

        var tempi = CMSampleTimingInfo(duration: .invalid,
                                       presentationTimeStamp: CMTime(value: CMTimeValue(truncatingIfNeeded: fotogramma.timestamp - primo), timescale: 1_000_000),
                                       decodeTimeStamp: .invalid)
        var copiaCreata: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: campione,
                                                    sampleTimingEntryCount: 1, sampleTimingArray: &tempi,
                                                    sampleBufferOut: &copiaCreata) == noErr,
              let copia = copiaCreata else { return nil }
        if ingressoAttivo.append(copia) { ultimoTimestamp = fotogramma.timestamp }
        return nil
    }

    /// I secondi di video scritti finora.
    private var secondiScritti: Int {
        guard let primo = primoTimestamp, let ultimo = ultimoTimestamp, ultimo > primo else { return 0 }
        return Int((ultimo - primo) / 1_000_000)
    }

    /// Dopo un errore di scrittura il file si apre fino all'ultimo frammento completo: i secondi dei frammenti interi.
    private var secondiNeiFrammenti: Int {
        let passo = Int(Self.intervalloFrammenti.value) / Int(Self.intervalloFrammenti.timescale)
        return secondiScritti / passo * passo
    }

    /// Lo scrittore è fallito: disco pieno o un altro errore di scrittura.
    private func causaErrore() -> InterruzioneRegistrazione.Causa {
        var errore = scrittore?.error as NSError?
        while let attuale = errore {
            if (attuale.domain == AVFoundationErrorDomain && attuale.code == AVError.Code.diskFull.rawValue)
                || (attuale.domain == NSPOSIXErrorDomain && attuale.code == Int(ENOSPC))
                || (attuale.domain == NSCocoaErrorDomain && attuale.code == NSFileWriteOutOfSpaceError) {
                return .discoPieno
            }
            errore = attuale.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        // L'errore non lo dice sempre: con meno di 200 MB davvero liberi sul disco del file è il disco pieno.
        var cartella = file.deletingLastPathComponent()
        cartella.removeAllCachedResourceValues()
        if let liberi = try? cartella.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           liberi < 200_000_000 {
            return .discoPieno
        }
        return .erroreScrittura
    }

    /// Ferma e salva (l'utente, l'uscita, il telefono andato via): `completamento` riceve il file, oppure nil se
    /// non c'è niente da tenere. Se intanto la scrittura è fallita, il file resta fino all'ultimo frammento.
    func chiudi(_ completamento: @escaping @Sendable (URL?) -> Void) {
        if scrittore?.status == .failed {
            return completamento(tieniDopoErrore() ? file : nil)
        }
        guard let scrittore, let ingresso, scrittore.status == .writing else { return completamento(nil) }
        ingresso.markAsFinished()
        let file = self.file
        // Se la chiusura fallisce (disco pieno proprio adesso) il file resta leggibile fino all'ultimo frammento: si
        // tiene, come dopo un errore durante la registrazione, e non si dice «niente da salvare».
        let conFrammenti = secondiNeiFrammenti > 0
        scrittore.finishWriting {
            if scrittore.status == .completed { return completamento(file) }
            if !conFrammenti { try? FileManager.default.removeItem(at: file) }
            completamento(conFrammenti ? file : nil)
        }
    }

    /// La registrazione si è chiusa da sola (`causa`): il file si chiude se si può, altrimenti resta fino all'ultimo
    /// frammento. Non si cancella più (punto 5): con il disco pieno si tiene ciò che c'è.
    func chiudi(causa: InterruzioneRegistrazione.Causa, _ completamento: @escaping @Sendable (InterruzioneRegistrazione) -> Void) {
        if scrittore?.status == .failed {
            let secondi = secondiNeiFrammenti
            let salvato = tieniDopoErrore()
            return completamento(InterruzioneRegistrazione(causa: causa, salvato: salvato, secondi: salvato ? secondi : 0))
        }
        let secondi = secondiScritti
        chiudi { fileSalvato in
            completamento(InterruzioneRegistrazione(causa: causa, salvato: fileSalvato != nil, secondi: secondi))
        }
    }

    /// Dopo un errore di scrittura: vero se nel file c'è almeno un frammento completo, che si apre. Altrimenti il
    /// file (solo l'intestazione, che non si apre) si toglie, per non lasciare un .mov vuoto in Filmati.
    /// Mai `cancelWriting`: cancellerebbe anche il file.
    private func tieniDopoErrore() -> Bool {
        let tieni = secondiNeiFrammenti > 0
        if !tieni { try? FileManager.default.removeItem(at: file) }
        scrittore = nil
        ingresso = nil
        adattatore = nil
        return tieni
    }
}
