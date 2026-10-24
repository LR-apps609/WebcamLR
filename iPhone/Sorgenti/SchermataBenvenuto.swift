import Stile
import SwiftUI

/// Benvenuto (round 2, novità 16): tre schermate alla prima apertura. I permessi si spiegano prima
/// che iOS li chieda: la fotocamera alla fine di queste schermate, la rete locale appena parte la ricerca.
struct SchermataBenvenuto: View {
    /// Chiamata quando l'utente ha finito: da qui in poi non si mostra più.
    let fine: () -> Void
    @State private var pagina = 0

    private static let ultimaPagina = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pagina) {
                paginaCosaFa.tag(0)
                paginaWiFi.tag(1)
                paginaPermessi.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                avanti()
            } label: {
                Text(pagina < Self.ultimaPagina ? "Avanti" : "Inizia")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Tema.ciano, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Tema.fondo)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .preferredColorScheme(.dark)
    }

    private var paginaCosaFa: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    LogoWebcamLR(lato: 56)
                    MarchioWebcamLR(dimensione: 34)
                }
                Text("Il tuo iPhone diventa la webcam")
                    .font(.titolo(38))
                Text("WebcamLR manda il video della fotocamera dell'iPhone al Mac o al PC, per videochiamate, lezioni e dirette. Molto più nitido della webcam del computer, con pochissimo ritardo.")
                    .foregroundStyle(Tema.testoChiaro)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var paginaWiFi: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                icona("wifi")
                Text("Sulla stessa rete Wi-Fi")
                    .font(.titolo(38))
                Text("Apri WebcamLR anche sul computer e tieni iPhone e computer sulla stessa rete Wi-Fi: il computer compare qui da solo, basta toccare «Collega».")
                    .foregroundStyle(Tema.testoChiaro)
                Text("Se non compare, inquadra il QR code che WebcamLR mostra sul computer.")
                    .foregroundStyle(Tema.testoSecondario)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var paginaPermessi: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                icona("lock.shield")
                Text("Due permessi")
                    .font(.titolo(38))
                permesso(icona: "camera.fill", titolo: "Fotocamera",
                         testo: "Per mandare il video al computer. Senza, WebcamLR non può funzionare.")
                permesso(icona: "dot.radiowaves.left.and.right", titolo: "Rete locale",
                         testo: "Per trovare il computer sulla tua Wi-Fi. Il video va dritto al computer e resta nella tua rete.")
                Text("Toccando «Inizia» iOS te li chiede uno dopo l'altro: rispondi «Consenti» e «OK». Puoi cambiarli quando vuoi in Impostazioni › WebcamLR.")
                    .font(.subheadline)
                    .foregroundStyle(Tema.testoSecondario)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icona(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(Tema.ciano)
            .frame(width: 64, height: 64)
            .background(Tema.cianoTenue, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }

    private func permesso(icona: String, titolo: LocalizedStringKey, testo: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icona)
                .font(.system(size: 20))
                .foregroundStyle(Tema.ciano)
                .frame(width: 40, height: 40)
                .background(Tema.cianoTenue, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titolo).fontWeight(.semibold)
                Text(testo)
                    .font(.subheadline)
                    .foregroundStyle(Tema.testoChiaro)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func avanti() {
        if pagina < Self.ultimaPagina {
            withAnimation { pagina += 1 }
        } else {
            // Prima la fotocamera; la rete locale la chiede iOS quando parte la ricerca dei computer.
            Task { @MainActor in
                _ = await Cattura.chiediPermesso()
                fine()
            }
        }
    }
}

#Preview {
    SchermataBenvenuto {}
}
