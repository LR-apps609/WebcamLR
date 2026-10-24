import AVFoundation
import Stile
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import WebcamLRProtocollo

/// Schermata «In onda» (bozza grafica, iPhone 3) e schermo oscurato (iPhone 6).
/// La sessione nasce in `SchermataConnessione` quando si sceglie il computer: così la fotocamera
/// e il collegamento si creano una volta sola, anche se SwiftUI ricostruisce questa vista.
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
    @State private var compitoOscuramento: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaFotocamera(livello: sessione.cattura.anteprima, azioni: azioniAnteprima)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel("Anteprima della fotocamera")
                .accessibilityHint("Tocca per mettere a fuoco, tieni premuto per bloccare messa a fuoco ed esposizione, tocca due volte per cambiare fotocamera.")
                .accessibilityAction(named: "Cambia fotocamera") { sessione.cambiaFotocamera() }
            if let punto = sessione.puntoFuoco {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Tema.ambra, lineWidth: 2)
                    .frame(width: 84, height: 84)
                    .position(punto)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if griglia {
                GrigliaTerzi()
                    .ignoresSafeArea()
            }
            if livellaAccesa {
                LineaLivella(livella: livella)
            }

            sovrapposizioni
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                // I testi crescono con la dimensione scelta nel sistema, ma senza coprire tutto il video.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            if sessione.oscurato {
                SchermoOscurato(sessione: sessione)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            // La sessione è già partita al tocco su «Collega» (SchermataConnessione), non a fine animazione.
            if livellaAccesa { livella.avvia() }
            rimandaOscuramento()
        }
        .onDisappear {
            sessione.termina()
            livella.ferma()
            compitoOscuramento?.cancel()
        }
    }

    /// Ogni tocco fa ripartire i 30 secondi. Si oscura solo col video che va: davanti a un errore
    /// o durante la riconnessione lo schermo resta acceso. Con VoiceOver non si oscura da solo.
    private func rimandaOscuramento() {
        compitoOscuramento?.cancel()
        guard oscuraDaSolo else { return }
        compitoOscuramento = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                if sessione.stato == .collegato && !UIAccessibility.isVoiceOverRunning {
                    if !sessione.oscurato {
                        withAnimation { sessione.oscurato = true }
                    }
                    return
                }
            }
        }
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
            },
            qualsiasiTocco: { rimandaOscuramento() }
        )
    }

    private var sovrapposizioni: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // In verticale lo spazio è poco: stato, dati tecnici e batteria vanno uno sotto l'altro.
                if classeVerticale == .regular {
                    VStack(alignment: .leading, spacing: 8) {
                        PillolaStato(statoPillola, testo: testoPillola)
                        if sessione.stato == .collegato {
                            Chip { telemetria }
                        }
                        Chip { Text(testoBatteria) }
                    }
                } else {
                    HStack(spacing: 8) {
                        PillolaStato(statoPillola, testo: testoPillola)
                        if sessione.stato == .collegato {
                            Chip { telemetria }
                        }
                        Spacer(minLength: 0)
                        Chip { Text(testoBatteria) }
                    }
                }
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
                // Le frasi con il carattere di sistema, i numeri tecnici con quello a spaziatura fissa.
                if sessione.reteDebole && sessione.stato == .collegato {
                    Chip { Text("Rete lenta: qualità abbassata da sola").font(.footnote.weight(.medium)).foregroundStyle(Tema.ambraTesto) }
                }
                if sessione.qualitaRidotta {
                    Chip { Text("Telefono molto caldo: qualità ridotta a 720p").font(.footnote.weight(.medium)).foregroundStyle(Tema.ambraTesto) }
                }
                if sessione.batteriaBassa {
                    Chip {
                        Text(sessione.risparmioBatteria
                             ? "Batteria al \(sessione.batteria)%: 24 fps per risparmiare, collega il caricatore"
                             : "Batteria al \(sessione.batteria)%: collega il caricatore")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Tema.ambraTesto)
                    }
                }
                if classeVerticale == .regular {
                    Chip { Text("Gira l'iPhone in orizzontale per un'inquadratura larga").font(.footnote) }
                }
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

    private var telemetria: some View {
        HStack(spacing: 10) {
            // Round 2: la qualità in parole, come sul computer; i millisecondi restano accanto, più tenui
            // (VoiceOver li legge già nella qualità).
            if let latenza = sessione.latenzaMs {
                ChipQualita(qualita, latenzaMs: latenza)
                Text("\(latenza) ms")
                    .foregroundStyle(Tema.testoSecondario)
                    .accessibilityHidden(true)
            } else {
                Text("— ms")
            }
            Text(sessione.larghezza > 0 ? "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps)" : "—")
            Text("Wi-Fi")
            if sessione.zoom > 1.05 {
                Text(String(format: "%.1f×", sessione.zoom).replacingOccurrences(of: ".", with: ","))
            }
            // Esposizione manuale dal computer: la luce non si adatta più da sola.
            // Il tempo mostrato è quello usato: mai più lungo di un fotogramma.
            if sessione.iso > 0 || sessione.tempo > 0 {
                Text([sessione.iso > 0 ? "ISO \(Int(sessione.iso))" : nil,
                      sessione.tempo > 0 ? "1/\(max(sessione.tempo, sessione.fps)) s" : nil].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(Tema.ambraTesto)
            }
        }
        .lineLimit(1)
    }

    /// In orizzontale sugli iPhone più bassi i pulsanti non stanno tutti: allora la barra scorre.
    private var barraComandi: some View {
        ViewThatFits(in: .vertical) {
            pulsantiBarra
            ScrollView(.vertical, showsIndicators: false) { pulsantiBarra }
        }
        .background(Tema.fondo.opacity(0.82), in: RoundedRectangle(cornerRadius: 30))
        .frame(maxHeight: .infinity)
    }

    private var pulsantiBarra: some View {
        VStack(spacing: 10) {
            // Il microfono e i controlli Pro non ci sono ancora: si vede che arrivano, non che sono rotti.
            InArrivo(etichetta: "Microfono") {
                Image(systemName: "mic")
                    .font(.system(size: 17, weight: .medium))
            }
            PulsanteTondo("Torcia", icona: sessione.torciaAccesa ? "flashlight.on.fill" : "flashlight.off.fill",
                          attivo: sessione.torciaAccesa) {
                sessione.cambiaTorcia()
            }
            .disabled(!sessione.torciaDisponibile)
            .opacity(sessione.torciaDisponibile ? 1 : 0.4)
            // Gli effetti video di iOS (Ritratto, Luce da studio): il pannello è quello di sistema.
            PulsanteTondo("Effetti video", icona: "person.and.background.dotted") {
                AVCaptureDevice.showSystemUserInterface(.videoEffects)
            }
            InArrivo(etichetta: "Controlli Pro") {
                Text("PRO")
                    .font(.titolo(16))
            }
            PulsanteTondo("Oscura lo schermo", icona: "moon.fill") {
                withAnimation { sessione.oscurato = true }
            }
            Button {
                chiudi()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(Tema.bordo))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scollega")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    /// Stesse soglie di Mac e Windows (Stile `QualitaCollegamento`), con i fotogrammi scartati dal telefono.
    private var qualita: QualitaCollegamento {
        QualitaCollegamento(latenzaMs: sessione.latenzaMs ?? 0, perdite: sessione.perditeRecenti)
    }

    /// Il banner compare mentre si ritrova il computer perso, anche dopo «Riprova ora».
    private var inizioRiconnessioneVisibile: Date? {
        switch sessione.stato {
        case .riconnessione, .collegamento: sessione.inizioRiconnessione
        case .collegato, .chiusa, .errore: nil
        }
    }

    /// Riconnessione chiara (round 2): da quanti secondi si cerca il computer, e «Riprova ora».
    private func bannerRiconnessione(da inizio: Date) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Tema.ambraTesto)
            TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                VStack(alignment: .leading, spacing: 2) {
                    // Se non ci si è mai collegati il computer non è «perso».
                    Text(!sessione.reteDisponibile
                         ? "Nessuna rete: mi ricollego appena torna il Wi-Fi…"
                         : sessione.giaCollegato
                         ? "Computer perso, mi ricollego…"
                         : "Non riesco a collegarmi a \(sessione.computer.nome), riprovo…")
                        .font(.subheadline.weight(.semibold))
                    Text(secondi == 1 ? "da 1 secondo" : "da \(secondi) secondi")
                        .font(.numeri(12.5))
                }
                .foregroundStyle(Tema.ambraTesto)
            }
            Spacer(minLength: 8)
            Button("Riprova ora") { sessione.riprova() }
                .fontWeight(.semibold)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Tema.ciano, in: Capsule())
                .foregroundStyle(Tema.fondo)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Tema.ambraTenue.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
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
            Text("Su \(sessione.computer.nome) consenti questo iPhone, se il codice di conferma è lo stesso:")
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
            HStack {
                // Identità cambiata: riprovare non serve, si riabbina con il QR code dalla lista dei computer.
                if !sessione.erroreDefinitivo {
                    Button("Riprova") { sessione.riprova() }
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Tema.ciano, in: Capsule())
                        .foregroundStyle(Tema.fondo)
                }
                Button("Torna ai computer") { chiudi() }
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
            }
        }
        .padding(16)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Tema.fondo.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Tema.testo)
    }

    private var statoPillola: StatoCollegamento {
        switch sessione.stato {
        case .collegato where sessione.inOnda != nil: .inOnda(app: sessione.inOnda?.app)
        case .collegato: .collegato
        case .collegamento, .riconnessione: .riconnessione
        case .chiusa, .errore: .nessunTelefono
        }
    }

    private var testoPillola: String {
        switch sessione.stato {
        case .collegato where sessione.inOnda != nil: sessione.inOnda?.app.map { "In onda · \($0)" } ?? "In onda"
        case .collegato: "Collegato · \(sessione.computer.nome)"
        case .collegamento: "Collegamento…"
        case .riconnessione(let tentativo): "Riconnessione \(tentativo)/\(SessioneTelefono.tentativiMassimi)"
        case .chiusa, .errore: "Scollegato"
        }
    }

    private var testoBatteria: String {
        let batteria = sessione.batteria >= 0 ? "\(sessione.batteria)%" : "—"
        return "\(batteria) · temperatura \(sessione.temperatura.descrizione)"
    }
}

