import Stile
import SwiftUI
import WebcamLRProtocollo

/// Il gobbo (pacchetto funzioni): si incolla il testo qui, scorre sullo schermo del telefono vicino all'obiettivo.
/// Il testo si può preparare anche senza telefono; i comandi partono come messaggio `gobbo`.
struct FinestraGobbo: View {
    static let id = "gobbo"

    @Bindable var ricevitore: Ricevitore

    var body: some View {
        VStack(alignment: .leading, spacing: Spazi.medio) {
            Text("Gobbo")
                .font(.stile(.titoloGrande))
            Text("Incolla il testo da leggere: scorre sul telefono, vicino all'obiettivo, così guardi in camera.")
                .font(.stile(.corpo))
                .foregroundStyle(Tema.testoSecondario)
                .fixedSize(horizontal: false, vertical: true)
            // WebcamLR Pro: il testo si prepara lo stesso, ma parte solo con un telefono che l'ha sbloccato.
            if ricevitore.bloccoPro { RigaPro() }

            TextEditor(text: $ricevitore.gobbo.testo)
                .font(.stile(.corpo))
                .scrollContentBackground(.hidden)
                .padding(Spazi.stretto)
                // Un campo: un gradino sopra il fondo, con il contorno dei controlli (≥ 3:1).
                .background(Tema.barraLaterale, in: RoundedRectangle(cornerRadius: Raggi.controllo))
                .overlay(RoundedRectangle(cornerRadius: Raggi.controllo).strokeBorder(Tema.contornoControllo))
                .frame(minHeight: 160, maxHeight: .infinity)
                .accessibilityLabel("Testo del gobbo")

            contatore

            if ricevitore.testoGobboInviato != nil, ricevitore.testoGobboCambiato, ricevitore.gobboDisponibile {
                VStack(alignment: .leading, spacing: Spazi.stretto) { avvisoTestoCambiato }
            }

            velocita
            dimensione
            posizione

            // La finestra è larga almeno 420 punti: i due pulsanti ci stanno sempre in riga.
            HStack(spacing: Spazi.stretto) { pulsanti }
            .richiedePro(ricevitore.bloccoPro)
            .richiedeTelefono(ricevitore.telefonoAttivo)
            .disabled(ricevitore.telefonoAttivo && !ricevitore.gobboDisponibile)

            if let nota {
                Text(nota)
                    .font(.stile(.corpo))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Testo nostro in Barlow (Documenti/Stile.md, «Barlow o sistema»): etichette, campo e pulsanti.
        .font(.stile(.corpo))
        .padding(Spazi.largo)
        .frame(minWidth: 420, minHeight: 520)
        .background(Tema.fondo)
        .foregroundStyle(Tema.testo)
        .tint(Tema.accento)
        .preferredColorScheme(.dark)
    }

    // MARK: - Parti

    private var contatore: some View {
        let caratteri = ricevitore.gobbo.testo.count
        return HStack(spacing: Spazi.stretto) {
            if caratteri > Gobbo.lunghezzaMassima {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Tema.ambra)
                    .accessibilityHidden(true)
                Text("Oltre \(Self.numero(Gobbo.lunghezzaMassima)) caratteri: il telefono riceve solo i primi.")
                    .foregroundStyle(Tema.ambraTesto)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Self.numero(caratteri)) caratteri su \(Self.numero(Gobbo.lunghezzaMassima))")
                    .font(.stile(.numeri))
                    .foregroundStyle(Tema.testoSecondario)
            }
        }
        .font(.stile(.corpo))
    }

    @ViewBuilder private var avvisoTestoCambiato: some View {
        Text("Il testo è cambiato: il telefono ha ancora quello di prima.")
            .font(.stile(.corpo))
            .foregroundStyle(Tema.testoTenue)
            .fixedSize(horizontal: false, vertical: true)
        Button("Aggiorna il testo") {
            ricevitore.mandaTestoGobbo(attivo: ricevitore.gobboAttivo)
        }
        .buttonStyle(StileSecondario())
        .help("Manda il testo nuovo: il gobbo riparte dall'inizio")
    }

