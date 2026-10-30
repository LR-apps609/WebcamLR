import AppKit
import Foundation
import Observation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Controlla se c'è una versione nuova di WebcamLR per Mac: all'avvio e ogni 6 ore legge il file pubblico
/// `versione.json` del sito (InfoApp.versioneRecente, il formato è in Documenti/Pubblicazione.md) e lo confronta
/// con la versione e il numero di build dell'app. Niente rete, file assente o sbagliato: non dice niente.
/// Non scarica e non installa nulla: «Scarica» apre la pagina del sito nel browser.
@Observable
@MainActor
final class ControlloAggiornamenti {
    /// Il contenuto di `versione.json`. Solo `versione` è obbligatoria.
    struct Versione: Decodable, Equatable, Identifiable {
        let versione: String
        let build: Int?
        /// «2026-10-25».
        let data: String?
        /// La pagina da aprire con «Scarica».
        let pagina: String?
        /// Le novità, in poche righe.
        let novita: String?

        enum CodingKeys: String, CodingKey {
            case versione, build, data, pagina, novita
        }

        init(versione: String, build: Int?, data: String?, pagina: String?, novita: String?) {
            self.versione = versione
            self.build = build
            self.data = data
            self.pagina = pagina
            self.novita = novita
        }

        /// `build` può arrivare come numero o come testo («3»): vanno bene tutti e due.
        init(from decoder: Decoder) throws {
            let contenitore = try decoder.container(keyedBy: CodingKeys.self)
            versione = try contenitore.decode(String.self, forKey: .versione)
            if let numero = try? contenitore.decode(Int.self, forKey: .build) {
                build = numero
            } else if let testo = try? contenitore.decode(String.self, forKey: .build) {
                build = Int(testo)
            } else {
                build = nil
            }
            data = try? contenitore.decode(String.self, forKey: .data)
            pagina = try? contenitore.decode(String.self, forKey: .pagina)
            novita = try? contenitore.decode(String.self, forKey: .novita)
        }

        /// «1.0.1 (3)».
        var testo: String {
            build.map { "\(versione) (\($0))" } ?? versione
        }

        var id: String { testo }

        /// «25 ottobre 2026» (nella lingua del Mac) da «2026-10-25»; il testo com'è se non è una data.
        var dataLeggibile: String? {
            guard let data else { return nil }
            let lettore = DateFormatter()
            lettore.locale = Locale(identifier: "en_US_POSIX")
            lettore.timeZone = TimeZone(secondsFromGMT: 0)
            lettore.dateFormat = "yyyy-MM-dd"
            guard let giorno = lettore.date(from: data) else { return data }
            var stile = Date.FormatStyle(date: .long, time: .omitted)
            stile.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            return giorno.formatted(stile)
        }

        /// La pagina da aprire: quella del file, altrimenti la pagina di download del sito.
        var indirizzo: URL {
            pagina.flatMap { URL(string: $0) } ?? InfoApp.download
        }
    }

    static let condiviso = ControlloAggiornamenti()

    /// Ogni quanto si ricontrolla mentre l'app resta aperta.
    private static let intervallo: Duration = .seconds(6 * 60 * 60)
    private static let chiaveRimandata = "aggiornamentoRimandato"

    /// La versione nuova, se c'è ed è più recente di questa app.
    private(set) var nuova: Versione?
    /// «Più tardi» su questa versione: il pulsante torna solo con una versione ancora più nuova.
    private var rimandata = UserDefaults.standard.string(forKey: ControlloAggiornamenti.chiaveRimandata)
    @ObservationIgnored private var compito: Task<Void, Never>?

    /// Il pulsante «Aggiornamento disponibile» si vede.
    var daMostrare: Versione? {
        guard let nuova, nuova.testo != rimandata else { return nil }
        return nuova
    }

