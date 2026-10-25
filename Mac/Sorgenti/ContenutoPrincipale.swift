import AppKit
import AVFoundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Finestra del ricevitore, con l'identità di LR Apps (fondo verde scuro, salvia, corallo solo per «in onda»).
/// Tre colonne: a sinistra dispositivi, connessione, uscite e il QR dell'app per il telefono (ColonnaDispositivi);
/// al centro il video con i dati essenziali sopra, la barra delle azioni e le app che usano WebcamLR;
/// a destra il profilo e i comandi della fotocamera (ColonnaControlli). A 960×600 le colonne scorrono.
struct ContenutoPrincipale: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    let riprese: Riprese
    @AppStorage(Preferenze.vistaPulita) private var vistaPulita = false
    @AppStorage(Preferenze.riempi) private var riempi = false
    /// Il puntatore è sopra il video: in vista pulita compare il pulsante per uscire.
    @State private var sopraVideo = false
    /// Il lampo bianco dopo uno scatto (funzione 27).
    @State private var opacitaLampo = 0.0
    /// I numeri del collegamento, dal chip della qualità sopra il video (funzioni 28 e 31).
    @State private var mostraNumeri = false
    /// Il foglio di «Aggiornamento disponibile», con la versione che mostra (resta anche se intanto cambia).
    @State private var aggiornamentoMostrato: ControlloAggiornamenti.Versione?
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        VStack(spacing: 0) {
            if !vistaPulita {
                intestazione
                Divider().overlay(Tema.lineaTenue)
            }
            GeometryReader { spazio in
                // Sotto i 1180 punti le colonne laterali si stringono: a 960 il video resta largo almeno 400.
                let stretta = spazio.size.width < 1180
                HStack(spacing: 0) {
                    if !vistaPulita {
                        ColonnaDispositivi(ricevitore: ricevitore, fotocamera: fotocamera)
                            .frame(width: stretta ? 236 : 272)
                            .background(Tema.barraLaterale)
                        Divider().overlay(Tema.lineaTenue)
                    }
                    centro
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !vistaPulita {
                        Divider().overlay(Tema.lineaTenue)
                        ColonnaControlli(ricevitore: ricevitore)
                            .frame(width: stretta ? 280 : 320)
                            .background(Tema.barraLaterale)
                    }
                }
            }
        }
        .background(vistaPulita ? Color.black : Tema.fondo)
        .background(MonitorTastiera(gestisci: tasto))
        .foregroundStyle(Tema.testo)
        .font(.corpo(13))
        // Azioni e selezione nell'accento salvia (Specchia e Sfoca sfondo accesi, Riempi), non nel colore di sistema.
        .tint(Tema.ciano)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            ricevitore.imposta(riempi: riempi)
            // Per riaprire la finestra dal clic su una notifica o sull'icona nel Dock (DelegatoApp).
            if Notifiche.condivise.apriFinestraPrincipale == nil {
                let apri = apriFinestra
                Notifiche.condivise.apriFinestraPrincipale = { apri(id: WebcamLRMacApp.idPrincipale) }
            }
        }
        .onChange(of: riempi) { ricevitore.imposta(riempi: riempi) }
        // Pausa intelligente: il telefono sa se qui qualcuno vede il video (finestra coperta, ridotta a icona, chiusa).
        .background(OsservatoreFinestra { visibile in ricevitore.aggiornaVisibilitaPrincipale(visibile) })
        .onDisappear { ricevitore.aggiornaVisibilitaPrincipale(false) }
        .sheet(item: $aggiornamentoMostrato) { versione in
            FoglioAggiornamento(versione: versione, controllo: ControlloAggiornamenti.condiviso)
        }
    }

    // MARK: - Tasti (funzione 25)

    /// 1–4 obiettivi nell'ordine del telefono, + e − zoom, F messa a fuoco automatica. Vero se il tasto è stato usato.
    private func tasto(_ evento: NSEvent) -> Bool {
        let modificatori = evento.modifierFlags.intersection([.command, .control, .option])
        // ⌘C copia il fotogramma (funzione 26); in un campo di testo non si arriva qui e ⌘C copia il testo.
        if modificatori == .command, evento.charactersIgnoringModifiers?.lowercased() == "c" {
            guard ricevitore.telefono != nil else { return false }
            riprese.copiaFotogramma()
            return true
        }
        // Le scorciatoie con ⌘ (prima nel menu «Video», ora solo nella finestra).
        if modificatori == .command || modificatori == [.command, .option] {
            let maiuscolo = evento.modifierFlags.contains(.shift)
            let lettera = evento.charactersIgnoringModifiers?.lowercased() ?? ""
            switch (lettera, maiuscolo, modificatori == .command) {
            case ("t", false, true):
                // ⌘T: foto, come in Photo Booth.
                guard ricevitore.telefono != nil else { return false }
                riprese.scattaFoto()
                return true
            case ("t", true, true):
                // ⇧⌘T: foto tra 3 secondi; con il timer partito lo annulla, anche se il telefono se n'è andato.
                guard ricevitore.telefono != nil || riprese.contoAllaRovescia != nil else { return false }
                riprese.scattaConTimer()
                return true
            case ("r", false, true):
                // ⌘R: registra o ferma.
                guard riprese.registra || ricevitore.telefonoAttivo else { return false }
                riprese.alternaRegistrazione()
                return true
            case ("p", true, true):
                // ⇧⌘P: vista pulita.
                vistaPulita.toggle()
                return true
            case ("m", true, true):
                // ⇧⌘M: finestra mini.
                alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
                return true
            case ("f", false, false):
                // ⌥⌘F: riempi il riquadro.
                riempi.toggle()
                return true
            default:
                break
            }
        }
        // Esc esce dalla vista pulita (funzione 29).
        if evento.keyCode == 53, modificatori.isEmpty, vistaPulita {
            vistaPulita = false
            return true
        }
        guard modificatori.isEmpty, ricevitore.telefonoAttivo, let carattere = evento.characters else { return false }
        switch carattere {
        case "1", "2", "3", "4":
            guard let numero = Int(carattere) else { return false }
            ricevitore.scegliObiettivo(numero: numero - 1)
        case "+", "=":
            // «=» è il tasto del + senza Maiusc sulle tastiere americane.
            ricevitore.cambiaZoom(di: Ricevitore.passoZoom)
        case "-":
            ricevitore.cambiaZoom(di: -Ricevitore.passoZoom)
        case "f", "F":
            ricevitore.fuocoAutomatico()
        default:
            return false
        }
        return true
    }

    // MARK: - Intestazione

    /// Al posto della barra del titolo: i tre pulsanti della finestra restano a sinistra.
    /// Se la finestra è stretta (960 punti, avviso dello spazio) «Aiuto» resta solo icona:
    /// il nome è nell'aiuto e per VoiceOver. Mai oltre il bordo della finestra.
    private var intestazione: some View {
        ViewThatFits(in: .horizontal) {
            rigaIntestazione(compatta: false)
            rigaIntestazione(compatta: true)
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 52)
        // La sfumatura del logo, appena accennata da sinistra.
        .background(LinearGradient(colors: [Tema.sfumaturaChiara.opacity(0.6), Tema.pannelloScuro],
                                   startPoint: .leading, endPoint: .trailing))
    }

    private func rigaIntestazione(compatta: Bool) -> some View {
        HStack(spacing: compatta ? 8 : 12) {
            LogoWebcamLR(lato: 24)
            MarchioWebcamLR(dimensione: 20)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            if let liberi = riprese.spazioScarso {
                // Spazio quasi finito durante la registrazione (funzione 37): avviso in ambra.
                Label("Solo \(Riprese.testoByte(liberi)) liberi", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.ambra)
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
                    .help("Solo \(Riprese.testoByte(liberi)) liberi: lo spazio sul disco sta finendo. Ferma la registrazione o libera spazio.")
            }
            PillolaStato(ricevitore.collegamento)
            if let nuova = ControlloAggiornamenti.condiviso.daMostrare {
                // Una versione nuova sul sito: pillola nell'accento (un'azione), mai in corallo.
                Button {
                    aggiornamentoMostrato = nuova
                } label: {
                    Label("Aggiornamento disponibile", systemImage: "arrow.down.circle")
                        .labelStyle(StileEtichettaAdattabile(compatta: compatta))
                }
                .buttonStyle(StilePillolaAccento())
                .help("WebcamLR \(nuova.testo) è disponibile sul sito")
            }
            // Tutto dentro l'app, niente menu in più: aiuto (guida, domande frequenti, «Segnala un bug»,
            // Pro, informazioni) e impostazioni.
            Button {
                apriFinestraApp(.guida, apri: apriFinestra)
            } label: {
                Label("Aiuto", systemImage: "questionmark.circle")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .buttonStyle(StilePulsanteSecondario())
            .help("Guida, domande frequenti, «Segnala un bug» e informazioni")
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(StilePulsanteSecondario())
            .help("Impostazioni (⌘,)")
            .accessibilityLabel("Impostazioni")
        }
    }

    // MARK: - Centro

    private var centro: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Il video prende il suo spazio per primo: la barra e le app sotto usano ciò che resta.
            riquadroVideo
                .layoutPriority(1)
            if !vistaPulita {
                barraAzioni
                // A 960×600 le schede delle app scorrono se non ci stanno.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let telefono = ricevitore.telefono, let avviso = ControlloAggiornamenti.avvisoVersione(telefono) {
                            AvvisoVersione(testo: avviso)
                        }
                        SezioneAppWebcam(webcamDisponibile: fotocamera.disponibile, webcamAttiva: fotocamera.stato == .attiva,
                                         firme: ricevitore.appWebcam, inUso: ricevitore.webcamInUso)
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(vistaPulita ? 0 : 16)
    }

    /// Il video con ciò che gli sta sopra. In vista pulita (funzione 29) occupa tutta la finestra.
    @ViewBuilder private var riquadroVideo: some View {
        if vistaPulita {
            videoConSovrapposizioni
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        } else {
            videoConSovrapposizioni
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(bordoVideo, lineWidth: inOnda ? 2 : 1))
                .frame(maxWidth: .infinity)
        }
    }

    private var inOnda: Bool {
        if case .inOnda = ricevitore.collegamento { return true }
        return false
    }

    /// Il bordo del video: corallo quando è in onda (tally), altrimenti la linea del pannello.
    private var bordoVideo: Color {
        inOnda ? Tema.tally : Tema.linea
    }

    /// I chip sopra il video (qualità, formato, strada) ci sono solo con il video che arriva.
    private var mostraChip: Bool {
        !vistaPulita && ricevitore.telefono != nil && ricevitore.statistiche.larghezza > 0
    }

    private var videoConSovrapposizioni: some View {
        ZStack(alignment: .topLeading) {
            // Il video com'è arrivato, mai specchiato qui: «Specchia» lo fa il telefono per tutti (1.14).
            VistaSchermo(livello: ricevitore.schermo.livello)
            if ricevitore.telefono == nil {
                PrimoCollegamento(ricevitore: ricevitore)
            } else if let motivo = ricevitore.statoTelefono?.pausa {
                // Pausa intelligente: il telefono non manda video, ma è collegato. Niente corallo: è uno stato calmo.
                SovrapposizionePausa(motivo: motivo)
            }
            VStack(alignment: .leading, spacing: 8) {
                if ricevitore.collegamento == .riconnessione {
                    PillolaStato(.riconnessione)
                }
                avvisiTelefono
                if let avviso = ricevitore.avvisoTelefoni {
                    // P21: un terzo telefono non entra; «Lezione» con la frontale. Ambra, come gli altri avvisi; dice cosa fare.
                    BannerAvviso(icona: "iphone", testo: avviso)
                }
            }
            .padding(12)
            .padding(.trailing, ricevitore.altri.isEmpty || vistaPulita ? 0 : MiniaturaTelefono.larghezza + 12)
            // Con due telefoni (P21): l'altro in un angolo; un clic lo mette nella webcam.
            // In vista pulita no: lì c'è solo il video, e l'altro telefono può andare in pausa.
            if !vistaPulita, let altro = ricevitore.altri.first {
                MiniaturaTelefono(telefono: altro) { ricevitore.scegli(altro) }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .onAppear { ricevitore.aggiornaVisibilitaMiniatura(true) }
                    .onDisappear { ricevitore.aggiornaVisibilitaMiniatura(false) }
            }
            if mostraChip {
                chipVideo
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            Color.white
                .opacity(opacitaLampo)
                .allowsHitTesting(false)
            if let secondi = riprese.contoAllaRovescia {
                // Conto alla rovescia della foto con il timer (funzione 36).
                Text("\(secondi)")
                    .font(.titolo(120))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Foto tra \(secondi) secondi")
            }
            if let avviso = riprese.avviso {
                // Le frasi lunghe vanno a capo dentro il video stretto (960 punti): angoli arrotondati, non una capsula.
                // Sopra i chip, che stanno in basso a sinistra.
                Text(avviso)
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.testo)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Tema.pannelloChiaro.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.bottom, mostraChip ? 48 : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
            pulsanteEsciVistaPulita
        }
        .animation(.default, value: riprese.avviso)
        .animation(.default, value: ricevitore.avvisoTelefoni)
        .animation(.easeOut(duration: 0.15), value: sopraVideo)
        .animation(.default, value: riprese.contoAllaRovescia)
        .onChange(of: riprese.lampo) {
            opacitaLampo = 0.85
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.easeOut(duration: 0.35)) { opacitaLampo = 0 }
            }
        }
        .onHover { sopraVideo = $0 }
        // Senza chip (telefono andato, video fermo) i numeri si chiudono: altrimenti ricomparirebbero da soli col video.
        .onChange(of: mostraChip) { if !mostraChip { mostraNumeri = false } }
    }

    /// In basso a sinistra sul video: la qualità (un clic apre i numeri e il grafico della latenza),
    /// risoluzione · fps · formato e la strada del collegamento. Piccoli, su un fondo scuro trasparente.
    private var chipVideo: some View {
        let statistiche = ricevitore.statistiche
        return HStack(spacing: 6) {
            Button {
                mostraNumeri.toggle()
            } label: {
                HStack(spacing: 5) {
                    if let latenza = statistiche.latenzaMs, let qualita = ricevitore.attivo?.qualita {
                        // Stessa regola del telefono: latenza e fotogrammi persi (1.14), così le due app dicono la stessa parola.
                        ChipQualita(qualita, latenzaMs: latenza)
                        Text(verbatim: "\(latenza) ms")
                            .font(.numeri(11))
                            .foregroundStyle(Tema.testoTenue)
                            .accessibilityHidden(true)
                    } else {
                        Text("Misuro il collegamento…")
                            .font(.corpo(11.5))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Tema.testoSecondario)
                        .accessibilityHidden(true)
                }
                .modifier(StileChip())
            }
            .buttonStyle(.plain)
            .help("Mostra i numeri del collegamento")
            .accessibilityHint("Mostra i numeri del collegamento")
            .popover(isPresented: $mostraNumeri, arrowEdge: .top) {
                PannelloNumeri(statistiche: statistiche, storico: ricevitore.storicoLatenza, avvio: ricevitore.tempoAvvio)
            }
            Text(verbatim: "\(Lingua.risoluzione(altezza: min(statistiche.larghezza, statistiche.altezza), fps: statistiche.fps)) · \(statistiche.codec == .hevc ? "HEVC" : "H.264")")
                .font(.numeri(11))
                .lineLimit(1)
                .modifier(StileChip())
            if let via = ricevitore.tipoCollegamento {
                IndicatoreCollegamento(via, qualita: ricevitore.attivo?.qualita)
                    .modifier(StileChip())
            }
        }
    }

    /// Avvisi dal telefono sopra il video (funzione 33): caldo e batteria, in ambra.
    @ViewBuilder private var avvisiTelefono: some View {
        if let stato = ricevitore.statoTelefono, ricevitore.telefono != nil {
            if stato.temperatura == .moltoCalda || stato.temperatura == .critica {
                BannerAvviso(icona: "thermometer",
                             testo: stato.temperatura == .critica
                                ? String(localized: "Il telefono è troppo caldo: il video può fermarsi. Toglilo dal sole o dalla custodia.")
                                : String(localized: "Il telefono è molto caldo: la qualità può calare. Toglilo dal sole o dalla custodia."))
            }
            if stato.batteria >= 0, stato.batteria <= 20, !stato.inCarica {
                BannerAvviso(icona: "battery.25",
                             testo: String(localized: "Batteria del telefono al \(stato.batteria)%: collega il caricatore."))
            }
        }
    }

    /// Esce dalla vista pulita: compare solo con il puntatore sopra il video.
    @ViewBuilder private var pulsanteEsciVistaPulita: some View {
        if vistaPulita && sopraVideo {
            Button {
                vistaPulita = false
            } label: {
                Label("Esci dalla vista pulita", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.corpo(12.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Tema.pannelloChiaro.opacity(0.92), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tema.testo)
            .help("Esci dalla vista pulita (Esc)")
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(.opacity)
        }
    }

    // MARK: - Barra delle azioni

    /// Sotto il video, pulsanti con il nome: Specchia e Sfoca sfondo (accesi nell'accento), Foto, Registra,
    /// Finestra mini, Schermo intero, Vista e Scollega.
    /// A 960 punti non ci stanno tutti con i nomi: allora restano solo le icone (il nome è nell'aiuto e per
    /// VoiceOver), mai oltre il bordo del riquadro.
    private var barraAzioni: some View {
        ViewThatFits(in: .horizontal) {
            rigaAzioni(compatta: false)
            rigaAzioni(compatta: true)
        }
        .buttonStyle(StilePulsanteSecondario())
    }

    private func rigaAzioni(compatta: Bool) -> some View {
        HStack(spacing: 8) {
            pulsantiVideo(compatta: compatta)
            pulsanteFoto(compatta: compatta)
            pulsanteRegistra(compatto: compatta)
            Button {
                alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
            } label: {
                Label(ricevitore.miniAperta ? "Chiudi mini" : "Finestra mini",
                      systemImage: ricevitore.miniAperta ? "pip.exit" : "pip.enter")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .help(ricevitore.miniAperta ? "Chiudi la finestra mini (⇧⌘M)" : "Finestra mini, sempre in primo piano (⇧⌘M)")
            .accessibilityLabel(ricevitore.miniAperta ? "Chiudi la finestra mini" : "Apri la finestra mini")
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Label("Schermo intero", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            // ⌃⌘F c'è già nel menu Vista di sistema: qui solo il suggerimento.
            .help("Schermo intero (⌃⌘F)")
            menuVista(compatta: compatta)
            Spacer(minLength: 8)
            if ricevitore.telefono != nil {
                Button {
                    ricevitore.scollega()
                } label: {
                    Label("Scollega", systemImage: "iphone.slash")
                        .labelStyle(StileEtichettaAdattabile(compatta: compatta))
                }
                .help(ricevitore.telefoni.count > 1
                      ? "Scollega «\(ricevitore.telefono?.nome ?? "")», quello nella webcam: non si ricollega da solo"
                      : "Scollega il telefono: non si ricollega da solo")
            }
        }
    }

    /// «Specchia» e «Sfoca sfondo» (1.14): un clic, accesi nell'accento salvia. Valgono per il video inviato, quello
    /// che vedono anche le app e il telefono: il telefono li applica e il pulsante segue il suo `stato`.
    /// Senza telefono restano grigi; con un telefono che non li sa fare (`capacita`) non ci sono.
    @ViewBuilder private func pulsantiVideo(compatta: Bool) -> some View {
        let inAttesa = !ricevitore.telefonoAttivo || ricevitore.capacita == nil
        if inAttesa || ricevitore.specchioDisponibile {
            let acceso = !inAttesa && ricevitore.specchiato
            Button {
                ricevitore.alternaSpecchio()
            } label: {
                Label("Specchia", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .buttonStyle(StilePulsanteInterruttore(acceso: acceso))
            .help(acceso ? "Specchiato: le app di chiamata, il telefono e questa finestra vedono il video girato. Clic per raddrizzarlo"
                  : "Specchia il video da sinistra a destra: per le app di chiamata, il telefono e questa finestra")
            .accessibilityAddTraits(acceso ? .isSelected : [])
            .richiedeTelefono(!inAttesa)
        }
        if inAttesa || ricevitore.sfondoDisponibile {
            let acceso = !inAttesa && ricevitore.sfondoSfocato
            Button {
                ricevitore.alternaSfocatura()
            } label: {
                Label("Sfoca sfondo", systemImage: "person.and.background.dotted")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .buttonStyle(StilePulsanteInterruttore(acceso: acceso))
            .help(acceso ? "Sfondo sfocato. Clic per toglierlo; l'intensità è nella sezione «Effetti»"
                  : "Sfoca lo sfondo dietro di te; l'intensità è nella sezione «Effetti»")
            .accessibilityAddTraits(acceso ? .isSelected : [])
            .richiedeTelefono(!inAttesa)
        }
    }

    /// «Foto» con il nome, e accanto un menu piccolo per le altre due: tra 3 secondi e copia (niente icone doppie).
    /// Con il timer partito il pulsante diventa «Annulla il timer», anche se intanto il telefono se n'è andato.
    @ViewBuilder private func pulsanteFoto(compatta: Bool) -> some View {
        if riprese.contoAllaRovescia != nil {
            Button {
                riprese.scattaConTimer()
            } label: {
                Label("Annulla il timer", systemImage: "xmark")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .help("Annulla il timer (⇧⌘T)")
        } else {
            HStack(spacing: 2) {
                Button {
                    riprese.scattaFoto()
                } label: {
                    Label("Foto", systemImage: "camera")
                        .labelStyle(StileEtichettaAdattabile(compatta: compatta))
                }
                .help("Salva l'immagine attuale in Immagini › WebcamLR (⌘T)")
                Menu {
                    Button("Foto tra 3 secondi (⇧⌘T)") { riprese.scattaConTimer() }
                    Button("Copia il fotogramma (⌘C)") { riprese.copiaFotogramma() }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Foto tra 3 secondi, o copia l'immagine da incollare ovunque")
                .accessibilityLabel("Altre foto")
            }
            // WebcamLR Pro: foto e registrazione con un telefono gratis restano grigie, con «PRO».
            .richiedePro(ricevitore.bloccoPro, segno: !compatta)
            .richiedeTelefono(ricevitore.telefono != nil)
        }
    }

    /// Registra (funzione 35): pulsante secondario come gli altri; il punto corallo (tally) solo mentre registra.
    /// Mentre registra mostra durata e dimensione del file (funzione 37). `compatto`: solo il punto e il tempo.
    @ViewBuilder private func pulsanteRegistra(compatto: Bool) -> some View {
        if let inizio = riprese.inizioRegistrazione {
            Button {
                riprese.fermaRegistrazione()
            } label: {
                HStack(spacing: 6) {
                    // Letta qui, sulla coda principale: la chiusura del TimelineView resta senza stato di Riprese.
                    let dimensione = Riprese.testoByte(riprese.dimensioneRegistrazione)
                    Circle().fill(Tema.tally).frame(width: 9, height: 9)
                    TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                        let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                        let tempo = String(format: "%02d:%02d", secondi / 60, secondi % 60)
                        Text(compatto ? tempo : String(localized: "Ferma · \(tempo) · \(dimensione)"))
                            .font(.numeri(12))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            .help("Ferma la registrazione e mostra il file (⌘R)")
            .accessibilityLabel("Ferma la registrazione")
            .accessibilityValue(Riprese.testoByte(riprese.dimensioneRegistrazione))
        } else {
            Button {
                riprese.avviaRegistrazione()
            } label: {
                Label("Registra", systemImage: "record.circle")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatto))
            }
            .richiedePro(ricevitore.bloccoPro, segno: !compatto)
            .richiedeTelefono(ricevitore.telefonoAttivo)
            .help("Registra il video del telefono in Filmati › WebcamLR (⌘R)")
        }
    }

    /// «Vista»: le scelte che valgono solo per l'anteprima qui, in un menu con i nomi.
    private func menuVista(compatta: Bool) -> some View {
        Menu {
            Toggle("Riempi il riquadro (⌥⌘F)", isOn: $riempi)
            Divider()
            Button("Vista pulita: solo il video (⇧⌘P)") { vistaPulita = true }
        } label: {
            Label("Vista", systemImage: "rectangle.on.rectangle")
                .labelStyle(StileEtichettaAdattabile(compatta: compatta))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Riempi e Vista pulita valgono solo qui: le altre app ricevono il video intero")
    }
}

// MARK: - Componenti

/// Un chip sopra il video: piccolo, fondo scuro trasparente, angoli tondi.
private struct StileChip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Tema.testo)
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.08)))
    }
}

/// I numeri di sempre, a un clic dal chip della qualità: risoluzione, fotogrammi, formato, velocità, latenza
/// e il grafico dell'ultimo minuto (funzioni 28 e 31).
private struct PannelloNumeri: View {
    let statistiche: Statistiche
    let storico: [Int?]
    /// «Avvio: 0,9 s» (1.11): dall'arrivo del telefono al primo fotogramma a schermo.
    var avvio: String?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                GraficoLatenza(valori: storico)
                    .frame(height: 28)
                    .gridCellColumns(2)
                    .help("Latenza dell'ultimo minuto; la riga tratteggiata è a 100 ms")
            }
            riga("Risoluzione", "\(statistiche.larghezza)×\(statistiche.altezza)")
            riga("Fotogrammi", String(localized: "\(statistiche.fps) al secondo"))
            riga("Formato", nomeCodec)
            riga("Velocità", Lingua.decimali(String(format: "%.1f Mbit/s", statistiche.megabitAlSecondo)))
            GridRow {
                Text("Latenza").foregroundStyle(Tema.testoSecondario)
                Text(statistiche.latenzaMs.map { "\($0) ms" } ?? "—")
                    .font(.numeri(12.5))
                    .foregroundStyle(coloreLatenza)
            }
            if let media {
                riga("Media dell'ultimo minuto", "\(media) ms")
            }
            if let avvio {
                // «Avvio: 0,9 s» → «0,9 s»: il nome è già nella colonna a sinistra.
                // Dopo i due punti, così vale anche in inglese («Startup: 0.9 s», P22).
                riga("Avvio", avvio.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? avvio)
            }
            Divider().gridCellColumns(2)
            Text("Ottimo sotto gli 80 ms, buono sotto i 150.")
                .font(.corpo(12.5))
                .foregroundStyle(Tema.testoSecondario)
                .gridCellColumns(2)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func riga(_ nome: LocalizedStringKey, _ valore: String) -> some View {
        GridRow {
            Text(nome).foregroundStyle(Tema.testoSecondario)
            Text(valore).font(.numeri(12.5))
        }
    }

    private var nomeCodec: String {
        statistiche.codec == .hevc ? "HEVC" : "H.264"
    }

    private var media: Int? {
        let noti = storico.compactMap { $0 }
        return noti.isEmpty ? nil : noti.reduce(0, +) / noti.count
    }

    /// Accento sotto i 100 ms (l'obiettivo per una chiamata), ambra sopra.
    private var coloreLatenza: Color {
        guard let latenza = statistiche.latenzaMs else { return Tema.testoTenue }
        return latenza < 100 ? Tema.cianoChiaro : Tema.ambra
    }
}

/// Le versioni di WebcamLR sul telefono e sul Mac sono diverse in modo che conta (ControlloAggiornamenti):
/// un'informazione con cosa fare, calma, nell'accento.
private struct AvvisoVersione: View {
    let testo: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Tema.accento)
                .accessibilityHidden(true)
            Text(testo)
                .font(.corpo(12.5))
                .foregroundStyle(Tema.testoChiaro)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Tema.accentoTenue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Un avviso in ambra sopra il video, come i banner del telefono.
private struct BannerAvviso: View {
    let icona: String
    let testo: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icona)
                .foregroundStyle(Tema.ambra)
                .accessibilityHidden(true)
            // Tre righe: nel video stretto (960 punti) la frase sul caldo non ci sta in due.
            Text(testo)
                .foregroundStyle(Tema.ambraTesto)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.corpo(12.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Tema.ambraTenue.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.ambra.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

/// Sopra il video quando il telefono è in pausa (`stato.pausa`): calmo, nei colori del pannello, mai in corallo.
private struct SovrapposizionePausa: View {
    let motivo: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Tema.testoTenue)
                .accessibilityHidden(true)
            Text("In pausa")
                .font(.titolo(30))
                .foregroundStyle(Tema.testo)
            Text(Ricevitore.testoPausa(motivo))
                .font(.corpo(12.5))
                .foregroundStyle(Tema.testoTenue)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.pannelloScuro.opacity(0.9))
        .accessibilityElement(children: .combine)
    }
}

