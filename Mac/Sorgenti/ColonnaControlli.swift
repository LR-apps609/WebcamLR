import Stile
import SwiftUI
import WebcamLRProtocollo

/// La colonna di destra della finestra principale. In cima la scelta principale, «Profilo»; sotto pochi comandi
/// a vista («Fotocamera»: obiettivo, zoom, esposizione, torcia, messa a fuoco) e il resto in sezioni richiudibili,
/// chiuse di serie e ricordate: «Effetti», «Regole fini» (ISO, tempo, bianco, regolazioni). In fondo, fermo,
/// «Scollega» (interfaccia finale). La qualità video è nel menu dell'etichetta sul video (SopraIlVideo.swift).
/// Il microfono del telefono sta una volta sola, in «Uscite» a sinistra; Specchia e Sfondo sotto il video.
/// Senza telefono tutto resta visibile ma grigio: un clic dice «Collega un telefono».
/// WebcamLR Pro: con un telefono gratis profili, «Regole fini», gli effetti Pro e la qualità sopra 720p a 30 fps
/// restano visibili con il segno «PRO», grigi, e dicono come sbloccarli dall'iPhone (`richiedePro`).
struct ColonnaControlli: View {
    let ricevitore: Ricevitore
    @AppStorage(Preferenze.sezioneEffetti) private var effettiAperti = false
    @AppStorage(Preferenze.sezioneRegoleFini) private var regoleAperte = false

