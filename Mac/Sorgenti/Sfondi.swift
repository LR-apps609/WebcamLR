import AppKit
import ImageIO
import Observation
import Stile
import SwiftUI
import UniformTypeIdentifiers
import WebcamLRProtocollo

// Sfondi dal Mac (27 ottobre): il pulsante «Sfondo» sotto il video, gli sfondi pronti con le miniature,
// «Carica un'immagine…» e il logo della scritta. Il telefono fa il lavoro: il Mac sceglie, riduce e manda
// (pacchetto immagine, tipo 4, solo se `capacita.immagini`; Documenti/Protocollo.md).

/// Nomi e miniature degli sfondi pronti (`SfondiPronti`): le miniature 320×180 sono in «Sfondi/<id>.jpg» nel bundle.
@MainActor
enum SfondiComputer {
    /// Il nome mostrato di uno sfondo; gli identificativi sono fissi nel protocollo.
    static func nome(_ id: String) -> String {
        switch id {
        case SfondiPronti.ufficio: String(localized: "Ufficio luminoso")
        case SfondiPronti.libreria: String(localized: "Libreria")
        case SfondiPronti.soggiorno: String(localized: "Soggiorno")
        case SfondiPronti.studio: String(localized: "Studio scuro")
        case SfondiPronti.citta: String(localized: "Città di sera")
        case SfondiPronti.cemento: String(localized: "Parete di cemento")
        case SfondiPronti.piante: String(localized: "Piante")
        case SfondiPronti.lrapps: String(localized: "Verde WebcamLR")
        case SfondiPronti.personale: String(localized: "La tua immagine")
        default: id.capitalized
        }
    }

    private static var miniature: [String: NSImage] = [:]

    /// La miniatura di uno sfondo pronto, letta una volta sola.
    static func miniatura(_ id: String) -> NSImage? {
        if let pronta = miniature[id] { return pronta }
        guard let url = Bundle.main.url(forResource: id, withExtension: "jpg", subdirectory: "Sfondi"),
              let immagine = NSImage(contentsOf: url) else { return nil }
        miniature[id] = immagine
        return immagine
    }

    /// Una copia piccola (48×27 punti) per le voci dei menu, che mostrano le immagini alla loro misura.
    static func perMenu(_ immagine: NSImage?) -> NSImage? {
        guard let copia = immagine?.copy() as? NSImage else { return nil }
        copia.size = NSSize(width: 48, height: 27)
        return copia
    }
}

/// L'immagine personale e il logo caricati dal Mac: una copia già ridotta nella cartella dell'app (Application Support
/// del sandbox), che resta tra i riavvii; e l'ultima scelta del pulsante «Sfondo».
@Observable
@MainActor
final class ImmaginiComputer {
    static let condivise = ImmaginiComputer()
    /// `ultimaScelta` per la sfocatura (con l'ultimo livello, `Ricevitore.livelloSfocatura`).
    static let sceltaSfocatura = "sfocatura"

    private static let fileSfondo = "sfondo-personale.jpg"
    private static let fileLogo = "logo.png"

    /// Impronta della copia dell'immagine personale (`PacchettoImmagine.improntaDi`); nil se non ce n'è una.
    private(set) var improntaSfondo: String? = nil
    private(set) var miniaturaSfondo: NSImage? = nil
    /// Impronta della copia del logo; nil se non ce n'è uno.
    private(set) var improntaLogo: String? = nil

    /// L'ultima scelta del pulsante «Sfondo»: `sceltaSfocatura` o l'id di uno sfondo (anche `SfondiPronti.personale`).
    var ultimaScelta: String {
        didSet { UserDefaults.standard.set(ultimaScelta, forKey: Preferenze.ultimoSfondo) }
    }

    private init() {
        ultimaScelta = UserDefaults.standard.string(forKey: Preferenze.ultimoSfondo) ?? Self.sceltaSfocatura
        if let dati = Self.leggi(Self.fileSfondo) {
            improntaSfondo = PacchettoImmagine.improntaDi(dati)
            miniaturaSfondo = NSImage(data: dati)
        }
        if let dati = Self.leggi(Self.fileLogo) {
            improntaLogo = PacchettoImmagine.improntaDi(dati)
        }
    }

    /// I byte da mandare dell'immagine personale.
    func datiSfondo() -> Data? { Self.leggi(Self.fileSfondo) }

    /// Sostituisce la copia dell'immagine personale (già ridotta).
    func salvaSfondo(_ dati: Data) throws {
        try dati.write(to: Self.cartella().appendingPathComponent(Self.fileSfondo), options: .atomic)
        improntaSfondo = PacchettoImmagine.improntaDi(dati)
        miniaturaSfondo = NSImage(data: dati)
    }

