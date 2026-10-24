import AppKit
import AVFoundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Finestra del ricevitore (bozza grafica, Mac 1): telefoni e uscite, anteprima, fotocamera.
struct ContenutoPrincipale: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    let riprese: Riprese
    @AppStorage(Preferenze.specchia) private var specchia = false
    @AppStorage(Preferenze.vistaPulita) private var vistaPulita = false
    @AppStorage(Preferenze.riempi) private var riempi = false
    @State private var mostraQR = false
    /// Il puntatore è sopra il video: in vista pulita compare il pulsante per uscire.
    @State private var sopraVideo = false
    /// Il lampo bianco dopo uno scatto (funzione 27).
    @State private var opacitaLampo = 0.0
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        VStack(spacing: 0) {
            if !vistaPulita {
                intestazione
                Divider().overlay(Tema.lineaTenue)
            }
            HStack(spacing: 0) {
                if !vistaPulita {
                    barraLaterale
                        .frame(width: 250)
                        .background(Tema.barraLaterale)
                    Divider().overlay(Tema.lineaTenue)
                }
                anteprima
                    .frame(maxWidth: .infinity)
                if !vistaPulita {
                    Divider().overlay(Tema.lineaTenue)
                    pannelloFotocamera
                        .frame(width: 280)
                        .background(Tema.barraLaterale)
                }
            }
        }
        .background(vistaPulita ? Color.black : Tema.fondo)
        .background(MonitorTastiera(gestisci: tasto))
        .foregroundStyle(Tema.testo)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { ricevitore.schermo.imposta(riempi: riempi) }
        .onChange(of: riempi) { ricevitore.schermo.imposta(riempi: riempi) }
    }

    // MARK: - Tasti (funzione 25)

    /// 1–4 obiettivi nell'ordine del telefono, + e − zoom, F fuoco automatico. Vero se il tasto è stato usato.
    private func tasto(_ evento: NSEvent) -> Bool {
        let modificatori = evento.modifierFlags.intersection([.command, .control, .option])
        // ⌘C copia il fotogramma (funzione 26); in un campo di testo non si arriva qui e ⌘C copia il testo.
        if modificatori == .command, evento.charactersIgnoringModifiers?.lowercased() == "c" {
            guard ricevitore.telefono != nil else { return false }
            riprese.copiaFotogramma()
            return true
        }
        // Esc esce dalla vista pulita (funzione 29).
        if evento.keyCode == 53, modificatori.isEmpty, vistaPulita {
            vistaPulita = false
            return true
        }
        guard modificatori.isEmpty, ricevitore.telefonoAttivo, let carattere = evento.characters else { return false }
        switch carattere {
        case "1", "2", "3", "4":
            guard let numero = Int(carattere) else { return false }
            ricevitore.scegliObiettivo(numero: numero - 1)
        case "+", "=":
            // «=» è il tasto del + senza Maiusc sulle tastiere americane.
            ricevitore.cambiaZoom(di: Ricevitore.passoZoom)
        case "-":
            ricevitore.cambiaZoom(di: -Ricevitore.passoZoom)
        case "f", "F":
            ricevitore.fuocoAutomatico()
        default:
            return false
        }
        return true
    }

    // MARK: - Intestazione

    /// Al posto della barra del titolo: i tre pulsanti della finestra restano a sinistra.
    private var intestazione: some View {
        HStack(spacing: 12) {
            LogoWebcamLR(lato: 20)
            MarchioWebcamLR(dimensione: 18)
            Spacer()
            PillolaStato(ricevitore.collegamento, testo: testoPillola)
            if let liberi = riprese.spazioScarso {
                // Spazio quasi finito durante la registrazione (funzione 37): avviso in ambra.
                Label("Solo \(Riprese.testoByte(liberi)) liberi", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(Tema.ambra)
                    .help("Lo spazio sul disco sta finendo: ferma la registrazione o libera spazio.")
            }
            pulsanteRegistra
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Color(esadecimale: 0x161D1C))
    }

    private var testoPillola: String? {
        switch ricevitore.collegamento {
        case .collegato: "Collegato · pronta"
        case .riconnessione: "Riconnessione"
        case .nessunTelefono: "Nessun telefono"
        case .inOnda: nil
        }
    }

    // MARK: - Barra laterale

    private var barraLaterale: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                EtichettaSezione("Telefoni").padding(.horizontal, 8)
                if let telefono = ricevitore.telefono {
                    SchedaTelefono(telefono: telefono, stato: ricevitore.statoTelefono,
                                   latenza: ricevitore.statistiche.latenzaMs,
                                   collegato: ricevitore.telefonoAttivo)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("In attesa di un telefono")
                        Text(testoRete)
                            .font(.numeri(11.5))
                            .foregroundStyle(Tema.testoSecondario)
                        Button {
                            mostraQR.toggle()
                        } label: {
                            Label("Collega con QR code", systemImage: "qrcode")
                        }
                        .padding(.top, 6)
                        .popover(isPresented: $mostraQR, arrowEdge: .trailing) {
                            PannelloAssociazione(porta: ricevitore.porta)
                                .padding(16)
                                .frame(width: 240)
                        }
                    }
                    .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                EtichettaSezione("Uscite").padding(.horizontal, 8)
                RigaUscita(nome: "Webcam virtuale", stato: testoFotocamera, attiva: fotocamera.stato == .attiva)
                if !fotocamera.disponibile {
                    Text("Serve l'account sviluppatore Apple: arriverà con il round 2.")
                        .font(.callout)
                        .foregroundStyle(Tema.testoSecondario)
                        .padding(.horizontal, 8)
                } else if fotocamera.stato != .attiva {
                    Button("Attiva la webcam virtuale") { fotocamera.attiva() }
                        .disabled(fotocamera.stato == .inCorso)
                        .padding(.horizontal, 8)
                }
                if case .errore(let spiegazione) = fotocamera.stato {
                    Text(spiegazione)
                        .font(.callout)
                        .foregroundStyle(Tema.ambra)
                        .padding(.horizontal, 8)
                }
                RigaUscita(nome: "Microfono", stato: "dal round 5", attiva: false)
                RigaUscita(nome: "Uscita NDI", stato: "dal round 7", attiva: false)
            }

            Spacer()

            Text(fotocamera.stato == .attiva
                 ? LocalizedStringKey("Nelle app scegli **WebcamLR** come videocamera.")
                 : LocalizedStringKey("Per ora il video si vede qui. Con la webcam virtuale lo vedranno anche Zoom, Teams e le altre app."))
                .font(.callout)
                .foregroundStyle(Tema.testoTenue)
                .padding(10)
                .background(Tema.pannello, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var testoRete: String {
        switch ricevitore.rete {
        case .fermo: "Non visibile in rete"
        case .visibile(let porta): "Visibile in rete · porta \(porta)"
        case .errore(let descrizione): "Errore di rete: \(descrizione)"
        }
    }

    private var testoFotocamera: String {
        guard fotocamera.disponibile else { return "non inclusa" }
        return switch fotocamera.stato {
        case .nonAttiva: "spenta"
        case .inCorso: "attivazione…"
        case .daApprovare: "da approvare"
        case .riavvioNecessario: "riavvia il Mac"
        case .attiva: "attiva"
        case .errore: "non attivata"
        }
    }

    // MARK: - Anteprima

    private var anteprima: some View {
        VStack(spacing: 12) {
            riquadroVideo
            if !vistaPulita {
                BarraStatistiche(statistiche: ricevitore.statistiche, storico: ricevitore.storicoLatenza,
                                 collegato: ricevitore.telefono != nil)
                pulsantiAnteprima
                Spacer(minLength: 0)
            }
        }
        .padding(vistaPulita ? 0 : 16)
    }

    /// Il video con ciò che gli sta sopra. In vista pulita (funzione 29) occupa tutta la finestra.
    @ViewBuilder private var riquadroVideo: some View {
        if vistaPulita {
            videoConSovrapposizioni
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        } else {
            videoConSovrapposizioni
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var videoConSovrapposizioni: some View {
        ZStack(alignment: .topLeading) {
            VistaSchermo(livello: ricevitore.schermo.livello)
                .scaleEffect(x: specchia ? -1 : 1, y: 1)
            if ricevitore.telefono == nil {
                PrimoCollegamento(porta: ricevitore.porta)
            }
            VStack(alignment: .leading, spacing: 8) {
                if ricevitore.collegamento == .riconnessione {
                    PillolaStato(.riconnessione)
                }
                avvisiTelefono
            }
            .padding(12)
            Color.white
                .opacity(opacitaLampo)
                .allowsHitTesting(false)
            if let secondi = riprese.contoAllaRovescia {
                // Conto alla rovescia della foto con il timer (funzione 36).
                Text("\(secondi)")
                    .font(.titolo(120))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Foto tra \(secondi) secondi")
            }
            if let avviso = riprese.avviso {
                Text(avviso)
                    .font(.callout)
                    .foregroundStyle(Tema.testo)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Tema.pannelloChiaro.opacity(0.92), in: Capsule())
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }
            pulsanteEsciVistaPulita
        }
        .animation(.default, value: riprese.avviso)
        .animation(.easeOut(duration: 0.15), value: sopraVideo)
        .animation(.default, value: riprese.contoAllaRovescia)
        .onChange(of: riprese.lampo) {
            opacitaLampo = 0.85
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(40))
                withAnimation(.easeOut(duration: 0.35)) { opacitaLampo = 0 }
            }
        }
        .onHover { sopraVideo = $0 }
    }

    /// Avvisi dal telefono sopra il video (funzione 33): caldo e batteria, in ambra.
    @ViewBuilder private var avvisiTelefono: some View {
        if let stato = ricevitore.statoTelefono, ricevitore.telefono != nil {
            if stato.temperatura == .moltoCalda || stato.temperatura == .critica {
                BannerAvviso(icona: "thermometer",
                             testo: stato.temperatura == .critica
                                ? "Il telefono è troppo caldo: il video può fermarsi. Toglilo dal sole o dalla custodia."
                                : "Il telefono è molto caldo: la qualità può calare. Toglilo dal sole o dalla custodia.")
            }
            if stato.batteria >= 0, stato.batteria <= 20, !stato.inCarica {
                BannerAvviso(icona: "battery.25",
                             testo: "Batteria del telefono al \(stato.batteria)%: collega il caricatore.")
            }
        }
    }

    /// Esce dalla vista pulita: compare solo con il puntatore sopra il video.
    @ViewBuilder private var pulsanteEsciVistaPulita: some View {
        if vistaPulita && sopraVideo {
            Button {
                vistaPulita = false
            } label: {
                Label("Esci dalla vista pulita", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Tema.pannelloChiaro.opacity(0.92), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tema.testo)
            .help("Esci dalla vista pulita (Esc)")
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(.opacity)
        }
    }

    private var pulsantiAnteprima: some View {
        HStack(spacing: 8) {
            Button {
                riprese.scattaFoto()
            } label: {
                Label("Foto", systemImage: "camera")
            }
            .disabled(ricevitore.telefono == nil)
            .help("Salva l'immagine attuale in Immagini › WebcamLR (⌘T)")
            Button {
                riprese.scattaConTimer()
            } label: {
                Image(systemName: riprese.contoAllaRovescia == nil ? "timer" : "xmark")
            }
            .disabled(ricevitore.telefono == nil)
            .help(riprese.contoAllaRovescia == nil ? "Foto tra 3 secondi (⇧⌘T)" : "Annulla il timer")
            .accessibilityLabel(riprese.contoAllaRovescia == nil ? "Foto tra 3 secondi" : "Annulla il timer")
            Button {
                riprese.copiaFotogramma()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(ricevitore.telefono == nil)
            .help("Copia l'immagine attuale, da incollare ovunque (⌘C)")
            .accessibilityLabel("Copia il fotogramma")
            Toggle("Specchia", isOn: $specchia)
                .toggleStyle(.button)
            Toggle(isOn: $riempi) {
                Image(systemName: "aspectratio")
            }
            .toggleStyle(.button)
            .help(riempi ? "Il video riempie il riquadro; spegni per vederlo intero (⌥⌘F)"
                  : "Riempi il riquadro, tagliando i bordi del video (⌥⌘F)")
            .accessibilityLabel("Riempi il riquadro")
            Button {
                vistaPulita = true
            } label: {
                Image(systemName: "rectangle.inset.filled")
            }
            .help("Vista pulita: solo il video (⇧⌘P, Esc per uscire)")
            .accessibilityLabel("Vista pulita")
            Button("Schermo intero") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            // ⌃⌘F c'è già nel menu Vista di sistema: qui solo il suggerimento.
            .help("Schermo intero (⌃⌘F)")
            Button {
                alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
            } label: {
                Image(systemName: ricevitore.miniAperta ? "pip.exit" : "pip.enter")
            }
            .help(ricevitore.miniAperta ? "Chiudi la finestra mini (⌥⌘M)" : "Finestra mini, sempre in primo piano (⌥⌘M)")
            .accessibilityLabel(ricevitore.miniAperta ? "Chiudi la finestra mini" : "Apri la finestra mini")
            Spacer()
            if ricevitore.telefono != nil {
                Button("Scollega il telefono") { ricevitore.scollega() }
            }
        }
    }

    /// Registra (funzione 35): il rosso è permesso, come per «in onda».
    /// Mentre registra mostra durata e dimensione del file (funzione 37).
    @ViewBuilder private var pulsanteRegistra: some View {
        if let inizio = riprese.inizioRegistrazione {
            Button {
                riprese.fermaRegistrazione()
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Tema.tally).frame(width: 10, height: 10)
                    TimelineView(.periodic(from: inizio, by: 1)) { contesto in
                        let secondi = max(0, Int(contesto.date.timeIntervalSince(inizio)))
                        Text(String(format: "Ferma · %02d:%02d", secondi / 60, secondi % 60)
                             + " · " + Riprese.testoByte(riprese.dimensioneRegistrazione))
                            .font(.numeri(12.5))
                            .monospacedDigit()
                    }
                }
            }
            .help("Ferma la registrazione e mostra il file (⌘R)")
        } else {
            Button {
                riprese.avviaRegistrazione()
            } label: {
                Label("Registra", systemImage: "record.circle")
            }
            .disabled(!ricevitore.telefonoAttivo)
            .help("Registra il video dell'iPhone in Filmati › WebcamLR (⌘R)")
        }
    }

    // MARK: - Fotocamera

    private var pannelloFotocamera: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Fotocamera")
                .font(.titolo(22))
            if let stato = ricevitore.statoTelefono {
                VStack(alignment: .leading, spacing: 10) {
                    RigaDato(nome: "Obiettivo", valore: stato.obiettivo.capitalized)
                    RigaDato(nome: "Batteria", valore: stato.batteria >= 0 ? "\(stato.batteria)%\(stato.inCarica ? " · in carica" : "")" : "—")
                    RigaDato(nome: "Temperatura", valore: descrizione(stato.temperatura),
                             avviso: stato.temperatura == .moltoCalda || stato.temperatura == .critica)
                }
            }
            if let capacita = ricevitore.capacita, ricevitore.telefonoAttivo {
                ControlliFotocamera(ricevitore: ricevitore, capacita: capacita,
                                    obiettivoAttuale: ricevitore.controlli.obiettivo ?? ricevitore.statoTelefono?.obiettivo)
            } else {
                Text("I comandi della fotocamera compaiono qui quando un iPhone è collegato.")
                    .font(.callout)
                    .foregroundStyle(Tema.testoSecondario)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func descrizione(_ temperatura: Temperatura) -> String {
        switch temperatura {
        case .normale: "normale"
        case .calda: "calda"
        case .moltoCalda: "molto calda"
        case .critica: "critica"
        }
    }
}

