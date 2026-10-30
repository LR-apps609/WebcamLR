import AppKit
import Stile
import SwiftUI

/// I pannelli di Impostazioni di Sistema dove si risolvono i problemi (passo 7: ogni errore con il suo pulsante).
enum ImpostazioniDiSistema {
    enum Pannello {
        /// Rete › Firewall (da macOS 13 il firewall sta in «Rete»).
        case firewall
        /// Wi-Fi.
        case wifi
        /// Privacy e sicurezza › Fotocamera: il permesso per mettere le immagini nella webcam virtuale.
        case fotocamera
    }

    static func indirizzo(_ pannello: Pannello) -> URL? {
        switch pannello {
        case .firewall: URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")
        case .wifi: URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")
        case .fotocamera: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        }
    }

    static func apri(_ pannello: Pannello) {
        guard let url = indirizzo(pannello) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Perché nessun telefono si collega, e cosa fare (1.3). Sempre una causa e un'azione, mai solo un errore;
/// «Leggi la risposta» porta alla domanda frequente giusta (1.4).
struct Diagnosi: Equatable {
    enum Azione: Equatable {
        case riprova
        case attivaWifiDiretto
        case collegaCavo
        /// Passo 7 (mac.md 16): «Apri Impostazioni Wi-Fi».
        case apriWifi
    }

    /// La causa, in breve.
    let titolo: String
    /// Cosa fare.
    let spiegazione: String
    let azione: Azione?
    /// L'`id` in `DomandeFrequenti`.
    let domanda: String
    /// Ambra per i problemi; tenue per le informazioni (per esempio l'iPhone sul cavo che aspetta l'app).
    var avviso = true

    /// Nil se non c'è niente da dire: un telefono è collegato, o tutto è pronto e si aspetta solo il telefono.
    @MainActor
    static func calcola(_ ricevitore: Ricevitore, wifiDiretto: Bool) -> Diagnosi? {
        guard ricevitore.telefono == nil else { return nil }
        // L'ascolto è fallito (anche sulla porta di riserva): senza, nessun telefono in rete può arrivare.
        if case .errore = ricevitore.rete {
            return Diagnosi(
                titolo: String(localized: "Il Mac non riesce a farsi trovare"),
                spiegazione: String(localized: "La rete non risponde o un'altra app occupa la porta. Scegli «Riprova»; se non basta, riavvia WebcamLR."),
                azione: .riprova,
                domanda: "non-trova")
        }
        // Il cavo prima della rete: se c'è un iPhone sul cavo, è quello che l'utente sta provando a usare.
        switch ricevitore.statoCavo {
        case .inAttesaApp:
            return Diagnosi(
                titolo: String(localized: "iPhone collegato con il cavo"),
                spiegazione: String(localized: "Apri WebcamLR sull'iPhone e tienila aperta. Se l'iPhone chiede «Autorizzare questo computer?», scegli «Autorizza»."),
                azione: nil,
                domanda: "cavo",
                avviso: false)
        case .inPausa:
            return Diagnosi(
                titolo: String(localized: "Cavo USB in pausa"),
                spiegazione: String(localized: "L'iPhone sul cavo è stato scollegato o non consentito. Scegli «Collega via cavo» per riprovare."),
                azione: .collegaCavo,
                domanda: "cavo",
                avviso: false)
        case .nessunIPhone, .servizioAssente, .collegato:
            break
        }
        // Nessun indirizzo: il Mac non è su nessuna rete, e nessun telefono può trovarlo in Wi-Fi.
        if ricevitore.indirizzi.isEmpty {
            if wifiDiretto {
                return Diagnosi(
                    titolo: String(localized: "Il Mac non è collegato a una rete"),
                    spiegazione: String(localized: "Collega il Mac al Wi-Fi o usa il cavo. Il Wi-Fi diretto è acceso: l'iPhone può trovare il Mac anche così, se il Wi-Fi del Mac è acceso."),
                    azione: .apriWifi,
                    domanda: "cavo")
            }
            return Diagnosi(
                titolo: String(localized: "Il Mac non è collegato a una rete"),
                spiegazione: String(localized: "Collega il Mac al Wi-Fi o usa il cavo. Senza una rete in comune puoi accendere il Wi-Fi diretto, come con AirDrop."),
                azione: .attivaWifiDiretto,
                domanda: "cavo")
        }
        return nil
    }
}

/// Il riquadro della diagnosi: causa, cosa fare, il pulsante giusto e il collegamento alla risposta.
struct RiquadroDiagnosi: View {
    let diagnosi: Diagnosi
    let ricevitore: Ricevitore
    @AppStorage(Preferenze.wifiDiretto) private var wifiDiretto = false
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(diagnosi.titolo)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: diagnosi.avviso ? "exclamationmark.triangle" : "cable.connector")
                    .foregroundStyle(diagnosi.avviso ? Tema.ambra : Tema.testoTenue)
            }
            .foregroundStyle(diagnosi.avviso ? Tema.ambraTesto : Tema.testo)
            Text(diagnosi.spiegazione)
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
            // Nella barra laterale (250 punti) «Accendi il Wi-Fi diretto» e «Leggi la risposta» non stanno
            // sulla stessa riga: allora uno sotto l'altro, invece di tagliare i nomi o uscire dal riquadro.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { pulsanti }
                VStack(alignment: .leading, spacing: 6) { pulsanti }
            }
            .padding(.top, 2)
        }
        .font(.corpo(12.5))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(diagnosi.avviso ? Tema.ambraTenue.opacity(0.6) : Tema.pannello, in: RoundedRectangle(cornerRadius: 8))
        .tint(Tema.ciano)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var pulsanti: some View {
        if let azione = diagnosi.azione {
            Button(testo(azione)) { esegui(azione) }
        }
        Button("Leggi la risposta") {
            apriDomandaFrequente(diagnosi.domanda, apri: apriFinestra)
        }
        .buttonStyle(.link)
    }

    private func testo(_ azione: Diagnosi.Azione) -> String {
        switch azione {
        case .riprova: String(localized: "Riprova")
        case .attivaWifiDiretto: String(localized: "Accendi il Wi-Fi diretto")
        case .collegaCavo: String(localized: "Collega via cavo")
        case .apriWifi: String(localized: "Apri Impostazioni Wi-Fi")
        }
    }

    private func esegui(_ azione: Diagnosi.Azione) {
        switch azione {
        case .riprova:
            ricevitore.avvia()
        case .attivaWifiDiretto:
            wifiDiretto = true
            // Le Impostazioni lo fanno da sole solo se sono aperte: qui si riapre l'ascolto con AWDL.
            ricevitore.riavviaAscolto()
        case .collegaCavo:
            ricevitore.collegaCavo()
        case .apriWifi:
            ImpostazioniDiSistema.apri(.wifi)
        }
    }
}
