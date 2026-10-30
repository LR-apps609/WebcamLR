import Stile
import SwiftUI
import WebcamLRProtocollo

// Il pannello «Impostazioni» (Viste.swift): scorre da destra sopra il video, largo 360 punti, con un elenco di voci
// in cui si entra e da cui si torna con la freccia «Indietro», come le Impostazioni di iOS. Dal passo 8 è l'unico posto
// delle impostazioni: si apre dal pulsante in alto (viste Essenziale e Completo) e da «Impostazioni…» ⌘,, e ha anche le
// pagine della vecchia finestra di ⌘, (Impostazioni.swift). È alto quanto la finestra e ogni pagina scorre: mai più alto
// dello schermo (M24). Ogni pagina riusa le sezioni delle colonne della vista Completo (ColonnaDispositivi.swift,
// ColonnaControlli.swift) e i menu sopra e sotto il video: nessuna logica in doppio. Si chiude con la X, con Esc o con
// un clic sul video.

/// Le voci del pannello, nell'ordine in cui compaiono.
enum PaginaImpostazioni: String, CaseIterable, Identifiable {
    case fotocamera
    case effetti
    case sfondo
    case profili
    case qualita
    case schermo
    case microfono
    case telefoni
    case sicurezza
    case uscite
    case attesa
    case gobbo
    case avvio
    case registro

    var id: String { rawValue }

    var titolo: String {
        switch self {
        case .fotocamera: String(localized: "Fotocamera")
        case .effetti: String(localized: "Effetti")
        case .sfondo: String(localized: "Sfondo")
        case .profili: String(localized: "Profili")
        case .qualita: String(localized: "Qualità e collegamento")
        case .schermo: String(localized: "Schermo")
        case .microfono: String(localized: "Microfono")
        case .telefoni: String(localized: "Telefoni")
        case .sicurezza: String(localized: "Sicurezza")
        case .uscite: String(localized: "Uscite")
        case .attesa: String(localized: "Schermata di attesa")
        case .gobbo: String(localized: "Gobbo")
        case .avvio: String(localized: "Avvio e notifiche")
        case .registro: String(localized: "Registro del collegamento")
        }
    }

    /// Una riga sotto il titolo nell'elenco: cosa c'è dentro.
    var dettaglio: String {
        switch self {
        case .fotocamera: String(localized: "Obiettivo, zoom, esposizione, fuoco, bianco")
        case .effetti: String(localized: "Filtro, regolazioni, ritocco, scritta e logo")
        case .sfondo: String(localized: "Nessuno, sfocatura o un'immagine")
        case .profili: String(localized: "Profili pronti e profili salvati")
        case .qualita: String(localized: "Qualità video, Wi-Fi o USB, numeri")
        case .schermo: String(localized: "Riempi l'inquadratura, finestra mini, barra dei menu")
        case .microfono: String(localized: "Il microfono del telefono sul Mac")
        case .telefoni: String(localized: "Collegati, conosciuti, collegane un altro")
        case .sicurezza: String(localized: "Codice di questo Mac, telefoni fidati")
        case .uscite: String(localized: "Webcam virtuale, microfono, NDI")
        case .attesa: String(localized: "Cosa vedono le app quando il video non c'è")
        case .gobbo: String(localized: "Un testo che scorre sul telefono")
        case .avvio: String(localized: "Apri all'avvio del Mac, notifiche")
        case .registro: String(localized: "Gli ultimi eventi, da copiare")
        }
    }

    var icona: String {
        switch self {
        case .fotocamera: "camera"
        case .effetti: "wand.and.stars"
        case .sfondo: "person.and.background.dotted"
        case .profili: "rectangle.stack"
        case .qualita: "antenna.radiowaves.left.and.right"
        case .schermo: "rectangle.on.rectangle"
        case .microfono: "mic"
        case .telefoni: "iphone"
        case .sicurezza: "lock.shield"
        case .uscite: "video"
        case .attesa: "photo"
        case .gobbo: "text.alignleft"
        case .avvio: "power"
        case .registro: "list.bullet.rectangle"
        }
    }
}

