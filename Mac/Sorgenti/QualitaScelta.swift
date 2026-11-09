import Foundation
import WebcamLRProtocollo

/// Qualità 15 (Documenti/Protocollo.md, «Qualità a scelta»): Auto, Alta o Massima per il flusso dal telefono. Si sceglie
/// qui, nel menu della qualità sopra il video (come le risoluzioni), e vale per tutti i telefoni che la sanno fare
/// (`capacita.sceltaQualita`). Il Mac la salva e la rimanda a ogni sessione; il telefono la conferma in `stato.qualita`.
extension Ricevitore {
    /// La scelta salvata su questo Mac; Auto se non c'è.
    var qualitaScelta: String {
        LivelliQualita.normalizza(UserDefaults.standard.string(forKey: Preferenze.qualitaFlusso))
    }

    /// Il telefono nella webcam accetta `comando.qualita`: solo allora il menu mostra la scelta.
    var sceltaQualitaDisponibile: Bool {
        telefonoAttivo && capacita?.sceltaQualita == true
    }

    /// Quella in uso sul telefono nella webcam (`stato.qualita`, l'unica fonte di verità), altrimenti quella scelta qui.
    var qualitaInUso: String {
        LivelliQualita.normalizza(statoTelefono?.qualita ?? qualitaScelta)
    }

    /// Dal menu: salva e manda a ogni telefono collegato che la sa fare.
    func scegliQualita(_ livello: String) {
        let nuovo = LivelliQualita.normalizza(livello)
        UserDefaults.standard.set(nuovo, forKey: Preferenze.qualitaFlusso)
        for telefono in telefoni { mandaQualita(nuovo, a: telefono) }
    }

    /// Alla `capacita` (Ricevitore): la scelta salvata, una volta per sessione, anche Auto (il telefono può essere
    /// rimasto su un'altra scelta di prima).
    func mandaQualitaSeServe(_ telefono: TelefonoCollegato) {
        guard let sessione = telefono.sessione, telefono.qualitaInviataA !== sessione else { return }
        mandaQualita(qualitaScelta, a: telefono)
    }

    /// Con Massima, al telefono nella webcam prima il `formato` più alto del menu (così il codec è quello giusto, HEVC
    /// per il 4K), poi `comando.qualita`: il telefono si riconfigura una volta sola.
    private func mandaQualita(_ livello: String, a telefono: TelefonoCollegato) {
        guard let sessione = telefono.sessione, telefono.capacita?.sceltaQualita == true else { return }
        telefono.qualitaInviataA = sessione
        if livello == LivelliQualita.massima, telefono === attivo,
           let piuAlta = OpzioneQualita.elenco(telefono.capacita).last {
            chiediFormato(larghezza: piuAlta.larghezza, altezza: piuAlta.altezza, fps: piuAlta.fps)
        }
        registra(String(localized: "Qualità chiesta al telefono: \(Self.nomeQualita(livello))"), di: telefono)
        sessione.comanda(Comando(qualita: livello))
    }

    /// «Auto», «Alta», «Massima».
    static func nomeQualita(_ livello: String) -> String {
        switch LivelliQualita.normalizza(livello) {
        case LivelliQualita.alta: String(localized: "Alta")
        case LivelliQualita.massima: String(localized: "Massima")
        default: String(localized: "Auto")
        }
    }

    /// La nota breve accanto alla scelta nel menu.
    static func notaQualita(_ livello: String) -> String {
        switch LivelliQualita.normalizza(livello) {
        case LivelliQualita.alta: String(localized: "più nitida")
        case LivelliQualita.massima: String(localized: "il massimo del telefono")
        default: String(localized: "segue la rete")
        }
    }
}
