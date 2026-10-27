import AVFoundation
import Stile
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import WebcamLRProtocollo

/// Schermata «In onda» (bozza grafica, iPhone 3) e schermo oscurato (iPhone 6).
/// La sessione nasce in `SchermataConnessione` quando si sceglie il computer: così la fotocamera
/// e il collegamento si creano una volta sola, anche se SwiftUI ricostruisce questa vista.
///
/// 1.14: sopra il video solo una riga di stato (i numeri sono nei «Dettagli», con un tocco sulla riga) e un avviso
/// alla volta che si chiude da solo. Interfaccia finale: a destra la colonna di pulsanti tondi Specchia · Sfoca
/// sfondo · Microfono · Pausa · Luce (luce sul volto), in alto a destra Impostazioni e Scollega, in basso gli
/// obiettivi con la torcia (solo con gli obiettivi posteriori). In orizzontale, dopo 5 secondi senza tocchi, la
/// «vista pulita»: solo «IN ONDA» e «Tocca per i comandi». Effetti (anche sfondi e logo),
/// inquadratura, assistente e controlli Pro si comandano dal computer (prima prova e sfondi dal computer, 27 ottobre);
/// dalle Impostazioni si apre solo la messa a fuoco manuale, che esiste soltanto sul telefono.
struct SchermataInOnda: View {
    let sessione: SessioneTelefono
    @Environment(\.dismiss) private var chiudi
    @Environment(\.verticalSizeClass) private var classeVerticale
    @State private var zoomIniziale: CGFloat = 1
    /// Griglia dei terzi e livella (round 2), da accendere nelle impostazioni.
    @AppStorage("griglia") private var griglia = false
    @AppStorage("livella") private var livellaAccesa = false
    @State private var livella = Livella()
    /// Oscuramento automatico dopo 30 secondi senza tocchi (round 2), si può spegnere nelle impostazioni.
    @AppStorage("oscuraDaSolo") private var oscuraDaSolo = true
    @State private var compitoOscuramento: Task<Void, Never>? = nil
    /// La risposta che spiega l'errore (1.4), in un foglio.
    @State private var domandaAperta: DomandaDaAprire? = nil
    /// 1.14: i numeri del collegamento e il registro, aperti con un tocco sulla riga di stato.
    @State private var mostraDettagli = false
    /// P03: le Impostazioni anche durante la sessione, in un foglio con «Fine».
    @State private var mostraImpostazioni = false
    /// Il foglio scelto nelle Impostazioni: si apre appena le Impostazioni si sono chiuse.
    @State private var foglioInAttesa: FoglioSessione? = nil
    /// La messa a fuoco lascia toccare «In onda» sotto il foglio: un altro foglio chiesto intanto
    /// (Dettagli, Impostazioni, una risposta) si apre quando quello a metà schermo si è chiuso.
    @State private var dopoIlFoglio: (() -> Void)? = nil
    /// P16: la messa a fuoco manuale (cursore della distanza e «Automatica»), aperta dalle Impostazioni.
    @State private var mostraMessaAFuoco = false
    /// La X chiede conferma prima di scollegare (Ledion, 27 ottobre).
    @State private var confermaScollega = false
    /// Le funzioni del volto (inquadratura, luce, postura, volto e scrivania).
    /// Gli avvisi sopra il video, uno alla volta.
    @State private var avvisi = CodaAvvisi()
    /// Lo zoom si legge al centro solo mentre si pizzica, come nella Fotocamera.
    @State private var zoomVisibile = false
    @State private var compitoZoom: Task<Void, Never>? = nil
    /// Interfaccia finale: in orizzontale i comandi spariscono dopo 5 secondi senza tocchi; un tocco li riporta.
    @State private var vistaPulita = false
    @State private var compitoVistaPulita: Task<Void, Never>? = nil
    private static let secondiPrimaDellaVistaPulita: Duration = .seconds(5)
    /// Seconda prova (bug D): da che parte è l'isola in orizzontale, aggiornato anche da un orizzontale all'altro.
    @State private var lato = LatoDellaTacca()
    /// Seconda prova (bug B): l'altezza della riga in basso (obiettivi), lasciata libera sotto avvisi e pannelli.
    @State private var altezzaInBasso: CGFloat = 54

