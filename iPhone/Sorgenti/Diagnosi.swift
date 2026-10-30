import Stile
import SwiftUI
import UIKit
import WebcamLRProtocollo

/// Diagnosi automatica (1.3): quando l'iPhone non trova o non raggiunge il computer, la causa più probabile
/// e una sola azione chiara. Ogni diagnosi porta alla sua risposta nelle domande frequenti.
enum Diagnosi: Equatable {
    /// iOS non dà il permesso «Rete locale»: senza, il computer non si vede.
    case permessoReteLocale
    /// Né Wi-Fi né cavo di rete né hotspot: per esempio solo la rete cellulare.
    case senzaWiFi
    /// Il computer si vede ma non risponde: rete che separa i dispositivi, o il firewall di Windows.
    case reteIsolata(windows: Bool)
    /// Il computer parla il protocollo 1.
    case computerVecchio(nome: String)
    /// Nessuna causa precisa: i passi di sempre.
    case nonTrova
    /// G2.3: iOS non dà il permesso «Fotocamera» (rifiutato o tolto in Impostazioni).
    case fotocameraNegata
    /// G2.3: iOS non dà il permesso «Microfono»: il video va, l'audio no.
    case microfonoNegato

    enum Azione: Equatable {
        case apriImpostazioni
        /// G2.4: l'aggiornamento si fa sul computer, quindi il link si manda (AirDrop, Messaggi, Mail).
        case mandaLinkComputer
    }

    var titolo: String {
        switch self {
        case .permessoReteLocale: String(localized: "Serve il permesso «Rete locale»")
        case .senzaWiFi: String(localized: "Collegati al Wi-Fi o usa il cavo")
        case .reteIsolata(let windows):
            windows ? String(localized: "Il PC non risponde") : String(localized: "La rete tiene separati i dispositivi")
        case .computerVecchio: String(localized: "Aggiorna WebcamLR sul computer")
        case .nonTrova: String(localized: "Non trovi il computer?")
        case .fotocameraNegata: String(localized: "Serve il permesso «Fotocamera»")
        case .microfonoNegato: String(localized: "Serve il permesso «Microfono»")
        }
    }

    var spiegazione: String {
        switch self {
        case .permessoReteLocale:
            String(localized: "Senza questo permesso l'iPhone non può vedere il computer. Tocca «Apri Impostazioni» e attiva «Rete locale», poi torna qui.")
        case .senzaWiFi:
            String(localized: "L'iPhone non è su una rete Wi-Fi. Collegalo alla stessa rete del computer, oppure collega il cavo USB e apri WebcamLR sul computer.")
        case .reteIsolata(let windows):
            windows
                ? String(localized: "Il PC si vede ma non accetta il collegamento: di solito è il firewall di Windows. Sul PC consenti WebcamLR per le reti private, oppure usa il cavo USB o l'Hotspot personale dell'iPhone.")
                : String(localized: "Il computer si vede ma non risponde: molte reti di hotel, uffici e scuole non fanno parlare i dispositivi tra loro. Usa il cavo USB, oppure attiva l'Hotspot personale dell'iPhone e collega il computer a quello.")
        case .computerVecchio(let nome):
            String(localized: "Su \(nome) c'è una versione di WebcamLR senza collegamento sicuro. Aggiornala sul computer: con «Mandami il link» ti mandi l'indirizzo per scaricarla. Poi tocca «Riprova».")
        case .nonTrova:
            String(localized: "Apri WebcamLR sul computer e controlla che iPhone e computer siano sulla stessa rete Wi-Fi.")
        case .fotocameraNegata:
            String(localized: "WebcamLR non può usare la fotocamera. Tocca «Apri Impostazioni» e attiva «Fotocamera».")
        case .microfonoNegato:
            String(localized: "Microfono non consentito: il computer non riceve l'audio. Tocca «Apri Impostazioni» e attiva «Microfono».")
        }
    }

    var azione: Azione? {
        switch self {
        case .permessoReteLocale, .fotocameraNegata, .microfonoNegato: .apriImpostazioni
        case .computerVecchio: .mandaLinkComputer
        case .senzaWiFi, .reteIsolata, .nonTrova: nil
        }
    }

