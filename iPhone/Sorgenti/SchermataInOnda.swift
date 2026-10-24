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
    /// 1.5: spenta si vedono qualità e tipo di collegamento; accesa anche millisecondi, risoluzione e formato.
    @AppStorage("modalitaAvanzata") private var modalitaAvanzata = false
    /// La risposta che spiega l'errore (1.4), in un foglio.
    @State private var domandaAperta: DomandaDaAprire?
    /// Il registro del collegamento (1.5) aperto da qui, in modalità avanzata.
    @State private var mostraRegistro = false
    /// P03: le Impostazioni anche durante la sessione, in un foglio con «Fine».
    @State private var mostraImpostazioni = false
    /// B2: il foglio «Effetti» (filtri, regolazioni, sfondo, pelle, scritta), a metà schermo sopra l'anteprima.
    @State private var mostraEffetti = false
    /// P16: ISO, tempo, bianco, compensazione e messa a fuoco manuali, solo in modalità avanzata.
    @State private var mostraControlliPro = false
    /// Una riga breve dopo il tocco su «Modalità avanzata»: dice cosa è cambiato.
    @State private var avvisoBreve: String?
    @State private var compitoAvviso: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaFotocamera(livello: sessione.cattura.anteprima, livelloEffetti: sessione.effetti.anteprima.livello,
                                azioni: azioniAnteprima)
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
        .sheet(item: $domandaAperta) { domanda in
            FoglioDomande(aperta: domanda.id)
        }
        .sheet(isPresented: $mostraRegistro) {
            NavigationStack {
                VistaRegistro()
                    .navigationTitle("Registro del collegamento")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        // A destra ci sono già «Condividi» e «Svuota» del registro.
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Fine") { mostraRegistro = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .tint(Tema.ciano)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $mostraImpostazioni, onDismiss: {
            // Risoluzione, fotogrammi e formato cambiati: la fotocamera si riconfigura una volta, qui.
            sessione.applicaImpostazioni()
            rimandaOscuramento()
        }) {
            NavigationStack {
                SchermataImpostazioni(duranteLaSessione: true)
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
        .onChange(of: modalitaAvanzata) { _, accesa in
            if !accesa { mostraControlliPro = false }
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
        .onAppear {
            // La sessione è già partita al tocco su «Collega» (SchermataConnessione), non a fine animazione.
            if livellaAccesa { livella.avvia() }
            rimandaOscuramento()
        }
        .onDisappear {
            sessione.termina()
            livella.ferma()
            compitoOscuramento?.cancel()
            compitoAvviso?.cancel()
        }
    }

    /// Ogni tocco fa ripartire i 30 secondi. Si oscura solo col video che va: davanti a un errore
    /// o durante la riconnessione lo schermo resta acceso. Con VoiceOver non si oscura da solo.
    private func rimandaOscuramento() {
        compitoOscuramento?.cancel()
        // Con le Impostazioni aperte lo schermo non si oscura sotto il foglio: si riparte alla chiusura.
        guard oscuraDaSolo, !mostraImpostazioni, !mostraEffetti, !mostraControlliPro, !sessione.gobbo.visibile else { return }
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
                        chipDati
                        Chip { Text(testoBatteria) }
                    }
                } else {
                    // In orizzontale tutto su una riga, se ci sta; sugli iPhone piccoli, con nomi lunghi o testo
                    // grande, i dati tecnici vanno sulla riga sotto invece di essere troncati.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            PillolaStato(statoPillola, testo: testoPillola)
                            chipDati
                            Spacer(minLength: 0)
                            Chip { Text(testoBatteria) }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                PillolaStato(statoPillola, testo: testoPillola)
                                Spacer(minLength: 0)
                                Chip { Text(testoBatteria) }
                            }
                            HStack(spacing: 8) { chipDati }
                        }
                    }
                }
                // P20: il microfono va al computer. Ciano, non rosso: il rosso è solo per «In onda».
                if sessione.staInviandoAudio {
                    Chip {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tema.cianoChiaro)
                            .accessibilityHidden(true)
                        Text("Microfono al computer").font(.footnote.weight(.medium)).foregroundStyle(Tema.cianoChiaro)
                    }
                }
                if let avviso = sessione.avvisoMicrofono {
                    Chip { Text(avviso).font(.footnote.weight(.medium)).foregroundStyle(Tema.ambraTesto) }
                }
                if let avvisoBreve {
                    Chip { Text(avvisoBreve).font(.footnote.weight(.medium)).foregroundStyle(Tema.cianoChiaro) }
                        .transition(.opacity)
                }
                if modalitaAvanzata {
                    pulsanteRegistro
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
                if let consiglio = consiglioCollegamento {
                    Chip {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tema.testoSecondario)
                            .accessibilityHidden(true)
                        Text(consiglio).font(.footnote.weight(.medium)).foregroundStyle(Tema.testoChiaro)
                    }
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
                // P11 e P07/P10: promemoria della postura e pause.
                BannerAssistente(sessione: sessione)
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

    /// «1080p30 · H.264», solo in modalità avanzata.
    private var testoFormato: String {
        guard sessione.larghezza > 0 else { return "—" }
        return "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps) · \(sessione.codec.nome)"
    }

    /// «ISO 400 · 1/50 s»: scritto a parte, così il compilatore non fatica a dedurre i tipi.
    private var testoEsposizioneManuale: String {
        var parti: [String] = []
        if sessione.iso > 0 { parti.append("ISO \(Int(sessione.iso))") }
        if sessione.tempo > 0 { parti.append("1/\(max(sessione.tempo, sessione.fps)) s") }
        return parti.joined(separator: " · ")
    }

    /// Qualità e collegamento; in modalità avanzata un secondo riquadro con formato e avvio,
    /// così sugli schermi stretti la qualità non viene troncata.
    @ViewBuilder private var chipDati: some View {
        if sessione.stato == .collegato {
            Chip { telemetria }
            if modalitaAvanzata {
                Chip { datiAvanzati }
            }
        }
    }

    /// Solo in modalità avanzata: «1080p30 · H.264» e, 1.11, quanto ci è voluto ad avere il video sul computer.
    private var datiAvanzati: some View {
        HStack(spacing: 10) {
            Text(testoFormato)
            if let avvio = sessione.tempoAvvio {
                Text("Avvio: \(MisuraAvvio.testo(avvio))")
            }
        }
        .lineLimit(1)
    }

    /// Modalità avanzata (1.5): il registro del collegamento anche da qui, senza tornare ai computer.
    private var pulsanteRegistro: some View {
        Button {
            mostraRegistro = true
        } label: {
            Label("Registro del collegamento", systemImage: "list.bullet.rectangle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Tema.cianoChiaro)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Tema.fondo.opacity(0.72), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Modalità avanzata a vista (come sul Mac): un tocco la accende o la spegne, e una riga breve dice cosa cambia.
    private func cambiaModalitaAvanzata() {
        modalitaAvanzata.toggle()
        let testo = modalitaAvanzata
            ? "Modalità avanzata accesa: millisecondi, formato, avvio e registro"
            : "Modalità avanzata spenta"
        withAnimation { avvisoBreve = testo }
        compitoAvviso?.cancel()
        compitoAvviso = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            withAnimation { avvisoBreve = nil }
        }
    }

    private var telemetria: some View {
        HStack(spacing: 10) {
            // Round 2: la qualità in parole, come sul computer. 1.5: i millisecondi accanto, più tenui,
            // solo in modalità avanzata (VoiceOver li legge già nella qualità).
            if let latenza = sessione.latenzaMs {
                ChipQualita(qualita, latenzaMs: latenza)
                if modalitaAvanzata {
                    Text("\(latenza) ms")
                        .foregroundStyle(Tema.testoSecondario)
                        .accessibilityHidden(true)
                }
            } else if modalitaAvanzata || sessione.tipoCollegamento == nil {
                Text("— ms")
            }
            // 1.2: come si è collegati, accanto alla qualità.
            if let tipo = sessione.tipoCollegamento {
                IndicatoreCollegamento(tipo: tipo)
            }
            if sessione.zoom > 1.05 {
                Text(String(format: "%.1f×", sessione.zoom).replacingOccurrences(of: ".", with: ","))
            }
            // Esposizione manuale dal computer: la luce non si adatta più da sola.
            // Il tempo mostrato è quello usato: mai più lungo di un fotogramma.
            if sessione.iso > 0 || sessione.tempo > 0 {
                Text(testoEsposizioneManuale)
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
            // B2: gli effetti di WebcamLR (filtri, sfondo, pelle, scritta), in ciano se almeno uno è acceso.
            PulsanteTondo("Effetti", icona: "camera.filters", attivo: sessione.visivi.qualcosaAttivo) {
                compitoOscuramento?.cancel()
                mostraEffetti = true
            }
            // P20: il microfono del telefono verso il computer, in ciano quando è chiesto.
            PulsanteTondo("Microfono al computer", icona: sessione.audioRichiesto ? "mic.fill" : "mic.slash",
                          attivo: sessione.audioRichiesto) {
                sessione.impostaAudio(!sessione.audioRichiesto)
            }
            .accessibilityValue(sessione.audioRichiesto ? "acceso" : "spento")
            .accessibilityHint("Manda l'audio del microfono dell'iPhone al computer")
            // P04 e seguenti: inquadratura automatica a un tocco e il foglio dell'assistente.
            PulsantiAssistente(sessione: sessione)
            // Modalità avanzata (1.5) a vista, come sul Mac: resta anche nelle Impostazioni.
            PulsanteTondo("Modalità avanzata", icona: "slider.horizontal.3", attivo: modalitaAvanzata) {
                cambiaModalitaAvanzata()
            }
            .accessibilityValue(modalitaAvanzata ? "accesa" : "spenta")
            .accessibilityHint("Mostra o nasconde millisecondi, formato del video e registro del collegamento")
            // P16: i controlli manuali della fotocamera, solo in modalità avanzata; in ciano se qualcosa è manuale.
            if modalitaAvanzata {
                PulsanteTondo("Controlli Pro", icona: "camera.aperture", attivo: controlliManuali) {
                    compitoOscuramento?.cancel()
                    mostraControlliPro = true
                }
            }
            // P03: le Impostazioni anche da qui; ciò che riavvia la fotocamera si applica con «Fine».
            PulsanteTondo("Impostazioni", icona: "gearshape") {
                compitoOscuramento?.cancel()
                mostraImpostazioni = true
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

    /// P16: almeno un valore della fotocamera è scelto a mano (dal telefono o dal computer).
    private var controlliManuali: Bool {
        sessione.iso > 0 || sessione.tempo > 0 || sessione.bianco > 0 || sessione.esposizione != 0
            || sessione.posizioneFuoco != nil
    }

    /// 1.2: un consiglio gentile quando il collegamento è debole e ne esiste uno migliore (per esempio il cavo).
    private var consiglioCollegamento: String? {
        guard sessione.stato == .collegato, qualita == .debole || sessione.reteDebole,
              let tipo = sessione.tipoCollegamento else { return nil }
        return tipo.consiglioSeDebole
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
            return "Collega l'iPhone alla stessa rete Wi-Fi del computer: riparto da solo."
        }
        if sessione.soloAlRitorno {
            return "Il computer ha chiuso il collegamento: riparto da solo quando WebcamLR si riapre, oppure tocca «Riprova ora»."
        }
        return "Riparto da solo appena WebcamLR è aperto sul computer."
    }

    /// Se non ci si è mai collegati il computer non è «perso». Sul cavo (1.6) la rete non conta.
    private var testoRiconnessione: String {
        if sessione.viaCavo {
            return sessione.giaCollegato
                ? "Cavo scollegato? Riparto appena il computer risponde…"
                : "Aspetto il computer sul cavo USB…"
        }
        // 1.9: il cavo si è staccato in una sessione nata in Wi-Fi: si prova il Wi-Fi, il cavo può tornare.
        if sessione.daCavoAlWiFi {
            return sessione.reteDisponibile
                ? "Cavo scollegato: provo il Wi-Fi…"
                : "Cavo scollegato e nessuna rete: ricollega il cavo…"
        }
        if !sessione.reteDisponibile { return "Nessuna rete: mi ricollego appena torna il Wi-Fi…" }
        if sessione.inAttesaDelComputer { return "In attesa di «\(sessione.computer.nome)»…" }
        return sessione.giaCollegato
            ? "Computer perso, mi ricollego…"
            : "Non riesco a collegarmi a \(sessione.computer.nome), riprovo…"
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
        case .riconnessione(let tentativo):
            sessione.inAttesaDelComputer ? "In attesa"
                : sessione.viaCavo || sessione.daCavoAlWiFi ? "Riconnessione"
                : "Riconnessione \(tentativo)/\(SessioneTelefono.tentativiMassimi)"
        case .chiusa, .errore: "Scollegato"
        }
    }

    private var testoBatteria: String {
        let batteria = sessione.batteria >= 0 ? "\(sessione.batteria)%" : "—"
        return "\(batteria) · temperatura \(sessione.temperatura.descrizione)"
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
    @AppStorage("modalitaAvanzata") private var modalitaAvanzata = false

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
                    Text(testoQualita)
                    if let tipo = sessione.tipoCollegamento {
                        Text(tipo.testo)
                    }
                    if modalitaAvanzata {
                        Text(sessione.larghezza > 0 ? "\(min(sessione.larghezza, sessione.altezza))p\(sessione.fps)" : "—")
                    }
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

    /// «Ottimo», e in modalità avanzata «Ottimo · 38 ms».
    private var testoQualita: String {
        guard let latenza = sessione.latenzaMs else { return modalitaAvanzata ? "— ms" : "—" }
        let parola = QualitaCollegamento(latenzaMs: latenza, perdite: sessione.perditeRecenti).testo
        return modalitaAvanzata ? "\(parola) · \(latenza) ms" : parola
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
