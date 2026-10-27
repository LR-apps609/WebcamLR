import Stile
import SwiftUI
import UIKit

/// I fogli di «In onda» che si aprono dalle Impostazioni durante la sessione: le Impostazioni si chiudono
/// e al loro posto si apre il foglio scelto. Dalla prima prova (27 ottobre) le Impostazioni aprono solo ciò che
/// esiste soltanto sul telefono: la messa a fuoco manuale. Sfondi e logo si scelgono e si caricano dal computer.
enum FoglioSessione: Hashable {
    case controlliPro
}

/// Impostazioni del telefono (prima prova, 27 ottobre): una lista sola e semplice, solo cose del telefono. Effetti,
/// inquadratura automatica, assistente e controlli della fotocamera si comandano dal computer.
///
/// Ordine: WebcamLR Pro · Video · Fotocamera · Collegamento · Schermo e batteria · Altro. Le stesse aperte da «In onda»
/// e dalla schermata dei computer, in un foglio con «Fine». Dalla lista dei computer valgono dal prossimo
/// collegamento; aperte da «In onda» (P03) risoluzione, fotogrammi, formato e stabilizzazione si applicano alla
/// chiusura del foglio (`SessioneTelefono.applicaImpostazioni`), il resto subito.
struct SchermataImpostazioni: View {
    @AppStorage("griglia") private var griglia = false
    @AppStorage("livella") private var livella = false
    @AppStorage("oscuraDaSolo") private var oscuraDaSolo = true
    @AppStorage("risoluzione") private var risoluzione = "1080p"
    @AppStorage("fps") private var fps = 30
    @AppStorage("codec") private var codec = "h264"
    @AppStorage("stabilizzazione") private var stabilizzazione = false
    @AppStorage("riduciSeCaldo") private var riduciSeCaldo = true
    @AppStorage("risparmioBatteria") private var risparmioBatteria = true
    // Le stesse chiavi di `FunzioniVolto` e `GestorePausa`, che seguono `UserDefaults` e mandano lo `stato`.
    @AppStorage(FunzioniVolto.Chiave.postura) private var postura = false
    @AppStorage(GestorePausa.Chiave.facciaInGiu) private var facciaInGiu = true
    /// Interfaccia finale: la strada preferita. La sessione segue `UserDefaults` e lo dice al computer nello `stato`.
    @AppStorage(PreferenzaCollegamento.chiave) private var collegamento: PreferenzaCollegamento = .automatico
    /// La pagina WebcamLR Pro in un foglio, aperta scegliendo una qualità di Pro senza Pro.
    @State private var mostraPro = false
    /// Bug A (seconda prova): le qualità di `capacita.formati`, le stesse che il computer offre.
    @State private var qualita = QualitaTelefono.salvate()
    /// Aperte da «In onda»: le righe delle funzioni solo del telefono che aprono un foglio della sessione.
    private let duranteLaSessione: Bool
    private let apriFoglio: ((FoglioSessione) -> Void)?
    /// L'ultima latenza misurata, per i dati tecnici di «Segnala un bug».
    private let ultimaLatenzaMs: Int?

    init(duranteLaSessione: Bool = false, ultimaLatenzaMs: Int? = nil,
         apriFoglio: ((FoglioSessione) -> Void)? = nil) {
        self.duranteLaSessione = duranteLaSessione
        self.ultimaLatenzaMs = ultimaLatenzaMs
        self.apriFoglio = apriFoglio
    }

    private var pro: Bool { NegozioPro.condiviso.attivo }

    /// Senza Pro si vede (e si invia) 720p; scegliendo 1080p o 4K si apre la pagina Pro e la scelta salvata resta.
    /// Una scelta salvata che l'obiettivo attuale non ha (per esempio il 4K sulla frontale) si vede come la più alta
    /// che c'è (la fotocamera in quel caso scende al 1080p, `Cattura.applica`).
    private var sceltaRisoluzione: Binding<String> {
        Binding(get: {
                    guard pro else { return "720p" }
                    let chiavi = qualita.map(\.chiave)
                    return chiavi.contains(risoluzione) ? risoluzione : (chiavi.last ?? "720p")
                },
                set: { nuova in
                    if pro || nuova == "720p" { risoluzione = nuova } else { mostraPro = true }
                })
    }

    /// I fotogrammi al secondo massimi della qualità che si vede scelta (il 4K a 30).
    private var fpsMassimoScelto: Int {
        qualita.first { $0.chiave == sceltaRisoluzione.wrappedValue }?.fpsMassimo ?? 30
    }

    /// Senza Pro al massimo 30 fps; i 60 aprono la pagina Pro.
    private var sceltaFps: Binding<Int> {
        Binding(get: { pro ? fps : min(fps, LimitiGratis.fps) },
                set: { nuovi in
                    if pro || nuovi <= LimitiGratis.fps { fps = nuovi } else { mostraPro = true }
                })
    }

