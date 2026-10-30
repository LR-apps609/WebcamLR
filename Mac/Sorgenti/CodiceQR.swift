import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin
import Network
import Stile
import SwiftUI
import SystemConfiguration
import WebcamLRProtocollo

/// Il nome del Mac («MacBook Air di Ledion»), letto una volta sola.
/// `Host.current().localizedName` può fermarsi a lungo sulla rete: qui si chiede direttamente
/// al sistema il nome scelto in Impostazioni di Sistema › Generali › Condivisione.
enum NomeMac {
    static let attuale: String = {
        if let nome = SCDynamicStoreCopyComputerName(nil, nil) {
            let testo = nome as String
            if !testo.isEmpty { return testo }
        }
        return Host.current().localizedName ?? "Mac"
    }()
}

/// Indirizzi IPv4 del Mac per il QR code (funzione 2, aggiornamento 1.10): tutti quelli utili, il più probabile
/// per primo, perché il telefono li prova tutti insieme e usa il primo che risponde.
/// Ordine: Wi-Fi, cavo di rete, Hotspot personale dell'iPhone (172.20.10.x), ponte Thunderbolt, il resto.
/// Il Tethering USB di Android (NCM; il Mac non ha RNDIS) compare come un'altra `en*` di tipo `wiredEthernet`:
/// entra nel QR come cavo di rete, dopo il Wi-Fi. Non si distingue in modo sicuro da un adattatore Ethernet USB
/// (anche molti di quelli usano NCM), quindi non ha una priorità sua come su Windows.
/// Niente loopback né interfacce virtuali (VPN, macchine virtuali, Condivisione Internet); 169.254.x.x
/// solo se non c'è nient'altro. La stessa scelta di Windows/WebcamLR.Ricevitore/IndirizziLocali.cs.
enum IndirizziLocali {
    /// Oltre questi indirizzi il QR diventa fitto e difficile da inquadrare.
    static let massimo = 6

    /// `tipi`: il tipo di ogni interfaccia per nome, dall'ultimo percorso di rete (NWPathMonitor).
    /// Se un nome manca si decide dal nome: en0 di solito è il Wi-Fi sui portatili.
    static func ipv4(tipi: [String: NWInterface.InterfaceType] = [:]) -> [String] {
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
            trovati.append((String(cString: voce.ifa_name), String(cString: testo)))
        }
        return scegli(trovati, tipi: tipi)
    }

    /// La scelta e l'ordine, senza domande al sistema.
    static func scegli(_ voci: [(interfaccia: String, indirizzo: String)],
                       tipi: [String: NWInterface.InterfaceType]) -> [String] {
        let candidati = voci.enumerated().filter { voce in
            !virtuale(voce.element.interfaccia) && !voce.element.indirizzo.hasPrefix("127.")
        }
        // 169.254.x.x: indirizzo automatico senza rete vera; serve solo se non c'è nient'altro (cavo diretto).
        let utili = candidati.filter { !$0.element.indirizzo.hasPrefix("169.254.") }
        let scelti = utili.isEmpty ? candidati : utili
        let ordinati = scelti.sorted { primo, secondo in
            let p1 = priorita(primo.element, tipi: tipi)
            let p2 = priorita(secondo.element, tipi: tipi)
            return p1 != p2 ? p1 < p2 : primo.offset < secondo.offset
        }
        var visti = Set<String>()
        var unici: [String] = []
        for voce in ordinati where visti.insert(voce.element.indirizzo).inserted {
            unici.append(voce.element.indirizzo)
        }
        return Array(unici.prefix(massimo))
    }

    /// VPN (utun, ipsec, ppp), Wi-Fi diretto (awdl, llw: ha già la sua strada), macchine virtuali
    /// (vmnet, vboxnet, vnic, bridge100 e oltre, che crea anche Condivisione Internet), ZeroTier (feth, zt),
    /// interfacce interne di Apple (anpi, ap) e tunnel vari.
    static func virtuale(_ interfaccia: String) -> Bool {
        let prefissi = ["lo", "utun", "ipsec", "ppp", "gif", "stf", "awdl", "llw", "vmnet", "vboxnet", "vnic",
                        "anpi", "ap", "feth", "zt", "tun", "tap"]
        if prefissi.contains(where: { interfaccia.hasPrefix($0) }) { return true }
        // bridge0 è il ponte Thunderbolt, una rete vera tra due computer; bridge100 e oltre no.
        if interfaccia.hasPrefix("bridge"), let numero = Int(interfaccia.dropFirst("bridge".count)), numero >= 100 {
            return true
        }
        return false
    }

    /// 0 Wi-Fi, 1 cavo di rete, 2 Hotspot dell'iPhone, 3 ponte Thunderbolt, 4 il resto.
    static func priorita(_ voce: (interfaccia: String, indirizzo: String),
                         tipi: [String: NWInterface.InterfaceType]) -> Int {
        if dallHotspot(voce.indirizzo) { return 2 }
        if voce.interfaccia.hasPrefix("bridge") { return 3 }
        switch tipi[voce.interfaccia] {
        case .some(.wifi):
            return 0
        case .some(.wiredEthernet):
            return 1
        case .none:
            if voce.interfaccia == "en0" { return 0 }
            return voce.interfaccia.hasPrefix("en") ? 1 : 4
        default:
            return 4
        }
    }

    /// L'Hotspot personale dell'iPhone dà ai computer indirizzi 172.20.10.1–14.
    static func dallHotspot(_ indirizzo: String) -> Bool {
        let parti = indirizzo.split(separator: ".").compactMap { Int($0) }
        return parti.count == 4 && parti[0] == 172 && parti[1] == 20 && parti[2] == 10 && parti[3] < 16
    }
}

