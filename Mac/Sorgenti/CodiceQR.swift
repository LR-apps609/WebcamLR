import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin
import Stile
import SwiftUI
import SystemConfiguration
import WebcamLRProtocollo

/// Il nome del Mac («MacBook Air di Ledion»), letto una volta sola.
/// `Host.current().localizedName` può fermarsi a lungo sulla rete: qui si chiede direttamente
/// al sistema il nome scelto in Impostazioni di Sistema › Generali › Condivisione.
enum NomeMac {
    static let attuale: String = {
        if let nome = SCDynamicStoreCopyComputerName(nil, nil) as String?, !nome.isEmpty { return nome }
        return Host.current().localizedName ?? "Mac"
    }()
}

/// Indirizzi IPv4 del Mac nella rete locale, il Wi-Fi o il cavo per primi (funzione 2).
enum IndirizziLocali {
    static func ipv4() -> [String] {
        var trovati: [(interfaccia: String, indirizzo: String)] = []
        var elenco: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&elenco) == 0, let primo = elenco else { return [] }
        defer { freeifaddrs(elenco) }

        for puntatore in sequence(first: primo, next: { $0.pointee.ifa_next }) {
            let voce = puntatore.pointee
            guard let indirizzo = voce.ifa_addr, indirizzo.pointee.sa_family == UInt8(AF_INET),
                  (voce.ifa_flags & UInt32(IFF_UP)) != 0, (voce.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var testo = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(indirizzo, socklen_t(indirizzo.pointee.sa_len), &testo, socklen_t(testo.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: testo)
            // 169.254.x.x: indirizzo automatico senza rete vera, inutile per il telefono.
            guard !ip.hasPrefix("169.254.") else { continue }
            trovati.append((String(cString: voce.ifa_name), ip))
        }
        // en0 di solito è il Wi-Fi sui portatili; le altre en* sono cavi e adattatori.
        return trovati
            .sorted { priorita($0.interfaccia) < priorita($1.interfaccia) }
            .map(\.indirizzo)
    }

    private static func priorita(_ interfaccia: String) -> Int {
        if interfaccia == "en0" { return 0 }
        if interfaccia.hasPrefix("en") { return 1 }
        return 2
    }
}

/// Il QR code da inquadrare con l'iPhone.
struct CodiceQR: View {
    let testo: String
    var lato: CGFloat = 180

    var body: some View {
        Group {
            if let immagine = Self.immagine(testo) {
                Image(decorative: immagine, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .frame(width: lato, height: lato)
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("QR code per collegare l'iPhone")
    }

    /// L'ultimo QR disegnato: la vista si ridisegna spesso, il testo cambia di rado (gettone nuovo, altra rete).
    @MainActor private static var ultimo: (testo: String, immagine: CGImage)?
    @MainActor private static let contesto = CIContext()

    @MainActor private static func immagine(_ testo: String) -> CGImage? {
        if let ultimo, ultimo.testo == testo { return ultimo.immagine }
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(testo.utf8)
        filtro.correctionLevel = "M"
        guard let uscita = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let disegnata = contesto.createCGImage(uscita, from: uscita.extent) else { return nil }
        ultimo = (testo, disegnata)
        return disegnata
    }
}

/// Riquadro «Nuovo telefono?» con il QR code e gli indirizzi da scrivere a mano.
/// Protocollo 2 (0.10): il QR porta anche l'impronta del Mac e il gettone, e si rifà quando il gettone cambia.
struct PannelloAssociazione: View {
    let ricevitore: Ricevitore
    var lato: CGFloat = 180

    var body: some View {
        // Indirizzi e nome già pronti nel ricevitore: niente domande al sistema a ogni disegno.
        let indirizzi = ricevitore.indirizzi
        VStack(alignment: .leading, spacing: 10) {
            if indirizzi.isEmpty {
                Text("Il Mac non è collegato a una rete: collegalo al Wi-Fi o al cavo.")
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
            } else if let porta = ricevitore.porta {
                let associazione = Associazione(indirizzi: indirizzi, porta: porta,
                                                nome: NomeMac.attuale,
                                                versione: Sicurezza.versioneSicura,
                                                impronta: ricevitore.improntaMac, gettone: ricevitore.gettone)
                CodiceQR(testo: associazione.testo, lato: lato)
                Text("Sull'iPhone: «Inquadra il QR code del computer».")
                    .font(.callout)
                    .foregroundStyle(Tema.testoTenue)
                Text("Oppure scrivi: \(indirizzi[0])\(porta == Servizio.portaPredefinita ? "" : ":\(porta)")")
                    .font(.numeri(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .textSelection(.enabled)
            } else if case .errore = ricevitore.rete {
                Text("La rete non risponde: controlla il Wi-Fi e scegli «Riprova».")
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Riprova") { ricevitore.avvia() }
            } else {
                // Il ricevitore sta aprendo la porta (una frazione di secondo all'avvio): stesso spazio del QR.
                ProgressView()
                    .controlSize(.small)
                    .frame(width: lato + 20, height: lato + 20)
                    .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Preparo il QR code")
            }
        }
        // Un indirizzo cambiato senza che la rete lo annunci (per esempio un nuovo indirizzo dal router).
        .onAppear { ricevitore.aggiornaIndirizzi() }
    }
}