/// Al posto del video finché non c'è un telefono (funzione 32): QR code grande per collegarsi e i tre passi.
/// Se il riquadro è piccolo il QR si rimpicciolisce, e al limite restano solo i passi.
private struct PrimoCollegamento: View {
    let ricevitore: Ricevitore

    var body: some View {
        ViewThatFits(in: .vertical) {
            disposizione(lato: 170)
            disposizione(lato: 110)
            passi
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Tema.sfumaturaChiara.opacity(0.5), Tema.pannelloScuro],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func disposizione(lato: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 28) {
            PannelloAssociazione(ricevitore: ricevitore, lato: lato)
                .frame(width: lato + 40)
            passi
        }
    }

    private var passi: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collega il telefono")
                .font(.titolo(28))
            passo(1, "Apri WebcamLR sul telefono.")
            passo(2, "Tieni telefono e Mac sulla stessa rete Wi-Fi, oppure collegali con il cavo USB.")
            passo(3, "Scegli «\(NomeMac.attuale)» nell'elenco, oppure inquadra il QR code.")
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    private func passo(_ numero: Int, _ testo: LocalizedStringKey) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(numero)")
                .font(.numeriEvidenti(13))
                .foregroundStyle(Tema.fondo)
                .frame(width: 24, height: 24)
                .background(Tema.salviaChiara, in: Circle())
            Text(testo)
                .font(.corpo(13))
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Con due telefoni (P21): il video dell'altro in un angolo dell'anteprima. Un clic lo mette nella webcam
/// (e lo scambia con quello grande). Il suo livello è quello del suo `Schermo`: nessuna seconda decodifica.
private struct MiniaturaTelefono: View {
    static let larghezza: CGFloat = 176