    /// L'`id` in `DomandeFrequenti`; `nil` se non c'è una risposta adatta.
    var domanda: String? {
        switch self {
        case .permessoReteLocale: "rete-locale"
        case .senzaWiFi: "cavo"
        case .reteIsolata(let windows): windows ? "firewall" : "rete-ospiti"
        case .computerVecchio: "aggiorna"
        case .nonTrova: "non-trova"
        // Nessuna risposta sui permessi: il testo dice già cosa fare.
        case .fotocameraNegata, .microfonoNegato: nil
        }
    }

    var simbolo: String {
        switch self {
        case .permessoReteLocale: "lock.shield"
        case .senzaWiFi: "wifi.slash"
        case .reteIsolata: "wifi.exclamationmark"
        case .computerVecchio: "arrow.down.circle"
        case .nonTrova: "questionmark.circle"
        case .fotocameraNegata: "video.slash"
        case .microfonoNegato: "mic.slash"
        }
    }

    /// Nella schermata dei computer («Non trovo nessun computer»): perché non ne compare nessuno. `attesaFinita`: sono passati alcuni secondi
    /// di ricerca a vuoto, e allora valgono i passi di sempre.
    @MainActor
    static func ricerca(permessoNegato: Bool, nessunComputer: Bool, attesaFinita: Bool,
                        rete: StatoRete) -> Diagnosi? {
        guard nessunComputer else { return nil }
        if permessoNegato || rete.permessoNegato { return .permessoReteLocale }
        if rete.senzaReteLocale { return .senzaWiFi }
        return attesaFinita ? .nonTrova : nil
    }

    /// Un computer che non risponde dopo tutti i tentativi. `annunciato`: trovato dalla ricerca, quindi acceso
    /// e con WebcamLR aperto; se non risponde, la rete lo tiene separato. `nil` se non c'è una causa più
    /// precisa di «Il computer non risponde» (per esempio dopo essere già stati collegati, o dal QR code).
    @MainActor
    static func collegamento(giaCollegato: Bool, annunciato: Bool, piattaforma: Piattaforma?,
                             rete: StatoRete) -> Diagnosi? {
        if rete.permessoNegato { return .permessoReteLocale }
        if rete.senzaReteLocale { return .senzaWiFi }
        if !giaCollegato && annunciato { return .reteIsolata(windows: piattaforma == .windows) }
        return nil
    }
}

/// L'azione della diagnosi («Apri Impostazioni» o «Mandami il link») e il link alla risposta.
struct AzioniDiagnosi: View {
    let diagnosi: Diagnosi
    /// G1.2: con il video che va, «Apri Impostazioni» chiede prima (uscire dall'app ferma il video). Oggi il pannello
    /// d'errore compare a video già fermo, e allora si apre subito.
    var inDiretta = false
    let apriDomanda: (String) -> Void
    @State private var domandaImpostazioniIOS = false

    var body: some View {
        // Sugli iPhone piccoli o con il testo grande uno sotto l'altro, senza troncare.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { pulsanti }
            VStack(alignment: .leading, spacing: 8) { pulsanti }
        }
        .domandaPrimaDelleImpostazioniIOS(isPresented: $domandaImpostazioniIOS)
    }

    @ViewBuilder private var pulsanti: some View {
        if diagnosi.azione == .apriImpostazioni {
            Button("Apri Impostazioni") {
                if inDiretta { domandaImpostazioniIOS = true } else { ImpostazioniIOS.apri() }
            }
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Tema.ciano, in: Capsule())
                .foregroundStyle(Tema.fondo)
        }
        if diagnosi.azione == .mandaLinkComputer {
            // G2.4: stesso link e stesso messaggio di «Mandami il link per il computer» (fase C della schermata dei computer).
            ShareLink(item: PaginaComputer.collegamento, subject: Text("WebcamLR per il computer"),
                      message: Text("Scarica WebcamLR sul computer")) {
                Text("Mandami il link")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Tema.ciano, in: Capsule())
                    .foregroundStyle(Tema.fondo)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Manda l'indirizzo per scaricare WebcamLR, per esempio con AirDrop o Messaggi"))
        }
        if let domanda = diagnosi.domanda {
            Button("Perché succede?") { apriDomanda(domanda) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tema.cianoChiaro)
                .frame(minHeight: 40)
        }
    }
}
