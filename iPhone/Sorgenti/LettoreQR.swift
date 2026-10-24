import Network
import Stile
import SwiftUI
import VisionKit
import WebcamLRProtocollo

extension ComputerTrovato {
    /// Un computer letto dal QR code o scritto a mano: si prova il primo indirizzo (funzione 2).
    init?(associazione: Associazione) {
        guard let primo = associazione.indirizzi.first, let porta = NWEndpoint.Port(rawValue: associazione.porta) else {
            return nil
        }
        self.init(id: "qr-\(primo):\(associazione.porta)", nome: associazione.nome, piattaforma: nil,
                  endpoint: .hostPort(host: NWEndpoint.Host(primo), port: porta),
                  impronta: associazione.impronta, gettone: associazione.gettone)
    }
}

/// Foglio che inquadra il QR code mostrato dal computer.
struct FoglioLettoreQR: View {
    let suLettura: (Associazione) -> Void
    @Environment(\.dismiss) private var chiudi
    @State private var avviso: String?
    /// `isAvailable` è falso finché non c'è il permesso della fotocamera: lo si chiede prima.
    @State private var permessoChiesto = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if !permessoChiesto {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    LettoreQR { testo in
                        if let associazione = Associazione(testo: testo) {
                            chiudi()
                            suLettura(associazione)
                        } else {
                            avviso = "Questo QR code non è di WebcamLR."
                        }
                    }
                    .ignoresSafeArea()
                } else {
                    Text("Questo iPhone non può leggere i QR code da qui. Scrivi l'indirizzo che il computer mostra sotto il QR code.")
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(avviso ?? "Inquadra il QR code nel menu di WebcamLR sul computer.")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Tema.fondo.opacity(0.85), in: Capsule())
                    .padding(.bottom, 24)
            }
            .background(Tema.fondo)
            .task {
                _ = await Cattura.chiediPermesso()
                permessoChiesto = true
            }
            .navigationTitle("QR code del computer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { chiudi() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// VisionKit: riconosce i QR code dal vivo, senza scattare foto.
private struct LettoreQR: UIViewControllerRepresentable {
    let suTesto: (String) -> Void

    func makeCoordinator() -> Coordinatore {
        Coordinatore(suTesto: suTesto)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let lettore = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .fast,
                                                isHighlightingEnabled: true)
        lettore.delegate = context.coordinator
        DispatchQueue.main.async { try? lettore.startScanning() }
        return lettore
    }

    func updateUIViewController(_ lettore: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ lettore: DataScannerViewController, coordinator: Coordinatore) {
        lettore.stopScanning()
    }

    final class Coordinatore: NSObject, DataScannerViewControllerDelegate {
        let suTesto: (String) -> Void
        private var ultimo: String?

        init(suTesto: @escaping (String) -> Void) {
            self.suTesto = suTesto
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for elemento in addedItems {
                guard case .barcode(let codice) = elemento, let testo = codice.payloadStringValue, testo != ultimo else { continue }
                ultimo = testo
                suTesto(testo)
                return
            }
        }
    }
}
