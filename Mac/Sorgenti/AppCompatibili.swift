import Stile
import SwiftUI

/// Un'app con cui WebcamLR funziona come webcam, per la riga «Disponibile per Zoom · Slack · OBS · Meet e tanti altri»
/// in fondo sotto il video (`RigaAppWebcam`). Con la webcam virtuale attiva la riga dice quale app la sta usando
/// («In uso da Zoom», in corallo come «in onda»): lo sa l'estensione, che legge la firma di chi avvia il video
/// (proprietà «appl», UscitaWebcam).
///
/// Niente loghi ufficiali: sono marchi delle rispettive aziende e per usarli serve il loro permesso (lo chiedono
/// anche le regole dell'App Store). Al loro posto, davanti al nome, un segno neutro (simbolo SF o iniziale) nei colori
/// di Stile. Se arriva il permesso: le immagini vanno in Mac/Risorse/Assets.xcassets, un image set per app (per esempio
/// «LogoZoom», disegnato per stare nel testo: circa 13 × 13 pt, vettoriale), e qui basta scriverne il nome in
/// `immagine`: la riga la mostra al posto del segno.
struct AppCompatibile: Identifiable {
    /// Cosa si vede davanti al nome quando non c'è un'immagine.
    enum Segno {
        case simbolo(String)
        case iniziale(String)
    }

    let id: String
    /// Il nome in «In uso da …».
    let nome: String
    let segno: Segno
    /// L'inizio delle firme (identificativi dei pacchetti) dell'app e dei suoi aiutanti: «com.google.Chrome»
    /// vale anche per «com.google.Chrome.helper».
    var firme: [String] = []
    /// Il nome nella riga «Disponibile per …», se è diverso da `nome` (i siti nel browser: «Meet»).
    var nomeBreve: String? = nil
    /// Il nome dell'image set in Assets.xcassets, solo con il permesso del proprietario del marchio.
    var immagine: String? = nil