    var body: some View {
        List {
            sezionePro
            sezioneVideo
            sezioneFotocamera
            sezioneCollegamento
            sezioneSchermoEBatteria
            sezioneAltro
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
            qualita = QualitaTelefono.salvate()
            limitaFps()
        }
        .onChange(of: risoluzione) { _, _ in limitaFps() }
        .sheet(isPresented: $mostraPro) { FoglioPro() }
    }

    // MARK: - Sezioni

    /// 1. Una riga: «WebcamLR Pro» con «Sblocca» o «Attivo ✓», che apre la pagina Pro.
    private var sezionePro: some View {
        Section {
            NavigationLink {
                SchermataPro()
                    .navigationTitle(Text(verbatim: "WebcamLR Pro"))
                    .navigationBarTitleDisplayMode(.inline)
                    .intestazioneOpaca()
            } label: {
                HStack(spacing: 10) {
                    SegnoPro()
                    Text(verbatim: "WebcamLR Pro")
                        .fontWeight(.semibold)
                    Spacer(minLength: 8)
                    if pro {
                        Label("Attivo", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Tema.accentoChiaro)
                    } else {
                        Text("Sblocca")
                            .fontWeight(.semibold)
                            .foregroundStyle(Tema.accento)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione("WebcamLR Pro")
        }
    }

    /// 2. Risoluzione, fotogrammi, formato e stabilizzazione: le scelte di partenza dell'iPhone (il computer può
    /// chiedere un altro formato durante la sessione).
    private var sezioneVideo: some View {
        Section {
            riga("Qualità") {
                // Le stesse del computer, con gli stessi nomi; senza Pro quelle Pro restano in vista, marcate.
                Picker("Qualità", selection: sceltaRisoluzione) {
                    ForEach(qualita) { voce in
                        Text(verbatim: voce.pro && !pro ? voce.chiave + " · PRO" : voce.chiave).tag(voce.chiave)
                    }
                }
                .labelsHidden()
            }
            riga("Fotogrammi") {
                Picker("Fotogrammi", selection: sceltaFps) {
                    Text(verbatim: "24 fps").tag(24)
                    Text(verbatim: "30 fps").tag(30)
                    // Solo se la qualità scelta ci arriva: il 4K va a 30 fps (a 60 scalda e la rete non regge).
                    if fpsMassimoScelto >= 60 {
                        Text(verbatim: pro ? "60 fps" : "60 fps · PRO").tag(60)
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
        } header: {
            EtichettaSezione(String(localized: "Video"))
        } footer: {
            nota(Text(duranteLaSessione
                      ? "Si applicano quando tocchi «Fine»: il video si ferma per un attimo."
                      : "Il 4K va a 30 fps e in HEVC. HEVC su Windows chiede l'estensione HEVC di Microsoft."))
        }
    }

    /// 3. Aiuti per inquadrarsi, solo sull'iPhone.
    private var sezioneFotocamera: some View {
        Section {
            Toggle("Griglia dei terzi", isOn: $griglia)
                .listRowBackground(Tema.pannello)
            Toggle("Livella", isOn: $livella)
                .listRowBackground(Tema.pannello)
            // P16: la posizione della lente non viaggia nel protocollo, si sceglie solo qui.
            if duranteLaSessione {
                pulsante("Messa a fuoco manuale", icona: "camera.aperture", apre: .controlliPro)
            }
        } header: {
            EtichettaSezione(String(localized: "Fotocamera"))
        } footer: {
            nota(Text("Solo sull'iPhone, non nel video."))
        }
    }

    /// 4. La strada preferita, con una frase su cosa fa.
    private var sezioneCollegamento: some View {
        Section {
            Picker(selection: $collegamento) {
                ForEach(PreferenzaCollegamento.allCases) { preferenza in
                    Text(preferenza.testo).tag(preferenza)
                }
            } label: {
                Label("Usa", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione(String(localized: "Collegamento"))
        } footer: {
            nota(testoCollegamento)
        }
    }

    /// 5. Cosa fa il telefono durante l'uso per lo schermo, la batteria e il calore.
    private var sezioneSchermoEBatteria: some View {
        Section {
            Toggle("Oscura lo schermo dopo 30 secondi senza tocchi", isOn: $oscuraDaSolo)
                .listRowBackground(Tema.pannello)
            Toggle("Pausa a faccia in giù", isOn: $facciaInGiu)
                .listRowBackground(Tema.pannello)
            Toggle("Promemoria postura", isOn: $postura)
                .listRowBackground(Tema.pannello)
            Toggle("Riduci la qualità se si scalda", isOn: $riduciSeCaldo)
                .listRowBackground(Tema.pannello)
            Toggle("Risparmio batteria: 24 fps sotto il 20%", isOn: $risparmioBatteria)
                .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione(String(localized: "Schermo e batteria"))
        } footer: {
            nota(Text("A faccia in giù il video si ferma senza scollegarsi."))
        }
    }

    /// 6. Aiuto, segnalazioni, computer conosciuti, lingua, registro e informazioni.
    private var sezioneAltro: some View {
        Section {
            NavigationLink {
                VistaDomandeFrequenti()
                    .navigationTitle("Domande frequenti")
                    .navigationBarTitleDisplayMode(.inline)
                    .intestazioneOpaca()
            } label: {
                Label("Domande frequenti", systemImage: "questionmark.bubble")
            }
            .listRowBackground(Tema.pannello)
            NavigationLink {
                ModuloSegnalazione(datiTecnici: SchermataApp.datiTecnici(ultimaLatenzaMs: ultimaLatenzaMs))
                    .navigationTitle("Segnala un bug")
                    .navigationBarTitleDisplayMode(.inline)
                    .intestazioneOpaca()
            } label: {
                Label("Segnala un bug", systemImage: "ant")
            }
            .listRowBackground(Tema.pannello)
            NavigationLink {
                pagina(Text("Computer conosciuti")) { SezioneComputerConosciuti() }
            } label: {
                Label("Computer conosciuti", systemImage: "laptopcomputer")
            }
            .listRowBackground(Tema.pannello)
            Button {
                // La lingua dell'app si sceglie nelle Impostazioni di iOS (WebcamLR › Lingua).
                if let indirizzo = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(indirizzo)
                }
            } label: {
                HStack {
                    Label("Lingua", systemImage: "globe")
                        .foregroundStyle(Tema.testo)
                    Spacer(minLength: 8)
                    Text(lingua)
                        .foregroundStyle(Tema.testoSecondario)
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Tema.testoSecondario)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Apre le impostazioni di iOS per WebcamLR")
            .listRowBackground(Tema.pannello)
            // Solo sul telefono: gli eventi del collegamento, per capire cosa è successo.
            NavigationLink {
                VistaRegistro()
                    .navigationTitle("Registro del collegamento")
                    .navigationBarTitleDisplayMode(.inline)
                    .intestazioneOpaca()
            } label: {
                Label("Registro del collegamento", systemImage: "list.bullet.rectangle")
            }
            .listRowBackground(Tema.pannello)
            NavigationLink {
                pagina(Text("Informazioni")) { SezioneInformazioni() }
            } label: {
                Label("Informazioni", systemImage: "info.circle")
            }
            .listRowBackground(Tema.pannello)
        } header: {
            EtichettaSezione(String(localized: "Altro"))
        } footer: {
            // Stessa dicitura della sezione App.
            Text("WebcamLR · versione \(InfoApp.versione)")
                .font(.numeri(12))
                .foregroundStyle(Tema.testoSecondario)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
    }

    // MARK: - Pezzi

    /// La lingua in cui l'app si mostra adesso, nel suo nome («Italiano», «English»).
    private var lingua: String {
        let codice = Bundle.main.preferredLocalizations.first ?? "it"
        let nome = Locale(identifier: codice).localizedString(forLanguageCode: codice) ?? codice
        return nome.prefix(1).uppercased() + nome.dropFirst()
    }

    /// Una pagina spinta con una sola sezione (computer conosciuti, informazioni), con lo stile delle Impostazioni.
    private func pagina<Contenuto: View>(_ titolo: Text,
                                         @ViewBuilder contenuto: () -> Contenuto) -> some View {
        List { contenuto() }
            .tint(Tema.ciano)
            .scrollContentBackground(.hidden)
            .background(Tema.fondo)
            .foregroundStyle(Tema.testo)
            .navigationTitle(titolo)
            .navigationBarTitleDisplayMode(.inline)
            .intestazioneOpaca()
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

    private func riga<Valore: View>(_ titolo: LocalizedStringKey, @ViewBuilder valore: () -> Valore) -> some View {
        LabeledContent(titolo) { valore() }
            .listRowBackground(Tema.pannello)
    }

    /// Il 4K va solo a 30 fps (e una qualità può non arrivare a 60): una scelta vecchia a 60 si corregge qui.
    private func limitaFps() {
        if pro && fps > fpsMassimoScelto { fps = 30 }
    }

    /// Cosa fa la scelta, in una frase. La stessa scelta si fa anche dal computer.
    private var testoCollegamento: Text {
        switch collegamento {
        case .automatico:
            Text("Automatico: all'inizio la strada più veloce, poi resta quella. Cambia solo se si stacca o se attacchi il cavo.")
        case .wifi:
            Text("Resta sul Wi-Fi. Se il Wi-Fi si stacca usa il cavo per non perdere il video, poi torna al Wi-Fi.")
        case .cavo:
            Text("Resta sul cavo USB. Se il cavo si stacca usa il Wi-Fi per non perdere il video, poi torna al cavo.")
        }
    }

    private func nota(_ testo: Text) -> some View {
        testo
            .font(.footnote)
            .foregroundStyle(Tema.testoSecondario)
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
