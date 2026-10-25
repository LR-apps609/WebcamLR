import Stile
import SwiftUI
import WebcamLRProtocollo

/// P16 «Controlli Pro»: ISO, tempo, bilanciamento del bianco, compensazione dell'esposizione e messa a fuoco
/// manuale, da «In onda».
///
/// ISO, tempo, bianco ed esposizione passano per `SessioneTelefono.applica(_:)` con un `Comando`, la stessa strada
/// dei comandi del computer (`comando.iso/tempo/bianco/esposizione`): stessi limiti, stessa riapplicazione dopo un
/// cambio di formato. La messa a fuoco manuale è solo del telefono (il protocollo conosce solo «continuo»);
/// «Messa a fuoco automatica» manda proprio `fuoco: "continuo"`. Con «AE/AF bloccati» esposizione manuale e messa a
/// fuoco restano ferme finché non si sbloccano.
struct FoglioControlliPro: View {
    let sessione: SessioneTelefono
    @Environment(\.dismiss) private var chiudi
    /// Limiti e valori della fotocamera, riletti ogni mezzo secondo (cambiano con l'obiettivo e in automatico).
    @State private var lettura: LetturaFotocamera? = nil

    /// Tempi di posa proposti, come denominatori (60 = 1/60 s): si mostrano solo quelli possibili.
    private static let tempiProposti = [3, 4, 6, 8, 10, 15, 20, 24, 25, 30, 40, 50, 60, 80, 100, 120, 125, 160, 200,
                                        250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000,
                                        5000, 6400, 8000]