    /// Il telefono scelto è collegato e ha detto cosa sa fare.
    private var pronto: Bool {
        ricevitore.telefonoAttivo && ricevitore.capacita != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                contenuto
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().overlay(Tema.lineaTenue)
            pulsanteScollega
                .padding(12)
        }
    }

    /// «Scollega» il telefono nella webcam: non si ricollega da solo (con due telefoni anche nelle schede a sinistra).
    /// Senza telefono resta grigio e dice a cosa servono i comandi.
    @ViewBuilder private var pulsanteScollega: some View {
        if let nome = ricevitore.telefono?.nome {
            Button {
                ricevitore.chiediEScollega()
            } label: {
                Label("Scollega «\(nome)»", systemImage: "iphone.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StilePulsanteSecondario())
            .help(ricevitore.telefoni.count > 1
                  ? "Scollega «\(nome)», quello nella webcam: non si ricollega da solo"
                  : "Scollega il telefono: non si ricollega da solo")
        } else {
            Button {} label: {
                Text("Collega un telefono per usarli")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(StilePulsanteSecondario())
            .disabled(true)
        }
    }

    private var contenuto: some View {
        VStack(alignment: .leading, spacing: 16) {
            if ricevitore.telefoni.count > 1, let nome = ricevitore.telefono?.nome {
                // P21: i comandi valgono per il telefono nella webcam.
                Label(nome, systemImage: "video")
                    .font(.corpoEvidente(12.5))
                    .foregroundStyle(Tema.cianoChiaro)
                    .lineLimit(1)
                    .help("I comandi valgono per «\(nome)», il telefono nella webcam")
            }
            ComandiProfilo(ricevitore: ricevitore)

            Divider().overlay(Tema.lineaTenue)

            VStack(alignment: .leading, spacing: 12) {
                Text("Fotocamera")
                    .font(.titolo(20))
                ComandiFotocamera(ricevitore: ricevitore)
            }

            Divider().overlay(Tema.lineaTenue)

            VStack(alignment: .leading, spacing: 4) {
                // Solo ciò che il telefono dichiara: un telefono senza effetti non mostra la sezione.
                if let capacita = ricevitore.capacitaEffetti, pronto {
                    if Effetti.disponibili(capacita) {
                        SezioneRichiudibile("Effetti", aperta: $effettiAperti) {
                            ComandiEffetti(ricevitore: ricevitore)
                        }
                    }
                    SezioneRichiudibile("Regole fini", aperta: $regoleAperte, pro: ricevitore.bloccoPro) {
                        ComandiRegoleFini(ricevitore: ricevitore)
                    }
                } else {
                    SezioneRichiudibile("Effetti", aperta: $effettiAperti) {
                        ComandiEffetti(ricevitore: ricevitore)
                    }
                    SezioneRichiudibile("Regole fini", aperta: $regoleAperte) {
                        ComandiRegoleFini(ricevitore: ricevitore)
                    }
                }
            }
        }
    }
}

// MARK: - Le sezioni, riusate dal pannello «Impostazioni» (vista Essenziale)

/// «Profilo»: i profili pronti e quelli salvati, grigi senza telefono e con «PRO» con un telefono gratis.
struct ComandiProfilo: View {
    let ricevitore: Ricevitore
    /// Il titolo «Profilo»: nella colonna sì; nella pagina «Profili» delle Impostazioni il titolo è già in alto.
    var conTitolo = true

    var body: some View {
        let pronto = ricevitore.telefonoAttivo && ricevitore.capacita != nil
        VStack(alignment: .leading, spacing: 8) {
            SezioneProfilo(ricevitore: ricevitore, attiva: pronto && ricevitore.proAttivo, conTitolo: conTitolo)
                .richiedePro(ricevitore.bloccoPro, segno: false)
            if ricevitore.bloccoPro { RigaPro() }
        }
        .richiedeTelefono(pronto)
    }
}

/// I comandi a vista della fotocamera (obiettivo, zoom, esposizione, torcia, messa a fuoco). Senza telefono gli
/// stessi comandi grigi, con il perché.
struct ComandiFotocamera: View {
    let ricevitore: Ricevitore

    var body: some View {
        if let capacita = ricevitore.capacita, ricevitore.telefonoAttivo {
            ControlliFotocamera(ricevitore: ricevitore, capacita: capacita,
                                obiettivoAttuale: ricevitore.controlli.obiettivo ?? ricevitore.statoTelefono?.obiettivo)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(testoComandiAssenti)
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                // Gli stessi comandi, grigi: si vede cosa arriva con il telefono; un clic dice «Collega un telefono».
                AnteprimaControlliFotocamera()
                    .richiedeTelefono(false)
            }
        }
    }

    /// Perché i comandi sono grigi. Durante la riconnessione il telefono c'è ancora: non si chiede di collegarne uno.
    private var testoComandiAssenti: String {
        if ricevitore.collegamento == .riconnessione && ricevitore.inSottofondo {
            return Ricevitore.testoPausa(MotiviPausa.sottofondo)
        }
        if ricevitore.collegamento == .riconnessione {
            return String(localized: "Mi ricollego al telefono: i comandi tornano appena il video riprende.")
        }
        if ricevitore.telefono != nil {
            return String(localized: "Il telefono è collegato: i comandi arrivano tra un attimo.")
        }
        return String(localized: "Si attivano quando colleghi un telefono.")
    }
}

/// Gli effetti del telefono (gratis: luce sul volto, sfondo sfocato, postura; il resto con il segno «PRO»).
/// Senza telefono gli stessi comandi grigi.
struct ComandiEffetti: View {
    let ricevitore: Ricevitore

    var body: some View {
        // Con gli effetti sul computer: quelli che sa fare il Mac (`capacitaEffetti`).
        if let capacita = ricevitore.capacitaEffetti, ricevitore.telefonoAttivo {
            VStack(alignment: .leading, spacing: 12) {
                if ricevitore.bloccoPro { RigaPro() }
                ControlliEffetti(ricevitore: ricevitore, capacita: capacita)
            }
        } else {
            AnteprimaEffetti()
                .richiedeTelefono(false)
        }
    }
}

/// «Regole fini», di WebcamLR Pro: ISO e tempo, bianco (`fotocamera`) e le quattro regolazioni (`regolazioni`).
/// La colonna di destra le mostra insieme; le Impostazioni le dividono tra «Fotocamera» ed «Effetti».
struct ComandiRegoleFini: View {
    enum Parte {
        case tutte
        case fotocamera
        case regolazioni
    }

    let ricevitore: Ricevitore
    var parte = Parte.tutte

    var body: some View {
        if let capacita = ricevitore.capacita, ricevitore.telefonoAttivo {
            VStack(alignment: .leading, spacing: 16) {
                if ricevitore.bloccoPro { RigaPro() }
                VStack(alignment: .leading, spacing: 16) {
                    if parte != .regolazioni {
                        ControlliFotocamera(ricevitore: ricevitore, capacita: capacita, obiettivoAttuale: nil, parte: .regoleFini)
                    }
                    if parte != .fotocamera, let capacitaEffetti = ricevitore.capacitaEffetti {
                        ControlliEffetti(ricevitore: ricevitore, capacita: capacitaEffetti, parte: .regolazioni)
                    }
                }
                .richiedePro(ricevitore.bloccoPro, segno: false)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if parte != .regolazioni {
                    AnteprimaControlliFotocamera(parte: .regoleFini)
                }
                if parte != .fotocamera {
                    AnteprimaEffetti(parte: .regolazioni)
                }
            }
            .richiedeTelefono(false)
        }
    }
}

/// Una sezione che si apre e si chiude con un clic sul titolo (non solo sul triangolo), come in Impostazioni.
private struct SezioneRichiudibile<Contenuto: View>: View {
    let titolo: LocalizedStringKey
    @Binding var aperta: Bool
    /// Riduci movimento (M21): niente animazione, il contenuto compare e basta.
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento
    /// Il segno «PRO» accanto al titolo: tutta la sezione è di WebcamLR Pro e il telefono non ce l'ha.
    let pro: Bool
    let contenuto: Contenuto

    init(_ titolo: LocalizedStringKey, aperta: Binding<Bool>, pro: Bool = false, @ViewBuilder contenuto: () -> Contenuto) {
        self.titolo = titolo
        _aperta = aperta
        self.pro = pro
        self.contenuto = contenuto()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(riduciMovimento ? nil : .easeOut(duration: 0.15)) { aperta.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tema.testoSecondario)
                        .rotationEffect(.degrees(aperta ? 90 : 0))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text(titolo)
                        .font(.titolo(18))
                        .foregroundStyle(Tema.testo)
                    if pro { SegnoPro() }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(aperta ? Text("aperta") : Text("chiusa"))
            if aperta {
                contenuto
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
            Divider().overlay(Tema.lineaTenue)
        }
    }
}

/// I comandi della fotocamera come appariranno con un telefono, ma fermi.
private struct AnteprimaControlliFotocamera: View {
    var parte = ControlliFotocamera.Parte.essenziali

    var body: some View {
        switch parte {
        case .essenziali:
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    EtichettaSezione(String(localized: "Obiettivo"))
                    Picker("Obiettivo", selection: .constant(1)) {
                        Text("0,5×").tag(0)
                        Text("1×").tag(1)
                        Text("Tele").tag(2)
                        Text("Frontale").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                cursore("Zoom", testo: Lingua.decimali("1.0×"))
                cursore("Esposizione", testo: Lingua.decimali("+0.0"))
                // Uno accanto all'altro se ci stanno, altrimenti uno sotto l'altro: mai oltre il bordo del pannello.
                ViewThatFits(in: .horizontal) {
                    HStack { pulsantiFinali }
                    VStack(alignment: .leading, spacing: 8) { pulsantiFinali }
                }
            }
            .tint(Tema.ciano)
        case .regoleFini:
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Esposizione manuale (ISO e tempo)", isOn: .constant(false))
                Toggle("Bilanciamento del bianco automatico", isOn: .constant(true))
            }
            .tint(Tema.ciano)
        }
    }

    @ViewBuilder private var pulsantiFinali: some View {
        Toggle("Torcia", isOn: .constant(false))
            .toggleStyle(.button)
        Button("Messa a fuoco automatica") {}
    }

    private func cursore(_ nome: LocalizedStringKey, testo: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nome)
                Spacer()
                Text(testo)
                    .font(.numeri(12.5))
                    .foregroundStyle(Tema.testoTenue)
            }
            Slider(value: .constant(0.5))
                .labelsHidden()
        }
    }
}

