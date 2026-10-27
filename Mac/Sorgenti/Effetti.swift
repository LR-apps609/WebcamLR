import Stile
import SwiftUI
import WebcamLRProtocollo

/// Gli effetti del telefono come li mostra il Mac (pacchetto effetti, Documenti/Protocollo.md).
/// I valori arrivano con ogni `stato` del telefono; da qui partono come `comando`.
struct Effetti: Equatable {
    var filtro = Filtri.naturale
    var luminosita = 0.0
    var contrasto = 0.0
    var saturazione = 0.0
    var nitidezza = 0.0
    var sfondo = ModiSfondo.nessuno
    var intensitaSfondo = 0.5
    /// Con lo sfondo sostituito: uno degli `SfondiPronti` o `SfondiPronti.personale` (`stato.immagineSfondo`);
    /// nil finché il telefono non lo dice. Ha la stessa precedenza di `sfondo` (`chiaveSfondo`).
    var immagineSfondo: String?
    var pelle = 0.0
    var inquadratura = false
    var luceVolto = false
    /// Nome e ruolo scritti nei campi; si vedono nel video solo con `scrittaMostrata`.
    var nome = ""
    var ruolo = ""
    var scrittaMostrata = false
    var doppiaVista = false
    var postura = false
    /// Il video inviato è specchiato (`stato.specchia`, Documenti/Protocollo.md › Specchio): lo stesso per il telefono,
    /// per il Mac e per le app. Il Mac non specchia niente per conto suo.
    var specchia = false

    // Le chiavi per l'attesa dei comandi e la precedenza sullo `stato` (Ricevitore.mandaEffetto).
    static let chiaveFiltro = "filtro"
    static let chiaveLuminosita = "luminosita"
    static let chiaveContrasto = "contrasto"
    static let chiaveSaturazione = "saturazione"
    static let chiaveNitidezza = "nitidezza"
    static let chiaveSfondo = "sfondo"
    static let chiaveIntensitaSfondo = "intensitaSfondo"
    static let chiavePelle = "pelle"
    static let chiaveInquadratura = "inquadratura"
    static let chiaveLuceVolto = "luceVolto"
    static let chiaveScritta = "scritta"
    static let chiaveDoppiaVista = "doppiaVista"
    static let chiavePostura = "postura"
    static let chiaveSpecchia = "specchia"

    /// La scritta da mandare: nome vuoto = nessuna scritta.
    var scrittaDaInviare: Scritta {
        let nome = self.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruolo = self.ruolo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scrittaMostrata, !nome.isEmpty else { return .nessuna }
        return Scritta(nome: nome, ruolo: ruolo.isEmpty ? nil : ruolo)
    }