    var body: some View {
        ZStack {
            // Il nero delle bande attorno al video, come nella Fotocamera: non è un colore dell'interfaccia.
            Color.black.ignoresSafeArea()
            AnteprimaFotocamera(livello: sessione.cattura.anteprima, livelloEffetti: sessione.effetti.anteprima.livello,
                                azioni: azioniAnteprima)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Anteprima della fotocamera")
                .accessibilityHint("Tocca per mettere a fuoco, tieni premuto per bloccare messa a fuoco ed esposizione, tocca due volte per cambiare fotocamera.")
                .accessibilityAction(named: "Cambia fotocamera") { sessione.cambiaFotocamera() }

            sopraIlVideo
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if vistaPulita {
                VistaPulita(puntoColore: colorePuntoStato, testo: testoStatoBreve) {
                    withAnimation(.easeOut(duration: 0.2)) { vistaPulita = false }
                    rimandaVistaPulita()
                }
                .transition(.opacity)
            } else {
                // Bug 4 e seconda prova (bug D): i margini si calcolano qui (`margini`). In verticale la riga in cima
                // sta sotto l'isola (o la tacca), mai accanto; in orizzontale solo il lato dell'isola tiene il
                // margine sicuro, l'altro sta vicino al bordo vero (X e ingranaggio nell'angolo).
                GeometryReader { area in
                    let margini = Self.margini(sicuri: Self.zoneSicure(area.safeAreaInsets), misura: area.size,
                                               taccaASinistra: lato.aSinistra)
                    ZStack(alignment: .bottom) {
                        sovrapposizioni
                            .padding(.leading, margini.leading)
                            .padding(.trailing, margini.trailing)
                        // Bug B: gli obiettivi centrati sull'asse dello schermo (margini uguali ai due lati), non
                        // sulla parte a sinistra della colonna dei comandi. In orizzontale la colonna arriva fin
                        // quaggiù: la riga le lascia il suo spazio, da tutti e due i lati per restare al centro.
                        rigaInBasso
                            .padding(.horizontal, max(margini.leading, margini.trailing)
                                     + (area.size.width > area.size.height ? Self.spazioColonna : 0))
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altezzaInBasso = $0 }
                    }
                    .padding(.top, margini.top)
                    .padding(.bottom, margini.bottom)
                    .frame(width: area.size.width, height: area.size.height)
                }
                .ignoresSafeArea(edges: [.horizontal, .vertical])
                // I testi crescono con la dimensione scelta nel sistema, ma senza coprire tutto il video.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .transition(.opacity)
            }

            // P06: il gobbo in alto, vicino all'obiettivo; sopra i dati ma mai sopra la barra dei comandi.
            if sessione.gobbo.visibile {
                // Seconda prova (bug D): negli stessi margini dei comandi, mai accanto all'isola.
                GeometryReader { area in
                    let margini = Self.margini(sicuri: Self.zoneSicure(area.safeAreaInsets), misura: area.size,
                                               taccaASinistra: lato.aSinistra)
                    posizioneGobbo
                        .padding(.leading, margini.leading)
                        .padding(.trailing, margini.trailing)
                        .padding(.top, margini.top)
                        .padding(.bottom, margini.bottom)
                        .frame(width: area.size.width, height: area.size.height)
                }
                .ignoresSafeArea(edges: [.horizontal, .vertical])
                .transition(.opacity)
            }

            if sessione.oscurato {
                // Su tutto lo schermo: ai lati della tacca e sopra l'indicatore Home un tocco arriverebbe
                // all'anteprima (doppio tocco = cambia fotocamera) invece di riaccendere.
                SchermoOscurato(sessione: sessione)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(item: $domandaAperta, onDismiss: { rimandaOscuramento() }) { domanda in
            FoglioDomande(aperta: domanda.id)
        }
        .sheet(isPresented: $mostraDettagli, onDismiss: { rimandaOscuramento() }) {
            FoglioDettagli(sessione: sessione)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $mostraImpostazioni, onDismiss: {
            // Risoluzione, fotogrammi e formato cambiati: la fotocamera si riconfigura una volta, qui.
            sessione.applicaImpostazioni()
            if let foglio = foglioInAttesa {
                foglioInAttesa = nil
                apri(foglio)
            } else {
                rimandaOscuramento()
            }
        }) {
            NavigationStack {
                SchermataImpostazioni(duranteLaSessione: true, ultimaLatenzaMs: sessione.ultimaLatenzaMs) { foglio in
                    foglioInAttesa = foglio
                    mostraImpostazioni = false
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fine") { mostraImpostazioni = false }
                            .fontWeight(.semibold)
                    }
                }
            }
            .tint(Tema.ciano)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $mostraMessaAFuoco, onDismiss: { chiusoFoglioAMeta() }) {
            FoglioMessaAFuoco(sessione: sessione)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .confirmationDialog("Scollegare il telefono?", isPresented: $confermaScollega, titleVisibility: .visible) {
            Button("Scollega", role: .destructive) { chiudi() }
            Button("Annulla", role: .cancel) { rimandaOscuramento() }
        } message: {
            Text("Il video si ferma e torni alla lista dei computer.")
        }
        .onChange(of: sessione.gobbo.visibile) { _, visibile in
            // Col gobbo lo schermo resta acceso e non si oscura da solo: un testo nuovo riaccende lo schermo.
            if visibile {
                withAnimation { sessione.oscurato = false }
                compitoOscuramento?.cancel()
            } else {
                rimandaOscuramento()
            }
        }
        .onChange(of: livellaAccesa) { _, accesa in
            // Si può accendere dalle Impostazioni aperte da qui.
            if accesa { livella.avvia() } else { livella.ferma() }
        }
        .onChange(of: avvisiAttivi.map(\.id)) { _, _ in
            withAnimation { avvisi.aggiorna(avvisiAttivi) }
        }
        .onChange(of: classeVerticale) { _, _ in controllaVistaPulita() }
        .onChange(of: foglioAperto) { _, _ in controllaVistaPulita() }
        .onChange(of: sessione.stato) { _, _ in controllaVistaPulita() }
        .onChange(of: sessione.codiceConferma) { _, _ in controllaVistaPulita() }
        .onChange(of: avvisi.attuale?.id) { _, _ in controllaVistaPulita() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            controllaVistaPulita()
        }
        .onAppear {
            // La sessione è già partita al tocco su «Collega» (SchermataConnessione), non a fine animazione.
            if livellaAccesa { livella.avvia() }
            lato.avvia()
            rimandaOscuramento()
            avvisi.aggiorna(avvisiAttivi)
        }
        .onDisappear {
            sessione.termina()
            livella.ferma()
            lato.ferma()
            compitoOscuramento?.cancel()
            compitoVistaPulita?.cancel()
            compitoZoom?.cancel()
            avvisi.ferma()
        }
    }

    /// Un foglio scelto nelle Impostazioni, aperto dopo che si sono chiuse.
    private func apri(_ foglio: FoglioSessione) {
        compitoOscuramento?.cancel()
        switch foglio {
        case .messaAFuoco: mostraMessaAFuoco = true
        }
    }

    /// SwiftUI presenta un foglio alla volta: con la messa a fuoco aperta (che lascia toccare i pulsanti
    /// sotto) il nuovo foglio non comparirebbe e il suo stato resterebbe acceso. Prima si chiude quello a metà.
    private func apriSopra(_ apri: @escaping () -> Void) {
        compitoOscuramento?.cancel()
        if mostraMessaAFuoco {
            dopoIlFoglio = apri
            mostraMessaAFuoco = false
        } else {
            apri()
        }
    }

    private func chiusoFoglioAMeta() {
        if let apri = dopoIlFoglio {
            dopoIlFoglio = nil
            apri()
        } else {
            rimandaOscuramento()
        }
    }

    /// Ogni tocco fa ripartire i 30 secondi. Si oscura solo col video che va: davanti a un errore
    /// o durante la riconnessione lo schermo resta acceso. Con VoiceOver non si oscura da solo.
    private func rimandaOscuramento() {
        compitoOscuramento?.cancel()
        rimandaVistaPulita()
        // Con un foglio aperto lo schermo non si oscura sotto il foglio: si riparte alla chiusura.
        guard oscuraDaSolo, !foglioAperto, !sessione.gobbo.visibile else { return }
        compitoOscuramento = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                if sessione.stato == .collegato && !UIAccessibility.isVoiceOverRunning && !sessione.gobbo.visibile {
                    if !sessione.oscurato {
                        withAnimation { sessione.oscurato = true }
                    }
                    return
                }
            }
        }
    }

    private var foglioAperto: Bool {
        mostraImpostazioni || mostraMessaAFuoco || mostraDettagli
            || domandaAperta != nil
    }

    /// Interfaccia finale: in orizzontale, 5 secondi dopo l'ultimo tocco, restano solo «IN ONDA» e «Tocca per i
    /// comandi». Mai con un foglio aperto, con VoiceOver, in verticale, o quando c'è qualcosa da leggere (errore,
    /// codice di conferma, riconnessione, un avviso): allora si ricontrolla ogni secondo.
    private func rimandaVistaPulita() {
        compitoVistaPulita?.cancel()
        compitoVistaPulita = Task { @MainActor in
            try? await Task.sleep(for: Self.secondiPrimaDellaVistaPulita)
            while !Task.isCancelled {
                if vistaPulitaPossibile {
                    withAnimation(.easeOut(duration: 0.35)) { vistaPulita = true }
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var vistaPulitaPossibile: Bool {
        classeVerticale == .compact && !foglioAperto && !UIAccessibility.isVoiceOverRunning
            && sessione.stato == .collegato && sessione.codiceConferma == nil && avvisi.attuale == nil
            && !sessione.oscurato
    }

    /// Un foglio che si apre, VoiceOver, il verticale o un problema riportano subito i comandi.
    private func controllaVistaPulita() {
        if vistaPulita && !vistaPulitaPossibile {
            withAnimation(.easeOut(duration: 0.2)) { vistaPulita = false }
            rimandaVistaPulita()
        }
    }

    /// P06: in verticale il gobbo sta sotto la fotocamera frontale, in alto. In orizzontale l'obiettivo è su un lato:
    /// il gobbo resta in alto ma si stringe verso quel lato (il lato del bordo superiore del telefono).
    private var posizioneGobbo: some View {
        let orizzontale = classeVerticale == .compact
        let fotocameraASinistra = lato.aSinistra
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if orizzontale && !fotocameraASinistra { Spacer(minLength: 0) }
                VistaGobbo(gobbo: sessione.gobbo, righeVisibili: orizzontale ? 3 : 4)
                    .frame(maxWidth: orizzontale ? 560 : .infinity)
                if orizzontale && fotocameraASinistra { Spacer(minLength: 0) }
            }
            Spacer(minLength: 0)
        }
        // La colonna dei comandi a destra resta libera (larghezza della colonna e spazio). I margini sicuri li
        // mette chi la contiene (`margini`). Sotto la riga in cima: la X del gobbo non finisce accanto (o sopra)
        // all'ingranaggio e alla X di «Scollega», e il tocco sul gobbo non copre le Impostazioni.
        .padding(.top, Self.altezzaRigaInAlto)
        .padding(.trailing, Self.spazioColonna)
    }

    /// Tocco, doppio tocco, tocco lungo e pizzico sull'anteprima (gesti UIKit, vedi `AnteprimaFotocamera`).
    private var azioniAnteprima: AzioniAnteprima {
        AzioniAnteprima(
            tocco: { punto in sessione.metteAFuoco(punto) },
            doppioTocco: { sessione.cambiaFotocamera() },
            toccoLungo: { punto in sessione.bloccaFuocoEdEsposizione(punto) },
            pizzico: { inizio, scala in
                if inizio { zoomIniziale = sessione.zoom }
                sessione.impostaZoom(zoomIniziale * scala)
                mostraZoom()
            },
            qualsiasiTocco: { rimandaOscuramento() }
        )
    }

    /// Lo zoom al centro mentre si pizzica; sparisce poco dopo l'ultimo movimento.
    private func mostraZoom() {
        if !zoomVisibile { zoomVisibile = true }
        compitoZoom?.cancel()
        compitoZoom = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if Task.isCancelled { return }
            withAnimation { zoomVisibile = false }
        }
    }

    // MARK: - Sopra il video

    /// Griglia, livella, riquadro del fuoco e zoom sul video come si vede: dalla seconda prova (bug E) l'anteprima
    /// riempie lo schermo (`resizeAspectFill`), quindi il rettangolo del video può uscire dallo schermo. La griglia
    /// divide il video vero (che il computer riceve intero); il riquadro del fuoco resta nella parte visibile.
    private var sopraIlVideo: some View {
        GeometryReader { area in
            let video = Self.rettangoloVideo(in: area.size, video: sessione.dimensioniVideo)
            let visibile = video.intersection(CGRect(origin: .zero, size: area.size))
            ZStack(alignment: .topLeading) {
                if griglia {
                    GrigliaTerzi()
                        .frame(width: video.width, height: video.height)
                        .position(x: video.midX, y: video.midY)
                }
                if livellaAccesa {
                    LineaLivella(livella: livella)
                        .position(x: video.midX, y: video.midY)
                }
                if let punto = sessione.puntoFuoco {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Tema.ambra, lineWidth: 2)
                        .frame(width: 84, height: 84)
                        .position(Self.dentro(visibile.isNull ? video : visibile, punto: punto, margine: 42))
                }
                if zoomVisibile {
                    Text(verbatim: Double(sessione.zoom).formatted(.number.precision(.fractionLength(1))) + "×")
                        .font(.numeriEvidenti(17))
                        .foregroundStyle(Tema.testo)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Tema.fondo.opacity(0.78), in: Capsule())
                        .position(x: video.midX, y: video.midY)
                        .transition(.opacity)
                }
            }
            .frame(width: area.size.width, height: area.size.height)
            .clipped()
        }
    }

    /// Il rettangolo del video che riempie l'area (come `resizeAspectFill` dei livelli di anteprima): può uscire
    /// dall'area da due lati. Senza misure, tutta l'area.
    static func rettangoloVideo(in area: CGSize, video: CGSize) -> CGRect {
        guard video.width > 0, video.height > 0, area.width > 0, area.height > 0 else {
            return CGRect(origin: .zero, size: area)
        }
        let scala = max(area.width / video.width, area.height / video.height)
        let misura = CGSize(width: video.width * scala, height: video.height * scala)
        return CGRect(x: (area.width - misura.width) / 2, y: (area.height - misura.height) / 2,
                      width: misura.width, height: misura.height)
    }

    /// Il punto spostato quanto basta perché un riquadro di mezzo lato `margine` resti dentro il rettangolo.
    static func dentro(_ rettangolo: CGRect, punto: CGPoint, margine: CGFloat) -> CGPoint {
        let interno = rettangolo.insetBy(dx: min(margine, rettangolo.width / 2), dy: min(margine, rettangolo.height / 2))
        return CGPoint(x: min(max(punto.x, interno.minX), interno.maxX),
                       y: min(max(punto.y, interno.minY), interno.maxY))
    }

    // MARK: - Sovrapposizioni

    /// Interfaccia finale: in cima la riga di stato a sinistra e Impostazioni e Scollega nell'angolo in alto a destra
    /// (bug 4: la riga in cima prende tutta la larghezza; prima stava nella colonna di sinistra e i due pulsanti
    /// finivano a metà schermo, accanto alla colonna dei comandi). Sotto: a sinistra gli avvisi e i pannelli; a
    /// destra, a metà altezza, la colonna dei pulsanti tondi. Gli obiettivi in basso sono a parte (`rigaInBasso`),
    /// centrati sullo schermo. Uguale in verticale e in orizzontale.
    private var sovrapposizioni: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                rigaStato
                Spacer(minLength: 8)
                pulsantiInAlto
            }
            HStack(alignment: .top, spacing: 12) {
                contenutoSinistra
                colonnaComandi
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Lo spazio della colonna dei comandi a destra: la colonna (pulsanti da 48 e 8 di bordo per lato) e 12 di
    /// distanza. Il gobbo e, in orizzontale, la riga in basso lo lasciano libero.
    static let spazioColonna: CGFloat = 76

    /// L'altezza della riga in cima (pulsanti da 44) con lo spazio sotto: il gobbo comincia qui.
    static let altezzaRigaInAlto: CGFloat = 52

    /// Seconda prova (bug D): i margini di comandi e scritte, dentro le zone sicure vere.
    /// - In verticale la riga in cima sta sotto l'isola (o la tacca), mai accanto, con 10 punti di respiro; ai lati
    ///   12 punti. Con la barra di stato nascosta il margine alto potrebbe arrivare più basso dell'isola: sugli
    ///   iPhone con l'isola o la tacca (quelli con l'indicatore Home, margine in basso maggiore di 0) vale almeno 59.
    /// - In orizzontale (bug 4) il lato dell'isola tiene il margine sicuro (almeno 59), l'altro non ha nulla da
    ///   evitare e sta a 16 punti dal bordo. In basso sempre sopra l'indicatore Home.
    static func margini(sicuri: EdgeInsets, misura: CGSize, taccaASinistra: Bool) -> EdgeInsets {
        let minimoIsola: CGFloat = sicuri.bottom > 0 ? 59 : 0
        if misura.height >= misura.width {
            return EdgeInsets(top: max(sicuri.top, minimoIsola) + 10, leading: 12,
                              bottom: sicuri.bottom + 10, trailing: 12)
        }
        let latoIsola = max(taccaASinistra ? sicuri.leading : sicuri.trailing, minimoIsola, 12)
        return EdgeInsets(top: sicuri.top + 10, leading: taccaASinistra ? latoIsola : 16,
                          bottom: sicuri.bottom + 10, trailing: taccaASinistra ? 16 : latoIsola)
    }

    /// Terza prova (punto D): le zone sicure vere, lette dalla finestra. Le viste qui sopra ignorano le zone sicure
    /// (`ignoresSafeArea`), quindi il loro `GeometryReader` riceve margini a 0: la riga in cima finiva accanto
    /// all'isola, tagliata, e il minimo di 59 non scattava (si basava sul margine in basso, anche lui 0). La finestra
    /// li conosce sempre, anche con la barra di stato nascosta. Lato per lato il più grande dei due.
    @MainActor
    static func zoneSicure(_ vista: EdgeInsets) -> EdgeInsets {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let finestre = scene.flatMap { $0.windows }
        guard let finestra = finestre.first(where: { $0.isKeyWindow }) ?? finestre.first else { return vista }
        let margini = finestra.safeAreaInsets
        return EdgeInsets(top: max(vista.top, margini.top), leading: max(vista.leading, margini.left),
                          bottom: max(vista.bottom, margini.bottom), trailing: max(vista.trailing, margini.right))
    }

    /// Riga in alto «ai lati dell'isola» (struttura B, Ledion 27 ottobre): le due «orecchie» accanto all'isola o
    /// alla tacca, dove iOS mette l'ora e la batteria.
    struct Orecchie: Equatable {
        /// La larghezza utile di ogni orecchia, già senza i margini.
        var larghezza: CGFloat
        /// Il centro verticale dell'isola (o della tacca), dal bordo in alto dello schermo.
        var centro: CGFloat
    }

    /// Dal bordo dello schermo all'orecchia e dall'orecchia all'isola.
    static let margineEsternoOrecchie: CGFloat = 12
    static let margineIsola: CGFloat = 6
    /// Ingranaggio e X con l'area di tocco di 44 punti ciascuno, uno accanto all'altro.
    static let larghezzaPulsantiOrecchia: CGFloat = 88

    /// Le orecchie, solo in verticale e solo sugli iPhone con l'isola o la tacca in alto al centro; `nil` altrove
    /// (iPhone SE, orizzontale) e quando l'ingranaggio e la X non ci stanno con la loro area di tocco: allora resta
    /// la riga di sempre, sotto l'isola. Le misure dell'isola non si possono leggere: si stimano dal margine sicuro
    /// in alto (dalla finestra, `zoneSicure`). Da 59 punti in su l'isola, circa 126 × 37 a 11 punti dal bordo; da 44
    /// a 58 la tacca dei modelli più vecchi, circa 210 punti, centrata a metà del margine.
    static func orecchie(sicuri: EdgeInsets, misura: CGSize) -> Orecchie? {
        guard misura.height > misura.width else { return nil }
        let isola: CGFloat
        let centro: CGFloat
        if sicuri.top >= 59 {
            isola = 126
            centro = 11 + 37 / 2
        } else if sicuri.top >= 44 {
            isola = 210
            centro = sicuri.top / 2
        } else {
            return nil
        }
        let larghezza = (misura.width - isola) / 2 - margineEsternoOrecchie - margineIsola
        guard larghezza >= larghezzaPulsantiOrecchia else { return nil }
        return Orecchie(larghezza: larghezza, centro: centro)
    }

    /// Sotto la riga in cima, a sinistra della colonna dei comandi.
    private var contenutoSinistra: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sessione.aeafBloccati {
                // Come nella Fotocamera: si sblocca con un tocco.
                Text("AE/AF bloccati")
                    .font(.etichetta(15))
                    .tracking(0.6)
                    .foregroundStyle(Tema.fondo)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 26)
                    .background(Tema.ambra, in: Capsule())
                    .accessibilityLabel("AE/AF bloccati: messa a fuoco ed esposizione restano ferme. Tocca l'anteprima per sbloccarle.")
            }
            // Un avviso alla volta; il promemoria della postura solo quando non ce n'è un altro.
            if let avviso = avvisi.attuale {
                vistaAvviso(avviso)
                    .id(avviso.id)
                    .transition(.opacity)
            } else {
                BannerPostura(sessione: sessione)
            }
            // P07, P10 e il pulsante «Pausa»: uno stato vero, resta finché dura.
            BannerPausa(sessione: sessione)
            Spacer()
            // Con VoiceOver errore, codice e riconnessione si leggono per primi: dicono cosa fare.
            if case .errore(let descrizione) = sessione.stato {
                pannelloErrore(descrizione)
                    .accessibilitySortPriority(2)
            }
            if let codice = sessione.codiceConferma {
                pannelloConferma(codice)
                    .accessibilitySortPriority(2)
            } else if let inizio = inizioRiconnessioneVisibile {
                bannerRiconnessione(da: inizio)
                    .accessibilitySortPriority(1)
            }
            Spacer()
        }
        // La riga in basso (`rigaInBasso`) sta sopra, a tutta larghezza: qui il suo spazio resta libero.
        .padding(.bottom, altezzaInBasso + 8)
        // Terza prova (punto D): tutta la larghezza libera, così la colonna dei comandi sta sempre a destra. Senza,
        // con nessun avviso questa colonna era larga 0 e i pulsanti tondi finivano a sinistra.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Seconda prova (bug B): in fondo, centrati sull'asse dello schermo, «Usa questa prospettiva» (con più
    /// telefoni) e gli obiettivi con la torcia.
    private var rigaInBasso: some View {
        VStack(spacing: 8) {
            if sessione.prontaCam2 {
                pulsanteUsaProspettiva
            }
            SelettoreObiettivo(sessione: sessione)
        }
        .frame(maxWidth: .infinity)
    }

    /// Una riga sola: «● Collegato · MacBook» (o «● In onda», col punto corallo solo allora), il collegamento e le
    /// tacche della qualità. Un tocco apre i «Dettagli». Se il nome non ci sta, resta «Collegato»: mai troncato.
    private var rigaStato: some View {
        Button {
            apriSopra { mostraDettagli = true }
        } label: {
            // Con il testo grande o sugli iPhone stretti si toglie prima il nome, poi «Wi-Fi»/«USB»: la pillola non
            // spinge mai l'ingranaggio e la X fuori dallo schermo.
            ViewThatFits(in: .horizontal) {
                contenutoStato(testoStato, conStrada: true)
                contenutoStato(testoStatoBreve, conStrada: true)
                contenutoStato(testoStatoBreve, conStrada: false)
            }
            .foregroundStyle(Tema.testo)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Tema.fondo.opacity(0.78), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etichettaStato)
        .accessibilityHint("Mostra i dettagli del collegamento")
    }

    /// Il punto, lo stato e, da collegati, la strada e le tacche della qualità.
    private func contenutoStato(_ testo: String, conStrada: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorePuntoStato)
                .frame(width: 8, height: 8)
            Text(testo)
                .font(.etichetta(16))
                .tracking(0.6)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
            if sessione.stato == .collegato {
                // Bug 8: accanto a «Collegato» / «In onda» la strada, in parola: «Wi-Fi» o «USB».
                if conStrada, let tipo = tipoVisibile {
                    HStack(spacing: 4) {
                        Image(systemName: tipo.simbolo)
                            .font(.system(size: 11, weight: .semibold))
                        Text(verbatim: "· " + tipo.testoBreve)
                            .fixedSize()
                    }
                    .font(.etichetta(16))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Tema.testoSecondario)
                }
                if sessione.latenzaMs != nil {
                    TaccheQualita(qualita: qualita)
                }
            }
        }
    }

    /// Con più telefoni, su quello che non è nella webcam (interfaccia finale, «Due telefoni»): grande, in basso,
    /// nell'accento salvia. La scelta si vede solo quando il computer manda il nuovo `in-onda`.
    private var pulsanteUsaProspettiva: some View {
        Button {
            sessione.usaProspettiva()
            rimandaOscuramento()
        } label: {
            Text("Usa questa prospettiva")
                .font(.corpoForte(17))
                .foregroundStyle(Tema.fondo)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .frame(maxWidth: 520, minHeight: 60)
                .background(Tema.accento, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityHint(Text("Sul computer va in onda l'altro telefono: passa a questo"))
    }

    /// Bug 8: la strada da dire nella riga di stato. Sul cavo si sa anche prima che il percorso lo confermi.
    private var tipoVisibile: TipoCollegamento? {
        sessione.tipoCollegamento ?? (sessione.viaCavo ? .cavoUSB : nil)
    }

    /// Per VoiceOver: lo stato, la strada e, se si sa, la qualità.
    private var etichettaStato: String {
        guard sessione.stato == .collegato else { return testoStato }
        let conStrada = tipoVisibile.map { "\(testoStato), \($0.testo)" } ?? testoStato
        guard sessione.latenzaMs != nil else { return conStrada }
        return String(localized: "\(conStrada), collegamento \(qualita.testo.lowercased())")
    }

    private var colorePuntoStato: Color {
        switch sessione.stato {
        // Con più telefoni, quello che non è nella webcam: salvia, mai corallo.
        case .collegato where sessione.prontaCam2: Tema.accento
        // Il corallo solo quando un'app usa davvero la webcam.
        case .collegato where sessione.inOnda != nil: Tema.tally
        case .collegato: Tema.verde
        case .collegamento, .riconnessione: Tema.ambra
        case .chiusa, .errore: Tema.testoTenue
        }
    }

    private var testoStato: String {
        switch sessione.stato {
        case .collegato where sessione.prontaCam2: String(localized: "Pronta · CAM 2")
        case .collegato where sessione.inOnda != nil:
            sessione.inOnda?.app.map { String(localized: "In onda · \($0)") } ?? String(localized: "In onda")
        case .collegato: String(localized: "Collegato · \(sessione.computer.nome)")
        case .collegamento: String(localized: "Collegamento…")
        case .riconnessione(let tentativo):
            sessione.inAttesaDelComputer ? String(localized: "In attesa")
                : sessione.viaCavo || sessione.daCavoAlWiFi ? String(localized: "Riconnessione")
                : String(localized: "Riconnessione \(tentativo)/\(SessioneTelefono.tentativiMassimi)")
        case .chiusa, .errore: String(localized: "Scollegato")
        }
    }

    /// Quando il testo intero non ci sta: senza il nome del computer o dell'app.
    private var testoStatoBreve: String {
        switch sessione.stato {
        case .collegato where sessione.prontaCam2: String(localized: "Pronta · CAM 2")
        case .collegato where sessione.inOnda != nil: String(localized: "In onda")
        case .collegato: String(localized: "Collegato")
        case .riconnessione: String(localized: "Riconnessione")
        default: testoStato
        }
    }

    /// Stesse soglie di Mac e Windows (Stile `QualitaCollegamento`), con i fotogrammi scartati dal telefono.
    private var qualita: QualitaCollegamento {
        QualitaCollegamento(latenzaMs: sessione.latenzaMs ?? 0, perdite: sessione.perditeRecenti)
    }

    // MARK: - Avvisi

    /// Le condizioni da dire adesso, una per argomento. La coda le mostra una alla volta, senza ripetersi.
    private var avvisiAttivi: [CodaAvvisi.Avviso] {
        guard sessione.stato == .collegato else { return [] }
        var elenco: [CodaAvvisi.Avviso] = []
        if let avviso = sessione.avvisoMicrofono {
            elenco.append(.init(id: "microfono", testo: avviso, icona: "mic.slash", tipo: .avviso, priorita: 5))
        }
        if sessione.qualitaRidotta {
            elenco.append(.init(id: "caldo", testo: String(localized: "Telefono molto caldo: qualità ridotta finché si raffredda"),
                                icona: "thermometer.high", tipo: .avviso, priorita: 4))
        }
        if sessione.batteriaBassa {
            let testo = sessione.risparmioBatteria
                ? String(localized: "Batteria al \(sessione.batteria)%: 24 fps per risparmiare, collega il caricatore")
                : String(localized: "Batteria al \(sessione.batteria)%: collega il caricatore")
            elenco.append(.init(id: "batteria", testo: testo, icona: "battery.25", tipo: .avviso, priorita: 4))
        }
        if let rete = testoRete {
            elenco.append(.init(id: "rete", testo: rete, icona: "wifi.exclamationmark", tipo: .avviso, priorita: 3))
        }
        // Seconda prova (bug E): l'anteprima riempie lo schermo e taglia i bordi; lo si dice una volta per sessione.
        elenco.append(.init(id: "ritaglio", testo: String(localized: "L'anteprima riempie lo schermo e taglia i bordi: al computer arriva il video intero."),
                            icona: "crop", tipo: .suggerimento, priorita: 2))
        if classeVerticale == .regular {
            elenco.append(.init(id: "orizzontale", testo: String(localized: "Gira l'iPhone in orizzontale per un'inquadratura larga"),
                                icona: "rectangle.landscape.rotate", tipo: .suggerimento, priorita: 1))
        }
        return elenco
    }

    /// Rete lenta e consiglio del cavo in una frase sola (1.2): mai due avvisi sulla stessa cosa.
    private var testoRete: String? {
        let consiglio = sessione.tipoCollegamento?.consiglioSeDebole
        if sessione.reteDebole {
            if let consiglio { return String(localized: "Rete lenta: qualità abbassata da sola. \(consiglio).") }
            return String(localized: "Rete lenta: qualità abbassata da sola")
        }
        if sessione.latenzaMs != nil, qualita == .debole, let consiglio { return consiglio }
        return nil
    }

    private func vistaAvviso(_ avviso: CodaAvvisi.Avviso) -> some View {
        Button {
            withAnimation { avvisi.chiudi() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: avviso.icona)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(avviso.tipo == .avviso ? Tema.ambraTesto : Tema.cianoChiaro)
                    .accessibilityHidden(true)
                Text(avviso.testo)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Tema.testo)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Tema.pannello.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tocca per chiudere")
    }

    // MARK: - Colonna dei comandi

    /// Interfaccia finale: cinque pulsanti tondi a destra, a metà altezza (Specchia · Sfoca sfondo · Microfono ·
    /// Pausa · Luce). Sugli iPhone più bassi in orizzontale, o con il testo molto grande, la colonna scorre.
    private var colonnaComandi: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ViewThatFits(in: .vertical) {
                pulsantiColonna
                ScrollView(.vertical, showsIndicators: false) { pulsantiColonna }
            }
            .background(Tema.fondo.opacity(0.75), in: RoundedRectangle(cornerRadius: 32))
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    /// Acceso con la sfocatura e anche con uno sfondo sostituito (scelto dal computer): un tocco lo spegne.
    /// Terza prova (punto F): con la posteriore lo sfondo è spento e il pulsante grigio.
    private var sfondoAcceso: Bool { sessione.visivi.sfondoEffettivo != ModiSfondo.nessuno }
    private var inPausa: Bool { sessione.pausa.utente }
    private var luceAccesa: Bool { sessione.funzioni.luceVolto }

    private var pulsantiColonna: some View {
        VStack(spacing: 8) {
            // Specchia il video che arriva al computer, subito; nell'accento quando è acceso.
            // Terza prova (punto E): solo con la frontale; con la posteriore è grigio e spento.
            PulsanteTondo(String(localized: "Specchia"), icona: "flip.horizontal", attivo: sessione.specchioEffettivo) {
                sessione.impostaSpecchio(!sessione.specchiato)
            }
            .disabled(!sessione.conFrontale)
            .opacity(sessione.conFrontale ? 1 : 0.4)
            .accessibilityValue(sessione.specchioEffettivo ? "acceso" : "spento")
            .accessibilityHint("Specchia il video che arriva al computer")
            // Un tocco: sfocato o niente, con l'intensità scelta dal computer (gratis). Con uno sfondo sostituito,
            // scelto dal computer, il pulsante è acceso e un tocco spegne lo sfondo.
            PulsanteTondo(String(localized: "Sfoca sfondo"), icona: "person.and.background.dotted", attivo: sfondoAcceso) {
                sessione.visivi.scegliSfondo(sfondoAcceso ? ModiSfondo.nessuno : ModiSfondo.sfocato)
            }
            .disabled(!sessione.conFrontale)
            .opacity(sessione.conFrontale ? 1 : 0.4)
            .accessibilityValue(sfondoAcceso ? "acceso" : "spento")
            // P20: il microfono del telefono verso il computer, nell'accento quando è chiesto.
            PulsanteTondo(String(localized: "Microfono al computer"), icona: sessione.audioRichiesto ? "mic.fill" : "mic.slash",
                          attivo: sessione.audioRichiesto) {
                sessione.impostaAudio(!sessione.audioRichiesto)
            }
            .accessibilityValue(sessione.audioRichiesto ? "acceso" : "spento")
            .accessibilityHint("Manda l'audio del microfono dell'iPhone al computer")
            // Il video si ferma, il collegamento resta (come a faccia in giù).
            PulsanteTondo(inPausa ? String(localized: "Riprendi") : String(localized: "Pausa"),
                          icona: inPausa ? "play.fill" : "pause.fill", attivo: inPausa) {
                sessione.pausa.impostaPausaUtente(!inPausa)
            }
            // P08: la luce sul volto (gratis), la stessa del computer: luce ad anello virtuale nel video (bug 5)
            // ed esposizione sul volto.
            PulsanteTondo(String(localized: "Luce sul volto"), icona: luceAccesa ? "sun.max.fill" : "sun.max",
                          attivo: luceAccesa) {
                sessione.funzioni.impostaLuceVolto(!luceAccesa)
            }
            .accessibilityValue(luceAccesa ? "accesa" : "spenta")
            .accessibilityHint("Schiarisce il volto come una luce ad anello, anche con una finestra alle spalle")
        }
        .padding(8)
    }

    /// In alto a destra, piccoli: le Impostazioni del telefono (WebcamLR Pro in cima) e Scollega.
    private var pulsantiInAlto: some View {
        HStack(spacing: 8) {
            pulsantePiccolo(icona: "gearshape", attivo: controlliManuali) {
                apriSopra { mostraImpostazioni = true }
            }
            .accessibilityLabel("Impostazioni")
            .accessibilityHint("WebcamLR Pro, video, fotocamera e collegamento")
            pulsantePiccolo(icona: "xmark", attivo: false) {
                // Con la messa a fuoco aperta (si tocca anche sotto) prima si chiude il foglio: altrimenti
                // resterebbe aperto sopra la lista dei computer, su una sessione già chiusa.
                apriSopra { confermaScollega = true }
            }
            .accessibilityLabel("Scollega")
        }
    }

    private func pulsantePiccolo(icona: String, attivo: Bool, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Image(systemName: icona)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(attivo ? Tema.cianoChiaro : Tema.testo)
                .frame(width: 42, height: 42)
                .background(attivo ? Tema.cianoTenue : Tema.fondo.opacity(0.8), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
    }

    /// P16: almeno un valore della fotocamera è scelto a mano (dal telefono o dal computer): le Impostazioni,
    /// da cui si apre la messa a fuoco manuale, restano nell'accento.
    private var controlliManuali: Bool {
        sessione.iso > 0 || sessione.tempo > 0 || sessione.bianco > 0 || sessione.esposizione != 0
            || sessione.posizioneFuoco != nil
    }

    // MARK: - Riconnessione, conferma, errore

    /// Il banner compare mentre si ritrova il computer perso, anche dopo «Riprova ora».
    private var inizioRiconnessioneVisibile: Date? {
        switch sessione.stato {
        case .riconnessione, .collegamento: sessione.inizioRiconnessione
        case .collegato, .chiusa, .errore: nil
        }
    }

    /// Riconnessione chiara (round 2): da quanti secondi si cerca il computer, e «Riprova ora».
    private func bannerRiconnessione(da inizio: Date) -> some View {
        // 1.12: in attesa di un computer fidato il banner è calmo: niente secondi che corrono, colori neutri.
        let attesa = sessione.inAttesaDelComputer
        return HStack(spacing: 12) {
            ProgressView()
                .tint(attesa ? Tema.ciano : Tema.ambraTesto)
            if attesa {
                VStack(alignment: .leading, spacing: 2) {
                    Text(testoRiconnessione)
                        .font(.subheadline.weight(.semibold))
                    Text(sottotitoloAttesa)
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Tema.testo)
            } else {
                TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                    let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(testoRiconnessione)
                            .font(.subheadline.weight(.semibold))
                        Text(secondi == 1 ? "da 1 secondo" : "da \(secondi) secondi")
                            .font(.numeri(12.5))
                    }
                    .foregroundStyle(Tema.ambraTesto)
                }
            }
            Spacer(minLength: 8)
            // Sul cavo è il computer a riaprire la connessione: riprovare da qui non serve.
            if !sessione.viaCavo {
                Button("Riprova ora") { sessione.riprova() }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Tema.ciano, in: Capsule())
                    .foregroundStyle(Tema.fondo)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(attesa ? Tema.pannello.opacity(0.95) : Tema.ambraTenue.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    /// 1.12: cosa succede mentre si aspetta il computer, e cosa può fare l'utente.
    private var sottotitoloAttesa: String {
        if StatoRete.condiviso.senzaReteLocale {
            return String(localized: "Collega l'iPhone alla stessa rete Wi-Fi del computer: riparto da solo.")
        }
        if sessione.soloAlRitorno {
            return String(localized: "Il computer ha chiuso il collegamento: riparto da solo quando WebcamLR si riapre, oppure tocca «Riprova ora».")
        }
        return String(localized: "Riparto da solo appena WebcamLR è aperto sul computer.")
    }

    /// Se non ci si è mai collegati il computer non è «perso». Sul cavo (1.6) la rete non conta.
    private var testoRiconnessione: String {
        if sessione.viaCavo {
            return sessione.giaCollegato
                ? String(localized: "Cavo scollegato? Riparto appena il computer risponde…")
                : String(localized: "Aspetto il computer sul cavo USB…")
        }
        // Interfaccia finale: preferenza «Wi-Fi» mentre si era sul cavo: si passa al Wi-Fi di proposito.
        if sessione.versoIlWiFi {
            return String(localized: "Passo al Wi-Fi…")
        }
        // 1.9: il cavo si è staccato in una sessione nata in Wi-Fi: si prova il Wi-Fi, il cavo può tornare.
        if sessione.daCavoAlWiFi {
            return sessione.reteDisponibile
                ? String(localized: "Cavo scollegato: provo il Wi-Fi…")
                : String(localized: "Cavo scollegato e nessuna rete: ricollega il cavo…")
        }
        if !sessione.reteDisponibile { return String(localized: "Nessuna rete: mi ricollego appena torna il Wi-Fi…") }
        if sessione.inAttesaDelComputer { return String(localized: "In attesa di «\(sessione.computer.nome)»…") }
        return sessione.giaCollegato
            ? String(localized: "Computer perso, mi ricollego…")
            : String(localized: "Non riesco a collegarmi a \(sessione.computer.nome), riprovo…")
    }

    /// Prima volta con questo computer (0.10): lo stesso codice di conferma compare sul computer,
    /// che chiede «Consentire l'iPhone di …?». Si aspetta finché l'utente non risponde.
    private func pannelloConferma(_ codice: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(Tema.ciano)
                    .accessibilityHidden(true)
                Text("Conferma sul computer")
                    .font(.titolo(28))
            }
            // Via cavo il nome del computer arriva solo dopo la conferma (1.6).
            Text(sessione.viaCavo
                 ? "Sul computer consenti questo iPhone, se il codice di conferma è lo stesso:"
                 : "Su \(sessione.computer.nome) consenti questo iPhone, se il codice di conferma è lo stesso:")
                .font(.subheadline)
                .foregroundStyle(Tema.testoChiaro)
                .fixedSize(horizontal: false, vertical: true)
            Text(codice)
                .font(.numeriEvidenti(46))
                .tracking(10)
                .foregroundStyle(Tema.testo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 12))
                // VoiceOver legge le cifre una per una.
                .accessibilityLabel("Codice di conferma \(codice.map { String($0) }.joined(separator: " "))")
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Tema.ciano)
                Text("Aspetto la risposta, fino a un minuto")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
        }
        .padding(18)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Tema.fondo.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Tema.ciano))
        .foregroundStyle(Tema.testo)
        .accessibilityElement(children: .combine)
    }

    private func pannelloErrore(_ descrizione: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sessione.titoloErrore)
                .font(.titolo(24))
            Text(descrizione)
                .font(.subheadline)
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
            if let diagnosi = sessione.diagnosi {
                // 1.3: l'azione della diagnosi (per esempio «Apri Impostazioni») e la risposta.
                AzioniDiagnosi(diagnosi: diagnosi) { domanda in apriSopra { domandaAperta = DomandaDaAprire(id: domanda) } }
            } else if let domanda = sessione.domandaErrore {
                Button("Perché succede?") { apriSopra { domandaAperta = DomandaDaAprire(id: domanda) } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tema.cianoChiaro)
            }
            // Sugli iPhone piccoli o con il testo grande i due pulsanti vanno uno sotto l'altro, senza troncare.
            ViewThatFits(in: .horizontal) {
                HStack { pulsantiErrore }
                VStack(alignment: .leading, spacing: 8) { pulsantiErrore }
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Tema.fondo.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Tema.testo)
    }

    @ViewBuilder private var pulsantiErrore: some View {
        // Identità cambiata: riprovare non serve, si riabbina con il QR code dalla lista dei computer.
        if !sessione.erroreDefinitivo {
            Button("Riprova") { sessione.riprova() }
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Tema.ciano, in: Capsule())
                .foregroundStyle(Tema.fondo)
        }
        Button("Torna ai computer") { apriSopra { chiudi() } }
            .fontWeight(.semibold)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
    }
}

