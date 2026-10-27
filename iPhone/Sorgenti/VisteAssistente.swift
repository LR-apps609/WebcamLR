import Stile
import SwiftUI
import WebcamLRProtocollo

/// Sopra il video di «In onda»: la pausa (P07, P10 e il pulsante «Pausa»). È uno stato vero, quindi resta
/// finché la pausa dura; piccola, non blocca nulla.
struct BannerPausa: View {
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
    }
}

/// Il promemoria della postura (P11): sparisce da solo o con un tocco. «In onda» lo mostra solo quando non c'è
/// già un altro avviso: uno alla volta.
struct BannerPostura: View {
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

/// Le funzioni del volto durante la sessione, in un foglio con «Fine» (dalle Impostazioni di «In onda»).
struct FoglioAssistente: View {
    let sessione: SessioneTelefono
    @Environment(\.dismiss) private var chiudi
    // Le stesse chiavi di `FunzioniVolto` e `GestorePausa`, che seguono `UserDefaults` e mandano lo `stato`.
    @AppStorage(FunzioniVolto.Chiave.inquadratura) private var inquadratura = false
    @AppStorage(FunzioniVolto.Chiave.luceVolto) private var luceVolto = false
    @AppStorage(FunzioniVolto.Chiave.postura) private var postura = false
    @AppStorage(GestorePausa.Chiave.facciaInGiu) private var facciaInGiu = true
    /// La pagina WebcamLR Pro: inquadratura automatica e volto + scrivania ne fanno parte.
    @State private var mostraPro = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        VistaProvaWebcam(sessione: sessione)
                            .intestazioneOpaca()
                    } label: {
                        Label("Prova la webcam", systemImage: "checkmark.seal")
                    }
                    .listRowBackground(Tema.pannello)
                } footer: {
                    nota(TestiAssistente.prova)
                }
                Section {
                    Toggle(isOn: $inquadratura) {
                        HStack(spacing: 6) {
                            Text("Inquadratura automatica")
                            if !NegozioPro.condiviso.attivo { SegnoPro() }
                        }
                    }
                    .soloPro(NegozioPro.condiviso.attivo) { mostraPro = true }
                    .listRowBackground(Tema.pannello)
                    Toggle("Luce sul volto", isOn: $luceVolto)
                        .listRowBackground(Tema.pannello)
                } header: {
                    EtichettaSezione(String(localized: "Volto"))
                } footer: {
                    nota(TestiAssistente.volto)
                }
                Section {
                    Toggle("Promemoria postura", isOn: $postura)
                        .listRowBackground(Tema.pannello)
                    Toggle("Pausa a faccia in giù", isOn: $facciaInGiu)
                        .listRowBackground(Tema.pannello)
                } footer: {
                    nota(TestiAssistente.postura)
                }
                SezioneDoppiaVista(sessione: sessione) { mostraPro = true }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .foregroundStyle(Tema.testo)
            .navigationTitle("Assistente")
            .navigationBarTitleDisplayMode(.inline)
            .intestazioneOpaca()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { chiudi() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Tema.ciano)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $mostraPro) { FoglioPro() }
    }

    private func nota(_ testo: String) -> some View {
        Text(testo)
            .font(.footnote)
            .foregroundStyle(Tema.testoSecondario)
    }
}

/// P09: «Volto e scrivania» nel foglio dell'assistente (solo durante la sessione: cambia l'obiettivo).
/// Senza il Grandangolo 0,5× resta solo la riga che lo spiega, niente interruttore grigio.
private struct SezioneDoppiaVista: View {
    let sessione: SessioneTelefono
    /// Senza WebcamLR Pro: apre la pagina Pro.
    let apriPro: () -> Void

    var body: some View {
        let doppia = sessione.doppiaVista
        Section {
            if doppia.disponibile {
                Toggle(isOn: Binding(get: { doppia.attiva }, set: { sessione.impostaDoppiaVista($0) })) {
                    HStack(spacing: 6) {
                        Text("Volto e scrivania")
                        if !sessione.pro { SegnoPro() }
                    }
                }
                .soloPro(sessione.pro || doppia.attiva, apri: apriPro)
                .listRowBackground(Tema.pannello)
                if doppia.attiva {
                    Picker("Disposizione", selection: Binding(get: { doppia.disposizione },
                                                              set: { doppia.impostaDisposizione($0) })) {
                        ForEach(EffettoDoppiaVista.Disposizione.allCases) { disposizione in
                            Text(disposizione.nome).tag(disposizione)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Tema.pannello)
                }
            } else {
                Text(TestiAssistente.doppiaVistaNonDisponibile)
                    .font(.subheadline)
                    .foregroundStyle(Tema.testoSecondario)
                    .listRowBackground(Tema.pannello)
            }
        } header: {
            EtichettaSezione(String(localized: "Volto e scrivania"))
        } footer: {
            if doppia.disponibile {
                Text(TestiAssistente.doppiaVista)
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }
        }
    }
}

/// Le spiegazioni dell'assistente: una riga ciascuna, il resto nella Guida.
enum TestiAssistente {
    static let prova = String(localized: "5 secondi per controllare luce, inquadratura e distanza.")
    static let volto = String(localized: "Lo zoom segue il volto; la luce si regola sul volto, non sullo sfondo.")
    static let postura = String(localized: "Il promemoria si vede solo sull'iPhone; a faccia in giù il video va in pausa.")
    static let doppiaVista = String(localized: "Fotocamera posteriore verso di te: il Grandangolo 0,5× mostra volto e scrivania insieme.")
    static let doppiaVistaNonDisponibile = String(localized: "Volto e scrivania serve il Grandangolo 0,5×, che questo iPhone non ha.")

    static func titoloPausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.facciaInGiu: String(localized: "In pausa: iPhone a faccia in giù")
        case MotiviPausa.nessunaApp: String(localized: "In pausa: nessuna app usa la webcam")
        default: String(localized: "In pausa")
        }
    }

    static func spiegazionePausa(_ motivo: String) -> String {
        switch motivo {
        case MotiviPausa.facciaInGiu: String(localized: "Gira l'iPhone per riprendere il video. Il collegamento resta aperto.")
        case MotiviPausa.nessunaApp: String(localized: "Fotocamera spenta per risparmiare batteria: riparte da sola quando un'app usa la webcam.")
        case MotiviPausa.utente: String(localized: "Tocca ▶ a destra per riprendere. Il collegamento resta aperto.")
        default: String(localized: "Il collegamento resta aperto.")
        }
    }
}
