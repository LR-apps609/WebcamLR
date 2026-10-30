import Network
import Stile
import SwiftUI
import UIKit
import WebcamLRProtocollo

/// Ricollegamento automatico (round 2, novità 2): all'avvio, se la ricerca trova l'ultimo computer usato,
/// ci si collega da soli dopo un breve conto alla rovescia. Una volta sola per avvio dell'app.
/// 1.11: durante il conto alla rovescia collegamento sicuro e fotocamera partono già: alla fine il video è pronto.
enum Ricollegamento {
    /// 1.11: i secondi del conto alla rovescia (erano 3): basta per toccare «Annulla», il QR code o l'indirizzo.
    static let secondi = 2
    /// Il nome Bonjour (o del QR code) dell'ultimo computer a cui ci si è collegati.
    static let chiaveUltimoComputer = "ultimoComputer"
    /// Già tentato, oppure l'utente ha già scelto o scollegato da sé: niente più fino al prossimo avvio.
    static var fatto = false
}

/// Schermata «Scegli il computer» (bozza grafica, iPhone 1).
struct SchermataConnessione: View {
    @State private var cerca = CercaComputer()
    /// Resta valorizzata anche durante l'animazione di ritorno, così «In onda» non diventa vuota.
    @State private var sessione: SessioneTelefono? = nil
    @State private var inOnda = false
    @State private var mostraLettore = false
    /// 1.10: la sessione dal QR code è già partita alla lettura; «In onda» si apre quando il foglio è chiuso.
    @State private var daMostrare = false
    @State private var mostraIndirizzo = false
    @State private var indirizzoScritto = ""
    /// A7 (passo 9): l'ultimo indirizzo valido scritto a mano, riproposto la volta dopo (come su Android).
    @AppStorage("ultimoIndirizzo") private var ultimoIndirizzo = ""
    @State private var indirizzoNonValido = false
    /// Dopo 15 secondi senza computer compare «Non trovo nessun computer» con le cose da controllare (funzione 34).
    @State private var mostraAiuto = false
    /// «Usa il cavo USB»: la scheda del cavo resta aperta.
    @State private var mostraCavo = false
    /// Il computer a cui ci si sta per ricollegare da soli, con i secondi che mancano.
    @State private var ricollegaA: ComputerTrovato? = nil
    @State private var secondiAlRicollegamento = Ricollegamento.secondi
    @State private var compitoRicollegamento: Task<Void, Never>? = nil
    /// 1.11: la sessione già avviata durante il conto alla rovescia, che aspetta solo la fine per mandare il `ciao`.
    /// Se il conto si annulla, si chiude.
    @State private var preparata: SessioneTelefono? = nil
    /// Sezione App (0.12): guida, segnalazioni, computer conosciuti e informazioni.
    @State private var mostraSezioneApp = false
    /// Le Impostazioni del telefono, in un foglio con «Fine» come da «In onda» (prima prova, 27 ottobre).
    @State private var mostraImpostazioni = false
    /// Bug 1/11: WebcamLR Pro dalla voce in alto, visibile senza passare dall'icona delle informazioni.
    @State private var mostraPro = false
    /// Una risposta delle domande frequenti aperta da una diagnosi (1.4).
    @State private var domandaAperta: DomandaDaAprire? = nil
    /// La presentazione si vede solo alla prima apertura (round 2, novità 16; ora `PresentazioneVista`).
    @AppStorage("benvenutoVisto") private var benvenutoVisto = false
    /// Con `-presentazione` o `-presentazioneAutoplay` la presentazione si vede anche se è già stata vista.
    @State private var presentazioneForzata = ArgomentiPresentazione.forzata
    /// Il Portachiavi non ha salvato l'identità dell'iPhone: lo si dice una volta per avvio.
    @State private var mostraAvvisoIdentita = false
    @State private var identitaControllata = false
    /// 1.6: l'ascolto sul cavo USB (127.0.0.1:52741), acceso quando non c'è una sessione
    /// (1.9: e durante una sessione Wi-Fi, per passare al cavo).
    @State private var ascolto = AscoltoCavo()
    /// Questa schermata è in cima (non coperta da «In onda» o dalle Impostazioni).
    @State private var visibile = false
    /// Dopo «Scollega» su una sessione via cavo l'ascolto resta spento, altrimenti il computer
    /// ricollegherebbe subito: riparte con «Collega via cavo» o tornando nell'app.
    @State private var cavoInPausa = false
    /// L'ultima sessione via cavo si è fermata per un computer da ricollegare (codice di sicurezza diverso):
    /// la pausa resta anche uscendo dall'app, altrimenti a ogni ritorno il computer (che ritenta ogni 2 secondi)
    /// riaprirebbe «In onda» con lo stesso errore. Riparte solo con «Collega via cavo».
    @State private var cavoRifiutato = false
    /// Primo piano o sottofondo dell'app (non la `Fase` della schermata, più sotto).
    @Environment(\.scenePhase) private var faseApp