extension Codec {
    /// Come in Impostazioni › Formato.
    var nome: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        }
    }
}

extension Temperatura {
    var descrizione: String {
        switch self {
        case .normale: String(localized: "normale")
        case .calda: String(localized: "calda")
        case .moltoCalda: String(localized: "molto calda")
        case .critica: String(localized: "critica")
        }
    }
}

extension Obiettivo {
    /// Per VoiceOver: «0,5×» o «Tele» da soli non dicono molto.
    var nomeAccessibile: String {
        switch self {
        case .grandangolo: String(localized: "Grandangolo 0,5×")
        case .principale: String(localized: "Principale 1×")
        case .tele: String(localized: "Teleobiettivo")
        case .frontale: String(localized: "Fotocamera frontale")
        }
    }
}

/// Le tre tacche della qualità, senza parola: nella riga di stato basta il colore (la parola è nei Dettagli).
private struct TaccheQualita: View {
    let qualita: QualitaCollegamento

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { indice in
                RoundedRectangle(cornerRadius: 1)
                    .fill(indice < qualita.tacche ? qualita.colore : Tema.linea)
                    .frame(width: 3, height: CGFloat(5 + indice * 3))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Seconda prova (bug D): da che parte è l'isola (o la tacca) quando il telefono è in orizzontale. Passando da un
/// orizzontale all'altro le misure e i margini sicuri non cambiano (in orizzontale sono uguali ai due lati), quindi
/// SwiftUI non ridisegnava e i comandi restavano accanto all'isola: qui si segue l'orientamento della scena.
@Observable
@MainActor
final class LatoDellaTacca {
    /// `landscapeRight`: il tasto laterale in alto, l'isola a sinistra. In verticale non conta.
    private(set) var aSinistra = false
    @ObservationIgnored private var osservazione: NSKeyValueObservation?

    func avvia() {
        guard osservazione == nil,
              let scena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        aggiorna(scena.effectiveGeometry.interfaceOrientation)
        // `effectiveGeometry` cambia (sul thread principale) a ogni rotazione dell'interfaccia.
        osservazione = scena.observe(\.effectiveGeometry, options: [.new]) { [weak self] scena, _ in
            MainActor.assumeIsolated {
                self?.aggiorna(scena.effectiveGeometry.interfaceOrientation)
            }
        }
    }

    func ferma() {
        osservazione?.invalidate()
        osservazione = nil
    }

    private func aggiorna(_ orientamento: UIInterfaceOrientation) {
        let nuovo = orientamento == .landscapeRight
        if nuovo != aSinistra { aSinistra = nuovo }
    }
}

/// Gli avvisi sopra il video, uno alla volta (1.14). Ogni avviso ha un argomento (`id`): mai due sulla stessa
/// cosa. Si chiude da solo dopo 6 secondi o con un tocco. Un suggerimento si vede una volta per sessione; un
/// avviso torna solo se la sua condizione è finita e poi ricomincia, e non prima di due minuti.
@Observable
@MainActor
final class CodaAvvisi {
    struct Avviso: Equatable, Identifiable {
        enum Tipo {
            /// Qualcosa che non va (caldo, batteria, rete, microfono): in ambra.
            case avviso
            /// Un consiglio (gira in orizzontale): nell'accento.
            case suggerimento
        }

        /// L'argomento: «rete», «caldo», «batteria»…
        let id: String
        let testo: String
        let icona: String
        let tipo: Tipo
        /// Più alto, prima.
        let priorita: Int
    }

    private(set) var attuale: Avviso?
    @ObservationIgnored private var inAttesa: [Avviso] = []
    @ObservationIgnored private var mostrati: [String: Date] = [:]
    /// Argomenti già mostrati la cui condizione poi è finita: possono tornare.
    @ObservationIgnored private var finiti: Set<String> = []
    @ObservationIgnored private var attivi: Set<String> = []
    @ObservationIgnored private var compito: Task<Void, Never>?

    private static let durata: Duration = .seconds(6)
    private static let pausaPrimaDiRipetere: TimeInterval = 120

    /// Le condizioni vere adesso.
    func aggiorna(_ nuovi: [Avviso]) {
        let adesso = Set(nuovi.map(\.id))
        for id in attivi.subtracting(adesso) where mostrati[id] != nil {
            finiti.insert(id)
        }
        attivi = adesso
        // Condizioni finite: non si dicono più, e quella a schermo si chiude.
        inAttesa.removeAll { !adesso.contains($0.id) }
        if let attuale, !adesso.contains(attuale.id) {
            chiudi()
        }
        for avviso in nuovi {
            guard attuale?.id != avviso.id, !inAttesa.contains(where: { $0.id == avviso.id }) else { continue }
            if let quando = mostrati[avviso.id] {
                guard avviso.tipo == .avviso, finiti.contains(avviso.id),
                      Date().timeIntervalSince(quando) >= Self.pausaPrimaDiRipetere else { continue }
            }
            inAttesa.append(avviso)
        }
        inAttesa.sort { $0.priorita > $1.priorita }
        if attuale == nil { avanza() }
    }

    /// Chiude l'avviso a schermo e passa al prossimo, se c'è.
    func chiudi() {
        compito?.cancel()
        attuale = nil
        avanza()
    }

    /// Alla fine della sessione.
    func ferma() {
        compito?.cancel()
        compito = nil
        inAttesa = []
        attuale = nil
    }

    private func avanza() {
        guard attuale == nil, !inAttesa.isEmpty else { return }
        let prossimo = inAttesa.removeFirst()
        mostrati[prossimo.id] = Date()
        finiti.remove(prossimo.id)
        attuale = prossimo
        compito = Task { [weak self] in
            try? await Task.sleep(for: Self.durata)
            guard !Task.isCancelled, let self else { return }
            withAnimation { self.chiudi() }
        }
    }
}

/// «Dettagli» (1.14): i numeri tolti da sopra il video, con un tocco sulla riga di stato. Si aggiornano dal vivo.
private struct FoglioDettagli: View {
    let sessione: SessioneTelefono
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            List {
                Section {
                    riga("Computer", sessione.computer.nome)
                    if let tipo = sessione.tipoCollegamento {
                        riga("Collegamento", tipo.testo)
                    }
                    riga("Qualità", testoQualita)
                } header: {
                    EtichettaSezione(String(localized: "Collegamento"))
                }
                Section {
                    riga("Formato", testoFormato)
                    if let avvio = sessione.tempoAvvio {
                        riga("Avvio", MisuraAvvio.testo(avvio))
                    }
                    riga("Zoom", Double(sessione.zoom).formatted(.number.precision(.fractionLength(1))) + "×")
                    // Esposizione manuale dal computer o dai controlli Pro: la luce non si adatta più da sola.
                    if sessione.iso > 0 || sessione.tempo > 0 {
                        riga("Esposizione manuale", testoEsposizioneManuale)
                    }
                } header: {
                    EtichettaSezione(String(localized: "Video"))
                } footer: {
                    Text("L'anteprima riempie lo schermo e taglia i bordi: al computer arriva il video intero.")
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                }
                Section {
                    riga("Batteria", testoBatteria)
                    riga("Temperatura", sessione.temperatura.descrizione)
                } header: {
                    EtichettaSezione(String(localized: "iPhone"))
                }
                Section {
                    NavigationLink {
                        VistaRegistro()
                            .navigationTitle("Registro del collegamento")
                            .navigationBarTitleDisplayMode(.inline)
                            .intestazioneOpaca()
                    } label: {
                        Label("Registro del collegamento", systemImage: "list.bullet.rectangle")
                    }
                    .listRowBackground(Tema.pannello)
                }
            }
            .tint(Tema.ciano)
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .foregroundStyle(Tema.testo)
            .navigationTitle("Dettagli")
            .navigationBarTitleDisplayMode(.inline)
            .intestazioneOpaca()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { chiudi() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Tema.ciano)
        .preferredColorScheme(.dark)
    }

    private func riga(_ titolo: LocalizedStringKey, _ valore: String) -> some View {
        LabeledContent(titolo) {
            Text(valore)
                .font(.numeri(13))
                .foregroundStyle(Tema.testoChiaro)
                .multilineTextAlignment(.trailing)
        }
        .listRowBackground(Tema.pannello)
    }

    /// «Ottimo · 38 ms».
    private var testoQualita: String {
        guard let latenza = sessione.latenzaMs else { return "— ms" }
        let parola = QualitaCollegamento(latenzaMs: latenza, perdite: sessione.perditeRecenti).testo
        return "\(parola) · \(latenza) ms"
    }

    /// «1080p30 · H.264».
    private var testoFormato: String {
        guard sessione.larghezza > 0 else { return "—" }
        return "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps) · \(sessione.codec.nome)"
    }

    /// «ISO 400 · 1/50 s»: il tempo mostrato è quello usato, mai più lungo di un fotogramma.
    private var testoEsposizioneManuale: String {
        var parti: [String] = []
        if sessione.iso > 0 { parti.append("ISO \(Int(sessione.iso))") }
        if sessione.tempo > 0 { parti.append("1/\(max(sessione.tempo, sessione.fps)) s") }
        return parti.joined(separator: " · ")
    }

    private var testoBatteria: String {
        guard sessione.batteria >= 0 else { return "—" }
        let percento = "\(sessione.batteria)%"
        return sessione.inCarica ? String(localized: "\(percento), in carica") : percento
    }
}

/// Gli obiettivi in basso, compatti. Il fondo è quasi pieno: la griglia non si vede passare sotto.
/// Interfaccia finale: accanto, la torcia, solo con gli obiettivi posteriori (con la frontale sparisce).
private struct SelettoreObiettivo: View {
    let sessione: SessioneTelefono