    var body: some View {
        NavigationStack {
            List {
                if let lettura {
                    sezioneLettura(lettura)
                    if sessione.aeafBloccati { sezioneBlocco }
                    sezioneEsposizione(lettura)
                    sezioneBianco(lettura)
                    sezioneFuoco(lettura)
                } else {
                    Text("La fotocamera non è accesa: i controlli compaiono quando riparte il video.")
                        .font(.subheadline)
                        .foregroundStyle(Tema.testoSecondario)
                        .listRowBackground(Tema.pannello)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .foregroundStyle(Tema.testo)
            .navigationTitle("Controlli Pro")
            .navigationBarTitleDisplayMode(.inline)
            .intestazioneOpaca()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Tutto automatico") { tuttoAutomatico() }
                        .disabled(!qualcosaManuale)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fine") { chiudi() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Tema.ciano)
        .preferredColorScheme(.dark)
        .task {
            // Anche i valori automatici cambiano di continuo: la riga in alto li segue.
            while !Task.isCancelled {
                let nuova = sessione.cattura.lettura
                if nuova != lettura { lettura = nuova }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Sezioni

    private func sezioneLettura(_ lettura: LetturaFotocamera) -> some View {
        Section {
            HStack(spacing: 14) {
                Text(verbatim: "ISO \(Int(lettura.iso.rounded()))")
                Text(Self.testoDurata(lettura.durata))
                if lettura.temperatura > 0 { Text(verbatim: "\(lettura.temperatura) K") }
                Spacer(minLength: 0)
            }
            .font(.numeri(14))
            .foregroundStyle(Tema.testoChiaro)
            .listRowBackground(Tema.pannello)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Adesso: ISO \(Int(lettura.iso.rounded())), tempo \(Self.testoDurata(lettura.durata)), \(lettura.temperatura) kelvin")
        } footer: {
            Text("I valori usati adesso. Al ricollegamento il computer rimanda i suoi.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    private var sezioneBlocco: some View {
        Section {
            HStack(spacing: 10) {
                Text("AE/AF bloccati")
                    .font(.etichetta(15))
                    .tracking(0.6)
                    .foregroundStyle(Tema.fondo)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 26)
                    .background(Tema.ambra, in: Capsule())
                Spacer(minLength: 8)
                Button("Sblocca") { sessione.impostaFuocoManuale(nil) }
                    .fontWeight(.semibold)
            }
            .listRowBackground(Tema.pannello)
        } footer: {
            Text("Esposizione e messa a fuoco restano ferme come le hai bloccate. Sblocca per regolarle a mano.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    private func sezioneEsposizione(_ lettura: LetturaFotocamera) -> some View {
        let bloccata = sessione.aeafBloccati || !lettura.esposizioneManuale
        return Section {
            // ISO
            Toggle("ISO automatico", isOn: Binding(get: { sessione.iso == 0 }, set: { automatico in
                let iniziale = min(max(lettura.iso.rounded(), lettura.isoMinimo), lettura.isoMassimo)
                sessione.applica(Comando(iso: automatico ? 0 : iniziale))
            }))
            .disabled(bloccata)
            .listRowBackground(Tema.pannello)
            if sessione.iso > 0 && lettura.isoMassimo > lettura.isoMinimo {
                rigaCursore(valore: "ISO \(Int(sessione.iso))") {
                    Slider(value: Binding(get: { min(max(sessione.iso, lettura.isoMinimo), lettura.isoMassimo) },
                                          set: { sessione.applica(Comando(iso: $0.rounded())) }),
                           in: lettura.isoMinimo...lettura.isoMassimo)
                    .accessibilityLabel(Text(verbatim: "ISO"))
                    .accessibilityValue(Text(verbatim: "\(Int(sessione.iso))"))
                }
                .disabled(bloccata)
            }
            // Tempo
            let tempi = Self.tempiPossibili(lettura)
            Toggle("Tempo automatico", isOn: Binding(get: { sessione.tempo == 0 }, set: { automatico in
                let attuale = lettura.durata > 0 ? Int((1 / lettura.durata).rounded()) : 60
                sessione.applica(Comando(tempo: automatico ? 0 : Self.piuVicino(attuale, in: tempi)))
            }))
            .disabled(bloccata || tempi.isEmpty)
            .listRowBackground(Tema.pannello)
            if sessione.tempo > 0 && tempi.count > 1 {
                rigaCursore(valore: "1/\(max(sessione.tempo, tempi.first ?? sessione.tempo)) s") {
                    Slider(value: Binding(get: { Double(Self.indice(sessione.tempo, in: tempi)) },
                                          set: { sessione.applica(Comando(tempo: tempi[min(max(Int($0.rounded()), 0), tempi.count - 1)])) }),
                           in: 0...Double(tempi.count - 1), step: 1)
                    .accessibilityLabel("Tempo di posa")
                    .accessibilityValue("1 su \(sessione.tempo) di secondo")
                }
                .disabled(bloccata)
            }
            // Compensazione: vale con l'esposizione automatica (anche con un solo valore manuale non conta).
            rigaCursore(titolo: "Compensazione", valore: Self.testoStop(sessione.esposizione)) {
                Slider(value: Binding(get: { sessione.esposizione },
                                      set: { sessione.applica(Comando(esposizione: ($0 * 10).rounded() / 10)) }),
                       in: lettura.compensazioneMinima...max(lettura.compensazioneMassima, lettura.compensazioneMinima + 0.1))
                .accessibilityLabel("Compensazione dell'esposizione")
                .accessibilityValue(Self.testoStop(sessione.esposizione))
            }
            .disabled(sessione.iso > 0 || sessione.tempo > 0)
        } header: {
            EtichettaSezione(String(localized: "Esposizione"))
        } footer: {
            Text(lettura.esposizioneManuale
                 ? "Il tempo non supera mai la durata di un fotogramma: i fotogrammi al secondo non cambiano. La compensazione vale solo con ISO e tempo automatici."
                 : "Questo obiettivo non permette l'esposizione manuale.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    private func sezioneBianco(_ lettura: LetturaFotocamera) -> some View {
        Section {
            Toggle("Bilanciamento del bianco automatico", isOn: Binding(get: { sessione.bianco == 0 }, set: { automatico in
                let iniziale = lettura.temperatura > 0 ? Int((Double(lettura.temperatura) / 100).rounded()) * 100 : 5000
                sessione.applica(Comando(bianco: automatico ? 0 : min(max(iniziale, 2500), 7500)))
            }))
            .disabled(!lettura.biancoManuale)
            .listRowBackground(Tema.pannello)
            if sessione.bianco > 0 {
                rigaCursore(valore: "\(sessione.bianco) K") {
                    Slider(value: Binding(get: { Double(sessione.bianco) },
                                          set: { sessione.applica(Comando(bianco: Int(($0 / 100).rounded()) * 100)) }),
                           in: 2500...7500, step: 100)
                    .accessibilityLabel("Temperatura del bianco")
                    .accessibilityValue("\(sessione.bianco) kelvin")
                }
            }
        } header: {
            EtichettaSezione(String(localized: "Bilanciamento del bianco"))
        } footer: {
            Text(lettura.biancoManuale
                 ? "Valori bassi per la luce calda delle lampadine (2700 K), alti per la luce del giorno nuvolosa (6500 K)."
                 : "Questo obiettivo non permette il bilanciamento del bianco manuale.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    private func sezioneFuoco(_ lettura: LetturaFotocamera) -> some View {
        let possibile = lettura.fuocoManuale && !sessione.aeafBloccati
        return Section {
            if let posizione = sessione.posizioneFuoco {
                rigaCursore(valore: posizione < 0.5 ? String(localized: "vicino") : String(localized: "lontano")) {
                    Slider(value: Binding(get: { posizione }, set: { sessione.impostaFuocoManuale($0) }), in: 0...1)
                        .accessibilityLabel("Messa a fuoco")
                        .accessibilityValue("\(Int((posizione * 100).rounded())) per cento verso lontano")
                }
                .disabled(!possibile)
                Button("Messa a fuoco automatica") { sessione.impostaFuocoManuale(nil) }
                    .fontWeight(.semibold)
                    .listRowBackground(Tema.pannello)
            } else {
                Button("Messa a fuoco manuale") {
                    sessione.impostaFuocoManuale(min(max(lettura.posizioneLente, 0), 1))
                }
                .fontWeight(.semibold)
                .disabled(!possibile)
                .listRowBackground(Tema.pannello)
            }
        } header: {
            EtichettaSezione(String(localized: "Messa a fuoco"))
        } footer: {
            Text(lettura.fuocoManuale
                 ? "Manuale: la messa a fuoco resta dove la metti, anche se ti muovi. Un tocco sull'anteprima torna all'automatica."
                 : "Questo obiettivo non permette la messa a fuoco manuale.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    /// Un cursore con il valore a destra, come nel foglio «Effetti».
    private func rigaCursore<Cursore: View>(titolo: LocalizedStringKey? = nil, valore: String,
                                            @ViewBuilder cursore: () -> Cursore) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let titolo { Text(titolo) }
                Spacer(minLength: 8)
                Text(valore)
                    .font(.numeri(13))
                    .foregroundStyle(Tema.cianoChiaro)
            }
            cursore()
        }
        .listRowBackground(Tema.pannello)
    }

    // MARK: - Interni

    private var qualcosaManuale: Bool {
        sessione.iso > 0 || sessione.tempo > 0 || sessione.bianco > 0 || sessione.esposizione != 0
            || sessione.posizioneFuoco != nil
    }

    private func tuttoAutomatico() {
        sessione.applica(Comando(esposizione: 0, bianco: 0, iso: 0, tempo: 0))
        if sessione.posizioneFuoco != nil { sessione.impostaFuocoManuale(nil) }
    }

    /// I tempi proposti dentro i limiti dell'obiettivo e del fotogramma.
    private static func tempiPossibili(_ lettura: LetturaFotocamera) -> [Int] {
        tempiProposti.filter { denominatore in
            let durata = 1 / Double(denominatore)
            return durata <= lettura.durataMassima + 0.0001 && durata >= lettura.durataMinima - 0.000_001
        }
    }

    private static func piuVicino(_ denominatore: Int, in tempi: [Int]) -> Int {
        tempi.min { abs($0 - denominatore) < abs($1 - denominatore) } ?? denominatore
    }

    private static func indice(_ denominatore: Int, in tempi: [Int]) -> Int {
        let vicino = piuVicino(denominatore, in: tempi)
        return tempi.firstIndex(of: vicino) ?? 0
    }

    /// «1/60 s», o «0,5 s» per i tempi lunghi (con la virgola o il punto della lingua dell'app).
    static func testoDurata(_ secondi: Double) -> String {
        guard secondi > 0, secondi.isFinite else { return "—" }
        if secondi >= 0.5 { return secondi.formatted(.number.precision(.fractionLength(1))) + " s" }
        return "1/\(Int((1 / secondi).rounded())) s"
    }

    /// «+0,3», «−1,0», «0» (in inglese «+0.3»).
    static func testoStop(_ stop: Double) -> String {
        if abs(stop) < 0.05 { return "0" }
        return stop.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
            .replacingOccurrences(of: "-", with: "−")
    }
}