// MARK: - Componenti

/// Un avviso in ambra sopra il video, come i banner del telefono.
private struct BannerAvviso: View {
    let icona: String
    let testo: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icona)
                .foregroundStyle(Tema.ambra)
                .accessibilityHidden(true)
            Text(testo)
                .foregroundStyle(Tema.ambraTesto)
                .lineLimit(2)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Tema.ambraTenue.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.ambra.opacity(0.35)))
        .accessibilityElement(children: .combine)
    }
}

/// Al posto del video finché non c'è un telefono (funzione 32): QR code grande e i tre passi.
/// Se il riquadro è piccolo il QR si rimpicciolisce, e al limite restano solo i passi.
private struct PrimoCollegamento: View {
    let porta: UInt16?

    private static let nomeMac = Host.current().localizedName ?? "questo Mac"

    var body: some View {
        ViewThatFits(in: .vertical) {
            disposizione(lato: 170)
            disposizione(lato: 110)
            passi
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.pannelloScuro)
    }

    private func disposizione(lato: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 28) {
            PannelloAssociazione(porta: porta, lato: lato)
                .frame(width: lato + 40)
            passi
        }
    }

    private var passi: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collega l'iPhone")
                .font(.titolo(28))
            passo(1, "Apri WebcamLR sull'iPhone.")
            passo(2, "Tieni iPhone e Mac sulla stessa rete Wi-Fi.")
            passo(3, "Scegli «\(Self.nomeMac)» nell'elenco, oppure inquadra il QR code.")
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    private func passo(_ numero: Int, _ testo: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(numero)")
                .font(.numeriEvidenti(13))
                .foregroundStyle(Tema.testo)
                .frame(width: 24, height: 24)
                .background(Tema.pannelloChiaro, in: Circle())
            Text(testo)
                .foregroundStyle(Tema.testoTenue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SchedaTelefono: View {
    let telefono: Ciao
    let stato: StatoTelefono?
    let latenza: Int?
    let collegato: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(collegato ? Tema.verde : Tema.ambra)
                    .frame(width: 8, height: 8)
                Text(telefono.nome)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Text(dettagli)
                .font(.numeri(11.5))
                .foregroundStyle(Tema.testoTenue)
                .padding(.leading, 16)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.cianoTenue, in: RoundedRectangle(cornerRadius: 8))
    }

    private var dettagli: String {
        var parti = ["Wi-Fi"]
        parti.append(latenza.map { "\($0) ms" } ?? "— ms")
        if let stato, stato.batteria >= 0 { parti.append("\(stato.batteria)%") }
        return parti.joined(separator: " · ")
    }
}

