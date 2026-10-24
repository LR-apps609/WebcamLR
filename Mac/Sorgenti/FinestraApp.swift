import AppKit
import Darwin
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Le schede della finestra «App e assistenza» (0.12).
enum SchedaApp: String, CaseIterable, Identifiable {
    case pro, guida, domande, segnala, informazioni

    var id: Self { self }

    var titolo: String {
        switch self {
        case .pro: String(localized: "Pro e account")
        case .guida: String(localized: "Guida")
        case .domande: String(localized: "Domande frequenti")
        case .segnala: String(localized: "Segnala un bug")
        case .informazioni: String(localized: "Informazioni")
        }
    }

    var simbolo: String {
        switch self {
        case .pro: "star"
        case .guida: "book"
        case .domande: "questionmark.bubble"
        case .segnala: "ladybug"
        case .informazioni: "info.circle"
        }
    }
}

/// Sezione App (0.12): WebcamLR Pro, accesso, guida, «Segnala un bug» e informazioni.
/// I contenuti stanno nel pacchetto Stile, uguali sull'iPhone; Windows ha gli stessi testi.
struct FinestraApp: View {
    static let id = "app"

    let ricevitore: Ricevitore
    @AppStorage(Preferenze.schedaApp) private var scheda: SchedaApp = .guida

    var body: some View {
        HStack(spacing: 0) {
            List(SchedaApp.allCases, selection: Binding<SchedaApp?>(
                get: { scheda },
                set: { nuova in if let nuova { scheda = nuova } })) { voce in
                Label(voce.titolo, systemImage: voce.simbolo)
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            Divider().overlay(Tema.lineaTenue)
            dettaglio
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Tema.fondo)
        }
        .frame(minWidth: 720, minHeight: 520)
        .foregroundStyle(Tema.testo)
        .tint(Tema.ciano)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var dettaglio: some View {
        switch scheda {
        case .pro:
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SchedaPro()
                    SchedaAccesso()
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
            }
        case .guida:
            VistaGuida()
        case .domande:
            VistaDomandeFrequenti()
        case .segnala:
            ModuloSegnalazione(datiTecnici: ricevitore.datiTecnici)
        case .informazioni:
            Informazioni()
        }
    }
}

private struct Informazioni: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    LogoWebcamLR(lato: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WebcamLR per Mac")
                            .font(.titolo(26))
                        Text("Versione \(InfoApp.versione)")
                            .font(.numeri(12.5))
                            .foregroundStyle(Tema.testoSecondario)
                            .textSelection(.enabled)
                    }
                }
                Text("Il video va dal telefono al Mac solo sulla tua rete, cifrato: niente passa da Internet.")
                    .foregroundStyle(Tema.testoChiaro)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: InfoApp.privacy) {
                    Label("Privacy", systemImage: "hand.raised")
                }
                Link(destination: InfoApp.sito) {
                    Label("Sito di WebcamLR", systemImage: "safari")
                }
                Text("Un'app di LR Apps, come \(InfoApp.altreAppLR.joined(separator: String(localized: " e ", comment: "Tra i nomi delle altre app di LR Apps"))).")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
                    .padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }
}

/// Le domande frequenti (1.4): tutte quelle di Stile, con la ricerca, senza bisogno di Internet.
/// Gli errori dell'app portano qui con `apriDomandaFrequente`, che apre e mostra la risposta giusta.
private struct VistaDomandeFrequenti: View {
    @AppStorage(Preferenze.domandaFrequente) private var richiesta = ""
    @State private var ricerca = ""
    @State private var aperte: Set<String> = []

    private var trovate: [DomandaFrequente] {
        DomandeFrequenti.tutte.filter { $0.corrisponde(ricerca) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            campoRicerca
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
            ScrollViewReader { lettore in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if trovate.isEmpty {
                            Text("Nessuna risposta per «\(ricerca)». Prova con altre parole, oppure scrivici con «Segnala un bug».")
                                .foregroundStyle(Tema.testoSecondario)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(trovate) { domanda in
                            VoceDomanda(domanda: domanda, aperta: Binding(
                                get: { aperte.contains(domanda.id) },
                                set: { aperta in
                                    if aperta { aperte.insert(domanda.id) } else { aperte.remove(domanda.id) }
                                }))
                            .id(domanda.id)
                        }
                        Link(destination: InfoApp.aiuto) {
                            Label("Altre risposte sul sito", systemImage: "arrow.up.right.square")
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 680, alignment: .leading)
                }
                .onAppear { mostraRichiesta(lettore) }
                .onChange(of: richiesta) { mostraRichiesta(lettore) }
            }
        }
        .background(Tema.fondo)
    }