extension Temperatura {
    var descrizione: String {
        switch self {
        case .normale: "normale"
        case .calda: "calda"
        case .moltoCalda: "molto calda"
        case .critica: "critica"
        }
    }
}

extension Obiettivo {
    /// Per VoiceOver: «0,5×» o «Tele» da soli non dicono molto.
    var nomeAccessibile: String {
        switch self {
        case .grandangolo: "Grandangolo 0,5×"
        case .principale: "Principale 1×"
        case .tele: "Teleobiettivo"
        case .frontale: "Fotocamera frontale"
        }
    }
}

/// Un comando che arriverà: tondo come gli altri ma tratteggiato, con «PRESTO» sotto l'icona.
private struct InArrivo<Icona: View>: View {
    let etichetta: String
    @ViewBuilder let icona: Icona

    var body: some View {
        VStack(spacing: 1) {
            icona
            Text("PRESTO")
                .font(.etichetta(9))
                .tracking(0.5)
        }
        .foregroundStyle(Tema.testoSecondario)
        .frame(width: 48, height: 48)
        .overlay(Circle().stroke(Tema.bordo, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        // Non scala con la dimensione del testo: deve restare dentro il tondo.
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(etichetta): in arrivo")
    }
}

/// Riquadro scuro semitrasparente per i dati tecnici sopra il video.
private struct Chip<Contenuto: View>: View {
    @ViewBuilder let contenuto: Contenuto

    var body: some View {
        HStack(spacing: 8) { contenuto }
            .font(.numeri(12.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: 30)
            // Su una riga è una capsula; se il testo va a capo (testo grande) resta ordinato.
            .background(Tema.fondo.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct SelettoreObiettivo: View {
    let sessione: SessioneTelefono

    var body: some View {
        HStack(spacing: 6) {
            ForEach(sessione.obiettiviDisponibili) { obiettivo in
                let scelto = obiettivo == sessione.obiettivo
                Button {
                    sessione.scegli(obiettivo)
                } label: {
                    Text(obiettivo.etichetta)
                        .font(.numeriEvidenti(scelto ? 14 : 13))
                        .foregroundStyle(scelto ? Tema.fondo : .white)
                        .frame(minWidth: scelto ? 44 : 40, minHeight: scelto ? 44 : 40)
                        .padding(.horizontal, obiettivo == .frontale || obiettivo == .tele ? 6 : 0)
                        .background(scelto ? Tema.testo : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(obiettivo.nomeAccessibile)
                .accessibilityAddTraits(scelto ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Tema.fondo.opacity(0.72), in: Capsule())
    }
}

/// Linee dei terzi, come nel mirino della bozza.
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
            .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Livella al centro dello schermo: la linea segue l'orizzonte e diventa verde entro ±1°.
private struct LineaLivella: View {
    let livella: Livella

    var body: some View {
        if let scostamento = livella.scostamento {
            let colore = livella.dritto ? Tema.verde : Color.white.opacity(0.75)
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
            .shadow(color: .black.opacity(0.5), radius: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
                HStack(spacing: 16) {
                    Text(sessione.latenzaMs.map { latenza in
                        "\(QualitaCollegamento(latenzaMs: latenza, perdite: sessione.perditeRecenti).testo) · \(latenza) ms"
                    } ?? "— ms")
                    Text(sessione.larghezza > 0 ? "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps)" : "—")
                    Text(sessione.batteria >= 0 ? "batteria \(sessione.batteria)%" : "batteria —")
                    Text("temperatura \(sessione.temperatura.descrizione)")
                }
                .font(.numeri(13))
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
        .accessibilityAction(named: "Riaccendi lo schermo") {
            sessione.oscurato = false
        }
    }

    /// Anche a schermo spento il rosso compare solo quando un'app usa davvero la webcam.
    private var colorePunto: Color {
        guard sessione.stato == .collegato else { return Tema.ambra.opacity(0.7) }
        return sessione.inOnda != nil ? Tema.tally : Tema.verde.opacity(0.7)
    }

    private var testoStato: String {
        guard sessione.stato == .collegato else { return "Riconnessione…" }
        return sessione.inOnda != nil ? "In onda su \(sessione.computer.nome)" : "Collegato a \(sessione.computer.nome)"
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
                if let livello { layer.addSublayer(livello) }
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
        }
    }

    func makeCoordinator() -> Coordinatore {
        Coordinatore(azioni: azioni)
    }

    func makeUIView(context: Context) -> Vista {
        let vista = Vista()
        vista.backgroundColor = .black
        vista.livello = livello

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
        context.coordinator.azioni = azioni
    }
}
