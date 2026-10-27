/// Le chiavi delle preferenze salvate in UserDefaults, in un posto solo.
enum Preferenze {
    /// Chiavi di prima della 1.14 (lo specchio solo dell'anteprima): ora lo specchio è uno solo, del telefono
    /// (`stato.specchia`). Si cancellano all'avvio.
    static let vecchieSpecchio = ["specchia", "specchiaDiSerie"]
    /// Notifiche di WebcamLR accese (funzione 22).
    static let notifiche = "notifiche"
    /// Vista pulita: solo il video, senza barre e pulsanti (funzione 29).
    static let vistaPulita = "vistaPulita"
    /// Il video riempie il riquadro invece di vedersi intero (funzione 30).
    static let riempi = "riempi"
    /// Telefoni fidati del collegamento sicuro (0.10): impronta → nome.
    static let telefoniFidati = "telefoniFidati"
    /// La scheda aperta nella finestra «App e assistenza» (0.12).
    static let schedaApp = "schedaApp"
    /// La domanda frequente da aprire nella scheda «Domande frequenti» (1.4): la scrive chi ci porta lì, la scheda la consuma.
    static let domandaFrequente = "domandaFrequente"
    /// Wi-Fi diretto (0.11), spento di serie: fa saltare la radio Wi-Fi tra due canali e rende la latenza meno stabile.
    static let wifiDiretto = "wifiDiretto"
    /// Microfono del telefono acceso (P20): si richiede a ogni telefono che sa mandare l'audio.
    static let microfonoTelefono = "microfonoTelefono"
    /// L'ultimo livello di sfocatura di «Sfondo» sotto il video (`LivelloSfocatura`: poco, medio, tanto).
    static let livelloSfocatura = "livelloSfocatura"
    /// L'ultima scelta del pulsante «Sfondo» (`ImmaginiComputer.ultimaScelta`): «sfocatura» o l'id di uno sfondo.
    static let ultimoSfondo = "ultimoSfondo"
    /// L'ultimo profilo pronto scelto nel pannello «Profilo» (Profili.swift).
    static let profiloPronto = "profiloPronto"
    /// Le sezioni richiudibili del pannello di destra, aperte o chiuse (chiuse di serie).
    static let sezioneEffetti = "sezioneEffettiAperta"
    static let sezioneRegoleFini = "sezioneRegoleFiniAperta"
    /// La vista della finestra principale (`VistaFinestra`): «essenziale» o «completo».
    static let vista = "vista"

    /// Chiavi che ci sono solo se WebcamLR è già stata aperta su questo Mac (`vistaPulita` si scrive a ogni avvio).
    private static let segniDiUnUsoPrecedente = [vistaPulita, riempi, notifiche, telefoniFidati, wifiDiretto,
                                                 microfonoTelefono, schedaApp, ultimoSfondo, profiloPronto,
                                                 sezioneEffetti, sezioneRegoleFini]

    /// La prima volta con le tre viste: chi aveva già usato WebcamLR resta su «Completo», com'era; un'installazione
    /// nuova parte da «Essenziale». Va chiamata all'avvio, prima di qualsiasi altra scrittura nelle preferenze.
    static func preparaVista() {
        let preferenze = UserDefaults.standard
        guard preferenze.string(forKey: vista) == nil else { return }
        let giaUsata = segniDiUnUsoPrecedente.contains { preferenze.object(forKey: $0) != nil }
        preferenze.set((giaUsata ? VistaFinestra.completo : VistaFinestra.essenziale).rawValue, forKey: vista)
    }
}