    let telefono: TelefonoCollegato
    let scegli: () -> Void
    @State private var sopra = false

    var body: some View {
        Button(action: scegli) {
            ZStack(alignment: .bottomLeading) {
                VistaSchermo(livello: telefono.schermo.livello)
                    .allowsHitTesting(false)
                if telefono.statoTelefono?.pausa != nil {
                    // Nessuno lo guardava: il telefono è in pausa e riprende tra un attimo (pausa intelligente).
                    Image(systemName: "pause.circle")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Tema.testoTenue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Tema.pannelloScuro.opacity(0.85))
                } else if telefono.collegamento == .riconnessione {
                    Text("Mi ricollego…")
                        .font(.corpo(12.5))
                        .foregroundStyle(Tema.ambraTesto)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Tema.pannelloScuro.opacity(0.85))
                }
                HStack(spacing: 4) {
                    Text(telefono.telefono.nome)
                        .lineLimit(1)
                    if sopra {
                        Image(systemName: "arrow.left.arrow.right")
                            .accessibilityHidden(true)
                    }
                }
                .font(.corpo(11))
                .foregroundStyle(Tema.testo)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Tema.pannelloScuro.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                .padding(6)
            }
            .frame(width: Self.larghezza, height: Self.larghezza * 9 / 16)
            // Il clic arriva al pulsante anche sopra il video (la vista AppKit sotto non lo prende).
            .overlay(Color.clear.contentShape(Rectangle()))
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(sopra ? Tema.ciano : Tema.linea, lineWidth: sopra ? 2 : 1))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help("Clic per mettere «\(telefono.telefono.nome)» nella webcam")
        .accessibilityLabel("\(telefono.telefono.nome), l'altro telefono")
        .accessibilityHint("Lo mette nella webcam")
    }
}

