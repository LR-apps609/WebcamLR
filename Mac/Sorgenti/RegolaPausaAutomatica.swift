import Foundation
import WebcamLRProtocollo

/// Cosa sa il Mac, adesso, del bisogno del video del telefono (Qualità 18, Protocollo.md, «Pausa automatica»).
/// Come `UsoVideo` di Windows (WebcamLR.Ricevitore/RegolaPausaAutomatica.cs, provato lì con i test).
struct UsoVideo: Equatable {
    /// «Pausa quando nessuna app usa la webcam» (Impostazioni › Uscite), acceso di serie.
    var interruttore: Bool
    /// La webcam virtuale risponde (Camera Extension, solo con l'account a pagamento): senza, il Mac non sa se un'app la
    /// usa e la funzione resta spenta.
    var saLeggereUso: Bool
    var webcamInUso: Bool
    var registra: Bool
    /// La finestra principale è quella in primo piano (attiva), oppure è aperta la finestra mini.
    var finestraGuardata: Bool

    /// La funzione può lavorare: interruttore acceso e uso della webcam leggibile.
    var possibile: Bool { interruttore && saLeggereUso }

    /// Il video serve adesso: niente pausa, e se c'è finisce subito.
    var serve: Bool { !possibile || webcamInUso || registra || finestraGuardata }
}

/// Qualità 18, la pausa automatica: quando il video non serve da almeno `attesa` secondi, il Mac chiede ai telefoni di
/// fermare fotocamera e codifica (`pausa-automatica`); appena serve di nuovo, la toglie subito. Tempi in secondi
/// dall'orologio di chi la usa (`ProcessInfo.systemUptime`). Vale per tutti i telefoni insieme, come su Windows.
struct RegolaPausaAutomatica {
    /// 20 secondi, come su Windows.
    static let attesa = TimeInterval(Servizio.secondiPausaAutomatica)
    /// In pausa la webcam si controlla più spesso: il video riparte in meno di un secondo.
    static let controlloRapido = Duration.milliseconds(250)
    static let controlloNormale = Duration.seconds(1)

    /// Da quando il video non serve; nil se serve.
    private(set) var inutileDa: TimeInterval?
    /// Vero se adesso il Mac chiede la pausa ai telefoni.
    private(set) var pausa = false

    /// La decisione per adesso: vero = chiedere la pausa automatica.
    mutating func valuta(_ uso: UsoVideo, adesso: TimeInterval) -> Bool {
        guard !uso.serve else {
            inutileDa = nil
            pausa = false
            return false
        }
        // L'orologio tornato indietro (non dovrebbe): si riparte a contare da qui.
        if inutileDa == nil || adesso < inutileDa! { inutileDa = adesso }
        pausa = adesso - inutileDa! >= Self.attesa
        return pausa
    }

    /// Un telefono appena collegato, o l'interruttore appena acceso: la pausa finisce e i secondi ripartono da capo.
    mutating func riparti(adesso: TimeInterval) {
        if inutileDa != nil { inutileDa = adesso }
        pausa = false
    }

    /// Ogni quanto leggere l'uso della webcam virtuale.
    var controllo: Duration { pausa ? Self.controlloRapido : Self.controlloNormale }
}
