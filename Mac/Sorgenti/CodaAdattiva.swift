import Foundation

// Qualità 14: la coda di ricezione che si adatta (Documenti/Protocollo.md, «Latenza»). La stessa logica di Windows
// (Windows/WebcamLR.Ricevitore/CodaAdattiva.cs), provata là con tempi finti in CodaAdattivaTest.cs: qui Swift non si
// prova, quindi le due vanno tenute uguali.

/// Quanto far aspettare le immagini sul Mac prima di mostrarle: il meno possibile con la rete stabile, un po' di più solo
/// quando il ritardo varia (jitter), mai oltre `tetto`.
///
/// Per ogni immagine si guarda il suo **margine**: quanto prima del suo istante di uscita è pronta (negativo = in ritardo,
/// si vedrà uno scatto). Degli ultimi `finestra` margini si prende il «basso»: il più piccolo dopo aver lasciato fuori i
/// `tollerati` peggiori (una pausa isolata della rete non fa crescere la coda, una che torna sì). Se il basso è sopra
/// l'obiettivo di oltre `isteresi`, la coda si accorcia; se è sotto, si allunga (ma l'immagine arrivata prima non aspetta
/// mai oltre il tetto); ogni volta di al massimo `passoMassimo` per immagine. I margini già in finestra si correggono
/// dello stesso passo. Sul Mac si usa `uscita(cattura:adesso:)`: l'istante è la cattura più un ritardo che si adatta.
/// Nessun tetto allo spostamento totale (la deriva tra gli orologi si accumula, collaudo 38). Solo su una coda.
struct CodaAdattiva {
    /// Quanti margini si guardano: 5 secondi a 30 fps.
    static let finestra = 150
    /// Prima di questi margini non si cambia nulla.
    static let minimi = 30
    /// Le immagini più in ritardo, su una finestra intera, che non fanno crescere la coda (il 2%).
    static let tollerati = 3
    /// µs per immagine, al massimo.
    static let passoMassimo: Int64 = 2_000
    /// Sopra l'obiettivo di meno di questo (µs) non si accorcia.
    static let isteresi: Int64 = 3_000
    /// La coda più profonda (µs): oltre, meglio uno scatto che altro ritardo.
    static let tetto: Int64 = 100_000
    /// Un margine oltre questo (µs) non è credibile (orologi cambiati).
    static let margineAssurdo: Int64 = 2_000_000
    /// Mac: l'immagine è già decodificata, basta la precisione del timer.
    static let obiettivoMac: Int64 = 2_000

    /// Il margine voluto per il «basso» della finestra (µs).
    let obiettivo: Int64
    /// Di quanto la coda è stata accorciata in tutto (µs); negativo se allungata più che accorciata.
    private(set) var spostamento: Int64 = 0
    /// In ordine di arrivo; al massimo `finestra`.
    private var margini: [Int64] = []
    /// Dalla cattura all'uscita (µs); nil prima della prima immagine.
    private var ritardoUscita: Int64?

    init(obiettivo: Int64 = CodaAdattiva.obiettivoMac) {
        self.obiettivo = obiettivo
        margini.reserveCapacity(Self.finestra + 1)
    }

    /// La profondità della coda adesso: il margine più grande della finestra (µs). 0 senza misure.
    var profondita: Int64 { max(margini.max() ?? 0, 0) }

    /// Il margine di un'immagine, con la coda già corretta. Restituisce di quanto accorciarla (positivo), allungarla
    /// (negativo) o 0; `spostamento` cambia dello stesso valore.
    @discardableResult
    mutating func aggiungi(margine: Int64) -> Int64 {
        guard margine <= Self.margineAssurdo, margine >= -Self.margineAssurdo else {
            margini.removeAll(keepingCapacity: true)
            return 0
        }
        margini.append(margine)
        if margini.count > Self.finestra { margini.removeFirst() }
        guard margini.count >= Self.minimi else { return 0 }

        let ordinati = margini.sorted()
        let basso = ordinati[Self.tollerati * ordinati.count / Self.finestra]
        let alto = ordinati[ordinati.count - 1]

        var passo: Int64 = 0
        if alto > Self.tetto {
            // Troppo profonda (la prima immagine era arrivata tardi, o una rete pessima): si accorcia comunque.
            passo = min(Self.passoMassimo, alto - Self.tetto)
        } else if basso > obiettivo + Self.isteresi {
            passo = min(Self.passoMassimo, basso - obiettivo)
        } else if basso < obiettivo {
            passo = -min(Self.passoMassimo, obiettivo - basso, max(0, Self.tetto - alto))
        }
        guard passo != 0 else { return 0 }
        spostamento += passo
        // I margini in fila valevano per la coda di prima.
        for indice in margini.indices { margini[indice] -= passo }
        return passo
    }

    /// L'istante (`Orologio`, µs) in cui far uscire un'immagine catturata a `cattura` (orologio del Mac, µs) e pronta
    /// `adesso`; può essere già passato (immagine in ritardo). nil se il transito non è credibile: l'immagine esce subito
    /// e non entra nelle misure.
    mutating func uscita(cattura: Int64, adesso: UInt64) -> UInt64? {
        let transito = Int64(truncatingIfNeeded: adesso) &- cattura
        guard transito >= 0, transito < Int64(RitardoVetro.massimoMs) * 1000 else { return nil }
        var ritardo: Int64
        if let attuale = ritardoUscita, abs(attuale - transito) <= Self.margineAssurdo {
            ritardo = attuale
        } else {
            // La prima immagine, o gli orologi cambiati di colpo: si riparte da questa, con il margine voluto.
            margini.removeAll(keepingCapacity: true)
            ritardo = transito + obiettivo
        }
        ritardo -= aggiungi(margine: ritardo - transito)
        ritardoUscita = ritardo
        return UInt64(max(cattura &+ ritardo, 0))
    }

    /// Scarta le vecchie invece di accumulare ritardo: delle immagini in fila (i loro istanti, in ordine), quante delle
    /// prime buttare perché ce n'è una più recente già al suo momento. Si mostra solo l'ultima scaduta.
    static func daScartare(_ istanti: [UInt64], adesso: UInt64, anticipo: UInt64) -> Int {
        var scadute = 0
        while scadute < istanti.count, istanti[scadute] <= adesso + anticipo { scadute += 1 }
        return max(scadute - 1, 0)
    }
}
