import Foundation
import Security
import WebcamLRProtocollo

/// Un telefono che può collegarsi senza domande (protocollo 2, «Prova e abbinamento»).
struct TelefonoFidato: Identifiable, Hashable, Sendable {
    let impronta: String
    let nome: String

    var id: String { impronta }
}

/// Chi può collegarsi a questo Mac: i telefoni fidati, chi rimanda il gettone del QR code mostrato ora,
/// oppure chi l'utente conferma con il codice di 4 cifre. La stessa logica di Windows/WebcamLR.Ricevitore/Abbinamento.cs.
/// Si usa dalla coda della sessione e dall'interfaccia: tutto passa da un lucchetto.
final class Abbinamento: @unchecked Sendable {
    let identita: IdentitaDispositivo

    private let blocco = NSLock()
    /// Impronta del telefono → nome.
    private var fidatiSalvati: [String: String]
    private var gettoneAttuale = Sicurezza.nuovoGettone()
    private var avvisoCambio: (@Sendable () -> Void)?

    init(identita: IdentitaDispositivo) {
        self.identita = identita
        fidatiSalvati = UserDefaults.standard.dictionary(forKey: Preferenze.telefoniFidati) as? [String: String] ?? [:]
    }

    /// Chiamata (da qualsiasi coda) quando cambiano il gettone o i telefoni fidati.
    var suCambio: (@Sendable () -> Void)? {
        get {
            blocco.lock()
            defer { blocco.unlock() }
            return avvisoCambio
        }
        set {
            blocco.lock()
            avvisoCambio = newValue
            blocco.unlock()
        }
    }

    /// Il gettone del QR code mostrato ora: cambia a ogni avvio e dopo ogni uso.
    var gettone: String {
        blocco.lock()
        defer { blocco.unlock() }
        return gettoneAttuale
    }

    /// In ordine di nome, per le impostazioni.
    var fidati: [TelefonoFidato] {
        blocco.lock()
        defer { blocco.unlock() }
        return fidatiSalvati
            .map { TelefonoFidato(impronta: $0.key, nome: $0.value) }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
    }

    func fidato(_ impronta: String) -> Bool {
        blocco.lock()
        defer { blocco.unlock() }
        return fidatiSalvati[impronta] != nil
    }

    func fida(_ impronta: String, nome: String) {
        blocco.lock()
        // Già fidato con lo stesso nome (ogni ricollegamento): niente da salvare né da ridisegnare (1.11).
        if fidatiSalvati[impronta] == nome {
            blocco.unlock()
            return
        }
        fidatiSalvati[impronta] = nome
        let copia = fidatiSalvati
        blocco.unlock()
        UserDefaults.standard.set(copia, forKey: Preferenze.telefoniFidati)
        suCambio?()
    }

    func rimuovi(_ impronta: String) {
        blocco.lock()
        guard fidatiSalvati.removeValue(forKey: impronta) != nil else {
            blocco.unlock()
            return
        }
        let copia = fidatiSalvati
        blocco.unlock()
        UserDefaults.standard.set(copia, forKey: Preferenze.telefoniFidati)
        suCambio?()
    }

    /// Vero se il gettone è quello del QR code attuale; in quel caso il QR cambia.
    func usaGettone(_ proposto: String?) -> Bool {
        guard let proposto, !proposto.isEmpty else { return false }
        blocco.lock()
        // Confronto a tempo costante: dalla durata non si indovina il gettone.
        guard Self.ugualiATempoCostante(Array(proposto.utf8), Array(gettoneAttuale.utf8)) else {
            blocco.unlock()
            return false
        }
        gettoneAttuale = Sicurezza.nuovoGettone()
        blocco.unlock()
        suCambio?()
        return true
    }

    /// Come CryptographicOperations.FixedTimeEquals: la lunghezza diversa si vede subito, il contenuto no.
    static func ugualiATempoCostante(_ primo: [UInt8], _ secondo: [UInt8]) -> Bool {
        guard primo.count == secondo.count else { return false }
        var differenza: UInt8 = 0
        for indice in primo.indices {
            differenza |= primo[indice] ^ secondo[indice]
        }
        return differenza == 0
    }
}

/// La chiave di firma permanente del Mac, nel Portachiavi come password generica (va bene anche nella sandbox).
enum Portachiavi {
    private static let servizio = "it.lrapps.webcamlr.identita"
    private static let conto = "mac"

    /// La crea alla prima apertura, poi la rilegge sempre uguale: è ciò che i telefoni riconoscono.
    static func identitaMac() -> IdentitaDispositivo {
        let ricerca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servizio,
            kSecAttrAccount as String: conto
        ]
        var domanda = ricerca
        domanda[kSecReturnData as String] = true
        domanda[kSecMatchLimit as String] = kSecMatchLimitOne
        var risultato: CFTypeRef?
        let esito = SecItemCopyMatching(domanda as CFDictionary, &risultato)
        if esito == errSecSuccess, let dati = risultato as? Data,
           let salvata = try? IdentitaDispositivo(datiSalvati: dati) {
            return salvata
        }

        let nuova = IdentitaDispositivo()
        // Un errore diverso da «non c'è» (Portachiavi bloccato, accesso negato) non deve cancellare
        // la chiave buona: per questa volta si usa una chiave nuova, senza salvarla.
        guard esito == errSecItemNotFound || esito == errSecSuccess else { return nuova }
        if esito == errSecSuccess {
            // C'era, ma illeggibile: si sostituisce.
            _ = SecItemDelete(ricerca as CFDictionary)
        }
        var aggiunta = ricerca
        aggiunta[kSecValueData as String] = nuova.datiDaSalvare
        aggiunta[kSecAttrLabel as String] = "WebcamLR · identità di questo Mac"
        _ = SecItemAdd(aggiunta as CFDictionary, nil)
        return nuova
    }
}