    private var mostraBenvenuto: Binding<Bool> {
        Binding(get: { !benvenutoVisto || presentazioneForzata },
                set: { mostra in
                    if !mostra {
                        benvenutoVisto = true
                        presentazioneForzata = false
                    }
                })
    }

    var body: some View {
        // Interfaccia finale (TelefonoSenzaComputer): A «Cerco il tuo computer…», B «Computer trovati», C dopo
        // 15 secondi senza computer (o subito con una causa precisa) «Non trovo nessun computer». I pulsanti in fondo.
        GeometryReader { area in
            ScrollView {
                VStack(alignment: .leading, spacing: Spazi.medio) {
                    intestazione
                    if let computer = ricollegaA {
                        bannerRicollegamento(computer)
                    }
                    switch fase {
                    case .cerca: contenutoCerca
                    case .trovati: contenutoTrovati
                    case .aiuto: contenutoAiuto
                    }
                    // 1.6: il cavo USB, aperto da «Usa il cavo USB» o rimasto in pausa dopo «Scollega».
                    if mostraCavo || cavoInPausa {
                        schedaUSB
                            .transition(.opacity)
                    }
                    Spacer(minLength: Spazi.largo)
                    switch fase {
                    case .cerca: pulsantiCerca
                    case .trovati: pulsantiTrovati
                    case .aiuto: pulsantiAiuto
                    }
                }
                .padding(.horizontal, Spazi.largo)
                .padding(.top, Spazi.piccolo)
                .padding(.bottom, Spazi.medio)
                .frame(minHeight: area.size.height, alignment: .top)
                .animation(.easeInOut(duration: 0.25), value: fase)
            }
        }
        .background { sfondo.ignoresSafeArea() }
        .foregroundStyle(Tema.testo)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $inOnda) {
            if let sessione {
                SchermataInOnda(sessione: sessione)
            }
        }
        .sheet(isPresented: $mostraLettore, onDismiss: {
            // 1.10: il collegamento è partito alla lettura; «In onda» si apre quando il foglio è chiuso del tutto,
            // così la navigazione non si incrocia.
            if daMostrare {
                daMostrare = false
                if sessione != nil { inOnda = true }
            }
        }) {
            FoglioLettoreQR { associazione in
                collegaDalQR(associazione)
            }
        }
        .sheet(isPresented: $mostraSezioneApp) {
            SchermataApp(ultimaLatenzaMs: sessione?.ultimaLatenzaMs)
        }
        .sheet(isPresented: $mostraImpostazioni) {
            NavigationStack {
                SchermataImpostazioni(ultimaLatenzaMs: sessione?.ultimaLatenzaMs)
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
        .sheet(isPresented: $mostraPro) {
            FoglioPro()
        }
        .sheet(item: $domandaAperta) { domanda in
            FoglioDomande(aperta: domanda.id)
        }
        .alert("Indirizzo del computer", isPresented: $mostraIndirizzo) {
            TextField("192.168.1.20", text: $indirizzoScritto)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Collega") {
                if let associazione = Associazione(indirizzoScritto: indirizzoScritto) {
                    ultimoIndirizzo = indirizzoScritto.trimmingCharacters(in: .whitespacesAndNewlines)
                    collega(associazione)
                } else {
                    // Un secondo avviso va aperto quando il primo è chiuso del tutto.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { indirizzoNonValido = true }
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Lo trovi nella finestra di WebcamLR sul computer, sotto il QR code.")
        }
        .alert("Indirizzo non valido", isPresented: $indirizzoNonValido) {
            // Come sopra: il primo avviso si riapre quando questo è chiuso del tutto, altrimenti non compare.
            Button("Riprova") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { mostraIndirizzo = true } }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Scrivi quattro numeri separati da punti, per esempio 192.168.1.20.")
        }
        .alert("L'iPhone non riesce a ricordare questo collegamento", isPresented: $mostraAvvisoIdentita) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Il Portachiavi dell'iPhone non ha salvato i dati di sicurezza di WebcamLR: il collegamento funziona, ma al prossimo avvio il computer chiederà di nuovo il codice di conferma. Sblocca l'iPhone e riapri WebcamLR; se succede ancora, riavvia l'iPhone o usa «Segnala un bug».")
        }
        .fullScreenCover(isPresented: mostraBenvenuto) {
            PresentazioneVista {
                benvenutoVisto = true
                presentazioneForzata = false
            }
        }
        .task(id: benvenutoVisto) {
            // La lettura del Portachiavi è già partita all'avvio: qui si aspetta il risultato fuori dal thread principale.
            guard benvenutoVisto, !identitaControllata else { return }
            identitaControllata = true
            let temporanea = await Task.detached(priority: .userInitiated) { IdentitaTelefono.soloPerQuestaVolta }.value
            if temporanea { mostraAvvisoIdentita = true }
        }
        .onChange(of: qualcosaInPrimoPiano) { _, aperto in
            // Un foglio chiuso: se l'ultimo computer era comparso nel frattempo, il conto alla rovescia parte ora.
            if !aperto { controllaRicollegamento(cerca.computer) }
        }
        .task(id: benvenutoVisto) {
            guard benvenutoVisto else { return }
            try? await Task.sleep(for: .seconds(15))
            if Task.isCancelled { return }
            withAnimation { mostraAiuto = true }
        }
        // La ricerca fa chiedere a iOS il permesso «Rete locale»: parte solo dopo il benvenuto, che lo spiega.
        .onAppear {
            // Lo stato della rete non chiede permessi: serve alla diagnosi (1.3).
            StatoRete.condiviso.avvia()
            if benvenutoVisto {
                cerca.avvia()
                // 1.10: la fotocamera del lettore QR si prepara già (spenta), se il permesso c'è.
                FotocameraQR.condivisa.prepara()
            }
        }
        .onChange(of: benvenutoVisto) { _, visto in
            if visto {
                cerca.avvia()
                FotocameraQR.condivisa.prepara()
            }
        }
        .onDisappear {
            visibile = false
            cerca.ferma()
            annullaRicollegamento()
        }
        // 1.6: cavo USB. L'ascolto segue lo stato della schermata; la connessione che arriva apre «In onda».
        .onAppear {
            visibile = true
            ascolto.suConnessione = { connessione in arrivoDalCavo(connessione) }
        }
        .onChange(of: deveAscoltare, initial: true) { _, attivo in
            ascolto.imposta(attivo: attivo)
        }
        .onChange(of: inOnda) { _, aperta in
            if !aperta { pausaDopoScollega() }
        }
        .onChange(of: faseApp) { _, nuova in
            // Uscendo dall'app la pausa finisce: al ritorno il cavo funziona di nuovo da solo.
            if nuova == .background && !cavoRifiutato { cavoInPausa = false }
        }
        .onChange(of: cerca.computer) { _, trovati in
            controllaRicollegamento(trovati)
        }
    }

