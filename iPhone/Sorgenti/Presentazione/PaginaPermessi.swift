import Stile
import SwiftUI

/// Ultima pagina, «Goditi l'esperienza»: i permessi spiegati prima che iOS li chieda. Toccando un permesso la
/// scena fa vedere a cosa serve (il video che va al computer, l'audio, la ricerca sulla Wi-Fi).
/// «Inizia» chiede fotocamera e microfono; la rete locale la chiede iOS quando parte la ricerca dei computer.
struct PaginaPermessi: View {
    /// Vero mentre iOS sta chiedendo i permessi: «Inizia» non si tocca due volte.
    let chiedendo: Bool
    let inizia: () -> Void
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    enum Permesso: CaseIterable, Hashable {
        case fotocamera
        case microfono
        case rete

        var simbolo: String {
            switch self {
            case .fotocamera: "camera.fill"
            case .microfono: "mic.fill"
            case .rete: "wifi"
            }
        }
    }

    @State private var scelto: Permesso = .fotocamera

    var body: some View {
        ImpaginazionePagina(quotaScena: 0.28) {
            scena
        } contenuto: {
            VStack(alignment: .leading, spacing: Spazi.piccolo) {
                TitoloPresentazione(Text("Goditi l'esperienza"))
                TestoPresentazione(Text("Prima di iniziare, tre permessi: ecco a cosa servono."))
                permesso(.fotocamera, titolo: "Fotocamera",
                         testo: "Per mandare il video al computer. Senza, WebcamLR non può funzionare.",
                         identificatore: "presentazione.permesso.fotocamera")
                permesso(.microfono, titolo: "Microfono",
                         testo: "Per usare l'iPhone anche come microfono del computer, se lo accendi.",
                         identificatore: "presentazione.permesso.microfono")
                permesso(.rete, titolo: "Rete locale",
                         testo: "Per trovare il computer sulla tua Wi-Fi. Il video va dritto al computer e resta nella tua rete.",
                         identificatore: "presentazione.permesso.rete")
                TestoPresentazione(Text("Toccando «Inizia» iOS ti chiede fotocamera e microfono: rispondi «Consenti». La rete locale te la chiede quando WebcamLR cerca il computer. Puoi cambiarli quando vuoi in Impostazioni › WebcamLR."),
                                   colore: Tema.testoSecondario, dimensione: 14)
            }
        } azioni: {
            PulsantePresentazione(titolo: Text("Inizia"), identificatore: "presentazione.inizia", azione: inizia)
                .disabled(chiedendo)
                .opacity(chiedendo ? 0.6 : 1)
        }
        .sensoryFeedback(.selection, trigger: scelto)
        .task { await autoplay() }
    }

    private func permesso(_ tipo: Permesso, titolo: LocalizedStringKey, testo: LocalizedStringKey,
                          identificatore: String) -> some View {
        let attivo = scelto == tipo
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { scelto = tipo }
        } label: {
            HStack(alignment: .top, spacing: Spazi.medio) {
                Image(systemName: tipo.simbolo)
                    .font(.system(size: 19))
                    .foregroundStyle(attivo ? Tema.accento : Tema.testoSecondario)
                    .frame(width: 40, height: 40)
                    .background(attivo ? Tema.accentoTenue : Tema.pannelloChiaro,
                                in: RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spazi.minimo) {
                    Text(titolo)
                        .font(.stile(.comando))
                        .foregroundStyle(Tema.testo)
                    Text(testo)
                        .font(.stile(.corpo))
                        .foregroundStyle(Tema.testoChiaro)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Spazi.piccolo)
            .background(Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous)
                .stroke(attivo ? Tema.accento.opacity(0.7) : Tema.contornoControllo, lineWidth: attivo ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(attivo ? .isSelected : [])
        .accessibilityIdentifier(identificatore)
    }

    // MARK: La scena

    private var scena: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let computer = min(w * 0.46, h * 1.3)
            let telefono = min(w * 0.17, h * 0.92 / Proporzioni.telefono)
            HStack(spacing: Spazi.stretto) {
                TelefonoFronte(larghezza: telefono) {
                    Image(systemName: scelto.simbolo)
                        .font(.system(size: telefono * 0.32, weight: .semibold))
                        .foregroundStyle(Tema.accento)
                        .contentTransition(.symbolEffect(.replace))
                }
                FlussoPermesso(permesso: scelto)
                    .frame(maxWidth: .infinity, maxHeight: h * 0.6)
                DisegnoPortatile(larghezza: computer) {
                    schermoComputer(larghezza: computer)
                }
            }
            .frame(width: w, height: h)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descrizioneScena)
    }