    /// All'avvio dell'app; chiamarla di nuovo non raddoppia nulla.
    func avvia() {
        guard compito == nil else { return }
        compito = Task { [weak self] in
            while !Task.isCancelled {
                let letta = await Self.leggi()
                guard let self, !Task.isCancelled else { return }
                if let letta, Self.piuRecente(letta, diVersione: Self.versioneApp, build: Self.buildApp) {
                    self.nuova = letta
                } else if letta != nil {
                    // Il file dice che questa è l'ultima: niente pulsante (anche dopo un aggiornamento).
                    self.nuova = nil
                }
                try? await Task.sleep(for: Self.intervallo)
            }
        }
    }

    /// Com'è andata «Verifica aggiornamenti…».
    enum EsitoVerifica {
        case nuova(Versione)
        case aggiornata
        case nonRaggiungibile
    }

    /// «Verifica aggiornamenti…» (M18): legge subito il file del sito, senza aspettare le 6 ore, e dice sempre com'è
    /// andata. Aggiorna anche il punto sull'«Account».
    func verificaOra() async -> EsitoVerifica {
        guard let letta = await Self.leggi() else { return .nonRaggiungibile }
        if Self.piuRecente(letta, diVersione: Self.versioneApp, build: Self.buildApp) {
            nuova = letta
            return .nuova(letta)
        }
        nuova = nil
        return .aggiornata
    }

    /// «Più tardi»: nasconde il pulsante fino a una versione dopo quella mostrata nel foglio.
    func rimanda(_ versione: Versione) {
        rimandata = versione.testo
        UserDefaults.standard.set(versione.testo, forKey: Self.chiaveRimandata)
    }

    /// «Scarica»: apre nel browser la pagina della versione mostrata nel foglio.
    func scarica(_ versione: Versione) {
        NSWorkspace.shared.open(versione.indirizzo)
    }

    // MARK: - Lettura e confronto