    private var campoRicerca: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Tema.testoSecondario)
                .accessibilityHidden(true)
            TextField("Cerca: cavo, codice, ritardo…", text: $ricerca)
                .textFieldStyle(.plain)
                .accessibilityLabel("Cerca tra le domande frequenti")
            if !ricerca.isEmpty {
                Button {
                    ricerca = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Tema.testoSecondario)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancella la ricerca")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.lineaTenue))
    }

    /// Arrivati da un errore: si apre quella risposta e la si porta in vista. Poi la richiesta è consumata.
    private func mostraRichiesta(_ lettore: ScrollViewProxy) {
        guard !richiesta.isEmpty else { return }
        let id = richiesta
        richiesta = ""
        ricerca = ""
        aperte.insert(id)
        DispatchQueue.main.async {
            withAnimation { lettore.scrollTo(id, anchor: .top) }
        }
    }
}

/// Una domanda: il titolo sempre visibile, la risposta con un clic.
private struct VoceDomanda: View {
    let domanda: DomandaFrequente
    @Binding var aperta: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $aperta) {
            Text(domanda.risposta)
                .foregroundStyle(Tema.testoChiaro)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text(domanda.domanda)
                .fontWeight(.semibold)
                .foregroundStyle(Tema.testo)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { aperta.toggle() } }
        }
        .padding(12)
        .background(aperta ? Tema.pannello : Tema.pannelloScuro, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tema.lineaTenue))
    }
}

/// Apre le domande frequenti sulla risposta `id` (da `DomandeFrequenti`): così ogni errore porta alla sua spiegazione.
@MainActor
func apriDomandaFrequente(_ id: String, apri: OpenWindowAction) {
    UserDefaults.standard.set(id, forKey: Preferenze.domandaFrequente)
    apriFinestraApp(.domande, apri: apri)
}

/// Apre la finestra «App e assistenza» sulla scheda scelta (dal pulsante «Aiuto» della finestra e da «Informazioni su WebcamLR»).
@MainActor
func apriFinestraApp(_ scheda: SchedaApp, apri: OpenWindowAction) {
    UserDefaults.standard.set(scheda.rawValue, forKey: Preferenze.schedaApp)
    NSApp.activate(ignoringOtherApps: true)
    apri(id: FinestraApp.id)
}

extension Ricevitore {
    /// Per «Segnala un bug»: solo dati tecnici, nessun dato personale (niente nomi né indirizzi).
    var datiTecnici: [(String, String)] {
        let sistema = ProcessInfo.processInfo.operatingSystemVersion
        var dati: [(String, String)] = [
            (String(localized: "App"), String(localized: "WebcamLR per Mac \(InfoApp.versione)")),
            (String(localized: "Sistema"), "macOS \(sistema.majorVersion).\(sistema.minorVersion).\(sistema.patchVersion)"),
            (String(localized: "Modello"), Self.modelloMac)
        ]
        if let telefono {
            dati.append((String(localized: "Telefono"), "\(Self.nomePiattaforma(telefono.piattaforma)) · app \(telefono.versioneApp)"))
        }
        dati.append((String(localized: "Latenza"), statistiche.latenzaMs.map { "\($0) ms" } ?? "—"))
        return dati
    }

    private static func nomePiattaforma(_ piattaforma: Piattaforma) -> String {
        switch piattaforma {
        case .iphone: "iPhone"
        case .android: "Android"
        case .mac: "Mac"
        case .windows: "Windows"
        }
    }

    /// Il modello del Mac, per esempio «Mac14,2» (sysctl hw.model).
    private static let modelloMac: String = {
        var lunghezza = 0
        guard sysctlbyname("hw.model", nil, &lunghezza, nil, 0) == 0, lunghezza > 0 else { return "—" }
        var byte = [CChar](repeating: 0, count: lunghezza)
        guard sysctlbyname("hw.model", &byte, &lunghezza, nil, 0) == 0 else { return "—" }
        return String(cString: byte)
    }()
}
