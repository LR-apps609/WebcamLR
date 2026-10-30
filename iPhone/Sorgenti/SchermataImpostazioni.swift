import Stile
import SwiftUI
import UIKit

/// I fogli di «In onda» che si aprono dalle Impostazioni durante la sessione: le Impostazioni si chiudono
/// e al loro posto si apre il foglio scelto. Dalla prima prova (27 ottobre) le Impostazioni aprono solo ciò che
/// esiste soltanto sul telefono: la messa a fuoco manuale. Sfondi e logo si scelgono e si caricano dal computer.
enum FoglioSessione: Hashable {
    /// Solo la messa a fuoco (cursore della distanza e «Automatica»), non più tutti i controlli Pro.
    case messaAFuoco
}

/// Impostazioni del telefono (prima prova, 27 ottobre): una lista sola e semplice, solo cose del telefono. Effetti,
/// inquadratura automatica, assistente e controlli della fotocamera si comandano dal computer.
///
/// Ordine: WebcamLR Pro · Video · Fotocamera · Collegamento · Schermo e batteria · Altro. Le stesse aperte da «In onda»
/// e dalla schermata dei computer, in un foglio con «Fine». Dalla lista dei computer valgono dal prossimo
/// collegamento; aperte da «In onda» (P03) la stabilizzazione si applica alla chiusura del foglio
/// (`SessioneTelefono.applicaImpostazioni`), il resto subito. Qualità, fotogrammi e formato si scelgono solo sul
/// computer (decisione di Ledion, 27 ottobre): qui si vede soltanto quello che il telefono manda davvero.
struct SchermataImpostazioni: View {
    @AppStorage("griglia") private var griglia = false
    @AppStorage("livella") private var livella = false
    @AppStorage("oscuraDaSolo") private var oscuraDaSolo = true
    @AppStorage("stabilizzazione") private var stabilizzazione = false
    @AppStorage("riduciSeCaldo") private var riduciSeCaldo = true
    @AppStorage("risparmioBatteria") private var risparmioBatteria = true
    // Le stesse chiavi di `FunzioniVolto` e `GestorePausa`, che seguono `UserDefaults` e mandano lo `stato`.
    @AppStorage(FunzioniVolto.Chiave.postura) private var postura = false
    @AppStorage(GestorePausa.Chiave.facciaInGiu) private var facciaInGiu = true
    /// Interfaccia finale: la strada preferita. La sessione segue `UserDefaults` e lo dice al computer nello `stato`.
    @AppStorage(PreferenzaCollegamento.chiave) private var collegamento: PreferenzaCollegamento = .automatico
    /// G1.2: «Lingua» in diretta chiede prima di aprire le Impostazioni di iOS.
    @State private var domandaImpostazioniIOS = false
    /// Aperte da «In onda»: le righe delle funzioni solo del telefono che aprono un foglio della sessione.
    private let duranteLaSessione: Bool
    /// La sessione aperta, per la qualità che il telefono sta mandando; `nil` dalla lista dei computer.
    private let sessione: SessioneTelefono?
    private let apriFoglio: ((FoglioSessione) -> Void)?
    /// L'ultima latenza misurata, per i dati tecnici di «Segnala un bug».
    private let ultimaLatenzaMs: Int?

    init(duranteLaSessione: Bool = false, sessione: SessioneTelefono? = nil, ultimaLatenzaMs: Int? = nil,
         apriFoglio: ((FoglioSessione) -> Void)? = nil) {
        self.duranteLaSessione = duranteLaSessione
        self.sessione = sessione
        self.ultimaLatenzaMs = ultimaLatenzaMs
        self.apriFoglio = apriFoglio
    }

    private var pro: Bool { NegozioPro.condiviso.attivo }