    /// Il nome mostrato di un filtro; gli identificativi sono fissi nel protocollo.
    static func nomeFiltro(_ filtro: String) -> String {
        switch filtro {
        case Filtri.naturale: String(localized: "Naturale")
        case Filtri.caldo: String(localized: "Caldo")
        case Filtri.freddo: String(localized: "Freddo")
        case Filtri.luminoso: String(localized: "Luminoso")
        case Filtri.cinema: String(localized: "Cinema")
        case Filtri.vivido: String(localized: "Vivido")
        case Filtri.tenue: String(localized: "Tenue")
        case Filtri.biancoNero: String(localized: "Bianco e nero")
        case Filtri.seppia: String(localized: "Seppia")
        case Filtri.notte: String(localized: "Notte")
        default: filtro.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    /// Il telefono sa fare almeno uno degli effetti (o il gobbo): solo allora compare la sezione.
    static func disponibili(_ capacita: Capacita) -> Bool {
        capacita.filtri?.isEmpty == false || capacita.sfondo == true || capacita.pelle == true
            || capacita.inquadratura == true || capacita.luceVolto == true || capacita.scritta == true
            || capacita.doppiaVista == true || capacita.postura == true || capacita.gobbo == true
    }
}

/// I tre livelli di sfocatura di «Sfondo» sotto il video: Poco (morbido), Medio, Tanto. Ognuno è un'intensità dello sfondo sfocato
/// (`comando.intensitaSfondo`); un clic su «Sfondo» (se l'ultima scelta è la sfocatura) usa l'ultimo scelto (`Preferenze.livelloSfocatura`). Gratis.
enum LivelloSfocatura: String, CaseIterable, Identifiable {
    case poco
    case medio
    case tanto

    var id: String { rawValue }

    var intensita: Double {
        switch self {
        case .poco: 0.25
        case .medio: 0.55
        case .tanto: 1.0
        }
    }

    var nome: String {
        switch self {
        case .poco: String(localized: "Poco")
        case .medio: String(localized: "Medio")
        case .tanto: String(localized: "Tanto")
        }
    }

    /// Il livello più vicino a un'intensità (quella che il telefono conferma in `stato.intensitaSfondo`).
    static func vicino(a intensita: Double) -> LivelloSfocatura {
        allCases.min { abs($0.intensita - intensita) < abs($1.intensita - intensita) } ?? .medio
    }
}

/// Il gobbo preparato sul Mac: testo, velocità e dimensione restano anche senza telefono.
struct GobboComputer: Equatable {
    var testo = ""
    /// Righe al secondo, da 0,5 a 3.
    var velocita = 1.5
    var dimensione = DimensioniGobbo.media
}

/// Nelle sezioni «Effetti» e «Regole fini» del pannello di destra: solo gli effetti che il telefono dichiara
/// in `capacita`. Ogni modifica parte subito come `comando` (i cursori dopo ~100 ms); i valori seguono lo `stato`.
struct ControlliEffetti: View {
    /// Quale parte mostrare: gli effetti, oppure le quattro regolazioni (nelle «Regole fini»).
    enum Parte {
        case effetti
        case regolazioni
    }

    @Bindable var ricevitore: Ricevitore
    let capacita: Capacita
    var parte = Parte.effetti
    @Environment(\.openWindow) private var apriFinestra

    /// WebcamLR Pro: il telefono è gratis. Restano luce sul volto, sfondo sfocato e postura; gli altri comandi
    /// si vedono con il segno «PRO», grigi (`richiedePro`).
    private var bloccato: Bool { ricevitore.bloccoPro }

    var body: some View {
        switch parte {
        case .effetti:
            effetti
        case .regolazioni:
            if let filtri = capacita.filtri, !filtri.isEmpty {
                regolazioni
                    .tint(Tema.ciano)
            }
        }
    }

    private var effetti: some View {
        VStack(alignment: .leading, spacing: 16) {
            if capacita.inquadratura == true || capacita.luceVolto == true {
                VStack(alignment: .leading, spacing: 8) {
                    if capacita.inquadratura == true {
                        interruttore("Inquadratura automatica", valore: \.inquadratura, chiave: Effetti.chiaveInquadratura,
                                     aiuto: "Segue il volto con lo zoom digitale") { Comando(inquadratura: $0) }
                            .richiedePro(bloccato)
                    }
                    if capacita.luceVolto == true {
                        if ricevitore.luceSistema {
                            // La luce del telefono (Effetti video di Apple, «Luce da studio»): accesa, si regola lì.
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle(isOn: .constant(true)) {
                                    Text("Luce del telefono")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .disabled(true)
                                Text("Si regola sul telefono, negli Effetti video di Apple.")
                                    .font(.corpo(12))
                                    .foregroundStyle(Tema.testoSecondario)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .help("Si regola sul telefono, negli Effetti video di Apple.")
                        } else {
                            interruttore("Luce sul volto", valore: \.luceVolto, chiave: Effetti.chiaveLuceVolto,
                                         aiuto: "Esposizione regolata sul volto, anche con una finestra alle spalle") { Comando(luceVolto: $0) }
                        }
                    }
                }
            }
            if let filtri = capacita.filtri, !filtri.isEmpty {
                sceltaFiltro(filtri)
                    .richiedePro(bloccato, segno: false)
            }
            if capacita.sfondo == true {
                sfondo
            }
            if capacita.pelle == true {
                cursore("Ritocco della pelle", valore: \.pelle, intervallo: 0...1, chiave: Effetti.chiavePelle,
                        testo: ricevitore.effetti.pelle < 0.01 ? String(localized: "Spento") : "\(Int((ricevitore.effetti.pelle * 100).rounded()))%") {
                    Comando(pelle: $0)
                }
                .richiedePro(bloccato)
            }
            if capacita.scritta == true {
                scritta
                    .richiedePro(bloccato, segno: false)
            }
            if capacita.doppiaVista == true || capacita.postura == true {
                VStack(alignment: .leading, spacing: 8) {
                    if capacita.doppiaVista == true {
                        interruttore("Volto e scrivania", valore: \.doppiaVista, chiave: Effetti.chiaveDoppiaVista,
                                     aiuto: "Volto e scrivania insieme, con il Grandangolo 0,5× posteriore del telefono: il telefono passa da solo a quell'obiettivo") { Comando(doppiaVista: $0) }
                            .richiedePro(bloccato)
                    }
                    if capacita.postura == true {
                        interruttore("Promemoria della postura", valore: \.postura, chiave: Effetti.chiavePostura,
                                     aiuto: "Avvisi sulla postura, mostrati solo sul telefono") { Comando(postura: $0) }
                    }
                }
            }
            if capacita.gobbo == true {
                Button {
                    apriFinestra(id: FinestraGobbo.id)
                } label: {
                    Label("Gobbo", systemImage: "text.alignleft")
                }
                .help("Un testo che scorre sul telefono, vicino all'obiettivo")
                .richiedePro(bloccato)
            }
        }
        .tint(Tema.ciano)
    }

    // MARK: - Filtro

    /// Una griglia di nomi: due colonne nel pannello largo 280–320 punti, mai oltre il bordo.
    private func sceltaFiltro(_ filtri: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EtichettaSezione(String(localized: "Filtro"))
                if bloccato { SegnoPro() }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(filtri, id: \.self) { filtro in
                    PulsanteFiltro(nome: Effetti.nomeFiltro(filtro), scelto: ricevitore.effetti.filtro == filtro) {
                        ricevitore.effetti.filtro = filtro
                        ricevitore.mandaEffetto(Effetti.chiaveFiltro) { Comando(filtro: $0.filtro) }
                    }
                }
            }
        }
    }

    /// Le quattro regolazioni, da -1 a 1 (0 = neutra). Ognuna parte da sola.
    private var regolazioni: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EtichettaSezione(String(localized: "Regolazioni"))
                if bloccato { SegnoPro() }
                Spacer(minLength: 8)
                Button("Azzera") {
                    ricevitore.azzeraRegolazioni()
                }
                .buttonStyle(.link)
                .font(.corpo(12.5))
                .disabled(ricevitore.effetti.luminosita == 0 && ricevitore.effetti.contrasto == 0
                          && ricevitore.effetti.saturazione == 0 && ricevitore.effetti.nitidezza == 0)
            }
            cursoreRegolazione("Luminosità", valore: \.luminosita, chiave: Effetti.chiaveLuminosita) {
                Comando(regolazioni: Regolazioni(luminosita: $0))
            }
            cursoreRegolazione("Contrasto", valore: \.contrasto, chiave: Effetti.chiaveContrasto) {
                Comando(regolazioni: Regolazioni(contrasto: $0))
            }
            cursoreRegolazione("Saturazione", valore: \.saturazione, chiave: Effetti.chiaveSaturazione) {
                Comando(regolazioni: Regolazioni(saturazione: $0))
            }
            cursoreRegolazione("Nitidezza", valore: \.nitidezza, chiave: Effetti.chiaveNitidezza) {
                Comando(regolazioni: Regolazioni(nitidezza: $0))
            }
        }
    }

    private func cursoreRegolazione(_ nome: LocalizedStringKey, valore: WritableKeyPath<Effetti, Double>, chiave: String,
                                    comando: @escaping (Double) -> Comando) -> some View {
        let numero = Int((ricevitore.effetti[keyPath: valore] * 100).rounded())
        return cursore(nome, valore: valore, intervallo: -1...1, chiave: chiave,
                       testo: numero == 0 ? "0" : String(format: "%+ld", numero), comando: comando)
    }

    // MARK: - Sfondo

    private var sfondo: some View {
        VStack(alignment: .leading, spacing: 8) {
            EtichettaSezione(String(localized: "Sfondo"))
            // Segmenti se ci stanno, altrimenti un menu: mai oltre il bordo del pannello.
            ViewThatFits(in: .horizontal) {
                sceltaSfondo
                    .pickerStyle(.segmented)
                sceltaSfondo
                    .pickerStyle(.menu)
            }
            if ricevitore.sfocaturaDelTelefono {
                Text("Sfocatura del telefono: si regola sul telefono, negli Effetti video di Apple.")
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if bloccato {
                // «Sfocato» è gratis; «Sostituito» è di WebcamLR Pro.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SegnoPro()
                    Text("«Sostituito» è di WebcamLR Pro: si sblocca dall'iPhone.")
                        .font(.corpo(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(TestiPro.strada)
            }
            if ricevitore.effetti.sfondo != ModiSfondo.nessuno {
                cursore("Intensità", valore: \.intensitaSfondo, intervallo: 0...1, chiave: Effetti.chiaveIntensitaSfondo,
                        testo: "\(Int((ricevitore.effetti.intensitaSfondo * 100).rounded()))%") {
                    Comando(intensitaSfondo: $0)
                }
                .help(ricevitore.effetti.sfondo == ModiSfondo.sfocato ? "Quanto sfocare lo sfondo"
                      : "Quanto è netto il bordo tra te e lo sfondo")
                if ricevitore.effetti.sfondo == ModiSfondo.sostituito {
                    Text("L'immagine si sceglie dal pulsante «Sfondo» sotto il video.")
                        .font(.corpo(12.5))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sceltaSfondo: some View {
        Picker("Sfondo", selection: Binding(
            get: { ricevitore.effetti.sfondo },
            set: { nuovo in
                // WebcamLR Pro: con un telefono gratis «Sostituito» non parte (il telefono lo ignorerebbe).
                guard !(bloccato && nuovo == ModiSfondo.sostituito) else { return }
                ricevitore.effetti.sfondo = nuovo
                // Con lo sfondo acceso si manda anche l'intensità che si vede qui.
                ricevitore.mandaEffetto(Effetti.chiaveSfondo) { effetti in
                    effetti.sfondo == ModiSfondo.nessuno
                        ? Comando(sfondo: effetti.sfondo)
                        : Comando(sfondo: effetti.sfondo, intensitaSfondo: effetti.intensitaSfondo)
                }
            })) {
            Text("Nessuno").tag(ModiSfondo.nessuno)
            Text("Sfocato").tag(ModiSfondo.sfocato)
            Text("Sostituito").tag(ModiSfondo.sostituito)
        }
        .labelsHidden()
    }

    // MARK: - Scritta

    /// Sottopancia: nome e ruolo, nel video solo con «Mostra la scritta». Mentre si vede, i testi
    /// partono quando si smette di scrivere.
    private var scritta: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                EtichettaSezione(String(localized: "Scritta"))
                if bloccato { SegnoPro() }
            }
            TextField("Nome", text: Binding(
                get: { ricevitore.effetti.nome },
                set: { nuovo in
                    ricevitore.effetti.nome = nuovo
                    testoScrittaCambiato()
                }))
            TextField("Ruolo (facoltativo)", text: Binding(
                get: { ricevitore.effetti.ruolo },
                set: { nuovo in
                    ricevitore.effetti.ruolo = nuovo
                    testoScrittaCambiato()
                }))
            Toggle(isOn: Binding(
                get: { ricevitore.effetti.scrittaMostrata },
                set: { mostra in
                    ricevitore.effetti.scrittaMostrata = mostra
                    ricevitore.mandaEffetto(Effetti.chiaveScritta) { Comando(scritta: $0.scrittaDaInviare) }
                })) {
                Text("Mostra la scritta")
            }
            .disabled(!ricevitore.effetti.scrittaMostrata
                      && ricevitore.effetti.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Nome e ruolo in basso nel video, come in TV")
            // Il logo accanto alla scritta: si carica solo dal Mac, su un telefono che accetta le immagini.
            if capacita.immagini == true {
                HStack(spacing: 8) {
                    Button {
                        SceltaFile.caricaLogo(ricevitore)
                    } label: {
                        Label("Carica logo…", systemImage: "photo.badge.plus")
                    }
                    .help("Un logo PNG accanto alla scritta (meglio con la trasparenza)")
                    if ricevitore.logoSulTelefono {
                        Button("Togli logo") {
                            ricevitore.togliLogo()
                        }
                        .help("Il telefono cancella il logo")
                    }
                }
            }
        }
    }

    private func testoScrittaCambiato() {
        guard ricevitore.effetti.scrittaMostrata else { return }
        if ricevitore.effetti.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Senza nome non c'è scritta: si toglie subito.
            ricevitore.effetti.scrittaMostrata = false
            ricevitore.mandaEffetto(Effetti.chiaveScritta) { _ in Comando(scritta: .nessuna) }
        } else {
            ricevitore.mandaEffetto(Effetti.chiaveScritta, attesa: Ricevitore.attesaTesti) { Comando(scritta: $0.scrittaDaInviare) }
        }
    }

    // MARK: - Componenti

    private func interruttore(_ titolo: LocalizedStringKey, valore: WritableKeyPath<Effetti, Bool>, chiave: String, aiuto: LocalizedStringKey,
                              comando: @escaping (Bool) -> Comando) -> some View {
        Toggle(isOn: Binding(
            get: { ricevitore.effetti[keyPath: valore] },
            set: { nuovo in
                ricevitore.effetti[keyPath: valore] = nuovo
                ricevitore.mandaEffetto(chiave) { comando($0[keyPath: valore]) }
            })) {
            Text(titolo)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(aiuto)
    }

    private func cursore(_ nome: LocalizedStringKey, valore: WritableKeyPath<Effetti, Double>, intervallo: ClosedRange<Double>,
                         chiave: String, testo: String, comando: @escaping (Double) -> Comando) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nome)
                Spacer(minLength: 8)
                Text(testo)
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoTenue)
                    .lineLimit(1)
            }
            Slider(value: Binding(
                get: { ricevitore.effetti[keyPath: valore] },
                set: { nuovo in
                    ricevitore.effetti[keyPath: valore] = nuovo
                    ricevitore.mandaEffetto(chiave, attesa: Ricevitore.attesaCursori) { comando($0[keyPath: valore]) }
                }), in: intervallo, step: 0.05)
            .labelsHidden()
            .accessibilityLabel(nome)
            .accessibilityValue(testo)
        }
    }
}

