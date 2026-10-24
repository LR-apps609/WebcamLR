import Stile
import SwiftUI
import WebcamLRProtocollo

/// Ricollegamento automatico (round 2, novità 2): all'avvio, se la ricerca trova l'ultimo computer usato,
/// ci si collega da soli dopo 3 secondi. Una volta sola per avvio dell'app.
enum Ricollegamento {
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
    @State private var daCollegare: Associazione?
    @State private var mostraIndirizzo = false
    @State private var indirizzoScritto = ""
    @State private var indirizzoNonValido = false
    /// Dopo qualche secondo senza computer compare la scheda con le cose da controllare (funzione 34).
    @State private var mostraAiuto = false
    /// Il computer a cui ci si sta per ricollegare da soli, con i secondi che mancano.
    @State private var ricollegaA: ComputerTrovato?
    @State private var secondiAlRicollegamento = 3
    @State private var compitoRicollegamento: Task<Void, Never>?
    /// Sezione App (0.12): guida, segnalazioni, computer conosciuti e informazioni.
    @State private var mostraSezioneApp = false
    /// Le tre schermate di benvenuto si vedono solo alla prima apertura (round 2, novità 16).
    @AppStorage("benvenutoVisto") private var benvenutoVisto = false

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
                if let computer = ricollegaA {
                    bannerRicollegamento(computer)
                }
                if mostraAiuto && cerca.computer.isEmpty {
                    schedaAiuto
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
            // Si collega quando il foglio è chiuso del tutto, così la navigazione non si incrocia.
            if let associazione = daCollegare {
                daCollegare = nil
                collega(associazione)
            }
        }) {
            FoglioLettoreQR { associazione in
                daCollegare = associazione
            }
        }
        .sheet(isPresented: $mostraSezioneApp) {
            SchermataApp(ultimaLatenzaMs: sessione?.ultimaLatenzaMs)
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
        .fullScreenCover(isPresented: mostraBenvenuto) {
            SchermataBenvenuto { benvenutoVisto = true }
        }
        .task(id: benvenutoVisto) {
            guard benvenutoVisto else { return }
            try? await Task.sleep(for: .seconds(8))
            if Task.isCancelled { return }
            withAnimation { mostraAiuto = true }
        }
        // La ricerca fa chiedere a iOS il permesso «Rete locale»: parte solo dopo il benvenuto, che lo spiega.
        .onAppear {
            if benvenutoVisto { cerca.avvia() }
        }
        .onChange(of: benvenutoVisto) { _, visto in
            if visto { cerca.avvia() }
        }
        .onDisappear {
            cerca.ferma()
            annullaRicollegamento()
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

    /// Alla prima comparsa dell'ultimo computer usato parte il conto alla rovescia.
    private func controllaRicollegamento(_ trovati: [ComputerTrovato]) {
        guard !Ricollegamento.fatto, ricollegaA == nil,
              let ultimo = UserDefaults.standard.string(forKey: Ricollegamento.chiaveUltimoComputer),
              let computer = trovati.first(where: { $0.nome == ultimo }) else { return }
        Ricollegamento.fatto = true
        secondiAlRicollegamento = 3
        withAnimation { ricollegaA = computer }
        compitoRicollegamento = Task { @MainActor in
            for secondi in [3, 2, 1] {
                secondiAlRicollegamento = secondi
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            apri(SessioneTelefono(computer: computer))
        }
    }

    private func annullaRicollegamento() {
        compitoRicollegamento?.cancel()
        compitoRicollegamento = nil
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
            .accessibilityHint("Guida, Segnala un bug, computer conosciuti e informazioni")
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
                Text("Serve il permesso «Rete locale»: attivalo in Impostazioni › WebcamLR.")
            case .errore(let descrizione):
                Text("Ricerca non riuscita: \(descrizione)")
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
                passo(2, "iPhone e computer devono essere sulla stessa rete Wi-Fi. Con un Mac basta il Wi-Fi acceso su entrambi, anche senza router.")
                passo(3, "Su Windows consenti le reti private quando WebcamLR lo chiede.")
                passo(4, "Reti di alberghi e uffici spesso separano i dispositivi: usa il QR code o l'hotspot dell'iPhone.")
            }
            if cerca.stato == .permessoNegato, let impostazioni = URL(string: UIApplication.openSettingsURLString) {
                Link("Attiva «Rete locale» nelle Impostazioni", destination: impostazioni)
                    .fontWeight(.semibold)
            }
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

    private var schedaUSB: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cable.connector")
                .foregroundStyle(Tema.testoSecondario)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Via cavo USB").fontWeight(.semibold)
                Text("Collega l'iPhone al computer: la connessione è più stabile e il telefono si ricarica.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tema.linea, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var pulsanti: some View {
        VStack(spacing: 10) {
            Button {
                mostraLettore = true
            } label: {
                Label("Inquadra il QR code del computer", systemImage: "qrcode.viewfinder")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Tema.testo, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Tema.fondo)
            }
            Button("Non lo trovi? Inserisci l'indirizzo") { mostraIndirizzo = true }
                .fontWeight(.semibold)
                .frame(minHeight: 44)
        }
    }

    private func collega(_ associazione: Associazione) {
        guard let computer = ComputerTrovato(associazione: associazione) else { return }
        apri(SessioneTelefono(computer: computer))
    }

    private func apri(_ nuova: SessioneTelefono) {
        // Scelto un computer (da sé o col conto alla rovescia): niente più ricollegamento in questo avvio.
        Ricollegamento.fatto = true
        annullaRicollegamento()
        sessione = nuova
        inOnda = true
    }
}

private struct RigaComputer: View {
    let computer: ComputerTrovato
    let collega: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: computer.piattaforma == .windows ? "desktopcomputer" : "laptopcomputer")
                .font(.system(size: 22))
                .foregroundStyle(Tema.ciano)
                .frame(width: 48, height: 48)
                .background(Tema.cianoTenue, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(computer.nome).fontWeight(.semibold)
                Text(descrizione)
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
            Spacer()
            Button("Collega", action: collega)
                .fontWeight(.semibold)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Tema.ciano, in: Capsule())
                .foregroundStyle(Tema.fondo)
                .accessibilityLabel("Collega a \(computer.nome)")
        }
        .padding(14)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tema.linea))
    }

    private var descrizione: String {
        switch computer.piattaforma {
        case .mac: "macOS · Wi-Fi"
        case .windows: "Windows · Wi-Fi"
        default: "Wi-Fi"
        }
    }
}

#Preview {
    NavigationStack { SchermataConnessione() }
        .preferredColorScheme(.dark)
}
