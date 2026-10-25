import Stile
import SwiftUI

/// I fogli di «In onda» che si aprono dalle Impostazioni durante la sessione: le Impostazioni si chiudono
/// e al loro posto si apre il foglio scelto.
enum FoglioSessione: Hashable {
    case effetti
    case assistente
    case controlliPro
}

/// Impostazioni (bozza grafica, iPhone 2), corte: ciò che riguarda l'iPhone. Profili ed effetti si scelgono sul
/// computer; risoluzione, fotogrammi e formato stanno in «Video avanzato». Dalla lista dei computer valgono dal
/// prossimo collegamento; aperte da «In onda» (P03) il video avanzato si applica alla chiusura del foglio
/// (`SessioneTelefono.applicaImpostazioni`), il resto subito.
struct SchermataImpostazioni: View {
    @AppStorage("griglia") private var griglia = false
    @AppStorage("livella") private var livella = false
    @AppStorage("oscuraDaSolo") private var oscuraDaSolo = true
    @AppStorage("risoluzione") private var risoluzione = "1080p"
    @AppStorage("fps") private var fps = 30
    // Le stesse chiavi di `FunzioniVolto` e `GestorePausa`, che seguono `UserDefaults` e mandano lo `stato`.
    @AppStorage(FunzioniVolto.Chiave.inquadratura) private var inquadratura = false
    @AppStorage(FunzioniVolto.Chiave.postura) private var postura = false
    @AppStorage(GestorePausa.Chiave.facciaInGiu) private var facciaInGiu = true
    /// Aperte da «In onda»: in cima i fogli della sessione (effetti, assistente, controlli Pro).
    private let duranteLaSessione: Bool
    private let apriFoglio: ((FoglioSessione) -> Void)?

    init(duranteLaSessione: Bool = false, apriFoglio: ((FoglioSessione) -> Void)? = nil) {
        self.duranteLaSessione = duranteLaSessione
        self.apriFoglio = apriFoglio
    }

