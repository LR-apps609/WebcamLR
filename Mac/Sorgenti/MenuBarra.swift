import AppKit
import SwiftUI

/// Menu nella barra in alto (bozza grafica, Mac 2).
struct MenuBarra: View {
    let annuncio: AnnuncioInRete
    let fotocamera: AttivazioneFotocamera

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                (Text("Webcam") + Text("LR").foregroundColor(Tema.tally))
                    .font(.system(size: 18, weight: .bold).width(.condensed))
                Spacer()
                Text("Nessun telefono")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tema.testoSecondario)
            }
            Text(!fotocamera.disponibile ? "Webcam virtuale non inclusa"
                 : fotocamera.stato == .attiva ? "Webcam virtuale attiva" : "Webcam virtuale spenta")
                .font(.callout)
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
    }
}