    private var descrizioneScena: Text {
        switch scelto {
        case .fotocamera: Text("Il video dell'iPhone arriva sul computer.")
        case .microfono: Text("L'audio dell'iPhone arriva sul computer.")
        case .rete: Text("L'iPhone trova il computer sulla stessa rete Wi-Fi.")
        }
    }

    @ViewBuilder private func schermoComputer(larghezza: CGFloat) -> some View {
        switch scelto {
        case .fotocamera:
            InquadraturaStanza(luceVolto: 0.6)
                .overlay(alignment: .bottomLeading) {
                    PuntoInOnda().padding(3)
                }
                .transition(.opacity)
        case .microfono:
            Image(systemName: "waveform")
                .font(.system(size: larghezza * 0.2, weight: .medium))
                .foregroundStyle(Tema.accento)
                .transition(.opacity)
        case .rete:
            VStack(spacing: larghezza * 0.03) {
                Image(systemName: "iphone")
                    .font(.system(size: larghezza * 0.14, weight: .medium))
                    .foregroundStyle(Tema.testoChiaro)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: larghezza * 0.09, weight: .bold))
                    .foregroundStyle(Tema.verde)
            }
            .transition(.opacity)
        }
    }

    // MARK: Autoplay

    /// Con `-presentazioneAutoplay` si toccano i tre permessi uno dopo l'altro; «Inizia» no.
    private func autoplay() async {
        guard ArgomentiPresentazione.autoplay else { return }
        for voce in [Permesso.microfono, .rete] {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { scelto = voce }
        }
    }
}

/// Tra telefono e computer: i fotogrammi che passano, le barre dell'audio o le onde della Wi-Fi.
/// Con «Riduci movimento» il disegno resta fermo.
private struct FlussoPermesso: View {
    let permesso: PaginaPermessi.Permesso
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: riduciMovimento)) { contesto in
            let tempo: Double = riduciMovimento ? 0.4 : contesto.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                switch permesso {
                case .fotocamera: fotogrammi(ctx, size, tempo)
                case .microfono: audio(ctx, size, tempo)
                case .rete: onde(ctx, size, tempo)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fotogrammi(_ ctx: GraphicsContext, _ size: CGSize, _ tempo: Double) {
        for indice in 0..<3 {
            let fase = (tempo * 0.5 + Double(indice) / 3).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(fase) * size.width
            let riquadro = CGRect(x: x - 9, y: size.height / 2 - 6, width: 18, height: 12)
            ctx.fill(Path(roundedRect: riquadro, cornerRadius: 3),
                     with: .color(Tema.accento.opacity(sin(fase * .pi))))
        }
    }

    private func audio(_ ctx: GraphicsContext, _ size: CGSize, _ tempo: Double) {
        let quante = 7
        let passo = size.width / CGFloat(quante)
        for indice in 0..<quante {
            let ampiezza = 0.25 + 0.75 * abs(sin(tempo * 4 + Double(indice) * 0.9))
            let altezza = size.height * 0.8 * CGFloat(ampiezza)
            let barra = CGRect(x: CGFloat(indice) * passo + passo * 0.3, y: (size.height - altezza) / 2,
                               width: passo * 0.4, height: altezza)
            ctx.fill(Path(roundedRect: barra, cornerRadius: passo * 0.2), with: .color(Tema.accento))
        }
    }

    private func onde(_ ctx: GraphicsContext, _ size: CGSize, _ tempo: Double) {
        let centro = CGPoint(x: size.width / 2, y: size.height * 0.85)
        let massimo = min(size.width / 2, size.height * 0.8)
        for indice in 0..<3 {
            let raggio = massimo * CGFloat(indice + 1) / 3
            let accesa = (Int(tempo * 2.5) % 4) > indice
            var arco = Path()
            for passo in 0...16 {
                let angolo = -Double.pi / 2 + (Double(passo) / 16 - 0.5) * 1.6
                let punto = CGPoint(x: centro.x + raggio * CGFloat(cos(angolo)),
                                    y: centro.y + raggio * CGFloat(sin(angolo)))
                if passo == 0 { arco.move(to: punto) } else { arco.addLine(to: punto) }
            }
            ctx.stroke(arco, with: .color(Tema.accento.opacity(accesa || riduciMovimento ? 1 : 0.25)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: centro.x - 3, y: centro.y - 3, width: 6, height: 6)),
                 with: .color(Tema.accento))
    }
}
