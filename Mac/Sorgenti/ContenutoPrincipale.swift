import AppKit
import AVFoundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Finestra del ricevitore, con l'identità di LR Apps (fondo verde scuro, salvia, corallo solo per «in onda»).
/// Interfaccia finale (Documenti/Interfaccia finale.md): in alto il marchio, lo stato, «Aiuto» e «Account»;
/// a sinistra telefoni, connessione, uscite e il QR per collegarsi sempre in fondo (ColonnaDispositivi);
/// al centro il video largo, con sopra la qualità e il collegamento (ognuno con il suo menu) e, con due telefoni,
/// la CAM 2; sotto, la barra Specchia · Sfoca · Foto · Registra | Schermo e le app che usano WebcamLR;
/// a destra il profilo, la fotocamera, gli effetti e «Scollega» (ColonnaControlli). A 960×600 le colonne scorrono.
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
    /// Il menu «Schermo» della barra sotto il video: schermo intero, finestra mini, riempi, vista pulita.
    @State private var mostraSchermo = false
    /// Il foglio di «Aggiornamento disponibile», con la versione che mostra (resta anche se intanto cambia).
    @State private var aggiornamentoMostrato: ControlloAggiornamenti.Versione?
    /// Il foglio «Telefoni conosciuti», dal menu «Account».
    @State private var mostraTelefoniConosciuti = false
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        VStack(spacing: 0) {
            if !vistaPulita {
                intestazione
                Divider().overlay(Tema.lineaTenue)
            }
            GeometryReader { spazio in
                // Colonne laterali strette (236 e 262 a 1280 punti, come nel disegno): il video è più largo.
                // Sotto i 1180 punti si stringono ancora: a 960 il video resta largo almeno 400.
                let stretta = spazio.size.width < 1180
                HStack(spacing: 0) {
                    if !vistaPulita {
                        ColonnaDispositivi(ricevitore: ricevitore, fotocamera: fotocamera)
                            .frame(width: stretta ? 220 : 236)
                            .background(Tema.barraLaterale)
                        Divider().overlay(Tema.lineaTenue)
                    }
                    centro
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !vistaPulita {
                        Divider().overlay(Tema.lineaTenue)
                        ColonnaControlli(ricevitore: ricevitore)
                            .frame(width: stretta ? 248 : 262)
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
        // `anteprima`: il telefono sa se qui qualcuno vede il video (finestra coperta, ridotta a icona, chiusa). Solo i
        // telefoni di prima del 27 ottobre andavano in pausa per questo; quelli nuovi continuano finché il Mac è aperto.
        .background(OsservatoreFinestra { visibile in ricevitore.aggiornaVisibilitaPrincipale(visibile) })
        .onDisappear { ricevitore.aggiornaVisibilitaPrincipale(false) }
        .sheet(item: $aggiornamentoMostrato) { versione in
            FoglioAggiornamento(versione: versione, controllo: ControlloAggiornamenti.condiviso)
        }
        .sheet(isPresented: $mostraTelefoniConosciuti) {
            FoglioTelefoniConosciuti(ricevitore: ricevitore)
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
    /// Marchio e stato a sinistra; a destra «Aiuto» e «Account» (WebcamLR Pro, preferenze, telefoni conosciuti, lingua,
    /// aggiornamenti, informazioni; niente login). Una versione nuova: un punto sull'«Account» e la voce nel menu.
    /// Se la finestra è stretta (960 punti) «Aiuto» e «Account» restano solo icona: il nome è nell'aiuto e per
    /// VoiceOver. Mai oltre il bordo della finestra.
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
            PillolaStato(ricevitore.collegamento, testo: testoStato)
                .padding(.leading, 4)
            if let liberi = riprese.spazioScarso {
                // Spazio quasi finito durante la registrazione (funzione 37): avviso in ambra.
                Label("Solo \(Riprese.testoByte(liberi)) liberi", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.ambra)
                    .labelStyle(StileEtichettaAdattabile(compatta: compatta))
                    .help("Solo \(Riprese.testoByte(liberi)) liberi: lo spazio sul disco sta finendo. Ferma la registrazione o libera spazio.")
            }
            Spacer(minLength: 8)
            MenuAiuto(compatta: compatta)
            MenuAccount(ricevitore: ricevitore, compatta: compatta,
                        mostraAggiornamento: { aggiornamentoMostrato = $0 },
                        mostraTelefoniConosciuti: { mostraTelefoniConosciuti = true })
        }
    }

    /// «In attesa di un telefono» senza telefoni (come nel disegno); collegato, anche la strada: «Collegato · Wi-Fi»
    /// o «Collegato · USB». Negli altri casi la dicitura della pillola.
    private var testoStato: String? {
        switch ricevitore.collegamento {
        case .nessunTelefono:
            return String(localized: "In attesa di un telefono")
        case .collegato:
            guard let cavo = ricevitore.collegatoViaCavo else { return nil }
            return cavo ? String(localized: "Collegato · USB") : String(localized: "Collegato · Wi-Fi")
        default:
            return nil
        }
    }

    // MARK: - Centro

    private var centro: some View {
        VStack(alignment: .center, spacing: 12) {
            // Il video prende il suo spazio per primo: la barra e le app sotto usano ciò che resta.
            riquadroVideo
                .layoutPriority(1)
            if !vistaPulita {
                barraStudio
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

    /// Le etichette sopra il video (qualità, collegamento, CAM 1) ci sono solo con il video che arriva.
    private var mostraChip: Bool {
        !vistaPulita && ricevitore.telefono != nil && ricevitore.statistiche.larghezza > 0
    }

    private var videoConSovrapposizioni: some View {
        ZStack(alignment: .topLeading) {
            // Il video com'è arrivato, mai specchiato qui: «Specchia» lo fa il telefono per tutti (1.14).
            // Senza telefono lo `Schermo` mostra la schermata di attesa, la stessa che vedono Zoom e le altre app.
            VistaSchermo(livello: ricevitore.schermo.livello)
            // In alto a sinistra: qualità e collegamento, ognuno con il suo menu; sotto, gli avvisi.
            // La pausa la mostra la schermata di attesa sopra il video («Webcam in pausa»), uguale a quella che vede Zoom.
            VStack(alignment: .leading, spacing: 8) {
                if mostraChip {
                    HStack(spacing: 8) {
                        MenuQualita(ricevitore: ricevitore)
                        if let via = ricevitore.tipoCollegamento {
                            MenuCollegamento(ricevitore: ricevitore, via: via)
                        }
                    }
                }
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
            // In basso a sinistra: «CAM 1 · nome» (corallo solo in onda); senza telefono, che cosa si sta guardando.
            if mostraChip, let nome = ricevitore.telefono?.nome {
                EtichettaCam(nome: nome, inOnda: inOnda, dueTelefoni: !ricevitore.altri.isEmpty)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else if !vistaPulita && ricevitore.telefono == nil {
                Text("Quello che vedono Zoom e le altre app")
                    .font(.corpo(12.5))
                    .modifier(StileChipVideo())
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            // Con due telefoni (P21): la CAM 2 dentro il video, in basso a destra, solo quando c'è.
            // In vista pulita no: lì c'è solo il video.
            if !vistaPulita, let altro = ricevitore.altri.first {
                GeometryReader { spazio in
                    RiquadroSecondoTelefono(telefono: altro, larghezza: min(230, spazio.size.width * 0.32)) {
                        ricevitore.scegli(altro)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .onAppear { ricevitore.aggiornaVisibilitaMiniatura(true) }
                .onDisappear { ricevitore.aggiornaVisibilitaMiniatura(false) }
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
                // Sopra «CAM 1» e la CAM 2, che stanno in basso.
                Text(avviso)
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.testo)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Tema.pannelloChiaro.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.bottom, ricevitore.altri.isEmpty ? 48 : 150)
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

    // MARK: - Barra sotto il video

    /// Sotto il video, come nel disegno: Specchia · Sfoca · Foto · Registra | Schermo, con icona e nome.
    /// Più stretta quando la finestra è piccola; al limite solo le icone (il nome resta nell'aiuto e per VoiceOver).
    /// «Schermo» apre schermo intero, finestra mini, riempi e vista pulita; «Scollega» è nella colonna di destra.
    private var barraStudio: some View {
        ViewThatFits(in: .horizontal) {
            rigaStudio(larghezza: 86, soloIcona: false)
            rigaStudio(larghezza: 68, soloIcona: false)
            rigaStudio(larghezza: 46, soloIcona: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func rigaStudio(larghezza: CGFloat, soloIcona: Bool) -> some View {
        BarraStudio {
            pulsantiVideo(larghezza: larghezza, soloIcona: soloIcona)
            pulsanteFoto(larghezza: larghezza, soloIcona: soloIcona)
            pulsanteRegistra(larghezza: larghezza, soloIcona: soloIcona)
            SeparatoreStudio()
            pulsanteSchermo(larghezza: larghezza, soloIcona: soloIcona)
        }
        .fixedSize()
    }

    /// «Specchia» e «Sfoca» (1.14): un clic, accesi pieni nell'accento salvia. Valgono per il video inviato, quello
    /// che vedono anche le app e il telefono: il telefono li applica e il pulsante segue il suo `stato`.
    /// Senza telefono restano grigi; con un telefono che non li sa fare (`capacita`) non ci sono.
    @ViewBuilder private func pulsantiVideo(larghezza: CGFloat, soloIcona: Bool) -> some View {
        let inAttesa = !ricevitore.telefonoAttivo || ricevitore.capacita == nil
        if inAttesa || ricevitore.specchioDisponibile {
            let acceso = !inAttesa && ricevitore.specchiato
            Button {
                ricevitore.alternaSpecchio()
            } label: {
                Label("Specchia", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .buttonStyle(StilePulsanteStudio(acceso: acceso, larghezza: larghezza, soloIcona: soloIcona))
            .help(acceso ? "Specchiato: le app di chiamata, il telefono e questa finestra vedono il video girato. Clic per raddrizzarlo"
                  : "Specchia il video da sinistra a destra: per le app di chiamata, il telefono e questa finestra")
            .accessibilityLabel("Specchia")
            .accessibilityAddTraits(acceso ? .isSelected : [])
            .richiedeTelefono(!inAttesa)
        }
        if inAttesa || ricevitore.sfondoDisponibile {
            let acceso = !inAttesa && ricevitore.sfondoSfocato
            Button {
                ricevitore.alternaSfocatura()
            } label: {
                Label("Sfoca", systemImage: "person.and.background.dotted")
            }
            .buttonStyle(StilePulsanteStudio(acceso: acceso, larghezza: larghezza, soloIcona: soloIcona))
            .help(acceso ? "Sfondo sfocato. Clic per toglierlo; dalla freccina o con il clic destro: Poco, Medio o Tanto"
                  : "Sfoca lo sfondo dietro di te. Dalla freccina o con il clic destro: Poco, Medio o Tanto")
            .accessibilityLabel("Sfoca sfondo")
            .accessibilityValue(ricevitore.livelloSfocaturaAttuale.nome)
            .accessibilityAddTraits(acceso ? .isSelected : [])
            .contextMenu { vociLivelloSfocatura }
            .overlay(alignment: .topTrailing) { freccinaSfocatura(acceso: acceso) }
            .richiedeTelefono(!inAttesa)
        }
    }

    /// La freccina nell'angolo di «Sfoca»: apre Poco · Medio · Tanto (lo stesso menu del clic destro).
    private func freccinaSfocatura(acceso: Bool) -> some View {
        Menu {
            vociLivelloSfocatura
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(acceso ? Tema.fondo : Tema.testoSecondario)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(3)
        .help("Quanto sfocare: Poco, Medio o Tanto")
        .accessibilityLabel("Livello della sfocatura")
    }

    /// Poco · Medio · Tanto, con la spunta sul livello attuale (quello che il telefono conferma). Sceglierne uno
    /// accende la sfocatura con quel livello e lo ricorda per il prossimo clic su «Sfoca».
    private var vociLivelloSfocatura: some View {
        Picker("Livello della sfocatura", selection: Binding(
            get: { ricevitore.livelloSfocaturaAttuale },
            set: { ricevitore.scegliLivelloSfocatura($0) })) {
            ForEach(LivelloSfocatura.allCases) { livello in
                Text(livello.nome).tag(livello)
            }
        }
        .pickerStyle(.inline)
    }

    /// Il segno «PRO» piccolo nell'angolo di Foto e Registra con un telefono gratis.
    @ViewBuilder private var segnoProAngolo: some View {
        if ricevitore.bloccoPro {
            SegnoPro()
                .offset(x: 4, y: -4)
                .allowsHitTesting(false)
        }
    }

    /// «Foto»: salva l'immagine attuale. Foto tra 3 secondi e copia del fotogramma con il clic destro e con ⇧⌘T e ⌘C.
    /// Con il timer partito il pulsante diventa «Annulla», anche se intanto il telefono se n'è andato.
    @ViewBuilder private func pulsanteFoto(larghezza: CGFloat, soloIcona: Bool) -> some View {
        if riprese.contoAllaRovescia != nil {
            Button {
                riprese.scattaConTimer()
            } label: {
                Label("Annulla", systemImage: "xmark")
            }
            .buttonStyle(StilePulsanteStudio(larghezza: larghezza, soloIcona: soloIcona))
            .help("Annulla il timer (⇧⌘T)")
            .accessibilityLabel("Annulla il timer")
        } else {
            Button {
                riprese.scattaFoto()
            } label: {
                Label("Foto", systemImage: "camera")
            }
            .buttonStyle(StilePulsanteStudio(larghezza: larghezza, soloIcona: soloIcona))
            .help("Salva l'immagine attuale in Immagini › WebcamLR (⌘T). Clic destro: foto tra 3 secondi o copia")
            .accessibilityLabel("Foto")
            .contextMenu {
                Button("Foto tra 3 secondi (⇧⌘T)") { riprese.scattaConTimer() }
                Button("Copia il fotogramma (⌘C)") { riprese.copiaFotogramma() }
            }
            // WebcamLR Pro: foto e registrazione con un telefono gratis restano grigie, con «PRO».
            .richiedePro(ricevitore.bloccoPro, segno: false)
            .overlay(alignment: .topTrailing) { segnoProAngolo }
            .richiedeTelefono(ricevitore.telefono != nil)
        }
    }

    /// Registra (funzione 35). Mentre registra: il punto corallo (tally) e il tempo; la dimensione del file (funzione 37)
    /// nell'aiuto e per VoiceOver.
    @ViewBuilder private func pulsanteRegistra(larghezza: CGFloat, soloIcona: Bool) -> some View {
        if let inizio = riprese.inizioRegistrazione {
            // Letta qui, sulla coda principale: la chiusura del TimelineView resta senza stato di Riprese.
            let dimensione = Riprese.testoByte(riprese.dimensioneRegistrazione)
            Button {
                riprese.fermaRegistrazione()
            } label: {
                Label {
                    TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                        let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                        Text(verbatim: String(format: "%02d:%02d", secondi / 60, secondi % 60))
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(Tema.tally)
                }
            }
            .buttonStyle(StilePulsanteStudio(larghezza: larghezza, soloIcona: soloIcona))
            .help("Ferma la registrazione e mostra il file (⌘R). Finora: \(dimensione)")
            .accessibilityLabel("Ferma la registrazione")
            .accessibilityValue(dimensione)
        } else {
            Button {
                riprese.avviaRegistrazione()
            } label: {
                Label("Registra", systemImage: "record.circle")
            }
            .buttonStyle(StilePulsanteStudio(larghezza: larghezza, soloIcona: soloIcona))
            .help("Registra il video del telefono in Filmati › WebcamLR (⌘R)")
            .accessibilityLabel("Registra")
            .richiedePro(ricevitore.bloccoPro, segno: false)
            .overlay(alignment: .topTrailing) { segnoProAngolo }
            .richiedeTelefono(ricevitore.telefonoAttivo)
        }
    }

    /// «Schermo»: le scelte della finestra in un pannello con i nomi: schermo intero, finestra mini, riempi il
    /// riquadro e vista pulita (le ultime due valgono solo qui: le altre app ricevono il video intero).
    private func pulsanteSchermo(larghezza: CGFloat, soloIcona: Bool) -> some View {
        Button {
            mostraSchermo.toggle()
        } label: {
            Label("Schermo", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(StilePulsanteStudio(larghezza: larghezza, soloIcona: soloIcona))
        .help("Schermo intero, finestra mini e vista")
        .accessibilityLabel("Schermo")
        .accessibilityHint("Schermo intero, finestra mini e vista")
        .popover(isPresented: $mostraSchermo, arrowEdge: .top) {
            pannelloSchermo
        }
    }

    private var pannelloSchermo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                mostraSchermo = false
                // La finestra principale, non il pannello appena chiuso. ⌃⌘F c'è già nel menu Vista di sistema.
                finestraPrincipale?.toggleFullScreen(nil)
            } label: {
                Label("Schermo intero (⌃⌘F)", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                mostraSchermo = false
                alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
            } label: {
                Label(ricevitore.miniAperta ? "Chiudi la finestra mini (⇧⌘M)" : "Finestra mini, sempre in primo piano (⇧⌘M)",
                      systemImage: ricevitore.miniAperta ? "pip.exit" : "pip.enter")
            }
            Divider()
                .overlay(Tema.lineaTenue)
                .padding(.vertical, 4)
            Toggle("Riempi il riquadro (⌥⌘F)", isOn: $riempi)
                .toggleStyle(.checkbox)
            Button {
                mostraSchermo = false
                vistaPulita = true
            } label: {
                Label("Vista pulita: solo il video (⇧⌘P)", systemImage: "rectangle.on.rectangle")
            }
            Text("Riempi e Vista pulita valgono solo qui: le altre app ricevono il video intero")
                .font(.corpo(12))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .font(.corpo(13.5))
        .foregroundStyle(Tema.testo)
        .tint(Tema.ciano)
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    /// La finestra principale di AppKit (per lo schermo intero dal pannello «Schermo»).
    private var finestraPrincipale: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WebcamLRMacApp.idPrincipale) == true }
    }
}

// MARK: - Componenti

/// I numeri di sempre, a un clic dal chip della qualità: risoluzione, fotogrammi, formato, velocità, latenza
/// e il grafico dell'ultimo minuto (funzioni 28 e 31).
struct PannelloNumeri: View {
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
