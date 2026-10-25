import Stile
import SwiftUI

/// Un'app con cui WebcamLR funziona come webcam, per la sezione «App che utilizzano WebcamLR» sotto il video.
/// Con la webcam virtuale attiva ogni scheda dice se l'app la sta usando («In uso», in corallo come «in onda»)
/// o se è pronta: lo sa l'estensione, che legge la firma di chi avvia il video (proprietà «appl», UscitaWebcam).
///
/// Niente loghi ufficiali: sono marchi delle rispettive aziende e per usarli serve il loro permesso (lo chiedono
/// anche le regole dell'App Store). Al loro posto un riquadro neutro con un simbolo SF o l'iniziale, nei colori di Stile.
/// Se arriva il permesso: le immagini vanno in Mac/Risorse/Assets.xcassets, un image set per app (per esempio
/// «LogoZoom»), e qui basta scriverne il nome in `immagine`: `SchedaAppWebcam` la mostra al posto del simbolo.
struct AppCompatibile: Identifiable {
    /// Cosa si vede nel quadratino quando non c'è un'immagine.
    enum Segno {
        case simbolo(String)
        case iniziale(String)
    }

    let id: String
    let nome: String
    let segno: Segno
    /// L'inizio delle firme (identificativi dei pacchetti) dell'app e dei suoi aiutanti: «com.google.Chrome»
    /// vale anche per «com.google.Chrome.helper». Vuoto per «Altra app».
    var firme: [String] = []
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
        // solo il browser, non il sito: per questo Meet e gli altri siti sono una scheda sola.
        AppCompatibile(id: "siti", nome: String(localized: "Google Meet e altri siti"), segno: .simbolo("globe"),
                       firme: ["com.google.Chrome", "com.apple.Safari", "com.apple.WebKit", "org.mozilla.firefox",
                               "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
                               "com.operasoftware.Opera", "com.vivaldi.Vivaldi"]),
        AppCompatibile(id: "photobooth", nome: String(localized: "Photo Booth", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("camera.fill"), firme: ["com.apple.PhotoBooth"])
    ]

    /// Un'app che usa la webcam e non è nell'elenco (o una webcam virtuale di prima, che non dice quale app).
    static let altra = AppCompatibile(id: "altra", nome: String(localized: "Altra app"), segno: .simbolo("app.dashed"))

    /// Le firme di WebcamLR stessa: non contano mai come «app che usa la webcam».
    private static let firmaWebcamLR = "it.lrapps.webcamlr"

    func riconosce(_ firma: String) -> Bool {
        firme.contains { firma.hasPrefix($0) }
    }

    /// Quali schede sono «In uso», dalle firme lette dall'estensione. `altre`: almeno un'app fuori elenco,
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
}

/// Sotto il video: le app che possono usare WebcamLR come videocamera, in schede con lo stato.
/// - webcam virtuale attiva: «In uso» (corallo: per quell'app il video è in onda) o «Pronta» (verde salvia);
/// - webcam virtuale inclusa ma non attiva, o versione senza account: le schede senza stato e una riga onesta
///   su cosa serve, perché nessuna app può ancora vedere il video.
struct SezioneAppWebcam: View {
    /// `AttivazioneFotocamera.disponibile`: la webcam virtuale è inclusa (account sviluppatore a pagamento).
    let webcamDisponibile: Bool
    /// La webcam virtuale è attiva (approvata e installata).
    let webcamAttiva: Bool
    /// `Ricevitore.appWebcam` e `Ricevitore.webcamInUso`.
    let firme: [String]
    let inUso: Bool

    /// Una scheda dell'elenco con il suo stato.
    private struct Voce: Identifiable {
        let app: AppCompatibile
        let inUso: Bool
        var id: String { app.id }
    }

    /// Prima le app in uso, poi le altre nell'ordine dell'elenco; «Altra app» solo quando serve.
    private var schede: [Voce] {
        var inUsoOra = Set<String>()
        var altre = false
        if webcamAttiva {
            let stato = AppCompatibile.inUso(firme: firme, inUso: inUso)
            inUsoOra = stato.schede
            altre = stato.altre
        }
        let tutte = AppCompatibile.tutte.map { Voce(app: $0, inUso: inUsoOra.contains($0.id)) }
        var risultato = tutte.filter { $0.inUso }
        if altre { risultato.append(Voce(app: AppCompatibile.altra, inUso: true)) }
        risultato.append(contentsOf: tutte.filter { !$0.inUso })
        return risultato
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtichettaSezione(String(localized: "App che utilizzano WebcamLR"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(schede) { scheda in
                    SchedaAppWebcam(app: scheda.app, stato: webcamAttiva ? (scheda.inUso ? .inUso : .pronta) : .senzaStato)
                }
            }
            Text(nota)
                .font(.corpo(12.5))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nota: String {
        if !webcamDisponibile {
            return String(localized: "Pronte con la webcam virtuale, che richiede l'account sviluppatore Apple a pagamento. Per ora il video si vede qui.")
        }
        if !webcamAttiva {
            return String(localized: "Attiva la webcam virtuale in «Uscite»: poi queste app possono usare il video.")
        }
        return String(localized: "Nell'app scegli «WebcamLR» come videocamera.")
    }
}

/// Una scheda: il quadratino con il simbolo (o l'iniziale, o l'immagine), il nome e lo stato.
private struct SchedaAppWebcam: View {
    enum Stato {
        case inUso
        case pronta
        case senzaStato
    }

    let app: AppCompatibile
    let stato: Stato

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                segno
                    .frame(width: 24, height: 24)
                    .background(Tema.pannelloChiaro, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
                Text(app.nome)
                    .font(.corpoEvidente(13))
                    .foregroundStyle(Tema.testo)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if stato != .senzaStato {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stato == .inUso ? Tema.tally : Tema.verde)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(stato == .inUso ? String(localized: "In uso") : String(localized: "Pronta"))
                        .font(.etichetta(13))
                        .tracking(0.4)
                        .foregroundStyle(stato == .inUso ? Tema.tallyTesto : Tema.testoSecondario)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stato == .inUso ? Tema.tallyTenue : Tema.pannello, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(stato == .inUso ? Tema.tally.opacity(0.55) : Tema.lineaTenue))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var segno: some View {
        if let immagine = app.immagine {
            Image(immagine)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            switch app.segno {
            case .simbolo(let nome):
                Image(systemName: nome)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.salviaChiara)
            case .iniziale(let lettera):
                Text(verbatim: lettera)
                    .font(.etichetta(15))
                    .foregroundStyle(Tema.salviaChiara)
            }
        }
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
