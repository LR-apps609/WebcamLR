import Foundation
import Security
import WebcamLRProtocollo

/// L'identità permanente del telefono (protocollo 2, «Identità»): la chiave di firma si crea una volta
/// e resta nel Portachiavi, solo su questo iPhone. I computer la riconoscono tra i telefoni fidati.
enum IdentitaTelefono {
    private static let servizio = "it.lrapps.webcamlr.identita"
    private static let account = "chiave-di-firma"

    /// Letta (o creata) alla prima richiesta, poi sempre la stessa per tutta la vita dell'app.
    /// La lettura del Portachiavi parte in sottofondo all'avvio (`prepara()`), non al tocco su «Collega».
    static var condivisa: IdentitaDispositivo { caricata.identita }

    /// Vero se il Portachiavi non ha letto o salvato l'identità: questa vale solo fino alla chiusura
    /// dell'app, e al prossimo avvio il computer chiederà di nuovo il codice di conferma.
    static var soloPerQuestaVolta: Bool { caricata.temporanea }

    private static let caricata: (identita: IdentitaDispositivo, temporanea: Bool) = caricaOCrea()

    /// Da chiamare all'avvio: legge il Portachiavi fuori dal thread principale.
    static func prepara() {
        DispatchQueue.global(qos: .userInitiated).async { _ = caricata }
    }

    private static func caricaOCrea() -> (identita: IdentitaDispositivo, temporanea: Bool) {
        let ricerca: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servizio,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var risultato: CFTypeRef?
        let stato = SecItemCopyMatching(ricerca as CFDictionary, &risultato)
        if stato == errSecSuccess, let dati = risultato as? Data,
           let salvata = try? IdentitaDispositivo(datiSalvati: dati) {
            return (salvata, false)
        }

        let nuova = IdentitaDispositivo()
        // Si sostituisce solo se non c'è o è rovinata: con altri errori (per esempio il Portachiavi
        // non ancora sbloccato) si usa una chiave solo per questa volta, senza cancellare quella vera.
        guard stato == errSecItemNotFound || stato == errSecSuccess else { return (nuova, true) }
        let elemento: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servizio,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(elemento as CFDictionary)
        var daSalvare = elemento
        daSalvare[kSecValueData as String] = nuova.datiDaSalvare
        daSalvare[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // Se il salvataggio non riesce l'identità cambierebbe a ogni avvio senza dirlo: lo si segnala.
        let salvata = SecItemAdd(daSalvare as CFDictionary, nil) == errSecSuccess
        return (nuova, !salvata)
    }
}

/// «Computer conosciuti» (protocollo 2, «Fiducia del telefono verso il computer»): nome del computer → impronta
/// della sua chiave, salvata dopo il primo `benvenuto`. Se un computer con lo stesso nome si presenta con
/// un'altra impronta, il telefono si ferma: va riabbinato con il QR code.
enum ComputerConosciuti {
    private static let chiave = "computerConosciuti"

    struct Voce: Identifiable, Hashable {
        let nome: String
        let impronta: String
        var id: String { nome }
    }

    static var tutti: [Voce] {
        elenco.map { Voce(nome: $0.key, impronta: $0.value) }
            .sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    static func impronta(di nome: String) -> String? {
        elenco[nome]
    }

    static func salva(_ impronta: String, per nome: String) {
        var nuovo = elenco
        guard nuovo[nome] != impronta else { return }
        nuovo[nome] = impronta
        UserDefaults.standard.set(nuovo, forKey: chiave)
    }

    static func dimentica(_ nome: String) {
        var nuovo = elenco
        nuovo.removeValue(forKey: nome)
        UserDefaults.standard.set(nuovo, forKey: chiave)
    }

    private static var elenco: [String: String] {
        UserDefaults.standard.dictionary(forKey: chiave) as? [String: String] ?? [:]
    }
}