/// Ospita un livello dello `Schermo` in SwiftUI (finestra principale e finestra mini).
struct VistaSchermo: NSViewRepresentable {
    let livello: AVSampleBufferDisplayLayer

    final class Vista: NSView {
        /// Nella finestra mini si trascina il video per spostare la finestra.
        override var mouseDownCanMoveWindow: Bool { true }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.sublayers?.forEach { $0.frame = bounds }
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Vista {
        let vista = Vista()
        vista.wantsLayer = true
        vista.layer?.backgroundColor = .black
        vista.layer?.addSublayer(livello)
        return vista
    }

    /// Con due telefoni (P21) l'anteprima grande e la miniatura si scambiano i livelli: si toglie quello
    /// di prima (se è ancora qui) e si mette il nuovo, che lascia da solo l'altra vista. Va bene in qualsiasi
    /// ordine aggiornino le due viste. Il livello porta con sé l'ultima immagine: nessun nero nel cambio.
    func updateNSView(_ vista: Vista, context: Context) {
        guard let radice = vista.layer, livello.superlayer !== radice else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        radice.sublayers?.filter { $0 is AVSampleBufferDisplayLayer }.forEach { $0.removeFromSuperlayer() }
        livello.frame = vista.bounds
        radice.addSublayer(livello)
        CATransaction.commit()
    }
}

/// Dice se la finestra che la ospita mostra davvero qualcosa: visibile, non ridotta a icona, non coperta del tutto
/// da altre finestre e con l'app non nascosta (`NSWindow.occlusionState`). Avvisa solo quando cambia.
struct OsservatoreFinestra: NSViewRepresentable {
    let suCambio: @MainActor (Bool) -> Void

