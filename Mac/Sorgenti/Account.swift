import AppKit
import Stile
import SwiftUI

// In alto a destra nella finestra principale (interfaccia finale): «Aiuto» e «WebcamLR». Non c'è un account (Glossario,
// «Modalità senza account»): il menu «WebcamLR» (prima «Account») raccoglie WebcamLR Pro, i telefoni, la lingua, gli
// aggiornamenti e le informazioni (le impostazioni stanno nel pannello «Impostazioni», passo 8). Una versione nuova sul
// sito accende un punto sul menu e una voce dentro.

extension View {
    /// I menu dell'intestazione («Aiuto», «WebcamLR»): il menu di sistema con l'aspetto del pulsante secondario di Stile,
    /// come «Impostazioni» accanto (`StileSecondario`: trasparente con il contorno a 3:1).
    func menuIntestazione() -> some View {
        menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(.stile(.corpo, .corpoForte))
            .superficieSecondaria()
    }
}

/// «Aiuto»: guida, domande frequenti, «Il telefono non trova il Mac?» e «Segnala un bug» (finestra «App e assistenza»).
struct MenuAiuto: View {
    let compatta: Bool
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Menu {
            Button {
                apriFinestraApp(.guida, apri: apriFinestra)
            } label: {
                Label("Guida", systemImage: "book")
            }
            Button {
                apriFinestraApp(.domande, apri: apriFinestra)
            } label: {
                Label("Domande frequenti", systemImage: "questionmark.bubble")
            }
            Button {
                apriDomandaFrequente("non-trova", apri: apriFinestra)
            } label: {
                Label("Il telefono non trova il Mac?", systemImage: "wifi.exclamationmark")
            }
            Divider()
            Button {
                apriFinestraApp(.segnala, apri: apriFinestra)
            } label: {
                Label("Segnala un bug", systemImage: "ladybug")
            }
        } label: {
            Label("Aiuto", systemImage: "questionmark.circle")
                .labelStyle(StileEtichettaAdattabile(compatta: compatta))
        }
        .menuIntestazione()
        .help("Guida, domande frequenti e «Segnala un bug»")
        .accessibilityLabel("Aiuto")
    }
}

/// «WebcamLR» (prima «Account»): WebcamLR Pro (con lo stato del telefono nella webcam), Telefoni, Lingua,
/// Aggiornamenti e «Informazioni e privacy». Niente login: il Pro arriva dal telefono (`capacita.pro`).
struct MenuWebcamLR: View {
    let ricevitore: Ricevitore
    let compatta: Bool
    /// Apre il foglio «Aggiornamento disponibile» (lo tiene la finestra principale).
    let mostraAggiornamento: (ControlloAggiornamenti.Versione) -> Void
    /// Apre il foglio «Telefoni».
    let mostraTelefoni: () -> Void
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        let nuova = ControlloAggiornamenti.condiviso.daMostrare
        Menu {
            Text(ricevitore.proAttivo ? String(localized: "WebcamLR Pro attivo") : String(localized: "WebcamLR gratuita"))
            Button {
                apriFinestraApp(.pro, apri: apriFinestra)
            } label: {
                Label("WebcamLR Pro", systemImage: "star")
            }
            Divider()
            Button {
                mostraTelefoni()
            } label: {
                Label("Telefoni…", systemImage: "checkmark.shield")
            }
            Button {
                apriLingua()
            } label: {
                Label("Lingua: \(nomeLingua)", systemImage: "globe")
            }
            if let nuova {
                // Una versione nuova sul sito: nell'accento (un'azione), mai in corallo.
                Button {
                    mostraAggiornamento(nuova)
                } label: {
                    Label("Aggiornamento disponibile: WebcamLR \(nuova.testo)", systemImage: "arrow.down.circle")
                }
            } else {
                Text("Aggiornamenti: \(InfoApp.versione) · aggiornata")
            }
            Divider()
            Button {
                apriFinestraApp(.informazioni, apri: apriFinestra)
            } label: {
                Label("Informazioni e privacy", systemImage: "info.circle")
            }
        } label: {
            // Il nome dell'app, non «Account»: non c'è un account. Icona generica «altro», non una persona.
            Label { Text(verbatim: "WebcamLR") } icon: { Image(systemName: "ellipsis.circle") }
                .labelStyle(StileEtichettaAdattabile(compatta: compatta))
        }
        .menuIntestazione()
        .overlay(alignment: .topTrailing) {
            if nuova != nil {
                Circle()
                    .fill(Tema.accento)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Tema.fondo, lineWidth: 2))
                    .offset(x: 3, y: -3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .help(nuova.map { String(localized: "WebcamLR \($0.testo) è disponibile sul sito") }
              ?? String(localized: "WebcamLR Pro, telefoni, lingua, aggiornamenti e informazioni"))
        .accessibilityLabel(Text(verbatim: "WebcamLR"))
        .accessibilityValue(nuova != nil ? String(localized: "Aggiornamento disponibile") : "")
    }

    /// La lingua in cui si vede WebcamLR, nel suo nome («Italiano», «English»).
    private var nomeLingua: String {
        let codice = Lingua.inglese ? "en" : "it"
        return Locale(identifier: codice).localizedString(forLanguageCode: codice)?.capitalized ?? codice
    }

    /// La lingua di WebcamLR si sceglie in macOS: Impostazioni di Sistema › Generali › Lingua e zona › Applicazioni.
    private func apriLingua() {
        if let indirizzo = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(indirizzo)
        }
    }
}

/// «Telefoni» dal menu «WebcamLR» e dalla pagina «Telefoni» delle Impostazioni: i telefoni fidati (già confermati:
/// si collegano senza domande), con «Rimuovi». Gli stessi di Impostazioni › Sicurezza.
struct FoglioTelefoni: View {
    let ricevitore: Ricevitore
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        VStack(alignment: .leading, spacing: Spazi.medio) {
            Text("Telefoni")
                .font(.stile(.titoloGrande))
            Text("I telefoni fidati si ricollegano da soli quando apri WebcamLR sul telefono. Un telefono rimosso dovrà essere confermato di nuovo.")
                .font(.stile(.nota))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
            if ricevitore.telefoniFidati.isEmpty {
                Text("Nessun telefono fidato, per ora.")
                    .foregroundStyle(Tema.testoSecondario)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spazi.stretto) {
                        ForEach(ricevitore.telefoniFidati) { telefono in
                            let collegato = ricevitore.telefoni.contains { $0.impronta == telefono.impronta }
                            HStack(spacing: Spazi.stretto) {
                                Image(systemName: "iphone")
                                    .foregroundStyle(collegato ? Tema.verde : Tema.testoSecondario)
                                    .accessibilityHidden(true)
                                Text(telefono.nome)
                                    .lineLimit(1)
                                if collegato {
                                    Text("Collegato")
                                        .font(.stile(.sezione))
                                        .foregroundStyle(Tema.verde)
                                }
                                Spacer(minLength: Spazi.stretto)
                                Button("Rimuovi") { ricevitore.chiediERimuoviFidato(telefono) }
                                    .buttonStyle(StileDistruttivo())
                                    .accessibilityLabel("Rimuovi \(telefono.nome)")
                            }
                            .padding(Spazi.stretto)
                            .background(Tema.barraLaterale, in: RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous).strokeBorder(Tema.linea))
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
            HStack {
                Spacer()
                Button("Fine") { chiudi() }
                    .buttonStyle(StilePrimario())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spazi.largo)
        .frame(width: 420)
        .font(.stile(.corpo))
        .foregroundStyle(Tema.testo)
        .tint(Tema.accento)
        .background(Tema.fondo)
    }
}