/// Sotto l'anteprima: la qualità in parole e il grafico della latenza; i numeri si aprono con un clic (funzioni 28 e 31).
private struct BarraStatistiche: View {
    let statistiche: Statistiche
    let storico: [Int?]
    let collegato: Bool
    @State private var mostraNumeri = false

    var body: some View {
        HStack(spacing: 14) {
            if collegato && statistiche.larghezza > 0 {
                Button {
                    mostraNumeri.toggle()
                } label: {
                    HStack(spacing: 6) {
                        if let latenza = statistiche.latenzaMs {
                            ChipQualita(QualitaCollegamento(latenzaMs: latenza), latenzaMs: latenza)
                        } else {
                            Text("Misuro il collegamento…")
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Tema.testoSecondario)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Mostra i numeri del collegamento")
                .accessibilityHint("Mostra i numeri del collegamento")
                .popover(isPresented: $mostraNumeri, arrowEdge: .top) {
                    numeri
                }

                GraficoLatenza(valori: storico)
                    .frame(width: 150, height: 20)
                    .help("Latenza dell'ultimo minuto; la riga tratteggiata è a 100 ms")

                Spacer()
                Text("\(min(statistiche.larghezza, statistiche.altezza))p\(statistiche.fps) · \(nomeCodec)")
            } else {
                Text("Nessun telefono collegato")
                Spacer()
            }
        }
        .font(.numeri(12))
        .foregroundStyle(Tema.testoTenue)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(Color(esadecimale: 0x161D1C), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.lineaTenue))
    }

    /// I numeri di sempre, a portata di clic.
    private var numeri: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            riga("Risoluzione", "\(statistiche.larghezza)×\(statistiche.altezza)")
            riga("Fotogrammi", "\(statistiche.fps) al secondo")
            riga("Codec", nomeCodec)
            riga("Velocità", String(format: "%.1f Mbit/s", statistiche.megabitAlSecondo).replacingOccurrences(of: ".", with: ","))
            GridRow {
                Text("Latenza").foregroundStyle(Tema.testoSecondario)
                Text(statistiche.latenzaMs.map { "\($0) ms" } ?? "—")
                    .font(.numeri(12.5))
                    .foregroundStyle(coloreLatenza)
            }
            if let media {
                riga("Media dell'ultimo minuto", "\(media) ms")
            }
            Divider().gridCellColumns(2)
            Text("Ottimo sotto gli 80 ms, buono sotto i 150.")
                .font(.callout)
                .foregroundStyle(Tema.testoSecondario)
                .gridCellColumns(2)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func riga(_ nome: String, _ valore: String) -> some View {
        GridRow {
            Text(nome).foregroundStyle(Tema.testoSecondario)
            Text(valore).font(.numeri(12.5))
        }
    }

    private var nomeCodec: String {
        statistiche.codec == .hevc ? "HEVC" : "H.264"
    }

    private var media: Int? {
        let noti = storico.compactMap { $0 }
        return noti.isEmpty ? nil : noti.reduce(0, +) / noti.count
    }

    /// Ciano sotto i 100 ms (l'obiettivo del round 1), ambra sopra.
    private var coloreLatenza: Color {
        guard let latenza = statistiche.latenzaMs else { return Tema.testoTenue }
        return latenza < 100 ? Tema.cianoChiaro : Tema.ambra
    }
}

private struct RigaUscita: View {
    let nome: String
    let stato: String
    let attiva: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: attiva ? "checkmark" : "minus")
                .foregroundStyle(attiva ? Tema.verde : Tema.testoSecondario)
                .frame(width: 16)
            Text(nome)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(stato)
                .font(.caption)
                .foregroundStyle(Tema.testoSecondario)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
    }
}