    /// Sostituisce la copia del logo (già ridotto, PNG).
    func salvaLogo(_ dati: Data) throws {
        try dati.write(to: Self.cartella().appendingPathComponent(Self.fileLogo), options: .atomic)
        improntaLogo = PacchettoImmagine.improntaDi(dati)
    }

    private static func cartella() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let cartella = base.appendingPathComponent("WebcamLR", isDirectory: true)
        try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        return cartella
    }

    private static func leggi(_ nome: String) -> Data? {
        try? Data(contentsOf: cartella().appendingPathComponent(nome))
    }
}

/// Riduce un'immagine scelta dall'utente prima di mandarla: lato lungo al massimo `latoMassimo` (mai ingrandita),
/// girata secondo l'orientamento EXIF. Sfondo in JPEG (qualità 0,85); logo in PNG, che tiene la trasparenza.
/// Solo ImageIO di sistema: apre JPEG, PNG e HEIC. Fuori dalla coda principale.
enum RiduzioneImmagine {
    static func riduci(_ url: URL, latoMassimo: Int, png: Bool) -> Data? {
        guard let sorgente = CGImageSourceCreateWithURL(url as CFURL, nil),
              let proprieta = CGImageSourceCopyPropertiesAtIndex(sorgente, 0, nil) as? [String: Any],
              let larghezza = proprieta[kCGImagePropertyPixelWidth as String] as? Int,
              let altezza = proprieta[kCGImagePropertyPixelHeight as String] as? Int,
              larghezza > 0, altezza > 0 else { return nil }
        let opzioni: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(latoMassimo, max(larghezza, altezza)),
        ]
        guard let immagine = CGImageSourceCreateThumbnailAtIndex(sorgente, 0, opzioni as CFDictionary) else { return nil }
        let dati = NSMutableData()
        let tipo = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destinazione = CGImageDestinationCreateWithData(dati as CFMutableData, tipo, 1, nil) else { return nil }
        let impostazioni: [CFString: Any] = png ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destinazione, immagine, impostazioni as CFDictionary)
        guard CGImageDestinationFinalize(destinazione), dati.length > 0,
              dati.length <= PacchettoImmagine.dimensioneMassima else { return nil }
        return dati as Data
    }
}

/// La finestra di sistema per scegliere un file. Il sandbox lo permette con `files.user-selected.read-only`.
@MainActor
enum SceltaFile {
    static func scegli(tipi: [UTType], messaggio: String) -> URL? {
        let pannello = NSOpenPanel()
        pannello.allowedContentTypes = tipi
        pannello.allowsMultipleSelection = false
        pannello.canChooseDirectories = false
        pannello.canChooseFiles = true
        pannello.message = messaggio
        NSApp.activate(ignoringOtherApps: true)
        return pannello.runModal() == .OK ? pannello.url : nil
    }

    /// «Carica un'immagine…»: sceglie e manda (dopo che i menu si sono chiusi).
    static func caricaSfondo(_ ricevitore: Ricevitore) {
        Task { @MainActor in
            guard let url = scegli(tipi: [.jpeg, .png, .heic],
                                   messaggio: String(localized: "Scegli un'immagine per lo sfondo (JPEG, PNG o HEIC)")) else { return }
            await ricevitore.caricaImmagineSfondo(da: url)
        }
    }

    /// «Carica logo…»: un PNG, meglio con la trasparenza.
    static func caricaLogo(_ ricevitore: Ricevitore) {
        Task { @MainActor in
            guard let url = scegli(tipi: [.png],
                                   messaggio: String(localized: "Scegli il logo: un PNG con la trasparenza")) else { return }
            await ricevitore.caricaLogo(da: url)
        }
    }
}

// MARK: - Il menu di «Sfondo»

