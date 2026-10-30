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

/// Vista Essenziale, in alto a sinistra sul video: il telefono nella webcam (punto salvia collegato, ambra mentre si
/// ricollega) o, senza telefono, «Collega il tuo telefono». Un clic apre lo stesso QR della colonna di sinistra
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
            HStack(spacing: Spazi.stretto) {
                if nome != nil {
                    Circle()
                        .fill(ricevitore.telefonoAttivo || ricevitore.inSottofondo ? Tema.verde : Tema.ambra)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                }
                Image(systemName: "iphone")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
                if let nome {
                    Text(verbatim: nome)
                        .font(.stile(.corpo, .corpoEvidente))
                } else {
                    Text("Collega il tuo telefono")
                        .font(.stile(.corpo, .corpoEvidente))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .chipInformativo()
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(nome == nil ? String(localized: "Mostra il QR code per collegare il telefono")
                          : String(localized: "Telefoni collegati e QR code per collegarne un altro"))
        .accessibilityLabel(nome.map { String(localized: "Telefono: \($0)") } ?? String(localized: "Collega il tuo telefono"))
        .accessibilityHint(nome == nil ? String(localized: "Mostra il QR code per collegare il telefono")
                                       : String(localized: "Telefoni collegati e QR code per collegarne un altro"))
        .popover(isPresented: $aperto, arrowEdge: .bottom) {
            VStack(spacing: Spazi.stretto) {
                RiquadroCollega(ricevitore: ricevitore)
                Button {
                    aperto = false
                    apriTelefoni()
                } label: {
                    // Lo stesso nome della pagina e della voce del menu «WebcamLR»: «Telefoni».
                    Label("Telefoni…", systemImage: "checkmark.shield")
                }
                .buttonStyle(StileSecondario())
            }
            .padding(Spazi.piccolo)
            .frame(width: 280)
            .foregroundStyle(Tema.testo)
            .tint(Tema.accento)
        }
    }
}

/// «Ottimo · 720p 30»: la qualità del collegamento e il formato che arriva; se il telefono manda meno di quanto chiesto,
/// anche il perché («Ottimo · 1080p 30 · ridotta dal telefono: è caldo»). Un clic apre la qualità video
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
            HStack(spacing: Spazi.stretto) {
                if ricevitore.statistiche.latenzaMs == nil {
                    Text("Misuro il collegamento…")
                        .font(.stile(.corpo))
                } else {
                    if let qualita = ricevitore.attivo?.qualita {
                        // Le tre tacche del segnale, come sul telefono: la qualità si legge anche senza la parola.
                        TaccheQualita(qualita)
                    }
                    Text(verbatim: testo)
                        .font(.stile(.corpo, .corpoEvidente))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            // Beta 4: un chip informativo bordato come gli altri, mai pieno (il pieno è del primario).
            .chipInformativo()
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
        if let motivo = motivoRiduzione { formato += " · " + motivo }
        guard let qualita = ricevitore.attivo?.qualita else { return formato }
        return "\(qualita.testo) · \(formato)"
    }

    /// Perché il telefono manda meno di quanto chiesto da qui, in breve; nil se manda quello chiesto. Si guarda il
    /// formato che il telefono dice di mandare (`formato`), non i fotogrammi contati, che ballano con la rete. Senza
    /// una richiesta da qui conta solo il calore, rispetto a quello di serie del telefono (1080p 30 con Pro, 720p 30
    /// senza). La qualità si sceglie solo qui: il telefono mostra gli stessi numeri e lo stesso motivo.
    private var motivoRiduzione: String? {
        guard let telefono = ricevitore.attivo, let inviato = telefono.formatoTelefono else { return nil }
        let stato = telefono.statoTelefono
        let caldo = (stato?.temperatura ?? .normale) != .normale
        let chiesto = telefono.formatoChiesto
        guard chiesto != nil || caldo else { return nil }
        let pro = ricevitore.proAttivo
        let latoChiesto = chiesto.map { min($0.larghezza, $0.altezza) } ?? (pro ? 1080 : 720)
        let fpsChiesti = chiesto?.fps ?? 30
        let lato = min(inviato.larghezza, inviato.altezza)
        guard lato < latoChiesto || inviato.fps < fpsChiesti else { return nil }
        if !pro && (latoChiesto > 720 || fpsChiesti > 30) && lato <= 720 && inviato.fps <= 30 {
            return String(localized: "limite della versione gratuita")
        }
        if caldo { return String(localized: "ridotta dal telefono: è caldo") }
        if let stato, stato.batteria >= 0, stato.batteria < 20, !stato.inCarica, inviato.fps <= 24 {
            return String(localized: "ridotta dal telefono: batteria scarica")
        }
        return String(localized: "ridotta dal telefono")
    }
}