private struct RigaDato: View {
    let nome: String
    let valore: String
    var avviso = false

    var body: some View {
        HStack {
            Text(nome).foregroundStyle(Tema.testoSecondario)
            Spacer()
            Text(valore)
                .font(.numeri(12.5))
                .foregroundStyle(avviso ? Tema.ambra : Tema.testo)
        }
    }
}

/// Ospita un livello dello `Schermo` in SwiftUI (finestra principale e finestra mini).
struct VistaSchermo: NSViewRepresentable {
    let livello: AVSampleBufferDisplayLayer

    final class Vista: NSView {
        /// Nella finestra mini si trascina il video per spostare la finestra.
        override var mouseDownCanMoveWindow: Bool { true }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.sublayers?.forEach { $0.frame = bounds }
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> Vista {
        let vista = Vista()
        vista.wantsLayer = true
        vista.layer?.backgroundColor = .black
        vista.layer?.addSublayer(livello)
        return vista
    }

    func updateNSView(_ vista: Vista, context: Context) {}
}

/// Comandi della fotocamera dell'iPhone dal Mac (round 4): ogni modifica parte subito come `comando`.
private struct ControlliFotocamera: View {
    @Bindable var ricevitore: Ricevitore
    let capacita: Capacita
    let obiettivoAttuale: String?
    @State private var chiediNome = false
    @State private var nomeProfilo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            profili
            VStack(alignment: .leading, spacing: 6) {
                EtichettaSezione("Obiettivo")
                Picker("Obiettivo", selection: Binding(
                    get: { obiettivoAttuale ?? capacita.obiettivi.first ?? "" },
                    set: { nuovo in ricevitore.scegliObiettivo(nuovo) })) {
                    ForEach(capacita.obiettivi, id: \.self) { obiettivo in
                        Text(Ricevitore.etichetta(obiettivo: obiettivo)).tag(obiettivo)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Tasti da 1 a \(min(capacita.obiettivi.count, 4))")
            }

            if capacita.zoomMassimo > 1 {
                cursore("Zoom", valore: $ricevitore.controlli.zoom, intervallo: 1...capacita.zoomMassimo, passo: 0.1,
                        testo: String(format: "%.1f×", ricevitore.controlli.zoom)) { valore in
                    Comando(zoom: valore)
                }
                .help("Tasti + e −")
            }

            if !ricevitore.controlli.esposizioneManuale {
                cursore("Esposizione", valore: $ricevitore.controlli.esposizione, intervallo: -2...2, passo: 0.1,
                        testo: String(format: "%+.1f", ricevitore.controlli.esposizione)) { valore in
                    Comando(esposizione: valore)
                }
            }

            esposizioneManuale

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Bilanciamento del bianco automatico", isOn: Binding(
                    get: { ricevitore.controlli.biancoAutomatico },
                    set: { automatico in
                        ricevitore.controlli.biancoAutomatico = automatico
                        ricevitore.comanda(Comando(bianco: automatico ? 0 : Int(ricevitore.controlli.bianco)))
                    }))
                if !ricevitore.controlli.biancoAutomatico {
                    cursore("Bianco", valore: $ricevitore.controlli.bianco, intervallo: 2500...7500, passo: 100,
                            testo: "\(Int(ricevitore.controlli.bianco)) K") { valore in
                        Comando(bianco: Int(valore))
                    }
                }
            }

