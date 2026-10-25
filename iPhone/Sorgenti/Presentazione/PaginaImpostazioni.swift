import Stile
import SwiftUI

/// Terza pagina, «Le impostazioni extra sono sul computer»: l'iPhone fa soprattutto da telecomando, profili ed
/// effetti si scelgono nella finestra del computer. Quattro profili da toccare cambiano l'anteprima disegnata.
struct PaginaImpostazioni: View {
    let avanti: () -> Void
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento
    @Environment(\.dynamicTypeSize) private var dimensioneTesto

    enum Profilo: CaseIterable, Hashable {
        case riunione
        case lezione
        case diretta
        case colloquio
    }

    @State private var profilo: Profilo = .riunione

    var body: some View {
        ImpaginazionePagina {
            scena
        } contenuto: {
            VStack(alignment: .leading, spacing: 14) {
                profili
                descrizione(profilo)
                    .font(.corpo(14))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(profilo)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                TitoloPresentazione(Text("Le impostazioni extra sono sul computer"))
                TestoPresentazione(Text("L'iPhone fa da telecomando: il resto lo scegli nella finestra di WebcamLR sul computer."))
                colonne
            }
        } azioni: {
            PulsantePresentazione(titolo: Text("Avanti"), identificatore: "presentazione.avanti.impostazioni", azione: avanti)
        }
        .sensoryFeedback(.selection, trigger: profilo)
        .task { await autoplay() }
    }

    // MARK: Profili