    var body: some View {
        // Bug B: gli obiettivi al centro dello schermo anche con la torcia accanto (a sinistra lo stesso spazio,
        // vuoto). Se non ci sta (iPhone piccolo, testo grande) la torcia resta solo a destra.
        ViewThatFits(in: .horizontal) {
            riga(simmetrica: true)
            riga(simmetrica: false)
        }
    }

    private func riga(simmetrica: Bool) -> some View {
        HStack(spacing: 8) {
            if simmetrica && sessione.torciaDisponibile {
                Color.clear
                    .frame(width: 46, height: 46)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            obiettivi
            if sessione.torciaDisponibile {
                torcia
            }
        }
    }

    private var torcia: some View {
        Button {
            sessione.cambiaTorcia()
        } label: {
            Image(systemName: sessione.torciaAccesa ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(sessione.torciaAccesa ? Tema.fondo : Tema.testo)
                .frame(width: 46, height: 46)
                .background(sessione.torciaAccesa ? Tema.ciano : Tema.fondo.opacity(0.9), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Torcia")
        .accessibilityValue(sessione.torciaAccesa ? "accesa" : "spenta")
        .transition(.opacity)
    }

    private var obiettivi: some View {
        HStack(spacing: 4) {
            ForEach(sessione.obiettiviDisponibili) { obiettivo in
                let scelto = obiettivo == sessione.obiettivo
                Button {
                    sessione.scegli(obiettivo)
                } label: {
                    Text(obiettivo.etichetta)
                        .font(.numeriEvidenti(scelto ? 13 : 12))
                        .foregroundStyle(scelto ? Tema.fondo : Tema.testo)
                        .frame(minWidth: 38, minHeight: 38)
                        .padding(.horizontal, obiettivo == .frontale || obiettivo == .tele ? 6 : 0)
                        .background(scelto ? Tema.testo : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(obiettivo.nomeAccessibile)
                .accessibilityAddTraits(scelto ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Tema.fondo.opacity(0.9), in: Capsule())
    }
}

/// Linee dei terzi, come nel mirino della bozza: si disegnano nel riquadro che le viene dato (il video).
private struct GrigliaTerzi: View {
    var body: some View {
        GeometryReader { area in
            Path { linee in
                for frazione in [1.0 / 3, 2.0 / 3] {
                    linee.move(to: CGPoint(x: area.size.width * frazione, y: 0))
                    linee.addLine(to: CGPoint(x: area.size.width * frazione, y: area.size.height))
                    linee.move(to: CGPoint(x: 0, y: area.size.height * frazione))
                    linee.addLine(to: CGPoint(x: area.size.width, y: area.size.height * frazione))
                }
            }
            .stroke(Tema.testo.opacity(0.18), lineWidth: 1)
        }
    }
}

/// Livella al centro del video: la linea segue l'orizzonte e diventa verde entro ±1°.
private struct LineaLivella: View {
    let livella: Livella

    var body: some View {
        if let scostamento = livella.scostamento {
            let colore = livella.dritto ? Tema.verde : Tema.testo.opacity(0.75)
            ZStack {
                // Due tacche ferme ai lati: il riferimento del telefono.
                HStack(spacing: 150) {
                    Rectangle().fill(colore).frame(width: 18, height: 2)
                    Rectangle().fill(colore).frame(width: 18, height: 2)
                }
                Rectangle()
                    .fill(colore)
                    .frame(width: 120, height: 2)
                    .rotationEffect(.degrees(livella.dritto ? 0 : -scostamento))
            }
            .shadow(color: Tema.sfumaturaScura.opacity(0.6), radius: 1)
        }
    }
}

/// Interfaccia finale, in orizzontale: solo «IN ONDA» in piccolo e «Tocca per i comandi». Il primo tocco riporta i
/// comandi e non arriva all'anteprima (niente messa a fuoco per sbaglio). Con VoiceOver non compare mai.
private struct VistaPulita: View {
    let puntoColore: Color
    let testo: String
    let mostraComandi: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { mostraComandi() }
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(puntoColore)
                            .frame(width: 8, height: 8)
                        Text(testo)
                            .font(.etichetta(14))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(Tema.testo)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background(Tema.fondo.opacity(0.6), in: Capsule())
                    Spacer()
                }
                Spacer()
                Text("Tocca per i comandi")
                    .font(.footnote)
                    .foregroundStyle(Tema.testo.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Tema.fondo.opacity(0.5), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { mostraComandi() }
    }
}

/// Schermo nero durante l'uso (funzione 32): il video continua, lo schermo non consuma.
private struct SchermoOscurato: View {
    let sessione: SessioneTelefono

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(colorePunto)
                        .frame(width: 9, height: 9)
                    Text(testoStato)
                        .font(.etichetta(22))
                }
                // In orizzontale su una riga; in verticale non ci sta: collegamento sopra, telefono sotto.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        datiCollegamento
                        datiTelefono
                    }
                    VStack(spacing: 6) {
                        HStack(spacing: 16) { datiCollegamento }
                        HStack(spacing: 16) { datiTelefono }
                    }
                }
                .font(.numeri(13))
                .padding(.horizontal, 16)
                Text("Tocca due volte per riaccendere lo schermo")
                    .font(.footnote)
                    .padding(.top, 18)
            }
            // Con il testo grande o un nome di computer lungo le righe vanno a capo: centrate, lontane dai bordi.
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .foregroundStyle(Tema.testoSecondario)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation { sessione.oscurato = false }
        }
        // Con VoiceOver il doppio tocco arriva come un tocco solo: l'azione predefinita riaccende lo schermo,
        // e i comandi nascosti sotto il nero non si raggiungono più.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction {
            sessione.oscurato = false
        }
        .accessibilityAction(named: "Riaccendi lo schermo") {
            sessione.oscurato = false
        }
    }

