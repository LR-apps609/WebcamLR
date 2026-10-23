import SwiftUI

/// Segnaposto della schermata «In onda» (bozza grafica, iPhone 3): il video arriva al round 1.
struct SchermataInOnda: View {
    let computer: ComputerTrovato

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "video")
                .font(.system(size: 40))
                .foregroundStyle(Tema.ciano)
            Text("Collegamento a \(computer.nome)")
                .font(.title3.weight(.semibold))
            Text("Il video arriverà con il round 1.")
                .foregroundStyle(Tema.testoSecondario)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
    }
}
