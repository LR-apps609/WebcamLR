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
        case .ottima: String(localized: "Ottimo", bundle: .stile)
        case .buona: String(localized: "Buono", bundle: .stile)
        case .debole: String(localized: "Debole", bundle: .stile)
        }
    }

    public var colore: Color {
        switch self {
        case .ottima: Tema.verde
        case .buona: Tema.accentoChiaro
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

/// Le tre tacche della qualità, come il segnale del telefono: piene quante dice la qualità, nel suo colore.
/// È un segno disegnato (tacche larghe 3 punti, alte 5, 8 e 11, a 2 punti l'una dall'altra), non testo.
public struct TaccheQualita: View {
    let qualita: QualitaCollegamento

    public init(_ qualita: QualitaCollegamento) {
        self.qualita = qualita
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { indice in
                Capsule()
                    .fill(indice < qualita.tacche ? qualita.colore : Tema.linea)
                    .frame(width: 3, height: CGFloat(5 + indice * 3))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tre tacche e la parola: «▮▮▮ Ottimo». Il numero in ms resta per chi lo vuole, nell'aiuto al passaggio.
/// Dentro un chip informativo: `ChipQualita(qualita).chipInformativo()`.
public struct ChipQualita: View {
    let qualita: QualitaCollegamento
    let latenzaMs: Int?

    public init(_ qualita: QualitaCollegamento, latenzaMs: Int? = nil) {
        self.qualita = qualita
        self.latenzaMs = latenzaMs
    }

    public var body: some View {
        HStack(spacing: Spazi.stretto) {
            TaccheQualita(qualita)
            Text(qualita.testo)
                .font(.stile(.sezione))
                .foregroundStyle(qualita.colore)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(latenzaMs.map { String(localized: "Collegamento \(qualita.testo.lowercased()), \($0) millisecondi", bundle: .stile) }
                            ?? String(localized: "Collegamento \(qualita.testo.lowercased())", bundle: .stile))
    }
}