    /// G1.2: aperte da «In onda» con il video che va: uscire dall'app lo ferma.
    private var inDiretta: Bool {
        duranteLaSessione && sessione?.stato == .collegato
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
        .tint(Tema.accento)
        .scrollContentBackground(.hidden)
        // Le liste sono nostre: Barlow (Documenti/Stile.md, «Barlow o sistema»).
        .font(.stile(.corpo))
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .intestazioneOpaca()
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
                HStack(spacing: Spazi.stretto) {
                    SegnoPro()
                    Text(verbatim: "WebcamLR Pro")
                        .font(.stile(.corpo, .corpoForte))
                    Spacer(minLength: Spazi.stretto)
                    if pro {
                        Label("Attivo", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Tema.accentoChiaro)
                    } else {
                        Text("Sblocca")
                            .font(.stile(.corpo, .corpoForte))
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

    /// 2. La qualità che il telefono manda adesso, in sola lettura (si sceglie sul computer, sopra il video), e la
    /// stabilizzazione, che è solo della fotocamera e il computer non comanda.
    private var sezioneVideo: some View {
        Section {
            LabeledContent("Qualità") {
                VStack(alignment: .trailing, spacing: Spazi.minimo) {
                    Text(verbatim: testoQualitaInviata ?? "—")
                        .foregroundStyle(Tema.testoChiaro)
                    // Se il telefono ha abbassato la qualità chiesta, il perché: così i numeri tornano.
                    if let motivo = motivoRiduzione {
                        Text(verbatim: motivo)
                            .font(.stile(.nota))
                            .foregroundStyle(Tema.testoSecondario)
                    }
                }
                .multilineTextAlignment(.trailing)
            }
            .listRowBackground(Tema.pannello)
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
            if testoQualitaInviata == nil {
                nota(Text("Si sceglie sul computer quando colleghi il telefono."))
            } else if duranteLaSessione {
                nota(Text("La qualità si sceglie sul computer, sopra il video.") + Text(verbatim: " ")
                     + Text("La stabilizzazione cambia quando tocchi «Fine»: il video si ferma per un attimo."))
            } else {
                nota(Text("La qualità si sceglie sul computer, sopra il video."))
            }
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
                pulsante("Messa a fuoco manuale", icona: "camera.aperture", apre: .messaAFuoco)
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
                ModuloSegnalazione(datiTecnici: SchermataApp.datiTecnici(ultimaLatenzaMs: ultimaLatenzaMs),
                                   registro: RegistroCollegamento.condiviso.testo)
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
                // La lingua dell'app si sceglie nelle Impostazioni di iOS (WebcamLR › Lingua). G1.2: in diretta
                // WebcamLR andrebbe in sottofondo e il video si fermerebbe: prima si chiede.
                if inDiretta {
                    domandaImpostazioniIOS = true
                } else {
                    ImpostazioniIOS.apri()
                }
            } label: {
                HStack {
                    Label("Lingua", systemImage: "globe")
                        .foregroundStyle(Tema.testo)
                    Spacer(minLength: Spazi.stretto)
                    Text(lingua)
                        .foregroundStyle(Tema.testoSecondario)
                    Image(systemName: "arrow.up.forward")
                        .font(.stile(.nota, .corpoForte))
                        .foregroundStyle(Tema.testoSecondario)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Apre le impostazioni di iOS per WebcamLR")
            .listRowBackground(Tema.pannello)
            .domandaPrimaDelleImpostazioniIOS(isPresented: $domandaImpostazioniIOS)
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
                .font(.stile(.numeri))
                .foregroundStyle(Tema.testoSecondario)
                .frame(maxWidth: .infinity)
                .padding(.top, Spazi.medio)
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
            .tint(Tema.accento)
            .scrollContentBackground(.hidden)
            // Le liste sono nostre: Barlow (Documenti/Stile.md, «Barlow o sistema»).
            .font(.stile(.corpo))
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
                Spacer(minLength: Spazi.stretto)
                Image(systemName: "chevron.right")
                    .font(.stile(.nota, .corpoForte))
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

    /// Quello che il telefono sta mandando adesso, «1080p · 30 fps · HEVC»; `nil` senza collegamento.
    private var testoQualitaInviata: String? {
        guard let sessione, sessione.stato == .collegato, sessione.larghezza > 0 else { return nil }
        let lato = min(sessione.larghezza, sessione.altezza)
        // Con gli stessi nomi del menu del computer: 720p, 1080p, 4K.
        let nome = lato >= 2160 ? "4K" : "\(lato)p"
        return "\(nome) · \(sessione.fps) fps · \(sessione.codec.nome)"
    }

    /// Perché il telefono manda meno di quanto chiesto dal computer, se è così.
    private var motivoRiduzione: String? {
        guard testoQualitaInviata != nil else { return nil }
        return sessione?.testoRiduzione
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
            .font(.stile(.nota))
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
