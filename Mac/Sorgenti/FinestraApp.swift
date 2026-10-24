import AppKit
import Darwin
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Le schede della finestra «App e assistenza» (0.12).
enum SchedaApp: String, CaseIterable, Identifiable {
    case pro, guida, segnala, informazioni

    var id: Self { self }

    var titolo: String {
        switch self {
        case .pro: "Pro e account"
        case .guida: "Guida"
        case .segnala: "Segnala un bug"
        case .informazioni: "Informazioni"
        }
    }

    var simbolo: String {
        switch self {
        case .pro: "star"
        case .guida: "book"
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
                Text("Il video va dall'iPhone al Mac solo sulla tua rete, cifrato: niente passa da Internet.")
                    .foregroundStyle(Tema.testoChiaro)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: InfoApp.privacy) {
                    Label("Privacy", systemImage: "hand.raised")
                }
                Link(destination: InfoApp.sito) {
                    Label("Sito di WebcamLR", systemImage: "safari")
                }
                Text("Una app di LR Apps, come \(InfoApp.altreAppLR.joined(separator: " e ")).")
                    .font(.footnote)
                    .foregroundStyle(Tema.testoSecondario)
                    .padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }
}

/// Apre la finestra «App e assistenza» sulla scheda scelta (dal menu dell'app, da Aiuto e dalla barra in alto).
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
            ("App", "WebcamLR per Mac \(InfoApp.versione)"),
            ("Sistema", "macOS \(sistema.majorVersion).\(sistema.minorVersion).\(sistema.patchVersion)"),
            ("Modello", Self.modelloMac)
        ]
        if let telefono {
            dati.append(("Telefono", "\(Self.nomePiattaforma(telefono.piattaforma)) · app \(telefono.versioneApp)"))
        }
        dati.append(("Latenza", statistiche.latenzaMs.map { "\($0) ms" } ?? "—"))
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