    final class Vista: NSView {
        var suCambio: (@MainActor (Bool) -> Void)?
        private var osservatori: [NSObjectProtocol] = []
        private var ultimo: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            osservatori.forEach { NotificationCenter.default.removeObserver($0) }
            osservatori = []
            guard let finestra = window else {
                comunica(false)
                return
            }
            let nomi: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification,
                                             NSWindow.didMiniaturizeNotification,
                                             NSWindow.didDeminiaturizeNotification,
                                             NSWindow.willCloseNotification]
            for nome in nomi {
                let osservatore = NotificationCenter.default.addObserver(forName: nome, object: finestra, queue: .main) { [weak self] avviso in
                    let chiusa = avviso.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated { self?.ricalcola(chiusa: chiusa) }
                }
                osservatori.append(osservatore)
            }
            ricalcola(chiusa: false)
        }

        private func ricalcola(chiusa: Bool) {
            guard let finestra = window, !chiusa else {
                comunica(false)
                return
            }
            comunica(finestra.isVisible && !finestra.isMiniaturized && finestra.occlusionState.contains(.visible))
        }

        /// Fuori dall'aggiornamento delle viste: il Ricevitore scrive nel registro, che SwiftUI osserva.
        private func comunica(_ visibile: Bool) {
            guard visibile != ultimo else { return }
            ultimo = visibile
            guard let suCambio else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { suCambio(visibile) }
            }
        }
    }

    func makeNSView(context: Context) -> Vista {
        let vista = Vista()
        vista.suCambio = suCambio
        return vista
    }

    func updateNSView(_ vista: Vista, context: Context) {
        vista.suCambio = suCambio
    }
}

