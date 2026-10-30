import Stile
import SwiftUI
import WebcamLRProtocollo

/// La colonna di destra della finestra principale. In cima la scelta principale, «Profilo»; sotto pochi comandi
/// a vista («Fotocamera»: obiettivo, zoom, esposizione, torcia, messa a fuoco) e il resto in sezioni richiudibili,
/// chiuse di serie e ricordate: «Effetti», «Regole fini» (ISO, tempo, bianco, regolazioni). «Scollega» non sta più
/// qui in fondo a tutta larghezza (beta 4): è un comando testuale nella scheda del telefono, nella colonna di sinistra.
/// La qualità video è nel menu dell'etichetta sul video (SopraIlVideo.swift).
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
        ScrollView(.vertical) {
            contenuto
                .padding(Spazi.medio)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contenuto: some View {
        VStack(alignment: .leading, spacing: Spazi.medio) {
            if ricevitore.telefono == nil {
                // Senza telefono i comandi restano a vista ma grigi: qui in cima il perché, una volta sola.
                Nota(testo: String(localized: "Collega un telefono per usarli"))
            }
            if ricevitore.telefoni.count > 1, let nome = ricevitore.telefono?.nome {
                // P21: i comandi valgono per il telefono nella webcam.
                Label(nome, systemImage: "iphone")
                    .font(.stile(.corpo, .corpoEvidente))
                    .foregroundStyle(Tema.accentoChiaro)
                    .lineLimit(1)
                    .help("I comandi valgono per «\(nome)», il telefono nella webcam")
            }
            ComandiProfilo(ricevitore: ricevitore)

            Divider().overlay(Tema.lineaTenue)

            VStack(alignment: .leading, spacing: Spazi.piccolo) {
                Text("Fotocamera")
                    .font(.stile(.titolo))
                ComandiFotocamera(ricevitore: ricevitore)
            }

            Divider().overlay(Tema.lineaTenue)

            VStack(alignment: .leading, spacing: Spazi.minimo) {
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
        VStack(alignment: .leading, spacing: Spazi.stretto) {
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
            VStack(alignment: .leading, spacing: Spazi.piccolo) {
                Text(testoComandiAssenti)
                    .font(.stile(.nota))
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
            VStack(alignment: .leading, spacing: Spazi.piccolo) {
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
            VStack(alignment: .leading, spacing: Spazi.medio) {
                if ricevitore.bloccoPro { RigaPro() }
                VStack(alignment: .leading, spacing: Spazi.medio) {
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
            VStack(alignment: .leading, spacing: Spazi.medio) {
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
                HStack(spacing: Spazi.stretto) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tema.testoSecondario)
                        .rotationEffect(.degrees(aperta ? 90 : 0))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    Text(titolo)
                        .font(.stile(.titolo))
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
                    .padding(.top, Spazi.stretto)
                    .padding(.bottom, Spazi.medio)
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
            VStack(alignment: .leading, spacing: Spazi.medio) {
                VStack(alignment: .leading, spacing: Spazi.stretto) {
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
                    VStack(alignment: .leading, spacing: Spazi.stretto) { pulsantiFinali }
                }
            }
            .tint(Tema.accento)
        case .regoleFini:
            VStack(alignment: .leading, spacing: Spazi.stretto) {
                Toggle("Esposizione manuale (ISO e tempo)", isOn: .constant(false))
                Toggle("Bilanciamento del bianco automatico", isOn: .constant(true))
            }
            .tint(Tema.accento)
        }
    }

    @ViewBuilder private var pulsantiFinali: some View {
        Button("Torcia") {}
            .buttonStyle(StileSecondario())
        Button("Messa a fuoco automatica") {}
            .buttonStyle(StileSecondario())
    }

    private func cursore(_ nome: LocalizedStringKey, testo: String) -> some View {
        VStack(alignment: .leading, spacing: Spazi.minimo) {
            HStack {
                Text(nome)
                Spacer()
                Text(testo)
                    .font(.stile(.numeri))
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
            VStack(alignment: .leading, spacing: Spazi.medio) {
                esposizioneManuale
                bilanciamentoBianco
            }
            .tint(Tema.accento)
        }
    }

    private var essenziali: some View {
        VStack(alignment: .leading, spacing: Spazi.medio) {
            VStack(alignment: .leading, spacing: Spazi.stretto) {
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
                    .font(.stile(.nota))
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
                VStack(alignment: .leading, spacing: Spazi.stretto) { torciaEFuoco }
            }
        }
        .tint(Tema.accento)
    }

    @ViewBuilder private var torciaEFuoco: some View {
        if capacita.torcia {
            // Un interruttore a un clic, come «Finestra mini»: il secondario acceso nell'accento.
            let accesa = ricevitore.controlli.torcia
            Button("Torcia") {
                ricevitore.controlli.torcia = !accesa
                ricevitore.comanda(Comando(torcia: !accesa))
            }
            .buttonStyle(StileSecondario(acceso: accesa))
            .accessibilityAddTraits(accesa ? .isSelected : [])
        }
        Button("Messa a fuoco automatica") {
            ricevitore.fuocoAutomatico()
        }
        .buttonStyle(StileSecondario())
        .help("Tasto F")
    }

    /// Bilanciamento del bianco automatico o manuale.
    private var bilanciamentoBianco: some View {
        VStack(alignment: .leading, spacing: Spazi.stretto) {
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
            VStack(alignment: .leading, spacing: Spazi.stretto) {
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
        VStack(alignment: .leading, spacing: Spazi.minimo) {
            HStack {
                Text(nome)
                Spacer()
                Text(Lingua.decimali(testo))
                    .font(.stile(.numeri))
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
