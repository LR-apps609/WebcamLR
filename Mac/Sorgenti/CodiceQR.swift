import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin
import Stile
import SwiftUI
import WebcamLRProtocollo

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

    private static func immagine(_ testo: String) -> CGImage? {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(testo.utf8)
        filtro.correctionLevel = "M"
        guard let uscita = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext().createCGImage(uscita, from: uscita.extent)
    }
}

/// Riquadro «Nuovo telefono?» con il QR code e gli indirizzi da scrivere a mano.
/// Protocollo 2 (0.10): il QR porta anche l'impronta del Mac e il gettone, e si rifà quando il gettone cambia.
struct PannelloAssociazione: View {
    let ricevitore: Ricevitore
    var lato: CGFloat = 180

    var body: some View {
        let indirizzi = IndirizziLocali.ipv4()
        VStack(alignment: .leading, spacing: 10) {
            if let porta = ricevitore.porta, !indirizzi.isEmpty {
                let associazione = Associazione(indirizzi: indirizzi, porta: porta,
                                                nome: Host.current().localizedName ?? "Mac",
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
            } else {
                Text("Il Mac non è collegato a una rete: collegalo al Wi-Fi o al cavo.")
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
            }
        }
    }
}
