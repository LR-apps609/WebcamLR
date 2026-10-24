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

    enum Azione: Equatable {
        case apriImpostazioni
    }

    var titolo: String {
        switch self {
        case .permessoReteLocale: "Serve il permesso «Rete locale»"
        case .senzaWiFi: "Collegati al Wi-Fi o usa il cavo"
        case .reteIsolata(let windows): windows ? "Il PC non risponde" : "La rete tiene separati i dispositivi"
        case .computerVecchio: "Aggiorna WebcamLR sul computer"
        case .nonTrova: "Non trovi il computer?"
        }
    }

    var spiegazione: String {
        switch self {
        case .permessoReteLocale:
            "Senza questo permesso l'iPhone non può vedere il computer. Tocca «Apri Impostazioni» e attiva «Rete locale», poi torna qui."
        case .senzaWiFi:
            "L'iPhone non è su una rete Wi-Fi. Collegalo alla stessa rete del computer, oppure collega il cavo USB e apri WebcamLR sul computer."
        case .reteIsolata(let windows):
            windows
                ? "Il PC si vede ma non accetta il collegamento: di solito è il firewall di Windows. Sul PC consenti WebcamLR per le reti private, oppure usa il cavo USB o l'Hotspot personale dell'iPhone."
                : "Il computer si vede ma non risponde: molte reti di hotel, uffici e scuole non fanno parlare i dispositivi tra loro. Usa il cavo USB, oppure attiva l'Hotspot personale dell'iPhone e collega il computer a quello."
        case .computerVecchio(let nome):
            "Su \(nome) c'è una versione di WebcamLR senza collegamento sicuro. Aggiornala dal sito di WebcamLR, poi tocca «Riprova»."
        case .nonTrova:
            "Apri WebcamLR sul computer e controlla che iPhone e computer siano sulla stessa rete Wi-Fi."
        }
    }

    var azione: Azione? {
        self == .permessoReteLocale ? .apriImpostazioni : nil
    }

    /// L'`id` in `DomandeFrequenti`; `nil` se non c'è una risposta adatta.
    var domanda: String? {
        switch self {
        case .permessoReteLocale: "rete-locale"
        case .senzaWiFi: "cavo"
        case .reteIsolata(let windows): windows ? "firewall" : "rete-ospiti"
        case .computerVecchio: "aggiorna"
        case .nonTrova: "non-trova"
        }
    }

    var simbolo: String {
        switch self {
        case .permessoReteLocale: "lock.shield"
        case .senzaWiFi: "wifi.slash"
        case .reteIsolata: "wifi.exclamationmark"
        case .computerVecchio: "arrow.down.circle"
        case .nonTrova: "questionmark.circle"
        }
    }

    /// Nella lista dei computer: perché non ne compare nessuno. `attesaFinita`: sono passati alcuni secondi
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

/// La diagnosi nella lista dei computer: titolo, spiegazione, azione e risposta.
struct SchedaDiagnosi: View {
    let diagnosi: Diagnosi
    let apriDomanda: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: diagnosi.simbolo)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Tema.ambraTesto)
                    .accessibilityHidden(true)
                Text(diagnosi.titolo)
                    .font(.titolo(26))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(diagnosi.spiegazione)
                .font(.subheadline)
                .foregroundStyle(Tema.testoChiaro)
                .fixedSize(horizontal: false, vertical: true)
            AzioniDiagnosi(diagnosi: diagnosi, apriDomanda: apriDomanda)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.ambraTenue, in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(Tema.testo)
        .transition(.opacity)
    }
}

/// L'azione della diagnosi (per ora «Apri Impostazioni») e il link alla risposta.
struct AzioniDiagnosi: View {
    let diagnosi: Diagnosi
    let apriDomanda: (String) -> Void
    @Environment(\.openURL) private var apriIndirizzo

    var body: some View {
        // Sugli iPhone piccoli o con il testo grande uno sotto l'altro, senza troncare.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { pulsanti }
            VStack(alignment: .leading, spacing: 8) { pulsanti }
        }
    }

    @ViewBuilder private var pulsanti: some View {
        if diagnosi.azione == .apriImpostazioni, let impostazioni = URL(string: UIApplication.openSettingsURLString) {
            Button("Apri Impostazioni") { apriIndirizzo(impostazioni) }
                .fontWeight(.semibold)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Tema.ciano, in: Capsule())
                .foregroundStyle(Tema.fondo)
        }
        if let domanda = diagnosi.domanda {
            Button("Perché succede?") { apriDomanda(domanda) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tema.cianoChiaro)
                .frame(minHeight: 40)
        }
    }
}
