/// Le chiavi delle preferenze salvate in UserDefaults, in un posto solo.
enum Preferenze {
    /// Anteprima specchiata (solo sul Mac: le altre app ricevono il video dritto).
    static let specchia = "specchia"
    /// Specchia a ogni apertura dell'app (funzione 35).
    static let specchiaDiSerie = "specchiaDiSerie"
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
}
