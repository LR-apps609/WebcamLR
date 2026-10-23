import AppKit
import AVFoundation
import Stile
import SwiftUI
import WebcamLRProtocollo

/// Finestra del ricevitore (bozza grafica, Mac 1): telefoni e uscite, anteprima, fotocamera.
struct ContenutoPrincipale: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    @AppStorage("specchia") private var specchia = false
    @State private var mostraQR = false
    @State private var avvisoFoto: String?

    var body: some View {
        VStack(spacing: 0) {
            intestazione
            Divider().overlay(Tema.lineaTenue)
            HStack(spacing: 0) {
                barraLaterale
                    .frame(width: 250)
                    .background(Tema.barraLaterale)
                Divider().overlay(Tema.lineaTenue)
                anteprima
                    .frame(maxWidth: .infinity)
                Divider().overlay(Tema.lineaTenue)
                pannelloFotocamera
                    .frame(width: 280)
                    .background(Tema.barraLaterale)
            }
        }
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Intestazione

    /// Al posto della barra del titolo: i tre pulsanti della finestra restano a sinistra.
    private var intestazione: some View {
        HStack(spacing: 12) {
            LogoWebcamLR(lato: 20)
            MarchioWebcamLR(dimensione: 18)
            Spacer()
            PillolaStato(ricevitore.collegamento, testo: testoPillola)
            Button {} label: {
                Label("Registra", systemImage: "record.circle")
            }
            .disabled(true)
            .help("Registrazione dal round 8")
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
            ZStack(alignment: .topLeading) {
                VistaSchermo(livello: ricevitore.schermo.livello)
                    .scaleEffect(x: specchia ? -1 : 1, y: 1)
                if ricevitore.telefono == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.system(size: 36))
                        Text("Apri WebcamLR sull'iPhone e scegli questo Mac")
                    }
                    .foregroundStyle(Tema.testoSecondario)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if ricevitore.collegamento == .riconnessione {
                    PillolaStato(.riconnessione)
                        .padding(12)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            BarraStatistiche(statistiche: ricevitore.statistiche, collegato: ricevitore.telefono != nil)

            HStack(spacing: 8) {
                Button {
                    scattaFoto()
                } label: {
                    Label("Foto", systemImage: "camera")
                }
                .disabled(ricevitore.telefono == nil)
                .help("Salva l'immagine attuale in Immagini › WebcamLR")
                Toggle("Specchia", isOn: $specchia)
                    .toggleStyle(.button)
                Button("Schermo intero") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                if let avvisoFoto {
                    Text(avvisoFoto)
                        .font(.callout)
                        .foregroundStyle(Tema.testoTenue)
                        .transition(.opacity)
                }
                Spacer()
                if ricevitore.telefono != nil {
                    Button("Scollega il telefono") { ricevitore.scollega() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    /// Foto dal computer (funzione 35): salva e la mostra nel Finder.
    private func scattaFoto() {
        ricevitore.schermo.fotografa { immagine in
            Task { @MainActor in
                do {
                    guard let immagine else { throw Fotografia.Errore.nessunVideo }
                    let file = try Fotografia.salva(immagine)
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    mostra("Foto salvata in Immagini › WebcamLR")
                } catch {
                    mostra(error.localizedDescription)
                }
            }
        }
    }

    private func mostra(_ testo: String) {
        withAnimation { avvisoFoto = testo }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { avvisoFoto = nil }
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

private struct BarraStatistiche: View {
    let statistiche: Statistiche
    let collegato: Bool

    var body: some View {
        HStack(spacing: 18) {
            if collegato && statistiche.larghezza > 0 {
                Text("\(statistiche.larghezza)×\(statistiche.altezza)")
                Text("\(statistiche.fps) fps")
                Text("H.264")
                Text(String(format: "%.1f Mbit/s", statistiche.megabitAlSecondo).replacingOccurrences(of: ".", with: ","))
                Text(statistiche.latenzaMs.map { "latenza \($0) ms" } ?? "latenza —")
                    .foregroundStyle(coloreLatenza)
            } else {
                Text("Nessun telefono collegato")
            }
            Spacer()
        }
        .font(.numeri(12))
        .foregroundStyle(Tema.testoTenue)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(esadecimale: 0x161D1C), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.lineaTenue))
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

/// Ospita il livello dello `Schermo` in SwiftUI.
private struct VistaSchermo: NSViewRepresentable {
    let livello: AVSampleBufferDisplayLayer

    final class Vista: NSView {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                EtichettaSezione("Obiettivo")
                Picker("Obiettivo", selection: Binding(
                    get: { obiettivoAttuale ?? capacita.obiettivi.first ?? "" },
                    set: { nuovo in
                        ricevitore.controlli.obiettivo = nuovo
                        ricevitore.controlli.zoom = 1
                        ricevitore.comanda(Comando(obiettivo: nuovo))
                    })) {
                    ForEach(capacita.obiettivi, id: \.self) { obiettivo in
                        Text(Self.etichetta(obiettivo)).tag(obiettivo)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if capacita.zoomMassimo > 1 {
                cursore("Zoom", valore: $ricevitore.controlli.zoom, intervallo: 1...capacita.zoomMassimo, passo: 0.1,
                        testo: String(format: "%.1f×", ricevitore.controlli.zoom)) { valore in
                    Comando(zoom: valore)
                }
            }

            cursore("Esposizione", valore: $ricevitore.controlli.esposizione, intervallo: -2...2, passo: 0.1,
                    testo: String(format: "%+.1f", ricevitore.controlli.esposizione)) { valore in
                Comando(esposizione: valore)
            }

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
                    ricevitore.comanda(Comando(fuoco: "continuo"))
                }
            }
        }
        .tint(Tema.ciano)
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

    private static func etichetta(_ obiettivo: String) -> String {
        switch obiettivo {
        case "grandangolo": "0,5"
        case "principale": "1×"
        case "tele": "Tele"
        case "frontale": "Front."
        default: obiettivo.capitalized
        }
    }
}
