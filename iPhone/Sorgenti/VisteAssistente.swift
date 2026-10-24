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

/// Sopra il video di «In onda»: i promemoria della postura (P11). Piccolo, non blocca nulla, sparisce da solo
/// o con un tocco.
struct BannerAssistente: View {
    let sessione: SessioneTelefono

    var body: some View {
        if let avviso = sessione.funzioni.avvisoPostura {
            Button {
                withAnimation { sessione.funzioni.nascondiAvviso() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: avviso.icona)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tema.cianoChiaro)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(avviso.titolo)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Tema.testo)
                        Text(avviso.consiglio)
                            .font(.footnote)
                            .foregroundStyle(Tema.testoSecondario)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 420, alignment: .leading)
                .background(Tema.pannello.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Tocca per chiudere")
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
                    NavigationLink {
                        VistaProvaWebcam(sessione: sessione)
                    } label: {
                        Label("Prova la webcam", systemImage: "checkmark.seal")
                    }
                    .listRowBackground(Tema.pannello)
                } footer: {
                    Text("5 secondi per controllare luce, inquadratura, distanza e se l'iPhone è dritto, con le correzioni a un tocco.")
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                }
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
                Section {
                    Toggle("Promemoria della postura", isOn: Binding(get: { funzioni.postura },
                                                                      set: { funzioni.impostaPostura($0) }))
                        .listRowBackground(Tema.pannello)
                } footer: {
                    Text(TestiAssistente.postura)
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
    @AppStorage(FunzioniVolto.Chiave.postura) private var postura = false

    var body: some View {
        Section {
            Toggle("Inquadratura automatica", isOn: $inquadratura)
                .listRowBackground(Tema.pannello)
            Toggle("Luce sul volto", isOn: $luceVolto)
                .listRowBackground(Tema.pannello)
            Toggle("Promemoria della postura", isOn: $postura)
                .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione("Assistente")
        } footer: {
            Text(TestiAssistente.volto + "\n" + TestiAssistente.postura)
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }
}

/// Le spiegazioni, uguali nel foglio e nelle Impostazioni.
enum TestiAssistente {
    static let inquadratura = "Inquadratura automatica: lo zoom segue il volto (o tutti i volti) e lo tiene al centro, fino a 1,6×. Si vede nel video sul computer; l'anteprima dell'iPhone resta intera."
    static let luceVolto = "Luce sul volto: l'esposizione si regola sul tuo volto, non sullo sfondo. Con ISO e tempo scelti sul computer o con «AE/AF bloccati» resta tutto com'è."
    static let postura = "Promemoria della postura: un avviso discreto sull'iPhone se sei molto vicino allo schermo o esci dall'inquadratura mentre sei in onda, al massimo ogni 3 minuti. Sul computer non si vede."
    static var volto: String { inquadratura + "\n" + luceVolto }
}