/// Il QR code da inquadrare con il telefono.
struct CodiceQR: View {
    let testo: String
    var lato: CGFloat = 180
    /// Per VoiceOver; nil = il QR per collegare il telefono.
    var descrizione: String?

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
        .padding(Spazi.stretto)
        .background(.white, in: RoundedRectangle(cornerRadius: Raggi.controllo))
        .accessibilityLabel(descrizione.map { Text($0) } ?? Text("QR code per collegare il telefono"))
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
    /// In fondo alla colonna di sinistra (interfaccia finale): centrato, senza la riga «Sul telefono…»
    /// (la dice chi lo contiene).
    var compatto = false

    var body: some View {
        // Indirizzi e nome già pronti nel ricevitore: niente domande al sistema a ogni disegno.
        let indirizzi = ricevitore.indirizzi
        VStack(alignment: compatto ? .center : .leading, spacing: Spazi.stretto) {
            if indirizzi.isEmpty {
                Text("Il Mac non è collegato a una rete: collegalo al Wi-Fi o al cavo.")
                    .font(.stile(.corpo))
                    .foregroundStyle(Tema.ambra)
                    .multilineTextAlignment(compatto ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                // Passo 7 (mac.md 16): l'errore con il pulsante che porta dove si risolve.
                Button("Apri Impostazioni Wi-Fi") { ImpostazioniDiSistema.apri(.wifi) }
                    .buttonStyle(StileSecondario())
            } else if let porta = ricevitore.porta {
                let associazione = Associazione(indirizzi: indirizzi, porta: porta,
                                                nome: NomeMac.attuale,
                                                versione: Sicurezza.versioneSicura,
                                                impronta: ricevitore.improntaMac, gettone: ricevitore.gettone)
                CodiceQR(testo: associazione.testo, lato: lato)
                // A capo e mai tagliati: nel riquadro stretto (popover di 240 punti, QR piccolo) non stanno su una riga.
                if !compatto {
                    Text("Sul telefono: «Inquadra il QR code del computer».")
                        .font(.stile(.nota))
                        .foregroundStyle(Tema.testoTenue)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Oppure scrivi: \(indirizzi[0])\(porta == Servizio.portaPredefinita ? "" : ":\(porta)")")
                    .font(.numeri(compatto ? 11 : 12))
                    .multilineTextAlignment(compatto ? .center : .leading)
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if case .errore = ricevitore.rete {
                Text("La rete non risponde: controlla il Wi-Fi e scegli «Riprova».")
                    .font(.stile(.corpo))
                    .foregroundStyle(Tema.ambra)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Riprova") { ricevitore.avvia() }
                    .buttonStyle(StileSecondario())
            } else {
                // Il ricevitore sta aprendo la porta (una frazione di secondo all'avvio): stesso spazio del QR.
                ProgressView()
                    .controlSize(.small)
                    .frame(width: lato + 20, height: lato + 20)
                    .background(Tema.pannello, in: RoundedRectangle(cornerRadius: Raggi.controllo))
                    .accessibilityLabel("Preparo il QR code")
            }
        }
        // Un indirizzo cambiato senza che la rete lo annunci (per esempio un nuovo indirizzo dal router).
        .onAppear { ricevitore.aggiornaIndirizzi() }
    }
}
