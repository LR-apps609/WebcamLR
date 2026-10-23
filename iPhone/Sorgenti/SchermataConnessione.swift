import Stile
import SwiftUI
import WebcamLRProtocollo

/// Schermata «Scegli il computer» (bozza grafica, iPhone 1).
struct SchermataConnessione: View {
    @State private var cerca = CercaComputer()
    @State private var sessione: SessioneTelefono?
    @State private var mostraLettore = false
    @State private var daCollegare: Associazione?
    @State private var mostraIndirizzo = false
    @State private var indirizzoScritto = ""
    @State private var indirizzoNonValido = false

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
                ForEach(cerca.computer) { computer in
                    RigaComputer(computer: computer) { sessione = SessioneTelefono(computer: computer) }
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
        .navigationDestination(isPresented: Binding(get: { sessione != nil }, set: { if !$0 { sessione = nil } })) {
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
        .alert("Indirizzo del computer", isPresented: $mostraIndirizzo) {
            TextField("192.168.1.20", text: $indirizzoScritto)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Collega") {
                if let associazione = Associazione(indirizzoScritto: indirizzoScritto) {
                    collega(associazione)
                } else {
                    indirizzoNonValido = true
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
        .onAppear { cerca.avvia() }
        .onDisappear { cerca.ferma() }
    }

    private var intestazione: some View {
        HStack {
            LogoWebcamLR(lato: 34)
            MarchioWebcamLR(dimensione: 26)
            Spacer()
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

    private var schedaUSB: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cable.connector")
                .foregroundStyle(Tema.testoSecondario)
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
        sessione = SessioneTelefono(computer: computer)
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
                .frame(height: 36)
                .background(Tema.ciano, in: Capsule())
                .foregroundStyle(Tema.fondo)
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
