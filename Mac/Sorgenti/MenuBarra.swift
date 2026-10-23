import AppKit
import Stile
import SwiftUI

/// Menu nella barra in alto (bozza grafica, Mac 2).
struct MenuBarra: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MarchioWebcamLR(dimensione: 18)
                Spacer()
                PillolaStato(ricevitore.collegamento)
                    .scaleEffect(0.85, anchor: .trailing)
            }

            if let telefono = ricevitore.telefono {
                VStack(alignment: .leading, spacing: 2) {
                    Text(telefono.nome).fontWeight(.semibold)
                    Text(dettagli)
                        .font(.numeri(11.5))
                        .foregroundStyle(Tema.testoTenue)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.pannelloChiaro, in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apri WebcamLR sull'iPhone e scegli questo Mac. Se non compare:")
                        .font(.callout)
                        .foregroundStyle(Tema.testoTenue)
                    PannelloAssociazione(porta: ricevitore.porta, lato: 120)
                }
            }

            Text(!fotocamera.disponibile ? "Webcam virtuale: dal round 2"
                 : fotocamera.stato == .attiva ? "Webcam virtuale attiva" : "Webcam virtuale spenta")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)

            Divider()
            HStack {
                Button("Apri WebcamLR") {
                    NSApp.activate(ignoringOtherApps: true)
                    for finestra in NSApp.windows where finestra.canBecomeMain {
                        finestra.makeKeyAndOrderFront(nil)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Esci") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .foregroundStyle(Tema.testo)
        .onAppear { ricevitore.avvia() }
    }

    private var dettagli: String {
        let statistiche = ricevitore.statistiche
        var parti: [String] = []
        if statistiche.larghezza > 0 { parti.append("\(min(statistiche.larghezza, statistiche.altezza))p\(statistiche.fps)") }
        parti.append(statistiche.latenzaMs.map { "\($0) ms" } ?? "— ms")
        if let stato = ricevitore.statoTelefono, stato.batteria >= 0 { parti.append("\(stato.batteria)%") }
        return parti.joined(separator: " · ")
    }
}
