import Stile
import SwiftUI

/// La latenza degli ultimi 60 secondi in una linea sottile (funzione 31).
/// Un punto al secondo, disegnato con un solo Path: costa pochissimo.
struct GraficoLatenza: View {
    /// Quanti secondi tiene il grafico.
    static let secondi = 60

    /// Il più vecchio per primo; nil dove la latenza non era nota.
    let valori: [Int?]

    var body: some View {
        Canvas { contesto, dimensione in
            let noti = valori.compactMap { $0 }
            // Scala fissa fino a 150 ms (oltre è «debole»), più alta solo se serve.
            let massimo = CGFloat(max(150, noti.max() ?? 0))
            let passo = dimensione.width / CGFloat(Self.secondi - 1)
            let primo = Self.secondi - valori.count

            func altezza(_ ms: Int) -> CGFloat {
                dimensione.height * (1 - min(CGFloat(ms), massimo) / massimo)
            }

            // I 100 ms, l'obiettivo per una chiamata, in una riga tratteggiata.
            var soglia = Path()
            soglia.move(to: CGPoint(x: 0, y: altezza(100)))
            soglia.addLine(to: CGPoint(x: dimensione.width, y: altezza(100)))
            contesto.stroke(soglia, with: .color(Tema.linea), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            var linea = Path()
            var aperta = false
            for (indice, valore) in valori.enumerated() {
                guard let valore else {
                    aperta = false
                    continue
                }
                let punto = CGPoint(x: CGFloat(primo + indice) * passo, y: altezza(valore))
                if aperta {
                    linea.addLine(to: punto)
                } else {
                    linea.move(to: punto)
                    aperta = true
                }
            }
            contesto.stroke(linea, with: .color(Tema.cianoChiaro),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityElement()
        .accessibilityLabel(descrizione)
    }

    private var descrizione: String {
        let noti = valori.compactMap { $0 }
        guard let massimo = noti.max(), !noti.isEmpty else { return String(localized: "Grafico della latenza: ancora nessun dato") }
        let media = noti.reduce(0, +) / noti.count
        return String(localized: "Latenza dell'ultimo minuto: media \(media) millisecondi, massimo \(massimo)")
    }
}