    private var profili: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(Profilo.allCases, id: \.self) { voce in
                    chip(voce, pieno: false)
                        .fixedSize()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Profilo.allCases, id: \.self) { voce in
                    chip(voce, pieno: true)
                }
            }
        }
    }

    private func chip(_ voce: Profilo, pieno: Bool) -> some View {
        ChipPresentazione(titolo: nome(voce), scelto: voce == profilo, pieno: pieno,
                          identificatore: "presentazione.profilo.\(String(describing: voce))") {
            scegli(voce)
        }
        .accessibilityHint(descrizione(voce))
    }

    private func scegli(_ voce: Profilo) {
        withAnimation(riduciMovimento ? .easeInOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.8)) {
            profilo = voce
        }
    }

    private func nome(_ voce: Profilo) -> Text {
        switch voce {
        case .riunione: Text("Riunione")
        case .lezione: Text("Lezione")
        case .diretta: Text("Diretta")
        case .colloquio: Text("Colloquio")
        }
    }

    private func descrizione(_ voce: Profilo) -> Text {
        switch voce {
        case .riunione: Text("Volto illuminato e al centro.")
        case .lezione: Text("Tu e la scrivania, inquadratura ferma.")
        case .diretta: Text("Movimento fluido a 60 fps.")
        case .colloquio: Text("Sfondo sfocato, pelle curata.")
        }
    }

    // MARK: Le due colonne

    private var colonne: some View {
        let disposizione = dimensioneTesto.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return disposizione {
            colonna(icona: "iphone", titolo: Text("Sull'iPhone"), testo: Text("obiettivo, zoom, torcia, specchio, sfondo sfocato, pausa"))
            colonna(icona: "laptopcomputer", titolo: Text("Sul computer"),
                    testo: Text("profili, effetti, microfono, registrazione"))
        }
    }

    private func colonna(icona: String, titolo: Text, testo: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                titolo
            } icon: {
                Image(systemName: icona)
                    .foregroundStyle(Tema.accento)
            }
            .font(.corpoForte(16))
            .foregroundStyle(Tema.testo)
            testo
                .font(.corpo(15))
                .foregroundStyle(Tema.testoChiaro)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.linea, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: La scena

    private var scena: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let computer = min(w * 0.84, h * 1.25)
            let altezzaComputer = computer * Proporzioni.portatile
            let telefono = min(computer * 0.17, h * 0.4 / Proporzioni.telefono)
            ZStack {
                DisegnoPortatile(larghezza: computer) { finestraComputer }
                    .position(x: w - computer / 2, y: altezzaComputer / 2 + 4)
                TelefonoFronte(larghezza: telefono) { telecomando(larghezza: telefono) }
                    .position(x: telefono / 2 + 4, y: h - telefono * Proporzioni.telefono / 2)
            }
            .frame(width: w, height: h)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Anteprima sul computer"))
        .accessibilityValue(Text("Profilo:") + Text(verbatim: " ") + nome(profilo) + Text(verbatim: ". ") + descrizione(profilo))
    }

    /// La finestra di WebcamLR sul computer: l'anteprima e, a destra, i profili.
    private var finestraComputer: some View {
        GeometryReader { g in
            let spazio: CGFloat = 4
            HStack(spacing: spazio) {
                anteprima
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .frame(width: (g.size.width - spazio * 3) * 0.74)
                VStack(alignment: .leading, spacing: spazio) {
                    ForEach(Profilo.allCases, id: \.self) { voce in
                        rigaLaterale(scelta: voce == profilo)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(spazio)
        }
    }

    private func rigaLaterale(scelta: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(scelta ? Tema.accento : Tema.testoSecondario.opacity(0.5))
                .frame(width: 5, height: 5)
            Capsule()
                .fill(scelta ? Tema.accentoChiaro : Tema.linea)
                .frame(height: 3)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, minHeight: 12)
        .background(scelta ? Tema.accentoTenue : Color.clear, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var anteprima: some View {
        InquadraturaStanza(luceVolto: luce, sfocaSfondo: sfocatura, scalaPersona: scala,
                           scrivania: profilo == .lezione ? 1 : 0)
            .overlay(alignment: .topTrailing) {
                if profilo == .diretta {
                    Text(verbatim: "60 fps")
                        .font(.numeriEvidenti(9))
                        .foregroundStyle(Tema.testo)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Tema.sfumaturaScura.opacity(0.8), in: Capsule())
                        .padding(4)
                        .transition(.opacity)
                }
            }
    }

    private var luce: Double {
        switch profilo {
        case .riunione: 0.85
        case .lezione: 0.3
        // Come i profili del Mac: la luce sul volto è accesa anche in «Diretta» e in «Colloquio».
        case .diretta: 0.6
        case .colloquio: 0.75
        }
    }

    private var sfocatura: CGFloat { profilo == .colloquio ? 5 : 0 }

    private var scala: CGFloat {
        switch profilo {
        case .lezione: 0.68
        case .colloquio: 1.05
        default: 1
        }
    }

    /// Il telefono come telecomando: obiettivo, zoom, torcia, pausa (specchio e sfondo sono nel testo).
    private func telecomando(larghezza: CGFloat) -> some View {
        let lato = larghezza * 0.32
        return VStack(spacing: larghezza * 0.08) {
            HStack(spacing: larghezza * 0.08) {
                tasto("camera.rotate", lato: lato)
                tasto("plus.magnifyingglass", lato: lato)
            }
            HStack(spacing: larghezza * 0.08) {
                tasto("flashlight.on.fill", lato: lato)
                tasto("pause.fill", lato: lato)
            }
        }
    }

    private func tasto(_ simbolo: String, lato: CGFloat) -> some View {
        Image(systemName: simbolo)
            .font(.system(size: lato * 0.45, weight: .semibold))
            .foregroundStyle(Tema.testoChiaro)
            .frame(width: lato, height: lato)
            .background(Tema.pannelloChiaro, in: Circle())
    }

    // MARK: Autoplay

    /// Con `-presentazioneAutoplay` si toccano i profili uno dopo l'altro, con i tempi di una persona.
    private func autoplay() async {
        guard ArgomentiPresentazione.autoplay else { return }
        try? await Task.sleep(for: .milliseconds(1800))
        for voce in [Profilo.lezione, .diretta, .colloquio] {
            guard !Task.isCancelled else { return }
            scegli(voce)
            try? await Task.sleep(for: .milliseconds(2300))
        }
    }
}
