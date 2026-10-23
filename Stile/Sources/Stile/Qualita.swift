import SwiftUI

/// Qualità del collegamento in parole, uguale su iPhone, Mac e Windows (round 2).
/// Le soglie sono quelle della checklist: sotto i 100 ms la latenza è buona per una chiamata.
public enum QualitaCollegamento: Equatable, Sendable {
    case ottima
    case buona
    case debole

    /// `perdite`: fotogrammi saltati negli ultimi secondi; anche con poca latenza, se si salta è debole.
    public init(latenzaMs: Int, perdite: Int = 0) {
        if latenzaMs >= 150 || perdite >= 10 {
            self = .debole
        } else if latenzaMs >= 80 || perdite > 0 {
            self = .buona
        } else {
            self = .ottima
        }
    }

    public var testo: String {
        switch self {
        case .ottima: "Ottimo"
        case .buona: "Buono"
        case .debole: "Debole"
        }
    }

    public var colore: Color {
        switch self {
        case .ottima: Tema.verde
        case .buona: Tema.cianoChiaro
        case .debole: Tema.ambraTesto
        }
    }

    /// Tacche piene su tre, come il segnale del telefono.
    public var tacche: Int {
        switch self {
        case .ottima: 3
        case .buona: 2
        case .debole: 1
        }
    }
}

/// Tre tacche e la parola: «▮▮▮ Ottimo». Il numero in ms resta per chi lo vuole, nell'aiuto al passaggio.
public struct ChipQualita: View {
    let qualita: QualitaCollegamento
    let latenzaMs: Int?

    public init(_ qualita: QualitaCollegamento, latenzaMs: Int? = nil) {
        self.qualita = qualita
        self.latenzaMs = latenzaMs
    }

    public var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { indice in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(indice < qualita.tacche ? qualita.colore : Tema.linea)
                        .frame(width: 3, height: CGFloat(5 + indice * 3))
                }
            }
            Text(qualita.testo)
                .font(.etichetta(14))
                .foregroundStyle(qualita.colore)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(latenzaMs.map { "Collegamento \(qualita.testo.lowercased()), \($0) millisecondi" }
                            ?? "Collegamento \(qualita.testo.lowercased())")
    }
}