    private var velocita: some View {
        VStack(alignment: .leading, spacing: Spazi.minimo) {
            HStack {
                Text("Velocità")
                Spacer(minLength: Spazi.stretto)
                Text(testoVelocita)
                    .font(.stile(.numeri))
                    .foregroundStyle(Tema.testoTenue)
                    .lineLimit(1)
            }
            Slider(value: Binding(
                get: { ricevitore.gobbo.velocita },
                set: { nuovo in
                    ricevitore.gobbo.velocita = nuovo
                    ricevitore.mandaVelocitaGobbo()
                }), in: Gobbo.velocitaMinima...Gobbo.velocitaMassima, step: 0.1)
            .labelsHidden()
            .accessibilityLabel("Velocità")
            .accessibilityValue(testoVelocita)
        }
    }

    private var testoVelocita: String {
        String(localized: "\(Lingua.decimali(String(format: "%.1f", ricevitore.gobbo.velocita))) righe al secondo")
    }

    private var dimensione: some View {
        HStack(spacing: Spazi.piccolo) {
            Text("Dimensione")
            Picker("Dimensione", selection: Binding(
                get: { ricevitore.gobbo.dimensione },
                set: { nuova in
                    ricevitore.gobbo.dimensione = nuova
                    ricevitore.mandaDimensioneGobbo()
                })) {
                Text("Piccola").tag(DimensioniGobbo.piccola)
                Text("Media").tag(DimensioniGobbo.media)
                Text("Grande").tag(DimensioniGobbo.grande)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
        }
    }

    /// Dove è arrivato il telefono: dall'ultimo `stato`, quindi con qualche secondo di ritardo mentre scorre.
    private var posizione: some View {
        VStack(alignment: .leading, spacing: Spazi.minimo) {
            HStack {
                Text("Posizione")
                Spacer(minLength: Spazi.stretto)
                Text(ricevitore.testoGobboInviato == nil ? "—" : "\(Int((ricevitore.posizioneGobbo * 100).rounded()))%")
                    .font(.stile(.numeri))
                    .foregroundStyle(Tema.testoTenue)
            }
            ProgressView(value: ricevitore.testoGobboInviato == nil ? 0 : ricevitore.posizioneGobbo)
                .progressViewStyle(.linear)
                .accessibilityLabel("Posizione nel testo")
        }
    }

    @ViewBuilder private var pulsanti: some View {
        Button {
            ricevitore.avviaOFermaGobbo()
        } label: {
            Label(ricevitore.gobboAttivo ? "Pausa" : "Avvia",
                  systemImage: ricevitore.gobboAttivo ? "pause.fill" : "play.fill")
                .frame(minWidth: 80)
        }
        .buttonStyle(StilePrimario())
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!ricevitore.gobboAttivo && ricevitore.testoGobboInviato == nil && testoVuoto)
        .help(ricevitore.gobboAttivo ? "Ferma il gobbo: il testo resta (⌘↩)" : "Fa scorrere il testo sul telefono (⌘↩)")
        Button {
            ricevitore.gobboDallInizio()
        } label: {
            Label("Dall'inizio", systemImage: "backward.end.fill")
        }
        .buttonStyle(StileSecondario())
        .disabled(ricevitore.testoGobboInviato == nil && testoVuoto)
        .help("Torna all'inizio del testo")
    }

    private var testoVuoto: Bool {
        ricevitore.gobbo.testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Perché i comandi sono spenti, quando lo sono.
    private var nota: String? {
        if ricevitore.collegamento == .riconnessione && ricevitore.inSottofondo {
            return Ricevitore.testoPausa(MotiviPausa.sottofondo)
        }
        if ricevitore.collegamento == .riconnessione {
            return String(localized: "Mi ricollego al telefono: il gobbo riprende da dove era.")
        }
        if !ricevitore.telefonoAttivo {
            return String(localized: "Puoi già preparare il testo: si manda quando colleghi un telefono.")
        }
        if !ricevitore.gobboDisponibile {
            return String(localized: "Questo telefono non ha ancora il gobbo: aggiorna WebcamLR sul telefono.")
        }
        return nil
    }

    /// «20.000»: numeri all'italiana, con il punto per le migliaia; in inglese «20,000» (P22).
    private static func numero(_ valore: Int) -> String {
        valore.formatted(.number.locale(Lingua.formatoNumeri))
    }
}
