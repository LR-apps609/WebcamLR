import SwiftUI

/// Il logo: griglia di pixel 3×3 con il centro rosso.
public struct LogoWebcamLR: View {
    let lato: CGFloat

    public init(lato: CGFloat) {
        self.lato = lato
    }

    public var body: some View {
        let cella = lato * 0.16
        let spazio = lato * 0.04
        ZStack {
            RoundedRectangle(cornerRadius: lato * 0.22)
                .fill(Color(esadecimale: 0x26302D))
            Grid(horizontalSpacing: spazio, verticalSpacing: spazio) {
                ForEach(0..<3, id: \.self) { riga in
                    GridRow {
                        ForEach(0..<3, id: \.self) { colonna in
                            RoundedRectangle(cornerRadius: cella * 0.2)
                                .fill(colore(riga: riga, colonna: colonna))
                                .frame(width: cella, height: cella)
                        }
                    }
                }
            }
        }
        .frame(width: lato, height: lato)
        .accessibilityHidden(true)
    }

    private func colore(riga: Int, colonna: Int) -> Color {
        if riga == 1 && colonna == 1 { return Tema.tally }
        return .white.opacity((riga + colonna) % 2 == 0 ? 0.35 : 0.6)
    }
}

/// «WebcamLR» con «LR» in rosso.
public struct MarchioWebcamLR: View {
    let dimensione: CGFloat

    public init(dimensione: CGFloat) {
        self.dimensione = dimensione
    }

    public var body: some View {
        (Text("Webcam") + Text("LR").foregroundColor(Tema.tally))
            .font(.titolo(dimensione))
            .accessibilityLabel("WebcamLR")
    }
}

/// Etichetta di sezione in maiuscolo, come «TELEFONI» o «VIDEO».
public struct EtichettaSezione: View {
    let testo: String

    public init(_ testo: String) {
        self.testo = testo
    }

    public var body: some View {
        Text(testo.uppercased())
            .font(.etichetta(14))
            .tracking(1.1)
            .foregroundStyle(Tema.testoSecondario)
    }
}

/// I quattro stati, uguali in tutte le app.
public enum StatoCollegamento: Equatable, Sendable {
    /// Un'app sta usando il video: l'unico caso in cui compare il rosso.
    case inOnda(app: String?)
    case collegato
    case riconnessione
    case nessunTelefono
}

public struct PillolaStato: View {
    let stato: StatoCollegamento
    let testo: String?

    /// `testo` sostituisce la dicitura predefinita (per esempio il nome del computer).
    public init(_ stato: StatoCollegamento, testo: String? = nil) {
        self.stato = stato
        self.testo = testo
    }

    public var body: some View {
        HStack(spacing: 8) {
            punto
            Text((testo ?? diciturePredefinite).uppercased())
                .font(.etichetta(16))
                .tracking(0.9)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .foregroundStyle(colorTesto)
        .background(sfondo, in: Capsule())
        .overlay {
            if stato == .nessunTelefono {
                Capsule().stroke(Tema.bordo)
            }
        }
    }

    @ViewBuilder private var punto: some View {
        switch stato {
        case .inOnda: Circle().fill(.white).frame(width: 8, height: 8)
        case .collegato: Circle().fill(Tema.verde).frame(width: 8, height: 8)
        case .riconnessione: Circle().fill(Tema.ambra).frame(width: 8, height: 8)
        case .nessunTelefono: Circle().stroke(Tema.testoTenue, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    private var diciturePredefinite: String {
        switch stato {
        case .inOnda(let app): app.map { "In onda · \($0)" } ?? "In onda"
        case .collegato: "Collegato"
        case .riconnessione: "Riconnessione"
        case .nessunTelefono: "Nessun telefono"
        }
    }

    private var colorTesto: Color {
        switch stato {
        case .inOnda: .white
        case .collegato: Tema.testo
        case .riconnessione: Tema.ambraTesto
        case .nessunTelefono: Tema.testoTenue
        }
    }

    private var sfondo: Color {
        switch stato {
        case .inOnda: Tema.tallyPieno
        case .collegato: Tema.pannelloChiaro
        case .riconnessione: Tema.ambraTenue
        case .nessunTelefono: .clear
        }
    }
}

/// Pulsante tondo con icona, come quelli della barra laterale di «In onda».
public struct PulsanteTondo: View {
    let icona: String
    let etichetta: String
    let attivo: Bool
    let azione: () -> Void

    public init(_ etichetta: String, icona: String, attivo: Bool = false, azione: @escaping () -> Void) {
        self.etichetta = etichetta
        self.icona = icona
        self.attivo = attivo
        self.azione = azione
    }

    public var body: some View {
        Button(action: azione) {
            Image(systemName: icona)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(attivo ? Tema.cianoChiaro : .white)
                .frame(width: 48, height: 48)
                .background(attivo ? Tema.cianoTenue : Tema.pannelloChiaro, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etichetta)
    }
}
