import Stile
import SwiftUI

/// Seconda pagina, «Scarica WebcamLR sul computer»: un portatile (Mac) e un monitor (Windows) disegnati senza
/// marchi; una freccia scende nello schermo, la barra si riempie e compare il logo di WebcamLR. Toccando un
/// computer lo scaricamento riparte lì. Sotto, l'indirizzo del sito e «Mandami il link» per mandarselo
/// (AirDrop, Messaggi, Mail…) e aprirlo sul computer.
struct PaginaComputer: View {
    let avanti: () -> Void
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    enum Sistema: Hashable {
        case mac
        case windows
    }

    @State private var scelto: Sistema = .mac
    @State private var scaricati: Set<Sistema> = []
    /// Da 0 a 1: la freccia che scende nello schermo scelto.
    @State private var freccia: CGFloat = 0
    @State private var frecciaVisibile = false
    /// Da 0 a 1: la barra dello scaricamento sullo schermo scelto.
    @State private var barra: CGFloat = 0
    /// Cambia a ogni tocco su un computer: fa ripartire l'animazione.
    @State private var giro = 0
    @State private var toccato = false

    static let indirizzo = "lr-apps609.github.io/WebcamLR"
    static let collegamento = URL(string: "https://lr-apps609.github.io/WebcamLR/download.html")!

    var body: some View {
        ImpaginazionePagina {
            scena
        } contenuto: {
            VStack(alignment: .leading, spacing: Spazi.medio) {
                TitoloPresentazione(Text("Scarica WebcamLR sul computer"))
                indirizzo
                ShareLink(item: Self.collegamento,
                          subject: Text("WebcamLR per il computer"),
                          message: Text("Scarica WebcamLR sul computer")) {
                    Label {
                        Text("Mandami il link")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(StileSecondario())
                .accessibilityHint(Text("Manda l'indirizzo per scaricare WebcamLR, per esempio con AirDrop o Messaggi"))
                .accessibilityIdentifier("presentazione.mandaLink")
                TestoPresentazione(Text("Poi apri WebcamLR sul computer: l'iPhone lo trova da solo sulla stessa rete Wi-Fi, o col cavo."),
                                   colore: Tema.testoSecondario, dimensione: 16)
            }
        } azioni: {
            PulsantePresentazione(titolo: Text("Avanti"), identificatore: "presentazione.avanti.computer", azione: avanti)
        }
        .task(id: giro) { await scaricamenti() }
    }

    private var indirizzo: some View {
        HStack(spacing: Spazi.stretto) {
            Image(systemName: "globe")
                .foregroundStyle(Tema.accento)
                .accessibilityHidden(true)
            Text(verbatim: Self.indirizzo)
                .font(.stile(.corpo, .numeriEvidenti))
                .foregroundStyle(Tema.testo)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Spazi.medio)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Raggi.pannello, style: .continuous).stroke(Tema.linea, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Indirizzo del sito"))
        .accessibilityValue(Text(verbatim: Self.indirizzo))
    }

    // MARK: La scena

    private var scena: some View {
        GeometryReader { g in
            let unita = min(g.size.width, g.size.height * 1.3)
            HStack(alignment: .bottom, spacing: unita * 0.08) {
                computer(.mac, larghezza: unita * 0.52)
                computer(.windows, larghezza: unita * 0.4)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func computer(_ sistema: Sistema, larghezza: CGFloat) -> some View {
        let attivo = scelto == sistema
        return Button {
            toccato = true
            scelto = sistema
            giro += 1
        } label: {
            VStack(spacing: Spazi.stretto) {
                Group {
                    switch sistema {
                    case .mac:
                        DisegnoPortatile(larghezza: larghezza) { schermo(sistema, larghezza: larghezza) }
                    case .windows:
                        DisegnoMonitor(larghezza: larghezza) { schermo(sistema, larghezza: larghezza) }
                    }
                }
                .overlay(alignment: .top) {
                    if attivo && frecciaVisibile {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Tema.fondo)
                            .frame(width: 30, height: 30)
                            .background(Tema.accento, in: Circle())
                            .offset(y: -larghezza * 0.32 + freccia * larghezza * 0.42)
                            .transition(.opacity)
                    }
                }
                Text(verbatim: sistema == .mac ? "Mac" : "Windows")
                    .font(.stile(.comando))
                    .foregroundStyle(attivo ? Tema.accento : Tema.testoSecondario)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: sistema == .mac ? "Mac" : "Windows"))
        .accessibilityValue(scaricati.contains(sistema) ? Text("WebcamLR scaricata") : Text("Da scaricare"))
        .accessibilityAddTraits(attivo ? .isSelected : [])
        .accessibilityIdentifier(sistema == .mac ? "presentazione.mac" : "presentazione.windows")
    }

    /// Lo schermo: una barra in alto (Mac) o in basso (Windows), poi lo scaricamento e il logo.
    private func schermo(_ sistema: Sistema, larghezza: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 0) {
                if sistema == .windows { Spacer(minLength: 0) }
                Rectangle()
                    .fill(Tema.pannelloChiaro)
                    .frame(height: max(3, larghezza * 0.035))
                if sistema == .mac { Spacer(minLength: 0) }
            }
            if scaricati.contains(sistema) {
                VStack(spacing: larghezza * 0.03) {
                    LogoWebcamLR(lato: larghezza * 0.2)
                    Text(verbatim: "WebcamLR")
                        .font(.etichetta(max(9, larghezza * 0.07)))
                        .foregroundStyle(Tema.testo)
                }
                .transition(riduciMovimento ? AnyTransition.opacity : AnyTransition.scale(scale: 0.6).combined(with: .opacity))
            } else if scelto == sistema && barra > 0 {
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.linea)
                    Capsule().fill(Tema.accento)
                        .frame(width: larghezza * 0.5 * barra)
                }
                .frame(width: larghezza * 0.5, height: max(4, larghezza * 0.03))
                .transition(.opacity)
            }
        }
    }

    // MARK: L'animazione

    /// Al primo giro scarica sul Mac e poi su Windows; dopo un tocco, solo sul computer toccato.
    private func scaricamenti() async {
        if toccato {
            await scarica(scelto)
            return
        }
        await scarica(.mac)
        try? await Task.sleep(for: .milliseconds(ArgomentiPresentazione.autoplay ? 900 : 700))
        guard !Task.isCancelled else { return }
        await scarica(.windows)
    }

    private func scarica(_ sistema: Sistema) async {
        var senzaAnimazione = Transaction()
        senzaAnimazione.disablesAnimations = true
        withTransaction(senzaAnimazione) {
            scelto = sistema
            scaricati.remove(sistema)
            frecciaVisibile = false
            freccia = 0
            barra = 0
        }
        if riduciMovimento {
            withAnimation(.easeInOut(duration: 0.4)) { _ = scaricati.insert(sistema) }
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { frecciaVisibile = true }
        withAnimation(.easeIn(duration: 0.8)) { freccia = 1 }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { frecciaVisibile = false }
        withAnimation(.easeInOut(duration: 1.3)) { barra = 1 }
        try? await Task.sleep(for: .milliseconds(1350))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { _ = scaricati.insert(sistema) }
    }
}
