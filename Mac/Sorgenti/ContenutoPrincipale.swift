import AppKit
import AVFoundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Finestra del ricevitore (bozza grafica, Mac 1): telefoni e uscite, anteprima, fotocamera.
struct ContenutoPrincipale: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    let riprese: Riprese
    @AppStorage(Preferenze.specchia) private var specchia = false
    @AppStorage(Preferenze.vistaPulita) private var vistaPulita = false
    @AppStorage(Preferenze.riempi) private var riempi = false
    @AppStorage(Preferenze.wifiDiretto) private var wifiDiretto = false
    @AppStorage(Preferenze.modalitaAvanzata) private var avanzata = false
    @State private var mostraQR = false
    @State private var mostraRegistro = false
    /// Il puntatore è sopra il video: in vista pulita compare il pulsante per uscire.
    @State private var sopraVideo = false
    /// Il lampo bianco dopo uno scatto (funzione 27).
    @State private var opacitaLampo = 0.0
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        VStack(spacing: 0) {
            if !vistaPulita {
                intestazione
                Divider().overlay(Tema.lineaTenue)
            }
            HStack(spacing: 0) {
                if !vistaPulita {
                    barraLaterale
                        .frame(width: 250)
                        .background(Tema.barraLaterale)
                    Divider().overlay(Tema.lineaTenue)
                }
                anteprima
                    .frame(maxWidth: .infinity)
                if !vistaPulita {
                    Divider().overlay(Tema.lineaTenue)
                    pannelloFotocamera
                        .frame(width: 300)
                        .background(Tema.barraLaterale)
                }
            }
        }
        .background(vistaPulita ? Color.black : Tema.fondo)
        .background(MonitorTastiera(gestisci: tasto))
        .foregroundStyle(Tema.testo)
        // Azioni e selezione in ciano (Specchia, Riempi, «Modalità avanzata» accesi), non nel colore di sistema.
        .tint(Tema.ciano)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            ricevitore.schermo.imposta(riempi: riempi)
            // Per riaprire la finestra dal clic su una notifica o sull'icona nel Dock (DelegatoApp).
            if Notifiche.condivise.apriFinestraPrincipale == nil {
                let apri = apriFinestra
                Notifiche.condivise.apriFinestraPrincipale = { apri(id: WebcamLRMacApp.idPrincipale) }
            }
        }
        .onChange(of: riempi) { ricevitore.schermo.imposta(riempi: riempi) }
        // Pausa intelligente: il telefono sa se qui qualcuno vede il video (finestra coperta, ridotta a icona, chiusa).
        .background(OsservatoreFinestra { visibile in ricevitore.aggiornaVisibilitaPrincipale(visibile) })
        .onDisappear { ricevitore.aggiornaVisibilitaPrincipale(false) }
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
    /// Se la finestra è stretta (960 punti, registrazione in corso, avviso dello spazio) i pulsanti
    /// restano solo icone: il nome è nell'aiuto e per VoiceOver. Mai oltre il bordo della finestra.
    private var intestazione: some View {
        ViewThatFits(in: .horizontal) {
            rigaIntestazione(compatta: false)
            rigaIntestazione(compatta: true)
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Tema.pannelloScuro)
    }

    private func rigaIntestazione(compatta: Bool) -> some View {
        HStack(spacing: compatta ? 8 : 12) {
            LogoWebcamLR(lato: 20)
            MarchioWebcamLR(dimensione: 18)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            PillolaStato(ricevitore.collegamento)
            if let liberi = riprese.spazioScarso {
                // Spazio quasi finito durante la registrazione (funzione 37): avviso in ambra.
                Label("Solo \(Riprese.testoByte(liberi)) liberi", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
                    .help("Solo \(Riprese.testoByte(liberi)) liberi: lo spazio sul disco sta finendo. Ferma la registrazione o libera spazio.")
            }
            pulsanteRegistra(compatto: compatta)
            // Modalità avanzata (1.5) a vista: un clic mostra o nasconde numeri, grafico, controlli manuali e registro.
            Toggle(isOn: $avanzata) {
                Label("Modalità avanzata", systemImage: "slider.horizontal.3")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .toggleStyle(.button)
            .help(avanzata ? "Modalità avanzata accesa: numeri, grafico, controlli manuali e registro. Clic per tornare all'essenziale."
                  : "Modalità avanzata: mostra numeri del collegamento, grafico della latenza, controlli manuali e registro.")
            // Tutto dentro l'app, niente menu in più: aiuto (guida, domande frequenti, «Segnala un bug»,
            // Pro, informazioni) e impostazioni.
            Button {
                apriFinestraApp(.guida, apri: apriFinestra)
            } label: {
                Label("Aiuto", systemImage: "questionmark.circle")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .help("Guida, domande frequenti, «Segnala un bug» e informazioni")
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Impostazioni (⌘,)")
            .accessibilityLabel("Impostazioni")
        }
    }

    // MARK: - Barra laterale

    /// Telefoni e uscite scorrono se non ci stanno (finestra alta 600 con la diagnosi aperta):
    /// prima ogni testo veniva tagliato con «…». Il suggerimento resta sempre in fondo.
    private var barraLaterale: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    sezioneTelefoni
                    sezioneUscite
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Text(fotocamera.stato == .attiva
                 ? LocalizedStringKey("Nelle app scegli **WebcamLR** come videocamera.")
                 : LocalizedStringKey("Il video si vede qui. Con la webcam virtuale lo vedono anche Zoom, Meet, Teams e le altre app."))
                .font(.callout)
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 8))
                .padding([.horizontal, .bottom], 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var sezioneTelefoni: some View {
        VStack(alignment: .leading, spacing: 8) {
            EtichettaSezione("Telefoni").padding(.horizontal, 8)
            if let telefono = ricevitore.telefono {
                SchedaTelefono(telefono: telefono, stato: ricevitore.statoTelefono,
                               latenza: avanzata ? ricevitore.statistiche.latenzaMs : nil,
                               via: ricevitore.tipoCollegamento, collegato: ricevitore.telefonoAttivo,
                               avanzata: avanzata, avvio: ricevitore.tempoAvvio)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("In attesa di un telefono")
                    // Diagnosi (1.3): una causa e cosa fare, al posto del solo errore.
                    if let diagnosi = Diagnosi.calcola(ricevitore, wifiDiretto: wifiDiretto) {
                        RiquadroDiagnosi(diagnosi: diagnosi, ricevitore: ricevitore)
                            .help(testoRete)
                            .padding(.vertical, 4)
                    } else {
                        Text(testoRete)
                            .font(.numeri(11.5))
                            .foregroundStyle(Tema.testoSecondario)
                    }
                    Button {
                        mostraQR.toggle()
                    } label: {
                        Label("Collega con QR code", systemImage: "qrcode")
                    }
                    .padding(.top, 6)
                    .popover(isPresented: $mostraQR, arrowEdge: .trailing) {
                        PannelloAssociazione(ricevitore: ricevitore)
                            .padding(16)
                            .frame(width: 240)
                    }
                    Button("Il telefono non trova il Mac?") {
                        apriDomandaFrequente("non-trova", apri: apriFinestra)
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .tint(Tema.ciano)
                }
                .padding(10)
            }
            if avanzata {
                pulsanteRegistro
            }
        }
    }

    private var sezioneUscite: some View {
        VStack(alignment: .leading, spacing: 6) {
            EtichettaSezione("Uscite").padding(.horizontal, 8)
            RigaUscita(nome: "Webcam virtuale", stato: testoFotocamera, attiva: fotocamera.stato == .attiva)
            if !fotocamera.disponibile {
                Text("Richiede l'account sviluppatore Apple a pagamento.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
                    .padding(.horizontal, 8)
            } else if fotocamera.stato == .daApprovare {
                Button("Apri Impostazioni di Sistema") { fotocamera.apriImpostazioni() }
                    .padding(.horizontal, 8)
            } else if fotocamera.stato != .attiva {
                Button("Attiva la webcam virtuale") { fotocamera.attiva() }
                    .disabled(fotocamera.stato == .inCorso)
                    .padding(.horizontal, 8)
            } else {
                // Prima di cestinare l'app (Documenti/Webcam virtuale Mac.md).
                Button("Rimuovi la webcam virtuale") { fotocamera.rimuovi() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Tema.testoTenue)
                    .padding(.horizontal, 8)
            }
            if let spiegazione = spiegazioneFotocamera {
                Text(spiegazione)
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            RigaUscita(nome: "Microfono", stato: "in arrivo", attiva: false, inArrivo: true)
            RigaUscita(nome: "Uscita NDI", stato: "in arrivo", attiva: false, inArrivo: true)
        }
    }

    /// Modalità avanzata (1.5): gli ultimi eventi del collegamento, per capire cosa è successo.
    private var pulsanteRegistro: some View {
        Button {
            mostraRegistro.toggle()
        } label: {
            Label("Registro del collegamento", systemImage: "list.bullet.rectangle")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tema.testoTenue)
        .padding(.horizontal, 8)
        .help("Gli ultimi \(Ricevitore.righeRegistro) eventi del collegamento, solo su questo Mac")
        .popover(isPresented: $mostraRegistro, arrowEdge: .trailing) {
            VistaRegistro(voci: ricevitore.registro)
        }
    }

    private var testoRete: String {
        switch ricevitore.rete {
        case .fermo: "Mi faccio trovare in rete…"
        case .visibile(let porta): "Visibile in rete · porta \(porta)"
        case .errore(let descrizione): descrizione
        }
    }

    private var testoFotocamera: String {
        guard fotocamera.disponibile else { return "non inclusa" }
        return switch fotocamera.stato {
        case .nonAttiva: "spenta"
        case .inCorso: "attivazione…"
        case .daApprovare: "da approvare"
        case .riavvioNecessario: "riavvia il Mac"
        case .attiva: "attiva"
        case .errore: "non attivata"
        }
    }

    /// Cosa fare quando la webcam virtuale non è ancora pronta.
    private var spiegazioneFotocamera: String? {
        switch fotocamera.stato {
        case .daApprovare: AttivazioneFotocamera.doveApprovare
        case .riavvioNecessario: "Riavvia il Mac per finire di installarla."
        case .errore(let spiegazione): spiegazione
        default: nil
        }
    }

    // MARK: - Anteprima

    private var anteprima: some View {
        VStack(spacing: 12) {
            riquadroVideo
            if !vistaPulita {
                BarraStatistiche(statistiche: ricevitore.statistiche, storico: ricevitore.storicoLatenza,
                                 collegato: ricevitore.telefono != nil, via: ricevitore.tipoCollegamento,
                                 avanzata: avanzata, avvio: ricevitore.tempoAvvio)
                pulsantiAnteprima
                Spacer(minLength: 0)
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var videoConSovrapposizioni: some View {
        ZStack(alignment: .topLeading) {
            VistaSchermo(livello: ricevitore.schermo.livello)
                .scaleEffect(x: specchia ? -1 : 1, y: 1)
            if ricevitore.telefono == nil {
                PrimoCollegamento(ricevitore: ricevitore)
            } else if let motivo = ricevitore.statoTelefono?.pausa {
                // Pausa intelligente: il telefono non manda video, ma è collegato. Niente rosso: è uno stato calmo.
                SovrapposizionePausa(motivo: motivo)
            }
            VStack(alignment: .leading, spacing: 8) {
                if ricevitore.collegamento == .riconnessione {
                    PillolaStato(.riconnessione)
                }
                avvisiTelefono
            }
            .padding(12)
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
                Text(avviso)
                    .font(.callout)
                    .foregroundStyle(Tema.testo)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Tema.pannelloChiaro.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
            pulsanteEsciVistaPulita
        }
        .animation(.default, value: riprese.avviso)
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
    }

    /// Avvisi dal telefono sopra il video (funzione 33): caldo e batteria, in ambra.
    @ViewBuilder private var avvisiTelefono: some View {
        if let stato = ricevitore.statoTelefono, ricevitore.telefono != nil {
            if stato.temperatura == .moltoCalda || stato.temperatura == .critica {
                BannerAvviso(icona: "thermometer",
                             testo: stato.temperatura == .critica
                                ? "Il telefono è troppo caldo: il video può fermarsi. Toglilo dal sole o dalla custodia."
                                : "Il telefono è molto caldo: la qualità può calare. Toglilo dal sole o dalla custodia.")
            }
            if stato.batteria >= 0, stato.batteria <= 20, !stato.inCarica {
                BannerAvviso(icona: "battery.25",
                             testo: "Batteria del telefono al \(stato.batteria)%: collega il caricatore.")
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
                    .font(.callout)
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

    /// A 960 punti con il telefono collegato non ci stanno tutti con i nomi: allora «Foto» e «Scollega»
    /// restano solo icone (il nome è nell'aiuto e per VoiceOver), mai oltre il bordo del riquadro.
    private var pulsantiAnteprima: some View {
        ViewThatFits(in: .horizontal) {
            rigaPulsantiAnteprima(compatta: false)
            rigaPulsantiAnteprima(compatta: true)
        }
    }

    private func rigaPulsantiAnteprima(compatta: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                riprese.scattaFoto()
            } label: {
                Label("Foto", systemImage: "camera")
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
            }
            .richiedeTelefono(ricevitore.telefono != nil)
            .help("Salva l'immagine attuale in Immagini › WebcamLR (⌘T)")
            Button {
                riprese.scattaConTimer()
            } label: {
                Image(systemName: riprese.contoAllaRovescia == nil ? "timer" : "xmark")
            }
            // Il timer partito si può sempre annullare, anche se intanto il telefono se n'è andato.
            .richiedeTelefono(ricevitore.telefono != nil || riprese.contoAllaRovescia != nil)
            .help(riprese.contoAllaRovescia == nil ? "Foto tra 3 secondi (⇧⌘T)" : "Annulla il timer")
            .accessibilityLabel(riprese.contoAllaRovescia == nil ? "Foto tra 3 secondi" : "Annulla il timer")
            Button {
                riprese.copiaFotogramma()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .richiedeTelefono(ricevitore.telefono != nil)
            .help("Copia l'immagine attuale, da incollare ovunque (⌘C)")
            .accessibilityLabel("Copia il fotogramma")
            // Solo icone; il nome è nell'aiuto e per VoiceOver.
            Toggle(isOn: $specchia) {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .toggleStyle(.button)
            .help("Specchia l'anteprima: vale solo qui, le altre app ricevono il video dritto")
            .accessibilityLabel("Specchia")
            Toggle(isOn: $riempi) {
                Image(systemName: "aspectratio")
            }
            .toggleStyle(.button)
            .help(riempi ? "Il video riempie il riquadro; spegni per vederlo intero (⌥⌘F)"
                  : "Riempi il riquadro, tagliando i bordi del video (⌥⌘F)")
            .accessibilityLabel("Riempi il riquadro")
            Button {
                vistaPulita = true
            } label: {
                Image(systemName: "rectangle.inset.filled")
            }
            .help("Vista pulita: solo il video (⇧⌘P, Esc per uscire)")
            .accessibilityLabel("Vista pulita")
            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            // ⌃⌘F c'è già nel menu Vista di sistema: qui solo il suggerimento.
            .help("Schermo intero (⌃⌘F)")
            .accessibilityLabel("Schermo intero")
            Button {
                alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
            } label: {
                Image(systemName: ricevitore.miniAperta ? "pip.exit" : "pip.enter")
            }
            .help(ricevitore.miniAperta ? "Chiudi la finestra mini (⇧⌘M)" : "Finestra mini, sempre in primo piano (⇧⌘M)")
            .accessibilityLabel(ricevitore.miniAperta ? "Chiudi la finestra mini" : "Apri la finestra mini")
            Spacer(minLength: 8)
            if ricevitore.telefono != nil {
                Button {
                    ricevitore.scollega()
                } label: {
                    Label("Scollega il telefono", systemImage: "iphone.slash")
                        .labelStyle(StileEtichettaAdattabile(compatta: compatta, soloTesto: true))
                }
                .help("Scollega il telefono: non si ricollega da solo")
            }
        }
    }

    /// Registra (funzione 35): il rosso è permesso, come per «in onda».
    /// Mentre registra mostra durata e dimensione del file (funzione 37).
    /// `compatto`: solo il punto rosso e il tempo (finestra stretta); dimensione e «Ferma» restano nell'aiuto.
    @ViewBuilder private func pulsanteRegistra(compatto: Bool) -> some View {
        if let inizio = riprese.inizioRegistrazione {
            Button {
                riprese.fermaRegistrazione()
            } label: {
                HStack(spacing: 6) {
                    // Letta qui, sulla coda principale: la chiusura del TimelineView resta senza stato di Riprese.
                    let dimensione = Riprese.testoByte(riprese.dimensioneRegistrazione)
                    Circle().fill(Tema.tally).frame(width: 10, height: 10)
                    TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                        let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                        let tempo = String(format: "%02d:%02d", secondi / 60, secondi % 60)
                        Text(compatto ? tempo : "Ferma · " + tempo + " · " + dimensione)
                            .font(.numeri(12.5))
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
            .richiedeTelefono(ricevitore.telefonoAttivo)
            .help("Registra il video del telefono in Filmati › WebcamLR (⌘R)")
        }
    }

    // MARK: - Fotocamera

    /// Scorre se non ci sta: in modalità avanzata con ISO, tempo e bianco manuali, a 600 punti di altezza,
    /// i comandi in fondo (torcia, messa a fuoco) finivano fuori dalla finestra.
    private var pannelloFotocamera: some View {
        ScrollView(.vertical) {
            contenutoPannelloFotocamera
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contenutoPannelloFotocamera: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fotocamera")
                .font(.titolo(22))
            if let stato = ricevitore.statoTelefono {
                VStack(alignment: .leading, spacing: 10) {
                    RigaDato(nome: "Obiettivo", valore: Ricevitore.nome(obiettivo: stato.obiettivo))
                    RigaDato(nome: "Batteria", valore: stato.batteria >= 0 ? "\(stato.batteria)%\(stato.inCarica ? " · in carica" : "")" : "—")
                    RigaDato(nome: "Temperatura", valore: descrizione(stato.temperatura),
                             avviso: stato.temperatura == .moltoCalda || stato.temperatura == .critica)
                }
            }
            if let capacita = ricevitore.capacita, ricevitore.telefonoAttivo {
                ControlliFotocamera(ricevitore: ricevitore, capacita: capacita,
                                    obiettivoAttuale: ricevitore.controlli.obiettivo ?? ricevitore.statoTelefono?.obiettivo)
                // Solo ciò che il telefono dichiara; un telefono senza effetti non mostra la sezione.
                if Effetti.disponibili(capacita) {
                    Divider().overlay(Tema.lineaTenue)
                    ControlliEffetti(ricevitore: ricevitore, capacita: capacita)
                }
            } else {
                Text(testoComandiAssenti)
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                // Gli stessi comandi, grigi: si vede cosa arriva con il telefono; un clic dice «Collega un telefono».
                AnteprimaControlliFotocamera(avanzata: avanzata)
                    .richiedeTelefono(false)
                Divider().overlay(Tema.lineaTenue)
                AnteprimaEffetti(avanzata: avanzata)
                    .richiedeTelefono(false)
            }
        }
    }

    /// Perché i comandi sono grigi. Durante la riconnessione il telefono c'è ancora: non si chiede di collegarne uno.
    private var testoComandiAssenti: String {
        if ricevitore.collegamento == .riconnessione {
            return "Mi ricollego al telefono: i comandi tornano appena il video riprende."
        }
        if ricevitore.telefono != nil {
            return "Il telefono è collegato: i comandi arrivano tra un attimo."
        }
        return "Si attivano quando colleghi un telefono."
    }

    private func descrizione(_ temperatura: Temperatura) -> String {
        switch temperatura {
        case .normale: "normale"
        case .calda: "calda"
        case .moltoCalda: "molto calda"
        case .critica: "critica"
        }
    }
}

// MARK: - Componenti

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
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Tema.ambraTenue.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.ambra.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

/// Sopra il video quando il telefono è in pausa (`stato.pausa`): calmo, nei colori del pannello, mai in rosso.
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
                .font(.callout)
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

/// Al posto del video finché non c'è un telefono (funzione 32): QR code grande e i tre passi.
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
        .background(Tema.pannelloScuro)
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

    private func passo(_ numero: Int, _ testo: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(numero)")
                .font(.numeriEvidenti(13))
                .foregroundStyle(Tema.testo)
                .frame(width: 24, height: 24)
                .background(Tema.pannelloChiaro, in: Circle())
            Text(testo)
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SchedaTelefono: View {
    let telefono: Ciao
    let stato: StatoTelefono?
    let latenza: Int?
    let via: TipoCollegamento?
    let collegato: Bool
    /// In modalità semplice niente millisecondi: solo come è collegato e la batteria.
    let avanzata: Bool
    /// «Avvio: 0,9 s» (1.11), solo in modalità avanzata.
    var avvio: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(collegato ? Tema.verde : Tema.ambra)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(telefono.nome)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Text(dettagli)
                .font(.numeri(11.5))
                .foregroundStyle(Tema.testoTenue)
                .padding(.leading, 16)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.cianoTenue, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityValue(collegato ? "collegato" : "in riconnessione")
    }

    private var dettagli: String {
        var parti = [via?.testo ?? "—"]
        if avanzata { parti.append(latenza.map { "\($0) ms" } ?? "— ms") }
        if avanzata, let avvio { parti.append(avvio) }
        if let stato, stato.batteria >= 0 { parti.append("\(stato.batteria)%") }
        return parti.joined(separator: " · ")
    }
}

/// Sotto l'anteprima: la qualità in parole e il grafico della latenza; i numeri si aprono con un clic (funzioni 28 e 31).
private struct BarraStatistiche: View {
    let statistiche: Statistiche
    let storico: [Int?]
    let collegato: Bool
    let via: TipoCollegamento?
    /// Modalità semplice (1.5): solo la qualità in parole e come è collegato; numeri e grafico in modalità avanzata.
    let avanzata: Bool
    /// «Avvio: 0,9 s» (1.11): dall'arrivo del telefono al primo fotogramma a schermo.
    var avvio: String?
    @State private var mostraNumeri = false

    var body: some View {
        // A 960 punti in modalità avanzata non ci sta tutto: prima sparisce il grafico, poi la risoluzione
        // (resta nei numeri con un clic). Mai oltre il bordo del riquadro.
        ViewThatFits(in: .horizontal) {
            riga(dettaglio: 2)
            riga(dettaglio: 1)
            riga(dettaglio: 0)
        }
        .font(.numeri(12))
        .foregroundStyle(Tema.testoTenue)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.lineaTenue))
        // Sulla barra e non sul pulsante: delle tre varianti se ne vede una sola.
        .popover(isPresented: $mostraNumeri, arrowEdge: .top) {
            numeri
        }
    }

    /// `dettaglio`: 2 con grafico e risoluzione, 1 senza grafico, 0 senza nemmeno la risoluzione.
    private func riga(dettaglio: Int) -> some View {
        HStack(spacing: 14) {
            if collegato && statistiche.larghezza > 0 && !avanzata {
                if let latenza = statistiche.latenzaMs {
                    ChipQualita(QualitaCollegamento(latenzaMs: latenza), latenzaMs: latenza)
                } else {
                    Text("Misuro il collegamento…")
                        .lineLimit(1)
                }
                if let via {
                    IndicatoreCollegamento(via, qualita: statistiche.latenzaMs.map { QualitaCollegamento(latenzaMs: $0) })
                }
                Spacer(minLength: 0)
            } else if collegato && statistiche.larghezza > 0 {
                Button {
                    mostraNumeri.toggle()
                } label: {
                    HStack(spacing: 6) {
                        if let latenza = statistiche.latenzaMs {
                            ChipQualita(QualitaCollegamento(latenzaMs: latenza), latenzaMs: latenza)
                        } else {
                            Text("Misuro il collegamento…")
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Tema.testoSecondario)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Mostra i numeri del collegamento")
                .accessibilityHint("Mostra i numeri del collegamento")

                if let via {
                    IndicatoreCollegamento(via, qualita: statistiche.latenzaMs.map { QualitaCollegamento(latenzaMs: $0) })
                }

                if dettaglio >= 2 {
                    GraficoLatenza(valori: storico)
                        .frame(width: 150, height: 20)
                        .help("Latenza dell'ultimo minuto; la riga tratteggiata è a 100 ms")
                }

                Spacer(minLength: 0)
                if dettaglio >= 1 {
                    Text("\(min(statistiche.larghezza, statistiche.altezza))p\(statistiche.fps) · \(nomeCodec)")
                        .lineLimit(1)
                }
            } else {
                Text("Nessun telefono collegato")
                    .lineLimit(1)
                Spacer(minLength: 0)
                if avanzata && dettaglio >= 1 {
                    // In modalità avanzata si vede già dove arriveranno i numeri.
                    Text("— ms · —p — fps · —")
                        .lineLimit(1)
                        .foregroundStyle(Tema.testoSecondario)
                        .richiedeTelefono(false)
                }
            }
        }
    }

    /// I numeri di sempre, a portata di clic.
    private var numeri: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            riga("Risoluzione", "\(statistiche.larghezza)×\(statistiche.altezza)")
            riga("Fotogrammi", "\(statistiche.fps) al secondo")
            riga("Formato", nomeCodec)
            riga("Velocità", String(format: "%.1f Mbit/s", statistiche.megabitAlSecondo).replacingOccurrences(of: ".", with: ","))
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
                riga("Avvio", avvio.replacingOccurrences(of: "Avvio: ", with: ""))
            }
            Divider().gridCellColumns(2)
            Text("Ottimo sotto gli 80 ms, buono sotto i 150.")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
                .gridCellColumns(2)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func riga(_ nome: String, _ valore: String) -> some View {
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

    /// Ciano sotto i 100 ms (l'obiettivo per una chiamata), ambra sopra.
    private var coloreLatenza: Color {
        guard let latenza = statistiche.latenzaMs else { return Tema.testoTenue }
        return latenza < 100 ? Tema.cianoChiaro : Tema.ambra
    }
}

/// Un'uscita del video. Quelle «in arrivo» sono tenui, con l'etichetta in una capsula: si vede che è voluto.
private struct RigaUscita: View {
    let nome: String
    let stato: String
    let attiva: Bool
    var inArrivo = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: inArrivo ? "clock" : attiva ? "checkmark" : "minus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(attiva ? Tema.verde : Tema.testoSecondario)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(nome)
                .foregroundStyle(inArrivo ? Tema.testoSecondario : Tema.testo)
                .lineLimit(1)
            Spacer(minLength: 8)
            if inArrivo {
                Text(stato.uppercased())
                    .font(.etichetta(12))
                    .tracking(0.6)
                    .foregroundStyle(Tema.testoSecondario)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(Tema.linea))
                    .fixedSize()
            } else {
                Text(stato)
                    .font(.caption)
                    .foregroundStyle(attiva ? Tema.verde : Tema.testoSecondario)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}

private struct RigaDato: View {
    let nome: String
    let valore: String
    var avviso = false

    var body: some View {
        HStack {
            Text(nome).foregroundStyle(Tema.testoSecondario)
            Spacer()
            Text(valore)
                .font(.numeri(12.5))
                .foregroundStyle(avviso ? Tema.ambra : Tema.testo)
        }
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

    func updateNSView(_ vista: Vista, context: Context) {}
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
private struct StileEtichettaAdattabile: LabelStyle {
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

    @ViewBuilder func body(content: Content) -> some View {
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
                        .font(.callout)
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

/// I comandi della fotocamera come appariranno con un telefono, ma fermi: obiettivo, zoom, esposizione,
/// torcia e messa a fuoco; in modalità avanzata anche profili, ISO e tempo, bianco.
private struct AnteprimaControlliFotocamera: View {
    let avanzata: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if avanzata {
                Label("Profili", systemImage: "slider.horizontal.3")
            }
            VStack(alignment: .leading, spacing: 6) {
                EtichettaSezione("Obiettivo")
                Picker("Obiettivo", selection: .constant(1)) {
                    Text("0,5×").tag(0)
                    Text("1×").tag(1)
                    Text("Tele").tag(2)
                    Text("Frontale").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            cursore("Zoom", testo: "1,0×")
            cursore("Esposizione", testo: "+0,0")
            if avanzata {
                Toggle("Esposizione manuale (ISO e tempo)", isOn: .constant(false))
                Toggle("Bilanciamento del bianco automatico", isOn: .constant(true))
            }
            // Uno accanto all'altro se ci stanno, altrimenti uno sotto l'altro: mai oltre il bordo del pannello.
            ViewThatFits(in: .horizontal) {
                HStack { pulsantiFinali }
                VStack(alignment: .leading, spacing: 8) { pulsantiFinali }
            }
        }
        .tint(Tema.ciano)
    }

    @ViewBuilder private var pulsantiFinali: some View {
        Toggle("Torcia", isOn: .constant(false))
            .toggleStyle(.button)
        Button("Messa a fuoco automatica") {}
    }

    private func cursore(_ nome: String, testo: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nome)
                Spacer()
                Text(testo)
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoTenue)
            }
            Slider(value: .constant(0.5))
                .labelsHidden()
        }
    }
}

/// Comandi della fotocamera del telefono dal Mac: ogni modifica parte subito come `comando`.
private struct ControlliFotocamera: View {
    @Bindable var ricevitore: Ricevitore
    let capacita: Capacita
    let obiettivoAttuale: String?
    /// Modalità semplice (1.5): obiettivo, zoom, esposizione, torcia e messa a fuoco. ISO, tempo, bianco
    /// e profili solo in modalità avanzata.
    @AppStorage(Preferenze.modalitaAvanzata) private var avanzata = false
    @State private var chiediNome = false
    @State private var nomeProfilo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if avanzata {
                profili
            }
            VStack(alignment: .leading, spacing: 6) {
                EtichettaSezione("Obiettivo")
                Picker("Obiettivo", selection: Binding(
                    get: { obiettivoAttuale ?? capacita.obiettivi.first ?? "" },
                    set: { nuovo in ricevitore.scegliObiettivo(nuovo) })) {
                    ForEach(capacita.obiettivi, id: \.self) { obiettivo in
                        Text(Ricevitore.etichetta(obiettivo: obiettivo)).tag(obiettivo)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Tasti da 1 a \(min(capacita.obiettivi.count, 4))")
            }

            if capacita.zoomMassimo > 1 {
                cursore("Zoom", valore: $ricevitore.controlli.zoom, intervallo: 1...capacita.zoomMassimo, passo: 0.1,
                        testo: String(format: "%.1f×", ricevitore.controlli.zoom)) { valore in
                    Comando(zoom: valore)
                }
                .help("Tasti + e −")
            }

            if !ricevitore.controlli.esposizioneManuale {
                cursore("Esposizione", valore: $ricevitore.controlli.esposizione, intervallo: -2...2, passo: 0.1,
                        testo: String(format: "%+.1f", ricevitore.controlli.esposizione)) { valore in
                    Comando(esposizione: valore)
                }
            }

            // In modalità semplice restano visibili solo se sono già in manuale: così si possono rimettere in automatico.
            if avanzata || ricevitore.controlli.esposizioneManuale {
                esposizioneManuale
            }
            if avanzata || !ricevitore.controlli.biancoAutomatico {
                bilanciamentoBianco
            }

            // Uno accanto all'altro se ci stanno, altrimenti uno sotto l'altro: mai oltre il bordo del pannello.
            ViewThatFits(in: .horizontal) {
                HStack { torciaEFuoco }
                VStack(alignment: .leading, spacing: 8) { torciaEFuoco }
            }
        }
        .tint(Tema.ciano)
    }

    @ViewBuilder private var torciaEFuoco: some View {
        if capacita.torcia {
            Toggle("Torcia", isOn: Binding(
                get: { ricevitore.controlli.torcia },
                set: { accesa in
                    ricevitore.controlli.torcia = accesa
                    ricevitore.comanda(Comando(torcia: accesa))
                }))
            .toggleStyle(.button)
        }
        Button("Messa a fuoco automatica") {
            ricevitore.fuocoAutomatico()
        }
        .help("Tasto F")
    }

    /// Bilanciamento del bianco automatico o manuale (modalità avanzata).
    private var bilanciamentoBianco: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Bilanciamento del bianco automatico", isOn: Binding(
                get: { ricevitore.controlli.biancoAutomatico },
                set: { automatico in
                    ricevitore.controlli.biancoAutomatico = automatico
                    ricevitore.comanda(Comando(bianco: automatico ? 0 : Int(ricevitore.controlli.bianco)))
                }))
            if !ricevitore.controlli.biancoAutomatico {
                cursore("Bianco", valore: $ricevitore.controlli.bianco, intervallo: 2500...7500, passo: 100,
                        testo: "\(Int(ricevitore.controlli.bianco)) K") { valore in
                    Comando(bianco: Int(valore))
                }
            }
        }
    }

    /// Profili (funzione 23): tutti i comandi qui sotto, salvati per nome e riapplicati con un clic.
    private var profili: some View {
        Menu {
            let nomi = ricevitore.profili.keys.sorted()
            ForEach(nomi, id: \.self) { nome in
                Button(nome) { ricevitore.applicaProfilo(nome) }
            }
            if !nomi.isEmpty { Divider() }
            Button("Salva i comandi attuali…") {
                nomeProfilo = ""
                chiediNome = true
            }
            if !nomi.isEmpty {
                Menu("Elimina") {
                    ForEach(nomi, id: \.self) { nome in
                        Button(nome, role: .destructive) { ricevitore.eliminaProfilo(nome) }
                    }
                }
            }
        } label: {
            Label("Profili", systemImage: "slider.horizontal.3")
        }
        .alert("Nuovo profilo", isPresented: $chiediNome) {
            TextField("Nome, per esempio «Riunione»", text: $nomeProfilo)
            Button("Salva") {
                let nome = nomeProfilo.trimmingCharacters(in: .whitespaces)
                if !nome.isEmpty { ricevitore.salvaProfilo(nome) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Obiettivo, zoom, esposizione, bianco e torcia di adesso. Con lo stesso nome il profilo si sovrascrive.")
        }
    }

    /// ISO e tempo di posa manuali (funzione 19), solo se il telefono dice i limiti ISO.
    @ViewBuilder private var esposizioneManuale: some View {
        if let minimo = capacita.isoMinimo, let massimo = capacita.isoMassimo, massimo > minimo {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Esposizione manuale (ISO e tempo)", isOn: Binding(
                    get: { ricevitore.controlli.esposizioneManuale },
                    set: { manuale in
                        ricevitore.controlli.esposizioneManuale = manuale
                        let controlli = ricevitore.controlli
                        ricevitore.comanda(manuale
                            ? Comando(iso: min(max(controlli.iso, minimo), massimo), tempo: controlli.tempo)
                            : Comando(iso: 0, tempo: 0))
                    }))
                if ricevitore.controlli.esposizioneManuale {
                    cursore("ISO", valore: $ricevitore.controlli.iso, intervallo: minimo...massimo, passo: 1,
                            testo: "\(Int(ricevitore.controlli.iso))") { valore in
                        Comando(iso: valore.rounded())
                    }
                    Picker("Tempo", selection: Binding(
                        get: { ricevitore.controlli.tempo },
                        set: { nuovo in
                            ricevitore.controlli.tempo = nuovo
                            ricevitore.comanda(Comando(tempo: nuovo))
                        })) {
                        ForEach([25, 30, 50, 60, 100, 120, 250, 500], id: \.self) { denominatore in
                            Text("1/\(denominatore) s").tag(denominatore)
                        }
                    }
                }
            }
        }
    }

    private func cursore(_ nome: String, valore: Binding<Double>, intervallo: ClosedRange<Double>, passo: Double,
                         testo: String, comando: @escaping (Double) -> Comando) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nome)
                Spacer()
                Text(testo.replacingOccurrences(of: ".", with: ","))
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoTenue)
            }
            Slider(value: Binding(
                get: { valore.wrappedValue },
                set: { nuovo in
                    valore.wrappedValue = nuovo
                    ricevitore.comanda(comando(nuovo))
                }), in: intervallo, step: passo)
            .labelsHidden()
            .accessibilityLabel(nome)
            .accessibilityValue(testo.replacingOccurrences(of: ".", with: ","))
        }
    }
}

/// Il registro del collegamento (1.5): ora ed evento, il più recente in basso, con «Copia» per «Segnala un bug».
private struct VistaRegistro: View {
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
                                    Text(voce.testo)
                                        .font(.callout)
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
                .font(.footnote)
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

    private func copia() {
        let testo = voci.map { "\(Self.ora($0.ora))  \($0.testo)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testo, forType: .string)
        copiato = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copiato = false
        }
    }
}