    private func bannerRicollegamento(_ computer: ComputerTrovato) -> some View {
        HStack(spacing: Spazi.piccolo) {
            ProgressView()
                .tint(Tema.accento)
            Text("Mi ricollego a \(computer.nome) tra \(secondiAlRicollegamento)…")
                .font(.stile(.corpo, .corpoForte))
            Spacer(minLength: Spazi.stretto)
            Button("Annulla") { annullaRicollegamento() }
                .buttonStyle(StileSecondario())
        }
        .padding(.horizontal, Spazi.medio)
        .padding(.vertical, Spazi.stretto)
        .background(Tema.accentoTenue, in: RoundedRectangle(cornerRadius: Raggi.pannello))
        .overlay(RoundedRectangle(cornerRadius: Raggi.pannello).stroke(Tema.accento))
        .transition(.opacity)
    }

    /// 1.12: l'ultimo computer, conosciuto, non si vede ancora: quando compare parte il ricollegamento da solo.
    private var computerAtteso: String? {
        guard benvenutoVisto, !Ricollegamento.fatto, ricollegaA == nil,
              let ultimo = UserDefaults.standard.string(forKey: Ricollegamento.chiaveUltimoComputer),
              ComputerConosciuti.impronta(di: ultimo) != nil,
              !cerca.computer.contains(where: { $0.nome == ultimo }) else { return nil }
        return ultimo
    }

    /// Un foglio o un avviso è aperto: «In onda» si aprirebbe sotto, senza che lo si veda.
    private var qualcosaInPrimoPiano: Bool {
        mostraLettore || mostraSezioneApp || mostraImpostazioni || mostraPro || mostraIndirizzo || indirizzoNonValido || mostraAvvisoIdentita
            || daMostrare || domandaAperta != nil || !benvenutoVisto || presentazioneForzata
    }