/// Il menu di «Sfondo» sotto il video, che si apre verso l'alto come «Schermo»: Nessuno · Sfocatura (Poco, Medio,
/// Tanto) · Sfondi ▸, che apre di lato le miniature. Spunta sulla scelta attuale, come la conferma il telefono.
struct PannelloSfondo: View {
    let ricevitore: Ricevitore
    /// Chiude il pannello dopo una scelta.
    let chiudi: () -> Void
    @State private var mostraSfondi = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VoceSfondo(titolo: String(localized: "Nessuno"), scelta: !ricevitore.sfondoAcceso && !ricevitore.sfocaturaDelTelefono) {
                ricevitore.scegliNessunSfondo()
                chiudi()
            }
            Divider().padding(.vertical, 4)
            EtichettaSezione(String(localized: "Sfocatura"))
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            if ricevitore.sfocaturaSistema {
                // La sfocatura del telefono (Effetti video di Apple): accesa e spiegata, i nostri livelli grigi.
                VoceSfondo(titolo: String(localized: "Sfocatura del telefono"), scelta: ricevitore.sfocaturaDelTelefono) {}
                    .disabled(true)
                Text("Si regola sul telefono, negli Effetti video di Apple.")
                    .font(.corpo(12))
                    .foregroundStyle(Tema.testoSecondario)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }
            ForEach(LivelloSfocatura.allCases) { livello in
                VoceSfondo(titolo: livello.nome,
                           scelta: ricevitore.sfondoSfocato && ricevitore.livelloSfocaturaAttuale == livello) {
                    ricevitore.scegliLivelloSfocatura(livello)
                    chiudi()
                }
                .disabled(ricevitore.sfocaturaSistema)
                .opacity(ricevitore.sfocaturaSistema ? 0.45 : 1)
            }
            Divider().padding(.vertical, 4)
            Button {
                mostraSfondi.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(ricevitore.effetti.sfondo == ModiSfondo.sostituito ? 1 : 0)
                        .frame(width: 14)
                    Text("Sfondi")
                    if ricevitore.bloccoPro { SegnoPro() }
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tema.testoSecondario)
                }
            }
            .buttonStyle(StileVoceSfondo())
            .accessibilityAddTraits(ricevitore.effetti.sfondo == ModiSfondo.sostituito ? .isSelected : [])
            .popover(isPresented: $mostraSfondi, arrowEdge: .trailing) {
                GrigliaSfondi(ricevitore: ricevitore) {
                    mostraSfondi = false
                    chiudi()
                }
            }
        }
        .padding(6)
        .frame(width: 220)
        .foregroundStyle(Tema.testo)
        .font(.corpo(13))
    }
}

/// Una voce del menu di «Sfondo»: la spunta (o lo spazio) e il nome.
private struct VoceSfondo: View {
    let titolo: String
    let scelta: Bool
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(scelta ? 1 : 0)
                    .frame(width: 14)
                Text(titolo)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(StileVoceSfondo())
        .accessibilityAddTraits(scelta ? .isSelected : [])
    }
}

/// Larga quanto il pannello, chiara al passaggio del puntatore.
private struct StileVoceSfondo: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CorpoVoceSfondo(configuration: configuration)
    }
}

private struct CorpoVoceSfondo: View {
    let configuration: ButtonStyleConfiguration
    @State private var sopra = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isPressed ? Tema.linea : sopra ? Tema.pannelloChiaro : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onHover { sopra = $0 }
    }
}

/// «Sfondi ▸»: le miniature degli sfondi pronti del telefono, poi «La tua immagine» e «Carica un'immagine…».
/// Di WebcamLR Pro: con un telefono gratis le miniature hanno il segno «PRO» e aprono la pagina di Pro.
private struct GrigliaSfondi: View {
    let ricevitore: Ricevitore
    let chiudi: () -> Void
    @Environment(\.openWindow) private var apriFinestra

