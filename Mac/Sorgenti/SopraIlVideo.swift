import Stile
import SwiftUI
import WebcamLRProtocollo

// Ciò che sta sopra il video della finestra principale (interfaccia finale, Documenti/Interfaccia finale.md):
// in alto a sinistra l'etichetta della qualità e quella del collegamento, ognuna con il suo menu; in basso a
// sinistra «CAM 1»; in basso a destra il riquadro «CAM 2» con «Usa prospettiva», solo con un secondo telefono.

// MARK: - Scelta del collegamento

extension Ricevitore {
    /// Il telefono nella webcam sa cambiare strada e accetta la preferenza (`capacita.sceltaCollegamento`).
    var sceltaCollegamentoDisponibile: Bool {
        telefonoAttivo && capacita?.sceltaCollegamento == true
    }

    /// «Automatico», «Wi-Fi» o «Cavo USB»: la preferenza va al telefono, che decide la strada e la conferma in
    /// `stato.collegamento`. Il menu segue lo `stato`, non quello che si è chiesto (come per «Specchia»).
    func scegliCollegamento(_ preferenza: String) {
        guard sceltaCollegamentoDisponibile, let telefono = attivo else { return }
        registra(String(localized: "Collegamento preferito: \(Self.nomePreferenza(preferenza))"), di: telefono)
        comanda(Comando(collegamento: preferenza))
    }

    /// Per «Collegato · Wi-Fi» o «Collegato · USB» in alto: vero sul cavo, falso su Wi-Fi, hotspot, Wi-Fi diretto e
    /// cavo di rete. Dalla strada che il telefono dice in `stato.collegamento.attivo`; da un telefono che non la dice,
    /// dalla connessione vista dal Mac. Nil senza telefono.
    var collegatoViaCavo: Bool? {
        if let attiva = attivo?.statoTelefono?.collegamento?.attivo { return attiva == StradeCollegamento.cavo }
        return tipoCollegamento.map { $0 == .cavoUSB }
    }

    /// Il nome di una preferenza (`PreferenzeCollegamento`) o di una strada (`StradeCollegamento`), come nel menu.
    static func nomePreferenza(_ valore: String) -> String {
        switch valore {
        case PreferenzeCollegamento.automatico: String(localized: "Automatico")
        case StradeCollegamento.wifi: String(localized: "Wi-Fi")
        case StradeCollegamento.cavo: String(localized: "Cavo USB")
        case StradeCollegamento.hotspot: String(localized: "Hotspot")
        case StradeCollegamento.wifiDiretto: String(localized: "Wi-Fi diretto")
        case StradeCollegamento.rete: String(localized: "Cavo di rete")
        // Un nome nuovo (Valori sconosciuti): un'etichetta generica.
        default: String(localized: "Collegato")
        }
    }
}

// MARK: - Etichette sopra il video