    /// L'elenco, in un posto solo. I nomi delle app sono marchi: nel catalogo dei testi non si traducono.
    static let tutte: [AppCompatibile] = [
        AppCompatibile(id: "zoom", nome: "Zoom", segno: .simbolo("video.fill"), firme: ["us.zoom."]),
        AppCompatibile(id: "teams", nome: String(localized: "Microsoft Teams", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("person.3.fill"), firme: ["com.microsoft.teams"]),
        // FaceTime usa la videocamera attraverso un servizio di sistema (avconferenced).
        AppCompatibile(id: "facetime", nome: String(localized: "FaceTime", comment: "Nome di un'app: non si traduce"),
                       segno: .iniziale("F"), firme: ["com.apple.FaceTime", "com.apple.avconferenced"]),
        AppCompatibile(id: "whatsapp", nome: String(localized: "WhatsApp", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("phone.bubble.left.fill"), firme: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]),
        AppCompatibile(id: "obs", nome: String(localized: "OBS", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("record.circle"), firme: ["com.obsproject.obs-studio"]),
        AppCompatibile(id: "discord", nome: String(localized: "Discord", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("headphones"), firme: ["com.hnc.Discord"]),
        AppCompatibile(id: "webex", nome: String(localized: "Webex", comment: "Nome di un'app: non si traduce"),
                       segno: .iniziale("W"), firme: ["Cisco-Systems.Spark", "com.cisco.webex", "com.webex."]),
        AppCompatibile(id: "slack", nome: String(localized: "Slack", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("number"), firme: ["com.tinyspeck.slackmacgap"]),
        // Nel browser: Meet, Teams e Zoom dal web, e ogni altro sito che chiede la webcam. Dalla firma si sa
        // solo il browser, non il sito: per questo «In uso da» dice «un sito nel browser».
        AppCompatibile(id: "siti", nome: String(localized: "un sito nel browser"), segno: .simbolo("globe"),
                       firme: ["com.google.Chrome", "com.apple.Safari", "com.apple.WebKit", "org.mozilla.firefox",
                               "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
                               "com.operasoftware.Opera", "com.vivaldi.Vivaldi"],
                       nomeBreve: String(localized: "Meet", comment: "Google Meet, nome di un servizio: non si traduce")),
        AppCompatibile(id: "photobooth", nome: String(localized: "Photo Booth", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("camera.fill"), firme: ["com.apple.PhotoBooth"])
    ]

    /// Le app nominate nella riga «Disponibile per …», in quest'ordine (le altre sono «e tanti altri»).
    static var inRiga: [AppCompatibile] {
        ["zoom", "slack", "obs", "siti"].compactMap { id in tutte.first { $0.id == id } }
    }

    /// Le firme di WebcamLR stessa: non contano mai come «app che usa la webcam».
    private static let firmaWebcamLR = "it.lrapps.webcamlr"

    func riconosce(_ firma: String) -> Bool {
        firme.contains { firma.hasPrefix($0) }
    }

    /// Quali app dell'elenco sono in uso, dalle firme lette dall'estensione. `altre`: almeno un'app fuori elenco,
    /// oppure un'app la usa ma l'estensione non dice quale (`inUso` vero e nessuna firma).
    static func inUso(firme: [String], inUso: Bool) -> (schede: Set<String>, altre: Bool) {
        var schede = Set<String>()
        var altre = false
        for firma in firme where !firma.hasPrefix(firmaWebcamLR) {
            if let app = tutte.first(where: { $0.riconosce(firma) }) {
                schede.insert(app.id)
            } else {
                altre = true
            }
        }
        if inUso && schede.isEmpty { altre = true }
        return (schede, altre)
    }

    /// Il nome dell'app che usa la webcam, se è una sola e dell'elenco («Zoom», «un sito nel browser»): per la domanda
    /// prima di uscire e per il menu del Dock. Nil con più app, con un'app fuori elenco o senza firme.
    static func nomeUnico(firme: [String]) -> String? {
        let uso = inUso(firme: firme, inUso: true)
        guard uso.schede.count == 1, !uso.altre, let id = uso.schede.first else { return nil }
        return tutte.first { $0.id == id }?.nome
    }

    /// Il segno davanti al nome nella riga, come testo (così la riga resta un testo solo, tradotto con il suo ordine):
    /// l'immagine se c'è il permesso, altrimenti il simbolo o l'iniziale in salvia chiaro.
    var segnoInRiga: Text {
        if let immagine {
            return Text(Image(immagine))
        }
        switch segno {
        case .simbolo(let nome):
            return Text(Image(systemName: nome))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Tema.salviaChiara)
        case .iniziale(let lettera):
            return Text(verbatim: lettera)
                .font(.etichetta(13))
                .foregroundStyle(Tema.salviaChiara)
        }
    }
}

/// In fondo sotto il video (viste Completo ed Essenziale) e in Impostazioni › Uscite: una riga sola, discreta.
/// - di solito «Disponibile per Zoom · Slack · OBS · Meet e tanti altri», ogni nome con il suo segno neutro;
/// - con la webcam virtuale attiva e un'app che la usa: «In uso da Zoom», in corallo come «in onda».
/// Cosa serve per usarla (account a pagamento, attivarla in «Uscite», sceglierla nell'app) sta nel suggerimento
/// della riga; in Uscite (`conAiuto`) anche scritto sotto.
struct RigaAppWebcam: View {
    /// `AttivazioneFotocamera.disponibile`: la webcam virtuale è inclusa (account sviluppatore a pagamento).
    let webcamDisponibile: Bool
    /// La webcam virtuale è attiva (approvata e installata).
    let webcamAttiva: Bool
    /// `Ricevitore.appWebcam` e `Ricevitore.webcamInUso`.
    let firme: [String]
    let inUso: Bool
    /// In Impostazioni › Uscite: sotto la riga anche l'aiuto, scritto.
    var conAiuto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            riga
                .font(.corpo(12.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(aiuto)
                .accessibilityElement(children: .combine)
            if conAiuto {
                Text(aiuto)
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var riga: some View {
        if let testo = testoInUso {
            HStack(spacing: 6) {
                Circle()
                    .fill(Tema.tally)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(testo)
                    .foregroundStyle(Tema.tallyTesto)
            }
        } else {
            Text("Disponibile per \(elenco) e tanti altri")
                .foregroundStyle(Tema.testoSecondario)
        }
    }

    /// Le app della riga, ognuna con il suo segno: «◻ Zoom · ◻ Slack · ◻ OBS · ◻ Meet».
    private var elenco: Text {
        var risultato = Text(verbatim: "")
        for (indice, app) in AppCompatibile.inRiga.enumerated() {
            if indice > 0 { risultato = risultato + Text(verbatim: " · ") }
            risultato = risultato + app.segnoInRiga + Text(verbatim: " " + (app.nomeBreve ?? app.nome))
        }
        return risultato
    }

    /// «In uso da Zoom», «In uso da Zoom · Slack e da altre app», «In uso da un'altra app»; nil se nessuna app la usa.
    private var testoInUso: String? {
        guard webcamAttiva else { return nil }
        let stato = AppCompatibile.inUso(firme: firme, inUso: inUso)
        let nomi = AppCompatibile.tutte.filter { stato.schede.contains($0.id) }.map(\.nome)
        if nomi.isEmpty {
            return stato.altre ? String(localized: "In uso da un'altra app") : nil
        }
        let elenco = nomi.joined(separator: " · ")
        return stato.altre ? String(localized: "In uso da \(elenco) e da altre app") : String(localized: "In uso da \(elenco)")
    }

    private var aiuto: String {
        if !webcamDisponibile {
            return String(localized: "Pronte con la webcam virtuale, che richiede l'account sviluppatore Apple a pagamento. Per ora il video si vede qui.")
        }
        if !webcamAttiva {
            return String(localized: "Attiva la webcam virtuale in «Uscite»: poi queste app possono usare il video.")
        }
        return String(localized: "Nell'app scegli «WebcamLR» come videocamera.")
    }
}

/// Mette le viste una dopo l'altra e va a capo quando la riga è piena, come le parole di un testo.
/// Una vista più larga della riga si stringe (il nome finisce con «…»), mai oltre il bordo.
struct DisposizioneACapo: Layout {
    var spaziatura: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        calcola(subviews, larghezzaMassima: proposal.width ?? .infinity).misura
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let risultato = calcola(subviews, larghezzaMassima: bounds.width)
        for (indice, vista) in subviews.enumerated() {
            let punto = risultato.punti[indice]
            vista.place(at: CGPoint(x: bounds.minX + punto.x, y: bounds.minY + punto.y),
                        anchor: .topLeading, proposal: ProposedViewSize(risultato.misure[indice]))
        }
    }

    /// Dove va ogni vista (in alto a sinistra), quanto è grande e quanto spazio occupano tutte insieme.
    private func calcola(_ subviews: Subviews, larghezzaMassima: CGFloat) -> (punti: [CGPoint], misure: [CGSize], misura: CGSize) {
        var punti: [CGPoint] = []
        var misure: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var altezzaRiga: CGFloat = 0
        var larghezzaUsata: CGFloat = 0
        for vista in subviews {
            var misura = vista.sizeThatFits(.unspecified)
            misura.width = min(misura.width, larghezzaMassima)
            if x > 0 && x + misura.width > larghezzaMassima {
                x = 0
                y += altezzaRiga + spaziatura
                altezzaRiga = 0
            }
            punti.append(CGPoint(x: x, y: y))
            misure.append(misura)
            larghezzaUsata = max(larghezzaUsata, x + misura.width)
            x += misura.width + spaziatura
            altezzaRiga = max(altezzaRiga, misura.height)
        }
        return (punti, misure, CGSize(width: larghezzaUsata, height: y + altezzaRiga))
    }
}
