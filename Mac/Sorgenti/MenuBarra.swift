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
    @AppStorage(Preferenze.wifiDiretto) private var wifiDiretto = false
    @AppStorage(Preferenze.modalitaAvanzata) private var avanzata = false
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra
    @Environment(\.openSettings) private var apriImpostazioni

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
                        if let via = ricevitore.tipoCollegamento {
                            IndicatoreCollegamento(via, qualita: ricevitore.statistiche.latenzaMs.map { QualitaCollegamento(latenzaMs: $0) })
                        }
                        if let latenza = ricevitore.statistiche.latenzaMs {
                            ChipQualita(QualitaCollegamento(latenzaMs: latenza), latenzaMs: latenza)
                        }
                    }
                    if !dettagli.isEmpty {
                        Text(dettagli)
                            .font(.numeri(11.5))
                            .foregroundStyle(Tema.testoTenue)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.pannelloChiaro, in: RoundedRectangle(cornerRadius: 8))

                comandi
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let diagnosi = Diagnosi.calcola(ricevitore, wifiDiretto: wifiDiretto) {
                        RiquadroDiagnosi(diagnosi: diagnosi, ricevitore: ricevitore)
                    }
                    Text("Apri WebcamLR sull'iPhone e scegli questo Mac. Se non compare:")
                        .font(.callout)
                        .foregroundStyle(Tema.testoTenue)
                    PannelloAssociazione(ricevitore: ricevitore, lato: 120)
                }
            }

            Text(!fotocamera.disponibile ? "Webcam virtuale: richiede l'account sviluppatore Apple a pagamento."
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
                Button {
                    apriFinestraApp(.guida, apri: apriFinestra)
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("Guida, Pro, «Segnala un bug» e informazioni")
                .accessibilityLabel("App e assistenza")
                // Non SettingsLink: dalla barra in alto WebcamLR spesso non è l'app attiva e le Impostazioni
                // si aprirebbero dietro le altre finestre. Prima si attiva l'app, poi si porta davanti la finestra.
                Button {
                    apriImpostazioniDavanti(apriImpostazioni)
                } label: {
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
                                .accessibilityHidden(true)
                            Text("Ferma")
                        }
                        .accessibilityLabel("Ferma la registrazione")
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
                .help(ricevitore.miniAperta ? "Chiudi la finestra mini (⇧⌘M)" : "Finestra mini, sempre in primo piano (⇧⌘M)")
                .accessibilityLabel(ricevitore.miniAperta ? "Chiudi la finestra mini" : "Apri la finestra mini")
            }

            Button("Scollega il telefono") { ricevitore.scollega() }
        }
    }

    private var dettagli: String {
        let statistiche = ricevitore.statistiche
        var parti: [String] = []
        // Modalità semplice (1.5): niente numeri tecnici, la qualità è già nel chip.
        if avanzata {
            if statistiche.larghezza > 0 { parti.append("\(min(statistiche.larghezza, statistiche.altezza))p\(statistiche.fps)") }
            parti.append(statistiche.latenzaMs.map { "\($0) ms" } ?? "— ms")
        }
        if let stato = ricevitore.statoTelefono, stato.batteria >= 0 { parti.append("\(stato.batteria)%") }
        return parti.joined(separator: " · ")
    }
}

/// L'icona nella barra in alto segue lo stato (funzione 34): vuota senza telefono,
/// piena con un telefono collegato, rossa solo quando un'app usa il video («in onda»).
struct IconaBarra: View {
    let ricevitore: Ricevitore
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        icona
            // L'icona nella barra c'è sempre, anche con tutte le finestre chiuse: da qui il clic
            // su una notifica può riaprire la finestra principale.
            .onAppear {
                let apri = apriFinestra
                Notifiche.condivise.apriFinestraPrincipale = { apri(id: WebcamLRMacApp.idPrincipale) }
            }
    }

    @ViewBuilder private var icona: some View {
        switch ricevitore.collegamento {
        case .inOnda:
            Image(nsImage: Self.inOnda)
                .renderingMode(.original)
                .accessibilityLabel("WebcamLR, in onda")
        case .collegato, .riconnessione:
            Image(systemName: "video.fill")
                .accessibilityLabel("WebcamLR, telefono collegato")
        case .nessunTelefono:
            Image(systemName: "video")
                .accessibilityLabel("WebcamLR, nessun telefono")
        }
    }

    /// Le icone della barra sono monocromatiche (template). Per il rosso si disegna una bitmap vera,
    /// non un simbolo con la configurazione a colori, che la barra può ridipingere in bianco e nero.
    /// Se macOS la mostrasse comunque come template resta riconoscibile: il pallino in alto a destra
    /// la distingue da «collegato».
    private static let inOnda: NSImage = {
        let configurazione = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let simbolo = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configurazione) else {
            return NSImage(systemSymbolName: "video.fill", accessibilityDescription: "WebcamLR, in onda") ?? NSImage()
        }
        let lato = simbolo.size
        let pallino: CGFloat = 5
        let dimensione = NSSize(width: ceil(lato.width + pallino + 1), height: ceil(max(lato.height, 16)))
        let rosso = NSColor(Tema.tally)
        let immagine = NSImage(size: dimensione, flipped: false) { area in
            let origine = NSPoint(x: 0, y: ((area.height - lato.height) / 2).rounded())
            simbolo.draw(at: origine, from: .zero, operation: .sourceOver, fraction: 1)
            rosso.set()
            // Solo dove c'è il simbolo: lo colora senza toccare la parte trasparente.
            NSRect(origin: origine, size: lato).fill(using: .sourceAtop)
            NSBezierPath(ovalIn: NSRect(x: area.width - pallino, y: area.height - pallino - 1,
                                        width: pallino, height: pallino)).fill()
            return true
        }
        immagine.isTemplate = false
        immagine.accessibilityDescription = "WebcamLR, in onda"
        return immagine
    }()
}

/// Apre le Impostazioni e le porta davanti, anche quando WebcamLR non era l'app attiva
/// (per esempio dalla barra in alto, mentre si usa un'altra app).
@MainActor
func apriImpostazioniDavanti(_ apri: OpenSettingsAction) {
    NSApp.activate(ignoringOtherApps: true)
    apri()
    // La finestra nasce un attimo dopo: al giro successivo la si porta in primo piano.
    DispatchQueue.main.async {
        NSApp.windows
            .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
            .makeKeyAndOrderFront(nil)
    }
}
