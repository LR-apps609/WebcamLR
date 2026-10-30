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
    /// G1.3: un doppio tocco sull'anteprima in onda, detto con un avviso invece di cambiare fotocamera.
    @State private var doppioToccoInOnda = false
    @State private var numeroDoppioTocco = 0
    @State private var compitoDoppioTocco: Task<Void, Never>? = nil
    /// G2.6: Specchia o Sfoca sfondo toccati con la fotocamera posteriore: un avviso dice perché non fanno nulla.
    @State private var soloFrontaleChiesto = false
    @State private var numeroSoloFrontale = 0
    @State private var compitoSoloFrontale: Task<Void, Never>? = nil
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
                // G1.3: in onda il doppio tocco non cambia fotocamera.
                .accessibilityHint(sessione.inOnda != nil
                                   ? Text("Tocca per mettere a fuoco, tieni premuto per bloccare messa a fuoco ed esposizione.")
                                   : Text("Tocca per mettere a fuoco, tieni premuto per bloccare messa a fuoco ed esposizione, tocca due volte per cambiare fotocamera."))
                .accessibilityAction(named: "Cambia fotocamera") { sessione.cambiaFotocamera() }

            sopraIlVideo
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if vistaPulita {
                VistaPulita(puntoColore: colorePuntoStato, testo: testoStatoBreve,
                            pillole: statoDaLontano.map { stato in
                                (conApp: pillola(stato, conApp: true, dimensione: StileTesto.statoGrande.misura),
                                 senzaApp: pillola(stato, conApp: false, dimensione: StileTesto.statoGrande.misura))
                            }) {
                    withAnimation(.easeOut(duration: 0.2)) { vistaPulita = false }
                    rimandaVistaPulita()
                }
                .transition(.opacity)
            } else {
                // Bug 4 e seconda prova (bug D): i margini si calcolano qui (`margini`). In verticale la riga in cima
                // sta sotto l'isola (o la tacca), mai accanto; in orizzontale solo il lato dell'isola tiene il
                // margine sicuro, l'altro sta vicino al bordo vero (X e ingranaggio nell'angolo).
                // Struttura B (27 ottobre): in verticale, sugli iPhone con l'isola o la tacca, la riga in cima sta
                // nelle «orecchie» ai lati dell'isola (`orecchie`); avvisi, pannelli e colonna restano sotto l'isola.
                GeometryReader { area in
                    let sicuri = Self.zoneSicure(area.safeAreaInsets)
                    let margini = Self.margini(sicuri: sicuri, misura: area.size, taccaASinistra: lato.aSinistra)
                    let orecchie = Self.orecchie(sicuri: sicuri, misura: area.size)
                    ZStack(alignment: .top) {
                        ZStack(alignment: .bottom) {
                            sovrapposizioni(conRigaInAlto: orecchie == nil)
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
                        if let orecchie {
                            rigaNelleOrecchie(orecchie)
                        }
                    }
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
                    let sicuri = Self.zoneSicure(area.safeAreaInsets)
                    let margini = Self.margini(sicuri: sicuri, misura: area.size, taccaASinistra: lato.aSinistra)
                    // Con la riga nelle orecchie sotto l'isola non c'è nulla da lasciare libero.
                    posizioneGobbo(sottoLaRiga: Self.orecchie(sicuri: sicuri, misura: area.size) == nil)
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
        // G1.7: chiudere questa pagina termina la sessione. Niente «indietro» di sistema: niente pulsante e niente
        // scorrimento dal bordo sinistro (`BloccoIndietro`). Si scollega solo dalla X, che chiede prima.
        .navigationBarBackButtonHidden(true)
        .background { BloccoIndietro().frame(width: 0, height: 0).accessibilityHidden(true) }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(item: $domandaAperta, onDismiss: { rimandaOscuramento() }) { domanda in
            FoglioDomande(aperta: domanda.id)
        }
        .sheet(isPresented: $mostraDettagli, onDismiss: { rimandaOscuramento() }) {
            FoglioDettagli(sessione: sessione, stato: testoStato)
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
                SchermataImpostazioni(duranteLaSessione: true, sessione: sessione,
                                      ultimaLatenzaMs: sessione.ultimaLatenzaMs) { foglio in
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
            .tint(Tema.accento)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $mostraMessaAFuoco, onDismiss: { chiusoFoglioAMeta() }) {
            FoglioMessaAFuoco(sessione: sessione)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        // G1.6: la domanda dice cosa si ferma davvero. Durante il codice di conferma non c'è ancora un video:
        // si annulla il collegamento. Il gesto «indietro» è spento (G1.7, `BloccoIndietro`): si passa sempre da qui.
        .confirmationDialog(titoloConfermaScollega, isPresented: $confermaScollega, titleVisibility: .visible) {
            if sessione.codiceConferma != nil {
                Button("Annulla collegamento", role: .destructive) { chiudi() }
                Button("Continua ad aspettare", role: .cancel) { rimandaOscuramento() }
            } else {
                Button("Scollega", role: .destructive) { chiudi() }
                Button("Annulla", role: .cancel) { rimandaOscuramento() }
            }
        } message: {
            if sessione.codiceConferma == nil {
                if let app = sessione.inOnda?.app {
                    Text("\(app) sta usando il video: si fermerà anche lì.")
                } else {
                    Text("Il video si ferma e torni alla lista dei computer.")
                }
            }
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
        // G2.2: il testo cambia con la condizione (la batteria scende): l'avviso a schermo e l'icona lo seguono.
        .onChange(of: avvisiAttivi.map(\.testo)) { _, _ in
            avvisi.aggiornaTesti(avvisiAttivi)
        }
        // G2.8 e A2: collegato, in onda, pausa, riconnessione, errore, codice di conferma e ogni avviso nuovo detti
        // a VoiceOver; quando un'app prende il video anche una vibrazione leggera.
        .onChange(of: sessione.stato) { prima, adesso in annunciaStato(da: prima, a: adesso) }
        // Solo il video preso o lasciato: al ritorno dalla riconnessione `in-onda` arriva di nuovo dal computer.
        .onChange(of: sessione.inOnda != nil && !sessione.prontaCam2) { _, inOnda in
            guard sessione.stato == .collegato, sessione.pausa.motivo == nil else { return }
            if inOnda { Vibrazione.inOnda() }
            annuncia(testoAnnuncioCollegato)
        }
        .onChange(of: sessione.pausa.motivo) { prima, adesso in
            guard sessione.stato == .collegato else { return }
            // Sottofondo: l'app non si vede. Fotocamera interrotta: la causa la dice già la sessione.
            if let adesso {
                guard prima == nil, adesso != MotiviPausa.sottofondo, adesso != MotiviPausa.fotocameraInterrotta else { return }
                annuncia(String(localized: "Video in pausa"))
            } else if let prima, prima != MotiviPausa.sottofondo, prima != MotiviPausa.nessunaApp {
                // «Nessuna app» finisce perché un'app prende il video: lo annuncia già `inOndaQui`.
                annuncia(testoAnnuncioCollegato)
            }
        }
        .onChange(of: sessione.codiceConferma) { _, codice in
            guard let codice else { return }
            annuncia(String(localized: "Conferma sul computer") + ". "
                     + String(localized: "Codice di conferma \(codice.map { String($0) }.joined(separator: " "))"))
        }
        .onChange(of: avvisi.attuale?.id) { _, _ in
            // Il microfono fermo lo annuncia già la sessione.
            guard let avviso = avvisi.attuale, avviso.id != "microfono-perso" else { return }
            annuncia(avviso.testo)
        }
        .onChange(of: classeVerticale) { _, _ in controllaVistaPulita() }
        .onChange(of: foglioAperto) { _, _ in controllaVistaPulita() }
        .onChange(of: sessione.stato) { _, _ in controllaVistaPulita() }
        .onChange(of: sessione.codiceConferma) { _, _ in controllaVistaPulita() }
        .onChange(of: avvisi.attuale?.id) { _, _ in controllaVistaPulita() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            controllaVistaPulita()
            // G2.8: con VoiceOver gli avvisi non si chiudono da soli; spento, riprendono i 6 secondi.
            avvisi.voiceOverCambiato()
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
            compitoDoppioTocco?.cancel()
            compitoSoloFrontale?.cancel()
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
    private func posizioneGobbo(sottoLaRiga: Bool) -> some View {
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
        // all'ingranaggio e alla X di «Scollega», e il tocco sul gobbo non copre le Impostazioni. Con la riga nelle
        // orecchie (`orecchie`) il gobbo parte subito sotto l'isola.
        .padding(.top, sottoLaRiga ? Self.altezzaRigaInAlto : 0)
        .padding(.trailing, Self.spazioColonna)
    }

    /// Tocco, doppio tocco, tocco lungo e pizzico sull'anteprima (gesti UIKit, vedi `AnteprimaFotocamera`).
    private var azioniAnteprima: AzioniAnteprima {
        AzioniAnteprima(
            tocco: { punto in sessione.metteAFuoco(punto) },
            // G1.3: in onda un doppio tocco per sbaglio (anche pulendo lo schermo) non gira la ripresa: lo dice un
            // avviso con il gesto giusto. Fuori onda cambia fotocamera, come prima.
            doppioTocco: {
                if sessione.inOnda != nil { avvisaDoppioTocco() } else { sessione.cambiaFotocamera() }
            },
            toccoLungo: { punto in sessione.bloccaFuocoEdEsposizione(punto) },
            pizzico: { inizio, scala in
                if inizio { zoomIniziale = sessione.zoom }
                sessione.impostaZoom(zoomIniziale * scala)
                mostraZoom()
            },
            qualsiasiTocco: { rimandaOscuramento() }
        )
    }

    /// G1.3: l'avviso del doppio tocco in onda. Ogni doppio tocco ha il suo numero, così torna anche subito dopo;
    /// la condizione dura poco più dei 6 secondi dell'avviso.
    private func avvisaDoppioTocco() {
        numeroDoppioTocco += 1
        doppioToccoInOnda = true
        compitoDoppioTocco?.cancel()
        compitoDoppioTocco = Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            if Task.isCancelled { return }
            doppioToccoInOnda = false
        }
    }

    /// G2.6: Specchia o Sfoca sfondo toccati con la posteriore. Come il doppio tocco: un numero per ogni tocco, così
    /// l'avviso torna anche subito dopo.
    private func avvisaSoloFrontale() {
        numeroSoloFrontale += 1
        soloFrontaleChiesto = true
        compitoSoloFrontale?.cancel()
        compitoSoloFrontale = Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            if Task.isCancelled { return }
            soloFrontaleChiesto = false
        }
    }

    // MARK: - Annunci (G2.8)

    /// Questo telefono è nel video di un'app (con più telefoni, quello scelto).
    private var inOndaQui: Bool {
        sessione.stato == .collegato && sessione.inOnda != nil && !sessione.prontaCam2
    }

    /// «In onda su Zoom» o «Collegato a MacBook»: lo stato del video detto a VoiceOver.
    private var testoAnnuncioCollegato: String {
        guard inOndaQui else { return String(localized: "Collegato a \(sessione.computer.nome)") }
        if let app = sessione.inOnda?.app { return String(localized: "In onda su \(app)") }
        return String(localized: "In onda")
    }

    private func annunciaStato(da prima: SessioneTelefono.Stato, a adesso: SessioneTelefono.Stato) {
        switch adesso {
        case .collegato where prima != .collegato:
            annuncia(sessione.pausa.motivo != nil ? String(localized: "Video in pausa") : testoAnnuncioCollegato)
        case .riconnessione where prima == .collegato:
            annuncia(String(localized: "Collegamento perso, mi ricollego"))
        case .errore(let descrizione):
            annuncia(sessione.titoloErrore + ". " + descrizione)
        default:
            break
        }
    }

    /// Solo con VoiceOver acceso; gli annunci in coda si leggono uno dopo l'altro (`accessibilitySpeechQueueAnnouncement`).
    private func annuncia(_ testo: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let frase = NSAttributedString(string: testo, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: frase)
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
                    RoundedRectangle(cornerRadius: Raggi.piccolo)
                        .stroke(Tema.ambra, lineWidth: 2)
                        .frame(width: 84, height: 84)
                        .position(Self.dentro(visibile.isNull ? video : visibile, punto: punto, margine: 42))
                }
                if zoomVisibile {
                    Text(verbatim: Double(sessione.zoom).formatted(.number.precision(.fractionLength(1))) + "×")
                        .font(.stile(.corpo, .numeriEvidenti))
                        .foregroundStyle(Tema.testo)
                        .padding(.horizontal, Spazi.piccolo)
                        .frame(minHeight: 34)
                        .background(Veli.coloreMedio, in: Capsule())
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
    /// centrati sullo schermo. Uguale in verticale e in orizzontale. Con le orecchie (struttura B) la riga in cima
    /// non è qui ma ai lati dell'isola (`rigaNelleOrecchie`).
    private func sovrapposizioni(conRigaInAlto: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            if conRigaInAlto {
                HStack(alignment: .top, spacing: Spazi.stretto) {
                    rigaStato
                    iconeAvvisi
                    Spacer(minLength: Spazi.stretto)
                    pulsantiInAlto(compatti: false)
                }
            }
            HStack(alignment: .top, spacing: Spazi.piccolo) {
                contenutoSinistra(conIcone: !conRigaInAlto)
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
    /// `conIcone`: con la riga nelle orecchie le icone degli avvisi ridotti (G2.2) stanno qui, subito sotto l'isola.
    private func contenutoSinistra(conIcone: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            if conIcone {
                iconeAvvisi
            }
            if sessione.aeafBloccati {
                // Come nella Fotocamera: si sblocca con un tocco.
                Text("AE/AF bloccati")
                    .font(.stile(.sezione))
                    .tracking(0.6)
                    .foregroundStyle(Tema.fondo)
                    .padding(.horizontal, Spazi.stretto)
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
        .padding(.bottom, altezzaInBasso + Spazi.stretto)
        // Terza prova (punto D): tutta la larghezza libera, così la colonna dei comandi sta sempre a destra. Senza,
        // con nessun avviso questa colonna era larga 0 e i pulsanti tondi finivano a sinistra.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Seconda prova (bug B): in fondo, centrati sull'asse dello schermo, «Usa questa prospettiva» (con più
    /// telefoni) e gli obiettivi con la torcia.
    private var rigaInBasso: some View {
        VStack(spacing: Spazi.stretto) {
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
            // G2.1: in onda (o in pausa) la pillola piena di Stile, «IN ONDA» sempre scritto; si toglie prima il nome
            // dell'app, poi la strada e le tacche.
            Group {
                if let lontano = statoDaLontano {
                    ViewThatFits(in: .horizontal) {
                        contenutoDaLontano(lontano, conApp: true, conStrada: true)
                        contenutoDaLontano(lontano, conApp: false, conStrada: true)
                        contenutoDaLontano(lontano, conApp: false, conStrada: false)
                        pillola(lontano, conApp: false)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        contenutoStato(testoStato, conStrada: true)
                        contenutoStato(testoStatoBreve, conStrada: true)
                        contenutoStato(testoStatoBreve, conStrada: false)
                    }
                    .padding(.horizontal, Spazi.piccolo)
                }
            }
            .foregroundStyle(Tema.testo)
            .frame(minHeight: 32)
            .background(Veli.coloreMedio, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etichettaStato)
        .accessibilityHint("Mostra i dettagli del collegamento")
    }

    /// Il punto, lo stato e, da collegati, la strada e le tacche della qualità.
    private func contenutoStato(_ testo: String, conStrada: Bool) -> some View {
        HStack(spacing: Spazi.stretto) {
            Circle()
                .fill(colorePuntoStato)
                .frame(width: 8, height: 8)
            Text(testo)
                .font(.stile(.sezione))
                .tracking(0.6)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
            secondiRiconnessione
            stradaETacche(conStrada: conStrada)
        }
    }

    /// Da collegati la strada, in parola («Wi-Fi» o «USB»), e le tacche della qualità.
    @ViewBuilder
    private func stradaETacche(conStrada: Bool) -> some View {
        if sessione.stato == .collegato {
            // Bug 8: accanto a «Collegato» / «In onda» la strada, in parola: «Wi-Fi» o «USB».
            if conStrada, let tipo = tipoVisibile {
                HStack(spacing: Spazi.minimo) {
                    Image(systemName: tipo.simbolo)
                        .font(.system(size: 11, weight: .semibold))
                    Text(verbatim: "· " + tipo.testoBreve)
                        .fixedSize()
                }
                .font(.stile(.sezione))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Tema.testoSecondario)
            }
            if sessione.latenzaMs != nil {
                TaccheQualita(qualita)
            }
        }
    }

    /// «Mi ricollego…» con i secondi, come il banner (al posto di «Riconnessione 2/5»). Non in attesa di un computer
    /// fidato: lì il banner è calmo, senza secondi.
    @ViewBuilder
    private var secondiRiconnessione: some View {
        if case .riconnessione = sessione.stato, !sessione.inAttesaDelComputer, let inizio = sessione.inizioRiconnessione {
            TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                Text(verbatim: "\(max(0, Int(contesto.date.timeIntervalSince(inizio)))) s")
                    .font(.stile(.numeri))
                    .foregroundStyle(Tema.ambraTesto)
                    .fixedSize()
            }
        }
    }

    // MARK: - Stato da lontano (G2.1)

    /// In onda: la pillola corallo piena. In pausa (qualsiasi motivo, A1): ambra. Altrimenti la riga di sempre.
    enum StatoDaLontano { case inOnda, inPausa }

    private var statoDaLontano: StatoDaLontano? {
        guard sessione.stato == .collegato else { return nil }
        if sessione.pausa.motivo != nil { return .inPausa }
        // Con più telefoni, quello che non è nella webcam: mai corallo.
        if sessione.prontaCam2 { return nil }
        return sessione.inOnda != nil ? .inOnda : nil
    }

    /// La `PillolaStato` di Stile: corallo pieno e testo bianco in onda; in pausa l'aspetto ambra di Stile
    /// (`.riconnessione`) con «In pausa». `conApp`: «In onda · Zoom», altrimenti «In onda».
    private func pillola(_ stato: StatoDaLontano, conApp: Bool, dimensione: CGFloat = PillolaStato.misuraNormale) -> PillolaStato {
        switch stato {
        case .inOnda:
            PillolaStato(.inOnda(app: conApp ? sessione.inOnda?.app : nil), dimensione: dimensione)
        case .inPausa:
            PillolaStato(.riconnessione, testo: String(localized: "In pausa"), dimensione: dimensione)
        }
    }

    /// La pillola e, se ci stanno, la strada e le tacche, dentro la capsula scura della riga.
    private func contenutoDaLontano(_ stato: StatoDaLontano, conApp: Bool, conStrada: Bool) -> some View {
        HStack(spacing: Spazi.stretto) {
            pillola(stato, conApp: conApp)
                .fixedSize()
            stradaETacche(conStrada: conStrada)
        }
        .padding(.trailing, conStrada || sessione.latenzaMs != nil ? Spazi.piccolo : 0)
    }

    /// Con più telefoni, su quello che non è nella webcam (interfaccia finale, «Due telefoni»): grande, in basso,
    /// nell'accento salvia. La scelta si vede solo quando il computer manda il nuovo `in-onda`.
    private var pulsanteUsaProspettiva: some View {
        Button("Usa questa prospettiva") {
            sessione.usaProspettiva()
            rimandaOscuramento()
        }
        .buttonStyle(StilePrimario(.grande))
        .frame(maxWidth: 520)
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
        // A1: video in pausa (qualsiasi motivo): ambra, mai il corallo di «In onda».
        case .collegato where sessione.pausa.motivo != nil: Tema.ambra
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
        case .collegato where sessione.pausa.motivo != nil: String(localized: "In pausa")
        case .collegato where sessione.prontaCam2: String(localized: "Pronta · CAM 2")
        case .collegato where sessione.inOnda != nil:
            sessione.inOnda?.app.map { String(localized: "In onda · \($0)") } ?? String(localized: "In onda")
        case .collegato: String(localized: "Collegato · \(sessione.computer.nome)")
        case .collegamento: String(localized: "Collegamento…")
        case .riconnessione:
            // Non più «Riconnessione 2/5»: i secondi li aggiunge la riga (`secondiRiconnessione`), come il banner.
            sessione.inAttesaDelComputer ? String(localized: "In attesa") : String(localized: "Mi ricollego…")
        case .chiusa, .errore: String(localized: "Scollegato")
        }
    }

    /// G1.6: durante il codice di conferma si annulla il collegamento (via cavo il nome arriva solo dopo).
    private var titoloConfermaScollega: Text {
        guard sessione.codiceConferma != nil else { return Text("Scollegare il telefono?") }
        return sessione.viaCavo
            ? Text("Annullare il collegamento?")
            : Text("Annullare il collegamento a «\(sessione.computer.nome)»?")
    }

    /// Quando il testo intero non ci sta: senza il nome del computer o dell'app.
    private var testoStatoBreve: String {
        switch sessione.stato {
        case .collegato where sessione.pausa.motivo != nil: String(localized: "In pausa")
        case .collegato where sessione.prontaCam2: String(localized: "Pronta · CAM 2")
        case .collegato where sessione.inOnda != nil: String(localized: "In onda")
        case .collegato: String(localized: "Collegato")
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
        // G1.1: di ritorno dal sottofondo, per quanto il video si è fermato.
        if let ritorno = sessione.avvisoRitorno {
            elenco.append(.init(id: "ritorno-\(sessione.numeroRitorno)", testo: ritorno, icona: "play.circle",
                                tipo: .avviso, priorita: 6))
        }
        // G1.3: risposta a un gesto, si vede subito (`subito`).
        if doppioToccoInOnda {
            elenco.append(.init(id: "doppio-tocco-\(numeroDoppioTocco)",
                                testo: String(localized: "In onda: per cambiare fotocamera tocca «Frontale» o «1×» in basso."),
                                icona: "hand.tap", tipo: .suggerimento, priorita: 7, subito: true))
        }
        // G2.6: Specchia o Sfoca sfondo toccati con la posteriore.
        if soloFrontaleChiesto {
            elenco.append(.init(id: "solo-frontale-\(numeroSoloFrontale)",
                                testo: String(localized: "Specchia e Sfoca sfondo funzionano con la fotocamera frontale."),
                                icona: "camera.rotate", tipo: .suggerimento, priorita: 7, subito: true))
        }
        // G1.5: il microfono fermato da una chiamata o da un'altra app resta detto finché non riparte.
        if sessione.microfonoPerso {
            elenco.append(.init(id: "microfono-perso", testo: TestiAssistente.microfonoFermo, icona: "mic.slash",
                                tipo: .avviso, priorita: 5, resta: true, tocco: .riprovaMicrofono))
        }
        // G2.3: permesso del microfono negato. Resta con «Apri Impostazioni» finché non si tocca (poi è un'icona).
        if sessione.microfonoNegato {
            let causa = Diagnosi.microfonoNegato
            elenco.append(.init(id: "microfono", testo: causa.spiegazione, icona: causa.simbolo, tipo: .avviso,
                                priorita: 5, resta: true, persiste: true, diagnosi: causa))
        }
        if sessione.qualitaRidotta {
            elenco.append(.init(id: "caldo", testo: String(localized: "Telefono molto caldo: qualità ridotta finché si raffredda"),
                                icona: "thermometer.high", tipo: .avviso, priorita: 4, persiste: true))
        }
        // A3: al 10% un avviso nuovo (un altro argomento), che si vede di nuovo anche se quello del 20% era un'icona.
        if sessione.batteriaBassa && sessione.batteria <= 10 {
            elenco.append(.init(id: "batteria-10",
                                testo: String(localized: "Batteria al 10%: collega il caricatore o il video si fermerà"),
                                icona: "battery.0", tipo: .avviso, priorita: 5, persiste: true))
        } else if sessione.batteriaBassa {
            let testo = sessione.risparmioBatteria
                ? String(localized: "Batteria al \(sessione.batteria)%: 24 fps per risparmiare, collega il caricatore")
                : String(localized: "Batteria al \(sessione.batteria)%: collega il caricatore")
            elenco.append(.init(id: "batteria", testo: testo, icona: "battery.25", tipo: .avviso, priorita: 4,
                                persiste: true))
        }
        if let rete = testoRete {
            elenco.append(.init(id: "rete", testo: rete, icona: "wifi.exclamationmark", tipo: .avviso, priorita: 3,
                                persiste: true))
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

    @ViewBuilder
    private func vistaAvviso(_ avviso: CodaAvvisi.Avviso) -> some View {
        if let diagnosi = avviso.diagnosi {
            // G2.3: con una diagnosi l'avviso porta anche i suoi pulsanti («Apri Impostazioni» chiede prima: si è in
            // onda). Un tocco sul testo lo chiude, come gli altri; i pulsanti non possono stare dentro un `Button`.
            Avviso(avviso.testo, icona: avviso.icona, tono: tono(avviso), larghezzaMassima: 420,
                   alTocco: { withAnimation { avvisi.chiudi() } }, suggerimentoTocco: Text("Tocca per chiudere")) {
                AzioniDiagnosi(diagnosi: diagnosi, inDiretta: sessione.stato == .collegato) { domanda in
                    apriSopra { domandaAperta = DomandaDaAprire(id: domanda) }
                }
            }
        } else {
            vistaAvvisoSemplice(avviso)
        }
    }

    /// Ambra per ciò che non va, accento per un consiglio.
    private func tono(_ avviso: CodaAvvisi.Avviso) -> TonoAvviso {
        avviso.tipo == .avviso ? .attenzione : .informazione
    }

    private func vistaAvvisoSemplice(_ avviso: CodaAvvisi.Avviso) -> some View {
        Button {
            switch avviso.tocco {
            case .chiudi: withAnimation { avvisi.chiudi() }
            // Resta a schermo: si chiude da solo quando il microfono riparte.
            case .riprovaMicrofono: sessione.riprovaMicrofono()
            }
        } label: {
            Avviso(avviso.testo, icona: avviso.icona, tono: tono(avviso), larghezzaMassima: 420)
                .contentShape(RoundedRectangle(cornerRadius: Raggi.pannello))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(avviso.tocco == .riprovaMicrofono ? Text("Tocca per riprovare") : Text("Tocca per chiudere"))
    }

    /// G2.2: gli avvisi chiusi la cui causa c'è ancora, come icone ambra accanto alla riga di stato. Un tocco li riapre.
    @ViewBuilder
    private var iconeAvvisi: some View {
        if !avvisi.ridotti.isEmpty {
            HStack(spacing: 0) {
                ForEach(avvisi.ridotti) { avviso in
                    Button {
                        withAnimation { avvisi.riapri(avviso.id) }
                        rimandaOscuramento()
                    } label: {
                        Image(systemName: avviso.icona)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Tema.ambra)
                            .frame(width: 32, height: 32)
                            .background(Veli.coloreMedio, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Avviso: \(avviso.testo)"))
                    .accessibilityHint(Text("Tocca per rileggere l'avviso"))
                }
            }
            .transition(.opacity)
        }
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
            .background(Veli.coloreMedio, in: Capsule())
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    /// Acceso con la sfocatura e anche con uno sfondo sostituito (scelto dal computer): un tocco lo spegne.
    /// Terza prova (punto F): con la posteriore lo sfondo è spento e il pulsante grigio.
    /// Quarta prova: solo le nostre funzioni, niente pannello Effetti video di Apple.
    /// Telecomando (`effettiSulComputer`): Specchia, Sfoca e Luce mostrano lo stato degli effetti del computer
    /// (`effetti`) e un tocco lo chiede al computer (`chiedi-effetto`); Microfono e Pausa restano del telefono.
    private var telecomando: Bool { sessione.effettiSulComputer }
    private var sfondoAcceso: Bool {
        telecomando ? (sessione.effettiComputer.map { $0.sfondo != ModiSfondo.nessuno } ?? false)
                    : sessione.visivi.sfondoEffettivo != ModiSfondo.nessuno
    }
    private var inPausa: Bool { sessione.pausa.utente }
    private var luceAccesa: Bool {
        telecomando ? sessione.effettiComputer?.luceVolto == true : sessione.funzioni.luceVolto
    }
    private var specchioAcceso: Bool {
        telecomando ? sessione.effettiComputer?.specchia == true : sessione.specchioEffettivo
    }
    /// Specchio e sfondo solo con la frontale, anche quelli del computer (con la posteriore non li fa).
    private var specchioESfondoDisponibili: Bool { sessione.conFrontale }

    private var pulsantiColonna: some View {
        VStack(spacing: Spazi.stretto) {
            // Specchia il video che arriva al computer, subito; nell'accento quando è acceso.
            // Terza prova (punto E): solo con la frontale; con la posteriore è grigio e spento.
            // G2.6: con la posteriore resta toccabile e un tocco dice perché non fa nulla.
            PulsanteTondo(String(localized: "Specchia"), icona: "flip.horizontal", attivo: specchioAcceso) {
                if !specchioESfondoDisponibili {
                    avvisaSoloFrontale()
                } else if telecomando {
                    sessione.chiediEffetto(RichiestaEffetto(specchia: !specchioAcceso))
                } else {
                    sessione.impostaSpecchio(!sessione.specchiato)
                }
            }
            .opacity(specchioESfondoDisponibili ? 1 : Opacita.spento)
            .accessibilityValue(specchioAcceso ? "acceso" : "spento")
            .accessibilityHint(specchioESfondoDisponibili ? Text("Specchia il video che arriva al computer")
                               : Text("Specchia e Sfoca sfondo funzionano con la fotocamera frontale."))
            // Un tocco: sfocato o niente, con l'intensità scelta dal computer (gratis). Con uno sfondo sostituito,
            // scelto dal computer, il pulsante è acceso e un tocco spegne lo sfondo.
            // Telecomando: «sfocato» accende la sfocatura con l'ultimo livello scelto sul computer.
            PulsanteTondo(String(localized: "Sfoca sfondo"), icona: "person.and.background.dotted", attivo: sfondoAcceso) {
                guard specchioESfondoDisponibili else { avvisaSoloFrontale(); return }
                let nuovo = sfondoAcceso ? ModiSfondo.nessuno : ModiSfondo.sfocato
                if telecomando {
                    sessione.chiediEffetto(RichiestaEffetto(sfondo: nuovo))
                } else {
                    sessione.visivi.scegliSfondo(nuovo)
                }
            }
            .opacity(specchioESfondoDisponibili ? 1 : Opacita.spento)
            .accessibilityValue(sfondoAcceso ? "acceso" : "spento")
            .accessibilityHint(specchioESfondoDisponibili ? Text(verbatim: "")
                               : Text("Specchia e Sfoca sfondo funzionano con la fotocamera frontale."))
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
                if telecomando {
                    sessione.chiediEffetto(RichiestaEffetto(luceVolto: !luceAccesa))
                } else {
                    sessione.funzioni.impostaLuceVolto(!luceAccesa)
                }
            }
            .accessibilityValue(luceAccesa ? "accesa" : "spenta")
            .accessibilityHint("Schiarisce il volto come una luce ad anello, anche con una finestra alle spalle")
        }
        .padding(Spazi.stretto)
    }

    /// In alto a destra, piccoli: le Impostazioni del telefono (WebcamLR Pro in cima) e Scollega. Nell'orecchia
    /// (`compatti`) i cerchi sono più piccoli e le aree di tocco da 44 si toccano, senza spazio in mezzo.
    private func pulsantiInAlto(compatti: Bool) -> some View {
        HStack(spacing: compatti ? 0 : Spazi.stretto) {
            pulsantePiccolo(icona: "gearshape", attivo: controlliManuali, compatto: compatti) {
                apriSopra { mostraImpostazioni = true }
            }
            .accessibilityLabel("Impostazioni")
            .accessibilityHint("WebcamLR Pro, video, fotocamera e collegamento")
            pulsantePiccolo(icona: "xmark", attivo: false, compatto: compatti) {
                // Con la messa a fuoco aperta (si tocca anche sotto) prima si chiude il foglio: altrimenti
                // resterebbe aperto sopra la lista dei computer, su una sessione già chiusa.
                apriSopra { confermaScollega = true }
            }
            .accessibilityLabel("Scollega")
        }
    }

    private func pulsantePiccolo(icona: String, attivo: Bool, compatto: Bool = false,
                                 azione: @escaping () -> Void) -> some View {
        let diametro: CGFloat = compatto ? 36 : 42
        return Button(action: azione) {
            Image(systemName: icona)
                .font(.system(size: compatto ? 15 : 17, weight: .semibold))
                .foregroundStyle(attivo ? Tema.accentoChiaro : Tema.testo)
                .frame(width: diametro, height: diametro)
                .background(attivo ? Tema.accentoTenue : Veli.coloreMedio, in: Circle())
                // Compatto: il tocco vale su tutti i 44 punti attorno al cerchio, non solo sul cerchio.
                .frame(width: compatto ? 44 : diametro, height: compatto ? 44 : diametro)
                .contentShape(compatto ? AnyShape(Rectangle()) : AnyShape(Circle()))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
    }

    /// Struttura B: la riga in cima nelle orecchie ai lati dell'isola, centrata in altezza sull'isola. A sinistra la
    /// pillola corta «● Wi-Fi» / «● USB» (il testo lungo è nei Dettagli e in VoiceOver), a destra ingranaggio e X.
    private func rigaNelleOrecchie(_ orecchie: Orecchie) -> some View {
        HStack(spacing: 0) {
            pillolaOrecchia
                .frame(width: orecchie.larghezza, alignment: .leading)
            Spacer(minLength: 0)
            pulsantiInAlto(compatti: true)
                .frame(width: orecchie.larghezza, alignment: .trailing)
        }
        .frame(height: 44)
        .padding(.horizontal, Self.margineEsternoOrecchie)
        .padding(.top, max(orecchie.centro - 22, 0))
    }

    /// La pillola dell'orecchia sinistra: il punto (stessi colori della riga di stato) e la strada. Se non ci sta,
    /// il punto con l'icona Wi-Fi/USB, poi il punto solo. Un tocco apre i Dettagli, come la riga di stato.
    private var pillolaOrecchia: some View {
        Button {
            apriSopra { mostraDettagli = true }
        } label: {
            Group {
                // G2.1: in onda «IN ONDA» sempre scritto nella pillola piena, anche qui (prima solo «● Wi-Fi»);
                // la strada resta nei Dettagli e in VoiceOver. Se non ci sta, la pillola più piccola.
                if let lontano = statoDaLontano {
                    ViewThatFits(in: .horizontal) {
                        pillola(lontano, conApp: false)
                        pillola(lontano, conApp: false, dimensione: StileTesto.sezione.misura)
                        puntoStato
                            .padding(.horizontal, Spazi.piccolo)
                            .frame(minHeight: 32)
                            .background(Veli.coloreMedio, in: Capsule())
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        contenutoOrecchia(conTesto: true)
                        contenutoOrecchia(conTesto: false)
                        puntoStato
                    }
                    .padding(.horizontal, Spazi.piccolo)
                    .frame(minHeight: 32)
                    .background(Veli.coloreMedio, in: Capsule())
                }
            }
            .foregroundStyle(Tema.testo)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etichettaStato)
        .accessibilityHint("Mostra i dettagli del collegamento")
    }

    /// «● Wi-Fi» (o l'icona sola). Senza strada nota, lo stato corto («Riconnessione»), che può non starci.
    @ViewBuilder
    private func contenutoOrecchia(conTesto: Bool) -> some View {
        if let tipo = tipoVisibile {
            HStack(spacing: Spazi.stretto) {
                puntoStato
                if conTesto {
                    Text(verbatim: tipo.testoBreve)
                        .font(.stile(.sezione))
                        .tracking(0.6)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Image(systemName: tipo.simbolo)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        } else if conTesto {
            HStack(spacing: Spazi.stretto) {
                puntoStato
                Text(testoStatoBreve)
                    .font(.stile(.sezione))
                    .tracking(0.6)
                    .lineLimit(1)
                    .fixedSize()
            }
        } else {
            puntoStato
        }
    }

    private var puntoStato: some View {
        Circle()
            .fill(colorePuntoStato)
            .frame(width: 8, height: 8)
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
        return HStack(spacing: Spazi.piccolo) {
            ProgressView()
                .tint(attesa ? Tema.accento : Tema.ambraTesto)
            if attesa {
                VStack(alignment: .leading, spacing: Spazi.minimo) {
                    Text(testoRiconnessione)
                        .font(.stile(.corpo, .corpoForte))
                    Text(sottotitoloAttesa)
                        .font(.stile(.nota))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Tema.testo)
            } else {
                TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                    let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                    VStack(alignment: .leading, spacing: Spazi.minimo) {
                        Text(testoRiconnessione)
                            .font(.stile(.corpo, .corpoForte))
                        Text(secondi == 1 ? "da 1 secondo" : "da \(secondi) secondi")
                            .font(.stile(.numeri))
                    }
                    .foregroundStyle(Tema.ambraTesto)
                }
            }
            Spacer(minLength: Spazi.stretto)
            // Sul cavo è il computer a riaprire la connessione: riprovare da qui non serve.
            if !sessione.viaCavo {
                Button("Riprova ora") { sessione.riprova() }
                    .buttonStyle(StilePrimario())
            }
        }
        .padding(.horizontal, Spazi.medio)
        .padding(.vertical, Spazi.stretto)
        .frame(maxWidth: 420, alignment: .leading)
        .background(attesa ? Tema.pannello.opacity(Veli.forte) : Tema.ambraTenue.opacity(Veli.forte), in: RoundedRectangle(cornerRadius: Raggi.pannello))
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
        // G2.7: dopo due minuti lo schermo può spegnersi, e a schermo spento la ricerca si ferma: si dice.
        // Col gobbo a schermo lo schermo resta acceso: lì vale ancora «riparto da solo».
        if sessione.gobbo.visibile {
            return String(localized: "Riparto da solo appena WebcamLR è aperto sul computer.")
        }
        return sessione.schermoLibero
            ? String(localized: "Ora lo schermo si spegne per risparmiare batteria: quando riapri WebcamLR riprovo subito.")
            : String(localized: "Tra 2 minuti lo schermo si spegne per risparmiare batteria: quando riapri WebcamLR riprovo subito.")
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
        VStack(alignment: .leading, spacing: Spazi.piccolo) {
            HStack(spacing: Spazi.stretto) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 22))
                    .foregroundStyle(Tema.accento)
                    .accessibilityHidden(true)
                Text("Conferma sul computer")
                    .font(.stile(.titoloGrande))
            }
            // Via cavo il nome del computer arriva solo dopo la conferma (1.6).
            Text(sessione.viaCavo
                 ? "Sul computer consenti questo iPhone, se il codice di conferma è lo stesso:"
                 : "Su \(sessione.computer.nome) consenti questo iPhone, se il codice di conferma è lo stesso:")
                .font(.stile(.corpo))
                .foregroundStyle(Tema.testoChiaro)
                .fixedSize(horizontal: false, vertical: true)
            // Il codice da confrontare con il computer: grande di proposito, fuori dalla scala dei testi.
            Text(codice)
                .font(.numeriEvidenti(46))
                .tracking(10)
                .foregroundStyle(Tema.testo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spazi.stretto)
                .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: Raggi.controllo))
                // VoiceOver legge le cifre una per una.
                .accessibilityLabel("Codice di conferma \(codice.map { String($0) }.joined(separator: " "))")
            HStack(spacing: Spazi.stretto) {
                ProgressView()
                    .tint(Tema.accento)
                Text("Aspetto la risposta, fino a un minuto")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
            }
        }
        .padding(Spazi.medio)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Veli.coloreForte, in: RoundedRectangle(cornerRadius: Raggi.pannello))
        .overlay(RoundedRectangle(cornerRadius: Raggi.pannello).stroke(Tema.accento))
        .foregroundStyle(Tema.testo)
        .accessibilityElement(children: .combine)
    }

    private func pannelloErrore(_ descrizione: String) -> some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            Text(sessione.titoloErrore)
                .font(.stile(.titoloGrande))
            Text(descrizione)
                .font(.stile(.corpo))
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
            if let diagnosi = sessione.diagnosi {
                // 1.3: l'azione della diagnosi (per esempio «Apri Impostazioni») e la risposta.
                AzioniDiagnosi(diagnosi: diagnosi, inDiretta: sessione.stato == .collegato) { domanda in apriSopra { domandaAperta = DomandaDaAprire(id: domanda) } }
            } else if let domanda = sessione.domandaErrore {
                Button("Perché succede?") { apriSopra { domandaAperta = DomandaDaAprire(id: domanda) } }
                    .buttonStyle(StileLink())
                    .font(.stile(.corpo, .corpoForte))
                    .frame(minHeight: 44)
            }
            // Sugli iPhone piccoli o con il testo grande i due pulsanti vanno uno sotto l'altro, senza troncare.
            ViewThatFits(in: .horizontal) {
                HStack { pulsantiErrore }
                VStack(alignment: .leading, spacing: Spazi.stretto) { pulsantiErrore }
            }
        }
        .padding(Spazi.medio)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Veli.coloreForte, in: RoundedRectangle(cornerRadius: Raggi.pannello))
        .foregroundStyle(Tema.testo)
    }

    @ViewBuilder private var pulsantiErrore: some View {
        // Identità cambiata: riprovare non serve, si riabbina con il QR code dalla lista dei computer.
        if !sessione.erroreDefinitivo {
            Button("Riprova") { sessione.riprova() }
                .buttonStyle(StilePrimario())
        }
        Button("Torna ai computer") { apriSopra { chiudi() } }
            .buttonStyle(StileSecondario())
    }
}

extension Codec {
    /// Come in Impostazioni › Qualità e nei Dettagli.
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
/// cosa. Si chiude da solo dopo 6 secondi o con un tocco; uno che resta (microfono fermo) rimane finché dura la sua
/// condizione, a turno con gli altri avvisi se ce ne sono. Un suggerimento si vede una volta per sessione; un
/// avviso torna solo se la sua condizione è finita e poi ricomincia, e non prima di due minuti.
/// G2.2: un avviso su una condizione in corso (`persiste`: caldo, batteria, rete, microfono) dopo i 6 secondi si
/// riduce a un'icona ambra nella riga di stato (`ridotti`) finché la condizione dura; un tocco sull'icona lo riapre.
/// Ogni avviso va anche nel registro. G2.8: con VoiceOver acceso un avviso non si chiude da solo finché non c'è altro
/// da dire; se altri aspettano lascia il posto dopo 20 secondi, così la coda non si blocca.
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
        var testo: String
        let icona: String
        let tipo: Tipo
        /// Più alto, prima.
        let priorita: Int
        /// G1.5: non si chiude dopo 6 secondi, solo quando la condizione finisce.
        var resta = false
        /// Cosa fa un tocco sull'avviso.
        var tocco: Tocco = .chiudi
        /// G1.3: la risposta a un gesto (doppio tocco in onda) prende subito il posto di quello a schermo, che torna dopo.
        var subito = false
        /// G2.2: descrive una condizione ancora in corso: chiuso (dopo 6 secondi o con un tocco) diventa un'icona.
        var persiste = false
        /// G2.3: una diagnosi con la sua azione (microfono negato → «Apri Impostazioni»), mostrata sotto il testo.
        var diagnosi: Diagnosi? = nil

        enum Tocco: Equatable {
            case chiudi
            /// G1.5: «Tocca per riprovare» sul microfono fermo.
            case riprovaMicrofono
        }
    }

    private(set) var attuale: Avviso?
    /// G2.2: gli avvisi chiusi la cui condizione dura ancora, come icone nella riga di stato.
    private(set) var ridotti: [Avviso] = []
    @ObservationIgnored private var inAttesa: [Avviso] = []
    @ObservationIgnored private var mostrati: [String: Date] = [:]
    /// Argomenti già mostrati la cui condizione poi è finita: possono tornare.
    @ObservationIgnored private var finiti: Set<String> = []
    @ObservationIgnored private var attivi: Set<String> = []
    @ObservationIgnored private var compito: Task<Void, Never>?

    private static let durata: Duration = .seconds(6)
    /// Con VoiceOver: il tempo di sentire l'avviso prima di passare al prossimo in coda.
    private static let durataConVoiceOver: Duration = .seconds(20)
    private static let pausaPrimaDiRipetere: TimeInterval = 120

    /// Le condizioni vere adesso.
    func aggiorna(_ nuovi: [Avviso]) {
        let adesso = Set(nuovi.map(\.id))
        for id in attivi.subtracting(adesso) where mostrati[id] != nil {
            finiti.insert(id)
        }
        attivi = adesso
        // Condizioni finite: non si dicono più, l'icona sparisce e quella a schermo si chiude.
        inAttesa.removeAll { !adesso.contains($0.id) }
        ridotti.removeAll { !adesso.contains($0.id) }
        if let attuale, !adesso.contains(attuale.id) {
            togli(riduci: false)
        }
        for avviso in nuovi {
            guard attuale?.id != avviso.id, !inAttesa.contains(where: { $0.id == avviso.id }),
                  !ridotti.contains(where: { $0.id == avviso.id }) else { continue }
            if let quando = mostrati[avviso.id] {
                // Uno che resta torna appena la condizione ricomincia: è uno stato, non un promemoria.
                guard avviso.tipo == .avviso, finiti.contains(avviso.id),
                      avviso.resta || Date().timeIntervalSince(quando) >= Self.pausaPrimaDiRipetere else { continue }
            }
            inAttesa.append(avviso)
        }
        inAttesa.sort { $0.priorita > $1.priorita }
        if let primo = inAttesa.first, primo.subito, let mostrato = attuale, !mostrato.subito {
            // Quello a schermo torna subito dopo, se la sua condizione dura ancora.
            inAttesa.removeFirst()
            inAttesa.insert(mostrato, at: 0)
            mostra(primo)
        } else if attuale == nil {
            avanza()
        } else if let attuale, compito == nil {
            // Uno che resta (o uno con VoiceOver) e un altro avviso che arriva: dopo un po' gli lascia il posto.
            programma(attuale)
        }
    }

    /// G2.2: lo stesso argomento con un testo nuovo («Batteria al 18%» → «al 15%»): a schermo, in coda e nelle
    /// icone si aggiorna senza ricominciare i 6 secondi.
    func aggiornaTesti(_ nuovi: [Avviso]) {
        let testi = Dictionary(nuovi.map { ($0.id, $0.testo) }, uniquingKeysWith: { primo, _ in primo })
        if let attuale, let testo = testi[attuale.id], testo != attuale.testo {
            self.attuale?.testo = testo
        }
        for indice in inAttesa.indices {
            if let testo = testi[inAttesa[indice].id] { inAttesa[indice].testo = testo }
        }
        for indice in ridotti.indices {
            if let testo = testi[ridotti[indice].id], testo != ridotti[indice].testo { ridotti[indice].testo = testo }
        }
    }

    /// Chiude l'avviso a schermo (un tocco) e passa al prossimo, se c'è. Su una condizione in corso resta l'icona.
    func chiudi() {
        togli(riduci: true)
    }

    /// G2.2: un tocco sull'icona riapre l'avviso; quello a schermo torna in coda per primo.
    func riapri(_ id: String) {
        guard let indice = ridotti.firstIndex(where: { $0.id == id }) else { return }
        let avviso = ridotti.remove(at: indice)
        if let mostrato = attuale {
            compito?.cancel()
            compito = nil
            inAttesa.insert(mostrato, at: 0)
        }
        mostra(avviso, riaperto: true)
    }

    /// G2.8: VoiceOver acceso o spento: il tempo dell'avviso a schermo riparte con la regola nuova (`programma`).
    func voiceOverCambiato() {
        guard let attuale else { return }
        programma(attuale)
    }

    /// Alla fine della sessione.
    func ferma() {
        compito?.cancel()
        compito = nil
        inAttesa = []
        ridotti = []
        attuale = nil
    }

    private func togli(riduci: Bool) {
        compito?.cancel()
        compito = nil
        if riduci, let mostrato = attuale, mostrato.persiste, attivi.contains(mostrato.id),
           !ridotti.contains(where: { $0.id == mostrato.id }) {
            ridotti.append(mostrato)
        }
        attuale = nil
        avanza()
    }

    private func avanza() {
        guard attuale == nil, !inAttesa.isEmpty else { return }
        mostra(inAttesa.removeFirst())
    }

    private func mostra(_ avviso: Avviso, riaperto: Bool = false) {
        // G2.2: ogni avviso nel registro, la prima volta che compare (non quando si riapre dall'icona).
        if avviso.tipo == .avviso && !riaperto && (mostrati[avviso.id] == nil || finiti.contains(avviso.id)) {
            RegistroCollegamento.condiviso.aggiungi(String(localized: "Avviso: \(avviso.testo)"))
        }
        mostrati[avviso.id] = Date()
        finiti.remove(avviso.id)
        ridotti.removeAll { $0.id == avviso.id }
        attuale = avviso
        programma(avviso)
    }

    /// Dopo 6 secondi l'avviso si chiude. Uno che resta (G1.5) rimane finché dura la sua condizione, ma non ferma la
    /// coda: se altri avvisi aspettano, dopo 6 secondi lascia il posto al primo e torna subito dopo di lui.
    /// G2.8: con VoiceOver non si chiude da solo se non aspetta nessuno; se altri aspettano, lascia il posto dopo
    /// 20 secondi (la coda non si blocca su un avviso che nessuno tocca).
    private func programma(_ avviso: Avviso) {
        compito?.cancel()
        compito = nil
        let conVoiceOver = UIAccessibility.isVoiceOverRunning
        if conVoiceOver && inAttesa.isEmpty { return }
        if avviso.resta && !inAttesa.contains(where: { $0.tipo == .avviso }) { return }
        let durata = conVoiceOver ? Self.durataConVoiceOver : Self.durata
        compito = Task { [weak self] in
            try? await Task.sleep(for: durata)
            guard !Task.isCancelled, let self else { return }
            self.compito = nil
            withAnimation { self.scaduto() }
        }
    }

    private func scaduto() {
        guard let mostrato = attuale else { return }
        guard mostrato.resta else { togli(riduci: true); return }
        // Gli altri nel frattempo sono finiti: resta a schermo.
        guard let indice = inAttesa.firstIndex(where: { $0.tipo == .avviso }) else { return }
        let altro = inAttesa.remove(at: indice)
        inAttesa.insert(mostrato, at: 0)
        mostra(altro)
    }
}

/// «Dettagli» (1.14): i numeri tolti da sopra il video, con un tocco sulla riga di stato. Si aggiornano dal vivo.
private struct FoglioDettagli: View {
    let sessione: SessioneTelefono
    /// Il testo lungo della riga di stato («Collegato · MacBook», «In onda · Zoom», «Pronta · CAM 2»): con la riga
    /// nelle orecchie dell'isola sopra il video resta solo «● Wi-Fi».
    let stato: String
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            List {
                Section {
                    riga("Stato", stato)
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
                    // Telecomando: il computer fa gli effetti di immagine, dal telefono arriva il video così com'è.
                    if sessione.effettiSulComputer {
                        riga("Effetti", String(localized: "sul computer"))
                    }
                    // Qualità ed efficienza: fps spediti, bitrate reale, effetti, maschere e stato termico.
                    if let prestazioni = sessione.testoPrestazioni {
                        riga("Prestazioni", prestazioni)
                    }
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
                        .font(.stile(.nota))
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
            .tint(Tema.accento)
            .scrollContentBackground(.hidden)
            // Le liste sono nostre: Barlow (Documenti/Stile.md, «Barlow o sistema»).
            .font(.stile(.corpo))
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
        .tint(Tema.accento)
        .preferredColorScheme(.dark)
    }

    private func riga(_ titolo: LocalizedStringKey, _ valore: String) -> some View {
        LabeledContent(titolo) {
            Text(valore)
                .font(.stile(.numeri))
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

    /// «1080p30 · H.264»: il formato davvero inviato e, se è più basso di quello chiesto dal computer, il motivo in
    /// breve («1080p30 · H.264 · ridotta per il calore»).
    private var testoFormato: String {
        guard sessione.larghezza > 0 else { return "—" }
        let formato = "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps) · \(sessione.codec.nome)"
        guard let motivo = sessione.testoRiduzione else { return formato }
        return formato + " · " + motivo
    }

    /// «ISO 400 · 1/50 s»: il tempo mostrato è quello usato, mai più lungo di un fotogramma (e senza bande con le
    /// luci di casa, vedi `Cattura.tempoSenzaBande`).
    private var testoEsposizioneManuale: String {
        var parti: [String] = []
        if sessione.iso > 0 { parti.append("ISO \(Int(sessione.iso))") }
        if sessione.tempo > 0 {
            parti.append("1/\(Cattura.tempoSenzaBande(richiesto: sessione.tempo, fps: sessione.fps)) s")
        }
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
        HStack(spacing: Spazi.stretto) {
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
                .background(sessione.torciaAccesa ? Tema.accento : Veli.coloreForte, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Torcia")
        .accessibilityValue(sessione.torciaAccesa ? "accesa" : "spenta")
        .transition(.opacity)
    }

    private var obiettivi: some View {
        HStack(spacing: Spazi.minimo) {
            ForEach(sessione.obiettiviDisponibili) { obiettivo in
                let scelto = obiettivo == sessione.obiettivo
                Button {
                    sessione.scegli(obiettivo)
                } label: {
                    Text(obiettivo.etichetta)
                        .font(.stile(.numeri, .numeriEvidenti))
                        .foregroundStyle(scelto ? Tema.fondo : Tema.testo)
                        .frame(minWidth: 38, minHeight: 38)
                        .padding(.horizontal, obiettivo == .frontale || obiettivo == .tele ? Spazi.stretto : 0)
                        .background(scelto ? Tema.testo : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(obiettivo.nomeAccessibile)
                .accessibilityAddTraits(scelto ? .isSelected : [])
            }
        }
        .padding(Spazi.minimo)
        .background(Veli.coloreForte, in: Capsule())
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
    /// G2.1: in onda o in pausa la pillola grande (56, alta almeno 88), con e senza il nome dell'app; `nil` negli
    /// altri stati, che restano piccoli.
    let pillole: (conApp: PillolaStato, senzaApp: PillolaStato)?
    let mostraComandi: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { mostraComandi() }
            VStack {
                HStack {
                    if let pillole {
                        // Si toglie prima il nome dell'app; all'ultimo la pillola si stringe.
                        ViewThatFits(in: .horizontal) {
                            pillole.conApp.fixedSize()
                            pillole.senzaApp.fixedSize()
                            pillole.senzaApp
                        }
                    } else {
                        statoPiccolo
                    }
                    Spacer()
                }
                Spacer()
                Text("Tocca per i comandi")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoChiaro)
                    .padding(.horizontal, Spazi.piccolo)
                    .padding(.vertical, Spazi.stretto)
                    .background(Veli.coloreLieve, in: Capsule())
            }
            .padding(.horizontal, Spazi.piccolo)
            .padding(.vertical, Spazi.stretto)
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { mostraComandi() }
    }

    /// Gli altri stati (collegato, CAM 2): il punto e lo stato, piccoli come prima.
    private var statoPiccolo: some View {
        HStack(spacing: Spazi.stretto) {
            Circle()
                .fill(puntoColore)
                .frame(width: 8, height: 8)
            Text(testo)
                .font(.stile(.sezione))
                .tracking(0.8)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(Tema.testo)
        .padding(.horizontal, Spazi.piccolo)
        .frame(minHeight: 30)
        .background(Veli.coloreLieve, in: Capsule())
    }
}

/// Schermo nero durante l'uso (funzione 32): il video continua, lo schermo non consuma.
private struct SchermoOscurato: View {
    let sessione: SessioneTelefono

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Spazi.medio) {
                if let pillola = pillolaGrande {
                    // G2.1: «IN ONDA» corallo pieno (o «IN PAUSA» ambra) da leggere a 2–3 metri, e sotto il computer.
                    pillola
                    Text(verbatim: sessione.computer.nome)
                        .font(.stile(.titolo, .etichette))
                } else {
                    HStack(spacing: Spazi.stretto) {
                        Circle()
                            .fill(colorePunto)
                            .frame(width: 9, height: 9)
                        Text(testoStato)
                            .font(.stile(.titolo, .etichette))
                    }
                }
                // In orizzontale su una riga; in verticale non ci sta: collegamento sopra, telefono sotto.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spazi.medio) {
                        datiCollegamento
                        datiTelefono
                    }
                    VStack(spacing: Spazi.stretto) {
                        HStack(spacing: Spazi.medio) { datiCollegamento }
                        HStack(spacing: Spazi.medio) { datiTelefono }
                    }
                }
                .font(.stile(.numeri))
                .padding(.horizontal, Spazi.medio)
                Text("Tocca due volte per riaccendere lo schermo")
                    .font(.stile(.nota))
                    .padding(.top, Spazi.medio)
            }
            // Con il testo grande o un nome di computer lungo le righe vanno a capo: centrate, lontane dai bordi.
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spazi.largo)
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

    /// G2.1: la pillola grande di Stile (etichetta 56, alta almeno 88): corallo in onda, ambra in pausa (A1).
    /// Negli altri stati (collegato, CAM 2, riconnessione) resta la riga di sempre.
    private var pillolaGrande: PillolaStato? {
        guard sessione.stato == .collegato else { return nil }
        if sessione.pausa.motivo != nil {
            return PillolaStato(.riconnessione, testo: String(localized: "In pausa"), dimensione: StileTesto.statoGrande.misura)
        }
        guard !sessione.prontaCam2, sessione.inOnda != nil else { return nil }
        return PillolaStato(.inOnda(app: nil), dimensione: StileTesto.statoGrande.misura)
    }

    /// Anche a schermo spento il rosso compare solo quando un'app usa davvero la webcam. Sullo schermo nero i punti
    /// sono attenuati di proposito (0,7: niente bagliore al buio), tranne il corallo di «in onda».
    private var colorePunto: Color {
        guard sessione.stato == .collegato else { return Tema.ambra.opacity(0.7) }
        // A1: in pausa ambra, mai corallo.
        if sessione.pausa.motivo != nil { return Tema.ambra.opacity(0.7) }
        if sessione.prontaCam2 { return Tema.accento.opacity(0.7) }
        return sessione.inOnda != nil ? Tema.tally : Tema.verde.opacity(0.7)
    }

    private var testoStato: String {
        guard sessione.stato == .collegato else { return String(localized: "Riconnessione…") }
        if sessione.pausa.motivo != nil { return String(localized: "In pausa") }
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

/// G1.7: «In onda» è una pagina spinta nella pila di `SchermataConnessione` e chiuderla termina la sessione. Con la
/// barra nascosta lo scorrimento dal bordo sinistro di iOS resterebbe attivo e scollegherebbe senza la domanda della
/// X: qui si spegne finché la pagina è a schermo e si riaccende come era quando la pagina se ne va.
/// Perché non un `fullScreenCover`: la lista dei computer conta sul suo `onDisappear` (ricerca ferma, ricollegamento
/// annullato) e sull'apertura a spinta; con una presentazione a schermo intero sotto resterebbe «visibile».
private struct BloccoIndietro: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controllore { Controllore() }
    func updateUIViewController(_ controllore: Controllore, context: Context) {}

    final class Controllore: UIViewController {
        private weak var gesto: UIGestureRecognizer?
        private var eraAttivo = true

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            blocca()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            blocca()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            blocca()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            gesto?.isEnabled = eraAttivo
            gesto = nil
        }

        /// Il controller della pila si trova risalendo i genitori (il controller di SwiftUI che ospita la pagina).
        private func blocca() {
            guard gesto == nil, let indietro = navigationController?.interactivePopGestureRecognizer else { return }
            eraAttivo = indietro.isEnabled
            indietro.isEnabled = false
            gesto = indietro
        }
    }
}