    /// Qualità, tipo di collegamento e formato.
    @ViewBuilder private var datiCollegamento: some View {
        Text(testoQualita)
        if let tipo = sessione.tipoCollegamento {
            Text(tipo.testo)
        }
        Text(verbatim: sessione.larghezza > 0 ? "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps)" : "—")
    }

    /// Batteria e temperatura.
    @ViewBuilder private var datiTelefono: some View {
        Text(sessione.batteria >= 0 ? "batteria \(sessione.batteria)%" : "batteria —")
        Text("temperatura \(sessione.temperatura.descrizione)")
    }

    /// «Ottimo · 38 ms».
    private var testoQualita: String {
        guard let latenza = sessione.latenzaMs else { return "— ms" }
        let parola = QualitaCollegamento(latenzaMs: latenza, perdite: sessione.perditeRecenti).testo
        return "\(parola) · \(latenza) ms"
    }

    /// Anche a schermo spento il rosso compare solo quando un'app usa davvero la webcam.
    private var colorePunto: Color {
        guard sessione.stato == .collegato else { return Tema.ambra.opacity(0.7) }
        if sessione.prontaCam2 { return Tema.accento.opacity(0.7) }
        return sessione.inOnda != nil ? Tema.tally : Tema.verde.opacity(0.7)
    }

