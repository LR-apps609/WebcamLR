import Network
import Stile
import SwiftUI
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
    @State private var sessione: SessioneTelefono?
    @State private var inOnda = false
    @State private var mostraLettore = false
    /// 1.10: la sessione dal QR code è già partita alla lettura; «In onda» si apre quando il foglio è chiuso.
    @State private var daMostrare = false
    @State private var mostraIndirizzo = false
    @State private var indirizzoScritto = ""
    @State private var indirizzoNonValido = false
    /// Dopo qualche secondo senza computer compare la scheda con le cose da controllare (funzione 34).
    @State private var mostraAiuto = false
    /// Il computer a cui ci si sta per ricollegare da soli, con i secondi che mancano.
    @State private var ricollegaA: ComputerTrovato?
    @State private var secondiAlRicollegamento = Ricollegamento.secondi
    @State private var compitoRicollegamento: Task<Void, Never>?
    /// 1.11: la sessione già avviata durante il conto alla rovescia, che aspetta solo la fine per mandare il `ciao`.
    /// Se il conto si annulla, si chiude.
    @State private var preparata: SessioneTelefono?
    /// Sezione App (0.12): guida, segnalazioni, computer conosciuti e informazioni.
    @State private var mostraSezioneApp = false
    /// Una risposta delle domande frequenti aperta da una diagnosi (1.4).
    @State private var domandaAperta: DomandaDaAprire?
    /// Le tre schermate di benvenuto si vedono solo alla prima apertura (round 2, novità 16).
    @AppStorage("benvenutoVisto") private var benvenutoVisto = false
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
    @Environment(\.scenePhase) private var fase

    private var mostraBenvenuto: Binding<Bool> {
        Binding(get: { !benvenutoVisto },
                set: { mostra in if !mostra { benvenutoVisto = true } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intestazione
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scegli il computer")
                        .font(.titolo(40))
                    Text("Apri WebcamLR sul Mac o sul PC: compare qui da solo, sulla stessa rete Wi-Fi.")
                        .font(.subheadline)
                        .foregroundStyle(Tema.testoSecondario)
                }
                statoRicerca
                if let nome = computerAtteso {
                    // 1.12: l'iPhone aperto prima del computer: si collega da solo appena il computer compare.
                    Text("Apri WebcamLR su «\(nome)»: mi collego da solo appena compare.")
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let computer = ricollegaA {
                    bannerRicollegamento(computer)
                }
                // 1.3: la causa probabile se non compare nessun computer; dopo qualche secondo i passi di sempre.
                if let diagnosi = diagnosiRicerca {
                    if diagnosi == .nonTrova {
                        schedaAiuto
                    } else {
                        SchedaDiagnosi(diagnosi: diagnosi) { domanda in apriDomanda(domanda) }
                    }
                }
                ForEach(cerca.computer) { computer in
                    RigaComputer(computer: computer) { apri(SessioneTelefono(computer: computer)) }
                }
                schedaUSB
                Spacer(minLength: 24)
                pulsanti
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Tema.fondo)
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
                    collega(associazione)
                } else {
                    // Un secondo avviso va aperto quando il primo è chiuso del tutto.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { indirizzoNonValido = true }
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Lo trovi sul computer, nel menu di WebcamLR, sotto il QR code.")
        }
        .alert("Indirizzo non valido", isPresented: $indirizzoNonValido) {
            Button("Riprova") { mostraIndirizzo = true }
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
            SchermataBenvenuto { benvenutoVisto = true }
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
            try? await Task.sleep(for: .seconds(8))
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
        .onChange(of: fase) { _, nuova in
            // Uscendo dall'app la pausa finisce: al ritorno il cavo funziona di nuovo da solo.
            if nuova == .background && !cavoRifiutato { cavoInPausa = false }
        }
        .onChange(of: cerca.computer) { _, trovati in
            controllaRicollegamento(trovati)
        }
    }

    private func bannerRicollegamento(_ computer: ComputerTrovato) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Tema.ciano)
            Text("Mi ricollego a \(computer.nome) tra \(secondiAlRicollegamento)…")
                .fontWeight(.semibold)
            Spacer(minLength: 8)
            Button("Annulla") { annullaRicollegamento() }
                .fontWeight(.semibold)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Tema.cianoTenue, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tema.ciano))
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
        mostraLettore || mostraSezioneApp || mostraIndirizzo || indirizzoNonValido || mostraAvvisoIdentita
            || daMostrare || domandaAperta != nil || !benvenutoVisto
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
        // Subito dopo l'apertura dell'app si misura da lì, altrimenti dalla comparsa del computer.
        let appenaAperta = Date().timeIntervalSince(MisuraAvvio.aperturaApp) < 30
        let nuova = SessioneTelefono(computer: computer)
        preparata = nuova
        nuova.avvia(origine: appenaAperta ? .aperturaApp : .comparsa, trattieniCiao: true,
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
            Spacer()
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
            NavigationLink {
                SchermataImpostazioni()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Tema.pannello, in: Circle())
            }
            .accessibilityLabel("Impostazioni")
        }
    }

    private var statoRicerca: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Tema.ciano)
                .accessibilityHidden(true)
            switch cerca.stato {
            case .permessoNegato:
                Text("Ricerca ferma: manca il permesso «Rete locale».")
            case .errore:
                Text("Ricerca ferma: controlla che il Wi-Fi sia acceso. Riprovo da solo.")
            default:
                Text("Cerco computer sulla rete…")
            }
            Spacer()
            Text(cerca.computer.count == 1 ? "1 trovato" : "\(cerca.computer.count) trovati")
                .font(.numeri(12))
                .foregroundStyle(Tema.testoSecondario)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tema.linea))
    }

    /// Le stesse soluzioni della pagina Aiuto del sito, nell'ordine in cui capitano più spesso.
    private var schedaAiuto: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Non trovi il computer?")
                .font(.titolo(26))
            VStack(alignment: .leading, spacing: 8) {
                passo(1, "Apri WebcamLR sul Mac o sul PC.")
                passo(2, "iPhone e computer devono essere sulla stessa rete Wi-Fi. Senza rete, con un Mac: accendi «Wi-Fi diretto» nelle Impostazioni di WebcamLR sul Mac.")
                passo(3, "Su Windows consenti le reti private quando WebcamLR lo chiede.")
                passo(4, "Reti di alberghi e uffici spesso separano i dispositivi: usa il QR code o l'Hotspot personale dell'iPhone.")
            }
            Button("Altre risposte nelle domande frequenti") { apriDomanda("non-trova") }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Tema.cianoChiaro)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.ambraTenue, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Tema.testo)
        .transition(.opacity)
    }

    private func passo(_ numero: Int, _ testo: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(numero)")
                .font(.numeriEvidenti(13))
                .foregroundStyle(Tema.ambraTesto)
            Text(testo)
                .font(.subheadline)
                .foregroundStyle(Tema.testoChiaro)
        }
    }

    /// 1.6: il cavo USB. Mentre l'app è aperta l'iPhone ascolta sul cavo: collegato il cavo e aperto WebcamLR
    /// sul computer, «In onda» si apre da sola.
    private var schedaUSB: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cable.connector")
                .font(.system(size: 20))
                .foregroundStyle(ascolto.inAscolto ? Tema.ciano : Tema.testoSecondario)
                .frame(width: 48, height: 48)
                .background(ascolto.inAscolto ? Tema.cianoTenue : Tema.pannello, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Via cavo USB").fontWeight(.semibold)
                Text(cavoInPausa
                     ? "Scollegato. Tocca «Collega via cavo» per collegarti di nuovo con il cavo."
                     : "Collega l'iPhone al computer con il cavo e apri WebcamLR sul computer: si collega da solo, ed è il modo più stabile.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    if cavoInPausa {
                        Button("Collega via cavo") {
                            cavoRifiutato = false
                            cavoInPausa = false
                        }
                            .fontWeight(.semibold)
                    }
                    Button("Come funziona") { apriDomanda("cavo") }
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Tema.cianoChiaro)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tema.linea))
        .accessibilityElement(children: .contain)
    }

    private var pulsanti: some View {
        VStack(spacing: 10) {
            Button {
                // Come per la sezione App: il conto alla rovescia non deve aprire «In onda» sotto il foglio.
                annullaRicollegamento()
                mostraLettore = true
            } label: {
                Label("Inquadra il QR code del computer", systemImage: "qrcode.viewfinder")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Tema.testo, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Tema.fondo)
            }
            Button("Non lo trovi? Inserisci l'indirizzo") {
                annullaRicollegamento()
                mostraIndirizzo = true
            }
                .fontWeight(.semibold)
                .frame(minHeight: 44)
        }
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
    let collega: () -> Void

    /// Tutta la riga si tocca, non solo «Collega»: si fa prima, anche con una mano.
    var body: some View {
        Button(action: collega) {
            HStack(spacing: 14) {
                Image(systemName: computer.piattaforma == .windows ? "desktopcomputer" : "laptopcomputer")
                    .font(.system(size: 22))
                    .foregroundStyle(Tema.ciano)
                    .frame(width: 48, height: 48)
                    .background(Tema.cianoTenue, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(computer.nome)
                        .fontWeight(.semibold)
                        .foregroundStyle(Tema.testo)
                        .multilineTextAlignment(.leading)
                    Text(descrizione)
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                }
                Spacer(minLength: 8)
                Text("Collega")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Tema.ciano, in: Capsule())
                    .foregroundStyle(Tema.fondo)
            }
            .padding(14)
            .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tema.linea))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Collega a \(computer.nome)")
        .accessibilityValue(descrizione)
        .accessibilityAddTraits(.isButton)
    }

    /// 1.2: come ci si collegherà, con le stesse parole dell'indicatore in «In onda».
    private var descrizione: String {
        let via = computer.diretto ? TipoCollegamento.wifiDiretto.testo : TipoCollegamento.wifi.testo
        switch computer.piattaforma {
        case .mac: return "macOS · \(via)"
        case .windows: return "Windows · \(via)"
        default: return via
        }
    }
}

#Preview {
    NavigationStack { SchermataConnessione() }
        .preferredColorScheme(.dark)
}
