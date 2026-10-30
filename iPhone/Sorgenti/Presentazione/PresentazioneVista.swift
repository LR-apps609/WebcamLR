import Stile
import SwiftUI
import UIKit

/// La presentazione alla prima apertura (prende il posto delle tre schermate di benvenuto del round 2, novità 16):
/// quattro pagine con scene disegnate e animate in SwiftUI, una cosa da toccare in ognuna, le barrette in stile
/// «storie» che si riempiono nel tempo di ogni pagina e «Salta» in alto a destra, che porta all'ultima pagina.
/// I permessi si spiegano prima che iOS li chieda: fotocamera e microfono con «Inizia», la rete locale appena
/// parte la ricerca. Con «Riduci movimento» le pagine si scambiano in dissolvenza e le scene stanno ferme.
///
/// Argomenti di avvio: `-presentazione` la mostra di nuovo, `-presentazioneAutoplay` la fa andare da sola
/// (circa 33 secondi, per il video del sito). Vedi `ArgomentiPresentazione`.
struct PresentazioneVista: View {
    /// Chiamata quando l'utente ha finito: da qui in poi non si mostra più.
    let fine: () -> Void
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento
    @State private var pagina = 0
    @State private var riempimento = 0.0
    @State private var chiedendo = false

    /// Quanto dura ogni pagina, in secondi: riempie la sua barretta e, con l'autoplay, poi si va avanti.
    private static let durate: [Double] = [10, 8, 10, 5]
    private static var ultima: Int { durate.count - 1 }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Tema.fondo, Tema.sfumaturaScura], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            Group {
                switch pagina {
                case 0: PaginaWebcam(avanti: avanti)
                case 1: PaginaComputer(avanti: avanti)
                case 2: PaginaImpostazioni(avanti: avanti)
                default: PaginaPermessi(chiedendo: chiedendo, inizia: inizia)
                }
            }
            .frame(maxWidth: 600)
            .id(pagina)
            .transition(transizione)
            intestazione
        }
        .foregroundStyle(Tema.testo)
        .preferredColorScheme(.dark)
        .onAppear { riempi() }
        .task(id: pagina) { await avantiDaSola() }
    }

    private var intestazione: some View {
        HStack(spacing: Spazi.piccolo) {
            BarreAvanzamento(pagina: pagina, totale: Self.durate.count, riempimento: riempimento)
            Spacer(minLength: Spazi.stretto)
            if pagina < Self.ultima {
                Button {
                    vai(a: Self.ultima)
                } label: {
                    Text("Salta")
                }
                .buttonStyle(StileSecondario())
                .accessibilityHint(Text("Va all'ultima pagina, quella dei permessi."))
                .accessibilityIdentifier("presentazione.salta")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spazi.largo)
        .padding(.top, Spazi.stretto)
        .frame(maxWidth: 600)
        // La riga in alto resta alta al massimo quanto lo spazio che le pagine le lasciano.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var transizione: AnyTransition {
        riduciMovimento
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                          removal: .move(edge: .leading).combined(with: .opacity))
    }

    private func avanti() {
        vai(a: min(pagina + 1, Self.ultima))
    }

    private func vai(a nuova: Int) {
        guard nuova != pagina else { return }
        withAnimation(riduciMovimento ? .easeInOut(duration: 0.35) : .spring(response: 0.5, dampingFraction: 0.9)) {
            pagina = nuova
        }
        riempi()
        // VoiceOver riparte dall'inizio della pagina nuova.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    /// La barretta della pagina attuale riparte da zero e si riempie nel tempo della pagina.
    private func riempi() {
        var senzaAnimazione = Transaction()
        senzaAnimazione.disablesAnimations = true
        withTransaction(senzaAnimazione) { riempimento = 0 }
        let durata = Self.durate[min(pagina, Self.ultima)]
        DispatchQueue.main.async {
            withAnimation(.linear(duration: durata)) { riempimento = 1 }
        }
    }

    /// Con `-presentazioneAutoplay`, finito il tempo della pagina si passa alla successiva (mai oltre l'ultima).
    private func avantiDaSola() async {
        guard ArgomentiPresentazione.autoplay, pagina < Self.ultima else { return }
        try? await Task.sleep(for: .seconds(Self.durate[pagina]))
        guard !Task.isCancelled else { return }
        avanti()
    }

    private func inizia() {
        guard !chiedendo else { return }
        chiedendo = true
        // Prima la fotocamera, poi il microfono (solo se iOS non l'ha mai chiesto);
        // la rete locale la chiede iOS quando parte la ricerca dei computer.
        Task { @MainActor in
            _ = await Cattura.chiediPermesso()
            if MicrofonoPermesso.attuale == .daChiedere {
                _ = await MicrofonoPermesso.chiedi()
            }
            fine()
        }
    }
}

#Preview {
    PresentazioneVista {}
}