    /// 1.6: senza sessione si ascolta quando la schermata è in cima e libera; durante una sessione via cavo
    /// solo mentre aspetta che il computer riapra la connessione.
    /// 1.9: durante una sessione Wi-Fi si ascolta anche (pure mentre ci si ricollega): collegando il cavo allo stesso
    /// computer si passa al cavo. Non dopo «Scollega» su una sessione via cavo né dopo un computer rifiutato.
    private var deveAscoltare: Bool {
        if inOnda {
            guard let attuale = sessione else { return false }
            if attuale.viaCavo { return attuale.attendeCavo }
            return attuale.accettaCavo && !cavoInPausa && !cavoRifiutato
        }
        return benvenutoVisto && visibile && !cavoInPausa && !qualcosaInPrimoPiano
    }

    private func arrivoDalCavo(_ connessione: NWConnection) {
        if inOnda {
            if let attuale = sessione, attuale.accogli(connessione) { return }
            connessione.cancel()
            return
        }
        guard visibile, !qualcosaInPrimoPiano else {
            connessione.cancel()
            return
        }
        // Collegare il cavo e aprire le app basta: «In onda» si apre da sola.
        apri(SessioneTelefono(cavo: connessione), origine: .cavo)
    }

    /// Uscendo da una sessione via cavo («Scollega» o «Torna ai computer») l'ascolto si ferma: il computer
    /// ritenta ogni 2 secondi e si ricollegherebbe da solo. Riparte con «Collega via cavo» o tornando nell'app.
    private func pausaDopoScollega() {
        guard let chiusa = sessione, chiusa.viaCavo else { return }
        cavoInPausa = true
        cavoRifiutato = chiusa.erroreDefinitivo
    }

    private var diagnosiRicerca: Diagnosi? {
        guard benvenutoVisto else { return nil }
        return Diagnosi.ricerca(permessoNegato: cerca.stato == .permessoNegato, nessunComputer: cerca.computer.isEmpty,
                                attesaFinita: mostraAiuto, rete: StatoRete.condiviso)
    }

    private func apriDomanda(_ id: String) {
        // Il conto alla rovescia del ricollegamento non deve aprire «In onda» sotto il foglio.
        annullaRicollegamento()
        domandaAperta = DomandaDaAprire(id: id)
    }