/// Un filtro nella griglia: scelto nell'accento (selezione), gli altri sul fondo del pannello.
private struct PulsanteFiltro: View {
    let nome: String
    let scelto: Bool
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            Text(nome)
                .font(.corpo(12.5))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .foregroundStyle(scelto ? Tema.cianoChiaro : Tema.testo)
                .background(scelto ? Tema.cianoTenue : Tema.pannello, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(scelto ? Tema.ciano : Tema.lineaTenue))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(scelto ? .isSelected : [])
    }
}

/// Gli effetti come appariranno con un telefono, ma fermi (come `AnteprimaControlliFotocamera`).
struct AnteprimaEffetti: View {
    var parte = ControlliEffetti.Parte.effetti

    var body: some View {
        switch parte {
        case .effetti:
            effetti
        case .regolazioni:
            VStack(alignment: .leading, spacing: 10) {
                EtichettaSezione(String(localized: "Regolazioni"))
                cursore("Luminosità", testo: "0")
                cursore("Contrasto", testo: "0")
                cursore("Saturazione", testo: "0")
                cursore("Nitidezza", testo: "0")
            }
            .tint(Tema.ciano)
        }
    }

    private var effetti: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Inquadratura automatica", isOn: .constant(false))
                Toggle("Luce sul volto", isOn: .constant(false))
            }
            VStack(alignment: .leading, spacing: 6) {
                EtichettaSezione(String(localized: "Filtro"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(Filtri.tutti, id: \.self) { filtro in
                        PulsanteFiltro(nome: Effetti.nomeFiltro(filtro), scelto: filtro == Filtri.naturale) {}
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                EtichettaSezione(String(localized: "Sfondo"))
                Picker("Sfondo", selection: .constant(0)) {
                    Text("Nessuno").tag(0)
                    Text("Sfocato").tag(1)
                    Text("Sostituito").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            cursore("Ritocco della pelle", testo: String(localized: "Spento"))
            VStack(alignment: .leading, spacing: 8) {
                EtichettaSezione(String(localized: "Scritta"))
                TextField("Nome", text: .constant(""))
                TextField("Ruolo (facoltativo)", text: .constant(""))
                Toggle("Mostra la scritta", isOn: .constant(false))
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Volto e scrivania", isOn: .constant(false))
                Toggle("Promemoria della postura", isOn: .constant(false))
            }
            Label("Gobbo", systemImage: "text.alignleft")
        }
        .tint(Tema.ciano)
    }

    private func cursore(_ nome: LocalizedStringKey, testo: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nome)
                Spacer()
                Text(testo)
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoTenue)
            }
            Slider(value: .constant(0))
                .labelsHidden()
        }
    }
}
