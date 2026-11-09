import Darwin
import Foundation

/// Il cavo USB di Android (Qualità 17): il minimo del protocollo con il server di adb, scritto da zero come usbmux
/// (Documenti/Protocollo.md, «Cavo USB con Android: adb»; la scelta in Documenti/Cavo USB Android.md). Le stesse
/// regole di Windows/WebcamLR.Ricevitore/ProtocolloAdb.cs, che ha i test.
///
/// Il server di adb gira sul Mac (lo avvia adb stesso, Android Studio, scrcpy…) e risponde su 127.0.0.1:5037. Ogni
/// richiesta è la lunghezza in 4 cifre esadecimali e il testo («0012host:track-devices»); la risposta è «OKAY», oppure
/// «FAIL» con un messaggio. Per il canale verso il telefono: «host:transport:seriale» e poi «tcp:52741» sulla stessa
/// connessione; con due «OKAY» il socket è la connessione con WebcamLR sul telefono, come dopo il `Connect` di usbmux.
///
/// Dal sandbox basta `com.apple.security.network.client` (connessione TCP su loopback). Avviare adb da qui no: il
/// sandbox lo impedisce. Se il server non c'è, la guida dice come averlo (Documenti/Cavo USB Android.md).
/// Socket BSD bloccanti, sempre fuori dalla coda principale.
enum Adb {
    static let portaServer: UInt16 = 5037

    /// Che cosa dice adb di un telefono (la seconda colonna di «adb devices»).
    enum StatoTelefono: Equatable, Sendable {
        /// «device»: debug USB consentito.
        case pronto
        /// «unauthorized»: sul telefono c'è la domanda «Consentire il debug USB?».
        case nonAutorizzato
        /// «offline», «authorizing», «no permissions», «recovery»…: per ora non si usa.
        case altro
    }

    struct Telefono: Equatable, Sendable {
        let seriale: String
        let stato: StatoTelefono
    }

    /// Una richiesta: lunghezza in 4 cifre esadecimali e testo.
    static func richiesta(_ servizio: String) -> Data {
        let testo = Data(servizio.utf8)
        let esadecimale = String(testo.count, radix: 16)
        let lunghezza = String(repeating: "0", count: max(0, 4 - esadecimale.count)) + esadecimale
        return Data(lunghezza.utf8) + testo
    }

    /// Le righe di «host:track-devices»: «seriale\tstato». Va bene anche il formato lungo con gli spazi.
    static func leggiElenco(_ testo: String) -> [Telefono] {
        testo.split(separator: "\n").compactMap { grezza -> Telefono? in
            let riga = grezza.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let seriale: String
            let stato: String
            if let tab = riga.firstIndex(of: "\t") {
                seriale = String(riga[..<tab]).trimmingCharacters(in: .whitespaces)
                stato = String(riga[riga.index(after: tab)...]).trimmingCharacters(in: .whitespaces)
            } else {
                let parti = riga.split(separator: " ").map(String.init)
                guard parti.count >= 2 else { return nil }
                seriale = parti[0]
                stato = parti.dropFirst().prefix(while: { !$0.contains(":") }).joined(separator: " ")
            }
            guard !seriale.isEmpty, !stato.isEmpty else { return nil }
            switch stato {
            case "device": return Telefono(seriale: seriale, stato: .pronto)
            case "unauthorized": return Telefono(seriale: seriale, stato: .nonAutorizzato)
            default: return Telefono(seriale: seriale, stato: .altro)
            }
        }
    }

    /// Il debug wireless («192.168.1.5:5555», «adb-…._adb-tls-connect._tcp») e gli emulatori non sono il cavo.
    static func viaUSB(_ seriale: String) -> Bool {
        !seriale.isEmpty && !seriale.contains(":") && !seriale.hasPrefix("emulator-") && !seriale.contains("._adb-tls-")
    }

    /// Un socket collegato al server di adb, oppure nil (server spento).
    static func apri() -> Int32? {
        let descrittore = socket(AF_INET, SOCK_STREAM, 0)
        guard descrittore >= 0 else { return nil }
        var indirizzo = sockaddr_in()
        indirizzo.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        indirizzo.sin_family = sa_family_t(AF_INET)
        indirizzo.sin_port = portaServer.bigEndian
        indirizzo.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian)
        let esito = withUnsafePointer(to: &indirizzo) { puntatore in
            puntatore.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descrittore, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard esito == 0 else {
            close(descrittore)
            return nil
        }
        var uno: Int32 = 1
        setsockopt(descrittore, SOL_SOCKET, SO_NOSIGPIPE, &uno, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(descrittore, IPPROTO_TCP, TCP_NODELAY, &uno, socklen_t(MemoryLayout<Int32>.size))
        return descrittore
    }

    /// La risposta a una richiesta: vero con «OKAY», falso con «FAIL» (il messaggio si legge e si scarta) o se il
    /// socket si chiude. Legge solo i byte della risposta: dopo l'«OKAY» di «tcp:52741» segue già il telefono.
    static func esito(da descrittore: Int32) -> Bool {
        guard let quattro = Usbmux.leggi(4, da: descrittore) else { return false }
        switch String(decoding: quattro, as: UTF8.self) {
        case "OKAY": return true
        case "FAIL":
            _ = blocco(da: descrittore)
            return false
        default: return false
        }
    }

    /// Un blocco con la lunghezza in testa (4 cifre esadecimali); nil se il socket si chiude o la lunghezza non va.
    static func blocco(da descrittore: Int32) -> String? {
        guard let quattro = Usbmux.leggi(4, da: descrittore),
              let lunghezza = Int(String(decoding: quattro, as: UTF8.self), radix: 16) else { return nil }
        guard let corpo = Usbmux.leggi(lunghezza, da: descrittore) else { return nil }
        return String(decoding: corpo, as: UTF8.self)
    }

    /// Il canale verso la porta del telefono: «host:transport:seriale» e «tcp:porta». Nil se l'app sul telefono non
    /// ascolta (adb risponde «FAIL closed»), se il telefono non è autorizzato o se il server non c'è.
    static func collega(seriale: String, porta: UInt16) -> Int32? {
        guard let descrittore = apri() else { return nil }
        var attesa = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descrittore, SOL_SOCKET, SO_RCVTIMEO, &attesa, socklen_t(MemoryLayout<timeval>.size))
        guard Usbmux.scrivi(richiesta("host:transport:" + seriale), su: descrittore), esito(da: descrittore),
              Usbmux.scrivi(richiesta("tcp:\(porta)"), su: descrittore), esito(da: descrittore) else {
            close(descrittore)
            return nil
        }
        var nessuna = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(descrittore, SOL_SOCKET, SO_RCVTIMEO, &nessuna, socklen_t(MemoryLayout<timeval>.size))
        return descrittore
    }
}