    /// Alla prima comparsa dell'ultimo computer usato parte il conto alla rovescia. 1.12: anche se compare più tardi
    /// (WebcamLR aperto sul computer dopo l'iPhone), e solo se è un computer conosciuto: mai da soli verso uno nuovo.
    private func controllaRicollegamento(_ trovati: [ComputerTrovato]) {
        guard !Ricollegamento.fatto, ricollegaA == nil, !qualcosaInPrimoPiano,
              let ultimo = UserDefaults.standard.string(forKey: Ricollegamento.chiaveUltimoComputer),
              ComputerConosciuti.impronta(di: ultimo) != nil,
              let computer = trovati.first(where: { $0.nome == ultimo }) else { return }
        Ricollegamento.fatto = true
        secondiAlRicollegamento = Ricollegamento.secondi
        withAnimation { ricollegaA = computer }
        // 1.11: collegamento sicuro e fotocamera partono già; il computer accoglie l'iPhone alla fine del conto.
        // 1.14: «Avvio» si misura dalla fine del conto alla rovescia (`conferma`), non dall'apertura dell'app.
        let nuova = SessioneTelefono(computer: computer)
        preparata = nuova
        nuova.avvia(origine: .comparsa, trattieniCiao: true,
                    primaDellaFotocamera: { await FotocameraQR.condivisa.fermaEAspetta() })
        compitoRicollegamento = Task { @MainActor in
            for secondi in stride(from: Ricollegamento.secondi, through: 1, by: -1) {
                secondiAlRicollegamento = secondi
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            // Ultimo controllo: se nel frattempo si è aperto qualcosa, si lascia scegliere all'utente.
            guard !qualcosaInPrimoPiano, preparata === nuova else {
                annullaRicollegamento()
                return
            }
            apri(nuova, giaAvviata: true)
        }
    }

    /// Ferma il conto alla rovescia e chiude la sessione preparata (B9: anche aprendo il QR code o l'indirizzo).
    private func annullaRicollegamento() {
        compitoRicollegamento?.cancel()
        compitoRicollegamento = nil
        if let daChiudere = preparata {
            preparata = nil
            daChiudere.termina()
        }
        if ricollegaA != nil {
            withAnimation { ricollegaA = nil }
        }
    }

    private var intestazione: some View {
        HStack {
            LogoWebcamLR(lato: 34)
            MarchioWebcamLR(dimensione: 26)
            Spacer(minLength: Spazi.stretto)
            pulsantePro
            Button {
                // Il conto alla rovescia del ricollegamento non deve aprire «In onda» sotto il foglio.
                annullaRicollegamento()
                mostraSezioneApp = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Tema.pannello, in: Circle())
            }
            .accessibilityLabel("App e assistenza")
            .accessibilityHint("Guida, «Segnala un bug», computer conosciuti e informazioni")
            Button {
                annullaRicollegamento()
                mostraImpostazioni = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Tema.pannello, in: Circle())
            }
            .accessibilityLabel("Impostazioni")
        }
    }

    /// Bug 1/11: WebcamLR Pro sempre in vista sul telefono, accanto alle informazioni: il segno «PRO» con «Sblocca»
    /// (o con la spunta quando è attivo). Se lo spazio non basta (iPhone piccolo, testo grande) resta il solo segno.
    private var pulsantePro: some View {
        let attivo = NegozioPro.condiviso.attivo
        return Button {
            // Il conto alla rovescia del ricollegamento non deve aprire «In onda» sotto il foglio.
            annullaRicollegamento()
            mostraPro = true
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spazi.stretto) {
                    SegnoPro()
                    if attivo {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Tema.accentoChiaro)
                    } else {
                        Text("Sblocca")
                            .font(.stile(.comando))
                            .foregroundStyle(Tema.accento)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, Spazi.piccolo)
                SegnoPro()
                    .padding(.horizontal, Spazi.stretto)
            }
            .frame(minHeight: 44)
            .background(Tema.pannello, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attivo ? String(localized: "WebcamLR Pro attivo") : String(localized: "Sblocca WebcamLR Pro"))
    }

    // MARK: - Fasi (Interfaccia finale)

    enum Fase: Hashable {
        /// A: nessun computer ancora, si cerca da soli.
        case cerca
        /// B: almeno un computer trovato.
        case trovati
        /// C: 15 secondi a vuoto, o subito con una causa precisa (permesso «Rete locale», niente Wi-Fi).
        case aiuto
    }

    private var fase: Fase {
        if !cerca.computer.isEmpty { return .trovati }
        return diagnosiRicerca == nil ? .cerca : .aiuto
    }

    /// A: fondo sfumato del logo; B e C sul fondo pieno.
    @ViewBuilder private var sfondo: some View {
        if fase == .cerca {
            RadialGradient(colors: [Tema.sfumaturaChiara, Tema.sfumaturaScura], center: UnitPoint(x: 0.5, y: 0.3),
                           startRadius: 0, endRadius: 520)
        } else {
            Tema.fondo
        }
    }

    // MARK: A · Cerco il tuo computer

    private var contenutoCerca: some View {
        VStack(spacing: Spazi.medio) {
            RadarRicerca()
                .padding(.top, Spazi.largo)
            Text("Cerco il tuo computer…")
                .font(.stile(.titoloGrande))
                .multilineTextAlignment(.center)
            Text("Apri WebcamLR sul Mac o sul PC, sulla stessa rete Wi-Fi. Il telefono lo trova da solo.")
                .font(.stile(.corpo))
                .foregroundStyle(Tema.testoSecondario)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let nome = computerAtteso {
                // 1.12: l'iPhone aperto prima del computer: si collega da solo appena il computer compare.
                Text("Apri WebcamLR su «\(nome)»: mi collego da solo appena compare.")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .errore = cerca.stato {
                Text("Ricerca ferma: controlla che il Wi-Fi sia acceso. Riprovo da solo.")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.ambraTesto)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pulsantiCerca: some View {
        VStack(spacing: Spazi.stretto) {
            pulsantePrincipale(Text("Inquadra il QR code"), icona: "qrcode.viewfinder") { apriLettore() }
            pulsanteSecondario(Text("Usa il cavo USB"), icona: "cable.connector") { usaCavo() }
            ShareLink(item: Self.linkComputer, subject: Text("WebcamLR per il computer"),
                      message: Text("Scarica WebcamLR sul computer")) {
                Text("Non hai ancora WebcamLR sul computer?")
                    .underline()
                    .font(.stile(.corpo))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(StileLink())
            .accessibilityHint(Text("Manda l'indirizzo per scaricare WebcamLR, per esempio con AirDrop o Messaggi"))
        }
    }

    // MARK: B · Computer trovati

    private var contenutoTrovati: some View {
        VStack(alignment: .leading, spacing: Spazi.medio) {
            Text("Computer trovati")
                .font(.stile(.titoloGrande))
            if let nome = computerAtteso {
                Text("Apri WebcamLR su «\(nome)»: mi collego da solo appena compare.")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(cerca.computer) { computer in
                RigaComputer(computer: computer, conosciuto: ComputerConosciuti.impronta(di: computer.nome) != nil) {
                    apri(SessioneTelefono(computer: computer))
                }
            }
            Text("Un computer nuovo chiede un codice di conferma la prima volta: lo vedi su entrambi gli schermi.")
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spazi.minimo)
        }
    }

    private var pulsantiTrovati: some View {
        VStack(spacing: Spazi.stretto) {
            pulsanteSecondario(Text("Inquadra il QR code"), icona: "qrcode.viewfinder") { apriLettore() }
            Button("Collega a mano (indirizzo)") { apriIndirizzo() }
                .buttonStyle(StileLink())
                .font(.stile(.corpo))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: C · Non trovo nessun computer

    private var permessoNegato: Bool {
        cerca.stato == .permessoNegato || StatoRete.condiviso.permessoNegato
    }

    private var contenutoAiuto: some View {
        let senzaRete = StatoRete.condiviso.senzaReteLocale
        return VStack(alignment: .leading, spacing: Spazi.medio) {
            Text("Non trovo nessun computer")
                .font(.stile(.titoloGrande))
                .fixedSize(horizontal: false, vertical: true)
            Text("Controlla queste tre cose:")
                .font(.stile(.corpo))
                .foregroundStyle(Tema.testoSecondario)
            VStack(spacing: Spazi.stretto) {
                controllo(1, problema: false,
                          titolo: Text("WebcamLR è aperta sul computer?"),
                          testo: Text("Se non ce l'hai, ti mando il link per scaricarla."))
                // Il nome della rete Wi-Fi chiederebbe un permesso in più (posizione e «Accesso alle informazioni
                // Wi-Fi»): si dice cosa controllare senza nome.
                controllo(2, problema: senzaRete,
                          titolo: Text("Stessa rete Wi-Fi?"),
                          testo: senzaRete
                            ? Text("Il telefono non è su una rete Wi-Fi: collegalo alla stessa rete del computer, oppure usa il cavo. Con un Mac puoi anche accendere «Wi-Fi diretto» in WebcamLR sul Mac.")
                            : StatoRete.condiviso.hotspot
                                ? Text("L'Hotspot personale è acceso: collega il computer all'Hotspot, oppure tutti e due alla stessa rete Wi-Fi.")
                                : Text("Telefono e computer devono essere sulla stessa rete Wi-Fi (non quella per gli ospiti)."))
                controllo(3, problema: permessoNegato,
                          titolo: Text("Permesso «Rete locale»"),
                          testo: permessoNegato
                            ? Text("È spento: senza, il telefono non vede il computer.")
                            : Text("Serve per vedere il computer: se l'iPhone lo chiede, tocca «Consenti»."),
                          azione: permessoNegato)
            }
            Button("Altre risposte nelle domande frequenti") { apriDomanda("non-trova") }
                .buttonStyle(StileLink())
                .font(.stile(.corpo, .corpoForte))
                .frame(minHeight: 44)
        }
    }

    private var pulsantiAiuto: some View {
        VStack(spacing: Spazi.stretto) {
            ShareLink(item: Self.linkComputer, subject: Text("WebcamLR per il computer"),
                      message: Text("Scarica WebcamLR sul computer")) {
                Text("Mandami il link per il computer")
            }
            .buttonStyle(StilePrimario(.grande))
            .accessibilityHint(Text("Manda l'indirizzo per scaricare WebcamLR, per esempio con AirDrop o Messaggi"))
            pulsanteSecondario(Text("Prova con il cavo USB"), icona: "cable.connector") { usaCavo() }
            // Il QR code e l'indirizzo restano a portata anche qui.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spazi.medio) { collegamentiAMano }
                VStack(spacing: Spazi.minimo) { collegamentiAMano }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var collegamentiAMano: some View {
        Button("Inquadra il QR code") { apriLettore() }
            .buttonStyle(StileLink())
            .frame(minHeight: 44)
        Button("Collega a mano (indirizzo)") { apriIndirizzo() }
            .buttonStyle(StileLink())
            .frame(minHeight: 44)
    }

    /// Un punto da controllare: il numero nell'accento, in ambra quando è proprio quello che non va.
    private func controllo(_ numero: Int, problema: Bool, titolo: Text, testo: Text, azione: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Spazi.piccolo) {
            Text(verbatim: "\(numero)")
                .font(.stile(.numeri, .numeriEvidenti))
                .foregroundStyle(Tema.fondo)
                .frame(width: 26, height: 26)
                .background(problema ? Tema.ambra : Tema.accento, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spazi.minimo) {
                titolo
                    .font(.stile(.corpo, .corpoForte))
                    .fixedSize(horizontal: false, vertical: true)
                testo
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                if azione, let impostazioni = URL(string: UIApplication.openSettingsURLString) {
                    Button("Apri Impostazioni") { UIApplication.shared.open(impostazioni) }
                        .buttonStyle(StilePrimario())
                        .padding(.top, Spazi.minimo)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spazi.medio)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Pulsanti e azioni comuni

    /// La pagina per scaricare WebcamLR sul computer, la stessa della presentazione.
    static let linkComputer = PaginaComputer.collegamento

    private func pulsantePrincipale(_ titolo: Text, icona: String, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Label { titolo } icon: { Image(systemName: icona) }
        }
        .buttonStyle(StilePrimario(.grande))
    }

    /// Il secondario di Stile, largo quanto la colonna.
    private func pulsanteSecondario(_ titolo: Text, icona: String, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Label { titolo } icon: { Image(systemName: icona) }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(StileSecondario())
    }

    private func apriLettore() {
        // Come per la sezione App: il conto alla rovescia non deve aprire «In onda» sotto il foglio.
        annullaRicollegamento()
        mostraLettore = true
    }

    private func apriIndirizzo() {
        annullaRicollegamento()
        if indirizzoScritto.isEmpty { indirizzoScritto = ultimoIndirizzo }
        mostraIndirizzo = true
    }

    /// «Usa il cavo USB»: l'ascolto sul cavo riparte (anche dopo «Scollega») e la scheda dice cosa fare.
    private func usaCavo() {
        cavoRifiutato = false
        cavoInPausa = false
        withAnimation { mostraCavo = true }
    }

    /// 1.6: il cavo USB. Mentre l'app è aperta l'iPhone ascolta sul cavo: collegato il cavo e aperto WebcamLR
    /// sul computer, «In onda» si apre da sola.
    private var schedaUSB: some View {
        HStack(alignment: .top, spacing: Spazi.medio) {
            Image(systemName: "cable.connector")
                .font(.system(size: 20))
                .foregroundStyle(ascolto.inAscolto ? Tema.accento : Tema.testoSecondario)
                .frame(width: 48, height: 48)
                .background(ascolto.inAscolto ? Tema.accentoTenue : Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.controllo))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spazi.minimo) {
                Text("Via cavo USB").font(.stile(.corpo, .corpoForte))
                Text(cavoInPausa
                     ? "Scollegato. Tocca «Collega via cavo» per collegarti di nuovo con il cavo."
                     : "Collega l'iPhone al computer con il cavo e apri WebcamLR sul computer: si collega da solo, ed è il modo più stabile.")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                // Con il testo grande i due pulsanti vanno uno sotto l'altro, senza troncare.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spazi.medio) { pulsantiUSB }
                    VStack(alignment: .leading, spacing: Spazi.stretto) { pulsantiUSB }
                }
                .foregroundStyle(Tema.accentoChiaro)
                .padding(.top, Spazi.minimo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spazi.medio)
        .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: Raggi.pannello))
        .overlay(RoundedRectangle(cornerRadius: Raggi.pannello).stroke(Tema.linea))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var pulsantiUSB: some View {
        if cavoInPausa {
            Button("Collega via cavo") {
                cavoRifiutato = false
                cavoInPausa = false
            }
            .buttonStyle(StileLink())
            .font(.stile(.corpo, .corpoForte))
            .frame(minHeight: 44)
        }
        Button("Come funziona") { apriDomanda("cavo") }
            .buttonStyle(StileLink())
            .font(.stile(.nota, .corpoForte))
            .frame(minHeight: 44)
    }

    private func collega(_ associazione: Associazione) {
        guard let computer = ComputerTrovato(associazione: associazione) else { return }
        apri(SessioneTelefono(computer: computer))
    }

    /// 1.10: letto il QR code, il collegamento parte subito, mentre il foglio si chiude; «In onda» si apre dopo.
    private func collegaDalQR(_ associazione: Associazione) {
        guard let computer = ComputerTrovato(associazione: associazione) else { return }
        daMostrare = true
        apri(SessioneTelefono(computer: computer), mostra: false, origine: .qr)
    }

    /// `mostra` falso: «In onda» la apre chi chiama (dopo la chiusura del foglio del QR code).
    /// `giaAvviata`: 1.11, la sessione preparata durante il conto alla rovescia: basta confermarla.
    private func apri(_ nuova: SessioneTelefono, mostra: Bool = true, origine: OrigineAvvio = .tocco,
                      giaAvviata: Bool = false) {
        // Scelto un computer (da sé o col conto alla rovescia): niente più ricollegamento in questo avvio.
        Ricollegamento.fatto = true
        // La sessione preparata che si apre non va chiusa con il conto alla rovescia.
        if giaAvviata && preparata === nuova { preparata = nil }
        annullaRicollegamento()
        sessione = nuova
        if giaAvviata {
            nuova.conferma()
        } else {
            // Collegamento e fotocamera partono subito, mentre «In onda» si apre. La fotocamera della sessione
            // si accende quando quella del lettore QR è spenta.
            nuova.avvia(origine: origine, primaDellaFotocamera: { await FotocameraQR.condivisa.fermaEAspetta() })
        }
        if mostra { inOnda = true }
    }
}

private struct RigaComputer: View {
    let computer: ComputerTrovato
    /// Già usato (codice di sicurezza salvato): in evidenza, si collega senza codice di conferma.
    let conosciuto: Bool
    let collega: () -> Void

    /// Tutta la riga si tocca, non solo «Collega»: si fa prima, anche con una mano.
    var body: some View {
        Button(action: collega) {
            HStack(spacing: Spazi.medio) {
                Image(systemName: computer.piattaforma == .windows ? "desktopcomputer" : "laptopcomputer")
                    .font(.system(size: 22))
                    .foregroundStyle(conosciuto ? Tema.accento : Tema.testoSecondario)
                    .frame(width: 46, height: 46)
                    .background(conosciuto ? Tema.pannello : Tema.fondo, in: RoundedRectangle(cornerRadius: Raggi.controllo))
                VStack(alignment: .leading, spacing: Spazi.minimo) {
                    Text(computer.nome)
                        .font(.stile(.corpo, .corpoForte))
                        .foregroundStyle(Tema.testo)
                        .multilineTextAlignment(.leading)
                    Text(descrizione)
                        .font(.stile(.nota))
                        .foregroundStyle(Tema.testoSecondario)
                }
                Spacer(minLength: Spazi.stretto)
                Text("Collega")
                    .font(.stile(.corpo, .corpoForte))
                    // Con il testo grande va a capo il nome del computer, non «Collega».
                    .fixedSize()
                    .foregroundStyle(conosciuto ? Tema.accento : Tema.testoSecondario)
                    .frame(minHeight: 36)
            }
            .padding(Spazi.medio)
            .background(conosciuto ? Tema.pannelloChiaro : Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.pannello))
            .overlay(RoundedRectangle(cornerRadius: Raggi.pannello).stroke(conosciuto ? Tema.accento : Tema.linea))
            .contentShape(RoundedRectangle(cornerRadius: Raggi.pannello))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Collega a \(computer.nome)")
        .accessibilityValue(descrizione)
        .accessibilityAddTraits(.isButton)
    }

    /// 1.2: come ci si collegherà, con le stesse parole dell'indicatore in «In onda»; poi già usato o nuovo.
    private var descrizione: String {
        let via = computer.diretto ? TipoCollegamento.wifiDiretto.testo : TipoCollegamento.wifi.testo
        // G2.5: il computer nuovo non è spento: la prima volta chiede il codice di conferma.
        let storia = conosciuto ? String(localized: "già usato") : String(localized: "nuovo · la prima volta chiede un codice")
        switch computer.piattaforma {
        case .mac: return "macOS · \(via) · \(storia)"
        case .windows: return "Windows · \(via) · \(storia)"
        default: return "\(via) · \(storia)"
        }
    }
}

/// «Cerco il tuo computer…»: tre cerchi attorno a un monitor; con «Riduci movimento» stanno fermi.
private struct RadarRicerca: View {
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento
    @State private var onda = false

    var body: some View {
        ZStack {
            // Un disegno: cerchi sempre più tenui (opacità e distanze del disegno, non token).
            Circle().stroke(Tema.accento.opacity(0.18), lineWidth: 1)
            Circle().stroke(Tema.accento.opacity(0.3), lineWidth: 1).padding(Spazi.ampio)
            Circle().stroke(Tema.accento.opacity(0.5), lineWidth: 1).padding(68)
            if !riduciMovimento {
                Circle()
                    .stroke(Tema.accento.opacity(onda ? 0 : 0.5), lineWidth: 1.5)
                    .scaleEffect(onda ? 1 : 0.45)
                    .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false), value: onda)
            }
            Image(systemName: "display")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Tema.accento)
        }
        .frame(width: 220, height: 220)
        .accessibilityHidden(true)
        .onAppear { onda = true }
    }
}

#Preview {
    NavigationStack { SchermataConnessione() }
        .preferredColorScheme(.dark)
}
