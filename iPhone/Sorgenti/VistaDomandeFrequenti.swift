import Stile
import SwiftUI

/// Una domanda da aprire da un errore o da una diagnosi (1.4): l'`id` di `DomandeFrequenti`.
struct DomandaDaAprire: Identifiable, Equatable {
    let id: String
}

/// Domande frequenti (1.4): con la ricerca, senza bisogno di Internet. I testi stanno in Stile.
/// `aperta`: la risposta da mostrare già aperta e per prima, quando si arriva da un errore.
struct VistaDomandeFrequenti: View {
    var aperta: String? = nil
    @State private var ricerca = ""
    @State private var espanse: Set<String> = []

    private var risultati: [DomandaFrequente] {
        let trovate = DomandeFrequenti.tutte.filter { $0.corrisponde(ricerca) }
        guard let aperta, ricerca.isEmpty else { return trovate }
        // Quella richiesta in cima, le altre sotto nell'ordine di sempre.
        return trovate.filter { $0.id == aperta } + trovate.filter { $0.id != aperta }
    }

    var body: some View {
        List {
            ForEach(risultati) { domanda in
                DisclosureGroup(isExpanded: espansa(domanda.id)) {
                    Text(domanda.risposta)
                        .font(.subheadline)
                        .foregroundStyle(Tema.testoChiaro)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                } label: {
                    Text(domanda.domanda)
                        .fontWeight(.semibold)
                        .foregroundStyle(Tema.testo)
                        .padding(.vertical, 4)
                }
                .listRowBackground(Tema.pannello)
            }
            if risultati.isEmpty {
                Text("Nessuna risposta per «\(ricerca)». Prova con un'altra parola, oppure usa «Segnala un bug».")
                    .font(.subheadline)
                    .foregroundStyle(Tema.testoSecondario)
                    .listRowBackground(Tema.pannello)
            }
        }
        .tint(Tema.ciano)
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .searchable(text: $ricerca, prompt: "Cerca tra le domande")
        .onAppear {
            if let aperta { espanse.insert(aperta) }
        }
    }

    private func espansa(_ id: String) -> Binding<Bool> {
        Binding(get: { espanse.contains(id) },
                set: { valore in
                    if valore { espanse.insert(id) } else { espanse.remove(id) }
                })
    }
}

/// Le domande frequenti in un foglio, aperte su una risposta: da un errore in «In onda» o da una diagnosi.
struct FoglioDomande: View {
    let aperta: String
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        NavigationStack {
            VistaDomandeFrequenti(aperta: aperta)
                .navigationTitle("Domande frequenti")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { chiudi() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .tint(Tema.ciano)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    FoglioDomande(aperta: "cavo")
}