/// Un'etichetta scura sopra il video (collegamento, «CAM 1»): fondo verde quasi nero trasparente, angoli tondi.
struct StileChipVideo: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Tema.testo)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Tema.sfumaturaScura.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Vista Essenziale, in alto a sinistra sul video: il telefono nella webcam (punto salvia collegato, ambra mentre si
/// ricollega) o, senza telefono, «Collega il tuo smartphone». Un clic apre lo stesso QR della colonna di sinistra
/// (`RiquadroCollega`) e la strada per la pagina «Telefoni» delle Impostazioni.
struct PillolaTelefono: View {
    let ricevitore: Ricevitore
    let apriTelefoni: () -> Void
    @State private var aperto = false

    var body: some View {
        let nome = ricevitore.telefono?.nome
        Button {
            aperto.toggle()
        } label: {
            HStack(spacing: 6) {
                if nome != nil {
                    Circle()
                        .fill(ricevitore.telefonoAttivo ? Tema.verde : Tema.ambra)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Image(systemName: "iphone")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                if let nome {
                    Text(verbatim: nome)
                        .font(.corpoEvidente(12.5))
                } else {
                    Text("Collega il tuo smartphone")
                        .font(.corpoEvidente(12.5))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .modifier(StileChipVideo())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(nome == nil ? String(localized: "Mostra il QR code per collegare il telefono")
                          : String(localized: "Telefoni collegati e QR code per collegarne un altro"))
        .accessibilityLabel(nome.map { String(localized: "Telefono: \($0)") } ?? String(localized: "Collega il tuo smartphone"))
        .accessibilityHint(nome == nil ? String(localized: "Mostra il QR code per collegare il telefono")
                                       : String(localized: "Telefoni collegati e QR code per collegarne un altro"))
        .popover(isPresented: $aperto, arrowEdge: .bottom) {
            VStack(spacing: 10) {
                RiquadroCollega(ricevitore: ricevitore)
                Button {
                    aperto = false
                    apriTelefoni()
                } label: {
                    Label("Tutti i telefoni…", systemImage: "iphone")
                }
                .buttonStyle(StilePulsanteSecondario())
            }
            .padding(12)
            .frame(width: 280)
            .foregroundStyle(Tema.testo)
            .tint(Tema.ciano)
        }
    }
}

/// «Ottimo · 720p 30»: la qualità del collegamento e il formato che arriva. Un clic apre la qualità video
/// (le qualità che il telefono dichiara in `capacita.formati`: 720p 30 gratis; 1080p, 60 fps e 4K con WebcamLR Pro,
/// grigi con «PRO» senza) e i numeri del collegamento.
struct MenuQualita: View {
    let ricevitore: Ricevitore
    @State private var aperto = false

    var body: some View {
        let testo = testoEtichetta
        Button {
            aperto.toggle()
        } label: {
            HStack(spacing: 6) {
                if ricevitore.statistiche.latenzaMs == nil {
                    Text("Misuro il collegamento…")
                        .font(.corpo(12.5))
                } else {
                    Text(verbatim: testo)
                        .font(.corpoEvidente(12.5))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .foregroundStyle(Tema.fondo)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Tema.testo, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Qualità video e numeri del collegamento")
        .accessibilityLabel("Qualità video: \(testo)")
        .accessibilityHint("Scegli la qualità video e mostra i numeri del collegamento")
        .popover(isPresented: $aperto, arrowEdge: .bottom) {
            PannelloQualita(ricevitore: ricevitore) { aperto = false }
        }
    }

    /// «Ottimo · 720p 30», con «HEVC» quando arriva in HEVC. Stessa parola del telefono (latenza e fotogrammi persi).
    private var testoEtichetta: String {
        let statistiche = ricevitore.statistiche
        var formato = "\(Lingua.nomeRisoluzione(altezza: min(statistiche.larghezza, statistiche.altezza))) \(statistiche.fps)"
        if statistiche.codec == .hevc { formato += " · HEVC" }
        guard let qualita = ricevitore.attivo?.qualita else { return formato }
        return "\(qualita.testo) · \(formato)"
    }
}

/// Il menu della qualità: le scelte da chiedere al telefono (`formato`, una richiesta: il telefono risponde con ciò
/// che manda davvero), la nota Pro e, a richiesta, i numeri del collegamento (funzioni 28 e 31).
struct PannelloQualita: View {
    let ricevitore: Ricevitore
    let chiudi: () -> Void
    @State private var numeri = false

    var body: some View {
        // WebcamLR Pro: con un telefono gratis le scelte sopra 720p a 30 fps si vedono, grigie con «PRO», e non
        // partono (il telefono gratis non le manderebbe comunque).
        let bloccate = ricevitore.bloccoPro
        let opzioni = OpzioneQualita.elenco(ricevitore.capacita)
            .filter { !bloccate || $0.gratis }
        let soloPro = bloccate ? OpzioneQualita.soloPro(ricevitore.capacita).filter { !opzioni.contains($0) } : []
        // Il 4K si nomina nelle note solo se il telefono lo sa fare.
        let con4K = (opzioni + soloPro).contains { $0.altezza >= 2160 }
        let statistiche = ricevitore.statistiche
        let attuale = OpzioneQualita.attuale(statistiche, tra: opzioni)
        VStack(alignment: .leading, spacing: 2) {
            EtichettaSezione(String(localized: "Qualità video"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            ForEach(opzioni) { opzione in
                RigaMenuVideo(testo: opzione.testo, scelta: opzione == attuale) {
                    ricevitore.chiediFormato(larghezza: opzione.larghezza, altezza: opzione.altezza, fps: opzione.fps)
                    chiudi()
                }
            }
            ForEach(soloPro) { opzione in
                RigaMenuVideo(testo: opzione.testo, pro: true, disattivata: true) {}
                    .help(TestiPro.strada)
            }
            if !soloPro.isEmpty {
                NotaMenuVideo(testo: con4K ? String(localized: "Sblocca WebcamLR Pro sul telefono per 1080p, 60 fps e 4K.")
                                           : String(localized: "Sblocca WebcamLR Pro sul telefono per 1080p e 60 fps."))
                    .help(TestiPro.strada)
            }
            NotaMenuVideo(testo: con4K
                ? String(localized: "Il telefono può scendere da solo se scalda o se la rete è debole. Con un'app a 60 fps il Mac li chiede da solo, fino al 1080p. Il 4K va a 30 fps, in HEVC.")
                : String(localized: "Il telefono può scendere da solo se scalda o se la rete è debole. Con un'app a 60 fps il Mac li chiede da solo, fino al 1080p."))
            Divider()
                .overlay(Tema.lineaTenue)
                .padding(.vertical, 4)
            RigaMenuVideo(testo: numeri ? String(localized: "Nascondi i numeri del collegamento")
                                        : String(localized: "Mostra i numeri del collegamento")) {
                withAnimation(.easeOut(duration: 0.15)) { numeri.toggle() }
            }
            if numeri {
                PannelloNumeri(statistiche: statistiche, storico: ricevitore.storicoLatenza, avvio: ricevitore.tempoAvvio)
            }
        }
        .padding(6)
        .frame(width: 300)
        .foregroundStyle(Tema.testo)
    }
}

/// «Wi-Fi ▾»: come è collegato il telefono. Con un telefono che sa cambiare strada (`capacita.sceltaCollegamento`)
/// un clic apre la scelta: Automatico, Wi-Fi, Cavo USB, con la latenza e «più veloce ora». Senza, solo l'etichetta.
struct MenuCollegamento: View {
    let ricevitore: Ricevitore
    let via: TipoCollegamento
    @State private var aperto = false

    var body: some View {
        if ricevitore.sceltaCollegamentoDisponibile {
            Button {
                aperto.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: via.simbolo)
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(via.testo)
                        .font(.corpo(12.5))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityHidden(true)
                }
                .modifier(StileChipVideo())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Scegli come si collega il telefono: Automatico, Wi-Fi o Cavo USB")
            .accessibilityLabel("Collegato via \(via.testo)")
            .accessibilityHint("Scegli come si collega il telefono")
            .popover(isPresented: $aperto, arrowEdge: .bottom) {
                PannelloCollegamento(ricevitore: ricevitore) { aperto = false }
            }
        } else {
            IndicatoreCollegamento(via, qualita: ricevitore.attivo?.qualita)
                .modifier(StileChipVideo())
        }
    }
}

/// Il menu del collegamento. Il segno di spunta è la preferenza (`stato.collegamento.preferenza`); la riga chiara è
/// la strada in uso; «più veloce ora» è solo un'informazione: in «Automatico» il telefono non cambia per la latenza.
struct PannelloCollegamento: View {
    let ricevitore: Ricevitore
    let chiudi: () -> Void

    private var stato: StatoCollegamento? {
        ricevitore.statoTelefono?.collegamento
    }

    private var preferenza: String {
        ricevitore.attivo?.preferenzaCollegamento ?? PreferenzeCollegamento.automatico
    }

    /// La strada in uso: quella che dice il telefono, altrimenti quella che vede il Mac.
    private var attiva: String? {
        if let attivo = stato?.attivo { return attivo }
        switch ricevitore.tipoCollegamento {
        case .some(.cavoUSB): return StradeCollegamento.cavo
        case .some(.wifi): return StradeCollegamento.wifi
        default: return nil
        }
    }

    /// «Più veloce ora» solo se ci sono almeno due strade misurate: con una sola non c'è nulla da confrontare.
    private var piuVeloce: String? {
        guard let stato, stato.strade.filter({ $0.ms != nil }).count > 1 else { return nil }
        return stato.piuVeloce
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EtichettaSezione(String(localized: "Collegamento del telefono"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            RigaMenuVideo(testo: Ricevitore.nomePreferenza(PreferenzeCollegamento.automatico),
                          nota: String(localized: "sceglie all'inizio, poi resta"),
                          scelta: preferenza == PreferenzeCollegamento.automatico) {
                scegli(PreferenzeCollegamento.automatico)
            }
            riga(StradeCollegamento.wifi)
            riga(StradeCollegamento.cavo)
            NotaMenuVideo(testo: preferenza == PreferenzeCollegamento.automatico
                ? String(localized: "In automatico non salta avanti e indietro: cambia solo se il collegamento si stacca o se attacchi il cavo.")
                : String(localized: "Resta su questa strada. Se si stacca, il telefono usa l'altra per non perdere il video e poi torna qui."))
        }
        .padding(6)
        .frame(width: 300)
        .foregroundStyle(Tema.testo)
    }

    private func riga(_ tipo: String) -> some View {
        let strada = stato?.strade.first { $0.tipo == tipo }
        let nome = Ricevitore.nomePreferenza(tipo)
        let testo = strada?.ms.map { "\(nome) · \($0) ms" } ?? nome
        // Una strada che il telefono non elenca ora (cavo non attaccato): si può preferire lo stesso.
        let assente = stato != nil && strada == nil
        let nota: String? = assente
            ? (tipo == StradeCollegamento.cavo ? String(localized: "non attaccato") : String(localized: "non disponibile"))
            : nil
        return RigaMenuVideo(testo: testo, nota: nota,
                             evidenza: piuVeloce == tipo ? String(localized: "più veloce ora") : nil,
                             scelta: preferenza == tipo, inUso: attiva == tipo) {
            scegli(tipo)
        }
    }

    private func scegli(_ preferenza: String) {
        ricevitore.scegliCollegamento(preferenza)
        chiudi()
    }
}

/// Una riga dei menu sopra il video: il testo, a destra una nota tenue, «più veloce ora» o «PRO», e la spunta della
/// scelta. `inUso`: fondo chiaro (la strada in uso); `disattivata`: grigia, non si sceglie (Pro).
private struct RigaMenuVideo: View {
    let testo: String
    var nota: String?
    var evidenza: String?
    var pro = false
    var scelta = false
    var inUso = false
    var disattivata = false
    let azione: () -> Void
    @State private var sopra = false

    var body: some View {
        Button(action: azione) {
            HStack(spacing: 8) {
                Text(verbatim: testo)
                    .font(.corpo(13.5))
                    .foregroundStyle(disattivata ? Tema.testoSecondario : Tema.testo)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let nota {
                    Text(verbatim: nota)
                        .font(.corpo(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .lineLimit(1)
                }
                if let evidenza {
                    Text(verbatim: evidenza)
                        .font(.corpoEvidente(11))
                        .foregroundStyle(Tema.accento)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Tema.accentoTenue, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .fixedSize()
                }
                if pro { SegnoPro() }
                if scelta {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Tema.accento)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(inUso || (sopra && !disattivata) ? Tema.pannelloChiaro : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disattivata)
        .onHover { sopra = $0 }
        .accessibilityAddTraits(scelta ? .isSelected : [])
    }
}

/// Una nota piccola in fondo a un menu sopra il video.
private struct NotaMenuVideo: View {
    let testo: String

    var body: some View {
        Text(verbatim: testo)
            .font(.corpo(12))
            .foregroundStyle(Tema.testoSecondario)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }
}

// MARK: - CAM 1 e CAM 2

/// In basso a sinistra sul video: «CAM 1 · iPhone di Ledion». Corallo (tally) solo quando è in onda; con due
/// telefoni dice «in uso»: è quello nella webcam.
struct EtichettaCam: View {
    let nome: String
    let inOnda: Bool
    let dueTelefoni: Bool

    var body: some View {
        Text(verbatim: testo)
            .font(inOnda ? .corpoEvidente(12.5) : .corpo(12.5))
            .lineLimit(1)
            .foregroundStyle(inOnda ? Tema.fondo : Tema.testo)
            .padding(.horizontal, 10)
            .frame(minHeight: 26)
            .background(inOnda ? Tema.tally : Tema.sfumaturaScura.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(testo)
    }

    private var testo: String {
        if dueTelefoni { return String(localized: "CAM 1 · \(nome) · in uso") }
        if inOnda { return String(localized: "CAM 1 · \(nome) · in onda") }
        return "CAM 1 · \(nome)"
    }
}

/// Con due telefoni (P21): la CAM 2 in un riquadro dentro il video, in basso a destra. «Usa prospettiva» la mette
/// nella webcam (la stessa scelta di «Nella webcam» nella colonna di sinistra) e la scambia con la grande.
/// Il suo livello è quello del suo `Schermo`: nessuna seconda decodifica.
struct RiquadroSecondoTelefono: View {
    let telefono: TelefonoCollegato
    var larghezza: CGFloat = 230
    let usa: () -> Void

    var body: some View {
        let nome = telefono.telefono.nome
        ZStack {
            VistaSchermo(livello: telefono.schermo.livello)
                .allowsHitTesting(false)
            if telefono.statoTelefono?.pausa != nil {
                // Il telefono è in pausa (faccia in giù, dal telefono, calore; «nessuna app» solo i telefoni di prima).
                Image(systemName: "pause.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Tema.testoTenue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tema.pannelloScuro.opacity(0.85))
                    .accessibilityLabel("In pausa")
            } else if telefono.collegamento == .riconnessione {
                Text("Mi ricollego…")
                    .font(.corpo(12.5))
                    .foregroundStyle(Tema.ambraTesto)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tema.pannelloScuro.opacity(0.85))
            }
            Text(verbatim: "CAM 2 · \(nome)")
                .font(.corpo(12))
                .lineLimit(1)
                .foregroundStyle(Tema.testo)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Tema.sfumaturaScura.opacity(0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Button(action: usa) {
                Text("Usa prospettiva")
                    .font(.corpoForte(12.5))
                    .foregroundStyle(Tema.fondo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Tema.accento, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Metti «\(nome)» nella webcam: va nel video grande, nelle app e nel microfono")
            .accessibilityLabel("Usa la prospettiva di «\(nome)»")
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: larghezza, height: larghezza * 9 / 16)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Tema.fondo, lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CAM 2, \(nome)")
    }
}