    private var testoStato: String {
        guard sessione.stato == .collegato else { return String(localized: "Riconnessione…") }
        if sessione.prontaCam2 { return String(localized: "Pronta · CAM 2") }
        return sessione.inOnda != nil ? String(localized: "In onda su \(sessione.computer.nome)")
            : String(localized: "Collegato a \(sessione.computer.nome)")
    }
}

/// I gesti sull'anteprima. Coordinate nel sistema della vista, che occupa tutto lo schermo.
private struct AzioniAnteprima {
    var tocco: (CGPoint) -> Void
    var doppioTocco: () -> Void
    var toccoLungo: (CGPoint) -> Void
    /// `inizio` vero al primo passo del pizzico; `scala` è rispetto all'inizio.
    var pizzico: (_ inizio: Bool, _ scala: CGFloat) -> Void
    /// Qualsiasi tocco nella finestra, anche sui pulsanti: rimanda l'oscuramento automatico.
    var qualsiasiTocco: () -> Void
}

/// Sente l'inizio di ogni tocco nella finestra senza mai prenderlo: fallisce subito,
/// così pulsanti e gesti funzionano come prima.
private final class RilevatoreTocchi: UIGestureRecognizer {
    var suTocco: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        suTocco?()
        state = .failed
    }
}

/// Mostra il livello di anteprima della fotocamera dentro SwiftUI, con i gesti in UIKit:
/// il tocco singolo aspetta che non sia un doppio tocco, il tocco lungo dà la posizione.
private struct AnteprimaFotocamera: UIViewRepresentable {
    let livello: AVCaptureVideoPreviewLayer
    /// B2: il video con gli effetti, sopra l'anteprima grezza; nascosto quando nessun effetto è acceso.
    let livelloEffetti: CALayer
    let azioni: AzioniAnteprima