struct PannelloImpostazioni: View {
    let ricevitore: Ricevitore
    let fotocamera: AttivazioneFotocamera
    /// La pagina aperta; nil per l'elenco. La tiene la finestra: la pillola del telefono apre direttamente «Telefoni».
    @Binding var pagina: PaginaImpostazioni?
    let chiudi: () -> Void
    /// Apre il foglio «Telefoni conosciuti» (lo tiene la finestra principale, come per il menu «Account»).
    let mostraTelefoniConosciuti: () -> Void
    /// Riduci movimento (M21): le pagine si dissolvono invece di scorrere.
    @Environment(\.accessibilityReduceMotion) private var riduciMovimento

    var body: some View {
        VStack(spacing: 0) {
            testata
            Divider().overlay(Tema.lineaTenue)
            ZStack(alignment: .topLeading) {
                if let pagina {
                    corpo(pagina)
                        .transition(riduciMovimento ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                } else {
                    elenco
                        .transition(riduciMovimento ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .background(Tema.barraLaterale)
        .foregroundStyle(Tema.testo)
        .font(.corpo(13))
        .tint(Tema.ciano)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Impostazioni")
    }

    // MARK: - Testata

    /// In alto: la freccia «Indietro» dentro una pagina, il titolo e la X per chiudere.
    private var testata: some View {
        HStack(spacing: 8) {
            if pagina != nil {
                Button {
                    vai(nil)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tema.accento)
                .help("Indietro")
                .accessibilityLabel("Indietro")
            }
            Text(pagina?.titolo ?? String(localized: "Impostazioni"))
                .font(.titolo(20))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button {
                chiudi()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Tema.pannelloChiaro, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tema.testoTenue)
            .help("Chiudi le impostazioni (Esc)")
            .accessibilityLabel("Chiudi le impostazioni")
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }

    private func vai(_ nuova: PaginaImpostazioni?) {
        withAnimation(.easeInOut(duration: 0.2)) { pagina = nuova }
    }

    // MARK: - Elenco

    private var elenco: some View {
        ScrollView(.vertical) {
            VStack(spacing: 2) {
                ForEach(PaginaImpostazioni.allCases) { voce in
                    RigaVoceImpostazioni(voce: voce) { vai(voce) }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Pagine

    /// Il registro ha già il suo scorrimento e prende tutta l'altezza; le altre pagine scorrono se non ci stanno.
    @ViewBuilder private func corpo(_ pagina: PaginaImpostazioni) -> some View {
        if pagina == .registro {
            VStack(alignment: .leading, spacing: 12) {
                // La diagnosi della maschera anche senza ⌥ clic su «Sfondo»: il video mostra in bianco la persona.
                Button("Mostra o nascondi la maschera della persona") { ricevitore.alternaMascheraVisibile() }
                VistaRegistro(voci: ricevitore.registro, conTitolo: false, dimensione: nil)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    contenuto(pagina)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder private func contenuto(_ pagina: PaginaImpostazioni) -> some View {
        switch pagina {
        case .fotocamera:
            ComandiFotocamera(ricevitore: ricevitore)
            Divider().overlay(Tema.lineaTenue)
            HStack(spacing: 6) {
                Text("Regole fini")
                    .font(.titolo(18))
                if ricevitore.bloccoPro { SegnoPro() }
            }
            ComandiRegoleFini(ricevitore: ricevitore, parte: .fotocamera)
        case .effetti:
            if let capacita = ricevitore.capacitaEffetti, ricevitore.telefonoAttivo, !Effetti.disponibili(capacita) {
                // Solo ciò che il telefono dichiara, come nella colonna di destra.
                Nota(testo: String(localized: "Questo telefono non ha effetti."))
            } else {
                ComandiEffetti(ricevitore: ricevitore)
            }
            Divider().overlay(Tema.lineaTenue)
            ComandiRegoleFini(ricevitore: ricevitore, parte: .regolazioni)
        case .sfondo:
            paginaSfondo
        case .profili:
            ComandiProfilo(ricevitore: ricevitore, conTitolo: false)
        case .qualita:
            PannelloQualita(ricevitore: ricevitore) {}
                .richiedeTelefono(ricevitore.telefonoAttivo)
            if ricevitore.sceltaCollegamentoDisponibile {
                Divider().overlay(Tema.lineaTenue)
                PannelloCollegamento(ricevitore: ricevitore) {}
            }
            Divider().overlay(Tema.lineaTenue)
            SezioneConnessione(ricevitore: ricevitore)
            // La spiegazione del Wi-Fi diretto, che prima stava nella finestra di ⌘,.
            Nota(testo: String(localized: "Per collegare l'iPhone dove non c'è una rete in comune, come con AirDrop. Lascialo spento se non serve: tiene occupata la radio Wi-Fi e la latenza diventa meno stabile."))
        case .schermo:
            PaginaSchermo(ricevitore: ricevitore)
        case .microfono:
            PaginaMicrofono(ricevitore: ricevitore)
        case .telefoni:
            paginaTelefoni
        case .sicurezza:
            PaginaSicurezza(ricevitore: ricevitore)
        case .uscite:
            SezioneUscite(ricevitore: ricevitore, fotocamera: fotocamera)
            Divider().overlay(Tema.lineaTenue)
            RigaAppWebcam(webcamDisponibile: fotocamera.disponibile, webcamAttiva: fotocamera.stato == .attiva,
                          firme: ricevitore.appWebcam, inUso: ricevitore.webcamInUso, conAiuto: true)
        case .attesa:
            PaginaSchermataAttesa(ricevitore: ricevitore)
        case .gobbo:
            PaginaGobbo(ricevitore: ricevitore)
        case .avvio:
            PaginaAvvio()
        case .registro:
            // Disegnata da `corpo`, senza lo scorrimento delle altre pagine.
            EmptyView()
        }
    }

    /// Lo stesso menu di «Sfondo» sotto il video, con le stesse regole: grigio senza telefono e con la posteriore.
    @ViewBuilder private var paginaSfondo: some View {
        let inAttesa = !ricevitore.telefonoAttivo || ricevitore.capacita == nil
        let posteriore = !inAttesa && ricevitore.soloFrontaleBloccati
        if !inAttesa && !ricevitore.sfondoDisponibile {
            Nota(testo: String(localized: "Questo telefono non cambia lo sfondo."))
        } else {
            PannelloSfondo(ricevitore: ricevitore, chiudi: {}, larghezza: nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .richiedeTelefono(!inAttesa)
                .soloFrontale(posteriore)
        }
    }

    /// I telefoni (con «Scollega» quando ce n'è uno solo: con due ce l'ha ogni scheda), il QR per collegarne un
    /// altro e i telefoni conosciuti.
    @ViewBuilder private var paginaTelefoni: some View {
        SezioneTelefoni(ricevitore: ricevitore, conRegistro: false)
        if ricevitore.telefoni.count == 1, let nome = ricevitore.telefono?.nome {
            Button {
                ricevitore.chiediEScollega()
            } label: {
                Label("Scollega «\(nome)»", systemImage: "iphone.slash")
            }
            .buttonStyle(StilePulsanteSecondario())
            .help("Scollega il telefono: non si ricollega da solo")
        }
        RiquadroCollega(ricevitore: ricevitore)
        Button {
            mostraTelefoniConosciuti()
        } label: {
            Label("Telefoni conosciuti", systemImage: "iphone")
        }
        .buttonStyle(StilePulsanteSecondario())
    }
}

// MARK: - Componenti del pannello

/// Una voce dell'elenco: icona nell'accento, nome, cosa c'è dentro e la freccina.
private struct RigaVoceImpostazioni: View {
    let voce: PaginaImpostazioni
    let azione: () -> Void
    @State private var sopra = false

    var body: some View {
        Button(action: azione) {
            HStack(spacing: 10) {
                Image(systemName: voce.icona)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Tema.accento)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(voce.titolo)
                        .font(.corpoEvidente(13.5))
                        .foregroundStyle(Tema.testo)
                    Text(voce.dettaglio)
                        .font(.corpo(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tema.testoSecondario)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 46)
            .background(sopra ? Tema.pannelloChiaro : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .accessibilityLabel(voce.titolo)
        .accessibilityHint(voce.dettaglio)
    }
}

/// Una riga di spiegazione tenue (anche nelle pagine di Impostazioni.swift).
struct Nota: View {
    let testo: String

    var body: some View {
        Text(testo)
            .font(.corpo(12.5))
            .foregroundStyle(Tema.testoSecondario)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// «Schermo»: Riempi l'inquadratura e la finestra mini, usciti dal menu «Schermo» sotto il video (che ora sceglie
/// la vista). Anche nel menu Vista, con ⌥⌘F e ⇧⌘M. In fondo l'icona nella barra dei menu (passo 6).
private struct PaginaSchermo: View {
    let ricevitore: Ricevitore
    @AppStorage(Preferenze.riempi) private var riempi = false
    @AppStorage(Preferenze.iconaBarraMenu) private var iconaBarraMenu = true
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.dismissWindow) private var chiudiFinestra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $riempi) {
                Text("Riempi l'inquadratura")
                    .font(.corpoEvidente(13))
            }
            .toggleStyle(.switch)
            Nota(testo: String(localized: "Il video copre tutta la finestra, tagliando i bordi. Vale solo qui: le altre app ricevono il video intero"))
        }
        Divider().overlay(Tema.lineaTenue)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                alternaFinestraMini(ricevitore, apri: apriFinestra, chiudi: chiudiFinestra)
            } label: {
                if ricevitore.miniAperta {
                    Label("Chiudi la finestra mini", systemImage: "pip.exit")
                } else {
                    Label("Finestra mini", systemImage: "pip.enter")
                }
            }
            .buttonStyle(StilePulsanteInterruttore(acceso: ricevitore.miniAperta))
            .accessibilityAddTraits(ricevitore.miniAperta ? .isSelected : [])
            Nota(testo: String(localized: "Finestra mini, sempre in primo piano"))
        }
        Divider().overlay(Tema.lineaTenue)
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $iconaBarraMenu) {
                Text("Mostra l'icona nella barra dei menu")
                    .font(.corpoEvidente(13))
            }
            .toggleStyle(.switch)
            Nota(testo: String(localized: "Lo stato di WebcamLR anche a finestra chiusa: in onda, registrazione, telefono collegato"))
        }
    }
}

/// «Microfono»: la stessa riga di «Uscite» (interruttore e livello) e sotto l'installazione o la rimozione, che prima
/// stavano nella finestra di ⌘, (Impostazioni.swift).
private struct PaginaMicrofono: View {
    let ricevitore: Ricevitore

    var body: some View {
        RigaMicrofono(ricevitore: ricevitore, conInstalla: false)
        Divider().overlay(Tema.lineaTenue)
        SezioneInstallazioneMicrofono(ricevitore: ricevitore)
    }
}

/// «Gobbo»: il testo si prepara nella sua finestra, anche senza telefono; parte con un telefono Pro che lo sa fare.
private struct PaginaGobbo: View {
    let ricevitore: Ricevitore
    @Environment(\.openWindow) private var apriFinestra

    var body: some View {
        Nota(testo: String(localized: "Incolla il testo da leggere: scorre sul telefono, vicino all'obiettivo, così guardi in camera."))
        if ricevitore.bloccoPro { RigaPro() }
        if ricevitore.telefonoAttivo, let capacita = ricevitore.capacita, capacita.gobbo != true {
            Nota(testo: String(localized: "Questo telefono non ha il gobbo."))
        }
        Button {
            apriFinestra(id: FinestraGobbo.id)
        } label: {
            Label("Apri il gobbo", systemImage: "text.alignleft")
        }
        .buttonStyle(StilePulsanteSecondario())
    }
}
