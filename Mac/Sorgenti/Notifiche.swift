import AppKit
import Foundation
import UserNotifications

/// Notifiche di macOS (funzione 22): telefono collegato o perso, batteria bassa, registrazione salvata.
/// Il permesso si chiede la prima volta che servono (il primo telefono collegato), mai all'avvio.
/// Arrivano solo quando WebcamLR non è in primo piano, tranne «registrazione salvata».
@MainActor
final class Notifiche: NSObject {
    static let condivise = Notifiche()

    /// Chiave in `userInfo` con il percorso del file da mostrare nel Finder al clic.
    nonisolated private static let chiaveFile = "file"

    /// L'interruttore nelle impostazioni; acceso di serie.
    var attive: Bool {
        UserDefaults.standard.object(forKey: Preferenze.notifiche) as? Bool ?? true
    }

    /// Da chiamare all'avvio: serve per mostrare le notifiche anche con l'app in primo piano e per i clic.
    func prepara() {
        UNUserNotificationCenter.current().delegate = self
    }

    func telefonoCollegato(_ nome: String) {
        // Il primo telefono collegato è il primo momento in cui le notifiche servono davvero.
        chiediPermesso()
        invia(titolo: "\(nome) collegato", testo: "Il video dell'iPhone arriva su questo Mac.")
    }

    func telefonoPerso(_ nome: String) {
        invia(titolo: "\(nome) perso", testo: "Il telefono non è tornato. Riapri WebcamLR sull'iPhone per ricollegarlo.")
    }

    func batteriaBassa(_ nome: String, percentuale: Int) {
        invia(titolo: "Batteria al \(percentuale)%", testo: "Collega \(nome) al caricatore per non perdere il video.")
    }

    /// Anche con l'app in primo piano: è la conferma che il file c'è.
    func registrazioneSalvata(_ file: URL) {
        invia(titolo: "Registrazione salvata", testo: "In Filmati › WebcamLR. Clic per mostrarla nel Finder.",
              ancheInPrimoPiano: true, file: file)
    }

    /// Chiede il permesso solo se macOS non l'ha ancora chiesto; se le notifiche sono spente, non chiede.
    func chiediPermesso() {
        guard attive else { return }
        Task {
            let centro = UNUserNotificationCenter.current()
            let impostazioni = await centro.notificationSettings()
            guard impostazioni.authorizationStatus == .notDetermined else { return }
            _ = try? await centro.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// Vero se l'utente le ha negate nelle Impostazioni di Sistema.
    func negate() async -> Bool {
        let impostazioni = await UNUserNotificationCenter.current().notificationSettings()
        return impostazioni.authorizationStatus == .denied
    }

    private func invia(titolo: String, testo: String, ancheInPrimoPiano: Bool = false, file: URL? = nil) {
        guard attive, ancheInPrimoPiano || !NSApp.isActive else { return }
        let contenuto = UNMutableNotificationContent()
        contenuto.title = titolo
        contenuto.body = testo
        contenuto.sound = .default
        if let file { contenuto.userInfo = [Self.chiaveFile: file.path(percentEncoded: false)] }
        let richiesta = UNNotificationRequest(identifier: UUID().uuidString, content: contenuto, trigger: nil)
        Task {
            let centro = UNUserNotificationCenter.current()
            let stato = await centro.notificationSettings().authorizationStatus
            if stato == .notDetermined {
                // Per esempio «registrazione salvata» prima di qualsiasi telefono: si chiede qui.
                guard (try? await centro.requestAuthorization(options: [.alert, .sound])) == true else { return }
            } else if stato == .denied {
                return
            }
            try? await centro.add(richiesta)
        }
    }
}

extension Notifiche: UNUserNotificationCenterDelegate {
    /// Con l'app in primo piano macOS non mostrerebbe nulla: le poche che mandiamo così si vedono.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clic sulla notifica: il file nel Finder, se c'è, altrimenti la finestra di WebcamLR.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let percorso = response.notification.request.content.userInfo[Self.chiaveFile] as? String
        Task { @MainActor in
            if let percorso {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: percorso)])
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        completionHandler()
    }
}
