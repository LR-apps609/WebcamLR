import Stile
import SwiftUI

/// I pulsanti dell'assistente nella barra di «In onda»: inquadratura automatica a un tocco e il foglio
/// con tutte le funzioni del volto.
struct PulsantiAssistente: View {
    let sessione: SessioneTelefono
    @State private var mostraFoglio = false

    var body: some View {
        let funzioni = sessione.funzioni
        PulsanteTondo("Inquadratura automatica", icona: "person.crop.rectangle", attivo: funzioni.inquadratura) {
            funzioni.impostaInquadratura(!funzioni.inquadratura)
        }
        .accessibilityValue(funzioni.inquadratura ? "accesa" : "spenta")
        .accessibilityHint("Lo zoom segue il tuo volto nel video inviato al computer")
        PulsanteTondo("Assistente", icona: "face.smiling") {
            mostraFoglio = true
        }
        .sheet(isPresented: $mostraFoglio) {
            FoglioAssistente(sessione: sessione)
        }
    }
}

/// Le funzioni del volto durante la sessione, in un foglio con «Fine».
struct FoglioAssistente: View {
    let sessione: SessioneTelefono
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        let funzioni = sessione.funzioni
        NavigationStack {
            List {
                Section {
                    Toggle("Inquadratura automatica", isOn: Binding(get: { funzioni.inquadratura },
                                                                     set: { funzioni.impostaInquadratura($0) }))
                        .listRowBackground(Tema.pannello)
                    Toggle("Luce sul volto", isOn: Binding(get: { funzioni.luceVolto },
                                                           set: { funzioni.impostaLuceVolto($0) }))
                        .listRowBackground(Tema.pannello)
                } header: {
                    EtichettaSezione("Volto")
                } footer: {
                    Text(TestiAssistente.volto)
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .foregroundStyle(Tema.testo)
            .navigationTitle("Assistente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { chiudi() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Tema.ciano)
        .preferredColorScheme(.dark)
    }
}

/// Le stesse scelte nelle Impostazioni: valgono anche durante la sessione.
struct SezioneAssistente: View {
    @AppStorage(FunzioniVolto.Chiave.inquadratura) private var inquadratura = false
    @AppStorage(FunzioniVolto.Chiave.luceVolto) private var luceVolto = false

    var body: some View {
        Section {
            Toggle("Inquadratura automatica", isOn: $inquadratura)
                .listRowBackground(Tema.pannello)
            Toggle("Luce sul volto", isOn: $luceVolto)
                .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione("Assistente")
        } footer: {
            Text(TestiAssistente.volto)
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }
}

/// Le spiegazioni, uguali nel foglio e nelle Impostazioni.
enum TestiAssistente {
    static let inquadratura = "Inquadratura automatica: lo zoom segue il volto (o tutti i volti) e lo tiene al centro, fino a 1,6×. Si vede nel video sul computer; l'anteprima dell'iPhone resta intera."
    static let luceVolto = "Luce sul volto: l'esposizione si regola sul tuo volto, non sullo sfondo. Con ISO e tempo scelti sul computer o con «AE/AF bloccati» resta tutto com'è."
    static var volto: String { inquadratura + "\n" + luceVolto }
}