    private let colonne = [GridItem(.fixed(132), spacing: 8), GridItem(.fixed(132), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ricevitore.bloccoPro {
                RigaPro()
            }
            LazyVGrid(columns: colonne, alignment: .leading, spacing: 10) {
                ForEach(ricevitore.sfondiPronti, id: \.self) { id in
                    MiniaturaSfondo(nome: SfondiComputer.nome(id), immagine: SfondiComputer.miniatura(id),
                                    scelta: ricevitore.immagineSfondoAttuale == id, pro: ricevitore.bloccoPro) {
                        scegli(id)
                    }
                }
                if ricevitore.immaginePersonaleDisponibile {
                    MiniaturaSfondo(nome: SfondiComputer.nome(SfondiPronti.personale),
                                    immagine: ImmaginiComputer.condivise.miniaturaSfondo,
                                    scelta: ricevitore.immagineSfondoAttuale == SfondiPronti.personale,
                                    pro: ricevitore.bloccoPro) {
                        scegli(SfondiPronti.personale)
                    }
                }
            }
            Divider()
            if ricevitore.immaginiDisponibili {
                Button {
                    carica()
                } label: {
                    HStack(spacing: 6) {
                        Label("Carica un'immagine…", systemImage: "photo.badge.plus")
                        if ricevitore.bloccoPro { SegnoPro() }
                    }
                }
                .buttonStyle(StileVoceSfondo())
                .help("Un'immagine dal Mac (JPEG, PNG o HEIC) come sfondo: resta anche sul telefono")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Carica un'immagine…", systemImage: "photo.badge.plus")
                        .foregroundStyle(Tema.testoSecondario)
                        .opacity(0.6)
                    Text("Aggiorna l'app del telefono per caricare un'immagine dal Mac.")
                        .font(.corpo(12))
                        .foregroundStyle(Tema.testoSecondario)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(width: 296)
        .foregroundStyle(Tema.testo)
        .font(.corpo(13))
    }

    private func scegli(_ id: String) {
        guard !ricevitore.bloccoPro else {
            apriPro()
            return
        }
        ricevitore.scegliImmagineSfondo(id)
        chiudi()
    }

    private func carica() {
        guard !ricevitore.bloccoPro else {
            apriPro()
            return
        }
        chiudi()
        SceltaFile.caricaSfondo(ricevitore)
    }

    /// La spiegazione di WebcamLR Pro: la scheda «WebcamLR Pro» della finestra «App e assistenza».
    private func apriPro() {
        chiudi()
        apriFinestraApp(.pro, apri: apriFinestra)
    }
}

/// Una miniatura 16:9 con il nome sotto; la scelta attuale ha il bordo e la spunta nell'accento.
private struct MiniaturaSfondo: View {
    let nome: String
    let immagine: NSImage?
    let scelta: Bool
    let pro: Bool
    let azione: () -> Void
    @State private var sopra = false

    var body: some View {
        Button(action: azione) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    if let immagine {
                        Image(nsImage: immagine)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Tema.pannelloChiaro
                        Image(systemName: "photo")
                            .foregroundStyle(Tema.testoSecondario)
                    }
                }
                .frame(width: 132, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(scelta ? Tema.accento : sopra ? Tema.bordo : Tema.lineaTenue, lineWidth: scelta ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if pro {
                        SegnoPro().padding(5)
                    } else if scelta {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Tema.fondo, Tema.accento)
                            .padding(5)
                    }
                }
                Text(nome)
                    .font(.corpo(12))
                    .foregroundStyle(scelta ? Tema.accentoChiaro : Tema.testoTenue)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sopra = $0 }
        .help(pro ? TestiPro.sblocca : nome)
        .accessibilityLabel(nome)
        .accessibilityAddTraits(scelta ? .isSelected : [])
    }
}

/// Lo stesso menu di «Sfondo» con il clic destro, come menu di sistema: Sfondi è un sottomenu con le miniature.
struct VociMenuSfondo: View {
    let ricevitore: Ricevitore
    let apriPro: () -> Void

    var body: some View {
        Toggle("Nessuno", isOn: Binding(
            get: { !ricevitore.sfondoAcceso && !ricevitore.sfocaturaDelTelefono },
            set: { _ in ricevitore.scegliNessunSfondo() }))
        Section("Sfocatura") {
            if ricevitore.sfocaturaSistema {
                // Grigie: la sfocatura del telefono si regola solo sul telefono.
                Toggle("Sfocatura del telefono", isOn: .constant(ricevitore.sfocaturaDelTelefono))
                    .disabled(true)
                Text("Si regola sul telefono, negli Effetti video di Apple.")
            }
            ForEach(LivelloSfocatura.allCases) { livello in
                Toggle(livello.nome, isOn: Binding(
                    get: { ricevitore.sfondoSfocato && ricevitore.livelloSfocaturaAttuale == livello },
                    set: { _ in ricevitore.scegliLivelloSfocatura(livello) }))
                .disabled(ricevitore.sfocaturaSistema)
            }
        }
        Menu {
            ForEach(ricevitore.sfondiPronti, id: \.self) { id in
                voce(id, immagine: SfondiComputer.miniatura(id))
            }
            if ricevitore.immaginePersonaleDisponibile {
                voce(SfondiPronti.personale, immagine: ImmaginiComputer.condivise.miniaturaSfondo)
            }
            Divider()
            Button("Carica un'immagine…") {
                if ricevitore.bloccoPro { apriPro() } else { SceltaFile.caricaSfondo(ricevitore) }
            }
            .disabled(!ricevitore.immaginiDisponibili)
        } label: {
            if ricevitore.bloccoPro {
                Text("Sfondi (WebcamLR Pro)")
            } else {
                Text("Sfondi")
            }
        }
    }

    private func voce(_ id: String, immagine: NSImage?) -> some View {
        Toggle(isOn: Binding(
            get: { ricevitore.immagineSfondoAttuale == id },
            set: { _ in
                if ricevitore.bloccoPro { apriPro() } else { ricevitore.scegliImmagineSfondo(id) }
            })) {
            if let piccola = SfondiComputer.perMenu(immagine) {
                Label { Text(SfondiComputer.nome(id)) } icon: { Image(nsImage: piccola) }
            } else {
                Text(SfondiComputer.nome(id))
            }
        }
    }
}
