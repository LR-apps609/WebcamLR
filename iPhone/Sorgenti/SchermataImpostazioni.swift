import Stile
import SwiftUI

/// Impostazioni (bozza grafica, iPhone 2). Dalla lista dei computer valgono dal prossimo collegamento;
/// aperte da «In onda» (P03) si applicano alla chiusura del foglio (`SessioneTelefono.applicaImpostazioni`).
/// Tutto sempre a vista: profili, risoluzione, fotogrammi, formato, stabilizzazione e il registro del collegamento.
struct SchermataImpostazioni: View {
    @AppStorage("risoluzione") private var risoluzione = "1080p"
    @AppStorage("fps") private var fps = 30
    @AppStorage("codec") private var codec = "h264"
    @AppStorage("specchia") private var specchia = false
    @AppStorage("riduciSeCaldo") private var riduciSeCaldo = true
    @AppStorage("stabilizzazione") private var stabilizzazione = false
    @AppStorage("griglia") private var griglia = false
    @AppStorage("livella") private var livella = false
    @AppStorage("oscuraDaSolo") private var oscuraDaSolo = true
    @AppStorage("risparmioBatteria") private var risparmioBatteria = true
    /// Aperte da «In onda»: una riga dice quando valgono le scelte che riavviano la fotocamera.
    private let duranteLaSessione: Bool

    init(duranteLaSessione: Bool = false) {
        self.duranteLaSessione = duranteLaSessione
    }

    private struct Profilo: Identifiable {
        let nome: String
        let risoluzione: String
        let fps: Int
        var id: String { nome }
        var sigla: String { "\(risoluzione)\(fps)" }
    }

    private let profili = [
        Profilo(nome: String(localized: "Riunione"), risoluzione: "1080p", fps: 30),
        Profilo(nome: String(localized: "Dirette"), risoluzione: "1080p", fps: 60),
        Profilo(nome: String(localized: "Ritratto"), risoluzione: "4K", fps: 30)
    ]

    var body: some View {
        List {
            Section {
                // Tre affiancati; con il testo grande (o sugli iPhone piccoli) uno sotto l'altro, senza troncare i nomi.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { schedeProfili }
                    VStack(spacing: 8) { schedeProfili }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                EtichettaSezione(String(localized: "Profili"))
            } footer: {
                if duranteLaSessione {
                    Text("Profilo, risoluzione, fotogrammi, formato, specchio e stabilizzazione si applicano quando tocchi «Fine»: il video si ferma per un attimo.")
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                }
            }

            // Risoluzione, fotogrammi, formato e stabilizzazione, sotto i profili che li scelgono in un tocco.
            sezioneVideo

            Section {
                Toggle("Griglia dei terzi", isOn: $griglia)
                    .listRowBackground(Tema.pannello)
                Toggle("Livella", isOn: $livella)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione(String(localized: "Inquadratura"))
            } footer: {
                Text("La livella diventa verde quando il telefono è dritto. Si vedono solo sull'iPhone, non nel video.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }

            // Inquadratura automatica, luce sul volto, postura e pause (P04–P11).
            SezioneAssistente()

            Section {
                Toggle("Specchia l'immagine inviata", isOn: $specchia)
                    .listRowBackground(Tema.pannello)
                Toggle("Riduci la qualità se si scalda", isOn: $riduciSeCaldo)
                    .listRowBackground(Tema.pannello)
                Toggle("Oscura lo schermo dopo 30 secondi senza tocchi", isOn: $oscuraDaSolo)
                    .listRowBackground(Tema.pannello)
                Toggle("Risparmio batteria: 24 fps sotto il 20%", isOn: $risparmioBatteria)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione(String(localized: "Durante l'uso"))
            }

            Section {
                NavigationLink {
                    VistaRegistro()
                        .navigationTitle("Registro del collegamento")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Registro del collegamento", systemImage: "list.bullet.rectangle")
                }
                .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione(String(localized: "Diagnosi"))
            } footer: {
                VStack(spacing: 24) {
                    Text("Gli ultimi eventi del collegamento con l'ora, per capire cosa è successo. Si apre anche in «In onda».")
                        .font(.footnote)
                        .foregroundStyle(Tema.testoSecondario)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Stessa dicitura della sezione App.
                    Text("WebcamLR · versione \(InfoApp.versione)")
                        .font(.numeri(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .frame(maxWidth: .infinity)
                }
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

    private var schedeProfili: some View {
        ForEach(profili) { profilo in
            let scelto = profilo.risoluzione == risoluzione && profilo.fps == fps
            Button {
                risoluzione = profilo.risoluzione
                fps = profilo.fps
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profilo.nome).font(.subheadline.weight(.semibold)).fixedSize()
                    Text(profilo.sigla).font(.numeri(11.5)).foregroundStyle(Tema.testoSecondario).fixedSize()
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

    private var sezioneVideo: some View {
        Section {
            riga("Risoluzione") {
                Picker("Risoluzione", selection: $risoluzione) {
                    Text(verbatim: "720p").tag("720p")
                    Text(verbatim: "1080p").tag("1080p")
                    Text(verbatim: "4K").tag("4K")
                }
                .labelsHidden()
            }
            riga("Fotogrammi") {
                Picker("Fotogrammi", selection: $fps) {
                    Text(verbatim: "24 fps").tag(24)
                    Text(verbatim: "30 fps").tag(30)
                    Text(verbatim: "60 fps").tag(60)
                }
                .labelsHidden()
            }
            riga("Formato") {
                Picker("Formato", selection: $codec) {
                    Text(verbatim: "H.264").tag("h264")
                    Text(verbatim: "HEVC").tag("hevc")
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
            EtichettaSezione(String(localized: "Video"))
        } footer: {
            Text("HEVC: stessa qualità con meno dati, utile in 4K. Su Windows serve l'estensione HEVC di Microsoft. La stabilizzazione aggiunge un po' di ritardo: spenta è più reattiva.")
                .font(.footnote)
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    private func riga<Valore: View>(_ titolo: LocalizedStringKey, @ViewBuilder valore: () -> Valore) -> some View {
        LabeledContent(titolo) { valore() }
            .listRowBackground(Tema.pannello)
    }
}
