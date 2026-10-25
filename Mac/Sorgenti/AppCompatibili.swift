import Stile
import SwiftUI

/// Un'app con cui WebcamLR funziona come webcam, per la sezione «Compatibile con» della finestra principale
/// (si vede finché non c'è un telefono collegato).
///
/// Niente loghi ufficiali: sono marchi delle rispettive aziende e per usarli serve il loro permesso (lo chiedono
/// anche le regole dell'App Store). Al loro posto un riquadro neutro con un simbolo SF o l'iniziale, nei colori di Stile.
/// Se arriva il permesso: le immagini vanno in Mac/Risorse/Assets.xcassets, un image set per app (per esempio
/// «LogoZoom»), e qui basta scriverne il nome in `immagine`: `RiquadroApp` la mostra al posto del simbolo.
struct AppCompatibile: Identifiable {
    /// Cosa si vede nel quadratino quando non c'è un'immagine.
    enum Segno {
        case simbolo(String)
        case iniziale(String)
    }

    let nome: String
    let segno: Segno
    /// Il nome dell'image set in Assets.xcassets, solo con il permesso del proprietario del marchio.
    var immagine: String? = nil

    var id: String { nome }

    /// L'elenco, in un posto solo. I nomi delle app sono marchi: nel catalogo dei testi non si traducono.
    static let tutte: [AppCompatibile] = [
        AppCompatibile(nome: "Zoom", segno: .simbolo("video.fill")),
        AppCompatibile(nome: String(localized: "Google Meet", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("video.bubble.left.fill")),
        AppCompatibile(nome: String(localized: "Microsoft Teams", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("person.3.fill")),
        AppCompatibile(nome: String(localized: "FaceTime", comment: "Nome di un'app: non si traduce"),
                       segno: .iniziale("F")),
        AppCompatibile(nome: String(localized: "WhatsApp", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("phone.bubble.left.fill")),
        AppCompatibile(nome: String(localized: "OBS", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("record.circle")),
        AppCompatibile(nome: String(localized: "Discord", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("headphones")),
        AppCompatibile(nome: String(localized: "Webex", comment: "Nome di un'app: non si traduce"),
                       segno: .iniziale("W")),
        AppCompatibile(nome: String(localized: "Slack", comment: "Nome di un'app: non si traduce"),
                       segno: .simbolo("number")),
        // Nel browser: Meet, Teams e Zoom dal web, e ogni altro sito che chiede la webcam.
        AppCompatibile(nome: String(localized: "Tutti i siti con la webcam"), segno: .simbolo("globe"))
    ]
}

/// Stato vuoto della finestra principale: con quali app funziona WebcamLR, in riquadri calmi che vanno a capo.
/// Sotto, una riga su cosa serve: la webcam virtuale (account a pagamento) o la scelta nell'app.
struct SezioneAppCompatibili: View {
    /// `AttivazioneFotocamera.disponibile`: la webcam virtuale è inclusa (account sviluppatore a pagamento).
    let webcamDisponibile: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EtichettaSezione(String(localized: "Compatibile con"))
            DisposizioneACapo(spaziatura: 6) {
                ForEach(AppCompatibile.tutte) { app in
                    RiquadroApp(app: app)
                }
            }
            Text(webcamDisponibile
                 ? String(localized: "Scegli «WebcamLR» come videocamera nell'app.")
                 : String(localized: "Con la webcam virtuale (richiede l'account sviluppatore Apple)."))
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Un riquadro: il quadratino con il simbolo (o l'iniziale, o l'immagine) e il nome dell'app.
private struct RiquadroApp: View {
    let app: AppCompatibile

    var body: some View {
        HStack(spacing: 7) {
            segno
                .frame(width: 22, height: 22)
                .background(Tema.pannelloChiaro, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            Text(app.nome)
                .font(.callout)
                .foregroundStyle(Tema.testoTenue)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Tema.lineaTenue))
    }

    @ViewBuilder private var segno: some View {
        if let immagine = app.immagine {
            Image(immagine)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            switch app.segno {
            case .simbolo(let nome):
                Image(systemName: nome)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.testoTenue)
            case .iniziale(let lettera):
                Text(verbatim: lettera)
                    .font(.etichetta(14))
                    .foregroundStyle(Tema.testoTenue)
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
