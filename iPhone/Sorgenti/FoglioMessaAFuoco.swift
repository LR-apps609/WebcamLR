import Stile
import SwiftUI

/// «Messa a fuoco manuale» delle Impostazioni durante la sessione (27 ottobre): solo la messa a fuoco, l'unico
/// controllo della fotocamera che esiste soltanto sul telefono (nel protocollo `fuoco` dice solo «continuo»).
/// ISO, tempo, bianco ed esposizione si comandano dal computer.
///
/// - Il cursore della distanza segue la lente anche in automatico (riletta ogni mezzo secondo); spostarlo passa alla
///   messa a fuoco manuale (`SessioneTelefono.impostaFuocoManuale`), che resta dove la si mette.
/// - «Automatica» torna alla messa a fuoco continua (`fuoco: "continuo"`, la stessa strada del computer).
/// - Con «AE/AF bloccati» la lente resta ferma finché non si sblocca.
/// - WebcamLR Pro: senza, cursore e interruttore si vedono con il segno «PRO» e un tocco apre la pagina Pro.
struct FoglioMessaAFuoco: View {
    let sessione: SessioneTelefono
    @Environment(\.dismiss) private var chiudi
    @State private var mostraPro = false
    /// Limiti e valori della fotocamera, riletti ogni mezzo secondo (cambiano con l'obiettivo e in automatico).
    @State private var lettura: LetturaFotocamera? = nil

    var body: some View {
        NavigationStack {
            List {
                if let lettura {
                    if sessione.aeafBloccati { sezioneBlocco }
                    sezioneFuoco(lettura)
                } else {
                    Text("La fotocamera non è accesa: i controlli compaiono quando riparte il video.")
                        .font(.stile(.corpo))
                        .foregroundStyle(Tema.testoSecondario)
                        .listRowBackground(Tema.pannello)
                }
            }
            .scrollContentBackground(.hidden)
            // Le liste sono nostre: Barlow (Documenti/Stile.md, «Barlow o sistema»).
            .font(.stile(.corpo))
            .background(Tema.fondo)
            .foregroundStyle(Tema.testo)
            .navigationTitle("Messa a fuoco")
            .navigationBarTitleDisplayMode(.inline)
            .intestazioneOpaca()
            .pulsanteFine { chiudi() }
        }
        .tint(Tema.accento)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $mostraPro) { FoglioPro() }
        .task {
            // Anche in automatico la lente si muove di continuo: il cursore la segue.
            while !Task.isCancelled {
                let nuova = sessione.cattura.lettura
                if nuova != lettura { lettura = nuova }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Sezioni

    private var sezioneBlocco: some View {
        Section {
            HStack(spacing: Spazi.stretto) {
                Text("AE/AF bloccati")
                    .font(.stile(.sezione))
                    .tracking(0.6)
                    // Come sopra il video: un'informazione, contornata e non piena.
                    .foregroundStyle(Tema.ambraTesto)
                    .padding(.horizontal, Spazi.stretto)
                    .frame(minHeight: 26)
                    .background(Tema.ambraTenue, in: Capsule())
                    .overlay(Capsule().stroke(Tema.ambra))
                Spacer(minLength: Spazi.stretto)
                Button("Sblocca") { sessione.impostaFuocoManuale(nil) }
                    .buttonStyle(StileLink())
                    .font(.stile(.corpo, .corpoForte))
            }
            .listRowBackground(Tema.pannello)
        } footer: {
            Text("Esposizione e messa a fuoco restano ferme come le hai bloccate. Sblocca per regolarle a mano.")
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    private func sezioneFuoco(_ lettura: LetturaFotocamera) -> some View {
        let possibile = lettura.fuocoManuale && !sessione.aeafBloccati
        let lente = min(max(lettura.posizioneLente, 0), 1)
        let posizione = sessione.posizioneFuoco ?? lente
        let automatica = sessione.posizioneFuoco == nil
        return Section {
            VStack(alignment: .leading, spacing: Spazi.minimo) {
                HStack {
                    Text("Distanza")
                    Spacer(minLength: Spazi.stretto)
                    Text(posizione < 0.5 ? String(localized: "vicino") : String(localized: "lontano"))
                        .font(.stile(.numeri))
                        .foregroundStyle(Tema.accentoChiaro)
                }
                Slider(value: Binding(get: { posizione }, set: { sessione.impostaFuocoManuale($0) }), in: 0...1)
                    .accessibilityLabel("Messa a fuoco")
                    .accessibilityValue("\(Int((posizione * 100).rounded())) per cento verso lontano")
            }
            .disabled(!possibile)
            .soloPro(sessione.pro) { mostraPro = true }
            .listRowBackground(Tema.pannello)
            Toggle("Automatica", isOn: Binding(get: { automatica }, set: { nuova in
                sessione.impostaFuocoManuale(nuova ? nil : lente)
            }))
            // Tornare all'automatica si può sempre; lasciarla solo dove la lente si muove a mano.
            .disabled(automatica && !possibile)
            .soloPro(sessione.pro) { mostraPro = true }
            .listRowBackground(Tema.pannello)
        } header: {
            EtichettaPro(String(localized: "Messa a fuoco"), pro: sessione.pro)
        } footer: {
            Text(lettura.fuocoManuale
                 ? "Manuale: la messa a fuoco resta dove la metti, anche se ti muovi. Un tocco sull'anteprima torna all'automatica."
                 : "Questo obiettivo non permette la messa a fuoco manuale.")
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
        }
    }
}