/// Il menu della qualità: le scelte da chiedere al telefono (`formato`, una richiesta: il telefono risponde con ciò
/// che manda davvero), la nota Pro e, a richiesta, i numeri del collegamento (funzioni 28 e 31).
struct PannelloQualita: View {
    let ricevitore: Ricevitore
    let chiudi: () -> Void
    @State private var numeri = false
    /// Riduci movimento (M21): niente animazione, il contenuto compare e basta.
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

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
        // Righe una sotto l'altra senza spazio: ognuna ha già il suo margine (StileRigaMenu).
        VStack(alignment: .leading, spacing: 0) {
            EtichettaSezione(String(localized: "Qualità video"))
                .padding(.horizontal, Spazi.stretto)
                .padding(.vertical, Spazi.stretto)
            ForEach(opzioni) { opzione in
                RigaMenuVideo(testo: opzione.testo, scelta: opzione == attuale) {
                    chiudi()
                    // Mentre registri chiede prima (punto 7). La stessa qualità di adesso non cambia il video.
                    guard opzione == attuale || ricevitore.confermaSeFerma(.qualita) else { return }
                    ricevitore.chiediFormato(larghezza: opzione.larghezza, altezza: opzione.altezza, fps: opzione.fps)
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
                .padding(.vertical, Spazi.minimo)
            RigaMenuVideo(testo: numeri ? String(localized: "Nascondi i numeri del collegamento")
                                        : String(localized: "Mostra i numeri del collegamento")) {
                withAnimation(riduciMovimento ? nil : .easeOut(duration: 0.15)) { numeri.toggle() }
            }
            if numeri {
                PannelloNumeri(statistiche: statistiche, storico: ricevitore.storicoLatenza, avvio: ricevitore.tempoAvvio)
            }
        }
        .padding(Spazi.stretto)
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
                HStack(spacing: Spazi.minimo) {
                    Image(systemName: via.simbolo)
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(via.testo)
                        .font(.stile(.corpo))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityHidden(true)
                }
                .chipInformativo()
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
                .chipInformativo()
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
        // Righe una sotto l'altra senza spazio: ognuna ha già il suo margine (StileRigaMenu).
        VStack(alignment: .leading, spacing: 0) {
            EtichettaSezione(String(localized: "Collegamento del telefono"))
                .padding(.horizontal, Spazi.stretto)
                .padding(.vertical, Spazi.stretto)
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
        .padding(Spazi.stretto)
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

/// Una riga dei menu sopra il video (la riga dei menu di Stile): il testo, a destra una nota tenue, «più veloce ora»
/// o «PRO», e la spunta della scelta. `inUso`: fondo chiaro (la strada in uso); `disattivata`: grigia, non si sceglie (Pro).
private struct RigaMenuVideo: View {
    let testo: String
    var nota: String?
    var evidenza: String?
    var pro = false
    var scelta = false
    var inUso = false
    var disattivata = false
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack(spacing: Spazi.stretto) {
                Text(verbatim: testo)
                    .font(.stile(.corpo))
                    .foregroundStyle(disattivata ? AnyShapeStyle(.testoNota) : AnyShapeStyle(Tema.testo))
                    .lineLimit(1)
                Spacer(minLength: Spazi.stretto)
                if let nota {
                    // Al passaggio la riga è su `pannelloChiaro`: la nota passa da sola a `testoTenue`.
                    Text(verbatim: nota)
                        .font(.stile(.nota))
                        .foregroundStyle(.testoNota)
                        .lineLimit(1)
                }
                if let evidenza {
                    Text(verbatim: evidenza)
                        .font(.stile(.nota, .corpoEvidente))
                        .foregroundStyle(Tema.accento)
                        .padding(.horizontal, Spazi.stretto)
                        .background(Tema.accentoTenue, in: RoundedRectangle(cornerRadius: Raggi.piccolo, style: .continuous))
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
        }
        .buttonStyle(StileRigaMenu(evidenziata: inUso))
        .disabled(disattivata)
        .accessibilityAddTraits(scelta ? .isSelected : [])
    }
}

/// Una nota piccola in fondo a un menu sopra il video.
private struct NotaMenuVideo: View {
    let testo: String

    var body: some View {
        Text(verbatim: testo)
            .font(.stile(.nota))
            .foregroundStyle(Tema.testoSecondario)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spazi.stretto)
            .padding(.top, Spazi.stretto)
            .padding(.bottom, Spazi.minimo)
    }
}

// MARK: - CAM 1 e CAM 2

/// In basso a sinistra sul video: «CAM 1 · iPhone di Ledion». Un chip informativo bordato, mai pieno: in onda ha
/// il punto corallo (tally) e lo dice; con due telefoni dice «in uso»: è quello nella webcam.
struct EtichettaCam: View {
    let nome: String
    let inOnda: Bool
    let dueTelefoni: Bool

    var body: some View {
        // In onda il punto corallo; il segno grande è la barra tally sul bordo alto del video.
        HStack(spacing: Spazi.stretto) {
            if inOnda {
                Circle()
                    .fill(Tema.tally)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(verbatim: testo)
                .font(inOnda ? .stile(.corpo, .corpoEvidente) : .stile(.corpo))
        }
        .lineLimit(1)
        .chipInformativo()
        .accessibilityElement(children: .ignore)
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
            if let motivo = telefono.statoTelefono?.pausa {
                // Il telefono è in pausa (sottofondo, fotocamera interrotta, faccia in giù, dal telefono; «nessuna app»
                // solo i telefoni di prima). Il motivo nell'aiuto e per VoiceOver: il riquadro è piccolo.
                Image(systemName: "pause.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Tema.testoTenue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tema.pannelloScuro.opacity(Veli.medio))
                    .help(Ricevitore.testoPausa(motivo))
                    .accessibilityLabel("In pausa")
                    .accessibilityValue(Ricevitore.testoPausa(motivo))
            } else if telefono.collegamento == .riconnessione {
                Text("Mi ricollego…")
                    .font(.stile(.corpo))
                    .foregroundStyle(Tema.ambraTesto)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Tema.pannelloScuro.opacity(Veli.medio))
            }
            Text(verbatim: "CAM 2 · \(nome)")
                .font(.stile(.nota))
                .lineLimit(1)
                .padding(.horizontal, Spazi.stretto)
                .padding(.vertical, Spazi.minimo)
                // Il chip informativo, più basso: il riquadro è piccolo.
                .foregroundStyle(Tema.testo)
                .background(Veli.coloreMedio, in: RoundedRectangle(cornerRadius: Raggi.piccolo, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Raggi.piccolo, style: .continuous).stroke(Tema.contornoSuVideo))
                .padding(Spazi.stretto)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Button("Usa prospettiva", action: usa)
            .buttonStyle(StilePrimario())
            .help("Metti «\(nome)» nella webcam: va nel video grande, nelle app e nel microfono")
            .accessibilityLabel("Usa la prospettiva di «\(nome)»")
            .padding(Spazi.stretto)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: larghezza, height: larghezza * 9 / 16)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Raggi.controllo, style: .continuous).stroke(Tema.fondo, lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CAM 2, \(nome)")
    }
}