    var body: some View {
        List {
            if duranteLaSessione {
                sezioneSessione
            }

            Section {
                Toggle("Griglia dei terzi", isOn: $griglia)
                    .listRowBackground(Tema.pannello)
                Toggle("Livella", isOn: $livella)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione(String(localized: "Inquadratura"))
            } footer: {
                nota(Text("Solo sull'iPhone, non nel video."))
            }

            Section {
                Toggle("Oscura lo schermo dopo 30 secondi senza tocchi", isOn: $oscuraDaSolo)
                    .listRowBackground(Tema.pannello)
                Toggle("Promemoria postura", isOn: $postura)
                    .listRowBackground(Tema.pannello)
                Toggle("Pausa a faccia in giù", isOn: $facciaInGiu)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione(String(localized: "Durante l'uso"))
            } footer: {
                nota(Text("A faccia in giù il video si ferma senza scollegarsi."))
            }

            Section {
                NavigationLink {
                    VideoAvanzato(duranteLaSessione: duranteLaSessione)
                } label: {
                    Label("Video avanzato", systemImage: "slider.horizontal.3")
                }
                .listRowBackground(Tema.pannello)
                Label("I profili si scelgono sul computer", systemImage: "laptopcomputer")
                    .foregroundStyle(Tema.testoSecondario)
                    .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione(String(localized: "Video"))
            }

            Section {
                NavigationLink {
                    VistaRegistro()
                        .navigationTitle("Registro del collegamento")
                        .navigationBarTitleDisplayMode(.inline)
                        .intestazioneOpaca()
                } label: {
                    Label("Registro del collegamento", systemImage: "list.bullet.rectangle")
                }
                .listRowBackground(Tema.pannello)
            } header: {
                EtichettaSezione(String(localized: "Diagnosi"))
            } footer: {
                // Stessa dicitura della sezione App.
                Text("WebcamLR · versione \(InfoApp.versione)")
                    .font(.numeri(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
        }
        .tint(Tema.ciano)
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .intestazioneOpaca()
        .onAppear {
            // Il 4K va solo a 30 fps: una scelta vecchia a 60 si corregge qui.
            if risoluzione == "4K" && fps > 30 { fps = 30 }
        }
    }

    /// Durante la sessione: gli effetti, l'inquadratura automatica, l'assistente e i controlli Pro, tolti dalla
    /// barra di «In onda».
    private var sezioneSessione: some View {
        Section {
            pulsante("Effetti", icona: "camera.filters", apre: .effetti)
            Toggle(isOn: $inquadratura) {
                Label("Inquadratura automatica", systemImage: "person.crop.rectangle")
            }
            .listRowBackground(Tema.pannello)
            pulsante("Assistente", icona: "face.smiling", apre: .assistente)
            pulsante("Controlli Pro", icona: "camera.aperture", apre: .controlliPro)
        } header: {
            EtichettaSezione(String(localized: "In questa sessione"))
        } footer: {
            nota(Text("Filtri, sfondo, ritocco e scritta stanno in «Effetti»."))
        }
    }

    /// Una riga che chiude le Impostazioni e apre un foglio di «In onda».
    private func pulsante(_ titolo: LocalizedStringKey, icona: String, apre foglio: FoglioSessione) -> some View {
        Button {
            apriFoglio?(foglio)
        } label: {
            HStack {
                Label(titolo, systemImage: icona)
                    .foregroundStyle(Tema.testo)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tema.testoSecondario)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Tema.pannello)
    }

    private func nota(_ testo: Text) -> some View {
        testo
            .font(.footnote)
            .foregroundStyle(Tema.testoSecondario)
    }
}

/// «Video avanzato»: risoluzione, fotogrammi, formato, stabilizzazione, calore e batteria. Il computer può chiedere
/// un altro formato durante la sessione: queste sono le scelte di partenza dell'iPhone.
private struct VideoAvanzato: View {
    let duranteLaSessione: Bool
    @AppStorage("risoluzione") private var risoluzione = "1080p"
    @AppStorage("fps") private var fps = 30
    @AppStorage("codec") private var codec = "h264"
    @AppStorage("stabilizzazione") private var stabilizzazione = false
    @AppStorage("riduciSeCaldo") private var riduciSeCaldo = true
    @AppStorage("risparmioBatteria") private var risparmioBatteria = true

    var body: some View {
        List {
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
                        // Il 4K solo a 30 fps: a 60 scalda e la rete non regge.
                        if risoluzione != "4K" {
                            Text(verbatim: "60 fps").tag(60)
                        }
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
            } footer: {
                Text(duranteLaSessione
                     ? "Si applicano quando tocchi «Fine»: il video si ferma per un attimo."
                     : "Il 4K va a 30 fps e in HEVC. HEVC su Windows chiede l'estensione HEVC di Microsoft.")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
            }

            Section {
                Toggle("Riduci la qualità se si scalda", isOn: $riduciSeCaldo)
                    .listRowBackground(Tema.pannello)
                Toggle("Risparmio batteria: 24 fps sotto il 20%", isOn: $risparmioBatteria)
                    .listRowBackground(Tema.pannello)
            }
        }
        .tint(Tema.ciano)
        .scrollContentBackground(.hidden)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .navigationTitle("Video avanzato")
        .navigationBarTitleDisplayMode(.inline)
        .intestazioneOpaca()
        .onAppear { limita4K() }
        .onChange(of: risoluzione) { _, _ in limita4K() }
    }

    private func limita4K() {
        if risoluzione == "4K" && fps > 30 { fps = 30 }
    }

    private func riga<Valore: View>(_ titolo: LocalizedStringKey, @ViewBuilder valore: () -> Valore) -> some View {
        LabeledContent(titolo) { valore() }
            .listRowBackground(Tema.pannello)
    }
}

extension View {
    /// L'intestazione dei fogli opaca, nel fondo di Stile: il contenuto che scorre non si vede sotto il titolo
    /// e sotto «Fine». Va messa sulla vista dentro il `NavigationStack` (e su ogni pagina spinta).
    func intestazioneOpaca() -> some View {
        toolbarBackground(Tema.fondo, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