            HStack {
                if capacita.torcia {
                    Toggle("Torcia", isOn: Binding(
                        get: { ricevitore.controlli.torcia },
                        set: { accesa in
                            ricevitore.controlli.torcia = accesa
                            ricevitore.comanda(Comando(torcia: accesa))
                        }))
                    .toggleStyle(.button)
                }
                Button("Fuoco automatico") {
                    ricevitore.fuocoAutomatico()
                }
                .help("Tasto F")
            }
        }
        .tint(Tema.ciano)
    }

    /// Profili (funzione 23): tutti i comandi qui sotto, salvati per nome e riapplicati con un clic.
    private var profili: some View {
        Menu {
            let nomi = ricevitore.profili.keys.sorted()
            ForEach(nomi, id: \.self) { nome in
                Button(nome) { ricevitore.applicaProfilo(nome) }
            }
            if !nomi.isEmpty { Divider() }
            Button("Salva i comandi attuali…") {
                nomeProfilo = ""
                chiediNome = true
            }
            if !nomi.isEmpty {
                Menu("Elimina") {
                    ForEach(nomi, id: \.self) { nome in
                        Button(nome, role: .destructive) { ricevitore.eliminaProfilo(nome) }
                    }
                }
            }
        } label: {
            Label("Profili", systemImage: "slider.horizontal.3")
        }
        .alert("Nuovo profilo", isPresented: $chiediNome) {
            TextField("Nome, per esempio «Riunione»", text: $nomeProfilo)
            Button("Salva") {
                let nome = nomeProfilo.trimmingCharacters(in: .whitespaces)
                if !nome.isEmpty { ricevitore.salvaProfilo(nome) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Obiettivo, zoom, esposizione, bianco e torcia di adesso. Con lo stesso nome il profilo si sovrascrive.")
        }
    }

    /// ISO e tempo di posa manuali (funzione 19), solo se il telefono dice i limiti ISO.
    @ViewBuilder private var esposizioneManuale: some View {
        if let minimo = capacita.isoMinimo, let massimo = capacita.isoMassimo, massimo > minimo {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Esposizione manuale (ISO e tempo)", isOn: Binding(
                    get: { ricevitore.controlli.esposizioneManuale },
                    set: { manuale in
                        ricevitore.controlli.esposizioneManuale = manuale
                        let controlli = ricevitore.controlli
                        ricevitore.comanda(manuale
                            ? Comando(iso: min(max(controlli.iso, minimo), massimo), tempo: controlli.tempo)
                            : Comando(iso: 0, tempo: 0))
                    }))
                if ricevitore.controlli.esposizioneManuale {
                    cursore("ISO", valore: $ricevitore.controlli.iso, intervallo: minimo...massimo, passo: 1,
                            testo: "\(Int(ricevitore.controlli.iso))") { valore in
                        Comando(iso: valore.rounded())
                    }
                    Picker("Tempo", selection: Binding(
                        get: { ricevitore.controlli.tempo },
                        set: { nuovo in
                            ricevitore.controlli.tempo = nuovo
                            ricevitore.comanda(Comando(tempo: nuovo))
                        })) {
                        ForEach([25, 30, 50, 60, 100, 120, 250, 500], id: \.self) { denominatore in
                            Text("1/\(denominatore) s").tag(denominatore)
                        }
                    }
                }
            }
        }
    }

    private func cursore(_ nome: String, valore: Binding<Double>, intervallo: ClosedRange<Double>, passo: Double,
                         testo: String, comando: @escaping (Double) -> Comando) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nome)
                Spacer()
                Text(testo.replacingOccurrences(of: ".", with: ","))
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoTenue)
            }
            Slider(value: Binding(
                get: { valore.wrappedValue },
                set: { nuovo in
                    valore.wrappedValue = nuovo
                    ricevitore.comanda(comando(nuovo))
                }), in: intervallo, step: passo)
            .labelsHidden()
        }
    }
}
