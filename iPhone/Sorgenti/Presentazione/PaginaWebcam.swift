import Stile
import SwiftUI

/// Prima pagina, «Il tuo iPhone diventa la webcam»: l'iPhone sul supporto manda il segnale al computer,
/// dove nella videochiamata il tuo riquadro è quello grande. Sul riquadro si trascina una linea per confrontare
/// la webcam del computer (sgranata, scura, morbida) con l'iPhone (nitido e luminoso).
struct PaginaWebcam: View {
    let avanti: () -> Void
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento
    /// Dove sta la linea del confronto, da 0 a 1: a sinistra la webcam del computer, a destra l'iPhone.
    @State private var confine: CGFloat = 0.5
    /// L'utente ha toccato il riquadro: il suggerimento animato si ferma.
    @State private var toccato = false
    @State private var ditoVisibile = false

    var body: some View {
        ImpaginazionePagina {
            scena
        } contenuto: {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Trascina la linea sul tuo riquadro per confrontare.")
                } icon: {
                    Image(systemName: "hand.draw")
                }
                .font(.corpo(14))
                .foregroundStyle(Tema.testoSecondario)
                .accessibilityHidden(true)
                TitoloPresentazione(Text("Il tuo iPhone diventa la webcam"))
                TestoPresentazione(Text("WebcamLR manda il video della fotocamera dell'iPhone al Mac o al PC, per videochiamate, lezioni e dirette. Molto più nitido della webcam del computer, con pochissimo ritardo."))
            }
        } azioni: {
            PulsantePresentazione(titolo: Text("Avanti"), identificatore: "presentazione.avanti.webcam", azione: avanti)
        }
        .task { await suggerimento() }
    }

    // MARK: La scena

    private var scena: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let computer = min(w * 0.84, h * 1.2)
            let altezzaComputer = computer * Proporzioni.portatile
            let telefono = computer * 0.13
            let altezzaTelefono = telefono * (Proporzioni.telefono + Proporzioni.supporto)
            let onde = telefono * 1.8
            ZStack {
                DisegnoPortatile(larghezza: computer) { chiamata }
                    .position(x: w - computer / 2, y: altezzaComputer / 2 + 4)
                TelefonoSuSupporto(larghezza: telefono)
                    .position(x: telefono / 2 + 6, y: h - altezzaTelefono / 2)
                OndeSegnale(direzione: .degrees(-50))
                    .frame(width: onde, height: onde)
                    .position(x: telefono + 8 + onde / 2, y: h - altezzaTelefono + telefono * 0.4 - onde / 2)
            }
            .frame(width: w, height: h)
        }
        // Le scritte dentro il disegno restano piccole: il testo della pagina cresce con le impostazioni.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Un iPhone su un supporto manda il video al computer. Nella videochiamata il tuo riquadro è quello grande."))
        .accessibilityValue(confine < 0.5
                            ? Text("Si vede soprattutto l'iPhone: nitido e luminoso.")
                            : Text("Si vede soprattutto la webcam del computer: sgranata e scura."))
        .accessibilityAdjustableAction { direzione in
            toccato = true
            switch direzione {
            case .increment: confine = min(confine + 0.25, 1)
            case .decrement: confine = max(confine - 0.25, 0)
            default: break
            }
        }
    }

    /// La videochiamata: il tuo riquadro grande a sinistra, tre persone piccole a destra.
    private var chiamata: some View {
        GeometryReader { g in
            let spazio: CGFloat = 4
            let larghezzaGrande = (g.size.width - spazio * 3) * 0.7
            HStack(spacing: spazio) {
                riquadroConfronto
                    .frame(width: larghezzaGrande)
                VStack(spacing: spazio) {
                    ForEach(0..<3, id: \.self) { indice in
                        RiquadroOspite(variante: indice)
                    }
                }
            }
            .padding(spazio)
        }
    }

    private var riquadroConfronto: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let x = w * confine
            ZStack(alignment: .topLeading) {
                // Destra: l'iPhone, nitido e luminoso
                InquadraturaStanza(luceVolto: 0.7)
                    .contrast(1.06)
                // Sinistra: la webcam del computer, morbida, scura, sgranata
                InquadraturaStanza()
                    .blur(radius: 1.8)
                    .saturation(0.3)
                    .brightness(-0.22)
                    .contrast(0.7)
                    .overlay(GranaVideo())
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: x)
                    }
                // La linea con la maniglia
                Rectangle()
                    .fill(Tema.testo)
                    .frame(width: 2, height: h)
                    .offset(x: x - 1)
                Circle()
                    .fill(Tema.testo)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tema.fondo)
                    }
                    .shadow(color: Tema.sfumaturaScura.opacity(0.6), radius: 4, y: 1)
                    .position(x: x, y: h / 2)
                // Il dito del suggerimento
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Tema.testo)
                    .shadow(color: Tema.sfumaturaScura.opacity(0.7), radius: 4)
                    .position(x: x + 12, y: h / 2 + 24)
                    .opacity(ditoVisibile ? 1 : 0)
                etichette(larghezza: w)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { valore in
                        toccato = true
                        ditoVisibile = false
                        confine = min(max(valore.location.x / max(w, 1), 0), 1)
                    }
            )
        }
    }

    private func etichette(larghezza: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                etichetta(Text("Webcam del computer"))
                    .frame(maxWidth: larghezza * 0.46, alignment: .leading)
                    .opacity(confine > 0.25 ? 1 : 0)
                Spacer(minLength: 4)
                etichetta(Text(verbatim: "iPhone"))
                    .opacity(confine < 0.75 ? 1 : 0)
            }
            Spacer(minLength: 0)
            PuntoInOnda()
        }
        .padding(5)
        .allowsHitTesting(false)
    }

    private func etichetta(_ testo: Text) -> some View {
        testo
            .font(.etichetta(10))
            .textCase(.uppercase)
            .lineLimit(2)
            .foregroundStyle(Tema.testo)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Tema.sfumaturaScura.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // MARK: Il suggerimento

    /// La linea si muove da sola una volta, come se la trascinasse un dito, per far vedere che si può.
    /// Con `-presentazioneAutoplay` il gesto è più ampio e lento, come lo farebbe una persona.
    private func suggerimento() async {
        guard !riduciMovimento else { return }
        try? await Task.sleep(for: .milliseconds(1200))
        guard !Task.isCancelled, !toccato else { return }
        let passi: [(valore: CGFloat, durata: Double, pausa: Int)] = ArgomentiPresentazione.autoplay
            ? [(0.86, 1.3, 700), (0.14, 1.9, 800), (0.5, 1.1, 300)]
            : [(0.7, 0.8, 200), (0.32, 1.0, 200), (0.5, 0.7, 100)]
        withAnimation(.easeOut(duration: 0.25)) { ditoVisibile = true }
        for passo in passi {
            guard !Task.isCancelled, !toccato else { break }
            withAnimation(.easeInOut(duration: passo.durata)) { confine = passo.valore }
            try? await Task.sleep(for: .milliseconds(Int(passo.durata * 1000) + passo.pausa))
        }
        withAnimation(.easeOut(duration: 0.3)) { ditoVisibile = false }
    }
}

/// Una delle altre persone nella videochiamata.
private struct RiquadroOspite: View {
    let variante: Int

    private static let maglie: [Color] = [Tema.salvia, Tema.salviaScura, Tema.testoSecondario]
    private static let sfondi: [Color] = [Tema.pannello, Tema.pannelloScuro, Tema.pannelloChiaro]

    var body: some View {
        GeometryReader { g in
            PersonaDisegnata(altezza: g.size.height * 0.78, pelle: Tema.salviaTenue,
                             maglia: Self.maglie[variante % 3])
                .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        }
        .background(Self.sfondi[variante % 3])
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
