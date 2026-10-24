import Stile
import SwiftUI

/// Impostazioni (bozza grafica, iPhone 2). Valgono dal prossimo collegamento.
struct SchermataImpostazioni: View {
    @AppStorage("risoluzione") private var risoluzione = "1080p"
    @AppStorage("fps") private var fps = 30
    @AppStorage("codec") private var codec = "h264"
    @AppStorage("specchia") private var specchia = false
    @AppStorage("microfono") private var microfono = true
    @AppStorage("riduciSeCaldo") private var riduciSeCaldo = true
    @AppStorage("stabilizzazione") private var stabilizzazione = false
    @AppStorage("griglia") private var griglia = false
    @AppStorage("livella") private var livella = false
    @AppStorage("oscuraDaSolo") private var oscuraDaSolo = true
    @AppStorage("risparmioBatteria") private var risparmioBatteria = true

    private struct Profilo: Identifiable {
        let nome: String
        let risoluzione: String
        let fps: Int
        var id: String { nome }
        var sigla: String { "\(risoluzione)\(fps)" }
    }

    private let profili = [
        Profilo(nome: "Riunione", risoluzione: "1080p", fps: 30),
        Profilo(nome: "Streaming", risoluzione: "1080p", fps: 60),
        Profilo(nome: "Ritratto", risoluzione: "4K", fps: 30)
    ]

    var body: some View {
        List {
            Section {
                riga("Risoluzione") {
                    Picker("Risoluzione", selection: $risoluzione) {
                        Text("720p").tag("720p")
                        Text("1080p").tag("1080p")
                        Text("4K").tag("4K")
                    }
                    .labelsHidden()
                }
                riga("Fotogrammi") {
                    Picker("Fotogrammi", selection: $fps) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .labelsHidden()
                }
                riga("Formato") {
                    Picker("Formato", selection: $codec) {
                        Text("H.264").tag("h264")
                        Text("HEVC").tag("hevc")
                    }
                    .labelsHidden()
                }
                riga("Stabilizzazione") {
                    Picker("Stabilizzazione", selection: $stabilizzazione) {
                        Text("Spenta").tag(false)
                        Text("Standard").tag(true)
                    }
                    .labelsHidden()
                }
            } header: {
                EtichettaSezione("Video")
            } footer: {
                Text("HEVC: stessa qualità con meno dati, utile in 4K. Su Windows serve l'estensione HEVC di Microsoft. La stabilizzazione aggiunge un po' di ritardo: spenta è più reattiva.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }

            Section {
                HStack(spacing: 8) {
                    ForEach(profili) { profilo in
                        let scelto = profilo.risoluzione == risoluzione && profilo.fps == fps
                        Button {
                            risoluzione = profilo.risoluzione
                            fps = profilo.fps
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profilo.nome).font(.subheadline.weight(.semibold))
                                Text(profilo.sigla).font(.numeri(11.5)).foregroundStyle(Tema.testoSecondario)
                            }
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(scelto ? Tema.cianoTenue : Tema.pannello, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(scelto ? Tema.ciano : Tema.linea))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(scelto ? .isSelected : [])
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                EtichettaSezione("Profili")
            }

            Section {
                Toggle("Griglia dei terzi", isOn: $griglia)
                    .listRowBackground(Tema.pannello)
                Toggle("Livella", isOn: $livella)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione("Inquadratura")
            } footer: {
                Text("La livella diventa verde quando il telefono è dritto. Si vedono solo sull'iPhone, non nel video.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }

            Section {
                Toggle("Microfono dell'iPhone (dal round 5)", isOn: $microfono)
                    .disabled(true)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione("Audio")
            }

            Section {
                Toggle("Specchia l'immagine inviata", isOn: $specchia)
                    .listRowBackground(Tema.pannello)
                Toggle("Riduci qualità se si scalda", isOn: $riduciSeCaldo)
                    .listRowBackground(Tema.pannello)
                Toggle("Oscura lo schermo dopo 30 secondi senza tocchi", isOn: $oscuraDaSolo)
                    .listRowBackground(Tema.pannello)
                Toggle("Risparmio batteria: 24 fps sotto il 20%", isOn: $risparmioBatteria)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione("Durante l'uso")
            } footer: {
                Text("WebcamLR · versione \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") · italiano")
                    .font(.numeri(12))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
        }
        .tint(Tema.ciano)
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func riga<Valore: View>(_ titolo: String, @ViewBuilder valore: () -> Valore) -> some View {
        LabeledContent(titolo) { valore() }
            .listRowBackground(Tema.pannello)
    }
}