/// Intestazione e pulsanti sotto il video: icona e nome (o solo il nome con `soloTesto`),
/// oppure solo l'icona quando la finestra è stretta. Il nome resta per VoiceOver anche quando non si vede.
struct StileEtichettaAdattabile: LabelStyle {
    let compatta: Bool
    var soloTesto = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if compatta {
            Label(configuration).labelStyle(.iconOnly)
        } else if soloTesto {
            Label(configuration).labelStyle(.titleOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon)
        }
    }
}

/// Comandi visibili ma grigi finché non c'è un telefono: chi li prova vede la nota «Collega un telefono».
private struct RichiedeTelefono: ViewModifier {
    let disponibile: Bool
    @State private var mostraNota = false

    func body(content: Content) -> some View {
        corpo(content)
            // La nota aperta resterebbe «vera» quando il comando si accende, e ricomparirebbe da sola alla prossima
            // volta senza telefono: si chiude appena cambia.
            .onChange(of: disponibile) { mostraNota = false }
    }

    @ViewBuilder private func corpo(_ content: Content) -> some View {
        if disponibile {
            content
        } else {
            content
                .disabled(true)
                .opacity(0.45)
                // Sopra il comando spento: il clic arriva qui e apre la nota.
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { mostraNota = true }
                }
                .popover(isPresented: $mostraNota, arrowEdge: .bottom) {
                    Label("Collega un telefono per usarlo.", systemImage: "iphone")
                        .font(.corpo(12.5))
                        .padding(12)
                }
                .accessibilityHint("Collega un telefono per usarlo.")
        }
    }
}

