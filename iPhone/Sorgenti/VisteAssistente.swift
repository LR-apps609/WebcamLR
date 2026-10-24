import Stile
import SwiftUI
import WebcamLRProtocollo

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

/// Sopra il video di «In onda»: la pausa (P07, P10) e i promemoria della postura (P11). Piccoli, non bloccano
/// nulla; il promemoria sparisce da solo o con un tocco.
struct BannerAssistente: View {
    let sessione: SessioneTelefono

    var body: some View {
        if sessione.stato == .collegato, let motivo = sessione.pausa.motivo {
            HStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tema.cianoChiaro)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TestiAssistente.titoloPausa(motivo))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tema.testo)
                    Text(TestiAssistente.spiegazionePausa(motivo))
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Tema.pannello.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
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
    // Le stesse chiavi di `FunzioniVolto` e `GestorePausa`, che seguono `UserDefaults` e mandano lo `stato`.
    @AppStorage(FunzioniVolto.Chiave.inquadratura) private var inquadratura = false
    @AppStorage(FunzioniVolto.Chiave.luceVolto) private var luceVolto = false
    @AppStorage(FunzioniVolto.Chiave.postura) private var postura = false
    @AppStorage(GestorePausa.Chiave.facciaInGiu) private var facciaInGiu = true

    var body: some View {
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
                    Toggle("Inquadratura automatica", isOn: $inquadratura)
                        .listRowBackground(Tema.pannello)
                    Toggle("Luce sul volto", isOn: $luceVolto)
                        .listRowBackground(Tema.pannello)
                } header: {
                    EtichettaSezione("Volto")
                } footer: {
                    Text(TestiAssistente.volto)
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                }
                Section {
                    Toggle("Promemoria della postura", isOn: $postura)
                        .listRowBackground(Tema.pannello)
                    Toggle("Pausa a faccia in giù", isOn: $facciaInGiu)
                        .listRowBackground(Tema.pannello)
                } footer: {
                    Text(TestiAssistente.postura + "\n" + TestiAssistente.facciaInGiu)
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
    @AppStorage(GestorePausa.Chiave.facciaInGiu) private var facciaInGiu = true

    var body: some View {
        Section {
            Toggle("Inquadratura automatica", isOn: $inquadratura)
                .listRowBackground(Tema.pannello)
            Toggle("Luce sul volto", isOn: $luceVolto)
                .listRowBackground(Tema.pannello)
            Toggle("Promemoria della postura", isOn: $postura)
                .listRowBackground(Tema.pannello)
            Toggle("Pausa a faccia in giù", isOn: $facciaInGiu)
                .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione("Assistente")
        } footer: {
            Text(TestiAssistente.volto + "\n" + TestiAssistente.postura + "\n" + TestiAssistente.facciaInGiu)
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
    static let facciaInGiu = "Pausa a faccia in giù: appoggia l'iPhone con lo schermo in giù per fermare il video senza scollegarti; giralo per riprendere. Spegnila se usi la fotocamera frontale puntata sulla scrivania."

    static func titoloPausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.facciaInGiu: "In pausa: iPhone a faccia in giù"
        case MotiviPausa.nessunaApp: "In pausa: nessuna app usa la webcam"
        default: "In pausa"
        }
    }

    static func spiegazionePausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.facciaInGiu: "Gira l'iPhone per riprendere il video. Il collegamento resta aperto."
        case MotiviPausa.nessunaApp: "Fotocamera spenta per risparmiare batteria: riparte da sola quando un'app usa la webcam o apri la finestra di WebcamLR sul computer."
        default: "Il collegamento resta aperto."
        }
    }

    static var volto: String { inquadratura + "\n" + luceVolto }
}