    final class Coordinatore: NSObject, UIGestureRecognizerDelegate {
        var azioni: AzioniAnteprima

        init(azioni: AzioniAnteprima) {
            self.azioni = azioni
        }

        /// Tocco e doppio tocco insieme: il fuoco parte subito, senza aspettare che il doppio tocco fallisca.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UITapGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer
        }

        @objc func tocco(_ gesto: UITapGestureRecognizer) {
            guard let vista = gesto.view else { return }
            azioni.tocco(gesto.location(in: vista))
        }

        @objc func doppioTocco(_ gesto: UITapGestureRecognizer) {
            azioni.doppioTocco()
        }

        @objc func toccoLungo(_ gesto: UILongPressGestureRecognizer) {
            guard gesto.state == .began, let vista = gesto.view else { return }
            azioni.toccoLungo(gesto.location(in: vista))
        }

        @objc func pizzico(_ gesto: UIPinchGestureRecognizer) {
            switch gesto.state {
            case .began: azioni.pizzico(true, gesto.scale)
            case .changed: azioni.pizzico(false, gesto.scale)
            default: break
            }
        }
    }

    final class Vista: UIView {
        var livello: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let livello { layer.insertSublayer(livello, at: 0) }
            }
        }
        /// Sempre sopra l'anteprima grezza, che resta sotto per il tocco del fuoco.
        var livelloEffetti: CALayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let livelloEffetti { layer.addSublayer(livelloEffetti) }
            }
        }
        /// Sta sulla finestra intera, non solo sull'anteprima.
        var rilevatore: RilevatoreTocchi?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let rilevatore else { return }
            rilevatore.view?.removeGestureRecognizer(rilevatore)
            window?.addGestureRecognizer(rilevatore)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Cornice data con `bounds` e `position`: il livello può essere specchiato con una trasformazione
            // (fotocamera posteriore, `Cattura.specchiaAnteprima`), e con una trasformazione `frame` non vale.
            livello?.bounds = CGRect(origin: .zero, size: bounds.size)
            livello?.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            livelloEffetti?.frame = bounds
            CATransaction.commit()
        }
    }

    func makeCoordinator() -> Coordinatore {
        Coordinatore(azioni: azioni)
    }

    func makeUIView(context: Context) -> Vista {
        let vista = Vista()
        vista.backgroundColor = .black
        vista.livello = livello
        vista.livelloEffetti = livelloEffetti

        let coordinatore = context.coordinator
        let doppio = UITapGestureRecognizer(target: coordinatore, action: #selector(Coordinatore.doppioTocco(_:)))
        doppio.numberOfTapsRequired = 2
        let singolo = UITapGestureRecognizer(target: coordinatore, action: #selector(Coordinatore.tocco(_:)))
        // Niente attesa del doppio tocco: la messa a fuoco risponde subito (circa 0,3 s prima).
        doppio.delegate = coordinatore
        singolo.delegate = coordinatore
        let lungo = UILongPressGestureRecognizer(target: coordinatore, action: #selector(Coordinatore.toccoLungo(_:)))
        lungo.minimumPressDuration = 0.6
        let pizzico = UIPinchGestureRecognizer(target: coordinatore, action: #selector(Coordinatore.pizzico(_:)))
        vista.addGestureRecognizer(doppio)
        vista.addGestureRecognizer(singolo)
        vista.addGestureRecognizer(lungo)
        vista.addGestureRecognizer(pizzico)

        let rilevatore = RilevatoreTocchi(target: nil, action: nil)
        rilevatore.cancelsTouchesInView = false
        rilevatore.delaysTouchesBegan = false
        rilevatore.delaysTouchesEnded = false
        rilevatore.suTocco = { [weak coordinatore] in coordinatore?.azioni.qualsiasiTocco() }
        vista.rilevatore = rilevatore
        return vista
    }

    func updateUIView(_ vista: Vista, context: Context) {
        if vista.livello !== livello { vista.livello = livello }
        if vista.livelloEffetti !== livelloEffetti { vista.livelloEffetti = livelloEffetti }
        context.coordinator.azioni = azioni
    }
}