extension View {
    /// Grigio e con la nota «Collega un telefono» quando `disponibile` è falso.
    func richiedeTelefono(_ disponibile: Bool) -> some View {
        modifier(RichiedeTelefono(disponibile: disponibile))
    }
}

/// Il registro del collegamento (1.5): ora ed evento, il più recente in basso, con «Copia» per «Segnala un bug».
struct VistaRegistro: View {
    let voci: [Ricevitore.VoceRegistro]
    /// Per due secondi dopo «Copia» il pulsante dice «Copiato»: prima il clic non dava nessun segno.
    @State private var copiato = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Registro del collegamento")
                    .font(.titolo(20))
                Spacer()
                Button(copiato ? "Copiato" : "Copia") { copia() }
                    .disabled(voci.isEmpty)
            }
            if voci.isEmpty {
                Text("Ancora nessun evento.")
                    .foregroundStyle(Tema.testoSecondario)
            } else {
                ScrollViewReader { lettore in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(voci) { voce in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(Self.ora(voce.ora))
                                        .font(.numeri(11.5))
                                        .foregroundStyle(Tema.testoSecondario)
                                    Text(Self.testo(voce))
                                        .font(.corpo(12.5))
                                        .foregroundStyle(Tema.testoChiaro)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                                .id(voce.id)
                            }
                        }
                        // A sinistra anche con poche righe corte: senza, lo ScrollView le centrava.
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear {
                        if let ultima = voci.last { lettore.scrollTo(ultima.id, anchor: .bottom) }
                    }
                    .onChange(of: voci.last?.id) {
                        if let ultima = voci.last { lettore.scrollTo(ultima.id, anchor: .bottom) }
                    }
                }
            }
            Text("Solo su questo Mac e solo finché WebcamLR è aperta: niente viene inviato.")
                .font(.corpo(11.5))
                .foregroundStyle(Tema.testoSecondario)
        }
        .padding(16)
        .frame(width: 420, height: 360)
        .foregroundStyle(Tema.testo)
        .tint(Tema.ciano)
    }

    private static func ora(_ data: Date) -> String {
        data.formatted(date: .omitted, time: .standard)
    }

    /// Con più telefoni (P21) la riga dice di quale telefono è.
    private static func testo(_ voce: Ricevitore.VoceRegistro) -> String {
        guard let telefono = voce.telefono else { return voce.testo }
        return "\(telefono) · \(voce.testo)"
    }

    private func copia() {
        let testo = voci.map { "\(Self.ora($0.ora))  \(Self.testo($0))" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testo, forType: .string)
        copiato = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copiato = false
        }
    }
}
