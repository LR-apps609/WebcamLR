import AppKit
import AVFoundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Finestra del ricevitore, con l'identità di LR Apps (fondo verde scuro, salvia, corallo solo per «in onda»).
/// Interfaccia finale (Documenti/Interfaccia finale.md): in alto il marchio, lo stato, «Impostazioni», «Aiuto» e «WebcamLR»;
/// a sinistra telefoni, connessione, uscite e il QR per collegarsi sempre in fondo (ColonnaDispositivi);
/// al centro il video largo, con sopra la qualità e il collegamento (ognuno con il suo menu) e, con due telefoni,
/// la CAM 2; sotto, la barra Specchia · Sfondo · Foto · Registra | Schermo e le app che usano WebcamLR;
/// a destra il profilo, la fotocamera, gli effetti e «Scollega» (ColonnaControlli). A 960×600 le colonne scorrono.
/// Questa è la vista «Completo». In «Essenziale» le colonne non ci sono e sul video c'è la pillola del telefono. In tutte
/// e due, in alto, «Impostazioni» (e ⌘,) apre un pannello da destra (PannelloImpostazioni). A «Schermo intero» solo il
/// video (Viste.swift).
struct ContenutoPrincipale: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    let riprese: Riprese
    @AppStorage(Preferenze.vistaPulita) private var vistaPulita = false
    @AppStorage(Preferenze.riempi) private var riempi = false
    @AppStorage(Preferenze.vista) private var vista = VistaFinestra.essenziale
    /// La finestra è a schermo intero (OsservatoreSchermoIntero): solo il video.
    @State private var schermoIntero = false
    /// A schermo intero: «Esci» visibile, per qualche secondo dopo un movimento del mouse o un tasto.
    @State private var esciVisibile = false
    @State private var scadenzaEsci = ScadenzaEsci()
    /// Il pannello «Impostazioni» e la sua pagina (nil: l'elenco). Si apre dal pulsante in alto e da ⌘,.
    @State private var impostazioniAperte = false
    @State private var paginaImpostazioni: PaginaImpostazioni?
    /// Il puntatore è sopra il video: in vista pulita compare il pulsante per uscire.
    @State private var sopraVideo = false
    /// Il lampo bianco dopo uno scatto (funzione 27).
    @State private var opacitaLampo = 0.0
    /// Il menu «Schermo» della barra sotto il video: le tre viste (schermo intero, Essenziale, Completo).
    @State private var mostraSchermo = false
    /// Il menu «Sfondo» della barra sotto il video: nessuno, sfocatura, sfondi pronti e immagini dal Mac.
    @State private var mostraSfondo = false
    /// Il foglio di «Aggiornamento disponibile», con la versione che mostra (resta anche se intanto cambia).
    @State private var aggiornamentoMostrato: ControlloAggiornamenti.Versione?
    /// Il foglio «Telefoni», dal menu «WebcamLR» e dalla pagina «Telefoni» delle Impostazioni.
    @State private var mostraTelefoni = false
    @Environment(\.openWindow) private var apriFinestra
    /// Riduci movimento (M21): niente scorrimenti, solo dissolvenza o niente.
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    /// L'animazione, o nessuna con Riduci movimento: per i cambi che spostano le cose (viste, pannelli, avvisi).
    private func movimento(_ animazione: Animation) -> Animation? {
        riduciMovimento ? nil : animazione
    }

    /// Lo scorrimento da un bordo, o la sola dissolvenza con Riduci movimento.
    private func entrata(_ bordo: Edge) -> AnyTransition {
        riduciMovimento ? .opacity : .move(edge: bordo).combined(with: .opacity)
    }

    /// Solo il video: vista pulita (⇧⌘P) o schermo intero.
    private var soloVideo: Bool {
        vistaPulita || schermoIntero
    }

    /// Le colonne a sinistra e a destra (vista «Completo»).
    private var completo: Bool {
        vista == .completo && !soloVideo
    }

    /// Vista «Essenziale»: «Impostazioni» in alto e la pillola del telefono sul video.
    private var essenziale: Bool {
        vista == .essenziale && !soloVideo
    }

    var body: some View {
        VStack(spacing: 0) {
            if !soloVideo {
                intestazione
                Divider().overlay(Tema.lineaTenue)
            }
            GeometryReader { spazio in
                // Colonne laterali strette (236 e 262 a 1280 punti, come nel disegno): il video è più largo.
                // Sotto i 1180 punti si stringono ancora: a 960 il video resta largo almeno 400.
                let stretta = spazio.size.width < 1180
                // Il centro resta sempre lo stesso: cambiando vista il video non si ricrea e non si ferma.
                HStack(spacing: 0) {
                    if completo {
                        HStack(spacing: 0) {
                            ColonnaDispositivi(ricevitore: ricevitore, fotocamera: fotocamera)
                                .frame(width: stretta ? 220 : 236)
                                .background(Tema.barraLaterale)
                            Divider().overlay(Tema.lineaTenue)
                        }
                        .transition(entrata(.leading))
                    }
                    centro
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if completo {
                        HStack(spacing: 0) {
                            Divider().overlay(Tema.lineaTenue)
                            ColonnaControlli(ricevitore: ricevitore)
                                .frame(width: stretta ? 248 : 262)
                                .background(Tema.barraLaterale)
                        }
                        .transition(entrata(.trailing))
                    }
                }
                .overlay(alignment: .trailing) { pannelloImpostazioni }
                .clipped()
            }
        }
        .background(soloVideo ? Color.black : Tema.fondo)
        // Il passaggio tra le viste: morbido, senza toccare il video che esce verso le altre app.
        // Con Riduci movimento le colonne compaiono e spariscono di colpo; il pannello si dissolve.
        .animation(movimento(.easeInOut(duration: 0.25)), value: vista)
        .animation(movimento(.easeInOut(duration: 0.25)), value: soloVideo)
        .animation(.easeInOut(duration: 0.22), value: impostazioniAperte)
        .background(OsservatoreSchermoIntero { intero in
            guard intero != schermoIntero else { return }
            schermoIntero = intero
            if intero {
                impostazioniAperte = false
                mostraEsci()
            } else {
                esciVisibile = false
            }
        })
        // Cambiando vista il pannello si chiude: il video si sposta.
        .onChange(of: vista) { impostazioniAperte = false }
        // ⌘, e «Verifica aggiornamenti…» dalla barra dei menu (ComandiMenu.swift), anche a finestra appena aperta.
        .onChange(of: RichiesteFinestra.condivise.impostazioni) { prendiRichieste() }
        .onChange(of: RichiesteFinestra.condivise.aggiornamento) { prendiRichieste() }
        .background(MonitorTastiera(gestisci: tasto))
        .foregroundStyle(Tema.testo)
        .font(.stile(.corpo))
        // Azioni e selezione nell'accento salvia (Specchia e Sfondo accesi, Riempi), non nel colore di sistema.
        .tint(Tema.accento)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            prendiRichieste()
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
        .background(OsservatoreFinestra(suCambio: { visibile in ricevitore.aggiornaVisibilitaPrincipale(visibile) },
                                        suChiusura: finestraChiusa))
        .onDisappear { ricevitore.aggiornaVisibilitaPrincipale(false) }
        .sheet(item: $aggiornamentoMostrato) { versione in
            FoglioAggiornamento(versione: versione, controllo: ControlloAggiornamenti.condiviso)
        }
        .sheet(isPresented: $mostraTelefoni) {
            FoglioTelefoni(ricevitore: ricevitore)
        }
    }

    // MARK: - Tasti (funzione 25)

    /// 1–4 obiettivi nell'ordine del telefono, + e − zoom, F messa a fuoco automatica: scritti anche nel menu Video
    /// (passo 8, M23), ma qui valgono solo fuori dai campi di testo (MonitorTastiera). Vero se il tasto è stato usato.
    private func tasto(_ evento: NSEvent) -> Bool {
        // A schermo intero ogni tasto mostra «Esci» per qualche secondo, poi fa ciò che fa sempre.
        if schermoIntero { mostraEsci() }
        let modificatori = evento.modifierFlags.intersection([.command, .control, .option])
        // ⌘C copia il fotogramma (funzione 26); in un campo di testo non si arriva qui e ⌘C copia il testo.
        if modificatori == .command, evento.charactersIgnoringModifiers?.lowercased() == "c" {
            guard ricevitore.telefono != nil else { return false }
            riprese.copiaFotogramma()
            return true
        }
        // ⌘T, ⇧⌘T, ⌘R e ⇧⌘P sono voci del menu Video (passo 8); ⌘1, ⌘2, ⇧⌘M e ⌥⌘F del menu Vista. Qui passano oltre.
        // Esc chiude il pannello «Impostazioni», esce dallo schermo intero e dalla vista pulita (funzione 29).
        if evento.keyCode == 53, modificatori.isEmpty {
            // Solo se si vede: in vista pulita il pannello è nascosto ed Esc deve uscire dalla vista pulita.
            if impostazioniAperte && !soloVideo {
                impostazioniAperte = false
                return true
            }
            if schermoIntero {
                FinestraPrincipale.alternaSchermoIntero()
                return true
            }
            if vistaPulita {
                vistaPulita = false
                return true
            }
        }
        guard modificatori.isEmpty, ricevitore.telefonoAttivo, let carattere = evento.characters else { return false }
        switch carattere {
        case "1", "2", "3", "4":
            guard let numero = Int(carattere), let obiettivi = ricevitore.capacita?.obiettivi,
                  obiettivi.indices.contains(numero - 1) else { return false }
            let scelto = obiettivi[numero - 1]
            // L'obiettivo di adesso non cambia niente; un altro, mentre registri, chiede prima (punto 7). La domanda
            // dopo il tasto, fuori dalla gestione dell'evento.
            guard scelto != (ricevitore.controlli.obiettivo ?? ricevitore.statoTelefono?.obiettivo) else { return true }
            Task { @MainActor in
                guard ricevitore.confermaSeFerma(.obiettivo) else { return }
                ricevitore.scegliObiettivo(scelto)
            }
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

    /// Al posto della barra del titolo, come la barra degli strumenti unificata di macOS: i tre pulsanti della finestra
    /// restano a sinistra, il fondo è quello della finestra con un divisore sotto. Marchio e stato a sinistra; a destra
    /// «Impostazioni», «Aiuto» e «WebcamLR» (WebcamLR Pro, telefoni, lingua, aggiornamenti, informazioni; niente login:
    /// non c'è un account). Una versione nuova: un punto su «WebcamLR» e la voce nel menu.
    /// Se la finestra è stretta (960 punti) i tre restano solo icona: il nome è nell'aiuto e per VoiceOver. Mai oltre il
    /// bordo della finestra.
    private var intestazione: some View {
        ViewThatFits(in: .horizontal) {
            rigaIntestazione(compatta: false)
            rigaIntestazione(compatta: true)
        }
        // Lo spazio dei tre pulsanti della finestra (non è una spaziatura della griglia).
        .padding(.leading, 84)
        .padding(.trailing, Spazi.medio)
        .frame(height: 52)
        // Il fondo della finestra (gradino 1), come una barra degli strumenti unificata: le colonne sotto sono un gradino
        // più chiare. Niente sfumatura: il logo ce l'ha già.
        .background(Tema.fondo)
    }

    private func rigaIntestazione(compatta: Bool) -> some View {
        HStack(spacing: compatta ? Spazi.stretto : Spazi.piccolo) {
            LogoWebcamLR(lato: 24)
            MarchioWebcamLR(dimensione: 20)
                .lineLimit(1)
                .fixedSize()
            PillolaStato(statoPillola, testo: testoStato)
                .padding(.leading, Spazi.minimo)
            Spacer(minLength: Spazi.stretto)
            pulsanteImpostazioni(compatta: compatta)
            MenuAiuto(compatta: compatta)
            MenuWebcamLR(ricevitore: ricevitore, compatta: compatta,
                         mostraAggiornamento: { aggiornamentoMostrato = $0 },
                         mostraTelefoni: { mostraTelefoni = true })
        }
    }

    /// «Impostazioni», accanto ad «Aiuto» e «WebcamLR» e con lo stesso aspetto, in tutte e due le viste (passo 8: le
    /// impostazioni stanno solo qui). Apre e chiude il pannello che scorre da destra, proprio sotto, come ⌘,.
    /// Acceso nell'accento mentre il pannello è aperto.
    private func pulsanteImpostazioni(compatta: Bool) -> some View {
        Button {
            impostazioniAperte.toggle()
        } label: {
            // Lo stile sull'etichetta, dentro il pulsante: tutto il riquadro risponde al clic.
            Label("Impostazioni", systemImage: "gearshape")
                .labelStyle(StileEtichettaAdattabile(compatta: compatta))
        }
        .buttonStyle(StileSecondario(acceso: impostazioniAperte))
        .help("Fotocamera, effetti, collegamento, telefoni, uscite, avvio, notifiche e sicurezza (⌘,)")
        .accessibilityLabel("Impostazioni")
        .accessibilityAddTraits(impostazioniAperte ? .isSelected : [])
    }

    /// Apre il pannello «Impostazioni» su una pagina (dalla pillola del telefono: «Telefoni»), o sull'elenco.
    private func apriImpostazioni(_ pagina: PaginaImpostazioni?) {
        paginaImpostazioni = pagina
        impostazioniAperte = true
    }

    /// Le richieste dei menu (ComandiMenu.swift): il pannello «Impostazioni», che si vede solo nella finestra (si esce
    /// dalla vista pulita e dallo schermo intero), e il foglio di una versione nuova. Prese una volta, poi azzerate.
    private func prendiRichieste() {
        let richieste = RichiesteFinestra.condivise
        if let pagina = richieste.impostazioni {
            richieste.impostazioni = nil
            vistaPulita = false
            FinestraPrincipale.esciDaSchermoIntero()
            apriImpostazioni(pagina)
        }
        if let versione = richieste.aggiornamento {
            richieste.aggiornamento = nil
            aggiornamentoMostrato = versione
        }
    }

    /// Il pannello «Impostazioni», sopra il video lungo il bordo destro. Dal passo 8 anche nella vista Completo (sopra la
    /// colonna di destra): è l'unico posto delle impostazioni, anche per ⌘,.
    @ViewBuilder private var pannelloImpostazioni: some View {
        if impostazioniAperte && !soloVideo {
            PannelloImpostazioni(ricevitore: ricevitore, fotocamera: fotocamera, pagina: $paginaImpostazioni,
                                 chiudi: { impostazioniAperte = false },
                                 mostraTelefoni: { mostraTelefoni = true })
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Tema.linea)
                        .frame(width: 1)
                        .accessibilityHidden(true)
                }
                .shadow(color: .black.opacity(0.4), radius: 16, x: -4)
                .transition(riduciMovimento ? .opacity : .move(edge: .trailing))
                // Riaperto, riparte dall'elenco (a meno che non lo apra la pillola su una pagina).
                .onDisappear { paginaImpostazioni = nil }
        }
    }

    /// Il telefono nella webcam è in pausa (`stato.pausa`: faccia in giù, dal telefono, sottofondo…), anche se un'app tiene
    /// la webcam: la pillola dice «In pausa» in ambra, come sul telefono, non «In onda». In sottofondo anche se intanto
    /// il collegamento tace (resta la pausa, non «Riconnessione»).
    private var telefonoInPausa: Bool {
        guard ricevitore.statoTelefono?.pausa != nil else { return false }
        switch ricevitore.collegamento {
        case .inOnda, .collegato: return true
        case .riconnessione: return ricevitore.inSottofondo
        case .nessunTelefono: return false
        }
    }

    /// In onda con il nome dell'app, se è una sola e si conosce (M8): «In onda · Zoom», come la riga sotto il video.
    /// In pausa la pillola ambra (`.riconnessione` con il testo «In pausa», come sull'iPhone).
    private var statoPillola: FaseCollegamento {
        if telefonoInPausa { return .riconnessione }
        if case .inOnda = ricevitore.collegamento {
            return .inOnda(app: ricevitore.nomeAppInOnda)
        }
        return ricevitore.collegamento
    }

    /// «In attesa di un telefono» senza telefoni (come nel disegno); collegato, anche la strada: «Collegato · Wi-Fi»
    /// o «Collegato · USB». Negli altri casi la dicitura della pillola.
    private var testoStato: String? {
        if telefonoInPausa { return String(localized: "In pausa") }
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

    /// ⌘W o il pulsante rosso mentre registri o sei in onda: WebcamLR resta aperta, e la prima volta in questo avvio
    /// una notifica lo dice. Non durante l'uscita.
    @MainActor private func finestraChiusa() {
        guard !DelegatoApp.uscitaInCorso else { return }
        let inOnda = ricevitore.webcamInUso && ricevitore.telefonoAttivo
        guard riprese.registra || inOnda else { return }
        Notifiche.condivise.finestraChiusaMaContinua(registrando: riprese.registra)
    }

    // MARK: - Centro

    private var centro: some View {
        VStack(alignment: .center, spacing: Spazi.piccolo) {
            // Il video prende il suo spazio per primo: la barra e la riga delle app sotto usano ciò che resta.
            riquadroVideo
                .layoutPriority(1)
            if !soloVideo {
                barraStudio
                if let avviso = avvisoVersione {
                    // L'avviso delle versioni resta in tutte e due le viste, perché dice cosa fare: un'informazione,
                    // calma, nell'accento. Con «Scarica» quando è il Mac da aggiornare (passo 7, mac.md 16).
                    Avviso(avviso, icona: "arrow.triangle.2.circlepath", tono: .informazione,
                           larghezzaMassima: completo ? CGFloat.infinity : 640, azioni: {
                        if let scarica = scaricaVersione {
                            Button("Scarica", action: scarica)
                                .buttonStyle(StileSecondario())
                                .fixedSize()
                        }
                    })
                }
                if completo {
                    Spacer(minLength: 0)
                }
                // In fondo, una riga sola: «Disponibile per Zoom · Slack · OBS · Meet e tanti altri», o «In uso da Zoom».
                RigaAppWebcam(webcamDisponibile: fotocamera.disponibile, webcamAttiva: fotocamera.stato == .attiva,
                              firme: ricevitore.appWebcam, inUso: ricevitore.webcamInUso)
            }
        }
        .padding(soloVideo ? 0 : Spazi.medio)
    }

    /// Le versioni sul telefono e sul Mac sono diverse in modo che conta (ControlloAggiornamenti).
    private var avvisoVersione: String? {
        guard let telefono = ricevitore.telefono else { return nil }
        return ControlloAggiornamenti.avvisoVersione(telefono)
    }

    /// «Scarica» nell'avviso delle versioni, solo quando è il Mac da aggiornare (passo 7, mac.md 16).
    private var scaricaVersione: (() -> Void)? {
        guard let telefono = ricevitore.telefono, ControlloAggiornamenti.macDaAggiornare(telefono) else { return nil }
        return { ControlloAggiornamenti.condiviso.scaricaUltima() }
    }

    /// Il video con ciò che gli sta sopra. In vista pulita (funzione 29) e a schermo intero occupa tutta la finestra.
    @ViewBuilder private var riquadroVideo: some View {
        if soloVideo {
            videoConSovrapposizioni
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        } else {
            videoConSovrapposizioni
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .overlay(alignment: .top) { barraTally }
                .clipShape(RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous).strokeBorder(Tema.linea))
                .frame(maxWidth: .infinity)
        }
    }

    /// In onda davvero: un'app tiene la webcam e il telefono non è in pausa. In pausa niente corallo (il corallo vale
    /// solo per «in onda» e registrazione): la pillola dice «In pausa» in ambra, come su Windows.
    private var inOnda: Bool {
        if telefonoInPausa { return false }
        if case .inOnda = ricevitore.collegamento { return true }
        return false
    }

    /// Beta 4: la barra tally, 3 punti corallo sul bordo alto del video, quando un'app usa il video (non in pausa).
    /// Prende il posto del bordo corallo: si vede da lontano senza coprire il video. Non in vista pulita né a schermo
    /// intero (lì c'è solo il video). Per VoiceOver lo stato lo dice la pillola.
    @ViewBuilder private var barraTally: some View {
        if inOnda {
            Rectangle()
                .fill(Tema.tally)
                .frame(height: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    /// Passo 7 (mac.md 13): vista Essenziale senza telefoni (nemmeno uno che si ricollega), finestra intera.
    private var primoAvvioAlCentro: Bool {
        essenziale && ricevitore.telefoni.isEmpty
    }

    /// Le etichette sopra il video (qualità, collegamento, CAM 1) ci sono solo con il video che arriva.
    private var mostraChip: Bool {
        !soloVideo && ricevitore.telefono != nil && ricevitore.statistiche.larghezza > 0
    }

    /// La schermata di attesa scelta (WebcamLR Pro: nero o immagine) non scrive il motivo della pausa. Non è osservata:
    /// si rilegge quando cambia la pausa, cioè quando serve.
    private static var attesaSenzaScritte: Bool {
        let stile = AttesaWebcam.condivisa.istantanea().stile
        return stile == .nero || stile == .immagine
    }

    private var videoConSovrapposizioni: some View {
        ZStack(alignment: .topLeading) {
            // Il video com'è arrivato, mai specchiato qui: «Specchia» lo fa il telefono per tutti (1.14).
            // Senza telefono lo `Schermo` mostra la schermata di attesa, la stessa che vedono Zoom e le altre app.
            VistaSchermo(livello: ricevitore.schermo.livello)
            if impostazioniAperte && !soloVideo {
                // Con il pannello «Impostazioni» aperto, un clic sul video lo chiude (i pulsanti sopra il video valgono).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { impostazioniAperte = false }
                    .accessibilityHidden(true)
            }
            if primoAvvioAlCentro {
                // Passo 7 (mac.md 13): senza telefoni, al centro della vista Essenziale il QR grande e i tre passi,
                // non dentro un popover. Con un telefono la vista torna quella di sempre.
                RiquadroCollega(ricevitore: ricevitore, grande: true)
                    .padding(.horizontal, Spazi.largo)
                    // Posizione nel video: lascia libere la riga degli avvisi in alto e «CAM 1» in basso.
                    .padding(.vertical, 52)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            // In alto a sinistra: nella vista Essenziale il telefono; poi qualità e collegamento, ognuno con il suo menu;
            // sotto, gli avvisi. La pausa la mostra la schermata di attesa sopra il video («Webcam in pausa» con il
            // motivo sotto), uguale a quella che vede Zoom; con uno stile d'attesa senza scritte, il motivo sta qui.
            VStack(alignment: .leading, spacing: Spazi.stretto) {
                if (essenziale && !primoAvvioAlCentro) || mostraChip {
                    HStack(spacing: Spazi.stretto) {
                        // Senza telefoni il QR è già al centro: niente pillola con lo stesso QR in un popover.
                        if essenziale && !primoAvvioAlCentro {
                            PillolaTelefono(ricevitore: ricevitore) { apriImpostazioni(.telefoni) }
                        }
                        if mostraChip {
                            MenuQualita(ricevitore: ricevitore)
                            if let via = ricevitore.tipoCollegamento {
                                MenuCollegamento(ricevitore: ricevitore, via: via)
                            }
                        }
                    }
                }
                // In sottofondo il telefono può tacere o cadere: resta la pausa, non «Riconnessione».
                if ricevitore.collegamento == .riconnessione && !ricevitore.inSottofondo {
                    PillolaStato(.riconnessione)
                }
                if !soloVideo, let motivo = ricevitore.statoTelefono?.pausa, Self.attesaSenzaScritte {
                    Label(Ricevitore.testoPausa(motivo), systemImage: "pause.circle")
                        .font(.stile(.corpo))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Spazi.minimo)
                        .chipInformativo()
                }
                avvisoFisso
                if let avviso = ricevitore.avvisoTelefoni {
                    // P21: un terzo telefono non entra; «Lezione» con la frontale. Ambra, come gli altri avvisi; dice cosa fare.
                    Avviso(avviso, icona: "exclamationmark.triangle")
                }
                if let nome = ricevitore.telefonoNonTornato {
                    // Punto 10 (M11): il telefono perso non sparisce in silenzio. Resta finché non lo chiudi o torna.
                    Avviso(String(localized: "\(nome) non è tornato. Riapri WebcamLR sul telefono."), icona: "iphone.slash",
                           chiudi: { ricevitore.chiudiAvvisoNonTornato() }, azioni: {
                        Button("Il telefono non trova il Mac?") { apriDomandaFrequente("non-trova", apri: apriFinestra) }
                            .buttonStyle(StileLink())
                    })
                }
            }
            .padding(Spazi.piccolo)
            // In basso a sinistra: «CAM 1 · nome» (corallo solo in onda); senza telefono, che cosa si sta guardando.
            if mostraChip, let nome = ricevitore.telefono?.nome {
                EtichettaCam(nome: nome, inOnda: inOnda, dueTelefoni: !ricevitore.altri.isEmpty)
                    .padding(Spazi.piccolo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else if !soloVideo && ricevitore.telefono == nil {
                Text("Quello che vedono Zoom e le altre app")
                    .font(.stile(.corpo))
                    .chipInformativo()
                    .padding(Spazi.piccolo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            // Con due telefoni (P21): la CAM 2 dentro il video, in basso a destra, solo quando c'è.
            // In vista pulita e a schermo intero no: lì c'è solo il video.
            if !soloVideo, let altro = ricevitore.altri.first {
                GeometryReader { spazio in
                    RiquadroSecondoTelefono(telefono: altro, larghezza: min(230, spazio.size.width * 0.32)) {
                        // «Usa prospettiva»: mentre registri chiede prima (punto 7).
                        guard ricevitore.confermaSeFerma(.telefono) else { return }
                        ricevitore.scegli(altro)
                    }
                    .padding(Spazi.piccolo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .onAppear { ricevitore.aggiornaVisibilitaMiniatura(true) }
                .onDisappear { ricevitore.aggiornaVisibilitaMiniatura(false) }
            }
            Color.white
                .opacity(opacitaLampo)
                .allowsHitTesting(false)
            if let secondi = riprese.contoAllaRovescia {
                // Conto alla rovescia della foto con il timer (funzione 36): un numero da vedere al volo sopra il
                // video, fuori dalla scala dei testi di proposito.
                Text("\(secondi)")
                    .font(.titolo(120))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .contentTransition(riduciMovimento ? .opacity : .numericText(countsDown: true))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Foto tra \(secondi) secondi")
            }
            if let avviso = riprese.avviso {
                // Le frasi lunghe vanno a capo dentro il video stretto (960 punti): angoli arrotondati, non una capsula.
                // Sopra «CAM 1» e la CAM 2, che stanno in basso. Dopo foto e registrazioni, sotto la frase
                // «Mostra nel Finder» (punto 18): il Finder non si apre più da solo.
                VStack(spacing: Spazi.minimo) {
                    Text(avviso)
                        .foregroundStyle(Tema.testo)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if riprese.fileAvviso != nil {
                        Button("Mostra nel Finder") { riprese.mostraNelFinder() }
                            .buttonStyle(StileLink())
                    }
                }
                .font(.stile(.corpo))
                .accessibilityElement(children: .contain)
                .padding(.horizontal, Spazi.piccolo)
                .padding(.vertical, Spazi.stretto)
                .background(Tema.pannelloChiaro.opacity(Veli.forte), in: RoundedRectangle(cornerRadius: Raggi.pannello))
                .padding(.horizontal, Spazi.medio)
                // Sopra «CAM 1» (48) o sopra la CAM 2 (150): posizioni nel video, non spaziature.
                .padding(.bottom, ricevitore.altri.isEmpty ? 48 : 150)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
            pulsanteEsciVistaPulita
            pulsanteEsciSchermoIntero
        }
        .animation(movimento(.default), value: riprese.avviso)
        .animation(movimento(.default), value: ricevitore.avvisoTelefoni)
        .animation(movimento(.default), value: ricevitore.telefonoNonTornato)
        .animation(movimento(.default), value: primoAvvioAlCentro)
        .animation(.easeOut(duration: 0.15), value: sopraVideo)
        .animation(.easeOut(duration: 0.2), value: esciVisibile)
        .animation(.default, value: riprese.contoAllaRovescia)
        .onChange(of: riprese.lampo) {
            // Con Riduci movimento niente lampo: resta il suono dello scatto.
            guard !riduciMovimento else { return }
            opacitaLampo = 0.85
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.easeOut(duration: 0.35)) { opacitaLampo = 0 }
            }
        }
        .onHover { sopraVideo = $0 }
        // Clic destro (M19): Foto, Copia il fotogramma, Registra, Vista pulita, Riempi l'inquadratura.
        .contextMenu { VociContestualiVideo(ricevitore: ricevitore, riprese: riprese) }
        // A schermo intero ogni movimento del mouse mostra «Esci» per qualche secondo.
        .onContinuousHover { fase in
            if schermoIntero, case .active(_) = fase { mostraEsci() }
        }
    }

    /// Gli avvisi di una condizione che dura (passo 6): restano sopra il video finché la causa c'è, uno alla volta,
    /// il più urgente: spazio quasi finito mentre registri (funzione 37), telefono caldo, batteria bassa (funzione 33).
    /// Ognuno finisce nel registro quando compare (Riprese e Ricevitore).
    @ViewBuilder private var avvisoFisso: some View {
        let stato = ricevitore.telefono != nil ? ricevitore.statoTelefono : nil
        if let testo = riprese.testoSpazio {
            Avviso(String(localized: "\(testo). Ferma la registrazione o libera spazio sul disco."),
                   icona: "externaldrive.badge.exclamationmark")
        } else if let stato, let testo = Ricevitore.testoCalore(stato.temperatura) {
            Avviso(testo, icona: "thermometer")
        } else if let stato, let testo = Ricevitore.testoBatteria(stato) {
            Avviso(testo, icona: "battery.25")
        }
    }

    /// A schermo intero, in alto al centro: «Esci», solo per qualche secondo dopo un movimento del mouse o un tasto.
    /// Nascosto resta nella finestra (trasparente e senza clic), così VoiceOver lo trova sempre.
    @ViewBuilder private var pulsanteEsciSchermoIntero: some View {
        if schermoIntero {
            Button {
                FinestraPrincipale.alternaSchermoIntero()
            } label: {
                Label("Esci", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.stile(.corpo, .corpoEvidente))
                    .padding(.horizontal, Spazi.piccolo)
                    .padding(.vertical, Spazi.stretto)
                    .background(Tema.pannelloChiaro.opacity(Veli.forte), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tema.testo)
            .help("Esci dallo schermo intero (Esc)")
            .accessibilityLabel("Esci dallo schermo intero")
            .opacity(esciVisibile ? 1 : 0)
            .allowsHitTesting(esciVisibile)
            .padding(Spazi.medio)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Mostra «Esci» e sposta in avanti la sua scadenza: sparisce 3 secondi dopo l'ultimo movimento o tasto.
    /// Un solo compito alla volta aspetta la scadenza, che il mouse sposta senza ridisegnare la finestra.
    private func mostraEsci() {
        let scadenza = scadenzaEsci
        scadenza.data = Date().addingTimeInterval(3)
        guard !esciVisibile else { return }
        esciVisibile = true
        Task { @MainActor in
            while scadenza.data.timeIntervalSinceNow > 0 {
                try? await Task.sleep(for: .seconds(max(0.1, scadenza.data.timeIntervalSinceNow)))
            }
            esciVisibile = false
        }
    }

    /// Esce dalla vista pulita: compare solo con il puntatore sopra il video.
    @ViewBuilder private var pulsanteEsciVistaPulita: some View {
        if vistaPulita && !schermoIntero && sopraVideo {
            Button {
                vistaPulita = false
            } label: {
                Label("Esci dalla vista pulita", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.stile(.corpo))
                    .padding(.horizontal, Spazi.stretto)
                    .padding(.vertical, Spazi.minimo)
                    .background(Tema.pannelloChiaro.opacity(Veli.forte), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tema.testo)
            .help("Esci dalla vista pulita (Esc)")
            .padding(Spazi.piccolo)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(.opacity)
        }
    }

    // MARK: - Barra sotto il video

    /// Sotto il video, come nel disegno: Specchia · Sfondo · Foto · Registra | Schermo, con icona e nome.
    /// Più stretta quando la finestra è piccola; al limite solo le icone (il nome resta nell'aiuto e per VoiceOver).
    /// «Schermo» apre schermo intero, finestra mini e riempi l'inquadratura; «Scollega» è nella colonna di destra.
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

    /// «Specchia» e «Sfondo» (1.14): un clic; accesi con il fondo accento tenue, il bordo accento e la riga «Acceso».
    /// Valgono per il video inviato, quello che vedono anche le app e il telefono: il telefono li applica e il pulsante
    /// segue il suo `stato`.
    /// Senza telefono restano grigi; con un telefono che non li sa fare (`capacita`) non ci sono. Con la fotocamera
    /// posteriore grigi anche loro, con «Solo con la fotocamera frontale», e il menu di «Sfondo» non si apre.
    @ViewBuilder private func pulsantiVideo(larghezza: CGFloat, soloIcona: Bool) -> some View {
        let inAttesa = !ricevitore.telefonoAttivo || ricevitore.capacita == nil
        let posteriore = !inAttesa && ricevitore.soloFrontaleBloccati
        if inAttesa || ricevitore.specchioDisponibile {
            let acceso = !inAttesa && !posteriore && ricevitore.specchiato
            Button {
                ricevitore.alternaSpecchio()
            } label: {
                Label("Specchia", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .buttonStyle(ComandoRegia(acceso: acceso, larghezza: larghezza, soloIcona: soloIcona))
            .help(acceso ? "Specchiato: le app di chiamata, il telefono e questa finestra vedono il video girato. Clic per raddrizzarlo"
                  : "Specchia il video da sinistra a destra: per le app di chiamata, il telefono e questa finestra")
            .accessibilityLabel("Specchia")
            .accessibilityAddTraits(acceso ? .isSelected : [])
            .richiedeTelefono(!inAttesa)
            .soloFrontale(posteriore)
        }
        if inAttesa || ricevitore.sfondoDisponibile {
            // La sfocatura del telefono (Effetti video di Apple) accende il pulsante; un clic apre il menu, perché si
            // spegne solo sul telefono.
            let delTelefono = !inAttesa && !posteriore && ricevitore.sfocaturaDelTelefono
            let acceso = !inAttesa && !posteriore && (ricevitore.sfondoAcceso || delTelefono)
            Button {
                // ⌥ clic: la diagnosi nascosta della maschera (lo sfondo resta com'è).
                if NSEvent.modifierFlags.contains(.option) {
                    ricevitore.alternaMascheraVisibile()
                } else if delTelefono {
                    mostraSfondo = true
                } else {
                    ricevitore.alternaSfondo()
                }
            } label: {
                Label("Sfondo", systemImage: "person.and.background.dotted")
            }
            .buttonStyle(ComandoRegia(acceso: acceso, larghezza: larghezza, soloIcona: soloIcona))
            .help(delTelefono ? "Sfocatura del telefono: si regola sul telefono, negli Effetti video di Apple. Dalla freccina: uno sfondo"
                  : acceso ? "Sfondo acceso: \(ricevitore.descrizioneSfondo). Clic per toglierlo; dalla freccina: sfocatura o sfondi"
                  : "Sfoca o cambia lo sfondo dietro di te. Clic: l'ultima scelta; dalla freccina: Poco, Medio, Tanto o uno sfondo")
            .accessibilityLabel("Sfondo")
            .accessibilityValue(ricevitore.descrizioneSfondo)
            .accessibilityAddTraits(acceso ? .isSelected : [])
            .contextMenu {
                if !posteriore {
                    VociMenuSfondo(ricevitore: ricevitore) {
                        apriFinestraApp(.pro, apri: apriFinestra)
                    }
                }
            }
            .overlay(alignment: .topTrailing) { freccinaSfondo(acceso: acceso) }
            .richiedeTelefono(!inAttesa)
            .soloFrontale(posteriore)
            // Passando alla posteriore con il menu aperto: si chiude.
            .onChange(of: posteriore) { _, bloccato in
                if bloccato { mostraSfondo = false }
            }
        }
    }

    /// La freccina nell'angolo di «Sfondo»: apre verso l'alto, come «Schermo», Nessuno · Sfocatura · Sfondi ▸.
    /// L'area di clic è 24×24 (WCAG 2.5.8), nell'angolo del comando.
    private func freccinaSfondo(acceso: Bool) -> some View {
        Button {
            mostraSfondo.toggle()
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(acceso ? Tema.accentoChiaro : Tema.testoSecondario)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(Spazi.minimo / 2)
        .help("Nessuno, sfocatura (Poco, Medio, Tanto) o uno sfondo")
        .accessibilityLabel("Scegli lo sfondo")
        .popover(isPresented: $mostraSfondo, arrowEdge: .top) {
            PannelloSfondo(ricevitore: ricevitore) { mostraSfondo = false }
        }
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
                // La X resta solo per chiudere: annullare il timer è tornare indietro.
                Label("Annulla", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(ComandoRegia(larghezza: larghezza, soloIcona: soloIcona))
            .help("Annulla il timer (⇧⌘T)")
            .accessibilityLabel("Annulla il timer")
        } else {
            Button {
                riprese.scattaFoto()
            } label: {
                Label("Foto", systemImage: "camera")
            }
            .buttonStyle(ComandoRegia(larghezza: larghezza, soloIcona: soloIcona))
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

    /// Registra (funzione 35). Da fermo neutro come gli altri comandi. Mentre registra (beta 4): il nome resta,
    /// l'icona diventa «ferma» in corallo e la riga di stato dice «● 12:31»; la dimensione del file (funzione 37)
    /// nell'aiuto e per VoiceOver.
    @ViewBuilder private func pulsanteRegistra(larghezza: CGFloat, soloIcona: Bool) -> some View {
        if let inizio = riprese.inizioRegistrazione {
            // Letta qui, sulla coda principale: la chiusura del TimelineView resta senza stato di Riprese.
            let dimensione = Riprese.testoByte(riprese.dimensioneRegistrazione)
            TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                Button {
                    riprese.fermaRegistrazione()
                } label: {
                    Label("Registra", systemImage: "stop.circle.fill")
                }
                .buttonStyle(ComandoRegia(larghezza: larghezza, soloIcona: soloIcona,
                                          registrazione: String(format: "%02d:%02d", secondi / 60, secondi % 60)))
            }
            .help("Ferma la registrazione e la salva in Filmati › WebcamLR (⌘R). Finora: \(dimensione)")
            .accessibilityLabel("Ferma la registrazione")
            .accessibilityValue(dimensione)
        } else {
            Button {
                riprese.avviaRegistrazione()
            } label: {
                Label("Registra", systemImage: "record.circle")
            }
            .buttonStyle(ComandoRegia(larghezza: larghezza, soloIcona: soloIcona))
            .help("Registra il video del telefono, senza audio, in Filmati › WebcamLR (⌘R)")
            .accessibilityLabel("Registra")
            .richiedePro(ricevitore.bloccoPro, segno: false)
            .overlay(alignment: .topTrailing) { segnoProAngolo }
            .richiedeTelefono(ricevitore.telefonoAttivo)
        }
    }

    /// «Schermo»: le tre viste in un pannello che si apre verso l'alto (Schermo intero · Essenziale · Completo).
    /// Le scorciatoie (⌃⌘F, ⌘1, ⌘2 e ⇧⌘P per la vista pulita) restano attive, ma non si scrivono nel pannello.
    /// Finestra mini e Riempi l'inquadratura sono nel menu Vista e in Impostazioni › Schermo.
    private func pulsanteSchermo(larghezza: CGFloat, soloIcona: Bool) -> some View {
        Button {
            mostraSchermo.toggle()
        } label: {
            // Un'icona sua: le frecce sono di «Schermo intero», una delle tre scelte dentro.
            Label("Schermo", systemImage: "display")
        }
        .buttonStyle(ComandoRegia(larghezza: larghezza, soloIcona: soloIcona))
        .help("Schermo intero, vista Essenziale o vista Completo")
        .accessibilityLabel("Schermo")
        .accessibilityHint("Schermo intero, vista Essenziale o vista Completo")
        .popover(isPresented: $mostraSchermo, arrowEdge: .top) {
            pannelloSchermo
        }
    }

    /// Le tre viste, icona sopra e nome sotto come i pulsanti della barra; quella attuale accesa (accento tenue, bordo
    /// accento e riga «Acceso»).
    private var pannelloSchermo: some View {
        HStack(spacing: Spazi.stretto) {
            Button {
                mostraSchermo = false
                // La finestra principale, non il pannello appena chiuso. ⌃⌘F è la voce di sistema del menu Vista.
                FinestraPrincipale.alternaSchermoIntero()
            } label: {
                Label("Schermo intero", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(ComandoRegia(acceso: schermoIntero, larghezza: 118))
            .help("Solo il video, su tutto lo schermo. Esc per uscire")
            .accessibilityAddTraits(schermoIntero ? .isSelected : [])
            pulsanteVista(.essenziale)
            pulsanteVista(.completo)
        }
        .padding(Spazi.stretto)
    }

    @ViewBuilder private func pulsanteVista(_ voce: VistaFinestra) -> some View {
        let acceso = !schermoIntero && vista == voce
        Button {
            mostraSchermo = false
            scegliVista(voce)
        } label: {
            switch voce {
            case .essenziale: Label("Essenziale", systemImage: "rectangle")
            case .completo: Label("Completo", systemImage: "rectangle.split.3x1")
            }
        }
        .buttonStyle(ComandoRegia(acceso: acceso, larghezza: 118))
        .help(voce == .essenziale ? "Il video, la barra e le Impostazioni a destra"
                                  : "Il video con telefoni, collegamento e comandi nelle colonne ai lati")
        .accessibilityAddTraits(acceso ? .isSelected : [])
    }

    /// Cambia vista (si ricorda per la prossima volta); da schermo intero torna anche nella finestra.
    private func scegliVista(_ voce: VistaFinestra) {
        vista = voce
        FinestraPrincipale.esciDaSchermoIntero()
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
        Grid(alignment: .leading, horizontalSpacing: Spazi.medio, verticalSpacing: Spazi.stretto) {
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
                    .font(.stile(.numeri))
                    .foregroundStyle(coloreLatenza)
            }
            if statistiche.anteprimaMs != nil || statistiche.webcamMs != nil {
                // Le tappe da vetro a uscita (Protocollo.md, «Latenza»): la latenza qui sopra è l'ultima che c'è.
                let arrivo = RitardoVetro.testo(statistiche.arrivoMs)
                let finestra = RitardoVetro.testo(statistiche.anteprimaMs)
                let webcam = RitardoVetro.testo(statistiche.webcamMs)
                if let effettiMs = statistiche.effettiMs {
                    // Il motore effetti del Mac: il suo tempo è già dentro finestra e webcam.
                    riga("Tappe", String(localized: "arrivo \(arrivo) · effetti \(effettiMs) ms · finestra \(finestra) · webcam \(webcam)"))
                } else {
                    riga("Tappe", String(localized: "arrivo \(arrivo) · finestra \(finestra) · webcam \(webcam)"))
                }
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
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
                .gridCellColumns(2)
        }
        .padding(Spazi.medio)
        .frame(width: 300)
    }

    private func riga(_ nome: LocalizedStringKey, _ valore: String) -> some View {
        GridRow {
            Text(nome).foregroundStyle(Tema.testoSecondario)
            Text(valore).font(.stile(.numeri))
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
        return latenza < 100 ? Tema.accentoChiaro : Tema.ambra
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
/// `suChiusura`: la finestra si chiude (⌘W o il pulsante rosso), non quando si riduce a icona.
struct OsservatoreFinestra: NSViewRepresentable {
    let suCambio: @MainActor (Bool) -> Void
    var suChiusura: (@MainActor () -> Void)? = nil

    final class Vista: NSView {
        var suCambio: (@MainActor (Bool) -> Void)?
        var suChiusura: (@MainActor () -> Void)?
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
                    MainActor.assumeIsolated {
                        self?.ricalcola(chiusa: chiusa)
                        if chiusa { self?.suChiusura?() }
                    }
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
        vista.suChiusura = suChiusura
        return vista
    }

    func updateNSView(_ vista: Vista, context: Context) {
        vista.suCambio = suCambio
        vista.suChiusura = suChiusura
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
                .spento()
                // Sopra il comando spento: il clic arriva qui e apre la nota.
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { mostraNota = true }
                }
                .popover(isPresented: $mostraNota, arrowEdge: .bottom) {
                    Label("Collega un telefono per usarlo.", systemImage: "iphone")
                        .font(.stile(.corpo))
                        .padding(Spazi.piccolo)
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

    /// «Specchia» e «Sfondo» con la fotocamera posteriore: grigi, con «Solo con la fotocamera frontale» nell'aiuto e al clic.
    func soloFrontale(_ bloccato: Bool) -> some View {
        modifier(SoloFrontale(bloccato: bloccato))
    }
}

/// Come `RichiedeTelefono`, ma con la fotocamera posteriore: il telefono non specchia e non cambia lo sfondo finché
/// non torna alla frontale (`Ricevitore.soloFrontaleBloccati`).
private struct SoloFrontale: ViewModifier {
    let bloccato: Bool
    @State private var mostraNota = false

    func body(content: Content) -> some View {
        corpo(content)
            .onChange(of: bloccato) { mostraNota = false }
    }

    @ViewBuilder private func corpo(_ content: Content) -> some View {
        if bloccato {
            content
                .spento()
                // Sopra il pulsante spento: l'aiuto al passaggio del puntatore e la nota al clic.
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { mostraNota = true }
                        .help("Solo con la fotocamera frontale")
                }
                .popover(isPresented: $mostraNota, arrowEdge: .bottom) {
                    Label("Solo con la fotocamera frontale", systemImage: "camera.rotate")
                        .font(.stile(.corpo))
                        .padding(Spazi.piccolo)
                }
                .accessibilityHint("Solo con la fotocamera frontale")
        } else {
            content
        }
    }
}

/// Il registro del collegamento (1.5): ora ed evento, il più recente in basso, con «Copia» per «Segnala un bug».
struct VistaRegistro: View {
    let voci: [Ricevitore.VoceRegistro]
    /// Il titolo: nel popover sì; nella pagina delle Impostazioni il titolo è già in alto.
    var conTitolo = true
    /// La misura del popover; nil nella pagina delle Impostazioni, dove prende lo spazio che c'è.
    var dimensione: CGSize? = CGSize(width: 420, height: 360)
    /// Per due secondi dopo «Copia» il pulsante dice «Copiato»: prima il clic non dava nessun segno.
    @State private var copiato = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
            HStack {
                if conTitolo {
                    Text("Registro del collegamento")
                        .font(.stile(.titolo))
                }
                Spacer()
                Button(copiato ? "Copiato" : "Copia") { copia() }
                    .buttonStyle(StileSecondario())
                    .disabled(voci.isEmpty)
            }
            if voci.isEmpty {
                Text("Ancora nessun evento.")
                    .foregroundStyle(Tema.testoSecondario)
            } else {
                ScrollViewReader { lettore in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spazi.minimo) {
                            ForEach(voci) { voce in
                                HStack(alignment: .firstTextBaseline, spacing: Spazi.stretto) {
                                    Text(Self.ora(voce.ora))
                                        .font(.stile(.numeri))
                                        .foregroundStyle(Tema.testoSecondario)
                                    Text(Self.testo(voce))
                                        .font(.stile(.corpo))
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
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
        }
        .padding(dimensione == nil ? 0 : Spazi.medio)
        .frame(width: dimensione?.width, height: dimensione?.height)
        .foregroundStyle(Tema.testo)
        .tint(Tema.accento)
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
        let testo = voci.map(\.riga).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testo, forType: .string)
        copiato = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copiato = false
        }
    }
}
