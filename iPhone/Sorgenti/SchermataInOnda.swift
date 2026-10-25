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
/// 1.14: sopra il video solo una riga di stato (i numeri sono nei «Dettagli», con un tocco sulla riga), un avviso
/// alla volta che si chiude da solo, e sei pulsanti: Specchia, Sfoca sfondo, Microfono, Torcia (solo se c'è),
/// Pausa, Impostazioni; «Scollega» a parte, in fondo. Effetti, inquadratura, assistente e controlli Pro si aprono
/// dalle Impostazioni.
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
    /// B2: il foglio «Effetti» (filtri, regolazioni, sfondo, pelle, scritta), a metà schermo sopra l'anteprima.
    @State private var mostraEffetti = false
    /// P16: ISO, tempo, bianco, compensazione e messa a fuoco manuali.
    @State private var mostraControlliPro = false
    /// Le funzioni del volto (inquadratura, luce, postura, volto e scrivania).
    @State private var mostraAssistente = false
    /// Gli avvisi sopra il video, uno alla volta.
    @State private var avvisi = CodaAvvisi()
    /// Lo zoom si legge al centro solo mentre si pizzica, come nella Fotocamera.
    @State private var zoomVisibile = false
    @State private var compitoZoom: Task<Void, Never>? = nil

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

            sovrapposizioni
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                // I testi crescono con la dimensione scelta nel sistema, ma senza coprire tutto il video.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            // P06: il gobbo in alto, vicino all'obiettivo; sopra i dati ma mai sopra la barra dei comandi.
            if sessione.gobbo.visibile {
                posizioneGobbo
                    .transition(.opacity)
            }

            if sessione.oscurato {
                SchermoOscurato(sessione: sessione)
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
                SchermataImpostazioni(duranteLaSessione: true) { foglio in
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
        .sheet(isPresented: $mostraEffetti, onDismiss: { rimandaOscuramento() }) {
            SchermataEffetti(visivi: sessione.visivi, anteprima: sessione.effetti.anteprima) {
                mostraEffetti = false
            }
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $mostraControlliPro, onDismiss: { rimandaOscuramento() }) {
            FoglioControlliPro(sessione: sessione)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $mostraAssistente, onDismiss: { rimandaOscuramento() }) {
            FoglioAssistente(sessione: sessione)
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
        .onAppear {
            // La sessione è già partita al tocco su «Collega» (SchermataConnessione), non a fine animazione.
            if livellaAccesa { livella.avvia() }
            rimandaOscuramento()
            avvisi.aggiorna(avvisiAttivi)
        }
        .onDisappear {
            sessione.termina()
            livella.ferma()
            compitoOscuramento?.cancel()
            compitoZoom?.cancel()
            avvisi.ferma()
        }
    }

    /// Un foglio scelto nelle Impostazioni, aperto dopo che si sono chiuse.
    private func apri(_ foglio: FoglioSessione) {
        compitoOscuramento?.cancel()
        switch foglio {
        case .effetti: mostraEffetti = true
        case .assistente: mostraAssistente = true
        case .controlliPro: mostraControlliPro = true
        }
    }

    /// Ogni tocco fa ripartire i 30 secondi. Si oscura solo col video che va: davanti a un errore
    /// o durante la riconnessione lo schermo resta acceso. Con VoiceOver non si oscura da solo.
    private func rimandaOscuramento() {
        compitoOscuramento?.cancel()
        // Con un foglio aperto lo schermo non si oscura sotto il foglio: si riparte alla chiusura.
        let foglioAperto = mostraImpostazioni || mostraEffetti || mostraControlliPro || mostraAssistente
            || mostraDettagli || domandaAperta != nil
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

    /// P06: in verticale il gobbo sta sotto la fotocamera frontale, in alto. In orizzontale l'obiettivo è su un lato:
    /// il gobbo resta in alto ma si stringe verso quel lato (il lato del bordo superiore del telefono).
    private var posizioneGobbo: some View {
        let orizzontale = classeVerticale == .compact
        let fotocameraASinistra = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first == .landscapeRight
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if orizzontale && !fotocameraASinistra { Spacer(minLength: 0) }
                VistaGobbo(gobbo: sessione.gobbo, righeVisibili: orizzontale ? 3 : 4)
                    .frame(maxWidth: orizzontale ? 560 : .infinity)
                if orizzontale && fotocameraASinistra { Spacer(minLength: 0) }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        // La barra dei comandi a destra resta libera (larghezza della barra e margini).
        .padding(.trailing, 88)
        .padding(.top, 6)
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

    /// Griglia, livella, riquadro del fuoco e zoom: solo dentro il video vero (adattato senza tagli,
    /// `resizeAspect`), mai sulle bande nere. Stesse coordinate dell'anteprima, che occupa tutto lo schermo.
    private var sopraIlVideo: some View {
        GeometryReader { area in
            let video = Self.rettangoloVideo(in: area.size, video: sessione.dimensioniVideo)
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
                        .position(Self.dentro(video, punto: punto, margine: 42))
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
        }
    }

    /// Il rettangolo del video adattato senza tagli nell'area (come `resizeAspect`). Senza misure, tutta l'area.
    static func rettangoloVideo(in area: CGSize, video: CGSize) -> CGRect {
        guard video.width > 0, video.height > 0, area.width > 0, area.height > 0 else {
            return CGRect(origin: .zero, size: area)
        }
        let scala = min(area.width / video.width, area.height / video.height)
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

    private var sovrapposizioni: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                rigaStato
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
                HStack {
                    Spacer()
                    SelettoreObiettivo(sessione: sessione)
                    Spacer()
                }
            }
            barraComandi
        }
        .accessibilityElement(children: .contain)
    }

    /// Una riga sola: «● Collegato · MacBook» (o «● In onda», col punto corallo solo allora), il collegamento e le
    /// tacche della qualità. Un tocco apre i «Dettagli». Se il nome non ci sta, resta «Collegato»: mai troncato.
    private var rigaStato: some View {
        Button {
            compitoOscuramento?.cancel()
            mostraDettagli = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(colorePuntoStato)
                    .frame(width: 8, height: 8)
                ViewThatFits(in: .horizontal) {
                    Text(testoStato).fixedSize()
                    Text(testoStatoBreve).fixedSize()
                }
                .font(.etichetta(16))
                .tracking(0.6)
                .textCase(.uppercase)
                .lineLimit(1)
                if sessione.stato == .collegato {
                    if let tipo = sessione.tipoCollegamento {
                        Image(systemName: tipo.simbolo)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tema.testoSecondario)
                    }
                    if sessione.latenzaMs != nil {
                        TaccheQualita(qualita: qualita)
                    }
                }
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

    /// Per VoiceOver: lo stato e, se si sa, la qualità.
    private var etichettaStato: String {
        guard sessione.stato == .collegato, sessione.latenzaMs != nil else { return testoStato }
        return String(localized: "\(testoStato), collegamento \(qualita.testo.lowercased())")
    }

    private var colorePuntoStato: Color {
        switch sessione.stato {
        // Il corallo solo quando un'app usa davvero la webcam.
        case .collegato where sessione.inOnda != nil: Tema.tally
        case .collegato: Tema.verde
        case .collegamento, .riconnessione: Tema.ambra
        case .chiusa, .errore: Tema.testoTenue
        }
    }

    private var testoStato: String {
        switch sessione.stato {
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

    // MARK: - Barra dei comandi

    /// Sei pulsanti in alto, «Scollega» da solo in fondo. In orizzontale sugli iPhone più bassi i pulsanti non
    /// stanno tutti: allora la barra scorre.
    private var barraComandi: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .vertical) {
                pulsantiBarra
                ScrollView(.vertical, showsIndicators: false) { pulsantiBarra }
            }
            .background(Tema.fondo.opacity(0.82), in: RoundedRectangle(cornerRadius: 30))
            .layoutPriority(1)
            Spacer(minLength: 0)
            pulsanteScollega
        }
        .frame(maxHeight: .infinity)
    }

    private var sfondoSfocato: Bool { sessione.visivi.sfondo == ModiSfondo.sfocato }
    private var inPausa: Bool { sessione.pausa.utente }

    private var pulsantiBarra: some View {
        VStack(spacing: 10) {
            // Specchia il video che arriva al computer, subito; nell'accento quando è acceso.
            PulsanteTondo(String(localized: "Specchia"), icona: "flip.horizontal", attivo: sessione.specchiato) {
                sessione.impostaSpecchio(!sessione.specchiato)
            }
            .accessibilityValue(sessione.specchiato ? "acceso" : "spento")
            .accessibilityHint("Specchia il video che arriva al computer")
            // Un tocco: sfocato o niente, con l'intensità scelta nel foglio Effetti (anche dal computer).
            PulsanteTondo(String(localized: "Sfoca sfondo"), icona: "person.and.background.dotted", attivo: sfondoSfocato) {
                sessione.visivi.scegliSfondo(sfondoSfocato ? ModiSfondo.nessuno : ModiSfondo.sfocato)
            }
            .accessibilityValue(sfondoSfocato ? "acceso" : "spento")
            // P20: il microfono del telefono verso il computer, nell'accento quando è chiesto.
            PulsanteTondo(String(localized: "Microfono al computer"), icona: sessione.audioRichiesto ? "mic.fill" : "mic.slash",
                          attivo: sessione.audioRichiesto) {
                sessione.impostaAudio(!sessione.audioRichiesto)
            }
            .accessibilityValue(sessione.audioRichiesto ? "acceso" : "spento")
            .accessibilityHint("Manda l'audio del microfono dell'iPhone al computer")
            // La torcia solo dove c'è: con la frontale sparisce, non resta grigia.
            if sessione.torciaDisponibile {
                PulsanteTondo(String(localized: "Torcia"), icona: sessione.torciaAccesa ? "flashlight.on.fill" : "flashlight.off.fill",
                              attivo: sessione.torciaAccesa) {
                    sessione.cambiaTorcia()
                }
                .accessibilityValue(sessione.torciaAccesa ? "accesa" : "spenta")
            }
            // Il video si ferma, il collegamento resta (come a faccia in giù).
            PulsanteTondo(inPausa ? String(localized: "Riprendi") : String(localized: "Pausa"),
                          icona: inPausa ? "play.fill" : "pause.fill", attivo: inPausa) {
                sessione.pausa.impostaPausaUtente(!inPausa)
            }
            // P03: le Impostazioni, e da lì effetti, inquadratura, assistente e controlli Pro.
            PulsanteTondo(String(localized: "Impostazioni"), icona: "gearshape", attivo: controlliManuali) {
                compitoOscuramento?.cancel()
                mostraImpostazioni = true
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    private var pulsanteScollega: some View {
        Button {
            chiudi()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tema.testo)
                .frame(width: 48, height: 48)
                .background(Tema.fondo.opacity(0.82), in: Circle())
                .overlay(Circle().stroke(Tema.bordo))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel("Scollega")
    }

    /// P16: almeno un valore della fotocamera è scelto a mano (dal telefono o dal computer): le Impostazioni,
    /// da cui si aprono i controlli Pro, restano nell'accento.
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
                AzioniDiagnosi(diagnosi: diagnosi) { domanda in domandaAperta = DomandaDaAprire(id: domanda) }
            } else if let domanda = sessione.domandaErrore {
                Button("Perché succede?") { domandaAperta = DomandaDaAprire(id: domanda) }
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
        Button("Torna ai computer") { chiudi() }
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
private struct SelettoreObiettivo: View {
    let sessione: SessioneTelefono

    var body: some View {
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
        return sessione.inOnda != nil ? Tema.tally : Tema.verde.opacity(0.7)
    }

    private var testoStato: String {
        guard sessione.stato == .collegato else { return String(localized: "Riconnessione…") }
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
            livello?.frame = bounds
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
