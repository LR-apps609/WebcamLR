import AppKit
import Stile
import SwiftUI

/// Menu nella barra in alto (bozza grafica, Mac 2): stato del telefono e i comandi di tutti i giorni
/// (funzione 24): obiettivo, specchia, foto, registra, finestra mini, scollega.
struct MenuBarra: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    let riprese: Riprese
    @AppStorage(Preferenze.specchia) private var specchia = false
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MarchioWebcamLR(dimensione: 18)
                Spacer()
                PillolaStato(ricevitore.collegamento)
                    .scaleEffect(0.85, anchor: .trailing)
            }

            if let telefono = ricevitore.telefono {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(telefono.nome).fontWeight(.semibold).lineLimit(1)
                        Spacer()
                        if let latenza = ricevitore.statistiche.latenzaMs {
                            ChipQualita(QualitaCollegamento(latenzaMs: latenza), latenzaMs: latenza)
                        }
                    }
                    Text(dettagli)
                        .font(.numeri(11.5))
                        .foregroundStyle(Tema.testoTenue)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.pannelloChiaro, in: RoundedRectangle(cornerRadius: 8))

                comandi
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apri WebcamLR sull'iPhone e scegli questo Mac. Se non compare:")
                        .font(.callout)
                        .foregroundStyle(Tema.testoTenue)
                    PannelloAssociazione(porta: ricevitore.porta, lato: 120)
                }
            }

            Text(!fotocamera.disponibile ? "Webcam virtuale: dal round 2"
                 : fotocamera.stato == .attiva ? "Webcam virtuale attiva" : "Webcam virtuale spenta")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)

            Divider()
            HStack {
                Button("Apri WebcamLR") {
                    NSApp.activate(ignoringOtherApps: true)
                    apriFinestra(id: WebcamLRMacApp.idPrincipale)
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Impostazioni (⌘,)")
                .accessibilityLabel("Impostazioni")
                Button("Esci") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .foregroundStyle(Tema.testo)
        .tint(Tema.ciano)
        .onAppear { ricevitore.avvia() }
    }

    /// I comandi con un telefono collegato.
    private var comandi: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let capacita = ricevitore.capacita, ricevitore.telefonoAttivo, capacita.obiettivi.count > 1 {
                Picker("Obiettivo", selection: Binding(
                    get: { ricevitore.controlli.obiettivo ?? ricevitore.statoTelefono?.obiettivo ?? capacita.obiettivi.first ?? "" },
                    set: { nuovo in ricevitore.scegliObiettivo(nuovo) })) {
                    ForEach(capacita.obiettivi, id: \.self) { obiettivo in
                        Text(Ricevitore.etichetta(obiettivo: obiettivo)).tag(obiettivo)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Obiettivo")
            }

            HStack(spacing: 8) {
                Button {
                    riprese.scattaFoto()
                } label: {
                    Label("Foto", systemImage: "camera")
                }
                .help("Salva l'immagine attuale in Immagini › WebcamLR")

                Button {
                    riprese.alternaRegistrazione()
                } label: {
                    if riprese.registra {
                        HStack(spacing: 5) {
                            // Il rosso è permesso solo per la registrazione e «in onda».
                            Circle().fill(Tema.tally).frame(width: 8, height: 8)
                            Text("Ferma")
                        }
                    } else {
                        Label("Registra", systemImage: "record.circle")
                    }
                }
                .disabled(!riprese.registra && !ricevitore.telefonoAttivo)
                .help(riprese.registra ? "Ferma la registrazione e mostra il file" : "Registra in Filmati › WebcamLR")

                Spacer()

                Toggle(isOn: $specchia) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .toggleStyle(.button)
                .help("Specchia l'anteprima")
                .accessibilityLabel("Specchia")

                Button {
                    alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
                } label: {
                    Image(systemName: ricevitore.miniAperta ? "pip.exit" : "pip.enter")
                }
                .help(ricevitore.miniAperta ? "Chiudi la finestra mini" : "Finestra mini, sempre in primo piano")
                .accessibilityLabel(ricevitore.miniAperta ? "Chiudi la finestra mini" : "Apri la finestra mini")
            }

            Button("Scollega il telefono") { ricevitore.scollega() }
        }
    }

    private var dettagli: String {
        let statistiche = ricevitore.statistiche
        var parti: [String] = []
        if statistiche.larghezza > 0 { parti.append("\(min(statistiche.larghezza, statistiche.altezza))p\(statistiche.fps)") }
        parti.append(statistiche.latenzaMs.map { "\($0) ms" } ?? "— ms")
        if let stato = ricevitore.statoTelefono, stato.batteria >= 0 { parti.append("\(stato.batteria)%") }
        return parti.joined(separator: " · ")
    }
}

/// L'icona nella barra in alto segue lo stato (funzione 34): vuota senza telefono,
/// piena con un telefono collegato, rossa solo quando un'app usa il video («in onda»).
struct IconaBarra: View {
    let ricevitore: Ricevitore

    var body: some View {
        switch ricevitore.collegamento {
        case .inOnda:
            Image(nsImage: Self.inOnda)
                .accessibilityLabel("WebcamLR, in onda")
        case .collegato, .riconnessione:
            Image(systemName: "video.fill")
                .accessibilityLabel("WebcamLR, telefono collegato")
        case .nessunTelefono:
            Image(systemName: "video")
                .accessibilityLabel("WebcamLR, nessun telefono")
        }
    }

    /// Le icone della barra sono monocromatiche (template): per il rosso serve un'immagine non template.
    private static let inOnda: NSImage = {
        let configurazione = NSImage.SymbolConfiguration(paletteColors: [NSColor(Tema.tally)])
        guard let base = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "WebcamLR, in onda"),
              let colorata = base.withSymbolConfiguration(configurazione) else {
            return NSImage(systemSymbolName: "video.fill", accessibilityDescription: "WebcamLR, in onda") ?? NSImage()
        }
        colorata.isTemplate = false
        return colorata
    }()
}