/// Comandi della fotocamera del telefono dal Mac: ogni modifica parte subito come `comando`.
/// `essenziali` a vista (obiettivo, zoom, esposizione, torcia, messa a fuoco); `regoleFini` nella sezione
/// richiudibile (ISO e tempo manuali, bilanciamento del bianco).
private struct ControlliFotocamera: View {
    enum Parte {
        case essenziali
        case regoleFini
    }

    @Bindable var ricevitore: Ricevitore
    let capacita: Capacita
    let obiettivoAttuale: String?
    var parte = Parte.essenziali
    /// Cresce quando «Annulla» ferma il cambio di obiettivo: il segmento si ridisegna sull'obiettivo di prima.
    @State private var sceltaAnnullata = 0

    var body: some View {
        switch parte {
        case .essenziali:
            essenziali
        case .regoleFini:
            VStack(alignment: .leading, spacing: 14) {
                esposizioneManuale
                bilanciamentoBianco
            }
            .tint(Tema.ciano)
        }
    }

    private var essenziali: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                EtichettaSezione(String(localized: "Obiettivo"))
                Picker("Obiettivo", selection: Binding(
                    get: { obiettivoAttuale ?? capacita.obiettivi.first ?? "" },
                    set: { nuovo in
                        guard nuovo != (obiettivoAttuale ?? capacita.obiettivi.first) else { return }
                        // Mentre registri chiede prima (punto 7); con «Annulla» il segmento torna sull'obiettivo di prima.
                        if ricevitore.confermaSeFerma(.obiettivo) {
                            ricevitore.scegliObiettivo(nuovo)
                        } else {
                            sceltaAnnullata += 1
                        }
                    })) {
                    ForEach(capacita.obiettivi, id: \.self) { obiettivo in
                        Text(Ricevitore.etichetta(obiettivo: obiettivo)).tag(obiettivo)
                    }
                }
                .pickerStyle(.segmented)
                .id(sceltaAnnullata)
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