    static var versioneApp: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildApp: Int {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) } ?? 0
    }

    /// Il file del sito, senza cache; nil per qualsiasi errore (rete, 404, contenuto sbagliato).
    nonisolated private static func leggi() async -> Versione? {
        var richiesta = URLRequest(url: InfoApp.versioneRecente, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        richiesta.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let risultato = try? await URLSession.shared.data(for: richiesta),
              (risultato.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Versione.self, from: risultato.0)
    }

    /// Prima la versione, numero per numero («1.10» viene dopo «1.9», «1.0» è uguale a «1.0.0»), poi la build.
    nonisolated static func piuRecente(_ letta: Versione, diVersione versione: String, build: Int) -> Bool {
        let confronto = confronta(letta.versione, versione)
        if confronto != 0 { return confronto > 0 }
        guard let nuovaBuild = letta.build else { return false }
        return nuovaBuild > build
    }

    /// 1 se `a` è più recente di `b`, -1 se è più vecchia, 0 se sono uguali.
    nonisolated static func confronta(_ a: String, _ b: String) -> Int {
        let numeriA = numeri(a)
        let numeriB = numeri(b)
        for indice in 0..<max(numeriA.count, numeriB.count) {
            let x = indice < numeriA.count ? numeriA[indice] : 0
            let y = indice < numeriB.count ? numeriB[indice] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    /// «1.0.1 (3)» → [1, 0, 1]: solo i numeri prima di uno spazio o di altro testo.
    nonisolated private static func numeri(_ versione: String) -> [Int] {
        let parte = versione.split(separator: " ").first.map(String.init) ?? versione
        return parte.split(separator: ".").map { pezzo in Int(pezzo.prefix { $0.isNumber }) ?? 0 }
    }

    // MARK: - Versione dell'app sul telefono

    /// Quando la versione dell'app sul telefono (`ciao.versioneApp`) e quella del Mac sono diverse in modo che conta:
    /// diversa la prima o la seconda cifra (1.0 e 1.1 sì, 1.0 e 1.0.1 no). Solo per l'iPhone, che ha la stessa
    /// numerazione del Mac (Strumenti/Versione.xcconfig); Android e Windows per ora hanno la loro.
    static func avvisoVersione(_ telefono: Ciao) -> String? {
        guard let confronto = confrontoVersioni(telefono) else { return nil }
        if confronto < 0 {
            return String(localized: "«\(telefono.nome)» ha WebcamLR \(telefono.versioneApp), il Mac \(versioneApp): aggiorna WebcamLR sul telefono.")
        }
        if confronto > 0 {
            return String(localized: "«\(telefono.nome)» ha WebcamLR \(telefono.versioneApp), il Mac \(versioneApp): aggiorna WebcamLR sul Mac.")
        }
        return nil
    }

    /// Passo 7 (mac.md 16): è il Mac da aggiornare (il telefono ha una versione più nuova). Allora l'avviso ha «Scarica».
    static func macDaAggiornare(_ telefono: Ciao) -> Bool {
        (confrontoVersioni(telefono) ?? 0) > 0
    }

    /// Le prime due cifre del telefono contro quelle del Mac: negativo se il telefono è indietro, positivo se è il Mac.
    /// Nil se il telefono non è un iPhone o non dice una versione con i numeri.
    private static func confrontoVersioni(_ telefono: Ciao) -> Int? {
        // Una versione vuota o senza numeri (arriva dalla rete) non dice niente: prima valeva «0» e chiedeva
        // di aggiornare il telefono con «ha WebcamLR , il Mac 1.0».
        guard telefono.piattaforma == .iphone, telefono.versioneApp.first?.isNumber == true else { return nil }
        let telefonoVersione = Array(numeri(telefono.versioneApp).prefix(2))
        let macVersione = Array(numeri(versioneApp).prefix(2))
        return confronta(telefonoVersione.map(String.init).joined(separator: "."),
                         macVersione.map(String.init).joined(separator: "."))
    }

    /// «Scarica» dall'avviso delle versioni: la versione nuova del sito se il controllo l'ha già trovata, altrimenti
    /// la pagina di download.
    func scaricaUltima() {
        NSWorkspace.shared.open(nuova?.indirizzo ?? InfoApp.download)
    }
}

/// Il foglio di «Aggiornamento disponibile»: versione, data, novità, «Scarica» e «Più tardi».
struct FoglioAggiornamento: View {
    let versione: ControlloAggiornamenti.Versione
    let controllo: ControlloAggiornamenti
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        VStack(alignment: .leading, spacing: Spazi.medio) {
            HStack(spacing: Spazi.piccolo) {
                LogoWebcamLR(lato: 40)
                VStack(alignment: .leading, spacing: Spazi.minimo) {
                    Text("Aggiornamento disponibile")
                        .font(.stile(.titoloGrande))
                    Text("WebcamLR \(versione.testo) · ora hai \(ControlloAggiornamenti.versioneApp) (\(ControlloAggiornamenti.buildApp))")
                        .font(.stile(.numeri))
                        .foregroundStyle(Tema.testoSecondario)
                }
            }
            if let data = versione.dataLeggibile {
                Text("Pubblicata il \(data)")
                    .font(.stile(.nota))
                    .foregroundStyle(Tema.testoSecondario)
            }
            if let novita = versione.novita, !novita.isEmpty {
                ScrollView {
                    // Le novità arrivano dal sito, in italiano come il resto del sito.
                    Text(verbatim: novita)
                        .font(.stile(.corpo))
                        .foregroundStyle(Tema.testoChiaro)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
                .padding(Spazi.stretto)
                .background(Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.controllo))
            }
            Text("Si scarica dal sito: chiudi WebcamLR, apri il file scaricato e sostituisci l'app nella cartella Applicazioni.")
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Più tardi") {
                    controllo.rimanda(versione)
                    chiudi()
                }
                .buttonStyle(StileSecondario())
                Button("Scarica") {
                    controllo.scarica(versione)
                    chiudi()
                }
                .buttonStyle(StilePrimario())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spazi.largo)
        .frame(width: 420)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .tint(Tema.accento)
    }
}
