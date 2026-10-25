import Darwin
import Foundation

/// 1.11: quanto ci vuole ad avere il video sul computer. Si misura fino al primo fotogramma spedito dopo il `benvenuto`
/// (il primo fotogramma chiave consegnato alla rete): si vede in «In onda» («Avvio: 1,4 s») e nel registro.
enum MisuraAvvio {
    /// Il momento in cui iOS ha avviato l'app (il processo); se non si riesce a leggerlo, il primo uso di questo valore,
    /// che `WebcamLRApp` fa all'avvio.
    static let aperturaApp: Date = {
        var informazioni = kinfo_proc()
        var dimensione = MemoryLayout<kinfo_proc>.stride
        var nomi: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let esito = nomi.withUnsafeMutableBufferPointer { puntatore in
            sysctl(puntatore.baseAddress, 4, &informazioni, &dimensione, nil, 0)
        }
        // `p_starttime` in C è una macro (`p_un.__p_starttime`): Swift non la importa, si usa il campo vero.
        let inizio = informazioni.kp_proc.p_un.__p_starttime
        guard esito == 0, inizio.tv_sec > 0 else { return Date() }
        let data = Date(timeIntervalSince1970: TimeInterval(inizio.tv_sec) + TimeInterval(inizio.tv_usec) / 1_000_000)
        // Un valore assurdo (nel futuro o di ore fa) non serve: si usa adesso.
        let fa = Date().timeIntervalSince(data)
        return fa >= 0 && fa < 60 ? data : Date()
    }()

    /// Il primo video di questo avvio dell'app: solo per lui il registro dice anche il tempo dall'apertura.
    @MainActor static var primoVideoMisurato = false

    /// «1,4 s», con la virgola.
    static func testo(_ secondi: TimeInterval) -> String {
        String(format: "%.1f s", max(secondi, 0)).replacingOccurrences(of: ".", with: ",")
    }
}

/// 1.11: da dove parte la misura dell'avvio di una sessione.
enum OrigineAvvio {
    /// Tocco su un computer della lista o «Collega» con l'indirizzo scritto.
    case tocco
    /// QR code appena letto.
    case qr
    /// Ricollegamento da solo all'ultimo computer, quando compare nella ricerca. 1.14: la misura che si mostra
    /// riparte alla fine del conto alla rovescia (`SessioneTelefono.conferma`); il tempo dall'apertura dell'app
    /// resta solo nel registro, per il primo video di ogni avvio.
    case comparsa
    /// Il computer ha aperto la connessione sul cavo USB.
    case cavo

    /// 1.14: sempre adesso, il momento del tocco (o della lettura, della comparsa, del cavo): mai l'avvio del
    /// processo, che contava anche presentazione, fogli e ricerca.
    var inizio: Date {
        Date()
    }

    var testo: String {
        switch self {
        case .tocco: "dal tocco"
        case .qr: "dalla lettura del QR code"
        case .comparsa: "dalla comparsa del computer"
        case .cavo: "dall'arrivo del cavo"
        }
    }
}
