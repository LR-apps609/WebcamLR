import Foundation
import Observation
import Stile
import SwiftUI

/// «Registro del collegamento» (1.5, modalità avanzata): gli ultimi 50 eventi con l'ora, solo in memoria.
/// Non si salva e non esce dall'iPhone, se non quando l'utente lo condivide da sé.
@Observable
@MainActor
final class RegistroCollegamento {
    struct Voce: Identifiable {
        let id = UUID()
        let data: Date
        let testo: String
    }

    static let condiviso = RegistroCollegamento()
    static let massimo = 50

    private(set) var voci: [Voce] = []

    func aggiungi(_ testo: String) {
        voci.append(Voce(data: Date(), testo: testo))
        if voci.count > Self.massimo {
            voci.removeFirst(voci.count - Self.massimo)
        }
    }

    func svuota() {
        voci.removeAll()
    }

    /// Da qualsiasi coda.
    nonisolated static func scrivi(_ testo: String) {
        Task { @MainActor in
            RegistroCollegamento.condiviso.aggiungi(testo)
        }
    }

    /// Il registro come testo, dal più vecchio al più recente: per «Segnala un bug» o un messaggio.
    var testo: String {
        voci.map { "\(Self.ora($0.data))  \($0.testo)" }.joined(separator: "\n")
    }

    nonisolated static func ora(_ data: Date) -> String {
        data.formatted(date: .omitted, time: .standard)
    }
}

/// Il registro, dal più recente in giù.
struct VistaRegistro: View {
    private var registro: RegistroCollegamento { RegistroCollegamento.condiviso }

    var body: some View {
        List {
            if registro.voci.isEmpty {
                Text("Ancora niente: gli eventi compaiono qui mentre l'app cerca il computer e si collega.")
                    .font(.subheadline)
                    .foregroundStyle(Tema.testoSecondario)
                    .listRowBackground(Tema.pannello)
            } else {
                Section {
                    ForEach(Array(registro.voci.reversed())) { voce in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(RegistroCollegamento.ora(voce.data))
                                .font(.numeri(12))
                                .foregroundStyle(Tema.testoSecondario)
                            Text(voce.testo)
                                .font(.subheadline)
                                .foregroundStyle(Tema.testoChiaro)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .listRowBackground(Tema.pannello)
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text("Solo in memoria: si cancella quando chiudi l'app.")
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                }
            }
        }
        .tint(Tema.ciano)
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !registro.voci.isEmpty {
                    ShareLink(item: registro.testo) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Condividi il registro")
                    Button("Svuota") { registro.svuota() }
                }
            }
        }
    }
}