            if ricevitore.controlli.esposizioneManuale {
                // ISO e tempo manuali: l'esposizione automatica non vale, si cambia nelle «Regole fini».
                Text("Esposizione manuale accesa: ISO e tempo in «Regole fini».")
                    .font(.corpo(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                cursore("Esposizione", valore: $ricevitore.controlli.esposizione, intervallo: -2...2, passo: 0.1,
                        testo: String(format: "%+.1f", ricevitore.controlli.esposizione)) { valore in
                    Comando(esposizione: valore)
                }
            }

            // Uno accanto all'altro se ci stanno, altrimenti uno sotto l'altro: mai oltre il bordo del pannello.
            ViewThatFits(in: .horizontal) {
                HStack { torciaEFuoco }
                VStack(alignment: .leading, spacing: 8) { torciaEFuoco }
            }
        }
        .tint(Tema.ciano)
    }

    @ViewBuilder private var torciaEFuoco: some View {
        if capacita.torcia {
            Toggle("Torcia", isOn: Binding(
                get: { ricevitore.controlli.torcia },
                set: { accesa in
                    ricevitore.controlli.torcia = accesa
                    ricevitore.comanda(Comando(torcia: accesa))
                }))
            .toggleStyle(.button)
        }
        Button("Messa a fuoco automatica") {
            ricevitore.fuocoAutomatico()
        }
        .help("Tasto F")
    }

    /// Bilanciamento del bianco automatico o manuale.
    private var bilanciamentoBianco: some View {
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
                        // Solo multipli di 1/100 s: con le luci a 50 Hz non fanno bande (Protocollo.md, «tempo»).
                        ForEach([25, 50, 100], id: \.self) { denominatore in
                            Text("1/\(denominatore) s").tag(denominatore)
                        }
                    }
                }
            }
        }
    }

    private func cursore(_ nome: LocalizedStringKey, valore: Binding<Double>, intervallo: ClosedRange<Double>, passo: Double,
                         testo: String, comando: @escaping (Double) -> Comando) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nome)
                Spacer()
                Text(Lingua.decimali(testo))
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
            .accessibilityLabel(nome)
            .accessibilityValue(Lingua.decimali(testo))
        }
    }
}
